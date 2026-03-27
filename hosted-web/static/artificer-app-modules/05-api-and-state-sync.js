      }
      matchedMode = mappedMode;
      matchedTag = tag;
      working = working.slice(match[0].length);
      guard += 1;
      if (!/^\s*\/[a-z]/i.test(working)) {
        break;
      }
    }
    return {
      mode: matchedMode,
      tag: matchedTag,
      skillIds: parsePromptExplicitSkillTags(working),
      prompt: trim(working),
      raw: raw
    };
  }

  function runtimeModeById(modeId) {
    var target = trim(String(modeId || ""));
    if (!target) {
      return null;
    }
    var runtime = normalizeModeRuntime(state.modeRuntime);
    var modes = Array.isArray(runtime.modes) ? runtime.modes : [];
    for (var i = 0; i < modes.length; i += 1) {
      var mode = modes[i] || {};
      if (String(mode.id || "") === target) {
        return mode;
      }
    }
    return null;
  }

  function normalizeAssistantModeId(modeId) {
    var value = trim(String(modeId || "")).toLowerCase();
    if (!value) {
      return "";
    }
    if (!/^[a-z0-9._-]+$/.test(value)) {
      return "";
    }
    var runtime = normalizeModeRuntime(state.modeRuntime);
    var modes = Array.isArray(runtime.modes) ? runtime.modes : [];
    if (!modes.length) {
      return value;
    }
    var mode = runtimeModeById(value);
    if (!mode) {
      return "";
    }
    return value;
  }

  function saveAssistantModeId(modeId) {
    var next = normalizeAssistantModeId(modeId);
    state.assistantModeId = next;
    storageSet("artificer.assistantModeId", next);
  }

  function reconcileAssistantModeId() {
    var next = normalizeAssistantModeId(state.assistantModeId);
    if (next === state.assistantModeId) {
      return;
    }
    state.assistantModeId = next;
    storageSet("artificer.assistantModeId", next);
  }

  function assistantModeLabel(modeId) {
    var mode = runtimeModeById(modeId);
    if (!mode) {
      return "";
    }
    return trim(String(mode.name || mode.id || ""));
  }

  function normalizeRunMode(mode) {
    var value = String(mode || "").toLowerCase();
    if (value === "team" || value === "teams") {
      value = "assistant";
    }
    if (
      value !== "instant" &&
      value !== "auto" &&
      value !== "programming" &&
      value !== "pentest" &&
      value !== "security-audit" &&
      value !== "chat" &&
      value !== "teacher" &&
      value !== "report" &&
      value !== "text-perfecter" &&
      value !== "gui-testing" &&
      value !== "assistant"
    ) {
      value = "auto";
    }
    return value;
  }

  function runModeLabel(mode) {
    var value = normalizeRunMode(mode);
    if (value === "instant") {
      return "Instant";
    }
    if (value === "programming") {
      return "Programming";
    }
    if (value === "pentest") {
      return "Pentest";
    }
    if (value === "security-audit") {
      return "Security Audit";
    }
    if (value === "chat") {
      return "Chat";
    }
    if (value === "teacher") {
      return "Teacher";
    }
    if (value === "report") {
      return "Report";
    }
    if (value === "text-perfecter") {
      return "Text Perfecter";
    }
    if (value === "gui-testing") {
      return "GUI Testing";
    }
    if (value === "assistant") {
      var focusLabel = assistantModeLabel(state.assistantModeId);
      if (focusLabel) {
        return "Team - " + focusLabel;
      }
      return "Team";
    }
    return "Auto/Thinking";
  }

  function runModeDescription(mode) {
    var value = normalizeRunMode(mode);
    if (value === "instant") {
      return "Single-pass quick reply. Fastest turnaround.";
    }
    if (value === "programming") {
      return "Code-specialized loop with stronger execution and verification defaults. Inline tag: /task";
    }
    if (value === "pentest") {
      return "Adversarial security testing mode for exploit-path discovery and mitigation validation. Inline tag: /pentest";
    }
    if (value === "security-audit") {
      return "Systematic security audit mode for risk analysis, hardening, and evidence-backed remediation. Inline tag: /security-audit";
    }
    if (value === "chat") {
      return "Human conversation mode. Direct assistant-style responses. Inline tag: /chat";
    }
    if (value === "teacher") {
      return "Personalized teaching mode with learner modeling, curriculum sequencing, and spaced review prompts. Inline tag: /teacher";
    }
    if (value === "report") {
      return "Extended investigation mode that prioritizes evidence gathering and report-quality output. Inline tag: /report";
    }
    if (value === "text-perfecter") {
      return "Iterative text-and-content perfection mode with broad web research, contradiction checks, and convergence/stability stopping criteria. Inline tag: /text-perfecter";
    }
    if (value === "gui-testing") {
      return "Hands-on GUI testing mode that drives real browser automation (Safari/Firefox/system harness), detects UX flow defects, and verifies fixes with reruns. Inline tag: /gui-testing";
    }
    if (value === "assistant") {
      var focusMode = runtimeModeById(state.assistantModeId);
      if (focusMode) {
        return "Global LLM team mode with long-loop initiative. Active team: " + (focusMode.name || focusMode.id) + ". " + (focusMode.description || "");
      }
      return "Global LLM team mode with long-loop initiative within safety and approval constraints. Inline tag: /assistant or /team";
    }
    return "Adaptive default. Balanced thinking loop for mixed tasks.";
  }

  function runModeDefaultProfile(mode) {
    var value = normalizeRunMode(mode);
    if (value === "instant") {
      return { advancedLoop: false, reasoning: "low", minIterations: 1, maxIterations: 2 };
    }
    if (value === "programming") {
      return { advancedLoop: true, reasoning: "high", minIterations: 6, maxIterations: 12 };
    }
    if (value === "pentest") {
      return { advancedLoop: true, reasoning: "extra-high", minIterations: 8, maxIterations: 16 };
    }
    if (value === "security-audit") {
      return { advancedLoop: true, reasoning: "high", minIterations: 8, maxIterations: 16 };
    }
    if (value === "chat") {
      return { advancedLoop: false, reasoning: "medium", minIterations: 1, maxIterations: 2 };
    }
    if (value === "teacher") {
      return { advancedLoop: true, reasoning: "high", minIterations: 6, maxIterations: 12 };
    }
    if (value === "report") {
      return { advancedLoop: true, reasoning: "high", minIterations: 8, maxIterations: 12 };
    }
    if (value === "text-perfecter") {
      return { advancedLoop: true, reasoning: "extra-high", minIterations: 8, maxIterations: 14 };
    }
    if (value === "gui-testing") {
      return { advancedLoop: true, reasoning: "extra-high", minIterations: 10, maxIterations: 14 };
    }
    if (value === "assistant") {
      return { advancedLoop: true, reasoning: "extra-high", minIterations: 10, maxIterations: 12 };
    }
    return { advancedLoop: true, reasoning: "medium", minIterations: 2, maxIterations: 12 };
  }

  function reasoningRank(level) {
    if (level === "low") {
      return 1;
    }
    if (level === "high") {
      return 3;
    }
    if (level === "extra-high") {
      return 4;
    }
    return 2;
  }

  function saveRunMode(mode) {
    var next = normalizeRunMode(mode);
    var profile = runModeDefaultProfile(next);
    state.runMode = next;
    storageSet("artificer.runMode", next);
    saveAgentLoopEnabled(!!profile.advancedLoop);
    saveReasoningEffort(profile.reasoning);
  }

  function saveReasoningEffort(level) {
    var next = "medium";
    if (level === "low" || level === "medium" || level === "high" || level === "extra-high") {
      next = level;
    }
    state.reasoningEffort = next;
    storageSet("artificer.reasoningEffort", next);
  }

  function normalizeComputeBudget(value) {
    var next = String(value || "").toLowerCase();
    if (
      next !== "auto" &&
      next !== "quick" &&
      next !== "standard" &&
      next !== "long" &&
      next !== "until-complete"
    ) {
      next = "auto";
    }
    return next;
  }

  function saveComputeBudget(value) {
    var next = normalizeComputeBudget(value);
    state.computeBudget = next;
    storageSet("artificer.computeBudget", next);
  }

  function normalizeProgrammerReviewEnabledValue(value) {
    if (value === true || value === 1 || value === "1") {
      return true;
    }
    var text = String(value || "").toLowerCase();
    if (
      text === "true" ||
      text === "yes" ||
      text === "on" ||
      text === "enabled"
    ) {
      return true;
    }
    if (
      text === "false" ||
      text === "no" ||
      text === "off" ||
      text === "disabled" ||
      text === "0"
    ) {
      return false;
    }
    return !!value;
  }

  function normalizeProgrammerReviewRoundsValue(value) {
    var rounds = Number(value);
    if (!isFinite(rounds) || rounds < 1) {
      rounds = 2;
    }
    rounds = Math.floor(rounds);
    if (rounds < 1) {
      rounds = 1;
    } else if (rounds > 4) {
      rounds = 4;
    }
    return rounds;
  }

  function saveProgrammerReviewEnabled(enabled) {
    state.programmerReviewEnabled = !!enabled;
    storageSet("artificer.programmerReviewEnabled", state.programmerReviewEnabled ? "1" : "0");
  }

  function saveProgrammerReviewRounds(rounds) {
    state.programmerReviewRounds = normalizeProgrammerReviewRoundsValue(rounds);
    storageSet("artificer.programmerReviewRounds", String(state.programmerReviewRounds));
  }

  function computeBudgetLabel(value) {
    var next = normalizeComputeBudget(value);
    if (next === "quick") {
      return "Instant";
    }
    if (next === "standard") {
      return "Standard";
    }
    if (next === "long") {
      return "Long-term";
    }
    if (next === "until-complete") {
      return "Until Complete";
    }
    return "Auto";
  }

  function computeBudgetRequestTimeoutMs(value, runPayload) {
    var budget = normalizeComputeBudget(value);
    if (budget === "quick") {
      return 10 * 60 * 1000;
    }
    if (budget === "standard") {
      return 25 * 60 * 1000;
    }
    if (budget === "long") {
      return 90 * 60 * 1000;
    }
    if (budget === "until-complete") {
      return 8 * 60 * 60 * 1000;
    }

    var timeoutMs = 20 * 60 * 1000;
    var maxIterations = Number(runPayload && runPayload.max_iterations ? runPayload.max_iterations : 0);
    var advancedLoop = String(runPayload && runPayload.advanced_loop ? runPayload.advanced_loop : "") === "1";
    var reasoning = String(runPayload && runPayload.reasoning_effort ? runPayload.reasoning_effort : "").toLowerCase();
    var promptText = String(runPayload && runPayload.prompt ? runPayload.prompt : "");
    var promptLower = promptText.toLowerCase();

    if (advancedLoop) {
      timeoutMs = Math.max(timeoutMs, 30 * 60 * 1000);
    }
    if (maxIterations >= 10) {
      timeoutMs = Math.max(timeoutMs, 36 * 60 * 1000);
    } else if (maxIterations >= 8) {
      timeoutMs = Math.max(timeoutMs, 30 * 60 * 1000);
    }
    if (reasoning === "high" || reasoning === "extra-high") {
      timeoutMs = Math.max(timeoutMs, 28 * 60 * 1000);
    }
    if (promptText.length > 900) {
      timeoutMs = Math.max(timeoutMs, 28 * 60 * 1000);
    }
    if (
      /godot|barnes[- ]?hut|checksum|deterministic replay|final[ -]?state|regression|self[- ]?tests?|gameplay|challenge|polish|interactiv|objective|score|combo|large[ -]?context|architecture|monorepo|migration|distributed|launch|business|compliance|operations|curriculum|lesson plan|spaced review|pedagog|learning model|tutor/.test(promptLower)
    ) {
      timeoutMs = Math.max(timeoutMs, 45 * 60 * 1000);
    }
    return timeoutMs;
  }

  function computeBudgetQueueWatchTimeoutMs(value) {
    var budget = normalizeComputeBudget(value);
    if (budget === "quick") {
      return 12 * 60 * 1000;
    }
    if (budget === "standard") {
      return 35 * 60 * 1000;
    }
    if (budget === "long") {
      return 2 * 60 * 60 * 1000;
    }
    if (budget === "until-complete") {
      return 10 * 60 * 60 * 1000;
    }
    return 45 * 60 * 1000;
  }

  function reasoningLabel(level) {
    if (level === "low") {
      return "Low";
    }
    if (level === "high") {
      return "High";
    }
    if (level === "extra-high") {
      return "Extra High";
    }
    return "Medium";
  }

  function reasoningIconMarkup() {
    return "<svg viewBox='0 0 16 16' fill='none' stroke='currentColor' stroke-width='1.35' stroke-linecap='round' stroke-linejoin='round'><path d='M5.1 3.2c-.9 0-1.8.7-1.8 1.8 0 .4.1.8.4 1.1-.7.4-1.1 1-1.1 1.8 0 1.2.9 2.1 2.1 2.1.1 1.1 1 1.9 2.1 1.9 1 0 1.8-.6 2.1-1.5.2.9 1.1 1.5 2.1 1.5 1.1 0 2-.8 2.1-1.9 1.2 0 2.1-.9 2.1-2.1 0-.8-.4-1.4-1.1-1.8.2-.3.4-.7.4-1.1 0-1-.8-1.8-1.8-1.8-.4 0-.8.1-1.1.4-.4-.8-1.2-1.3-2.1-1.3-.9 0-1.7.5-2.1 1.3-.3-.2-.7-.4-1.1-.4z'></path><path d='M6.3 5.8c-.6.2-.9.6-.9 1.1'></path><path d='M8 5.4v4.3'></path><path d='M9.8 5.9c.6.2.9.6.9 1.1'></path><path d='M6.4 8.6c.4.4 1 .6 1.6.6'></path><path d='M9.6 8.6c-.4.4-1 .6-1.6.6'></path></svg>";
  }

  function effectiveRunProfileForMode(modeValue) {
    var reasoningToIterations = {
      low: 2,
      medium: 4,
      high: 6,
      "extra-high": 8
    };
    var mode = normalizeRunMode(modeValue || state.runMode);
    var defaults = runModeDefaultProfile(mode);
    var reasoning = String(state.reasoningEffort || defaults.reasoning || "medium");
    if (reasoningRank(reasoning) < reasoningRank(defaults.reasoning)) {
      reasoning = defaults.reasoning;
    }
    var iterations = reasoningToIterations[reasoning] || 4;
    if (Number(defaults.minIterations || 0) > iterations) {
      iterations = Number(defaults.minIterations || iterations);
    }
    var maxIterations = Number(defaults.maxIterations || 0);
    if (maxIterations > 0 && iterations > maxIterations) {
      iterations = maxIterations;
    }
    var advancedLoop = !!defaults.advancedLoop;
    if (mode === "auto") {
      advancedLoop = !!state.agentLoopEnabled;
    }
    return {
      mode: mode,
      reasoning: reasoning,
      maxIterations: iterations,
      advancedLoop: advancedLoop,
      computeBudget: normalizeComputeBudget(state.computeBudget)
    };
  }

  function effectiveRunProfile() {
    return effectiveRunProfileForMode(state.runMode);
  }

  function saveNetworkAccess(enabled) {
    state.networkAccess = !!enabled;
    storageSet("artificer.networkAccess", state.networkAccess ? "1" : "0");
  }

  function saveWebAccess(enabled) {
    state.webAccess = !!enabled;
    storageSet("artificer.webAccess", state.webAccess ? "1" : "0");
  }

  function appendTerminalLine(line) {
    var next = state.terminalStreamText + String(line || "") + "\n";
    if (next.length > 180000) {
      next = next.slice(next.length - 180000);
    }
    state.terminalStreamText = next;
    renderTerminal();
  }

  function titleFromPrompt(promptText) {
    var directive = parsePromptModeDirective(promptText);
    var titleSource = trim(directive.prompt || promptText);
    var first = trim(String(titleSource || "").split(/\r?\n/)[0] || "");
    if (!first) {
      return "New Thread";
    }
    if (first.length > 52) {
      return first.slice(0, 49) + "...";
    }
    return first;
  }

  function clearDraftAutosaveTimer() {
    if (saveDraftTimer) {
      clearTimeout(saveDraftTimer);
      saveDraftTimer = null;
    }
  }

  function revokeAttachmentPreview(attachment) {
    if (attachment && attachment.previewUrl) {
      URL.revokeObjectURL(attachment.previewUrl);
    }
  }

  function clearPendingAttachments() {
    for (var i = 0; i < state.pendingAttachments.length; i += 1) {
      revokeAttachmentPreview(state.pendingAttachments[i]);
    }
    state.pendingAttachments = [];
  }

  function resetComposerAttachments() {
    clearPendingAttachments();
    state.composerDragDepth = 0;
    setComposerDragActive(false);
    renderAttachmentStrip();
  }

  function removePendingAttachmentById(attachmentId) {
    var kept = [];
    for (var i = 0; i < state.pendingAttachments.length; i += 1) {
      var attachment = state.pendingAttachments[i];
      if (attachment.id === attachmentId) {
        revokeAttachmentPreview(attachment);
      } else {
        kept.push(attachment);
      }
    }
    state.pendingAttachments = kept;
    renderAttachmentStrip();
  }

  function attachmentAlreadyQueued(file) {
    var name = String(file && file.name || "");
    var size = Number(file && file.size || 0);
    var lastModified = Number(file && file.lastModified || 0);
    for (var i = 0; i < state.pendingAttachments.length; i += 1) {
      var attachment = state.pendingAttachments[i];
      if (attachment.name === name && Number(attachment.size || 0) === size && Number(attachment.lastModified || 0) === lastModified) {
        return true;
      }
    }
    return false;
  }

  function addComposerAttachment(file) {
    if (!file) {
      return;
    }

    if (attachmentAlreadyQueued(file)) {
      return;
    }

    var kind = attachmentKindForFile(file);
    if (!kind) {
      throw new Error("Unsupported file type for attachment: " + String(file.name || "file"));
    }

    var maxBytes = 15 * 1024 * 1024;
    if (Number(file.size || 0) > maxBytes) {
      throw new Error("Attachment too large: " + String(file.name || "file") + " (" + formatBytes(file.size) + "). Max 15 MB.");
    }

    var previewUrl = URL.createObjectURL(file);

    state.pendingAttachments.push({
      id: newClientAttachmentId(),
      file: file,
      name: String(file.name || "attachment"),
      mime: String(file.type || ""),
      size: Number(file.size || 0),
      lastModified: Number(file.lastModified || 0),
      kind: kind,
      previewUrl: previewUrl
    });
  }

  function addComposerFiles(fileList) {
    if (!fileList || !fileList.length) {
      return;
    }

    for (var i = 0; i < fileList.length; i += 1) {
      addComposerAttachment(fileList[i]);
    }
    renderAttachmentStrip();
  }

  function attachmentById(attachmentId) {
    for (var i = 0; i < state.pendingAttachments.length; i += 1) {
      if (state.pendingAttachments[i].id === attachmentId) {
        return state.pendingAttachments[i];
      }
    }
    return null;
  }

  function openAttachmentPreview(attachmentId) {
    var attachment = attachmentById(attachmentId);
    if (!attachment || !attachment.previewUrl) {
      return;
    }
    window.open(attachment.previewUrl, "_blank", "noopener");
  }

  function fileToBase64(file) {
    return new Promise(function (resolve, reject) {
      var reader = new FileReader();
      reader.onload = function () {
        var dataUrl = String(reader.result || "");
        var comma = dataUrl.indexOf(",");
        if (comma < 0) {
          reject(new Error("Could not read attachment data."));
          return;
        }
        resolve(dataUrl.slice(comma + 1));
      };
      reader.onerror = function () {
        reject(new Error("Could not read attachment: " + String(file && file.name || "file")));
      };
      reader.readAsDataURL(file);
    });
  }

  function uploadAttachment(workspaceId, conversationId, attachment) {
    return fileToBase64(attachment.file).then(function (encoded) {
      return apiPost("upload_attachment", {
        workspace_id: workspaceId,
        conversation_id: conversationId,
        name: attachment.name,
        mime: attachment.mime,
        data: encoded
      }).then(function (response) {
        if (!response.success || !response.attachment || !response.attachment.id) {
          throw new Error(response.error || "Failed to upload attachment");
        }
        return response.attachment;
      });
    });
  }

  function uploadPendingAttachments(workspaceId, conversationId) {
    if (!state.pendingAttachments.length) {
      return Promise.resolve([]);
    }

    var uploaded = [];
    var chain = Promise.resolve();
    for (var i = 0; i < state.pendingAttachments.length; i += 1) {
      (function (attachment) {
        chain = chain.then(function () {
          return uploadAttachment(workspaceId, conversationId, attachment).then(function (item) {
            uploaded.push(item);
          });
        });
      })(state.pendingAttachments[i]);
    }
    return chain.then(function () {
      return uploaded;
    });
  }

  function loadState(options) {
    var requestOptions = null;
    var requestParams = { level: "light", cached: "1" };
    if (Object.keys(state.optimisticConversationsByKey || {}).length > 0) {
      // While client-created threads are awaiting server acknowledgement,
      // prefer uncached state to prevent stale snapshots from hiding them.
      requestParams.cached = "0";
    }
    if (options && Number(options.timeoutMs) > 0) {
      requestOptions = { timeoutMs: Number(options.timeoutMs) };
    }
    if (options && options.full) {
      requestParams.level = "full";
    }
    if (options && options.fresh) {
      requestParams.cached = "0";
    }
    return apiGet("state", requestParams, requestOptions).then(function (response) {
      if (!response.success) {
        throw new Error(response.error || "Failed to load state");
      }
      var incomingStateRevision = normalizeStateRevision(response.state_revision);
      if (
        incomingStateRevision > 0 &&
        state.stateRevisionApplied > 0 &&
        incomingStateRevision < state.stateRevisionApplied
      ) {
        // Ignore stale state payloads that arrive late after a fresher revision was already applied.
        return;
      }
      if (incomingStateRevision > state.stateRevisionApplied) {
        state.stateRevisionApplied = incomingStateRevision;
      }
      state.workspaces = response.workspaces || [];
      pruneExpiredPendingOutgoing();
      mergeOptimisticConversationsIntoWorkspaces(state.workspaces);
      state.modeRuntime = normalizeModeRuntime(response.mode_runtime);
      state.triage = {
        count: String((response.triage && response.triage.count) || "0"),
        cards: Array.isArray(response.triage && response.triage.cards) ? response.triage.cards : []
      };
      applyAutomationsState(response.automations);
      state.multi_agentCatalog = response.multi_agent_catalog && typeof response.multi_agent_catalog === "object"
        ? response.multi_agent_catalog
        : { curated_residents: [], target_types: [], escalation_classes: [] };
      reconcileAssistantModeId();
      state.modeRuntimeError = "";
      for (var i = 0; i < state.workspaces.length; i += 1) {
        if (typeof state.workspaces[i].multi_agent_background_residents === "undefined") {
          state.workspaces[i].multi_agent_background_residents = "0";
        } else {
          state.workspaces[i].multi_agent_background_residents = String(state.workspaces[i].multi_agent_background_residents || "0");
        }
        if (!Array.isArray(state.workspaces[i].multi_agent_residents)) {
          state.workspaces[i].multi_agent_residents = [];
        }
        if (!Array.isArray(state.workspaces[i].multi_agent_unratified_amendments)) {
          state.workspaces[i].multi_agent_unratified_amendments = [];
        }
        if (!state.workspaces[i].multi_agent_toggles || typeof state.workspaces[i].multi_agent_toggles !== "object") {
          state.workspaces[i].multi_agent_toggles = {};
        }
        if (!Array.isArray(state.workspaces[i].conversations)) {
          state.workspaces[i].conversations = [];
        }
        for (var j = 0; j < state.workspaces[i].conversations.length; j += 1) {
          var conv = state.workspaces[i].conversations[j];
          if (typeof conv.created === "undefined" || conv.created === null || conv.created === "") {
            if (typeof conv.updated !== "undefined" && conv.updated !== null && conv.updated !== "") {
              conv.created = String(conv.updated);
            } else {
              conv.created = "0";
            }
          } else {
            conv.created = String(conv.created);
          }
          if (typeof conv.updated === "undefined" || conv.updated === null || conv.updated === "") {
            conv.updated = conv.created;
          } else {
            conv.updated = String(conv.updated);
          }
          if (typeof conv.queue_pending === "undefined") {
            conv.queue_pending = "0";
          }
          if (typeof conv.queue_running === "undefined") {
            conv.queue_running = "0";
          }
          if (typeof conv.queue_done === "undefined") {
            conv.queue_done = "0";
          }
          if (typeof conv.queue_last_status === "undefined") {
            conv.queue_last_status = "";
          }
          if (typeof conv.queue_first_id === "undefined") {
            conv.queue_first_id = "";
          }
          conv.decision_request = normalizeDecisionRequest(conv.decision_request);
          conv.approval_request = normalizeApprovalRequest(conv.approval_request);
        }
      }
      if (state.activeTriage && Number(state.triage.count || 0) < 1) {
        state.activeTriage = false;
      }
      reconcilePendingOutgoingFromWorkspaceSummaries();
      syncWorkspaceOrderingWithState({ prependUnknownWorkspaces: true });
      persistWorkspaceOrderingState();
      saveWorkspaceStateCache(state.workspaces);
      bootstrapSeenConversationsIfNeeded();
      pruneSeenConversationState();
      pruneRunEventsByKnownConversations();
      applyRouteSelectionIfPending();
      ensureSelection();
      reconcileRunEventsFromQueueState();
      syncSelectionUrl(true);
    });
  }

  function loadModels() {
    return apiGet("models").then(function (response) {
      if (!response.success) {
        throw new Error(response.error || "Failed to load models");
      }
      state.modelLoadError = "";
      state.models = response.models || [];
    });
  }

  function loadModelCatalog() {
    return apiGet("model_catalog").then(function (response) {
      if (!response.success) {
        throw new Error(response.error || "Failed to load model catalog");
      }
      state.modelCatalog = response.available || [];
      state.modelInstalls = response.installs || [];
    });
  }

  function refreshModelData(options) {
    var opts = options || {};
    var force = !!opts.force;
    var silent = opts.silent !== false;
    var now = Date.now();
    if (modelAutoRefreshBusy && !force) {
      return Promise.resolve(false);
    }
    if (!force && modelAutoRefreshLastAt > 0 && now - modelAutoRefreshLastAt < 2500) {
      return Promise.resolve(false);
    }
    modelAutoRefreshBusy = true;
    return Promise.all([
      loadModels().catch(function (err) {
        state.models = [];
        state.modelLoadError = err && err.message ? err.message : "Model check failed";
        return null;
      }),
      loadModelCatalog().catch(function () {
        state.modelCatalog = [];
        state.modelInstalls = [];
        return null;
      })
    ]).then(function () {
      syncModelInstallPollingFromCatalog();
      modelAutoRefreshLastAt = Date.now();
      if (!silent) {
        renderUi();
      }
      return true;
    }).finally(function () {
      modelAutoRefreshBusy = false;
    });
  }

  function startModelAutoRefreshLoop() {
    if (modelAutoRefreshTimer) {
      clearInterval(modelAutoRefreshTimer);
      modelAutoRefreshTimer = null;
    }
    modelAutoRefreshTimer = setInterval(function () {
      refreshModelData({ silent: true }).then(function (updated) {
        if (updated) {
          renderUi();
        }
      }).catch(function () {
        return null;
      });
    }, 15000);
  }

  function stopModelAutoRefreshLoop() {
    if (modelAutoRefreshTimer) {
      clearInterval(modelAutoRefreshTimer);
      modelAutoRefreshTimer = null;
    }
  }

  function loadAppIcons() {
    return apiGet("app_icons").then(function (response) {
      if (!response.success) {
        throw new Error(response.error || "Failed to load app icons");
      }
      state.appIcons = {
        finder: String(response.finder || ""),
        textmate: String(response.textmate || "")
      };
    });
  }

  function stopModelInstallPolling() {
    if (modelInstallPollTimer) {
      clearInterval(modelInstallPollTimer);
      modelInstallPollTimer = null;
    }
  }

  function pollModelInstallStatus(jobId) {
    if (!jobId) {
      return Promise.resolve();
    }
    return apiGet("model_install_status", { job_id: jobId }).then(function (response) {
      if (!response.success) {
        throw new Error(response.error || "Failed to load install status");
      }
      state.modelInstallJob = response.job || null;
      state.modelInstallLog = response.job && response.job.log ? String(response.job.log) : "";
      if (response.job) {
        var replaced = false;
        for (var i = 0; i < state.modelInstalls.length; i += 1) {
          if (String(state.modelInstalls[i].id || "") === String(response.job.id || "")) {
            state.modelInstalls[i] = response.job;
            replaced = true;
            break;
          }
        }
        if (!replaced) {
          state.modelInstalls.unshift(response.job);
        }
      }

      var status = String((response.job && response.job.status) || "");
      if (status === "done" || status === "failed") {
        stopModelInstallPolling();
        return loadModels()
          .catch(function () { return null; })
          .then(function () {
            return loadModelCatalog().catch(function () { return null; });
          })
          .then(function () {
            renderUi();
          });
      }
      renderUi();
      return null;
    });
  }

  function ensureModelInstallPolling(jobId) {
    if (!jobId) {
      return;
    }
    stopModelInstallPolling();
    modelInstallPollTimer = setInterval(function () {
      pollModelInstallStatus(jobId).catch(function () {
        return null;
      });
    }, 1200);
  }

  function syncModelInstallPollingFromCatalog() {
    var runningJobId = "";
    for (var i = 0; i < state.modelInstalls.length; i += 1) {
      var job = state.modelInstalls[i] || {};
      if (String(job.status || "") === "running" && String(job.id || "")) {
        runningJobId = String(job.id);
        state.modelInstallJob = job;
        break;
      }
    }
    if (runningJobId) {
      ensureModelInstallPolling(runningJobId);
    } else {
      stopModelInstallPolling();
    }
  }

  function startModelInstall(modelName) {
    var target = trim(modelName);
    if (!target) {
      return Promise.resolve();
    }
    return apiPost("model_install_start", { model: target }, { timeoutMs: 12000 }).then(function (response) {
      if (!response.success || !response.job) {
        throw new Error(response.error || "Model install failed to start");
      }
      state.modelInstallJob = response.job;
      state.modelInstallLog = "";
      ensureModelInstallPolling(String(response.job.id || ""));
      renderUi();
      return pollModelInstallStatus(String(response.job.id || "")).catch(function () {
        return null;
      });
    });
  }

  function startModelUninstall(modelName) {
    var target = trim(modelName);
    if (!target) {
      return Promise.resolve();
    }
    return apiPost("model_uninstall", { model: target }, { timeoutMs: 30000 }).then(function (response) {
      if (!response.success) {
        throw new Error(response.error || "Model uninstall failed");
      }
      return refreshModelData({ force: true, silent: false }).then(function () {
        renderUi();
      });
    });
  }

  function loadThemes() {
    return apiGet("themes").then(function (response) {
      if (!response.success) {
        throw new Error(response.error || "Failed to load themes");
      }
      var loadedThemes = normalizeThemes(response.themes || []);
      // If backend returns a sparse set (for example stale site assets),
      // merge with the known shared catalog so users still get full theme access.
      if (loadedThemes.length <= 1) {
        loadedThemes = normalizeThemes(loadedThemes.concat(themeNameListFallback()));
      }
      state.themes = loadedThemes;
      ensureActiveThemeInList();
      applyTheme(state.activeTheme);
    }).catch(function () {
      state.themes = normalizeThemes(themeNameListFallback());
      ensureActiveThemeInList();
      applyTheme(state.activeTheme);
    });
  }

  function loadConversation(options) {
    var opts = options || {};
    var explicitWorkspaceId = "";
    var explicitConversationId = "";
    if (opts && Object.prototype.hasOwnProperty.call(opts, "workspaceId")) {
      explicitWorkspaceId = String(opts.workspaceId || "");
    }
    if (opts && Object.prototype.hasOwnProperty.call(opts, "conversationId")) {
      explicitConversationId = String(opts.conversationId || "");
    }
    var workspaceId = explicitWorkspaceId || state.activeWorkspaceId;
    var conversationId = explicitConversationId || state.activeConversationId;
    var isExplicitTarget = !!(explicitWorkspaceId || explicitConversationId);
    var shouldShowLoading = !!opts.showLoading;
    var shouldApplyComposerDraft = !!opts.applyComposerDraft;
    if (!workspaceId || !conversationId) {
      if (!isExplicitTarget) {
        state.activeConversation = null;
        state.activeConversationSelectedAt = 0;
        setActiveConversationLoading("", "", false);
      }
      return Promise.resolve();
    }
    var targetLoadingKey = conversationReadKey(workspaceId, conversationId);
    var isCurrentActiveTarget = !isExplicitTarget || (
      state.activeWorkspaceId === workspaceId &&
      state.activeConversationId === conversationId
    );
    if (shouldShowLoading && isCurrentActiveTarget) {
      setActiveConversationLoading(workspaceId, conversationId, true);
      renderUi();
    }

    var requestOptions = null;
    if (opts && Number(opts.timeoutMs) > 0) {
      requestOptions = { timeoutMs: Number(opts.timeoutMs) };
    }

    return apiGet("get_conversation", {
      workspace_id: workspaceId,
      conversation_id: conversationId
    }, requestOptions).then(function (response) {
      if (!response.success) {
        throw new Error(response.error || "Failed to load thread");
      }
      if (!isExplicitTarget && (state.activeWorkspaceId !== workspaceId || state.activeConversationId !== conversationId)) {
        return null;
      }
      var conversation = response.conversation || null;
      if (conversation) {
        markOptimisticConversationSeen(workspaceId, conversation);
        var draftKey = outgoingKeyFor(workspaceId, conversationId, "");
        var existingLocalDraft = hasComposerDraftForKey(draftKey) ? String(state.composerDraftByKey[draftKey] || "") : "";
        var remoteDraft = String(conversation.draft || "");
        if (remoteDraft || !existingLocalDraft) {
          // Preserve unsaved local text when the server still reports an empty draft.
          setComposerDraftForKey(draftKey, remoteDraft);
        }
        conversation.decision_request = normalizeDecisionRequest(conversation.decision_request);
        conversation.approval_request = normalizeApprovalRequest(conversation.approval_request);
        if (Array.isArray(conversation.run_events)) {
          mergeConversationRunEvents(conversationId, conversation.run_events);
          backfillRunEventAnchorsFromMessages(
            conversationId,
            Array.isArray(conversation.messages) ? conversation.messages : []
          );
        }
        cacheConversationSnapshot(workspaceId, conversationId, conversation);
      }
      var isActiveTarget = state.activeWorkspaceId === workspaceId && state.activeConversationId === conversationId;
      if (isActiveTarget) {
        state.activeConversationLoadError = "";
        state.activeConversation = conversation;
        // Remove switching overlay in the same render pass as fresh conversation content.
        state.conversationSwitchOverlay = false;
        setActiveConversationLoading(workspaceId, conversationId, false);
        if (shouldApplyComposerDraft && el.runPrompt) {
          var nextDraftText = getComposerDraftForTarget(workspaceId, conversationId, "");
          if (String(el.runPrompt.value || "") !== nextDraftText) {
            el.runPrompt.value = nextDraftText;
            if (typeof el.runPrompt.setSelectionRange === "function") {
              var draftCaret = nextDraftText.length;
              el.runPrompt.setSelectionRange(draftCaret, draftCaret);
            }
          }
        }
        if (state.activeConversation) {
          finalizeStaleRunningEventsForConversation(workspaceId, state.activeConversation);
          reconcilePendingOutgoingFromConversation(workspaceId, conversationId, state.activeConversation);
          if (
            queueNumber(state.activeConversation.queue_pending) > 0 ||
            isQueueEditForConversation(workspaceId, conversationId)
          ) {
            loadQueueItems(workspaceId, conversationId, { minIntervalMs: 0 }).catch(function () {
              return null;
            });
          } else {
            clearQueueItemsForConversation(workspaceId, conversationId);
          }
        }
        if (opts.markSeen !== false) {
          markConversationSeen(workspaceId, conversationId, conversation);
        }
        if (opts.renderOnUpdate !== false) {
          renderUi();
        }
      }
      return conversation;
    }).finally(function () {
      if (
        shouldShowLoading &&
        targetLoadingKey &&
        state.activeConversationLoadingKey === targetLoadingKey
      ) {
        setActiveConversationLoading(workspaceId, conversationId, false);
      }
    });
  }

  function loadDraft(workspaceId) {
    if (!workspaceId) {
      return Promise.resolve("");
    }

    return apiGet("get_draft", { workspace_id: workspaceId }).then(function (response) {
      if (!response.success) {
        throw new Error(response.error || "Failed to load draft");
      }
      state.draftTextByWorkspace[workspaceId] = response.draft || "";
      return response.draft || "";
    });
  }

  function saveDraft(workspaceId, text) {
    if (!workspaceId) {
      return Promise.resolve();
    }

    return apiPost("save_draft", {
      workspace_id: workspaceId,
      draft: text
    }).then(function (response) {
      if (!response.success) {
        throw new Error(response.error || "Failed to save draft");
      }
      state.draftTextByWorkspace[workspaceId] = text;
      var ws = getWorkspaceById(workspaceId);
      if (ws) {
        ws.draft_exists = trim(text) ? "1" : "0";
      }
    });
  }

  function saveConversationDraft(workspaceId, conversationId, text) {
    if (!workspaceId || !conversationId) {
      return Promise.resolve();
    }
    return apiPost("save_conversation_draft", {
      workspace_id: workspaceId,
      conversation_id: conversationId,
      draft: String(text || "")
    }).then(function (response) {
      if (!response || !response.success) {
        throw new Error((response && response.error) || "Failed to save conversation draft");
      }
      return true;
    });
  }

  function saveComposerDraftDebounced() {
    var isWorkspaceDraft = !!state.activeDraftWorkspaceId;
    var workspaceId = String(state.activeWorkspaceId || "");
    var conversationId = String(state.activeConversationId || "");
    var draftWorkspaceId = String(state.activeDraftWorkspaceId || "");
    var draftText = String((el.runPrompt && el.runPrompt.value) || "");
    if (!isWorkspaceDraft && (!workspaceId || !conversationId)) {
      return;
    }

    clearDraftAutosaveTimer();
    saveDraftTimer = setTimeout(function () {
      if (isWorkspaceDraft) {
        saveDraft(draftWorkspaceId, draftText).catch(showError);
        return;
      }
      saveConversationDraft(workspaceId, conversationId, draftText).catch(showError);
    }, 550);
  }

  function clearPersistedComposerDraft(workspaceId, conversationId, draftWorkspaceId) {
    var wsId = String(workspaceId || "");
    var convId = String(conversationId || "");
    var draftWsId = String(draftWorkspaceId || "");
    if (draftWsId) {
      return saveDraft(draftWsId, "").catch(function () {
        return null;
      });
    }
    if (wsId && convId) {
      return saveConversationDraft(wsId, convId, "").catch(function () {
        return null;
      });
    }
    return Promise.resolve();
  }

  function persistComposerDraftForKey(key, text) {
    var parsed = parseOutgoingKey(key);
    var draftText = String(text || "");
    if (!parsed) {
      return Promise.resolve(false);
    }
    if (parsed.draftWorkspaceId) {
      state.draftTextByWorkspace[parsed.draftWorkspaceId] = draftText;
      return saveDraft(parsed.draftWorkspaceId, draftText).then(function () {
        return true;
      });
    }
    if (parsed.workspaceId && parsed.conversationId) {
      return saveConversationDraft(parsed.workspaceId, parsed.conversationId, draftText).then(function () {
        return true;
      });
    }
    return Promise.resolve(false);
  }

  function persistComposerDraftForKeys(keys, text) {
    var list = Array.isArray(keys) ? keys : [];
    var seen = {};
    var chain = Promise.resolve();
    for (var i = 0; i < list.length; i += 1) {
      (function (rawKey) {
        var key = String(rawKey || "");
        if (!key || seen[key]) {
          return;
        }
        seen[key] = true;
        chain = chain.then(function () {
          return persistComposerDraftForKey(key, text).catch(function () {
            return false;
          });
        });
      })(list[i]);
    }
    return chain;
  }

  function refreshGitStatus() {
    if (!state.activeWorkspaceId) {
      return Promise.resolve();
    }

    return apiGet("git_status", { workspace_id: state.activeWorkspaceId })
      .then(function (response) {
        if (!response.success) {
          throw new Error(response.error || "Failed to load git status");
        }
        state.gitByWorkspace[state.activeWorkspaceId] = {
          is_repo: !!response.is_repo,
          branch: response.branch || "",
          ahead: Number(response.ahead || 0),
          behind: Number(response.behind || 0),
          added: Number(response.added || 0),
          deleted: Number(response.deleted || 0),
          changes: Number(response.changes || 0),
          staged_changes: Number(response.staged_changes || 0),
          unstaged_changes: Number(response.unstaged_changes || 0)
        };
      })
      .catch(function (err) {
        state.gitByWorkspace[state.activeWorkspaceId] = {
          is_repo: false,
          branch: "",
          ahead: 0,
          behind: 0,
          added: 0,
          deleted: 0,
          changes: 0,
          staged_changes: 0,
          unstaged_changes: 0
        };
        throw err;
      });
  }

  function warmGitStatusForWorkspaces(workspaceIds) {
    var ids = Array.isArray(workspaceIds) ? workspaceIds.slice() : [];
    var chain = Promise.resolve();
    for (var i = 0; i < ids.length; i += 1) {
      (function (workspaceId) {
        if (!workspaceId || state.gitByWorkspace[workspaceId]) {
          return;
        }
        chain = chain.then(function () {
          return apiGet("git_status", { workspace_id: workspaceId })
            .then(function (response) {
              if (!response.success) {
                return;
              }
              state.gitByWorkspace[workspaceId] = {
                is_repo: !!response.is_repo,
                branch: response.branch || "",
                ahead: Number(response.ahead || 0),
                behind: Number(response.behind || 0),
                added: Number(response.added || 0),
                deleted: Number(response.deleted || 0),
                changes: Number(response.changes || 0),
                staged_changes: Number(response.staged_changes || 0),
                unstaged_changes: Number(response.unstaged_changes || 0)
              };
            })
            .catch(function () {
              return null;
            });
        });
      })(ids[i]);
    }
    return chain;
  }

  function refreshBranches() {
    if (!state.activeWorkspaceId) {
      return Promise.resolve();
    }

    return apiGet("git_branches", { workspace_id: state.activeWorkspaceId }).then(function (response) {
      if (!response.success) {
        throw new Error(response.error || "Failed to load branches");
      }
      state.branchesByWorkspace[state.activeWorkspaceId] = response.branches || [];
    });
  }

  function refreshDiff() {
    if (!state.activeWorkspaceId) {
      state.diffText = "";
      return Promise.resolve();
    }

    return apiGet("git_diff", { workspace_id: state.activeWorkspaceId }).then(function (response) {
      if (!response.success) {
        throw new Error(response.error || "Failed to load git diff");
      }
      state.diffText = response.diff || "";
      var gitState = activeGitState();
      if (!gitState.is_repo) {
        el.diffSummary.textContent = "Not a git repository.";
      } else {
        el.diffSummary.innerHTML = gitDeltaMarkup(response.added, response.deleted);
      }
    });
  }

  function refreshAll() {
    setArtificerBootPhase("loading-state", "Loading projects and threads…");
    return runWithRetry(function () {
      return loadState({ fast: true, fresh: true, timeoutMs: 30000 });
    }, 3, 220)
      .then(function () {
        var activeConversationPromise;
        if (state.activeWorkspaceId && state.activeConversationId) {
          setArtificerBootPhase("loading-conversation", "Loading current thread…");
          activeConversationPromise = loadConversation({
            showLoading: false,
            applyComposerDraft: true,
            timeoutMs: 12000
          });
        } else {
          state.activeConversation = null;
          state.activeConversationSelectedAt = 0;
          setActiveConversationLoading("", "", false);
          activeConversationPromise = Promise.resolve();
        }

        state.modelDataLoading = true;
        setArtificerBootPhase("loading-models", "Loading models…");

        var modelPromise = Promise.all([
          runWithRetry(loadModels, 3, 220).catch(function (err) {
            state.models = [];
            state.modelLoadError = err && err.message ? err.message : "Model check failed";
            return null;
          }),
          runWithRetry(loadModelCatalog, 2, 180).catch(function () {
            state.modelCatalog = [];
            state.modelInstalls = [];
            return null;
          }),
          runWithRetry(loadAppIcons, 2, 180).catch(function () {
            state.appIcons = { finder: "", textmate: "" };
            return null;
          }),
          runWithRetry(loadThemes, 2, 120).catch(function () {
            state.themes = normalizeThemes(themeNameListFallback());
            ensureActiveThemeInList();
            applyTheme(state.activeTheme);
            return null;
          })
        ]).then(function () {
          syncModelInstallPollingFromCatalog();
          modelAutoRefreshLastAt = Date.now();
        }).finally(function () {
          state.modelDataLoading = false;
        });

        setArtificerBootPhase("loading-ui", "Loading interface state…");

        var uiPromise = Promise.all([
          syncCommandExecModeForWorkspace(state.activeWorkspaceId).catch(function () {
            return null;
          }),
          Promise.all([
          runWithRetry(function () {
            return loadDictationPrewarmSetting();
          }, 2, 180).catch(function () {
            return null;
          }),
          runWithRetry(function () {
            return loadDictationStatus({ silent: true });
          }, 2, 180).catch(function () {
            return null;
          }),
          runWithRetry(function () {
            return loadDictationShortcutPrefs();
          }, 2, 180).catch(function () {
            return null;
          }),
          runWithRetry(function () {
            return loadDictationLanguageSetting();
          }, 2, 180).catch(function () {
            return null;
          })
          ]).catch(function () {
            return null;
          }),
          refreshGitStatus()
          .then(function () {
            return refreshBranches().catch(function () {
              return null;
            });
          })
          .catch(function () {
            return null;
          })
          .then(function () {
            if (state.diffOpen) {
              return refreshDiff().catch(function () {
                return null;
              });
            }
            return null;
          })
          .catch(function () {
            return null;
          })
        ]);

        return Promise.all([activeConversationPromise, modelPromise, uiPromise]).then(function () {
          state.initialLoadComplete = true;
          renderUi();
          return null;
        });
      });
  }

  function hydrateWorkspaceStateFromCache() {
    var cached = loadWorkspaceStateCache();
    if (!cached || !Array.isArray(cached.workspaces) || !cached.workspaces.length) {
      return false;
    }
    state.workspaces = cached.workspaces;
    for (var i = 0; i < state.workspaces.length; i += 1) {
      if (!Array.isArray(state.workspaces[i].conversations)) {
        state.workspaces[i].conversations = [];
      }
      for (var j = 0; j < state.workspaces[i].conversations.length; j += 1) {
        var conv = state.workspaces[i].conversations[j];
        if (typeof conv.created === "undefined" || conv.created === null || conv.created === "") {
          conv.created = typeof conv.updated !== "undefined" && conv.updated !== null && conv.updated !== "" ? String(conv.updated) : "0";
        } else {
          conv.created = String(conv.created);
        }
        if (typeof conv.updated === "undefined" || conv.updated === null || conv.updated === "") {
          conv.updated = conv.created;
        } else {
          conv.updated = String(conv.updated);
        }
        if (typeof conv.queue_pending === "undefined") {
          conv.queue_pending = "0";
        }
        if (typeof conv.queue_running === "undefined") {
          conv.queue_running = "0";
        }
        if (typeof conv.queue_done === "undefined") {
          conv.queue_done = "0";
        }
        if (typeof conv.queue_last_status === "undefined") {
          conv.queue_last_status = "";
        }
        if (typeof conv.queue_first_id === "undefined") {
          conv.queue_first_id = "";
        }
        conv.decision_request = normalizeDecisionRequest(conv.decision_request);
        conv.approval_request = normalizeApprovalRequest(conv.approval_request);
      }
    }
    bootstrapSeenConversationsIfNeeded();
    syncWorkspaceOrderingWithState({ prependUnknownWorkspaces: true });
    persistWorkspaceOrderingState();
    pruneSeenConversationState();
    pruneRunEventsByKnownConversations();
    applyRouteSelectionIfPending();
    ensureSelection();
    reconcileRunEventsFromQueueState();
    syncSelectionUrl(true);
    return true;
  }

  function addWorkspaceByPath(pathText, nameText) {
    var path = trim(pathText);
    var name = trim(nameText);
    if (!path) {
      return Promise.resolve();
    }

    return apiPost("add_workspace", {
      path: path,
      name: name,
      command_exec_mode: state.commandExecMode
    }, { timeoutMs: 12000 }).then(function (response) {
      if (!response.success) {
        throw new Error(response.error || "Could not add project");
      }

      return loadState({ fast: true, timeoutMs: 8000 }).then(function () {
        if (response.workspace && response.workspace.id) {
          state.activeWorkspaceId = response.workspace.id;
          state.activeConversationId = "";
          state.activeConversation = null;
          state.activeDraftWorkspaceId = "";
          state.expandedWorkspaceIds[response.workspace.id] = true;
          moveWorkspaceToFront(response.workspace.id);
        }
        return refreshGitStatus().catch(function () {
          return null;
        });
      });
    });
  }

  function removeWorkspace(workspaceId) {
    var workspace = getWorkspaceById(workspaceId);
    if (!workspace) {
      return Promise.resolve();
    }

    return apiPost("delete_workspace", {
      workspace_id: workspaceId
    }).then(function (response) {
      if (!response.success) {
        throw new Error(response.error || "Could not remove project");
      }
      if (state.activeWorkspaceId === workspaceId) {
        state.activeWorkspaceId = "";
        state.activeConversationId = "";
        state.activeConversation = null;
        state.activeDraftWorkspaceId = "";
      }
      if (state.openWorkspaceMenuWorkspaceId === workspaceId) {
        state.openWorkspaceMenuWorkspaceId = "";
      }
      var workspacePrefix = String(workspaceId || "") + "::";
      Object.keys(state.conversationCacheByKey).forEach(function (key) {
        if (String(key || "").indexOf(workspacePrefix) === 0) {
          delete state.conversationCacheByKey[key];
        }
      });
      delete state.expandedWorkspaceIds[workspaceId];
      delete state.gitByWorkspace[workspaceId];
      delete state.branchesByWorkspace[workspaceId];
      return refreshAll();
    });
  }

  function archiveConversation(workspaceId, conversationId) {
    if (!workspaceId || !conversationId) {
      return Promise.resolve();
    }

    return apiPost("archive_conversation", {
      workspace_id: workspaceId,
      conversation_id: conversationId
    }).then(function (response) {
      if (!response.success) {
        throw new Error(response.error || "Could not archive thread");
      }

      if (state.activeWorkspaceId === workspaceId && state.activeConversationId === conversationId) {
        state.activeConversationId = "";
        state.activeConversation = null;
      }
      clearOptimisticConversation(workspaceId, conversationId);
      delete state.conversationCacheByKey[conversationReadKey(workspaceId, conversationId)];

      state.pendingArchiveKey = "";
      state.pendingArchiveReadyAt = 0;
      state.pendingArchiveSubmittingKey = "";
      return loadState()
        .then(function () {
          if (state.activeWorkspaceId) {
            return loadConversation().catch(function () {
              return null;
            });
          }
          return null;
        })
        .then(function () {
          renderUi();
        });
    });
  }

  function renameWorkspace(workspaceId, newName) {
    var name = trim(newName);
    if (!workspaceId) {
      return Promise.reject(new Error("Project is required."));
    }
    if (!name) {
      return Promise.reject(new Error("Project name is required."));
    }

    return apiPost("rename_workspace", {
      workspace_id: workspaceId,
      name: name
    }).then(function (response) {
      if (!response.success) {
        throw new Error(response.error || "Could not rename project");
      }

      var workspace = getWorkspaceById(workspaceId);
      if (workspace) {
        workspace.name = name;
      }
      if (state.openWorkspaceMenuWorkspaceId === workspaceId) {
        state.openWorkspaceMenuWorkspaceId = "";
      }
      renderUi();
    });
  }

  function addWorkspaceFromDropCandidate(pathText) {
    var candidate = trim(pathText);
    if (!candidate) {
      return Promise.reject(new Error("Dropped folder path unavailable here. Click + and use Browse."));
    }

    return addWorkspaceByPath(candidate, "").catch(function (firstErr) {
      var parent = dirname(candidate);
      if (parent && parent !== candidate) {
        return addWorkspaceByPath(parent, "");
      }
      throw firstErr;
    });
  }

  function selectWorkspace(workspaceId) {
    var selectionVersion = newSelectionVersion();
    state.chatAutoScroll = true;
    state.conversationSwitchOverlay = false;
    rememberActiveComposerDraft();
    var workspace = getWorkspaceById(workspaceId);
    if (!workspace) {
      return Promise.resolve();
    }

    state.activeWorkspaceId = workspaceId;
    state.activeConversation = null;
    state.activeDraftWorkspaceId = "";
    state.openWorkspaceMenuWorkspaceId = "";
    state.expandedWorkspaceIds[workspaceId] = true;

    var conversations = getSortedConversations(workspace);
    if (conversations.length > 0) {
      state.activeConversationId = conversations[0].id;
      state.activeConversationSelectedAt = Date.now();
      syncSelectionUrl(false);
      return loadConversation({ applyComposerDraft: true })
        .then(function () {
          if (!isSelectionVersionCurrent(selectionVersion)) {
            return;
          }
          resetComposerAttachments();
          return refreshGitStatus().catch(function () {
            return null;
          });
        })
        .then(function () {
          if (!isSelectionVersionCurrent(selectionVersion)) {
            return;
          }
          return refreshBranches().catch(function () {
            return null;
          });
        })
        .then(function () {
          if (!isSelectionVersionCurrent(selectionVersion)) {
            return;
          }
          if (state.diffOpen) {
            return refreshDiff().catch(function () {
              return null;
            });
          }
          return null;
        })
        .then(function () {
          if (!isSelectionVersionCurrent(selectionVersion)) {
            return;
          }
          return syncCommandExecModeForWorkspace(workspaceId);
        })
        .then(function () {
          if (!isSelectionVersionCurrent(selectionVersion)) {
            return;
          }
          renderUi();
        });
    }

    state.activeConversationId = "";
    state.activeConversationSelectedAt = 0;
    syncSelectionUrl(false);
    if (workspace.draft_exists === "1") {
      return selectDraft(workspaceId);
    }

    el.runPrompt.value = getComposerDraftForTarget(workspaceId, "", workspaceId);
    resetComposerAttachments();

    return refreshGitStatus()
      .catch(function () {
        return null;
      })
      .then(function () {
        return refreshBranches().catch(function () {
          return null;
        });
      })
      .then(function () {
        return syncCommandExecModeForWorkspace(workspaceId);
      })
      .then(function () {
        renderUi();
      });
  }

  function selectConversation(workspaceId, conversationId) {
    var selectionVersion = newSelectionVersion();
    rememberActiveComposerDraft();
    if (!isQueueEditForConversation(workspaceId, conversationId) && state.queueEdit.itemId) {
      clearQueueEditState();
    }
    state.chatAutoScroll = true;
    state.activeTriage = false;
    state.activeConversationLoadError = "";
    var switchingConversation = (
      String(state.activeWorkspaceId || "") !== String(workspaceId || "") ||
      String(state.activeConversationId || "") !== String(conversationId || "") ||
      !!state.activeDraftWorkspaceId
    );
    var previousConversation = switchingConversation ? cloneConversationData(state.activeConversation) : null;
    state.activeWorkspaceId = workspaceId;
    state.activeConversationId = conversationId;
    var workspace = getWorkspaceById(workspaceId);
    var summary = getConversationById(workspace, conversationId);
    var convKey = conversationReadKey(workspaceId, conversationId);
    var cachedConversation = cloneConversationData(state.conversationCacheByKey[convKey]);
    if (cachedConversation && summary) {
      var cachedUpdated = conversationUpdatedNumber(cachedConversation);
      var summaryUpdated = conversationUpdatedNumber(summary);
      if (summaryUpdated > 0 && cachedUpdated > 0 && summaryUpdated > cachedUpdated) {
        cachedConversation = null;
      }
    }
    if (!cachedConversation) {
      if (summary) {
        cachedConversation = {
          id: summary.id,
          title: summary.title || "Thread",
          model: summary.model || "",
          created: summary.created || "",
          updated: summary.updated || "",
          messages: [],
          decision_request: normalizeDecisionRequest(summary.decision_request),
          approval_request: normalizeApprovalRequest(summary.approval_request)
        };
      }
    }
    var hasCachedMessages = !!(
      cachedConversation &&
      Array.isArray(cachedConversation.messages) &&
      cachedConversation.messages.length
    );
    var hasCachedDraft = hasComposerDraftForKey(outgoingKeyFor(workspaceId, conversationId, ""));
    var canRenderCachedConversation = hasCachedMessages && hasCachedDraft;
    if (canRenderCachedConversation) {
      state.activeConversation = cachedConversation;
    } else if (switchingConversation && previousConversation) {
      state.activeConversation = previousConversation;
    } else {
      state.activeConversation = null;
    }
    state.activeConversationSelectedAt = Date.now();
    setActiveConversationLoading(workspaceId, conversationId, !canRenderCachedConversation);
    state.conversationSwitchOverlay = switchingConversation && !!previousConversation;
    state.activeDraftWorkspaceId = "";
    state.openWorkspaceMenuWorkspaceId = "";
    state.expandedWorkspaceIds[workspaceId] = true;
    if (el.runPrompt) {
      el.runPrompt.value = hasCachedDraft ? getComposerDraftForTarget(workspaceId, conversationId, "") : "";
    }
    syncSelectionUrl(false);
    renderUi();

    return loadConversation({ showLoading: !canRenderCachedConversation, applyComposerDraft: true })
      .catch(function (firstErr) {
        if (!canRenderCachedConversation) {
          setActiveConversationLoading(workspaceId, conversationId, true);
          renderUi();
        }
        return loadState({ fast: true })
          .then(function () {
            if (state.activeWorkspaceId !== workspaceId || state.activeConversationId !== conversationId) {
              return null;
            }
            if (!canRenderCachedConversation) {
              setActiveConversationLoading(workspaceId, conversationId, true);
            }
            return loadConversation({ showLoading: !canRenderCachedConversation, applyComposerDraft: true });
          })
          .catch(function () {
            if (isSelectionVersionCurrent(selectionVersion)) {
              state.activeConversationLoadError = firstErr && firstErr.message ? firstErr.message : "Could not load thread";
              state.conversationSwitchOverlay = false;
              setActiveConversationLoading(workspaceId, conversationId, false);
              renderUi();
            }
            throw firstErr;
          });
      })
      .then(function () {
        if (!isSelectionVersionCurrent(selectionVersion)) {
          return;
        }
        state.conversationSwitchOverlay = false;
        resetComposerAttachments();
        return refreshGitStatus().catch(function () {
          return null;
        });
      })
      .then(function () {
        if (!isSelectionVersionCurrent(selectionVersion)) {
          return;
        }
        return refreshBranches().catch(function () {
          return null;
        });
      })
      .then(function () {
        if (!isSelectionVersionCurrent(selectionVersion)) {
          return;
        }
        if (state.diffOpen) {
          return refreshDiff().catch(function () {
            return null;
          });
        }
        return null;
      })
      .then(function () {
        if (!isSelectionVersionCurrent(selectionVersion)) {
          return;
        }
        return syncCommandExecModeForWorkspace(workspaceId);
      })
      .then(function () {
        if (!isSelectionVersionCurrent(selectionVersion)) {
          return;
        }
        renderUi();
      });
  }

  function selectDraft(workspaceId) {
    var selectionVersion = newSelectionVersion();
    rememberActiveComposerDraft();
    state.conversationSwitchOverlay = false;
    if (state.queueEdit.itemId) {
      clearQueueEditState();
    }
    state.chatAutoScroll = true;
    state.activeTriage = false;
    state.activeWorkspaceId = workspaceId;
    state.activeConversationId = "";
    state.activeConversation = null;
    state.activeDraftWorkspaceId = workspaceId;
    state.openWorkspaceMenuWorkspaceId = "";
    state.expandedWorkspaceIds[workspaceId] = true;
    syncSelectionUrl(false);

    return loadDraft(workspaceId)
      .then(function (draft) {
        if (!isSelectionVersionCurrent(selectionVersion)) {
          return;
        }
        var localDraft = getComposerDraftForTarget(workspaceId, "", workspaceId);
        el.runPrompt.value = hasComposerDraftForKey(outgoingKeyFor(workspaceId, "", workspaceId)) ? localDraft : draft;
        resetComposerAttachments();
        return refreshGitStatus().catch(function () {
          return null;
        });
      })
      .then(function () {
        if (!isSelectionVersionCurrent(selectionVersion)) {
          return;
        }
        return refreshBranches().catch(function () {
          return null;
        });
      })
      .then(function () {
        if (!isSelectionVersionCurrent(selectionVersion)) {
          return;
        }
        return syncCommandExecModeForWorkspace(workspaceId);
      })
      .then(function () {
        if (!isSelectionVersionCurrent(selectionVersion)) {
          return;
        }
        renderUi();
      });
  }

  function createDraftForWorkspace(workspaceId) {
    rememberActiveComposerDraft();
    state.chatAutoScroll = true;
    state.activeTriage = false;
    state.conversationSwitchOverlay = false;
    state.activeWorkspaceId = workspaceId;
    state.activeConversationId = "";
    state.activeConversation = null;
    state.activeDraftWorkspaceId = workspaceId;
    state.openWorkspaceMenuWorkspaceId = "";
    state.expandedWorkspaceIds[workspaceId] = true;
    syncSelectionUrl(false);

    return loadDraft(workspaceId)
      .then(function (draft) {
        var localDraft = getComposerDraftForTarget(workspaceId, "", workspaceId);
        el.runPrompt.value = hasComposerDraftForKey(outgoingKeyFor(workspaceId, "", workspaceId)) ? localDraft : draft;
        resetComposerAttachments();
        return syncCommandExecModeForWorkspace(workspaceId);
      })
      .then(function () {
        renderUi();
      })
      .then(function () {
        setTimeout(function () {
          el.runPrompt.focus();
        }, 0);
      });
  }

  function ensureConversationFromDraft(prompt, options) {
    var opts = options && typeof options === "object" ? options : {};
    var workspaceId = trim(String(opts.draftWorkspaceId || state.activeDraftWorkspaceId || ""));
    var knownConversationId = trim(String(opts.conversationId || state.activeConversationId || ""));
    if (!workspaceId) {
      return Promise.resolve(knownConversationId);
    }
    if (knownConversationId) {
      return Promise.resolve(knownConversationId);
    }
    if (
      Object.prototype.hasOwnProperty.call(draftConversationCreationPromiseByWorkspace, workspaceId) &&
      draftConversationCreationPromiseByWorkspace[workspaceId] &&
      typeof draftConversationCreationPromiseByWorkspace[workspaceId].then === "function"
    ) {
      return draftConversationCreationPromiseByWorkspace[workspaceId];
    }

    var model = activeModelName();
    var title = titleFromPrompt(prompt);
    function upsertCreatedConversationInWorkspace(createdConversation) {
      var ws = getWorkspaceById(workspaceId);
      if (!ws) {
        return;
      }
      if (!Array.isArray(ws.conversations)) {
        ws.conversations = [];
      }
      var existing = getConversationById(ws, createdConversation.id);
      if (existing) {
        existing.title = String(createdConversation.title || existing.title || "New Conversation");
        if (typeof createdConversation.model !== "undefined") {
          existing.model = String(createdConversation.model || "");
        }
        existing.updated = String(createdConversation.updated || existing.updated || Math.floor(Date.now() / 1000));
        if (typeof existing.created === "undefined" || existing.created === null || existing.created === "") {
          existing.created = String(createdConversation.created || existing.updated || Math.floor(Date.now() / 1000));
        }
      } else {
        ws.conversations.unshift({
          id: String(createdConversation.id || ""),
          title: String(createdConversation.title || "New Conversation"),
          model: String(createdConversation.model || ""),
          created: String(createdConversation.created || Math.floor(Date.now() / 1000)),
          updated: String(createdConversation.updated || Math.floor(Date.now() / 1000)),
          queue_pending: "0",
          queue_running: "0",
          queue_done: "0",
          queue_last_status: "",
          queue_first_id: "",
          decision_request: null,
          approval_request: null
        });
      }
      moveConversationToFront(workspaceId, createdConversation.id, { persist: false });
      moveWorkspaceToFront(workspaceId, { persist: false });
      persistWorkspaceOrderingState();
      registerOptimisticConversation(workspaceId, createdConversation);
    }

    var creationPromise = apiPost("new_conversation", {
      workspace_id: workspaceId,
      title: title,
      model: model
    }, { timeoutMs: 60000 }).then(function (response) {
      if (!response.success || !response.conversation || !response.conversation.id) {
        throw new Error(response.error || "Failed to create thread from draft");
      }
      var createdConversation = response.conversation;
      upsertCreatedConversationInWorkspace(createdConversation);

      return saveDraft(workspaceId, "").catch(function () {
        return null;
      }).then(function () {
        // Avoid loading the brand-new thread before enqueue: backend recovery seeding
        // can create a duplicate first user message when the queue write follows.
        return loadState({ fast: true, fresh: true, timeoutMs: 30000 })
          .catch(function () {
            return null;
          })
          .then(function () {
            // If state refresh races or is stale, keep the created thread visible locally.
            upsertCreatedConversationInWorkspace(createdConversation);
          })
          .then(function () {
            return String(createdConversation.id || "");
          });
      });
    });
    var sharedCreationPromise = null;
    sharedCreationPromise = creationPromise.then(function (conversationId) {
      if (draftConversationCreationPromiseByWorkspace[workspaceId] === sharedCreationPromise) {
        delete draftConversationCreationPromiseByWorkspace[workspaceId];
      }
      return conversationId;
    }, function (error) {
      if (draftConversationCreationPromiseByWorkspace[workspaceId] === sharedCreationPromise) {
        delete draftConversationCreationPromiseByWorkspace[workspaceId];
      }
      throw error;
    });
    draftConversationCreationPromiseByWorkspace[workspaceId] = sharedCreationPromise;
    return sharedCreationPromise;
  }

  function applyModelSelection(modelName) {
    var model = trim(modelName);
    if (!model) {
      return Promise.resolve();
    }

    if (state.activeConversationId && state.activeWorkspaceId) {
      return apiPost("set_model", {
        workspace_id: state.activeWorkspaceId,
        conversation_id: state.activeConversationId,
        model: model
      }).then(function (response) {
        if (!response.success) {
          throw new Error(response.error || "Could not update model");
        }

        if (state.activeConversation) {
          state.activeConversation.model = model;
        }

        var ws = getWorkspaceById(state.activeWorkspaceId);
        var conv = getConversationById(ws, state.activeConversationId);
        if (conv) {
          conv.model = model;
        }
      });
    }

    if (state.activeDraftWorkspaceId) {
      state.draftModelByWorkspace[state.activeDraftWorkspaceId] = model;
    }

    return Promise.resolve();
  }

  function defaultCommandRulePattern(commandText) {
    var cmd = trim(commandText);
    if (!cmd) {
      return "^.+$";
    }
    var first = cmd.split(/\s+/)[0] || "";
    var escaped = first.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    if (!escaped) {
      return "^.+$";
    }
    return "^" + escaped + "([[:space:]].*)?$";
  }

  function openCommandApprovalPanel(commandText, reasonText) {
    return new Promise(function (resolve, reject) {
      if (
        !el.commandApprovalInline ||
        !el.commandApprovalInlineAllowOnce ||
        !el.commandApprovalInlineDenyOnce ||
        !el.commandApprovalInlineAllowRemember ||
        !el.commandApprovalInlineDenyRemember
      ) {
        openCommandApprovalModal(commandText, reasonText).then(resolve).catch(reject);
        return;
      }

      if (pendingCommandApproval && typeof pendingCommandApproval.cancel === "function") {
        pendingCommandApproval.cancel(new Error("Command approval replaced by a newer request."));
      }

      var done = false;
      function finish(value, isReject) {
        if (done) {
          return;
        }
        done = true;
        pendingCommandApproval = null;
        el.commandApprovalInline.classList.add("hidden");
        if (isReject) {
          reject(value instanceof Error ? value : new Error(String(value || "Command approval cancelled")));
        } else {
          resolve(value);
        }
      }

      function choice(decision, scope) {
        return function () {
          var matchMode = "exact";
          var pattern = String(commandText || "");
          if (scope === "remember") {
            matchMode = trim(el.commandApprovalInlineMatchMode && el.commandApprovalInlineMatchMode.value) || "exact";
            pattern = trim(el.commandApprovalInlinePattern && el.commandApprovalInlinePattern.value) || String(commandText || "");
          }
          finish({
            decision: decision,
            scope: scope,
            match_mode: matchMode,
            pattern: pattern
          }, false);
        };
      }

      function closeHandler() {
        finish(new Error("Command approval cancelled"), true);
      }

      pendingCommandApproval = {
        cancel: closeHandler
      };

      var reason = trim(reasonText);
      if (el.commandApprovalInlineText) {
        el.commandApprovalInlineText.textContent = reason
          ? "Agent requested a command (" + reason + ")."
          : "Agent requested a command.";
      }
      if (el.commandApprovalInlineCommand) {
        el.commandApprovalInlineCommand.textContent = String(commandText || "");
      }
      if (el.commandApprovalInlineMatchMode) {
        el.commandApprovalInlineMatchMode.value = "exact";
      }
      if (el.commandApprovalInlinePattern) {
        el.commandApprovalInlinePattern.value = defaultCommandRulePattern(commandText);
      }

      el.commandApprovalInlineAllowOnce.onclick = choice("allow", "once");
      el.commandApprovalInlineDenyOnce.onclick = choice("deny", "once");
      el.commandApprovalInlineAllowRemember.onclick = choice("allow", "remember");
      el.commandApprovalInlineDenyRemember.onclick = choice("deny", "remember");
      if (el.commandApprovalInlineClose) {
        el.commandApprovalInlineClose.onclick = closeHandler;
      }

      el.commandApprovalInline.classList.remove("hidden");
      renderUi();
      window.setTimeout(function () {
        if (el.commandApprovalInlineAllowOnce) {
          el.commandApprovalInlineAllowOnce.focus();
        }
      }, 0);
    });
  }

  function openCommandApprovalModal(commandText, reasonText) {
    return new Promise(function (resolve, reject) {
      if (!el.commandApprovalModal) {
        reject(new Error("Command approval UI is unavailable."));
        return;
      }

      if (el.commandApprovalText) {
        var reason = trim(reasonText);
        el.commandApprovalText.textContent = reason
          ? "Agent requested a command (" + reason + ")."
          : "Agent requested a command.";
      }
      if (el.commandApprovalCommand) {
        el.commandApprovalCommand.textContent = String(commandText || "");
      }
      if (el.commandApprovalMatchMode) {
        el.commandApprovalMatchMode.value = "exact";
      }
      if (el.commandApprovalPattern) {
        el.commandApprovalPattern.value = defaultCommandRulePattern(commandText);
      }

      var done = false;
      function finish(value, isReject) {
        if (done) {
          return;
        }
        done = true;
        closeModal(el.commandApprovalModal);
        if (isReject) {
          reject(value instanceof Error ? value : new Error(String(value || "Command approval cancelled")));
        } else {
          resolve(value);
        }
      }

      function choice(decision, scope) {
        return function () {
          var matchMode = "exact";
          var pattern = String(commandText || "");
          if (scope === "remember") {
            matchMode = trim(el.commandApprovalMatchMode && el.commandApprovalMatchMode.value) || "exact";
            pattern = trim(el.commandApprovalPattern && el.commandApprovalPattern.value) || String(commandText || "");
          }
          finish({
            decision: decision,
            scope: scope,
            match_mode: matchMode,
            pattern: pattern
          }, false);
        };
      }

      function closeHandler() {
        finish(new Error("Command approval cancelled"), true);
      }

      var handlers = [
        [el.commandApprovalAllowOnce, choice("allow", "once")],
        [el.commandApprovalDenyOnce, choice("deny", "once")],
        [el.commandApprovalAllowRemember, choice("allow", "remember")],
        [el.commandApprovalDenyRemember, choice("deny", "remember")],
        [el.commandApprovalClose, closeHandler]
      ];

      function bindAll() {
        for (var i = 0; i < handlers.length; i += 1) {
          var pair = handlers[i];
          if (pair[0]) {
            pair[0].addEventListener("click", pair[1], { once: true });
          }
        }
        if (el.commandApprovalModal) {
          el.commandApprovalModal.addEventListener("click", overlayClick, { once: true });
        }
      }

      function overlayClick(event) {
        if (event.target === el.commandApprovalModal) {
          closeHandler();
          return;
        }
        if (el.commandApprovalModal) {
          el.commandApprovalModal.addEventListener("click", overlayClick, { once: true });
        }
      }

      bindAll();
      openModal(el.commandApprovalModal);
      window.setTimeout(function () {
        if (el.commandApprovalAllowOnce) {
          el.commandApprovalAllowOnce.focus();
        }
      }, 0);
    });
  }

  function handleBlockedCommandsApproval(workspaceId, conversationId, blockedCommands) {
    var list = Array.isArray(blockedCommands) ? blockedCommands.slice(0) : [];
    if (!list.length) {
      return Promise.resolve(false);
    }
    setAwaitingApprovalState(workspaceId, conversationId, true);
    renderUi();

    function step(index) {
      if (index >= list.length) {
        return Promise.resolve(true);
      }
      var item = list[index] || {};
      var commandText = String(item.command || "");
      var reasonText = String(item.reason || "");
      if (!trim(commandText)) {
        return step(index + 1);
      }
      return openCommandApprovalPanel(commandText, reasonText).then(function (choice) {
        return apiPost("command_approval_save", {
          workspace_id: workspaceId,
          command: commandText,
          decision: choice.decision || "deny",
          scope: choice.scope || "once",
          match_mode: choice.match_mode || "exact",
          pattern: choice.pattern || commandText
        }).then(function (response) {
          if (!response || !response.success) {
            throw new Error((response && response.error) || "Could not save command approval.");
          }
          if ((choice.decision || "") === "deny") {
            return false;
          }
          return step(index + 1);
        });
      });
    }

    return step(0).finally(function () {
      setAwaitingApprovalState(workspaceId, conversationId, false);
      renderUi();
    });
  }

  function runAgent(workspaceId, conversationId, promptText, options) {
    var runOptions = options || {};
    var preserveSelection = runOptions.preserveSelection !== false;
    var approvalRetry = runOptions.approvalRetry === true;
    var queueItemId = String(runOptions.queueItemId || "");
    var explicitModeOverride = trim(String(runOptions.runMode || ""));
    var explicitAssistantModeOverride = trim(String(runOptions.assistantModeId || ""));
    var explicitComputeBudgetOverride = trim(String(runOptions.computeBudget || ""));
    var explicitPermissionModeOverride = normalizePermissionModeValue(runOptions.permissionMode || "");
    var explicitCommandExecModeOverride = normalizeCommandExecModeValue(runOptions.commandExecMode || "");
    var explicitSkillIdsOverride = Array.isArray(runOptions.explicitSkillIds) ? runOptions.explicitSkillIds : [];
    var explicitProgrammerReviewOverride = null;
    var explicitProgrammerReviewRoundsOverride = null;
    if (Object.prototype.hasOwnProperty.call(runOptions, "programmerReview")) {
      explicitProgrammerReviewOverride = normalizeProgrammerReviewEnabledValue(runOptions.programmerReview);
    }
    if (Object.prototype.hasOwnProperty.call(runOptions, "programmerReviewRounds")) {
      explicitProgrammerReviewRoundsOverride = normalizeProgrammerReviewRoundsValue(runOptions.programmerReviewRounds);
    }
    if (explicitModeOverride) {
      explicitModeOverride = normalizeRunMode(explicitModeOverride);
    }
    if (explicitAssistantModeOverride) {
      explicitAssistantModeOverride = normalizeAssistantModeId(explicitAssistantModeOverride);
    }
    if (explicitComputeBudgetOverride) {
      explicitComputeBudgetOverride = normalizeComputeBudget(explicitComputeBudgetOverride);
    }
    var directive = parsePromptModeDirective(promptText);
    var promptForRun = trim(directive.prompt || promptText);
    var modeOverride = explicitModeOverride || (directive.mode ? normalizeRunMode(directive.mode) : "");
    var directiveSkillIds = Array.isArray(directive.skillIds) ? directive.skillIds : [];
    var explicitSkillIdsForRun = mergeSkillIdLists(explicitSkillIdsOverride, directiveSkillIds);
    var attachmentList = Array.isArray(runOptions.attachments) ? runOptions.attachments : [];
    var attachmentIds = [];
    var attachmentNames = [];
    var assistantDeliveryCleared = false;
    var assistantDeliveryFallbackAttempts = 0;

    if (!workspaceId || !conversationId) {
      return Promise.reject(new Error("Choose a project thread first."));
    }
    if (!promptForRun) {
      return Promise.reject(new Error("Prompt is empty."));
    }
    stopAssistantDeliveryWatchesForConversation(workspaceId, conversationId);
    markAssistantDeliveryPending(workspaceId, conversationId);

    for (var i = 0; i < attachmentList.length; i += 1) {
      var item = attachmentList[i] || {};
      if (item.id) {
        attachmentIds.push(String(item.id));
      }
      if (item.name) {
        attachmentNames.push(String(item.name));
      }
    }

    var pendingEvent = runOptions.pendingEvent || null;
    var runAnchor = 0;
    var preferredEventId = "";
    if (queueItemId && /^[A-Za-z0-9._-]+$/.test(queueItemId)) {
      preferredEventId = "run-" + queueItemId;
    }

    if (
      !approvalRetry &&
      !queueItemId &&
      state.activeWorkspaceId === workspaceId &&
      state.activeConversation &&
      state.activeConversation.id === conversationId
    ) {
      consumePendingOutgoingByText(outgoingKeyFor(workspaceId, conversationId, ""), promptText);
      if (!Array.isArray(state.activeConversation.messages)) {
        state.activeConversation.messages = [];
      }
      var userContent = promptForRun;
      if (attachmentNames.length) {
        userContent += "\n\nAttached files:\n- " + attachmentNames.join("\n- ");
      }
      state.activeConversation.messages.push({ role: "user", content: userContent });
      cacheActiveConversationSnapshot(workspaceId, conversationId);
    }

    runAnchor = conversationMessageCount(workspaceId, conversationId);
    if (queueItemId && !approvalRetry) {
      var anchorMessages = conversationMessagesSnapshot(workspaceId, conversationId);
      var promptAnchor = inferMessageAnchorForPrompt(anchorMessages, promptText);
      if (promptAnchor < 0 && promptForRun !== promptText) {
        promptAnchor = inferMessageAnchorForPrompt(anchorMessages, promptForRun);
      }
      if (promptAnchor >= 0) {
        runAnchor = promptAnchor;
      } else {
        runAnchor = Math.max(1, runAnchor + 1);
      }
    }

    if (!pendingEvent) {
      var runStartedAtIso = new Date().toISOString();
      pendingEvent = pushRunEvent(conversationId, {
        id: preferredEventId,
        status: "running",
        started_at: runStartedAtIso,
        last_activity_at: runStartedAtIso,
        stream_text: "",
        awaiting_assistant: 0,
        message_anchor: runAnchor
      });
    } else {
      if (preferredEventId && String(pendingEvent.id || "") !== preferredEventId) {
        pendingEvent.id = preferredEventId;
      }
      var pendingAnchor = Number(pendingEvent.message_anchor);
      if (!isFinite(pendingAnchor) || pendingAnchor < 0) {
        pendingEvent.message_anchor = runAnchor;
      }
      if (!trim(String(pendingEvent.last_activity_at || ""))) {
        pendingEvent.last_activity_at = new Date().toISOString();
      }
      pendingEvent.awaiting_assistant = 0;
      persistRunEventsSoon();
    }

    renderUi();

    var runProfile = modeOverride ? effectiveRunProfileForMode(modeOverride) : effectiveRunProfile();
    var assistantModeForRun = "";
    if (normalizeRunMode(runProfile.mode) === "assistant") {
      assistantModeForRun = explicitAssistantModeOverride || normalizeAssistantModeId(state.assistantModeId);
    }
    var computeBudgetForRun = explicitComputeBudgetOverride || normalizeComputeBudget(runProfile.computeBudget || state.computeBudget);
    var permissionModeForRun = explicitPermissionModeOverride || normalizePermissionModeValue(state.permissionMode) || "default";
    var commandExecModeForRun = explicitCommandExecModeOverride || normalizeCommandExecModeValue(state.commandExecMode) || "ask-some";
    var programmerReviewEnabledForRun = explicitProgrammerReviewOverride !== null
      ? explicitProgrammerReviewOverride
      : !!state.programmerReviewEnabled;
    var programmerReviewRoundsForRun = explicitProgrammerReviewRoundsOverride !== null
      ? explicitProgrammerReviewRoundsOverride
      : normalizeProgrammerReviewRoundsValue(state.programmerReviewRounds);
    if (
      normalizeRunMode(runProfile.mode) !== "programming" &&
      normalizeRunMode(runProfile.mode) !== "pentest" &&
      normalizeRunMode(runProfile.mode) !== "security-audit"
    ) {
      programmerReviewEnabledForRun = false;
    }
    if (!programmerReviewEnabledForRun) {
      programmerReviewRoundsForRun = 0;
    }
    var selectedIterations = Number(runProfile.maxIterations || 2);
    if (computeBudgetForRun === "long" && selectedIterations < 10) {
      selectedIterations += 2;
    } else if (computeBudgetForRun === "until-complete") {
      // 0 is the backend sentinel for unbounded iterations (still bounded by runtime budget).
      selectedIterations = 0;
    }
    var streamSession = String(Date.now()) + "-" + String(Math.floor(Math.random() * 1000000));
    var streamOffset = 0;
    var streamPollActive = true;
    var streamPollBusy = false;
    var streamRenderTimer = null;
    var streamTimerKey = workspaceId + "::" + conversationId;

    if (runStreamPollTimers[streamTimerKey]) {
      clearInterval(runStreamPollTimers[streamTimerKey]);
      delete runStreamPollTimers[streamTimerKey];
    }

    function stopStreamPoll() {
      streamPollActive = false;
      if (streamRenderTimer) {
        clearTimeout(streamRenderTimer);
        streamRenderTimer = null;
      }
      if (runStreamPollTimers[streamTimerKey]) {
        clearInterval(runStreamPollTimers[streamTimerKey]);
        delete runStreamPollTimers[streamTimerKey];
      }
    }

    function scheduleStreamRender() {
      if (streamRenderTimer) {
        return;
      }
      streamRenderTimer = setTimeout(function () {
        streamRenderTimer = null;
        renderUi();
      }, 120);
    }

    function pollStreamOnce() {
      if (!streamPollActive || streamPollBusy) {
        return;
      }
      streamPollBusy = true;
      apiGet("run_stream_poll", {
        workspace_id: workspaceId,
        conversation_id: conversationId,
        stream_session: streamSession,
        offset: String(streamOffset)
      }, { timeoutMs: 12000 })
        .then(function (response) {
          if (!response || !response.success) {
            return;
          }
          var delta = String(response.delta || "");
          var taskStatus = normalizeRunTaskStatusSnapshot(response.task_status);
          streamOffset = Number(response.offset || streamOffset || 0);
          if (delta && pendingEvent) {
            pendingEvent.stream_text = String(pendingEvent.stream_text || "") + delta;
            pendingEvent.last_activity_at = new Date().toISOString();
            persistRunEventsSoon();
            scheduleStreamRender();
          }
          if (taskStatus && pendingEvent) {
            pendingEvent.task_status = taskStatus;
            pendingEvent.last_activity_at = new Date().toISOString();
            persistRunEventsSoon();
            scheduleStreamRender();
          }
        })
        .catch(function () {
          return null;
        })
        .finally(function () {
          streamPollBusy = false;
        });
    }

    runStreamPollTimers[streamTimerKey] = setInterval(pollStreamOnce, 1200);
    pollStreamOnce();

    return apiPost("run", {
      workspace_id: workspaceId,
      conversation_id: conversationId,
      prompt: promptForRun,
      permission_mode: permissionModeForRun,
      command_exec_mode: commandExecModeForRun,
      approval_retry: approvalRetry ? "1" : "0",
      network_access: state.networkAccess ? "1" : "0",
      web_access: state.webAccess ? "1" : "0",
      attachment_ids: attachmentIds.join(","),
      queue_item_id: queueItemId,
      advanced_loop: runProfile.advancedLoop ? "1" : "0",
      run_mode: runProfile.mode,
      assistant_mode_id: assistantModeForRun,
      compute_budget: computeBudgetForRun,
      programmer_review: programmerReviewEnabledForRun ? "1" : "0",
      programmer_review_rounds: String(programmerReviewRoundsForRun),
      explicit_skill_ids: explicitSkillIdsForRun.join(","),
      reasoning_effort: runProfile.reasoning,
      max_iterations: String(selectedIterations),
      stream_session: streamSession,
      run_event_id: pendingEvent && pendingEvent.id ? String(pendingEvent.id) : "",
      run_message_anchor: String(Math.max(0, Math.floor(Number(runAnchor || 0))))
    })
      .then(function (response) {
        stopStreamPoll();
        if (!response.success) {
          throw new Error(response.error || "Run failed");
        }
        var decisionRequest = normalizeDecisionRequest(response.decision_request);
        if (typeof response.decision_request !== "undefined") {
          setConversationDecisionRequest(workspaceId, conversationId, decisionRequest);
        }
        if (
          state.activeConversation &&
          state.activeWorkspaceId === workspaceId &&
          state.activeConversationId === conversationId
        ) {
          state.activeConversation.decision_request = decisionRequest;
        }
        var assistantText = trim(String(response.assistant || ""));
        var responseQueueStatus = String(response.queue_last_status || "");
        var responseApprovalRequest = normalizeApprovalRequest(response.approval_request);
        var awaitingApproval = responseQueueStatus === "awaiting_approval" || !!responseApprovalRequest;
        var awaitingDecision = responseQueueStatus === "awaiting_decision" || !!decisionRequest;
        if (responseQueueStatus) {
          setConversationQueueFields(workspaceId, conversationId, {
            lastStatus: responseQueueStatus,
            approvalRequest: typeof response.approval_request === "undefined" ? undefined : responseApprovalRequest
          });
        }
        setAwaitingApprovalState(workspaceId, conversationId, awaitingApproval);
        if (
          state.activeConversation &&
          state.activeWorkspaceId === workspaceId &&
          state.activeConversationId === conversationId &&
          typeof response.approval_request !== "undefined"
        ) {
          state.activeConversation.approval_request = responseApprovalRequest;
        }
        if (assistantLooksLikeTrace(assistantText)) {
          if (pendingEvent && !trim(String(pendingEvent.failures || ""))) {
            pendingEvent.failures = assistantText;
          }
          assistantText = "";
        }
        var fallbackAttemptCount = 0;
        if (!assistantText) {
          fallbackAttemptCount = runTraceAttemptCount(response || {});
          if (!fallbackAttemptCount && pendingEvent) {
            fallbackAttemptCount = runTraceAttemptCount(pendingEvent);
          }
        }
        assistantDeliveryFallbackAttempts = fallbackAttemptCount;
        if (assistantText) {
          appendAssistantMessageOptimistic(workspaceId, conversationId, assistantText);
          if (pendingEvent) {
            pendingEvent.awaiting_assistant = 0;
          }
          if (conversationHasAssistantAfterAnchor(workspaceId, conversationId, runAnchor)) {
            if (clearAssistantDeliveryPending(workspaceId, conversationId)) {
              assistantDeliveryCleared = true;
            }
          }
        }

        var blockedCommands = Array.isArray(response.blocked_commands) ? response.blocked_commands : [];
        if (blockedCommands.length && !queueItemId) {
          return handleBlockedCommandsApproval(workspaceId, conversationId, blockedCommands).then(function (approved) {
            if (!approved) {
              throw new Error("Command execution denied.");
            }
            return runAgent(workspaceId, conversationId, promptText, {
              preserveSelection: preserveSelection,
              attachments: attachmentList,
              queueItemId: queueItemId,
              runMode: modeOverride,
              assistantModeId: assistantModeForRun,
              computeBudget: computeBudgetForRun,
              programmerReview: programmerReviewEnabledForRun,
              programmerReviewRounds: programmerReviewRoundsForRun,
              explicitSkillIds: explicitSkillIdsForRun,
              approvalRetry: true,
              pendingEvent: pendingEvent
            });
          });
        }

        if (pendingEvent) {
          pendingEvent.status = awaitingApproval
            ? "awaiting_approval"
            : (awaitingDecision ? "awaiting_decision" : "done");
          pendingEvent.model = response.model || "";
          pendingEvent.plan = response.plan || "";
          pendingEvent.commands = response.commands || [];
          pendingEvent.git_status = response.git_status || "";
          pendingEvent.git_diff = response.git_diff || "";
          pendingEvent.state = response.state || "";
          pendingEvent.failures = response.failures || "";
          pendingEvent.session_log = response.session_log || "";
          pendingEvent.task_status = normalizeRunTaskStatusSnapshot(response.task_status);
          pendingEvent.awaiting_assistant = (!assistantText && !awaitingApproval && !awaitingDecision) ? 1 : 0;
          pendingEvent.finished_at = new Date().toISOString();
          pendingEvent.last_activity_at = pendingEvent.finished_at;
          pendingEvent.decision_hint = trim(String(response.decision_hint || ""));
          if (pendingEvent.id) {
            delete state.runDetailsOpenByEventId[String(pendingEvent.id)];
            delete state.runDigestOpenByEventId[String(pendingEvent.id)];
          }
          persistRunEventsSoon();
        }
        renderUi();

        return loadState({ fast: true, timeoutMs: 20000 })
          .catch(function () {
            return null;
          })
          .then(function () {
            if (!preserveSelection) {
              state.activeWorkspaceId = workspaceId;
              state.activeConversationId = conversationId;
              state.activeDraftWorkspaceId = "";
            }
            return loadConversation({
              workspaceId: workspaceId,
              conversationId: conversationId,
              timeoutMs: 15000,
              markSeen: false
            }).catch(function () {
              if (
                assistantText &&
                state.activeConversation &&
                state.activeWorkspaceId === workspaceId &&
                state.activeConversation.id === conversationId
              ) {
                if (!Array.isArray(state.activeConversation.messages)) {
                  state.activeConversation.messages = [];
                }
                var msgs = state.activeConversation.messages;
                var last = msgs.length ? msgs[msgs.length - 1] : null;
                if (!last || last.role !== "assistant" || String(last.content || "") !== assistantText) {
                  msgs.push({ role: "assistant", content: assistantText });
                  cacheActiveConversationSnapshot(workspaceId, conversationId);
                }
              }
              return null;
            });
          })
          .then(function () {
            if (
              !assistantText &&
              state.activeConversation &&
              state.activeWorkspaceId === workspaceId &&
              state.activeConversation.id === conversationId &&
              !conversationHasAssistantAfterAnchor(workspaceId, conversationId, runAnchor)
            ) {
              assistantText = structuredRunFallbackMessage(fallbackAttemptCount);
              appendAssistantMessageOptimistic(workspaceId, conversationId, assistantText);
              assistantDeliveryFallbackAttempts = fallbackAttemptCount;
              if (pendingEvent) {
                pendingEvent.awaiting_assistant = 0;
                persistRunEventsSoon();
              }
            }
            return null;
          })
          .then(function () {
            return refreshGitStatus().catch(function () {
              return null;
            });
          })
          .then(function () {
            return refreshBranches().catch(function () {
              return null;
            });
          })
          .then(function () {
            if (state.diffOpen) {
              return refreshDiff().catch(function () {
                return null;
              });
            }
            return null;
          })
          .then(function () {
            renderUi();
            return {
              awaitingDecision: awaitingDecision,
              awaitingApproval: awaitingApproval
            };
          });
      })
      .catch(function (err) {
        stopStreamPoll();
        setAwaitingApprovalState(workspaceId, conversationId, false);
        var errorMessage = trim(String(err && err.message ? err.message : err || ""));
        if (pendingEvent) {
          pendingEvent.status = "error";
          pendingEvent.error = errorMessage || "Run failed";
          pendingEvent.awaiting_assistant = 0;
          pendingEvent.finished_at = new Date().toISOString();
          pendingEvent.last_activity_at = pendingEvent.finished_at;
          if (pendingEvent.id) {
            delete state.runDetailsOpenByEventId[String(pendingEvent.id)];
            delete state.runDigestOpenByEventId[String(pendingEvent.id)];
          }
          persistRunEventsSoon();
        }
        renderUi();
        if (
          /workspace path is missing or unavailable/i.test(errorMessage) ||
          /invalid workspace_id/i.test(errorMessage)
        ) {
          loadState({ fresh: true, timeoutMs: 12000 })
            .catch(function () {
              return null;
            })
            .then(function () {
              ensureSelection();
              renderUi();
              return null;
            });
        }
        throw err;
      })
      .finally(function () {
        stopStreamPoll();
        var currentStatus = pendingEvent ? String(pendingEvent.status || "") : "";
        var needsAssistantDeliveryWatch = (
          currentStatus === "done" &&
          !conversationHasAssistantAfterAnchor(workspaceId, conversationId, runAnchor)
        );
        if (assistantDeliveryCleared) {
          if (pendingEvent && Number(pendingEvent.awaiting_assistant || 0) > 0) {
            pendingEvent.awaiting_assistant = 0;
            persistRunEventsSoon();
          }
          renderUi();
          return;
        }
        if (needsAssistantDeliveryWatch) {
          if (pendingEvent && Number(pendingEvent.awaiting_assistant || 0) < 1) {
            pendingEvent.awaiting_assistant = 1;
            persistRunEventsSoon();
          }
          startAssistantDeliveryWatch(
            workspaceId,
            conversationId,
            runAnchor,
            pendingEvent && pendingEvent.id ? String(pendingEvent.id) : "",
            assistantDeliveryFallbackAttempts
          );
          renderUi();
          return;
        }
        if (pendingEvent && Number(pendingEvent.awaiting_assistant || 0) > 0) {
          pendingEvent.awaiting_assistant = 0;
          persistRunEventsSoon();
        }
        if (clearAssistantDeliveryPending(workspaceId, conversationId)) {
          assistantDeliveryCleared = true;
          renderUi();
        }
      });
  }

  function applyQueueStateFromResponse(workspaceId, conversationId, response) {
    if (!response) {
      return;
    }

    var pendingCount = queueNumber(response.queue_pending);

    setConversationQueueFields(workspaceId, conversationId, {
      pending: pendingCount,
      running: Number(response.queue_running || 0) > 0,
      done: Number(response.queue_done || 0) > 0,
      lastStatus: response.queue_last_status || "",
      firstId: response.queue_first_id || "",
      decisionRequest: typeof response.decision_request === "undefined" ? undefined : response.decision_request,
      approvalRequest: typeof response.approval_request === "undefined" ? undefined : response.approval_request
    });

    var queueLastStatus = String(response.queue_last_status || "");
    var responseRunning = Number(response.queue_running || 0) > 0;
    updateAwaitingApprovalFromQueueSnapshot(workspaceId, conversationId, {
      lastStatus: queueLastStatus,
      approvalRequest: response.approval_request,
      pending: pendingCount,
      running: responseRunning
    });
    releaseApprovalAnswerUiPendingIfAdvanced(workspaceId, conversationId, {
      queue_last_status: queueLastStatus,
      approval_request: response.approval_request
    });
    var queueTerminal = !responseRunning && pendingCount === 0;
    if (queueTerminal) {
      var eventStatus = queueLastStatus;
      if (
        eventStatus !== "done" &&
        eventStatus !== "error" &&
        eventStatus !== "cancelled" &&
        eventStatus !== "awaiting_decision" &&
        eventStatus !== "awaiting_approval"
      ) {
        eventStatus = "done";
      }
      finalizeAllRunningEvents(
        conversationId,
        eventStatus || "done",
        eventStatus === "error" ? "Run did not complete." : ""
      );
      if (eventStatus !== "awaiting_approval") {
        setAwaitingApprovalState(workspaceId, conversationId, false);
      }
    }
    if (
      !responseRunning &&
      state.busy &&
      String(state.runningWorkspaceId || "") === String(workspaceId || "") &&
      String(state.runningConversationId || "") === String(conversationId || "")
    ) {
      var eventStatus = queueLastStatus;
      if (
        eventStatus !== "done" &&
        eventStatus !== "error" &&
        eventStatus !== "cancelled" &&
        eventStatus !== "awaiting_decision" &&
        eventStatus !== "awaiting_approval"
      ) {
        eventStatus = "done";
      }
      finalizeAllRunningEvents(
        conversationId,
        eventStatus || "done",
        eventStatus === "error" ? "Run did not complete." : ""
      );
      setBusy(false);
    }

    if (pendingCount === 0 && conversationId) {
      delete state.lastQueuedItemIdByConversation[conversationId];
      clearQueueItemsForConversation(workspaceId, conversationId);
      clearPendingOutgoingForConversation(workspaceId, conversationId);
      clearQueueEditPostSaveHold(workspaceId, conversationId);
      if (isQueueEditForConversation(workspaceId, conversationId)) {
        clearQueueEditState();
      }
    }

    var workspace = getWorkspaceById(workspaceId);
    var conversation = getConversationById(workspace, conversationId);
    if (conversation) {
      finalizeStaleRunningEventsForConversation(workspaceId, conversation);
    }
  }

  function enqueuePrompt(workspaceId, conversationId, promptText, position, attachmentIds, runMode, assistantModeId, computeBudget, explicitSkillIds, permissionMode, commandExecMode, programmerReviewEnabled, programmerReviewRounds) {
    var attachmentList = Array.isArray(attachmentIds) ? attachmentIds : [];
    var normalizedMode = normalizeRunMode(runMode || state.runMode);
    var normalizedAssistantMode = normalizedMode === "assistant" ? normalizeAssistantModeId(assistantModeId || state.assistantModeId) : "";
    var normalizedComputeBudget = normalizeComputeBudget(computeBudget || state.computeBudget);
    var normalizedPermissionMode = normalizePermissionModeValue(permissionMode || state.permissionMode) || "default";
    var normalizedCommandExecMode = normalizeCommandExecModeValue(commandExecMode || state.commandExecMode) || "ask-some";
    var normalizedProgrammerReview = normalizeProgrammerReviewEnabledValue(
      typeof programmerReviewEnabled === "undefined" ? state.programmerReviewEnabled : programmerReviewEnabled
    );
    var normalizedProgrammerReviewRounds = normalizeProgrammerReviewRoundsValue(
      typeof programmerReviewRounds === "undefined" ? state.programmerReviewRounds : programmerReviewRounds
    );
    if (normalizedMode !== "programming" && normalizedMode !== "pentest" && normalizedMode !== "security-audit") {
      normalizedProgrammerReview = false;
    }
    if (!normalizedProgrammerReview) {
      normalizedProgrammerReviewRounds = 0;
    }
    var normalizedSkillIds = mergeSkillIdLists(explicitSkillIds, []);
    return apiPost("queue_enqueue", {
      workspace_id: workspaceId,
      conversation_id: conversationId,
      prompt: promptText,
      position: position || "tail",
      attachments: attachmentList.join(","),
      run_mode: normalizedMode,
      assistant_mode_id: normalizedAssistantMode,
      compute_budget: normalizedComputeBudget,
      permission_mode: normalizedPermissionMode,
      command_exec_mode: normalizedCommandExecMode,
      programmer_review: normalizedProgrammerReview ? "1" : "0",
      programmer_review_rounds: String(normalizedProgrammerReviewRounds),
      explicit_skill_ids: normalizedSkillIds.join(",")
    }, { timeoutMs: 90000 }).then(function (response) {
      if (!response.success) {
        throw new Error(response.error || "Could not queue message");
      }
      applyQueueStateFromResponse(workspaceId, conversationId, response);
      if (response.item_id) {
        state.lastQueuedItemIdByConversation[conversationId] = String(response.item_id);
      }
      return loadQueueItems(workspaceId, conversationId, { force: true, minIntervalMs: 0 }).catch(function () {
        return null;
      }).then(function () {
        return response;
      });
    });
  }

  function enqueuePromptInConversationOrder(workspaceId, conversationId, promptText, position, attachmentIds, runMode, assistantModeId, computeBudget, explicitSkillIds, permissionMode, commandExecMode, programmerReviewEnabled, programmerReviewRounds) {
    var queueKey = queueConversationKey(workspaceId, conversationId);
    if (!queueKey) {
      return enqueuePrompt(
        workspaceId,
        conversationId,
        promptText,
        position,
        attachmentIds,
        runMode,
        assistantModeId,
        computeBudget,
        explicitSkillIds,
        permissionMode,
        commandExecMode,
        programmerReviewEnabled,
        programmerReviewRounds
      );
    }
    var previous = enqueueChainByConversationKey[queueKey];
    var start = Promise.resolve();
    if (previous && typeof previous.then === "function") {
      start = previous.then(function () {
        return null;
      }, function () {
        return null;
      });
    }
    var current = start.then(function () {
      return enqueuePrompt(
        workspaceId,
        conversationId,
        promptText,
        position,
        attachmentIds,
        runMode,
        assistantModeId,
        computeBudget,
        explicitSkillIds,
        permissionMode,
        commandExecMode,
        programmerReviewEnabled,
        programmerReviewRounds
      );
    });
    enqueueChainByConversationKey[queueKey] = current;
    return current.then(function (response) {
      if (enqueueChainByConversationKey[queueKey] === current) {
        delete enqueueChainByConversationKey[queueKey];
      }
      return response;
    }, function (error) {
      if (enqueueChainByConversationKey[queueKey] === current) {
        delete enqueueChainByConversationKey[queueKey];
      }
      throw error;
    });
  }

  function queueFinish(workspaceId, conversationId, itemId, status, errorText) {
    return apiPost("queue_finish", {
      workspace_id: workspaceId,
      conversation_id: conversationId,
      item_id: itemId || "",
      status: status || "done",
      error: errorText || ""
    }, { timeoutMs: 60000 }).then(function (response) {
      if (!response.success) {
        throw new Error(response.error || "Could not finalize queue item");
      }
      applyQueueStateFromResponse(workspaceId, conversationId, response);
      return loadQueueItems(workspaceId, conversationId, { force: true, minIntervalMs: 0 }).catch(function () {
        return null;
      }).then(function () {
        return response;
      });
    });
  }

  function findConversationStateEntry(stateResponse, workspaceId, conversationId) {
    if (!stateResponse || !stateResponse.success || !Array.isArray(stateResponse.workspaces)) {
      return null;
    }
    for (var i = 0; i < stateResponse.workspaces.length; i += 1) {
      var workspace = stateResponse.workspaces[i];
      if (!workspace || String(workspace.id || "") !== String(workspaceId || "")) {
        continue;
      }
      var conversations = Array.isArray(workspace.conversations) ? workspace.conversations : [];
      for (var j = 0; j < conversations.length; j += 1) {
        var conversation = conversations[j];
        if (conversation && String(conversation.id || "") === String(conversationId || "")) {
          return conversation;
        }
      }
    }
    return null;
  }

  function startQueueCompletionWatch(workspaceId, conversationId, queueItemId, computeBudget) {
    var active = true;
    var inFlight = false;
    var pollTimer = null;
    var maxWaitMs = computeBudgetQueueWatchTimeoutMs(computeBudget || state.computeBudget);
    var pollFailures = 0;
    var missingConversationPolls = 0;

    var promise = new Promise(function (resolve) {
      function finish(payload) {
        if (!active) {
          return;
        }
        active = false;
        if (pollTimer) {
          clearInterval(pollTimer);
          pollTimer = null;
        }
        resolve(payload || null);
      }

      function checkOnce() {
        if (!active || inFlight) {
          return;
        }
        inFlight = true;
        apiGet("state", {}, { timeoutMs: 18000 })
          .then(function (response) {
            if (!active) {
              return;
            }
            var hasQueuedOrRunning = hasAnyQueuedOrRunningConversationInStateResponse(response);
            var conversation = findConversationStateEntry(response, workspaceId, conversationId);
            if (!conversation) {
              missingConversationPolls += 1;
              if (!hasQueuedOrRunning || missingConversationPolls >= 4) {
                finish({
                  lastStatus: "done",
                  pending: 0,
                  firstId: "",
                  decisionRequest: undefined,
                  approvalRequest: undefined
                });
              }
              return;
            }
            missingConversationPolls = 0;
            var running = String(conversation.queue_running || "0") === "1";
            var pending = queueNumber(conversation.queue_pending);
            var firstId = String(conversation.queue_first_id || "");
            var lastStatus = String(conversation.queue_last_status || "");
            pollFailures = 0;

            if (running) {
              return;
            }
            if (
              lastStatus !== "done" &&
              lastStatus !== "error" &&
              lastStatus !== "cancelled" &&
              lastStatus !== "awaiting_approval" &&
              lastStatus !== "awaiting_decision"
            ) {
              return;
            }
            if (pending > 0 && queueItemId && firstId === String(queueItemId || "")) {
              return;
            }

            finish({
              lastStatus: lastStatus,
              pending: pending,
              firstId: firstId,
              decisionRequest: typeof conversation.decision_request === "undefined" ? undefined : conversation.decision_request,
              approvalRequest: typeof conversation.approval_request === "undefined" ? undefined : conversation.approval_request
            });
          })
          .catch(function () {
            pollFailures += 1;
            return null;
          })
          .finally(function () {
            inFlight = false;
          });
      }

      pollTimer = setInterval(checkOnce, 6000);
      setTimeout(checkOnce, 1200);
      setTimeout(function () {
        finish({
          lastStatus: "error",
          pending: 0,
          firstId: "",
          decisionRequest: undefined
        });
      }, maxWaitMs);
    });

    return {
      promise: promise,
      stop: function () {
        active = false;
        if (pollTimer) {
          clearInterval(pollTimer);
          pollTimer = null;
        }
      }
    };
  }

  function executeQueuedItem(workspaceId, conversationId, queueItem, executeOptions) {
    var item = queueItem || {};
    var options = executeOptions || {};
    var itemId = item.id || "";
    var runError = null;
    var runResult = null;
    var finalStatus = "done";
    var finalErrorText = "";
    var queueFinalizeApplied = false;
    var queueWatch = null;
    var resumedPendingEvent = null;

    if (itemId && state.lastQueuedItemIdByConversation[conversationId] === itemId) {
      delete state.lastQueuedItemIdByConversation[conversationId];
    }
    if (trim(String(item.prompt || ""))) {
      consumePendingOutgoingByText(outgoingKeyFor(workspaceId, conversationId, ""), String(item.prompt || ""));
    }

    setBusy(true, workspaceId, conversationId);
    setConversationQueueFields(workspaceId, conversationId, {
      running: true,
      done: false,
      lastStatus: "running"
    });
    if (options.approvalRetry === true) {
      resumedPendingEvent = findLatestRunEventByStatus(conversationId, ["awaiting_approval", "done", "running"]);
      if (resumedPendingEvent) {
        resumedPendingEvent.status = "running";
        resumedPendingEvent.finished_at = "";
        resumedPendingEvent.error = "";
        if (!trim(String(resumedPendingEvent.started_at || ""))) {
          resumedPendingEvent.started_at = new Date().toISOString();
        }
        persistRunEventsSoon();
      }
    }
    renderUi();

    queueWatch = startQueueCompletionWatch(workspaceId, conversationId, itemId, item.compute_budget || state.computeBudget);

    function applyWatchInfo(watchInfo) {
      if (!watchInfo) {
        return false;
      }
      finalStatus = String(watchInfo.lastStatus || "done");
      if (
        finalStatus !== "done" &&
        finalStatus !== "error" &&
        finalStatus !== "cancelled" &&
        finalStatus !== "awaiting_decision" &&
        finalStatus !== "awaiting_approval"
      ) {
        finalStatus = "done";
      }
      queueFinalizeApplied = true;
      if (typeof watchInfo.decisionRequest !== "undefined") {
        setConversationQueueFields(workspaceId, conversationId, {
          decisionRequest: watchInfo.decisionRequest
        });
      }
      if (typeof watchInfo.approvalRequest !== "undefined") {
        setConversationQueueFields(workspaceId, conversationId, {
          approvalRequest: watchInfo.approvalRequest
        });
      }
      setAwaitingApprovalState(workspaceId, conversationId, finalStatus === "awaiting_approval");
      setConversationQueueFields(workspaceId, conversationId, {
        pending: queueNumber(watchInfo.pending),
        running: false,
        done: finalStatus === "done",
        lastStatus: finalStatus,
        firstId: watchInfo.firstId || ""
      });
      if (finalStatus === "error") {
        runError = new Error("Run ended with an error.");
        finalErrorText = runError.message;
      } else {
        finalErrorText = "";
        runResult = {
          awaitingDecision: finalStatus === "awaiting_decision",
          awaitingApproval: finalStatus === "awaiting_approval"
