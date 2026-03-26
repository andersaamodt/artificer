#!/bin/sh

ARTIFICER_STATE_ROOT=${ARTIFICER_STATE_ROOT:-${XDG_STATE_HOME:-$HOME/.local/state}/artificer}
ARTIFICER_CACHE_ROOT=${ARTIFICER_CACHE_ROOT:-${XDG_CACHE_HOME:-$HOME/.cache}/artificer}
ARTIFICER_REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)

ARTIFICER_ASSAY_REPORTS_DIR=${ARTIFICER_ASSAY_REPORTS_DIR:-$ARTIFICER_STATE_ROOT/assay-reports}
ARTIFICER_ASSAY_RUNS_DIR=${ARTIFICER_ASSAY_RUNS_DIR:-$ARTIFICER_STATE_ROOT/assay-runs}
ARTIFICER_GUI_PLAYWRIGHT_BROWSERS_DIR=${ARTIFICER_GUI_PLAYWRIGHT_BROWSERS_DIR:-$ARTIFICER_CACHE_ROOT/playwright-browsers}
ARTIFICER_GUI_PLAYWRIGHT_VENV_DIR=${ARTIFICER_GUI_PLAYWRIGHT_VENV_DIR:-$ARTIFICER_CACHE_ROOT/venv-gui-playwright}
ARTIFICER_GUI_TMP_SITES_DIR=${ARTIFICER_GUI_TMP_SITES_DIR:-$ARTIFICER_CACHE_ROOT/tmp-gui-probe-sites}
ARTIFICER_DOC_EXPORTS_DIR=${ARTIFICER_DOC_EXPORTS_DIR:-$ARTIFICER_STATE_ROOT/doc-exports}

artificer_local_path_is_inside_repo() {
  candidate_path=$1
  [ -n "$candidate_path" ] || return 1
  case "$candidate_path/" in
    "$ARTIFICER_REPO_ROOT/"*|"$ARTIFICER_REPO_ROOT")
      return 0
      ;;
  esac
  return 1
}

artificer_local_normalize_artifact_paths() {
  if artificer_local_path_is_inside_repo "$ARTIFICER_STATE_ROOT"; then
    ARTIFICER_STATE_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}/artificer"
  fi
  if artificer_local_path_is_inside_repo "$ARTIFICER_CACHE_ROOT"; then
    ARTIFICER_CACHE_ROOT="${XDG_CACHE_HOME:-$HOME/.cache}/artificer"
  fi

  default_assay_reports="$ARTIFICER_STATE_ROOT/assay-reports"
  default_assay_runs="$ARTIFICER_STATE_ROOT/assay-runs"
  default_playwright_browsers="$ARTIFICER_CACHE_ROOT/playwright-browsers"
  default_playwright_venv="$ARTIFICER_CACHE_ROOT/venv-gui-playwright"
  default_tmp_sites="$ARTIFICER_CACHE_ROOT/tmp-gui-probe-sites"
  default_doc_exports="$ARTIFICER_STATE_ROOT/doc-exports"

  if artificer_local_path_is_inside_repo "$ARTIFICER_ASSAY_REPORTS_DIR"; then
    ARTIFICER_ASSAY_REPORTS_DIR="$default_assay_reports"
  fi
  if artificer_local_path_is_inside_repo "$ARTIFICER_ASSAY_RUNS_DIR"; then
    ARTIFICER_ASSAY_RUNS_DIR="$default_assay_runs"
  fi
  if artificer_local_path_is_inside_repo "$ARTIFICER_GUI_PLAYWRIGHT_BROWSERS_DIR"; then
    ARTIFICER_GUI_PLAYWRIGHT_BROWSERS_DIR="$default_playwright_browsers"
  fi
  if artificer_local_path_is_inside_repo "$ARTIFICER_GUI_PLAYWRIGHT_VENV_DIR"; then
    ARTIFICER_GUI_PLAYWRIGHT_VENV_DIR="$default_playwright_venv"
  fi
  if artificer_local_path_is_inside_repo "$ARTIFICER_GUI_TMP_SITES_DIR"; then
    ARTIFICER_GUI_TMP_SITES_DIR="$default_tmp_sites"
  fi
  if artificer_local_path_is_inside_repo "$ARTIFICER_DOC_EXPORTS_DIR"; then
    ARTIFICER_DOC_EXPORTS_DIR="$default_doc_exports"
  fi
}

artificer_ensure_local_dirs() {
  artificer_local_normalize_artifact_paths
  mkdir -p \
    "$ARTIFICER_STATE_ROOT" \
    "$ARTIFICER_CACHE_ROOT" \
    "$ARTIFICER_ASSAY_REPORTS_DIR" \
    "$ARTIFICER_ASSAY_RUNS_DIR" \
    "$ARTIFICER_GUI_PLAYWRIGHT_BROWSERS_DIR" \
    "$ARTIFICER_GUI_PLAYWRIGHT_VENV_DIR" \
    "$ARTIFICER_GUI_TMP_SITES_DIR" \
    "$ARTIFICER_DOC_EXPORTS_DIR"
}
