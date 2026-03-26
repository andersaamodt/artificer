    teaching)
      if [ "$verified" -eq 1 ]; then
        printf 'Residual Risk: Medium because %s may still reflect fluent repetition rather than real transfer under pressure.' "$anchor_phrase"
      else
        printf 'Residual Risk: High because %s lacks counterexample and near-miss transfer evidence.' "$anchor_phrase"
      fi
      ;;
    strategy)
      if [ "$verified" -eq 1 ]; then
        printf 'Residual Risk: Medium because %s can still break a sacrificed guardrail once commitments harden.' "$anchor_phrase"
      else
        printf 'Residual Risk: High because %s lacks hard evidence on stakeholder guardrails and sacrifice bounds.' "$anchor_phrase"
      fi
      ;;
    *)
      if [ "$verified" -eq 1 ]; then
        printf 'Residual Risk: Medium until independent revalidation closes remaining uncertainty for %s.' "$anchor_phrase"
      else
        printf 'Residual Risk: High because %s still lacks direct verification evidence; treat this as planning guidance only.' "$anchor_phrase"
      fi
      ;;
  esac
}

scenario_specific_block_lower() {
  final_text_raw=$1
  printf '%s\n' "$final_text_raw" | awk '
    BEGIN {
      capture = 0
    }
    {
      line = tolower($0)
      stripped = line
      sub(/^[[:space:]]+/, "", stripped)
      if (stripped ~ /^scenario-specific check:/) {
        capture = 1
        print stripped
        next
      }
      if (capture == 1) {
        if (stripped ~ /^[a-z][a-z0-9 _\/-]*:/) {
          exit
        }
        print stripped
      }
    }
  '
}

scenario_non_template_body_lower() {
  final_text_raw=$1
  printf '%s\n' "$final_text_raw" | awk '
    {
      line = tolower($0)
      stripped = line
      sub(/^[[:space:]]+/, "", stripped)
      if (stripped ~ /^[[:space:]]*$/) next
      if (stripped ~ /^(outcome|verification evidence|context anchor|domain anchor|scenario-specific check|trap and counterevidence check|false premise challenge|premise validation|cross-domain integration|domain linkage|architecture lens|product\/ux lens|security\/compliance lens|metrics\/causality lens|incident\/ops lens|tradeoff ledger|rejected alternative|stakeholder impact map|recovery and self-correction|re-plan trigger|self-correction evidence|revised from|validation owner|time window|evidence anchors|claim-to-evidence map|quantified thresholds|evidence caveats|source quality ranking|source conflict resolution|assumption register|uncertainty range|command anchors|near-miss guard|verification status|go\/no-go|required evidence to proceed|residual risk):/) next
      gsub(/for this scenario[[:space:]]*\([^)]*\)/, "", stripped)
      gsub(/scenario:[[:space:]]*[^.]+/, "", stripped)
      if (stripped ~ /^[[:space:]]*$/) next
      print stripped
    }
  '
}

final_has_scenario_specific_depth() {
  final_text=$1
  final_text_lower=$(printf '%s' "$final_text" | tr '[:upper:]' '[:lower:]')
  prompt_text=${2-}
  prompt_tokens=$(prompt_anchor_tokens_for_depth "$prompt_text")
  scenario_block=$(scenario_specific_block_lower "$final_text")
  non_template_body=$(scenario_non_template_body_lower "$final_text")
  token_total=0
  token_matches=0
  scenario_token_matches=0
  non_template_token_matches=0
  required_matches=1

  if [ -n "$(trim "$prompt_tokens")" ]; then
    while IFS= read -r token || [ -n "$token" ]; do
      token=$(trim "$token")
      [ -n "$token" ] || continue
      token_total=$((token_total + 1))
      if printf '%s' "$final_text_lower" | grep -Fq "$token"; then
        token_matches=$((token_matches + 1))
      fi
      if [ -n "$(trim "$scenario_block")" ] && printf '%s' "$scenario_block" | grep -Fq "$token"; then
        scenario_token_matches=$((scenario_token_matches + 1))
      fi
      if [ -n "$(trim "$non_template_body")" ] && printf '%s' "$non_template_body" | grep -Fq "$token"; then
        non_template_token_matches=$((non_template_token_matches + 1))
      fi
    done <<EOF
$prompt_tokens
EOF
  fi

  if [ "$token_total" -ge 4 ]; then
    required_matches=2
  fi

  has_context_anchor=0
  if printf '%s' "$final_text_lower" | grep -Eq 'context anchor:|domain anchor:'; then
    has_context_anchor=1
  fi

  has_scenario_block=0
  if [ -n "$(trim "$scenario_block")" ]; then
    has_scenario_block=1
  fi

  if [ "$has_context_anchor" -ne 1 ] || [ "$has_scenario_block" -ne 1 ]; then
    return 1
  fi

  has_scenario_specificity=0
  if printf '%s' "$scenario_block" | grep -Eq '(if[[:space:]]|when[[:space:]]|unless[[:space:]]|counterexample|invalidat|falsif|re-plan|pivot|rollback|fallback|disconfirm|decision window|review window|owner[^a-z0-9])'; then
    has_scenario_specificity=1
  fi
  if [ "$has_scenario_specificity" -ne 1 ]; then
    return 1
  fi

  if [ "$token_total" -le 0 ]; then
    return 0
  fi
  if [ "$token_matches" -lt "$required_matches" ]; then
    return 1
  fi
  if [ "$scenario_token_matches" -lt 1 ]; then
    return 1
  fi
  required_non_template_matches=1
  if [ "$token_total" -ge 6 ]; then
    required_non_template_matches=2
  fi
  if [ "$non_template_token_matches" -lt "$required_non_template_matches" ]; then
    return 1
  fi
  return 0
}

reasoning_domain_hint() {
  prompt_primary=$1
  prompt_primary=$(reasoning_prompt_anchor_source "$prompt_primary")
  prompt_text_lower=$(printf '%s' "$prompt_primary" | tr '[:upper:]' '[:lower:]')
  printf '%s\n' "$prompt_text_lower" | awk '
    function add(domain, points, strong_points) {
      score[domain] += points
      strong[domain] += strong_points
    }
    BEGIN {
      domain_count = 8
      domains[1] = "architecture"
      domains[2] = "forensics"
      domains[3] = "security/compliance"
      domains[4] = "product/ux"
      domains[5] = "metrics/causality"
      domains[6] = "incident response"
      domains[7] = "teaching"
      domains[8] = "strategy"

      priority["forensics"] = 1
      priority["metrics/causality"] = 2
      priority["architecture"] = 3
      priority["security/compliance"] = 4
      priority["product/ux"] = 5
      priority["teaching"] = 6
      priority["incident response"] = 7
      priority["strategy"] = 8
    }
    {
      if (length(text) > 0) {
        text = text " "
      }
      text = text $0
    }
    END {
      if (text ~ /architecture|event ingestion|partner-event|partner intake|shared ingestion|shared feed for partner events|shared partner-event path|shared intake lane|single event lane|queue topology|append-only|state machine|merchant-isolated|merchant isolated|merchant records can.t bleed|late and out of order|late arrivals|exact replays|tenant isolation|pci retention|retention timers differ by merchant|retention clocks differ by merchant|retention clocks|replays mix tenants|mix tenants|retention exceptions|smaller merchants/) add("architecture", 7, 2)
      if (text ~ /tenant|pipeline|replay|ingestion/) add("architecture", 3, 0)
      if (text ~ /merchant/ && text ~ /late and out of order/) add("architecture", 5, 1)
      if (text ~ /replay/ && (text ~ /tenant/ || text ~ /merchant/)) add("architecture", 4, 1)
      if ((text ~ /shared feed for partner events|shared feed/) && (text ~ /late and out of order|out-of-order replays|replays mix tenants|mix tenants/) && (text ~ /retention exceptions|retention exception|retention/) && (text ~ /smaller merchants|merchant/)) add("architecture", 8, 2)
      if (text ~ /shared ingestion/ && text ~ /finance|spend|cost/) add("architecture", 3, 0)

      if (text ~ /forensic|debug|root cause|stack trace|error trace|reconcil|replica divergence|replicas? disagree|deterministic repro|host clocks|different hosts|clock drift|clock skew|clock skews|drifting clocks|timeline|traces show|noisy warning stream|noisy logs?|disaster-recovery rehearsal|recovery rehearsal|rejoin|balance mismatches?|data mismatch|event order|node clocks did not agree|replica kept diverging|replica still diverges/) add("forensics", 6, 2)
      if ((text ~ /failover rehearsal|failover practice/) && (text ~ /timestamps/ || text ~ /host clocks/ || text ~ /different hosts/ || text ~ /clock drift|drifting clocks|node clocks did not agree|event order/)) add("forensics", 6, 1)
      if ((text ~ /failover practice/) && (text ~ /replica kept diverging|replica still diverges|one replica kept diverging/) && (text ~ /replay/ || text ~ /event order/ || text ~ /clock skew/)) add("forensics", 8, 2)
      if (text ~ /root cause|deterministic repro|timeline consistency/) add("forensics", 4, 1)

      if (text ~ /customer-managed keys|control evidence|boundary review|audit trail|analyst workflows|analyst access|emergency analyst access|emergency support bypass|attributable|region-bound|region bound|regional controls|residency|retention|exception path|deletion guarantees|who accessed what/) add("security/compliance", 6, 2)
      if (text ~ /security|compliance|policy|consent|legal|audit/) add("security/compliance", 3, 0)
      if (text ~ /analyst access/ && (text ~ /attributable/ || text ~ /region-bound|region bound|regional/)) add("security/compliance", 6, 1)
      if (text ~ /customer-managed keys/ && text ~ /analyst workflows/) add("security/compliance", 5, 1)

      if (text ~ /onboarding|ux|user flow|conversion|setup flow|workflow ergonomics|completion|honest-user completion|signup|page speed|support tickets|support volume|support load|support contacts|identity friction|fraud losses|fraud loss|fraud pressure|cohort|volatile latency|latency|trust gates|trust checks|review friction|permission wall|review gate|review queues|consent confirmation|consent-confirmation|consent checkpoints|manual review|document verification|document checks|document latency/) add("product/ux", 4, 1)
      if ((text ~ /visible review gate|review gate/) && (text ~ /consent confirmation|consent step/) && (text ~ /honest-user completion falls|honest user completion falls|completion falls|completion drops/) && (text ~ /something feels off|feels off/)) add("product/ux", 7, 2)
      if ((text ~ /visible review gate|review gate/) && (text ~ /consent confirmation|consent-confirmation/) && (text ~ /honest-user drop|honest user drop|honest-user completion/) && (text ~ /latency volatility|volatile latency|latency/)) add("product/ux", 8, 2)
      if ((text ~ /onboarding|signup/) && (text ~ /consent checks|trust checks|trust gates/) && (text ~ /latency|page speed/)) add("product/ux", 6, 2)
      if ((text ~ /visible review gate|trust wants a visible review gate/) && (text ~ /consent confirmation|consent step/) && (text ~ /honest-user completion falls|honest user completion falls|completion falls|completion drops/) && (text ~ /backend latency stays volatile|backend latency remains volatile|latency stays volatile|volatile latency/)) add("product/ux", 8, 2)
      if (text ~ /identity friction/ && (text ~ /fraud losses|fraud loss|support volume|support tickets/)) add("product/ux", 6, 1)
      if ((text ~ /signup|review friction|permission wall/) && (text ~ /consent confirmation|consent-confirmation|consent step|one more consent/) && (text ~ /review gate|visible review gate|trust says|trust wants|review queues/) && (text ~ /support tickets|support load|support contacts|abuse climbs|assisted cohorts/) && (text ~ /page latency|backend latency|latency swings|latency keeps swinging|document latency/)) add("product/ux", 6, 2)
      if ((text ~ /visible review gate/) && (text ~ /reduce abuse during signup|signup/) && (text ~ /consent confirmation/) && (text ~ /honest users|honest-user/) && (text ~ /review queues grow|review queues/) && (text ~ /backend latency keeps swinging|latency remains volatile|volatile latency|backend latency/)) add("product/ux", 8, 2)
      if ((text ~ /regulated signup|signup flow|strict review gate|permission wall/) && (text ~ /consent checkpoints|extra consent checkpoints|consent confirmation|consent-confirmation/) && (text ~ /manual review|trust queues grow|trust wants manual review|review queues lengthen|review queues/) && (text ~ /document checks spike latency|document verification latency|document latency/) && (text ~ /support volume|support contacts|support contact|support load/)) add("product/ux", 7, 2)
      if ((text ~ /strict consent-confirmation gate|regulated signup/) && (text ~ /honest-user completion drops|review staffing doubled/) && (text ~ /fraud pressure returned|review queues lengthen|document latency/)) add("product/ux", 8, 2)
      if ((text ~ /consent confirmation wall|consent-confirmation wall|consent wall/) && (text ~ /fraud/) && (text ~ /review queues lengthen|review queues/) && (text ~ /document latency/) && (text ~ /support contacts|support contact|support load|support volume/)) add("product/ux", 8, 2)

      if (text ~ /causal|metric|experiment|confound|counterfactual|uplift|chargeback|chargebacks|queue age|support queue age|ranking tweak|ranking shift|ranking change|ranking changes|activation|lagged harm|lagged harms|correlation|refunds?|trial starts?|call-center wait|cancellation pressure|cancellation calls|cancellation chats|revenue bump proves causality/) add("metrics/causality", 5, 1)
      if ((text ~ /trial starts up|trial starts jump|trial starts pop|trial starts/) && (text ~ /refunds later|refunds rise|refunds/) && (text ~ /queue age climbs|queue age/) && (text ~ /cohort retention weakens|cohort retention softens|retention weakens|retention softens/)) add("metrics/causality", 8, 2)
      if ((text ~ /ranking change|ranking changes/) && (text ~ /refunds?|chargebacks?|queue age|call-center wait/)) add("metrics/causality", 6, 2)
      if ((text ~ /ranking tweak|new ranking|ranking change/) && (text ~ /trial starts jump|trial starts pop/) && text ~ /refunds/ && (text ~ /support queue age|cancellation calls|cancellation chats/)) add("metrics/causality", 6, 2)
      if (text ~ /marketing wants to scale|proves causality/) add("metrics/causality", 4, 1)

      if (text ~ /incident|mitigation|outage|degradation|burn-rate|containment|flapping|oscillating|oscillation|flaring|vip complaints|executive accounts complain|rollback could overload|rollback would hit|rollback would hammer|rollback itself loads|rollback would stress|shared dependency|weakest dependency|first-hour|first hour|throttling a struggling service|throttling|rate limits|rate limiting|blast radius/) add("incident response", 4, 1)
      if ((text ~ /vip complaints|executive accounts complain/) && (text ~ /flapping|oscillating|flaring/)) add("incident response", 6, 2)
      if ((text ~ /vip complaints cluster|vip complaints/) && (text ~ /requests flap against rate limits|rate limits|rate limiting/) && (text ~ /rollback strains the weakest dependency|weakest dependency|rollback would stress/)) add("incident response", 9, 2)
      if (text ~ /rollback could overload|shared dependency/) add("incident response", 5, 1)
      if (text ~ /incident/ && text ~ /mitigation|containment/) add("incident response", 4, 1)
      if ((text ~ /status page stays calm|external messaging stays calm|first graph dips/) && text ~ /vip complaints/ && text ~ /one region|single region|region/ && text ~ /flap|flapping|rate limits|throttling/ && text ~ /rollback itself loads|rollback would stress|weakest dependency|shared dependency/) add("incident response", 7, 2)
      if (text ~ /vip complaints/ && text ~ /one region|single region|region/ && text ~ /oscillat|rate limits|rate limiting|flapping/ && text ~ /rollback itself would stress|rollback would stress|weakest dependency|shared dependency/) add("incident response", 8, 2)

      if (text ~ /teach|teaching|teacher|learner|misconception|lesson|curriculum|counterexample|near-miss|quiz|new hire insists|stop making that mistake|under real pressure|tokenized production snippets|tokenized production examples|paste into email|chat or email|direct identifiers are removed|names are gone|tokens are not names|raw secrets are removed|raw secrets removed|riskier samples|less careful samples/) add("teaching", 5, 1)
      if ((text ~ /teach|teaching/) && (text ~ /counterexample|near-miss|misconception/)) add("teaching", 6, 2)
      if ((text ~ /emailing tokenized production snippets/) && (text ~ /raw secrets are removed|raw secrets removed/)) add("teaching", 8, 2)
      if (text ~ /new hire insists/ && text ~ /tokenized|production samples/) add("teaching", 5, 1)

      if (text ~ /strategy|stakeholder|quarter|roadmap|finance wants|sales wants|operations goals|board wants|board still wants|margin|politically risky|political-risk|political exposure|politically unstable|growth|reliability budget|counsel warns|counsel flags|counsel says|sanctions exposure|next quarter|partner-heavy region|newly opened market|newly opened region|fast-growing region|enterprise signups|signups surge|signups spike|trial conversions jump|renewal cohorts weaken|renewal cohorts soften|renewals soften|renewals weaken/) add("strategy", 4, 1)
      if ((text ~ /fast-growing region|new region|pushing harder|lifted signups/) && text ~ /churn cohorts?/ && text ~ /reliability budget/ && text ~ /politically unstable|counsel flags|counsel says/) add("strategy", 6, 2)
      if ((text ~ /fast-growing region|newly opened region|newly opened market|pushing harder into/) && (text ~ /lifts signups|lifted signups|signups lift|signups lifted|signups surge|signups spike|signups jump/) && text ~ /renewals soften|renewals weaken|renewal cohorts soften|renewal cohorts weaken/ && text ~ /reliability budget|budget is tight|budget tightens|tight reliability budget/ && text ~ /sanctions exposure|counsel flags sanctions exposure|counsel warns sanctions exposure/) add("strategy", 8, 2)
      if ((text ~ /newly opened market|partner-heavy region/) && (text ~ /enterprise signups spike|trial conversions jump/) && text ~ /renewal cohorts weaken|renewal cohorts soften|renewals weaken/ && text ~ /reliability budget/ && text ~ /sanctions exposure/) add("strategy", 6, 2)
      if ((text ~ /newly opened region|fast-growing region/) && (text ~ /signups surge|signups spike|signups jump/) && text ~ /renewals soften|renewals weaken|renewal cohorts soften|renewal cohorts weaken/ && text ~ /reliability budget/ && text ~ /political exposure|politically risky|political-risk/) add("strategy", 7, 2)
      if (text ~ /board wants/ && text ~ /growth/ && text ~ /margin/) add("strategy", 6, 2)
      if (text ~ /reliability budget/ && text ~ /politically risky|political-risk|politically unstable|sanctions exposure/) add("strategy", 5, 1)

      best_domain = "cross-domain"
      best_score = 0
      best_strong = 0
      best_priority = 999
      second_score = 0
      second_strong = 0

      for (i = 1; i <= domain_count; i++) {
        domain = domains[i]
        current_score = score[domain] + 0
        current_strong = strong[domain] + 0
        current_priority = priority[domain] + 0
        if (current_score > best_score || (current_score == best_score && current_strong > best_strong) || (current_score == best_score && current_strong == best_strong && current_priority < best_priority && current_score > 0)) {
          second_score = best_score
          second_strong = best_strong
          best_domain = domain
          best_score = current_score
          best_strong = current_strong
          best_priority = current_priority
        } else if (current_score > second_score || (current_score == second_score && current_strong > second_strong)) {
          second_score = current_score
          second_strong = current_strong
        }
      }

      if (best_score < 5) {
        print "cross-domain"
        exit
      }
      if (best_score == second_score && best_strong == second_strong && best_score < 9) {
        print "cross-domain"
        exit
      }
      print best_domain
    }
  '
}

reasoning_domain_label_for_prompt() {
  domain_hint=$(reasoning_domain_hint "$1")
  case "$domain_hint" in
    architecture)
      printf '%s' "technical architecture"
      ;;
    forensics)
      printf '%s' "debugging/forensics with incomplete evidence"
      ;;
    security/compliance)
      printf '%s' "security + compliance + policy tradeoffs"
      ;;
    product/ux)
      printf '%s' "product/UX + technical constraints"
      ;;
    metrics/causality)
      printf '%s' "data/metrics causal reasoning"
      ;;
    incident\ response)
      printf '%s' "incident response under uncertainty"
      ;;
    teaching)
      printf '%s' "teaching/explanation under misconception pressure"
      ;;
    strategy)
      printf '%s' "strategic planning with conflicting stakeholder goals"
      ;;
    *)
      printf '%s' "cross-domain integrated reasoning"
      ;;
  esac
}

reasoning_outcome_stub_for_prompt() {
  prompt_text=$1
  scenario_ref=$(reasoning_scenario_reference_for_prompt "$prompt_text")
  anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  domain_label=$(reasoning_domain_label_for_prompt "$prompt_text")
  domain_article=$(reasoning_indefinite_article_for_phrase "$domain_label")
  if [ -n "$(trim "$anchor_phrase")" ] && [ "$scenario_ref" != "$anchor_phrase" ]; then
    printf 'Delivered %s %s decision synthesis for %s, grounded in %s.' "$domain_article" "$domain_label" "$scenario_ref" "$anchor_phrase"
    return 0
  fi
  printf 'Delivered %s %s decision synthesis for %s.' "$domain_article" "$domain_label" "$scenario_ref"
}

reasoning_decision_line_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf 'Selected the architecture that protects %s before latency/cost optimization.' "$anchor_phrase"
      ;;
    forensics)
      printf 'Selected the forensics path that tests %s in evidence order before root-cause claims.' "$anchor_phrase"
      ;;
    security/compliance)
      printf 'Selected the policy-safe plan that secures %s before workflow acceleration.' "$anchor_phrase"
      ;;
    product/ux)
      printf 'Selected the UX/system path that balances %s against abuse and support-risk growth.' "$anchor_phrase"
      ;;
    metrics/causality)
      printf 'Selected the causal path that stress-tests %s against confounds and counterfactuals.' "$anchor_phrase"
      ;;
    incident\ response)
      printf 'Selected the mitigation sequence that contains %s and minimizes user harm under uncertainty.' "$anchor_phrase"
      ;;
    teaching)
      printf 'Selected the explanation strategy that corrects misconceptions around %s before abstraction.' "$anchor_phrase"
      ;;
    strategy)
      printf 'Selected the staged strategy that makes speed-versus-risk tradeoffs explicit for %s.' "$anchor_phrase"
      ;;
    *)
      printf 'Selected a defensible primary path with explicit tradeoffs around %s.' "$anchor_phrase"
      ;;
  esac
}

reasoning_fallback_line_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf 'If %s signals drift out of bounds, switch to the lower-coupling architecture tier.' "$anchor_phrase"
      ;;
    forensics)
      printf 'If %s tests fail disconfirming checks, pivot to the next hypothesis and widen evidence capture.' "$anchor_phrase"
      ;;
    security/compliance)
      printf 'If %s controls show policy or audit drift, revert to segmented rollout with stricter boundaries.' "$anchor_phrase"
      ;;
    product/ux)
      printf 'If %s gains come with abuse/support overload, revert to a more gated onboarding path.' "$anchor_phrase"
      ;;
    metrics/causality)
      printf 'If %s uplift disappears under confound controls, revert to control policy and re-estimate causal effects.' "$anchor_phrase"
      ;;
    incident\ response)
      printf 'If mitigation around %s misses the burn-rate trigger window, execute rollback and containment immediately.' "$anchor_phrase"
      ;;
    teaching)
      printf 'If misconception checks for %s still fail, switch to counterexample-first instruction with smaller diagnostic steps.' "$anchor_phrase"
      ;;
    strategy)
      printf 'If margin, consent, or reliability thresholds tied to %s miss, shift to a phased plan prioritizing risk controls.' "$anchor_phrase"
      ;;
    *)
      printf 'If leading indicators tied to %s regress, switch to the lower-risk alternative path with smaller blast radius.' "$anchor_phrase"
      ;;
  esac
}

reasoning_disconfirming_line_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf 'Trigger a pivot if evidence around %s invalidates replay integrity, tenant isolation, or cost-per-transaction bounds.' "$anchor_phrase"
      ;;
    forensics)
      printf 'Trigger a pivot when evidence around %s fails deterministic repro or log-chain consistency checks.' "$anchor_phrase"
      ;;
    security/compliance)
      printf 'Trigger a pivot on policy violations, audit gaps, or scope creep tied to %s.' "$anchor_phrase"
      ;;
    product/ux)
      printf 'Trigger a pivot if %s improvements coincide with abuse or support burden crossing thresholds.' "$anchor_phrase"
      ;;
    metrics/causality)
      printf 'Trigger a pivot if %s uplift fails controlled experiments or counterfactual checks within confidence bounds.' "$anchor_phrase"
      ;;
    incident\ response)
      printf 'Trigger a pivot if user-impact or error-budget burn linked to %s fails to improve in the first mitigation window.' "$anchor_phrase"
      ;;
    teaching)
      printf 'Trigger a pivot if learners still fail contradiction checks after counterexamples on %s.' "$anchor_phrase"
      ;;
    strategy)
      printf 'Trigger a pivot if strategy indicators tied to %s cross pre-set margin, compliance-risk, or reliability thresholds.' "$anchor_phrase"
      ;;
    *)
      printf 'Trigger a pivot when evidence around %s invalidates a core assumption.' "$anchor_phrase"
      ;;
  esac
}

reasoning_freeform_recommendation_sentence_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_freeform_anchor_phrase_for_prompt "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf 'Use the lower-coupling architecture for %s rather than a single shared path.' "$anchor_phrase"
      ;;
    forensics)
      printf 'Treat %s as an evidence-order investigation, not a confirmed root cause.' "$anchor_phrase"
      ;;
    security/compliance)
      printf 'Take the policy-safe path for %s rather than expanding access or exceptions for speed.' "$anchor_phrase"
      ;;
    product/ux)
      printf 'Keep the more constrained product path for %s until the upside is proven without hidden harm.' "$anchor_phrase"
      ;;
    metrics/causality)
      printf 'Treat %s as a provisional signal, not a scale-up decision yet.' "$anchor_phrase"
      ;;
    incident\ response)
      printf 'Use the containment path for %s that cuts direct harm fastest, even if it looks less calm externally.' "$anchor_phrase"
      ;;
    teaching)
      printf 'Teach %s with a counterexample-first explanation rather than a fluent summary.' "$anchor_phrase"
      ;;
    strategy)
      printf 'Take the staged strategy for %s and make the sacrifice explicit now.' "$anchor_phrase"
      ;;
    *)
      printf 'Take the lower-risk path for %s until the uncertain parts are better evidenced.' "$anchor_phrase"
      ;;
  esac
}

reasoning_freeform_rationale_sentence_for_prompt() {
  prompt_text=$1
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf '%s' 'The simpler-looking option concentrates replay ordering, late-event recovery, and retention risk in one surface.'
      ;;
    forensics)
      printf '%s' 'The fastest narrative is not yet the best-supported explanation once timeline quality and deterministic repro are considered.'
      ;;
    security/compliance)
      printf '%s' 'The faster path leaves auditability, residency, or deletion guarantees too weak to defend later.'
      ;;
    product/ux)
      printf '%s' 'The cleaner-looking flow can improve completion while quietly pushing abuse, review load, or support costs upward.'
      ;;
    metrics/causality)
      printf '%s' 'The visible lift can still be partly confounded or offset by delayed harm in refunds, churn, or queue age.'
      ;;
    incident\ response)
      printf '%s' 'A calmer-looking option can still let concentrated user harm and blast radius persist.'
      ;;
    teaching)
      printf '%s' 'The learner can sound correct while still carrying the old rule into the first near miss.'
      ;;
    strategy)
      printf '%s' 'The superficially ambitious plan hides at least one delayed cost or veto constraint.'
      ;;
    *)
      printf '%s' 'The optimistic reading still hides at least one unclosed risk or alternative explanation.'
      ;;
  esac
}

reasoning_freeform_anchor_phrase_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_followup_scenario_reference_for_prompt "$prompt_text")
  anchor_phrase=$(trim "$anchor_phrase")
  anchor_phrase_lower=$(printf '%s' "$anchor_phrase" | tr '[:upper:]' '[:lower:]')
  if prompt_prefers_freeform_frame "$prompt_text" && printf '%s' "$anchor_phrase_lower" | grep -Eq '^(current picture:|current state:|status:|for context:|snapshot:|today:|what we know:)'; then
    anchor_phrase=""
  fi
  if [ -n "$anchor_phrase" ]; then
    printf '%s' "$anchor_phrase"
    return 0
  fi
  reasoning_prompt_anchor_phrase "$prompt_text"
}

reasoning_freeform_uncertainty_sentence_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_freeform_anchor_phrase_for_prompt "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf 'The main uncertainty is whether %s can stay correct under failover and replay stress without blowing the cost envelope.' "$anchor_phrase"
      ;;
    forensics)
      printf 'The main uncertainty is which hypothesis survives deterministic repro once the trace conflicts around %s are cleaned up.' "$anchor_phrase"
      ;;
    security/compliance)
      printf 'The main uncertainty is how much operational friction remains once the tighter control path for %s is implemented correctly.' "$anchor_phrase"
      ;;
    product/ux)
      printf 'The main uncertainty is whether the current friction around %s is buying real risk reduction or only delaying honest users.' "$anchor_phrase"
      ;;
    metrics/causality)
      printf 'The main uncertainty is how much of the observed effect around %s survives lagged-outcome checks and cleaner controls.' "$anchor_phrase"
      ;;
    incident\ response)
      printf 'The main uncertainty is whether the chosen mitigation for %s actually reduces concentrated harm before the next burn window.' "$anchor_phrase"
      ;;
    teaching)
      printf 'The main uncertainty is whether the explanation for %s transfers once the wording changes and the boundary case arrives.' "$anchor_phrase"
      ;;
    strategy)
      printf 'The main uncertainty is how much upside for %s survives once the most likely stakeholder veto and delayed downside are priced in.' "$anchor_phrase"
      ;;
    *)
      printf 'The main uncertainty is whether the leading explanation for %s survives the next direct disconfirming check.' "$anchor_phrase"
      ;;
  esac
}

reasoning_freeform_reversal_sentence_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_freeform_anchor_phrase_for_prompt "$prompt_text")
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf 'I would reverse this only if replay drills show %s can preserve merchant boundaries, retention rules, and recovery behavior without breaching the cost ceiling.' "$anchor_phrase"
      ;;
    forensics)
      printf 'I would reverse this only if a competing hypothesis gains cleaner timeline, reproduction, and log-chain support than the current lead for %s.' "$anchor_phrase"
      ;;
    security/compliance)
      printf 'I would reverse this only if attributable logs, residency boundaries, and deletion or retention proofs stay intact while the faster path still meets the target for %s.' "$anchor_phrase"
      ;;
    product/ux)
      printf 'I would reverse this only if cohort data shows %s improves while abuse, support volume, and latency all stay inside guardrails.' "$anchor_phrase"
      ;;
    metrics/causality)
      printf 'I would reverse this only if controlled or same-cohort checks keep the upside for %s while downstream harm signals stay bounded.' "$anchor_phrase"
      ;;
    incident\ response)
      printf 'I would reverse this only if the current path for %s fails to improve harm or burn-rate signals in the first mitigation window and the fallback materially reduces exposure.' "$anchor_phrase"
      ;;
    teaching)
      printf 'I would reverse this only if the learner can handle the near miss for %s and restate the corrected rule without leaning on memorized phrasing.' "$anchor_phrase"
      ;;
    strategy)
      printf 'I would reverse this only if the faster plan for %s clears margin, compliance, and reliability thresholds without borrowing risk into a later quarter.' "$anchor_phrase"
      ;;
    *)
      printf 'I would reverse this only if the next direct evidence check invalidates the current recommendation for %s.' "$anchor_phrase"
      ;;
  esac
}

reasoning_freeform_delta_sentence_for_prompt() {
  prompt_text=$1
  if ! printf '%s\n' "$prompt_text" | grep -Eq '^Updated conditions:$'; then
    return 0
  fi
  followup_delta=$(reasoning_freeform_followup_delta_for_prompt "$prompt_text")
  [ -n "$(trim "$followup_delta")" ] || return 0
  anchor_phrase=$(reasoning_followup_scenario_reference_for_prompt "$prompt_text")
  if [ -z "$(trim "$anchor_phrase")" ]; then
    anchor_phrase=$(reasoning_prompt_anchor_phrase "$prompt_text")
  fi
  printf 'Given the updated conditions for %s, especially %s, the revised recommendation should be read against that new evidence rather than the first-pass intuition.' "$anchor_phrase" "$followup_delta"
}

reasoning_freeform_memo_for_prompt() {
  prompt_text=$1
  recommendation=$(reasoning_freeform_recommendation_sentence_for_prompt "$prompt_text")
  rationale=$(reasoning_freeform_rationale_sentence_for_prompt "$prompt_text")
  delta_sentence=$(reasoning_freeform_delta_sentence_for_prompt "$prompt_text")
  uncertainty=$(reasoning_freeform_uncertainty_sentence_for_prompt "$prompt_text")
  reversal=$(reasoning_freeform_reversal_sentence_for_prompt "$prompt_text")
  if [ -n "$(trim "$delta_sentence")" ]; then
    printf '%s %s %s %s %s' "$recommendation" "$rationale" "$delta_sentence" "$uncertainty" "$reversal"
    return 0
  fi
  printf '%s %s %s %s' "$recommendation" "$rationale" "$uncertainty" "$reversal"
}

reasoning_freeform_reflection_opening_sentence_for_prompt() {
  prompt_text=$1
  anchor_phrase=$(reasoning_freeform_anchor_phrase_for_prompt "$prompt_text")
  printf 'This looks less settled than it first appears for %s.' "$anchor_phrase"
}

reasoning_freeform_reflection_tension_sentence_for_prompt() {
  prompt_text=$1
  domain_hint=$(reasoning_domain_hint "$prompt_text")
  case "$domain_hint" in
    architecture)
      printf '%s' 'The tension is that the simpler-looking shape concentrates replay ordering, late-event recovery, and retention risk in one surface.'
      ;;
    forensics)
      printf '%s' 'The tension is that the cleanest first story can still be the least reliable once timeline quality and deterministic repro are tested.'
      ;;
    security/compliance)
      printf '%s' 'The tension is that the faster-looking path weakens auditability, residency, or deletion guarantees exactly where later scrutiny will land.'
      ;;
    product/ux)
      printf '%s' 'The tension is that the smoother-looking flow can improve visible completion while quietly moving cost into abuse, review load, or support burden.'
      ;;
    metrics/causality)
      printf '%s' 'The tension is that the visible lift can still be partly confounded or offset by delayed harm that arrives after the headline metric.'
      ;;
    incident\ response)
      printf '%s' 'The tension is that the calmer-looking move can still leave concentrated harm and blast radius untouched during the next burn window.'
      ;;
    teaching)
      printf '%s' 'The tension is that the material can feel anonymized and still teach the wrong lesson once the first near miss shows up.'
      ;;
    strategy)
      printf '%s' 'The tension is that the ambitious-looking upside is arriving alongside at least one delayed veto, cost, or reliability constraint.'
      ;;
    *)
      printf '%s' 'The tension is that the first clean story still hides at least one unclosed risk or alternative explanation.'
      ;;
  esac
}

reasoning_freeform_reflection_unresolved_sentence_for_prompt() {
