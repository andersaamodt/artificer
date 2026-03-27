    var key = conversationReadKey(workspaceId, conversationId);
    if (value) {
      state.awaitingApprovalByConversation[key] = 1;
    } else if (state.awaitingApprovalByConversation[key]) {
      delete state.awaitingApprovalByConversation[key];
    }
  }

  function isAwaitingApprovalConversation(workspaceId, conversationId) {
    if (!workspaceId || !conversationId) {
      return false;
    }
    var key = conversationReadKey(workspaceId, conversationId);
    return !!state.awaitingApprovalByConversation[key];
  }

  function markAssistantDeliveryPending(workspaceId, conversationId) {
    var key = conversationReadKey(workspaceId, conversationId);
    if (!key) {
      return false;
    }
    var nextCount = Number(state.pendingAssistantDeliveryCountByConversation[key] || 0);
    if (!isFinite(nextCount) || nextCount < 0) {
      nextCount = 0;
    }
    state.pendingAssistantDeliveryCountByConversation[key] = nextCount + 1;
    return true;
  }

  function clearAssistantDeliveryPending(workspaceId, conversationId) {
    var key = conversationReadKey(workspaceId, conversationId);
    if (!key) {
      return false;
    }
    var count = Number(state.pendingAssistantDeliveryCountByConversation[key] || 0);
    if (!isFinite(count) || count <= 0) {
      return false;
    }
    if (count <= 1) {
      delete state.pendingAssistantDeliveryCountByConversation[key];
      return true;
    }
    state.pendingAssistantDeliveryCountByConversation[key] = count - 1;
    return true;
  }

  function assistantDeliveryPendingCount(workspaceId, conversationId) {
    var key = conversationReadKey(workspaceId, conversationId);
    if (!key) {
      return 0;
    }
    var count = Number(state.pendingAssistantDeliveryCountByConversation[key] || 0);
    if (!isFinite(count) || count < 0) {
      return 0;
    }
    return Math.floor(count);
  }

  function conversationHasAssistantAfterAnchor(workspaceId, conversationId, messageAnchor) {
    var wsId = String(workspaceId || "");
    var convId = String(conversationId || "");
    if (!wsId || !convId) {
      return false;
    }
    var anchorIndex = Number(messageAnchor);
    if (!isFinite(anchorIndex) || anchorIndex < 0) {
      anchorIndex = 0;
    } else {
      anchorIndex = Math.floor(anchorIndex);
    }
    var workspace = getWorkspaceById(wsId);
    var conversation = getConversationById(workspace, convId);
    if (
      state.activeConversation &&
      String(state.activeWorkspaceId || "") === wsId &&
      String(state.activeConversationId || "") === convId
    ) {
      conversation = state.activeConversation;
    }
    if (!conversation || !Array.isArray(conversation.messages)) {
      return false;
    }
    for (var msgIndex = anchorIndex; msgIndex < conversation.messages.length; msgIndex += 1) {
      var anchoredMessage = conversation.messages[msgIndex] || {};
      if (String(anchoredMessage.role || "") !== "assistant") {
        continue;
      }
      if (trim(String(anchoredMessage.content || ""))) {
        return true;
      }
    }
    return false;
  }

  function assistantDeliveryWatchKeyForRun(workspaceId, conversationId, messageAnchor, runEventId) {
    var wsId = String(workspaceId || "");
    var convId = String(conversationId || "");
    if (!wsId || !convId) {
      return "";
    }
    var anchor = Number(messageAnchor);
    if (!isFinite(anchor) || anchor < 0) {
      anchor = 0;
    } else {
      anchor = Math.floor(anchor);
    }
    var eventId = trim(String(runEventId || ""));
    return wsId + "::" + convId + "::" + String(anchor) + "::" + eventId;
  }

  function stopAssistantDeliveryWatchByKey(watchKey, options) {
    var key = String(watchKey || "");
    if (!key) {
      return false;
    }
    var watch = assistantDeliveryWatchByKey[key];
    if (!watch || typeof watch.stop !== "function") {
      return false;
    }
    watch.stop(options || {});
    return true;
  }

  function stopAssistantDeliveryWatch(workspaceId, conversationId, messageAnchor, runEventId, options) {
    var watchKey = assistantDeliveryWatchKeyForRun(workspaceId, conversationId, messageAnchor, runEventId);
    if (!watchKey) {
      return false;
    }
    return stopAssistantDeliveryWatchByKey(watchKey, options || {});
  }

  function stopAssistantDeliveryWatchesForConversation(workspaceId, conversationId, options) {
    var wsId = String(workspaceId || "");
    var convId = String(conversationId || "");
    if (!wsId || !convId) {
      return 0;
    }
    var prefix = wsId + "::" + convId + "::";
    var keys = Object.keys(assistantDeliveryWatchByKey || {});
    var stopped = 0;
    for (var i = 0; i < keys.length; i += 1) {
      var key = String(keys[i] || "");
      if (!key || key.indexOf(prefix) !== 0) {
        continue;
      }
      if (stopAssistantDeliveryWatchByKey(key, options || {})) {
        stopped += 1;
      }
    }
    return stopped;
  }

  function findRunEventByIdForConversation(conversationId, eventId) {
    var convId = String(conversationId || "");
    var id = String(eventId || "");
    if (!convId || !id) {
      return null;
    }
    var events = runEventsForConversation(convId);
    if (!Array.isArray(events) || !events.length) {
      return null;
    }
    for (var i = events.length - 1; i >= 0; i -= 1) {
      var event = events[i] || {};
      if (String(event.id || "") === id) {
        return event;
      }
    }
    return null;
  }

  function startAssistantDeliveryWatch(workspaceId, conversationId, messageAnchor, runEventId, fallbackAttemptHint) {
    var wsId = String(workspaceId || "");
    var convId = String(conversationId || "");
    if (!wsId || !convId) {
      return "";
    }
    var anchor = Number(messageAnchor);
    if (!isFinite(anchor) || anchor < 0) {
      anchor = 0;
    } else {
      anchor = Math.floor(anchor);
    }
    var eventId = trim(String(runEventId || ""));
    var watchKey = assistantDeliveryWatchKeyForRun(wsId, convId, anchor, eventId);
    if (!watchKey) {
      return "";
    }

    stopAssistantDeliveryWatchByKey(watchKey, { clearPending: false });

    var active = true;
    var pollBusy = false;
    var pollTimer = null;
    var deadlineMs = Date.now() + 90000;

    function finish(options) {
      if (!active) {
        return;
      }
      active = false;
      if (pollTimer) {
        clearInterval(pollTimer);
        pollTimer = null;
      }
      delete assistantDeliveryWatchByKey[watchKey];
      var matchedEvent = null;
      if (eventId) {
        matchedEvent = findRunEventByIdForConversation(convId, eventId);
      }
      if (!matchedEvent) {
        matchedEvent = findLatestRunEventByStatus(convId, ["done", "running", "awaiting_decision", "awaiting_approval", "error"]);
      }
      if (matchedEvent && Number(matchedEvent.awaiting_assistant || 0) > 0) {
        matchedEvent.awaiting_assistant = 0;
        persistRunEventsSoon();
      }
      var opts = options && typeof options === "object" ? options : {};
      if (opts.clearPending === false) {
        return;
      }
      if (clearAssistantDeliveryPending(wsId, convId)) {
        renderUi();
      }
    }

    function ensureFallbackMessage() {
      if (conversationHasAssistantAfterAnchor(wsId, convId, anchor)) {
        return false;
      }
      var attempts = Number(fallbackAttemptHint || 0);
      if (!isFinite(attempts) || attempts < 0) {
        attempts = 0;
      }
      var matchedEvent = findRunEventByIdForConversation(convId, eventId);
      if (!matchedEvent) {
        matchedEvent = findLatestRunEventByStatus(convId, ["done", "running", "awaiting_decision", "awaiting_approval", "error"]);
      }
      if (matchedEvent) {
        var eventAttempts = runTraceAttemptCount(matchedEvent);
        if (eventAttempts > attempts) {
          attempts = eventAttempts;
        }
      }
      return appendAssistantMessageOptimistic(wsId, convId, structuredRunFallbackMessage(attempts));
    }

    function tick() {
      if (!active) {
        return;
      }
      if (conversationHasAssistantAfterAnchor(wsId, convId, anchor)) {
        finish();
        return;
      }
      if (Date.now() >= deadlineMs) {
        ensureFallbackMessage();
        finish();
        return;
      }
      if (pollBusy) {
        return;
      }
      pollBusy = true;
      loadConversation({
        workspaceId: wsId,
        conversationId: convId,
        timeoutMs: 15000,
        markSeen: false
      })
        .catch(function () {
          return null;
        })
        .finally(function () {
          pollBusy = false;
          if (active && conversationHasAssistantAfterAnchor(wsId, convId, anchor)) {
            finish();
          }
        });
    }

    assistantDeliveryWatchByKey[watchKey] = {
      stop: finish
    };
    pollTimer = setInterval(tick, 3000);
    setTimeout(tick, 250);
    return watchKey;
  }

  function updateAwaitingApprovalFromQueueSnapshot(workspaceId, conversationId, snapshot) {
    var wsId = String(workspaceId || "");
    var convId = String(conversationId || "");
    if (!wsId || !convId) {
      return;
    }
    var data = snapshot || {};
    var lastStatus = String(data.lastStatus || "");
    var hasApprovalRequest = !!normalizeApprovalRequest(data.approvalRequest);
    var pending = queueNumber(data.pending);
    var running = !!data.running;

    if (lastStatus === "awaiting_approval" || hasApprovalRequest) {
      setAwaitingApprovalState(wsId, convId, true);
      return;
    }

    var explicitNotAwaiting = (
      lastStatus === "done" ||
      lastStatus === "error" ||
      lastStatus === "cancelled" ||
      lastStatus === "awaiting_decision" ||
      running ||
      pending > 0
    );
    if (explicitNotAwaiting) {
      setAwaitingApprovalState(wsId, convId, false);
    }
  }

  function conversationUpdatedNumber(conversation) {
    var parsed = Number(conversation && conversation.updated || 0);
    if (!isFinite(parsed) || parsed < 0) {
      return 0;
    }
    return Math.floor(parsed);
  }

  function conversationCreatedNumber(conversation) {
    var parsed = Number(conversation && conversation.created || 0);
    if (!isFinite(parsed) || parsed < 0) {
      return 0;
    }
    return Math.floor(parsed);
  }

  function persistSeenConversationState() {
    state.seenConversationUpdatedByKey = saveSeenConversationState(state.seenConversationUpdatedByKey || {});
  }

  function seenUpdatedForConversation(workspaceId, conversationId) {
    var key = conversationReadKey(workspaceId, conversationId);
    return parseSeenUpdatedValue(state.seenConversationUpdatedByKey[key]);
  }

  function markConversationSeen(workspaceId, conversationId, conversation) {
    if (!workspaceId || !conversationId) {
      return;
    }

    var updated = conversationUpdatedNumber(conversation);
    if (updated <= 0) {
      var workspace = getWorkspaceById(workspaceId);
      var fallbackConversation = getConversationById(workspace, conversationId);
      updated = conversationUpdatedNumber(fallbackConversation);
    }
    if (updated <= 0) {
      updated = Math.floor(Date.now() / 1000);
    }

    var key = conversationReadKey(workspaceId, conversationId);
    var previous = parseSeenUpdatedValue(state.seenConversationUpdatedByKey[key]);
    if (previous >= updated) {
      return;
    }

    state.seenConversationUpdatedByKey[key] = updated;
    persistSeenConversationState();
  }

  function bootstrapSeenConversationsIfNeeded() {
    if (!state.seenConversationBootstrapPending) {
      return;
    }

    for (var i = 0; i < state.workspaces.length; i += 1) {
      var workspace = state.workspaces[i];
      var workspaceId = workspace && workspace.id ? workspace.id : "";
      if (!workspaceId || !workspace || !Array.isArray(workspace.conversations)) {
        continue;
      }
      for (var j = 0; j < workspace.conversations.length; j += 1) {
        var conversation = workspace.conversations[j] || {};
        if (!conversation.id) {
          continue;
        }
        var updated = conversationUpdatedNumber(conversation);
        if (updated <= 0) {
          continue;
        }
        state.seenConversationUpdatedByKey[conversationReadKey(workspaceId, conversation.id)] = updated;
      }
    }

    state.seenConversationBootstrapPending = false;
    persistSeenConversationState();
  }

  function pruneSeenConversationState() {
    var valid = {};
    for (var i = 0; i < state.workspaces.length; i += 1) {
      var workspace = state.workspaces[i];
      if (!workspace || !workspace.id || !Array.isArray(workspace.conversations)) {
        continue;
      }
      for (var j = 0; j < workspace.conversations.length; j += 1) {
        var conversation = workspace.conversations[j] || {};
        if (!conversation.id) {
          continue;
        }
        valid[conversationReadKey(workspace.id, conversation.id)] = true;
      }
    }

    var changed = false;
    var existingKeys = Object.keys(state.seenConversationUpdatedByKey || {});
    for (var k = 0; k < existingKeys.length; k += 1) {
      var key = existingKeys[k];
      if (!valid[key]) {
        delete state.seenConversationUpdatedByKey[key];
        changed = true;
      }
    }

    if (changed) {
      persistSeenConversationState();
    }
  }

  function isConversationUnread(workspaceId, conversation) {
    if (!workspaceId || !conversation || !conversation.id) {
      return false;
    }
    var updated = conversationUpdatedNumber(conversation);
    if (updated <= 0) {
      return false;
    }
    return updated > seenUpdatedForConversation(workspaceId, conversation.id);
  }

  function queueStatsForConversation(workspaceId, conversationId) {
    var workspace = getWorkspaceById(workspaceId);
    var conversation = getConversationById(workspace, conversationId);
    if (!conversation) {
      return {
        pending: 0,
        running: false,
        done: false,
        lastStatus: "",
        firstId: ""
      };
    }

    return {
      pending: queueNumber(conversation.queue_pending),
      running: String(conversation.queue_running || "0") === "1",
      done: String(conversation.queue_done || "0") === "1",
      lastStatus: String(conversation.queue_last_status || ""),
      firstId: String(conversation.queue_first_id || "")
    };
  }

  function setConversationQueueFields(workspaceId, conversationId, patch) {
    var workspace = getWorkspaceById(workspaceId);
    var conversation = getConversationById(workspace, conversationId);
    if (!conversation || !patch) {
      return;
    }

    if (typeof patch.pending !== "undefined") {
      conversation.queue_pending = String(queueNumber(patch.pending));
    }
    if (typeof patch.running !== "undefined") {
      conversation.queue_running = patch.running ? "1" : "0";
    }
    if (typeof patch.done !== "undefined") {
      conversation.queue_done = patch.done ? "1" : "0";
    }
    if (typeof patch.lastStatus !== "undefined") {
      conversation.queue_last_status = String(patch.lastStatus || "");
    }
    if (typeof patch.firstId !== "undefined") {
      conversation.queue_first_id = String(patch.firstId || "");
    }
    if (typeof patch.decisionRequest !== "undefined") {
      conversation.decision_request = normalizeDecisionRequest(patch.decisionRequest);
    }
    if (typeof patch.approvalRequest !== "undefined") {
      conversation.approval_request = normalizeApprovalRequest(patch.approvalRequest);
    }
  }

  function activeConversationQueueStats() {
    if (!state.activeWorkspaceId || !state.activeConversationId) {
      return {
        pending: 0,
        running: false,
        done: false,
        lastStatus: "",
        firstId: ""
      };
    }
    return queueStatsForConversation(state.activeWorkspaceId, state.activeConversationId);
  }

  function queueConversationKey(workspaceId, conversationId) {
    var wsId = String(workspaceId || "");
    var convId = String(conversationId || "");
    if (!wsId || !convId) {
      return "";
    }
    return conversationReadKey(wsId, convId);
  }

  function normalizeQueueListItem(source) {
    var item = source && typeof source === "object" ? source : {};
    return {
      id: String(item.id || ""),
      order: String(item.order || ""),
      prompt: String(item.prompt || ""),
      run_mode: normalizeRunMode(item.run_mode || "auto"),
      assistant_mode_id: normalizeAssistantModeId(item.assistant_mode_id || ""),
      compute_budget: normalizeComputeBudget(item.compute_budget || "auto"),
      command_exec_mode: normalizeCommandExecModeValue(item.command_exec_mode || ""),
      permission_mode: normalizePermissionModeValue(item.permission_mode || ""),
      programmer_review: normalizeProgrammerReviewEnabledValue(item.programmer_review),
      programmer_review_rounds: normalizeProgrammerReviewRoundsValue(item.programmer_review_rounds || 2),
      explicit_skill_ids: Array.isArray(item.explicit_skill_ids) ? item.explicit_skill_ids : []
    };
  }

  function queueItemsForConversation(workspaceId, conversationId) {
    var key = queueConversationKey(workspaceId, conversationId);
    if (!key) {
      return [];
    }
    var list = state.queueItemsByConversation[key];
    return Array.isArray(list) ? list : [];
  }

  function setQueueItemsForConversation(workspaceId, conversationId, items) {
    var key = queueConversationKey(workspaceId, conversationId);
    if (!key) {
      return;
    }
    if (!Array.isArray(items) || !items.length) {
      delete state.queueItemsByConversation[key];
      return;
    }
    state.queueItemsByConversation[key] = items;
  }

  function clearQueueItemsForConversation(workspaceId, conversationId) {
    var key = queueConversationKey(workspaceId, conversationId);
    if (!key) {
      return;
    }
    delete state.queueItemsByConversation[key];
    delete state.queueItemsLoadingByConversation[key];
    delete state.queueItemsFetchedAtByConversation[key];
  }

  function clearQueueEditPostSaveHold(workspaceId, conversationId) {
    var key = queueConversationKey(workspaceId, conversationId);
    if (!key) {
      return;
    }
    delete state.queueEditPostSaveHoldByConversation[key];
    var timerId = state.queueEditPostSaveHoldTimerByConversation[key];
    if (timerId) {
      clearTimeout(timerId);
    }
    delete state.queueEditPostSaveHoldTimerByConversation[key];
  }

  function queueEditPostSaveHoldForConversation(workspaceId, conversationId) {
    var key = queueConversationKey(workspaceId, conversationId);
    if (!key) {
      return null;
    }
    var hold = state.queueEditPostSaveHoldByConversation[key];
    if (!hold) {
      return null;
    }
    var holdUntil = Number(hold.until || 0);
    if (!isFinite(holdUntil) || holdUntil <= Date.now()) {
      clearQueueEditPostSaveHold(workspaceId, conversationId);
      return null;
    }
    return hold;
  }

  function armQueueEditPostSaveHold(workspaceId, conversationId, itemId, promptText, holdMs) {
    var wsId = String(workspaceId || "");
    var convId = String(conversationId || "");
    var key = queueConversationKey(wsId, convId);
    if (!key) {
      return 0;
    }
    var durationMs = Number(holdMs || 0);
    if (!isFinite(durationMs) || durationMs < 0) {
      durationMs = 0;
    }
    clearQueueEditPostSaveHold(wsId, convId);
    if (durationMs < 50) {
      return 0;
    }
    var holdUntil = Date.now() + durationMs;
    state.queueEditPostSaveHoldByConversation[key] = {
      workspaceId: wsId,
      conversationId: convId,
      itemId: String(itemId || ""),
      prompt: String(promptText || ""),
      until: holdUntil
    };
    state.queueEditPostSaveHoldTimerByConversation[key] = window.setTimeout(function () {
      var current = state.queueEditPostSaveHoldByConversation[key];
      if (!current) {
        return;
      }
      var currentUntil = Number(current.until || 0);
      if (isFinite(currentUntil) && currentUntil > Date.now()) {
        return;
      }
      clearQueueEditPostSaveHold(wsId, convId);
      renderUi();
      kickQueueWorker();
    }, durationMs + 80);
    return durationMs;
  }

  function clearQueueEditState() {
    state.queueEdit.workspaceId = "";
    state.queueEdit.conversationId = "";
    state.queueEdit.itemId = "";
    state.queueEdit.draftText = "";
    state.queueEdit.saving = false;
  }

  function beginQueueItemEdit(workspaceId, conversationId, itemId, initialText) {
    clearQueueEditPostSaveHold(workspaceId, conversationId);
    state.queueEdit.workspaceId = String(workspaceId || "");
    state.queueEdit.conversationId = String(conversationId || "");
    state.queueEdit.itemId = String(itemId || "");
    state.queueEdit.draftText = String(initialText || "");
    state.queueEdit.saving = false;
  }

  function isQueueEditForConversation(workspaceId, conversationId) {
    return (
      !!state.queueEdit.itemId &&
      String(state.queueEdit.workspaceId || "") === String(workspaceId || "") &&
      String(state.queueEdit.conversationId || "") === String(conversationId || "")
    );
  }

  function queueItemPreview(promptText, maxLength) {
    var raw = trim(String(promptText || "").replace(/\s+/g, " "));
    var limit = Number(maxLength || 0);
    if (!isFinite(limit) || limit < 32) {
      limit = 220;
    }
    if (raw.length <= limit) {
      return raw;
    }
    return raw.slice(0, limit - 1) + "…";
  }

  function isConversationQueueBlockedByEdit(workspaceId, conversationId) {
    if (!isQueueEditForConversation(workspaceId, conversationId)) {
      return false;
    }
    var editingItemId = String(state.queueEdit.itemId || "");
    if (!editingItemId) {
      return false;
    }
    var stats = queueStatsForConversation(workspaceId, conversationId);
    if (stats.firstId && stats.firstId === editingItemId) {
      return true;
    }
    var items = queueItemsForConversation(workspaceId, conversationId);
    if (items.length && String(items[0].id || "") === editingItemId) {
      return true;
    }
    return false;
  }

  function isConversationQueueBlockedByPostSaveHold(workspaceId, conversationId) {
    return !!queueEditPostSaveHoldForConversation(workspaceId, conversationId);
  }

  function loadQueueItems(workspaceId, conversationId, options) {
    var wsId = String(workspaceId || "");
    var convId = String(conversationId || "");
    if (!wsId || !convId) {
      return Promise.resolve([]);
    }
    var opts = options || {};
    var force = !!opts.force;
    var key = queueConversationKey(wsId, convId);
    if (!key) {
      return Promise.resolve([]);
    }
    if (!force && state.queueItemsLoadingByConversation[key]) {
      return Promise.resolve(queueItemsForConversation(wsId, convId));
    }
    var minIntervalMs = Number(opts.minIntervalMs || 0);
    if (!isFinite(minIntervalMs) || minIntervalMs < 0) {
      minIntervalMs = 0;
    }
    if (!force && minIntervalMs > 0) {
      var fetchedAt = Number(state.queueItemsFetchedAtByConversation[key] || 0);
      if (fetchedAt > 0 && Date.now() - fetchedAt < minIntervalMs) {
        return Promise.resolve(queueItemsForConversation(wsId, convId));
      }
    }

    state.queueItemsLoadingByConversation[key] = true;
    var limit = Number(opts.limit || 24);
    if (!isFinite(limit) || limit < 1) {
      limit = 24;
    }
    if (limit > 80) {
      limit = 80;
    }

    return apiGet("queue_list", {
      workspace_id: wsId,
      conversation_id: convId,
      limit: String(limit)
    }, { timeoutMs: 12000 })
      .then(function (response) {
        if (!response || !response.success) {
          throw new Error((response && response.error) || "Could not load queued messages");
        }
        var rawItems = Array.isArray(response.items) ? response.items : [];
        var normalizedItems = [];
        for (var i = 0; i < rawItems.length; i += 1) {
          var normalized = normalizeQueueListItem(rawItems[i]);
          if (!normalized.id) {
            continue;
          }
          normalizedItems.push(normalized);
        }
        setQueueItemsForConversation(wsId, convId, normalizedItems);
        state.queueItemsFetchedAtByConversation[key] = Date.now();
        applyQueueStateFromResponse(wsId, convId, response);

        if (isQueueEditForConversation(wsId, convId)) {
          var editingItemId = String(state.queueEdit.itemId || "");
          var stillExists = false;
          for (var j = 0; j < normalizedItems.length; j += 1) {
            if (String(normalizedItems[j].id || "") === editingItemId) {
              stillExists = true;
              break;
            }
          }
          if (!stillExists) {
            clearQueueEditState();
          }
        }
        return normalizedItems;
      })
      .finally(function () {
        delete state.queueItemsLoadingByConversation[key];
      });
  }

  function workspaceUpdatedScore(workspace) {
    if (!workspace || !workspace.conversations || workspace.conversations.length === 0) {
      return 0;
    }
    var max = 0;
    for (var i = 0; i < workspace.conversations.length; i += 1) {
      var score = Number(workspace.conversations[i].updated || 0);
      if (score > max) {
        max = score;
      }
    }
    return max;
  }

  function workspaceCreatedScore(workspace) {
    if (!workspace || !workspace.conversations || workspace.conversations.length === 0) {
      return 0;
    }
    var max = 0;
    for (var i = 0; i < workspace.conversations.length; i += 1) {
      var score = conversationCreatedNumber(workspace.conversations[i]);
      if (score > max) {
        max = score;
      }
    }
    return max;
  }

  function isReservedWorkspaceIdValue(workspaceId) {
    var value = trim(String(workspaceId || "")).toLowerCase();
    return value === "null" || value === "undefined" || value === "none";
  }

  function workspacePathAvailable(workspace) {
    if (!workspace || typeof workspace !== "object") {
      return false;
    }
    var raw = String(workspace.path_exists || "");
    if (raw === "1" || raw.toLowerCase() === "true" || raw.toLowerCase() === "yes") {
      return true;
    }
    if (raw === "0" || raw.toLowerCase() === "false" || raw.toLowerCase() === "no") {
      return false;
    }
    return !!trim(String(workspace.path || ""));
  }

  function workspaceIsUsable(workspace) {
    if (!workspace || typeof workspace !== "object") {
      return false;
    }
    var workspaceId = trim(String(workspace.id || ""));
    if (!workspaceId || isReservedWorkspaceIdValue(workspaceId)) {
      return false;
    }
    return workspacePathAvailable(workspace);
  }

  function firstWorkspaceId(preferUsable) {
    var sorted = getSortedWorkspaces();
    if (!sorted.length) {
      return "";
    }
    if (preferUsable !== false) {
      for (var i = 0; i < sorted.length; i += 1) {
        if (workspaceIsUsable(sorted[i])) {
          return String(sorted[i].id || "");
        }
      }
    }
    return String((sorted[0] && sorted[0].id) || "");
  }

  function getSortedWorkspaces() {
    var list = state.workspaces.slice();
    var order = normalizeOrderedIdList(state.workspaceOrderIds);
    var orderIndex = {};
    for (var i = 0; i < order.length; i += 1) {
      orderIndex[order[i]] = i;
    }
    list.sort(function (a, b) {
      var aUsable = workspaceIsUsable(a) ? 1 : 0;
      var bUsable = workspaceIsUsable(b) ? 1 : 0;
      if (aUsable !== bUsable) {
        return bUsable - aUsable;
      }
      var aid = String(a && a.id || "");
      var bid = String(b && b.id || "");
      var ai = Object.prototype.hasOwnProperty.call(orderIndex, aid) ? Number(orderIndex[aid]) : -1;
      var bi = Object.prototype.hasOwnProperty.call(orderIndex, bid) ? Number(orderIndex[bid]) : -1;
      if (ai >= 0 || bi >= 0) {
        if (ai < 0) {
          return 1;
        }
        if (bi < 0) {
          return -1;
        }
        if (ai !== bi) {
          return ai - bi;
        }
      }
      var au = state.sortMode === "created" ? workspaceCreatedScore(a) : workspaceUpdatedScore(a);
      var bu = state.sortMode === "created" ? workspaceCreatedScore(b) : workspaceUpdatedScore(b);
      if (au !== bu) {
        return bu - au;
      }
      return String(a.name || "").localeCompare(String(b.name || ""));
    });
    return list;
  }

  function getSortedConversations(workspace) {
    var workspaceId = String(workspace && workspace.id || "");
    var list = workspace && workspace.conversations ? workspace.conversations.slice() : [];
    var order = normalizeOrderedIdList(
      workspaceId && state.conversationOrderIdsByWorkspace
        ? state.conversationOrderIdsByWorkspace[workspaceId]
        : []
    );
    var orderIndex = {};
    for (var i = 0; i < order.length; i += 1) {
      orderIndex[order[i]] = i;
    }
    list.sort(function (a, b) {
      var aid = String(a && a.id || "");
      var bid = String(b && b.id || "");
      var ai = Object.prototype.hasOwnProperty.call(orderIndex, aid) ? Number(orderIndex[aid]) : -1;
      var bi = Object.prototype.hasOwnProperty.call(orderIndex, bid) ? Number(orderIndex[bid]) : -1;
      if (ai >= 0 || bi >= 0) {
        if (ai < 0) {
          return 1;
        }
        if (bi < 0) {
          return -1;
        }
        if (ai !== bi) {
          return ai - bi;
        }
      }
      var aScore = state.sortMode === "created" ? conversationCreatedNumber(a) : conversationUpdatedNumber(a);
      var bScore = state.sortMode === "created" ? conversationCreatedNumber(b) : conversationUpdatedNumber(b);
      if (aScore !== bScore) {
        return bScore - aScore;
      }
      return String(a.title || "").localeCompare(String(b.title || ""));
    });
    return list;
  }

  function persistWorkspaceOrderingState() {
    saveWorkspaceOrderState(state.workspaceOrderIds);
    saveConversationOrderState(state.conversationOrderIdsByWorkspace);
  }

  function baseConversationOrderIds(workspace) {
    var list = workspace && workspace.conversations ? workspace.conversations.slice() : [];
    list.sort(function (a, b) {
      var aScore = state.sortMode === "created" ? conversationCreatedNumber(a) : conversationUpdatedNumber(a);
      var bScore = state.sortMode === "created" ? conversationCreatedNumber(b) : conversationUpdatedNumber(b);
      if (aScore !== bScore) {
        return bScore - aScore;
      }
      return String(a.title || "").localeCompare(String(b.title || ""));
    });
    var out = [];
    for (var i = 0; i < list.length; i += 1) {
      var id = trim(String(list[i] && list[i].id || ""));
      if (id) {
        out.push(id);
      }
    }
    return out;
  }

  function syncWorkspaceOrderingWithState(options) {
    var opts = options || {};
    var prependUnknownWorkspaces = opts.prependUnknownWorkspaces !== false;
    var workspaceIds = [];
    for (var i = 0; i < state.workspaces.length; i += 1) {
      var wsId = trim(String(state.workspaces[i] && state.workspaces[i].id || ""));
      if (wsId) {
        workspaceIds.push(wsId);
      }
    }

    var knownWorkspaceOrder = normalizeOrderedIdList(state.workspaceOrderIds);
    var knownWorkspaceSet = {};
    for (var k = 0; k < knownWorkspaceOrder.length; k += 1) {
      knownWorkspaceSet[knownWorkspaceOrder[k]] = true;
    }
    var missingWorkspaceIds = [];
    for (var j = 0; j < workspaceIds.length; j += 1) {
      if (!knownWorkspaceSet[workspaceIds[j]]) {
        missingWorkspaceIds.push(workspaceIds[j]);
      }
    }
    var nextWorkspaceOrder = prependUnknownWorkspaces
      ? missingWorkspaceIds.concat(knownWorkspaceOrder)
      : knownWorkspaceOrder.concat(missingWorkspaceIds);
    var validWorkspaceOrder = [];
    var validWorkspaceSet = {};
    for (var w = 0; w < nextWorkspaceOrder.length; w += 1) {
      var candidateWorkspaceId = nextWorkspaceOrder[w];
      if (validWorkspaceSet[candidateWorkspaceId]) {
        continue;
      }
      var exists = false;
      for (var wx = 0; wx < workspaceIds.length; wx += 1) {
        if (workspaceIds[wx] === candidateWorkspaceId) {
          exists = true;
          break;
        }
      }
      if (!exists) {
        continue;
      }
      validWorkspaceSet[candidateWorkspaceId] = true;
      validWorkspaceOrder.push(candidateWorkspaceId);
    }
    state.workspaceOrderIds = validWorkspaceOrder;

    var nextConversationOrderByWorkspace = {};
    var existingConversationOrderByWorkspace = state.conversationOrderIdsByWorkspace && typeof state.conversationOrderIdsByWorkspace === "object"
      ? state.conversationOrderIdsByWorkspace
      : {};
    for (var si = 0; si < state.workspaces.length; si += 1) {
      var workspace = state.workspaces[si] || {};
      var workspaceId = trim(String(workspace.id || ""));
      if (!workspaceId) {
        continue;
      }
      var existingIds = normalizeOrderedIdList(existingConversationOrderByWorkspace[workspaceId]);
      var conversationIds = [];
      var conversationSet = {};
      var conversations = Array.isArray(workspace.conversations) ? workspace.conversations : [];
      for (var ci = 0; ci < conversations.length; ci += 1) {
        var conversationId = trim(String(conversations[ci] && conversations[ci].id || ""));
        if (!conversationId || conversationSet[conversationId]) {
          continue;
        }
        conversationSet[conversationId] = true;
        conversationIds.push(conversationId);
      }
      var validExistingIds = [];
      var validExistingSet = {};
      for (var ei = 0; ei < existingIds.length; ei += 1) {
        var existingId = existingIds[ei];
        if (conversationSet[existingId] && !validExistingSet[existingId]) {
          validExistingSet[existingId] = true;
          validExistingIds.push(existingId);
        }
      }
      var missingConversationIds = [];
      for (var mi = 0; mi < conversationIds.length; mi += 1) {
        if (!validExistingSet[conversationIds[mi]]) {
          missingConversationIds.push(conversationIds[mi]);
        }
      }
      var orderedIds = validExistingIds.length
        ? missingConversationIds.concat(validExistingIds)
        : baseConversationOrderIds(workspace);
      if (orderedIds.length) {
        nextConversationOrderByWorkspace[workspaceId] = normalizeOrderedIdList(orderedIds);
      }
    }
    state.conversationOrderIdsByWorkspace = nextConversationOrderByWorkspace;
  }

  function moveWorkspaceToFront(workspaceId, options) {
    var wsId = trim(String(workspaceId || ""));
    if (!wsId) {
      return;
    }
    var next = [wsId];
    var current = normalizeOrderedIdList(state.workspaceOrderIds);
    for (var i = 0; i < current.length; i += 1) {
      if (current[i] !== wsId) {
        next.push(current[i]);
      }
    }
    state.workspaceOrderIds = next;
    if (!options || options.persist !== false) {
      persistWorkspaceOrderingState();
    }
  }

  function moveConversationToFront(workspaceId, conversationId, options) {
    var wsId = trim(String(workspaceId || ""));
    var convId = trim(String(conversationId || ""));
    if (!wsId || !convId) {
      return;
    }
    if (!state.conversationOrderIdsByWorkspace || typeof state.conversationOrderIdsByWorkspace !== "object") {
      state.conversationOrderIdsByWorkspace = {};
    }
    var current = normalizeOrderedIdList(state.conversationOrderIdsByWorkspace[wsId]);
    var next = [convId];
    for (var i = 0; i < current.length; i += 1) {
      if (current[i] !== convId) {
        next.push(current[i]);
      }
    }
    state.conversationOrderIdsByWorkspace[wsId] = next;
    if (!options || options.persist !== false) {
      persistWorkspaceOrderingState();
    }
  }

  function markConversationActivity(workspaceId, conversationId) {
    var wsId = trim(String(workspaceId || ""));
    var convId = trim(String(conversationId || ""));
    if (!wsId || !convId) {
      return;
    }
    moveConversationToFront(wsId, convId, { persist: false });
    moveWorkspaceToFront(wsId, { persist: false });
    var workspace = getWorkspaceById(wsId);
    var conversation = getConversationById(workspace, convId);
    if (conversation) {
      conversation.updated = String(Math.floor(Date.now() / 1000));
    }
    persistWorkspaceOrderingState();
  }

  function findNextQueuedConversation() {
    if (state.activeWorkspaceId && state.activeConversationId) {
      var activeStats = queueStatsForConversation(state.activeWorkspaceId, state.activeConversationId);
      if (
        activeStats.pending > 0 &&
        !isConversationQueueBlockedByEdit(state.activeWorkspaceId, state.activeConversationId) &&
        !isConversationQueueBlockedByPostSaveHold(state.activeWorkspaceId, state.activeConversationId)
      ) {
        return {
          workspaceId: state.activeWorkspaceId,
          conversationId: state.activeConversationId
        };
      }
    }

    var workspaces = getSortedWorkspaces();
    for (var i = 0; i < workspaces.length; i += 1) {
      var conversations = getSortedConversations(workspaces[i]);
      for (var j = 0; j < conversations.length; j += 1) {
        if (
          queueNumber(conversations[j].queue_pending) > 0 &&
          !isConversationQueueBlockedByEdit(workspaces[i].id, conversations[j].id) &&
          !isConversationQueueBlockedByPostSaveHold(workspaces[i].id, conversations[j].id)
        ) {
          return {
            workspaceId: workspaces[i].id,
            conversationId: conversations[j].id
          };
        }
      }
    }

    return null;
  }

  function hasDraftForWorkspace(workspace) {
    if (!workspace) {
      return false;
    }
    if (state.activeDraftWorkspaceId === workspace.id) {
      return true;
    }
    if (workspace.draft_exists === "1") {
      return true;
    }
    if (trim(state.draftTextByWorkspace[workspace.id])) {
      return true;
    }
    return false;
  }

  function isConversationRelevant(workspaceId, conversation) {
    if (!conversation) {
      return false;
    }
    if (workspaceId === state.activeWorkspaceId && conversation.id === state.activeConversationId) {
      return true;
    }
    if (conversationDecisionRequest(conversation)) {
      return true;
    }
    if (String(conversation.queue_last_status || "") === "awaiting_decision") {
      return true;
    }
    if (String(conversation.queue_last_status || "") === "awaiting_approval") {
      return true;
    }
    if (isAwaitingApprovalConversation(workspaceId, conversation.id)) {
      return true;
    }
    if (queueNumber(conversation.queue_pending) > 0) {
      return true;
    }
    if (String(conversation.queue_running || "0") === "1") {
      return true;
    }
    if (String(conversation.queue_done || "0") === "1" && isConversationUnread(workspaceId, conversation)) {
      return true;
    }
    return false;
  }

  function isConversationRunning(workspaceId, conversation) {
    if (!workspaceId || !conversation || !conversation.id) {
      return false;
    }
    var events = runEventsForConversation(conversation.id);
    for (var i = events.length - 1; i >= 0; i -= 1) {
      if (String(events[i].status || "") === "running") {
        return true;
      }
    }
    if (String(conversation.queue_running || "0") === "1") {
      return true;
    }
    if (String(conversation.queue_last_status || "") === "running") {
      return true;
    }
    if (
      state.busy &&
      String(state.runningWorkspaceId || "") === String(workspaceId) &&
      String(state.runningConversationId || "") === String(conversation.id)
    ) {
      return true;
    }
    return false;
  }

  function formatAgeShort(epochSeconds) {
    var ts = Number(epochSeconds || 0);
    if (!isFinite(ts) || ts <= 0) {
      return "now";
    }
    var now = Math.floor(Date.now() / 1000);
    var diff = now - Math.floor(ts);
    if (diff < 0) {
      diff = 0;
    }
    if (diff < 60) {
      return "now";
    }
    if (diff < 3600) {
      return Math.floor(diff / 60) + "m";
    }
    if (diff < 86400) {
      return Math.floor(diff / 3600) + "h";
    }
    if (diff < 86400 * 30) {
      return Math.floor(diff / 86400) + "d";
    }
    if (diff < 86400 * 365) {
      return Math.floor(diff / (86400 * 30)) + "mo";
    }
    return Math.floor(diff / (86400 * 365)) + "y";
  }

  function conversationStatusPillMarkup(workspaceId, conversation) {
    if (!workspaceId || !conversation || !conversation.id) {
      return "";
    }
    var lastStatus = String(conversation.queue_last_status || "");
    var awaitingApproval = isAwaitingApprovalConversation(workspaceId, conversation.id) || lastStatus === "awaiting_approval";
    if (awaitingApproval) {
      return "<span class='thread-status-pill approval'><span class='pill-spinner' aria-hidden='true'></span><span>Awaiting approval</span></span>";
    }
    var decisionRequest = conversationDecisionRequest(conversation);
    if (decisionRequest || lastStatus === "awaiting_decision") {
      return "<span class='thread-status-pill decision'>Awaiting decision</span>";
    }
    return "";
  }

  function conversationMetaMarkup(workspaceId, conversation) {
    var gitState = state.gitByWorkspace[workspaceId] || {};
    var add = Number(gitState.added || 0);
    var del = Number(gitState.deleted || 0);
    var hasDiff = add > 0 || del > 0;
    var age = formatAgeShort(conversationCreatedNumber(conversation));
    var conversationId = conversation && conversation.id ? conversation.id : "";
    var archiveKey = conversationReadKey(workspaceId, conversationId);
    var isArchiveArmed = archiveKey === state.pendingArchiveKey;
    var isArchiveSubmitting = archiveKey === state.pendingArchiveSubmittingKey;
    var html = "<span class='conversation-meta' title='Project diff since last commit'>";
    if (hasDiff) {
      html += "<span class='meta-diff'>";
      html += "<span class='meta-add' title='Lines added since last commit'>+" + escHtml(String(add)) + "</span>";
      html += "<span class='meta-del' title='Lines removed since last commit'>-" + escHtml(String(del)) + "</span>";
      html += "</span>";
    }
    html += "<span class='meta-age-slot'>";
    html += "<span class='meta-age' title='Thread age'>" + ((isArchiveArmed || isArchiveSubmitting) ? "" : escHtml(age)) + "</span>";
    html += archiveControlMarkup(workspaceId, conversationId);
    html += "</span></span>";
    return html;
  }

  function conversationDisplayTitle(title) {
    var text = String(title || "Thread");
    text = text.replace(/[.](?:[\s\u00a0]+[.]){2,}/g, "...");
    text = text.replace(/…+/g, "...");
    text = text.replace(/\s+/g, " ").trim();
    return text || "Thread";
  }

  function threadFolderPathTooltip(workspaceId) {
    var workspace = getWorkspaceById(workspaceId);
    var path = trim(workspace && workspace.path ? workspace.path : "");
    return path;
  }

  function archiveControlMarkup(workspaceId, conversationId) {
    var key = conversationReadKey(workspaceId, conversationId);
    var isArmed = key === state.pendingArchiveKey;
    var isSubmitting = key === state.pendingArchiveSubmittingKey;
    if (!isArmed) {
      return (
        "<span class='thread-archive-wrap'><button type='button' class='thread-archive-btn' title='Archive thread' data-action='arm-archive-conversation' data-workspace-id='" + escHtml(workspaceId) + "' data-conversation-id='" + escHtml(conversationId) + "'><span class='archive-icon' aria-hidden='true'><svg viewBox='0 0 16 16' fill='none' stroke='currentColor' stroke-width='1.4' stroke-linecap='round' stroke-linejoin='round'><rect x='2.4' y='3.2' width='11.2' height='9.2' rx='1.4'></rect><path d='M4.5 6.1h7'></path><path d='M6 8.3h4'></path></svg></span></button></span>"
      );
    }

    var ready = !isSubmitting;
    var readyClass = ready ? " ready" : "";
    var loadingClass = isSubmitting ? " loading" : "";
    var label = isSubmitting
      ? "<span class='thread-confirm-spinner' aria-hidden='true'></span><span>Archiving...</span>"
      : "Confirm";
    return (
      "<span class='thread-archive-wrap'><button type='button' class='thread-confirm-btn" + readyClass + loadingClass + "' data-action='confirm-archive-conversation' data-workspace-id='" + escHtml(workspaceId) + "' data-conversation-id='" + escHtml(conversationId) + "'>" + label + "</button></span>"
    );
  }

  function activeModelName() {
    if (state.activeConversation && state.activeConversation.model) {
      return state.activeConversation.model;
    }

    if (state.activeDraftWorkspaceId && state.draftModelByWorkspace[state.activeDraftWorkspaceId]) {
      return state.draftModelByWorkspace[state.activeDraftWorkspaceId];
    }

    if (state.models.length > 0) {
      return state.models[0];
    }

    return "";
  }

  function normalizePermissionToggles() {
    if (!state.networkAccess && state.webAccess) {
      state.webAccess = false;
      storageSet("artificer.webAccess", "0");
    }
  }

  function permissionModeLabel(mode) {
    switch (mode) {
      case "workspace-write":
        return "Project write";
      case "read-only":
        return "Read only";
      case "full-access":
        return "Full access";
      default:
        return "Default permissions";
    }
  }

  function permissionModeIconMarkup(mode) {
    if (mode === "workspace-write") {
      return "<svg viewBox='0 0 16 16' fill='none' stroke='currentColor' stroke-width='1.4' stroke-linecap='round' stroke-linejoin='round'><path d='M3.1 12.9l2.9-.6 6-6-2.3-2.3-6 6z'></path><path d='M8.9 3.7l2.3 2.3'></path></svg>";
    }
    if (mode === "read-only") {
      return "<svg viewBox='0 0 16 16' fill='none' stroke='currentColor' stroke-width='1.4' stroke-linecap='round' stroke-linejoin='round'><path d='M1.8 8s2.3-3.6 6.2-3.6S14.2 8 14.2 8s-2.3 3.6-6.2 3.6S1.8 8 1.8 8z'></path><circle cx='8' cy='8' r='1.7'></circle></svg>";
    }
    if (mode === "full-access") {
      return "<svg viewBox='0 0 16 16' fill='none' stroke='currentColor' stroke-width='1.4' stroke-linecap='round' stroke-linejoin='round'><circle cx='8' cy='8' r='1.6'></circle><path d='M8 2.3v1.3'></path><path d='M8 12.4v1.3'></path><path d='M2.3 8h1.3'></path><path d='M12.4 8h1.3'></path><path d='M3.9 3.9l.9.9'></path><path d='M11.2 11.2l.9.9'></path><path d='M12.1 3.9l-.9.9'></path><path d='M4.8 11.2l-.9.9'></path></svg>";
    }
    return "<svg viewBox='0 0 16 16' fill='none' stroke='currentColor' stroke-width='1.4' stroke-linecap='round' stroke-linejoin='round'><path d='M8 1.6l4.6 1.8v3.7c0 3-1.7 5.4-4.6 7.2-2.9-1.8-4.6-4.2-4.6-7.2V3.4L8 1.6z'></path></svg>";
  }

  function commandExecModeLabel(mode) {
    if (mode === "none") {
      return "None";
    }
    if (mode === "ask-all") {
      return "Ask all";
    }
    if (mode === "ask-some" || mode === "ask") {
      return "Ask some";
    }
    if (mode === "all") {
      return "Ask none";
    }
    return "Ask some";
  }

  function normalizeCommandExecModeValue(mode) {
    var value = trim(String(mode || "")).toLowerCase();
    if (value === "ask") {
      return "ask-some";
    }
    if (value === "none" || value === "ask-all" || value === "ask-some" || value === "all") {
      return value;
    }
    return "";
  }

  function normalizePermissionModeValue(mode) {
    var value = trim(String(mode || "")).toLowerCase();
    if (value === "workspace-write" || value === "read-only" || value === "default" || value === "full-access") {
      return value;
    }
    return "";
  }

  function gitDeltaMarkup(added, deleted) {
    var addCount = Number(added || 0);
    var delCount = Number(deleted || 0);
    return "<span class='git-delta'><span class='git-add'>+" + addCount + "</span> <span class='git-del'>-" + delCount + "</span></span>";
  }

  function activeGitState() {
    return (
      state.gitByWorkspace[state.activeWorkspaceId] || {
        is_repo: false,
        branch: "",
        ahead: 0,
        behind: 0,
        added: 0,
        deleted: 0,
        changes: 0,
        staged_changes: 0,
        unstaged_changes: 0
      }
    );
  }

  function closeAllMenus(exceptId) {
    var ids = Object.keys(menuById);
    for (var i = 0; i < ids.length; i += 1) {
      var id = ids[i];
      if (exceptId && id === exceptId) {
        continue;
      }
      if (menuById[id]) {
        menuById[id].classList.add("hidden");
      }
    }

    if (el.modelStatusBtn) {
      el.modelStatusBtn.setAttribute("aria-expanded", "false");
    }
    if (el.openMenuBtn) {
      el.openMenuBtn.setAttribute("aria-expanded", "false");
    }
    if (el.commitMenuBtn) {
      el.commitMenuBtn.setAttribute("aria-expanded", "false");
    }
    if (el.triageCleanupMenuBtn) {
      el.triageCleanupMenuBtn.setAttribute("aria-expanded", "false");
    }
    if (el.branchMenuBtn) {
      el.branchMenuBtn.setAttribute("aria-expanded", "false");
    }
    if (el.permissionsMenuBtn) {
      el.permissionsMenuBtn.setAttribute("aria-expanded", "false");
    }
    if (el.modelPickerBtn) {
      el.modelPickerBtn.setAttribute("aria-expanded", "false");
    }
    if (el.runModeBtn) {
      el.runModeBtn.setAttribute("aria-expanded", "false");
    }
    if (el.themePickerBtn) {
      el.themePickerBtn.setAttribute("aria-expanded", "false");
    }
    if (el.reasoningMenuBtn) {
      el.reasoningMenuBtn.setAttribute("aria-expanded", "false");
    }
    if (el.computeMenuBtn) {
      el.computeMenuBtn.setAttribute("aria-expanded", "false");
    }
    if (el.runBtn) {
      el.runBtn.setAttribute("aria-expanded", "false");
    }
    if (el.organizeBtn) {
      el.organizeBtn.setAttribute("aria-expanded", "false");
    }
    if (el.contextWindowBtn) {
      el.contextWindowBtn.setAttribute("aria-expanded", "false");
    }

    if (!exceptId && state.openWorkspaceMenuWorkspaceId) {
      state.openWorkspaceMenuWorkspaceId = "";
      renderWorkspaceTree();
    }
    if (!exceptId || exceptId !== "run-mode-menu") {
      state.runModeMoreExpanded = false;
    }
    if (!exceptId && state.triageOtherInputProposalId) {
      state.triageOtherInputProposalId = "";
    }
  }

  function toggleMenu(menuId, buttonEl) {
    var menu = menuById[menuId];
    if (!menu) {
      return;
    }

    var isOpen = !menu.classList.contains("hidden");
    closeAllMenus();

    if (isOpen) {
      return;
    }

    menu.classList.remove("hidden");
    if (buttonEl) {
      buttonEl.setAttribute("aria-expanded", "true");
    }
  }

  function openModal(modalEl) {
    if (!modalEl) {
      return;
    }
    modalEl.classList.remove("hidden");
  }

  function closeModal(modalEl) {
    if (!modalEl) {
      return;
    }
    modalEl.classList.add("hidden");
  }

  function closeAllModals() {
    closeModal(el.workspaceModal);
    closeModal(el.automationModal);
    closeModal(el.commitModal);
    closeModal(el.runActionModal);
    closeModal(el.settingsModal);
    closeModal(el.commandApprovalModal);
    closeModal(el.multi_agentModal);
  }

  function setWorkspaceDropActive(active) {
    if (active) {
      el.workspacePanel.classList.add("drop-active");
    } else {
      el.workspacePanel.classList.remove("drop-active");
    }
  }

  function setComposerDragActive(active) {
    if (!el.runForm) {
      return;
    }
    el.runForm.classList.toggle("drag-active", !!active);
  }

  function setBusy(value, workspaceId, conversationId) {
    state.busy = !!value;
    if (state.busy) {
      state.runningWorkspaceId = workspaceId || state.runningWorkspaceId || state.activeWorkspaceId || "";
      state.runningConversationId = conversationId || state.runningConversationId || state.activeConversationId || "";
      if (!liveRunTickTimer) {
        liveRunTickTimer = setInterval(function () {
          refreshRunningElapsedBadges();
        }, 1000);
      }
      if (!runReconcileTimer) {
        runReconcileTimer = setInterval(function () {
          reconcileRunningState();
        }, 2200);
      }
    } else {
      state.runningWorkspaceId = "";
      state.runningConversationId = "";
      if (runReconcileTimer) {
        clearInterval(runReconcileTimer);
        runReconcileTimer = null;
      }
      runReconcileBusy = false;
    }
  }

  function activeConversationMissingKey(workspaceId, conversationId) {
    var wsId = String(workspaceId || "");
    var convId = String(conversationId || "");
    if (!wsId || !convId) {
      return "";
    }
    return conversationReadKey(wsId, convId);
  }

  function clearActiveConversationMissingMarker(workspaceId, conversationId) {
    var key = activeConversationMissingKey(workspaceId, conversationId);
    if (!key) {
      return;
    }
    delete state.activeConversationMissingSinceByKey[key];
  }

  function pruneActiveConversationMissingMarkers() {
    var keepKey = activeConversationMissingKey(state.activeWorkspaceId, state.activeConversationId);
    var keys = Object.keys(state.activeConversationMissingSinceByKey || {});
    for (var i = 0; i < keys.length; i += 1) {
      var key = String(keys[i] || "");
      if (!key || !keepKey || key !== keepKey) {
        delete state.activeConversationMissingSinceByKey[key];
      }
    }
  }

  function conversationHasTransientInFlightSignals(workspaceId, conversationId) {
    var wsId = String(workspaceId || "");
    var convId = String(conversationId || "");
    if (!wsId || !convId) {
      return false;
    }
    var loadingKey = conversationReadKey(wsId, convId);
    if (state.activeConversationLoading && String(state.activeConversationLoadingKey || "") === loadingKey) {
      return true;
    }
    if (
      String(state.runningWorkspaceId || "") === wsId &&
      String(state.runningConversationId || "") === convId
    ) {
      return true;
    }
    var pendingKey = outgoingKeyFor(wsId, convId, "");
    if (pendingOutgoingList(pendingKey).length > 0) {
      return true;
    }
    if (assistantDeliveryPendingCount(wsId, convId) > 0 || isAwaitingApprovalConversation(wsId, convId)) {
      return true;
    }
    var events = runEventsForConversation(convId);
    for (var i = events.length - 1; i >= 0; i -= 1) {
      var event = events[i] || {};
      var status = String(event.status || "");
      if (
        status === "running" ||
        status === "awaiting_approval" ||
        status === "awaiting_decision" ||
        Number(event.awaiting_assistant || 0) > 0
      ) {
        return true;
      }
    }
    return false;
  }

  function conversationSummaryFromClientState(workspaceId, conversationId) {
    var wsId = String(workspaceId || "");
    var convId = String(conversationId || "");
    if (!wsId || !convId) {
      return null;
    }
    var cacheKey = conversationReadKey(wsId, convId);
    var candidate = cloneConversationData(state.conversationCacheByKey[cacheKey]);
    if (
      !candidate &&
      state.activeConversation &&
      String(state.activeWorkspaceId || "") === wsId &&
      String(state.activeConversationId || "") === convId
    ) {
      candidate = cloneConversationData(state.activeConversation);
    }
    if (!candidate) {
      var optimisticKey = optimisticConversationKey(wsId, convId);
      var optimisticEntry = state.optimisticConversationsByKey[optimisticKey];
      if (optimisticEntry && optimisticEntry.conversation) {
        candidate = cloneConversationData(optimisticEntry.conversation);
      }
    }
    var summary = normalizeOptimisticConversationSummary(candidate || {}, convId);
    if (!summary) {
      return null;
    }
    if (!trim(String(summary.title || ""))) {
      summary.title = "Thread";
    }
    return summary;
  }

  function reinsertMissingConversationSummary(workspaceId, conversationId) {
    var wsId = String(workspaceId || "");
    var convId = String(conversationId || "");
    var workspace = getWorkspaceById(wsId);
    if (!wsId || !convId || !workspace) {
      return false;
    }
    if (!Array.isArray(workspace.conversations)) {
      workspace.conversations = [];
    }
    if (getConversationById(workspace, convId)) {
      return true;
    }
    var summary = conversationSummaryFromClientState(wsId, convId);
    if (!summary) {
      return false;
    }
    workspace.conversations.unshift(summary);
    return true;
  }

  function shouldRetainMissingActiveConversation(workspaceId, conversationId) {
    var wsId = String(workspaceId || "");
    var convId = String(conversationId || "");
    var key = activeConversationMissingKey(wsId, convId);
    if (!key) {
      return false;
    }
    var now = Date.now();
    var firstMissingAt = Number(state.activeConversationMissingSinceByKey[key] || 0);
    if (!isFinite(firstMissingAt) || firstMissingAt <= 0) {
      firstMissingAt = now;
      state.activeConversationMissingSinceByKey[key] = firstMissingAt;
    }
    var missingAgeMs = now - firstMissingAt;
    if (missingAgeMs > ACTIVE_CONVERSATION_MISSING_HARD_MAX_MS) {
      return false;
    }
    if (conversationHasTransientInFlightSignals(wsId, convId)) {
      return reinsertMissingConversationSummary(wsId, convId);
    }
    if (missingAgeMs <= ACTIVE_CONVERSATION_MISSING_STALE_GRACE_MS) {
      return reinsertMissingConversationSummary(wsId, convId);
    }
    return false;
  }

  function ensureSelection() {
    if (state.activeTriage) {
      state.activeWorkspaceId = "";
      state.activeConversationId = "";
      state.activeConversation = null;
      state.activeDraftWorkspaceId = "";
      pruneActiveConversationMissingMarkers();
      return;
    }
    if (!state.workspaces.length) {
      state.activeWorkspaceId = "";
      state.activeConversationId = "";
      state.activeConversation = null;
      state.activeDraftWorkspaceId = "";
      pruneActiveConversationMissingMarkers();
      return;
    }

    var activeWorkspace = getWorkspaceById(state.activeWorkspaceId);
    if (!activeWorkspace || !workspaceIsUsable(activeWorkspace)) {
      state.activeWorkspaceId = firstWorkspaceId(true);
      state.activeConversationId = "";
      state.activeConversation = null;
      state.activeDraftWorkspaceId = "";
    }

    if (state.activeWorkspaceId && typeof state.expandedWorkspaceIds[state.activeWorkspaceId] === "undefined") {
      state.expandedWorkspaceIds[state.activeWorkspaceId] = true;
    }

    if (state.activeConversationId) {
      var workspace = getWorkspaceById(state.activeWorkspaceId);
      var activeConversationId = String(state.activeConversationId || "");
      if (!getConversationById(workspace, activeConversationId)) {
        if (!shouldRetainMissingActiveConversation(state.activeWorkspaceId, activeConversationId)) {
          clearActiveConversationMissingMarker(state.activeWorkspaceId, activeConversationId);
          state.activeConversationId = "";
          state.activeConversation = null;
        }
      } else {
        clearActiveConversationMissingMarker(state.activeWorkspaceId, activeConversationId);
      }
    }

    if (state.activeDraftWorkspaceId && !getWorkspaceById(state.activeDraftWorkspaceId)) {
      state.activeDraftWorkspaceId = "";
    }
    pruneActiveConversationMissingMarkers();
  }

  function resolveWorkspaceFromRouteToken(token) {
    var raw = String(token || "");
    if (!raw) {
      return null;
    }
    var idHint = String(routeIdHint(raw) || "");
    for (var i = 0; i < state.workspaces.length; i += 1) {
      if (String(state.workspaces[i].id || "") === idHint) {
        return state.workspaces[i];
      }
    }
    var wantedSlug = slugifyRoutePart(raw);
    for (var j = 0; j < state.workspaces.length; j += 1) {
      if (slugifyRoutePart(state.workspaces[j].name || state.workspaces[j].id) === wantedSlug) {
        return state.workspaces[j];
      }
    }
    return null;
  }

  function resolveConversationFromRouteToken(workspace, token) {
    if (!workspace || !token || !Array.isArray(workspace.conversations)) {
      return null;
    }
    var raw = String(token || "");
    var idHint = String(routeIdHint(raw) || "");
    for (var i = 0; i < workspace.conversations.length; i += 1) {
      if (String(workspace.conversations[i].id || "") === idHint) {
        return workspace.conversations[i];
      }
    }
    var wantedSlug = slugifyRoutePart(raw);
    var match = null;
    var matchUpdated = 0;
    for (var j = 0; j < workspace.conversations.length; j += 1) {
      var conversation = workspace.conversations[j] || {};
      var slug = slugifyRoutePart(conversation.title || conversation.id);
      if (slug !== wantedSlug) {
        continue;
      }
      var updated = conversationUpdatedNumber(conversation);
      if (!match || updated > matchUpdated) {
        match = conversation;
        matchUpdated = updated;
      }
    }
    return match;
  }

  function applyRouteSelectionIfPending() {
    var requested = state.pendingRouteSelection;
    if (!requested || !requested.workspaceToken) {
      return;
    }
    state.pendingRouteSelection = null;
    var workspace = resolveWorkspaceFromRouteToken(requested.workspaceToken);
    if (!workspace) {
      return;
    }
    state.activeWorkspaceId = workspace.id;
    state.activeConversation = null;
    state.activeDraftWorkspaceId = "";
    state.expandedWorkspaceIds[workspace.id] = true;
    var conversation = resolveConversationFromRouteToken(workspace, requested.conversationToken || "");
    state.activeConversationId = conversation && conversation.id ? conversation.id : "";
  }

  function buildRoutePathForSelection() {
    var workspace = getWorkspaceById(state.activeWorkspaceId);
    if (!workspace) {
      return "/";
    }
    var workspaceToken = routeTokenFromLabelAndId(workspace.name || workspace.id, workspace.id);
    if (!workspaceToken) {
      return "/";
    }
    var parts = [encodeRoutePart(workspaceToken)];
    if (state.activeConversationId) {
      var conversation = getConversationById(workspace, state.activeConversationId);
      var conversationToken = routeTokenFromLabelAndId(
        (conversation && (conversation.title || conversation.id)) || state.activeConversationId,
        state.activeConversationId
      );
      if (conversationToken) {
        parts.push(encodeRoutePart(conversationToken));
      }
    }
    return "/" + parts.join("/") + "/";
  }

  function buildRouteHashForSelection() {
    var routePath = normalizeRoutePath(buildRoutePathForSelection());
    if (routePath === "/") {
      return "";
    }
    return "#" + routePath;
  }

  function syncSelectionUrl(replace) {
    if (state.suppressSelectionUrlSync || typeof window === "undefined" || !window.history || !window.location) {
      return;
    }
    var currentPath = normalizeRoutePath(window.location.pathname || "/");
    var currentSearch = String(window.location.search || "");
    var currentHash = normalizeRouteHash(window.location.hash || "");
    var nextHash = normalizeRouteHash(buildRouteHashForSelection());
    if (nextHash === currentHash) {
      return;
    }
    var method = replace ? "replaceState" : "pushState";
    if (typeof window.history[method] !== "function") {
      return;
    }
    try {
      window.history[method]({}, "", currentPath + currentSearch + nextHash);
    } catch (_err) {
      return;
    }
  }

  function navigateToRouteSelection() {
    var requested = parseRouteSelectionFromLocation();
    if (!requested || !requested.workspaceToken) {
      return Promise.resolve();
    }
    if (!state.workspaces.length) {
      state.pendingRouteSelection = requested;
      return Promise.resolve();
    }
    var workspace = resolveWorkspaceFromRouteToken(requested.workspaceToken);
    if (!workspace) {
      return Promise.resolve();
    }
    var conversation = resolveConversationFromRouteToken(workspace, requested.conversationToken || "");
    if (conversation && String(conversation.id || "") === String(state.activeConversationId || "") && String(workspace.id || "") === String(state.activeWorkspaceId || "")) {
      return Promise.resolve();
    }
