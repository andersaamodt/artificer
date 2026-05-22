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
    if (!merged.capability_guidance && fallback.capability_guidance) {
      merged.capability_guidance = fallback.capability_guidance;
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
