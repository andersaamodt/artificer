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

