            fileBadges.push("trigger.yaml");
          }
          if (skill.files.tools_json) {
            fileBadges.push("tools.json");
          }
          if (skill.files.output_schema_json) {
            fileBadges.push("output.schema.json");
          }
        }
        skillsHtml += "<p class='settings-hint'>capabilities: " + escHtml(caps.join(", ") || "none") + " | stateless actuator | interrupt authority: " + (skill.interrupt_authority ? "yes" : "no") + "</p>";
        if (fileBadges.length) {
          skillsHtml += "<p class='settings-hint'>bundle files: " + escHtml(fileBadges.join(", ")) + "</p>";
        }
        skillsHtml += "<div class='mode-runtime-actions'><button type='button' data-action='mode-runtime-skill-quick' data-skill-id='" + escAttr(skill.id || "") + "'>Use skill</button></div>";
        skillsHtml += "</article>";
      }
      skillsHtml += "</section>";
    }
    el.modeRuntimeSkills.innerHTML = skillsHtml;

    if (el.modeRuntimeFailureTaxonomy) {
      var taxonomy = runtime.failure_taxonomy && typeof runtime.failure_taxonomy === "object" ? runtime.failure_taxonomy : {};
      var taxonomyCategories = Array.isArray(taxonomy.categories) ? taxonomy.categories : [];
      var taxonomyRecent = Array.isArray(taxonomy.recent) ? taxonomy.recent : [];
      var taxonomyQueryState = state.modeRuntimeTaxonomyQuery && typeof state.modeRuntimeTaxonomyQuery === "object"
        ? state.modeRuntimeTaxonomyQuery
        : {};
      var taxonomyQueryFilters = normalizeModeRuntimeTaxonomyQueryFilters(taxonomyQueryState.filters || defaultModeRuntimeTaxonomyQueryFilters());
      var taxonomyQueryEvents = Array.isArray(taxonomyQueryState.events) ? taxonomyQueryState.events : [];
      var taxonomyQueryHasQueried = taxonomyQueryState.hasQueried === true;
      var taxonomyQueryLoading = taxonomyQueryState.loading === true;
      var taxonomyQueryError = trim(String(taxonomyQueryState.error || ""));
      var taxonomyQueryMatched = trim(String(taxonomyQueryState.matched_total || "0"));
      var taxonomyQueryReturned = trim(String(taxonomyQueryState.returned || "0"));
      var taxonomyQueryDisplayEvents = taxonomyQueryHasQueried ? taxonomyQueryEvents : taxonomyRecent;
      var taxonomySurfaceMap = {};
      for (var ts = 0; ts < taxonomyCategories.length; ts += 1) {
        var surfaceValue = trim(String((taxonomyCategories[ts] && taxonomyCategories[ts].surface) || "")).toLowerCase();
        if (!surfaceValue) {
          continue;
        }
        taxonomySurfaceMap[surfaceValue] = true;
      }
      var taxonomySurfaceOptions = Object.keys(taxonomySurfaceMap).sort();
      var taxonomyHtml = "";
      taxonomyHtml += "<section class='mode-runtime-group'>";
      taxonomyHtml += "<div class='mode-runtime-group-head'><p class='command-rules-group-title'>Failure taxonomy</p></div>";
      taxonomyHtml += "<p class='settings-hint'>File-backed failure memory used to identify recurring breakdowns and improve planning behavior over time.</p>";
      taxonomyHtml += "<div class='mode-runtime-metrics'>";
      taxonomyHtml += "<span class='mode-runtime-metric'><em>Total failures</em><strong>" + escHtml(String(taxonomy.total || "0")) + "</strong></span>";
      taxonomyHtml += "<span class='mode-runtime-metric'><em>Last recorded</em><strong>" + escHtml(String(taxonomy.last_recorded_at || "n/a")) + "</strong></span>";
      taxonomyHtml += "</div>";
      if (!taxonomyCategories.length) {
        taxonomyHtml += "<p class='empty-state'>No failure taxonomy entries yet.</p>";
      } else {
        taxonomyHtml += "<div class='mode-runtime-taxonomy-list'>";
        for (var t = 0; t < taxonomyCategories.length && t < 10; t += 1) {
          var category = taxonomyCategories[t] || {};
          taxonomyHtml += "<article class='mode-runtime-taxonomy-row'>";
          taxonomyHtml += "<div class='mode-runtime-taxonomy-head'><strong>" + escHtml(category.label || category.id || "Category") + "</strong><span class='mode-runtime-chip'>" + escHtml(String(category.count || "0")) + "</span></div>";
          taxonomyHtml += "<p class='settings-hint'>surface: " + escHtml(String(category.surface || "unknown")) + " | severity: " + escHtml(String(category.severity || "unknown")) + "</p>";
          if (category.last_seen) {
            taxonomyHtml += "<p class='settings-hint'>last seen: " + escHtml(String(category.last_seen || "")) + "</p>";
          }
          taxonomyHtml += "</article>";
        }
        taxonomyHtml += "</div>";
      }
      taxonomyHtml += "<div class='mode-runtime-taxonomy-query-controls'>";
      taxonomyHtml += "<p class='settings-hint'><strong>Query taxonomy</strong> for targeted failure patterns.</p>";
      taxonomyHtml += "<div class='mode-runtime-taxonomy-query-grid'>";
      taxonomyHtml += "<input data-role='mode-runtime-taxonomy-category' placeholder='category id (optional)' value='" + escAttr(String(taxonomyQueryFilters.category || "")) + "' />";
      taxonomyHtml += "<select data-role='mode-runtime-taxonomy-severity'>";
      taxonomyHtml += "<option value='' " + (taxonomyQueryFilters.severity ? "" : "selected") + ">all severities</option>";
      taxonomyHtml += "<option value='low' " + (taxonomyQueryFilters.severity === "low" ? "selected" : "") + ">low</option>";
      taxonomyHtml += "<option value='medium' " + (taxonomyQueryFilters.severity === "medium" ? "selected" : "") + ">medium</option>";
      taxonomyHtml += "<option value='high' " + (taxonomyQueryFilters.severity === "high" ? "selected" : "") + ">high</option>";
      taxonomyHtml += "</select>";
      taxonomyHtml += "<select data-role='mode-runtime-taxonomy-surface'>";
      taxonomyHtml += "<option value='' " + (taxonomyQueryFilters.surface ? "" : "selected") + ">all surfaces</option>";
      for (var tso = 0; tso < taxonomySurfaceOptions.length; tso += 1) {
        var surfaceOption = String(taxonomySurfaceOptions[tso] || "");
        if (!surfaceOption) {
          continue;
        }
        taxonomyHtml += "<option value='" + escAttr(surfaceOption) + "' " + (taxonomyQueryFilters.surface === surfaceOption ? "selected" : "") + ">" + escHtml(surfaceOption) + "</option>";
      }
      taxonomyHtml += "</select>";
      taxonomyHtml += "<input data-role='mode-runtime-taxonomy-mode' placeholder='mode id (optional)' value='" + escAttr(String(taxonomyQueryFilters.mode || "")) + "' />";
      taxonomyHtml += "<input data-role='mode-runtime-taxonomy-since-epoch' inputmode='numeric' placeholder='since epoch' value='" + escAttr(String(taxonomyQueryFilters.since_epoch || "0")) + "' />";
      taxonomyHtml += "<select data-role='mode-runtime-taxonomy-limit'>";
      taxonomyHtml += "<option value='12' " + (taxonomyQueryFilters.limit === "12" ? "selected" : "") + ">12 rows</option>";
      taxonomyHtml += "<option value='25' " + (taxonomyQueryFilters.limit === "25" ? "selected" : "") + ">25 rows</option>";
      taxonomyHtml += "<option value='50' " + (taxonomyQueryFilters.limit === "50" ? "selected" : "") + ">50 rows</option>";
      taxonomyHtml += "<option value='100' " + (taxonomyQueryFilters.limit === "100" ? "selected" : "") + ">100 rows</option>";
      taxonomyHtml += "</select>";
      taxonomyHtml += "<div class='mode-runtime-actions'>";
      taxonomyHtml += "<button type='button' data-action='mode-runtime-taxonomy-query'>Run query</button>";
      taxonomyHtml += "<button type='button' class='ghost' data-action='mode-runtime-taxonomy-query-reset'>Reset</button>";
      taxonomyHtml += "</div>";
      taxonomyHtml += "</div>";
      taxonomyHtml += "</div>";
      if (taxonomyQueryLoading) {
        taxonomyHtml += "<p class='settings-hint'>Querying failure taxonomy...</p>";
      }
      if (taxonomyQueryError) {
        taxonomyHtml += "<p class='settings-hint mode-runtime-query-error'>" + escHtml(taxonomyQueryError) + "</p>";
      }
      if (taxonomyQueryHasQueried && !taxonomyQueryLoading) {
        taxonomyHtml += "<p class='settings-hint'>Filtered result: matched " + escHtml(taxonomyQueryMatched || "0") + ", returned " + escHtml(taxonomyQueryReturned || "0") + ".</p>";
      }
      if (taxonomyQueryDisplayEvents.length) {
        taxonomyHtml += "<details class='mode-runtime-taxonomy-recent'><summary>" + (taxonomyQueryHasQueried ? "Filtered failure events" : "Recent failure events") + "</summary><div class='mode-runtime-directive-list'>";
        for (var tr = 0; tr < taxonomyQueryDisplayEvents.length && tr < 12; tr += 1) {
          var recentEvent = taxonomyQueryDisplayEvents[tr] || {};
          var recentPrefix = trim(String(recentEvent.category_label || recentEvent.category || "failure"));
          taxonomyHtml += "<p class='settings-hint mode-runtime-directive-item'><strong>" + escHtml(recentPrefix) + "</strong>: " + escHtml(String(recentEvent.error || recentEvent.action || "event"));
          if (recentEvent.timestamp) {
            taxonomyHtml += " <span class='mode-runtime-directive-time'>" + escHtml(String(recentEvent.timestamp || "")) + "</span>";
          }
          taxonomyHtml += "</p>";
        }
        taxonomyHtml += "</div></details>";
      }
      taxonomyHtml += "</section>";
      el.modeRuntimeFailureTaxonomy.innerHTML = taxonomyHtml;
    }

    if (el.modeRuntimeImprovementProposals) {
      var proposalState = runtime.improvement_proposals && typeof runtime.improvement_proposals === "object" ? runtime.improvement_proposals : {};
      var proposalCounts = proposalState.counts && typeof proposalState.counts === "object" ? proposalState.counts : {};
      var proposalItems = Array.isArray(proposalState.items) ? proposalState.items : [];
      var proposalHtml = "";
      proposalHtml += "<section class='mode-runtime-group'>";
      proposalHtml += "<div class='mode-runtime-group-head'><p class='command-rules-group-title'>Improvement proposals</p><button type='button' data-action='mode-runtime-proposal-generate'>Generate from failures</button></div>";
      proposalHtml += "<p class='settings-hint'>Contained self-improvement: proposals are generated from failure patterns but only changed when manually reviewed.</p>";
      proposalHtml += "<div class='mode-runtime-metrics'>";
      proposalHtml += "<span class='mode-runtime-metric'><em>Proposed</em><strong>" + escHtml(String(proposalCounts.proposed || "0")) + "</strong></span>";
      proposalHtml += "<span class='mode-runtime-metric'><em>Accepted</em><strong>" + escHtml(String(proposalCounts.accepted || "0")) + "</strong></span>";
      proposalHtml += "<span class='mode-runtime-metric'><em>Applied</em><strong>" + escHtml(String(proposalCounts.applied || "0")) + "</strong></span>";
      proposalHtml += "<span class='mode-runtime-metric'><em>Rejected</em><strong>" + escHtml(String(proposalCounts.rejected || "0")) + "</strong></span>";
      proposalHtml += "</div>";
      if (!proposalItems.length) {
        proposalHtml += "<p class='empty-state'>No improvement proposals yet.</p>";
      } else {
        proposalHtml += "<div class='mode-runtime-proposal-list'>";
        for (var p = 0; p < proposalItems.length && p < 14; p += 1) {
          var proposal = proposalItems[p] || {};
          var proposalStatus = trim(String(proposal.status || "proposed")).toLowerCase();
          var proposalSourceSummary = "source: " + String(proposal.source || "manual");
          if (proposal.source_mode) {
            proposalSourceSummary += " (" + String(proposal.source_mode) + " mode)";
          }
          proposalHtml += "<article class='mode-runtime-proposal-item'>";
          proposalHtml += "<div class='mode-runtime-mode-head'><strong>" + escHtml(proposal.title || proposal.id || "Proposal") + "</strong><span class='mode-runtime-chip'>" + escHtml(proposalStatus) + "</span></div>";
          proposalHtml += "<p class='settings-hint'>scope: " + escHtml(String(proposal.scope || "other")) + " | risk: " + escHtml(String(proposal.risk_level || "medium")) + " | " + escHtml(proposalSourceSummary) + "</p>";
          if (proposal.taxonomy_category_label) {
            proposalHtml += "<p class='settings-hint'>taxonomy: " + escHtml(String(proposal.taxonomy_category_label || proposal.taxonomy_category || "")) + "</p>";
          }
          if (proposal.rationale) {
            proposalHtml += "<p class='settings-hint'><strong>Rationale:</strong> " + escHtml(String(proposal.rationale || "")) + "</p>";
          }
          if (proposal.proposed_change) {
            proposalHtml += "<p class='settings-hint'><strong>Change:</strong> " + escHtml(String(proposal.proposed_change || "")) + "</p>";
          }
          if (proposal.created_at) {
            proposalHtml += "<p class='settings-hint'>created: " + escHtml(String(proposal.created_at || "")) + "</p>";
          }
          if (proposalStatus === "proposed" || proposalStatus === "accepted") {
            proposalHtml += "<div class='mode-runtime-actions'>";
            if (proposalStatus === "proposed") {
              proposalHtml += "<button type='button' data-action='mode-runtime-proposal-decision' data-proposal-id='" + escAttr(proposal.id || "") + "' data-decision='accept'>Accept</button>";
            }
            proposalHtml += "<button type='button' data-action='mode-runtime-proposal-decision' data-proposal-id='" + escAttr(proposal.id || "") + "' data-decision='apply'>Apply</button>";
            proposalHtml += "<button type='button' class='ghost' data-action='mode-runtime-proposal-decision' data-proposal-id='" + escAttr(proposal.id || "") + "' data-decision='reject'>Reject</button>";
            proposalHtml += "</div>";
          }
          proposalHtml += "</article>";
        }
        proposalHtml += "</div>";
      }
      if (proposalState.manual_apply_only !== false) {
        proposalHtml += "<p class='settings-hint'>Safety guard: applying a proposal updates proposal state only; it does not autonomously rewrite pipelines.</p>";
      }
      proposalHtml += "</section>";
      el.modeRuntimeImprovementProposals.innerHTML = proposalHtml;
    }

    if (el.modeRuntimeControllerVariants) {
      var controllerVariantsState = runtime.controller_variants && typeof runtime.controller_variants === "object"
        ? runtime.controller_variants
        : {};
      var compare = controllerVariantsState.quality_compare && typeof controllerVariantsState.quality_compare === "object"
        ? controllerVariantsState.quality_compare
        : {};
      var variants = Array.isArray(controllerVariantsState.items) ? controllerVariantsState.items : [];
      var variantsHtml = "";
      variantsHtml += "<section class='mode-runtime-group'>";
      variantsHtml += "<div class='mode-runtime-group-head'><p class='command-rules-group-title'>Controller variants</p></div>";
      variantsHtml += "<p class='settings-hint'>Versioned controller prompt variants with guarded A/B sampling and manual promote/rollback.</p>";
      variantsHtml += "<div class='mode-runtime-metrics'>";
      variantsHtml += "<span class='mode-runtime-metric'><em>Active</em><strong>" + escHtml(String(controllerVariantsState.active_variant_id || "none")) + "</strong></span>";
      variantsHtml += "<span class='mode-runtime-metric'><em>Sample rate</em><strong>" + escHtml(String(controllerVariantsState.sample_rate_percent || "0")) + "%</strong></span>";
      variantsHtml += "<span class='mode-runtime-metric'><em>Max candidate samples</em><strong>" + escHtml(String(controllerVariantsState.max_sample_size || "0")) + "</strong></span>";
      variantsHtml += "</div>";
      if (compare && (compare.active_id || compare.candidate_id)) {
        variantsHtml += "<p class='settings-hint'>Compare: active " + escHtml(String(compare.active_id || "none")) + " (" + escHtml(String(compare.active_avg_quality || "0.000")) + ", n=" + escHtml(String(compare.active_runs || "0")) + ")";
        variantsHtml += " vs candidate " + escHtml(String(compare.candidate_id || "none")) + " (" + escHtml(String(compare.candidate_avg_quality || "0.000")) + ", n=" + escHtml(String(compare.candidate_runs || "0")) + ")";
        variantsHtml += " | delta " + escHtml(String(compare.quality_delta || "0.000"));
        if (compare.recommendation) {
          variantsHtml += " | recommendation: " + escHtml(String(compare.recommendation || ""));
        }
        variantsHtml += "</p>";
      }
      if (compare && compare.candidate_id) {
        variantsHtml += "<div class='mode-runtime-actions'>";
        variantsHtml += "<button type='button' data-action='mode-runtime-controller-promote' data-variant-id='" + escAttr(String(compare.candidate_id || "")) + "'>Promote candidate</button>";
        variantsHtml += "<button type='button' class='ghost' data-action='mode-runtime-controller-rollback'>Rollback active</button>";
        variantsHtml += "</div>";
      } else {
        variantsHtml += "<p class='settings-hint'>No candidate variant is queued right now. Accept/apply proposals to mint new candidates.</p>";
      }
      if (!variants.length) {
        variantsHtml += "<p class='empty-state'>No controller variants found.</p>";
      } else {
        variantsHtml += "<div class='mode-runtime-proposal-list'>";
        for (var cv = 0; cv < variants.length && cv < 12; cv += 1) {
          var variant = variants[cv] || {};
          var variantId = trim(String(variant.id || ""));
          if (!variantId) {
            continue;
          }
          variantsHtml += "<article class='mode-runtime-proposal-item'>";
          variantsHtml += "<div class='mode-runtime-mode-head'><strong>" + escHtml(String(variant.name || variantId)) + "</strong><span class='mode-runtime-chip'>" + escHtml(String(variant.status || "standby")) + "</span></div>";
          variantsHtml += "<p class='settings-hint'>id: " + escHtml(variantId) + " | kind: " + escHtml(String(variant.kind || "manual")) + " | scope: " + escHtml(String(variant.scope || "other")) + " | risk: " + escHtml(String(variant.risk_level || "medium")) + "</p>";
          variantsHtml += "<p class='settings-hint'>quality " + escHtml(String(variant.avg_quality || "0.000")) + " | success " + escHtml(String(variant.success_rate_pct || "0.0")) + "% | runs " + escHtml(String(variant.runs || "0")) + "</p>";
          if (variant.source_proposal) {
            variantsHtml += "<p class='settings-hint'>source proposal: " + escHtml(String(variant.source_proposal || "")) + "</p>";
          }
          if (variant.instructions) {
            variantsHtml += "<p class='settings-hint'><strong>Guidance:</strong> " + escHtml(String(variant.instructions || "")) + "</p>";
          }
          if (variant.status !== "active") {
            variantsHtml += "<div class='mode-runtime-actions'><button type='button' data-action='mode-runtime-controller-promote' data-variant-id='" + escAttr(variantId) + "'>Promote</button></div>";
          }
          variantsHtml += "</article>";
        }
        variantsHtml += "</div>";
      }
      variantsHtml += "</section>";
      el.modeRuntimeControllerVariants.innerHTML = variantsHtml;
    }

    if (el.modeRuntimeQualityScorecard) {
      var scorecard = runtime.quality_scorecard && typeof runtime.quality_scorecard === "object"
        ? runtime.quality_scorecard
        : {};
      var scorecardRecent = Array.isArray(scorecard.recent) ? scorecard.recent : [];
      var scorecardHtml = "";
      scorecardHtml += "<section class='mode-runtime-group'>";
      scorecardHtml += "<div class='mode-runtime-group-head'><p class='command-rules-group-title'>Intelligence quality scorecard</p></div>";
      scorecardHtml += "<p class='settings-hint'>Tracks run-quality deltas over time and can raise improvement proposals when regressions appear.</p>";
      scorecardHtml += "<div class='mode-runtime-metrics'>";
      scorecardHtml += "<span class='mode-runtime-metric'><em>Total scored runs</em><strong>" + escHtml(String(scorecard.total_runs || "0")) + "</strong></span>";
      scorecardHtml += "<span class='mode-runtime-metric'><em>Overall avg</em><strong>" + escHtml(String(scorecard.overall_avg_quality || "0.000")) + "</strong></span>";
      scorecardHtml += "<span class='mode-runtime-metric'><em>Last updated</em><strong>" + escHtml(String(scorecard.last_updated || "n/a")) + "</strong></span>";
      scorecardHtml += "</div>";
      if (scorecard.scorecard_path) {
        scorecardHtml += "<p class='settings-hint'>Scorecard file: " + escHtml(String(scorecard.scorecard_path || "")) + "</p>";
      }
      if (!scorecardRecent.length) {
        scorecardHtml += "<p class='empty-state'>No quality-scorecard entries yet.</p>";
      } else {
        scorecardHtml += "<div class='mode-runtime-proposal-list'>";
        for (var qs = 0; qs < scorecardRecent.length && qs < 8; qs += 1) {
          var scoreEntry = scorecardRecent[qs] || {};
          scorecardHtml += "<article class='mode-runtime-proposal-item'>";
          scorecardHtml += "<div class='mode-runtime-mode-head'><strong>" + escHtml(String(scoreEntry.run_mode || "run")) + "</strong><span class='mode-runtime-chip'>" + escHtml(String(scoreEntry.quality_score || "0.000")) + "</span></div>";
          scorecardHtml += "<p class='settings-hint'>delta: " + escHtml(String(scoreEntry.delta_score || "0.000")) + " | status: " + escHtml(String(scoreEntry.queue_status || "unknown")) + "/" + escHtml(String(scoreEntry.final_state || "unknown")) + " | variant: " + escHtml(String(scoreEntry.variant_id || "n/a")) + "</p>";
          scorecardHtml += "<p class='settings-hint'>iterations: " + escHtml(String(scoreEntry.iteration_count || "0")) + " | failures: " + escHtml(String(scoreEntry.failure_count || "0")) + " | elapsed: " + escHtml(String(scoreEntry.run_elapsed_sec || "0")) + "s</p>";
          if (scoreEntry.timestamp) {
            scorecardHtml += "<p class='settings-hint'>timestamp: " + escHtml(String(scoreEntry.timestamp || "")) + "</p>";
          }
          scorecardHtml += "</article>";
        }
        scorecardHtml += "</div>";
      }
      el.modeRuntimeQualityScorecard.innerHTML = scorecardHtml;
    }

    if (el.assistantModeSelect) {
      var assistantValue = normalizeAssistantModeId(state.assistantModeId);
      var assistantOptions = "<option value=''>General Team</option>";
      for (var a = 0; a < modes.length; a += 1) {
        var modeOption = modes[a] || {};
        var optionId = trim(String(modeOption.id || ""));
        if (!optionId) {
          continue;
        }
        assistantOptions += "<option value='" + escAttr(optionId) + "'>" + escHtml(modeOption.name || optionId) + "</option>";
      }
      if (el.assistantModeSelect.innerHTML !== assistantOptions) {
        el.assistantModeSelect.innerHTML = assistantOptions;
      }
      el.assistantModeSelect.value = assistantValue;
      if (el.assistantModeSelect.value !== assistantValue) {
        el.assistantModeSelect.value = "";
      }
    }

    if (el.modeRuntimeSkillMode) {
      var modeSelectOptions = "<option value='assistant'>team (manual)</option>";
      for (var b = 0; b < modes.length; b += 1) {
        var modeEntry = modes[b] || {};
        var modeEntryId = trim(String(modeEntry.id || ""));
        if (!modeEntryId) {
          continue;
        }
        modeSelectOptions += "<option value='" + escAttr(modeEntryId) + "'>" + escHtml(modeEntry.name || modeEntryId) + "</option>";
      }
      if (el.modeRuntimeSkillMode.innerHTML !== modeSelectOptions) {
        el.modeRuntimeSkillMode.innerHTML = modeSelectOptions;
      }
      var hasModeSelection = false;
      for (var bm = 0; bm < el.modeRuntimeSkillMode.options.length; bm += 1) {
        if (String(el.modeRuntimeSkillMode.options[bm].value || "") === String(el.modeRuntimeSkillMode.value || "")) {
          hasModeSelection = true;
          break;
        }
      }
      if (!hasModeSelection) {
        el.modeRuntimeSkillMode.value = "assistant";
      }
    }

    if (el.modeRuntimeSkillSelect) {
      var skillOptions = "<option value=''>Select skill</option>";
      for (var c = 0; c < skills.length; c += 1) {
        var skillOption = skills[c] || {};
        var skillOptionId = trim(String(skillOption.id || ""));
        if (!skillOptionId) {
          continue;
        }
        skillOptions += "<option value='" + escAttr(skillOptionId) + "'>" + escHtml(skillOption.name || skillOptionId) + "</option>";
      }
      if (el.modeRuntimeSkillSelect.innerHTML !== skillOptions) {
        el.modeRuntimeSkillSelect.innerHTML = skillOptions;
      }
      var hasSkillSelection = false;
      for (var cs = 0; cs < el.modeRuntimeSkillSelect.options.length; cs += 1) {
        if (String(el.modeRuntimeSkillSelect.options[cs].value || "") === String(el.modeRuntimeSkillSelect.value || "")) {
          hasSkillSelection = true;
          break;
        }
      }
      if (!hasSkillSelection && skills.length) {
        el.modeRuntimeSkillSelect.value = String((skills[0] && skills[0].id) || "");
      }
    }
  }

  function openSettingsModal() {
    openModal(el.settingsModal);
    state.dictationInstallReady = false;
    state.dictationInstallCancelling = false;
    state.dictationInstallPendingCancel = false;
    state.dictationInstallCancelJobId = "";
    state.dictationInstallError = "";
    state.automationDaemon.error = "";
    state.automationDaemon.lastTickMessage = "";
    var preferredWorkspace = String(state.commandRulesWorkspaceId || state.activeWorkspaceId || "");
    if (!preferredWorkspace && state.workspaces.length) {
      preferredWorkspace = firstWorkspaceId(true);
    }
    state.commandRulesWorkspaceId = preferredWorkspace;
    renderCommandRulesSettings();
    renderAutomationDaemonSettings();
    renderDictationInstallSettings();
    renderProgrammingSettings();
    var dictationBootstrap = Promise.all([
      loadAuthStatus().catch(function () {
        return null;
      }),
      loadDictationPrewarmSetting().catch(function () {
        return null;
      }),
      loadDictationShortcutPrefs().catch(function () {
        return null;
      }),
      loadDictationLanguageSetting().catch(function () {
        return null;
      }),
      loadDictationStatus({ silent: true }).catch(function () {
        return null;
      })
    ]).finally(function () {
      state.dictationInstallReady = true;
      renderDictationInstallSettings();
    });

    var selfImproveBootstrap = refreshModelData({ force: true, silent: true })
      .catch(function () {
        return null;
      })
      .then(function () {
        return loadSelfImproveSettings().catch(function () {
          return null;
        });
      });
    var settingsBootstrap = Promise.all([
      loadLlmRuntimeSettings().catch(function () {
        return null;
      }),
      loadAutomationDaemonStatus({ silent: false }).catch(function () {
        return null;
      }),
      selfImproveBootstrap,
      loadCommandRules(preferredWorkspace).catch(function () {
        return null;
      }),
      loadModeRuntimeState().catch(function () {
        return null;
      })
    ]);
    return Promise.all([dictationBootstrap, settingsBootstrap]);
  }

  function commandRuleDecisionLabel(decision) {
    var value = String(decision || "");
    if (value === "allow") {
      return "Allow";
    }
    if (value === "deny") {
      return "Deny";
    }
    return "Rule";
  }

  function commandRuleMatchModeLabel(matchMode) {
    var value = String(matchMode || "").toLowerCase();
    if (value === "regex") {
      return "regex";
    }
    return "exact";
  }

  function renderCommandRulesSettings() {
    if (!el.commandRulesWorkspace || !el.commandRulesList || !el.commandRulesGlobalList || !el.commandRulesStatus) {
      return;
    }
    var workspaceOptions = "";
    if (!state.workspaces.length) {
      workspaceOptions = "<option value=''>No projects</option>";
    } else {
      for (var i = 0; i < state.workspaces.length; i += 1) {
        var workspace = state.workspaces[i] || {};
        var wsId = String(workspace.id || "");
        if (!wsId) {
          continue;
        }
        workspaceOptions += "<option value='" + escAttr(wsId) + "'>" + escHtml(workspace.name || wsId) + "</option>";
      }
    }
    if (el.commandRulesWorkspace.innerHTML !== workspaceOptions) {
      el.commandRulesWorkspace.innerHTML = workspaceOptions;
    }
    if (state.commandRulesWorkspaceId) {
      el.commandRulesWorkspace.value = state.commandRulesWorkspaceId;
      if (el.commandRulesWorkspace.value !== state.commandRulesWorkspaceId && el.commandRulesWorkspace.options.length) {
        el.commandRulesWorkspace.value = el.commandRulesWorkspace.options[0].value;
        state.commandRulesWorkspaceId = el.commandRulesWorkspace.value;
      }
    } else if (el.commandRulesWorkspace.options.length) {
      el.commandRulesWorkspace.value = el.commandRulesWorkspace.options[0].value;
      state.commandRulesWorkspaceId = el.commandRulesWorkspace.value;
    }

    var wsId = String(state.commandRulesWorkspaceId || "");
    var rulesData = wsId ? (state.commandRulesByWorkspace[wsId] || null) : null;
    if (!rulesData && state.commandRulesLoading) {
      var fallbackWsId = String(state.commandRulesLastRenderedWorkspaceId || "");
      if (fallbackWsId) {
        rulesData = state.commandRulesByWorkspace[fallbackWsId] || null;
      }
    }
    var statusText = "";
    if (state.commandRulesLoading) {
      statusText = "Loading command rules...";
    } else if (state.commandRulesError) {
      statusText = state.commandRulesError;
    }
    el.commandRulesStatus.textContent = statusText;

    var globalHtml = "";
    var html = "";
    if (!rulesData) {
      globalHtml = "<p class='empty-state'>No command rule data available.</p>";
      html = "";
      el.commandRulesGlobalList.innerHTML = globalHtml;
      el.commandRulesList.innerHTML = html;
      return;
    }
    if (wsId && state.commandRulesByWorkspace[wsId]) {
      state.commandRulesLastRenderedWorkspaceId = wsId;
    }

    var globalDefaults = Array.isArray(rulesData.global_defaults) ? rulesData.global_defaults : [];
    var remembered = Array.isArray(rulesData.remembered) ? rulesData.remembered : [];
    var onceRules = Array.isArray(rulesData.once) ? rulesData.once : [];

    globalHtml += "<section class='command-rules-group'><div class='command-rules-group-head'><p class='command-rules-group-title'>Global defaults</p></div><p class='settings-hint'>Global defaults apply to all projects.</p>";
    if (!globalDefaults.length) {
      globalHtml += "<p class='empty-state'>No global defaults configured.</p>";
    } else {
      globalHtml += "<div class='command-rule-table command-rule-table-global'>";
      globalHtml += "<div class='command-rule-table-head'><span>Command</span><span>Regex</span></div>";
      for (var g = 0; g < globalDefaults.length; g += 1) {
        var globalRule = globalDefaults[g] || {};
        globalHtml += "<div class='command-rule-row table global locked'>";
        globalHtml += "<div class='command-rule-col command'><span class='command-rule-command-text'>" + escHtml(globalRule.label || "Safe command") + "</span></div>";
        globalHtml += "<code class='command-rule-col regex'>" + escHtml(globalRule.pattern || "") + "</code>";
        globalHtml += "</div>";
      }
      globalHtml += "</div>";
    }
    globalHtml += "</section>";

    html += "<section class='command-rules-group'><div class='command-rules-group-head'><p class='command-rules-group-title'>Remembered project rules</p>";
    if (remembered.length) {
      html += "<button type='button' class='command-rule-clear ghost' data-action='clear-command-rules' data-rule-scope='remember'>Clear</button>";
    }
    html += "</div>";
    if (!remembered.length) {
      html += "<p class='empty-state'>No remembered project rules.</p>";
    } else {
      html += "<div class='command-rule-table command-rule-table-workspace'>";
      html += "<div class='command-rule-table-head'><span>Rule</span><span>Match</span><span></span></div>";
      for (var r = 0; r < remembered.length; r += 1) {
        var rememberedRule = remembered[r] || {};
        var ruleIndex = String(rememberedRule.index || "");
        var rememberedMode = commandRuleMatchModeLabel(rememberedRule.match_mode);
        var rememberedPattern = String(rememberedRule.pattern || "");
        var rememberedRuleText = rememberedMode === "exact" ? rememberedPattern : "regex rule";
        var rememberedMatchText = rememberedMode === "regex"
          ? "<code class='command-rule-col regex'>" + escHtml(rememberedPattern) + "</code>"
          : "<span class='command-rule-mode'><em>exact</em></span>";
        html += "<div class='command-rule-row table workspace'>";
        html += "<div class='command-rule-col command'><span class='command-rule-pill'>" + escHtml(commandRuleDecisionLabel(rememberedRule.decision)) + "</span><span class='command-rule-command-text'>" + escHtml(rememberedRuleText) + "</span></div>";
        html += "<div class='command-rule-col match'>" + rememberedMatchText + "</div>";
        html += "<button type='button' class='command-rule-delete' data-action='delete-command-rule' data-rule-scope='remember' data-rule-index='" + escAttr(ruleIndex) + "' aria-label='Delete rule' title='Delete rule'><svg viewBox='0 0 16 16' fill='none' stroke='currentColor' stroke-width='1.4' stroke-linecap='round' stroke-linejoin='round' aria-hidden='true'><path d='M3.5 4.4h9'></path><path d='M6.1 4.4V3.2h3.8v1.2'></path><path d='M5.2 6.1v6'></path><path d='M8 6.1v6'></path><path d='M10.8 6.1v6'></path><path d='M4.4 4.4l.6 8.2h6l.6-8.2'></path></svg></button>";
        html += "</div>";
      }
      html += "</div>";
    }
    html += "</section>";

    html += "<section class='command-rules-group'><div class='command-rules-group-head'><p class='command-rules-group-title'>One-time project rules</p>";
    if (onceRules.length) {
      html += "<button type='button' class='command-rule-clear ghost' data-action='clear-command-rules' data-rule-scope='once'>Clear</button>";
    }
    html += "</div>";
    if (!onceRules.length) {
      html += "<p class='empty-state'>No one-time project rules.</p>";
    } else {
      html += "<div class='command-rule-table command-rule-table-workspace'>";
      html += "<div class='command-rule-table-head'><span>Rule</span><span>Match</span><span></span></div>";
      for (var o = 0; o < onceRules.length; o += 1) {
        var onceRule = onceRules[o] || {};
        var onceIndex = String(onceRule.index || "");
        var onceMode = commandRuleMatchModeLabel(onceRule.match_mode);
        var oncePattern = String(onceRule.pattern || "");
        var onceRuleText = onceMode === "exact" ? oncePattern : "regex rule";
        var onceMatchText = onceMode === "regex"
          ? "<code class='command-rule-col regex'>" + escHtml(oncePattern) + "</code>"
          : "<span class='command-rule-mode'><em>exact</em></span>";
        html += "<div class='command-rule-row table workspace'>";
        html += "<div class='command-rule-col command'><span class='command-rule-pill'>" + escHtml(commandRuleDecisionLabel(onceRule.decision)) + "</span><span class='command-rule-command-text'>" + escHtml(onceRuleText) + "</span></div>";
        html += "<div class='command-rule-col match'>" + onceMatchText + "</div>";
        html += "<button type='button' class='command-rule-delete' data-action='delete-command-rule' data-rule-scope='once' data-rule-index='" + escAttr(onceIndex) + "' aria-label='Delete rule' title='Delete rule'><svg viewBox='0 0 16 16' fill='none' stroke='currentColor' stroke-width='1.4' stroke-linecap='round' stroke-linejoin='round' aria-hidden='true'><path d='M3.5 4.4h9'></path><path d='M6.1 4.4V3.2h3.8v1.2'></path><path d='M5.2 6.1v6'></path><path d='M8 6.1v6'></path><path d='M10.8 6.1v6'></path><path d='M4.4 4.4l.6 8.2h6l.6-8.2'></path></svg></button>";
        html += "</div>";
      }
      html += "</div>";
    }
    html += "</section>";

    el.commandRulesGlobalList.innerHTML = globalHtml;
    el.commandRulesList.innerHTML = html;
  }

  function loadCommandRules(workspaceId) {
    var wsId = trim(workspaceId || "");
    var settingsCard = el.settingsModal && el.settingsModal.querySelector
      ? el.settingsModal.querySelector(".modal-card")
      : null;
    var preservedScrollTop = settingsCard ? settingsCard.scrollTop : 0;
    if (!wsId) {
      state.commandRulesError = "";
      renderCommandRulesSettings();
      if (settingsCard) {
        settingsCard.scrollTop = preservedScrollTop;
      }
      return Promise.resolve(null);
    }
    state.commandRulesWorkspaceId = wsId;
    state.commandRulesLoading = true;
    state.commandRulesError = "";
    renderCommandRulesSettings();
    if (settingsCard) {
      settingsCard.scrollTop = preservedScrollTop;
    }
    return apiGet("command_rules_list", { workspace_id: wsId })
      .then(function (response) {
        if (!response || !response.success) {
          throw new Error((response && response.error) || "Could not load command rules");
        }
        state.commandRulesByWorkspace[wsId] = response;
        state.commandRulesError = "";
        return response;
      })
      .catch(function (error) {
        var message = error && error.message ? error.message : "Could not load command rules";
        if (/workspace not found/i.test(message)) {
          var nextWorkspaces = [];
          for (var i = 0; i < state.workspaces.length; i += 1) {
            var workspace = state.workspaces[i] || {};
            if (String(workspace.id || "") !== wsId) {
              nextWorkspaces.push(workspace);
            }
          }
          state.workspaces = nextWorkspaces;
          delete state.commandRulesByWorkspace[wsId];
          if (String(state.commandRulesWorkspaceId || "") === wsId) {
            state.commandRulesWorkspaceId = state.workspaces.length ? firstWorkspaceId(true) : "";
          }
          if (state.commandRulesWorkspaceId) {
            state.commandRulesError = "Selected project was removed. Switched to another project.";
            return loadCommandRules(state.commandRulesWorkspaceId);
          }
          state.commandRulesError = "Selected project was removed.";
          return null;
        }
        state.commandRulesError = message;
        return null;
      })
      .finally(function () {
        state.commandRulesLoading = false;
        renderCommandRulesSettings();
        if (settingsCard) {
          settingsCard.scrollTop = preservedScrollTop;
        }
      });
  }

  function deleteCommandRule(workspaceId, scope, indexValue) {
    var wsId = trim(workspaceId || "");
    var ruleScope = trim(scope || "");
    var idx = trim(String(indexValue || ""));
    if (!wsId || !ruleScope || !idx) {
      return Promise.resolve(null);
    }
    return apiPost("command_rule_delete", {
      workspace_id: wsId,
      scope: ruleScope,
      index: idx
    }).then(function (response) {
      if (!response || !response.success) {
        throw new Error((response && response.error) || "Could not delete rule");
      }
      return loadCommandRules(wsId);
    });
  }

  function clearCommandRules(workspaceId, scope) {
    var wsId = trim(workspaceId || "");
    var ruleScope = trim(scope || "");
    if (!wsId || !ruleScope) {
      return Promise.resolve(null);
    }
    return apiPost("command_rules_clear", {
      workspace_id: wsId,
      scope: ruleScope
    }).then(function (response) {
      if (!response || !response.success) {
        throw new Error((response && response.error) || "Could not clear command rules");
      }
      return loadCommandRules(wsId);
    });
  }

  function loadWorkspaceMultiAgent(workspaceId) {
    var wsId = trim(String(workspaceId || ""));
    if (!wsId) {
      return Promise.resolve(null);
    }
    state.workspaceMultiAgentLoadingById[wsId] = true;
    renderMultiAgentModal();
    return apiGet("multi_agent_workspace_get", { workspace_id: wsId })
      .then(function (response) {
        if (!response || !response.success || !response.workspace_multi_agent) {
          throw new Error((response && response.error) || "Could not load agent settings");
        }
        state.workspaceMultiAgentById[wsId] = response.workspace_multi_agent;
        state.workspaceMultiAgentErrorById[wsId] = "";
        return response.workspace_multi_agent;
      })
      .catch(function (error) {
        state.workspaceMultiAgentErrorById[wsId] = error && error.message ? error.message : "Could not load agent settings";
        throw error;
      })
      .finally(function () {
        state.workspaceMultiAgentLoadingById[wsId] = false;
        renderMultiAgentModal();
      });
  }

  function saveWorkspaceMultiAgent(workspaceId, payload) {
    var wsId = trim(String(workspaceId || ""));
    if (!wsId) {
      return Promise.resolve(null);
    }
    var body = payload && typeof payload === "object" ? payload : {};
    if (Object.prototype.hasOwnProperty.call(body, "charter")) {
      body.charter_present = "1";
    }
    body.workspace_id = wsId;
    state.workspaceMultiAgentLoadingById[wsId] = true;
    renderMultiAgentModal();
    return apiPost("multi_agent_workspace_update", body)
      .then(function (response) {
        if (!response || !response.success || !response.workspace_multi_agent) {
          throw new Error((response && response.error) || "Could not save agent settings");
        }
        state.workspaceMultiAgentById[wsId] = response.workspace_multi_agent;
        state.workspaceMultiAgentErrorById[wsId] = "";
        return response.workspace_multi_agent;
      })
      .catch(function (error) {
        state.workspaceMultiAgentErrorById[wsId] = error && error.message ? error.message : "Could not save agent settings";
        throw error;
      })
      .finally(function () {
        state.workspaceMultiAgentLoadingById[wsId] = false;
        renderMultiAgentModal();
      });
  }

  function saveMultiAgentGovernanceFromControls(workspaceId) {
    var wsId = trim(String(workspaceId || ""));
    if (!wsId) {
      return Promise.resolve(null);
    }
    var contextSharingEnabled = el.multi_agentToggleContextSharing && el.multi_agentToggleContextSharing.checked ? "1" : "0";
    var policyAmendmentsEnabled = el.multi_agentToggleAmendments && el.multi_agentToggleAmendments.checked ? "1" : "0";
    var attentionPoliciesEnabled = el.multi_agentTogglePolicies && el.multi_agentTogglePolicies.checked ? "1" : "0";
    if (contextSharingEnabled !== "1") {
      policyAmendmentsEnabled = "0";
      attentionPoliciesEnabled = "0";
    }
    return saveWorkspaceMultiAgent(wsId, {
      context_sharing: contextSharingEnabled,
      dilemma_surfacing: "1",
      amendments: policyAmendmentsEnabled,
      interpretation_log: policyAmendmentsEnabled,
      commitments: el.multi_agentToggleCommitments && el.multi_agentToggleCommitments.checked ? "1" : "0",
      attention_policies: attentionPoliciesEnabled
    });
  }

  function normalizeSharedInstructionsText(rawText) {
    var text = String(rawText || "");
    var trimmedText = trim(text);
    var legacyDefault = trim("# Workspace Charter\n\nState your intent, constraints, and governance priorities for this workspace.");
    if (trimmedText === legacyDefault) {
      return "";
    }
    return text;
  }

  function flushMultiAgentCharterSave(workspaceId) {
    var wsId = trim(String(workspaceId || ""));
    if (!wsId) {
      return Promise.resolve(null);
    }
    var charterText = normalizeSharedInstructionsText((el.multi_agentCharter && el.multi_agentCharter.value) || "");
    var current = normalizeSharedInstructionsText(state.workspaceMultiAgentById[wsId] && String(state.workspaceMultiAgentById[wsId].charter || ""));
    if (charterText === current) {
      return Promise.resolve(null);
    }
    return saveWorkspaceMultiAgent(wsId, {
      charter: charterText
    }).then(function () {
      return loadState();
    }).then(renderUi);
  }

  function scheduleMultiAgentCharterSave(workspaceId, delayMs) {
    var wsId = trim(String(workspaceId || ""));
    if (!wsId) {
      return;
    }
    var timers = state.multiAgentCharterAutosaveTimerByWorkspace;
    if (timers[wsId]) {
      clearTimeout(timers[wsId]);
      delete timers[wsId];
    }
    var waitMs = Number(delayMs || 0);
    if (!isFinite(waitMs) || waitMs < 0) {
      waitMs = 700;
    }
    timers[wsId] = setTimeout(function () {
      delete timers[wsId];
      flushMultiAgentCharterSave(wsId).catch(showError);
    }, waitMs);
  }

  function applyAutomationsFromResponse(response) {
    if (!response || typeof response !== "object") {
      return;
    }
    if (response.automations && typeof response.automations === "object") {
      applyAutomationsState(response.automations);
    }
  }

  function automationScheduleHintText(kind) {
    var normalized = trim(String(kind || "")).toLowerCase();
    if (normalized === "cron") {
      return "Cron format: minute hour day month weekday (example: 0 9 * * 1-5).";
    }
    if (normalized === "once") {
      return "One-time run: use ISO time (for example 2026-03-25T09:30) or Unix epoch.";
    }
    return "Interval examples: 15m, 1h, 86400.";
  }

  function renderAutomationScheduleHint() {
    if (!el.automationScheduleHint || !el.automationScheduleKind) {
      return;
    }
    var kind = String(el.automationScheduleKind.value || "interval");
    el.automationScheduleHint.textContent = automationScheduleHintText(kind);
    if (kind === "interval" && el.automationScheduleValue) {
      el.automationScheduleValue.placeholder = "15m";
    } else if (kind === "cron" && el.automationScheduleValue) {
      el.automationScheduleValue.placeholder = "0 9 * * 1-5";
    } else if (el.automationScheduleValue) {
      el.automationScheduleValue.placeholder = "2026-03-25T09:30";
    }
  }

  function epochToDatetimeLocalInput(epochValue) {
    var epoch = parseEpochOrZero(epochValue);
    if (!epoch) {
      return "";
    }
    try {
      var dt = new Date(epoch * 1000);
      var year = String(dt.getFullYear());
      var month = String(dt.getMonth() + 1).padStart(2, "0");
      var day = String(dt.getDate()).padStart(2, "0");
      var hours = String(dt.getHours()).padStart(2, "0");
      var minutes = String(dt.getMinutes()).padStart(2, "0");
      return year + "-" + month + "-" + day + "T" + hours + ":" + minutes;
    } catch (_err) {
      return "";
    }
  }

  function datetimeLocalInputToEpoch(value) {
    var raw = trim(String(value || ""));
    if (!raw) {
      return "";
    }
    var parsed = Date.parse(raw);
    if (!isFinite(parsed) || parsed <= 0) {
      return "";
    }
    return String(Math.floor(parsed / 1000));
  }

  function populateAutomationWorkspaceOptions(selectedWorkspaceId) {
    if (!el.automationWorkspace) {
      return;
    }
    var selectedId = trim(String(selectedWorkspaceId || ""));
    var html = "";
    for (var i = 0; i < state.workspaces.length; i += 1) {
      var workspace = state.workspaces[i] || {};
      var workspaceId = trim(String(workspace.id || ""));
      if (!workspaceId) {
        continue;
      }
      html += "<option value='" + escAttr(workspaceId) + "'" + (workspaceId === selectedId ? " selected" : "") + ">" + escHtml(workspace.name || workspaceId) + "</option>";
    }
    el.automationWorkspace.innerHTML = html;
    if (!selectedId && el.automationWorkspace.options.length) {
      el.automationWorkspace.selectedIndex = 0;
    }
  }

  function populateAutomationConversationOptions(workspaceId, selectedConversationId) {
    if (!el.automationConversation) {
      return;
    }
    var workspace = getWorkspaceById(workspaceId);
    var conversations = workspace && Array.isArray(workspace.conversations) ? workspace.conversations : [];
    var selectedId = trim(String(selectedConversationId || ""));
    var html = "<option value=''>Create/use dedicated automation thread</option>";
    for (var i = 0; i < conversations.length; i += 1) {
      var conversation = conversations[i] || {};
      var conversationId = trim(String(conversation.id || ""));
      if (!conversationId) {
        continue;
      }
      html += "<option value='" + escAttr(conversationId) + "'" + (conversationId === selectedId ? " selected" : "") + ">" + escHtml(conversationDisplayTitle(conversation.title || conversationId)) + "</option>";
    }
    el.automationConversation.innerHTML = html;
  }

  function openAutomationModal(mode, automationId) {
    if (!el.automationModal || !el.automationForm) {
      return;
    }
    var selectedMode = mode === "edit" ? "edit" : "create";
    var editing = selectedMode === "edit" ? automationById(automationId) : null;
    automationModalMode = selectedMode;
    automationModalEditingId = editing ? String(editing.id || "") : "";

    if (el.automationModalTitle) {
      el.automationModalTitle.textContent = editing ? "Edit automation" : "Create automation";
    }
    var defaultWorkspaceId = editing
      ? String(editing.workspace_id || "")
      : (String(state.activeWorkspaceId || "") || String(firstWorkspaceId(true) || ""));
    if (!defaultWorkspaceId && state.workspaces.length) {
      defaultWorkspaceId = String(state.workspaces[0].id || "");
    }
    populateAutomationWorkspaceOptions(defaultWorkspaceId);
    populateAutomationConversationOptions(defaultWorkspaceId, editing ? String(editing.conversation_id || "") : String(state.activeConversationId || ""));

    if (el.automationName) {
      el.automationName.value = editing ? String(editing.name || "") : "";
    }
    if (el.automationPrompt) {
      el.automationPrompt.value = editing ? String(editing.prompt || "") : "";
    }
    if (el.automationScheduleKind) {
      el.automationScheduleKind.value = editing && editing.schedule_kind ? String(editing.schedule_kind) : "interval";
    }
    if (el.automationScheduleValue) {
      el.automationScheduleValue.value = editing ? String(editing.schedule_value || "") : "15m";
    }
    if (el.automationEnabled) {
      el.automationEnabled.checked = !editing || String(editing.enabled || "0") === "1";
    }
    if (el.automationAllowSelfReschedule) {
      el.automationAllowSelfReschedule.checked = editing ? String(editing.allow_self_reschedule || "0") === "1" : false;
    }
    if (el.automationNextRun) {
      el.automationNextRun.value = editing ? epochToDatetimeLocalInput(editing.next_run) : "";
    }
    if (el.automationSaveBtn) {
      var hasWorkspace = !!defaultWorkspaceId;
      el.automationSaveBtn.disabled = !hasWorkspace;
    }
    renderAutomationScheduleHint();
    openModal(el.automationModal);
    window.setTimeout(function () {
      if (el.automationName && typeof el.automationName.focus === "function") {
        el.automationName.focus();
      }
    }, 0);
  }

  function closeAutomationModal() {
    closeModal(el.automationModal);
    automationModalMode = "create";
    automationModalEditingId = "";
  }

  function saveAutomationFromModal() {
    if (!el.automationWorkspace || !el.automationPrompt || !el.automationScheduleKind || !el.automationScheduleValue) {
      return Promise.resolve(null);
    }
    var workspaceId = trim(String(el.automationWorkspace.value || ""));
    if (!workspaceId) {
      return Promise.reject(new Error("Choose a project."));
    }
    var promptText = String(el.automationPrompt.value || "");
    if (!trim(promptText)) {
      return Promise.reject(new Error("Automation prompt is required."));
    }
    var payload = {
      workspace_id: workspaceId,
      conversation_id: trim(String((el.automationConversation && el.automationConversation.value) || "")),
      name: trim(String((el.automationName && el.automationName.value) || "")),
      prompt: promptText,
      schedule_kind: trim(String(el.automationScheduleKind.value || "")) || "interval",
      schedule_value: trim(String(el.automationScheduleValue.value || "")),
      enabled: el.automationEnabled && el.automationEnabled.checked ? "1" : "0",
      allow_self_reschedule: el.automationAllowSelfReschedule && el.automationAllowSelfReschedule.checked ? "1" : "0"
    };
    var nextRunEpoch = datetimeLocalInputToEpoch(el.automationNextRun && el.automationNextRun.value);
    if (nextRunEpoch) {
      payload.next_run = nextRunEpoch;
    }
    if (automationModalMode === "edit" && automationModalEditingId) {
      payload.automation_id = automationModalEditingId;
    }
    return apiPost("automation_upsert", payload)
      .then(function (response) {
        if (!response || !response.success) {
          throw new Error((response && response.error) || "Could not save automation");
        }
        applyAutomationsFromResponse(response);
        if (response.automation && response.automation.id) {
          state.activeAutomationId = String(response.automation.id || "");
        }
        saveSidebarSection("automations");
        showTransientNotice(automationModalMode === "edit" ? "Automation updated." : "Automation created.");
        closeAutomationModal();
        renderUi();
        return response;
      });
  }

  function setAutomationEnabled(automationId, enabled) {
    return apiPost("automation_toggle", {
      automation_id: String(automationId || ""),
      enabled: enabled ? "1" : "0"
    }).then(function (response) {
      if (!response || !response.success) {
        throw new Error((response && response.error) || "Could not update automation");
      }
      applyAutomationsFromResponse(response);
      renderUi();
      return response;
    });
  }

  function runAutomationNow(automationId) {
    return apiPost("automation_run_now", {
      automation_id: String(automationId || "")
    }).then(function (response) {
      if (!response || !response.success) {
        throw new Error((response && response.error) || "Could not queue automation");
      }
      applyAutomationsFromResponse(response);
      state.activeAutomationId = String(response.automation_id || state.activeAutomationId || "");
      kickQueueWorker();
      return loadState({ fast: true }).catch(function () {
        return null;
      }).then(function () {
        renderUi();
        showTransientNotice("Automation queued.");
        return response;
      });
    });
  }

  function deleteAutomationById(automationId) {
    return apiPost("automation_delete", {
      automation_id: String(automationId || "")
    }).then(function (response) {
      if (!response || !response.success) {
        throw new Error((response && response.error) || "Could not delete automation");
      }
      applyAutomationsFromResponse(response);
      renderUi();
      showTransientNotice("Automation deleted.");
      return response;
    });
  }

  function tickAutomations(options) {
    var opts = options || {};
    if (automationsTickBusy) {
      return Promise.resolve(false);
    }
    automationsTickBusy = true;
    return apiPost("automations_tick", {})
      .then(function (response) {
        if (!response || !response.success) {
          return false;
        }
        applyAutomationsFromResponse(response);
        if (Number(response.triggered || 0) > 0) {
          kickQueueWorker();
        }
        if (opts.render !== false) {
          renderUi();
        }
        return true;
      })
      .catch(function () {
        return false;
      })
      .finally(function () {
        automationsTickBusy = false;
      });
  }

  function stopAutomationsTickLoop() {
    if (automationsTickTimer) {
      clearInterval(automationsTickTimer);
      automationsTickTimer = null;
    }
    automationsTickBusy = false;
  }

  function startAutomationsTickLoop() {
    stopAutomationsTickLoop();
    automationsTickTimer = setInterval(function () {
      tickAutomations({ render: state.sidebarSection === "automations" });
    }, 15000);
    tickAutomations({ render: false });
  }

  function triageRefresh() {
    return apiGet("triage_list", {})
      .then(function (response) {
        if (!response || !response.success) {
          throw new Error((response && response.error) || "Could not refresh triage");
        }
        state.triage = {
          count: String(response.count || "0"),
          cards: Array.isArray(response.cards) ? response.cards : []
        };
        state.triageOtherInputProposalId = "";
        if (state.activeTriage && Number(state.triage.count || 0) < 1) {
          state.activeTriage = false;
        }
      });
  }

  function triageDecide(proposalId, decisionText) {
    var decision = trim(String(decisionText || ""));
    return apiPost("triage_decide", {
      proposal_id: String(proposalId || ""),
      decision: decision || "accepted"
    }).then(function (response) {
      if (!response || !response.success) {
        throw new Error((response && response.error) || "Could not apply decision");
      }
      state.triage.cards = Array.isArray(response.cards) ? response.cards : [];
      state.triage.count = String(state.triage.cards.length);
      state.triageOtherInputProposalId = "";
    });
  }

  function triageSuppress(proposalId, scopeValue) {
    return apiPost("triage_suppress", {
      proposal_id: String(proposalId || ""),
      scope: scopeValue === "global" ? "global" : "workspace"
    }).then(function (response) {
      if (!response || !response.success) {
        throw new Error((response && response.error) || "Could not suppress proposal");
      }
      state.triage.cards = Array.isArray(response.cards) ? response.cards : [];
      state.triage.count = String(state.triage.cards.length);
      state.triageOtherInputProposalId = "";
    });
  }

  function triageCleanup(directiveText) {
    return apiPost("triage_cleanup", {
      directive: String(directiveText || "")
    }).then(function (response) {
      if (!response || !response.success || !response.result) {
        throw new Error((response && response.error) || "Cleanup failed");
      }
      var result = response.result || {};
      var beforeCount = Number(result.before || 0);
      var afterCount = Number(result.after || 0);
      showTransientNotice("Triage cleanup preview: " + String(beforeCount) + " -> " + String(afterCount));
      return result;
    });
  }

  function openMultiAgentModal(workspaceId) {
    var wsId = trim(String(workspaceId || state.activeWorkspaceId || ""));
    if (!wsId) {
      return Promise.resolve(null);
    }
    state.commandRulesWorkspaceId = wsId;
    return loadWorkspaceMultiAgent(wsId)
      .catch(function () {
        return null;
      })
      .then(function () {
        openModal(el.multi_agentModal);
        renderMultiAgentModal();
        return null;
      });
  }

  function multiAgentPreferredModelForResident(residentId, resident) {
    var explicit = trim(String(resident && resident.preferred_model || ""));
    if (explicit) {
      return explicit;
    }
    var mapped = {
      "credibility-manager": "llama3.1:8b",
      "continuity-steward": "llama3.1:8b",
      "semantic-watchtower": "deepseek-r1:8b",
      "compliance-guardian": "llama3.1:8b",
      "failure-simulator": "deepseek-r1:8b",
      "epistemic-calibrator": "deepseek-r1:8b",
      "red-team-twin": "deepseek-r1:8b",
      "narrative-coherence": "llama3.1:8b",
      "reputation-thermostat": "llama3.1:8b",
      "chrono-budgeter": "llama3.1:8b"
    };
    var rid = trim(String(residentId || ""));
    return mapped[rid] || "";
  }

  function multiAgentCurrentAutoModel(preferredModel) {
    var preferred = trim(String(preferredModel || ""));
    if (preferred && isModelInstalled(preferred)) {
      return preferred;
    }
    if (Array.isArray(state.models) && state.models.length) {
      return trim(String(state.models[0] || ""));
    }
    return "";
  }

  function isModelInstalled(modelName) {
    var target = trim(String(modelName || ""));
    if (!target) {
      return false;
    }
    for (var i = 0; i < state.models.length; i += 1) {
      if (String(state.models[i] || "") === target) {
        return true;
      }
    }
    return false;
  }

  function multiAgentSectionVisibilitySync() {
    var contextSharingEnabled = !(el.multi_agentToggleContextSharing && !el.multi_agentToggleContextSharing.checked);
    if (el.multi_agentCharter) {
      el.multi_agentCharter.disabled = !contextSharingEnabled;
    }
    if (el.multi_agentToggleAmendments) {
      if (!contextSharingEnabled) {
        el.multi_agentToggleAmendments.checked = false;
      }
      el.multi_agentToggleAmendments.disabled = !contextSharingEnabled;
    }
    if (el.multi_agentTogglePolicies) {
      if (!contextSharingEnabled) {
        el.multi_agentTogglePolicies.checked = false;
      }
      el.multi_agentTogglePolicies.disabled = !contextSharingEnabled;
    }
    if (el.multi_agentSectionAmendments && el.multi_agentToggleAmendments) {
      el.multi_agentSectionAmendments.classList.remove("hidden");
      el.multi_agentSectionAmendments.classList.toggle("collapsed", !el.multi_agentToggleAmendments.checked);
    }
    if (el.multi_agentSectionCommitments && el.multi_agentToggleCommitments) {
      el.multi_agentSectionCommitments.classList.remove("hidden");
      el.multi_agentSectionCommitments.classList.toggle("collapsed", !el.multi_agentToggleCommitments.checked);
    }
    if (el.multi_agentSectionPolicies && el.multi_agentTogglePolicies) {
      el.multi_agentSectionPolicies.classList.remove("hidden");
      el.multi_agentSectionPolicies.classList.toggle("collapsed", !el.multi_agentTogglePolicies.checked);
    }
  }

  function multiAgentParseEpoch(value) {
    var n = Number(value || 0);
    if (!isFinite(n) || n <= 0) {
      return 0;
    }
    return Math.floor(n);
  }

  function multiAgentRelativeAge(epochValue) {
    var epoch = multiAgentParseEpoch(epochValue);
    if (!epoch) {
      return "";
    }
    var nowEpoch = Math.floor(Date.now() / 1000);
    var delta = nowEpoch - epoch;
    if (!isFinite(delta) || delta < 0) {
      delta = 0;
    }
    if (delta < 60) {
      return "just now";
    }
    if (delta < 3600) {
      var mins = Math.floor(delta / 60);
      return String(mins) + "m ago";
    }
    if (delta < 86400) {
      var hours = Math.floor(delta / 3600);
      return String(hours) + "h ago";
    }
    var days = Math.floor(delta / 86400);
    if (days < 30) {
      return String(days) + "d ago";
    }
    var months = Math.floor(days / 30);
    if (months < 12) {
      return String(months) + "mo ago";
    }
    var years = Math.floor(months / 12);
    return String(years) + "y ago";
  }

  function multiAgentSortByCreatedDesc(items) {
    var list = Array.isArray(items) ? items.slice() : [];
    list.sort(function (a, b) {
      return multiAgentParseEpoch((b && b.created) || 0) - multiAgentParseEpoch((a && a.created) || 0);
    });
    return list;
  }

  function multiAgentCommitmentStatus(value) {
    var status = trim(String(value || "")).toLowerCase();
    if (status === "fulfilled" || status === "revoked") {
      return status;
    }
    return "active";
  }

  function multiAgentCommitmentStatusLabel(status) {
    if (status === "fulfilled") {
      return "Fulfilled";
    }
    if (status === "revoked") {
      return "Revoked";
    }
    return "Active";
  }

  function multiAgentSummaryLabel(baseText, count) {
    var total = Number(count || 0);
    if (!isFinite(total) || total < 1) {
      return String(baseText || "");
    }
    return String(baseText || "") + " (" + String(total) + ")";
  }

  function multiAgentHumanizeEnum(value) {
    var token = trim(String(value || ""));
    if (!token) {
      return "";
    }
    var spaced = token.replace(/([a-z0-9])([A-Z])/g, "$1 $2").replace(/[_-]+/g, " ");
    return spaced.replace(/\s+/g, " ").replace(/^\w/, function (ch) {
      return ch.toUpperCase();
    });
  }

  function multiAgentTargetTypeLabel(value) {
    var token = trim(String(value || ""));
    if (token === "Resident") {
      return "Agent role";
    }
    if (token === "Charter") {
      return "Project instructions";
    }
    return multiAgentHumanizeEnum(token);
  }

  function multiAgentEscalationLabel(value) {
    return multiAgentHumanizeEnum(value);
  }

  function multiAgentSetAllResidentsEnabled(workspaceId, enabled) {
    var wsId = trim(String(workspaceId || ""));
    if (!wsId) {
      return Promise.resolve(null);
    }
    var data = state.workspaceMultiAgentById[wsId] || {};
    var catalog = Array.isArray(state.multi_agentCatalog && state.multi_agentCatalog.curated_residents)
      ? state.multi_agentCatalog.curated_residents
      : [];
    if (!catalog.length) {
      return Promise.resolve(null);
    }
    var residentMap = {};
    var activeResidents = Array.isArray(data && data.residents) ? data.residents : [];
    for (var i = 0; i < activeResidents.length; i += 1) {
      var entry = activeResidents[i] || {};
      var entryId = trim(String(entry.id || ""));
      if (entryId) {
        residentMap[entryId] = entry;
      }
    }

    var requests = [];
    for (var j = 0; j < catalog.length; j += 1) {
      var curated = catalog[j] || {};
      var rid = trim(String(curated.id || ""));
      if (!rid) {
        continue;
      }
      var existing = residentMap[rid] || null;
      var modelValue = trim(String(existing && existing.model || ""));
      if (enabled) {
        if (!existing) {
          requests.push(apiPost("multi_agent_resident_spawn", {
            workspace_id: wsId,
            resident_id: rid,
            visible: "0",
            background: "1",
            reserve_compute: "0",
            model: modelValue
          }));
        } else {
          requests.push(apiPost("multi_agent_resident_update", {
            workspace_id: wsId,
            resident_id: rid,
            enabled: "1",
            visible: existing.visible ? "1" : "0",
            background: existing.background ? "1" : "0",
            model_present: "1",
            model: modelValue
          }));
        }
      } else if (existing) {
        requests.push(apiPost("multi_agent_resident_update", {
          workspace_id: wsId,
          resident_id: rid,
          enabled: "0",
          visible: existing.visible ? "1" : "0",
          background: existing.background ? "1" : "0",
          model_present: "1",
          model: modelValue
        }));
      }
    }

    if (!requests.length) {
      return Promise.resolve(null);
    }

    state.multiAgentResidentBulkSavingByWorkspace[wsId] = true;
    renderMultiAgentModal();
    return Promise.all(requests).then(function () {
      return loadWorkspaceMultiAgent(wsId).catch(function () {
        return null;
      });
    }).then(function () {
      return loadState();
    }).then(function () {
      renderUi();
      return null;
    }).finally(function () {
      state.multiAgentResidentBulkSavingByWorkspace[wsId] = false;
      renderMultiAgentModal();
    });
  }

  function renderMultiAgentModal() {
    if (!el.multi_agentModal) {
      return;
    }
    var wsId = trim(String(state.commandRulesWorkspaceId || state.activeWorkspaceId || ""));
    var ws = wsId ? getWorkspaceById(wsId) : null;
    var data = wsId ? (state.workspaceMultiAgentById[wsId] || null) : null;
    var loading = !!state.workspaceMultiAgentLoadingById[wsId];
    var governanceSaving = !!state.multiAgentGovernanceSavingByWorkspace[wsId];
    var bulkResidentSaving = !!state.multiAgentResidentBulkSavingByWorkspace[wsId];
    var errorText = trim(String(state.workspaceMultiAgentErrorById[wsId] || ""));
    var catalog = Array.isArray(state.multi_agentCatalog && state.multi_agentCatalog.curated_residents)
      ? state.multi_agentCatalog.curated_residents
      : [];
    var residentMap = {};
    var activeResidents = Array.isArray(data && data.residents) ? data.residents : [];
    for (var r = 0; r < activeResidents.length; r += 1) {
      var activeResident = activeResidents[r] || {};
      var activeId = trim(String(activeResident.id || ""));
      if (!activeId) {
        continue;
      }
      residentMap[activeId] = activeResident;
    }

    if (el.multi_agentProjectLabel) {
      el.multi_agentProjectLabel.textContent = ws ? (ws.name || ws.id) : "No project selected";
    }
    if (el.multi_agentStatus) {
      el.multi_agentStatus.classList.remove("show", "error");
      if (errorText) {
        el.multi_agentStatus.textContent = errorText;
        el.multi_agentStatus.classList.add("show", "error");
      } else if (bulkResidentSaving) {
        el.multi_agentStatus.textContent = "Updating agent team...";
        el.multi_agentStatus.classList.add("show");
      } else if (governanceSaving) {
        el.multi_agentStatus.textContent = "Saving...";
        el.multi_agentStatus.classList.add("show");
      } else {
        el.multi_agentStatus.textContent = "";
      }
    }

    if (!data) {
      if (el.multi_agentResidentsList) {
        el.multi_agentResidentsList.innerHTML = "<p class='empty-state subtle-empty'>No agent settings loaded.</p>";
      }
      if (el.multi_agentPoliciesList) {
        el.multi_agentPoliciesList.innerHTML = "<p class='empty-state subtle-empty'>No decision filters yet. In Triage, use Don't ask about this to mute recurring low-priority decisions.</p>";
      }
      if (el.multi_agentAmendmentsList) {
        el.multi_agentAmendmentsList.innerHTML = "<p class='empty-state subtle-empty'>No pending instruction updates.</p>";
      }
      if (el.multi_agentCommitmentsList) {
        el.multi_agentCommitmentsList.innerHTML = "<p class='empty-state subtle-empty'>No commitments yet. Agent commitments will appear here with status updates over time.</p>";
      }
      if (el.multi_agentInterpretationList) {
        el.multi_agentInterpretationList.innerHTML = "<p class='empty-state subtle-empty'>No interpretation notes.</p>";
      }
      if (el.multi_agentRolesHint) {
        el.multi_agentRolesHint.textContent = "Turn built-in specialist agents on or off. Use each row menu for model and visibility.";
      }
      if (el.multi_agentAmendmentsSummary) {
        el.multi_agentAmendmentsSummary.textContent = "Instruction updates";
      }
      if (el.multi_agentInterpretationSummary) {
        el.multi_agentInterpretationSummary.textContent = "Interpretation notes";
      }
      if (el.multi_agentCommitmentsSummary) {
        el.multi_agentCommitmentsSummary.textContent = "Commitments";
      }
      if (el.multi_agentPoliciesSummary) {
        el.multi_agentPoliciesSummary.textContent = "Decision filters";
      }
      if (el.multi_agentToggleContextSharing) {
        el.multi_agentToggleContextSharing.checked = true;
      }
      if (el.multi_agentToggleAllResidents) {
        el.multi_agentToggleAllResidents.checked = false;
        el.multi_agentToggleAllResidents.indeterminate = false;
        el.multi_agentToggleAllResidents.disabled = true;
      }
      multiAgentSectionVisibilitySync();
      return;
    }

    if (el.multi_agentCharter) {
      el.multi_agentCharter.value = normalizeSharedInstructionsText(data.charter || "");
    }
    var toggles = data.toggles && typeof data.toggles === "object" ? data.toggles : {};
    if (el.multi_agentToggleAmendments) {
      el.multi_agentToggleAmendments.checked = !!Number(toggles.amendments || 0) || !!Number(toggles.interpretation_log || 0);
    }
    if (el.multi_agentToggleCommitments) {
      el.multi_agentToggleCommitments.checked = !!Number(toggles.commitments || 0);
    }
    if (el.multi_agentToggleContextSharing) {
      el.multi_agentToggleContextSharing.checked = !Object.prototype.hasOwnProperty.call(toggles, "context_sharing") || !!Number(toggles.context_sharing || 0);
    }
    if (el.multi_agentTogglePolicies) {
      el.multi_agentTogglePolicies.checked = !!Number(toggles.attention_policies || 0);
    }
    multiAgentSectionVisibilitySync();

    var amendments = multiAgentSortByCreatedDesc(Array.isArray(data.unratified_amendments) ? data.unratified_amendments : []);
    var commitments = multiAgentSortByCreatedDesc(Array.isArray(data.commitments_log) ? data.commitments_log : []);
    var interpretations = multiAgentSortByCreatedDesc(Array.isArray(data.interpretation_log) ? data.interpretation_log : []);
    var workspacePolicies = multiAgentSortByCreatedDesc(Array.isArray(data.attention_policies) ? data.attention_policies : []);
    var globalPolicies = multiAgentSortByCreatedDesc(Array.isArray(data.global_attention_policies) ? data.global_attention_policies : []);

    if (el.multi_agentAmendmentsSummary) {
      el.multi_agentAmendmentsSummary.textContent = multiAgentSummaryLabel("Instruction updates", amendments.length);
    }
    if (el.multi_agentInterpretationSummary) {
      el.multi_agentInterpretationSummary.textContent = multiAgentSummaryLabel("Interpretation notes", interpretations.length);
    }
    if (el.multi_agentCommitmentsSummary) {
      el.multi_agentCommitmentsSummary.textContent = multiAgentSummaryLabel("Commitments", commitments.length);
    }
    if (el.multi_agentPoliciesSummary) {
      el.multi_agentPoliciesSummary.textContent = multiAgentSummaryLabel("Decision filters", workspacePolicies.length + globalPolicies.length);
    }
    if (el.multi_agentRolesHint) {
      var activeRoleCount = 0;
      var visibleRoleCount = 0;
      for (var ar = 0; ar < activeResidents.length; ar += 1) {
        var roleEntry = activeResidents[ar] || {};
        if (roleEntry.enabled) {
          activeRoleCount += 1;
        }
        if (roleEntry.enabled && roleEntry.visible) {
          visibleRoleCount += 1;
        }
      }
      var roleTotal = catalog.length;
      if (roleTotal > 0) {
        el.multi_agentRolesHint.textContent = String(activeRoleCount) + " of " + String(roleTotal) + " active. " + String(visibleRoleCount) + " shown in Threads.";
      } else {
        el.multi_agentRolesHint.textContent = "Turn built-in specialist agents on or off. Use each row menu for model and visibility.";
      }
      if (el.multi_agentToggleAllResidents) {
        el.multi_agentToggleAllResidents.disabled = loading || bulkResidentSaving || roleTotal < 1;
        el.multi_agentToggleAllResidents.checked = roleTotal > 0 && activeRoleCount === roleTotal;
        el.multi_agentToggleAllResidents.indeterminate = activeRoleCount > 0 && activeRoleCount < roleTotal;
      }
    }

    if (el.multi_agentResidentsList) {
      var residentsHtml = "";
      if (!catalog.length) {
        residentsHtml = "<p class='empty-state'>No built-in agent roles available.</p>";
      } else {
        var selectedResidentId = trim(String(state.multiAgentSelectedResidentIdByWorkspace[wsId] || ""));
        var openOptionsResidentId = trim(String(state.multiAgentOpenResidentOptionsByWorkspace[wsId] || ""));
        for (var cr = 0; cr < catalog.length; cr += 1) {
          var curated = catalog[cr] || {};
          var rid = trim(String(curated.id || ""));
          if (!rid) {
            continue;
          }
          var existing = residentMap[rid] || null;
          var isEnabled = !!(existing && existing.enabled);
          var showThreads = !!(existing && existing.visible);
          var selectedModel = trim(String(existing && existing.model || ""));
          var preferredModel = multiAgentPreferredModelForResident(rid, curated);
          var preferredInstalled = !preferredModel || isModelInstalled(preferredModel);
          var currentAutoModel = multiAgentCurrentAutoModel(preferredModel);
          var selectedInstalled = !selectedModel || isModelInstalled(selectedModel);
          var disableEnable = false;
          var selectedRow = selectedResidentId && selectedResidentId === rid;
          var roleStatusLabel = isEnabled ? "On" : "Off";
          var roleStatusClass = isEnabled ? "on" : "off";
          var roleModelLabel = selectedModel || ("Auto: " + (currentAutoModel || "none"));
          var preferredDisplay = "";
          if (preferredModel) {
            preferredDisplay = "preferred: " + preferredModel + (preferredInstalled ? "" : " (not installed)");
          }
          var autoOptionLabel = "Auto";
          if (currentAutoModel) {
            autoOptionLabel = "Auto (current: " + currentAutoModel + ")";
          } else {
            autoOptionLabel = "Auto (no model available)";
          }
          if (selectedModel && !selectedInstalled) {
            roleModelLabel += " (not installed)";
          }
          var optionsOpen = openOptionsResidentId && openOptionsResidentId === rid;

          residentsHtml += "<article class='resident-row" + (selectedRow ? " selected" : "") + "' data-action='multi_agent-resident-select' data-workspace-id='" + escAttr(wsId) + "' data-resident-id='" + escAttr(rid) + "'>";
          residentsHtml += "<div class='resident-row-head'>";
          residentsHtml += "<label class='resident-enable-row' title='Enable or disable this agent role.'>";
          residentsHtml += "<input type='checkbox' data-action='multi_agent-resident-enable' data-workspace-id='" + escAttr(wsId) + "' data-resident-id='" + escAttr(rid) + "'" + (isEnabled ? " checked" : "") + (disableEnable ? " disabled" : "") + " />";
          residentsHtml += "<span class='resident-title-wrap'>";
          residentsHtml += "<span class='resident-title'>" + escHtml(curated.name || rid) + "</span>";
          if (preferredDisplay) {
            residentsHtml += "<span class='resident-title-preferred' title='" + escAttr(preferredDisplay) + "'>" + escHtml(preferredDisplay) + "</span>";
          }
          residentsHtml += "</span>";
          residentsHtml += "</label>";
          residentsHtml += "<div class='resident-head-actions'>";
          residentsHtml += "<span class='resident-inline-chips'>";
          if (isEnabled) {
            residentsHtml += "<button type='button' class='resident-chip resident-chip-btn status-" + escAttr(roleStatusClass) + "' data-action='multi_agent-resident-quick-toggle' data-workspace-id='" + escAttr(wsId) + "' data-resident-id='" + escAttr(rid) + "' title='Turn this agent off'>" + escHtml(roleStatusLabel) + "</button>";
          }
          if (isEnabled) {
            residentsHtml += "<button type='button' class='resident-chip resident-chip-btn' data-action='multi_agent-resident-open-model' data-workspace-id='" + escAttr(wsId) + "' data-resident-id='" + escAttr(rid) + "' title='" + escAttr("Model: " + roleModelLabel + ". Open model options for this agent") + "'>" + escHtml(roleModelLabel) + "</button>";
          }
          residentsHtml += "</span>";
          residentsHtml += "<button type='button' class='resident-menu-trigger' data-action='multi_agent-resident-options-toggle' data-resident-id='" + escAttr(rid) + "' title='" + escAttr(optionsOpen ? "Collapse options" : "Expand options") + "' aria-label='Toggle options'>" + (optionsOpen ? "▾" : "▸") + "</button>";
          residentsHtml += "</div>";
          residentsHtml += "</div>";
          residentsHtml += "<p class='resident-description'>" + escHtml(curated.mandate || "") + "</p>";
          if (disableEnable) {
            residentsHtml += "<p class='resident-meta'>Preferred model missing. Choose an alternate model in options to enable this role.</p>";
          }
          residentsHtml += "<div class='resident-options" + (optionsOpen ? "" : " hidden") + "' id='multi_agent-resident-options-" + escAttr(rid) + "'>";
          residentsHtml += "<label class='toggle-row' title='When enabled, also show this agent in the threads list.'><input type='checkbox' data-action='multi_agent-resident-visible' data-workspace-id='" + escAttr(wsId) + "' data-resident-id='" + escAttr(rid) + "'" + (showThreads ? " checked" : "") + (isEnabled ? "" : " disabled") + " /> Show in threads list</label>";
          residentsHtml += "<label title='Override model selection for this agent role.'>Model override</label>";
          residentsHtml += "<select data-action='multi_agent-resident-model' data-workspace-id='" + escAttr(wsId) + "' data-resident-id='" + escAttr(rid) + "'>";
          residentsHtml += "<option value=''" + (!selectedModel ? " selected" : "") + ">" + escHtml(autoOptionLabel) + "</option>";
          for (var mi = 0; mi < state.models.length; mi += 1) {
            var modelName = String(state.models[mi] || "");
            residentsHtml += "<option value='" + escAttr(modelName) + "'" + (selectedModel === modelName ? " selected" : "") + ">" + escHtml(modelName) + "</option>";
          }
          residentsHtml += "</select>";
          residentsHtml += "</div>";
          residentsHtml += "</article>";
        }
      }
      el.multi_agentResidentsList.innerHTML = residentsHtml;
    }

    if (el.multi_agentPoliciesList) {
      var policiesHtml = "";
      var contextSharingActive = !(el.multi_agentToggleContextSharing && !el.multi_agentToggleContextSharing.checked);
      if (!contextSharingActive) {
        policiesHtml = "<p class='empty-state subtle-empty'>Enable agent context sharing to use decision filters.</p>";
      } else if (!workspacePolicies.length && !globalPolicies.length) {
        policiesHtml = "<p class='empty-state subtle-empty'>No decision filters yet. In Triage, use Don't ask about this to mute recurring low-priority decisions.</p>";
      } else {
        for (var p = 0; p < workspacePolicies.length; p += 1) {
          var wp = workspacePolicies[p] || {};
          var wpId = trim(String(wp.id || ""));
          if (!wpId) {
            continue;
          }
          policiesHtml += "<article class='multi_agent-item multi-agent-card'>";
          policiesHtml += "<p class='multi-agent-card-title'>Project filter</p>";
          policiesHtml += "<div class='multi-agent-chip-row'>";
          policiesHtml += "<span class='multi-agent-chip'>" + escHtml(multiAgentEscalationLabel(wp.escalation_class) || "Any class") + "</span>";
          policiesHtml += "<span class='multi-agent-chip'>" + escHtml(multiAgentTargetTypeLabel(wp.target_type) || "Any target") + "</span>";
          policiesHtml += "<span class='multi-agent-chip'>" + escHtml(wp.resident || "Any agent") + "</span>";
          policiesHtml += "<span class='multi-agent-chip'>impact >= " + escHtml(String(wp.impact_threshold || "0")) + "</span>";
          policiesHtml += "</div>";
          var wpAge = multiAgentRelativeAge(wp.created);
          if (wpAge) {
            policiesHtml += "<p class='multi-agent-card-meta'>Created " + escHtml(wpAge) + "</p>";
          }
          policiesHtml += "<div class='multi-agent-card-actions'>";
          policiesHtml += "<button type='button' class='ghost' data-action='multi_agent-log-delete' data-workspace-id='" + escAttr(wsId) + "' data-log-kind='policies' data-entry-id='" + escAttr(wpId) + "'>Delete</button>";
          policiesHtml += "</div>";
          policiesHtml += "</article>";
        }
        for (var g = 0; g < globalPolicies.length; g += 1) {
          var gp = globalPolicies[g] || {};
          var gpId = trim(String(gp.id || ""));
          if (!gpId) {
            continue;
          }
          policiesHtml += "<article class='multi_agent-item multi-agent-card'>";
          policiesHtml += "<p class='multi-agent-card-title'>Global filter</p>";
          policiesHtml += "<div class='multi-agent-chip-row'>";
          policiesHtml += "<span class='multi-agent-chip'>" + escHtml(multiAgentEscalationLabel(gp.escalation_class) || "Any class") + "</span>";
          policiesHtml += "<span class='multi-agent-chip'>" + escHtml(multiAgentTargetTypeLabel(gp.target_type) || "Any target") + "</span>";
          policiesHtml += "<span class='multi-agent-chip'>" + escHtml(gp.resident || "Any agent") + "</span>";
          policiesHtml += "<span class='multi-agent-chip'>impact >= " + escHtml(String(gp.impact_threshold || "0")) + "</span>";
          policiesHtml += "</div>";
          var gpAge = multiAgentRelativeAge(gp.created);
          if (gpAge) {
            policiesHtml += "<p class='multi-agent-card-meta'>Created " + escHtml(gpAge) + "</p>";
          }
          policiesHtml += "<div class='multi-agent-card-actions'>";
          policiesHtml += "<button type='button' class='ghost' data-action='multi_agent-log-delete' data-workspace-id='" + escAttr(wsId) + "' data-log-kind='global-policies' data-entry-id='" + escAttr(gpId) + "'>Delete</button>";
          policiesHtml += "</div>";
          policiesHtml += "</article>";
        }
      }
      el.multi_agentPoliciesList.innerHTML = policiesHtml;
    }

    if (el.multi_agentAmendmentsList) {
      var amendmentsHtml = "";
      if (!amendments.length) {
        amendmentsHtml = "<p class='empty-state subtle-empty'>No pending instruction updates.</p>";
      } else {
        for (var a = 0; a < amendments.length; a += 1) {
          var amendment = amendments[a] || {};
          var amendmentId = trim(String(amendment.id || ""));
          if (!amendmentId) {
            continue;
          }
          amendmentsHtml += "<article class='multi_agent-item multi-agent-card'>";
          amendmentsHtml += "<p class='multi-agent-card-title'>" + escHtml(amendment.summary || "Instruction update") + "</p>";
          if (trim(String(amendment.rationale || ""))) {
            amendmentsHtml += "<p class='multi-agent-card-body'>" + escHtml(amendment.rationale || "") + "</p>";
          }
          amendmentsHtml += "<div class='multi-agent-chip-row'>";
          amendmentsHtml += "<span class='multi-agent-chip'>" + escHtml(amendment.resident || "agent") + "</span>";
          amendmentsHtml += "<span class='multi-agent-chip'>" + escHtml(multiAgentEscalationLabel(amendment.escalation_class) || "Policy tradeoff") + "</span>";
          var amendmentAge = multiAgentRelativeAge(amendment.created);
          if (amendmentAge) {
            amendmentsHtml += "<span class='multi-agent-chip'>" + escHtml(amendmentAge) + "</span>";
          }
          amendmentsHtml += "</div>";
          amendmentsHtml += "<div class='multi-agent-card-actions'>";
          amendmentsHtml += "<button type='button' data-action='triage-decide' data-proposal-id='" + escAttr(amendmentId) + "'>Accept</button>";
          amendmentsHtml += "<button type='button' class='ghost' data-action='triage-decide' data-proposal-id='" + escAttr(amendmentId) + "' data-decision='dismissed'>Dismiss</button>";
          amendmentsHtml += "</div>";
          amendmentsHtml += "</article>";
        }
      }
      el.multi_agentAmendmentsList.innerHTML = amendmentsHtml;
    }

    if (el.multi_agentCommitmentsList) {
      var commitmentsHtml = "";
      if (!commitments.length) {
        commitmentsHtml = "<p class='empty-state subtle-empty'>No commitments yet. Agent commitments will appear here with status updates over time.</p>";
      } else {
        for (var c = 0; c < commitments.length; c += 1) {
          var commitment = commitments[c] || {};
          var commitmentId = trim(String(commitment.id || ""));
          if (!commitmentId) {
            continue;
          }
          var commitmentStatus = multiAgentCommitmentStatus(commitment.status);
          commitmentsHtml += "<article class='multi_agent-item multi-agent-card'>";
          commitmentsHtml += "<p class='multi-agent-card-title'>" + escHtml(commitment.statement || "") + "</p>";
          commitmentsHtml += "<div class='multi-agent-chip-row'>";
          commitmentsHtml += "<span class='multi-agent-chip status-" + escAttr(commitmentStatus) + "'>" + escHtml(multiAgentCommitmentStatusLabel(commitmentStatus)) + "</span>";
          commitmentsHtml += "<span class='multi-agent-chip'>scope: " + escHtml(commitment.scope || "project") + "</span>";
          commitmentsHtml += "<span class='multi-agent-chip'>duration: " + escHtml(commitment.duration || "unspecified") + "</span>";
          commitmentsHtml += "<span class='multi-agent-chip'>revocability: " + escHtml(commitment.revocability || "revocable") + "</span>";
          commitmentsHtml += "<span class='multi-agent-chip'>audience: " + escHtml(commitment.audience || "internal") + "</span>";
          commitmentsHtml += "</div>";
          var commitmentAge = multiAgentRelativeAge(commitment.created);
          if (commitmentAge) {
            commitmentsHtml += "<p class='multi-agent-card-meta'>Created " + escHtml(commitmentAge) + "</p>";
          }
          commitmentsHtml += "<div class='multi-agent-card-actions'>";
          if (commitmentStatus === "active") {
            commitmentsHtml += "<button type='button' data-action='multi_agent-commitment-status' data-workspace-id='" + escAttr(wsId) + "' data-entry-id='" + escAttr(commitmentId) + "' data-status='fulfilled'>Fulfilled</button>";
            commitmentsHtml += "<button type='button' class='ghost' data-action='multi_agent-commitment-status' data-workspace-id='" + escAttr(wsId) + "' data-entry-id='" + escAttr(commitmentId) + "' data-status='revoked'>Revoke</button>";
          } else {
            commitmentsHtml += "<button type='button' data-action='multi_agent-commitment-status' data-workspace-id='" + escAttr(wsId) + "' data-entry-id='" + escAttr(commitmentId) + "' data-status='active'>Reopen</button>";
          }
          commitmentsHtml += "<button type='button' class='ghost' data-action='multi_agent-log-delete' data-workspace-id='" + escAttr(wsId) + "' data-log-kind='commitments' data-entry-id='" + escAttr(commitmentId) + "'>Delete</button>";
          commitmentsHtml += "</div>";
          commitmentsHtml += "</article>";
        }
      }
      el.multi_agentCommitmentsList.innerHTML = commitmentsHtml;
    }

    if (el.multi_agentInterpretationList) {
      var interpretationHtml = "";
      if (!interpretations.length) {
        interpretationHtml = "<p class='empty-state subtle-empty'>No interpretation notes.</p>";
      } else {
        for (var it = 0; it < interpretations.length; it += 1) {
          var entry = interpretations[it] || {};
          var interpretationId = trim(String(entry.id || ""));
          if (!interpretationId) {
            continue;
          }
          interpretationHtml += "<article class='multi_agent-item multi-agent-card'>";
          interpretationHtml += "<p class='multi-agent-card-body'>" + escHtml(entry.statement || "") + "</p>";
          var interpretationAge = multiAgentRelativeAge(entry.created);
          if (interpretationAge) {
            interpretationHtml += "<p class='multi-agent-card-meta'>Added " + escHtml(interpretationAge) + "</p>";
          }
          interpretationHtml += "<div class='multi-agent-card-actions'>";
          interpretationHtml += "<button type='button' class='ghost' data-action='multi_agent-log-delete' data-workspace-id='" + escAttr(wsId) + "' data-log-kind='interpretation' data-entry-id='" + escAttr(interpretationId) + "'>Delete</button>";
          interpretationHtml += "</div>";
          interpretationHtml += "</article>";
        }
      }
      el.multi_agentInterpretationList.innerHTML = interpretationHtml;
    }
  }

  function handleWorkspaceTreeClick(event) {
    var target = event.target.closest("[data-action]");
    if (!target) {
      return;
    }

    var action = target.getAttribute("data-action");
    var workspaceId = target.getAttribute("data-workspace-id");
    var conversationId = target.getAttribute("data-conversation-id");
    var proposalId = target.getAttribute("data-proposal-id");
    var automationId = target.getAttribute("data-automation-id");
    var threadNavigationAction = (
      action === "toggle-workspace" ||
      action === "new-conversation" ||
      action === "select-workspace" ||
      action === "select-conversation" ||
      action === "select-draft"
    );
    if (state.sidebarSection === "automations" && threadNavigationAction) {
      saveSidebarSection("threads");
    }

    if (action === "automation-toggle-label") {
      event.preventDefault();
      event.stopPropagation();
      return;
    }

    if (action === "open-threads") {
      event.preventDefault();
      saveSidebarSection("threads");
      renderUi();
      return;
    }

    if (action === "automation-new") {
      event.preventDefault();
      event.stopPropagation();
      if (!state.workspaces.length) {
        showError(new Error("Add a project before creating automations."));
        return;
      }
      saveSidebarSection("automations");
