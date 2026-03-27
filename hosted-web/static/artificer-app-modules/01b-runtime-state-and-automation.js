    ".js,.jsx,.ts,.tsx,.py,.go,.rs,.java,.kt,.swift,.rb,.php,.c,.h,.cpp,.hpp,.cc,.cxx",
    ".html,.htm,.css,.scss,.less,.sql,.xml,.vue,.svelte,.dockerfile,.makefile,.gradle"
  ].join(",");

  function fileExtension(fileName) {
    var name = String(fileName || "");
    var dot = name.lastIndexOf(".");
    if (dot < 0 || dot >= name.length - 1) {
      return "";
    }
    return name.slice(dot + 1).toLowerCase();
  }

  function attachmentKindForFile(file) {
    var mime = String((file && file.type) || "").toLowerCase();
    var ext = fileExtension(file && file.name);

    if (/^image\/(png|jpeg|jpg|gif|webp|bmp|tiff|x-icon|svg\+xml)$/.test(mime)) {
      return "image";
    }

    if (/^text\//.test(mime)) {
      return "text";
    }

    if (/^application\/(json|xml|yaml|x-yaml|toml|javascript|x-javascript|typescript|x-typescript|x-sh|x-shellscript)$/.test(mime)) {
      return "text";
    }

    if (mime === "application/pdf") {
      return "document";
    }

    if (textAttachmentExtensions[ext]) {
      return "text";
    }

    if (ext === "pdf") {
      return "document";
    }

    return "";
  }

  function formatBytes(bytes) {
    var value = Number(bytes || 0);
    if (!isFinite(value) || value <= 0) {
      return "0 B";
    }
    if (value < 1024) {
      return String(Math.round(value)) + " B";
    }
    var kb = value / 1024;
    if (kb < 1024) {
      return String(Math.round(kb)) + " KB";
    }
    var mb = kb / 1024;
    if (mb < 1024) {
      return mb.toFixed(1) + " MB";
    }
    return (mb / 1024).toFixed(1) + " GB";
  }

  function newClientAttachmentId() {
    return "att-" + Date.now() + "-" + String(Math.floor(Math.random() * 999999));
  }

  function parseJsonResponse(rawText) {
    var raw = String(typeof rawText === "undefined" || rawText === null ? "" : rawText);
    try {
      return JSON.parse(raw);
    } catch (_err) {
      // Some CGI paths can prepend non-JSON noise before the first payload object.
    }
    var start = raw.indexOf("{");
    if (start >= 0) {
      try {
        return JSON.parse(raw.slice(start));
      } catch (_err2) {
        // Fall through to deterministic parse error below.
      }
    }
    throw new Error("Server returned non-JSON response: " + raw.slice(0, 220));
  }

  function normalizeStateRevision(value) {
    var raw = trim(String(value || ""));
    if (!raw || /[^0-9]/.test(raw)) {
      return 0;
    }
    var parsed = Number(raw);
    if (!isFinite(parsed) || parsed <= 0) {
      return 0;
    }
    return Math.floor(parsed);
  }

  function requestJson(url, options) {
    var controller = new AbortController();
    var externalSignal = options && options.signal ? options.signal : null;
    var abortedByCaller = false;
    var onExternalAbort = null;
    var timeoutMs = Number(options && options.timeoutMs ? options.timeoutMs : 30000);
    if (!isFinite(timeoutMs) || timeoutMs <= 0) {
      timeoutMs = 30000;
    }
    return new Promise(function (resolve, reject) {
      var settled = false;
      var timeoutErrorText = "Request timed out after " + Math.round(timeoutMs / 1000) + "s.";
      var timeoutId = setTimeout(function () {
        if (settled) {
          return;
        }
        settled = true;
        if (externalSignal && onExternalAbort) {
          externalSignal.removeEventListener("abort", onExternalAbort);
          onExternalAbort = null;
        }
        try {
          controller.abort();
        } catch (_abortErr) {
          // Ignore abort failures; timeout already finalized.
        }
        reject(new Error(timeoutErrorText));
      }, timeoutMs);

      if (externalSignal) {
        if (externalSignal.aborted) {
          settled = true;
          clearTimeout(timeoutId);
          reject(new Error("Request cancelled."));
          return;
        }
        onExternalAbort = function () {
          if (settled) {
            return;
          }
          settled = true;
          abortedByCaller = true;
          clearTimeout(timeoutId);
          try {
            controller.abort();
          } catch (_abortErr2) {
            // Ignore abort failures; caller cancellation already finalized.
          }
          reject(new Error("Request cancelled."));
        };
        externalSignal.addEventListener("abort", onExternalAbort, { once: true });
      }

      fetch(url, {
        method: options.method,
        headers: options.headers,
        body: options.body,
        cache: options.cacheMode || "default",
        signal: controller.signal
      })
        .then(function (response) {
          return response.text().then(function (raw) {
            if (!response.ok) {
              throw new Error("Request failed (" + response.status + "): " + raw.slice(0, 220));
            }
            return parseJsonResponse(raw);
          });
        })
        .then(function (json) {
          if (settled) {
            return;
          }
          settled = true;
          clearTimeout(timeoutId);
          if (externalSignal && onExternalAbort) {
            externalSignal.removeEventListener("abort", onExternalAbort);
            onExternalAbort = null;
          }
          resolve(json);
        })
        .catch(function (err) {
          if (settled) {
            return;
          }
          settled = true;
          clearTimeout(timeoutId);
          if (externalSignal && onExternalAbort) {
            externalSignal.removeEventListener("abort", onExternalAbort);
            onExternalAbort = null;
          }
          if (err && err.name === "AbortError") {
            if (abortedByCaller) {
              reject(new Error("Request cancelled."));
              return;
            }
            reject(new Error(timeoutErrorText));
            return;
          }
          reject(err);
        });
    });
  }

  function apiGet(action, params, options) {
    var search = new URLSearchParams(params || {});
    var stateRequestKey = "";
    if (action === "state") {
      var requestedLevel = trim(String(search.get("level") || ""));
      if (!requestedLevel) {
        requestedLevel = "light";
        search.set("level", requestedLevel);
      }
      var requestedCached = trim(String(search.get("cached") || ""));
      if (requestedCached !== "0") {
        requestedCached = "1";
      }
      search.set("cached", requestedCached);
      stateRequestKey = "state:" + requestedLevel + ":cached=" + requestedCached;
      if (stateGetInFlight && stateGetInFlightKey === stateRequestKey) {
        return stateGetInFlight;
      }
    }
    search.set("action", action);
    search.set("_ts", String(Date.now()) + "-" + String(Math.floor(Math.random() * 1000000)));
    var timeoutMs = 30000;
    if (options && Number(options.timeoutMs) > 0) {
      timeoutMs = Number(options.timeoutMs);
    }
    var requestPromise = requestJson("/cgi/artificer-api?" + search.toString(), {
      method: "GET",
      headers: { Accept: "application/json" },
      cacheMode: "no-store",
      timeoutMs: timeoutMs
    });
    if (action === "state") {
      stateGetInFlightKey = stateRequestKey;
      stateGetInFlight = requestPromise.finally(function () {
        if (stateGetInFlightKey === stateRequestKey) {
          stateGetInFlight = null;
          stateGetInFlightKey = "";
        }
      });
      return stateGetInFlight;
    }
    return requestPromise;
  }

  function apiPost(action, data, options) {
    var timeoutMs = 30000;
    if (action === "run") {
      var computeBudget = normalizeComputeBudget(data && data.compute_budget ? data.compute_budget : state.computeBudget);
      timeoutMs = computeBudgetRequestTimeoutMs(computeBudget, data || {});
      if (!isFinite(timeoutMs) || timeoutMs < 30000) {
        timeoutMs = 30000;
      }
    } else if (options && Number(options.timeoutMs) > 0) {
      timeoutMs = Number(options.timeoutMs);
    }
    var body = new URLSearchParams(data || {});
    body.set("action", action);
    return requestJson("/cgi/artificer-api", {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded;charset=UTF-8",
        Accept: "application/json"
      },
      body: body.toString(),
      timeoutMs: timeoutMs,
      signal: options && options.signal ? options.signal : null
    });
  }

  function setControlPending(control, isPending, options) {
    var node = control && control.nodeType === 1 ? control : null;
    if (!node || !node.classList) {
      return;
    }

    var pending = !!isPending;
    if (pending && String(node.getAttribute("data-ui-pending") || "") === "1") {
      return;
    }
    if (!pending && String(node.getAttribute("data-ui-pending") || "") !== "1") {
      return;
    }

    if (pending) {
      node.setAttribute("data-ui-pending", "1");
      node.setAttribute("aria-busy", "true");
      node.classList.add("ui-pending");

      var allowSpinner = !(options && options.spinner === false);
      if (allowSpinner && node.tagName === "BUTTON") {
        var width = 0;
        try {
          width = Math.round(node.getBoundingClientRect().width || 0);
        } catch (_err) {
          width = 0;
        }
        if (width >= 56) {
          node.classList.add("ui-pending-spinner");
        }
      }

      if ("disabled" in node) {
        node.setAttribute("data-ui-pending-was-disabled", node.disabled ? "1" : "0");
        node.disabled = true;
      } else {
        node.setAttribute("data-ui-pending-block-pointer", "1");
      }
      return;
    }

    node.removeAttribute("data-ui-pending");
    node.removeAttribute("aria-busy");
    node.classList.remove("ui-pending");
    node.classList.remove("ui-pending-spinner");

    if ("disabled" in node) {
      var wasDisabled = node.getAttribute("data-ui-pending-was-disabled") === "1";
      node.removeAttribute("data-ui-pending-was-disabled");
      if (!wasDisabled) {
        node.disabled = false;
      }
    } else {
      node.removeAttribute("data-ui-pending-block-pointer");
    }
  }

  function runWithControlPending(control, runner, options) {
    var node = control && control.nodeType === 1 ? control : null;
    if (node && String(node.getAttribute("data-ui-pending") || "") === "1") {
      return Promise.resolve(null);
    }
    if (node) {
      setControlPending(node, true, options);
    }
    return Promise.resolve()
      .then(function () {
        if (typeof runner === "function") {
          return runner();
        }
        return null;
      })
      .finally(function () {
        if (node) {
          setControlPending(node, false, options);
        }
      });
  }

  function getWorkspaceById(workspaceId) {
    for (var i = 0; i < state.workspaces.length; i += 1) {
      if (state.workspaces[i].id === workspaceId) {
        return state.workspaces[i];
      }
    }
    return null;
  }

  function activeWorkspace() {
    if (!state.activeWorkspaceId) {
      return null;
    }
    return getWorkspaceById(state.activeWorkspaceId);
  }

  function getConversationById(workspace, conversationId) {
    if (!workspace || !workspace.conversations) {
      return null;
    }
    for (var i = 0; i < workspace.conversations.length; i += 1) {
      if (workspace.conversations[i].id === conversationId) {
        return workspace.conversations[i];
      }
    }
    return null;
  }

  function optimisticConversationKey(workspaceId, conversationId) {
    var wsId = String(workspaceId || "");
    var convId = String(conversationId || "");
    if (!wsId || !convId) {
      return "";
    }
    return wsId + "::" + convId;
  }

  function normalizeOptimisticConversationSummary(conversation, fallbackConversationId) {
    var conv = conversation && typeof conversation === "object" ? conversation : {};
    var convId = trim(String(conv.id || fallbackConversationId || ""));
    if (!convId) {
      return null;
    }
    var nowSec = String(Math.floor(Date.now() / 1000));
    return {
      id: convId,
      title: String(conv.title || "New Conversation"),
      model: String(conv.model || ""),
      created: String(conv.created || nowSec),
      updated: String(conv.updated || nowSec),
      queue_pending: String(conv.queue_pending || "0"),
      queue_running: String(conv.queue_running || "0"),
      queue_done: String(conv.queue_done || "0"),
      queue_last_status: String(conv.queue_last_status || ""),
      queue_first_id: String(conv.queue_first_id || ""),
      decision_request: normalizeDecisionRequest(conv.decision_request),
      approval_request: normalizeApprovalRequest(conv.approval_request)
    };
  }

  function registerOptimisticConversation(workspaceId, conversation) {
    var wsId = String(workspaceId || "");
    var conv = normalizeOptimisticConversationSummary(conversation, "");
    var convId = trim(String(conv && conv.id || ""));
    if (!wsId || !convId) {
      return;
    }
    var key = optimisticConversationKey(wsId, convId);
    if (!key) {
      return;
    }
    var now = Date.now();
    state.optimisticConversationsByKey[key] = {
      workspaceId: wsId,
      conversation: conv,
      createdAt: now,
      expiresAt: now + OPTIMISTIC_CONVERSATION_TTL_MS,
      seenAt: 0,
      seenGraceUntil: 0
    };
  }

  function clearOptimisticConversation(workspaceId, conversationId) {
    var key = optimisticConversationKey(workspaceId, conversationId);
    if (!key) {
      return;
    }
    delete state.optimisticConversationsByKey[key];
  }

  function markOptimisticConversationSeen(workspaceId, conversation) {
    var wsId = String(workspaceId || "");
    var conv = normalizeOptimisticConversationSummary(conversation, "");
    var convId = String(conv && conv.id || "");
    if (!wsId || !convId) {
      return;
    }
    var key = optimisticConversationKey(wsId, convId);
    if (!key || !state.optimisticConversationsByKey[key]) {
      return;
    }
    var now = Date.now();
    var entry = state.optimisticConversationsByKey[key];
    entry.workspaceId = wsId;
    entry.conversation = conv;
    if (!Number(entry.seenAt || 0)) {
      entry.seenAt = now;
    }
    var seenGraceUntil = Number(entry.seenGraceUntil || 0);
    if (!isFinite(seenGraceUntil) || seenGraceUntil <= 0) {
      seenGraceUntil = now + OPTIMISTIC_CONVERSATION_SEEN_GRACE_MS;
    }
    entry.seenGraceUntil = seenGraceUntil;
  }

  function mergeOptimisticConversationsIntoWorkspaces(workspaces) {
    var list = Array.isArray(workspaces) ? workspaces : [];
    var now = Date.now();
    var keys = Object.keys(state.optimisticConversationsByKey || {});
    for (var i = 0; i < keys.length; i += 1) {
      var key = keys[i];
      var entry = state.optimisticConversationsByKey[key] || null;
      if (!entry || !entry.workspaceId || !entry.conversation) {
        delete state.optimisticConversationsByKey[key];
        continue;
      }
      var optimisticConversationId = String(entry.conversation.id || "");
      var optimisticOutgoingKey = outgoingKeyFor(entry.workspaceId, optimisticConversationId, "");
      var hasPendingOutgoing = pendingOutgoingList(optimisticOutgoingKey).length > 0;
      var workspace = null;
      for (var w = 0; w < list.length; w += 1) {
        if (String(list[w] && list[w].id || "") === String(entry.workspaceId || "")) {
          workspace = list[w];
          break;
        }
      }
      if (!workspace || !Array.isArray(workspace.conversations)) {
        continue;
      }
      var existingConversation = getConversationById(workspace, optimisticConversationId);
      if (existingConversation) {
        var seenAt = Number(entry.seenAt || 0);
        if (!isFinite(seenAt) || seenAt <= 0) {
          entry.seenAt = now;
          seenAt = now;
        }
        var seenGraceUntil = Number(entry.seenGraceUntil || 0);
        if (!isFinite(seenGraceUntil) || seenGraceUntil <= 0) {
          seenGraceUntil = now + OPTIMISTIC_CONVERSATION_SEEN_GRACE_MS;
        }
        if (hasPendingOutgoing && seenGraceUntil < now + OPTIMISTIC_CONVERSATION_PENDING_EXTENSION_MS) {
          seenGraceUntil = now + OPTIMISTIC_CONVERSATION_PENDING_EXTENSION_MS;
        }
        entry.seenGraceUntil = seenGraceUntil;
        entry.conversation = normalizeOptimisticConversationSummary(existingConversation, optimisticConversationId) || entry.conversation;
        if (!hasPendingOutgoing && seenGraceUntil < now) {
          delete state.optimisticConversationsByKey[key];
        }
        continue;
      }
      var expiresAt = 0;
      var seen = Number(entry.seenAt || 0);
      if (isFinite(seen) && seen > 0) {
        expiresAt = Number(entry.seenGraceUntil || 0);
        if (!isFinite(expiresAt) || expiresAt <= 0) {
          expiresAt = now + OPTIMISTIC_CONVERSATION_SEEN_GRACE_MS;
        }
      } else {
        expiresAt = Number(entry.expiresAt || 0);
        if (!isFinite(expiresAt) || expiresAt <= 0) {
          expiresAt = now + OPTIMISTIC_CONVERSATION_TTL_MS;
        }
      }
      if (hasPendingOutgoing && expiresAt < now + OPTIMISTIC_CONVERSATION_PENDING_EXTENSION_MS) {
        expiresAt = now + OPTIMISTIC_CONVERSATION_PENDING_EXTENSION_MS;
      }
      if (isFinite(seen) && seen > 0) {
        entry.seenGraceUntil = expiresAt;
      } else {
        entry.expiresAt = expiresAt;
      }
      if (!hasPendingOutgoing && expiresAt < now) {
        delete state.optimisticConversationsByKey[key];
        continue;
      }
      workspace.conversations.unshift(cloneConversationData(entry.conversation));
    }
  }

  function findWorkspaceIdForConversation(conversationId) {
    var targetId = String(conversationId || "");
    if (!targetId) {
      return "";
    }
    for (var i = 0; i < state.workspaces.length; i += 1) {
      var workspace = state.workspaces[i];
      if (!workspace || !Array.isArray(workspace.conversations)) {
        continue;
      }
      for (var j = 0; j < workspace.conversations.length; j += 1) {
        var conversation = workspace.conversations[j];
        if (conversation && String(conversation.id || "") === targetId) {
          return String(workspace.id || "");
        }
      }
    }
    return "";
  }

  function queueNumber(value) {
    var parsed = Number(value || 0);
    if (!isFinite(parsed) || parsed < 0) {
      return 0;
    }
    return Math.floor(parsed);
  }

  function conversationReadKey(workspaceId, conversationId) {
    return String(workspaceId || "") + "::" + String(conversationId || "");
  }

  function setActiveConversationLoading(workspaceId, conversationId, loading) {
    var key = conversationReadKey(workspaceId, conversationId);
    if (!key) {
      state.activeConversationLoading = false;
      state.activeConversationLoadingKey = "";
      return;
    }
    if (loading) {
      state.activeConversationLoading = true;
      state.activeConversationLoadingKey = key;
      return;
    }
    if (state.activeConversationLoadingKey === key) {
      state.activeConversationLoading = false;
      state.activeConversationLoadingKey = "";
    }
  }

  function cloneConversationData(conversation) {
    if (!conversation || typeof conversation !== "object") {
      return null;
    }
    try {
      return JSON.parse(JSON.stringify(conversation));
    } catch (_err) {
      return null;
    }
  }

  function cacheConversationSnapshot(workspaceId, conversationId, conversation) {
    var wsId = String(workspaceId || "");
    var convId = String(conversationId || "");
    if (!wsId || !convId || !conversation || typeof conversation !== "object") {
      return;
    }
    var cloned = cloneConversationData(conversation);
    if (!cloned) {
      return;
    }
    if (!cloned.id) {
      cloned.id = convId;
    }
    state.conversationCacheByKey[conversationReadKey(wsId, convId)] = cloned;
  }

  function cacheActiveConversationSnapshot(workspaceId, conversationId) {
    var wsId = String(workspaceId || "");
    var convId = String(conversationId || "");
    if (!wsId || !convId || !state.activeConversation) {
      return;
    }
    if (
      String(state.activeWorkspaceId || "") !== wsId ||
      String(state.activeConversationId || "") !== convId ||
      String(state.activeConversation.id || "") !== convId
    ) {
      return;
    }
    cacheConversationSnapshot(wsId, convId, state.activeConversation);
  }

  function conversationMessagesSnapshot(workspaceId, conversationId) {
    var wsId = String(workspaceId || "");
    var convId = String(conversationId || "");
    if (!wsId || !convId) {
      return [];
    }
    if (
      state.activeConversation &&
      String(state.activeWorkspaceId || "") === wsId &&
      String(state.activeConversationId || "") === convId &&
      Array.isArray(state.activeConversation.messages)
    ) {
      return state.activeConversation.messages;
    }
    var cacheKey = conversationReadKey(wsId, convId);
    var cached = state.conversationCacheByKey[cacheKey];
    if (cached && Array.isArray(cached.messages)) {
      return cached.messages;
    }
    return [];
  }

  function conversationMessageCount(workspaceId, conversationId) {
    var messages = conversationMessagesSnapshot(workspaceId, conversationId);
    if (!Array.isArray(messages)) {
      return 0;
    }
    return messages.length;
  }

  function runEventPromptHint(event) {
    var sessionLog = String((event && event.session_log) || "");
    if (sessionLog) {
      var sessionMatch = sessionLog.match(/User request:\s*([\s\S]*?)(?:\n\nModel raw output:|$)/i);
      if (sessionMatch && sessionMatch[1]) {
        var sessionPrompt = trim(sessionMatch[1]);
        if (sessionPrompt) {
          return sessionPrompt;
        }
      }
    }
    var planText = String((event && event.plan) || "");
    if (planText) {
      var planMatch = planText.match(/Goal:\s*-\s*([^\n\r]+)/i);
      if (planMatch && planMatch[1]) {
        var planPrompt = trim(planMatch[1]);
        if (planPrompt) {
          return planPrompt;
        }
      }
    }
    return "";
  }

  function messageContentMatchesPrompt(contentText, promptText) {
    var content = trim(String(contentText || ""));
    var prompt = trim(String(promptText || ""));
    if (!content || !prompt) {
      return false;
    }
    if (content === prompt) {
      return true;
    }
    if (content.indexOf(prompt + "\n\nAttached files:") === 0) {
      return true;
    }
    return prompt.length >= 48 && content.indexOf(prompt) >= 0;
  }

  function inferMessageAnchorForPrompt(messages, promptText) {
    var prompt = trim(String(promptText || ""));
    var items = Array.isArray(messages) ? messages : [];
    if (!prompt || !items.length) {
      return -1;
    }
    for (var i = items.length - 1; i >= 0; i -= 1) {
      var msg = items[i] || {};
      if (String(msg.role || "") !== "user") {
        continue;
      }
      if (messageContentMatchesPrompt(msg.content || "", prompt)) {
        return i + 1;
      }
    }
    return -1;
  }

  function backfillRunEventAnchorsFromMessages(conversationId, messages) {
    var convId = String(conversationId || "");
    var items = Array.isArray(messages) ? messages : [];
    if (!convId || !items.length) {
      return;
    }
    var events = state.runEventsByConversation[convId];
    if (!Array.isArray(events) || !events.length) {
      return;
    }
    var changed = false;
    for (var i = 0; i < events.length; i += 1) {
      var event = events[i] || {};
      var promptHint = runEventPromptHint(event);
      if (!promptHint) {
        continue;
      }
      var currentAnchor = Number(event.message_anchor);
      var currentMatches = false;
      if (isFinite(currentAnchor) && currentAnchor >= 1) {
        var currentIndex = Math.floor(currentAnchor) - 1;
        if (currentIndex >= 0 && currentIndex < items.length) {
          var currentMsg = items[currentIndex] || {};
          if (String(currentMsg.role || "") === "user" && messageContentMatchesPrompt(currentMsg.content || "", promptHint)) {
            currentMatches = true;
          }
        }
      }
      if (currentMatches) {
        continue;
      }
      var inferredAnchor = inferMessageAnchorForPrompt(items, promptHint);
      if (inferredAnchor >= 0 && (!isFinite(currentAnchor) || currentAnchor < 0 || Math.floor(currentAnchor) !== inferredAnchor)) {
        event.message_anchor = inferredAnchor;
        changed = true;
      }
    }
    if (changed) {
      persistRunEventsSoon();
    }
  }

  function normalizeDecisionRequest(request) {
    var source = request && typeof request === "object" ? request : null;
    if (!source) {
      return null;
    }
    var question = trim(String(source.question || ""));
    if (!question) {
      return null;
    }
    var optionsRaw = Array.isArray(source.options) ? source.options : [];
    var options = [];
    for (var i = 0; i < optionsRaw.length; i += 1) {
      var optionText = trim(String(optionsRaw[i] || ""));
      if (!optionText) {
        continue;
      }
      if (optionText.toLowerCase() === "other") {
        continue;
      }
      options.push(optionText);
      if (options.length >= 5) {
        break;
      }
    }
    if (!options.length) {
      return null;
    }
    return {
      question: question,
      options: options
    };
  }

  function normalizeApprovalRequest(request) {
    var source = request && typeof request === "object" ? request : null;
    if (!source) {
      return null;
    }
    var command = trim(String(source.command || ""));
    if (!command) {
      return null;
    }
    return {
      command: command,
      reason: trim(String(source.reason || ""))
    };
  }

  function asArrayCopy(value) {
    if (!Array.isArray(value)) {
      return [];
    }
    return value.slice(0);
  }

  function normalizeModeRuntime(payload) {
    var source = payload && typeof payload === "object" ? payload : {};
    var scheduler = source.scheduler && typeof source.scheduler === "object" ? source.scheduler : {};
    var cooperation = source.cooperation && typeof source.cooperation === "object" ? source.cooperation : {};
    var failureTaxonomy = source.failure_taxonomy && typeof source.failure_taxonomy === "object" ? source.failure_taxonomy : {};
    var proposalState = source.improvement_proposals && typeof source.improvement_proposals === "object" ? source.improvement_proposals : {};
    var proposalCounts = proposalState.counts && typeof proposalState.counts === "object" ? proposalState.counts : {};
    var controllerVariantsState = source.controller_variants && typeof source.controller_variants === "object"
      ? source.controller_variants
      : {};
    var controllerCompareState = controllerVariantsState.quality_compare && typeof controllerVariantsState.quality_compare === "object"
      ? controllerVariantsState.quality_compare
      : {};
    var qualityScorecardState = source.quality_scorecard && typeof source.quality_scorecard === "object"
      ? source.quality_scorecard
      : {};
    var modesRaw = asArrayCopy(source.modes);
    var skillsRaw = asArrayCopy(source.skills);
    var panelsRaw = asArrayCopy(source.panels);
    var directivesRaw = asArrayCopy(cooperation.recent);
    var failureCategoriesRaw = asArrayCopy(failureTaxonomy.categories);
    var failureRecentRaw = asArrayCopy(failureTaxonomy.recent);
    var proposalItemsRaw = asArrayCopy(proposalState.items);
    var controllerVariantsItemsRaw = asArrayCopy(controllerVariantsState.items);
    var qualityRecentRaw = asArrayCopy(qualityScorecardState.recent);
    var modes = [];
    var skills = [];
    var panels = [];
    var directives = [];
    var failureCategories = [];
    var failureRecent = [];
    var proposalItems = [];
    var controllerVariantItems = [];
    var qualityRecentItems = [];

    for (var i = 0; i < modesRaw.length; i += 1) {
      var mode = modesRaw[i];
      if (!mode || typeof mode !== "object") {
        continue;
      }
      var modeId = trim(String(mode.id || ""));
      if (!modeId) {
        continue;
      }
      modes.push({
        id: modeId,
        name: trim(String(mode.name || modeId)),
        description: trim(String(mode.description || "")),
        enabled: Number(mode.enabled || 0) > 0,
        priority: queueNumber(mode.priority || 0),
        cadence_sec: queueNumber(mode.cadence_sec || 0),
        interrupt_rights: Number(mode.interrupt_rights || 0) > 0,
        allow_queue_injection: Number(mode.allow_queue_injection || 0) > 0,
        status: trim(String(mode.status || "idle")),
        drift_score: trim(String(mode.drift_score || "0.00")),
        last_tick: trim(String(mode.last_tick || "")),
        next_tick: trim(String(mode.next_tick || "")),
        goal_state: trim(String(mode.goal_state || "")),
        last_skill_plan: asArrayCopy(mode.last_skill_plan),
        last_directive_count: trim(String(mode.last_directive_count || "0")),
        last_directive_emits: trim(String(mode.last_directive_emits || "0")),
        last_directive_summary: trim(String(mode.last_directive_summary || "none")),
        telemetry_subscriptions: asArrayCopy(mode.telemetry_subscriptions),
        allowed_capabilities: asArrayCopy(mode.allowed_capabilities)
      });
    }

    for (var j = 0; j < skillsRaw.length; j += 1) {
      var skill = skillsRaw[j];
      if (!skill || typeof skill !== "object") {
        continue;
      }
      var skillId = trim(String(skill.id || ""));
      if (!skillId) {
        continue;
      }
      skills.push({
        id: skillId,
        name: trim(String(skill.name || skillId)),
        description: trim(String(skill.description || "")),
        trigger: trim(String(skill.trigger || "")),
        capabilities: asArrayCopy(skill.capabilities),
        stateless: skill.stateless !== false,
        interrupt_authority: skill.interrupt_authority === true,
        files: skill.files && typeof skill.files === "object" ? skill.files : {}
      });
    }

    for (var k = 0; k < panelsRaw.length; k += 1) {
      var panel = panelsRaw[k];
      if (!panel || typeof panel !== "object") {
        continue;
      }
      var panelId = trim(String(panel.id || ""));
      if (!panelId) {
        continue;
      }
      panels.push({
        id: panelId,
        title: trim(String(panel.title || panelId)),
        summary: trim(String(panel.summary || "")),
        stream: trim(String(panel.stream || "")),
        metrics: asArrayCopy(panel.metrics)
      });
    }

    for (var d = 0; d < directivesRaw.length; d += 1) {
      var directive = directivesRaw[d];
      if (!directive || typeof directive !== "object") {
        continue;
      }
      directives.push({
        timestamp: trim(String(directive.timestamp || "")),
        from_mode: trim(String(directive.from_mode || "")),
        to_mode: trim(String(directive.to_mode || "")),
        kind: trim(String(directive.kind || "")),
        priority: trim(String(directive.priority || "")),
        payload: trim(String(directive.payload || "")),
        expires_epoch: trim(String(directive.expires_epoch || "")),
        expired: Number(directive.expired || 0) > 0 || directive.expired === true
      });
    }

    for (var fc = 0; fc < failureCategoriesRaw.length; fc += 1) {
      var failureCategory = failureCategoriesRaw[fc];
      if (!failureCategory || typeof failureCategory !== "object") {
        continue;
      }
      var failureCategoryId = trim(String(failureCategory.id || ""));
      if (!failureCategoryId) {
        continue;
      }
      failureCategories.push({
        id: failureCategoryId,
        label: trim(String(failureCategory.label || failureCategoryId)),
        count: trim(String(failureCategory.count || "0")),
        last_seen: trim(String(failureCategory.last_seen || "")),
        surface: trim(String(failureCategory.surface || "")),
        severity: trim(String(failureCategory.severity || ""))
      });
    }

    for (var fr = 0; fr < failureRecentRaw.length; fr += 1) {
      var failureEvent = failureRecentRaw[fr];
      if (!failureEvent || typeof failureEvent !== "object") {
        continue;
      }
      var failureTimestamp = trim(String(failureEvent.timestamp || ""));
      var failureCategoryIdRecent = trim(String(failureEvent.category || ""));
      var failureAction = trim(String(failureEvent.action || ""));
      var failureError = trim(String(failureEvent.error || ""));
      if (!failureTimestamp && !failureCategoryIdRecent && !failureAction && !failureError) {
        continue;
      }
      failureRecent.push({
        timestamp: failureTimestamp,
        category: failureCategoryIdRecent,
        category_label: trim(String(failureEvent.category_label || failureCategoryIdRecent)),
        surface: trim(String(failureEvent.surface || "")),
        severity: trim(String(failureEvent.severity || "")),
        mode: trim(String(failureEvent.mode || "")),
        action: failureAction,
        error: failureError,
        hypothesis: trim(String(failureEvent.hypothesis || "")),
        next_attempt: trim(String(failureEvent.next_attempt || ""))
      });
    }

    for (var pi = 0; pi < proposalItemsRaw.length; pi += 1) {
      var proposalItem = proposalItemsRaw[pi];
      if (!proposalItem || typeof proposalItem !== "object") {
        continue;
      }
      var proposalId = trim(String(proposalItem.id || ""));
      if (!proposalId) {
        continue;
      }
      proposalItems.push({
        id: proposalId,
        title: trim(String(proposalItem.title || proposalId)),
        scope: trim(String(proposalItem.scope || "other")),
        risk_level: trim(String(proposalItem.risk_level || "medium")),
        status: trim(String(proposalItem.status || "proposed")),
        source: trim(String(proposalItem.source || "manual")),
        source_mode: trim(String(proposalItem.source_mode || "")),
        created_at: trim(String(proposalItem.created_at || "")),
        updated_at: trim(String(proposalItem.updated_at || "")),
        applied_at: trim(String(proposalItem.applied_at || "")),
        taxonomy_category: trim(String(proposalItem.taxonomy_category || "")),
        taxonomy_category_label: trim(String(proposalItem.taxonomy_category_label || "")),
        rationale: trim(String(proposalItem.rationale || "")),
        proposed_change: trim(String(proposalItem.proposed_change || ""))
      });
    }

    for (var cv = 0; cv < controllerVariantsItemsRaw.length; cv += 1) {
      var variantItem = controllerVariantsItemsRaw[cv];
      if (!variantItem || typeof variantItem !== "object") {
        continue;
      }
      var variantId = trim(String(variantItem.id || ""));
      if (!variantId) {
        continue;
      }
      controllerVariantItems.push({
        id: variantId,
        name: trim(String(variantItem.name || variantId)),
        status: trim(String(variantItem.status || "standby")),
        kind: trim(String(variantItem.kind || "manual")),
        parent_id: trim(String(variantItem.parent_id || "")),
        source_proposal: trim(String(variantItem.source_proposal || "")),
        scope: trim(String(variantItem.scope || "other")),
        risk_level: trim(String(variantItem.risk_level || "medium")),
        created_at: trim(String(variantItem.created_at || "")),
        updated_at: trim(String(variantItem.updated_at || "")),
        last_seen_at: trim(String(variantItem.last_seen_at || "")),
        instructions: trim(String(variantItem.instructions || "")),
        runs: trim(String(variantItem.runs || "0")),
        successes: trim(String(variantItem.successes || "0")),
        avg_quality: trim(String(variantItem.avg_quality || "0.000")),
        success_rate_pct: trim(String(variantItem.success_rate_pct || "0.0"))
      });
    }

    for (var qr = 0; qr < qualityRecentRaw.length; qr += 1) {
      var qualityRecentItem = qualityRecentRaw[qr];
      if (!qualityRecentItem || typeof qualityRecentItem !== "object") {
        continue;
      }
      var qualityTimestamp = trim(String(qualityRecentItem.timestamp || ""));
      var qualityRunMode = trim(String(qualityRecentItem.run_mode || ""));
      var qualityScore = trim(String(qualityRecentItem.quality_score || ""));
      if (!qualityTimestamp && !qualityRunMode && !qualityScore) {
        continue;
      }
      qualityRecentItems.push({
        timestamp: qualityTimestamp,
        variant_id: trim(String(qualityRecentItem.variant_id || "")),
        run_id: trim(String(qualityRecentItem.run_id || "")),
        run_mode: qualityRunMode,
        queue_status: trim(String(qualityRecentItem.queue_status || "")),
        final_state: trim(String(qualityRecentItem.final_state || "")),
        quality_score: qualityScore,
        delta_score: trim(String(qualityRecentItem.delta_score || "0.000")),
        run_elapsed_sec: trim(String(qualityRecentItem.run_elapsed_sec || "0")),
        iteration_count: trim(String(qualityRecentItem.iteration_count || "0")),
        failure_count: trim(String(qualityRecentItem.failure_count || "0")),
        decision_requested: Number(qualityRecentItem.decision_requested || 0) > 0 || qualityRecentItem.decision_requested === true
      });
    }

    modes.sort(function (a, b) {
      var priorityDiff = Number(b.priority || 0) - Number(a.priority || 0);
      if (priorityDiff !== 0) {
        return priorityDiff;
      }
      return String(a.name || a.id || "").localeCompare(String(b.name || b.id || ""));
    });
    skills.sort(function (a, b) {
      return String(a.name || a.id || "").localeCompare(String(b.name || b.id || ""));
    });
    failureCategories.sort(function (a, b) {
      var countDiff = Number(b.count || 0) - Number(a.count || 0);
      if (countDiff !== 0) {
        return countDiff;
      }
      return String(a.label || a.id || "").localeCompare(String(b.label || b.id || ""));
    });
    failureRecent.sort(function (a, b) {
      return String(b.timestamp || "").localeCompare(String(a.timestamp || ""));
    });
    proposalItems.sort(function (a, b) {
      return String(b.created_at || "").localeCompare(String(a.created_at || ""));
    });
    controllerVariantItems.sort(function (a, b) {
      var statusA = String(a.status || "");
      var statusB = String(b.status || "");
      if (statusA !== statusB) {
        if (statusA === "active") {
          return -1;
        }
        if (statusB === "active") {
          return 1;
        }
        if (statusA === "candidate") {
          return -1;
        }
        if (statusB === "candidate") {
          return 1;
        }
      }
      return String(b.updated_at || b.created_at || "").localeCompare(String(a.updated_at || a.created_at || ""));
    });
    qualityRecentItems.sort(function (a, b) {
      return String(b.timestamp || "").localeCompare(String(a.timestamp || ""));
    });

    return {
      scheduler: {
        last_tick: trim(String(scheduler.last_tick || "")),
        last_tick_iso: trim(String(scheduler.last_tick_iso || "")),
        ticks: trim(String(scheduler.ticks || "0")),
        last_due_modes: trim(String(scheduler.last_due_modes || "0")),
        last_injections: trim(String(scheduler.last_injections || "0")),
        last_directives_received: trim(String(scheduler.last_directives_received || "0")),
        last_directives_emitted: trim(String(scheduler.last_directives_emitted || "0")),
        summary: trim(String(scheduler.summary || ""))
      },
      modes: modes,
      skills: skills,
      panels: panels,
      cooperation: {
        pending_total: trim(String(cooperation.pending_total || "0")),
        modes_with_pending: trim(String(cooperation.modes_with_pending || "0")),
        recent: directives
      },
      failure_taxonomy: {
        total: trim(String(failureTaxonomy.total || "0")),
        last_recorded_at: trim(String(failureTaxonomy.last_recorded_at || "")),
        categories: failureCategories,
        recent: failureRecent
      },
      improvement_proposals: {
        manual_apply_only: proposalState.manual_apply_only !== false,
        counts: {
          total: trim(String(proposalCounts.total || "0")),
          proposed: trim(String(proposalCounts.proposed || "0")),
          accepted: trim(String(proposalCounts.accepted || "0")),
          applied: trim(String(proposalCounts.applied || "0")),
          rejected: trim(String(proposalCounts.rejected || "0"))
        },
        items: proposalItems
      },
      controller_variants: {
        active_variant_id: trim(String(controllerVariantsState.active_variant_id || "")),
        previous_active_variant_id: trim(String(controllerVariantsState.previous_active_variant_id || "")),
        sample_rate_percent: trim(String(controllerVariantsState.sample_rate_percent || "0")),
        max_sample_size: trim(String(controllerVariantsState.max_sample_size || "0")),
        sample_min_runs_for_promotion: trim(String(controllerVariantsState.sample_min_runs_for_promotion || "0")),
        updated_at: trim(String(controllerVariantsState.updated_at || "")),
        quality_compare: {
          active_id: trim(String(controllerCompareState.active_id || "")),
          candidate_id: trim(String(controllerCompareState.candidate_id || "")),
          active_runs: trim(String(controllerCompareState.active_runs || "0")),
          candidate_runs: trim(String(controllerCompareState.candidate_runs || "0")),
          active_avg_quality: trim(String(controllerCompareState.active_avg_quality || "0.000")),
          candidate_avg_quality: trim(String(controllerCompareState.candidate_avg_quality || "0.000")),
          quality_delta: trim(String(controllerCompareState.quality_delta || "0.000")),
          sample_min_runs_for_promotion: trim(String(controllerCompareState.sample_min_runs_for_promotion || "0")),
          recommendation: trim(String(controllerCompareState.recommendation || "insufficient-data"))
        },
        items: controllerVariantItems
      },
      quality_scorecard: {
        total_runs: trim(String(qualityScorecardState.total_runs || "0")),
        overall_avg_quality: trim(String(qualityScorecardState.overall_avg_quality || "0.000")),
        last_updated: trim(String(qualityScorecardState.last_updated || "")),
        scorecard_path: trim(String(qualityScorecardState.scorecard_path || "")),
        markdown_preview: trim(String(qualityScorecardState.markdown_preview || "")),
        recent: qualityRecentItems
      }
    };
  }

  function conversationDecisionRequest(conversation) {
    return normalizeDecisionRequest(conversation && conversation.decision_request ? conversation.decision_request : null);
  }

  function conversationApprovalRequest(conversation) {
    return normalizeApprovalRequest(conversation && conversation.approval_request ? conversation.approval_request : null);
  }

  function setConversationDecisionRequest(workspaceId, conversationId, request) {
    var workspace = getWorkspaceById(workspaceId);
    var conversation = getConversationById(workspace, conversationId);
    if (!conversation) {
      return;
    }
    conversation.decision_request = normalizeDecisionRequest(request);
  }

  function setAwaitingApprovalState(workspaceId, conversationId, value) {
    if (!workspaceId || !conversationId) {
      return;
    }
