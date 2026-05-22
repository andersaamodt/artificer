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
    var explicitReflexiveKnowledgeOverride = null;
    var explicitSelfActuationOverride = null;
    var explicitSkillIdsOverride = Array.isArray(runOptions.explicitSkillIds) ? runOptions.explicitSkillIds : [];
    var explicitProgrammerReviewOverride = null;
    var explicitProgrammerReviewRoundsOverride = null;
    if (Object.prototype.hasOwnProperty.call(runOptions, "reflexiveKnowledge")) {
      explicitReflexiveKnowledgeOverride = !!runOptions.reflexiveKnowledge;
    }
    if (Object.prototype.hasOwnProperty.call(runOptions, "selfActuation")) {
      explicitSelfActuationOverride = !!runOptions.selfActuation;
    }
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
    var reflexiveKnowledgeForRun = explicitReflexiveKnowledgeOverride !== null
      ? explicitReflexiveKnowledgeOverride
      : !!state.reflexiveKnowledge;
    var selfActuationForRun = explicitSelfActuationOverride !== null
      ? explicitSelfActuationOverride
      : !!state.selfActuation;
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
    var streamPollPromise = null;
    var streamRenderTimer = null;
    var streamDrainPromise = null;
    var streamPollIntervalMs = 350;
    var streamPollTimeoutMs = 12000;
    var streamTimerKey = workspaceId + "::" + conversationId;

    if (runStreamPollTimers[streamTimerKey]) {
      clearInterval(runStreamPollTimers[streamTimerKey]);
      delete runStreamPollTimers[streamTimerKey];
    }

    function requestStreamPollStop() {
      streamPollActive = false;
      if (runStreamPollTimers[streamTimerKey]) {
        clearInterval(runStreamPollTimers[streamTimerKey]);
        delete runStreamPollTimers[streamTimerKey];
      }
    }

    function stopStreamPoll() {
      requestStreamPollStop();
      if (streamRenderTimer) {
        clearTimeout(streamRenderTimer);
        streamRenderTimer = null;
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

    function pollStreamOnce(options) {
      var force = !!(options && options.force);
      if ((!streamPollActive && !force) || streamPollBusy) {
        if (streamPollPromise && typeof streamPollPromise.then === "function") {
          return streamPollPromise;
        }
        return Promise.resolve(false);
      }
      streamPollBusy = true;
      var sawUpdate = false;
      streamPollPromise = apiGet("run_stream_poll", {
        workspace_id: workspaceId,
        conversation_id: conversationId,
        stream_session: streamSession,
        offset: String(streamOffset)
      }, { timeoutMs: streamPollTimeoutMs })
        .then(function (response) {
          if (!response || !response.success) {
            return false;
          }
          var delta = String(response.delta || "");
          var taskStatus = normalizeRunTaskStatusSnapshot(response.task_status);
          streamOffset = Number(response.offset || streamOffset || 0);
          if (delta) {
            sawUpdate = true;
          }
          if (delta && pendingEvent) {
            pendingEvent.stream_text = String(pendingEvent.stream_text || "") + delta;
            pendingEvent.last_activity_at = new Date().toISOString();
            persistRunEventsSoon();
            scheduleStreamRender();
          }
          if (taskStatus) {
            sawUpdate = true;
          }
          if (taskStatus && pendingEvent) {
            pendingEvent.task_status = taskStatus;
            pendingEvent.last_activity_at = new Date().toISOString();
            persistRunEventsSoon();
            scheduleStreamRender();
          }
          return sawUpdate;
        })
        .catch(function () {
          return false;
        })
        .finally(function () {
          streamPollBusy = false;
          streamPollPromise = null;
        });
      return streamPollPromise;
    }

    function drainStreamAndStop() {
      if (streamDrainPromise && typeof streamDrainPromise.then === "function") {
        return streamDrainPromise;
      }
      requestStreamPollStop();
      streamDrainPromise = Promise.resolve()
        .then(function () {
          return pollStreamOnce({ force: true });
        })
        .then(function (firstChanged) {
          if (firstChanged) {
            return pollStreamOnce({ force: true });
          }
          return false;
        })
        .catch(function () {
          return false;
        })
        .finally(function () {
          stopStreamPoll();
          streamDrainPromise = null;
        });
      return streamDrainPromise;
    }

    runStreamPollTimers[streamTimerKey] = setInterval(pollStreamOnce, streamPollIntervalMs);
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
      reflexive_knowledge: reflexiveKnowledgeForRun ? "1" : "0",
      self_actuation: selfActuationForRun ? "1" : "0",
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
          pendingEvent.capability_guidance = normalizeCapabilityGuidanceTrace(response.capability_guidance);
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
        return drainStreamAndStop()
          .catch(function () {
            return null;
          })
          .then(function () {
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
            return null;
          });
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

  function enqueuePrompt(workspaceId, conversationId, promptText, position, attachmentIds, runMode, assistantModeId, computeBudget, explicitSkillIds, permissionMode, commandExecMode, programmerReviewEnabled, programmerReviewRounds, reflexiveKnowledgeEnabled, selfActuationEnabled) {
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
    var normalizedReflexiveKnowledge = typeof reflexiveKnowledgeEnabled === "undefined"
      ? !!state.reflexiveKnowledge
      : !!reflexiveKnowledgeEnabled;
    var normalizedSelfActuation = typeof selfActuationEnabled === "undefined"
      ? !!state.selfActuation
      : !!selfActuationEnabled;
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
      reflexive_knowledge: normalizedReflexiveKnowledge ? "1" : "0",
      self_actuation: normalizedSelfActuation ? "1" : "0",
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

  function enqueuePromptInConversationOrder(workspaceId, conversationId, promptText, position, attachmentIds, runMode, assistantModeId, computeBudget, explicitSkillIds, permissionMode, commandExecMode, programmerReviewEnabled, programmerReviewRounds, reflexiveKnowledgeEnabled, selfActuationEnabled) {
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
        programmerReviewRounds,
        reflexiveKnowledgeEnabled,
        selfActuationEnabled
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
        programmerReviewRounds,
        reflexiveKnowledgeEnabled,
        selfActuationEnabled
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
