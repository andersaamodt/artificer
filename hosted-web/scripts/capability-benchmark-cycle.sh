#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SITE_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
PROJECT_ROOT=$(CDPATH= cd -- "$SITE_ROOT/.." && pwd)

. "$SCRIPT_DIR/artificer-local-paths.sh"
artificer_ensure_local_dirs

DEFAULT_MANIFEST="$SITE_ROOT/tests/fixtures/artificer-capability-benchmark-manifest-v1.tsv"
DEFAULT_EXTERNAL_REGISTRY="$SITE_ROOT/tests/fixtures/artificer-capability-external-adapters-v1.tsv"

usage() {
  cat <<'EOF_USAGE'
Usage:
  capability-benchmark-cycle.sh manifest [--manifest FILE]
  capability-benchmark-cycle.sh plan [--label LABEL] [--reports-dir DIR] [--manifest FILE]
  capability-benchmark-cycle.sh score [--label LABEL] [--reports-dir DIR] [--manifest FILE] [--out-json FILE] [--out-md FILE]
  capability-benchmark-cycle.sh compare --baseline FILE --candidate FILE [--label LABEL] [--reports-dir DIR] [--out-json FILE] [--out-md FILE]
  capability-benchmark-cycle.sh external-adapters [--registry FILE]
  capability-benchmark-cycle.sh external-plan --adapter ID [--label LABEL] [--reports-dir DIR] [--manifest FILE] [--registry FILE] [--out-json FILE] [--out-md FILE]
  capability-benchmark-cycle.sh external-run --adapter ID [--label LABEL] [--reports-dir DIR] [--manifest FILE] [--registry FILE] [--out-json FILE] [--out-md FILE]
  capability-benchmark-cycle.sh external-compare --external-baseline FILE --candidate FILE --external-name NAME [--external-kind KIND] [--external-model MODEL] [--external-notes TEXT] [--label LABEL] [--reports-dir DIR] [--out-json FILE] [--out-md FILE]
EOF_USAGE
}

command_name=${1:-}
[ -n "$command_name" ] || {
  usage >&2
  exit 1
}
shift

REPORTS_DIR_DEFAULT=$ARTIFICER_ASSAY_REPORTS_DIR
MANIFEST_DEFAULT=$DEFAULT_MANIFEST
EXTERNAL_REGISTRY_DEFAULT=$DEFAULT_EXTERNAL_REGISTRY
SITE_ROOT_ENV=$SITE_ROOT
PROJECT_ROOT_ENV=$PROJECT_ROOT

MANIFEST_DEFAULT=$MANIFEST_DEFAULT EXTERNAL_REGISTRY_DEFAULT=$EXTERNAL_REGISTRY_DEFAULT REPORTS_DIR_DEFAULT=$REPORTS_DIR_DEFAULT SITE_ROOT_ENV=$SITE_ROOT_ENV PROJECT_ROOT_ENV=$PROJECT_ROOT_ENV \
python3 - "$command_name" "$@" <<'PY'
import argparse
import datetime as dt
import json
import math
import os
import pathlib
import shlex
import subprocess
import sys


def fail(message):
    print(message, file=sys.stderr)
    raise SystemExit(1)


def clamp(value, low=0.0, high=100.0):
    if value < low:
        return low
    if value > high:
        return high
    return value


def normalize_bool(value):
    text = str(value).strip().lower()
    return text in {"1", "true", "yes", "on"}


def risk_penalty(risk):
    return {"low": 0.0, "medium": 7.0, "high": 18.0}.get(str(risk).strip().lower(), 7.0)


def parse_json_file(path, fallback):
    try:
        with open(path, "r", encoding="utf-8") as handle:
            payload = json.load(handle)
    except Exception:
        payload = fallback
    if isinstance(fallback, dict) and not isinstance(payload, dict):
        payload = fallback
    if isinstance(fallback, list) and not isinstance(payload, list):
        payload = fallback
    return payload


def parse_tsv_rows(path):
    rows = []
    try:
        raw_text = pathlib.Path(path).read_text(encoding="utf-8")
    except Exception:
        return rows
    lines = [line.rstrip("\n") for line in raw_text.splitlines() if line.strip()]
    if not lines:
        return rows
    header = [cell.strip() for cell in lines[0].split("\t")]
    if not header:
        return rows
    for raw_line in lines[1:]:
        cells = [cell.strip() for cell in raw_line.split("\t")]
        row = {}
        for index, key in enumerate(header):
            if not key:
                continue
            row[key] = cells[index] if index < len(cells) else ""
        rows.append(row)
    return rows


def resolve_path(raw_path, project_root, site_root):
    text = str(raw_path or "").strip()
    if not text:
        return ""
    path = pathlib.Path(text)
    if path.is_absolute():
        return str(path)
    site_candidate = pathlib.Path(site_root) / text
    if site_candidate.exists():
        return str(site_candidate)
    project_candidate = pathlib.Path(project_root) / text
    return str(project_candidate)


def load_manifest(path, project_root, site_root):
    manifest_path = pathlib.Path(path).expanduser()
    if not manifest_path.is_file():
        fail(f"Manifest not found: {manifest_path}")
    families = []
    for row in parse_tsv_rows(manifest_path):
        if not row:
            continue
        family_id = str(row.get("family_id", "")).strip()
        if not family_id or family_id.startswith("#"):
            continue
        family = {
            "family_id": family_id,
            "name": " ".join(str(row.get("name", family_id)).split()).strip() or family_id,
            "axis": " ".join(str(row.get("axis", "")).split()).strip(),
            "weight": float(str(row.get("weight", "1") or "1").strip()),
            "critical": normalize_bool(row.get("critical", "0")),
            "run_style": str(row.get("run_style", "profile")).strip() or "profile",
            "transfer_style": str(row.get("transfer_style", "simple")).strip() or "simple",
            "score_style": str(row.get("score_style", "simple")).strip() or "simple",
            "cycle_script": resolve_path(row.get("cycle_script", ""), project_root, site_root),
            "regressions_fixture": resolve_path(row.get("regressions_fixture", ""), project_root, site_root),
            "holdout_fixture": resolve_path(row.get("holdout_fixture", ""), project_root, site_root),
        }
        families.append(family)
    return manifest_path, families


def load_external_registry(path):
    registry_path = pathlib.Path(path).expanduser()
    if not registry_path.is_file():
        fail(f"External registry not found: {registry_path}")
    adapters = []
    for row in parse_tsv_rows(registry_path):
        if not row:
            continue
        adapter_id = str(row.get("adapter_id", "")).strip()
        if not adapter_id or adapter_id.startswith("#"):
            continue
        command_template = " ".join(str(row.get("command_template", "")).split()).strip()
        if not command_template:
            fail(f"External adapter missing command_template: {adapter_id}")
        adapters.append(
            {
                "adapter_id": adapter_id,
                "name": " ".join(str(row.get("name", adapter_id)).split()).strip() or adapter_id,
                "kind": " ".join(str(row.get("kind", "")).split()).strip(),
                "model": " ".join(str(row.get("model", "")).split()).strip(),
                "notes": " ".join(str(row.get("notes", "")).split()).strip(),
                "command_template": command_template,
            }
        )
    return registry_path, adapters


def find_external_adapter(adapters, adapter_id):
    for adapter in adapters:
        if adapter.get("adapter_id") == adapter_id:
            return adapter
    fail(f"Unknown external adapter: {adapter_id}")


def family_artifacts(reports_dir, label, family):
    family_id = family["family_id"]
    prefix = f"{label}-{family_id}"
    return {
        "regressions_summary": str(pathlib.Path(reports_dir) / f"{prefix}-regressions-summary.json"),
        "holdout_summary": str(pathlib.Path(reports_dir) / f"{prefix}-holdout-summary.json"),
        "transfer_json": str(pathlib.Path(reports_dir) / f"{prefix}-transfer.json"),
    }


def external_adapter_artifacts(reports_dir, label, adapter_id, out_json="", out_md=""):
    prefix = f"{label}-{adapter_id}"
    artifacts = {
        "out_json": out_json or str(pathlib.Path(reports_dir) / f"{prefix}-capability-benchmark-external-scorecard.json"),
        "out_md": out_md or str(pathlib.Path(reports_dir) / f"{prefix}-capability-benchmark-external-scorecard.md"),
    }
    return artifacts


def plan_commands(reports_dir, label, family):
    cycle = family["cycle_script"]
    artifacts = family_artifacts(reports_dir, label, family)
    family_id = family["family_id"]
    reg_label = f"{label}-{family_id}-regressions"
    hold_label = f"{label}-{family_id}-holdout"
    reports_env = f"ARTIFICER_ASSAY_REPORTS_DIR={shlex.quote(reports_dir)}"
    commands = []
    if family["run_style"] == "tasks":
        commands.append(
            f"{reports_env} sh {shlex.quote(cycle)} run --label {shlex.quote(reg_label)} --tasks-file {shlex.quote(family['regressions_fixture'])}"
        )
        commands.append(
            f"{reports_env} sh {shlex.quote(cycle)} run --label {shlex.quote(hold_label)} --tasks-file {shlex.quote(family['holdout_fixture'])}"
        )
    else:
        commands.append(
            f"{reports_env} sh {shlex.quote(cycle)} run --profile regressions --label {shlex.quote(reg_label)}"
        )
        commands.append(
            f"{reports_env} sh {shlex.quote(cycle)} run --profile holdout --label {shlex.quote(hold_label)}"
        )
    if family["transfer_style"] == "battery":
        commands.append(
            f"{reports_env} sh {shlex.quote(cycle)} transfer --battery-summary {shlex.quote(artifacts['regressions_summary'])} --holdout-summary {shlex.quote(artifacts['holdout_summary'])} --label {shlex.quote(label + '-' + family_id)}"
        )
    else:
        commands.append(
            f"{reports_env} sh {shlex.quote(cycle)} transfer --regressions-report {shlex.quote(artifacts['regressions_summary'])} --holdout-report {shlex.quote(artifacts['holdout_summary'])} --label {shlex.quote(label + '-' + family_id)}"
        )
    return commands, artifacts


def external_adapter_command(adapter, reports_dir, label, manifest_path, out_json="", out_md="", site_root="", project_root=""):
    artifacts = external_adapter_artifacts(reports_dir, label, adapter["adapter_id"], out_json=out_json, out_md=out_md)
    variables = {
        "adapter_id": adapter["adapter_id"],
        "reports_dir": str(pathlib.Path(reports_dir)),
        "label": label,
        "manifest": str(pathlib.Path(manifest_path)),
        "out_json": artifacts["out_json"],
        "out_md": artifacts["out_md"],
        "site_root": str(pathlib.Path(site_root)),
        "project_root": str(pathlib.Path(project_root)),
    }
    try:
        template_tokens = shlex.split(adapter["command_template"])
    except Exception as exc:
        fail(f"Invalid external adapter command template for {adapter['adapter_id']}: {exc}")
    command = []
    for token in template_tokens:
        try:
            command.append(token.format_map(variables))
        except KeyError as exc:
            fail(f"Unknown placeholder in external adapter template {adapter['adapter_id']}: {exc}")
    if not command:
        fail(f"External adapter command resolved empty: {adapter['adapter_id']}")
    return command, artifacts


def weak_reason(present, gate_pass, risk, score):
    if not present:
        return "missing-report"
    if not gate_pass:
        return "gate-failed"
    if str(risk).strip().lower() == "high":
        return "high-risk"
    if score < 75.0:
        return "score-below-threshold"
    return ""


def score_simple(report):
    reg = float(report.get("regressions_pass_rate", 0.0) or 0.0)
    hold = float(report.get("holdout_pass_rate", 0.0) or 0.0)
    gate_pass = bool(report.get("all_gates_pass", False))
    risk = str(report.get("transfer_risk", "medium")).strip().lower() or "medium"
    base = ((reg + hold) / 2.0) * 100.0
    if not gate_pass:
        base -= 10.0
    base -= risk_penalty(risk)
    return round(clamp(base), 2), gate_pass, risk, {
        "regressions_pass_rate": round(reg, 4),
        "holdout_pass_rate": round(hold, 4),
    }


def score_broad(report):
    holdout = report.get("holdout", {}) if isinstance(report.get("holdout", {}), dict) else {}
    deltas = report.get("deltas", {}) if isinstance(report.get("deltas", {}), dict) else {}
    overall = float(holdout.get("avg_overall", 0.0) or 0.0)
    transfer = float(holdout.get("avg_transfer_readiness", 0.0) or 0.0)
    evidence = float(holdout.get("avg_evidence", 0.0) or 0.0)
    claim = float(holdout.get("avg_claim_evidence_completeness", 0.0) or 0.0)
    gate_pass = bool(report.get("all_gates_pass", False))
    risk = str(report.get("transfer_risk", "medium")).strip().lower() or "medium"
    overfit = bool(report.get("overfit_risk", False))
    delta_overall = float(deltas.get("overall", 0.0) or 0.0)
    delta_transfer = float(deltas.get("transfer_readiness", 0.0) or 0.0)
    base = (0.35 * overall) + (0.25 * transfer) + (0.20 * evidence) + (0.20 * claim)
    if not gate_pass:
        base -= 10.0
    if overfit:
        base -= 8.0
    if delta_overall < 0:
        base += delta_overall * 1.5
    if delta_transfer < 0:
        base += delta_transfer * 1.5
    base -= risk_penalty(risk)
    return round(clamp(base), 2), gate_pass, risk, {
        "avg_overall": round(overall, 2),
        "avg_transfer_readiness": round(transfer, 2),
        "avg_evidence": round(evidence, 2),
        "avg_claim_evidence_completeness": round(claim, 2),
        "overfit_risk": overfit,
    }


def score_rich(report):
    holdout = report.get("holdout", {}) if isinstance(report.get("holdout", {}), dict) else {}
    overall = float(holdout.get("avg_overall", report.get("avg_overall", 0.0)) or 0.0)
    exact = float(holdout.get("exact_contract_rate", report.get("exact_contract_rate", 0.0)) or 0.0)
    required = float(holdout.get("avg_required_ratio", report.get("avg_required_ratio", 0.0)) or 0.0)
    generic = float(holdout.get("generic_fallback_rate", report.get("generic_fallback_rate", 0.0)) or 0.0)
    gate_pass = bool(report.get("all_gates_pass", False))
    risk = str(report.get("transfer_risk", "medium")).strip().lower() or "medium"
    base = (0.55 * overall) + (20.0 * exact) + (20.0 * required) - (10.0 * generic)
    if not gate_pass:
        base -= 10.0
    base -= risk_penalty(risk)
    return round(clamp(base), 2), gate_pass, risk, {
        "avg_overall": round(overall, 2),
        "exact_contract_rate": round(exact, 4),
        "avg_required_ratio": round(required, 4),
        "generic_fallback_rate": round(generic, 4),
    }


def score_family(report_path, family):
    report = parse_json_file(report_path, {})
    if not report:
        return {
            "id": family["family_id"],
            "name": family["name"],
            "axis": family["axis"],
            "weight": family["weight"],
            "critical": family["critical"],
            "report_kind": family["score_style"],
            "cycle_script": family["cycle_script"],
            "report_path": str(report_path),
            "present": False,
            "score": 0.0,
            "gate_pass": False,
            "risk": "missing",
            "weak_reason": "missing-report",
            "metrics": {},
        }
    if family["score_style"] == "broad":
        score, gate_pass, risk, metrics = score_broad(report)
    elif family["score_style"] == "rich":
        score, gate_pass, risk, metrics = score_rich(report)
    else:
        score, gate_pass, risk, metrics = score_simple(report)
    weak = weak_reason(True, gate_pass, risk, score)
    return {
        "id": family["family_id"],
        "name": family["name"],
        "axis": family["axis"],
        "weight": family["weight"],
        "critical": family["critical"],
        "report_kind": family["score_style"],
        "cycle_script": family["cycle_script"],
        "report_path": str(report_path),
        "present": True,
        "score": score,
        "gate_pass": gate_pass,
        "risk": risk,
        "weak_reason": weak,
        "metrics": metrics,
    }


def build_scorecard(manifest_path, families, reports_dir, label):
    rows = []
    total_weight = 0.0
    weighted_score = 0.0
    present_count = 0
    critical_failures = 0
    high_risk = 0
    weak_families = []
    for family in families:
        total_weight += family["weight"]
        artifacts = family_artifacts(reports_dir, label, family)
        row = score_family(artifacts["transfer_json"], family)
        rows.append(row)
        if row["present"]:
            present_count += 1
        weighted_score += row["score"] * family["weight"]
        if row["risk"] == "high":
            high_risk += 1
        if row["critical"] and ((not row["present"]) or (not row["gate_pass"]) or row["score"] < 70.0 or row["risk"] == "high"):
            critical_failures += 1
        if row["weak_reason"]:
            weak_families.append({
                "id": row["id"],
                "score": row["score"],
                "critical": row["critical"],
                "reason": row["weak_reason"],
            })
    overall_score = round(weighted_score / total_weight, 2) if total_weight > 0 else 0.0
    coverage_ratio = round(present_count / len(families), 4) if families else 0.0
    recommendation = "hold"
    if coverage_ratio >= 1.0 and critical_failures == 0 and high_risk == 0 and overall_score >= 80.0:
        recommendation = "promote"
    weak_families.sort(key=lambda item: (not item["critical"], item["score"], item["id"]))
    scorecard = {
        "label": label,
        "generated_at": dt.datetime.utcnow().replace(microsecond=0).isoformat() + "Z",
        "manifest_path": str(manifest_path),
        "family_count": len(families),
        "families": rows,
        "totals": {
            "overall_score": overall_score,
            "coverage_ratio": coverage_ratio,
            "critical_failures": critical_failures,
            "high_risk_family_count": high_risk,
            "weak_family_count": len(weak_families),
            "present_family_count": present_count,
        },
        "weak_families": weak_families[:6],
        "recommendation": recommendation,
    }
    return scorecard


def render_scorecard_markdown(scorecard):
    lines = [
        f"# Capability Benchmark Scorecard: {scorecard['label']}",
        "",
        "## Summary",
        f"- Overall score: {scorecard['totals']['overall_score']}",
        f"- Coverage ratio: {scorecard['totals']['coverage_ratio']}",
        f"- Critical failures: {scorecard['totals']['critical_failures']}",
        f"- High-risk families: {scorecard['totals']['high_risk_family_count']}",
        f"- Weak families: {scorecard['totals']['weak_family_count']}",
        f"- Recommendation: {scorecard['recommendation']}",
        "",
        "## Families",
        "| Family | Score | Gate | Risk | Critical | Weak reason |",
        "|---|---:|---|---|---|---|",
    ]
    for row in scorecard["families"]:
        lines.append(
            f"| {row['id']} | {row['score']} | {'pass' if row['gate_pass'] else 'fail'} | {row['risk']} | {'yes' if row['critical'] else 'no'} | {row['weak_reason'] or ''} |"
        )
    if scorecard["weak_families"]:
        lines.extend(["", "## Highest-Leverage Gaps"])
        for item in scorecard["weak_families"]:
            lines.append(f"- {item['id']}: score={item['score']} critical={'yes' if item['critical'] else 'no'} reason={item['reason']}")
    return "\n".join(lines) + "\n"


def load_scorecard(path):
    payload = parse_json_file(path, {})
    if not payload:
        fail(f"Scorecard not found or invalid: {path}")
    return payload


def compare_scorecards(label, baseline, candidate):
    baseline_families = {item.get("id"): item for item in baseline.get("families", []) if isinstance(item, dict)}
    candidate_families = {item.get("id"): item for item in candidate.get("families", []) if isinstance(item, dict)}
    baseline_weak = {item.get("id") for item in baseline.get("weak_families", []) if isinstance(item, dict)}
    candidate_weak = {item.get("id") for item in candidate.get("weak_families", []) if isinstance(item, dict)}
    recovered = sorted([family_id for family_id in baseline_weak if family_id and family_id not in candidate_weak])
    new_weak = sorted([family_id for family_id in candidate_weak if family_id and family_id not in baseline_weak])
    improved = []
    degraded = []
    for family_id, candidate_row in sorted(candidate_families.items()):
        baseline_row = baseline_families.get(family_id, {})
        delta = round(float(candidate_row.get("score", 0.0) or 0.0) - float(baseline_row.get("score", 0.0) or 0.0), 2)
        if delta > 0:
            improved.append({"id": family_id, "score_delta": delta})
        elif delta < 0:
            degraded.append({"id": family_id, "score_delta": delta})
    overall_delta = round(float(candidate.get("totals", {}).get("overall_score", 0.0) or 0.0) - float(baseline.get("totals", {}).get("overall_score", 0.0) or 0.0), 2)
    coverage_delta = round(float(candidate.get("totals", {}).get("coverage_ratio", 0.0) or 0.0) - float(baseline.get("totals", {}).get("coverage_ratio", 0.0) or 0.0), 4)
    candidate_promotable = (
        str(candidate.get("recommendation", "")).strip().lower() == "promote"
        and overall_delta >= 0
        and coverage_delta >= 0
        and int(candidate.get("totals", {}).get("critical_failures", 0) or 0) <= int(baseline.get("totals", {}).get("critical_failures", 0) or 0)
    )
    result = {
        "label": label,
        "baseline_label": baseline.get("label", ""),
        "candidate_label": candidate.get("label", ""),
        "generated_at": dt.datetime.utcnow().replace(microsecond=0).isoformat() + "Z",
        "recommendation": "promote-candidate" if candidate_promotable else "hold",
        "candidate_promotable": candidate_promotable,
        "deltas": {
            "overall_score": overall_delta,
            "coverage_ratio": coverage_delta,
            "critical_failures": int(candidate.get("totals", {}).get("critical_failures", 0) or 0) - int(baseline.get("totals", {}).get("critical_failures", 0) or 0),
            "high_risk_family_count": int(candidate.get("totals", {}).get("high_risk_family_count", 0) or 0) - int(baseline.get("totals", {}).get("high_risk_family_count", 0) or 0),
        },
        "recovered_families": recovered,
        "new_weak_families": new_weak,
        "improved_families": improved[:10],
        "degraded_families": degraded[:10],
    }
    return result


def compare_external_scorecards(label, external_meta, external, candidate):
    external_families = {item.get("id"): item for item in external.get("families", []) if isinstance(item, dict)}
    candidate_families = {item.get("id"): item for item in candidate.get("families", []) if isinstance(item, dict)}
    family_ids = sorted(set(external_families.keys()) | set(candidate_families.keys()))

    candidate_lead_families = []
    candidate_gap_families = []
    for family_id in family_ids:
        external_row = external_families.get(family_id, {})
        candidate_row = candidate_families.get(family_id, {})
        candidate_score = round(float(candidate_row.get("score", 0.0) or 0.0), 2)
        external_score = round(float(external_row.get("score", 0.0) or 0.0), 2)
        score_delta = round(candidate_score - external_score, 2)
        if score_delta == 0:
            continue
        item = {
            "id": family_id,
            "score_delta": score_delta,
            "candidate_score": candidate_score,
            "external_score": external_score,
            "candidate_critical": bool(candidate_row.get("critical", False)),
            "candidate_gate_pass": bool(candidate_row.get("gate_pass", False)),
            "candidate_weak_reason": str(candidate_row.get("weak_reason", "")).strip(),
            "external_risk": str(external_row.get("risk", "")).strip(),
        }
        if score_delta > 0:
            candidate_lead_families.append(item)
        else:
            candidate_gap_families.append(item)

    candidate_lead_families.sort(key=lambda item: (-item["score_delta"], item["id"]))
    candidate_gap_families.sort(key=lambda item: (not item["candidate_critical"], item["score_delta"], item["id"]))

    overall_delta = round(float(candidate.get("totals", {}).get("overall_score", 0.0) or 0.0) - float(external.get("totals", {}).get("overall_score", 0.0) or 0.0), 2)
    coverage_delta = round(float(candidate.get("totals", {}).get("coverage_ratio", 0.0) or 0.0) - float(external.get("totals", {}).get("coverage_ratio", 0.0) or 0.0), 4)
    critical_delta = int(candidate.get("totals", {}).get("critical_failures", 0) or 0) - int(external.get("totals", {}).get("critical_failures", 0) or 0)
    high_risk_delta = int(candidate.get("totals", {}).get("high_risk_family_count", 0) or 0) - int(external.get("totals", {}).get("high_risk_family_count", 0) or 0)
    candidate_beats_external = (
        str(candidate.get("recommendation", "")).strip().lower() == "promote"
        and overall_delta >= 0
        and coverage_delta >= 0
        and critical_delta <= 0
        and high_risk_delta <= 0
        and not any(item.get("candidate_critical", False) for item in candidate_gap_families)
    )
    recommendation = "external-still-ahead"
    if candidate_beats_external:
        recommendation = "candidate-beats-external"
    elif overall_delta >= 0 and coverage_delta >= 0 and critical_delta <= 0:
        recommendation = "mixed"

    result = {
        "label": label,
        "generated_at": dt.datetime.utcnow().replace(microsecond=0).isoformat() + "Z",
        "external_baseline": {
            "name": " ".join(str(external_meta.get("name", "")).split()).strip(),
            "kind": " ".join(str(external_meta.get("kind", "")).split()).strip(),
            "model": " ".join(str(external_meta.get("model", "")).split()).strip(),
            "notes": " ".join(str(external_meta.get("notes", "")).split()).strip(),
        },
        "external_label": external.get("label", ""),
        "candidate_label": candidate.get("label", ""),
        "recommendation": recommendation,
        "candidate_beats_external": candidate_beats_external,
        "deltas": {
            "overall_score": overall_delta,
            "coverage_ratio": coverage_delta,
            "critical_failures": critical_delta,
            "high_risk_family_count": high_risk_delta,
        },
        "candidate_gap_families": candidate_gap_families[:10],
        "candidate_lead_families": candidate_lead_families[:10],
    }
    return result


def render_compare_markdown(payload):
    lines = [
        f"# Capability Benchmark Compare: {payload['label']}",
        "",
        "## Summary",
        f"- Baseline: {payload['baseline_label']}",
        f"- Candidate: {payload['candidate_label']}",
        f"- Overall score delta: {payload['deltas']['overall_score']}",
        f"- Coverage ratio delta: {payload['deltas']['coverage_ratio']}",
        f"- Recommendation: {payload['recommendation']}",
        f"- Candidate promotable: {'true' if payload['candidate_promotable'] else 'false'}",
    ]
    if payload["recovered_families"]:
        lines.extend(["", "## Recovered Families"])
        for family_id in payload["recovered_families"]:
            lines.append(f"- {family_id}")
    if payload["new_weak_families"]:
        lines.extend(["", "## New Weak Families"])
        for family_id in payload["new_weak_families"]:
            lines.append(f"- {family_id}")
    return "\n".join(lines) + "\n"


def render_external_compare_markdown(payload):
    external_baseline = payload.get("external_baseline", {}) if isinstance(payload, dict) else {}
    lines = [
        f"# Capability Benchmark External Compare: {payload['label']}",
        "",
        "## Summary",
        f"- External baseline: {external_baseline.get('name', '')}",
        f"- External kind: {external_baseline.get('kind', '')}",
        f"- External model: {external_baseline.get('model', '')}",
        f"- Candidate: {payload.get('candidate_label', '')}",
        f"- Overall score delta: {payload['deltas']['overall_score']}",
        f"- Coverage ratio delta: {payload['deltas']['coverage_ratio']}",
        f"- Recommendation: {payload['recommendation']}",
        f"- Candidate beats external: {'true' if payload.get('candidate_beats_external') else 'false'}",
    ]
    if external_baseline.get("notes"):
        lines.append(f"- Notes: {external_baseline.get('notes')}")
    if payload.get("candidate_gap_families"):
        lines.extend(["", "## External Baseline Still Ahead"])
        for item in payload["candidate_gap_families"]:
            lines.append(
                f"- {item['id']}: delta={item['score_delta']} candidate={item['candidate_score']} external={item['external_score']}"
            )
    if payload.get("candidate_lead_families"):
        lines.extend(["", "## Candidate Leads"])
        for item in payload["candidate_lead_families"]:
            lines.append(
                f"- {item['id']}: delta={item['score_delta']} candidate={item['candidate_score']} external={item['external_score']}"
            )
    return "\n".join(lines) + "\n"


parser = argparse.ArgumentParser(add_help=False)
parser.add_argument("command")
parser.add_argument("rest", nargs=argparse.REMAINDER)
ns = parser.parse_args(sys.argv[1:2] + sys.argv[2:])

default_manifest = os.environ.get("MANIFEST_DEFAULT", "")
default_external_registry = os.environ.get("EXTERNAL_REGISTRY_DEFAULT", "")
default_reports_dir = os.environ.get("REPORTS_DIR_DEFAULT", "")
site_root = os.environ.get("SITE_ROOT_ENV", "")
project_root = os.environ.get("PROJECT_ROOT_ENV", "")

command = ns.command
argv = sys.argv[2:]

if command == "manifest":
    ap = argparse.ArgumentParser(prog="capability-benchmark-cycle.sh manifest")
    ap.add_argument("--manifest", default=default_manifest)
    args = ap.parse_args(argv)
    manifest_path, families = load_manifest(args.manifest, project_root, site_root)
    payload = {
        "manifest_path": str(manifest_path),
        "family_count": len(families),
        "families": families,
    }
    print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))
elif command == "plan":
    ap = argparse.ArgumentParser(prog="capability-benchmark-cycle.sh plan")
    ap.add_argument("--label", default="capability-battery")
    ap.add_argument("--reports-dir", default=default_reports_dir)
    ap.add_argument("--manifest", default=default_manifest)
    args = ap.parse_args(argv)
    manifest_path, families = load_manifest(args.manifest, project_root, site_root)
    plan = []
    for family in families:
        commands, artifacts = plan_commands(args.reports_dir, args.label, family)
        plan.append({
            "id": family["family_id"],
            "name": family["name"],
            "axis": family["axis"],
            "commands": commands,
            "artifacts": artifacts,
        })
    payload = {
        "manifest_path": str(manifest_path),
        "label": args.label,
        "reports_dir": args.reports_dir,
        "family_count": len(families),
        "families": plan,
    }
    print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))
elif command == "score":
    ap = argparse.ArgumentParser(prog="capability-benchmark-cycle.sh score")
    ap.add_argument("--label", required=True)
    ap.add_argument("--reports-dir", default=default_reports_dir)
    ap.add_argument("--manifest", default=default_manifest)
    ap.add_argument("--out-json", default="")
    ap.add_argument("--out-md", default="")
    args = ap.parse_args(argv)
    manifest_path, families = load_manifest(args.manifest, project_root, site_root)
    pathlib.Path(args.reports_dir).mkdir(parents=True, exist_ok=True)
    out_json = pathlib.Path(args.out_json) if args.out_json else pathlib.Path(args.reports_dir) / f"{args.label}-capability-benchmark-scorecard.json"
    out_md = pathlib.Path(args.out_md) if args.out_md else pathlib.Path(args.reports_dir) / f"{args.label}-capability-benchmark-scorecard.md"
    scorecard = build_scorecard(manifest_path, families, args.reports_dir, args.label)
    out_json.write_text(json.dumps(scorecard, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    out_md.write_text(render_scorecard_markdown(scorecard), encoding="utf-8")
    print(str(out_json))
    print(str(out_md))
elif command == "compare":
    ap = argparse.ArgumentParser(prog="capability-benchmark-cycle.sh compare")
    ap.add_argument("--baseline", required=True)
    ap.add_argument("--candidate", required=True)
    ap.add_argument("--label", default="capability-benchmark-compare")
    ap.add_argument("--reports-dir", default=default_reports_dir)
    ap.add_argument("--out-json", default="")
    ap.add_argument("--out-md", default="")
    args = ap.parse_args(argv)
    pathlib.Path(args.reports_dir).mkdir(parents=True, exist_ok=True)
    baseline = load_scorecard(args.baseline)
    candidate = load_scorecard(args.candidate)
    payload = compare_scorecards(args.label, baseline, candidate)
    out_json = pathlib.Path(args.out_json) if args.out_json else pathlib.Path(args.reports_dir) / f"{args.label}-capability-benchmark-compare.json"
    out_md = pathlib.Path(args.out_md) if args.out_md else pathlib.Path(args.reports_dir) / f"{args.label}-capability-benchmark-compare.md"
    out_json.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    out_md.write_text(render_compare_markdown(payload), encoding="utf-8")
    print(str(out_json))
    print(str(out_md))
elif command == "external-adapters":
    ap = argparse.ArgumentParser(prog="capability-benchmark-cycle.sh external-adapters")
    ap.add_argument("--registry", default=default_external_registry)
    args = ap.parse_args(argv)
    registry_path, adapters = load_external_registry(args.registry)
    payload = {
        "registry_path": str(registry_path),
        "adapter_count": len(adapters),
        "adapters": [
            {
                "adapter_id": adapter["adapter_id"],
                "name": adapter["name"],
                "kind": adapter["kind"],
                "model": adapter["model"],
                "notes": adapter["notes"],
            }
            for adapter in adapters
        ],
    }
    print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))
elif command == "external-plan":
    ap = argparse.ArgumentParser(prog="capability-benchmark-cycle.sh external-plan")
    ap.add_argument("--adapter", required=True)
    ap.add_argument("--label", default="external-benchmark")
    ap.add_argument("--reports-dir", default=default_reports_dir)
    ap.add_argument("--manifest", default=default_manifest)
    ap.add_argument("--registry", default=default_external_registry)
    ap.add_argument("--out-json", default="")
    ap.add_argument("--out-md", default="")
    args = ap.parse_args(argv)
    manifest_path, _ = load_manifest(args.manifest, project_root, site_root)
    registry_path, adapters = load_external_registry(args.registry)
    adapter = find_external_adapter(adapters, args.adapter)
    command_tokens, artifacts = external_adapter_command(
        adapter,
        args.reports_dir,
        args.label,
        manifest_path,
        out_json=args.out_json,
        out_md=args.out_md,
        site_root=site_root,
        project_root=project_root,
    )
    payload = {
        "registry_path": str(registry_path),
        "adapter": {
            "adapter_id": adapter["adapter_id"],
            "name": adapter["name"],
            "kind": adapter["kind"],
            "model": adapter["model"],
            "notes": adapter["notes"],
        },
        "label": args.label,
        "reports_dir": args.reports_dir,
        "manifest_path": str(manifest_path),
        "command": command_tokens,
        "command_display": " ".join(shlex.quote(token) for token in command_tokens),
        "artifacts": artifacts,
    }
    print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))
elif command == "external-run":
    ap = argparse.ArgumentParser(prog="capability-benchmark-cycle.sh external-run")
    ap.add_argument("--adapter", required=True)
    ap.add_argument("--label", default="external-benchmark")
    ap.add_argument("--reports-dir", default=default_reports_dir)
    ap.add_argument("--manifest", default=default_manifest)
    ap.add_argument("--registry", default=default_external_registry)
    ap.add_argument("--out-json", default="")
    ap.add_argument("--out-md", default="")
    args = ap.parse_args(argv)
    pathlib.Path(args.reports_dir).mkdir(parents=True, exist_ok=True)
    manifest_path, _ = load_manifest(args.manifest, project_root, site_root)
    registry_path, adapters = load_external_registry(args.registry)
    adapter = find_external_adapter(adapters, args.adapter)
    command_tokens, artifacts = external_adapter_command(
        adapter,
        args.reports_dir,
        args.label,
        manifest_path,
        out_json=args.out_json,
        out_md=args.out_md,
        site_root=site_root,
        project_root=project_root,
    )
    env = dict(os.environ)
    env["ARTIFICER_ASSAY_REPORTS_DIR"] = args.reports_dir
    proc = subprocess.run(command_tokens, check=False, capture_output=True, text=True, env=env)
    if proc.returncode != 0:
        fail(
            "External adapter failed for "
            + adapter["adapter_id"]
            + ": "
            + " ".join(str(proc.stderr or proc.stdout or "").split())
        )
    load_scorecard(artifacts["out_json"])
    print(str(pathlib.Path(artifacts["out_json"])))
    print(str(pathlib.Path(artifacts["out_md"])))
elif command == "external-compare":
    ap = argparse.ArgumentParser(prog="capability-benchmark-cycle.sh external-compare")
    ap.add_argument("--external-baseline", required=True)
    ap.add_argument("--candidate", required=True)
    ap.add_argument("--external-name", required=True)
    ap.add_argument("--external-kind", default="")
    ap.add_argument("--external-model", default="")
    ap.add_argument("--external-notes", default="")
    ap.add_argument("--label", default="capability-benchmark-external-compare")
    ap.add_argument("--reports-dir", default=default_reports_dir)
    ap.add_argument("--out-json", default="")
    ap.add_argument("--out-md", default="")
    args = ap.parse_args(argv)
    pathlib.Path(args.reports_dir).mkdir(parents=True, exist_ok=True)
    external = load_scorecard(args.external_baseline)
    candidate = load_scorecard(args.candidate)
    payload = compare_external_scorecards(
        args.label,
        {
            "name": args.external_name,
            "kind": args.external_kind,
            "model": args.external_model,
            "notes": args.external_notes,
        },
        external,
        candidate,
    )
    out_json = pathlib.Path(args.out_json) if args.out_json else pathlib.Path(args.reports_dir) / f"{args.label}-capability-benchmark-external-compare.json"
    out_md = pathlib.Path(args.out_md) if args.out_md else pathlib.Path(args.reports_dir) / f"{args.label}-capability-benchmark-external-compare.md"
    out_json.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    out_md.write_text(render_external_compare_markdown(payload), encoding="utf-8")
    print(str(out_json))
    print(str(out_md))
else:
    fail(f"Unknown command: {command}")
PY
