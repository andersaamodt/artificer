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
    try {
      window.localStorage.setItem(
        seenConversationStorageKey,
        JSON.stringify(state.seenConversationUpdatedByKey || {})
      );
    } catch (_err) {
      return;
    }
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
    state.suppressSelectionUrlSync = true;
    var task = conversation && conversation.id
      ? selectConversation(workspace.id, conversation.id)
      : selectWorkspace(workspace.id);
    return task.finally(function () {
      state.suppressSelectionUrlSync = false;
    });
  }

  function newSelectionVersion() {
    state.selectionVersion += 1;
    return state.selectionVersion;
  }

  function isSelectionVersionCurrent(version) {
    return version === state.selectionVersion;
  }

  function isChatAtBottom() {
    if (!el.chatLog) {
      return true;
    }
    var remaining = el.chatLog.scrollHeight - el.chatLog.clientHeight - el.chatLog.scrollTop;
    return remaining <= 8;
  }

  function updateChatJumpButton() {
    if (!el.chatJumpBottomBtn) {
      return;
    }
    var shouldShow = !state.chatAutoScroll && !!state.activeConversationId;
    el.chatJumpBottomBtn.classList.toggle("show", shouldShow);
    el.chatJumpBottomBtn.classList.toggle("hidden", !shouldShow);
  }

  function jumpChatToBottom() {
    if (!el.chatLog) {
      return;
    }
    el.chatLog.scrollTop = el.chatLog.scrollHeight;
    state.chatAutoScroll = true;
    updateChatJumpButton();
  }

  function normalizedRunEventsList(list) {
    var items = Array.isArray(list) ? list : [];
    var normalized = [];
    for (var i = 0; i < items.length; i += 1) {
      var event = sanitizeRunEventForStorage(items[i]);
      if (event) {
        normalized.push(event);
      }
    }
    normalized.sort(compareRunEventsChronological);
    if (normalized.length > 22) {
      normalized = normalized.slice(normalized.length - 22);
    }
    return normalized;
  }

  function runEventTimestampValue(event) {
    var started = Date.parse(event && event.started_at || "");
    if (isFinite(started) && started > 0) {
      return started;
    }
    var finished = Date.parse(event && event.finished_at || "");
    if (isFinite(finished) && finished > 0) {
      return finished;
    }
    var idPrefix = Number(String((event && event.id) || "").split("-")[0]);
    if (isFinite(idPrefix) && idPrefix > 0) {
      return idPrefix;
    }
    return 0;
  }

  function compareRunEventsChronological(a, b) {
    var at = runEventTimestampValue(a);
    var bt = runEventTimestampValue(b);
    if (at !== bt) {
      return at - bt;
    }
    var aStatus = String((a && a.status) || "");
    var bStatus = String((b && b.status) || "");
    if (aStatus === "running" && bStatus !== "running") {
      return 1;
    }
    if (bStatus === "running" && aStatus !== "running") {
      return -1;
    }
    return String((a && a.id) || "").localeCompare(String((b && b.id) || ""));
  }

  function mergeRunEventMissingFields(primaryEvent, fallbackEvent) {
    var primary = sanitizeRunEventForStorage(primaryEvent);
    if (!primary) {
      return sanitizeRunEventForStorage(fallbackEvent);
    }
    var fallback = sanitizeRunEventForStorage(fallbackEvent);
    if (!fallback) {
      return primary;
    }
    var merged = primary;
    var primaryAnchor = Number(merged.message_anchor);
    var fallbackAnchor = Number(fallback.message_anchor);
    if ((!isFinite(primaryAnchor) || primaryAnchor < 0) && isFinite(fallbackAnchor) && fallbackAnchor >= 0) {
      merged.message_anchor = Math.floor(fallbackAnchor);
    }
    if (!merged.started_at && fallback.started_at) {
      merged.started_at = fallback.started_at;
    }
    if (!merged.finished_at && fallback.finished_at) {
      merged.finished_at = fallback.finished_at;
    }
    if (!merged.last_activity_at && fallback.last_activity_at) {
      merged.last_activity_at = fallback.last_activity_at;
    }
    if (!trim(merged.model || "") && trim(fallback.model || "")) {
      merged.model = fallback.model;
    }
    if (!trim(merged.decision_hint || "") && trim(fallback.decision_hint || "")) {
      merged.decision_hint = fallback.decision_hint;
    }
    if (!trim(merged.stream_text || "") && trim(fallback.stream_text || "")) {
      merged.stream_text = fallback.stream_text;
    }
    if (!merged.task_status && fallback.task_status) {
      merged.task_status = fallback.task_status;
    }
    if ((!Array.isArray(merged.commands) || !merged.commands.length) && Array.isArray(fallback.commands) && fallback.commands.length) {
      merged.commands = fallback.commands.slice(0, 12);
    }
    if (!trim(merged.error || "") && trim(fallback.error || "")) {
      merged.error = fallback.error;
    }
    if (!trim(merged.plan || "") && trim(fallback.plan || "")) {
      merged.plan = fallback.plan;
    }
    if (!trim(merged.git_status || "") && trim(fallback.git_status || "")) {
      merged.git_status = fallback.git_status;
    }
    if (!trim(merged.git_diff || "") && trim(fallback.git_diff || "")) {
      merged.git_diff = fallback.git_diff;
    }
    if (!trim(merged.state || "") && trim(fallback.state || "")) {
      merged.state = fallback.state;
    }
    if (!trim(merged.failures || "") && trim(fallback.failures || "")) {
      merged.failures = fallback.failures;
    }
    if (!trim(merged.session_log || "") && trim(fallback.session_log || "")) {
      merged.session_log = fallback.session_log;
    }
    var mergedAwaitingAssistant = Number(merged.awaiting_assistant);
    var fallbackAwaitingAssistant = Number(fallback.awaiting_assistant);
    if ((!isFinite(mergedAwaitingAssistant) || mergedAwaitingAssistant < 1) && isFinite(fallbackAwaitingAssistant) && fallbackAwaitingAssistant > 0) {
      merged.awaiting_assistant = 1;
    }
    return merged;
  }

  function mergeConversationRunEvents(conversationId, remoteEvents) {
    var convId = String(conversationId || "");
    if (!convId) {
      return;
    }
    var remoteList = normalizedRunEventsList(remoteEvents);
    if (!remoteList.length) {
      return;
    }
    var hasRemoteRunning = false;
    for (var r = 0; r < remoteList.length; r += 1) {
      if (String((remoteList[r] && remoteList[r].status) || "") === "running") {
        hasRemoteRunning = true;
        break;
      }
    }
    var localList = normalizedRunEventsList(state.runEventsByConversation[convId]);
    var merged = [];
    var mergedById = {};

    function pushEvent(event, allowNew) {
      var sanitized = sanitizeRunEventForStorage(event);
      if (!sanitized) {
        return;
      }
      var key = String(sanitized.id || "");
      if (key && Object.prototype.hasOwnProperty.call(mergedById, key)) {
        var existingIndex = mergedById[key];
        merged[existingIndex] = mergeRunEventMissingFields(merged[existingIndex], sanitized);
        return;
      }
      if (allowNew === false) {
        return;
      }
      merged.push(sanitized);
      if (key) {
        mergedById[key] = merged.length - 1;
      }
    }

    for (var i = 0; i < remoteList.length; i += 1) {
      pushEvent(remoteList[i], true);
    }
    for (var j = 0; j < localList.length; j += 1) {
      var localEvent = localList[j] || {};
      var localStatus = String(localEvent.status || "");
      var shouldAddLocal = localStatus === "approval_granted" || (localStatus === "running" && !hasRemoteRunning);
      pushEvent(localEvent, shouldAddLocal);
    }

    merged.sort(compareRunEventsChronological);

    if (merged.length > 22) {
      merged = merged.slice(merged.length - 22);
    }
    state.runEventsByConversation[convId] = merged;
    persistRunEventsSoon();
  }

  function runEventsForConversation(conversationId) {
    if (!conversationId) {
      return [];
    }
    return state.runEventsByConversation[conversationId] || [];
  }

  function outgoingKeyFor(workspaceId, conversationId, draftWorkspaceId) {
    var wsId = String(workspaceId || "");
    var convId = String(conversationId || "");
    var draftId = String(draftWorkspaceId || "");
    if (wsId && convId) {
      return "c:" + wsId + "::" + convId;
    }
    if (draftId) {
      return "d:" + draftId;
    }
    return "";
  }

  function activeOutgoingKey() {
    var draftWorkspaceId = state.activeDraftWorkspaceId;
    if (!draftWorkspaceId && state.activeWorkspaceId && !state.activeConversationId) {
      draftWorkspaceId = state.activeWorkspaceId;
    }
    return outgoingKeyFor(state.activeWorkspaceId, state.activeConversationId, draftWorkspaceId);
  }

  function parseOutgoingKey(key) {
    var safeKey = String(key || "");
    if (!safeKey) {
      return null;
    }
    if (safeKey.indexOf("d:") === 0) {
      var draftWorkspaceId = String(safeKey.slice(2) || "");
      if (!draftWorkspaceId) {
        return null;
      }
      return {
        draftWorkspaceId: draftWorkspaceId
      };
    }
    if (safeKey.indexOf("c:") === 0) {
      var payload = String(safeKey.slice(2) || "");
      var splitAt = payload.indexOf("::");
      if (splitAt <= 0) {
        return null;
      }
      var workspaceId = String(payload.slice(0, splitAt) || "");
      var conversationId = String(payload.slice(splitAt + 2) || "");
      if (!workspaceId || !conversationId) {
        return null;
      }
      return {
        workspaceId: workspaceId,
        conversationId: conversationId
      };
    }
    return null;
  }

  function buildComposerTargetContextFromState() {
    var workspaceId = String(state.activeWorkspaceId || "");
    var conversationId = String(state.activeConversationId || "");
    var draftWorkspaceId = String(state.activeDraftWorkspaceId || "");
    if (!workspaceId && draftWorkspaceId) {
      workspaceId = draftWorkspaceId;
    }
    if (!workspaceId) {
      return null;
    }
    if (!conversationId && !draftWorkspaceId) {
      draftWorkspaceId = workspaceId;
    }
    var outgoingKey = outgoingKeyFor(workspaceId, conversationId, draftWorkspaceId);
    if (!outgoingKey && workspaceId) {
      outgoingKey = outgoingKeyFor(workspaceId, "", workspaceId);
      draftWorkspaceId = workspaceId;
    }
    if (!outgoingKey) {
      return null;
    }
    return {
      captureId: "dictation-target-" + String(Date.now()) + "-" + String(Math.floor(Math.random() * 1000000)),
      workspaceId: workspaceId,
      conversationId: conversationId,
      draftWorkspaceId: draftWorkspaceId,
      outgoingKey: outgoingKey,
      promptSnapshot: String((el.runPrompt && el.runPrompt.value) || ""),
      sessionId: "",
      createdAt: Date.now()
    };
  }

  function registerDictationCaptureForSession(sessionId, context) {
    var id = trim(String(sessionId || ""));
    var capture = context && typeof context === "object" ? context : null;
    if (!id || !capture) {
      return;
    }
    capture.sessionId = id;
    state.dictateCaptureBySessionId[id] = capture;
  }

  function dictationCaptureContextForSession(sessionId) {
    var id = trim(String(sessionId || ""));
    if (!id) {
      return state.dictateCaptureContext && typeof state.dictateCaptureContext === "object"
        ? state.dictateCaptureContext
        : null;
    }
    if (state.dictateCaptureBySessionId[id] && typeof state.dictateCaptureBySessionId[id] === "object") {
      return state.dictateCaptureBySessionId[id];
    }
    if (
      state.dictateCaptureContext &&
      typeof state.dictateCaptureContext === "object" &&
      String(state.dictateCaptureContext.sessionId || "") === id
    ) {
      return state.dictateCaptureContext;
    }
    return null;
  }

  function clearDictationCaptureContextForSession(sessionId) {
    var id = trim(String(sessionId || ""));
    if (id) {
      delete state.dictateCaptureBySessionId[id];
    }
    if (
      state.dictateCaptureContext &&
      typeof state.dictateCaptureContext === "object" &&
      (!id || String(state.dictateCaptureContext.sessionId || "") === id)
    ) {
      state.dictateCaptureContext = null;
    }
  }

  function setComposerDraftForKey(key, text) {
    var safeKey = String(key || "");
    if (!safeKey) {
      return;
    }
    var value = String(text || "");
    if (!value) {
      delete state.composerDraftByKey[safeKey];
      return;
    }
    state.composerDraftByKey[safeKey] = value;
  }

  function hasComposerDraftForKey(key) {
    var safeKey = String(key || "");
    return !!safeKey && Object.prototype.hasOwnProperty.call(state.composerDraftByKey, safeKey);
  }

  function getComposerDraftForTarget(workspaceId, conversationId, draftWorkspaceId) {
    var key = outgoingKeyFor(workspaceId, conversationId, draftWorkspaceId);
    if (!hasComposerDraftForKey(key)) {
      return "";
    }
    return String(state.composerDraftByKey[key] || "");
  }

  function rememberActiveComposerDraft() {
    if (!el.runPrompt) {
      return;
    }
    var key = activeOutgoingKey();
    if (!key) {
      return;
    }
    setComposerDraftForKey(key, el.runPrompt.value || "");
  }

  function pendingOutgoingList(key) {
    var safeKey = String(key || "");
    if (!safeKey) {
      return [];
    }
    var list = state.pendingOutgoingByKey[safeKey];
    return Array.isArray(list) ? list : [];
  }

  function hasAnyPendingOutgoing() {
    var keys = Object.keys(state.pendingOutgoingByKey || {});
    for (var i = 0; i < keys.length; i += 1) {
      var list = pendingOutgoingList(keys[i]);
      if (list.length > 0) {
        return true;
      }
    }
    return false;
  }

  function queueStatusAllowsPendingClear(lastStatus) {
    var status = String(lastStatus || "");
    return (
      status === "done" ||
      status === "error" ||
      status === "cancelled" ||
      status === "awaiting_decision" ||
      status === "awaiting_approval"
    );
  }

  function clearPendingOutgoingForConversation(workspaceId, conversationId, options) {
    var wsId = String(workspaceId || "");
    var convId = String(conversationId || "");
    if (!wsId || !convId) {
      return false;
    }
    var key = outgoingKeyFor(wsId, convId, "");
    if (!key || !pendingOutgoingList(key).length) {
      return false;
    }
    delete state.pendingOutgoingByKey[key];
    var opts = options && typeof options === "object" ? options : {};
    if (opts.persist !== false) {
      persistPendingOutgoingSoon();
    }
    return true;
  }

  function reconcilePendingOutgoingFromWorkspaceSummaries() {
    var changed = false;
    var keys = Object.keys(state.pendingOutgoingByKey || {});
    for (var i = 0; i < keys.length; i += 1) {
      var parsed = parseOutgoingKey(keys[i]);
      if (!parsed || !parsed.workspaceId || !parsed.conversationId) {
        continue;
      }
      var workspace = getWorkspaceById(parsed.workspaceId);
      var conversation = getConversationById(workspace, parsed.conversationId);
      if (!conversation) {
        continue;
      }
      var pending = queueNumber(conversation.queue_pending);
      var running = String(conversation.queue_running || "0") === "1";
      var lastStatus = String(conversation.queue_last_status || "");
      if (!running && pending === 0 && queueStatusAllowsPendingClear(lastStatus)) {
        if (clearPendingOutgoingForConversation(parsed.workspaceId, parsed.conversationId, { persist: false })) {
          changed = true;
        }
      }
    }
    if (changed) {
      persistPendingOutgoingSoon();
    }
  }

  function reconcilePendingOutgoingFromStateResponse(stateResponse) {
    if (!stateResponse || !stateResponse.success) {
      return false;
    }
    var changed = false;
    var keys = Object.keys(state.pendingOutgoingByKey || {});
    for (var i = 0; i < keys.length; i += 1) {
      var parsed = parseOutgoingKey(keys[i]);
      if (!parsed || !parsed.workspaceId || !parsed.conversationId) {
        continue;
      }
      var entry = findConversationStateEntry(stateResponse, parsed.workspaceId, parsed.conversationId);
      if (!entry) {
        continue;
      }
      var pending = queueNumber(entry.queue_pending);
      var running = String(entry.queue_running || "0") === "1";
      var lastStatus = String(entry.queue_last_status || "");
      if (!running && pending === 0 && queueStatusAllowsPendingClear(lastStatus)) {
        if (clearPendingOutgoingForConversation(parsed.workspaceId, parsed.conversationId, { persist: false })) {
          changed = true;
        }
      }
    }
    if (changed) {
      persistPendingOutgoingSoon();
    }
    return changed;
  }

  function pendingOutgoingEntriesOldEnoughForOrphanClear(key) {
    var safeKey = String(key || "");
    if (!safeKey) {
      return false;
    }
    var list = pendingOutgoingList(safeKey);
    if (!list.length) {
      return false;
    }
    var now = Date.now();
    for (var i = 0; i < list.length; i += 1) {
      var entry = list[i] || {};
      var createdAt = Number(entry.createdAt || 0);
      if (!isFinite(createdAt) || createdAt <= 0) {
        return false;
      }
      if (now - createdAt < PENDING_OUTGOING_ORPHAN_CLEAR_MS) {
        return false;
      }
    }
    return true;
  }

  function shouldClearOrphanedPendingOutgoingTarget(target, stateResponse) {
    if (!target || !stateResponse || !stateResponse.success) {
      return false;
    }
    if (findConversationStateEntry(stateResponse, target.workspaceId, target.conversationId)) {
      return false;
    }
    return pendingOutgoingEntriesOldEnoughForOrphanClear(target.key);
  }

  function pendingOutgoingConversationTargets(limit) {
    var maxCount = Number(limit || 0);
    if (!isFinite(maxCount) || maxCount < 1) {
      maxCount = 4;
    }
    var keys = Object.keys(state.pendingOutgoingByKey || {});
    var targets = [];
    for (var i = 0; i < keys.length; i += 1) {
      var key = String(keys[i] || "");
      if (!key) {
        continue;
      }
      var parsed = parseOutgoingKey(key);
      if (!parsed || !parsed.workspaceId || !parsed.conversationId) {
        continue;
      }
      targets.push({
        key: key,
        workspaceId: parsed.workspaceId,
        conversationId: parsed.conversationId
      });
      if (targets.length >= maxCount) {
        break;
      }
    }
    return targets;
  }

  function reconcilePendingOutgoingViaQueueProbe(stateResponse) {
    var targets = pendingOutgoingConversationTargets(6);
    if (!targets.length) {
      return Promise.resolve(false);
    }
    var changed = false;

    function maybeClearTarget(target, response) {
      if (!target) {
        return;
      }
      if (response && response.success) {
        var pendingCount = queueNumber(response.queue_pending);
        var running = Number(response.queue_running || 0) > 0;
        var lastStatus = String(response.queue_last_status || "");
        var queueSettledWithoutStatus = !running && pendingCount === 0 && !trim(lastStatus);
        if (!running && pendingCount === 0 && (queueStatusAllowsPendingClear(lastStatus) || queueSettledWithoutStatus)) {
          if (clearPendingOutgoingForConversation(target.workspaceId, target.conversationId, { persist: false })) {
            changed = true;
          }
        }
        return;
      }
      if (shouldClearOrphanedPendingOutgoingTarget(target, stateResponse)) {
        if (clearPendingOutgoingForConversation(target.workspaceId, target.conversationId, { persist: false })) {
          changed = true;
        }
      }
    }

    function step(index) {
      if (index >= targets.length) {
        return Promise.resolve();
      }
      var target = targets[index];
      return apiGet("queue_list", {
        workspace_id: target.workspaceId,
        conversation_id: target.conversationId,
        limit: "1"
      }, { timeoutMs: 6000 })
        .then(function (response) {
          maybeClearTarget(target, response);
          return null;
        })
        .catch(function () {
          maybeClearTarget(target, null);
          return null;
        })
        .then(function () {
          return step(index + 1);
        });
    }

    return step(0).then(function () {
      if (changed) {
        persistPendingOutgoingSoon();
      }
      return changed;
    });
  }

  function addPendingOutgoing(key, text) {
    var safeKey = String(key || "");
    var content = trim(text || "");
    if (!safeKey || !content) {
      return "";
    }
    if (!Array.isArray(state.pendingOutgoingByKey[safeKey])) {
      state.pendingOutgoingByKey[safeKey] = [];
    }
    var id = "pending-" + String(Date.now()) + "-" + String(Math.floor(Math.random() * 1000000));
    state.pendingOutgoingByKey[safeKey].push({
      id: id,
      content: content,
      createdAt: Date.now()
    });
    // Flush immediately so reload/crash right after submit does not drop queued user text.
    persistPendingOutgoingNow();
    return id;
  }

  function removePendingOutgoing(key, pendingId) {
    var safeKey = String(key || "");
    var id = String(pendingId || "");
    if (!safeKey || !id) {
      return;
    }
    var list = pendingOutgoingList(safeKey);
    if (!list.length) {
      return;
    }
    var kept = [];
    for (var i = 0; i < list.length; i += 1) {
      if (String(list[i].id || "") !== id) {
        kept.push(list[i]);
      }
    }
    if (kept.length) {
      state.pendingOutgoingByKey[safeKey] = kept;
    } else {
      delete state.pendingOutgoingByKey[safeKey];
    }
    persistPendingOutgoingSoon();
  }

  function movePendingOutgoing(oldKey, newKey, pendingId) {
    var fromKey = String(oldKey || "");
    var toKey = String(newKey || "");
    var id = String(pendingId || "");
    if (!fromKey || !toKey || !id || fromKey === toKey) {
      return;
    }
    var fromList = pendingOutgoingList(fromKey);
    if (!fromList.length) {
      return;
    }
    var entry = null;
    var kept = [];
    for (var i = 0; i < fromList.length; i += 1) {
      var item = fromList[i];
      if (!entry && String(item.id || "") === id) {
        entry = item;
      } else {
        kept.push(item);
      }
    }
    if (!entry) {
      return;
    }
    if (kept.length) {
      state.pendingOutgoingByKey[fromKey] = kept;
    } else {
      delete state.pendingOutgoingByKey[fromKey];
    }
    if (!Array.isArray(state.pendingOutgoingByKey[toKey])) {
      state.pendingOutgoingByKey[toKey] = [];
    }
    state.pendingOutgoingByKey[toKey].push(entry);
    persistPendingOutgoingNow();
  }

  function consumePendingOutgoingByText(key, text) {
    var safeKey = String(key || "");
    var content = trim(text || "");
    if (!safeKey || !content) {
      return false;
    }
    var list = pendingOutgoingList(safeKey);
    if (!list.length) {
      return false;
    }
    var kept = [];
    var removed = false;
    for (var i = 0; i < list.length; i += 1) {
      var item = list[i];
      if (!removed && trim(item.content || "") === content) {
        removed = true;
      } else {
        kept.push(item);
      }
    }
    if (!removed) {
      return false;
    }
    if (kept.length) {
      state.pendingOutgoingByKey[safeKey] = kept;
    } else {
      delete state.pendingOutgoingByKey[safeKey];
    }
    persistPendingOutgoingSoon();
    return true;
  }

  function appendAssistantMessageOptimistic(workspaceId, conversationId, assistantText) {
    var wsId = String(workspaceId || "");
    var convId = String(conversationId || "");
    var content = trim(assistantText || "");
    if (!wsId || !convId || !content) {
      return false;
    }
    if (
      !state.activeConversation ||
      String(state.activeWorkspaceId || "") !== wsId ||
      String(state.activeConversationId || "") !== convId
    ) {
      return false;
    }
    if (!Array.isArray(state.activeConversation.messages)) {
      state.activeConversation.messages = [];
    }
    var messages = state.activeConversation.messages;
    var last = messages.length ? messages[messages.length - 1] : null;
    if (last && String(last.role || "") === "assistant" && String(last.content || "") === content) {
      return false;
    }
    messages.push({ role: "assistant", content: content });
    cacheActiveConversationSnapshot(wsId, convId);
    return true;
  }

  function reconcilePendingOutgoingFromConversation(workspaceId, conversationId, conversation) {
    var key = outgoingKeyFor(workspaceId, conversationId, "");
    var pendingList = pendingOutgoingList(key);
    if (!pendingList.length) {
      return;
    }
    var messages = Array.isArray(conversation && conversation.messages) ? conversation.messages : [];
    var userCounts = {};
    for (var i = 0; i < messages.length; i += 1) {
      var msg = messages[i] || {};
      if (String(msg.role || "") !== "user") {
        continue;
      }
      var content = trim(msg.content || "");
      if (!content) {
        continue;
      }
      userCounts[content] = (userCounts[content] || 0) + 1;
    }
    var kept = [];
    for (var j = 0; j < pendingList.length; j += 1) {
      var pending = pendingList[j] || {};
      var pendingText = trim(pending.content || "");
      if (pendingText && userCounts[pendingText] > 0) {
        userCounts[pendingText] -= 1;
      } else {
        kept.push(pending);
      }
    }
    if (kept.length) {
      state.pendingOutgoingByKey[key] = kept;
    } else {
      delete state.pendingOutgoingByKey[key];
    }
    persistPendingOutgoingSoon();
  }

  function applyRunEventTerminalState(event, status, errorText, finishedAt) {
    if (!event) {
      return;
    }
    if (status === "error") {
      event.status = "error";
      if (!trim(errorText || "")) {
        event.error = trim(event.error || "Run did not complete.");
      } else {
        event.error = trim(errorText);
      }
    } else if (status === "cancelled") {
      event.status = "cancelled";
    } else if (status === "awaiting_approval") {
      event.status = "awaiting_approval";
    } else if (status === "awaiting_decision") {
      event.status = "awaiting_decision";
    } else {
      event.status = "done";
    }
    event.finished_at = finishedAt || new Date().toISOString();
    if (event.id) {
      delete state.runDetailsOpenByEventId[String(event.id)];
      delete state.runDigestOpenByEventId[String(event.id)];
    }
    persistRunEventsSoon();
  }

  function finalizeLatestRunningEvent(conversationId, status, errorText) {
    var convId = String(conversationId || "");
    if (!convId) {
      return;
    }
    var events = state.runEventsByConversation[convId];
    if (!Array.isArray(events) || !events.length) {
      return;
    }
    var finishedAt = new Date().toISOString();
    for (var i = events.length - 1; i >= 0; i -= 1) {
      if (String(events[i].status || "") === "running") {
        applyRunEventTerminalState(events[i], status, errorText, finishedAt);
        return;
      }
    }
  }

  function finalizeAllRunningEvents(conversationId, status, errorText) {
    var convId = String(conversationId || "");
    if (!convId) {
      return;
    }
    var events = state.runEventsByConversation[convId];
    if (!Array.isArray(events) || !events.length) {
      return;
    }
    var finishedAt = new Date().toISOString();
    for (var i = events.length - 1; i >= 0; i -= 1) {
      if (String(events[i].status || "") !== "running") {
        continue;
      }
      applyRunEventTerminalState(events[i], status, errorText, finishedAt);
    }
  }

  function finalizeStaleRunningEventsForConversation(workspaceId, conversation) {
    if (!workspaceId || !conversation || !conversation.id) {
      return;
    }
    var pending = queueNumber(conversation.queue_pending);
    var running = String(conversation.queue_running || "0") === "1";
    if (running || pending > 0) {
      return;
    }
    var queueStatus = String(conversation.queue_last_status || "");
    if (!queueStatus) {
      if (conversationApprovalRequest(conversation) || isAwaitingApprovalConversation(workspaceId, conversation.id)) {
        queueStatus = "awaiting_approval";
      }
    }
    var eventStatus = "done";
    if (queueStatus === "error") {
      eventStatus = "error";
    } else if (queueStatus === "cancelled") {
      eventStatus = "cancelled";
    } else if (queueStatus === "awaiting_approval") {
      eventStatus = "awaiting_approval";
    } else if (queueStatus === "awaiting_decision") {
      eventStatus = "awaiting_decision";
    }
    finalizeAllRunningEvents(
      String(conversation.id || ""),
      eventStatus,
      eventStatus === "error" ? "Run did not complete." : ""
    );
  }

  function reconcileRunEventsFromQueueState() {
    for (var i = 0; i < state.workspaces.length; i += 1) {
      var workspace = state.workspaces[i];
      if (!workspace || !Array.isArray(workspace.conversations)) {
        continue;
      }
      for (var j = 0; j < workspace.conversations.length; j += 1) {
        finalizeStaleRunningEventsForConversation(workspace.id, workspace.conversations[j]);
      }
    }
  }

  function hasAnyRunningRunEvent() {
    var keys = Object.keys(state.runEventsByConversation || {});
    for (var i = 0; i < keys.length; i += 1) {
      var events = state.runEventsByConversation[keys[i]];
      if (!Array.isArray(events) || !events.length) {
        continue;
      }
      for (var j = events.length - 1; j >= 0; j -= 1) {
        if (String(events[j].status || "") === "running") {
          return true;
        }
      }
    }
    return false;
  }

  function hasAnyQueuedOrRunningConversation() {
    for (var i = 0; i < state.workspaces.length; i += 1) {
      var workspace = state.workspaces[i];
      var conversations = workspace && Array.isArray(workspace.conversations) ? workspace.conversations : [];
      for (var j = 0; j < conversations.length; j += 1) {
        var conversation = conversations[j] || {};
        if (String(conversation.queue_running || "0") === "1") {
          return true;
        }
        if (queueNumber(conversation.queue_pending) > 0) {
          return true;
        }
      }
    }
    return false;
  }

  function hasAnyQueuedOrRunningConversationInStateResponse(stateResponse) {
    if (!stateResponse || !stateResponse.success || !Array.isArray(stateResponse.workspaces)) {
      return false;
    }
    for (var i = 0; i < stateResponse.workspaces.length; i += 1) {
      var workspace = stateResponse.workspaces[i];
      var conversations = workspace && Array.isArray(workspace.conversations) ? workspace.conversations : [];
      for (var j = 0; j < conversations.length; j += 1) {
        var conversation = conversations[j] || {};
        if (String(conversation.queue_running || "0") === "1") {
          return true;
        }
        if (queueNumber(conversation.queue_pending) > 0) {
          return true;
        }
      }
    }
    return false;
  }

  function syncConversationQueueFromStateEntry(workspaceId, conversationId, conversationEntry) {
    var wsId = String(workspaceId || "");
    var convId = String(conversationId || "");
    var entry = conversationEntry || null;
    if (!wsId || !convId || !entry) {
      return;
    }

    var pending = queueNumber(entry.queue_pending);
    var running = String(entry.queue_running || "0") === "1";
    var lastStatus = String(entry.queue_last_status || "");
    setConversationQueueFields(wsId, convId, {
      pending: pending,
      running: running,
      done: lastStatus === "done",
      lastStatus: lastStatus,
      firstId: String(entry.queue_first_id || ""),
      decisionRequest: typeof entry.decision_request === "undefined" ? undefined : entry.decision_request,
      approvalRequest: typeof entry.approval_request === "undefined" ? undefined : entry.approval_request
    });
    updateAwaitingApprovalFromQueueSnapshot(wsId, convId, {
      lastStatus: lastStatus,
      approvalRequest: entry.approval_request,
      pending: pending,
      running: running
    });
    if (!running && pending === 0 && queueStatusAllowsPendingClear(lastStatus)) {
      clearPendingOutgoingForConversation(wsId, convId);
    }
    finalizeStaleRunningEventsForConversation(wsId, entry);
  }

  function normalizedTerminalRunStatus(queueLastStatus) {
    var status = String(queueLastStatus || "");
    if (
      status !== "done" &&
      status !== "error" &&
      status !== "cancelled" &&
      status !== "awaiting_decision" &&
      status !== "awaiting_approval"
    ) {
      status = "done";
    }
    return status;
  }

  function healRunningEventsForConversationFromSummary(workspaceId, conversationId) {
    var wsId = String(workspaceId || "");
    var convId = String(conversationId || "");
    if (!wsId || !convId) {
      return;
    }
    var workspace = getWorkspaceById(wsId);
    var conversation = getConversationById(workspace, convId);
    if (!conversation) {
      return;
    }

    finalizeStaleRunningEventsForConversation(wsId, conversation);

    var pending = queueNumber(conversation.queue_pending);
    var running = String(conversation.queue_running || "0") === "1";
    if (running || pending > 0) {
      return;
    }

    var events = runEventsForConversation(convId);
    var hasRunning = false;
    for (var i = events.length - 1; i >= 0; i -= 1) {
      if (String(events[i].status || "") === "running") {
        hasRunning = true;
        break;
      }
    }
    if (!hasRunning) {
      return;
    }

    var terminalStatus = normalizedTerminalRunStatus(conversation.queue_last_status);
    finalizeLatestRunningEvent(convId, terminalStatus, "");
    if (terminalStatus !== "awaiting_approval") {
      setAwaitingApprovalState(wsId, convId, false);
    }
    if (
      state.busy &&
      String(state.runningWorkspaceId || "") === wsId &&
      String(state.runningConversationId || "") === convId
    ) {
      setBusy(false);
    }
  }

  function reconcileRunningState() {
    var shouldReconcile = state.busy || hasAnyRunningRunEvent();
    if (!shouldReconcile || runReconcileBusy) {
      return;
    }
    var workspaceId = String(state.runningWorkspaceId || "");
    var conversationId = String(state.runningConversationId || "");
    runReconcileBusy = true;
    loadState({ timeoutMs: 6000, fast: true })
      .then(function () {
        reconcileRunEventsFromQueueState();
        var hasQueuedOrRunning = hasAnyQueuedOrRunningConversation();
        if (state.busy && !hasQueuedOrRunning) {
          setBusy(false);
        }
        if (!state.busy && hasQueuedOrRunning) {
          state.queueWorkerActive = false;
          kickQueueWorker();
        }

        if (!workspaceId || !conversationId) {
          if (state.activeWorkspaceId && state.activeConversationId) {
            loadConversation({ timeoutMs: 6000 }).catch(function () {
              return null;
            });
          }
          return null;
        }

        var gitRefresh = Promise.resolve();
        if (state.activeWorkspaceId === workspaceId) {
          gitRefresh = refreshGitStatus().catch(function () {
            return null;
          });
        }
        return gitRefresh.then(function () {
          var ws = getWorkspaceById(workspaceId);
          var conv = getConversationById(ws, conversationId);
          var stillRunning = !!(conv && String(conv.queue_running || "0") === "1");
          var pending = conv ? queueNumber(conv.queue_pending) : 0;
          if (stillRunning || pending > 0) {
            return;
          }
          setBusy(false);
          finalizeLatestRunningEvent(conversationId, "done", "");
          if (state.activeWorkspaceId === workspaceId && state.activeConversationId === conversationId) {
            loadConversation({ timeoutMs: 6000 }).catch(function () {
              return null;
            });
          }
          return null;
        });
      })
      .catch(function () {
        return null;
      })
      .finally(function () {
        runReconcileBusy = false;
        renderUi();
      });
  }

  function startRunEventHealLoop() {
    if (runEventHealTimer) {
      clearInterval(runEventHealTimer);
      runEventHealTimer = null;
    }
    runEventHealTimer = setInterval(function () {
      if (runEventHealBusy) {
        if (runEventHealBusySince > 0 && Date.now() - runEventHealBusySince > 12000) {
          runEventHealBusy = false;
          runEventHealBusySince = 0;
          renderUi();
        }
        return;
      }
      var activeConversationNeedsLifecycleSync = false;
      if (state.activeWorkspaceId && state.activeConversationId) {
        var activeWorkspace = getWorkspaceById(state.activeWorkspaceId);
        var activeSummary = getConversationById(activeWorkspace, state.activeConversationId);
        var queueStatus = String(activeSummary && activeSummary.queue_last_status || "");
        var hasDecisionRequest = !!conversationDecisionRequest(state.activeConversation) || !!conversationDecisionRequest(activeSummary);
        var hasApprovalRequest = !!conversationApprovalRequest(state.activeConversation) || !!conversationApprovalRequest(activeSummary);
        if (
          queueStatus === "awaiting_decision" ||
          queueStatus === "awaiting_approval" ||
          hasDecisionRequest ||
          hasApprovalRequest
        ) {
          activeConversationNeedsLifecycleSync = true;
        }
      }
      var domShowsRunning = !!(el.chatLog && el.chatLog.querySelector(".run-line.running"));
      if (!state.busy && !hasAnyRunningRunEvent() && !domShowsRunning && !activeConversationNeedsLifecycleSync) {
        return;
      }
      runEventHealBusy = true;
      runEventHealBusySince = Date.now();
      if (runEventHealGuardTimer) {
        clearTimeout(runEventHealGuardTimer);
        runEventHealGuardTimer = null;
      }
      runEventHealGuardTimer = setTimeout(function () {
        if (!runEventHealBusy) {
          runEventHealGuardTimer = null;
          return;
        }
        runEventHealBusy = false;
        runEventHealBusySince = 0;
        runEventHealGuardTimer = null;
        renderUi();
      }, 12500);
      var watchedWorkspaceId = String(state.runningWorkspaceId || state.activeWorkspaceId || "");
      var watchedConversationId = String(state.runningConversationId || state.activeConversationId || "");
      loadState({ timeoutMs: 6000, fast: true, fresh: activeConversationNeedsLifecycleSync })
        .then(function () {
          reconcileRunEventsFromQueueState();

          var hasQueuedOrRunning = hasAnyQueuedOrRunningConversation();
          if (state.busy && !hasQueuedOrRunning) {
            setBusy(false);
          }
          if (!state.busy && findNextQueuedConversation()) {
            state.queueWorkerActive = false;
            kickQueueWorker();
          }

          if (state.activeWorkspaceId && state.activeConversationId) {
            loadConversation({ timeoutMs: 6000 }).catch(function () {
              return null;
            });
          }
          return null;
        })
        .catch(function () {
          return apiGet("state", {}, { timeoutMs: 15000 })
            .then(function (response) {
              if (!response || !response.success) {
                return null;
              }
              var hasQueuedOrRunning = hasAnyQueuedOrRunningConversationInStateResponse(response);
              var entry = findConversationStateEntry(response, watchedWorkspaceId, watchedConversationId);
              if (entry && watchedWorkspaceId && watchedConversationId) {
                syncConversationQueueFromStateEntry(watchedWorkspaceId, watchedConversationId, entry);
              } else if (!hasQueuedOrRunning && watchedConversationId) {
                finalizeLatestRunningEvent(watchedConversationId, "done", "");
              }

              if (state.busy && !hasQueuedOrRunning) {
                setBusy(false);
              }

              if (
                !state.busy &&
                entry &&
                queueNumber(entry.queue_pending) > 0 &&
                String(entry.queue_running || "0") !== "1"
              ) {
                state.queueWorkerActive = false;
                kickQueueWorker();
              }

              if (state.activeWorkspaceId && state.activeConversationId) {
                loadConversation({ timeoutMs: 6000 }).catch(function () {
                  return null;
                });
              }
              return null;
            })
            .catch(function () {
              return null;
            });
        })
        .finally(function () {
          runEventHealBusy = false;
          runEventHealBusySince = 0;
          if (runEventHealGuardTimer) {
            clearTimeout(runEventHealGuardTimer);
            runEventHealGuardTimer = null;
          }
          renderUi();
        });
    }, 1800);
  }

  function stopRunEventHealLoop() {
    if (runEventHealTimer) {
      clearInterval(runEventHealTimer);
      runEventHealTimer = null;
    }
    runEventHealBusy = false;
    runEventHealBusySince = 0;
    if (runEventHealGuardTimer) {
      clearTimeout(runEventHealGuardTimer);
      runEventHealGuardTimer = null;
    }
  }

  function startPendingOutgoingReconcileLoop() {
    if (pendingOutgoingReconcileTimer) {
      clearInterval(pendingOutgoingReconcileTimer);
      pendingOutgoingReconcileTimer = null;
    }
    pendingOutgoingReconcileBlockedCycles = 0;
    pendingOutgoingReconcileTimer = setInterval(function () {
      if (pendingOutgoingReconcileBusy) {
        return;
      }
      pruneExpiredPendingOutgoing();
      if (!hasAnyPendingOutgoing()) {
        pendingOutgoingReconcileBlockedCycles = 0;
        return;
      }
      if (runEventHealBusy || runReconcileBusy || state.activeConversationLoading) {
        pendingOutgoingReconcileBlockedCycles += 1;
        // Avoid starvation: if the UI remains "busy" for several cycles, force one reconcile pass.
        if (pendingOutgoingReconcileBlockedCycles < 3) {
          return;
        }
      }
      pendingOutgoingReconcileBlockedCycles = 0;
      pendingOutgoingReconcileBusy = true;
      var stateSnapshot = null;
      loadState({ timeoutMs: 6000, fast: true, fresh: true })
        .then(function () {
          stateSnapshot = {
            success: true,
            workspaces: Array.isArray(state.workspaces) ? state.workspaces : []
          };
          return null;
        })
        .catch(function () {
          return apiGet("state", {}, { timeoutMs: 6000 })
            .then(function (response) {
              stateSnapshot = response || null;
              reconcilePendingOutgoingFromStateResponse(response);
              return null;
            })
            .catch(function () {
              return null;
            });
        })
        .then(function () {
          return reconcilePendingOutgoingViaQueueProbe(stateSnapshot).catch(function () {
            return null;
          });
        })
        .finally(function () {
          pendingOutgoingReconcileBusy = false;
          renderUi();
        });
    }, 2600);
  }

  function stopPendingOutgoingReconcileLoop() {
    if (pendingOutgoingReconcileTimer) {
      clearInterval(pendingOutgoingReconcileTimer);
      pendingOutgoingReconcileTimer = null;
    }
    pendingOutgoingReconcileBusy = false;
    pendingOutgoingReconcileBlockedCycles = 0;
  }

  function persistRunEventsSoon() {
    if (runEventsSaveTimer) {
      return;
    }
    runEventsSaveTimer = setTimeout(function () {
      runEventsSaveTimer = null;
      saveRunEventsState(state.runEventsByConversation);
    }, 240);
  }

  function persistPendingOutgoingSoon() {
    if (pendingOutgoingSaveTimer) {
      return;
    }
    pendingOutgoingSaveTimer = setTimeout(function () {
      pendingOutgoingSaveTimer = null;
      savePendingOutgoingState(state.pendingOutgoingByKey);
    }, 140);
  }

  function persistPendingOutgoingNow() {
    if (pendingOutgoingSaveTimer) {
      clearTimeout(pendingOutgoingSaveTimer);
      pendingOutgoingSaveTimer = null;
    }
    savePendingOutgoingState(state.pendingOutgoingByKey);
  }

  function pruneExpiredPendingOutgoing() {
    var now = Date.now();
    var changed = false;
    var keys = Object.keys(state.pendingOutgoingByKey || {});
    for (var i = 0; i < keys.length; i += 1) {
      var key = String(keys[i] || "");
      if (!key) {
        continue;
      }
      var list = Array.isArray(state.pendingOutgoingByKey[key]) ? state.pendingOutgoingByKey[key] : [];
      if (!list.length) {
        delete state.pendingOutgoingByKey[key];
        changed = true;
        continue;
      }
      var kept = [];
      for (var j = 0; j < list.length; j += 1) {
        var entry = list[j] || {};
        var createdAt = Number(entry.createdAt || 0);
        if (!isFinite(createdAt) || createdAt <= 0) {
          createdAt = now;
        }
        if (now - createdAt > PENDING_OUTGOING_MAX_AGE_MS) {
          changed = true;
          continue;
        }
        kept.push({
          id: String(entry.id || ("pending-" + String(createdAt) + "-" + String(Math.floor(Math.random() * 1000000)))),
          content: String(entry.content || ""),
          createdAt: createdAt
        });
      }
      if (kept.length) {
        state.pendingOutgoingByKey[key] = kept;
      } else {
        delete state.pendingOutgoingByKey[key];
      }
    }
    if (changed) {
      persistPendingOutgoingNow();
    }
  }

  function pruneRunEventsByKnownConversations() {
    var known = {};
    for (var i = 0; i < state.workspaces.length; i += 1) {
      var workspace = state.workspaces[i];
      var conversations = workspace && Array.isArray(workspace.conversations) ? workspace.conversations : [];
      for (var j = 0; j < conversations.length; j += 1) {
        var conversation = conversations[j] || {};
        if (conversation.id) {
          known[String(conversation.id)] = true;
        }
      }
    }
    var changed = false;
    var keys = Object.keys(state.runEventsByConversation || {});
