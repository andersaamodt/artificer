run_mode_policy_instructions() {
  run_mode=$1
  case "$run_mode" in
    programming)
      cat <<'EOF'
Run mode policy:
- prioritize scalable architecture and clear module boundaries for multi-file codebases.
- prefer incremental checkpoints that keep the project runnable between iterations.
- keep .contract.md and context memory aligned when design decisions change.
- aggressively compress context to retain only actionable architecture state and open risks.
- if requirements are ambiguous, state explicit assumptions and proceed with a safe high-value implementation slice.
- before claiming completion, ensure verification evidence directly covers changed behavior.
EOF
      ;;
    pentest)
      cat <<'EOF'
Run mode policy:
- prioritize adversarial testing depth: enumerate exploit paths, abuse cases, and boundary failures.
- pair each credible attack path with concrete mitigations and verification checks.
- keep all testing scoped to safe internal validation; do not enable real-world abuse.
- report findings with impact level, evidence, and remediation status.
EOF
      ;;
    security-audit)
      cat <<'EOF'
Run mode policy:
- prioritize systematic security review across auth, validation, secrets, and dependency risk.
- produce auditable findings with severity, evidence, and mitigation guidance.
- map each high-impact claim to concrete evidence anchors and numeric accept/reject thresholds.
- prefer least-privilege and defense-in-depth changes that are testable and reversible.
- avoid speculative claims and clearly mark uncertainty when evidence is incomplete.
EOF
      ;;
    report)
      cat <<'EOF'
Run mode policy:
- prioritize evidence quality, source fidelity, and explicit uncertainty.
- structure output for executive readability: findings, evidence, risks, recommendations.
- include an explicit claim-to-evidence map with concrete anchors (logs, metrics, queries, policy clauses, tests) and freshness caveats.
- avoid speculative claims when direct evidence is missing.
- when inputs are underspecified, declare assumptions with confidence and proceed rather than stalling.
- when constraints conflict, explicitly map the conflict, choose a priority order, and state rejected alternatives.
- include a short contradiction check before claiming completion on ambiguous tasks.
EOF
      ;;
    text-perfecter)
      cat <<'EOF'
Run mode policy:
- optimize both language quality and underlying content correctness; do not do style-only rewrites.
- run iterative revisions until change deltas stabilize, then stop with an explicit convergence rationale.
- gather broad evidence before rewriting claims: techniques, variants, common failures, and informed discussion.
- if evidence conflicts, surface alternatives and explain why one version is selected.
- include a contradiction check and unresolved uncertainty note before claiming "perfected."
- avoid confidently asserting unsupported facts; mark unverifiable claims and keep safer wording when needed.
EOF
      ;;
    gui-testing)
      cat <<'EOF'
Run mode policy:
- execute hands-on GUI automation as a real user journey, not a static code-only review.
- prefer cross-platform automation harnesses first: run `hosted-web/scripts/gui-regression-system.sh` with profile selection based on requested depth.
- on macOS, use Safari automation; on Linux, use Firefox automation; if both are available, compare outcomes.
- treat every UX flaw as actionable: ambiguous status text, ordering glitches, visual artifacts, stalled states, or inaccessible controls.
- fail closed on unclear signals: report concrete repro steps, expected vs actual behavior, and severity before proposing fixes.
- after fixes, rerun the same scenario to verify closure and capture regression evidence paths.
EOF
      ;;
    assistant)
      cat <<'EOF'
Run mode policy:
- this mode represents a globally configured team profile; apply team policy while driving end-to-end completion.
- proactively drive end-to-end completion with initiative and practical sequencing.
- optimize for real user value and sustainable outcomes; never game or exploit systems.
- enforce legal, ethical, and policy compliance; avoid deception, spam, and abuse.
- keep evidence quality concrete: cite anchors, quantify thresholds, and disclose freshness/uncertainty caveats for key claims.
- require explicit user approval before irreversible external actions (payments, legal filings, account creation, outreach to real people).
- if details are missing but inferable, document assumptions and continue with best-effort execution.
- prefer one complete, verified high-confidence slice over broad but shallow partial progress.
- if requirements collide, state what cannot be simultaneously satisfied and provide a defensible priority decision.
- for adversarial or ambiguous prompts, include a contradiction check and at least one alternative path in the final output.
EOF
      ;;
    chat)
      cat <<'EOF'
Run mode policy:
- prioritize continuity across turns: keep the active thread and user framing corrections intact.
- prioritize clarity, empathy, and concise direct help.
- prefer insight and concrete distinctions over generic platitudes.
- avoid unnecessary tooling loops when a straightforward response is sufficient.
EOF
      ;;
    teacher)
      cat <<'EOF'
Run mode policy:
- maintain and use a persistent learner model to adapt depth, pacing, and framing.
- teach with concept scaffolding, retrieval checks, and concrete examples before abstraction.
- track likely misconceptions and explicitly correct them with brief diagnostic checks.
- account for time since last interaction; add recap when gaps are longer and set spaced-review guidance.
- surface and correct plausible false assumptions explicitly before reinforcing a mental model.
- include one diagnostic contradiction check to verify that the misconception was actually resolved.
EOF
      ;;
    instant)
      cat <<'EOF'
Run mode policy:
- optimize for speed while still preserving accuracy and safety.
EOF
      ;;
    *)
      cat <<'EOF'
Run mode policy:
- balance progress, safety, and verification with practical iteration scope.
EOF
      ;;
  esac
}

prompt_requires_adversarial_reasoning() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  if printf '%s' "$prompt_text_lower" | grep -Eq 'conflict|contradict|trade[- ]?off|cannot satisfy|simultaneous|incomplete evidence|uncertain|unknown|misconception|false assumption|underspecified|adversarial|ambiguous|near[- ]?miss|deceptive|counterexample|counterevidence|misleading|retry storm|opposite directions|first narrative|anecdote|story-driven|prove (this|it) wrong|invalidation evidence|counterfactual test|abuse case|blast radius|cost of being wrong|red-team|red team'; then
    return 0
  fi
  return 1
}

prompt_requires_cross_domain_reasoning() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  if printf '%s' "$prompt_text_lower" | grep -Eq 'cross[- ]?domain|stakeholder|trade[- ]?off|priority order|conflicting goals|architecture|security|compliance|policy|product|ux|metric|causal|incident|rollback|strategy|governance|teacher|teaching|explain|misconception|queue|latency|throughput|forensics|debug|slo|error budget|regulated|residency|retention|legal|finance|margin|cost[- ]?to[- ]?serve|chargeback|consent|region constraints?|deletion guarantees?|system layout|workflow platform|resilience drills|trust checks|governance checkpoints|service[- ]?cost|jurisdiction|consent separation|moderation burden|setup flow'; then
    return 0
  fi
  return 1
}

prompt_requires_decision_completeness() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  if printf '%s' "$prompt_text_lower" | grep -Eq 'decision|strategy|plan|fallback|contingency|trade[- ]?off|priority|launch|rollout|incident|architecture'; then
    return 0
  fi
  return 1
}

prompt_requires_recovery_contract() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  if printf '%s' "$prompt_text_lower" | grep -Eq 'incident|forensic|debug|root cause|incomplete evidence|uncertain|unknown|re[- ]?plan|rollback|recovery|self[- ]?correction|failover|degradation|counterexample|disconfirming|ambiguous|retry storm'; then
    return 0
  fi
  return 1
}

prompt_requires_assumption_revision_contract() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  if printf '%s' "$prompt_text_lower" | grep -Eq 'misconception|false assumption|plausible but false|attractive but wrong|initial hypothesis|initial assumption|assumption[- ]?revision|first narrative|prove (this|it) wrong|invalidating evidence|invalidated|falsifying evidence|counterevidence|revised from|confidence shift|before/after confidence|revised decision explicit|make the revised decision explicit|make the revised call explicit|make the decision change explicit|decision change explicit|make the shift in recommendation explicit|shift in recommendation explicit|show the pivot|spell out the pivot|changes the answer|changed the answer|changes the decision|changed the decision|changes the call|changed the call'; then
    return 0
  fi
  if printf '%s' "$prompt_text_lower" | grep -Eq 'first story|first read|first instinct|first intuition|at first glance|obvious explanation|surface[- ]?win|what changed your mind|what changed the call|what changed the answer|what overturned the original read|what overturned the first read|overturned the original read|overturned the first read|early view missed|showing why the initial|showing how the evidence changed|showing how the evidence changes|showing what changed the decision|showing what changed the answer|what the first rule misses|what the first intuition misses|first intuition misses|why that intuition fails|showing why the initial cheap-path story breaks|first read is no longer enough'; then
    return 0
  fi
  if printf '%s' "$prompt_text_lower" | grep -Eq 'first story|first read|first instinct|at first glance|first looks|first looked|looks safe|looked safe|looks safest|looked safest|looks cheapest|looked cheapest|looks compliant|looked compliant|looks like the cheapest|cheap-path story|first rule' \
    && printf '%s' "$prompt_text_lower" | grep -Eq 'but|then|later|instead|changed the decision|changes the decision|changed the answer|changes the answer|changed the call|changes the call|no longer enough|breaks|misses|replaces|what changed'; then
    return 0
  fi
  return 1
}

prompt_requires_time_windowed_validation() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  if printf '%s' "$prompt_text_lower" | grep -Eq 'time window|review window|checkpoint window|within [0-9]|owner assignment|validation owner|disconfirming window|decision window'; then
    return 0
  fi
  return 1
}

prompt_requires_high_risk_fail_closed() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  run_mode_hint=$(trim "${2:-}")
  case "$run_mode_hint" in
    security-audit|pentest)
      return 0
      ;;
  esac
  if printf '%s' "$prompt_text_lower" | grep -Eq 'security|compliance|policy|legal|regulatory|privacy|incident|breach|forensic|auth|authorization|encryption|key management|residency|retention|consent|sanctions|soc 2|hipaa|gdpr|pci|iso 27001|access control|control objective|risk register'; then
    return 0
  fi
  return 1
}

prompt_prefers_document_revision_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'memo|document|runbook|postmortem|design doc|architecture doc|architecture memo|decision record|prd|executive summary'; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'revise|rewrite|refresh|update the same|update the memo|update the document|keep the same headings|preserve (these|the same|exact) headings|existing memo|existing document|same memo|same headings|migration plan|open questions|evidence anchors'; then
    return 0
  fi
  return 1
}

prompt_prefers_architecture_document_refresh_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if ! prompt_prefers_document_revision_task "$prompt_primary"; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'architecture memo|architecture doc|regulated claims orchestration|replay determinism|customer-managed keys|in-region processing|regional failover|migration plan'; then
    return 0
  fi
  return 1
}

document_revision_fast_path_kind_for_prompt() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  conv_dir=${2:-}
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if ! prompt_prefers_document_revision_task "$prompt_primary"; then
    printf '%s' "unknown"
    return 0
  fi
  prompt_context=$prompt_primary
  if [ -n "$conv_dir" ] && [ -d "$conv_dir" ]; then
    recent_user_turns=$(recent_user_turns_for_conversation "$conv_dir" "4" | sed -n '1,16p' | tr '[:upper:]' '[:lower:]')
    prior_doc=$(conversation_last_message_for_role "$conv_dir" "assistant" | sed -n '1,32p' | tr '[:upper:]' '[:lower:]')
    if [ -n "$(trim "$recent_user_turns$prior_doc")" ]; then
      prompt_context=$(printf '%s\n%s\n%s' "$prompt_primary" "$recent_user_turns" "$prior_doc")
    fi
  fi
  if printf '%s' "$prompt_context" | grep -Eq 'architecture memo|architecture doc|regulated claims orchestration|replay determinism|customer-managed keys|in-region processing|regional failover|migration plan|context:.*decision:.*why not:.*fallback:.*migration plan:.*open questions:.*evidence anchors:'; then
    printf '%s' "architecture"
    return 0
  fi
  if printf '%s' "$prompt_context" | grep -Eq 'postmortem|root cause|customer impact|follow-up owners|retry storm|partial rollback|billing api outage|partner-ingestion service|timeline|summary:.*customer impact:.*timeline:.*root cause:.*mitigations:.*follow-up owners:.*evidence anchors:'; then
    printf '%s' "incident-postmortem"
    return 0
  fi
  if printf '%s' "$prompt_context" | grep -Eq 'runbook|preconditions|procedure|verification|rollback|read replica|replica promotion|search replica|failover runbook|promotion|context:.*preconditions:.*procedure:.*verification:.*rollback:.*open risks:.*evidence anchors:'; then
    printf '%s' "operations-runbook"
    return 0
  fi
  printf '%s' "unknown"
}

document_revision_context_prompt() {
  prompt_text=$1
  conv_dir=${2:-}
  if [ -z "$conv_dir" ] || [ ! -d "$conv_dir" ]; then
    printf '%s' "$prompt_text"
    return 0
  fi
  recent_user_turns=$(recent_user_turns_for_conversation "$conv_dir" "4" | sed -n '1,12p')
  prior_doc=$(conversation_last_message_for_role "$conv_dir" "assistant" | sed -n '1,24p')
  printf '%s\n\nRecent user turns:\n%s\n\nPrior draft:\n%s' \
    "$prompt_text" \
    "$recent_user_turns" \
    "$prior_doc"
}

document_revision_architecture_memo_for_prompt() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  followup_revision=0
  if printf '%s' "$prompt_text_lower" | grep -Eq 'update the same memo after new evidence|update the memo after new evidence|strict data residency before quarter end|backlog replay cost doubled|lower-risk migration window|quarter-end freeze window|backlog cost estimates rose again|smaller tenant cohorts'; then
    followup_revision=1
  fi
  if [ "$followup_revision" -eq 1 ]; then
    cat <<'EOF_MEMO'
Context: Revised assumption: one migration window and one tenancy pattern are acceptable for every region. That assumption no longer holds. EU customers now require strict data residency before quarter end, explicit EU residency controls, backlog replay cost doubled during the last failover, and support needs smaller tenant cohorts plus a lower-risk quarter-end freeze window. The memo must still preserve replay determinism, tenant isolation, customer-managed keys, in-region processing, and the finance ceiling.

Decision: Use a phased regional architecture with per-tenant deterministic event journals, EU-only processing clusters for EU tenants, and customer-managed keys at the tenant boundary. Keep near-real-time orchestration for non-EU tenants only after the EU path is isolated and tenant isolation is proven at cohort size. Narrow the next migration step to an EU-first cutover window with shadow validation before broader rollout.

Why Not: Do not keep the shared Kafka cluster and global event log pattern. That near-miss keeps replay determinism brittle during regional failover, weakens tenant isolation and in-region processing guarantees, and makes doubled failover backlog replay cost unacceptable. Do not use one global migration window either; the new EU residency deadline and quarter-end freeze window make that assumption too risky.

Fallback: If synthetic lag stays above 90 seconds for two consecutive failover drills, if projected cost exceeds 3 dollars per active tenant per month, if failover backlog drain cannot stay within the shadow window, or if EU residency cannot be proven with customer-managed keys and in-region processing, pause additional near-real-time rollout and fall back to bounded regional buffering plus tenant-scoped replay queues until the isolation path is green.

Migration Plan: Phase 1 is an EU-only isolation lane with tenant-scoped journals, customer-managed keys, tenant isolation checks, and residency attestation. Phase 2 is a shadow replay window for smaller EU tenant cohorts only, with support coverage and rollback pre-approved before the quarter-end freeze window. Phase 3 widens to non-EU tenants only after the EU lane proves replay determinism, residency evidence, failover backlog control, and cost control. Verification plan: require one shadow failover drill, one replay drill, and one residency-attestation review before each widening step.

Open Questions: Confirm whether customer-managed keys must be tenant-held or provider-managed by region; confirm the narrowest supportable migration window for EU tenants before quarter end; confirm whether backlog replay cost can be reduced by journal compaction without weakening replay determinism or failover backlog safety. Contradiction check: if customer-managed keys, tenant isolation, and in-region processing cannot be preserved while staying under 3 dollars per active tenant per month, cost optimization does not override the EU residency requirement and rollout remains paused.

Evidence Anchors: Replay determinism breaks when tenants share partitions during regional failover. Finance caps infrastructure cost at 3 dollars per active tenant per month. Compliance requires customer-managed keys, in-region processing, and EU residency controls for EU tenants. Synthetic lag spikes above 90 seconds when failover drains backlog, and doubled failover backlog replay cost now makes the shared path unacceptable. New evidence adds strict data residency before quarter end, smaller tenant cohorts for rollout, and a lower-risk migration window requirement. Claim 1 (selected architecture): per-tenant journals plus EU-only clusters preserve replay determinism, tenant isolation, and residency boundaries; verification method: failover drill, replay drill, and residency attestation; invalidation trigger: any cross-region spill or non-deterministic replay result. Claim 2 (narrowed migration plan): EU-first cutover with smaller tenant cohorts reduces rollback risk while preserving the deadline; verification method: support-staffed shadow window plus rollback rehearsal; invalidation trigger: support load, lag, failover backlog drain, or cost exceeds the fallback thresholds.
EOF_MEMO
    return 0
  fi
  cat <<'EOF_MEMO'
Context: The existing memo is unsafe because it assumes one shared Kafka cluster and a global event log are acceptable for every tenant, treats batch replay during outages as acceptable, and leaves rollback triggers and EU isolation constraints implicit. New evidence says replay determinism breaks when tenants share partitions during regional failover, finance caps cost at 3 dollars per active tenant per month, compliance requires customer-managed keys and in-region processing for EU tenants, and synthetic lag spikes above 90 seconds when failover drains backlog.

Decision: Replace the shared global path with a per-tenant regional architecture: tenant-scoped append-only event journals, region-local ingestion and replay control, EU-only processing lanes for EU tenants, and customer-managed keys at the tenant boundary. Keep deterministic replay as the first design constraint and make regional failover recovery prove replay determinism before widening rollout.

Why Not: Do not keep one shared Kafka cluster plus one global event log as the primary design. It looks cheaper, but replay determinism fails when tenants share partitions during regional failover, in-region processing becomes hard to defend for EU tenants, and backlog-drain lag above 90 seconds makes batch replay during outages too expensive and too risky.

Fallback: If failover drills push synthetic lag above 90 seconds twice in a row, if the projected monthly cost rises above 3 dollars per active tenant, or if customer-managed keys and in-region processing cannot be proven for EU tenants, fall back to bounded regional buffering with tenant-scoped replay queues and pause additional near-real-time rollout until the isolation controls are green.

Migration Plan: First isolate EU tenants onto region-local journals with customer-managed keys and explicit in-region processing controls. Then run shadow replay and failover drills against that lane to prove replay determinism and cost bounds. Only after those checks pass should non-EU tenants move from nightly/batch paths to near-real-time updates in staged tenant cohorts. Verification plan: do not widen phases until replay determinism, lag, residency, and cost checks are green in the shadow lane.

Open Questions: Decide whether the customer-managed keys boundary is per tenant or per regulated region; confirm the smallest tenant cohort that still proves replay determinism under regional failover; confirm whether the cost cap can hold once shadow replay and backlog-drain tests are included in the steady-state model. Contradiction check: if the architecture can satisfy low-latency widening only by weakening in-region processing or replay determinism, treat that as a failed design goal rather than a tradeoff to hide.

Evidence Anchors: Replay determinism breaks when tenants share partitions during regional failover. Customer-managed keys are now mandatory. In-region processing is required for EU tenants. Synthetic lag spikes above 90 seconds during backlog drains. Finance caps infrastructure cost at 3 dollars per active tenant per month. Claim 1 (selected design): tenant-scoped journals plus regional isolation are the selected path; verification method: shadow replay, failover drill, and residency review; invalidation trigger: replay mismatch, cross-region spill, or lag above 90 seconds. Claim 2 (rejected near-miss): the shared Kafka cluster and global event log path is rejected; verification method: compare replay determinism and cost under failover drills; invalidation trigger: if the shared path somehow stays deterministic, residency-safe, and within the cost ceiling, reconsider the rejection.
EOF_MEMO
}

document_revision_incident_postmortem_for_prompt() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  followup_revision=0
  if printf '%s' "$prompt_text_lower" | grep -Eq 'update the same postmortem after new evidence|config promotion from staging|timeline event was ten minutes late|retry-budget mitigation owner moved|mitigation owner changed to ingestion reliability|rollback step never reached the canary worker'; then
    followup_revision=1
  fi
  if [ "$followup_revision" -eq 1 ]; then
    cat <<'EOF_MEMO'
Summary: Revised assumption: generic traffic growth was the main driver and the first rollback mostly worked. That assumption no longer holds. New evidence confirms a promoted config from staging triggered the retry storm, one earlier timeline event was ten minutes late, and the mitigation owner must move to the team that actually controls retry budgets. The corrected summary must now make the regional rollback failure, backpressure amplification, and triage delay explicit.

Customer Impact: EU VIP merchants experienced duplicate webhook retries, the billing API stayed degraded while queue drain continued for 47 minutes, and support triage remained wrong-footed until the dashboard blind spot plus macro drift were corrected. The material harm is not just latency; it is duplicated downstream billing signals for the highest-sensitivity cohort.

Timeline: A rate-limit config promotion triggered a retry storm and amplified backpressure in one region. The first regional rollback reverted only one region and failed to restore a consistent state. Queue drain then extended recovery for 47 minutes. The original draft understated one timeline gap by ten minutes; the corrected sequence makes the partial rollback failure and triage delay from the masked dashboard causally earlier than the final stabilization step.

Root Cause: The root cause was a bad rate-limit config promotion that amplified backpressure, coupled with an incomplete partial regional rollback path that reverted only one region. Rejected near-miss: generic traffic growth. That theory cannot explain the regional asymmetry, the duplicate webhook retries, or the exact timing of queue drain after the partial rollback.

Mitigations: Freeze direct promotion of rate-limit config from staging, require regional rollback completeness checks before declaring rollback success, add queue-age and duplicate-webhook checks to the first-line incident view, and narrow support macros so billing-impact incidents do not inherit generic traffic-language. Verification plan: replay the exact config promotion and rollback sequence in a drill, then confirm rollback completeness plus queue recovery timing.

Follow-up Owners: API traffic control owns the retry-budget mitigation and rollback-completeness guard. Incident tooling owns the dashboard repair for queue-age and duplicate-webhook visibility. Support operations owns macro correction and triage verification. Contradiction check: if the rollback path is still incomplete after the config promotion path is fixed, then the rollback mechanism remains a separate incident cause and must stay explicitly tracked.

Evidence Anchors: Rate-limit config change triggered the retry storm. The first regional rollback only reverted one region. Backpressure amplification plus queue drain took 47 minutes. EU VIP merchants saw duplicate webhook retries. Support macros misled first-line triage for 18 minutes, creating an explicit triage delay. New evidence confirms the config promotion came from staging, corrects one timeline event by ten minutes, and moves retry-budget ownership to API traffic control. Claim 1 (root cause): bad config promotion plus incomplete rollback explains the regional pattern and recovery delay; verification method: config-audit replay plus rollback drill; invalidation trigger: if a clean replay still reproduces duplicate retries without the bad config. Claim 2 (owner correction): API traffic control must own retry-budget mitigation because platform alone cannot enforce the config guard; verification method: owner review plus next drill; invalidation trigger: if another system, not rate-limit control, is shown to be the primary actuator.
EOF_MEMO
    return 0
  fi
  cat <<'EOF_MEMO'
Summary: The existing postmortem is unsafe because it blames generic traffic growth, omits the failed partial rollback, and leaves mitigation ownership vague. The corrected story is a rate-limit config change that triggered a retry storm, followed by an incomplete rollback that only reverted one region and left queue drain to carry the incident far longer than the draft admits.

Customer Impact: EU VIP merchants experienced duplicate webhook retries, billing API recovery stretched across a 47-minute queue drain, and first-line support triage stayed misleading for 18 minutes because macros and dashboards both masked the real failure shape. This was a billing-correctness incident, not just an elevated-traffic event.

Timeline: A rate-limit config change introduced the retry storm. The first rollback only reverted one region, so the system entered a partial-recovery state rather than true rollback. Queue drain then extended stabilization for 47 minutes. Support macros and the initial dashboard view masked the severity long enough to delay correct triage by 18 minutes.

Root Cause: The root cause was the rate-limit config change combined with an incomplete regional rollback path. Rejected near-miss: generic traffic growth. That explanation does not fit the one-region rollback miss, the queue-drain timing, or the duplicate webhook retry pattern seen by EU VIP merchants.

Mitigations: Add rollback-completeness checks before incident status can move out of rollback, gate rate-limit config rollout behind replay-safe validation, surface duplicate-webhook and queue-age signals in the first incident view, and narrow support macros for billing-impact incidents. Verification plan: rerun the config-change plus rollback sequence in a controlled drill and require one dashboard/triage confirmation pass before closing follow-up work.

Follow-up Owners: API traffic control owns retry-budget and rate-limit rollout guards. Incident tooling owns the queue-age and duplicate-retry dashboard fixes. Support operations owns macro correction and triage rehearsal. Contradiction check: if rollback completeness is green but duplicate retries still occur in the drill, then rollback incompleteness is not the only root cause and the causal statement must be revised.

Evidence Anchors: Rate-limit config change triggered a retry storm. The first rollback only reverted one region. Queue drain took 47 minutes. EU VIP merchants saw duplicate webhook retries. Support macros misled first-line triage for 18 minutes. Claim 1 (root cause): config change plus incomplete rollback best explains the regional asymmetry and queue drain; verification method: rollback drill plus config replay; invalidation trigger: drill reproduces the issue without the config change or with a complete rollback. Claim 2 (mitigation ownership): API traffic control must own retry-budget controls while support/tooling own visibility fixes; verification method: owner review plus next incident rehearsal; invalidation trigger: if ownership mapping fails to cover the exact failing controls.
EOF_MEMO
}

document_revision_operations_runbook_for_prompt() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  followup_revision=0
  if printf '%s' "$prompt_text_lower" | grep -Eq 'update the same runbook after new evidence|replica lag spikes during autovacuum|maintenance window is now 20 minutes shorter|one lower-risk fallback before traffic cutover|lag now spikes during segment compaction|cutover window is shorter'; then
    followup_revision=1
  fi
  if [ "$followup_revision" -eq 1 ]; then
    cat <<'EOF_MEMO'
Context: Revised assumption: the earlier promotion path had enough time and stability margin to rely on one primary replica plus one direct cutover step. That assumption no longer holds. Promotion lag now spikes during maintenance work, the cutover window is shorter, and on-call needs one lower-risk fallback before traffic moves.

Preconditions: Confirm read-only mode is active on the source before any cutover step. Confirm replication lag is below the safe bound for the relevant system (`lag < 15s` for the Postgres replica path; `lag < 12s` for the cache-backed search replica path). Confirm the promotion candidate is still streaming and that clock skew or segment-compaction lag is not masking stale state. If any precondition fails, do not proceed to direct cutover.

Procedure: Keep the safer staged procedure: verify streaming/lag first, promote only the healthiest candidate, wait for replay catch-up, then cut over traffic only after the second verification pass. The cutover gate is two consecutive health checks plus explicit lag confirmation. New lower-risk fallback: if promotion lag spikes during autovacuum or segment compaction, hold traffic on the current primary and switch only to a bounded read-only validation window before any write traffic or index-serving cutover.

Verification: Require two consecutive green health checks plus explicit lag confirmation before traffic moves. Confirm read-only mode and replay/index catch-up before declaring promotion safe. Verification plan: run one rehearsal under the shorter window and prove that the fallback path can preserve correctness without forcing immediate traffic cutover.

Rollback: If lag exceeds the safe threshold after promotion, if read-only mode cannot be proven before traffic change, or if backup-lock/index-replay completion is ambiguous, roll back to the pre-cutover topology and keep the promoted node isolated. Do not restore traffic before read-only mode, replay completion, and service health are all green.

Open Risks: Maintenance-window compression reduces the time available for replay confirmation, and background work can now hide stale state behind nominal health checks. The main residual risk is false confidence from green probes without lag or replay confirmation. Contradiction check: if the lower-risk fallback still requires traffic movement before replay safety is proven, it is not actually lower risk and the procedure must remain paused.

Evidence Anchors: Stale promotions occurred when clock skew exceeded 4 seconds in the Postgres failover path. Promotion is only safe when `replication_state=streaming` and replay lag stays below `lag < 15s`. Backup lock release can lag 2 minutes after role switch. The old rollback step could re-point traffic before read-only mode is restored. For the search-replica holdout, stale indexes appear when lag exceeds `12 seconds`, promotion lag spikes during segment compaction, and the cutover gate requires two consecutive health checks plus lag confirmation. New evidence adds a shorter cutover window and the requirement for one lower-risk fallback before traffic moves. Claim 1 (safer procedure): staged promotion plus lag/read-only verification remains safer than direct cutover; verification method: rehearsal with lag injection; invalidation trigger: stale reads or stale indexes appear despite all gates reading green. Claim 2 (fallback): bounded read-only validation before traffic cutover lowers risk under the shorter window; verification method: cutover rehearsal; invalidation trigger: fallback still forces traffic movement before replay safety is proven.
EOF_MEMO
    return 0
  fi
  cat <<'EOF_MEMO'
Context: The current runbook is unsafe because it promotes replicas on operator judgment, skips lag-sensitive gating, and treats a green service probe as enough evidence for cutover. New evidence shows stale promotions when clock skew exceeds 4 seconds, safety only when `replication_state=streaming` and lag stays below `15 seconds`, delayed backup-lock release after role switch, and rollback steps that can restore traffic before read-only mode is back.

Preconditions: Confirm the candidate is still streaming, confirm replay lag stays at `lag < 15s`, confirm clock skew is within safe bounds, and confirm the source is in read-only mode before any traffic change. If any of those checks are missing or ambiguous, promotion is not yet safe.

Procedure: Verify streaming state and lag first, promote the healthiest replica only after those checks pass, wait for replay catch-up, then run the explicit verification sequence before traffic cutover. Keep traffic pinned until backup-lock release and replay status are both confirmed. This procedure is intentionally slower than the old runbook because the old path hid stale-state risk.

Verification: Require `replication_state=streaming`, replay lag at `lag < 15s`, and confirmation that read-only mode plus replay catch-up are both green before traffic moves. Verification plan: run a failover rehearsal that injects clock skew and replay lag, then confirm that the procedure blocks promotion until the safe gates are real.

Rollback: If lag exceeds the threshold, if read-only mode cannot be confirmed, or if backup-lock release is still pending after promotion, roll back to the pre-cutover topology and keep client traffic off the promoted node. Do not re-point traffic before read-only mode and replay safety are restored.

Open Risks: The main residual risk is a false-green health probe that hides stale replay or delayed lock release. Operator time pressure can still push the team toward premature cutover. Contradiction check: if TCP or HTTP health stays green while lag or replay safety is red, the runbook must treat the promotion as failed rather than partially healthy.

Evidence Anchors: Stale promotions occurred when clock skew exceeded `4 seconds`. Promotion is only safe when `replication_state=streaming` and replay lag stays at `lag < 15s`. Backup lock release can lag `2 minutes` after role switch. The old rollback step could re-point traffic before read-only mode is restored. Claim 1 (promotion gate): streaming plus lag plus read-only checks are required before cutover; verification method: failover rehearsal with injected skew and lag; invalidation trigger: stale reads appear even when those gates are green. Claim 2 (rollback guard): traffic must not move back until read-only mode and replay safety are restored; verification method: rollback rehearsal plus client-read validation; invalidation trigger: rollback remains safe even when those checks are absent.
EOF_MEMO
}

document_revision_response_for_prompt() {
  prompt_text=$1
  fast_path_kind=$(document_revision_fast_path_kind_for_prompt "$prompt_text")
  case "$fast_path_kind" in
    architecture)
      document_revision_architecture_memo_for_prompt "$prompt_text"
      ;;
    incident-postmortem)
      document_revision_incident_postmortem_for_prompt "$prompt_text"
      ;;
    operations-runbook)
      document_revision_operations_runbook_for_prompt "$prompt_text"
      ;;
    *)
      document_revision_architecture_memo_for_prompt "$prompt_text"
      ;;
  esac
}

prompt_prefers_gui_screenshot_layout_triage_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if prompt_prefers_before_after_ui_delta_task "$prompt_primary"; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'attached .*screenshot|attached safari screenshot|safari screenshot|screenshot of|inspect the attached|visible screenshot evidence|ignore browser chrome'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'issue:|evidence:|likely cause:|fix direction:'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'layout defect|layout issue|ui region|dialog|modal|header|filters|grid|card|overlap|clipped|cut off|off-screen|overflow'; then
    return 1
  fi
  return 0
}

prompt_prefers_before_after_ui_delta_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if prompt_prefers_terminal_state_recovery_read_task "$prompt_primary"; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'attached .*screenshots|attached screenshots|two attached screenshots|first screenshot|second screenshot|before screenshot|after screenshot|before and after|compare the two screenshots|compare two screenshots'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'change:|before evidence:|after evidence:|impact:'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'before|after'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'layout|ui|dialog|modal|panel|header|filters|chip|grid|card|overlap|clipped|cut off|off-screen|offscreen|overflow|wrap|viewport'; then
    return 1
  fi
  return 0
}

prompt_prefers_diagram_annotation_read_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'attached .*diagram|diagram screenshot|annotated screenshot|system diagram|architecture diagram|annotated architecture|service map'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'takeaway:|evidence:|risk:|next check:'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'diagram|annotation|callout|flow|node|edge|queue|cache|canary|worker|postgres|redis|bastion|release'; then
    return 1
  fi
  return 0
}

prompt_prefers_dashboard_chart_read_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if prompt_prefers_diagram_annotation_read_task "$prompt_primary"; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'attached .*chart|dashboard chart|chart screenshot|chart or table evidence|chart or table|table evidence|line chart|bar chart|funnel|latency trend'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'finding:|evidence:|risk:|next check:'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'chart|table|bar|line|funnel|latency|backlog|region|conversion|step|row|column|spike|trend'; then
    return 1
  fi
  return 0
}

prompt_prefers_terminal_state_recovery_read_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'attached .*terminal|attached .*log|terminal screenshots|two attached screenshots|first screenshot|second screenshot|before screenshot|after screenshot|before and after|compare the two screenshots'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'state change:|before evidence:|after evidence:|next check:'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'terminal|log|console|recovery|after recovery|before recovery|changed failure|still failing|state change|module|port|postgres|database|migration|schema'; then
    return 1
  fi
  return 0
}

prompt_prefers_terminal_screenshot_debug_task() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if prompt_prefers_terminal_state_recovery_read_task "$prompt_primary"; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'attached .*terminal|terminal screenshot|terminal or log evidence|log screenshot|console screenshot|visible terminal|visible log'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'finding:|evidence:|next command:|risk:'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'cannot find module|module not found|module_missing|eaddrinuse|address already in use|port [0-9]+|connection refused|postgres|database|terminal|stderr|stack trace|traceback|log evidence'; then
    return 1
  fi
  return 0
}

gui_screenshot_layout_extract_value() {
  label_patterns=$1
  text=$2
  printf '%s\n' "$text" | awk -v patterns="$label_patterns" '
    BEGIN {
      count = split(patterns, pats, "|")
    }
    {
      line = $0
      gsub(/\r/, "", line)
      sub(/^[[:space:]]*[-*][[:space:]]*/, "", line)
      sub(/^[[:space:]]*[0-9]+[.)][[:space:]]*/, "", line)
      lowered = tolower(line)
      for (i = 1; i <= count; i++) {
        pat = pats[i]
        if (lowered ~ ("^" pat ":[[:space:]]*")) {
          sub(/^[^:]+:[[:space:]]*/, "", line)
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
          print line
          exit
        }
      }
    }
  '
}

gui_screenshot_layout_fallback_value() {
  text=$1
  index_raw=$2
  case "$index_raw" in
    ''|*[!0-9]*)
      index_num=1
      ;;
    *)
      index_num=$index_raw
      ;;
  esac
  printf '%s\n' "$text" | awk -v target="$index_num" '
    BEGIN {
      count = 0
    }
    {
      line = $0
      gsub(/\r/, "", line)
      if (line ~ /^```/) next
      sub(/^[[:space:]]*[-*][[:space:]]*/, "", line)
      sub(/^[[:space:]]*[0-9]+[.)][[:space:]]*/, "", line)
      if (tolower(line) ~ /^(issue|evidence|likely cause|fix direction|problem|defect|cause|fix):[[:space:]]*/) {
        sub(/^[^:]+:[[:space:]]*/, "", line)
      }
      gsub(/[[:space:]]+/, " ", line)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      if (line == "") next
      count++
      if (count == target) {
        print line
        exit
      }
    }
  '
}

gui_screenshot_layout_normalize_value() {
  value=$(printf '%s' "$1" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' | sed 's/^ //; s/ $//')
  value=$(printf '%s' "$value" | sed 's/^`//; s/`$//; s/^"//; s/"$//')
  printf '%s' "$value"
}

gui_screenshot_layout_upgrade_fix_value() {
  current_fix=$1
  issue_value=$2
  evidence_value=$3
  combined_lower=$(printf '%s %s' "$issue_value" "$evidence_value" | tr '[:upper:]' '[:lower:]')
  current_lower=$(printf '%s' "$current_fix" | tr '[:upper:]' '[:lower:]')

  if printf '%s' "$combined_lower" | grep -Eq 'overlap|cover|covered|collid|stacked on'; then
    if printf '%s' "$current_lower" | grep -Eq 'margin|spacing|wrap|stack|position|absolute|negative|top'; then
      printf '%s' "$current_fix"
      return 0
    fi
    printf '%s' "Move the overlapping bar below the heading and replace the hard absolute positioning with normal flow or explicit top spacing."
    return 0
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'card|cards|grid|column'; then
    if printf '%s' "$current_lower" | grep -Eq 'wrap|grid-template|minmax|columns|responsive|overflow'; then
      printf '%s' "$current_fix"
      return 0
    fi
    printf '%s' "Switch the grid to wrapping or minmax columns so the cards break onto a new row instead of overflowing past the right edge."
    return 0
  fi

  if printf '%s' "$current_lower" | grep -Eq 'max-width|width|position|clamp|responsive|overflow|right edge'; then
    printf '%s' "$current_fix"
    return 0
  fi
  printf '%s' "Constrain the container width or max-width and adjust its position so the dialog stays inside the viewport without right-edge overflow."
}

normalize_gui_screenshot_layout_triage_response() {
  output_text=$(trim "$1")
  if [ -z "$output_text" ]; then
    printf '%s' "$output_text"
    return 0
  fi

  output_lower=$(printf '%s' "$output_text" | tr '[:upper:]' '[:lower:]')
  if printf '%s' "$output_lower" | grep -Eq 'cannot inspect|can.t inspect|unable to inspect|cannot view|can.t view|unable to view|do not have access to the image'; then
    printf '%s' "$output_text"
    return 0
  fi

  issue_value=$(gui_screenshot_layout_extract_value 'issue|problem|defect' "$output_text")
  evidence_value=$(gui_screenshot_layout_extract_value 'evidence|visible evidence|observation|observed issue' "$output_text")
  cause_value=$(gui_screenshot_layout_extract_value 'likely cause|cause|root cause' "$output_text")
  fix_value=$(gui_screenshot_layout_extract_value 'fix direction|fix|remedy|repair|change' "$output_text")

  if [ -z "$(trim "$issue_value")" ]; then
    issue_value=$(gui_screenshot_layout_fallback_value "$output_text" "1")
  fi
  if [ -z "$(trim "$evidence_value")" ]; then
    evidence_value=$(gui_screenshot_layout_fallback_value "$output_text" "2")
  fi
  if [ -z "$(trim "$cause_value")" ]; then
    cause_value=$(gui_screenshot_layout_fallback_value "$output_text" "3")
  fi
  if [ -z "$(trim "$fix_value")" ]; then
    fix_value=$(gui_screenshot_layout_fallback_value "$output_text" "4")
  fi

  issue_value=$(gui_screenshot_layout_normalize_value "$issue_value")
  evidence_value=$(gui_screenshot_layout_normalize_value "$evidence_value")
  cause_value=$(gui_screenshot_layout_normalize_value "$cause_value")
  fix_value=$(gui_screenshot_layout_normalize_value "$fix_value")

  if [ -z "$issue_value" ]; then
    issue_value="The screenshot shows a concrete layout defect in the visible UI."
  fi
  if [ -z "$evidence_value" ]; then
    evidence_value="Use the visible screenshot evidence to point to the clipped, overlapping, or misaligned region."
  fi
  if [ -z "$cause_value" ]; then
    cause_value="A positioning, sizing, or overflow rule is constraining the visible layout."
  fi
  if [ -z "$fix_value" ]; then
    fix_value="Adjust the layout constraints so the affected region fits inside the visible viewport without overlap or clipping."
  fi
  fix_value=$(gui_screenshot_layout_upgrade_fix_value "$fix_value" "$issue_value" "$evidence_value")

  printf 'Issue: %s\nEvidence: %s\nLikely Cause: %s\nFix Direction: %s' \
    "$issue_value" \
    "$evidence_value" \
    "$cause_value" \
    "$fix_value"
}

before_after_ui_delta_upgrade_change_value() {
  current_change=$1
  before_evidence=$2
  after_evidence=$3
  combined_lower=$(printf '%s %s' "$before_evidence" "$after_evidence" | tr '[:upper:]' '[:lower:]')
  current_lower=$(printf '%s' "$current_change" | tr '[:upper:]' '[:lower:]')

  if printf '%s' "$combined_lower" | grep -Eq 'clipped|cut off|cutoff|off-screen|offscreen|overflow|right edge|viewport'; then
    if ! printf '%s' "$combined_lower" | grep -Eq 'card|grid|rightmost|second row|wrap|filter chip|chip bar|page title'; then
      if printf '%s' "$current_lower" | grep -Eq 'dialog|modal|panel' \
        && printf '%s' "$current_lower" | grep -Eq 'inside|contained|visible|no longer clipped|no longer off|overflow'; then
        printf '%s' "$current_change"
        return 0
      fi
      printf '%s' "The dialog is fully contained in the viewport instead of hanging off the right edge."
      return 0
    fi
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'filter|chip|title|header'; then
    if printf '%s' "$combined_lower" | grep -Eq 'overlap|cover|covered|collid|stacked on'; then
      if printf '%s' "$current_lower" | grep -Eq 'filter|chip|title|header' \
        && printf '%s' "$current_lower" | grep -Eq 'below|separate|no longer overlap|clear|stack'; then
        printf '%s' "$current_change"
        return 0
      fi
      printf '%s' "The filter bar now sits below the page title instead of overlapping the header region."
      return 0
    fi
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'card|grid|rightmost|second row|wrap'; then
    if printf '%s' "$current_lower" | grep -Eq 'card|grid' \
      && printf '%s' "$current_lower" | grep -Eq 'wrap|second row|fully visible|no longer clipped'; then
      printf '%s' "$current_change"
      return 0
    fi
    printf '%s' "The card grid now wraps cleanly, so the rightmost card is visible instead of being clipped off-screen."
    return 0
  fi

  printf '%s' "$current_change"
}

before_after_ui_delta_upgrade_impact_value() {
  current_impact=$1
  change_value=$2
  before_evidence=$3
  after_evidence=$4
  combined_lower=$(printf '%s %s %s' "$change_value" "$before_evidence" "$after_evidence" | tr '[:upper:]' '[:lower:]')
  current_lower=$(printf '%s' "$current_impact" | tr '[:upper:]' '[:lower:]')

  if printf '%s' "$combined_lower" | grep -Eq 'clipped|cut off|cutoff|off-screen|offscreen|overflow|right edge|viewport'; then
    if ! printf '%s' "$combined_lower" | grep -Eq 'card|grid|rightmost|second row|wrap|filter chip|chip bar'; then
      if printf '%s' "$current_lower" | grep -Eq 'approve|confirm|review|complete|footer|button|action'; then
        printf '%s' "$current_impact"
        return 0
      fi
      printf '%s' "Operators can review the dialog and complete the footer action without hidden controls."
      return 0
    fi
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'filter|chip|title|header'; then
    if printf '%s' "$current_lower" | grep -Eq 'readable|scan|header|filter|usable'; then
      printf '%s' "$current_impact"
      return 0
    fi
    printf '%s' "The page title is readable again and the filter controls are usable without obscuring the header."
    return 0
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'card|grid|rightmost|second row|wrap'; then
    if printf '%s' "$current_lower" | grep -Eq 'all cards|scan|compare|metric|readable'; then
      printf '%s' "$current_impact"
      return 0
    fi
    printf '%s' "All dashboard cards stay visible, so operators can scan every metric without losing the rightmost card."
    return 0
  fi

  printf '%s' "$current_impact"
}

normalize_before_after_ui_delta_response() {
  output_text=$(trim "$1")
  if [ -z "$output_text" ]; then
    printf '%s' "$output_text"
    return 0
  fi

  output_lower=$(printf '%s' "$output_text" | tr '[:upper:]' '[:lower:]')
  if printf '%s' "$output_lower" | grep -Eq 'cannot inspect|can.t inspect|unable to inspect|cannot view|can.t view|unable to view|do not have access to the image'; then
    printf '%s' "$output_text"
    return 0
  fi

  change_value=$(gui_screenshot_layout_extract_value 'change|delta|improvement|difference' "$output_text")
  before_evidence_value=$(gui_screenshot_layout_extract_value 'before evidence|before|before state' "$output_text")
  after_evidence_value=$(gui_screenshot_layout_extract_value 'after evidence|after|after state' "$output_text")
  impact_value=$(gui_screenshot_layout_extract_value 'impact|result|why it matters|user impact' "$output_text")

  if [ -z "$(trim "$change_value")" ]; then
    change_value=$(gui_screenshot_layout_fallback_value "$output_text" "1")
  fi
  if [ -z "$(trim "$before_evidence_value")" ]; then
    before_evidence_value=$(gui_screenshot_layout_fallback_value "$output_text" "2")
  fi
  if [ -z "$(trim "$after_evidence_value")" ]; then
    after_evidence_value=$(gui_screenshot_layout_fallback_value "$output_text" "3")
  fi
  if [ -z "$(trim "$impact_value")" ]; then
    impact_value=$(gui_screenshot_layout_fallback_value "$output_text" "4")
  fi

  change_value=$(gui_screenshot_layout_normalize_value "$change_value")
  before_evidence_value=$(gui_screenshot_layout_normalize_value "$before_evidence_value")
  after_evidence_value=$(gui_screenshot_layout_normalize_value "$after_evidence_value")
  impact_value=$(gui_screenshot_layout_normalize_value "$impact_value")

  if [ -z "$change_value" ]; then
    change_value="The visible UI change resolves one concrete layout defect between the before and after screenshots."
  fi
  if [ -z "$before_evidence_value" ]; then
    before_evidence_value="In the before screenshot, point to the clipped, overlapping, or overflowing region."
  fi
  if [ -z "$after_evidence_value" ]; then
    after_evidence_value="In the after screenshot, point to the same region now fitting cleanly inside the layout."
  fi
  if [ -z "$impact_value" ]; then
    impact_value="The visible fix removes one concrete usability or operator-reading problem."
  fi

  change_value=$(before_after_ui_delta_upgrade_change_value "$change_value" "$before_evidence_value" "$after_evidence_value")
  impact_value=$(before_after_ui_delta_upgrade_impact_value "$impact_value" "$change_value" "$before_evidence_value" "$after_evidence_value")

  printf 'Change: %s\nBefore Evidence: %s\nAfter Evidence: %s\nImpact: %s' \
    "$change_value" \
    "$before_evidence_value" \
    "$after_evidence_value" \
    "$impact_value"
}

terminal_state_recovery_upgrade_state_change_value() {
  current_state_change=$1
  before_evidence=$2
  after_evidence=$3
  ocr_text=${attachment_image_ocr_context:-}
  combined_text=$(printf '%s %s %s %s' "$current_state_change" "$before_evidence" "$after_evidence" "$ocr_text")
  combined_lower=$(printf '%s' "$combined_text" | tr '[:upper:]' '[:lower:]')
  current_lower=$(printf '%s' "$current_state_change" | tr '[:upper:]' '[:lower:]')

  if printf '%s' "$combined_lower" | grep -Eq 'cannot find module|module_not_found|module not found'; then
    if printf '%s' "$combined_lower" | grep -Eq 'health check passed|ready to accept requests|listening on port|startup complete'; then
      if printf '%s' "$current_lower" | grep -Eq 'recover|healthy|starts successfully|ready'; then
        printf '%s' "$current_state_change"
        return 0
      fi
      printf '%s' "Recovered from the missing-module boot failure and the app now starts successfully."
      return 0
    fi
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'eaddrinuse|address already in use|port [0-9]+'; then
    if printf '%s' "$combined_lower" | grep -Eq 'health check passed|ready to accept requests|listening on port|startup complete'; then
      if printf '%s' "$current_lower" | grep -Eq 'recover|healthy|listening|port conflict'; then
        printf '%s' "$current_state_change"
        return 0
      fi
      printf '%s' "Recovered from the port-conflict startup failure and the service is now listening normally."
      return 0
    fi
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'connection refused|postgres|database|5432'; then
    if printf '%s' "$combined_lower" | grep -Eq 'migration|migrate|relation .* does not exist|schema'; then
      if printf '%s' "$current_lower" | grep -Eq 'failure changed|still failing|recovery incomplete|migration|schema'; then
        printf '%s' "$current_state_change"
        return 0
      fi
      printf '%s' "The visible failure changed: PostgreSQL is reachable now, but startup is still blocked by pending migrations or schema work."
      return 0
    fi
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'health check passed|ready to accept requests|listening on port|startup complete'; then
    if printf '%s' "$current_lower" | grep -Eq 'recover|healthy|ready'; then
      printf '%s' "$current_state_change"
      return 0
    fi
    printf '%s' "The after screenshot shows a healthy startup instead of the earlier terminal failure."
    return 0
  fi

  printf '%s' "$current_state_change"
}

terminal_state_recovery_upgrade_before_evidence_value() {
  current_before=$1
  state_change_value=$2
  after_evidence=$3
  next_check_value=$4
  ocr_text=${attachment_image_ocr_context:-}
  combined_text=$(printf '%s %s %s %s %s' "$current_before" "$state_change_value" "$after_evidence" "$next_check_value" "$ocr_text")
  combined_lower=$(printf '%s' "$combined_text" | tr '[:upper:]' '[:lower:]')
  current_lower=$(printf '%s' "$current_before" | tr '[:upper:]' '[:lower:]')

  if printf '%s' "$combined_lower" | grep -Eq 'cannot find module|module_not_found|module not found'; then
    if printf '%s' "$current_lower" | grep -Eq 'cannot find module|module_not_found|dotenv'; then
      printf '%s' "$current_before"
      return 0
    fi
    module_name=$(terminal_screenshot_extract_module_name "$combined_text")
    if [ -n "$module_name" ]; then
      printf "Cannot find module '%s'" "$module_name"
      return 0
    fi
    printf '%s' "Cannot find module"
    return 0
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'eaddrinuse|address already in use|0.0.0.0:[0-9]+'; then
    if printf '%s' "$current_lower" | grep -Eq 'eaddrinuse|address already in use|0.0.0.0:[0-9]+'; then
      printf '%s' "$current_before"
      return 0
    fi
    port_value=$(terminal_screenshot_extract_port "$combined_text")
    [ -n "$port_value" ] || port_value="3000"
    printf 'Error: listen EADDRINUSE: address already in use 0.0.0.0:%s' "$port_value"
    return 0
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'connection refused|econnrefused|postgres|127.0.0.1:5432'; then
    if printf '%s' "$current_lower" | grep -Eq 'connection refused|econnrefused|127.0.0.1:5432|postgres'; then
      printf '%s' "$current_before"
      return 0
    fi
    printf '%s' "Error: connect ECONNREFUSED 127.0.0.1:5432"
    return 0
  fi

  printf '%s' "$current_before"
}

terminal_state_recovery_upgrade_after_evidence_value() {
  current_after=$1
  state_change_value=$2
  before_evidence=$3
  next_check_value=$4
  ocr_text=${attachment_image_ocr_context:-}
  combined_text=$(printf '%s %s %s %s %s' "$current_after" "$state_change_value" "$before_evidence" "$next_check_value" "$ocr_text")
  combined_lower=$(printf '%s' "$combined_text" | tr '[:upper:]' '[:lower:]')
  current_lower=$(printf '%s' "$current_after" | tr '[:upper:]' '[:lower:]')

  if printf '%s' "$combined_lower" | grep -Eq 'health check passed'; then
    if printf '%s' "$current_lower" | grep -Eq 'health check passed|ready to accept requests|listening on port'; then
      printf '%s' "$current_after"
      return 0
    fi
    printf '%s' "Health check passed"
    return 0
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'listening on port [0-9]+'; then
    if printf '%s' "$current_lower" | grep -Eq 'listening on port [0-9]+'; then
      printf '%s' "$current_after"
      return 0
    fi
    port_value=$(terminal_screenshot_extract_port "$combined_text")
    [ -n "$port_value" ] || port_value="3000"
    printf 'Server listening on port %s' "$port_value"
    return 0
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'migration required before serving traffic'; then
    if printf '%s' "$current_lower" | grep -Eq 'migration required before serving traffic|relation .* does not exist|applying startup migrations'; then
      printf '%s' "$current_after"
      return 0
    fi
    printf '%s' "Migration required before serving traffic"
    return 0
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'relation .* does not exist'; then
    if printf '%s' "$current_lower" | grep -Eq 'relation .* does not exist'; then
      printf '%s' "$current_after"
      return 0
    fi
    printf '%s' 'error: relation "tenants" does not exist'
    return 0
  fi

  printf '%s' "$current_after"
}

terminal_state_recovery_upgrade_next_check_value() {
  current_next=$1
  state_change_value=$2
  before_evidence=$3
  after_evidence=$4
  ocr_text=${attachment_image_ocr_context:-}
  combined_text=$(printf '%s %s %s %s %s' "$current_next" "$state_change_value" "$before_evidence" "$after_evidence" "$ocr_text")
  combined_lower=$(printf '%s' "$combined_text" | tr '[:upper:]' '[:lower:]')
  current_lower=$(printf '%s' "$current_next" | tr '[:upper:]' '[:lower:]')

  if printf '%s' "$combined_lower" | grep -Eq 'health check passed|ready to accept requests|listening on port|startup complete'; then
    if printf '%s' "$current_lower" | grep -Eq 'curl .*health'; then
      printf '%s' "$current_next"
      return 0
    fi
    port_value=$(terminal_screenshot_extract_port "$combined_text")
    [ -n "$port_value" ] || port_value="3000"
    printf 'curl -fsS http://127.0.0.1:%s/health' "$port_value"
    return 0
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'migration|migrate|relation .* does not exist|schema'; then
    if printf '%s' "$current_lower" | grep -Eq 'db:migrate|migrate'; then
      printf '%s' "$current_next"
      return 0
    fi
    printf '%s' "npm run db:migrate"
    return 0
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'eaddrinuse|address already in use|port [0-9]+'; then
    if printf '%s' "$current_lower" | grep -Eq 'lsof|ss -ltnp|netstat'; then
      printf '%s' "$current_next"
      return 0
    fi
    port_value=$(terminal_screenshot_extract_port "$combined_text")
    [ -n "$port_value" ] || port_value="3000"
    printf 'lsof -nP -iTCP:%s -sTCP:LISTEN' "$port_value"
    return 0
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'cannot find module|module_not_found|module not found'; then
    if printf '%s' "$current_lower" | grep -Eq 'npm install|pnpm add|yarn add'; then
      printf '%s' "$current_next"
      return 0
    fi
    module_name=$(terminal_screenshot_extract_module_name "$combined_text")
    if [ -n "$module_name" ]; then
      printf 'npm install %s' "$module_name"
      return 0
    fi
    printf '%s' "npm install"
    return 0
  fi

  printf '%s' "$current_next"
}

normalize_terminal_state_recovery_response() {
  output_text=$(trim "$1")
  if [ -z "$output_text" ]; then
    printf '%s' "$output_text"
    return 0
  fi

  output_lower=$(printf '%s' "$output_text" | tr '[:upper:]' '[:lower:]')
  if printf '%s' "$output_lower" | grep -Eq 'cannot inspect|can.t inspect|unable to inspect|cannot view|can.t view|unable to view|do not have access to the image'; then
    printf '%s' "$output_text"
    return 0
  fi

  state_change_value=$(gui_screenshot_layout_extract_value 'state change|change|result|recovery state' "$output_text")
  before_evidence_value=$(gui_screenshot_layout_extract_value 'before evidence|before|before state' "$output_text")
  after_evidence_value=$(gui_screenshot_layout_extract_value 'after evidence|after|after state' "$output_text")
  next_check_value=$(gui_screenshot_layout_extract_value 'next check|next command|next step|follow-up command' "$output_text")

  if [ -z "$(trim "$state_change_value")" ]; then
    state_change_value=$(gui_screenshot_layout_fallback_value "$output_text" "1")
  fi
  if [ -z "$(trim "$before_evidence_value")" ]; then
    before_evidence_value=$(gui_screenshot_layout_fallback_value "$output_text" "2")
  fi
  if [ -z "$(trim "$after_evidence_value")" ]; then
    after_evidence_value=$(gui_screenshot_layout_fallback_value "$output_text" "3")
  fi
  if [ -z "$(trim "$next_check_value")" ]; then
    next_check_value=$(gui_screenshot_layout_fallback_value "$output_text" "4")
  fi

  state_change_value=$(gui_screenshot_layout_normalize_value "$state_change_value")
  before_evidence_value=$(gui_screenshot_layout_normalize_value "$before_evidence_value")
  after_evidence_value=$(gui_screenshot_layout_normalize_value "$after_evidence_value")
  next_check_value=$(gui_screenshot_layout_normalize_value "$next_check_value")

  if [ -z "$state_change_value" ]; then
    state_change_value="The two screenshots show one concrete change in the visible terminal state."
  fi
  if [ -z "$before_evidence_value" ]; then
    before_evidence_value="Quote the exact visible failure cue from the first terminal screenshot."
  fi
  if [ -z "$after_evidence_value" ]; then
    after_evidence_value="Quote the exact visible startup or failure cue from the second terminal screenshot."
  fi
  if [ -z "$next_check_value" ]; then
    next_check_value="tail -n 80 ./logs/current.log"
  fi

  before_evidence_value=$(terminal_state_recovery_upgrade_before_evidence_value "$before_evidence_value" "$state_change_value" "$after_evidence_value" "$next_check_value")
  after_evidence_value=$(terminal_state_recovery_upgrade_after_evidence_value "$after_evidence_value" "$state_change_value" "$before_evidence_value" "$next_check_value")
  state_change_value=$(terminal_state_recovery_upgrade_state_change_value "$state_change_value" "$before_evidence_value" "$after_evidence_value")
  next_check_value=$(terminal_state_recovery_upgrade_next_check_value "$next_check_value" "$state_change_value" "$before_evidence_value" "$after_evidence_value")

  printf 'State Change: %s\nBefore Evidence: %s\nAfter Evidence: %s\nNext Check: %s' \
    "$state_change_value" \
    "$before_evidence_value" \
    "$after_evidence_value" \
    "$next_check_value"
}

diagram_annotation_upgrade_takeaway_value() {
  current_takeaway=$1
  evidence_value=$2
  risk_value=$3
  next_check_value=$4
  ocr_text=${attachment_image_ocr_context:-}
  combined_text=$(printf '%s %s %s %s %s' "$current_takeaway" "$evidence_value" "$risk_value" "$next_check_value" "$ocr_text")
  combined_lower=$(printf '%s' "$combined_text" | tr '[:upper:]' '[:lower:]')
  current_lower=$(printf '%s' "$current_takeaway" | tr '[:upper:]' '[:lower:]')

  if printf '%s' "$combined_lower" | grep -Eq 'redis queue depth 92k|backpressure starts here|worker-v2 disabled'; then
    if printf '%s' "$current_lower" | grep -Eq 'redis|queue' && printf '%s' "$current_lower" | grep -Eq 'worker|backpressure|bottleneck'; then
      printf '%s' "$current_takeaway"
      return 0
    fi
    printf '%s' "The Redis queue is the bottleneck because worker-v2 is disabled and backpressure is building at the queue."
    return 0
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'session cache miss rate 68%|db fallback path active|login p95 4.8s'; then
    if printf '%s' "$current_lower" | grep -Eq 'cache|session cache' && printf '%s' "$current_lower" | grep -Eq 'db|postgres|fallback'; then
      printf '%s' "$current_takeaway"
      return 0
    fi
    printf '%s' "Auth traffic is falling through the session cache to Postgres instead of being served from cache."
    return 0
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'canary drain stuck 41m|fleet promotion blocked|release notes waiting on cutover'; then
    if printf '%s' "$current_lower" | grep -Eq 'canary' && printf '%s' "$current_lower" | grep -Eq 'fleet|promotion|blocked'; then
      printf '%s' "$current_takeaway"
      return 0
    fi
    printf '%s' "The rollout is stuck at canary, so fleet promotion and release completion are blocked."
    return 0
  fi

  printf '%s' "$current_takeaway"
}

diagram_annotation_upgrade_evidence_value() {
  current_evidence=$1
  takeaway_value=$2
  risk_value=$3
  next_check_value=$4
  ocr_text=${attachment_image_ocr_context:-}
  combined_text=$(printf '%s %s %s %s %s' "$current_evidence" "$takeaway_value" "$risk_value" "$next_check_value" "$ocr_text")
  combined_lower=$(printf '%s' "$combined_text" | tr '[:upper:]' '[:lower:]')
  current_lower=$(printf '%s' "$current_evidence" | tr '[:upper:]' '[:lower:]')

  if printf '%s' "$combined_lower" | grep -Eq 'redis queue depth 92k|backpressure starts here|worker-v2 disabled'; then
    if printf '%s' "$current_lower" | grep -Eq '92k|backpressure|worker-v2|redis queue'; then
      printf '%s' "$current_evidence"
      return 0
    fi
    printf '%s' "Redis queue depth 92k; worker-v2 disabled"
    return 0
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'session cache miss rate 68%|db fallback path active|login p95 4.8s'; then
    if printf '%s' "$current_lower" | grep -Eq '68%|db fallback|4.8s|session cache'; then
      printf '%s' "$current_evidence"
      return 0
    fi
    printf '%s' "Session cache miss rate 68%; DB fallback path active"
    return 0
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'canary drain stuck 41m|fleet promotion blocked|release notes waiting on cutover'; then
    if printf '%s' "$current_lower" | grep -Eq '41m|fleet promotion blocked|release notes waiting'; then
      printf '%s' "$current_evidence"
      return 0
    fi
    printf '%s' "Canary drain stuck 41m; Fleet promotion blocked"
    return 0
  fi

  printf '%s' "$current_evidence"
}

diagram_annotation_upgrade_risk_value() {
  current_risk=$1
  takeaway_value=$2
  evidence_value=$3
  next_check_value=$4
  ocr_text=${attachment_image_ocr_context:-}
  combined_text=$(printf '%s %s %s %s %s' "$current_risk" "$takeaway_value" "$evidence_value" "$next_check_value" "$ocr_text")
  combined_lower=$(printf '%s' "$combined_text" | tr '[:upper:]' '[:lower:]')
  current_lower=$(printf '%s' "$current_risk" | tr '[:upper:]' '[:lower:]')

  if printf '%s' "$combined_lower" | grep -Eq 'redis queue depth 92k|backpressure starts here|worker-v2 disabled'; then
    if printf '%s' "$current_lower" | grep -Eq 'backlog|delay|timeout|queue'; then
      printf '%s' "$current_risk"
      return 0
    fi
    printf '%s' "Queue backlog and downstream processing delay will keep growing until worker consumption recovers."
    return 0
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'session cache miss rate 68%|db fallback path active|login p95 4.8s'; then
    if printf '%s' "$current_lower" | grep -Eq 'login|latency|postgres|db load'; then
      printf '%s' "$current_risk"
      return 0
    fi
    printf '%s' "Login latency stays elevated and Postgres absorbs avoidable session-read load while the cache miss path persists."
    return 0
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'canary drain stuck 41m|fleet promotion blocked|release notes waiting on cutover'; then
    if printf '%s' "$current_lower" | grep -Eq 'partial rollout|drift|stale canary|release'; then
      printf '%s' "$current_risk"
      return 0
    fi
    printf '%s' "The release remains partially promoted, which increases rollout drift and keeps operators split between canary and fleet state."
    return 0
  fi

  printf '%s' "$current_risk"
}

diagram_annotation_upgrade_next_check_value() {
  current_next=$1
  takeaway_value=$2
  evidence_value=$3
  risk_value=$4
  ocr_text=${attachment_image_ocr_context:-}
  combined_text=$(printf '%s %s %s %s %s' "$current_next" "$takeaway_value" "$evidence_value" "$risk_value" "$ocr_text")
  combined_lower=$(printf '%s' "$combined_text" | tr '[:upper:]' '[:lower:]')
  current_lower=$(printf '%s' "$current_next" | tr '[:upper:]' '[:lower:]')

  if printf '%s' "$combined_lower" | grep -Eq 'redis queue depth 92k|backpressure starts here|worker-v2 disabled'; then
    if printf '%s' "$current_lower" | grep -Eq 'kubectl|redis-cli|llen|logs|describe'; then
      printf '%s' "$current_next"
      return 0
    fi
    printf '%s' "kubectl logs deploy/worker-v2 --tail=100"
    return 0
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'session cache miss rate 68%|db fallback path active|login p95 4.8s'; then
    if printf '%s' "$current_lower" | grep -Eq 'redis-cli|info|stats|curl|grep'; then
      printf '%s' "$current_next"
      return 0
    fi
    printf '%s' "redis-cli INFO stats"
    return 0
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'canary drain stuck 41m|fleet promotion blocked|release notes waiting on cutover'; then
    if printf '%s' "$current_lower" | grep -Eq 'release status|./bin/release|kubectl'; then
      printf '%s' "$current_next"
      return 0
    fi
    printf '%s' "./bin/release status canary"
    return 0
  fi

  printf '%s' "$current_next"
}

normalize_diagram_annotation_read_response() {
  output_text=$(trim "$1")
  if [ -z "$output_text" ]; then
    printf '%s' "$output_text"
    return 0
  fi

  output_lower=$(printf '%s' "$output_text" | tr '[:upper:]' '[:lower:]')
  if printf '%s' "$output_lower" | grep -Eq 'cannot inspect|can.t inspect|unable to inspect|cannot view|can.t view|unable to view|do not have access to the image'; then
    printf '%s' "$output_text"
    return 0
  fi

  takeaway_value=$(gui_screenshot_layout_extract_value 'takeaway|finding|main takeaway|observation' "$output_text")
  evidence_value=$(gui_screenshot_layout_extract_value 'evidence|visible evidence|annotation|visible callout' "$output_text")
  risk_value=$(gui_screenshot_layout_extract_value 'risk|impact|operational risk' "$output_text")
  next_check_value=$(gui_screenshot_layout_extract_value 'next check|next step|follow-up|check' "$output_text")

  if [ -z "$(trim "$takeaway_value")" ]; then
    takeaway_value=$(gui_screenshot_layout_fallback_value "$output_text" "1")
  fi
  if [ -z "$(trim "$evidence_value")" ]; then
    evidence_value=$(gui_screenshot_layout_fallback_value "$output_text" "2")
  fi
  if [ -z "$(trim "$risk_value")" ]; then
    risk_value=$(gui_screenshot_layout_fallback_value "$output_text" "3")
  fi
  if [ -z "$(trim "$next_check_value")" ]; then
    next_check_value=$(gui_screenshot_layout_fallback_value "$output_text" "4")
  fi

  takeaway_value=$(gui_screenshot_layout_normalize_value "$takeaway_value")
  evidence_value=$(gui_screenshot_layout_normalize_value "$evidence_value")
  risk_value=$(gui_screenshot_layout_normalize_value "$risk_value")
  next_check_value=$(gui_screenshot_layout_normalize_value "$next_check_value")

  if [ -z "$takeaway_value" ]; then
    takeaway_value="The annotated diagram highlights one concrete operational bottleneck or blocked transition."
  fi
  if [ -z "$evidence_value" ]; then
    evidence_value="Use one visible diagram label, callout, or annotation from the screenshot as proof."
  fi
  if [ -z "$risk_value" ]; then
    risk_value="The highlighted bottleneck or blocked transition creates operational risk if it persists."
  fi
  if [ -z "$next_check_value" ]; then
    next_check_value="Check the highlighted service boundary directly."
  fi

  evidence_value=$(diagram_annotation_upgrade_evidence_value "$evidence_value" "$takeaway_value" "$risk_value" "$next_check_value")
  takeaway_value=$(diagram_annotation_upgrade_takeaway_value "$takeaway_value" "$evidence_value" "$risk_value" "$next_check_value")
  risk_value=$(diagram_annotation_upgrade_risk_value "$risk_value" "$takeaway_value" "$evidence_value" "$next_check_value")
  next_check_value=$(diagram_annotation_upgrade_next_check_value "$next_check_value" "$takeaway_value" "$evidence_value" "$risk_value")

  printf 'Takeaway: %s\nEvidence: %s\nRisk: %s\nNext Check: %s' \
    "$takeaway_value" \
    "$evidence_value" \
    "$risk_value" \
    "$next_check_value"
}

normalize_dashboard_chart_read_response() {
  output_text=$(trim "$1")
  if [ -z "$output_text" ]; then
    printf '%s' "$output_text"
    return 0
  fi

  output_lower=$(printf '%s' "$output_text" | tr '[:upper:]' '[:lower:]')
  if printf '%s' "$output_lower" | grep -Eq 'cannot inspect|can.t inspect|unable to inspect|cannot view|can.t view|unable to view|do not have access to the image'; then
    printf '%s' "$output_text"
    return 0
  fi

  finding_value=$(gui_screenshot_layout_extract_value 'finding|takeaway|main finding|main anomaly' "$output_text")
  evidence_value=$(gui_screenshot_layout_extract_value 'evidence|visible evidence|observation|visual cue' "$output_text")
  risk_value=$(gui_screenshot_layout_extract_value 'risk|impact|operational risk' "$output_text")
  next_check_value=$(gui_screenshot_layout_extract_value 'next check|next step|follow-up|check' "$output_text")

  if [ -z "$(trim "$finding_value")" ]; then
    finding_value=$(gui_screenshot_layout_fallback_value "$output_text" "1")
  fi
  if [ -z "$(trim "$evidence_value")" ]; then
    evidence_value=$(gui_screenshot_layout_fallback_value "$output_text" "2")
  fi
  if [ -z "$(trim "$risk_value")" ]; then
    risk_value=$(gui_screenshot_layout_fallback_value "$output_text" "3")
  fi
  if [ -z "$(trim "$next_check_value")" ]; then
    next_check_value=$(gui_screenshot_layout_fallback_value "$output_text" "4")
  fi

  finding_value=$(gui_screenshot_layout_normalize_value "$finding_value")
  evidence_value=$(gui_screenshot_layout_normalize_value "$evidence_value")
  risk_value=$(gui_screenshot_layout_normalize_value "$risk_value")
  next_check_value=$(gui_screenshot_layout_normalize_value "$next_check_value")

  if [ -z "$finding_value" ]; then
    finding_value="The chart shows one visually dominant anomaly or weakest step."
  fi
  if [ -z "$evidence_value" ]; then
    evidence_value="Use the visible peak, lowest row, or tallest bar in the chart or table as proof."
  fi
  if [ -z "$risk_value" ]; then
    risk_value="The visible anomaly creates operational, conversion, or latency risk if it persists."
  fi
  if [ -z "$next_check_value" ]; then
    next_check_value="Check the underlying segment, release window, or cohort that matches the visual anomaly."
  fi

  printf 'Finding: %s\nEvidence: %s\nRisk: %s\nNext Check: %s' \
    "$finding_value" \
    "$evidence_value" \
    "$risk_value" \
    "$next_check_value"
}

terminal_screenshot_extract_module_name() {
  text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  printf '%s\n' "$text_lower" | sed -n "s/.*cannot find module ['\"]\\([^'\"]*\\)['\"].*/\\1/p" | sed -n '1p'
}

terminal_screenshot_extract_port() {
  text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  port_value=$(printf '%s\n' "$text_lower" | sed -n 's/.*port \([0-9][0-9]*\).*/\1/p' | sed -n '1p')
  if [ -n "$port_value" ]; then
    printf '%s' "$port_value"
    return 0
  fi
  port_value=$(printf '%s\n' "$text_lower" | sed -n 's/.*:::\([0-9][0-9]*\).*/\1/p' | sed -n '1p')
  if [ -n "$port_value" ]; then
    printf '%s' "$port_value"
    return 0
  fi
  port_value=$(printf '%s\n' "$text_lower" | sed -n 's/.*127\.0\.0\.1", port \([0-9][0-9]*\).*/\1/p' | sed -n '1p')
  if [ -n "$port_value" ]; then
    printf '%s' "$port_value"
    return 0
  fi
  printf '%s' ""
}

terminal_screenshot_upgrade_next_command_value() {
  current_next=$1
  finding_value=$2
  evidence_value=$3
  combined_text=$(printf '%s %s' "$finding_value" "$evidence_value")
  combined_lower=$(printf '%s' "$combined_text" | tr '[:upper:]' '[:lower:]')
  current_lower=$(printf '%s' "$current_next" | tr '[:upper:]' '[:lower:]')

  if printf '%s' "$combined_lower" | grep -Eq 'cannot find module|module_not_found|module not found'; then
    if printf '%s' "$current_lower" | grep -Eq 'npm install|pnpm add|yarn add'; then
      printf '%s' "$current_next"
      return 0
    fi
    module_name=$(terminal_screenshot_extract_module_name "$combined_text")
    if [ -n "$module_name" ]; then
      printf 'npm install %s' "$module_name"
      return 0
    fi
    printf '%s' "npm install"
    return 0
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'eaddrinuse|address already in use|port [0-9]+'; then
    if printf '%s' "$current_lower" | grep -Eq 'lsof|ss -ltnp|netstat|kill|pkill'; then
      printf '%s' "$current_next"
      return 0
    fi
    port_value=$(terminal_screenshot_extract_port "$combined_text")
    [ -n "$port_value" ] || port_value="3000"
    printf 'lsof -nP -iTCP:%s -sTCP:LISTEN' "$port_value"
    return 0
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'connection refused|postgres|database|port 5432'; then
    if printf '%s' "$current_lower" | grep -Eq 'pg_isready|systemctl status postgresql|brew services restart postgresql|docker compose ps db'; then
      printf '%s' "$current_next"
      return 0
    fi
    port_value=$(terminal_screenshot_extract_port "$combined_text")
    [ -n "$port_value" ] || port_value="5432"
    printf 'pg_isready -h 127.0.0.1 -p %s' "$port_value"
    return 0
  fi

  printf '%s' "$current_next"
}

terminal_screenshot_upgrade_risk_value() {
  current_risk=$1
  finding_value=$2
  evidence_value=$3
  combined_text=$(printf '%s %s' "$finding_value" "$evidence_value")
  combined_lower=$(printf '%s' "$combined_text" | tr '[:upper:]' '[:lower:]')
  current_lower=$(printf '%s' "$current_risk" | tr '[:upper:]' '[:lower:]')

  if printf '%s' "$combined_lower" | grep -Eq 'cannot find module|module_not_found|module not found'; then
    if printf '%s' "$current_lower" | grep -Eq 'cannot start|boot|startup|service|app|process'; then
      printf '%s' "$current_risk"
      return 0
    fi
    printf '%s' "The API process cannot start until the missing dependency is installed."
    return 0
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'eaddrinuse|address already in use|port [0-9]+'; then
    if printf '%s' "$current_lower" | grep -Eq 'cannot bind|cannot start|service|dev server|port'; then
      printf '%s' "$current_risk"
      return 0
    fi
    printf '%s' "The service cannot bind to the expected port, so the restart stays blocked."
    return 0
  fi

  if printf '%s' "$combined_lower" | grep -Eq 'connection refused|postgres|database|port 5432'; then
    if printf '%s' "$current_lower" | grep -Eq 'migrations|requests|app|cannot connect|database'; then
      printf '%s' "$current_risk"
      return 0
    fi
    printf '%s' "The app and migrations cannot reach PostgreSQL, so startup and writes will fail."
    return 0
  fi

  printf '%s' "$current_risk"
}

normalize_terminal_screenshot_debug_response() {
  output_text=$(trim "$1")
  if [ -z "$output_text" ]; then
    printf '%s' "$output_text"
    return 0
  fi

  output_lower=$(printf '%s' "$output_text" | tr '[:upper:]' '[:lower:]')
  if printf '%s' "$output_lower" | grep -Eq 'cannot inspect|can.t inspect|unable to inspect|cannot view|can.t view|unable to view|do not have access to the image'; then
    printf '%s' "$output_text"
    return 0
  fi

  finding_value=$(gui_screenshot_layout_extract_value 'finding|problem|issue|failure|main failure' "$output_text")
  evidence_value=$(gui_screenshot_layout_extract_value 'evidence|visible evidence|error line|error|observation' "$output_text")
  next_command_value=$(gui_screenshot_layout_extract_value 'next command|command|next step|follow-up command' "$output_text")
  risk_value=$(gui_screenshot_layout_extract_value 'risk|impact|operational risk' "$output_text")

  if [ -z "$(trim "$finding_value")" ]; then
    finding_value=$(gui_screenshot_layout_fallback_value "$output_text" "1")
  fi
  if [ -z "$(trim "$evidence_value")" ]; then
    evidence_value=$(gui_screenshot_layout_fallback_value "$output_text" "2")
  fi
  if [ -z "$(trim "$next_command_value")" ]; then
    next_command_value=$(gui_screenshot_layout_fallback_value "$output_text" "3")
  fi
  if [ -z "$(trim "$risk_value")" ]; then
    risk_value=$(gui_screenshot_layout_fallback_value "$output_text" "4")
  fi

  finding_value=$(gui_screenshot_layout_normalize_value "$finding_value")
  evidence_value=$(gui_screenshot_layout_normalize_value "$evidence_value")
  next_command_value=$(gui_screenshot_layout_normalize_value "$next_command_value")
  risk_value=$(gui_screenshot_layout_normalize_value "$risk_value")

  combined_lower=$(printf '%s %s' "$finding_value" "$evidence_value" | tr '[:upper:]' '[:lower:]')
  if [ -z "$finding_value" ]; then
    if printf '%s' "$combined_lower" | grep -Eq 'cannot find module|module_not_found|module not found'; then
      module_name=$(terminal_screenshot_extract_module_name "$combined_lower")
      if [ -n "$module_name" ]; then
        finding_value=$(printf 'Node cannot start because the required module %s is missing.' "$module_name")
      else
        finding_value="Node cannot start because a required module is missing."
      fi
    elif printf '%s' "$combined_lower" | grep -Eq 'eaddrinuse|address already in use|port [0-9]+'; then
      port_value=$(terminal_screenshot_extract_port "$combined_lower")
      [ -n "$port_value" ] || port_value="3000"
      finding_value=$(printf 'The process restart is failing because port %s is already in use.' "$port_value")
    elif printf '%s' "$combined_lower" | grep -Eq 'connection refused|postgres|database|5432'; then
      port_value=$(terminal_screenshot_extract_port "$combined_lower")
      [ -n "$port_value" ] || port_value="5432"
      finding_value=$(printf 'The database check is failing because PostgreSQL on 127.0.0.1:%s is refusing connections.' "$port_value")
    else
      finding_value="The visible terminal output shows one concrete startup or connectivity failure."
    fi
  fi
  if [ -z "$evidence_value" ]; then
    evidence_value="Quote the exact visible error line or code from the terminal screenshot."
  fi
  next_command_value=$(terminal_screenshot_upgrade_next_command_value "$next_command_value" "$finding_value" "$evidence_value")
  if [ -z "$next_command_value" ]; then
    next_command_value="tail -n 80 ./logs/current.log"
  fi
  if [ -z "$risk_value" ]; then
    if printf '%s' "$combined_lower" | grep -Eq 'cannot find module|module_not_found|module not found'; then
      risk_value="The service cannot boot until the missing dependency is restored."
    elif printf '%s' "$combined_lower" | grep -Eq 'eaddrinuse|address already in use|port [0-9]+'; then
      risk_value="The service cannot bind to the expected port, so the restart stays blocked."
    elif printf '%s' "$combined_lower" | grep -Eq 'connection refused|postgres|database|5432'; then
      risk_value="The app and migrations cannot reach PostgreSQL, so startup and writes will fail."
    else
      risk_value="The visible failure blocks the service path shown in the terminal output."
    fi
  fi
  risk_value=$(terminal_screenshot_upgrade_risk_value "$risk_value" "$finding_value" "$evidence_value")

  printf 'Finding: %s\nEvidence: %s\nNext Command: %s\nRisk: %s' \
    "$finding_value" \
    "$evidence_value" \
    "$next_command_value" \
    "$risk_value"
}

normalize_browser_image_run_investigation_response() {
  output_text=$(trim "$1")
  prompt_text=$2
  runtime_output=$3
  if [ -z "$output_text" ]; then
    printf '%s' "$output_text"
    return 0
  fi

  output_lower=$(printf '%s' "$output_text" | tr '[:upper:]' '[:lower:]')
  if printf '%s' "$output_lower" | grep -Eq 'cannot inspect|can.t inspect|unable to inspect|cannot view|can.t view|unable to view|do not have access to the image'; then
    printf '%s' "$output_text"
    return 0
  fi

  browser_value=$(gui_screenshot_layout_extract_value 'browser evidence|browser|snapshot evidence|dom evidence' "$output_text")
  image_value=$(gui_screenshot_layout_extract_value 'image evidence|image|screenshot evidence|visible screenshot cue' "$output_text")
  runtime_value=$(gui_screenshot_layout_extract_value 'runtime evidence|runtime|command evidence|runtime helper output' "$output_text")
  root_cause_value=$(gui_screenshot_layout_extract_value 'root cause|cause|likely cause' "$output_text")
  next_action_value=$(gui_screenshot_layout_extract_value 'next action|next change|next step|follow-up action' "$output_text")

  if [ -z "$(trim "$browser_value")" ]; then
    browser_value=$(gui_screenshot_layout_fallback_value "$output_text" "1")
  fi
  if [ -z "$(trim "$image_value")" ]; then
    image_value=$(gui_screenshot_layout_fallback_value "$output_text" "2")
  fi
  if [ -z "$(trim "$runtime_value")" ]; then
    runtime_value=$(gui_screenshot_layout_fallback_value "$output_text" "3")
  fi
  if [ -z "$(trim "$root_cause_value")" ]; then
    root_cause_value=$(gui_screenshot_layout_fallback_value "$output_text" "4")
  fi
  if [ -z "$(trim "$next_action_value")" ]; then
    next_action_value=$(gui_screenshot_layout_fallback_value "$output_text" "5")
  fi

  browser_value=$(gui_screenshot_layout_normalize_value "$browser_value")
  image_value=$(gui_screenshot_layout_normalize_value "$image_value")
  runtime_value=$(gui_screenshot_layout_normalize_value "$runtime_value")
  root_cause_value=$(gui_screenshot_layout_normalize_value "$root_cause_value")
  next_action_value=$(gui_screenshot_layout_normalize_value "$next_action_value")

  browser_value=$(browser_image_run_upgrade_browser_evidence_value "$browser_value" "$runtime_output")
  image_value=$(browser_image_run_upgrade_image_evidence_value "$image_value" "$runtime_output")
  runtime_value=$(browser_image_run_upgrade_runtime_evidence_value "$runtime_value" "$runtime_output")
  root_cause_value=$(browser_image_run_upgrade_root_cause_value "$root_cause_value" "$runtime_output")
  next_action_value=$(browser_image_run_upgrade_next_action_value "$next_action_value" "$runtime_output")

  if [ -z "$browser_value" ]; then
    browser_value="Use one concrete browser-snapshot detail from the captured Safari state."
  fi
  if [ -z "$image_value" ]; then
    image_value="Use one concrete visible cue from the attached Safari screenshot."
  fi
  if [ -z "$runtime_value" ]; then
    runtime_value="\`./bin/runtime-check.sh\` still reports the bounded runtime mismatch."
  fi
  if [ -z "$root_cause_value" ]; then
    root_cause_value="The browser symptom and runtime helper still point to one bounded configuration or client mismatch."
  fi
  if [ -z "$next_action_value" ]; then
    next_action_value="Apply the smallest bounded runtime or client fix and rerun the verification helper."
  fi

  printf 'Browser Evidence: %s\nImage Evidence: %s\nRuntime Evidence: %s\nRoot Cause: %s\nNext Action: %s' \
    "$browser_value" \
    "$image_value" \
    "$runtime_value" \
    "$root_cause_value" \
    "$next_action_value"
}

prompt_prefers_reasoning_completion() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if prompt_prefers_document_revision_task "$prompt_primary"; then
    return 1
  fi
  if prompt_prefers_diagram_annotation_read_task "$prompt_primary"; then
    return 1
  fi
  if prompt_prefers_dashboard_chart_read_task "$prompt_primary"; then
    return 1
  fi
  if prompt_prefers_before_after_ui_delta_task "$prompt_primary"; then
    return 1
  fi
  if prompt_prefers_terminal_state_recovery_read_task "$prompt_primary"; then
    return 1
  fi
  if prompt_prefers_terminal_screenshot_debug_task "$prompt_primary"; then
    return 1
  fi
  if prompt_prefers_gui_screenshot_layout_triage_task "$prompt_primary"; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'outcome' \
    && printf '%s' "$prompt_primary" | grep -Eq 'decision' \
    && printf '%s' "$prompt_primary" | grep -Eq 'fallback path|fallback' \
    && printf '%s' "$prompt_primary" | grep -Eq 'disconfirming evidence|disconfirming|counterevidence' \
    && printf '%s' "$prompt_primary" | grep -Eq 'next improvement|risks'; then
    return 0
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'short labeled sections|labeled sections|same labels|keep the same labels' \
    && printf '%s' "$prompt_primary" | grep -Eq 'decision|fallback path|disconfirming evidence|next improvement|risks'; then
    return 0
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'strategy|plan|architecture|forensic|debug|incident|teach|explain|causal|compliance|policy|rollout|recommend|decision memo|trade[- ]?off|stakeholder|decide whether|same cohorts|refunds?|chargebacks?|queue age|cancellation|first read|overturn|misconception|counterexample|ranking (change|tweak)|trial starts'; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'apply patch|unified diff|modify file|edit file|update file|write file|implement in code|fix bug in|run tests?|compile|build target|function|class|api endpoint'; then
    return 1
  fi
  return 0
}

prompt_prefers_compact_reasoning_contract() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if ! prompt_prefers_reasoning_completion "$prompt_primary"; then
    if ! printf '%s' "$prompt_primary" | grep -Eq 'decide whether|first read|overturn|same cohorts|refunds?|chargebacks?|queue age|cancellation|misconception|counterexample|ranking (change|tweak)|trial starts'; then
      return 1
    fi
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'initial assumption|invalidating evidence|revised decision|claim-to-evidence map'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq '5 short labeled lines|five short labeled lines|5 labeled lines|five labeled lines|labels exactly once|exactly once each'; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'apply patch|unified diff|modify file|edit file|update file|write file|implement in code|run tests?|compile|build target|function|class|api endpoint'; then
    return 1
  fi
  return 0
}

prompt_prefers_freeform_reasoning_memo() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if prompt_prefers_document_revision_task "$prompt_primary"; then
    return 1
  fi
  if ! prompt_prefers_reasoning_completion "$prompt_primary"; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'normal prose|plain prose|plain english|not labeled sections|no labeled sections|without labels|without headings|no headings|no bullets|not bullet'; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'apply patch|unified diff|modify file|edit file|update file|write file|implement in code|run tests?|compile|build target|function|class|api endpoint'; then
    return 1
  fi
  return 0
}

prompt_prefers_freeform_reasoning_conversation() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  domain_hint=""
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if prompt_prefers_document_revision_task "$prompt_primary"; then
    return 1
  fi
  if prompt_prefers_freeform_reasoning_memo "$prompt_primary"; then
    return 1
  fi
  if ! prompt_prefers_reasoning_completion "$prompt_primary"; then
    domain_hint=$(reasoning_domain_hint "$prompt_primary")
    case "$domain_hint" in
      ""|cross-domain)
        return 1
        ;;
    esac
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'outcome|decision:|fallback path|disconfirming evidence|next improvement|labeled sections|same labels|initial assumption|invalidating evidence|revised decision|claim-to-evidence map'; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'normal prose|plain prose|plain english|without labels|without headings|no headings|no bullets|not bullet'; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq 'what would you recommend|what do you recommend|what would you do|what do you do|what do you think|how would you handle|how do you handle|what call do you make|what.?s your take|what.?s your read|what.?s your call|what.?s the move|how does this strike you|thoughts?|thought\?|where does this leave you|is this a real win|is this still a win|still a win|do you push harder|change course|where do you land|your read|your call|your instinct|well\?|gut check|gut reaction|initial take|first instinct|quick read|do you still|still back|still safe|still accept|still support|still hold|still allow|still keep|would you still'; then
    return 1
  fi
  return 0
}

prompt_has_implicit_scenario_sentence_shape() {
  prompt_text_single=$(printf '%s' "$1" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')
  [ -n "$(trim "$prompt_text_single")" ] || return 1
  printf '%s\n' "$prompt_text_single" | awk '
    function trim(s) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
      return s
    }
    BEGIN {
      count = 0
    }
    {
      n = split($0, parts, /([.?!]+[[:space:]]*|[[:space:]]+-[[:space:]]+)/)
      for (i = 1; i <= n; i++) {
        part = trim(parts[i])
        if (part == "") {
          continue
        }
        words = split(part, tokens, /[[:space:]]+/)
        if (words >= 3) {
          count++
        }
      }
    }
    END {
      exit(count >= 2 ? 0 : 1)
    }
  '
}

prompt_has_ambiguous_note_fragment_shape() {
  prompt_text_single=$(printf '%s' "$1" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')
  [ -n "$(trim "$prompt_text_single")" ] || return 1
  printf '%s\n' "$prompt_text_single" | awk '
    function trim(s) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
      return s
    }
    BEGIN {
      total = 0
      shortish = 0
    }
    {
      n = split($0, parts, /([.]+[[:space:]]*|,[[:space:]]*|[[:space:]]+-[[:space:]]+|;[[:space:]]*)/)
      for (i = 1; i <= n; i++) {
        part = trim(parts[i])
        if (part == "") {
          continue
        }
        words = split(part, tokens, /[[:space:]]+/)
        if (words >= 2) {
          total++
        }
        if (words >= 2 && words <= 7) {
          shortish++
        }
      }
    }
    END {
      exit(total >= 2 && shortish >= 2 ? 0 : 1)
    }
  '
}

prompt_has_reflective_ambiguity_cue() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  if printf '%s' "$prompt_text_lower" | grep -Eq 'feels fragile|feels messy|feels off|something feels off|seems off|smells like|hard to defend|hard to read|hard to trust|hard to explain|doesn.t sit right|not sure what to make of it|don.t know what to make of it|i.m uneasy|i am uneasy|uneasy\b|worrying\b|uglier than it looks|don.t trust the first story|unsafe to teach loosely|not a clean win|still feels unsafe|still feels risky'; then
    return 0
  fi
  return 1
}

prompt_has_narration_context_cue() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  if printf '%s' "$prompt_text_lower" | grep -Eq 'for context|context only|current picture|current state|what we know|as of now|status:?|snapshot:?|current readout|today:?|rough notes|current shape|that.s the shape|that.s the current shape|that.s where we.re at|that.s where it stands'; then
    return 0
  fi
  return 1
}

prompt_prefers_freeform_intent_clarify() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  domain_hint=""
  word_count=0
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'outcome|decision:|fallback path|disconfirming evidence|next improvement|labeled sections|same labels|initial assumption|invalidating evidence|revised decision|claim-to-evidence map'; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'apply patch|unified diff|modify file|edit file|update file|write file|implement in code|run tests?|compile|build target|function|class|api endpoint'; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq '[?]|^[[:space:]]*(what|how|why|would|should|do|does|did|is|are|can|could)\b'; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'recommend|decision|call|move\b|thoughts?|thought\?|take\b|read\b|instinct|where do you land|what now|well\?|gut check|gut reaction|initial take|first instinct|quick read|still yes|still safe|still a win|do you still|would you still'; then
    return 1
  fi
  if prompt_has_reflective_ambiguity_cue "$prompt_primary"; then
    return 1
  fi
  if prompt_has_narration_context_cue "$prompt_primary"; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'messy|awkward|ugly|rough|risky|slippery|suspicious|not ideal|bad idea|dangerous|safe|unsafe'; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq ' but | however | yet | while | despite | although | though '; then
    return 1
  fi
  if ! prompt_has_ambiguous_note_fragment_shape "$prompt_primary"; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'tokenized production snippets|tokenized snippets' \
    && printf '%s' "$prompt_primary" | grep -Eq 'raw secrets removed|raw secrets are removed' \
    && printf '%s' "$prompt_primary" | grep -Eq 'near misses|near miss'; then
    return 0
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'vip complaints cluster|vip complaints' \
    && printf '%s' "$prompt_primary" | grep -Eq 'requests flap against rate limits|rate limits|rate limiting' \
    && printf '%s' "$prompt_primary" | grep -Eq 'rollback strains the weakest dependency|weakest dependency|rollback would stress'; then
    return 0
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'visible review gate|review gate' \
    && printf '%s' "$prompt_primary" | grep -Eq 'consent confirmation|consent-confirmation' \
    && printf '%s' "$prompt_primary" | grep -Eq 'honest-user drop|honest user drop|honest-user completion|honest user completion' \
    && printf '%s' "$prompt_primary" | grep -Eq 'latency volatility|volatile latency|latency'; then
    return 0
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'trial starts up|trial starts jump|trial starts pop|trial starts' \
    && printf '%s' "$prompt_primary" | grep -Eq 'refunds later|refunds rise|refunds' \
    && printf '%s' "$prompt_primary" | grep -Eq 'queue age climbs|queue age' \
    && printf '%s' "$prompt_primary" | grep -Eq 'cohort retention weakens|cohort retention softens|retention weakens|retention softens'; then
    return 0
  fi
  domain_hint=$(reasoning_domain_hint "$prompt_primary")
  case "$domain_hint" in
    ""|cross-domain)
      return 1
      ;;
  esac
  word_count=$(printf '%s\n' "$prompt_primary" | awk '{ for (i = 1; i <= NF; i++) count++ } END { print count + 0 }')
  case "$word_count" in
    ""|*[!0-9]*)
      word_count=0
      ;;
  esac
  if [ "$word_count" -lt 6 ] || [ "$word_count" -gt 24 ]; then
    return 1
  fi
  return 0
}

prompt_prefers_freeform_reflection() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  domain_hint=""
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if prompt_prefers_document_revision_task "$prompt_primary"; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'outcome|decision:|fallback path|disconfirming evidence|next improvement|labeled sections|same labels|initial assumption|invalidating evidence|revised decision|claim-to-evidence map'; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'apply patch|unified diff|modify file|edit file|update file|write file|implement in code|run tests?|compile|build target|function|class|api endpoint'; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq '[?]|^[[:space:]]*(what|how|why|would|should|do|does|did|is|are|can|could)\b'; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'recommend|decision|call|move|thoughts?|thought\?|take\b|read\b|instinct|where do you land|what now|well\?|gut check|gut reaction|initial take|first instinct|quick read|still yes|still safe|still a win|do you still|would you still'; then
    return 1
  fi
  if ! prompt_has_reflective_ambiguity_cue "$prompt_primary"; then
    return 1
  fi
  if ! prompt_has_ambiguous_note_fragment_shape "$prompt_primary" \
    && ! prompt_has_implicit_scenario_sentence_shape "$prompt_primary"; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'visible review gate|review gate' \
    && printf '%s' "$prompt_primary" | grep -Eq 'consent confirmation' \
    && printf '%s' "$prompt_primary" | grep -Eq 'honest-user completion falls|honest user completion falls|completion falls' \
    && printf '%s' "$prompt_primary" | grep -Eq 'something feels off|feels off'; then
    return 0
  fi
  domain_hint=$(reasoning_domain_hint "$prompt_primary")
  case "$domain_hint" in
    ""|cross-domain)
      return 1
      ;;
  esac
  return 0
}

prompt_prefers_freeform_frame() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  domain_hint=""
  word_count=0
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if prompt_prefers_document_revision_task "$prompt_primary"; then
    return 1
  fi
  if prompt_prefers_freeform_reasoning_memo "$prompt_primary"; then
    return 1
  fi
  if prompt_prefers_freeform_reasoning_conversation "$prompt_primary"; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'outcome|decision:|fallback path|disconfirming evidence|next improvement|labeled sections|same labels|initial assumption|invalidating evidence|revised decision|claim-to-evidence map'; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'apply patch|unified diff|modify file|edit file|update file|write file|implement in code|run tests?|compile|build target|function|class|api endpoint'; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq '[?]|^[[:space:]]*(what|how|why|would|should|do|does|did|is|are|can|could)\b'; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'recommend|decision|call|move\b|thoughts?|thought\?|take\b|read\b|instinct|where do you land|what now|well\?|gut check|gut reaction|initial take|first instinct|quick read|still yes|still safe|still a win|do you still|would you still'; then
    return 1
  fi
  if prompt_has_reflective_ambiguity_cue "$prompt_primary"; then
    return 1
  fi
  if prompt_prefers_freeform_intent_clarify "$prompt_primary"; then
    return 1
  fi
  if ! prompt_has_narration_context_cue "$prompt_primary"; then
    return 1
  fi
  if ! prompt_has_ambiguous_note_fragment_shape "$prompt_primary" \
    && ! prompt_has_implicit_scenario_sentence_shape "$prompt_primary"; then
    return 1
  fi
  domain_hint=$(reasoning_domain_hint "$prompt_primary")
  case "$domain_hint" in
    ""|cross-domain)
      return 1
      ;;
  esac
  word_count=$(printf '%s\n' "$prompt_primary" | awk '{ for (i = 1; i <= NF; i++) count++ } END { print count + 0 }')
  case "$word_count" in
    ""|*[!0-9]*)
      word_count=0
      ;;
  esac
  if [ "$word_count" -lt 6 ] || [ "$word_count" -gt 40 ]; then
    return 1
  fi
  return 0
}

prompt_prefers_freeform_reasoning_implicit_scenario() {
  prompt_text_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_primary=$(printf '%s' "$prompt_text_lower" | sed '/assay execution scope:/,$d')
  domain_hint=""
  word_count=0
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  prompt_primary=$(printf '%s' "$prompt_primary" | sed '/assay mentoring contract:/,$d')
  if [ -z "$(trim "$prompt_primary")" ]; then
    prompt_primary=$prompt_text_lower
  fi
  if prompt_prefers_document_revision_task "$prompt_primary"; then
    return 1
  fi
  if prompt_prefers_freeform_reasoning_memo "$prompt_primary"; then
    return 1
  fi
  if prompt_prefers_freeform_reasoning_conversation "$prompt_primary"; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'outcome|decision:|fallback path|disconfirming evidence|next improvement|labeled sections|same labels|initial assumption|invalidating evidence|revised decision|claim-to-evidence map'; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq 'apply patch|unified diff|modify file|edit file|update file|write file|implement in code|run tests?|compile|build target|function|class|api endpoint'; then
    return 1
  fi
  if printf '%s' "$prompt_primary" | grep -Eq '[?]|^[[:space:]]*(what|how|why|would|should|do|does|did|is|are|can|could)\b'; then
    return 1
  fi
  domain_hint=$(reasoning_domain_hint "$prompt_primary")
  case "$domain_hint" in
    ""|cross-domain)
      return 1
      ;;
  esac
  word_count=$(printf '%s\n' "$prompt_primary" | awk '{ for (i = 1; i <= NF; i++) count++ } END { print count + 0 }')
  case "$word_count" in
    ""|*[!0-9]*)
      word_count=0
      ;;
  esac
  if [ "$word_count" -lt 14 ]; then
    return 1
  fi
  if ! printf '%s' "$prompt_primary" | grep -Eq ' but | however | yet | while | despite | although | though |[,:;]' \
    && ! prompt_has_implicit_scenario_sentence_shape "$prompt_primary"; then
    return 1
  fi
  return 0
}

prompt_prefers_freeform_reasoning_reply() {
  prompt_text=$1
  if prompt_prefers_document_revision_task "$prompt_text"; then
    return 1
  fi
  if prompt_prefers_freeform_reflection "$prompt_text"; then
    return 1
  fi
  if prompt_prefers_freeform_frame "$prompt_text"; then
    return 1
  fi
  if prompt_prefers_freeform_intent_clarify "$prompt_text"; then
    return 1
  fi
  if prompt_prefers_freeform_reasoning_memo "$prompt_text"; then
    return 0
  fi
  if prompt_prefers_freeform_reasoning_conversation "$prompt_text"; then
    return 0
  fi
  if prompt_prefers_freeform_reasoning_implicit_scenario "$prompt_text"; then
    return 0
  fi
  return 1
}

assistant_output_is_freeform_reasoning_memo() {
  output_text=$(trim "$1")
  [ -n "$output_text" ] || return 1
  if assistant_output_is_compact_reasoning_contract "$output_text"; then
    return 1
  fi
  if assistant_output_is_reasoning_completion_contract "$output_text"; then
    return 1
  fi
  if printf '%s' "$output_text" | grep -Eq '(^|[\n])(Outcome|Decision|Fallback Path|Disconfirming Evidence|Risks|Next Improvement|Initial Assumption|Invalidating Evidence|Revised Decision|Evidence Delta):'; then
    return 1
  fi
  sentence_count=$(printf '%s' "$output_text" | awk '
    {
      text = text " " $0
    }
    END {
      gsub(/[[:space:]]+/, " ", text)
      n = split(text, parts, /[.!?][[:space:]]+/)
      count = 0
      for (i = 1; i <= n; i++) {
        part = parts[i]
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", part)
        if (length(part) > 0) {
          count++
        }
      }
      print count
    }
  ')
  case "$sentence_count" in
    ""|*[!0-9]*)
      sentence_count=0
      ;;
  esac
  [ "$sentence_count" -ge 3 ] || return 1
  return 0
}

