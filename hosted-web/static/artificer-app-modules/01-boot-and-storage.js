(function () {
  "use strict";

  if (typeof window !== "undefined") {
    window.__artificerBooted = "loading";
  }

  var artificerBootLaunchKey = "";
  try {
    artificerBootLaunchKey = String(new URLSearchParams(String(window.location.search || "")).get("launch") || "");
  } catch (_bootLaunchErr) {
    artificerBootLaunchKey = "";
  }

  function notifyHostBoot(type, payload) {
    if (
      typeof window === "undefined" ||
      !window.parent ||
      window.parent === window ||
      typeof window.parent.postMessage !== "function"
    ) {
      return;
    }
    var message = {
      source: "artificer-hosted-web",
      type: String(type || ""),
      launch: artificerBootLaunchKey
    };
    var extra = payload && typeof payload === "object" ? payload : {};
    var keys = Object.keys(extra);
    for (var i = 0; i < keys.length; i += 1) {
      message[keys[i]] = extra[keys[i]];
    }
    try {
      window.parent.postMessage(message, "*");
    } catch (_postErr) {
      return;
    }
  }

  function setArtificerBootPhase(phase, text) {
    if (typeof window !== "undefined") {
      window.__artificerBooted = String(phase || "loading");
    }
    var statusText = trim(text || "");
    if (statusText) {
      notifyHostBoot("status", { text: statusText });
    }
  }

  var seenConversationStorageKey = "artificer.conversationSeenUpdated";
  var workspaceStateCacheKey = "artificer.workspaceStateCache.v1";
  var runEventsStorageKey = "artificer.runEventsByConversation.v1";
  var pendingOutgoingStorageKey = "artificer.pendingOutgoingByKey.v1";
  var workspaceOrderStorageKey = "artificer.workspaceOrder.v1";
  var conversationOrderStorageKey = "artificer.conversationOrderByWorkspace.v1";
  var durableUiStateSeenConversationKey = "seen_conversation_updated";
  var durableUiStateWorkspaceOrderKey = "workspace_order";
  var durableUiStateConversationOrderKey = "conversation_order_by_workspace";

  function storageGet(key, fallback) {
    try {
      var value = window.localStorage.getItem(key);
      if (value === null || typeof value === "undefined") {
        return fallback;
      }
      return value;
    } catch (_err) {
      return fallback;
    }
  }

  function storageSet(key, value) {
    try {
      window.localStorage.setItem(key, value);
      return true;
    } catch (_err) {
      return false;
    }
  }

  function parseSeenUpdatedValue(value) {
    var parsed = Number(value);
    if (!isFinite(parsed) || parsed < 0) {
      return 0;
    }
    return Math.floor(parsed);
  }

  function normalizeSeenConversationMap(source) {
    var parsed = source && typeof source === "object" ? source : {};
    var clean = {};
    var keys = Object.keys(parsed);
    for (var i = 0; i < keys.length; i += 1) {
      var key = keys[i];
      clean[key] = parseSeenUpdatedValue(parsed[key]);
    }
    return clean;
  }

  function saveSeenConversationState(nextMap, options) {
    var clean = normalizeSeenConversationMap(nextMap);
    try {
      window.localStorage.setItem(seenConversationStorageKey, JSON.stringify(clean));
    } catch (_err) {
      // Local cache failures should not block backend durability writes.
    }
    if (!options || options.persistBackend !== false) {
      queueDurableUiStateWrite(durableUiStateSeenConversationKey, clean);
    }
    return clean;
  }

  function loadSeenConversationState() {
    var raw = "";
    try {
      raw = window.localStorage.getItem(seenConversationStorageKey) || "";
    } catch (_err) {
      return { map: {}, hasSaved: false };
    }

    if (!raw) {
      return { map: {}, hasSaved: false };
    }

    var parsed = null;
    try {
      parsed = JSON.parse(raw);
    } catch (_err2) {
      return { map: {}, hasSaved: true };
    }

    if (!parsed || typeof parsed !== "object") {
      return { map: {}, hasSaved: true };
    }
    return { map: normalizeSeenConversationMap(parsed), hasSaved: true };
  }

  function clipTextForStorage(value, maxChars) {
    var text = String(value || "");
    var limit = Number(maxChars || 0);
    if (!isFinite(limit) || limit < 1) {
      return "";
    }
    if (text.length <= limit) {
      return text;
    }
    if (limit <= 16) {
      return text.slice(0, limit);
    }
    return text.slice(0, limit - 16) + " [truncated]";
  }

  function normalizeRunChecklistStatus(value) {
    var status = String(value || "").toLowerCase();
    if (status === "completed" || status === "complete" || status === "finished") {
      return "done";
    }
    if (status === "in-progress" || status === "in_progress" || status === "working") {
      return "active";
    }
    if (status === "todo" || status === "open" || status === "queued") {
      return "pending";
    }
    if (status !== "done" && status !== "active" && status !== "pending") {
      return "pending";
    }
    return status;
  }

  function normalizeRunTaskStatusSnapshot(snapshot) {
    if (!snapshot || typeof snapshot !== "object") {
      return null;
    }
    var source = String(snapshot.source || "backend");
    var inputTasks = Array.isArray(snapshot.tasks) ? snapshot.tasks : [];
    var tasks = [];
    var completed = 0;
    for (var i = 0; i < inputTasks.length && tasks.length < 40; i += 1) {
      var item = inputTasks[i] || {};
      var id = clipTextForStorage(item.id || "", 160);
      var text = clipTextForStorage(item.text || item.title || item.label || "", 520);
      if (!text) {
        continue;
      }
      var status = normalizeRunChecklistStatus(item.status || "");
      var done = status === "done" || item.done === true;
      if (done) {
        status = "done";
        completed += 1;
      }
      tasks.push({
        id: id,
        text: text,
        status: status,
        done: done
      });
    }
    if (!tasks.length) {
      return null;
    }
    return {
      tasks: tasks,
      completed: completed,
      total: tasks.length,
      source: clipTextForStorage(source, 64) || "backend"
    };
  }

  function sanitizeRunEventForStorage(event) {
    if (!event || typeof event !== "object") {
      return null;
    }
    var status = String(event.status || "done");
    if (
      status !== "running" &&
      status !== "done" &&
      status !== "error" &&
      status !== "cancelled" &&
      status !== "awaiting_approval" &&
      status !== "awaiting_decision" &&
      status !== "approval_granted"
    ) {
      status = "done";
    }
    var cleaned = {
      id: clipTextForStorage(event.id || "", 120),
      status: status,
      started_at: clipTextForStorage(event.started_at || "", 80),
      finished_at: clipTextForStorage(event.finished_at || "", 80),
      last_activity_at: clipTextForStorage(event.last_activity_at || "", 80),
      model: clipTextForStorage(event.model || "", 200),
      error: clipTextForStorage(event.error || "", 2400),
      decision_hint: clipTextForStorage(event.decision_hint || "", 1400),
      stream_text: clipTextForStorage(event.stream_text || "", 7000),
      plan: clipTextForStorage(event.plan || "", 5000),
      git_status: clipTextForStorage(event.git_status || "", 5000),
      git_diff: clipTextForStorage(event.git_diff || "", 7000),
      state: clipTextForStorage(event.state || "", 4000),
      failures: clipTextForStorage(event.failures || "", 7000),
      session_log: clipTextForStorage(event.session_log || "", 7000)
    };
    var awaitingAssistantRaw = Number(event.awaiting_assistant);
    if (isFinite(awaitingAssistantRaw) && awaitingAssistantRaw > 0) {
      cleaned.awaiting_assistant = 1;
    }
    var anchorRaw = Number(event.message_anchor);
    if (isFinite(anchorRaw) && anchorRaw >= 0) {
      cleaned.message_anchor = Math.floor(anchorRaw);
    }
    var taskStatus = normalizeRunTaskStatusSnapshot(event.task_status);
    if (taskStatus && taskStatus.total > 0) {
      cleaned.task_status = taskStatus;
    }
    var commands = Array.isArray(event.commands) ? event.commands : [];
    if (commands.length) {
      cleaned.commands = [];
      for (var i = 0; i < commands.length && cleaned.commands.length < 12; i += 1) {
        var item = commands[i] || {};
        cleaned.commands.push({
          command: clipTextForStorage(item.command || "", 800),
          status: clipTextForStorage(item.status || "", 40),
          output: clipTextForStorage(item.output || "", 1800)
        });
      }
    } else {
      cleaned.commands = [];
    }
    if (!cleaned.id) {
      cleaned.id = String(Date.now()) + "-" + String(Math.floor(Math.random() * 999999));
    }
    return cleaned;
  }

  function compactRunEventsForStorage(source) {
    var map = source && typeof source === "object" ? source : {};
    var result = {};
    var keys = Object.keys(map);
    for (var i = 0; i < keys.length; i += 1) {
      var conversationId = String(keys[i] || "");
      if (!conversationId) {
        continue;
      }
      var list = Array.isArray(map[conversationId]) ? map[conversationId] : [];
      if (!list.length) {
        continue;
      }
      var start = Math.max(0, list.length - 12);
      var cleanedList = [];
      for (var j = start; j < list.length; j += 1) {
        var sanitized = sanitizeRunEventForStorage(list[j]);
        if (sanitized) {
          cleanedList.push(sanitized);
        }
      }
      if (cleanedList.length) {
        result[conversationId] = cleanedList;
      }
    }
    return result;
  }

  function loadRunEventsState() {
    var raw = "";
    try {
      raw = window.localStorage.getItem(runEventsStorageKey) || "";
    } catch (_err) {
      return {};
    }
    if (!raw) {
      return {};
    }
    var parsed = null;
    try {
      parsed = JSON.parse(raw);
    } catch (_err2) {
      return {};
    }
    return compactRunEventsForStorage(parsed);
  }

  function saveRunEventsState(eventsMap) {
    try {
      var compacted = compactRunEventsForStorage(eventsMap);
      window.localStorage.setItem(runEventsStorageKey, JSON.stringify(compacted));
    } catch (_err) {
      return;
    }
  }

  function compactPendingOutgoingForStorage(source) {
    var map = source && typeof source === "object" ? source : {};
    var result = {};
    var keys = Object.keys(map);
    var maxKeys = 160;
    for (var i = 0; i < keys.length && Object.keys(result).length < maxKeys; i += 1) {
      var key = String(keys[i] || "");
      if (!key) {
        continue;
      }
      if (!parseOutgoingKey(key)) {
        continue;
      }
      var inputList = Array.isArray(map[key]) ? map[key] : [];
      if (!inputList.length) {
        continue;
      }
      var cleaned = [];
      for (var j = 0; j < inputList.length; j += 1) {
        var entry = inputList[j] || {};
        var content = trim(String(entry.content || ""));
        if (!content) {
          continue;
        }
        var createdAt = Number(entry.createdAt || 0);
        if (!isFinite(createdAt) || createdAt <= 0) {
          createdAt = Date.now();
        }
        cleaned.push({
          id: clipTextForStorage(entry.id || "", 120) || ("pending-" + String(createdAt) + "-" + String(Math.floor(Math.random() * 1000000))),
          content: clipTextForStorage(content, 7000),
          createdAt: Math.floor(createdAt)
        });
      }
      if (!cleaned.length) {
        continue;
      }
      cleaned.sort(function (a, b) {
        return Number(a.createdAt || 0) - Number(b.createdAt || 0);
      });
      if (cleaned.length > 30) {
        cleaned = cleaned.slice(cleaned.length - 30);
      }
      result[key] = cleaned;
    }
    return result;
  }

  function loadPendingOutgoingState() {
    var raw = "";
    try {
      raw = window.localStorage.getItem(pendingOutgoingStorageKey) || "";
    } catch (_err) {
      return {};
    }
    if (!raw) {
      return {};
    }
    var parsed = null;
    try {
      parsed = JSON.parse(raw);
    } catch (_err2) {
      return {};
    }
    return compactPendingOutgoingForStorage(parsed);
  }

  function savePendingOutgoingState(pendingOutgoingMap) {
    try {
      var compacted = compactPendingOutgoingForStorage(pendingOutgoingMap);
      window.localStorage.setItem(pendingOutgoingStorageKey, JSON.stringify(compacted));
    } catch (_err) {
      return;
    }
  }

  function parseStoredPaneWidth(key, fallback) {
    var raw = Number(storageGet(key, String(fallback)));
    if (!isFinite(raw) || raw <= 0) {
      return fallback;
    }
    return Math.round(raw);
  }

  function loadWorkspaceStateCache() {
    var raw = "";
    try {
      raw = window.localStorage.getItem(workspaceStateCacheKey) || "";
    } catch (_err) {
      return null;
    }
    if (!raw) {
      return null;
    }
    var parsed = null;
    try {
      parsed = JSON.parse(raw);
    } catch (_err2) {
      return null;
    }
    if (!parsed || typeof parsed !== "object" || !Array.isArray(parsed.workspaces)) {
      return null;
    }
    var savedAt = Number(parsed.saved_at || 0);
    if (!isFinite(savedAt) || savedAt <= 0) {
      return null;
    }
    if (Date.now() - savedAt > 1000 * 60 * 60 * 24) {
      return null;
    }
    return parsed;
  }

  function saveWorkspaceStateCache(workspaces) {
    if (!Array.isArray(workspaces)) {
      return;
    }
    try {
      window.localStorage.setItem(workspaceStateCacheKey, JSON.stringify({
        saved_at: Date.now(),
        workspaces: workspaces
      }));
    } catch (_err) {
      return;
    }
  }

  function normalizeOrderedIdList(list) {
    var input = Array.isArray(list) ? list : [];
    var seen = {};
    var out = [];
    for (var i = 0; i < input.length; i += 1) {
      var id = trim(String(input[i] || ""));
      if (!id || seen[id]) {
        continue;
      }
      seen[id] = true;
      out.push(id);
    }
    return out;
  }

  function loadWorkspaceOrderState() {
    var raw = "";
    try {
      raw = window.localStorage.getItem(workspaceOrderStorageKey) || "";
    } catch (_err) {
      return [];
    }
    if (!raw) {
      return [];
    }
    var parsed = null;
    try {
      parsed = JSON.parse(raw);
    } catch (_err2) {
      return [];
    }
    return normalizeOrderedIdList(parsed);
  }

  function saveWorkspaceOrderState(orderIds) {
    var normalized = normalizeOrderedIdList(orderIds);
    try {
      window.localStorage.setItem(workspaceOrderStorageKey, JSON.stringify(normalized));
    } catch (_err) {
      // Local cache failures should not block backend durability writes.
    }
    queueDurableUiStateWrite(durableUiStateWorkspaceOrderKey, normalized);
  }

  function loadConversationOrderState() {
    var raw = "";
    try {
      raw = window.localStorage.getItem(conversationOrderStorageKey) || "";
    } catch (_err) {
      return {};
    }
    if (!raw) {
      return {};
    }
    var parsed = null;
    try {
      parsed = JSON.parse(raw);
    } catch (_err2) {
      return {};
    }
    if (!parsed || typeof parsed !== "object") {
      return {};
    }
    var out = {};
    var workspaceIds = Object.keys(parsed);
    for (var i = 0; i < workspaceIds.length; i += 1) {
      var workspaceId = trim(String(workspaceIds[i] || ""));
      if (!workspaceId) {
        continue;
      }
      var list = normalizeOrderedIdList(parsed[workspaceId]);
      if (list.length) {
        out[workspaceId] = list;
      }
    }
    return out;
  }

  function saveConversationOrderState(conversationOrderByWorkspace) {
    if (!conversationOrderByWorkspace || typeof conversationOrderByWorkspace !== "object") {
      return;
    }
    var clean = {};
    var workspaceIds = Object.keys(conversationOrderByWorkspace);
    for (var i = 0; i < workspaceIds.length; i += 1) {
      var workspaceId = trim(String(workspaceIds[i] || ""));
      if (!workspaceId) {
        continue;
      }
      var list = normalizeOrderedIdList(conversationOrderByWorkspace[workspaceId]);
      if (list.length) {
        clean[workspaceId] = list;
      }
    }
    try {
      window.localStorage.setItem(conversationOrderStorageKey, JSON.stringify(clean));
    } catch (_err) {
      // Local cache failures should not block backend durability writes.
    }
    queueDurableUiStateWrite(durableUiStateConversationOrderKey, clean);
  }

  function slugifyRoutePart(text) {
    var value = String(text || "").toLowerCase();
    value = value.replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
    return value;
  }

  function encodeRoutePart(text) {
    return encodeURIComponent(String(text || ""));
  }

  function decodeRoutePart(text) {
    try {
      return decodeURIComponent(String(text || ""));
    } catch (_err) {
      return String(text || "");
    }
  }

  function normalizeRoutePath(pathname) {
    var raw = String(pathname || "/");
    if (!raw) {
      raw = "/";
    }
    if (raw.charAt(0) !== "/") {
      raw = "/" + raw;
    }
    return raw.replace(/\/{2,}/g, "/");
  }

  function normalizeRouteHash(hashText) {
    var raw = String(hashText || "");
    if (!raw) {
      return "";
    }
    if (raw.charAt(0) === "#") {
      raw = raw.slice(1);
    }
    raw = raw.replace(/^\s+|\s+$/g, "");
    if (!raw) {
      return "";
    }
    if (raw.charAt(0) !== "/") {
      raw = "/" + raw;
    }
    raw = normalizeRoutePath(raw);
    if (raw === "/") {
      return "";
    }
    return "#" + raw;
  }

  function routeSelectionFromSegments(segments) {
    var items = Array.isArray(segments) ? segments : [];
    if (!items.length) {
      return null;
    }
    var workspaceToken = decodeRoutePart(items[0]);
    var conversationToken = items.length > 1 ? decodeRoutePart(items[1]) : "";
    if (!workspaceToken) {
      return null;
    }
    return {
      workspaceToken: workspaceToken,
      conversationToken: conversationToken
    };
  }

  function routeTokenFromLabelAndId(label, id) {
    var idText = String(id || "");
    var slug = slugifyRoutePart(label || idText);
    if (slug && idText) {
      return slug + "--" + idText;
    }
    return slug || idText;
  }

  function routeIdHint(token) {
    var raw = String(token || "");
    var marker = raw.lastIndexOf("--");
    if (marker > 0 && marker + 2 < raw.length) {
      return raw.slice(marker + 2);
    }
    return raw;
  }

  function parseRouteSelectionFromLocation() {
    if (typeof window === "undefined" || !window.location) {
      return null;
    }
    var hash = normalizeRouteHash(window.location.hash || "");
    if (hash) {
      var hashPath = normalizeRoutePath(hash.slice(1));
      var hashSegments = hashPath.split("/").filter(function (part) {
        return !!part;
      });
      var hashSelection = routeSelectionFromSegments(hashSegments);
      if (hashSelection) {
        return hashSelection;
      }
    }
    var path = normalizeRoutePath(window.location.pathname || "/");
    var segments = path.split("/").filter(function (part) {
      return !!part;
    });
    if (segments.length >= 2 && segments[0] === "pages" && /^index\.html?$/i.test(segments[1])) {
      segments = segments.slice(2);
    }
    return routeSelectionFromSegments(segments);
  }

  var initialSeenConversationState = loadSeenConversationState();
  var initialRunEventsState = loadRunEventsState();
  var initialPendingOutgoingState = loadPendingOutgoingState();
  var initialWorkspaceOrderState = loadWorkspaceOrderState();
  var initialConversationOrderState = loadConversationOrderState();

  var state = {
    models: [],
    workspaces: [],
    activeWorkspaceId: "",
    activeConversationId: "",
    activeConversation: null,
    activeConversationLoadError: "",
    activeConversationLoading: false,
    activeConversationLoadingKey: "",
    conversationSwitchOverlay: false,
    activeConversationSelectedAt: 0,
    activeDraftWorkspaceId: "",
    draftTextByWorkspace: {},
    draftModelByWorkspace: {},
    runEventsByConversation: initialRunEventsState,
    expandedWorkspaceIds: {},
    busy: false,
    pickingWorkspace: false,
    sortMode: storageGet("artificer.workspaceSort", "updated"),
    organizeMode: storageGet("artificer.organizeMode", "project"),
    organizeShow: storageGet("artificer.organizeShow", "all"),
    sidebarSection: storageGet("artificer.sidebarSection", "threads"),
    permissionMode: storageGet("artificer.permissionMode", "default"),
    commandExecMode: storageGet("artificer.commandExecMode", "ask-some"),
    githubUsername: storageGet("artificer.githubUsername", ""),
    llmUseGpu: storageGet("artificer.llmUseGpu", "1") !== "0",
    selfImproveModel: "",
    selfImprovePlugins: [],
    selfImproveRunOptions: {
      objective: "",
      competition_enabled: true,
      challenger_model: "",
      sources: {
        papers: true,
        web: true,
        runtime: true,
        repo: true,
        platform: true
      }
    },
    selfImproveLastRun: {
      summary: "",
      generated_at: "",
      model: "",
      papers: [],
      web_signals: [],
      objective: "",
      competition_enabled: false,
      winner_lane: "",
      winner_model: "",
      lane_scores: {},
      evidence_counts: {},
      run_options: {},
      lanes: [],
      plugin_ids: []
    },
    selfImproveLoading: false,
    selfImproveError: "",
    networkAccess: storageGet("artificer.networkAccess", "0") === "1",
    webAccess: storageGet("artificer.webAccess", "0") === "1",
    reflexiveKnowledge: storageGet("artificer.reflexiveKnowledge", "0") === "1",
    selfActuation: storageGet("artificer.selfActuation", "0") === "1",
    agentLoopEnabled: storageGet("artificer.agentLoopEnabled", "1") !== "0",
    runMode: storageGet("artificer.runMode", "auto"),
    assistantModeId: storageGet("artificer.assistantModeId", ""),
    runModeMoreExpanded: false,
    reasoningEffort: storageGet("artificer.reasoningEffort", "medium"),
    computeBudget: storageGet("artificer.computeBudget", "auto"),
    programmerReviewEnabled: storageGet("artificer.programmerReviewEnabled", "1") !== "0",
    programmerReviewRounds: Number(storageGet("artificer.programmerReviewRounds", "2")),
    gitByWorkspace: {},
    branchesByWorkspace: {},
    diffOpen: false,
    diffText: "",
    terminalOpen: false,
    terminalBusy: false,
    terminalLines: [],
    terminalSessionId: "",
    terminalSessionWorkspaceId: "",
    terminalStreamText: "",
    terminalStreamOffset: 0,
    terminalCwd: "",
    terminalInputBuffer: "",
    openMenus: {},
    commitModalDefault: "commit",
    lastOpenTarget: storageGet("artificer.lastOpenTarget", "finder"),
    lastCommitAction: storageGet("artificer.lastCommitAction", "commit"),
    activeTheme: storageGet("artificer.activeTheme", "psionic"),
    themes: [],
    queueWorkerActive: false,
    queueItemsByConversation: {},
    queueItemsLoadingByConversation: {},
    queueItemsFetchedAtByConversation: {},
    queueEdit: {
      workspaceId: "",
      conversationId: "",
      itemId: "",
      draftText: "",
      saving: false
    },
    queueEditPostSaveHoldByConversation: {},
    queueEditPostSaveHoldTimerByConversation: {},
    queueDrag: {
      active: false,
      workspaceId: "",
      conversationId: "",
      itemId: ""
    },
    runningWorkspaceId: "",
    runningConversationId: "",
    awaitingApprovalByConversation: {},
    lastQueuedItemIdByConversation: {},
    decisionInlineDismissedKey: "",
    seenConversationUpdatedByKey: initialSeenConversationState.map,
    seenConversationBootstrapPending: !initialSeenConversationState.hasSaved,
    openWorkspaceMenuWorkspaceId: "",
    workspaceTreeMarkupCache: "",
    workspaceOrderIds: initialWorkspaceOrderState,
    conversationOrderIdsByWorkspace: initialConversationOrderState,
    optimisticConversationsByKey: {},
    workspaceTreeDrag: {
      active: false,
      type: "",
      workspaceId: "",
      conversationId: ""
    },
    pendingArchiveKey: "",
    pendingArchiveReadyAt: 0,
    pendingArchiveSubmittingKey: "",
    pendingAttachments: [],
    dictateBusy: false,
    dictateRecording: false,
    dictateSessionId: "",
    dictateTargetWorkspaceId: "",
    dictateTargetConversationId: "",
    dictateTargetDraftWorkspaceId: "",
    dictateTargetOutgoingKey: "",
    dictateTargetPromptSnapshot: "",
    dictateCaptureContext: null,
    dictateCaptureBySessionId: {},
    dictatePhase: "idle",
    dictateStartedAt: 0,
    dictateElapsedMs: 0,
    dictateWaveLevels: [],
    dictationShortcutHold: storageGet("artificer.dictationShortcutHold", "none"),
    dictationShortcutToggle: storageGet("artificer.dictationShortcutToggle", "none"),
    dictationPrewarmEnabled: storageGet("artificer.dictationPrewarmEnabled", "1") !== "0",
    dictationLanguage: storageGet("artificer.dictationLanguage", "auto"),
    dictationLanguages: [{ value: "auto", label: "Auto-detect" }],
    dictateHotkeyHoldActive: false,
    dictateHotkeyHoldTrigger: "",
    dictateHotkeyHoldIntent: false,
    dictationInstallReady: false,
    dictationInstallInfo: null,
    dictationInstallInfoLoading: false,
    dictationInstallBusy: false,
    dictationInstallCancelling: false,
    dictationInstallPendingCancel: false,
    dictationInstallCancelJobId: "",
    dictationInstallCancelRequestedAt: 0,
    dictationInstallCancelAttempts: 0,
    dictationInstallJob: null,
    dictationInstallError: "",
    dictationInstalled: false,
    dictationBackend: "",
    dictationPreferredBackend: "",
    composerDragDepth: 0,
    awaitingDirPicker: false,
    modelDataLoading: true,
    modelLoadError: "",
    appIcons: {
      finder: "",
      textmate: ""
    },
    modelCatalog: [],
    modelInstalls: [],
    modelInstallJob: null,
    modelInstallLog: "",
    commandRulesByWorkspace: {},
    commandRulesWorkspaceId: "",
    commandRulesLastRenderedWorkspaceId: "",
    commandRulesLoading: false,
    commandRulesError: "",
    modeRuntime: {
      scheduler: {},
      modes: [],
      skills: [],
      panels: [],
      failure_taxonomy: {
        total: "0",
        last_recorded_at: "",
        categories: [],
        recent: []
      },
      improvement_proposals: {
        manual_apply_only: true,
        counts: {
          total: "0",
          proposed: "0",
          accepted: "0",
          applied: "0",
          rejected: "0"
        },
        items: []
      }
    },
    modeRuntimeTaxonomyQuery: {
      hasQueried: false,
      loading: false,
      error: "",
      filters: {
        category: "",
        severity: "",
        surface: "",
        mode: "",
        since_epoch: "0",
        limit: "12"
      },
      matched_total: "0",
      returned: "0",
      events: []
    },
    triage: {
      count: "0",
      cards: []
    },
    automations: {
      count: "0",
      items: []
    },
    automationDaemon: {
      supported: false,
      enabled: false,
      active: false,
      method: "none",
      label: "",
      detail: "",
      loading: false,
      saving: false,
      ticking: false,
      lastTickMessage: "",
      error: ""
    },
    activeAutomationId: "",
    multi_agentCatalog: {
      curated_residents: [],
      target_types: [],
      escalation_classes: []
    },
    workspaceMultiAgentById: {},
    workspaceMultiAgentLoadingById: {},
    workspaceMultiAgentErrorById: {},
    multiAgentGovernanceSavingByWorkspace: {},
    multiAgentResidentBulkSavingByWorkspace: {},
    multiAgentSelectedResidentIdByWorkspace: {},
    multiAgentOpenResidentOptionsByWorkspace: {},
    multiAgentCharterAutosaveTimerByWorkspace: {},
    triageOtherInputProposalId: "",
    activeTriage: false,
    modeRuntimeLoading: false,
    modeRuntimeError: "",
    contextWindowText: "Context window information will display here.",
    lastErrorText: "",
    lastErrorAt: 0,
    stateRevisionApplied: 0,
    initialLoadComplete: false,
    selectionVersion: 0,
    chatAutoScroll: true,
    chatLastKey: "",
    chatMarkupCache: "",
    runDetailsOpenByEventId: {},
    runDigestOpenByEventId: {},
    pendingAssistantDeliveryCountByConversation: {},
    runStreamAutoFollowByEventId: {},
    runStreamScrollTopByEventId: {},
    runTodoMonitorOpenByConversation: {},
    runTerminalMonitorOpenByConversation: {},
    pendingOutgoingByKey: initialPendingOutgoingState,
    composerDraftByKey: {},
    conversationCacheByKey: {},
    activeConversationMissingSinceByKey: {},
    threadsPaneWidth: parseStoredPaneWidth("artificer.threadsPaneWidth", 308),
    diffPaneWidth: 300,
    modelsPaneHeight: parseStoredPaneWidth("artificer.modelsPaneHeight", 300),
    pendingRouteSelection: parseRouteSelectionFromLocation(),
    suppressSelectionUrlSync: false
  };

  var saveDraftTimer = null;
  var liveRunTickTimer = null;
  var runStreamPollTimers = {};
  var modelInstallPollTimer = null;
  var dictationInstallPollTimer = null;
  var dictationInstallPollSession = 0;
  var dictationShortcutPrefsRevision = 0;
  var dictationShortcutPrefsLoadSeq = 0;
  var assistantDeliveryWatchByKey = {};
  var modelAutoRefreshTimer = null;
  var modelAutoRefreshBusy = false;
  var modelAutoRefreshLastAt = 0;
  var runReconcileTimer = null;
  var runReconcileBusy = false;
  var runEventsSaveTimer = null;
  var pendingOutgoingSaveTimer = null;
  var runEventHealTimer = null;
  var runEventHealBusy = false;
  var runEventHealBusySince = 0;
  var runEventHealGuardTimer = null;
  var pendingOutgoingReconcileTimer = null;
  var pendingOutgoingReconcileBusy = false;
  var pendingOutgoingReconcileBlockedCycles = 0;
  var draftConversationCreationPromiseByWorkspace = {};
  var enqueueChainByConversationKey = {};
  var terminalStateWatchTimer = null;
  var terminalStateWatchBusy = false;
  var approvalResumeWatchTimer = null;
  var approvalResumeWatchBusy = false;
  var approvalResumeWatchKey = "";
  var approvalResumeWatchDeadline = 0;
  var terminalPollTimer = null;
  var terminalPollBusy = false;
  var terminalSessionStartPromise = null;
  var automationsTickTimer = null;
  var automationsTickBusy = false;
  var automationModalMode = "create";
  var automationModalEditingId = "";
  var paneDragState = null;
  var suppressMenuCloseUntilMs = 0;
  var pathWidgetClickTimer = null;
  var tooltipEl = null;
  var tooltipTarget = null;
  var tooltipShowTimer = null;
  var tooltipPendingTarget = null;
  var noticeEl = null;
  var noticeHideTimer = null;
  var pendingCommandApproval = null;
  var approvalAnswerPending = false;
  var TOOLTIP_DELAY_MS = 520;
  var DICTATION_PREINSTALL_SIZE_BYTES = 480000000;
  var PENDING_OUTGOING_MAX_AGE_MS = 24 * 60 * 60 * 1000;
  var PENDING_OUTGOING_ORPHAN_CLEAR_MS = 60 * 1000;
  var RUN_PROGRESS_STALL_SOFT_SEC = 6;
  var RUN_PROGRESS_STALL_HARD_SEC = 14;
  var RUN_FINALIZING_STALL_SOFT_SEC = 8;
  var RUN_FINALIZING_STALL_HARD_SEC = 24;
  var OPTIMISTIC_CONVERSATION_TTL_MS = 30 * 60 * 1000;
  var OPTIMISTIC_CONVERSATION_PENDING_EXTENSION_MS = 10 * 60 * 1000;
  var OPTIMISTIC_CONVERSATION_SEEN_GRACE_MS = 2 * 60 * 1000;
  var ACTIVE_CONVERSATION_MISSING_STALE_GRACE_MS = 12 * 1000;
  var ACTIVE_CONVERSATION_MISSING_HARD_MAX_MS = 2 * 60 * 1000;
  var DICTATION_SHORTCUT_TAP_MS = 200;
  var DICTATION_SHORTCUT_HOLD_OPTIONS = [
    { value: "none", label: "None" },
    { value: "alt", label: "Option (Alt)" },
    { value: "meta", label: "Command (Meta)" },
    { value: "shift", label: "Shift" },
    { value: "control", label: "Control" },
    { value: "ctrl-m", label: "Ctrl + M" },
    { value: "space", label: "Space" },
    { value: "backslash", label: "Backslash (\\)" },
    { value: "semicolon", label: "Semicolon (;)" },
    { value: "quote", label: "Quote (')" },
    { value: "f6", label: "F6" },
    { value: "f7", label: "F7" },
    { value: "f8", label: "F8" },
    { value: "f9", label: "F9" },
    { value: "f10", label: "F10" },
    { value: "f13", label: "F13" },
    { value: "f14", label: "F14" },
    { value: "f15", label: "F15" },
    { value: "f16", label: "F16" },
    { value: "f17", label: "F17" },
    { value: "f18", label: "F18" },
    { value: "f19", label: "F19" },
    { value: "mouse-button-4", label: "Mouse Button 4" },
    { value: "mouse-button-5", label: "Mouse Button 5" },
    { value: "mouse-wheel-click", label: "Mouse Wheel Click" }
  ];
  var DICTATION_SHORTCUT_TOGGLE_OPTIONS = [
    { value: "none", label: "None" },
    { value: "capslock", label: "Caps Lock" },
    { value: "backslash", label: "Backslash (\\)" },
    { value: "semicolon", label: "Semicolon (;)" },
    { value: "quote", label: "Quote (')" },
    { value: "f6", label: "F6" },
    { value: "f7", label: "F7" },
    { value: "f8", label: "F8" },
    { value: "f9", label: "F9" },
    { value: "f10", label: "F10" },
    { value: "f13", label: "F13" },
    { value: "f14", label: "F14" },
    { value: "f15", label: "F15" },
    { value: "f16", label: "F16" },
    { value: "f17", label: "F17" },
    { value: "f18", label: "F18" },
    { value: "f19", label: "F19" },
    { value: "mouse-button-4", label: "Mouse Button 4" },
    { value: "mouse-button-5", label: "Mouse Button 5" },
    { value: "mouse-wheel-click", label: "Mouse Wheel Click" }
  ];
  var DICTATION_LANGUAGE_DEFAULT_OPTIONS = [
    { value: "auto", label: "Auto-detect" }
  ];
  var stateGetInFlight = null;
  var stateGetInFlightKey = "";
  var dictationShortcutPressState = {};
  var dictationUiTickTimer = null;
  var dictationWaveMonitorSession = 0;
  var dictationWaveRafId = null;
  var dictationWaveStream = null;
  var dictationWaveAudioContext = null;
  var dictationWaveAnalyser = null;
  var dictationWaveSource = null;
  var dictationWaveData = null;
  var dictationWaveStartPromise = null;
  var dictationWavePollTimer = null;
  var dictationWaveWarmReleaseTimer = null;
  var dictationWaveMicLevel = 0;
  var dictationWaveMicLevelAt = 0;
  var dictationWaveBackendLevel = 0;
  var dictationWaveBackendLevelAt = 0;
  var dictationWaveBackendRecentLevels = [];
  var dictationWaveBackendFloor = 0.02;
  var dictationWaveBackendFloorCalibrating = true;
  var dictationWaveBackendFloorSeedSamples = [];
  var dictationWaveSeenSignal = false;
  var dictationWaveNoiseFloor = 0.02;
  var dictationWaveSignalCeil = 0.16;
  var dictationWaveActivatedAt = 0;
  var dictationWaveLastSampleAt = 0;
  var dictationWaveBarStartAt = 0;
  var dictationWaveBarPeakRaw = 0;
  var dictationWaveBarSumRaw = 0;
  var dictationWaveBarSampleCount = 0;
  var DICTATION_WAVE_BAR_INTERVAL_MS = 84;
  var dictationWaveBackendLastEmitAt = 0;
  var dictationWaveSilencePhase = 0;
  var dictationWavePollInFlight = false;
  var dictationWaveBackendPumpBusy = false;
  var dictationWaveBackendPumpAt = 0;
  var dictationPreparePromise = null;
  var dictationPrepareReadyUntil = 0;
  var dictationPrepareLoopTimer = null;
  var dictatePointerHandledAt = 0;
  var dictateStopPointerHandledAt = 0;
  var dictationShortcutLastToggleAtByTrigger = {};

  if (state.sortMode !== "updated" && state.sortMode !== "created") {
    state.sortMode = "updated";
  }
  if (state.organizeMode !== "project" && state.organizeMode !== "chrono") {
    state.organizeMode = "project";
  }
  if (state.organizeShow !== "all" && state.organizeShow !== "relevant" && state.organizeShow !== "running") {
    state.organizeShow = "all";
  }
  if (state.sidebarSection !== "threads" && state.sidebarSection !== "automations") {
    state.sidebarSection = "threads";
  }
  if (state.lastOpenTarget !== "finder" && state.lastOpenTarget !== "terminal" && state.lastOpenTarget !== "textmate") {
    state.lastOpenTarget = "finder";
  }
  if (state.lastCommitAction !== "commit" && state.lastCommitAction !== "push" && state.lastCommitAction !== "commit-push") {
    state.lastCommitAction = "commit";
  }
  if (
    state.reasoningEffort !== "low" &&
    state.reasoningEffort !== "medium" &&
    state.reasoningEffort !== "high" &&
    state.reasoningEffort !== "extra-high"
  ) {
    state.reasoningEffort = "medium";
  }
  if (
    state.computeBudget !== "auto" &&
    state.computeBudget !== "quick" &&
    state.computeBudget !== "standard" &&
    state.computeBudget !== "long" &&
    state.computeBudget !== "until-complete"
  ) {
    state.computeBudget = "auto";
  }
  if (!/^[a-z0-9_-]+$/.test(String(state.activeTheme || ""))) {
    state.activeTheme = "psionic";
  }
  if (
    state.commandExecMode !== "none" &&
    state.commandExecMode !== "ask" &&
    state.commandExecMode !== "ask-all" &&
    state.commandExecMode !== "ask-some" &&
    state.commandExecMode !== "all"
  ) {
    state.commandExecMode = "ask-some";
  }
  if (state.commandExecMode === "ask") {
    state.commandExecMode = "ask-some";
  }
  if (state.permissionMode === "full-access") {
    state.permissionMode = "default";
  }
  if (
    state.permissionMode !== "default" &&
    state.permissionMode !== "workspace-write" &&
    state.permissionMode !== "read-only"
  ) {
    state.permissionMode = "default";
  }
  state.reflexiveKnowledge = !!state.reflexiveKnowledge;
  state.selfActuation = !!state.selfActuation;
  state.dictationShortcutHold = normalizeDictationShortcut("hold", state.dictationShortcutHold);
  state.dictationShortcutToggle = normalizeDictationShortcut("toggle", state.dictationShortcutToggle);
  state.dictationLanguages = normalizeDictationLanguageOptions(state.dictationLanguages);
  state.dictationLanguage = normalizeDictationLanguageValue(state.dictationLanguage, state.dictationLanguages);
  state.runMode = normalizeRunMode(state.runMode);
  state.assistantModeId = normalizeAssistantModeId(state.assistantModeId);
  state.programmerReviewEnabled = !!state.programmerReviewEnabled;
  if (!isFinite(state.programmerReviewRounds) || state.programmerReviewRounds < 1) {
    state.programmerReviewRounds = 2;
  } else if (state.programmerReviewRounds > 4) {
    state.programmerReviewRounds = 4;
  } else {
    state.programmerReviewRounds = Math.floor(state.programmerReviewRounds);
  }
  if (state.runMode === "instant") {
    state.agentLoopEnabled = false;
    state.reasoningEffort = "low";
  } else if (state.runMode === "chat") {
    state.agentLoopEnabled = false;
    if (state.reasoningEffort === "low") {
      state.reasoningEffort = "medium";
    }
  } else if (state.runMode === "programming") {
    state.agentLoopEnabled = true;
    if (state.reasoningEffort === "low" || state.reasoningEffort === "medium") {
      state.reasoningEffort = "high";
    }
  } else if (state.runMode === "report") {
    state.agentLoopEnabled = true;
    if (state.reasoningEffort === "low" || state.reasoningEffort === "medium") {
      state.reasoningEffort = "high";
    }
  } else if (state.runMode === "text-perfecter") {
    state.agentLoopEnabled = true;
    state.reasoningEffort = "extra-high";
  } else if (state.runMode === "gui-testing") {
    state.agentLoopEnabled = true;
    state.reasoningEffort = "extra-high";
  } else if (state.runMode === "assistant") {
    state.agentLoopEnabled = true;
    state.reasoningEffort = "extra-high";
  }

  var el = {
    shell: document.getElementById("artificer-shell"),
    toolbar: document.querySelector(".toolbar"),
    workspacePanel: document.getElementById("workspace-dropzone"),
    threadsResizer: document.getElementById("threads-resizer"),
    workspaceTree: document.getElementById("workspace-tree"),
    workspaceTreeTitle: document.getElementById("workspace-tree-title"),
    sidebarNavAutomationsItem: document.getElementById("sidebar-nav-automations-item"),
    sidebarNavAutomationsCount: document.getElementById("sidebar-nav-automations-count"),
    addWorkspaceBtn: document.getElementById("add-workspace-btn"),
    organizeBtn: document.getElementById("organize-btn"),
    organizeMenu: document.getElementById("organize-menu"),
    modelStatusBtn: document.getElementById("model-status-btn"),
    settingsBtn: document.getElementById("settings-btn"),
    themePickerBtn: document.getElementById("theme-picker-btn"),
    themePickerMenu: document.getElementById("theme-picker-menu"),
    themePickerList: document.getElementById("theme-picker-list"),
    themeStylesheet: document.getElementById("artificer-theme-stylesheet"),
    modelsPane: document.getElementById("models-pane"),
    modelsPaneResizer: document.getElementById("models-pane-resizer"),
    modelsBox: document.getElementById("models-box"),
    modelsBoxHead: document.getElementById("models-box-head"),
    modelsBoxList: document.getElementById("models-box-list"),

    openMainBtn: document.getElementById("open-main-btn"),
    openMenuBtn: document.getElementById("open-menu-btn"),
    openMenu: document.getElementById("open-menu"),
    commitMainBtn: document.getElementById("commit-main-btn"),
    commitMenuBtn: document.getElementById("commit-menu-btn"),
    commitMenu: document.getElementById("commit-menu"),
    triageToolbarActions: document.getElementById("triage-toolbar-actions"),
    triageCleanupMainBtn: document.getElementById("triage-cleanup-main-btn"),
    triageCleanupMenuBtn: document.getElementById("triage-cleanup-menu-btn"),
    triageCleanupMenu: document.getElementById("triage-cleanup-menu"),
    branchMenuBtn: document.getElementById("branch-menu-btn"),
    branchMenu: document.getElementById("branch-menu"),
    branchMenuList: document.getElementById("branch-menu-list"),
    branchCreateForm: document.getElementById("branch-create-form"),
    branchCreateInput: document.getElementById("branch-create-input"),
    branchCreateSubmit: document.getElementById("branch-create-submit"),
    runActionBtn: document.getElementById("run-action-btn"),
    permissionsMenuBtn: document.getElementById("permissions-menu-btn"),
    permissionsMenu: document.getElementById("permissions-menu"),
    networkToggleBtn: document.getElementById("network-toggle-btn"),
    webToggleBtn: document.getElementById("web-toggle-btn"),
    reflexiveKnowledgeToggleBtn: document.getElementById("reflexive-knowledge-toggle-btn"),
    selfActuationToggleBtn: document.getElementById("self-actuation-toggle-btn"),
    terminalToggleBtn: document.getElementById("terminal-toggle-btn"),
    changesBtn: document.getElementById("changes-btn"),
    contextWindowBtn: document.getElementById("context-window-btn"),
    contextWindowMenu: document.getElementById("context-window-menu"),
    contextWindowBody: document.getElementById("context-window-body"),
    workspacePathWidget: document.getElementById("workspace-path-widget"),

    chatTitle: document.getElementById("chat-title"),
    chatLog: document.getElementById("chat-log"),
    conversationSwitchOverlay: document.getElementById("conversation-switch-overlay"),
    chatJumpBottomBtn: document.getElementById("chat-jump-bottom-btn"),
    composerRow: document.getElementById("composer-row"),
    runForm: document.getElementById("run-form"),
    runPrompt: document.getElementById("run-prompt"),
    attachBtn: document.getElementById("attach-btn"),
    dictateBtn: document.getElementById("dictate-btn"),
    attachmentPicker: document.getElementById("attachment-picker"),
    attachmentStrip: document.getElementById("attachment-strip"),
    modelPickerBtn: document.getElementById("model-picker-btn"),
    modelPickerMenu: document.getElementById("model-picker-menu"),
    modelPickerList: document.getElementById("model-picker-list"),
    runModeBtn: document.getElementById("run-mode-btn"),
    runModeMenu: document.getElementById("run-mode-menu"),
    runModeMoreToggle: document.getElementById("run-mode-more-toggle"),
    runModeMoreList: document.getElementById("run-mode-more-list"),
    agentLoopToggle: document.getElementById("agent-loop-toggle"),
    reasoningMenuBtn: document.getElementById("reasoning-menu-btn"),
    reasoningMenu: document.getElementById("reasoning-menu"),
    computeMenuBtn: document.getElementById("compute-menu-btn"),
    computeMenu: document.getElementById("compute-menu"),
    runTodoMonitor: document.getElementById("run-todo-monitor"),
    runTodoMonitorLabel: document.getElementById("run-todo-monitor-label"),
    runTodoMonitorList: document.getElementById("run-todo-monitor-list"),
    queueTray: document.getElementById("queue-tray"),
    queueTrayList: document.getElementById("queue-tray-list"),
    runTerminalMonitor: document.getElementById("run-terminal-monitor"),
    runTerminalMonitorLabel: document.getElementById("run-terminal-monitor-label"),
    runTerminalMonitorOutput: document.getElementById("run-terminal-monitor-output"),
    runTerminalMonitorStop: document.getElementById("run-terminal-monitor-stop"),
    queueControls: document.getElementById("queue-controls"),
    queueSteerBtn: document.getElementById("queue-steer-btn"),
    queueCancelBtn: document.getElementById("queue-cancel-btn"),
    sendMenu: document.getElementById("send-menu"),
    sendMenuQueueBtn: document.getElementById("send-menu-queue-btn"),
    sendMenuStopBtn: document.getElementById("send-menu-stop-btn"),
    runBtn: document.getElementById("run-btn"),
    dictationMode: document.getElementById("dictation-mode"),
    dictationWave: document.getElementById("dictation-wave"),
    dictationTimer: document.getElementById("dictation-timer"),
    dictationStopBtn: document.getElementById("dictation-stop-btn"),

    diffPanel: document.getElementById("diff-panel"),
    diffResizer: document.getElementById("diff-resizer"),
    diffSummary: document.getElementById("diff-summary"),
    diffView: document.getElementById("diff-view"),
    diffCloseBtn: document.getElementById("diff-close-btn"),

    terminalPanel: document.getElementById("terminal-panel"),
    terminalCwd: document.getElementById("terminal-cwd"),
    terminalOutput: document.getElementById("terminal-output"),
    terminalForm: document.getElementById("terminal-form"),
    terminalInput: document.getElementById("terminal-input"),
    terminalClearBtn: document.getElementById("terminal-clear-btn"),
    terminalCloseBtn: document.getElementById("terminal-close-btn"),

    workspaceModal: document.getElementById("workspace-modal"),
    workspaceModalClose: document.getElementById("workspace-modal-close"),
    workspaceCancelBtn: document.getElementById("workspace-cancel-btn"),
    workspaceForm: document.getElementById("workspace-form"),
    workspacePath: document.getElementById("workspace-path"),
    workspaceName: document.getElementById("workspace-name"),
    workspaceBrowseBtn: document.getElementById("workspace-browse-btn"),
    workspaceDirPicker: document.getElementById("workspace-dir-picker"),
    automationModal: document.getElementById("automation-modal"),
    automationModalTitle: document.getElementById("automation-modal-title"),
    automationModalClose: document.getElementById("automation-modal-close"),
    automationForm: document.getElementById("automation-form"),
    automationName: document.getElementById("automation-name"),
    automationWorkspace: document.getElementById("automation-workspace"),
    automationConversation: document.getElementById("automation-conversation"),
    automationPrompt: document.getElementById("automation-prompt"),
    automationScheduleKind: document.getElementById("automation-schedule-kind"),
    automationScheduleValue: document.getElementById("automation-schedule-value"),
    automationScheduleHint: document.getElementById("automation-schedule-hint"),
    automationEnabled: document.getElementById("automation-enabled"),
    automationAllowSelfReschedule: document.getElementById("automation-allow-self-reschedule"),
    automationNextRun: document.getElementById("automation-next-run"),
    automationSaveBtn: document.getElementById("automation-save-btn"),
    automationCancelBtn: document.getElementById("automation-cancel-btn"),

    commitModal: document.getElementById("commit-modal"),
    commitModalClose: document.getElementById("commit-modal-close"),
    commitBranchLabel: document.getElementById("commit-branch-label"),
    commitChangesLabel: document.getElementById("commit-changes-label"),
    commitIncludeUnstaged: document.getElementById("commit-include-unstaged"),
    commitMessage: document.getElementById("commit-message"),
    commitNextStep: document.getElementById("commit-next-step"),
    commitContinueBtn: document.getElementById("commit-continue-btn"),
    commandApprovalModal: document.getElementById("command-approval-modal"),
    commandApprovalClose: document.getElementById("command-approval-close"),
    commandApprovalText: document.getElementById("command-approval-text"),
    commandApprovalCommand: document.getElementById("command-approval-command"),
    commandApprovalMatchMode: document.getElementById("command-approval-match-mode"),
    commandApprovalPattern: document.getElementById("command-approval-pattern"),
    commandApprovalAllowOnce: document.getElementById("command-approval-allow-once"),
    commandApprovalDenyOnce: document.getElementById("command-approval-deny-once"),
    commandApprovalAllowRemember: document.getElementById("command-approval-allow-remember"),
    commandApprovalDenyRemember: document.getElementById("command-approval-deny-remember"),
    commandApprovalInline: document.getElementById("command-approval-inline"),
    commandApprovalInlineClose: document.getElementById("command-approval-inline-close"),
    commandApprovalInlineText: document.getElementById("command-approval-inline-text"),
    commandApprovalInlineCommand: document.getElementById("command-approval-inline-command"),
    commandApprovalInlineMatchMode: document.getElementById("command-approval-inline-match-mode"),
    commandApprovalInlinePattern: document.getElementById("command-approval-inline-pattern"),
    commandApprovalInlineAllowOnce: document.getElementById("command-approval-inline-allow-once"),
    commandApprovalInlineDenyOnce: document.getElementById("command-approval-inline-deny-once"),
    commandApprovalInlineAllowRemember: document.getElementById("command-approval-inline-allow-remember"),
    commandApprovalInlineDenyRemember: document.getElementById("command-approval-inline-deny-remember"),
    decisionRequestInline: document.getElementById("decision-request-inline"),
    decisionRequestInlineClose: document.getElementById("decision-request-inline-close"),
    decisionRequestInlineQuestion: document.getElementById("decision-request-inline-question"),
    decisionRequestForm: document.getElementById("decision-request-form"),
    decisionRequestOptions: document.getElementById("decision-request-options"),
    decisionRequestOtherWrap: document.getElementById("decision-request-other-wrap"),
    decisionRequestOtherInput: document.getElementById("decision-request-other-input"),
    decisionRequestSubmit: document.getElementById("decision-request-submit"),

    runActionModal: document.getElementById("run-action-modal"),
    runActionClose: document.getElementById("run-action-close"),
    runActionForm: document.getElementById("run-action-form"),
    runActionCommand: document.getElementById("run-action-command"),

    settingsModal: document.getElementById("settings-modal"),
    settingsCloseBtn: document.getElementById("settings-close-btn"),
    gitStatus: document.getElementById("git-status"),
    sshKeyStatus: document.getElementById("ssh-key-status"),
    llmUseGpuToggle: document.getElementById("llm-use-gpu-toggle"),
    selfImproveObjectiveInput: document.getElementById("self-improve-objective"),
    selfImproveCompetitionToggle: document.getElementById("self-improve-competition-toggle"),
    selfImproveModelSelect: document.getElementById("self-improve-model-select"),
    selfImproveChallengerModelSelect: document.getElementById("self-improve-challenger-model-select"),
    selfImproveSourcePapers: document.getElementById("self-improve-source-papers"),
    selfImproveSourceWeb: document.getElementById("self-improve-source-web"),
    selfImproveSourceRuntime: document.getElementById("self-improve-source-runtime"),
    selfImproveSourceRepo: document.getElementById("self-improve-source-repo"),
    selfImproveSourcePlatform: document.getElementById("self-improve-source-platform"),
    selfImproveRunBtn: document.getElementById("self-improve-run-btn"),
    selfImproveStatus: document.getElementById("self-improve-status"),
    selfImproveSummary: document.getElementById("self-improve-summary"),
    selfImprovePluginsList: document.getElementById("self-improve-plugins-list"),
    githubUsername: document.getElementById("github-username"),
    sshEmail: document.getElementById("ssh-email"),
    refreshAuthBtn: document.getElementById("refresh-auth-btn"),
    installDictationBtn: document.getElementById("install-dictation-btn"),
    dictationInstallStatus: document.getElementById("dictation-install-status"),
    automationDaemonToggle: document.getElementById("automation-daemon-toggle"),
    automationDaemonStatus: document.getElementById("automation-daemon-status"),
    automationDaemonRefreshBtn: document.getElementById("automation-daemon-refresh-btn"),
    automationDaemonRunNowBtn: document.getElementById("automation-daemon-run-now-btn"),
    dictationShortcutRow: document.getElementById("dictation-shortcut-row"),
    dictationHoldShortcut: document.getElementById("dictation-hold-shortcut"),
    dictationToggleShortcut: document.getElementById("dictation-toggle-shortcut"),
    dictationLanguageRow: document.getElementById("dictation-language-row"),
    dictationLanguageSelect: document.getElementById("dictation-language-select"),
    dictationPrewarmRow: document.getElementById("dictation-prewarm-row"),
    dictationPrewarmToggle: document.getElementById("dictation-prewarm-toggle"),
    dictationPrewarmHint: document.getElementById("dictation-prewarm-hint"),
    programmerReviewToggle: document.getElementById("programmer-review-toggle"),
    programmerReviewRounds: document.getElementById("programmer-review-rounds"),
    programmerReviewHint: document.getElementById("programmer-review-hint"),
    generateSshBtn: document.getElementById("generate-ssh-btn"),
    chooseSshBtn: document.getElementById("choose-ssh-btn"),
    clearSshBtn: document.getElementById("clear-ssh-btn"),
    selectedSshPath: document.getElementById("selected-ssh-path"),
    sshPubOutput: document.getElementById("ssh-pub-output"),
    commandRulesWorkspace: document.getElementById("command-rules-workspace"),
    commandRulesStatus: document.getElementById("command-rules-status"),
    commandRulesGlobalList: document.getElementById("command-rules-global-list"),
    commandRulesList: document.getElementById("command-rules-list"),
    modeRuntimeTickBtn: document.getElementById("mode-runtime-tick-btn"),
    modeRuntimeSummary: document.getElementById("mode-runtime-summary"),
    modeRuntimePanels: document.getElementById("mode-runtime-panels"),
    modeRuntimeModes: document.getElementById("mode-runtime-modes"),
    modeRuntimeSkills: document.getElementById("mode-runtime-skills"),
    modeRuntimeFailureTaxonomy: document.getElementById("mode-runtime-failure-taxonomy"),
    modeRuntimeImprovementProposals: document.getElementById("mode-runtime-improvement-proposals"),
    modeRuntimeControllerVariants: document.getElementById("mode-runtime-controller-variants"),
    modeRuntimeQualityScorecard: document.getElementById("mode-runtime-quality-scorecard"),
    assistantModeSelect: document.getElementById("assistant-mode-select"),
    assistantModeApplyBtn: document.getElementById("assistant-mode-apply-btn"),
    modeRuntimeSkillInvokeForm: document.getElementById("mode-runtime-skill-invoke-form"),
    modeRuntimeSkillSelect: document.getElementById("mode-runtime-skill-select"),
    modeRuntimeSkillMode: document.getElementById("mode-runtime-skill-mode"),
    modeRuntimeSkillCapabilities: document.getElementById("mode-runtime-skill-capabilities"),
    modeRuntimeSkillInput: document.getElementById("mode-runtime-skill-input"),
    modeRuntimeSkillInvokeBtn: document.getElementById("mode-runtime-skill-invoke-btn"),
    modeRuntimeSkillResult: document.getElementById("mode-runtime-skill-result"),
    modeRuntimeSkillCreateForm: document.getElementById("mode-runtime-skill-create-form"),
    modeRuntimeSkillCreateId: document.getElementById("mode-runtime-skill-create-id"),
    modeRuntimeSkillCreateName: document.getElementById("mode-runtime-skill-create-name"),
    modeRuntimeSkillCreateTrigger: document.getElementById("mode-runtime-skill-create-trigger"),
    modeRuntimeSkillCreateCapabilities: document.getElementById("mode-runtime-skill-create-capabilities"),
    modeRuntimeSkillCreateDescription: document.getElementById("mode-runtime-skill-create-description"),
    modeRuntimeSkillCreateBtn: document.getElementById("mode-runtime-skill-create-btn"),
    modeRuntimeSkillInstallForm: document.getElementById("mode-runtime-skill-install-form"),
    modeRuntimeSkillInstallSource: document.getElementById("mode-runtime-skill-install-source"),
    modeRuntimeSkillInstallId: document.getElementById("mode-runtime-skill-install-id"),
    modeRuntimeSkillInstallReplace: document.getElementById("mode-runtime-skill-install-replace"),
    modeRuntimeSkillInstallBtn: document.getElementById("mode-runtime-skill-install-btn"),
    multi_agentModal: document.getElementById("multi_agent-modal"),
    multi_agentModalClose: document.getElementById("multi_agent-modal-close"),
    multi_agentProjectLabel: document.getElementById("multi_agent-project-label"),
    multi_agentStatus: document.getElementById("multi_agent-status"),
    multi_agentCharter: document.getElementById("multi_agent-charter"),
    multi_agentRolesHint: document.getElementById("multi_agent-roles-hint"),
    multi_agentToggleAllResidents: document.getElementById("multi_agent-toggle-all-residents"),
    multi_agentSectionDilemma: document.getElementById("multi_agent-section-dilemma"),
    multi_agentSectionAmendments: document.getElementById("multi_agent-section-amendments"),
    multi_agentSectionCommitments: document.getElementById("multi_agent-section-commitments"),
    multi_agentSectionPolicies: document.getElementById("multi_agent-section-policies"),
    multi_agentToggleContextSharing: document.getElementById("multi_agent-toggle-context-sharing"),
    multi_agentToggleAmendments: document.getElementById("multi_agent-toggle-amendments"),
    multi_agentToggleCommitments: document.getElementById("multi_agent-toggle-commitments"),
    multi_agentTogglePolicies: document.getElementById("multi_agent-toggle-policies"),
    multi_agentAmendmentsSummary: document.getElementById("multi_agent-amendments-summary"),
    multi_agentInterpretationSummary: document.getElementById("multi_agent-interpretation-summary"),
    multi_agentCommitmentsSummary: document.getElementById("multi_agent-commitments-summary"),
    multi_agentPoliciesSummary: document.getElementById("multi_agent-policies-summary"),
    multi_agentAmendmentsList: document.getElementById("multi_agent-amendments-list"),
    multi_agentResidentsList: document.getElementById("multi_agent-residents-list"),
    multi_agentPoliciesList: document.getElementById("multi_agent-policies-list"),
    multi_agentCommitmentsList: document.getElementById("multi_agent-commitments-list"),
    multi_agentInterpretationList: document.getElementById("multi_agent-interpretation-list")
  };

  if (el.modelStatusBtn) {
    el.modelStatusBtn.textContent = "Loading...";
  }
  if (el.githubUsername) {
    el.githubUsername.value = state.githubUsername || "";
  }
  if (el.llmUseGpuToggle) {
    el.llmUseGpuToggle.checked = !!state.llmUseGpu;
  }

  var menuById = {
    "organize-menu": el.organizeMenu,
    "open-menu": el.openMenu,
    "commit-menu": el.commitMenu,
    "triage-cleanup-menu": el.triageCleanupMenu,
    "theme-picker-menu": el.themePickerMenu,
    "branch-menu": el.branchMenu,
    "permissions-menu": el.permissionsMenu,
    "model-picker-menu": el.modelPickerMenu,
    "run-mode-menu": el.runModeMenu,
    "reasoning-menu": el.reasoningMenu,
    "compute-menu": el.computeMenu,
    "send-menu": el.sendMenu,
    "context-window-menu": el.contextWindowMenu,
    "models-pane": el.modelsPane
  };

  function escHtml(text) {
    return String(text || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;");
  }

  function escAttr(text) {
    return escHtml(text)
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#39;");
  }

  function trim(text) {
    return String(text || "").replace(/^\s+|\s+$/g, "");
  }

  function copyTextToClipboard(text) {
    var value = String(text || "");
    if (!value) {
      return Promise.resolve(false);
    }
    if (navigator && navigator.clipboard && navigator.clipboard.writeText) {
      return navigator.clipboard.writeText(value).then(function () {
        return true;
      }).catch(function () {
        return false;
      });
    }
    try {
      var temp = document.createElement("textarea");
      temp.value = value;
      temp.setAttribute("readonly", "readonly");
      temp.style.position = "absolute";
      temp.style.left = "-9999px";
      document.body.appendChild(temp);
      temp.select();
      var ok = document.execCommand("copy");
      document.body.removeChild(temp);
      return Promise.resolve(!!ok);
    } catch (_error) {
      return Promise.resolve(false);
    }
  }

  function ensureTooltipEl() {
    if (tooltipEl && document.body && document.body.contains(tooltipEl)) {
      return tooltipEl;
    }
    tooltipEl = document.createElement("div");
    tooltipEl.className = "ui-tooltip";
    tooltipEl.setAttribute("role", "tooltip");
    tooltipEl.setAttribute("aria-hidden", "true");
    document.body.appendChild(tooltipEl);
    return tooltipEl;
  }

  function ensureNoticeEl() {
    if (noticeEl && document.body && document.body.contains(noticeEl)) {
      return noticeEl;
    }
    noticeEl = document.createElement("div");
    noticeEl.className = "ui-notice";
    noticeEl.setAttribute("aria-live", "polite");
    noticeEl.setAttribute("aria-atomic", "true");
    document.body.appendChild(noticeEl);
    return noticeEl;
  }

  function showTransientNotice(message, options) {
    var text = trim(message);
    if (!text) {
      return;
    }
    var opts = options || {};
    var node = ensureNoticeEl();
    if (noticeHideTimer) {
      clearTimeout(noticeHideTimer);
      noticeHideTimer = null;
    }
    node.classList.remove("transparent");
    if (opts.transparent) {
      node.classList.add("transparent");
    }
    node.textContent = text;
    node.classList.add("show");
    noticeHideTimer = setTimeout(function () {
      node.classList.remove("show");
      node.classList.remove("transparent");
      noticeHideTimer = null;
    }, 1350);
  }

  function tooltipTextFor(node) {
    if (!node || typeof node.getAttribute !== "function") {
      return "";
    }
    if (node.classList && node.classList.contains("workspace-menu-trigger")) {
      return "";
    }
    var workspaceRow = node.closest && node.closest(".workspace-row[data-workspace-id]");
    if (workspaceRow) {
      var workspaceId = String(workspaceRow.getAttribute("data-workspace-id") || "");
      if (workspaceId && workspaceId === String(state.openWorkspaceMenuWorkspaceId || "")) {
        return "";
      }
    }
    var anchor = node.closest && node.closest(".menu-anchor");
    if (anchor) {
      var openMenu = anchor.querySelector(".floating-menu:not(.hidden), .models-box:not(.hidden)");
      if (openMenu) {
        return "";
      }
    }
    return trim(node.getAttribute("data-tooltip") || "");
  }

  function tooltipPreferredPlacement(target) {
    if (!target || !target.getBoundingClientRect) {
      return "bottom";
    }
    if (target.closest && target.closest(".toolbar")) {
      return "top";
    }
    if (target.closest && target.closest(".composer-row, .session-row, .workspace-sidebar-footer")) {
      return "bottom";
    }
    var rect = target.getBoundingClientRect();
    var viewportHeight = window.innerHeight || document.documentElement.clientHeight || 768;
    var spaceAbove = rect.top;
    var spaceBelow = viewportHeight - rect.bottom;
    return spaceBelow >= spaceAbove ? "bottom" : "top";
  }

  function positionTooltip(target) {
    if (!tooltipEl || !target) {
      return;
    }
    var rect = target.getBoundingClientRect();
    var tipRect = tooltipEl.getBoundingClientRect();
    var viewportWidth = window.innerWidth || document.documentElement.clientWidth || 1024;
    var viewportHeight = window.innerHeight || document.documentElement.clientHeight || 768;
    var left = rect.left + (rect.width - tipRect.width) / 2;
    var placement = tooltipPreferredPlacement(target);
    var top = placement === "top" ? rect.top - tipRect.height - 8 : rect.bottom + 8;

    if (left < 8) {
      left = 8;
    }
    if (left + tipRect.width > viewportWidth - 8) {
      left = Math.max(8, viewportWidth - tipRect.width - 8);
    }
    if (top < 8 || top + tipRect.height > viewportHeight - 8) {
      if (placement === "top") {
        top = rect.bottom + 8;
      } else {
        top = rect.top - tipRect.height - 8;
      }
      if (top < 8) {
        top = 8;
      }
      if (top + tipRect.height > viewportHeight - 8) {
        top = Math.max(8, viewportHeight - tipRect.height - 8);
      }
    }

    tooltipEl.style.left = Math.round(left) + "px";
    tooltipEl.style.top = Math.round(top) + "px";
  }

  function showTooltipFor(target) {
    var text = tooltipTextFor(target);
    if (!text) {
      return;
    }
    var tip = ensureTooltipEl();
    tooltipTarget = target;
    tip.classList.remove("show");
    tip.textContent = text;
    tip.setAttribute("aria-hidden", "false");
    tip.style.left = "-9999px";
    tip.style.top = "-9999px";
    positionTooltip(target);
    tip.classList.add("show");
  }

  function clearTooltipShowTimer() {
    if (tooltipShowTimer) {
      clearTimeout(tooltipShowTimer);
      tooltipShowTimer = null;
    }
    tooltipPendingTarget = null;
  }

  function scheduleTooltipFor(target) {
    var text = tooltipTextFor(target);
    if (!text) {
      clearTooltipShowTimer();
      hideTooltip();
      return;
    }
    clearTooltipShowTimer();
    tooltipPendingTarget = target;
    tooltipShowTimer = setTimeout(function () {
      if (!tooltipPendingTarget || tooltipPendingTarget !== target) {
        return;
      }
      showTooltipFor(target);
      tooltipShowTimer = null;
      tooltipPendingTarget = null;
    }, TOOLTIP_DELAY_MS);
  }

  function hideTooltip() {
    clearTooltipShowTimer();
    tooltipTarget = null;
    if (!tooltipEl) {
      return;
    }
    tooltipEl.classList.remove("show");
    tooltipEl.setAttribute("aria-hidden", "true");
  }

  function hydrateTooltips() {
    var nodes = document.querySelectorAll("button, [role='button'], [aria-label], [title]");
    for (var i = 0; i < nodes.length; i += 1) {
      var node = nodes[i];
      var tip = trim(node.getAttribute("data-tooltip") || "");
      var title = trim(node.getAttribute("title") || "");
      var label = trim(node.getAttribute("aria-label") || "");
      if (!tip) {
        if (title) {
          tip = title;
        } else if (label) {
          tip = label;
        }
      }
      if (tip) {
        node.setAttribute("data-tooltip", tip);
      }
      if (node.hasAttribute("title")) {
        node.removeAttribute("title");
      }
    }
  }

  function waitMs(ms) {
    return new Promise(function (resolve) {
      setTimeout(resolve, ms);
    });
  }

  function isRetriableRequestError(error) {
    var message = "";
    if (error && error.message) {
      message = String(error.message || "");
    } else {
      message = String(error || "");
    }
    var lower = message.toLowerCase();
    if (!lower) {
      return false;
    }
    return (
      lower.indexOf("failed to fetch") >= 0 ||
      lower.indexOf("networkerror") >= 0 ||
      lower.indexOf("gateway timeout") >= 0 ||
      lower.indexOf("gateway time-out") >= 0 ||
      lower.indexOf("timed out") >= 0 ||
      lower.indexOf("json.parse") >= 0 ||
      (lower.indexOf("json") >= 0 && lower.indexOf("unexpected") >= 0)
    );
  }

  function runWithRetry(taskFn, attempts, delayMs) {
    var maxAttempts = Number(attempts || 1);
    if (!isFinite(maxAttempts) || maxAttempts < 1) {
      maxAttempts = 1;
    }

    function attempt(index) {
      return Promise.resolve()
        .then(taskFn)
        .catch(function (error) {
          if (index >= maxAttempts - 1 || !isRetriableRequestError(error)) {
            throw error;
          }
          return waitMs(delayMs).then(function () {
            return attempt(index + 1);
          });
        });
    }

    return attempt(0);
  }

  function dirname(pathText) {
    var clean = trim(pathText).replace(/[\\/]+$/, "");
    if (!clean) {
      return "";
    }
    var slash = Math.max(clean.lastIndexOf("/"), clean.lastIndexOf("\\"));
    if (slash <= 0) {
      return clean;
    }
    return clean.slice(0, slash);
  }

  function stripTrailingSlashes(pathText) {
    return String(pathText || "").replace(/[\\/]+$/, "");
  }

  function normalizeSlashes(pathText) {
    return String(pathText || "").replace(/\\/g, "/");
  }

  function denormalizeSlashes(pathText, preferBackslashes) {
    if (preferBackslashes) {
      return String(pathText || "").replace(/\//g, "\\");
    }
    return pathText;
  }

  function deriveDropRootFromFile(file) {
    if (!file || !file.path) {
      return "";
    }

    var filePath = String(file.path);
    var relative = String(file.webkitRelativePath || "");
    if (!relative) {
      return dirname(filePath);
    }

    var normalizedFile = normalizeSlashes(filePath);
    var normalizedRelative = normalizeSlashes(relative).replace(/^\/+/, "");
    if (!normalizedRelative) {
      return dirname(filePath);
    }

    if (normalizedFile.slice(-normalizedRelative.length) !== normalizedRelative) {
      return dirname(filePath);
    }

    var base = normalizedFile.slice(0, normalizedFile.length - normalizedRelative.length);
    var topFolder = normalizedRelative.split("/")[0] || "";
    var root = stripTrailingSlashes(base + topFolder);
    if (!root) {
      return dirname(filePath);
    }

    return denormalizeSlashes(root, filePath.indexOf("\\") >= 0);
  }

  function parseDownloadUrlPath(downloadUrlText) {
    var text = trim(downloadUrlText);
    if (!text) {
      return "";
    }
    var parts = text.split(":");
    if (parts.length < 3) {
      return "";
    }
    var candidate = parts.slice(2).join(":");
    return decodeFileUri(candidate);
  }

  function decodeFileUri(uri) {
    var text = trim(uri);
    if (!/^file:\/\//i.test(text)) {
      return "";
    }
    try {
      var parsed = new URL(text);
      var path = decodeURIComponent(parsed.pathname || "");
      if (/^\/[A-Za-z]:/.test(path)) {
        path = path.slice(1);
      }
      return path;
    } catch (_err) {
      return "";
    }
  }

  function looksLikeAbsolutePath(text) {
    return /^\/.+/.test(text) || /^[A-Za-z]:[\\/].+/.test(text);
  }

  function extractPathFromText(text) {
    var lines = String(text || "").split(/\r?\n/);
    for (var i = 0; i < lines.length; i += 1) {
      var line = trim(lines[i]);
      if (!line) {
        continue;
      }
      var fromUri = decodeFileUri(line);
      if (fromUri) {
        return fromUri;
      }
      if (looksLikeAbsolutePath(line)) {
        return line;
      }
    }
    return "";
  }

  function extractPathFromDataTransfer(dataTransfer) {
    if (!dataTransfer) {
      return "";
    }

    var uriList = dataTransfer.getData("text/uri-list");
    if (uriList) {
      var uriPath = extractPathFromText(uriList);
      if (uriPath) {
        return uriPath;
      }
    }

    var plain = dataTransfer.getData("text/plain");
    if (plain) {
      var plainPath = extractPathFromText(plain);
      if (plainPath) {
        return plainPath;
      }
    }

    var mozUrl = dataTransfer.getData("text/x-moz-url");
    if (mozUrl) {
      var mozPath = extractPathFromText(mozUrl);
      if (mozPath) {
        return mozPath;
      }
    }

    var downloadUrl = dataTransfer.getData("DownloadURL");
    if (downloadUrl) {
      var downloadPath = parseDownloadUrlPath(downloadUrl);
      if (downloadPath) {
        return downloadPath;
      }
    }

    if (dataTransfer.files && dataTransfer.files.length > 0) {
      for (var i = 0; i < dataTransfer.files.length; i += 1) {
        var file = dataTransfer.files[i];
        if (!file) {
          continue;
        }
        var dropRoot = deriveDropRootFromFile(file);
        if (dropRoot) {
          return dropRoot;
        }
        if (file.path) {
          return file.path;
        }
      }
    }

    if (dataTransfer.items && dataTransfer.items.length > 0) {
      for (var j = 0; j < dataTransfer.items.length; j += 1) {
        var item = dataTransfer.items[j];
        if (!item) {
          continue;
        }
        if (item.webkitGetAsEntry) {
          var entry = item.webkitGetAsEntry();
          if (entry && entry.fullPath && looksLikeAbsolutePath(entry.fullPath)) {
            return entry.fullPath;
          }
        }
        var maybeFile = item.getAsFile && item.getAsFile();
        if (maybeFile) {
          var maybeRoot = deriveDropRootFromFile(maybeFile);
          if (maybeRoot) {
            return maybeRoot;
          }
        }
        if (maybeFile && maybeFile.path) {
          return maybeFile.path;
        }
      }
    }

    return "";
  }

  function humanizeModelToken(token) {
    var clean = String(token || "").replace(/[-_]+/g, " ").trim();
    if (!clean) {
      return "Model";
    }

    return clean
      .split(/\s+/)
      .map(function (word) {
        if (!word) {
          return "";
        }
        return word.charAt(0).toUpperCase() + word.slice(1);
      })
      .join(" ");
  }

  function parseModelDisplay(modelName) {
    var raw = trim(modelName);
    if (!raw) {
      return { primary: "Model", meta: "", raw: "" };
    }

    var primaryPart = raw;
    var secondary = "";
    var colon = raw.indexOf(":");
    if (colon >= 0) {
      primaryPart = raw.slice(0, colon);
      secondary = trim(raw.slice(colon + 1));
    }

    var versionPart = "";
    var versionMatch = primaryPart.match(/^(.*?)(\d+(?:\.\d+)*)$/);
    var baseName = primaryPart;
    if (versionMatch && versionMatch[1]) {
      baseName = versionMatch[1];
      versionPart = "v" + versionMatch[2];
    }

    var primary = humanizeModelToken(baseName || primaryPart);
    var metaParts = [];
    if (versionPart) {
      metaParts.push(versionPart);
    }
    if (secondary) {
      metaParts.push(secondary);
    }

    return {
      primary: primary,
      meta: metaParts.join(" / "),
      raw: raw
    };
  }

  var textAttachmentExtensions = {
    txt: 1,
    md: 1,
    markdown: 1,
    rst: 1,
    log: 1,
    csv: 1,
    tsv: 1,
    json: 1,
    xml: 1,
    yaml: 1,
    yml: 1,
    toml: 1,
    ini: 1,
    conf: 1,
    cfg: 1,
    env: 1,
    sh: 1,
    bash: 1,
    zsh: 1,
    fish: 1,
    py: 1,
    js: 1,
    jsx: 1,
    ts: 1,
    tsx: 1,
    c: 1,
    h: 1,
    cpp: 1,
    cc: 1,
    cxx: 1,
    hpp: 1,
    java: 1,
    go: 1,
    rs: 1,
    php: 1,
    rb: 1,
    swift: 1,
    kt: 1,
    scala: 1,
    sql: 1,
    html: 1,
    htm: 1,
    css: 1,
    scss: 1,
    less: 1,
    vue: 1,
    svelte: 1,
    gradle: 1,
    dockerfile: 1,
    makefile: 1
  };

  var attachmentAcceptValue = [
    "image/*",
    "text/*",
    "application/pdf",
    ".md,.markdown,.txt,.rst,.log,.csv,.tsv",
    ".json,.yaml,.yml,.toml,.ini,.conf,.cfg,.env",
    ".sh,.bash,.zsh,.fish",
