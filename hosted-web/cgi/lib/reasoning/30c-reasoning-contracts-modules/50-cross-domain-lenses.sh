reasoning_cross_domain_line_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  prompt_focus=$(reasoning_prompt_focus_brief "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf 'Cross-Domain Integration: For technical architecture, tie topology, replay safety, and spend around %s to partner/operator trust, tenant-isolation compliance, empirical recovery checks, and rollback readiness before pursuing raw throughput.' "$anchor_phrase"
      ;;
    forensics)
      printf 'Cross-Domain Integration: For debugging/forensics, connect evidence order and reproduction quality for %s to user-impact containment, policy-safe data handling, measurable falsification checks, and incident communications discipline.' "$anchor_phrase"
      ;;
    security/compliance)
      printf 'Cross-Domain Integration: For security/compliance tradeoffs, connect control boundaries for %s to analyst workflow speed, audit evidence, operational recovery paths, and measurable exception drift instead of treating policy as a separate appendix.' "$anchor_phrase"
      ;;
    product/ux)
      printf 'Cross-Domain Integration: For product and UX constraints, connect onboarding clarity for %s to backend latency tolerance, abuse/compliance guardrails, measurable support load, and operator fallback readiness.' "$anchor_phrase"
      ;;
    metrics/causality)
      printf 'Cross-Domain Integration: For data and causal reasoning, connect the observed movement in %s to instrumentation quality, user-behavior shifts, chargeback or harm exposure, policy-safe measurement limits, and rollout/rollback readiness.' "$anchor_phrase"
      ;;
    incident\ response)
      printf 'Cross-Domain Integration: For incident response under uncertainty, connect mitigation speed for %s to direct user harm, forensic quality, policy-safe access and communications, measurable burn-rate improvement, and reversible operational controls.' "$anchor_phrase"
      ;;
    teaching)
      printf 'Cross-Domain Integration: For teaching under misconception pressure, connect the explanation of %s to the underlying mechanism, learner decisions, policy or safety consequences, measurable transfer checks, and the operational cost of getting the concept wrong.' "$anchor_phrase"
      ;;
    strategy)
      printf 'Cross-Domain Integration: For strategic planning, connect the plan around %s to customer value, platform/load realities, legal and compliance vetoes, leading indicators, and the operational cost of the chosen sacrifice.' "$anchor_phrase"
      ;;
    *)
      printf 'Cross-Domain Integration: For %s, connect the primary benefit around %s to architecture, user impact, compliance boundaries, measurable validation, and rollback operations before finalizing.' "$prompt_focus" "$anchor_phrase"
      ;;
  esac
}

reasoning_domain_linkage_line_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  domain_label=$(reasoning_domain_label_for_prompt "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf 'Domain Linkage: In this %s scenario, topology decisions for %s affect finance through steady-state cost, compliance through replay and audit evidence, and operations through blast radius and recovery time.' "$domain_label" "$anchor_phrase"
      ;;
    forensics)
      printf 'Domain Linkage: In this %s scenario, premature root-cause claims for %s create incident risk, misdirect engineering effort, and can produce policy or customer-impact mistakes if the wrong mitigation ships first.' "$domain_label" "$anchor_phrase"
      ;;
    security/compliance)
      printf 'Domain Linkage: In this %s scenario, choices about %s affect legal exposure, operations recoverability, analyst productivity, and customer trust simultaneously, so policy compliance cannot be treated as an afterthought.' "$domain_label" "$anchor_phrase"
      ;;
    product/ux)
      printf 'Domain Linkage: In this %s scenario, changing %s affects user comprehension, backend latency tolerance, operations burden, and policy risk together; an elegant UI alone is not a sufficient success condition.' "$domain_label" "$anchor_phrase"
      ;;
    metrics/causality)
      printf 'Domain Linkage: In this %s scenario, interpretation of %s affects product rollout, finance exposure, compliance risk, and incident load because a false causal read can scale the wrong intervention.' "$domain_label" "$anchor_phrase"
      ;;
    incident\ response)
      printf 'Domain Linkage: In this %s scenario, decisions about %s affect user harm, communications credibility, on-call load, and longer-term forensic quality, so mitigation speed and evidence quality must be balanced explicitly.' "$domain_label" "$anchor_phrase"
      ;;
    teaching)
      printf 'Domain Linkage: In this %s scenario, teaching around %s must connect mechanism, counterexample, and practical decision-making; otherwise the explanation remains stylistically strong but operationally weak.' "$domain_label" "$anchor_phrase"
      ;;
    strategy)
      printf 'Domain Linkage: In this %s scenario, choices about %s couple revenue timing, cost structure, legal exposure, operational load, and organizational trust; the right plan must make the sacrifice visible rather than hide it.' "$domain_label" "$anchor_phrase"
      ;;
    *)
      printf 'Domain Linkage: In this %s scenario, the decision for %s changes user impact, operational burden, and risk exposure together, so no single metric or anecdote is enough.' "$domain_label" "$anchor_phrase"
      ;;
  esac
}

reasoning_cross_domain_signal_check_line_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf 'Cross-Domain Signal Check: Verify replay correctness, partner/operator usability, tenant-boundary compliance, cost or throughput metrics, and rollback recovery for %s before finalizing.' "$anchor_phrase"
      ;;
    forensics)
      printf 'Cross-Domain Signal Check: Verify deterministic repro, user-impact containment, evidence-handling compliance, timeline and metric consistency, and mitigation rollback posture for %s before finalizing.' "$anchor_phrase"
      ;;
    security/compliance)
      printf 'Cross-Domain Signal Check: Verify control coverage, analyst workflow impact, audit and residency boundaries, exception-rate metrics, and recovery-path safety for %s before finalizing.' "$anchor_phrase"
      ;;
    product/ux)
      printf 'Cross-Domain Signal Check: Verify task completion, latency and support friction, abuse and policy guardrails, experiment or cohort evidence, and fallback-path readiness for %s before finalizing.' "$anchor_phrase"
      ;;
    metrics/causality)
      printf 'Cross-Domain Signal Check: Verify instrumentation integrity, user or operator impact, policy-safe measurement scope, confound-resistant metrics, and rollout rollback readiness for %s before finalizing.' "$anchor_phrase"
      ;;
    incident\ response)
      printf 'Cross-Domain Signal Check: Verify direct harm reduction, degraded user workflow impact, access and communication boundaries, burn-rate and blast-radius metrics, and rollback containment for %s before finalizing.' "$anchor_phrase"
      ;;
    teaching)
      printf 'Cross-Domain Signal Check: Verify mechanism accuracy, learner usability, safety or policy boundaries, transfer metrics, and operational consequences of misunderstanding %s before finalizing.' "$anchor_phrase"
      ;;
    strategy)
      printf 'Cross-Domain Signal Check: Verify platform feasibility, customer and operator impact, legal non-negotiables, leading indicators, and operational load for %s before finalizing.' "$anchor_phrase"
      ;;
    *)
      printf 'Cross-Domain Signal Check: Verify architecture, user impact, compliance constraints, metrics causality, and incident operations for %s before finalizing.' "$anchor_phrase"
      ;;
  esac
}

reasoning_architecture_lens_line_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf 'Architecture Lens: Use replay-safe boundaries, idempotent state transitions, tenant isolation, and bounded recovery domains for %s.' "$anchor_phrase"
      ;;
    forensics)
      printf 'Architecture Lens: Map the exact failing path, failover state transition, and dependency boundaries that can explain %s without skipping reproduction steps.' "$anchor_phrase"
      ;;
    security/compliance)
      printf 'Architecture Lens: Model key custody, data-flow segmentation, residency boundaries, and emergency-access paths for %s before endorsing workflow shortcuts.' "$anchor_phrase"
      ;;
    product/ux)
      printf 'Architecture Lens: Keep the flow for %s tolerant of latency spikes, retries, and partial backend failure so the UI does not promise a state the system cannot sustain.' "$anchor_phrase"
      ;;
    metrics/causality)
      printf 'Architecture Lens: Verify instrumentation boundaries, cohort definitions, logging integrity, and ranking or queue-state changes around %s before reading movement as causal.' "$anchor_phrase"
      ;;
    incident\ response)
      printf 'Architecture Lens: Isolate the failing component, containment boundary, and reversible control surface for %s so mitigation does not widen blast radius.' "$anchor_phrase"
      ;;
    teaching)
      printf 'Architecture Lens: Show the real mechanism, state change, or dependency chain behind %s instead of teaching only the surface rule.' "$anchor_phrase"
      ;;
    strategy)
      printf 'Architecture Lens: Check whether platform coupling, capacity headroom, and change-rate tolerance around %s can absorb the plan without hidden reliability debt.' "$anchor_phrase"
      ;;
    *)
      printf 'Architecture Lens: Summarize the system design and operational constraints that dominate feasibility for %s.' "$anchor_phrase"
      ;;
  esac
}

reasoning_product_lens_line_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf 'Product/UX Lens: Keep partner and operator workflows around %s legible during backlog, replay, or degraded-mode events, with explicit reason codes and recovery expectations.' "$anchor_phrase"
      ;;
    forensics)
      printf 'Product/UX Lens: Treat the explanation of %s as a user-facing decision too; the wrong story creates customer whiplash, support churn, and operator confusion.' "$anchor_phrase"
      ;;
    security/compliance)
      printf 'Product/UX Lens: Preserve analyst throughput and understandable failure modes for %s without creating silent policy exceptions or operator workarounds.' "$anchor_phrase"
      ;;
    product/ux)
      printf 'Product/UX Lens: Make the ordering, trust checks, fallback path, and latency expectations for %s understandable enough that high-risk users do not self-select into failure.' "$anchor_phrase"
      ;;
    metrics/causality)
      printf 'Product/UX Lens: Check whether the user or operator experience around %s changed in ways that would move the metric even if the underlying value did not.' "$anchor_phrase"
      ;;
    incident\ response)
      printf 'Product/UX Lens: Optimize the degraded path for %s so the first mitigation reduces harm and confusion for affected users, support, and operators.' "$anchor_phrase"
      ;;
    teaching)
      printf 'Product/UX Lens: Make the learner path around %s diagnostic rather than decorative, so confusion surfaces early instead of hiding behind fluent language.' "$anchor_phrase"
      ;;
    strategy)
      printf 'Product/UX Lens: Tie the plan for %s to customer value, adoption friction, support burden, and trust effects rather than roadmap aesthetics alone.' "$anchor_phrase"
      ;;
    *)
      printf 'Product/UX Lens: Summarize the user impact, adoption friction, and workflow ergonomics tradeoffs for %s.' "$anchor_phrase"
      ;;
  esac
}

reasoning_security_lens_line_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf 'Security/Compliance Lens: Make tenant boundaries, audit evidence, access scoping, and replay-safe retention rules for %s explicit enough to survive failure drills.' "$anchor_phrase"
      ;;
    forensics)
      printf 'Security/Compliance Lens: Preserve least-privilege log access, PII handling, chain-of-custody discipline, and policy-safe mitigation choices while investigating %s.' "$anchor_phrase"
      ;;
    security/compliance)
      printf 'Security/Compliance Lens: Preserve least privilege, residency, retention, approval ownership, and auditability for %s before trading control depth for speed.' "$anchor_phrase"
      ;;
    product/ux)
      printf 'Security/Compliance Lens: Keep trust checks, abuse controls, consent boundaries, and operator override policy for %s explicit even when conversion pressure is high.' "$anchor_phrase"
      ;;
    metrics/causality)
      printf 'Security/Compliance Lens: Ensure measurement for %s respects data minimization, retention, cohort access controls, and policy limits on what can be compared or stored.' "$anchor_phrase"
      ;;
    incident\ response)
      printf 'Security/Compliance Lens: Keep access escalation, evidence retention, and external communications for %s inside approved incident and policy boundaries.' "$anchor_phrase"
      ;;
    teaching)
      printf 'Security/Compliance Lens: Surface the safety or policy boundaries that become dangerous when %s is misunderstood, rather than teaching a purely neutral abstraction.' "$anchor_phrase"
      ;;
    strategy)
      printf 'Security/Compliance Lens: Test the plan for %s against legal vetoes, compliance staffing, and approval boundaries before calling it executable.' "$anchor_phrase"
      ;;
    *)
      printf 'Security/Compliance Lens: Summarize the policy, legal, and data-governance boundaries for %s.' "$anchor_phrase"
      ;;
  esac
}

reasoning_metrics_lens_line_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf 'Metrics/Causality Lens: Track replay mismatch, backlog age, tenant spillover, throughput under stress, and unit-cost drift for %s so the architecture is judged on failure behavior, not only nominal load.' "$anchor_phrase"
      ;;
    forensics)
      printf 'Metrics/Causality Lens: Require deterministic repro rate, timeline consistency, failing-sample stability, and explicit elimination of stronger alternatives for %s before escalating confidence.' "$anchor_phrase"
      ;;
    security/compliance)
      printf 'Metrics/Causality Lens: Track exception rate, analyst latency, audit-proof coverage, control ownership, and recovery-path dependence for %s instead of treating compliance as unmeasured overhead.' "$anchor_phrase"
      ;;
    product/ux)
      printf 'Metrics/Causality Lens: Pair completion and time-to-value for %s with abuse, support load, fallback usage, and p95 latency so local UX wins do not hide system harm.' "$anchor_phrase"
      ;;
    metrics/causality)
      printf 'Metrics/Causality Lens: Stress-test %s with confound checks, cohort drift inspection, lagged-harm tracking, and counterfactual reasoning before attributing movement to the proposed cause.' "$anchor_phrase"
      ;;
    incident\ response)
      printf 'Metrics/Causality Lens: Track direct harm, error-budget burn, mitigation timing, affected-scope growth, and signal freshness for %s during the first mitigation windows.' "$anchor_phrase"
      ;;
    teaching)
      printf 'Metrics/Causality Lens: Use prediction checks, near-miss discrimination, counterexample success, and delayed transfer on %s to distinguish real understanding from fluency.' "$anchor_phrase"
      ;;
    strategy)
      printf 'Metrics/Causality Lens: Tie %s to leading indicators, sacrifice budgets, resource burn, reliability drift, and review-window ownership so the strategy cannot hide behind a single headline metric.' "$anchor_phrase"
      ;;
    *)
      printf 'Metrics/Causality Lens: Summarize the measurement signals that can validate or falsify the decision for %s.' "$anchor_phrase"
      ;;
  esac
}

reasoning_incident_lens_line_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf 'Incident/Ops Lens: Predefine replay drills, per-tenant kill switches, recovery windows, and ownership for %s so rollback is real, not rhetorical.' "$anchor_phrase"
      ;;
    forensics)
      printf 'Incident/Ops Lens: Keep evidence preservation, mitigation checkpoints, communications timing, and escalation ownership for %s aligned while the root cause remains uncertain.' "$anchor_phrase"
      ;;
    security/compliance)
      printf 'Incident/Ops Lens: Verify revoke, rotate, emergency-access, and rollback procedures for %s before accepting a control design that looks safe only in steady state.' "$anchor_phrase"
      ;;
    product/ux)
      printf 'Incident/Ops Lens: Keep a manual or gated fallback path, support playbook, and kill switch for %s so user trust survives bad cohorts or backend instability.' "$anchor_phrase"
      ;;
    metrics/causality)
      printf 'Incident/Ops Lens: Hold scale-up, set review windows, and assign owners for %s so a weak causal read can be reversed before it becomes an incident.' "$anchor_phrase"
      ;;
    incident\ response)
      printf 'Incident/Ops Lens: Define containment order, rollback trigger, escalation owner, and evidence-preservation boundary for %s before acting on the first hypothesis.' "$anchor_phrase"
      ;;
    teaching)
      printf 'Incident/Ops Lens: Make explicit what operational mistake, escalation delay, or safety issue follows if %s is still misunderstood after the lesson.' "$anchor_phrase"
      ;;
    strategy)
      printf 'Incident/Ops Lens: Check whether sequencing, rollback options, staffing load, and support readiness for %s are realistic under the proposed pace of change.' "$anchor_phrase"
      ;;
    *)
      printf 'Incident/Ops Lens: Summarize rollback readiness, escalation triggers, and runtime risk controls for %s.' "$anchor_phrase"
      ;;
  esac
}

reasoning_tradeoff_ledger_line_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf 'Tradeoff Ledger: Tradeoff 1: stronger per-tenant isolation for %s lowers blast radius but raises steady-state cost and operational complexity; Tradeoff 2: shared ingestion improves utilization but makes replay correctness and noisy-neighbor failures harder to contain.' "$anchor_phrase"
      ;;
    forensics)
      printf 'Tradeoff Ledger: Tradeoff 1: narrowing quickly on %s speeds action but raises false-confidence risk; Tradeoff 2: keeping multiple live hypotheses preserves recovery options but slows narrative clarity.' "$anchor_phrase"
      ;;
    security/compliance)
      printf 'Tradeoff Ledger: Tradeoff 1: tighter controls for %s reduce legal and audit risk but add workflow latency; Tradeoff 2: faster analyst paths improve throughput but can create exception debt and harder recovery.' "$anchor_phrase"
      ;;
    product/ux)
      printf 'Tradeoff Ledger: Tradeoff 1: removing friction from %s can lift completion while increasing abuse or support cost; Tradeoff 2: stronger trust checks protect the system but can push good users into abandonment or manual review.' "$anchor_phrase"
      ;;
    metrics/causality)
      printf 'Tradeoff Ledger: Tradeoff 1: acting early on %s can capture upside while increasing the chance of scaling a confounded effect; Tradeoff 2: waiting for cleaner causal evidence lowers false-positive risk but delays visible progress.' "$anchor_phrase"
      ;;
    incident\ response)
      printf 'Tradeoff Ledger: Tradeoff 1: faster mitigation for %s can reduce direct harm while degrading evidence quality; Tradeoff 2: slower evidence collection improves confidence but can leave users exposed longer.' "$anchor_phrase"
      ;;
    teaching)
      printf 'Tradeoff Ledger: Tradeoff 1: a simplified explanation of %s improves fluency but can preserve the core misconception; Tradeoff 2: a counterexample-rich explanation improves transfer but raises short-term cognitive load.' "$anchor_phrase"
      ;;
    strategy)
      printf 'Tradeoff Ledger: Tradeoff 1: faster expansion around %s can raise near-term growth while increasing compliance, reliability, or support debt; Tradeoff 2: heavier controls protect trust and margin but slow visible progress and stakeholder enthusiasm.' "$anchor_phrase"
      ;;
    *)
      printf 'Tradeoff Ledger: Tradeoff 1: the faster path around %s increases momentum but can hide downstream cost; Tradeoff 2: the safer path preserves optionality but slows visible progress.' "$anchor_phrase"
      ;;
  esac
}

reasoning_rejected_alternative_line_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf 'Rejected Alternative: A single global ingestion path for %s was rejected because it looks cheaper on nominal load while concentrating replay, recovery, and tenant-containment risk into one surface.' "$anchor_phrase"
      ;;
    forensics)
      printf 'Rejected Alternative: A single-cause memo for %s based on the noisiest warning was rejected because it front-loads confidence before the timeline and reproduction evidence justify it.' "$anchor_phrase"
      ;;
    security/compliance)
      printf 'Rejected Alternative: A convenience-first rollout for %s was rejected because it depends on exceptions, weak auditability, or residency shortcuts that would surface later as governance debt.' "$anchor_phrase"
      ;;
    product/ux)
      printf 'Rejected Alternative: A completion-first flow for %s was rejected because it treats trust and abuse controls as secondary clean-up work instead of part of the core user path.' "$anchor_phrase"
      ;;
    metrics/causality)
      printf 'Rejected Alternative: A scale-now interpretation of %s was rejected because the observed lift can still be explained by cohort drift, ranking changes, or lagged harms.' "$anchor_phrase"
      ;;
    incident\ response)
      printf 'Rejected Alternative: Waiting for a perfect root cause before acting on %s was rejected because it leaves direct user harm live without enough upside to justify the delay.' "$anchor_phrase"
      ;;
    teaching)
      printf 'Rejected Alternative: A polished but abstraction-heavy lesson on %s was rejected because it can sound correct while still failing the learner on counterexamples and near misses.' "$anchor_phrase"
      ;;
    strategy)
      printf 'Rejected Alternative: An all-goals-win roadmap for %s was rejected because it depends on unstated resource, consent, or reliability miracles.' "$anchor_phrase"
      ;;
    *)
      printf 'Rejected Alternative: The superficially simpler path for %s was rejected because it assumes the current success signal generalizes without enough evidence.' "$anchor_phrase"
      ;;
  esac
}

reasoning_stakeholder_map_line_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf 'Stakeholder Impact Map: Partners need deterministic replay results for %s, SRE carries backlog and recovery pressure, compliance needs auditable tenant boundaries, and finance absorbs the downside if isolation is bought too late.' "$anchor_phrase"
      ;;
    forensics)
      printf 'Stakeholder Impact Map: Engineers need decisive repro steps for %s, incident command needs a mitigation path that survives uncertainty, and support or customers absorb harm if the wrong explanation drives communications.' "$anchor_phrase"
      ;;
    security/compliance)
      printf 'Stakeholder Impact Map: Analysts need usable controls for %s, legal and compliance need audit-safe boundaries, operations needs recoverability, and customers absorb trust loss when convenience outruns governance.' "$anchor_phrase"
      ;;
    product/ux)
      printf 'Stakeholder Impact Map: Users need a trustworthy path for %s, support absorbs ambiguous failures, risk and compliance teams absorb abuse or consent leakage, and operations carries the manual rescue burden if the flow is brittle.' "$anchor_phrase"
      ;;
    metrics/causality)
      printf 'Stakeholder Impact Map: Product wants to scale wins around %s, finance absorbs false-positive rollout cost, risk and compliance absorb delayed harms, and operations carries the incident load if the causal read is wrong.' "$anchor_phrase"
      ;;
    incident\ response)
      printf 'Stakeholder Impact Map: Affected users absorb harm from %s first, support and communications absorb confusion, incident command absorbs timing pressure, and engineering absorbs the cost of weak evidence if mitigation is mis-aimed.' "$anchor_phrase"
      ;;
    teaching)
      printf 'Stakeholder Impact Map: Learners need an explanation of %s that survives application, operators or reviewers absorb the cost of misunderstanding, and the teacher absorbs extra friction if transfer is not measured honestly.' "$anchor_phrase"
      ;;
    strategy)
      printf 'Stakeholder Impact Map: Customers need the benefits promised by %s, finance needs bounded spend and margin, legal needs a policy-safe scope, and operations needs a change rate the system and team can absorb.' "$anchor_phrase"
      ;;
    *)
      printf 'Stakeholder Impact Map: Users, operators, compliance owners, and finance see different costs and benefits from %s, so the decision must make those asymmetries explicit.' "$anchor_phrase"
      ;;
  esac
}

