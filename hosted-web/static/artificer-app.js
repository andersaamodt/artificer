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

    var clean = {};
    var keys = Object.keys(parsed);
    for (var i = 0; i < keys.length; i += 1) {
      var key = keys[i];
      clean[key] = parseSeenUpdatedValue(parsed[key]);
    }

    return { map: clean, hasSaved: true };
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
    try {
      window.localStorage.setItem(workspaceOrderStorageKey, JSON.stringify(normalizeOrderedIdList(orderIds)));
    } catch (_err) {
      return;
    }
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
      return;
    }
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
    for (var k = 0; k < keys.length; k += 1) {
      var key = String(keys[k] || "");
      if (!known[key]) {
        delete state.runEventsByConversation[key];
        changed = true;
      }
    }
    if (changed) {
      persistRunEventsSoon();
    }
  }

  function pushRunEvent(conversationId, eventData) {
    if (!conversationId) {
      return null;
    }

    if (!state.runEventsByConversation[conversationId]) {
      state.runEventsByConversation[conversationId] = [];
    }

    var event = eventData || {};
    if (!event.id) {
      event.id = String(Date.now()) + "-" + String(Math.floor(Math.random() * 999999));
    }

    state.runEventsByConversation[conversationId].push(event);
    if (state.runEventsByConversation[conversationId].length > 22) {
      state.runEventsByConversation[conversationId].shift();
    }
    persistRunEventsSoon();

    return event;
  }

  function formatRunCommands(commands) {
    if (!commands || commands.length === 0) {
      return "<p class='empty-state'>No commands were proposed or executed.</p>";
    }

    var html = "";
    for (var i = 0; i < commands.length; i += 1) {
      var item = commands[i] || {};
      var status = item.status || "unknown";
      html += "<div class='run-command'>";
      html += "<div class='run-command-head'><code>" + escHtml(item.command || "") + "</code><span class='badge " + escHtml(status) + "'>" + escHtml(status) + "</span></div>";
      html += "<pre class='run-code-block run-command-output'>" + escHtml(item.output || "") + "</pre>";
      html += "</div>";
    }
    return html;
  }

  function runTraceAttemptCount(event) {
    var combined = trim(String((event && event.failures) || "")) + "\n" + trim(String((event && event.session_log) || ""));
    if (!trim(combined)) {
      return 0;
    }
    var matches = combined.match(/^##\s+/gm);
    return matches ? matches.length : 0;
  }

  function runDetailsShouldBeOpen(eventId) {
    var key = String(eventId || "");
    if (!key) {
      return false;
    }
    return !!state.runDetailsOpenByEventId[key];
  }

  function formatDurationLabel(totalSeconds) {
    var seconds = Number(totalSeconds || 0);
    if (!isFinite(seconds) || seconds < 0) {
      seconds = 0;
    }
    seconds = Math.floor(seconds);
    var hours = Math.floor(seconds / 3600);
    var minutes = Math.floor((seconds % 3600) / 60);
    var remaining = seconds % 60;
    if (hours > 0) {
      return String(hours) + "h " + String(minutes) + "m " + String(remaining) + "s";
    }
    if (minutes > 0) {
      return String(minutes) + "m " + String(remaining) + "s";
    }
    return String(remaining) + "s";
  }

  function thoughtDurationLabel(startedAt, finishedAt) {
    var startedMs = Date.parse(startedAt || "");
    var endedMs = Date.parse(finishedAt || "");
    if (!isFinite(startedMs) || startedMs <= 0) {
      return "";
    }
    if (!isFinite(endedMs) || endedMs <= 0 || endedMs < startedMs) {
      endedMs = Date.now();
    }
    var totalSeconds = Math.max(0, Math.floor((endedMs - startedMs) / 1000));
    return formatDurationLabel(totalSeconds);
  }

  function runDurationSeconds(startedAt, finishedAt) {
    var startedMs = Date.parse(startedAt || "");
    var endedMs = Date.parse(finishedAt || "");
    if (!isFinite(startedMs) || startedMs <= 0) {
      return 0;
    }
    if (!isFinite(endedMs) || endedMs <= 0 || endedMs < startedMs) {
      endedMs = Date.now();
    }
    return Math.max(0, Math.floor((endedMs - startedMs) / 1000));
  }

  function runTraceReviewRoundCountFromText(rawText) {
    var text = normalizeRunNarrativeText(rawText);
    if (!text) {
      return 0;
    }
    var pattern = /code review round\s+(\d+)\s*\/\s*(\d+)/ig;
    var seen = {};
    var count = 0;
    var match = null;
    while ((match = pattern.exec(text)) !== null) {
      var roundIndex = Number(match[1] || 0);
      if (!isFinite(roundIndex) || roundIndex < 1) {
        continue;
      }
      var roundKey = String(Math.floor(roundIndex));
      if (Object.prototype.hasOwnProperty.call(seen, roundKey)) {
        continue;
      }
      seen[roundKey] = true;
      count += 1;
    }
    return count;
  }

  function synthesizeRunTimelineEntries(event) {
    var entries = [];
    var seen = {};

    function pushEntry(timeLabel, textLabel) {
      var text = trim(String(textLabel || ""));
      if (!text) {
        return;
      }
      text = text.replace(/\s+/g, " ");
      var key = text.toLowerCase();
      if (Object.prototype.hasOwnProperty.call(seen, key)) {
        return;
      }
      seen[key] = true;
      entries.push({
        time: trim(String(timeLabel || "")),
        text: text
      });
    }

    var commands = Array.isArray(event && event.commands) ? event.commands : [];
    for (var i = 0; i < commands.length; i += 1) {
      var command = commands[i] || {};
      var cmdText = trim(String(command.command || ""));
      if (!cmdText) {
        continue;
      }
      var statusText = trim(String(command.status || ""));
      var line = humanizeRunCommand(cmdText);
      if (statusText && statusText !== "ok") {
        line += " (" + statusText + ")";
      }
      pushEntry("step", line);
      if (statusText && statusText !== "ok") {
        var issueLine = trim(String(command.output || "")).split(/\r?\n/)[0] || "";
        issueLine = trim(issueLine);
        if (issueLine) {
          pushEntry("step", "Issue: " + issueLine);
        }
      }
      if (entries.length >= 120) {
        return entries;
      }
    }

    var sessionText = normalizeRunNarrativeText(event && event.session_log);
    if (sessionText) {
      var sessionLines = sessionText.split(/\n+/);
      for (var j = 0; j < sessionLines.length; j += 1) {
        var sessionLine = trim(sessionLines[j] || "");
        if (!sessionLine) {
          continue;
        }
        if (!/^(Checkpoint:|Transition:|Reason:|Action:|Error:|Next Attempt:|Assumption:|Current mode:|Command:|Status:)/i.test(sessionLine)) {
          continue;
        }
        if (sessionLine.length > 220) {
          sessionLine = sessionLine.slice(0, 217) + "...";
        }
        pushEntry("step", sessionLine);
        if (entries.length >= 120) {
          return entries;
        }
      }
    }

    var planText = normalizeRunNarrativeText(event && event.plan);
    if (planText) {
      var nextActionMatch = planText.match(/Next Action:\s*([^\n]+)/i);
      if (nextActionMatch && trim(nextActionMatch[1] || "")) {
        pushEntry("step", "Planned next action: " + trim(nextActionMatch[1] || ""));
      }
      var completionMatch = planText.match(/Completion Criteria:\s*([^\n]+)/i);
      if (completionMatch && trim(completionMatch[1] || "")) {
        pushEntry("step", "Completion criteria: " + trim(completionMatch[1] || ""));
      }
    }

    return entries;
  }

  function runTimelineEntries(event) {
    var streamEntries = splitRunStreamEntries(event && event.stream_text);
    if (streamEntries.length) {
      return streamEntries;
    }
    return synthesizeRunTimelineEntries(event);
  }

  function runTraceStepCount(event) {
    return runTimelineEntries(event).length;
  }

  function runTraceReviewRoundCount(event) {
    if (!event) {
      return 0;
    }
    var combined = trim(String(event.stream_text || "")) + "\n" + trim(String(event.session_log || ""));
    return runTraceReviewRoundCountFromText(combined);
  }

  function isOrchestrationRunStep(text) {
    var lower = String(text || "").toLowerCase();
    if (!lower) {
      return false;
    }
    if (/^run started\.?$/.test(lower)) {
      return true;
    }
    if (/^run mode:/.test(lower)) {
      return true;
    }
    if (/^run orchestration initialized\.?$/.test(lower)) {
      return true;
    }
    if (/^initial checkpoints seeded\.?$/.test(lower)) {
      return true;
    }
    if (/^run time budget:/.test(lower)) {
      return true;
    }
    if (/^requesting model output\.?$/.test(lower)) {
      return true;
    }
    if (/^context compacted for model window/.test(lower)) {
      return true;
    }
    if (/^current mode:/.test(lower)) {
      return true;
    }
    if (/^iteration \d+ started\.?$/.test(lower)) {
      return true;
    }
    if (/^step \d+ controller call started/.test(lower)) {
      return true;
    }
    if (/^step \d+ controller prompt assembled/.test(lower)) {
      return true;
    }
    if (/^step \d+ controller response captured/.test(lower)) {
      return true;
    }
    if (/^step \d+ control sections parsed/.test(lower)) {
      return true;
    }
    if (/^step \d+ decision checkpoint: no user decision required/.test(lower)) {
      return true;
    }
    if (/^step \d+ executing (investigate|design|verify) command batch/.test(lower)) {
      return true;
    }
    if (/^step \d+ command \d+ started:/.test(lower)) {
      return true;
    }
    if (/^step \d+ command \d+ status:/.test(lower)) {
      return true;
    }
    if (/^step \d+ completion check:/.test(lower)) {
      return true;
    }
    if (/^step \d+ confidence updated:/.test(lower)) {
      return true;
    }
    if (/^final response prepared for delivery/.test(lower)) {
      return true;
    }
    if (/^run artifacts captured \(state, failures, trace\)/.test(lower)) {
      return true;
    }
    if (/^run finalized with status:/.test(lower)) {
      return true;
    }
    if (/^quick response mode selected\.?$/.test(lower)) {
      return true;
    }
    if (/^explicit skill tags detected:/.test(lower)) {
      return true;
    }
    if (/^invoking explicit skill:/.test(lower)) {
      return true;
    }
    if (/^skill [^:]+ (completed with status:|could not be applied:)/.test(lower)) {
      return true;
    }
    if (/^inline mode directive detected:/.test(lower)) {
      return true;
    }
    if (/^queue mode lock applied:/.test(lower)) {
      return true;
    }
    return false;
  }

  function filterReadableRunTimeline(entries, isRunning) {
    var list = Array.isArray(entries) ? entries : [];
    if (isRunning || !list.length) {
      return {
        entries: list,
        hiddenEntries: [],
        hiddenCount: 0
      };
    }
    var visible = [];
    var hidden = [];
    for (var i = 0; i < list.length; i += 1) {
      var entry = list[i] || {};
      if (isOrchestrationRunStep(entry.text || "")) {
        hidden.push(entry);
      } else {
        visible.push(entry);
      }
    }
    if (!visible.length) {
      return {
        entries: list,
        hiddenEntries: [],
        hiddenCount: 0
      };
    }
    return {
      entries: visible,
      hiddenEntries: hidden,
      hiddenCount: hidden.length
    };
  }

  function runTraceMetaParts(event, isRunning) {
    var parts = [];
    var timeline = filterReadableRunTimeline(runTimelineEntries(event), !!isRunning);
    var stepCount = timeline.entries.length;
    if (stepCount > 0) {
      parts.push(String(stepCount) + " step" + (stepCount === 1 ? "" : "s"));
    }
    if (!isRunning && timeline.hiddenCount > 0) {
      parts.push(String(timeline.hiddenCount) + " orchestration hidden");
    }
    var reviewRoundCount = runTraceReviewRoundCount(event);
    if (reviewRoundCount > 0) {
      parts.push(String(reviewRoundCount) + " review round" + (reviewRoundCount === 1 ? "" : "s"));
    }
    return parts;
  }

  function refreshThinkingSummaryLabelText(existingLabel, durationLabel) {
    var base = "Thinking... " + (durationLabel || "0s");
    var existing = String(existingLabel || "");
    var marker = " \u00b7 ";
    var markerIndex = existing.indexOf(marker);
    if (markerIndex < 0) {
      return base;
    }
    var tail = trim(existing.slice(markerIndex + marker.length));
    if (!tail) {
      return base;
    }
    return base + marker + tail;
  }

  function runTraceSummaryLabel(event, isRunning) {
    var duration = thoughtDurationLabel(event && event.started_at, isRunning ? "" : (event && event.finished_at));
    var metaParts = runTraceMetaParts(event, isRunning);
    var metaSuffix = metaParts.length ? " \u00b7 " + metaParts.join(" \u00b7 ") : "";
    if (isRunning) {
      return "Thinking... " + (duration || "0s") + metaSuffix;
    }
    if (duration) {
      return "Worked for " + duration + metaSuffix;
    }
    if (metaParts.length) {
      return "Worked \u00b7 " + metaParts.join(" \u00b7 ");
    }
    return "Worked";
  }

  function secondsSinceIso(isoText) {
    var raw = trim(String(isoText || ""));
    if (!raw) {
      return 0;
    }
    var ms = Date.parse(raw);
    if (!isFinite(ms) || ms <= 0) {
      return 0;
    }
    var delta = Math.floor((Date.now() - ms) / 1000);
    if (!isFinite(delta) || delta < 0) {
      return 0;
    }
    return delta;
  }

  function runProgressLivenessText(lastActivityAt) {
    var quietSeconds = secondsSinceIso(lastActivityAt);
    if (quietSeconds >= RUN_PROGRESS_STALL_HARD_SEC) {
      return "No new step for " + String(quietSeconds) + "s; still working.";
    }
    if (quietSeconds >= RUN_PROGRESS_STALL_SOFT_SEC) {
      return "Still working (" + String(quietSeconds) + "s since last step).";
    }
    return "";
  }

  function runFinalizingLivenessText(finalizingAt) {
    var quietSeconds = secondsSinceIso(finalizingAt);
    if (quietSeconds >= RUN_FINALIZING_STALL_HARD_SEC) {
      return "Still finalizing (" + String(quietSeconds) + "s since run completion).";
    }
    if (quietSeconds >= RUN_FINALIZING_STALL_SOFT_SEC) {
      return "Preparing final response (" + String(quietSeconds) + "s).";
    }
    return "";
  }

  function formatRunRunningHeader(event, workspaceId, conversationId) {
    var startedAt = String((event && event.started_at) || "");
    var lastActivityAt = String((event && event.last_activity_at) || startedAt || "");
    var elapsed = thoughtDurationLabel(startedAt, "") || "0s";
    var metaParts = runTraceMetaParts(event, true);
    var runningMeta = metaParts.length ? metaParts.join(" \u00b7 ") : "waiting for first step";
    var livenessText = runProgressLivenessText(lastActivityAt);
    var startedAttr = startedAt ? " data-started-at='" + escAttr(startedAt) + "'" : "";
    var activityAttr = lastActivityAt ? " data-last-activity-at='" + escAttr(lastActivityAt) + "'" : "";
    var html = "<p class='run-line running'" + startedAttr + activityAttr + ">";
    html += "<span class='run-spinner' aria-hidden='true'></span>";
    html += "<span class='meta-glimmer'>Thinking...</span>";
    html += "<span class='run-elapsed'>" + escHtml(elapsed) + "</span>";
    html += "<span class='run-running-meta'>&middot; " + escHtml(runningMeta) + "</span>";
    html += "<span class='run-running-liveness'>" + (livenessText ? "&middot; " + escHtml(livenessText) : "") + "</span>";
    if (workspaceId && conversationId) {
      html += "<button type='button' class='run-stop-btn' aria-label='Stop run' title='Stop run' data-action='stop-run' data-workspace-id='" + escAttr(workspaceId) + "' data-conversation-id='" + escAttr(conversationId) + "'><span class='run-stop-square' aria-hidden='true'>&#9632;</span></button>";
    }
    html += "</p>";
    return html;
  }

  function decodeMaybeUriText(rawText) {
    var raw = String(rawText || "");
    if (!/%[0-9a-fA-F]{2}/.test(raw)) {
      return raw;
    }
    var plusEscaped = raw.replace(/\+/g, "%20");
    try {
      return decodeURIComponent(plusEscaped);
    } catch (_err) {
      return plusEscaped
        .replace(/%0D%0A/gi, "\n")
        .replace(/%0A/gi, "\n")
        .replace(/%09/gi, "\t")
        .replace(/%20/gi, " ")
        .replace(/%3A/gi, ":")
        .replace(/%2F/gi, "/")
        .replace(/%2D/gi, "-")
        .replace(/%5B/gi, "[")
        .replace(/%5D/gi, "]");
    }
  }

  function normalizeRunNarrativeText(rawText) {
    var text = String(decodeMaybeUriText(rawText) || "");
    if (!trim(text)) {
      return "";
    }
    text = text.replace(/\r\n?/g, "\n");
    text = text.replace(/\u0000/g, "");
    text = text.replace(/(\])(?=\[\d{2}:\d{2}:\d{2}\])/g, "$1\n");
    text = text.replace(/([.?!])\s*(\[\d{2}:\d{2}:\d{2}\])/g, "$1\n$2");
    text = text.replace(/\s*(MODE_UPDATE|COMMANDS|CONTRACT|PATCH|DONE_CLAIM|PLAN_UPDATE|CHECKPOINT|DECISION_REQUEST|FINAL):\s*/g, "\n$1: ");
    text = text.replace(/\s*(\*\*[^*\n]{3,}\*\*)\s*/g, "\n$1 ");
    text = text.replace(/\s*(###\s+[^\n]+)\s*/g, "\n$1\n");
    text = text.replace(/\s*(User request:|Latest user request:|Conversation context:|Workspace snapshot:|Failure ledger \(tail\):|Session log \(tail\):|Assumptions ledger \(tail\):|Previous iteration feedback:|Mode objective:|Mode constraints:|Current plan:|Rules:|Return ONLY these sections exactly:|Typed state:|Current mode:)\s*/g, "\n$1 ");
    text = text.replace(/\n{3,}/g, "\n\n");
    return trim(text);
  }

  function splitLongNarrativePart(text, maxLength) {
    var part = trim(text || "");
    var limit = Number(maxLength || 220);
    if (!part) {
      return [];
    }
    if (!isFinite(limit) || limit < 80) {
      limit = 220;
    }
    var pieces = [];
    var remaining = part;
    while (remaining.length > limit) {
      var breakAt = remaining.lastIndexOf(" ", limit);
      if (breakAt < Math.floor(limit * 0.5)) {
        breakAt = limit;
      }
      pieces.push(trim(remaining.slice(0, breakAt)));
      remaining = trim(remaining.slice(breakAt));
    }
    if (remaining) {
      pieces.push(remaining);
    }
    return pieces;
  }

  function prettifyRunStepText(rawText) {
    var text = trim(String(rawText || ""));
    if (!text) {
      return "";
    }
    text = text.replace(/^\*\*([^*]+)\*\*$/g, "$1");
    text = text.replace(/^MODE_UPDATE:\s*/i, "Mode update: ");
    text = text.replace(/^PLAN_UPDATE:\s*/i, "Plan update: ");
    text = text.replace(/^CHECKPOINT:\s*/i, "Checkpoint: ");
    text = text.replace(/^COMMANDS:\s*/i, "Command batch: ");
    text = text.replace(/^CONTRACT:\s*/i, "Contract note: ");
    text = text.replace(/^PATCH:\s*/i, "Patch update: ");
    text = text.replace(/^DECISION_REQUEST:\s*/i, "Decision request: ");
    text = text.replace(/^FINAL:\s*/i, "Final summary: ");
    text = text.replace(/^DONE_CLAIM:\s*yes\b/i, "Completion check: done");
    text = text.replace(/^DONE_CLAIM:\s*no\b/i, "Completion check: not yet");
    text = text.replace(/\s{2,}/g, " ");
    return trim(text);
  }

  function splitNarrativeFragments(lineText) {
    var line = String(lineText || "");
    if (!trim(line)) {
      return [];
    }
    line = line.replace(/([.!?])\s+(?=[A-Z0-9\[])/g, "$1\n");
    line = line.replace(/\s*(Goal:|Subgoals:|Constraints:|Unknowns:|Next Action:|Completion Criteria:|Transition:|Reason:|Checkpoint:|Command:|Status:|Output:|Question:|Options:|Input:|Assumption:|Action:|Error:|Hypothesis:|Current mode:)\s*/g, "\n$1 ");
    line = line.replace(/\n{2,}/g, "\n");
    var coarseParts = line.split(/\n+/);
    var parts = [];
    for (var i = 0; i < coarseParts.length; i += 1) {
      var coarse = trim(coarseParts[i] || "");
      if (!coarse) {
        continue;
      }
      var longParts = splitLongNarrativePart(coarse, 220);
      for (var j = 0; j < longParts.length; j += 1) {
        var item = prettifyRunStepText(longParts[j] || "");
        if (item) {
          parts.push(item);
        }
      }
    }
    return parts;
  }

  function splitRunStreamEntries(streamText) {
    var normalized = normalizeRunNarrativeText(streamText);
    if (!normalized) {
      return [];
    }
    var entries = [];
    var lastEntryKey = "";
    var stampRegex = /\[(\d{2}:\d{2}:\d{2})\]\s*/g;
    var match = null;
    var foundStamp = false;
    var activeStamp = "";
    var activeStart = 0;

    function pushEntry(stamp, textPart) {
      var text = trim(String(textPart || ""));
      if (!text) {
        return;
      }
      var key = String(stamp || "") + "|" + text.toLowerCase();
      if (key === lastEntryKey) {
        return;
      }
      lastEntryKey = key;
      entries.push({
        time: stamp,
        text: text
      });
    }

    function pushChunk(stamp, chunkText) {
      var chunk = trim(String(chunkText || ""));
      if (!chunk) {
        return;
      }
      var lines = chunk.split(/\n+/);
      for (var i = 0; i < lines.length; i += 1) {
        var lineParts = splitNarrativeFragments(lines[i] || "");
        for (var j = 0; j < lineParts.length; j += 1) {
          pushEntry(stamp, lineParts[j]);
        }
      }
    }

    while ((match = stampRegex.exec(normalized)) !== null) {
      foundStamp = true;
      if (activeStamp) {
        pushChunk(activeStamp, normalized.slice(activeStart, match.index));
      } else {
        pushChunk("", normalized.slice(0, match.index));
      }
      activeStamp = String(match[1] || "");
      activeStart = stampRegex.lastIndex;
    }

    if (foundStamp) {
      pushChunk(activeStamp, normalized.slice(activeStart));
      return entries;
    }

    var fallbackLines = normalized.split(/\n+/);
    for (var k = 0; k < fallbackLines.length; k += 1) {
      var fallbackParts = splitNarrativeFragments(fallbackLines[k] || "");
      for (var n = 0; n < fallbackParts.length; n += 1) {
        pushEntry("", fallbackParts[n]);
      }
    }
    return entries;
  }

  function runStepTone(text) {
    var lower = String(text || "").toLowerCase();
    if (!lower) {
      return "info";
    }
    if (/(fatal|failed|error|denied|blocked|mismatch)/.test(lower)) {
      return "error";
    }
    if (/(warning|retry|fallback|recovered)/.test(lower)) {
      return "warn";
    }
    if (/(run finalized|done|completed|success|verified|pass)/.test(lower)) {
      return "success";
    }
    if (/(current mode|mode[_ ]update|transition)/.test(lower)) {
      return "mode";
    }
    if (/(iteration\s+\d+\s+started|requesting model output|starting|compacted|plan update|checkpoint)/.test(lower)) {
      return "progress";
    }
    return "info";
  }

  function classifyRunCommandActivity(commandText) {
    var cmd = trim(String(commandText || "")).toLowerCase();
    if (!cmd) {
      return "";
    }
    if (/^rg\b|^grep\b|^find\b/.test(cmd)) {
      return "searches";
    }
    if (/^ls\b|^tree\b/.test(cmd)) {
      return "lists";
    }
    if (/^cat\b|^sed\b|^awk\b|^head\b|^tail\b/.test(cmd)) {
      return "reads";
    }
    if (/apply_patch|^git\s+diff\b|^git\s+status\b/.test(cmd)) {
      return "edits";
    }
    if (/npm\s+test|pytest|cargo\s+test|go\s+test|vitest|jest|headless|smoke|lint/.test(cmd)) {
      return "checks";
    }
    return "actions";
  }

  function humanizeRunCommand(commandText) {
    var cmd = trim(String(commandText || ""));
    if (!cmd) {
      return "";
    }
    var lowered = cmd.toLowerCase();
    if (/^cat\s+/.test(lowered)) {
      return "Read " + cmd.replace(/^cat\s+/i, "");
    }
    if (/^ls\s+/.test(lowered)) {
      return "Listed " + cmd.replace(/^ls\s+/i, "");
    }
    if (/^rg\s+/.test(lowered) || /^grep\s+/.test(lowered) || /^find\s+/.test(lowered)) {
      return "Searched " + cmd;
    }
    if (/apply_patch/i.test(cmd)) {
      return "Applied patch";
    }
    if (/^git\s+status\b/i.test(cmd)) {
      return "Checked git status";
    }
    if (/^git\s+diff\b/i.test(cmd)) {
      return "Inspected git diff";
    }
    return cmd;
  }

  function formatRunActivityDigest(event, isRunning) {
    var commands = Array.isArray(event && event.commands) ? event.commands : [];
    var streamEntries = runTimelineEntries(event);
    var durationSeconds = runDurationSeconds(event && event.started_at, isRunning ? "" : (event && event.finished_at));
    var counts = {
      reads: 0,
      searches: 0,
      lists: 0,
      edits: 0,
      checks: 0,
      actions: 0
    };
    var recentLines = [];

    for (var i = 0; i < commands.length; i += 1) {
      var cmdText = trim(String((commands[i] && commands[i].command) || ""));
      if (!cmdText) {
        continue;
      }
      var bucket = classifyRunCommandActivity(cmdText);
      if (bucket && Object.prototype.hasOwnProperty.call(counts, bucket)) {
        counts[bucket] += 1;
      } else {
        counts.actions += 1;
      }
      if (recentLines.length < 5) {
        recentLines.push(humanizeRunCommand(cmdText));
      }
    }

    if (!recentLines.length) {
      for (var e = 0; e < streamEntries.length && recentLines.length < 5; e += 1) {
        var line = trim(String((streamEntries[e] && streamEntries[e].text) || ""));
        if (!line) {
          continue;
        }
        if (/iteration|mode_update|plan_update|commands:|contract|checkpoint/i.test(line)) {
          continue;
        }
        recentLines.push(line);
      }
    }

    var summaryParts = [];
    if (counts.reads > 0) summaryParts.push(String(counts.reads) + " read" + (counts.reads === 1 ? "" : "s"));
    if (counts.searches > 0) summaryParts.push(String(counts.searches) + " search" + (counts.searches === 1 ? "" : "es"));
    if (counts.lists > 0) summaryParts.push(String(counts.lists) + " list" + (counts.lists === 1 ? "" : "s"));
    if (counts.edits > 0) summaryParts.push(String(counts.edits) + " edit" + (counts.edits === 1 ? "" : "s"));
    if (counts.checks > 0) summaryParts.push(String(counts.checks) + " check" + (counts.checks === 1 ? "" : "s"));
    if (!summaryParts.length && counts.actions > 0) {
      summaryParts.push(String(counts.actions) + " action" + (counts.actions === 1 ? "" : "s"));
    }
    if (!summaryParts.length || !recentLines.length) {
      return "";
    }

    var eventId = String((event && event.id) || "");
    var longRun = durationSeconds >= 240 || commands.length >= 36 || streamEntries.length >= 220;
    var hasSeen = !!(eventId && Object.prototype.hasOwnProperty.call(state.runDigestOpenByEventId, eventId));
    var openByDefault = !longRun;
    var isOpen = hasSeen ? !!state.runDigestOpenByEventId[eventId] : openByDefault;
    var html = "<details class='run-activity-card run-activity-digest' data-digest-event-id='" + escAttr(eventId) + "'" + (isOpen ? " open" : "") + ">";
    html += "<summary class='run-activity-summary'>" + escHtml((isRunning ? "Exploring " : "Explored ") + summaryParts.join(", ")) + "</summary>";
    html += "<div class='run-activity-lines'>";
    for (var r = 0; r < recentLines.length; r += 1) {
      html += "<p>" + escHtml(recentLines[r] || "") + "</p>";
    }
    html += "</div></details>";
    return html;
  }

  function formatRunStreamFeed(event, isRunning) {
    var timeline = filterReadableRunTimeline(runTimelineEntries(event), !!isRunning);
    var entries = timeline.entries;
    var hiddenEntries = timeline.hiddenEntries;
    var hiddenCount = timeline.hiddenCount;
    var maxEntries = isRunning ? 220 : 320;
    var clippedCount = 0;
    if (entries.length > maxEntries) {
      clippedCount = entries.length - maxEntries;
      entries = entries.slice(clippedCount);
    }
    var html = "<div class='run-live-feed'>";
    if (!entries.length) {
      html += "<p class='run-line subtle'>" + (isRunning ? "Waiting for trace output..." : "No step timeline captured for this run.") + "</p>";
      html += "</div>";
      return html;
    }
    if (clippedCount > 0) {
      html += "<p class='run-feed-clip'>Showing latest " + escHtml(String(entries.length)) + " steps (" + escHtml(String(clippedCount)) + " earlier steps hidden).</p>";
    }
    if (!isRunning && hiddenCount > 0) {
      html += "<details class='run-feed-fold run-feed-meta-fold'><summary>Hidden orchestration updates (" + escHtml(String(hiddenCount)) + ")</summary><div class='run-feed-fold-body'>";
      var hiddenRendered = hiddenEntries;
      var hiddenClippedCount = 0;
      if (hiddenRendered.length > 120) {
        hiddenClippedCount = hiddenRendered.length - 120;
        hiddenRendered = hiddenRendered.slice(hiddenClippedCount);
      }
      if (hiddenClippedCount > 0) {
        html += "<p class='run-feed-clip'>Showing latest " + escHtml(String(hiddenRendered.length)) + " hidden updates (" + escHtml(String(hiddenClippedCount)) + " earlier hidden updates clipped).</p>";
      }
      for (var x = 0; x < hiddenRendered.length; x += 1) {
        var hiddenEntry = hiddenRendered[x] || {};
        var hiddenTone = runStepTone(hiddenEntry.text);
        html += (
          "<div class='run-step " + escHtml(hiddenTone) + "'>" +
            "<span class='run-step-time'>" + escHtml(hiddenEntry.time || "step") + "</span>" +
            "<span class='run-step-text'>" + escHtml(hiddenEntry.text || "") + "</span>" +
          "</div>"
        );
      }
      html += "</div></details>";
    }
    function renderStep(entry) {
      var stepEntry = entry || {};
      var tone = runStepTone(stepEntry.text);
      return (
        "<div class='run-step " + escHtml(tone) + "'>" +
          "<span class='run-step-time'>" + escHtml(stepEntry.time || "step") + "</span>" +
          "<span class='run-step-text'>" + escHtml(stepEntry.text || "") + "</span>" +
        "</div>"
      );
    }

    var collapseMiddle = !isRunning && entries.length > 10;
    if (collapseMiddle) {
      var leadCount = 3;
      var tailCount = 8;
      var hiddenCount = entries.length - leadCount - tailCount;
      if (hiddenCount < 1) {
        collapseMiddle = false;
      } else {
        for (var h = 0; h < leadCount; h += 1) {
          html += renderStep(entries[h]);
        }
        html += "<details class='run-feed-fold'><summary>Earlier steps (" + escHtml(String(hiddenCount)) + ")</summary><div class='run-feed-fold-body'>";
        for (var m = leadCount; m < entries.length - tailCount; m += 1) {
          html += renderStep(entries[m]);
        }
        html += "</div></details>";
        for (var t = entries.length - tailCount; t < entries.length; t += 1) {
          html += renderStep(entries[t]);
        }
      }
    }
    if (!collapseMiddle) {
      for (var i = 0; i < entries.length; i += 1) {
        html += renderStep(entries[i]);
      }
    }
    html += "</div>";
    return html;
  }

  function formatRunInlineTimeline(event, isRunning, maxItems) {
    var timeline = filterReadableRunTimeline(runTimelineEntries(event), !!isRunning);
    var entries = timeline.entries;
    var hiddenCount = timeline.hiddenCount;
    if (!entries.length) {
      return "";
    }
    var limit = Number(maxItems || 0);
    if (!isFinite(limit) || limit < 1) {
      limit = isRunning ? 7 : 10;
    }
    var clippedCount = 0;
    if (entries.length > limit) {
      clippedCount = entries.length - limit;
      entries = entries.slice(clippedCount);
    }
    var html = "<div class='run-inline-feed'>";
    if (clippedCount > 0) {
      html += "<p class='run-inline-clip'>+" + escHtml(String(clippedCount)) + " earlier step" + (clippedCount === 1 ? "" : "s") + "</p>";
    }
    if (!isRunning && hiddenCount > 0) {
      html += "<p class='run-inline-clip'>+" + escHtml(String(hiddenCount)) + " orchestration update" + (hiddenCount === 1 ? "" : "s") + " hidden</p>";
    }
    for (var i = 0; i < entries.length; i += 1) {
      var entry = entries[i] || {};
      var tone = runStepTone(entry.text);
      html += "<p class='run-inline-step " + escHtml(tone) + "'>";
      html += "<span class='run-inline-time'>" + escHtml(entry.time || "step") + "</span>";
      html += "<span class='run-inline-text'>" + escHtml(entry.text || "") + "</span>";
      html += "</p>";
    }
    html += "</div>";
    return html;
  }

  function formatRunNarrativeSection(title, rawText) {
    var text = normalizeRunNarrativeText(rawText);
    if (!text) {
      return "";
    }
    var paragraphs = text.split(/\n{2,}/);
    var body = "";
    for (var i = 0; i < paragraphs.length; i += 1) {
      var paragraph = trim(paragraphs[i] || "");
      if (!paragraph) {
        continue;
      }
      body += "<p>" + escHtml(paragraph).replace(/\n/g, "<br>") + "</p>";
    }
    if (!body) {
      return "";
    }
    return "<div class='run-trace-block'><p class='run-trace-title'>" + escHtml(title) + "</p><div class='run-prose'>" + body + "</div></div>";
  }

  function summarizeRunChanges(event) {
    var summary = {
      added: 0,
      deleted: 0,
      files: [],
      hasDiff: false,
      perFile: {}
    };
    var fileMap = {};
    var diffText = String((event && event.git_diff) || "");
    var statusText = String((event && event.git_status) || "");
    if (trim(diffText)) {
      summary.hasDiff = true;
      var diffLines = diffText.split(/\r?\n/);
      for (var i = 0; i < diffLines.length; i += 1) {
        var line = diffLines[i] || "";
        var diffMatch = line.match(/^diff --git a\/(.+?) b\/(.+)$/);
        if (diffMatch) {
          var diffPath = trim(diffMatch[2] || diffMatch[1] || "");
          if (diffPath && !fileMap[diffPath]) {
            fileMap[diffPath] = true;
            summary.files.push(diffPath);
          }
          if (diffPath && !summary.perFile[diffPath]) {
            summary.perFile[diffPath] = { add: 0, del: 0 };
          }
          continue;
        }
        if (/^\+/.test(line) && !/^\+\+\+/.test(line)) {
          summary.added += 1;
          if (summary.files.length) {
            var plusPath = summary.files[summary.files.length - 1];
            if (!summary.perFile[plusPath]) {
              summary.perFile[plusPath] = { add: 0, del: 0 };
            }
            summary.perFile[plusPath].add += 1;
          }
        } else if (/^-/.test(line) && !/^---/.test(line)) {
          summary.deleted += 1;
          if (summary.files.length) {
            var minusPath = summary.files[summary.files.length - 1];
            if (!summary.perFile[minusPath]) {
              summary.perFile[minusPath] = { add: 0, del: 0 };
            }
            summary.perFile[minusPath].del += 1;
          }
        }
      }
    }
    if (!summary.files.length && trim(statusText)) {
      var statusLines = statusText.split(/\r?\n/);
      for (var j = 0; j < statusLines.length; j += 1) {
        var statusLine = trim(statusLines[j] || "");
        if (!statusLine) {
          continue;
        }
        var statusMatch = statusLine.match(/^[ MARCUD\?]{1,2}\s+(.+)$/);
        if (!statusMatch) {
          continue;
        }
        var statusPath = trim(statusMatch[1] || "");
        var arrow = statusPath.indexOf("->");
        if (arrow >= 0) {
          statusPath = trim(statusPath.slice(arrow + 2));
        }
        if (statusPath.charAt(0) === '"' && statusPath.charAt(statusPath.length - 1) === '"') {
          statusPath = statusPath.slice(1, -1);
        }
        if (!statusPath || fileMap[statusPath]) {
          continue;
        }
        fileMap[statusPath] = true;
        summary.files.push(statusPath);
      }
    }
    return summary;
  }

  function formatRunChangesCard(event) {
    var summary = summarizeRunChanges(event);
    if (!summary.files.length && summary.added === 0 && summary.deleted === 0) {
      return "";
    }
    var fileCount = summary.files.length;
    var html = "<div class='run-changes-card'>";
    html += "<p class='run-changes-title'>Changes made this run</p>";
    html += "<p class='run-changes-head'>" + escHtml(String(fileCount)) + " file" + (fileCount === 1 ? "" : "s") + " changed";
    html += " <span class='run-delta add'>+" + escHtml(String(summary.added)) + "</span>";
    html += " <span class='run-delta del'>-" + escHtml(String(summary.deleted)) + "</span></p>";
    if (fileCount > 0) {
      html += "<div class='run-changes-table'>";
      var shown = Math.min(6, fileCount);
      for (var i = 0; i < shown; i += 1) {
        var path = String(summary.files[i] || "");
        var perFile = summary.perFile[path] || { add: 0, del: 0 };
        var addCount = Number(perFile.add || 0);
        var delCount = Number(perFile.del || 0);
        var largeLine = (addCount + delCount) >= 260;
        html += "<div class='run-changes-row'>";
        html += "<code class='run-changes-path'>" + escHtml(path) + "</code>";
        html += "<span class='run-changes-stats'><span class='run-delta add'>+" + escHtml(String(addCount)) + "</span> <span class='run-delta del'>-" + escHtml(String(delCount)) + "</span></span>";
        if (largeLine) {
          html += "<span class='run-changes-note'>Too large to render inline</span>";
        }
        html += "</div>";
      }
      if (fileCount > shown) {
        html += "<p class='run-line subtle'>+" + escHtml(String(fileCount - shown)) + " more files</p>";
      }
      html += "</div>";
    }
    html += "</div>";
    return html;
  }

  function formatRunAdvancedTrace(event) {
    var sections = "";
    if (event && event.commands && event.commands.length) {
      sections += "<div class='run-trace-block'><p class='run-trace-title'>Command runs</p>" + formatRunCommands(event.commands || []) + "</div>";
    }
    if (trim(event && event.state)) {
      sections += "<div class='run-trace-block'><p class='run-trace-title'>Mode State</p><pre class='run-code-block'>" + escHtml(event.state || "") + "</pre></div>";
    }
    if (trim(event && event.failures)) {
      sections += "<div class='run-trace-block'><p class='run-trace-title'>Failure Ledger</p><pre class='run-code-block'>" + escHtml(event.failures || "") + "</pre></div>";
    }
    if (trim(event && event.session_log)) {
      sections += "<div class='run-trace-block'><p class='run-trace-title'>Session Log</p><pre class='run-code-block'>" + escHtml(event.session_log || "") + "</pre></div>";
    }
    if (trim(event && event.git_status)) {
      sections += "<div class='run-trace-block'><p class='run-trace-title'>Git Status</p><pre class='run-code-block'>" + escHtml(event.git_status || "") + "</pre></div>";
    }
    if (trim(event && event.git_diff)) {
      sections += "<div class='run-trace-block'><p class='run-trace-title'>Git Diff</p><div class='diff-view run-diff-view'>" + formatDiff(event.git_diff || "") + "</div></div>";
    }
    if (!sections) {
      return "";
    }
    return "<details class='run-details run-advanced'><summary><span class='run-summary-label'>Advanced run diagnostics</span></summary>" + sections + "</details>";
  }

  function runEventHasTraceData(event) {
    if (!event) {
      return false;
    }
    if (trim(event.stream_text || "")) {
      return true;
    }
    if (trim(event.plan || "")) {
      return true;
    }
    if (event.commands && event.commands.length) {
      return true;
    }
    if (trim(event.state || "")) {
      return true;
    }
    if (trim(event.failures || "")) {
      return true;
    }
    if (trim(event.session_log || "")) {
      return true;
    }
    if (trim(event.git_status || "")) {
      return true;
    }
    return trim(event.git_diff || "") !== "";
  }

  function shouldAutoCollapseCompletedRunTrace(event) {
    if (!event) {
      return true;
    }
    var duration = runDurationSeconds(event.started_at, event.finished_at);
    var streamEntries = runTimelineEntries(event);
    var commandCount = Array.isArray(event.commands) ? event.commands.length : 0;
    var planLength = trim(String(event.plan || "")).length;
    var failureLength = trim(String(event.failures || "")).length;
    var sessionLength = trim(String(event.session_log || "")).length;
    var diffLength = trim(String(event.git_diff || "")).length;
    var streamLength = trim(String(event.stream_text || "")).length;
    var complexityScore = 0;
    if (duration >= 90) complexityScore += 2;
    if (duration >= 180) complexityScore += 2;
    if (streamEntries.length >= 20) complexityScore += 2;
    if (streamEntries.length >= 50) complexityScore += 2;
    if (commandCount >= 8) complexityScore += 1;
    if (commandCount >= 18) complexityScore += 2;
    if (planLength >= 800) complexityScore += 1;
    if (failureLength >= 1000 || sessionLength >= 1800) complexityScore += 2;
    if (diffLength >= 3000) complexityScore += 2;
    if (streamLength >= 2400) complexityScore += 1;
    return complexityScore >= 3;
  }

  function formatRunTrace(event, options) {
    if (!event) {
      return "";
    }
    var opts = options || {};
    var isRunning = !!opts.isRunning;
    var sections = "";
    sections += formatRunActivityDigest(event, isRunning);
    sections += "<div class='run-trace-block run-trace-stream'><p class='run-trace-title'>" + (isRunning ? "Live steps" : "Step timeline") + "</p>" + formatRunStreamFeed(event, isRunning) + "</div>";
    sections += formatRunNarrativeSection("Plan", event.plan || "");
    var advanced = formatRunAdvancedTrace(event);
    if (advanced) {
      sections += advanced;
    }
    if (!sections || (!isRunning && !runEventHasTraceData(event) && !thoughtDurationLabel(event && event.started_at, event && event.finished_at))) {
      return "";
    }
    var eventId = String(event.id || "");
    var hasSeenToggle = Object.prototype.hasOwnProperty.call(state.runDetailsOpenByEventId, eventId);
    var isOpen = hasSeenToggle ? runDetailsShouldBeOpen(eventId) : !!opts.defaultOpen;
    var openAttr = isOpen ? " open" : "";
    var startedAttr = isRunning ? " data-started-at='" + escAttr(event.started_at || "") + "'" : "";
    var detailsClass = "run-details " + (isRunning ? "run-thinking" : "run-rollup");
    var summaryLabel = runTraceSummaryLabel(event, isRunning);
    var summaryInner = "";
    if (isRunning) {
      summaryInner = "<span class='run-spinner' aria-hidden='true'></span><span class='run-summary-label meta-glimmer'>" + escHtml(summaryLabel) + "</span>";
    } else {
      summaryInner = "<span class='run-summary-label'>" + escHtml(summaryLabel) + "</span>";
    }
    return "<details class='" + detailsClass + "' data-event-id='" + escAttr(eventId) + "'" + openAttr + startedAttr + "><summary>" + summaryInner + "</summary>" + sections + "</details>";
  }

  function friendlyRunErrorText(event) {
    var attempts = runTraceAttemptCount(event);
    var base = attempts > 0
      ? "I couldn't complete that run after " + attempts + " attempt" + (attempts === 1 ? "" : "s") + "."
      : "I couldn't complete that run.";
    var raw = String((event && event.error) || "").toLowerCase();
    if (raw.indexOf("approval") >= 0 || raw.indexOf("blocked") >= 0 || raw.indexOf("denied") >= 0) {
      return base + " A command needed approval.";
    }
    if (trim(event && event.error)) {
      return base + " " + String(event.error || "");
    }
    return base + " Please retry.";
  }

  function structuredRunFallbackMessage(attemptCount) {
    var attempts = Number(attemptCount || 0);
    if (!isFinite(attempts) || attempts < 0) {
      attempts = 0;
    }
    attempts = Math.floor(attempts);
    var outcome = attempts > 0
      ? "Outcome: I couldn't complete this run after " + attempts + " attempt" + (attempts === 1 ? "" : "s") + "."
      : "Outcome: I couldn't produce a final response for this run.";
    return [
      outcome,
      "Verification Evidence: Review the Thinking trace for executed steps and command outputs.",
      "Risks: The current result may be partial or stale.",
      "Next Improvement: Retry with a narrower scope or a higher compute budget."
    ].join("\\n");
  }

  function assistantLooksLikeTrace(text) {
    var raw = String(text || "");
    if (!trim(raw)) {
      return false;
    }
    var hasAttemptHeaders = /^##\s+\d{4}-\d{2}-\d{2}T/m.test(raw);
    var hasTraceMarkers = /(Action:|Hypothesis:|Next Attempt:|approval_required|Tool call failed|Refine command set)/i.test(raw);
    if (hasAttemptHeaders && hasTraceMarkers) {
      return true;
    }
    if (hasAttemptHeaders) {
      return true;
    }
    var hasControlScaffold = /(MODE_UPDATE:|PLAN_UPDATE:|DONE_CLAIM:|Transition:\s+[A-Z]+\s*->\s*[A-Z]+|Checkpoint:|final action plan|Next Action:\s*Completion Criteria:)/i.test(raw);
    var hasAgentModeMarkers = /(INVESTIGATE|DESIGN|IMPLEMENT|VERIFY|DONE)/i.test(raw);
    return hasControlScaffold && hasAgentModeMarkers;
  }

  function renderRunEvent(event, workspaceId, conversationId) {
    if (!event) {
      return "";
    }

    var status = event.status || "done";
    var defaultCompletedTraceOpen = !shouldAutoCollapseCompletedRunTrace(event);
    if (status !== "running" && status !== "awaiting_approval" && status !== "awaiting_decision") {
      defaultCompletedTraceOpen = false;
    }
    var decisionHint = trim(String(event.decision_hint || ""));
    var runClass = "msg run " + escHtml(status);
    var html = "";

    if (status === "running") {
      html = "<article class='" + runClass + " run-narrative'>";
      html += formatRunRunningHeader(event, workspaceId, conversationId);
      html += formatRunTrace(event, { isRunning: true, defaultOpen: true });
      html += "</article>";
      return html;
    }

    if (status === "cancelled") {
      html = "<article class='" + runClass + "'>";
      html += "<p class='run-line subtle'>Run stopped.</p>";
      html += formatRunTrace(event, { defaultOpen: defaultCompletedTraceOpen });
      html += "</article>";
      return html;
    }

    if (status === "approval_granted") {
      runClass += " run-narrative run-approval-note";
      html = "<article class='" + runClass + "'>";
      var approvedScope = String(event.approved_scope || "once");
      var approvedCommand = trim(String(event.approved_command || ""));
      var approvalText = approvedScope === "remember"
        ? "Execution approved and remembered."
        : "Execution approved once.";
      if (approvedCommand) {
        approvalText += " " + approvedCommand;
      }
      html += "<p class='run-line subtle'>" + escHtml(approvalText) + "</p>";
      if (decisionHint && !/one-time rule/i.test(decisionHint)) {
        html += "<p class='run-line subtle run-decision-hint'>Matched by: " + escHtml(decisionHint) + "</p>";
      }
      html += "</article>";
      return html;
    }

    if (status === "error") {
      html = "<article class='" + runClass + " run-narrative'>";
      html += "<p class='run-line error'>" + escHtml(friendlyRunErrorText(event)) + "</p>";
      html += formatRunTrace(event, { defaultOpen: defaultCompletedTraceOpen });
      html += formatRunChangesCard(event);
      html += "</article>";
      return html;
    }
    if (status === "awaiting_approval") {
      runClass += " run-narrative";
      html = "<article class='" + runClass + "'>";
      html += "<p class='run-line subtle'>Awaiting command approval.</p>";
      html += formatRunTrace(event, { defaultOpen: true });
      html += "</article>";
      return html;
    }
    if (status === "awaiting_decision") {
      runClass += " run-narrative";
      html = "<article class='" + runClass + "'>";
      html += "<p class='run-line subtle'>Awaiting your decision.</p>";
      html += formatRunTrace(event, { defaultOpen: true });
      html += "</article>";
      return html;
    }

    var runModelText = "";
    if (event.model) {
      var runModelParts = parseModelDisplay(event.model);
      runModelText = runModelParts.primary;
      if (runModelParts.meta) {
        runModelText += " (" + runModelParts.meta + ")";
      }
    }
    var conversation = null;
    if (workspaceId && conversationId) {
      conversation = getConversationById(getWorkspaceById(workspaceId), conversationId);
    }
    var queuePending = queueNumber(conversation && conversation.queue_pending);
    var queueRunning = !!(conversation && String(conversation.queue_running || "0") === "1");
    var queueLastStatus = String(conversation && conversation.queue_last_status || "");
    var queueAwaitingApproval = (
      queueLastStatus === "awaiting_approval" ||
      isAwaitingApprovalConversation(workspaceId, conversationId) ||
      !!conversationApprovalRequest(conversation)
    );
    var queueAwaitingDecision = queueLastStatus === "awaiting_decision" || !!normalizeDecisionRequest(conversation && conversation.decision_request);
    var eventAwaitingAssistant = Number(event.awaiting_assistant || 0) > 0;
    var pendingAssistantDelivery = assistantDeliveryPendingCount(workspaceId, conversationId) > 0;
    var hasAssistantAfterAnchor = conversationHasAssistantAfterAnchor(workspaceId, conversationId, event.message_anchor);
    var latestRunEvent = findLatestRunEventByStatus(conversationId, ["running", "done", "awaiting_decision", "awaiting_approval", "error", "cancelled"]);
    var isLatestRunEvent = !!(
      latestRunEvent &&
      String(latestRunEvent.id || "") &&
      String(latestRunEvent.id || "") === String(event.id || "")
    );
    var finishedAtMs = Date.parse(String(event.finished_at || ""));
    var recentlyFinishedWithoutAssistant = false;
    if (isFinite(finishedAtMs) && finishedAtMs > 0 && !hasAssistantAfterAnchor) {
      recentlyFinishedWithoutAssistant = (Date.now() - finishedAtMs) <= 90000;
    }
    var shouldShowFinalizingLine = false;
    if (!hasAssistantAfterAnchor) {
      if (eventAwaitingAssistant || pendingAssistantDelivery || recentlyFinishedWithoutAssistant) {
        shouldShowFinalizingLine = true;
      } else if (isLatestRunEvent && !queueRunning && queuePending < 1 && !queueAwaitingApproval && !queueAwaitingDecision) {
        shouldShowFinalizingLine = true;
      }
    }
    var completedSummaryLine = "";
    if (!queueRunning && queuePending < 1 && !queueAwaitingApproval && !queueAwaitingDecision && !shouldShowFinalizingLine) {
      completedSummaryLine = trim(runTraceSummaryLabel(event, false));
    }
    html = "<article class='" + runClass + " run-narrative'>";
    if (queueRunning || queuePending > 0) {
      html += "<p class='run-line subtle'>Run step complete. Continuing...</p>";
    } else if (queueAwaitingApproval) {
      html += "<p class='run-line subtle'>Run paused. Awaiting command approval.</p>";
    } else if (queueAwaitingDecision) {
      html += "<p class='run-line subtle'>Run paused. Awaiting your decision.</p>";
    } else if (shouldShowFinalizingLine) {
      var finalizingAt = trim(String(event.finished_at || event.last_activity_at || event.started_at || ""));
      var finalizingAttr = finalizingAt ? " data-finalizing-at='" + escAttr(finalizingAt) + "'" : "";
      var finalizingMeta = runFinalizingLivenessText(finalizingAt);
      html += "<p class='run-line subtle run-finalizing-line'" + finalizingAttr + "><span class='run-spinner' aria-hidden='true'></span>Finalizing response...<span class='run-finalizing-meta'>" + (finalizingMeta ? "&middot; " + escHtml(finalizingMeta) : "") + "</span></p>";
    } else {
      if (completedSummaryLine) {
        html += "<p class='run-line subtle'>" + escHtml(completedSummaryLine) + "</p>";
      }
      if (runModelText) {
        html += "<p class='run-line subtle'>Model: " + escHtml(runModelText) + "</p>";
      }
    }
    html += formatRunTrace(event, { defaultOpen: defaultCompletedTraceOpen });
    if (!queueRunning && queuePending < 1 && !queueAwaitingApproval && !queueAwaitingDecision) {
      html += formatRunChangesCard(event);
    }
    html += "</article>";
    return html;
  }

  function findLatestRunEventByStatus(conversationId, statuses) {
    var convId = String(conversationId || "");
    var wanted = Array.isArray(statuses) ? statuses : [];
    if (!convId || !wanted.length) {
      return null;
    }
    var events = state.runEventsByConversation[convId];
    if (!Array.isArray(events) || !events.length) {
      return null;
    }
    for (var i = events.length - 1; i >= 0; i -= 1) {
      var event = events[i] || {};
      var status = String(event.status || "");
      for (var j = 0; j < wanted.length; j += 1) {
        if (status === String(wanted[j] || "")) {
          return event;
        }
      }
    }
    return null;
  }

  function refreshRunningElapsedBadges() {
    if (!el.chatLog) {
      return;
    }
    var lines = el.chatLog.querySelectorAll(".run-line.running[data-started-at]");
    var nowMs = Date.now();
    if (lines && lines.length) {
      for (var i = 0; i < lines.length; i += 1) {
        var line = lines[i];
        var startedRaw = line.getAttribute("data-started-at") || "";
        var startedMs = Date.parse(startedRaw);
        if (!isFinite(startedMs) || startedMs <= 0) {
          continue;
        }
        var elapsed = Math.max(0, Math.floor((nowMs - startedMs) / 1000));
        var badge = line.querySelector(".run-elapsed");
        if (badge) {
          badge.textContent = elapsed > 0 ? String(elapsed) + "s" : "";
        }
        var livenessNode = line.querySelector(".run-running-liveness");
        if (livenessNode) {
          var activityRaw = line.getAttribute("data-last-activity-at") || startedRaw;
          var livenessText = runProgressLivenessText(activityRaw);
          livenessNode.textContent = livenessText ? "· " + livenessText : "";
        }
      }
    }

    var finalizingLines = el.chatLog.querySelectorAll(".run-finalizing-line[data-finalizing-at]");
    if (finalizingLines && finalizingLines.length) {
      for (var fi = 0; fi < finalizingLines.length; fi += 1) {
        var finalizingLine = finalizingLines[fi];
        var finalizingMeta = finalizingLine.querySelector(".run-finalizing-meta");
        if (!finalizingMeta) {
          continue;
        }
        var finalizingAt = finalizingLine.getAttribute("data-finalizing-at") || "";
        var finalizingText = runFinalizingLivenessText(finalizingAt);
        finalizingMeta.textContent = finalizingText ? "· " + finalizingText : "";
      }
    }

    var details = el.chatLog.querySelectorAll("details.run-details.run-thinking[data-started-at]");
    for (var j = 0; j < details.length; j += 1) {
      var panel = details[j];
      var started = panel.getAttribute("data-started-at") || "";
      var summary = panel.querySelector("summary");
      if (!summary) {
        continue;
      }
      var duration = thoughtDurationLabel(started, "");
      var summaryLabel = summary.querySelector(".run-summary-label");
      var refreshedLabel = refreshThinkingSummaryLabelText(
        summaryLabel ? summaryLabel.textContent : summary.textContent,
        duration || "0s"
      );
      if (summaryLabel) {
        summaryLabel.textContent = refreshedLabel;
      } else {
        summary.textContent = refreshedLabel;
      }
    }
  }

  function syncRunThinkingPreviewScroll() {
    if (!el.chatLog) {
      return;
    }
    var panels = el.chatLog.querySelectorAll("details.run-details.run-thinking[data-event-id]");
    if (!panels || !panels.length) {
      return;
    }
    for (var i = 0; i < panels.length; i += 1) {
      var panel = panels[i];
      if (!panel.open) {
        continue;
      }
      var preview = panel.querySelector(".run-live-feed");
      if (preview) {
        var eventId = String(panel.getAttribute("data-event-id") || "");
        var autoFollow = true;
        if (
          eventId &&
          Object.prototype.hasOwnProperty.call(state.runStreamAutoFollowByEventId, eventId)
        ) {
          autoFollow = !!state.runStreamAutoFollowByEventId[eventId];
        }
        if (autoFollow) {
          preview.scrollTop = preview.scrollHeight;
          if (eventId) {
            state.runStreamScrollTopByEventId[eventId] = preview.scrollTop;
          }
          continue;
        }
        if (
          eventId &&
          Object.prototype.hasOwnProperty.call(state.runStreamScrollTopByEventId, eventId)
        ) {
          var savedTop = Number(state.runStreamScrollTopByEventId[eventId]);
          if (isFinite(savedTop) && savedTop >= 0) {
            var maxTop = Math.max(0, Number(preview.scrollHeight || 0) - Number(preview.clientHeight || 0));
            preview.scrollTop = Math.min(maxTop, savedTop);
          }
        }
      }
    }
  }

  function workspaceTreeNodeKey(node) {
    if (!node || !node.getAttribute) {
      return "";
    }
    if (node.classList && node.classList.contains("workspace-group")) {
      var workspaceId = String(node.getAttribute("data-workspace-id") || "");
      return workspaceId ? ("workspace:" + workspaceId) : "";
    }
    if (node.classList && node.classList.contains("conversation-row")) {
      var wsId = String(node.getAttribute("data-workspace-id") || "");
      var convId = String(node.getAttribute("data-conversation-id") || "");
      if (wsId && convId) {
        return "conversation:" + wsId + ":" + convId;
      }
    }
    return "";
  }

  function snapshotWorkspaceTreePositions(selector) {
    if (!el.workspaceTree) {
      return {};
    }
    var query = trim(String(selector || ""));
    if (!query) {
      query = ".workspace-group[data-workspace-id], .conversation-row[data-workspace-id][data-conversation-id]";
    }
    var nodes = el.workspaceTree.querySelectorAll(query);
    var out = {};
    for (var i = 0; i < nodes.length; i += 1) {
      var node = nodes[i];
      var key = workspaceTreeNodeKey(node);
      if (!key) {
        continue;
      }
      out[key] = node.getBoundingClientRect();
    }
    return out;
  }

  function animateWorkspaceTreeFromSnapshot(snapshot, selector) {
    if (!el.workspaceTree || !snapshot || typeof snapshot !== "object") {
      return;
    }
    var query = trim(String(selector || ""));
    if (!query) {
      query = ".workspace-group[data-workspace-id], .conversation-row[data-workspace-id][data-conversation-id]";
    }
    var nodes = el.workspaceTree.querySelectorAll(query);
    for (var i = 0; i < nodes.length; i += 1) {
      var node = nodes[i];
      var key = workspaceTreeNodeKey(node);
      if (!key || !snapshot[key]) {
        continue;
      }
      var previous = snapshot[key];
      var next = node.getBoundingClientRect();
      var dx = previous.left - next.left;
      var dy = previous.top - next.top;
      if (Math.abs(dx) < 0.5 && Math.abs(dy) < 0.5) {
        continue;
      }
      node.style.transition = "none";
      node.style.transform = "translate(" + String(dx) + "px," + String(dy) + "px)";
      node.getBoundingClientRect();
      node.style.transition = "transform 220ms cubic-bezier(0.22, 0.9, 0.3, 1)";
      node.style.transform = "";
      (function (animatedNode) {
        window.setTimeout(function () {
          animatedNode.style.transition = "";
          animatedNode.style.transform = "";
        }, 240);
      })(node);
    }
  }

  function isElementScrollAtBottom(element, tolerancePx) {
    if (!element) {
      return true;
    }
    var tolerance = Number(tolerancePx || 0);
    if (!isFinite(tolerance) || tolerance < 0) {
      tolerance = 0;
    }
    var remaining = Number(element.scrollHeight || 0) - Number(element.scrollTop || 0) - Number(element.clientHeight || 0);
    return remaining <= tolerance;
  }

  function snapshotRunThinkingPreviewScroll() {
    if (!el.chatLog) {
      return;
    }
    var previews = el.chatLog.querySelectorAll("details.run-details.run-thinking[data-event-id] .run-live-feed");
    if (!previews || !previews.length) {
      return;
    }
    for (var i = 0; i < previews.length; i += 1) {
      var preview = previews[i];
      var panel = preview.closest("details.run-details.run-thinking[data-event-id]");
      if (!panel) {
        continue;
      }
      var eventId = String(panel.getAttribute("data-event-id") || "");
      if (!eventId) {
        continue;
      }
      state.runStreamScrollTopByEventId[eventId] = Number(preview.scrollTop || 0);
      state.runStreamAutoFollowByEventId[eventId] = isElementScrollAtBottom(preview, 8);
    }
  }

  function automationStatusClass(item) {
    var automationItem = item || {};
    var enabled = String(automationItem.enabled || "0") === "1";
    var status = trim(String(automationItem.last_status || ""));
    if (!enabled) {
      return "paused";
    }
    if (status === "error") {
      return "error";
    }
    return "ready";
  }

  function automationStatusLabel(item) {
    var automationItem = item || {};
    var enabled = String(automationItem.enabled || "0") === "1";
    var status = trim(String(automationItem.last_status || ""));
    if (!enabled) {
      return "Paused";
    }
    if (status === "error") {
      return "Error";
    }
    if (status === "queued" || status === "running") {
      return "Running";
    }
    if (status === "done") {
      return "Ready";
    }
    if (status === "scheduled") {
      return "Scheduled";
    }
    return "Active";
  }

  function renderWorkspaceTree() {
    if (el.workspaceTree) {
      el.workspaceTree.classList.remove("automations-mode");
    }
    var triageCards = Array.isArray(state.triage && state.triage.cards) ? state.triage.cards : [];
    var triageRowHtml = "";
    if (triageCards.length) {
      triageRowHtml += "<div class='workspace-tree-triage-row" + (state.activeTriage ? " active" : "") + "' role='button' tabindex='0' title='Open triage' data-action='select-triage'>";
      triageRowHtml += "<span class='workspace-tree-triage-icon' aria-hidden='true'><svg viewBox='0 0 16 16' fill='none' stroke='currentColor' stroke-width='1.4' stroke-linecap='round' stroke-linejoin='round'><path d='M2.4 4.1h11.2'/><path d='M2.4 8h11.2'/><path d='M2.4 11.9h7.4'/><circle cx='12.3' cy='11.9' r='1.2'></circle></svg></span>";
      triageRowHtml += "<span class='workspace-tree-triage-title'>Triage</span>";
      triageRowHtml += "<span class='workspace-tree-triage-count'>" + escHtml(String(triageCards.length)) + "</span>";
      triageRowHtml += "</div>";
    }

    if (!state.workspaces.length) {
      var emptyMarkup = "";
      if (!state.initialLoadComplete) {
        emptyMarkup = "<p class='empty-state workspace-loading'>Loading projects...<span class='run-spinner' aria-hidden='true'></span></p>";
      } else {
        emptyMarkup = "<p class='empty-state'>Drop a folder here or click + to add a project.</p>";
      }
      if (triageRowHtml) {
        emptyMarkup = triageRowHtml + emptyMarkup;
      }
      if (state.workspaceTreeMarkupCache === emptyMarkup) {
        return;
      }
      el.workspaceTree.innerHTML = emptyMarkup;
      state.workspaceTreeMarkupCache = emptyMarkup;
      return;
    }

    var folderIcon =
      "<span class='workspace-icon' aria-hidden='true'>" +
        "<svg class='folder-closed' viewBox='0 0 16 16' fill='none' stroke='currentColor' stroke-width='1.5' stroke-linecap='round' stroke-linejoin='round'><path d='M1.8 4.2h4.1l1.4 1.7h6.9v7.2H1.8z'/></svg>" +
        "<svg class='folder-open' viewBox='0 0 16 16' fill='none' stroke='currentColor' stroke-width='1.5' stroke-linecap='round' stroke-linejoin='round'><path d='M1.5 5.7h4.2l1.3 1.4h6.5l-1.1 4.8H2.3z'/><path d='M1.7 5.7v-1.5h4.1l1.3 1.5'/></svg>" +
      "</span>";

    var html = "";
    var workspaces = getSortedWorkspaces();
    var showRelevantOnly = state.organizeShow === "relevant";
    var showRunningOnly = state.organizeShow === "running";
    var allowManualReorder = state.organizeMode === "project" && state.organizeShow === "all";

    if (state.organizeMode === "chrono") {
      var entries = [];
      for (var ci = 0; ci < workspaces.length; ci += 1) {
        var chronoWorkspace = workspaces[ci];
        var chronoWorkspaceId = chronoWorkspace.id;
        var chronoConversations = getSortedConversations(chronoWorkspace);
        for (var cj = 0; cj < chronoConversations.length; cj += 1) {
          var chronoConversation = chronoConversations[cj];
          if (showRunningOnly && !isConversationRunning(chronoWorkspaceId, chronoConversation)) {
            continue;
          }
          if (showRelevantOnly && !isConversationRelevant(chronoWorkspaceId, chronoConversation)) {
            continue;
          }
          entries.push({
            workspaceId: chronoWorkspaceId,
            workspaceName: chronoWorkspace.name || "Project",
            conversation: chronoConversation
          });
        }
      }

      entries.sort(function (a, b) {
        var as = state.sortMode === "created" ? conversationCreatedNumber(a.conversation) : conversationUpdatedNumber(a.conversation);
        var bs = state.sortMode === "created" ? conversationCreatedNumber(b.conversation) : conversationUpdatedNumber(b.conversation);
        if (as !== bs) {
          return bs - as;
        }
        return String(a.conversation.title || "").localeCompare(String(b.conversation.title || ""));
      });

      if (!entries.length) {
        html = "<p class='empty-state'>No threads match current organize filters.</p>";
      } else {
        for (var ei = 0; ei < entries.length; ei += 1) {
          var entry = entries[ei];
          var chronoActive = entry.conversation.id === state.activeConversationId ? " active" : "";
          var chronoPending = queueNumber(entry.conversation.queue_pending);
          var chronoRunning = String(entry.conversation.queue_running || "0") === "1";
          var chronoDone = String(entry.conversation.queue_done || "0") === "1";
          if (
            state.busy &&
            state.runningWorkspaceId === entry.workspaceId &&
            state.runningConversationId === entry.conversation.id
          ) {
            chronoRunning = true;
          }

          var chronoIndicatorClass = "thread-indicator";
          if (chronoRunning) {
            chronoIndicatorClass += " running";
          } else if (chronoDone && isConversationUnread(entry.workspaceId, entry.conversation)) {
            chronoIndicatorClass += " done";
          } else if (chronoPending > 0) {
            chronoIndicatorClass += " pending";
          }

          html += "<div class='conversation-row chrono-row" + chronoActive + "' role='button' tabindex='0' title='Open thread' data-action='select-conversation' data-workspace-id='" + escHtml(entry.workspaceId) + "' data-conversation-id='" + escHtml(entry.conversation.id) + "'>";
          html += "<span class='" + chronoIndicatorClass + "' aria-hidden='true'></span>";
          var chronoStatusMarkup = conversationStatusPillMarkup(entry.workspaceId, entry.conversation, chronoRunning);
          var chronoTooltip = threadFolderPathTooltip(entry.workspaceId);
          var chronoTooltipAttr = chronoTooltip ? " data-tooltip='" + escAttr(chronoTooltip) + "'" : "";
          html += "<span class='conversation-title'" + chronoTooltipAttr + ">" + escHtml(conversationDisplayTitle(entry.conversation.title)) + "</span>";
          html += chronoStatusMarkup;
          if (chronoPending > 0) {
            html += "<span class='queue-count'>" + chronoPending + "</span>";
          }
          html += conversationMetaMarkup(entry.workspaceId, entry.conversation);
          html += "</div>";
        }
      }
    } else {
      for (var i = 0; i < workspaces.length; i += 1) {
        var workspace = workspaces[i];
        var workspaceId = workspace.id;
        var isActiveWorkspace = workspaceId === state.activeWorkspaceId;
        var isExpanded = !!state.expandedWorkspaceIds[workspaceId];
        if (typeof state.expandedWorkspaceIds[workspaceId] === "undefined") {
          isExpanded = true;
          state.expandedWorkspaceIds[workspaceId] = true;
        }

        var filteredConversations = [];
        var conversations = getSortedConversations(workspace);
        for (var fc = 0; fc < conversations.length; fc += 1) {
          if (showRunningOnly && !isConversationRunning(workspaceId, conversations[fc])) {
            continue;
          }
          if (!showRelevantOnly || isConversationRelevant(workspaceId, conversations[fc])) {
            filteredConversations.push(conversations[fc]);
          }
        }

        if (showRunningOnly && !filteredConversations.length) {
          continue;
        }

        if (showRelevantOnly && !filteredConversations.length && !hasDraftForWorkspace(workspace) && !isActiveWorkspace) {
          continue;
        }

        var groupClass = "workspace-group";
        if (isExpanded) {
          groupClass += " expanded";
        }

        html += "<section class='" + groupClass + "' data-workspace-id='" + escHtml(workspaceId) + "'>";
        html += "<div class='workspace-row' " + (allowManualReorder ? "draggable='true' data-drag-type='workspace' " : "") + "data-action='select-workspace' data-workspace-id='" + escHtml(workspaceId) + "'>";
        if (allowManualReorder) {
          html += "<button type='button' class='workspace-drag-handle' data-action='workspace-drag-handle' data-workspace-id='" + escHtml(workspaceId) + "' aria-label='Drag to reorder project' title='Drag to reorder project'>&#8942;&#8942;</button>";
        }
        html += folderIcon;
        html += "<button type='button' class='workspace-caret' data-action='toggle-workspace' data-workspace-id='" + escHtml(workspaceId) + "' aria-label='Toggle' title='Expand or collapse project'><span aria-hidden='true'>&rsaquo;</span></button>";
        var bgResidentsCount = Number(workspace.multi_agent_background_residents || 0);
        var workspaceLabel = escHtml(workspace.name || "Project");
        if (isFinite(bgResidentsCount) && bgResidentsCount > 0) {
          workspaceLabel += " <span class='workspace-brain-badge' title='Background agents active' aria-label='Background agents active'>" + reasoningIconMarkup() + "</span>";
        }
        html += "<div class='workspace-meta' title='" + escAttr(workspace.path || "") + "'>" + workspaceLabel + "</div>";
        html += "<button type='button' class='workspace-menu-trigger' data-action='toggle-workspace-menu' data-workspace-id='" + escHtml(workspaceId) + "' aria-label='Project menu' title='Project actions' aria-expanded='" + (state.openWorkspaceMenuWorkspaceId === workspaceId ? "true" : "false") + "'>&hellip;</button>";
        html += "<button type='button' class='workspace-new' data-action='new-conversation' data-workspace-id='" + escHtml(workspaceId) + "' aria-label='New thread' title='New thread'><span aria-hidden='true'><svg viewBox='0 0 16 16' fill='none' stroke='currentColor' stroke-width='1.35' stroke-linecap='round' stroke-linejoin='round'><rect x='2.2' y='2.1' width='11.6' height='11.8' rx='1.6'></rect><path d='M6.1 9.8l-.5 2 2-.5 3.8-3.8-1.5-1.5z'></path><path d='M9.8 6.1l1.5 1.5'></path></svg></span></button>";
        var workspaceMenuClass = "workspace-actions-pop floating-menu";
        if (state.openWorkspaceMenuWorkspaceId !== workspaceId) {
          workspaceMenuClass += " hidden";
        }
        html += "<div class='" + workspaceMenuClass + "' data-workspace-menu='" + escHtml(workspaceId) + "' role='menu' aria-label='Project actions'>";
        html += "<button type='button' data-action='open-workspace-multi_agent' data-workspace-id='" + escHtml(workspaceId) + "'>Manage agents...</button>";
        html += "<button type='button' data-action='open-workspace-approvals' data-workspace-id='" + escHtml(workspaceId) + "'>Command approvals...</button>";
        html += "<button type='button' data-action='rename-workspace' data-workspace-id='" + escHtml(workspaceId) + "'>Rename</button>";
        html += "<button type='button' data-action='remove-workspace' data-workspace-id='" + escHtml(workspaceId) + "'>Remove</button>";
        html += "</div>";
        html += "</div>";

        html += "<div class='conversation-shell'>";

        if (hasDraftForWorkspace(workspace)) {
          var draftActive = state.activeDraftWorkspaceId === workspaceId ? " active" : "";
          html += "<button type='button' class='conversation-draft" + draftActive + "' data-action='select-draft' data-workspace-id='" + escHtml(workspaceId) + "'>Draft (unsent)</button>";
        }

        if (!filteredConversations.length && !hasDraftForWorkspace(workspace)) {
          html += "<div class='conversation-empty' aria-hidden='true'>No threads</div>";
        }

        for (var j = 0; j < filteredConversations.length; j += 1) {
          var conversation = filteredConversations[j];
          var activeConv = conversation.id === state.activeConversationId ? " active" : "";
          var queuePending = queueNumber(conversation.queue_pending);
          var queueRunning = String(conversation.queue_running || "0") === "1";
          var queueDone = String(conversation.queue_done || "0") === "1";
          if (
            state.busy &&
            state.runningWorkspaceId === workspaceId &&
            state.runningConversationId === conversation.id
          ) {
            queueRunning = true;
          }

          var indicatorClass = "thread-indicator";
          var unreadDone = queueDone && isConversationUnread(workspaceId, conversation);
          if (queueRunning) {
            indicatorClass += " running";
          } else if (unreadDone) {
            indicatorClass += " done";
          } else if (queuePending > 0) {
            indicatorClass += " pending";
          }

          html += "<div class='conversation-row" + activeConv + "' " + (allowManualReorder ? "draggable='true' data-drag-type='conversation' " : "") + "role='button' tabindex='0' title='Open thread' data-action='select-conversation' data-workspace-id='" + escHtml(workspaceId) + "' data-conversation-id='" + escHtml(conversation.id) + "'>";
          if (allowManualReorder) {
            html += "<button type='button' class='conversation-drag-handle' data-action='conversation-drag-handle' data-workspace-id='" + escHtml(workspaceId) + "' data-conversation-id='" + escHtml(conversation.id) + "' aria-label='Drag to reorder thread' title='Drag to reorder thread'>&#8942;&#8942;</button>";
          }
          html += "<span class='" + indicatorClass + "' aria-hidden='true'></span>";
          var statusMarkup = conversationStatusPillMarkup(workspaceId, conversation, queueRunning);
          var threadTooltip = threadFolderPathTooltip(workspaceId);
          var threadTooltipAttr = threadTooltip ? " data-tooltip='" + escAttr(threadTooltip) + "'" : "";
          html += "<span class='conversation-title'" + threadTooltipAttr + ">" + escHtml(conversationDisplayTitle(conversation.title)) + "</span>";
          html += statusMarkup;
          if (queuePending > 0) {
            html += "<span class='queue-count'>" + queuePending + "</span>";
          }
          html += conversationMetaMarkup(workspaceId, conversation);
          html += "</div>";
        }

        html += "</div>";
        html += "</section>";
      }
    }

    if (!trim(html)) {
      html = "<p class='empty-state'>No threads match current organize filters.</p>";
    }

    if (triageRowHtml) {
      html = triageRowHtml + html;
    }

    if (state.workspaceTreeMarkupCache === html) {
      return;
    }

    var previousPositions = snapshotWorkspaceTreePositions();
    el.workspaceTree.innerHTML = html;
    state.workspaceTreeMarkupCache = html;
    animateWorkspaceTreeFromSnapshot(previousPositions);
  }

  function findWorkspaceGroupElement(workspaceId) {
    if (!el.workspaceTree || !workspaceId) {
      return null;
    }
    var groups = el.workspaceTree.querySelectorAll(".workspace-group[data-workspace-id]");
    for (var i = 0; i < groups.length; i += 1) {
      if (String(groups[i].dataset.workspaceId || "") === String(workspaceId || "")) {
        return groups[i];
      }
    }
    return null;
  }

  function animateWorkspaceGroupToggle(workspaceId, expand) {
    var group = findWorkspaceGroupElement(workspaceId);
    if (!group) {
      return false;
    }
    var shell = group.querySelector(".conversation-shell");
    if (!shell) {
      group.classList.toggle("expanded", !!expand);
      return true;
    }

    var shouldExpand = !!expand;
    var currentlyExpanded = group.classList.contains("expanded");
    if (currentlyExpanded === shouldExpand && !shell.classList.contains("is-animating")) {
      return true;
    }

    if (shell._workspaceAnimEndHandler) {
      shell.removeEventListener("transitionend", shell._workspaceAnimEndHandler);
      shell._workspaceAnimEndHandler = null;
    }
    if (shell._workspaceAnimTimer) {
      window.clearTimeout(shell._workspaceAnimTimer);
      shell._workspaceAnimTimer = 0;
    }

    shell.classList.add("is-animating");
    shell.style.willChange = "max-height, opacity";

    var done = function () {
      shell.classList.remove("is-animating");
      shell.style.willChange = "";
      shell.style.opacity = "";
      shell.style.maxHeight = shouldExpand ? "none" : "0px";
    };

    var onEnd = function (event) {
      if (event && event.target !== shell) {
        return;
      }
      if (event && event.propertyName && event.propertyName !== "max-height") {
        return;
      }
      if (shell._workspaceAnimEndHandler) {
        shell.removeEventListener("transitionend", shell._workspaceAnimEndHandler);
        shell._workspaceAnimEndHandler = null;
      }
      if (shell._workspaceAnimTimer) {
        window.clearTimeout(shell._workspaceAnimTimer);
        shell._workspaceAnimTimer = 0;
      }
      done();
    };

    shell._workspaceAnimEndHandler = onEnd;
    shell.addEventListener("transitionend", onEnd);
    shell._workspaceAnimTimer = window.setTimeout(onEnd, 380);

    if (shouldExpand) {
      group.classList.add("expanded");
      shell.style.maxHeight = "0px";
      shell.style.opacity = "0.02";
      window.requestAnimationFrame(function () {
        var targetHeight = shell.scrollHeight;
        shell.style.maxHeight = Math.max(1, targetHeight) + "px";
        shell.style.opacity = "1";
      });
      return true;
    }

    var startHeight = shell.scrollHeight;
    shell.style.maxHeight = Math.max(1, startHeight) + "px";
    shell.style.opacity = "1";
    window.requestAnimationFrame(function () {
      group.classList.remove("expanded");
      shell.style.maxHeight = "0px";
      shell.style.opacity = "0.02";
    });
    return true;
  }

  function setWorkspaceExpanded(workspaceId, expanded, options) {
    if (!workspaceId) {
      return;
    }
    state.expandedWorkspaceIds[workspaceId] = !!expanded;
    if (options && options.animate && animateWorkspaceGroupToggle(workspaceId, expanded)) {
      return;
    }
    renderUi();
  }

  function renderModelStatus() {
    if (!el.modelStatusBtn) {
      return;
    }
    if (state.modelLoadError) {
      el.modelStatusBtn.textContent = "Models unavailable";
      el.modelStatusBtn.title = "Could not read Ollama models";
      return;
    }
    var installedCount = Number(state.models.length || 0);
    var downloadingCount = 0;
    var installingCount = 0;
    var runningOtherCount = 0;
    var runningSeen = {};

    for (var i = 0; i < state.modelInstalls.length; i += 1) {
      var job = state.modelInstalls[i] || {};
      if (String(job.status || "") !== "running") {
        continue;
      }
      var jobId = String(job.id || "");
      if (jobId && runningSeen[jobId]) {
        continue;
      }
      if (jobId) {
        runningSeen[jobId] = true;
      }
      var phase = String(job.phase || "").toLowerCase();
      if (phase === "downloading") {
        downloadingCount += 1;
      } else if (phase === "installing") {
        installingCount += 1;
      } else {
        runningOtherCount += 1;
      }
    }

    var hasExtraRunning = false;
    if (state.modelInstallJob && String(state.modelInstallJob.status || "") === "running") {
      var activeJobId = String(state.modelInstallJob.id || "");
      if (!activeJobId || !runningSeen[activeJobId]) {
        hasExtraRunning = true;
        var activePhase = String(state.modelInstallJob.phase || "").toLowerCase();
        if (activePhase === "downloading") {
          downloadingCount += 1;
        } else if (activePhase === "installing") {
          installingCount += 1;
        } else {
          runningOtherCount += 1;
        }
      }
    }

    if (!installedCount && !downloadingCount && !installingCount && !runningOtherCount && state.modelDataLoading) {
      el.modelStatusBtn.textContent = "Loading models...";
      el.modelStatusBtn.title = "Loading Ollama models";
      return;
    }

    if (!installedCount && !downloadingCount && !installingCount && !runningOtherCount) {
      el.modelStatusBtn.textContent = "No models";
      el.modelStatusBtn.title = "No Ollama models detected";
      return;
    }

    var noun = installedCount === 1 ? "model" : "models";
    var parts = [installedCount + " " + noun];
    if (downloadingCount > 0) {
      parts.push(downloadingCount + " downloading");
    }
    if (installingCount > 0) {
      parts.push(installingCount + " installing");
    }
    if (runningOtherCount > 0) {
      parts.push(runningOtherCount + " preparing");
    }
    el.modelStatusBtn.textContent = parts.join(", ");

    var title = installedCount + " Ollama " + noun + " installed";
    if (downloadingCount > 0 || installingCount > 0 || runningOtherCount > 0 || hasExtraRunning) {
      var tail = [];
      if (downloadingCount > 0) {
        tail.push(downloadingCount + " downloading");
      }
      if (installingCount > 0) {
        tail.push(installingCount + " installing");
      }
      if (runningOtherCount > 0) {
        tail.push(runningOtherCount + " preparing");
      }
      if (tail.length) {
        title += ", " + tail.join(", ");
      }
    }
    el.modelStatusBtn.title = title;
  }

  function isModelInstalled(modelName) {
    var target = String(modelName || "");
    if (!target) {
      return false;
    }
    for (var i = 0; i < state.models.length; i += 1) {
      if (String(state.models[i]) === target) {
        return true;
      }
    }
    return false;
  }

  function currentModelInstallFor(modelName) {
    var target = String(modelName || "");
    if (!target || !Array.isArray(state.modelInstalls)) {
      return null;
    }
    for (var i = 0; i < state.modelInstalls.length; i += 1) {
      var job = state.modelInstalls[i] || {};
      if (String(job.model || "") !== target) {
        continue;
      }
      if (String(job.status || "") === "running") {
        return job;
      }
      if (!state.modelInstallJob || String(job.id || "") === String(state.modelInstallJob.id || "")) {
        return job;
      }
    }
    return null;
  }

  function catalogEntryForModel(modelName) {
    var target = trim(String(modelName || ""));
    if (!target || !Array.isArray(state.modelCatalog)) {
      return null;
    }
    for (var i = 0; i < state.modelCatalog.length; i += 1) {
      var entry = state.modelCatalog[i] || {};
      if (String(entry.name || "") === target) {
        return entry;
      }
    }
    return null;
  }

  function formatCatalogSizeLabel(sizeRaw) {
    var parsed = Number(sizeRaw);
    if (!isFinite(parsed) || parsed <= 0) {
      return "";
    }
    return parsed.toFixed(1) + "GB";
  }

  function numericProgressPercent(rawValue) {
    var parsed = Number(rawValue);
    if (!isFinite(parsed)) {
      return -1;
    }
    var rounded = Math.round(parsed);
    if (rounded < 0) {
      rounded = 0;
    }
    if (rounded > 100) {
      rounded = 100;
    }
    return rounded;
  }

  function modelInstallStatusLabel(job) {
    var installJob = job || {};
    var status = String(installJob.status || "");
    var phase = String(installJob.phase || "");
    var pct = numericProgressPercent(installJob.progress_pct);
    var resumeAvailable = !!installJob.resume_available;
    if (status === "done") {
      return "Installed";
    }
    if (status === "failed") {
      return "Retry install";
    }
    if (phase === "downloading") {
      if (resumeAvailable) {
        if (pct >= 0) {
          return "Resuming " + String(pct) + "%";
        }
        return "Resuming download…";
      }
      if (pct >= 0) {
        return "Downloading " + String(pct) + "%";
      }
      return "Downloading…";
    }
    if (phase === "installing") {
      return "Installing…";
    }
    return "Installing…";
  }

  function renderModelsDialog() {
    if (!el.modelsBoxList) {
      return;
    }

    var activeModel = activeModelName();
    var html = "";
    if (state.modelLoadError) {
      html += "<p class='empty-state'>Could not load models right now.</p>";
    }

    html += "<div class='models-section'><p class='models-section-title'>Installed</p>";
    if (!state.models.length) {
      html += "<p class='empty-state'>No installed models yet.</p>";
    } else {
      for (var i = 0; i < state.models.length; i += 1) {
        var model = state.models[i];
        var parts = parseModelDisplay(model);
        var activeClass = model === activeModel ? " active" : "";
        var installedEntry = catalogEntryForModel(model);
        var installedDescription = trim(installedEntry && installedEntry.description ? installedEntry.description : "");
        var installedSizeLabel = formatCatalogSizeLabel(installedEntry && installedEntry.size_gb ? installedEntry.size_gb : "");
        html += "<div class='catalog-item catalog-item-installed" + activeClass + "'>";
        html += "<button type='button' class='catalog-model-select' data-model-name='" + escAttr(model) + "' title='Use this model'>";
        html += "<span class='model-heading'><span class='model-primary'>" + escHtml(parts.primary) + "</span>";
        if (parts.meta) {
          html += "<span class='model-meta-inline'>" + escHtml(parts.meta) + "</span>";
        }
        html += "</span>";
        if (installedDescription) {
          html += "<span class='catalog-description'>" + escHtml(installedDescription) + "</span>";
        }
        html += "</button>";
        html += "<div class='catalog-actions'>";
        html += "<button type='button' class='catalog-install-btn catalog-uninstall-btn' data-action='uninstall-model' data-model-name='" + escAttr(model) + "'>Uninstall</button>";
        if (installedSizeLabel) {
          html += "<span class='catalog-size catalog-size-right'>" + escHtml(installedSizeLabel) + "</span>";
        }
        html += "</div>";
        html += "</div>";
      }
    }
    html += "</div>";

    html += "<div class='models-section'><p class='models-section-title'>Install curated models</p>";
    if (!Array.isArray(state.modelCatalog) || !state.modelCatalog.length) {
      html += "<p class='empty-state'>No curated models list found.</p>";
    } else {
      for (var j = 0; j < state.modelCatalog.length; j += 1) {
        var entry = state.modelCatalog[j] || {};
        var modelName = String(entry.name || "");
        if (!modelName) {
          continue;
        }
        var modelParts = parseModelDisplay(modelName);
        var description = trim(entry.description || "");
        var sizeLabel = formatCatalogSizeLabel(entry.size_gb);
        var isInstalled = isModelInstalled(modelName);
        var installJob = currentModelInstallFor(modelName);
        var isInstalling = !!(installJob && String(installJob.status || "") === "running");
        var isFailedInstall = !!(installJob && String(installJob.status || "") === "failed");
        var installLabel = installJob ? modelInstallStatusLabel(installJob) : "Install";
        var installDisabled = isInstalling;
        if (isFailedInstall && !isInstalled) {
          installDisabled = false;
        }
        if (isInstalled) {
          continue;
        }
        html += "<div class='catalog-item'>";
        html += "<div class='catalog-copy'><span class='model-heading'><span class='model-primary'>" + escHtml(modelParts.primary) + "</span>";
        if (modelParts.meta) {
          html += "<span class='model-meta-inline'>" + escHtml(modelParts.meta) + "</span>";
        }
        html += "</span>";
        if (description) {
          html += "<span class='catalog-description'>" + escHtml(description) + "</span>";
        }
        html += "</div>";
        html += "<div class='catalog-actions'>";
        html += "<button type='button' class='catalog-install-btn" + (installDisabled ? " disabled" : "") + "' data-action='install-model' data-model-name='" + escAttr(modelName) + "'" + (installDisabled ? " disabled" : "") + ">" + escHtml(installLabel) + "</button>";
        if (sizeLabel) {
          html += "<span class='catalog-size catalog-size-right'>" + escHtml(sizeLabel) + "</span>";
        }
        html += "</div>";
        html += "</div>";
      }
    }
    html += "</div>";

    if (state.modelInstallJob && trim(state.modelInstallLog || "")) {
      var jobModel = String(state.modelInstallJob.model || "");
      var jobStatus = String(state.modelInstallJob.status || "running");
      var jobPhase = String(state.modelInstallJob.phase || "");
      var jobProgress = numericProgressPercent(state.modelInstallJob.progress_pct);
      var phaseLabel = "";
      if (jobStatus === "running") {
        if (jobPhase === "downloading") {
          phaseLabel = jobProgress >= 0
            ? "downloading " + String(jobProgress) + "%"
            : "downloading";
        } else if (jobPhase === "installing") {
          phaseLabel = "installing";
        }
      }
      html += "<div class='models-section install-log-section'>";
      html += "<p class='models-section-title'>Install log: " + escHtml(jobModel) + " (" + escHtml(jobStatus + (phaseLabel ? ", " + phaseLabel : "")) + ")</p>";
      html += "<pre class='install-log'>" + escHtml(state.modelInstallLog) + "</pre>";
      html += "</div>";
    }

    el.modelsBoxList.innerHTML = html;
  }

  function themeLabel(name) {
    var raw = String(name || "");
    if (!raw) {
      return "Psionic";
    }
    return raw
      .replace(/[-_]+/g, " ")
      .replace(/\b[a-z]/g, function (m) {
        return m.toUpperCase();
      });
  }

  function themeNameListFallback() {
    return [
      "psionic",
      "adept",
      "alchemist",
      "archmage",
      "chronomancer",
      "conjurer",
      "druid",
      "empath",
      "enchanter",
      "geomancer",
      "hermeticist",
      "hierophant",
      "illusionist",
      "lich",
      "necromancer",
      "pyromancer",
      "seer",
      "shaman",
      "sorcerer",
      "sorceress",
      "technomancer",
      "thaumaturge",
      "thelemite",
      "theurgist",
      "wadjet",
      "warlock",
      "wizard"
    ];
  }

  function normalizeThemes(list) {
    var out = [];
    var seen = {};
    var input = Array.isArray(list) ? list : [];
    for (var i = 0; i < input.length; i += 1) {
      var item = trim(String(input[i] || "")).toLowerCase();
      if (!item || !/^[a-z0-9_-]+$/.test(item) || seen[item]) {
        continue;
      }
      seen[item] = true;
      out.push(item);
    }
    if (!seen.psionic) {
      out.unshift("psionic");
    }
    out.sort(function (a, b) {
      return a.localeCompare(b);
    });
    return out;
  }

  function ensureActiveThemeInList() {
    if (!state.themes.length) {
      state.themes = normalizeThemes(themeNameListFallback());
    }
    if (state.themes.indexOf(state.activeTheme) < 0) {
      state.activeTheme = "psionic";
      storageSet("artificer.activeTheme", state.activeTheme);
    }
  }

  function applyTheme(themeName) {
    var normalized = trim(String(themeName || "")).toLowerCase();
    if (!normalized || !/^[a-z0-9_-]+$/.test(normalized)) {
      normalized = "psionic";
    }
    state.activeTheme = normalized;
    storageSet("artificer.activeTheme", normalized);
    if (document && document.documentElement) {
      document.documentElement.setAttribute("data-theme", normalized);
    }
    if (el.themeStylesheet) {
      el.themeStylesheet.href = "/static/themes/" + normalized + ".css?v=20260217-themefix01";
    }
  }

  function renderThemePicker() {
    if (!el.themePickerBtn || !el.themePickerList) {
      return;
    }
    ensureActiveThemeInList();
    el.themePickerBtn.textContent = themeLabel(state.activeTheme);
    el.themePickerBtn.setAttribute("data-tooltip", "Theme: " + themeLabel(state.activeTheme));

    var html = "";
    for (var i = 0; i < state.themes.length; i += 1) {
      var theme = state.themes[i];
      var activeClass = theme === state.activeTheme ? " active" : "";
      html += "<button type='button' class='theme-item" + activeClass + "' data-theme-name='" + escAttr(theme) + "'>" + escHtml(themeLabel(theme)) + "</button>";
    }
    el.themePickerList.innerHTML = html;
  }

  function cycleTheme(step) {
    ensureActiveThemeInList();
    if (!state.themes.length) {
      return;
    }
    var delta = step < 0 ? -1 : 1;
    var currentIndex = state.themes.indexOf(state.activeTheme);
    if (currentIndex < 0) {
      currentIndex = 0;
    }
    var nextIndex = currentIndex + delta;
    if (nextIndex < 0) {
      nextIndex = state.themes.length - 1;
    } else if (nextIndex >= state.themes.length) {
      nextIndex = 0;
    }
    applyTheme(state.themes[nextIndex]);
    renderThemePicker();
  }

  function renderModelListInto(containerEl, activeModel) {
    if (!containerEl) {
      return;
    }

    if (!state.models.length) {
      containerEl.innerHTML = "<p class='empty-state'>No models detected.</p>";
      return;
    }

    var html = "";
    for (var i = 0; i < state.models.length; i += 1) {
      var model = state.models[i];
      var parts = parseModelDisplay(model);
      var activeClass = model === activeModel ? " active" : "";
      html += "<button type='button' class='model-item" + activeClass + "' data-model-name='" + escHtml(model) + "'>";
      html += "<span class='model-primary'>" + escHtml(parts.primary) + "</span>";
      html += "<span class='model-meta'>" + escHtml(parts.meta || parts.raw) + "</span>";
      html += "</button>";
    }

    containerEl.innerHTML = html;
  }

  function renderModelPickerButton() {
    if (!el.modelPickerBtn) {
      return;
    }
    var model = activeModelName();
    if (!model) {
      el.modelPickerBtn.innerHTML = "<span class='model-primary'>Select model</span>";
      return;
    }
    var parts = parseModelDisplay(model);
    el.modelPickerBtn.innerHTML = "<span class='model-primary'>" + escHtml(parts.primary) + "</span><span class='model-meta'>" + escHtml(parts.meta || parts.raw) + "</span>";
  }

  function renderRunModeMoreList() {
    if (!el.runModeMoreList) {
      return;
    }
    var runtime = normalizeModeRuntime(state.modeRuntime);
    var modes = Array.isArray(runtime.modes) ? runtime.modes.slice(0) : [];
    var html = "";
    html += "<button type='button' class='run-mode-advanced-item' data-assistant-mode-id=''>";
    html += "<span class='run-mode-row'><span class='run-mode-name'>General Team</span><span class='check' aria-hidden='true'>&check;</span></span>";
    html += "<span class='run-mode-blurb'>No specialized team policy.</span>";
    html += "</button>";
    for (var i = 0; i < modes.length; i += 1) {
      var mode = modes[i] || {};
      var modeId = trim(String(mode.id || ""));
      if (!modeId) {
        continue;
      }
      var blurb = trim(String(mode.description || ""));
      var details = blurb || "Specialized governance mode.";
      html += "<button type='button' class='run-mode-advanced-item' data-assistant-mode-id='" + escAttr(modeId) + "'>";
      html += "<span class='run-mode-row'><span class='run-mode-name'>" + escHtml(mode.name || modeId) + "</span><span class='check' aria-hidden='true'>&check;</span></span>";
      html += "<span class='run-mode-blurb'>" + escHtml(details) + "</span>";
      html += "</button>";
    }
    if (!modes.length) {
      html += "<p class='settings-hint' style='margin:0;padding:8px 10px;'>No teams found. Open Settings to configure teams.</p>";
    }
    el.runModeMoreList.innerHTML = html;
  }

  function renderRunControls() {
    if (el.runModeBtn) {
      var mode = normalizeRunMode(state.runMode);
      el.runModeBtn.textContent = runModeLabel(mode);
      el.runModeBtn.title = runModeDescription(mode);
      el.runModeBtn.setAttribute("aria-label", "Run mode: " + runModeLabel(mode) + ". " + runModeDescription(mode));
    }

    if (el.runModeMenu) {
      renderRunModeMoreList();
      var modeItems = el.runModeMenu.querySelectorAll("button[data-run-mode]");
      for (var mi = 0; mi < modeItems.length; mi += 1) {
        var modeValue = normalizeRunMode(modeItems[mi].getAttribute("data-run-mode"));
        modeItems[mi].classList.toggle("active", modeValue === normalizeRunMode(state.runMode));
        var modeBlurb = modeItems[mi].querySelector(".run-mode-blurb");
        if (modeBlurb) {
          modeBlurb.classList.toggle("hidden", !state.runModeMoreExpanded);
        }
      }
      var advancedItems = el.runModeMenu.querySelectorAll("button[data-assistant-mode-id]");
      for (var ai = 0; ai < advancedItems.length; ai += 1) {
        var profileId = trim(String(advancedItems[ai].getAttribute("data-assistant-mode-id") || ""));
        var active = normalizeRunMode(state.runMode) === "assistant" && profileId === normalizeAssistantModeId(state.assistantModeId);
        advancedItems[ai].classList.toggle("active", active);
      }
    }

    if (el.runModeMoreToggle) {
      var teamToggleLabel = "Team \u203a";
      var activeTeamLabel = assistantModeLabel(state.assistantModeId);
      if (activeTeamLabel) {
        teamToggleLabel = "Team \u203a " + activeTeamLabel;
      }
      var toggleLabelEl = el.runModeMoreToggle.querySelector("span");
      if (toggleLabelEl) {
        toggleLabelEl.textContent = teamToggleLabel;
      }
      el.runModeMoreToggle.setAttribute("aria-label", teamToggleLabel);
      el.runModeMoreToggle.setAttribute("aria-expanded", state.runModeMoreExpanded ? "true" : "false");
    }
    if (el.runModeMoreList) {
      el.runModeMoreList.classList.toggle("hidden", !state.runModeMoreExpanded);
    }

    if (el.agentLoopToggle) {
      el.agentLoopToggle.classList.toggle("on", !!state.agentLoopEnabled);
      el.agentLoopToggle.setAttribute("aria-pressed", state.agentLoopEnabled ? "true" : "false");
      el.agentLoopToggle.title = state.agentLoopEnabled ? "Advanced agentive loop is on" : "Quick single-pass mode is on";
    }

    if (el.reasoningMenuBtn) {
      el.reasoningMenuBtn.innerHTML =
        "<span class='menu-icon reasoning-brain-icon' aria-hidden='true'>" + reasoningIconMarkup() + "</span>" +
        "<span>" + escHtml(reasoningLabel(state.reasoningEffort)) + "</span>";
    }

    if (el.reasoningMenu) {
      var buttons = el.reasoningMenu.querySelectorAll("button[data-reasoning]");
      for (var i = 0; i < buttons.length; i += 1) {
        var level = buttons[i].getAttribute("data-reasoning");
        buttons[i].classList.toggle("active", level === state.reasoningEffort);
      }
    }

    if (el.computeMenuBtn) {
      el.computeMenuBtn.innerHTML =
        "<span class='menu-icon compute-clock-icon' aria-hidden='true'><svg viewBox='0 0 16 16' fill='none' stroke='currentColor' stroke-width='1.35' stroke-linecap='round' stroke-linejoin='round'><circle cx='8' cy='8' r='5.6'></circle><path d='M8 4.9v3.4l2.2 1.4'></path></svg></span>" +
        "<span>" + escHtml(computeBudgetLabel(state.computeBudget)) + "</span>";
      el.computeMenuBtn.setAttribute("aria-label", "Compute budget: " + computeBudgetLabel(state.computeBudget));
    }

    if (el.computeMenu) {
      var computeButtons = el.computeMenu.querySelectorAll("button[data-compute-budget]");
      for (var ci = 0; ci < computeButtons.length; ci += 1) {
        var budget = normalizeComputeBudget(computeButtons[ci].getAttribute("data-compute-budget"));
        computeButtons[ci].classList.toggle("active", budget === normalizeComputeBudget(state.computeBudget));
      }
    }

    var triageMode = !!state.activeTriage;
    if (el.toolbar) {
      el.toolbar.classList.toggle("triage-toolbar-mode", triageMode);
    }
    if (el.triageToolbarActions) {
      el.triageToolbarActions.classList.toggle("hidden", !triageMode);
    }
    if (!triageMode && el.triageCleanupMenu && !el.triageCleanupMenu.classList.contains("hidden")) {
      el.triageCleanupMenu.classList.add("hidden");
    }
  }

  function renderProgrammingSettings() {
    if (el.programmerReviewToggle) {
      el.programmerReviewToggle.checked = !!state.programmerReviewEnabled;
    }
    if (el.programmerReviewRounds) {
      var roundsValue = String(normalizeProgrammerReviewRoundsValue(state.programmerReviewRounds));
      if (el.programmerReviewRounds.value !== roundsValue) {
        el.programmerReviewRounds.value = roundsValue;
      }
      el.programmerReviewRounds.disabled = !state.programmerReviewEnabled;
    }
    if (el.programmerReviewHint) {
      var modeValue = normalizeRunMode(state.runMode);
      if (!state.programmerReviewEnabled) {
        el.programmerReviewHint.textContent = "Programming mode will skip built-in code review.";
      } else if (modeValue === "programming" || modeValue === "pentest" || modeValue === "security-audit") {
        el.programmerReviewHint.textContent = "Current build mode will run a reviewer pass for up to " + state.programmerReviewRounds + " round" + (state.programmerReviewRounds === 1 ? "" : "s") + ".";
      } else {
        el.programmerReviewHint.textContent = "Applies whenever Run mode is Programming, Pentest, or Security Audit.";
      }
    }
  }

  function renderRunButton() {
    if (!el.runBtn) {
      return;
    }
    var hasPrompt = trim(el.runPrompt ? el.runPrompt.value : "") !== "";
    var canRun = hasPrompt && !!(state.activeWorkspaceId || state.activeDraftWorkspaceId || state.activeConversationId);
    var runningHere =
      state.busy &&
      state.activeWorkspaceId &&
      state.activeConversationId &&
      state.runningWorkspaceId === state.activeWorkspaceId &&
      state.runningConversationId === state.activeConversationId;
    var hasRunningTarget = !!runningConversationTarget();

    el.runBtn.disabled = !canRun;
    el.runBtn.setAttribute("data-tooltip", "Send message. Right-click for Queue/Stop options.");
    if (runningHere) {
      el.runBtn.classList.add("running");
      el.runBtn.innerHTML = "<span aria-hidden='true'>...</span>";
    } else {
      el.runBtn.classList.remove("running");
      el.runBtn.innerHTML = "<span aria-hidden='true'>&uarr;</span>";
    }
    if (el.sendMenuQueueBtn) {
      el.sendMenuQueueBtn.disabled = !canRun;
    }
    if (el.sendMenuStopBtn) {
      el.sendMenuStopBtn.disabled = !hasRunningTarget;
    }
  }

  function clearDictationUiTicker() {
    if (dictationUiTickTimer) {
      clearInterval(dictationUiTickTimer);
      dictationUiTickTimer = null;
    }
  }

  function formatDictationElapsed(ms) {
    var total = Number(ms);
    if (!isFinite(total) || total < 0) {
      total = 0;
    }
    var seconds = Math.floor(total / 1000);
    var minutes = Math.floor(seconds / 60);
    var rem = seconds % 60;
    return String(minutes) + ":" + (rem < 10 ? "0" : "") + String(rem);
  }

  function dictationWaveTargetBarCount() {
    if (!el.dictationWave) {
      return 42;
    }
    var width = 0;
    try {
      width = Number(el.dictationWave.clientWidth || 0);
      if (!width && el.dictationWave.getBoundingClientRect) {
        width = Number(el.dictationWave.getBoundingClientRect().width || 0);
      }
    } catch (_err) {
      width = 0;
    }
    if (!isFinite(width) || width <= 0) {
      return 42;
    }
    // Match fixed bar geometry (2px bar + 1px gap) so the lane fills fully.
    var count = Math.floor((width + 1) / 3);
    if (!isFinite(count) || count < 32) {
      count = 32;
    } else if (count > 180) {
      count = 180;
    }
    return count;
  }

  function syncDictationWaveLevelsLength(targetCount) {
    var count = Number(targetCount || 0);
    if (!isFinite(count) || count < 1) {
      count = 64;
    }
    var levels = Array.isArray(state.dictateWaveLevels) ? state.dictateWaveLevels.slice() : [];
    if (levels.length > count) {
      levels = levels.slice(levels.length - count);
    } else if (levels.length < count) {
      while (levels.length < count) {
        levels.unshift(0);
      }
    }
    state.dictateWaveLevels = levels;
    return levels;
  }

  function ensureDictationWaveBars() {
    if (!el.dictationWave) {
      return [];
    }
    var targetCount = dictationWaveTargetBarCount();
    var bars = el.dictationWave.querySelectorAll(".dictation-wave-bar");
    if (bars && bars.length === targetCount) {
      syncDictationWaveLevelsLength(targetCount);
      return bars;
    }
    var html = "";
    for (var i = 0; i < targetCount; i += 1) {
      html += "<span class='dictation-wave-bar' aria-hidden='true'></span>";
    }
    el.dictationWave.innerHTML = html;
    syncDictationWaveLevelsLength(targetCount);
    return el.dictationWave.querySelectorAll(".dictation-wave-bar");
  }

  function clearDictationWaveWarmReleaseTimer() {
    if (dictationWaveWarmReleaseTimer) {
      clearTimeout(dictationWaveWarmReleaseTimer);
      dictationWaveWarmReleaseTimer = null;
    }
  }

  function releaseDictationWaveResources() {
    clearDictationWaveWarmReleaseTimer();
    if (dictationWaveSource) {
      try {
        dictationWaveSource.disconnect();
      } catch (_err) {
        // noop
      }
      dictationWaveSource = null;
    }
    if (dictationWaveAnalyser) {
      try {
        dictationWaveAnalyser.disconnect();
      } catch (_err2) {
        // noop
      }
      dictationWaveAnalyser = null;
    }
    if (dictationWaveStream) {
      try {
        var tracks = dictationWaveStream.getTracks ? dictationWaveStream.getTracks() : [];
        for (var ti = 0; ti < tracks.length; ti += 1) {
          if (tracks[ti] && typeof tracks[ti].stop === "function") {
            tracks[ti].stop();
          }
        }
      } catch (_err3) {
        // noop
      }
      dictationWaveStream = null;
    }
    if (dictationWaveAudioContext) {
      try {
        if (typeof dictationWaveAudioContext.close === "function") {
          dictationWaveAudioContext.close();
        }
      } catch (_err4) {
        // noop
      }
      dictationWaveAudioContext = null;
    }
    dictationWaveData = null;
  }

  function stopDictationWaveMonitor(options) {
    var opts = options && typeof options === "object" ? options : {};
    var keepWarm = !!opts.keepWarm;
    if (dictationWavePollTimer) {
      clearInterval(dictationWavePollTimer);
      dictationWavePollTimer = null;
    }
    dictationWaveMonitorSession += 1;
    if (dictationWaveRafId) {
      cancelAnimationFrame(dictationWaveRafId);
      dictationWaveRafId = null;
    }
    clearDictationWaveWarmReleaseTimer();
    if (keepWarm && dictationWaveStream && dictationWaveAnalyser && dictationWaveData) {
      dictationWaveWarmReleaseTimer = setTimeout(function () {
        releaseDictationWaveResources();
      }, 12000);
    } else {
      releaseDictationWaveResources();
    }
    dictationWaveStartPromise = null;
    dictationWaveMicLevel = 0;
    dictationWaveMicLevelAt = 0;
    dictationWaveBackendLevel = 0;
    dictationWaveBackendLevelAt = 0;
    dictationWaveBackendRecentLevels = [];
    dictationWaveBackendFloor = 0.02;
    dictationWaveBackendFloorCalibrating = true;
    dictationWaveBackendFloorSeedSamples = [];
    dictationWaveSeenSignal = false;
    dictationWaveNoiseFloor = 0.02;
    dictationWaveSignalCeil = 0.16;
    dictationWaveLastSampleAt = 0;
    dictationWaveBarStartAt = 0;
    dictationWaveBarPeakRaw = 0;
    dictationWaveBarSumRaw = 0;
    dictationWaveBarSampleCount = 0;
    dictationWaveBackendLastEmitAt = 0;
    dictationWaveSilencePhase = 0;
    dictationWavePollInFlight = false;
    state.dictateWaveLevels = [];
  }

  function applyDictationWaveLevel(levelValue) {
    var level = Number(levelValue || 0);
    if (!isFinite(level) || level < 0) {
      level = 0;
    }
    if (level > 1) {
      level = 1;
    }
    if (level < 0.006) {
      level = 0;
    }
    if (!dictationWaveSeenSignal && level >= 0.008) {
      dictationWaveSeenSignal = true;
    }
    dictationWaveSilencePhase = (Number(dictationWaveSilencePhase || 0) + 1) % 2;
    var barCount = dictationWaveTargetBarCount();
    var existing = syncDictationWaveLevelsLength(barCount).slice();
    var shifted = existing.slice(1);
    shifted.push(level);
    state.dictateWaveLevels = shifted;
    renderDictationWaveBars();
  }

  function applyDictationWaveHistoryLevels(levelsInput) {
    var barCount = dictationWaveTargetBarCount();
    var existing = syncDictationWaveLevelsLength(barCount).slice();
    var incoming = Array.isArray(levelsInput) ? levelsInput : [];
    var pushed = [];
    for (var i = 0; i < incoming.length; i += 1) {
      var level = Number(incoming[i] || 0);
      if (!isFinite(level) || level < 0) {
        level = 0;
      } else if (level > 1) {
        level = 1;
      }
      if (level < 0.006) {
        level = 0;
      }
      pushed.push(level);
    }
    if (!pushed.length) {
      return;
    }
    var framePeak = 0;
    for (var pi = 0; pi < pushed.length; pi += 1) {
      if (pushed[pi] > framePeak) {
        framePeak = pushed[pi];
      }
    }
    if (!dictationWaveSeenSignal && framePeak >= 0.008) {
      dictationWaveSeenSignal = true;
    }
    dictationWaveMicLevel = framePeak;
    dictationWaveMicLevelAt = Date.now();
    var shift = pushed.length;
    if (shift > barCount) {
      pushed = pushed.slice(shift - barCount);
      shift = pushed.length;
    }
    var out = existing.slice(shift);
    for (var ai = 0; ai < pushed.length; ai += 1) {
      out.push(pushed[ai]);
    }
    while (out.length < barCount) {
      out.unshift(0);
    }
    state.dictateWaveLevels = out;
    renderDictationWaveBars();
  }

  function applyDictationWaveBatch(levelsInput) {
    var barCount = dictationWaveTargetBarCount();
    var existing = syncDictationWaveLevelsLength(barCount).slice();
    var incoming = Array.isArray(levelsInput) ? levelsInput : [];
    var pushed = [];
    for (var i = 0; i < incoming.length; i += 1) {
      var level = Number(incoming[i] || 0);
      if (!isFinite(level) || level < 0) {
        level = 0;
      } else if (level > 1) {
        level = 1;
      }
      if (level < 0.006) {
        level = 0;
      }
      pushed.push(level);
    }
    if (!pushed.length) {
      return;
    }
    var framePeak = 0;
    for (var pi = 0; pi < pushed.length; pi += 1) {
      if (pushed[pi] > framePeak) {
        framePeak = pushed[pi];
      }
    }
    if (!dictationWaveSeenSignal && framePeak >= 0.008) {
      dictationWaveSeenSignal = true;
    }
    var shift = pushed.length;
    if (shift > barCount) {
      pushed = pushed.slice(shift - barCount);
      shift = pushed.length;
    }
    var out = existing.slice(shift);
    for (var ai = 0; ai < pushed.length; ai += 1) {
      out.push(pushed[ai]);
    }
    while (out.length < barCount) {
      out.unshift(0);
    }
    state.dictateWaveLevels = out;
    renderDictationWaveBars();
  }

  function emitDictationBackendBars(levelsInput, fallbackLevel) {
    var now = Date.now();
    var lastEmit = Number(dictationWaveBackendLastEmitAt || 0);
    if (!isFinite(lastEmit) || lastEmit <= 0) {
      dictationWaveBackendLastEmitAt = now;
      return false;
    }
    var elapsed = now - lastEmit;
    var barsDue = Math.floor(elapsed / DICTATION_WAVE_BAR_INTERVAL_MS);
    if (!isFinite(barsDue) || barsDue < 1) {
      return false;
    }
    if (barsDue > 4) {
      barsDue = 4;
    }
    var source = Array.isArray(levelsInput) ? levelsInput : [];
    var emit = [];
    if (source.length) {
      var start = source.length - barsDue;
      if (start < 0) {
        start = 0;
      }
      emit = source.slice(start);
    }
    var fallback = Number(fallbackLevel || 0);
    if (!isFinite(fallback) || fallback < 0) {
      fallback = 0;
    } else if (fallback > 1) {
      fallback = 1;
    }
    while (emit.length < barsDue) {
      emit.unshift(fallback);
    }
    applyDictationWaveBatch(emit);
    dictationWaveBackendLastEmitAt = now - (elapsed - (barsDue * DICTATION_WAVE_BAR_INTERVAL_MS));
    return true;
  }

  function calibrateDictationWaveNoiseFloor(ambientProbe) {
    var probe = Number(ambientProbe || 0);
    if (!isFinite(probe) || probe < 0) {
      probe = 0;
    }
    var floor = Number(dictationWaveNoiseFloor || 0.01);
    if (!isFinite(floor) || floor < 0) {
      floor = 0.01;
    }
    if (probe >= floor) {
      // Raise floor slowly so ambient fan noise is normalized out without
      // erasing short speech transients.
      floor = (floor * 0.992) + (probe * 0.008);
    } else {
      // Drop floor faster so silence can return to a thin baseline quickly.
      floor = (floor * 0.8) + (probe * 0.2);
    }
    if (floor < 0.0005) {
      floor = 0.0005;
    } else if (floor > 0.06) {
      floor = 0.06;
    }
    dictationWaveNoiseFloor = floor;
    return floor;
  }

  function updateDictationWaveSignalCeil(levelProbe) {
    var probe = Number(levelProbe || 0);
    if (!isFinite(probe) || probe < 0) {
      probe = 0;
    }
    var floor = Number(dictationWaveNoiseFloor || 0.01);
    if (!isFinite(floor) || floor < 0) {
      floor = 0.01;
    }
    var ceil = Number(dictationWaveSignalCeil || 0.16);
    if (!isFinite(ceil) || ceil <= 0) {
      ceil = Math.max(0.12, floor + 0.12);
    }
    if (probe > ceil) {
      // Track upward loudness quickly to avoid temporary max-lock plateaus.
      ceil = (ceil * 0.2) + (probe * 0.8);
    } else {
      // Decay slowly so brief quieter spans do not immediately collapse headroom.
      ceil = (ceil * 0.992) + (probe * 0.008);
    }
    var minCeil = floor + Math.max(0.04, floor * 1.9);
    if (ceil < minCeil) {
      ceil = minCeil;
    } else if (ceil > 0.9) {
      ceil = 0.9;
    }
    dictationWaveSignalCeil = ceil;
    return ceil;
  }

  function normalizedDictationWaveSliceLevel(rawLevel) {
    var raw = Number(rawLevel || 0);
    if (!isFinite(raw) || raw < 0) {
      raw = 0;
    }
    var floor = Number(dictationWaveNoiseFloor || 0.01);
    if (!isFinite(floor) || floor < 0) {
      floor = 0.01;
    }
    var ceil = Number(dictationWaveSignalCeil || 0.16);
    if (!isFinite(ceil) || ceil <= floor) {
      ceil = floor + 0.12;
    }
    var gate = (floor * 1.15) + 0.0005;
    if (raw <= gate) {
      return 0;
    }
    var signal = raw - gate;
    if (signal < 0) {
      signal = 0;
    }
    var dynamicRange = Math.max(0.03, (ceil - gate) * 0.95);
    var normalized = signal / dynamicRange;
    if (!isFinite(normalized) || normalized < 0) {
      normalized = 0;
    }
    // Soft-knee compression preserves bar-to-bar variance at loud segments.
    normalized = Math.tanh(normalized * 0.95);
    if (normalized > 0) {
      normalized = Math.pow(normalized, 0.9);
    }
    if (normalized < 0.0018) {
      normalized = 0;
    }
    return normalized;
  }

  function normalizedDictationBackendLevel(levelValue) {
    var raw = Number(levelValue || 0);
    if (!isFinite(raw) || raw < 0) {
      raw = 0;
    } else if (raw > 1) {
      raw = 1;
    }
    var floor = Number(dictationWaveBackendFloor || 0.01);
    if (!isFinite(floor) || floor < 0) {
      floor = 0.01;
    }
    var effectiveFloor = floor;
    if (raw > (floor * 2.0) + 0.016) {
      effectiveFloor = floor * 0.78;
    }
    var gate = (effectiveFloor * 1.22) + 0.001;
    if (raw <= gate) {
      return 0;
    }
    var normalized = (raw - gate) / Math.max(0.016, (0.096 + (effectiveFloor * 1.55)));
    if (!isFinite(normalized) || normalized < 0) {
      normalized = 0;
    } else if (normalized > 1) {
      normalized = 1;
    }
    if (normalized > 0) {
      normalized = Math.pow(normalized, 1.0);
    }
    if (normalized < 0.0022) {
      normalized = 0;
    }
    return normalized;
  }

  function updateDictationBackendFloorWithSamples(levelSamples, fallbackSample) {
    var samples = [];
    var arr = Array.isArray(levelSamples) ? levelSamples : [];
    for (var i = 0; i < arr.length; i += 1) {
      var v = Number(arr[i]);
      if (!isFinite(v) || v < 0) {
        continue;
      }
      if (v > 1) {
        v = 1;
      }
      samples.push(v);
    }
    var fallback = Number(fallbackSample);
    if (isFinite(fallback) && fallback >= 0) {
      if (fallback > 1) {
        fallback = 1;
      }
      samples.push(fallback);
    }
    if (!samples.length) {
      return Number(dictationWaveBackendFloor || 0.01);
    }
    var sorted = samples.slice().sort(function (a, b) {
      return a - b;
    });
    var targetIdx = Math.floor((sorted.length - 1) * 0.12);
    if (targetIdx < 0) {
      targetIdx = 0;
    } else if (targetIdx >= sorted.length) {
      targetIdx = sorted.length - 1;
    }
    var speechIdx = Math.floor((sorted.length - 1) * 0.75);
    if (speechIdx < 0) {
      speechIdx = 0;
    } else if (speechIdx >= sorted.length) {
      speechIdx = sorted.length - 1;
    }
    var target = Number(sorted[targetIdx] || 0);
    var speechProbe = Number(sorted[speechIdx] || 0);
    if (!isFinite(target) || target < 0) {
      target = 0;
    }
    if (!isFinite(speechProbe) || speechProbe < 0) {
      speechProbe = 0;
    }
    var floor = Number(dictationWaveBackendFloor || 0.01);
    if (!isFinite(floor) || floor < 0) {
      floor = 0.01;
    }
    var now = Date.now();
    var activatedAt = Number(dictationWaveActivatedAt || 0);
    var inStartupWindow = activatedAt > 0 && (now - activatedAt) <= 700;
    if (dictationWaveBackendFloorCalibrating) {
      for (var si = 0; si < sorted.length; si += 1) {
        dictationWaveBackendFloorSeedSamples.push(sorted[si]);
      }
      if (dictationWaveBackendFloorSeedSamples.length > 280) {
        dictationWaveBackendFloorSeedSamples = dictationWaveBackendFloorSeedSamples.slice(dictationWaveBackendFloorSeedSamples.length - 280);
      }
      var seedSorted = dictationWaveBackendFloorSeedSamples.slice().sort(function (a, b) {
        return a - b;
      });
      var seedIdx = Math.floor((seedSorted.length - 1) * 0.25);
      if (seedIdx < 0) {
        seedIdx = 0;
      } else if (seedIdx >= seedSorted.length) {
        seedIdx = seedSorted.length - 1;
      }
      var seededTarget = Number(seedSorted[seedIdx] || target);
      if (!isFinite(seededTarget) || seededTarget < 0) {
        seededTarget = target;
      }
      floor = (floor * 0.28) + (seededTarget * 0.72);
      if (!inStartupWindow || seedSorted.length >= 56) {
        dictationWaveBackendFloorCalibrating = false;
      }
    } else {
      var speechPresent = speechProbe > (target + Math.max(0.01, target * 1.6));
      var deadband = Math.max(0.0025, floor * 0.2);
      if (speechPresent) {
        if (target < floor - deadband) {
          floor = (floor * 0.92) + (target * 0.08);
        }
      } else if (target > floor + deadband) {
        floor = (floor * 0.99) + (target * 0.01);
      } else if (target < floor - deadband) {
        floor = (floor * 0.9) + (target * 0.1);
      }
    }
    if (floor < 0.0008) {
      floor = 0.0008;
    } else if (floor > 0.08) {
      floor = 0.08;
    }
    dictationWaveBackendFloor = floor;
    return floor;
  }

  function mergedDictationWaveLevel(candidateLevel) {
    var merged = Number(candidateLevel || 0);
    if (!isFinite(merged) || merged < 0) {
      merged = 0;
    }
    if (merged > 1) {
      merged = 1;
    }
    var now = Date.now();
    var micLevel = 0;
    var backendLevel = 0;
    var micFresh = now - Number(dictationWaveMicLevelAt || 0) <= 150;
    if (micFresh) {
      micLevel = Number(dictationWaveMicLevel || 0);
      if (!isFinite(micLevel) || micLevel < 0) {
        micLevel = 0;
      } else if (micLevel > 1) {
        micLevel = 1;
      }
    }
    if (now - Number(dictationWaveBackendLevelAt || 0) <= 170) {
      backendLevel = Number(dictationWaveBackendLevel || 0);
      if (!isFinite(backendLevel) || backendLevel < 0) {
        backendLevel = 0;
      } else if (backendLevel > 1) {
        backendLevel = 1;
      }
    }
    if (micFresh && micLevel > merged) {
      merged = micLevel;
    }
    // Backend levels also help recover signal when WebAudio frames momentarily flatten.
    if (backendLevel > merged) {
      merged = backendLevel;
    }
    return merged;
  }

  function pumpDictationWaveFromBackend() {
    if (dictationWaveAnalyser && dictationWaveData) {
      return;
    }
    if (dictationWavePollTimer && (Date.now() - Number(dictationWaveBackendLevelAt || 0) < 260)) {
      return;
    }
    if (dictationWaveBackendPumpBusy) {
      return;
    }
    if (state.dictatePhase !== "recording" && state.dictatePhase !== "starting") {
      return;
    }
    var activeSessionId = trim(String(state.dictateSessionId || ""));
    if (!activeSessionId) {
      return;
    }
    var now = Date.now();
    if (now - Number(dictationWaveBackendPumpAt || 0) < 90) {
      return;
    }
    dictationWaveBackendPumpAt = now;
    dictationWaveBackendPumpBusy = true;
    apiGet("dictate_levels", { session_id: activeSessionId }, { timeoutMs: 2200 }).then(function (response) {
      if (!response || !response.success) {
        return;
      }
      var polledLevel = Number(response.level || 0);
      if (!isFinite(polledLevel) || polledLevel < 0) {
        polledLevel = 0;
      } else if (polledLevel > 1) {
        polledLevel = 1;
      }
      var incomingLevels = Array.isArray(response.levels) ? response.levels : [];
      var parsedIncoming = [];
      for (var pi = 0; pi < incomingLevels.length; pi += 1) {
        var parsedValue = Number(incomingLevels[pi]);
        if (!isFinite(parsedValue) || parsedValue < 0) {
          continue;
        }
        if (parsedValue > 1) {
          parsedValue = 1;
        }
        parsedIncoming.push(parsedValue);
      }
      updateDictationBackendFloorWithSamples(parsedIncoming, polledLevel);
      var normalizedBackend = normalizedDictationBackendLevel(polledLevel);
      var normalizedSequence = [];
      for (var li = 0; li < parsedIncoming.length; li += 1) {
        normalizedSequence.push(normalizedDictationBackendLevel(parsedIncoming[li]));
      }
      if (normalizedSequence.length) {
        normalizedBackend = normalizedSequence[normalizedSequence.length - 1];
      }
      dictationWaveBackendLevel = normalizedBackend;
      dictationWaveBackendLevelAt = Date.now();
      var lifted = mergedDictationWaveLevel(normalizedBackend);
      emitDictationBackendBars(normalizedSequence, lifted);
    }).catch(function () {
      return null;
    }).finally(function () {
      dictationWaveBackendPumpBusy = false;
    });
  }

  function startDictationWaveMonitor() {
    clearDictationWaveWarmReleaseTimer();
    if (
      dictationWavePollTimer &&
      (state.dictatePhase === "recording" || state.dictatePhase === "starting")
    ) {
      return Promise.resolve(true);
    }
    if (dictationWaveStartPromise) {
      return dictationWaveStartPromise;
    }
    stopDictationWaveMonitor({ keepWarm: true });
    var monitorSession = dictationWaveMonitorSession + 1;
    dictationWaveMonitorSession = monitorSession;
    function startSamplingLoop() {
      var sample = function () {
        if (
          monitorSession !== dictationWaveMonitorSession ||
          (state.dictatePhase !== "recording" && state.dictatePhase !== "starting") ||
          !dictationWaveAnalyser ||
          !dictationWaveData
        ) {
          return;
        }
        dictationWaveAnalyser.getByteTimeDomainData(dictationWaveData);
        var sampleNow = Date.now();
        if (sampleNow - Number(dictationWaveLastSampleAt || 0) < 12) {
          dictationWaveRafId = requestAnimationFrame(sample);
          return;
        }
        dictationWaveLastSampleAt = sampleNow;
        var len = dictationWaveData.length;
        var from = 0;
        var sum = 0;
        var count = 0;
        for (var si = from; si < len; si += 1) {
          var centered = (Number(dictationWaveData[si] || 128) - 128) / 128;
          var mag = centered < 0 ? -centered : centered;
          sum += mag * mag;
          count += 1;
        }
        var rms = count > 0 ? Math.sqrt(sum / count) : 0;
        // Envelope-only extraction (RMS) avoids phase/oscilloscope artifacts.
        var rawLevel = rms * 3.6;
        if (rawLevel > Number(dictationWaveBarPeakRaw || 0)) {
          dictationWaveBarPeakRaw = rawLevel;
        }
        dictationWaveBarSumRaw += rawLevel;
        dictationWaveBarSampleCount += 1;
        if (!dictationWaveBarStartAt) {
          dictationWaveBarStartAt = sampleNow;
        }
        if (sampleNow - Number(dictationWaveBarStartAt || 0) < DICTATION_WAVE_BAR_INTERVAL_MS) {
          dictationWaveRafId = requestAnimationFrame(sample);
          return;
        }
        var avgRaw = dictationWaveBarSampleCount > 0 ? (dictationWaveBarSumRaw / dictationWaveBarSampleCount) : rawLevel;
        var summarizedRaw = (Number(dictationWaveBarPeakRaw || rawLevel) * 0.76) + (avgRaw * 0.24);
        dictationWaveBarStartAt = sampleNow;
        dictationWaveBarPeakRaw = 0;
        dictationWaveBarSumRaw = 0;
        dictationWaveBarSampleCount = 0;
        calibrateDictationWaveNoiseFloor(summarizedRaw);
        updateDictationWaveSignalCeil(summarizedRaw);
        var normalizedLevel = normalizedDictationWaveSliceLevel(summarizedRaw);
        if (!dictationWaveSeenSignal && summarizedRaw > (dictationWaveNoiseFloor + 0.0015)) {
          dictationWaveSeenSignal = true;
        }
        applyDictationWaveLevel(normalizedLevel);
        dictationWaveRafId = requestAnimationFrame(sample);
      };
      dictationWaveRafId = requestAnimationFrame(sample);
    }

    function startBackendPollLoop() {
      dictationWavePollTimer = setInterval(function () {
        if (
          monitorSession !== dictationWaveMonitorSession ||
          (state.dictatePhase !== "recording" && state.dictatePhase !== "starting")
        ) {
          return;
        }
        var activeSessionId = trim(String(state.dictateSessionId || ""));
        if (!activeSessionId) {
          return;
        }
        if (dictationWavePollInFlight) {
          return;
        }
        dictationWavePollInFlight = true;
        apiGet("dictate_levels", { session_id: activeSessionId }, { timeoutMs: 2200 }).then(function (response) {
          if (
            monitorSession !== dictationWaveMonitorSession ||
            (state.dictatePhase !== "recording" && state.dictatePhase !== "starting")
          ) {
            return;
          }
          if (!response || !response.success) {
            return;
          }
          var polledLevel = Number(response.level || 0);
          if (!isFinite(polledLevel) || polledLevel < 0) {
            polledLevel = 0;
          }
          if (polledLevel > 1) {
            polledLevel = 1;
          }
          var incomingLevels = Array.isArray(response.levels) ? response.levels : [];
          var parsedIncoming = [];
          for (var li = 0; li < incomingLevels.length; li += 1) {
            var seqLevel = Number(incomingLevels[li]);
            if (!isFinite(seqLevel) || seqLevel < 0) {
              continue;
            }
            if (seqLevel > 1) {
              seqLevel = 1;
            }
            parsedIncoming.push(seqLevel);
          }
          updateDictationBackendFloorWithSamples(parsedIncoming, polledLevel);
          var normalizedBackend = normalizedDictationBackendLevel(polledLevel);
          var normalizedSequence = [];
          if (parsedIncoming.length) {
            for (var ni = 0; ni < parsedIncoming.length; ni += 1) {
              normalizedSequence.push(normalizedDictationBackendLevel(parsedIncoming[ni]));
            }
            dictationWaveBackendRecentLevels = parsedIncoming.slice(parsedIncoming.length - 18);
          }
          if (normalizedSequence.length) {
            normalizedBackend = normalizedSequence[normalizedSequence.length - 1];
          }
          dictationWaveBackendLevel = normalizedBackend;
          dictationWaveBackendLevelAt = Date.now();
          var hasMicAnalyser = !!(dictationWaveAnalyser && dictationWaveData);
          if (!hasMicAnalyser) {
            var mergedBackendLevel = mergedDictationWaveLevel(normalizedBackend);
            emitDictationBackendBars(normalizedSequence, mergedBackendLevel);
          }
        }).catch(function () {
          return null;
        }).finally(function () {
          dictationWavePollInFlight = false;
        });
      }, 24);
    }

    if (dictationWaveStream && dictationWaveAnalyser && dictationWaveData) {
      startSamplingLoop();
      startBackendPollLoop();
      return Promise.resolve(true);
    }

    dictationWaveStartPromise = Promise.resolve(true).then(function () {
      var AudioContextCtor = window.AudioContext || window.webkitAudioContext;
      if (!AudioContextCtor || !navigator.mediaDevices || typeof navigator.mediaDevices.getUserMedia !== "function") {
        return false;
      }
      return navigator.mediaDevices.getUserMedia({
        audio: {
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: false
        }
      }).then(function (stream) {
        if (
          monitorSession !== dictationWaveMonitorSession ||
          (state.dictatePhase !== "recording" && state.dictatePhase !== "starting")
        ) {
          try {
            var staleTracks = stream.getTracks ? stream.getTracks() : [];
            for (var sti = 0; sti < staleTracks.length; sti += 1) {
              if (staleTracks[sti] && typeof staleTracks[sti].stop === "function") {
                staleTracks[sti].stop();
              }
            }
          } catch (_streamCloseErr) {
            // noop
          }
          return false;
        }
        var context = null;
        try {
          context = new AudioContextCtor();
        } catch (_contextErr) {
          try {
            var failedTracks = stream.getTracks ? stream.getTracks() : [];
            for (var fti = 0; fti < failedTracks.length; fti += 1) {
              if (failedTracks[fti] && typeof failedTracks[fti].stop === "function") {
                failedTracks[fti].stop();
              }
            }
          } catch (_streamCloseErr2) {
            // noop
          }
          return false;
        }
        var analyser = context.createAnalyser();
        analyser.fftSize = 2048;
        analyser.smoothingTimeConstant = 0.02;
        var source = context.createMediaStreamSource(stream);
        source.connect(analyser);
        var data = new Uint8Array(analyser.fftSize);

        dictationWaveStream = stream;
        dictationWaveAudioContext = context;
        dictationWaveAnalyser = analyser;
        dictationWaveSource = source;
        dictationWaveData = data;
        startSamplingLoop();
        return true;
      }).catch(function () {
        return false;
      });
    }).then(function () {
      startBackendPollLoop();
      return true;
    }).finally(function () {
      dictationWaveStartPromise = null;
    });
    return dictationWaveStartPromise;
  }

  function renderDictationWaveBars() {
    var bars = ensureDictationWaveBars();
    if (!bars || !bars.length) {
      return;
    }
    var levels = Array.isArray(state.dictateWaveLevels) ? state.dictateWaveLevels : [];
    var waveformActive = state.dictatePhase === "recording" || state.dictatePhase === "starting";
    var preSignalBaseline =
      waveformActive &&
      !dictationWaveSeenSignal &&
      (Date.now() - Number(dictationWaveActivatedAt || 0) < 1800) &&
      (Date.now() - Number(dictationWaveBackendLevelAt || 0) > 220);
    var silencePhase = Number(dictationWaveSilencePhase || 0);
    var baselineHeight = 3;
    var maxWaveHeight = 39;
    var silenceGate = 0.0054;
    for (var i = 0; i < bars.length; i += 1) {
      var bar = bars[i];
      var unit = Number(levels[i] || 0);
      if (!isFinite(unit) || unit < 0) {
        unit = 0;
      }
      if (!waveformActive) {
        bar.classList.remove("is-baseline");
        bar.style.height = "0px";
        continue;
      }
      if (preSignalBaseline) {
        bar.classList.add("is-baseline");
        bar.style.height = ((i + silencePhase) % 2 === 0) ? "3px" : "1px";
        continue;
      }
      var height = baselineHeight;
      if (unit <= silenceGate) {
        // Running silence: keep dot height but use active (darker) color.
        bar.classList.remove("is-baseline");
        bar.style.height = ((i + silencePhase) % 2 === 0) ? "3px" : "1px";
        continue;
      } else {
        bar.classList.remove("is-baseline");
        var adjusted = (unit - silenceGate) / (1 - silenceGate);
        if (adjusted < 0) {
          adjusted = 0;
        } else if (adjusted > 1) {
          adjusted = 1;
        }
        var waveTravel = Math.max(1, maxWaveHeight - baselineHeight);
        height = baselineHeight + (Math.pow(adjusted, 1.04) * waveTravel);
      }
      bar.style.height = String(height) + "px";
    }
  }

  function setDictationPhase(phase) {
    var next = String(phase || "idle");
    if (next !== "starting" && next !== "recording" && next !== "processing") {
      next = "idle";
    }
    state.dictatePhase = next;
    if (next === "recording" || next === "starting") {
      if (!dictationWaveActivatedAt) {
        dictationWaveActivatedAt = Date.now();
      }
      startDictationWaveMonitor().then(function (started) {
        if (!started && (state.dictatePhase === "recording" || state.dictatePhase === "starting")) {
          state.dictateWaveLevels = [];
          renderDictationWaveBars();
        }
      });
    } else {
      dictationWaveActivatedAt = 0;
      stopDictationWaveMonitor({ keepWarm: next === "idle" });
    }
    if (next === "recording") {
      if (!state.dictateStartedAt) {
        state.dictateStartedAt = Date.now();
      }
      state.dictateElapsedMs = Math.max(0, Date.now() - state.dictateStartedAt);
      if (!dictationUiTickTimer) {
        dictationUiTickTimer = setInterval(function () {
          if (state.dictatePhase !== "recording") {
            clearDictationUiTicker();
            return;
          }
          state.dictateElapsedMs = Math.max(0, Date.now() - Number(state.dictateStartedAt || Date.now()));
          pumpDictationWaveFromBackend();
          renderDictationMode();
        }, 120);
      }
      return;
    }
    clearDictationUiTicker();
    if (next === "idle") {
      state.dictateStartedAt = 0;
      state.dictateElapsedMs = 0;
    }
  }

  function renderDictationMode() {
    if (!el.dictationMode || !el.composerRow) {
      return;
    }
    var phase = String(state.dictatePhase || "idle");
    var showMode = phase === "starting" || phase === "recording" || phase === "processing";
    el.composerRow.classList.toggle("dictation-mode-active", showMode);
    el.dictationMode.classList.toggle("hidden", !showMode);
    el.dictationMode.classList.toggle("starting", phase === "starting");
    el.dictationMode.classList.toggle("processing", phase === "processing");
    el.dictationMode.classList.toggle("recording", phase === "recording");
    if (!showMode) {
      return;
    }
    if (el.dictationTimer) {
      if (phase === "recording") {
        el.dictationTimer.textContent = formatDictationElapsed(state.dictateElapsedMs);
      } else if (phase === "processing") {
        el.dictationTimer.textContent = "Processing...";
      } else {
        el.dictationTimer.textContent = formatDictationElapsed(0);
      }
    }
    renderDictationWaveBars();
    if (el.dictationStopBtn) {
      var processing = phase === "processing";
      var starting = phase === "starting";
      el.dictationStopBtn.disabled = processing || starting;
      el.dictationStopBtn.classList.toggle("processing", processing);
      if (processing) {
        el.dictationStopBtn.setAttribute("aria-label", "Processing dictation");
      } else {
        el.dictationStopBtn.setAttribute("aria-label", "Stop dictation");
      }
    }
  }

  function renderDictateButton() {
    if (!el.dictateBtn) {
      return;
    }
    var available = !!state.dictationInstalled || !!state.dictateRecording || !!state.dictateBusy || state.dictatePhase !== "idle";
    el.dictateBtn.classList.toggle("hidden", !available);
    if (!available) {
      el.dictateBtn.disabled = true;
      el.dictateBtn.classList.remove("recording");
      el.dictateBtn.setAttribute("aria-pressed", "false");
      if (el.dictateBtn.hasAttribute("title")) {
        el.dictateBtn.removeAttribute("title");
      }
      return;
    }
    var busy = !!state.dictateBusy;
    var recording = !!state.dictateRecording;
    el.dictateBtn.disabled = busy;
    el.dictateBtn.classList.toggle("recording", recording);
    el.dictateBtn.setAttribute("aria-pressed", recording ? "true" : "false");
    var phase = String(state.dictatePhase || "idle");
    if (recording || phase === "recording") {
      el.dictateBtn.setAttribute("aria-label", "Stop dictation");
      el.dictateBtn.setAttribute("data-tooltip", "Stop dictation");
    } else if (phase === "processing") {
      el.dictateBtn.setAttribute("aria-label", "Processing dictation");
      el.dictateBtn.setAttribute("data-tooltip", "Processing dictation...");
    } else if (busy) {
      el.dictateBtn.setAttribute("aria-label", "Starting dictation");
      el.dictateBtn.setAttribute("data-tooltip", "Starting dictation...");
    } else {
      el.dictateBtn.setAttribute("aria-label", "Dictate prompt");
      el.dictateBtn.setAttribute("data-tooltip", "Dictate prompt");
    }
    if (el.dictateBtn.hasAttribute("title")) {
      el.dictateBtn.removeAttribute("title");
    }
  }

  function renderQueueControls() {
    if (!el.queueControls) {
      return;
    }
    if (!state.activeWorkspaceId || !state.activeConversationId || !el.queueSteerBtn || !el.queueCancelBtn) {
      el.queueControls.classList.add("hidden");
      return;
    }

    var stats = activeConversationQueueStats();
    if (stats.pending < 1 || !stats.firstId) {
      el.queueControls.classList.add("hidden");
      return;
    }

    var queueItemId = stats.firstId;
    var preferredId = state.lastQueuedItemIdByConversation[state.activeConversationId] || "";
    if (preferredId) {
      queueItemId = preferredId;
    }

    el.queueSteerBtn.textContent = "Steer";
    if (stats.pending > 1) {
      el.queueSteerBtn.textContent = "Steer (" + stats.pending + ")";
    }
    el.queueSteerBtn.dataset.queueItemId = queueItemId;
    el.queueCancelBtn.dataset.queueItemId = queueItemId;
    el.queueSteerBtn.disabled = !queueItemId;
    el.queueCancelBtn.disabled = !queueItemId;
    el.queueControls.classList.remove("hidden");
  }

  function queueItemMetaLabel(item, index) {
    var parts = [];
    parts.push("Queued #" + String(index + 1));
    var modeValue = item && item.run_mode ? normalizeRunMode(item.run_mode) : "auto";
    if (item && item.run_mode) {
      parts.push(runModeLabel(modeValue));
    }
    if (item && item.compute_budget) {
      parts.push(computeBudgetLabel(item.compute_budget));
    }
    if (modeValue === "programming") {
      var reviewEnabled = normalizeProgrammerReviewEnabledValue(item && item.programmer_review);
      if (reviewEnabled) {
        var reviewRounds = normalizeProgrammerReviewRoundsValue(item && item.programmer_review_rounds);
        parts.push("Code review x" + String(reviewRounds));
      } else {
        parts.push("Code review off");
      }
    }
    if (item && Array.isArray(item.explicit_skill_ids) && item.explicit_skill_ids.length) {
      parts.push(String(item.explicit_skill_ids.length) + " skill" + (item.explicit_skill_ids.length === 1 ? "" : "s"));
    }
    return parts.join(" • ");
  }

  function runChecklistTaskKey(rawText) {
    var text = trim(String(rawText || "")).toLowerCase();
    if (!text) {
      return "";
    }
    text = text.replace(/[^a-z0-9 ]+/g, " ");
    text = text.replace(/\s+/g, " ");
    return trim(text);
  }

  function runChecklistTokens(rawText) {
    var words = runChecklistTaskKey(rawText).split(/\s+/);
    var tokens = [];
    var stop = {
      a: 1, an: 1, and: 1, are: 1, as: 1, at: 1, be: 1, by: 1, for: 1, from: 1, in: 1, into: 1, is: 1, it: 1, of: 1, on: 1, or: 1, that: 1, the: 1, to: 1, with: 1
    };
    for (var i = 0; i < words.length; i += 1) {
      var token = trim(words[i] || "");
      if (token.length < 3 || stop[token]) {
        continue;
      }
      tokens.push(token);
    }
    return tokens;
  }

  function runChecklistTasksFromText(rawText) {
    var text = normalizeRunNarrativeText(rawText);
    if (!text) {
      return [];
    }
    text = text.replace(/\r\n?/g, "\n");
    text = text.replace(/\s*(Goal:|Subgoals:|Constraints:|Unknowns:|Next Action:|Completion Criteria:|Plan:|PLAN_UPDATE:)\s*/g, "\n$1\n");
    text = text.replace(/\s*(\d+[\.\)])\s+/g, "\n$1 ");
    text = text.replace(/\s*([\-*•])\s+/g, "\n$1 ");
    text = text.replace(/\n{3,}/g, "\n\n");

    var lines = text.split(/\n+/);
    var tasks = [];
    var seen = {};
    var capturingSubgoals = false;
    var sawSubgoalsHeader = false;

    function pushTask(lineText) {
      var line = trim(String(lineText || ""));
      if (!line) {
        return;
      }
      var done = false;
      if (/^(?:\[[xX]\]|[\-*•]\s+\[[xX]\]|\d+[\.\)]\s+\[[xX]\])\s+/.test(line)) {
        done = true;
      }
      line = line.replace(/^[\-*•]\s+\[[ xX]\]\s+/, "");
      line = line.replace(/^\[[ xX]\]\s+/, "");
      line = line.replace(/^\d+[\.\)]\s+\[[ xX]\]\s+/, "");
      line = line.replace(/^[\-*•]\s+/, "");
      line = line.replace(/^\d+[\.\)]\s+/, "");
      line = trim(line);
      if (!line) {
        return;
      }
      var key = runChecklistTaskKey(line);
      if (!key || seen[key]) {
        return;
      }
      seen[key] = 1;
      tasks.push({
        text: line,
        done: done
      });
    }

    for (var i = 0; i < lines.length; i += 1) {
      var line = trim(lines[i] || "");
      if (!line) {
        continue;
      }
      if (/^Subgoals:/i.test(line)) {
        capturingSubgoals = true;
        sawSubgoalsHeader = true;
        continue;
      }
      if (
        capturingSubgoals &&
        /^(Constraints|Unknowns|Next Action|Completion Criteria|Goal|Plan|PLAN_UPDATE|Current mode|Mode State|Transition|Checkpoint):/i.test(line)
      ) {
        capturingSubgoals = false;
      }
      var isTaskLine = /^(\[[ xX]\]|\d+[\.\)]|[\-*•])\s+/.test(line);
      if (capturingSubgoals) {
        if (isTaskLine) {
          pushTask(line);
        } else if (tasks.length && !/^[A-Za-z][A-Za-z0-9 _-]{1,40}:$/.test(line)) {
          tasks[tasks.length - 1].text = trim(tasks[tasks.length - 1].text + " " + line);
        }
        continue;
      }
      if (!sawSubgoalsHeader && isTaskLine) {
        pushTask(line);
      }
    }

    if (tasks.length > 18) {
      tasks = tasks.slice(0, 18);
    }
    return tasks;
  }

  function runChecklistCompletionEvidence(event) {
    var evidence = [];
    var entries = splitRunStreamEntries(event && event.stream_text);
    for (var i = 0; i < entries.length; i += 1) {
      var text = trim(String((entries[i] && entries[i].text) || ""));
      if (!text) {
        continue;
      }
      var lower = text.toLowerCase();
      if (!/(done|completed|finished|implemented|verified|passed|resolved|validated)/.test(lower)) {
        continue;
      }
      if (/(not done|not completed|not finished|failed|failure|error|blocked|mismatch)/.test(lower)) {
        continue;
      }
      evidence.push({
        text: text,
        lower: lower
      });
    }
    if (evidence.length > 120) {
      evidence = evidence.slice(evidence.length - 120);
    }
    return evidence;
  }

  function runChecklistMarkCompletions(tasks, event) {
    var list = Array.isArray(tasks) ? tasks.slice() : [];
    if (!list.length) {
      return [];
    }

    var evidence = runChecklistCompletionEvidence(event);
    if (!evidence.length) {
      return list;
    }

    var taskTokens = [];
    for (var i = 0; i < list.length; i += 1) {
      taskTokens.push(runChecklistTokens(list[i] && list[i].text));
    }

    for (var j = 0; j < evidence.length; j += 1) {
      var line = evidence[j] || {};
      var indexMatch = String(line.lower || "").match(/\b(?:task|step)\s*#?\s*(\d{1,2})\b/);
      if (indexMatch) {
        var explicitIndex = Number(indexMatch[1] || 0) - 1;
        if (explicitIndex >= 0 && explicitIndex < list.length) {
          list[explicitIndex].done = true;
        }
      }
    }

    for (var k = 0; k < list.length; k += 1) {
      if (list[k].done) {
        continue;
      }
      var tokens = taskTokens[k] || [];
      if (!tokens.length) {
        continue;
      }
      for (var n = 0; n < evidence.length; n += 1) {
        var ev = evidence[n] || {};
        var evTokens = runChecklistTokens(ev.text || "");
        if (!evTokens.length) {
          continue;
        }
        var overlap = 0;
        for (var t = 0; t < tokens.length; t += 1) {
          for (var u = 0; u < evTokens.length; u += 1) {
            if (tokens[t] === evTokens[u]) {
              overlap += 1;
              break;
            }
          }
        }
        var required = tokens.length >= 5 ? 3 : 2;
        if (overlap >= required) {
          list[k].done = true;
          break;
        }
      }
    }

    return list;
  }

  function buildRunChecklistForEvent(event) {
    var structured = normalizeRunTaskStatusSnapshot(event && event.task_status);
    if (!structured || structured.total < 1) {
      return {
        tasks: [],
        completed: 0,
        total: 0,
        source: "backend"
      };
    }
    return {
      tasks: structured.tasks,
      completed: structured.completed,
      total: structured.total,
      source: structured.source || "backend"
    };
  }

  function findLatestRunChecklist(conversationId) {
    var convId = String(conversationId || "");
    if (!convId) {
      return null;
    }
    var activeEvent = findLatestRunEventByStatus(convId, ["running"]);
    if (activeEvent) {
      var activeChecklist = buildRunChecklistForEvent(activeEvent);
      if (activeChecklist.total > 0) {
        activeChecklist.event = activeEvent;
        return activeChecklist;
      }
      return null;
    }
    var events = runEventsForConversation(convId);
    if (!events.length) {
      return null;
    }
    var minIndex = events.length - 6;
    if (minIndex < 0) {
      minIndex = 0;
    }
    for (var i = events.length - 1; i >= minIndex; i -= 1) {
      var event = events[i] || {};
      var checklist = buildRunChecklistForEvent(event);
      if (checklist.total > 0) {
        checklist.event = event;
        return checklist;
      }
    }
    return null;
  }

  function renderRunTodoMonitor() {
    if (!el.runTodoMonitor || !el.runTodoMonitorLabel || !el.runTodoMonitorList) {
      return;
    }
    if (!state.activeWorkspaceId || !state.activeConversationId || state.activeDraftWorkspaceId) {
      el.runTodoMonitor.classList.add("hidden");
      return;
    }

    var checklist = findLatestRunChecklist(state.activeConversationId);
    if (!checklist || checklist.total < 1) {
      el.runTodoMonitor.classList.add("hidden");
      return;
    }

    var conversationKey = queueConversationKey(state.activeWorkspaceId, state.activeConversationId);
    var hasPreference = Object.prototype.hasOwnProperty.call(state.runTodoMonitorOpenByConversation, conversationKey);
    var shouldOpen = hasPreference ? !!state.runTodoMonitorOpenByConversation[conversationKey] : true;
    el.runTodoMonitor.open = shouldOpen;
    var checklistIsRunning = !!(checklist.event && String(checklist.event.status || "") === "running");
    el.runTodoMonitorLabel.classList.toggle("meta-glimmer", checklistIsRunning);
    el.runTodoMonitorLabel.textContent =
      String(checklist.completed) + " out of " + String(checklist.total) + " task" + (checklist.total === 1 ? "" : "s") + " completed";

    var html = "";
    for (var i = 0; i < checklist.tasks.length; i += 1) {
      var task = checklist.tasks[i] || {};
      html += "<li class='run-todo-item" + (task.done ? " done" : "") + "'>";
      html += "<span class='run-todo-check' aria-hidden='true'></span>";
      html += "<span class='run-todo-text'>" + escHtml(task.text || "") + "</span>";
      html += "</li>";
    }
    el.runTodoMonitorList.innerHTML = html;
    el.runTodoMonitor.classList.remove("hidden");
  }

  function runEventTerminalPreview(event) {
    var lines = [];
    var entries = splitRunStreamEntries(event && event.stream_text);
    var commandRegex = /(^|\b)(COMMANDS?:|COMMAND:|\/bin\/|apply_patch|git |rg |ls |cat |sed |awk |npm |pnpm |yarn |python |node |go |cargo |make |godot |sh |bash |zsh )/i;
    for (var i = 0; i < entries.length; i += 1) {
      var entry = entries[i] || {};
      var text = trim(String(entry.text || ""));
      if (!text) {
        continue;
      }
      if (commandRegex.test(text)) {
        lines.push((entry.time ? "[" + entry.time + "] " : "") + text);
      }
    }
    if (!lines.length) {
      for (var j = Math.max(0, entries.length - 20); j < entries.length; j += 1) {
        var fallback = entries[j] || {};
        var fallbackText = trim(String(fallback.text || ""));
        if (!fallbackText) {
          continue;
        }
        lines.push((fallback.time ? "[" + fallback.time + "] " : "") + fallbackText);
      }
    }
    if (!lines.length && event && Array.isArray(event.commands) && event.commands.length) {
      for (var c = 0; c < event.commands.length; c += 1) {
        var cmd = trim(String((event.commands[c] && event.commands[c].command) || ""));
        if (!cmd) {
          continue;
        }
        lines.push("$ " + cmd);
      }
    }
    if (!lines.length) {
      return "";
    }
    if (lines.length > 40) {
      lines = lines.slice(lines.length - 40);
    }
    return lines.join("\n");
  }

  function renderRunTerminalMonitor() {
    if (!el.runTerminalMonitor || !el.runTerminalMonitorLabel || !el.runTerminalMonitorOutput) {
      return;
    }
    if (!state.activeWorkspaceId || !state.activeConversationId) {
      el.runTerminalMonitor.classList.add("hidden");
      return;
    }
    var stats = activeConversationQueueStats();
    var event = findLatestRunEventByStatus(state.activeConversationId, ["running"]);
    var activeRunMatch = !!(
      state.busy &&
      String(state.runningWorkspaceId || "") === String(state.activeWorkspaceId || "") &&
      String(state.runningConversationId || "") === String(state.activeConversationId || "")
    );
    if (!event && !stats.running && !activeRunMatch) {
      el.runTerminalMonitor.classList.add("hidden");
      return;
    }

    var conversationKey = queueConversationKey(state.activeWorkspaceId, state.activeConversationId);
    var shouldOpen = !!state.runTerminalMonitorOpenByConversation[conversationKey];
    el.runTerminalMonitor.open = shouldOpen;
    el.runTerminalMonitor.classList.remove("hidden");
    var terminalIsRunning = !!(event || stats.running || activeRunMatch);
    el.runTerminalMonitorLabel.classList.toggle("meta-glimmer", terminalIsRunning);
    el.runTerminalMonitorLabel.textContent = "Running 1 terminal";
    el.runTerminalMonitorOutput.textContent = runEventTerminalPreview(event) || "Waiting for terminal activity...";
    if (el.runTerminalMonitorStop) {
      el.runTerminalMonitorStop.dataset.workspaceId = state.activeWorkspaceId;
      el.runTerminalMonitorStop.dataset.conversationId = state.activeConversationId;
    }
  }

  function renderQueueTray() {
    if (!el.queueTray || !el.queueTrayList) {
      return;
    }
    if (!state.activeWorkspaceId || !state.activeConversationId || state.activeDraftWorkspaceId) {
      el.queueTray.classList.add("hidden");
      return;
    }

    var wsId = state.activeWorkspaceId;
    var convId = state.activeConversationId;
    var stats = activeConversationQueueStats();
    var queueKey = queueConversationKey(wsId, convId);
    var isLoading = !!state.queueItemsLoadingByConversation[queueKey];
    var fetchedAt = Number(state.queueItemsFetchedAtByConversation[queueKey] || 0);
    var queueItems = queueItemsForConversation(wsId, convId);
    var queueSignalActive = stats.pending > 0 || stats.running || !!trim(String(stats.firstId || ""));
    var probeIntervalMs = queueSignalActive ? (stats.running ? 900 : 1600) : 6000;
    var isEditingHere = isQueueEditForConversation(wsId, convId);
    var postSaveHold = queueEditPostSaveHoldForConversation(wsId, convId);
    var showTray = stats.pending > 0 || queueItems.length > 0 || isEditingHere || !!postSaveHold;
    if (
      !isLoading &&
      !state.queueDrag.active &&
      queueKey &&
      (!fetchedAt || Date.now() - fetchedAt > probeIntervalMs)
    ) {
      loadQueueItems(wsId, convId, { minIntervalMs: probeIntervalMs }).then(function () {
        renderUi();
      }).catch(function () {
        return null;
      });
    }
    if (!showTray) {
      el.queueTray.classList.add("hidden");
      return;
    }
    var html = "";
    var editingItemId = isEditingHere ? String(state.queueEdit.itemId || "") : "";
    var hasEditingItemRow = false;
    var hasPostSaveHoldRow = false;
    function queueEditRowHtml(itemId, metaText) {
      var safeItemId = String(itemId || "");
      var savingAttr = state.queueEdit.saving ? " disabled" : "";
      var rowHtml = "";
      rowHtml += "<div class='queue-item queue-item-editing' data-queue-item-id='" + escAttr(safeItemId) + "'>";
      rowHtml += "<div class='queue-edit-wrap'>";
      rowHtml += "<p class='queue-item-meta'>" + escHtml(metaText || "Queued message") + "</p>";
      rowHtml += "<textarea class='queue-edit-input' data-action='queue-edit-input' data-queue-item-id='" + escAttr(safeItemId) + "'>" + escHtml(state.queueEdit.draftText || "") + "</textarea>";
      rowHtml += "<div class='queue-edit-actions'>";
      rowHtml += "<button type='button' class='queue-btn' data-action='queue-edit-save' data-queue-item-id='" + escAttr(safeItemId) + "'" + savingAttr + ">Save</button>";
      rowHtml += "<button type='button' class='queue-btn' data-action='queue-edit-cancel' data-queue-item-id='" + escAttr(safeItemId) + "'" + savingAttr + ">Cancel</button>";
      rowHtml += "</div>";
      rowHtml += "</div>";
      rowHtml += "</div>";
      return rowHtml;
    }
    if (!queueItems.length && stats.pending > 0 && !postSaveHold) {
      html += "<div class='queue-item'><div class='queue-item-main'><p class='queue-item-text'>Loading queued messages…</p></div></div>";
    }
    for (var i = 0; i < queueItems.length; i += 1) {
      var queueItem = queueItems[i] || {};
      var itemId = String(queueItem.id || "");
      if (!itemId) {
        continue;
      }
      if (postSaveHold && String(postSaveHold.itemId || "") === itemId) {
        hasPostSaveHoldRow = true;
      }
      var editingThis = isEditingHere && editingItemId === itemId;
      if (editingThis) {
        hasEditingItemRow = true;
        html += queueEditRowHtml(itemId, queueItemMetaLabel(queueItem, i));
      } else {
        html += "<div class='queue-item' draggable='true' data-queue-item-id='" + escAttr(itemId) + "'>";
        html += "<button type='button' class='queue-drag-handle' data-action='queue-drag-handle' data-queue-item-id='" + escAttr(itemId) + "' aria-label='Drag to reorder queued item' title='Drag to reorder queued item'>&#8942;&#8942;</button>";
        html += "<div class='queue-item-main'>";
        html += "<p class='queue-item-text'>" + escHtml(queueItemPreview(queueItem.prompt || "", 240)) + "</p>";
        html += "<p class='queue-item-meta'>" + escHtml(queueItemMetaLabel(queueItem, i)) + "</p>";
        html += "</div>";
        html += "<div class='queue-item-actions'>";
        html += "<button type='button' class='queue-btn' data-action='queue-steer-item' data-queue-item-id='" + escAttr(itemId) + "'>Steer</button>";
        html += "<button type='button' class='queue-btn' data-action='queue-edit-item' data-queue-item-id='" + escAttr(itemId) + "'>Edit</button>";
        html += "<button type='button' class='queue-btn queue-trash' data-action='queue-trash-item' data-queue-item-id='" + escAttr(itemId) + "' aria-label='Delete queued message' title='Delete queued message'>&times;</button>";
        html += "</div>";
        html += "</div>";
      }
    }
    if (isEditingHere && editingItemId && !hasEditingItemRow) {
      html += queueEditRowHtml(editingItemId, "Queued message (refreshing)");
    }
    if (postSaveHold && !hasPostSaveHoldRow && !isEditingHere) {
      html += "<div class='queue-item queue-item-updated' data-queue-item-id='" + escAttr(String(postSaveHold.itemId || "updated")) + "'>";
      html += "<div class='queue-item-main'>";
      html += "<p class='queue-item-text'>" + escHtml(queueItemPreview(postSaveHold.prompt || "", 240)) + "</p>";
      html += "<p class='queue-item-meta'>Queued message updated</p>";
      html += "</div>";
      html += "</div>";
    }

    if (isConversationQueueBlockedByEdit(wsId, convId)) {
      html += "<p class='queue-paused-note'>Queue paused while editing the next queued message.</p>";
    } else if (postSaveHold) {
      html += "<p class='queue-paused-note'>Queued message updated. Resuming queue…</p>";
    }
    el.queueTrayList.innerHTML = html;
    el.queueTray.classList.remove("hidden");
  }

  function renderBranchMenu() {
    if (!el.branchMenuList || !el.branchCreateForm) {
      return;
    }
    var workspaceId = state.activeWorkspaceId;
    var gitState = activeGitState();

    if (!workspaceId) {
      el.branchMenuList.innerHTML = "<p class='empty-state'>Select a project first.</p>";
      el.branchCreateForm.classList.add("hidden");
      if (el.branchCreateSubmit) {
        el.branchCreateSubmit.disabled = true;
      }
      return;
    }

    if (!gitState.is_repo) {
      el.branchMenuList.innerHTML = "<button type='button' data-branch-action='create-repo'>Create repo</button>";
      el.branchCreateForm.classList.add("hidden");
      if (el.branchCreateSubmit) {
        el.branchCreateSubmit.disabled = true;
      }
      return;
    }
    el.branchCreateForm.classList.remove("hidden");
    if (el.branchCreateSubmit) {
      el.branchCreateSubmit.disabled = trim(el.branchCreateInput ? el.branchCreateInput.value : "") === "";
    }

    var branches = state.branchesByWorkspace[workspaceId] || [];
    if (!branches.length) {
      if (gitState.branch) {
        el.branchMenuList.innerHTML = "<button type='button' data-branch-select='" + escHtml(gitState.branch) + "'>" + escHtml(gitState.branch + " *") + "</button>";
      } else {
        el.branchMenuList.innerHTML = "<p class='empty-state'>No branches found.</p>";
      }
      return;
    }

    var html = "";
    for (var i = 0; i < branches.length; i += 1) {
      var branch = branches[i];
      var currentMark = branch.current ? " *" : "";
      html += "<button type='button' data-branch-select='" + escHtml(branch.name) + "'>" + escHtml(branch.name + currentMark) + "</button>";
    }

    el.branchMenuList.innerHTML = html;
  }

  function renderPermissionsButton() {
    if (!el.permissionsMenuBtn) {
      return;
    }
    var label = permissionModeLabel(state.permissionMode);
    el.permissionsMenuBtn.innerHTML =
      "<span class='menu-icon mono-icon' aria-hidden='true'>" + permissionModeIconMarkup(state.permissionMode) + "</span><span>" + escHtml(label) + "</span>";
    el.permissionsMenuBtn.title = label;
    renderPermissionModeMenu();
    renderCommandExecMenu();
    renderPermissionToggles();
  }

  function renderPermissionModeMenu() {
    if (!el.permissionsMenu) {
      return;
    }
    var items = el.permissionsMenu.querySelectorAll("button[data-permission]");
    for (var i = 0; i < items.length; i += 1) {
      var mode = String(items[i].getAttribute("data-permission") || "");
      items[i].classList.toggle("active", mode === state.permissionMode);
    }
  }

  function renderCommandExecMenu() {
    if (!el.permissionsMenu) {
      return;
    }
    var items = el.permissionsMenu.querySelectorAll("button[data-command-exec]");
    for (var i = 0; i < items.length; i += 1) {
      var mode = items[i].getAttribute("data-command-exec");
      items[i].classList.toggle("active", mode === state.commandExecMode);
    }
  }

  function renderPermissionToggles() {
    normalizePermissionToggles();

    if (el.networkToggleBtn) {
      el.networkToggleBtn.classList.toggle("on", !!state.networkAccess);
      el.networkToggleBtn.setAttribute("aria-pressed", state.networkAccess ? "true" : "false");
    }
    if (el.webToggleBtn) {
      el.webToggleBtn.classList.toggle("on", !!state.webAccess);
      el.webToggleBtn.setAttribute("aria-pressed", state.webAccess ? "true" : "false");
      el.webToggleBtn.classList.toggle("disabled", !state.networkAccess);
      el.webToggleBtn.disabled = !state.networkAccess;
    }
  }

  function renderAttachmentStrip() {
    if (!el.attachmentStrip) {
      return;
    }

    if (!state.pendingAttachments.length) {
      el.attachmentStrip.classList.add("hidden");
      el.attachmentStrip.innerHTML = "";
      return;
    }

    var html = "";
    for (var i = 0; i < state.pendingAttachments.length; i += 1) {
      var attachment = state.pendingAttachments[i];
      var preview = attachment.previewUrl || "";
      var kind = attachment.kind || "file";
      html += "<div class='attachment-chip' data-action='preview-attachment' data-attachment-id='" + escAttr(attachment.id) + "' role='button' tabindex='0'>";
      html += "<button type='button' class='attachment-remove' data-action='remove-attachment' data-attachment-id='" + escAttr(attachment.id) + "' aria-label='Remove attachment'>&times;</button>";
      html += "<div class='attachment-thumb'>";
      if (kind === "image" && preview) {
        html += "<img src='" + escAttr(preview) + "' alt='" + escAttr(attachment.name || "image attachment") + "' />";
      } else if (kind === "text") {
        html += "<span>Text</span>";
      } else if (kind === "document") {
        html += "<span>PDF</span>";
      } else {
        html += "<span>File</span>";
      }
      html += "</div>";
      html += "<div class='attachment-name'>" + escHtml(attachment.name || "attachment") + "</div>";
      html += "<div class='attachment-meta'>" + escHtml(formatBytes(attachment.size || 0)) + "</div>";
      html += "</div>";
    }

    el.attachmentStrip.innerHTML = html;
    el.attachmentStrip.classList.remove("hidden");
  }

  function renderToolbarGit() {
    if (!el.branchMenuBtn || !el.commitMainBtn || !el.changesBtn) {
      return;
    }
    var gitState = activeGitState();

    if (!state.activeWorkspaceId) {
      el.branchMenuBtn.textContent = "No repo";
      el.branchMenuBtn.title = "Select a project first";
      el.commitMainBtn.disabled = true;
      if (el.commitMenuBtn) {
        el.commitMenuBtn.disabled = true;
      }
      el.changesBtn.innerHTML = gitDeltaMarkup(0, 0);
      return;
    }

    if (!gitState.is_repo) {
      el.branchMenuBtn.textContent = "Create repo";
      el.branchMenuBtn.title = "Initialize git repository";
      el.commitMainBtn.disabled = true;
      if (el.commitMenuBtn) {
        el.commitMenuBtn.disabled = true;
      }
      el.changesBtn.innerHTML = gitDeltaMarkup(0, 0);
      return;
    }

    el.branchMenuBtn.textContent = gitState.branch || "Branch";
    el.branchMenuBtn.title = "Git branch and repository";
    el.commitMainBtn.disabled = false;
    if (el.commitMenuBtn) {
      el.commitMenuBtn.disabled = false;
    }
    el.changesBtn.innerHTML = gitDeltaMarkup(gitState.added, gitState.deleted);
  }

  function renderChatHeader() {
    if (state.sidebarSection === "automations") {
      el.chatTitle.textContent = "Automations";
      return;
    }
    if (state.activeTriage) {
      el.chatTitle.textContent = "Triage";
      return;
    }
    if (!state.activeWorkspaceId) {
      el.chatTitle.textContent = "No thread";
      return;
    }

    if (state.activeDraftWorkspaceId) {
      el.chatTitle.textContent = "Draft thread";
      return;
    }

    if (state.activeConversation && state.activeConversation.title) {
      el.chatTitle.textContent = state.activeConversation.title;
      return;
    }

    var workspace = getWorkspaceById(state.activeWorkspaceId);
    var summary = getConversationById(workspace, state.activeConversationId);
    if (summary && summary.title) {
      el.chatTitle.textContent = summary.title;
      return;
    }

    el.chatTitle.textContent = "No thread";
  }

  function shouldRenderBlankRightPane() {
    if (state.sidebarSection === "automations") {
      return true;
    }
    if (state.activeTriage) {
      return false;
    }
    if (state.activeDraftWorkspaceId) {
      return false;
    }
    if (
      !!state.activeConversationId &&
      state.activeConversationLoading &&
      !state.conversationSwitchOverlay &&
      !state.activeConversation
    ) {
      return true;
    }
    return !state.activeConversationId;
  }

  function conversationSwitchOverlayVisible() {
    return !!state.conversationSwitchOverlay &&
      !!state.activeConversationId &&
      !state.activeDraftWorkspaceId &&
      !state.activeTriage;
  }

  var conversationSwitchOverlayHideTimer = 0;
  var conversationSwitchOverlayShowFrame = 0;
  var CONVERSATION_SWITCH_OVERLAY_FADE_OUT_MS = 85;

  function renderConversationSwitchOverlay() {
    if (!el.conversationSwitchOverlay) {
      return;
    }
    var overlay = el.conversationSwitchOverlay;
    var shouldShow = conversationSwitchOverlayVisible();
    if (shouldShow) {
      if (conversationSwitchOverlayHideTimer) {
        clearTimeout(conversationSwitchOverlayHideTimer);
        conversationSwitchOverlayHideTimer = 0;
      }
      if (conversationSwitchOverlayShowFrame) {
        cancelAnimationFrame(conversationSwitchOverlayShowFrame);
        conversationSwitchOverlayShowFrame = 0;
      }
      overlay.classList.remove("hidden");
      overlay.classList.remove("is-hiding");
      if (!overlay.classList.contains("is-visible")) {
        conversationSwitchOverlayShowFrame = window.requestAnimationFrame(function () {
          conversationSwitchOverlayShowFrame = 0;
          if (!el.conversationSwitchOverlay || !conversationSwitchOverlayVisible()) {
            return;
          }
          el.conversationSwitchOverlay.classList.add("is-visible");
        });
      }
      return;
    }
    if (conversationSwitchOverlayShowFrame) {
      cancelAnimationFrame(conversationSwitchOverlayShowFrame);
      conversationSwitchOverlayShowFrame = 0;
    }
    overlay.classList.remove("is-visible");
    if (overlay.classList.contains("hidden")) {
      overlay.classList.remove("is-hiding");
      return;
    }
    overlay.classList.add("is-hiding");
    if (conversationSwitchOverlayHideTimer) {
      clearTimeout(conversationSwitchOverlayHideTimer);
    }
    conversationSwitchOverlayHideTimer = window.setTimeout(function () {
      conversationSwitchOverlayHideTimer = 0;
      if (!el.conversationSwitchOverlay || conversationSwitchOverlayVisible()) {
        return;
      }
      el.conversationSwitchOverlay.classList.add("hidden");
      el.conversationSwitchOverlay.classList.remove("is-hiding");
    }, CONVERSATION_SWITCH_OVERLAY_FADE_OUT_MS + 10);
  }

  function renderToolbarSwitchLock() {
    if (!el.toolbar || !el.toolbar.querySelectorAll) {
      return;
    }
    var locked = conversationSwitchOverlayVisible();
    el.toolbar.classList.toggle("conversation-switch-locked", locked);
    var controls = el.toolbar.querySelectorAll("button, .path-widget");
    for (var i = 0; i < controls.length; i += 1) {
      setControlPending(controls[i], locked, { spinner: false });
    }
    var splitButtons = el.toolbar.querySelectorAll(".split-btn");
    for (var j = 0; j < splitButtons.length; j += 1) {
      var split = splitButtons[j];
      var childButtons = split.querySelectorAll("button");
      var splitDisabled = false;
      for (var k = 0; k < childButtons.length; k += 1) {
        if (childButtons[k].disabled || String(childButtons[k].getAttribute("data-ui-pending") || "") === "1") {
          splitDisabled = true;
          break;
        }
      }
      split.classList.toggle("is-disabled", splitDisabled);
    }
    if (el.workspacePathWidget) {
      var pathDisabled = !!el.workspacePathWidget.disabled ||
        String(el.workspacePathWidget.getAttribute("data-ui-pending") || "") === "1";
      el.workspacePathWidget.classList.toggle("is-disabled", pathDisabled);
    }
  }

  function renderRightPaneChrome() {
    if (!el.shell) {
      return;
    }
    var blank = shouldRenderBlankRightPane();
    el.shell.classList.toggle("right-pane-blank", blank);
  }

  function activeDecisionRequestInfo() {
    if (!state.activeWorkspaceId || !state.activeConversationId) {
      return null;
    }
    var request = conversationDecisionRequest(state.activeConversation);
    if (!request) {
      var workspace = getWorkspaceById(state.activeWorkspaceId);
      var conversation = getConversationById(workspace, state.activeConversationId);
      request = conversationDecisionRequest(conversation);
    }
    if (!request) {
      return null;
    }
    var key = conversationReadKey(state.activeWorkspaceId, state.activeConversationId);
    var marker = key + "::" + request.question + "::" + request.options.join("||");
    return {
      workspaceId: state.activeWorkspaceId,
      conversationId: state.activeConversationId,
      key: key,
      marker: marker,
      request: request
    };
  }

  function activeApprovalRequestInfo() {
    if (!state.activeWorkspaceId || !state.activeConversationId) {
      return null;
    }
    var workspace = getWorkspaceById(state.activeWorkspaceId);
    var conversation = getConversationById(workspace, state.activeConversationId);
    var summaryRequest = conversationApprovalRequest(conversation);
    var activeRequest = conversationApprovalRequest(state.activeConversation);
    var queueLastStatus = String(conversation && conversation.queue_last_status || "");
    var hasQueueTerminalStatus = (
      queueLastStatus === "done" ||
      queueLastStatus === "error" ||
      queueLastStatus === "cancelled" ||
      queueLastStatus === "awaiting_decision"
    );
    var request = summaryRequest;
    if (!request && activeRequest && !hasQueueTerminalStatus) {
      request = activeRequest;
    }
    if (!request && hasQueueTerminalStatus && state.activeConversation) {
      state.activeConversation.approval_request = null;
    }
    var awaitingByStateFlag = isAwaitingApprovalConversation(state.activeWorkspaceId, state.activeConversationId);
    var latestRunEvent = findLatestRunEventByStatus(
      state.activeConversationId,
      ["running", "awaiting_approval", "awaiting_decision", "done", "error", "cancelled", "approval_granted"]
    );
    var latestRunStatus = String(latestRunEvent && latestRunEvent.status || "");
    var latestRunIsTerminal = (
      latestRunStatus === "done" ||
      latestRunStatus === "error" ||
      latestRunStatus === "cancelled" ||
      latestRunStatus === "awaiting_decision" ||
      latestRunStatus === "approval_granted"
    );
    var awaitingApproval = false;
    if (queueLastStatus === "awaiting_approval" || !!request || latestRunStatus === "awaiting_approval") {
      awaitingApproval = true;
    } else if (awaitingByStateFlag && !hasQueueTerminalStatus && !latestRunIsTerminal) {
      // Keep short-lived local awaiting state only while no terminal evidence exists.
      awaitingApproval = true;
    } else if (awaitingByStateFlag) {
      setAwaitingApprovalState(state.activeWorkspaceId, state.activeConversationId, false);
    }

    if (!request && awaitingApproval) {
      var inferredCommand = inferredApprovalCommandFromConversation();
      request = {
        command: inferredCommand,
        reason: ""
      };
    }
    if (!request) {
      return null;
    }
    return {
      workspaceId: state.activeWorkspaceId,
      conversationId: state.activeConversationId,
      request: request,
      hasCommand: !!trim(request.command || "")
    };
  }

  function latestUserPromptFromActiveConversation() {
    var messages = Array.isArray(state.activeConversation && state.activeConversation.messages)
      ? state.activeConversation.messages
      : [];
    for (var i = messages.length - 1; i >= 0; i -= 1) {
      var msg = messages[i] || {};
      if (String(msg.role || "") === "user") {
        var content = trim(String(msg.content || ""));
        if (content) {
          return content;
        }
      }
    }
    return "";
  }

  function latestAssistantMessageFromActiveConversation() {
    var messages = Array.isArray(state.activeConversation && state.activeConversation.messages)
      ? state.activeConversation.messages
      : [];
    for (var i = messages.length - 1; i >= 0; i -= 1) {
      var msg = messages[i] || {};
      if (String(msg.role || "") === "assistant") {
        var content = trim(String(msg.content || ""));
        if (content) {
          return content;
        }
      }
    }
    return "";
  }

  function inferredApprovalCommandFromConversation() {
    var text = latestAssistantMessageFromActiveConversation();
    if (!text) {
      return "";
    }

    var commandLine = text.match(/Command:\s*([^\n\r]+)/i);
    if (commandLine && commandLine[1]) {
      var candidate = trim(commandLine[1]).replace(/[.,;:]+$/, "");
      if (/^[./A-Za-z0-9_-]+$/.test(candidate)) {
        return candidate;
      }
    }

    var explicitPath = text.match(/\b(\.\/[A-Za-z0-9._/-]+)\b/);
    if (explicitPath && explicitPath[1]) {
      return explicitPath[1];
    }

    var shellFile = text.match(/\b([A-Za-z0-9._-]+\.sh)\b/);
    if (shellFile && shellFile[1]) {
      return "./" + shellFile[1];
    }

    return "";
  }

  function submitApprovalRequestAnswer(decision, scope) {
    var info = activeApprovalRequestInfo();
    if (!info) {
      return Promise.resolve();
    }
    var approvedDecision = String(decision || "") === "allow";
    var matchMode = trim(el.commandApprovalInlineMatchMode && el.commandApprovalInlineMatchMode.value) || "exact";
    var pattern = trim(el.commandApprovalInlinePattern && el.commandApprovalInlinePattern.value) || info.request.command;
    var commandText = String(info.request.command || "");
    var effectiveScope = scope;
    if (!trim(commandText)) {
      effectiveScope = "once";
    }
    return apiPost("approval_answer", {
      workspace_id: info.workspaceId,
      conversation_id: info.conversationId,
      command: commandText,
      decision: decision,
      scope: effectiveScope,
      match_mode: matchMode,
      pattern: pattern
    }).then(function (response) {
      if (!response || !response.success) {
        throw new Error((response && response.error) || "Could not submit approval.");
      }
      var queuedAfterApproval = queueNumber(response.queue_pending) > 0 || Number(response.queue_running || 0) > 0;
      if (approvedDecision && !queuedAfterApproval) {
        throw new Error("Approval was accepted, but no retry run was queued.");
      }
      if (approvedDecision) {
        startApprovalResumeWatch(info.workspaceId, info.conversationId);
      } else {
        stopApprovalResumeWatch();
      }
      applyQueueStateFromResponse(info.workspaceId, info.conversationId, response);
      setConversationQueueFields(info.workspaceId, info.conversationId, {
        approvalRequest: null
      });
      if (approvedDecision) {
        var approvalAnchor = 0;
        if (
          state.activeConversation &&
          state.activeWorkspaceId === info.workspaceId &&
          state.activeConversationId === info.conversationId &&
          Array.isArray(state.activeConversation.messages)
        ) {
          approvalAnchor = state.activeConversation.messages.length;
        }
        pushRunEvent(info.conversationId, {
          status: "approval_granted",
          approved_scope: effectiveScope || "once",
          approved_command: commandText,
          decision_hint: trim(String(response.decision_hint || "")),
          message_anchor: approvalAnchor,
          started_at: new Date().toISOString(),
          finished_at: new Date().toISOString()
        });
      }
      if (
        state.activeConversation &&
        state.activeWorkspaceId === info.workspaceId &&
        state.activeConversationId === info.conversationId
      ) {
        state.activeConversation.approval_request = null;
      }
      loadConversation({ timeoutMs: 6000 }).catch(function () {
        return null;
      });
      return null;
    }).then(function () {
      renderUi();
      state.queueWorkerActive = false;
      if (approvedDecision) {
        resumeConversationQueueNow(info.workspaceId, info.conversationId)
          .then(function (started) {
            if (!started) {
              kickQueueWorker();
            }
            return null;
          })
          .catch(function () {
            kickQueueWorker();
            return null;
          });
        return;
      }
      kickQueueWorker();
    });
  }

  function commandApprovalActionButtons() {
    return [
      el.commandApprovalInlineAllowOnce,
      el.commandApprovalInlineDenyOnce,
      el.commandApprovalInlineAllowRemember,
      el.commandApprovalInlineDenyRemember,
      el.commandApprovalAllowOnce,
      el.commandApprovalDenyOnce,
      el.commandApprovalAllowRemember,
      el.commandApprovalDenyRemember
    ];
  }

  function setApprovalAnswerUiPending(isPending, activeButton) {
    var buttons = commandApprovalActionButtons();
    for (var i = 0; i < buttons.length; i += 1) {
      var btn = buttons[i];
      if (!btn) {
        continue;
      }
      if (isPending) {
        if (!btn.hasAttribute("data-default-label")) {
          btn.setAttribute("data-default-label", btn.textContent || "");
        }
        btn.disabled = true;
      } else {
        btn.disabled = false;
        if (btn.hasAttribute("data-default-label")) {
          btn.textContent = btn.getAttribute("data-default-label") || "";
          btn.removeAttribute("data-default-label");
        }
      }
      btn.classList.toggle("approval-submit-pending", isPending && btn === activeButton);
    }
    if (activeButton && isPending) {
      activeButton.textContent = "Sending...";
    }
    if (el.commandApprovalInlineMatchMode) {
      el.commandApprovalInlineMatchMode.disabled = !!isPending;
    }
    if (el.commandApprovalInlinePattern) {
      el.commandApprovalInlinePattern.disabled = !!isPending;
    }
    if (el.commandApprovalInlineClose) {
      el.commandApprovalInlineClose.disabled = !!isPending;
    }
    if (el.commandApprovalInline) {
      el.commandApprovalInline.classList.toggle("is-submitting", !!isPending);
    }
    if (el.commandApprovalModal) {
      el.commandApprovalModal.classList.toggle("is-submitting", !!isPending);
    }
  }

  function releaseApprovalAnswerUiPendingIfAdvanced(workspaceId, conversationId, conversationEntry) {
    if (!approvalAnswerPending) {
      return;
    }
    var wsId = String(workspaceId || "");
    var convId = String(conversationId || "");
    if (!wsId || !convId) {
      return;
    }
    if (
      String(state.activeWorkspaceId || "") !== wsId ||
      String(state.activeConversationId || "") !== convId
    ) {
      return;
    }
    var entry = conversationEntry || {};
    var lastStatus = String(entry.queue_last_status || "");
    var hasApprovalRequest = !!normalizeApprovalRequest(entry.approval_request);
    if (lastStatus === "awaiting_approval" || hasApprovalRequest) {
      return;
    }
    approvalAnswerPending = false;
    setApprovalAnswerUiPending(false, null);
  }

  function submitApprovalRequestAnswerWithUi(decision, scope, sourceButton) {
    if (approvalAnswerPending) {
      return Promise.resolve();
    }
    var info = activeApprovalRequestInfo();
    if (String(decision || "") === "allow" && info) {
      startApprovalResumeWatch(info.workspaceId, info.conversationId);
    }
    approvalAnswerPending = true;
    setApprovalAnswerUiPending(true, sourceButton || null);
    return submitApprovalRequestAnswer(decision, scope).finally(function () {
      approvalAnswerPending = false;
      setApprovalAnswerUiPending(false, null);
      renderUi();
    });
  }

  function updateDecisionOtherVisibility() {
    if (!el.decisionRequestOptions || !el.decisionRequestOtherWrap || !el.decisionRequestOtherInput) {
      return;
    }
    var selected = el.decisionRequestOptions.querySelector("input[name='decision-request-choice']:checked");
    var isOther = !!(selected && selected.value === "other");
    el.decisionRequestOtherWrap.classList.toggle("hidden", !isOther);
    if (isOther) {
      el.decisionRequestOtherInput.focus();
    }
  }

  function selectedDecisionAnswer() {
    if (!el.decisionRequestOptions) {
      return "";
    }
    var selected = el.decisionRequestOptions.querySelector("input[name='decision-request-choice']:checked");
    if (!selected) {
      return "";
    }
    if (selected.value === "other") {
      return trim(el.decisionRequestOtherInput && el.decisionRequestOtherInput.value || "");
    }
    return trim(selected.getAttribute("data-choice") || "");
  }

  function submitDecisionRequest() {
    var info = activeDecisionRequestInfo();
    if (!info) {
      return Promise.resolve();
    }
    var answer = selectedDecisionAnswer();
    if (!answer) {
      return Promise.reject(new Error("Choose an option or type an Other answer."));
    }
    if (el.decisionRequestSubmit) {
      el.decisionRequestSubmit.disabled = true;
    }
    return apiPost("decision_answer", {
      workspace_id: info.workspaceId,
      conversation_id: info.conversationId,
      answer: answer
    }).then(function (response) {
      if (!response || !response.success) {
        throw new Error((response && response.error) || "Could not submit decision.");
      }
      state.decisionInlineDismissedKey = "";
      applyQueueStateFromResponse(info.workspaceId, info.conversationId, response);
      setConversationDecisionRequest(info.workspaceId, info.conversationId, response.decision_request || null);
      if (
        state.activeConversation &&
        state.activeWorkspaceId === info.workspaceId &&
        state.activeConversationId === info.conversationId
      ) {
        state.activeConversation.decision_request = normalizeDecisionRequest(response.decision_request);
      }
      loadConversation({ timeoutMs: 6000 }).catch(function () {
        return null;
      });
      return null;
    }).then(function () {
      renderUi();
      kickQueueWorker();
    }).finally(function () {
      if (el.decisionRequestSubmit) {
        el.decisionRequestSubmit.disabled = false;
      }
    });
  }

  function renderDecisionRequestInline() {
    if (
      !el.decisionRequestInline ||
      !el.decisionRequestInlineQuestion ||
      !el.decisionRequestOptions
    ) {
      return;
    }
    var info = activeDecisionRequestInfo();
    if (!info) {
      el.decisionRequestInline.classList.add("hidden");
      return;
    }
    if (state.decisionInlineDismissedKey === info.marker) {
      el.decisionRequestInline.classList.add("hidden");
      return;
    }

    var options = Array.isArray(info.request.options) ? info.request.options : [];
    var optionsMarkup = "";
    for (var i = 0; i < options.length; i += 1) {
      optionsMarkup += "<label class='decision-option'><input type='radio' name='decision-request-choice' value='choice-" + String(i) + "' data-choice='" + escAttr(options[i]) + "'" + (i === 0 ? " checked" : "") + "><span class='decision-option-index'>" + String(i + 1) + ".</span><span class='decision-option-text'>" + escHtml(options[i]) + "</span></label>";
    }
    optionsMarkup += "<label class='decision-option'><input type='radio' name='decision-request-choice' value='other'><span class='decision-option-index'>" + String(options.length + 1) + ".</span><span class='decision-option-text'>Other</span></label>";

    el.decisionRequestInlineQuestion.textContent = info.request.question;
    el.decisionRequestOptions.innerHTML = optionsMarkup;
    if (el.decisionRequestOtherInput) {
      el.decisionRequestOtherInput.value = "";
    }
    if (el.decisionRequestInline) {
      el.decisionRequestInline.dataset.marker = info.marker;
    }
    updateDecisionOtherVisibility();
    el.decisionRequestInline.classList.remove("hidden");
  }

  function renderCommandApprovalInline() {
    if (
      !el.commandApprovalInline ||
      !el.commandApprovalInlineAllowOnce ||
      !el.commandApprovalInlineDenyOnce ||
      !el.commandApprovalInlineAllowRemember ||
      !el.commandApprovalInlineDenyRemember
    ) {
      return;
    }
    if (pendingCommandApproval || approvalAnswerPending) {
      return;
    }
    var info = activeApprovalRequestInfo();
    if (!info) {
      el.commandApprovalInline.classList.add("hidden");
      return;
    }
    if (el.commandApprovalInlineText) {
      if (!info.hasCommand) {
        el.commandApprovalInlineText.textContent = "A command approval is pending, but command details were unavailable. You can allow once to retry or deny once to cancel.";
      } else {
        el.commandApprovalInlineText.textContent = info.request.reason
          ? "Agent requested a command (" + info.request.reason + ")."
          : "Agent requested command execution approval.";
      }
    }
    if (el.commandApprovalInlineCommand) {
      el.commandApprovalInlineCommand.textContent = info.hasCommand ? info.request.command : "(Command unavailable)";
    }
    if (el.commandApprovalInlineMatchMode) {
      el.commandApprovalInlineMatchMode.value = "exact";
      el.commandApprovalInlineMatchMode.disabled = !info.hasCommand;
    }
    if (el.commandApprovalInlinePattern) {
      el.commandApprovalInlinePattern.value = info.hasCommand ? defaultCommandRulePattern(info.request.command) : "";
      el.commandApprovalInlinePattern.disabled = !info.hasCommand;
    }
    el.commandApprovalInlineAllowOnce.onclick = function () {
      submitApprovalRequestAnswerWithUi("allow", "once", el.commandApprovalInlineAllowOnce).catch(showError);
    };
    el.commandApprovalInlineDenyOnce.onclick = function () {
      submitApprovalRequestAnswerWithUi("deny", "once", el.commandApprovalInlineDenyOnce).catch(showError);
    };
    el.commandApprovalInlineAllowRemember.onclick = function () {
      submitApprovalRequestAnswerWithUi("allow", "remember", el.commandApprovalInlineAllowRemember).catch(showError);
    };
    el.commandApprovalInlineDenyRemember.onclick = function () {
      submitApprovalRequestAnswerWithUi("deny", "remember", el.commandApprovalInlineDenyRemember).catch(showError);
    };
    el.commandApprovalInlineAllowRemember.disabled = !info.hasCommand;
    el.commandApprovalInlineDenyRemember.disabled = !info.hasCommand;
    if (el.commandApprovalInlineClose) {
      el.commandApprovalInlineClose.onclick = function () {
        el.commandApprovalInline.classList.add("hidden");
      };
    }
    el.commandApprovalInline.classList.remove("hidden");
  }

  function basename(pathText) {
    var clean = trim(String(pathText || "")).replace(/[\\/]+$/, "");
    if (!clean) {
      return "";
    }
    var idx = Math.max(clean.lastIndexOf("/"), clean.lastIndexOf("\\"));
    if (idx < 0) {
      return clean;
    }
    return clean.slice(idx + 1);
  }

  function openTargetLabel(target) {
    if (target === "terminal") {
      return "Terminal";
    }
    if (target === "textmate") {
      return "TextMate";
    }
    return "Finder";
  }

  function firstOpenTargetFromMenu() {
    if (!el.openMenu) {
      return "finder";
    }
    var first = el.openMenu.querySelector("button[data-open-target]");
    if (!first) {
      return "finder";
    }
    return String(first.getAttribute("data-open-target") || "finder");
  }

  function normalizedOpenTarget(target) {
    var value = String(target || "");
    if (value === "finder" || value === "terminal" || value === "textmate") {
      return value;
    }
    return firstOpenTargetFromMenu();
  }

  function openTargetIconMarkup(target) {
    var finderIcon = state.appIcons && state.appIcons.finder ? String(state.appIcons.finder) : "";
    var textmateIcon = state.appIcons && state.appIcons.textmate ? String(state.appIcons.textmate) : "";
    if (target === "terminal") {
      return "<span class='btn-icon app-icon terminal-app-icon' aria-hidden='true'><svg viewBox='0 0 16 16' fill='none'><rect x='1.2' y='2' width='13.6' height='12' rx='2.2' fill='#181B2A' stroke='#454A66' stroke-width='1'></rect><path d='M4 6.1l2 1.9L4 9.9' stroke='#D8DEFF' stroke-width='1.2' stroke-linecap='round' stroke-linejoin='round'></path><path d='M7.8 10h4.2' stroke='#D8DEFF' stroke-width='1.2' stroke-linecap='round'></path></svg></span>";
    }
    if (target === "textmate") {
      if (textmateIcon) {
        return "<span class='btn-icon app-icon textmate-icon real-app-icon' aria-hidden='true'><img class='app-icon-img' src='" + escAttr(textmateIcon) + "' alt=''></span>";
      }
      return "<span class='btn-icon app-icon textmate-icon' aria-hidden='true'><svg viewBox='0 0 16 16' fill='none'><circle cx='8' cy='8' r='6.3' fill='#F5ECFF' stroke='#A669D8' stroke-width='1'></circle><path d='M8 3.2l1.2 2.2 2.3-.8-.9 2.2 2.2 1.2-2.2 1.2.9 2.2-2.3-.8L8 12.8l-1.2-2.2-2.3.8.9-2.2L3.2 8l2.2-1.2-.9-2.2 2.3.8L8 3.2z' fill='#B84FE8'></path></svg></span>";
    }
    if (finderIcon) {
      return "<span class='btn-icon app-icon finder-icon real-app-icon' aria-hidden='true'><img class='app-icon-img' src='" + escAttr(finderIcon) + "' alt=''></span>";
    }
    return "<span class='btn-icon app-icon finder-icon' aria-hidden='true'></span>";
  }

  function renderOpenMenuIcons() {
    function setMenuIcon(target, dataUri) {
      var button = el.openMenu ? el.openMenu.querySelector("button[data-open-target='" + target + "']") : null;
      if (!button) {
        return;
      }
      var host = button.querySelector(".app-icon");
      if (!host) {
        return;
      }
      if (!dataUri) {
        host.classList.remove("real-app-icon");
        host.innerHTML = "";
        return;
      }
      host.classList.add("real-app-icon");
      host.innerHTML = "<img class='app-icon-img' src='" + escAttr(dataUri) + "' alt=''>";
    }

    setMenuIcon("finder", state.appIcons.finder || "");
    setMenuIcon("textmate", state.appIcons.textmate || "");
  }

  function commitActionIconMarkup(action) {
    if (action === "push") {
      return "<span class='btn-icon' aria-hidden='true'>&#10548;</span>";
    }
    if (action === "commit-push") {
      return "<span class='btn-icon' aria-hidden='true'>&#10549;</span>";
    }
    return "<span class='btn-icon' aria-hidden='true'>&#10227;</span>";
  }

  function renderOpenButton() {
    if (!el.openMainBtn || !el.openMenuBtn) {
      return;
    }
    var ws = activeWorkspace();
    var target = normalizedOpenTarget(state.lastOpenTarget);
    state.lastOpenTarget = target;
    var label = "Open";
    if (!ws) {
      el.openMainBtn.innerHTML = openTargetIconMarkup(target) + "<span class='btn-label'>" + escHtml(label) + "</span>";
      el.openMainBtn.title = "";
      el.openMainBtn.disabled = true;
      el.openMenuBtn.disabled = true;
      return;
    }
    el.openMainBtn.innerHTML = openTargetIconMarkup(target) + "<span class='btn-label'>" + escHtml(label) + "</span>";
    el.openMainBtn.title = ws.path || "";
    el.openMainBtn.disabled = false;
    el.openMenuBtn.disabled = false;
    if (el.openMenu) {
      var openButtons = el.openMenu.querySelectorAll("button[data-open-target]");
      for (var i = 0; i < openButtons.length; i += 1) {
        var openTarget = openButtons[i].getAttribute("data-open-target");
        openButtons[i].classList.toggle("active", openTarget === target);
      }
    }
  }

  function commitActionLabel(action) {
    if (action === "push") {
      return "Push";
    }
    if (action === "commit-push") {
      return "Commit & Push";
    }
    return "Commit";
  }

  function renderCommitButton() {
    if (!el.commitMainBtn) {
      return;
    }
    var ws = activeWorkspace();
    var gitState = activeGitState();
    var commitEnabled = !!ws;
    var action = state.lastCommitAction || "commit";
    el.commitMainBtn.innerHTML =
      commitActionIconMarkup(action) +
      "<span class='btn-label'>" + escHtml(commitActionLabel(action)) + "</span>";
    el.commitMainBtn.disabled = !commitEnabled;
    if (el.commitMenuBtn) {
      el.commitMenuBtn.disabled = !commitEnabled;
    }
    if (!commitEnabled && el.commitMenu && !el.commitMenu.classList.contains("hidden")) {
      el.commitMenu.classList.add("hidden");
    }
    if (!ws) {
      el.commitMainBtn.title = "Select a project first";
    } else if (gitState && gitState.is_repo) {
      el.commitMainBtn.title = "Primary commit action";
    } else {
      el.commitMainBtn.title = "No repo yet: click to create one";
    }
    if (el.commitMenuBtn) {
      el.commitMenuBtn.title = commitEnabled ? "Choose commit action" : "Select a project first";
    }
    if (el.commitMenu) {
      var commitButtons = el.commitMenu.querySelectorAll("button[data-commit-action]");
      for (var i = 0; i < commitButtons.length; i += 1) {
        var commitAction = commitButtons[i].getAttribute("data-commit-action");
        commitButtons[i].classList.toggle("active", commitAction === action);
        commitButtons[i].disabled = !ws;
      }
    }
  }

  function renderWorkspacePathWidget() {
    if (!el.workspacePathWidget) {
      return;
    }
    var ws = activeWorkspace();
    if (!ws || !ws.path) {
      el.workspacePathWidget.classList.add("hidden");
      el.workspacePathWidget.innerHTML = "";
      el.workspacePathWidget.title = "";
      el.workspacePathWidget.setAttribute("data-tooltip", "No project selected");
      el.workspacePathWidget.setAttribute("aria-label", "No project selected");
      el.workspacePathWidget.disabled = true;
      return;
    }
    var folderName = basename(ws.path) || ws.path;
    el.workspacePathWidget.classList.remove("hidden");
    el.workspacePathWidget.innerHTML =
      "<span class='path-widget-icon' aria-hidden='true'><svg viewBox='0 0 16 16' fill='none' stroke='currentColor' stroke-width='1.4' stroke-linecap='round' stroke-linejoin='round'><path d='M1.8 4.4h4.1l1.2 1.3h7.1v6.1c0 .9-.7 1.6-1.6 1.6H3.4c-.9 0-1.6-.7-1.6-1.6z'></path></svg></span>" +
      "<span class='path-widget-label'>" + escHtml(folderName) + "</span>";
    el.workspacePathWidget.title = "Click to copy path. Double-click to open folder.";
    el.workspacePathWidget.setAttribute("data-tooltip", "Click to copy path. Double-click to open folder.");
    el.workspacePathWidget.setAttribute("aria-label", "Project path: " + ws.path);
    el.workspacePathWidget.disabled = false;
  }

  function updateToolbarCompaction() {
    if (!el.toolbar) {
      return;
    }
    function commitControlVisible() {
      if (!el.commitMainBtn || !el.commitMenuBtn) {
        return true;
      }
      var toolbarRect = el.toolbar.getBoundingClientRect();
      var mainRect = el.commitMainBtn.getBoundingClientRect();
      var menuRect = el.commitMenuBtn.getBoundingClientRect();
      return mainRect.left >= toolbarRect.left - 1 && menuRect.right <= toolbarRect.right + 1;
    }
    function fitsWithinToolbar() {
      return el.toolbar.scrollWidth <= el.toolbar.clientWidth + 1 && commitControlVisible();
    }
    function titleIsTruncated() {
      if (!el.chatTitle) {
        return false;
      }
      return el.chatTitle.scrollWidth > el.chatTitle.clientWidth + 1;
    }
    var compactClasses = ["path-icon-only", "open-icon-only", "commit-icon-only"];
    var i = 0;
    for (i = 0; i < compactClasses.length; i += 1) {
      el.toolbar.classList.remove(compactClasses[i]);
    }
    if (!fitsWithinToolbar() || titleIsTruncated()) {
      el.toolbar.classList.add("path-icon-only");
    }
    for (i = 0; i < compactClasses.length; i += 1) {
      if (fitsWithinToolbar()) {
        break;
      }
      el.toolbar.classList.add(compactClasses[i]);
    }
  }

  function contextKFromCatalogEntry(entry) {
    var raw = entry && typeof entry.context_k !== "undefined" ? entry.context_k : "";
    var parsed = Number(raw);
    if (!isFinite(parsed) || parsed <= 0) {
      return 0;
    }
    return Math.round(parsed);
  }

  function normalizedModelKey(text) {
    return trim(String(text || "")).toLowerCase();
  }

  function baseModelKey(text) {
    var key = normalizedModelKey(text);
    if (!key) {
      return "";
    }
    return key.split(":")[0];
  }

  function modelContextFromCatalog(modelName) {
    var target = normalizedModelKey(modelName);
    if (!target || !Array.isArray(state.modelCatalog) || !state.modelCatalog.length) {
      return 0;
    }
    var targetBase = baseModelKey(target);
    for (var i = 0; i < state.modelCatalog.length; i += 1) {
      var entry = state.modelCatalog[i] || {};
      if (normalizedModelKey(entry.name) === target) {
        return contextKFromCatalogEntry(entry);
      }
    }
    for (var j = 0; j < state.modelCatalog.length; j += 1) {
      var entry2 = state.modelCatalog[j] || {};
      if (baseModelKey(entry2.name) === targetBase) {
        return contextKFromCatalogEntry(entry2);
      }
    }
    return 0;
  }

  function inferredModelContextK(modelName) {
    var model = normalizedModelKey(modelName);
    if (!model) {
      return 0;
    }
    var explicitK = model.match(/(?:^|[^0-9])(\d{1,4})\s*k(?:[^a-z0-9]|$)/i);
    if (explicitK && explicitK[1]) {
      var parsed = Number(explicitK[1]);
      if (isFinite(parsed) && parsed > 0) {
        return Math.round(parsed);
      }
    }
    if (model.indexOf("llama3.1:8b") >= 0) {
      return 128;
    }
    if (model.indexOf("deepseek-coder-v2:16b") >= 0 || model.indexOf("qwen2.5-coder:7b") >= 0) {
      return 32;
    }
    if (model.indexOf("starcoder2:7b") >= 0 || model.indexOf("codellama:13b") >= 0) {
      return 16;
    }
    if (model.indexOf("phi3:mini") >= 0 || model.indexOf("mistral:7b") >= 0) {
      return 8;
    }
    return 0;
  }

  function activeModelContextInfo(modelName) {
    var catalogK = modelContextFromCatalog(modelName);
    if (catalogK > 0) {
      return {
        contextK: catalogK,
        source: "catalog"
      };
    }
    var inferredK = inferredModelContextK(modelName);
    if (inferredK > 0) {
      return {
        contextK: inferredK,
        source: "inferred"
      };
    }
    return {
      contextK: 0,
      source: "unknown"
    };
  }

  function renderContextWindowStatus() {
    if (!el.contextWindowBtn) {
      return;
    }
    var model = activeModelName();
    if (!model) {
      state.contextWindowText = "Context window information will display here.";
      el.contextWindowBtn.classList.add("unavailable");
      el.contextWindowBtn.setAttribute("data-tooltip", state.contextWindowText);
      el.contextWindowBtn.title = state.contextWindowText;
      return;
    }
    var info = activeModelContextInfo(model);
    if (info.contextK > 0) {
      var contextLabel = String(info.contextK) + "k tokens";
      var sourceLabel = info.source === "catalog" ? "catalog metadata" : "model-name inference";
      state.contextWindowText = "Context window: " + contextLabel + " (" + sourceLabel + "). Auto compaction: enabled.";
      el.contextWindowBtn.classList.remove("unavailable");
    } else {
      state.contextWindowText = "Context window unknown for this model. Auto compaction remains enabled with conservative limits.";
      el.contextWindowBtn.classList.add("unavailable");
    }
    el.contextWindowBtn.setAttribute("data-tooltip", state.contextWindowText);
    el.contextWindowBtn.setAttribute("aria-label", "Context window status. " + state.contextWindowText);
    el.contextWindowBtn.title = state.contextWindowText;
  }

  function renderChat() {
    var conversationKey = String(state.activeWorkspaceId || "") + "::" + String(state.activeConversationId || "") + "::" + String(state.activeDraftWorkspaceId || "");
    var keyChanged = conversationKey !== state.chatLastKey;
    var prevScrollTop = el.chatLog ? el.chatLog.scrollTop : 0;
    var prevClientHeight = el.chatLog ? el.chatLog.clientHeight : 0;
    var prevScrollHeight = el.chatLog ? el.chatLog.scrollHeight : 0;
    var prevBottomOffset = Math.max(0, prevScrollHeight - prevScrollTop - prevClientHeight);
    var shouldAutoScroll = keyChanged || state.chatAutoScroll;
    snapshotRunThinkingPreviewScroll();

    if (state.sidebarSection === "automations") {
      var automationViewHtml = "<section class='automations-main-view'>";
      automationViewHtml += "<div class='automations-main-head'>";
      automationViewHtml += "<h3>Automations</h3>";
      automationViewHtml += "<div class='automations-main-actions'>";
      automationViewHtml += "<button type='button' data-action='open-threads'>Threads</button>";
      automationViewHtml += "<button type='button' data-action='automation-new'" + (state.workspaces.length ? "" : " disabled") + ">New automation</button>";
      automationViewHtml += "</div>";
      automationViewHtml += "</div>";
      if (!state.automations || !Array.isArray(state.automations.items) || !state.automations.items.length) {
        automationViewHtml += "<p class='automation-empty automations-main-empty'>No automations yet. Create one to schedule recurring work.</p>";
      } else {
        for (var a = 0; a < state.automations.items.length; a += 1) {
          var automation = state.automations.items[a] || {};
          var automationId = String(automation.id || "");
          if (!automationId) {
            continue;
          }
          var isActiveAutomation = String(state.activeAutomationId || "") === automationId;
          var scheduleText = trim(String(automation.schedule_text || ""));
          if (!scheduleText) {
            scheduleText = trim(String(automation.schedule_kind || "")) + " " + trim(String(automation.schedule_value || ""));
          }
          var targetPieces = [];
          if (trim(String(automation.workspace_name || ""))) {
            targetPieces.push(String(automation.workspace_name || ""));
          } else if (trim(String(automation.workspace_id || ""))) {
            targetPieces.push(String(automation.workspace_id || ""));
          }
          if (trim(String(automation.conversation_title || ""))) {
            targetPieces.push(String(automation.conversation_title || ""));
          } else if (trim(String(automation.conversation_id || ""))) {
            targetPieces.push(String(automation.conversation_id || ""));
          }
          var targetLabel = targetPieces.join(" · ");
          if (!targetLabel) {
            targetLabel = "No thread selected";
          }
          var statusClass = automationStatusClass(automation);
          var statusLabel = automationStatusLabel(automation);
          var nextRunLabel = automationNextRunLabel(automation);
          var lastRunLabel = automationLastRunLabel(automation);

          automationViewHtml += "<section class='automation-row" + (isActiveAutomation ? " active" : "") + "' role='button' tabindex='0' data-action='select-automation' data-automation-id='" + escAttr(automationId) + "'>";
          automationViewHtml += "<div class='automation-row-head'>";
          automationViewHtml += "<span class='automation-title'>" + escHtml(automation.name || "Automation") + "</span>";
          automationViewHtml += "<span class='automation-state-pill " + escAttr(statusClass) + "'>" + escHtml(statusLabel) + "</span>";
          automationViewHtml += "</div>";
          automationViewHtml += "<div class='automation-meta'>";
          automationViewHtml += "<span><strong>Schedule:</strong> " + escHtml(scheduleText || "unspecified") + "</span>";
          automationViewHtml += "<span><strong>Next:</strong> " + escHtml(nextRunLabel) + "</span>";
          automationViewHtml += "<span><strong>Last:</strong> " + escHtml(lastRunLabel) + "</span>";
          automationViewHtml += "</div>";
          automationViewHtml += "<div class='automation-target' title='" + escAttr(targetLabel) + "'>" + escHtml(targetLabel) + "</div>";
          automationViewHtml += "<div class='automation-row-actions'>";
          automationViewHtml += "<label class='automation-enable-row' title='Enable or pause automation' data-action='automation-toggle-label' data-automation-id='" + escAttr(automationId) + "'><input type='checkbox' data-action='automation-toggle-enabled' data-automation-id='" + escAttr(automationId) + "'" + (String(automation.enabled || "0") === "1" ? " checked" : "") + " /> Enabled</label>";
          automationViewHtml += "<button type='button' data-action='automation-run-now' data-automation-id='" + escAttr(automationId) + "'>Run now</button>";
          automationViewHtml += "<button type='button' data-action='automation-edit' data-automation-id='" + escAttr(automationId) + "'>Edit</button>";
          automationViewHtml += "<button type='button' class='ghost danger' data-action='automation-delete' data-automation-id='" + escAttr(automationId) + "'>Delete</button>";
          automationViewHtml += "</div>";
          if (trim(String(automation.last_error || ""))) {
            automationViewHtml += "<p class='automation-error' title='" + escAttr(String(automation.last_error || "")) + "'>" + escHtml(String(automation.last_error || "")) + "</p>";
          }
          automationViewHtml += "</section>";
        }
      }
      automationViewHtml += "</section>";
      if (state.chatMarkupCache !== automationViewHtml) {
        el.chatLog.innerHTML = automationViewHtml;
        state.chatMarkupCache = automationViewHtml;
      }
      state.chatAutoScroll = true;
      state.chatLastKey = conversationKey;
      updateChatJumpButton();
      return;
    }

    if (state.activeTriage) {
      var triageCards = Array.isArray(state.triage && state.triage.cards) ? state.triage.cards : [];
      var triageViewHtml = "<section class='triage-main-view'><h3>Triage</h3>";
      if (!triageCards.length) {
        triageViewHtml += "<p class='empty-state'>No triage items right now.</p>";
      } else {
        for (var t = 0; t < triageCards.length; t += 1) {
          var triageCard = triageCards[t] || {};
          var triageCardId = String(triageCard.id || "");
          var triageOtherOpen = triageCardId && String(state.triageOtherInputProposalId || "") === triageCardId;
          triageViewHtml += "<article class='triage-main-card'>";
          triageViewHtml += "<div class='triage-main-card-head'>";
          triageViewHtml += "<p class='triage-main-title'><strong>" + escHtml(triageCard.summary || "Proposal") + "</strong></p>";
          triageViewHtml += "<button type='button' class='icon-btn triage-goto-btn' data-action='triage-open-context' data-workspace-id='" + escAttr(triageCard.workspace_id || "") + "' data-conversation-id='" + escAttr(triageCard.conversation_id || "") + "' data-proposal-id='" + escAttr(triageCardId) + "' title='Go to source thread' aria-label='Go to source thread'><span aria-hidden='true'>&#8599;</span></button>";
          triageViewHtml += "</div>";
          triageViewHtml += "<p class='settings-hint'>" + escHtml(multiAgentEscalationLabel(triageCard.escalation_class || "")) + " • " + escHtml(multiAgentTargetTypeLabel(triageCard.target_type || "")) + " • agent " + escHtml(triageCard.resident || "") + "</p>";
          triageViewHtml += "<p class='settings-hint'>" + escHtml(triageCard.rationale || "") + "</p>";
          triageViewHtml += "<div class='triage-question'>What should we do?</div>";
          triageViewHtml += "<div class='triage-choice-row'>";
          triageViewHtml += "<button type='button' data-action='triage-decide' data-proposal-id='" + escAttr(triageCardId) + "' data-decision='accepted'>Accept</button>";
          triageViewHtml += "<button type='button' data-action='triage-decide' data-proposal-id='" + escAttr(triageCardId) + "' data-decision='deferred'>Defer</button>";
          triageViewHtml += "<button type='button' data-action='triage-decide' data-proposal-id='" + escAttr(triageCardId) + "' data-decision='dismissed'>Dismiss</button>";
          triageViewHtml += "<button type='button' class='ghost' data-action='triage-decision-other-toggle' data-proposal-id='" + escAttr(triageCardId) + "'>" + (triageOtherOpen ? "Cancel" : "Other...") + "</button>";
          triageViewHtml += "</div>";
          triageViewHtml += "<div class='triage-other-row" + (triageOtherOpen ? "" : " hidden") + "' data-triage-other-row='" + escAttr(triageCardId) + "'>";
          triageViewHtml += "<input type='text' class='triage-other-input' data-triage-other-input='" + escAttr(triageCardId) + "' placeholder='Enter a custom decision' />";
          triageViewHtml += "<button type='button' data-action='triage-decision-other-submit' data-proposal-id='" + escAttr(triageCardId) + "'>Apply</button>";
          triageViewHtml += "</div>";
          triageViewHtml += "<div class='triage-card-footer'>";
          triageViewHtml += "<button type='button' class='ghost' data-action='triage-suppress-workspace' data-proposal-id='" + escAttr(triageCardId) + "'>Don't ask about this</button>";
          triageViewHtml += "</div>";
          triageViewHtml += "</article>";
        }
      }
      triageViewHtml += "</section>";
      if (state.chatMarkupCache !== triageViewHtml) {
        el.chatLog.innerHTML = triageViewHtml;
        state.chatMarkupCache = triageViewHtml;
      }
      state.chatAutoScroll = true;
      state.chatLastKey = conversationKey;
      updateChatJumpButton();
      return;
    }

    if (!state.activeWorkspaceId) {
      var emptyWorkspaceMarkup = "<p class='empty-thread-hint'>Select a thread</p>";
      if (state.chatMarkupCache !== emptyWorkspaceMarkup) {
        el.chatLog.innerHTML = emptyWorkspaceMarkup;
        state.chatMarkupCache = emptyWorkspaceMarkup;
      }
      state.chatAutoScroll = true;
      state.chatLastKey = conversationKey;
      updateChatJumpButton();
      return;
    }

    var outgoingKey = activeOutgoingKey();
    var pendingOutgoing = pendingOutgoingList(outgoingKey);

    if (state.activeDraftWorkspaceId) {
      if (pendingOutgoing.length) {
        var draftPendingHtml = "";
        for (var d = 0; d < pendingOutgoing.length; d += 1) {
          var pendingDraft = pendingOutgoing[d] || {};
          draftPendingHtml += "<article class='msg user pending'><div class='msg-body'>" + escHtml(pendingDraft.content || "") + "</div><p class='msg-pending-line'><span class='run-spinner' aria-hidden='true'></span>Sending...</p></article>";
        }
        if (state.chatMarkupCache !== draftPendingHtml) {
          el.chatLog.innerHTML = draftPendingHtml;
          state.chatMarkupCache = draftPendingHtml;
        }
      } else {
        var draftHintMarkup = "<p class='empty-state draft-create-hint'>Send a message to create the thread.</p>";
        if (state.chatMarkupCache !== draftHintMarkup) {
          el.chatLog.innerHTML = draftHintMarkup;
          state.chatMarkupCache = draftHintMarkup;
        }
      }
      state.chatAutoScroll = true;
      state.chatLastKey = conversationKey;
      updateChatJumpButton();
      return;
    }

    if (!state.activeConversationId) {
      var noConversationMarkup = "<p class='empty-thread-hint'>Select a thread</p>";
      if (state.chatMarkupCache !== noConversationMarkup) {
        el.chatLog.innerHTML = noConversationMarkup;
        state.chatMarkupCache = noConversationMarkup;
      }
      state.chatAutoScroll = true;
      state.chatLastKey = conversationKey;
      updateChatJumpButton();
      return;
    }

    if (!state.activeConversation) {
      if (state.activeConversationLoading && !state.conversationSwitchOverlay) {
        var inlineLoadingMarkup = "<p class='empty-thread-hint loading-thread-hint'><span>Loading...</span><span class='run-spinner' aria-hidden='true'></span></p>";
        if (state.chatMarkupCache !== inlineLoadingMarkup) {
          el.chatLog.innerHTML = inlineLoadingMarkup;
          state.chatMarkupCache = inlineLoadingMarkup;
        }
        state.chatAutoScroll = true;
        state.chatLastKey = conversationKey;
        updateChatJumpButton();
        return;
      }
      if (state.activeConversationLoading || state.conversationSwitchOverlay) {
        // During thread switch, keep existing chat paint and rely on the overlay.
        state.chatAutoScroll = true;
        state.chatLastKey = conversationKey;
        updateChatJumpButton();
        return;
      }
      var loadErrorText = trim(String(state.activeConversationLoadError || ""));
      if (loadErrorText) {
        var failedMarkup = "<div class='thread-load-error'><p><strong>Thread unavailable.</strong></p><p>" + escHtml(loadErrorText) + "</p><button type='button' class='ghost' data-action='retry-load-conversation'>Retry</button></div>";
        if (state.chatMarkupCache !== failedMarkup) {
          el.chatLog.innerHTML = failedMarkup;
          state.chatMarkupCache = failedMarkup;
        }
        state.chatAutoScroll = true;
        state.chatLastKey = conversationKey;
        updateChatJumpButton();
        return;
      }
      var noConversationMessagesMarkup = "<p class='empty-state'>No messages yet in this thread.</p>";
      if (state.chatMarkupCache !== noConversationMessagesMarkup) {
        el.chatLog.innerHTML = noConversationMessagesMarkup;
        state.chatMarkupCache = noConversationMessagesMarkup;
      }
      state.chatAutoScroll = true;
      state.chatLastKey = conversationKey;
      updateChatJumpButton();
      return;
    }

    if (state.activeConversationLoading) {
      // Keep the currently visible thread while loading the next one.
      state.chatAutoScroll = true;
      state.chatLastKey = conversationKey;
      updateChatJumpButton();
      return;
    }

    var messages = Array.isArray(state.activeConversation.messages) ? state.activeConversation.messages : [];
    healRunningEventsForConversationFromSummary(state.activeWorkspaceId, state.activeConversationId);
    backfillRunEventAnchorsFromMessages(state.activeConversationId, messages);
    var events = runEventsForConversation(state.activeConversationId).slice().sort(compareRunEventsChronological);

    if (!messages.length && !events.length && !pendingOutgoing.length) {
      var queueStats = activeConversationQueueStats();
      var runIsActiveHere = !!(
        queueStats.running ||
        queueStats.pending > 0 ||
        (
          state.busy &&
          String(state.runningWorkspaceId || "") === String(state.activeWorkspaceId || "") &&
          String(state.runningConversationId || "") === String(state.activeConversationId || "")
        )
      );
      var selectedAt = Number(state.activeConversationSelectedAt || 0);
      var recentlySelected = selectedAt > 0 && Date.now() - selectedAt < 12000;
      if (runIsActiveHere || recentlySelected) {
        var runningOnlyMarkup = "";
        if (runIsActiveHere) {
          var ghostStartedIso = selectedAt > 0 ? new Date(selectedAt).toISOString() : new Date().toISOString();
          runningOnlyMarkup = "<article class='run-line-only'>";
          runningOnlyMarkup += formatRunRunningHeader({
            started_at: ghostStartedIso,
            last_activity_at: ghostStartedIso
          }, state.activeWorkspaceId, state.activeConversationId);
          if (state.activeWorkspaceId && state.activeConversationId) {
            runningOnlyMarkup += "<p class='run-line subtle'>Working in this thread. Stream details will appear as events arrive.</p>";
          }
          runningOnlyMarkup += "</article>";
        } else {
          runningOnlyMarkup = "<p class='empty-state'>No messages yet in this thread.</p>";
        }
        if (state.chatMarkupCache !== runningOnlyMarkup) {
          el.chatLog.innerHTML = runningOnlyMarkup;
          state.chatMarkupCache = runningOnlyMarkup;
        }
      } else {
        var noMessagesMarkup = "<p class='empty-state'>No messages yet in this thread.</p>";
        if (state.chatMarkupCache !== noMessagesMarkup) {
          el.chatLog.innerHTML = noMessagesMarkup;
          state.chatMarkupCache = noMessagesMarkup;
        }
      }
      state.chatAutoScroll = true;
      state.chatLastKey = conversationKey;
      updateChatJumpButton();
      return;
    }

    if (hasActiveChatSelection()) {
      updateChatJumpButton();
      return;
    }

    var html = "";
    var anchoredEventsByIndex = {};
    var tailEvents = [];
    for (var e = 0; e < events.length; e += 1) {
      var queuedEvent = events[e] || {};
      var eventStatus = String(queuedEvent.status || "");
      var anchorRaw = Number(queuedEvent.message_anchor);
      var hasAnchor = isFinite(anchorRaw) && anchorRaw >= 0;
      if (!hasAnchor && eventStatus === "approval_granted") {
        anchorRaw = messages.length;
        hasAnchor = true;
      }
      if (hasAnchor) {
        var anchorIndex = Math.max(0, Math.min(messages.length, Math.floor(anchorRaw)));
        if (!anchoredEventsByIndex[anchorIndex]) {
          anchoredEventsByIndex[anchorIndex] = [];
        }
        anchoredEventsByIndex[anchorIndex].push(queuedEvent);
      } else {
        tailEvents.push(queuedEvent);
      }
    }

    var anchorKeys = Object.keys(anchoredEventsByIndex);
    for (var ak = 0; ak < anchorKeys.length; ak += 1) {
      var anchorBucket = anchoredEventsByIndex[anchorKeys[ak]];
      if (Array.isArray(anchorBucket) && anchorBucket.length > 1) {
        anchorBucket.sort(compareRunEventsChronological);
      }
    }
    if (tailEvents.length > 1) {
      tailEvents.sort(compareRunEventsChronological);
    }

    function renderAnchoredEventsAt(index) {
      var bucket = anchoredEventsByIndex[index];
      if (!bucket || !bucket.length) {
        return;
      }
      for (var bi = 0; bi < bucket.length; bi += 1) {
        html += renderRunEvent(bucket[bi], state.activeWorkspaceId, state.activeConversationId);
      }
    }

    function renderMessageAt(index) {
      var msg = messages[index] || {};
      var role = msg.role === "user" ? "user" : "assistant";
      if (role === "user") {
        html += "<article class='msg user'>";
        html += "<button type='button' class='msg-copy-btn' data-action='copy-user-message' data-copy-text='" + escAttr(msg.content || "") + "' aria-label='Copy message' title='Copy message'><span aria-hidden='true'><svg viewBox='0 0 16 16' fill='none' stroke='currentColor' stroke-width='1.35' stroke-linecap='round' stroke-linejoin='round'><rect x='5.4' y='5.3' width='7.2' height='7.2' rx='1.1'></rect><rect x='3.2' y='3.1' width='7.2' height='7.2' rx='1.1'></rect></svg></span></button>";
        html += "<div class='msg-body'>" + escHtml(msg.content || "") + "</div>";
        html += "</article>";
      } else {
        html += "<article class='msg assistant'><div class='msg-body'>" + escHtml(msg.content || "") + "</div></article>";
      }
    }

    renderAnchoredEventsAt(0);
    for (var m = 0; m < messages.length; m += 1) {
      renderMessageAt(m);
      renderAnchoredEventsAt(m + 1);
    }

    for (var p = 0; p < pendingOutgoing.length; p += 1) {
      var pending = pendingOutgoing[p] || {};
      html += "<article class='msg user pending'><div class='msg-body'>" + escHtml(pending.content || "") + "</div><p class='msg-pending-line'><span class='run-spinner' aria-hidden='true'></span>Sending...</p></article>";
    }

    for (var j = 0; j < tailEvents.length; j += 1) {
      var event = tailEvents[j] || {};
      html += renderRunEvent(event, state.activeWorkspaceId, state.activeConversationId);
    }

    if (state.chatMarkupCache !== html) {
      el.chatLog.innerHTML = html;
      state.chatMarkupCache = html;
    }
    var approvalInlineVisible = !!(
      el.commandApprovalInline &&
      !el.commandApprovalInline.classList.contains("hidden")
    );
    if (approvalInlineVisible && el.commandApprovalInline && el.chatLog) {
      if (el.commandApprovalInline.parentNode !== el.chatLog) {
        el.chatLog.appendChild(el.commandApprovalInline);
      }
      el.commandApprovalInline.classList.add("in-chat");
      shouldAutoScroll = true;
      state.chatAutoScroll = true;
    } else if (el.commandApprovalInline) {
      el.commandApprovalInline.classList.remove("in-chat");
    }
    if (shouldAutoScroll) {
      el.chatLog.scrollTop = el.chatLog.scrollHeight;
      state.chatAutoScroll = true;
    } else {
      var nextScrollTop = Math.max(0, el.chatLog.scrollHeight - el.chatLog.clientHeight - prevBottomOffset);
      el.chatLog.scrollTop = nextScrollTop;
      state.chatAutoScroll = isChatAtBottom();
    }
    state.chatLastKey = conversationKey;
    updateChatJumpButton();
    refreshRunningElapsedBadges();
    if (!liveRunTickTimer && el.chatLog && el.chatLog.querySelector(".run-line.running[data-started-at]")) {
      liveRunTickTimer = setInterval(function () {
        refreshRunningElapsedBadges();
      }, 1000);
    } else if (liveRunTickTimer && !state.busy && el.chatLog && !el.chatLog.querySelector(".run-line.running[data-started-at]")) {
      clearInterval(liveRunTickTimer);
      liveRunTickTimer = null;
    }
    syncRunThinkingPreviewScroll();
  }

  function hasActiveChatSelection() {
    if (!el.chatLog || !window.getSelection) {
      return false;
    }
    var sel = window.getSelection();
    if (!sel || sel.rangeCount < 1 || sel.isCollapsed) {
      return false;
    }
    var range = sel.getRangeAt(0);
    var container = range.commonAncestorContainer;
    if (!container) {
      return false;
    }
    var node = container.nodeType === 1 ? container : container.parentNode;
    return !!(node && el.chatLog.contains(node));
  }

  function formatDiff(diffText) {
    var raw = String(diffText || "");
    if (!trim(raw)) {
      return "<p class='empty-state'>No diff available.</p>";
    }

    var lines = raw.split(/\r?\n/);
    var html = "";
    for (var i = 0; i < lines.length; i += 1) {
      var line = lines[i];
      var cls = "";

      if (/^diff --git /.test(line) || /^\+\+\+ /.test(line) || /^--- /.test(line) || /^### /.test(line)) {
        cls = " file";
      } else if (/^@@ /.test(line)) {
        cls = " hunk";
      } else if (/^\+/.test(line) && !/^\+\+\+ /.test(line)) {
        cls = " add";
      } else if (/^-/.test(line) && !/^--- /.test(line)) {
        cls = " del";
      }

      html += "<span class='diff-line" + cls + "'>" + escHtml(line || " ") + "</span>";
    }
    return html;
  }

  function renderDiffView() {
    if (!el.diffView) {
      return;
    }
    el.diffView.innerHTML = formatDiff(state.diffText || "");
  }

  function renderTerminal() {
    if (!el.terminalOutput) {
      return;
    }
    if (el.terminalPanel) {
      el.terminalPanel.classList.toggle("busy", !!state.terminalBusy);
    }
    if (el.terminalCwd) {
      el.terminalCwd.textContent = state.terminalCwd || "Terminal";
    }
    var terminalText = String(state.terminalStreamText || "");
    if (state.terminalInputBuffer) {
      if (terminalText && terminalText.charAt(terminalText.length - 1) !== "\n") {
        terminalText += "\n";
      }
      terminalText += state.terminalInputBuffer;
    }
    var terminalHasVisibleText = /\S/.test(terminalText);
    var terminalIsEmpty = !!state.terminalOpen && !state.terminalBusy && !terminalHasVisibleText;
    if (el.shell) {
      el.shell.classList.toggle("terminal-empty", terminalIsEmpty);
    }
    if (el.terminalPanel) {
      el.terminalPanel.classList.toggle("empty", terminalIsEmpty);
    }
    el.terminalOutput.textContent = terminalText;
    el.terminalOutput.scrollTop = el.terminalOutput.scrollHeight;
  }

  function clampThreadsPaneWidth(width) {
    var minWidth = 250;
    var maxWidth = Math.min(620, Math.max(300, Math.floor(window.innerWidth * 0.66)));
    var value = Number(width || 0);
    if (!isFinite(value) || value <= 0) {
      value = 308;
    }
    if (value < minWidth) {
      value = minWidth;
    }
    if (value > maxWidth) {
      value = maxWidth;
    }
    return Math.round(value);
  }

  function clampDiffPaneWidth(width) {
    var shellWidth = (el.shell && el.shell.clientWidth) || window.innerWidth || 1200;
    var minWidth = 300;
    var maxWidth = Math.max(minWidth, Math.min(940, shellWidth - 260));
    var value = Number(width || 0);
    if (!isFinite(value) || value <= 0) {
      value = minWidth;
    }
    if (value < minWidth) {
      value = minWidth;
    }
    if (value > maxWidth) {
      value = maxWidth;
    }
    return Math.round(value);
  }

  function clampModelsPaneHeight(height) {
    var value = Number(height || 0);
    if (!isFinite(value) || value <= 0) {
      value = 300;
    }
    var minHeight = 140;
    var maxHeight = 560;
    if (el.workspacePanel) {
      var sidebarHeight = Number(el.workspacePanel.clientHeight || 0);
      var headEl = el.workspacePanel.querySelector(".workspace-sidebar-head");
      var footerEl = el.workspacePanel.querySelector(".workspace-sidebar-footer");
      var headHeight = headEl ? Number(headEl.offsetHeight || 0) : 0;
      var footerHeight = footerEl ? Number(footerEl.offsetHeight || 0) : 0;
      var minTreeHeight = 110;
      var dynamicMax = sidebarHeight - headHeight - footerHeight - minTreeHeight;
      if (isFinite(dynamicMax) && dynamicMax > 0) {
        maxHeight = Math.max(minHeight, Math.min(maxHeight, Math.floor(dynamicMax)));
      }
    }
    if (value < minHeight) {
      value = minHeight;
    }
    if (value > maxHeight) {
      value = maxHeight;
    }
    return Math.round(value);
  }

  function applyPaneWidths() {
    if (!el.shell) {
      return;
    }
    state.threadsPaneWidth = clampThreadsPaneWidth(state.threadsPaneWidth);
    state.diffPaneWidth = clampDiffPaneWidth(state.diffPaneWidth);
    state.modelsPaneHeight = clampModelsPaneHeight(state.modelsPaneHeight);
    el.shell.style.setProperty("--threads-width", state.threadsPaneWidth + "px");
    el.shell.style.setProperty("--diff-width", state.diffPaneWidth + "px");
    if (el.workspacePanel) {
      el.workspacePanel.style.setProperty("--models-pane-height", state.modelsPaneHeight + "px");
    }
  }

  function persistPaneWidths() {
    storageSet("artificer.threadsPaneWidth", String(state.threadsPaneWidth));
    storageSet("artificer.diffPaneWidth", String(state.diffPaneWidth));
    storageSet("artificer.modelsPaneHeight", String(state.modelsPaneHeight));
  }

  function stopPaneDrag() {
    if (!paneDragState) {
      return;
    }
    var draggedPaneType = String(paneDragState.type || "");
    paneDragState = null;
    if (document && document.body) {
      document.body.classList.remove("pane-resizing");
      document.body.classList.remove("pane-resizing-y");
    }
    if (draggedPaneType === "models") {
      suppressMenuCloseUntilMs = Date.now() + 280;
    }
    persistPaneWidths();
  }

  function onPaneDragMove(event) {
    if (!paneDragState || !el.shell) {
      return;
    }
    var shellRect = el.shell.getBoundingClientRect();
    if (paneDragState.type === "threads") {
      var nextThreads = event.clientX - shellRect.left;
      state.threadsPaneWidth = clampThreadsPaneWidth(nextThreads);
    } else if (paneDragState.type === "diff") {
      var nextDiff = shellRect.right - event.clientX;
      state.diffPaneWidth = clampDiffPaneWidth(nextDiff);
    } else if (paneDragState.type === "models") {
      if (!el.workspacePanel) {
        return;
      }
      var sidebarRect = el.workspacePanel.getBoundingClientRect();
      var footerEl = el.workspacePanel.querySelector(".workspace-sidebar-footer");
      var footerHeight = footerEl ? Number(footerEl.offsetHeight || 0) : 0;
      var nextModels = sidebarRect.bottom - event.clientY - footerHeight;
      state.modelsPaneHeight = clampModelsPaneHeight(nextModels);
    } else {
      return;
    }
    applyPaneWidths();
  }

  function startPaneDrag(type, event) {
    if (!el.shell) {
      return;
    }
    event.preventDefault();
    paneDragState = {
      type: type
    };
    if (document && document.body) {
      document.body.classList.add(type === "models" ? "pane-resizing-y" : "pane-resizing");
    }
  }

  function renderPanels() {
    if (!el.diffPanel || !el.terminalPanel || !el.shell) {
      return;
    }
    applyPaneWidths();
    if (state.diffOpen) {
      el.diffPanel.classList.remove("hidden");
      el.shell.classList.add("diff-open");
    } else {
      el.diffPanel.classList.add("hidden");
      el.shell.classList.remove("diff-open");
    }

    if (state.terminalOpen) {
      el.terminalPanel.classList.remove("hidden");
      el.shell.classList.add("terminal-open");
      if (
        state.activeWorkspaceId &&
        state.terminalSessionWorkspaceId &&
        state.terminalSessionWorkspaceId !== state.activeWorkspaceId
      ) {
        ensureTerminalSession().catch(function () {
          return null;
        });
      }
    } else {
      el.terminalPanel.classList.add("hidden");
      el.shell.classList.remove("terminal-open");
      el.shell.classList.remove("terminal-empty");
      el.terminalPanel.classList.remove("empty");
    }
    if (el.terminalToggleBtn) {
      el.terminalToggleBtn.classList.toggle("on", !!state.terminalOpen);
      el.terminalToggleBtn.setAttribute("aria-pressed", state.terminalOpen ? "true" : "false");
    }

    renderDiffView();
    renderTerminal();
  }

  function renderUi() {
    function safeStep(name, fn) {
      try {
        fn();
      } catch (err) {
        if (window && window.console && typeof window.console.error === "function") {
          window.console.error("Artificer render step failed:", name, err);
        }
      }
    }

    safeStep("ensureSelection", ensureSelection);
    safeStep("hydrateTooltips", hydrateTooltips);
    safeStep("renderSidebarSectionChrome", renderSidebarSectionChrome);
    safeStep("renderWorkspaceTree", renderWorkspaceTree);
    safeStep("renderModelStatus", renderModelStatus);
    safeStep("renderThemePicker", renderThemePicker);
    safeStep("renderOrganizeMenu", renderOrganizeMenu);
    safeStep("renderModelPickerButton", renderModelPickerButton);
    safeStep("renderRunControls", renderRunControls);
    safeStep("renderProgrammingSettings", renderProgrammingSettings);
    safeStep("renderSelfImproveSettings", renderSelfImproveSettings);
    safeStep("renderDictateButton", renderDictateButton);
    safeStep("renderDictationMode", renderDictationMode);
    safeStep("renderRunButton", renderRunButton);
    safeStep("renderQueueControls", renderQueueControls);
    safeStep("renderOpenButton", renderOpenButton);
    safeStep("renderOpenMenuIcons", renderOpenMenuIcons);
    safeStep("renderCommitButton", renderCommitButton);
    safeStep("renderWorkspacePathWidget", renderWorkspacePathWidget);
    safeStep("renderModelsDialog", renderModelsDialog);
    safeStep("renderModelList.modelPicker", function () {
      renderModelListInto(el.modelPickerList, activeModelName());
    });
    safeStep("renderPermissionsButton", renderPermissionsButton);
    safeStep("renderContextWindowStatus", renderContextWindowStatus);
    safeStep("renderToolbarGit", renderToolbarGit);
    safeStep("renderBranchMenu", renderBranchMenu);
    safeStep("renderRightPaneChrome", renderRightPaneChrome);
    safeStep("renderChatHeader", renderChatHeader);
    safeStep("renderDecisionRequestInline", renderDecisionRequestInline);
    safeStep("renderCommandApprovalInline", renderCommandApprovalInline);
    safeStep("renderChat", renderChat);
    safeStep("renderConversationSwitchOverlay", renderConversationSwitchOverlay);
    safeStep("renderToolbarSwitchLock", renderToolbarSwitchLock);
    safeStep("renderAttachmentStrip", renderAttachmentStrip);
    safeStep("renderRunTodoMonitor", renderRunTodoMonitor);
    safeStep("renderQueueTray", renderQueueTray);
    safeStep("renderRunTerminalMonitor", renderRunTerminalMonitor);
    safeStep("renderAutomationDaemonSettings", renderAutomationDaemonSettings);
    safeStep("renderDictationInstallSettings", renderDictationInstallSettings);
    safeStep("renderCommandRulesSettings", renderCommandRulesSettings);
    safeStep("renderModeRuntimeSettings", renderModeRuntimeSettings);
    safeStep("renderMultiAgentModal", renderMultiAgentModal);
    safeStep("renderPanels", renderPanels);
    safeStep("updateToolbarCompaction", updateToolbarCompaction);
    if (window && typeof window.requestAnimationFrame === "function") {
      window.requestAnimationFrame(updateToolbarCompaction);
    }
  }

  function saveSortMode(mode) {
    var next = mode === "created" ? "created" : "updated";
    state.sortMode = next;
    storageSet("artificer.workspaceSort", next);
  }

  function saveOrganizeMode(mode) {
    var next = mode === "chrono" ? "chrono" : "project";
    state.organizeMode = next;
    storageSet("artificer.organizeMode", next);
  }

  function saveOrganizeShow(mode) {
    var next = "all";
    if (mode === "relevant") {
      next = "relevant";
    } else if (mode === "running") {
      next = "running";
    }
    state.organizeShow = next;
    storageSet("artificer.organizeShow", next);
  }

  function normalizeAutomationsState(inputState) {
    var source = inputState && typeof inputState === "object" ? inputState : {};
    var sourceItems = Array.isArray(source.items) ? source.items : [];
    var items = [];
    for (var i = 0; i < sourceItems.length; i += 1) {
      var item = sourceItems[i] && typeof sourceItems[i] === "object" ? sourceItems[i] : {};
      var automationId = trim(String(item.id || ""));
      if (!automationId) {
        continue;
      }
      items.push({
        id: automationId,
        name: trim(String(item.name || "")) || "Automation",
        workspace_id: trim(String(item.workspace_id || "")),
        workspace_name: trim(String(item.workspace_name || "")),
        conversation_id: trim(String(item.conversation_id || "")),
        conversation_title: trim(String(item.conversation_title || "")),
        prompt: String(item.prompt || ""),
        schedule_kind: trim(String(item.schedule_kind || "")),
        schedule_value: trim(String(item.schedule_value || "")),
        schedule_text: trim(String(item.schedule_text || "")),
        enabled: String(item.enabled || "0") === "1" ? "1" : "0",
        allow_self_reschedule: String(item.allow_self_reschedule || "0") === "1" ? "1" : "0",
        next_run: String(item.next_run || "0"),
        next_run_iso: trim(String(item.next_run_iso || "")),
        last_run: String(item.last_run || "0"),
        last_run_iso: trim(String(item.last_run_iso || "")),
        last_status: trim(String(item.last_status || "")),
        last_error: trim(String(item.last_error || "")),
        created: String(item.created || "0"),
        created_iso: trim(String(item.created_iso || "")),
        updated: String(item.updated || "0"),
        updated_iso: trim(String(item.updated_iso || "")),
        run_mode: trim(String(item.run_mode || "assistant")) || "assistant",
        assistant_mode_id: trim(String(item.assistant_mode_id || "")),
        compute_budget: trim(String(item.compute_budget || "auto")) || "auto",
        command_exec_mode: trim(String(item.command_exec_mode || "")),
        permission_mode: trim(String(item.permission_mode || "")),
        programmer_review: String(item.programmer_review || "1") === "1" ? "1" : "0",
        programmer_review_rounds: String(item.programmer_review_rounds || "2"),
        assay_task_id: trim(String(item.assay_task_id || "")),
        explicit_skill_ids: Array.isArray(item.explicit_skill_ids) ? item.explicit_skill_ids : []
      });
    }
    items.sort(function (a, b) {
      var aEnabled = a.enabled === "1" ? 1 : 0;
      var bEnabled = b.enabled === "1" ? 1 : 0;
      if (aEnabled !== bEnabled) {
        return bEnabled - aEnabled;
      }
      var aRun = Number(a.next_run || 0);
      var bRun = Number(b.next_run || 0);
      if (!isFinite(aRun) || aRun < 0) {
        aRun = 0;
      }
      if (!isFinite(bRun) || bRun < 0) {
        bRun = 0;
      }
      if (aRun <= 0 && bRun > 0) {
        return 1;
      }
      if (bRun <= 0 && aRun > 0) {
        return -1;
      }
      if (aRun !== bRun) {
        return aRun - bRun;
      }
      return String(a.name || "").localeCompare(String(b.name || ""));
    });
    return {
      count: String(items.length),
      items: items
    };
  }

  function applyAutomationsState(inputState) {
    state.automations = normalizeAutomationsState(inputState);
    var activeId = String(state.activeAutomationId || "");
    var foundActive = false;
    for (var i = 0; i < state.automations.items.length; i += 1) {
      if (String(state.automations.items[i].id || "") === activeId) {
        foundActive = true;
        break;
      }
    }
    if (!foundActive) {
      state.activeAutomationId = state.automations.items.length ? String(state.automations.items[0].id || "") : "";
    }
  }

  function activeAutomation() {
    var targetId = String(state.activeAutomationId || "");
    if (!targetId || !state.automations || !Array.isArray(state.automations.items)) {
      return null;
    }
    for (var i = 0; i < state.automations.items.length; i += 1) {
      var item = state.automations.items[i] || {};
      if (String(item.id || "") === targetId) {
        return item;
      }
    }
    return null;
  }

  function automationById(automationId) {
    var targetId = trim(String(automationId || ""));
    if (!targetId || !state.automations || !Array.isArray(state.automations.items)) {
      return null;
    }
    for (var i = 0; i < state.automations.items.length; i += 1) {
      var item = state.automations.items[i] || {};
      if (String(item.id || "") === targetId) {
        return item;
      }
    }
    return null;
  }

  function saveSidebarSection(nextSection) {
    var normalized = nextSection === "automations" ? "automations" : "threads";
    state.sidebarSection = normalized;
    if (normalized === "automations" && state.activeTriage) {
      state.activeTriage = false;
    }
    storageSet("artificer.sidebarSection", normalized);
    state.workspaceTreeMarkupCache = "";
    closeAllMenus();
    state.openWorkspaceMenuWorkspaceId = "";
  }

  function renderSidebarSectionChrome() {
    var automationsMode = state.sidebarSection === "automations";
    if (el.sidebarNavAutomationsItem) {
      el.sidebarNavAutomationsItem.classList.toggle("active", automationsMode);
      el.sidebarNavAutomationsItem.setAttribute("aria-selected", automationsMode ? "true" : "false");
    }
    if (el.sidebarNavAutomationsCount) {
      var automationCount = 0;
      if (state.automations && Array.isArray(state.automations.items)) {
        automationCount = state.automations.items.length;
      } else {
        automationCount = Number(state.automations && state.automations.count || 0) || 0;
      }
      el.sidebarNavAutomationsCount.textContent = String(automationCount);
    }
    if (el.workspaceTreeTitle) {
      el.workspaceTreeTitle.textContent = "Threads";
    }
  }

  function parseEpochOrZero(value) {
    var n = Number(value || 0);
    if (!isFinite(n) || n <= 0) {
      return 0;
    }
    return Math.floor(n);
  }

  function formatFutureAgeShort(deltaSeconds) {
    var delta = Number(deltaSeconds || 0);
    if (!isFinite(delta) || delta <= 0) {
      return "now";
    }
    if (delta < 60) {
      return Math.ceil(delta) + "s";
    }
    if (delta < 3600) {
      return Math.ceil(delta / 60) + "m";
    }
    if (delta < 86400) {
      return Math.ceil(delta / 3600) + "h";
    }
    if (delta < 86400 * 30) {
      return Math.ceil(delta / 86400) + "d";
    }
    if (delta < 86400 * 365) {
      return Math.ceil(delta / (86400 * 30)) + "mo";
    }
    return Math.ceil(delta / (86400 * 365)) + "y";
  }

  function epochToLocalLabel(epochValue) {
    var epoch = parseEpochOrZero(epochValue);
    if (!epoch) {
      return "";
    }
    try {
      return new Date(epoch * 1000).toLocaleString([], {
        month: "short",
        day: "numeric",
        hour: "numeric",
        minute: "2-digit"
      });
    } catch (_err) {
      return "";
    }
  }

  function automationNextRunLabel(item) {
    var automationItem = item || {};
    var enabled = String(automationItem.enabled || "0") === "1";
    if (!enabled) {
      return "Disabled";
    }
    var nextEpoch = parseEpochOrZero(automationItem.next_run);
    if (!nextEpoch) {
      return "Not scheduled";
    }
    var nowEpoch = Math.floor(Date.now() / 1000);
    if (nextEpoch <= nowEpoch) {
      return "Due now";
    }
    var deltaLabel = formatFutureAgeShort(nextEpoch - nowEpoch);
    var localLabel = epochToLocalLabel(nextEpoch);
    if (localLabel) {
      return "in " + deltaLabel + " (" + localLabel + ")";
    }
    return "in " + deltaLabel;
  }

  function automationLastRunLabel(item) {
    var automationItem = item || {};
    var lastRunEpoch = parseEpochOrZero(automationItem.last_run);
    if (!lastRunEpoch) {
      return "never";
    }
    return formatAgeShort(lastRunEpoch) + " ago";
  }

  function renderOrganizeMenu() {
    if (!el.organizeMenu || state.sidebarSection !== "threads") {
      return;
    }
    var modeButtons = el.organizeMenu.querySelectorAll("button[data-organize-mode]");
    for (var i = 0; i < modeButtons.length; i += 1) {
      var modeValue = modeButtons[i].getAttribute("data-organize-mode");
      modeButtons[i].classList.toggle("active", modeValue === state.organizeMode);
    }

    var sortButtons = el.organizeMenu.querySelectorAll("button[data-organize-sort]");
    for (var j = 0; j < sortButtons.length; j += 1) {
      var sortValue = sortButtons[j].getAttribute("data-organize-sort");
      sortButtons[j].classList.toggle("active", sortValue === state.sortMode);
    }

    var showButtons = el.organizeMenu.querySelectorAll("button[data-organize-show]");
    for (var k = 0; k < showButtons.length; k += 1) {
      var showValue = showButtons[k].getAttribute("data-organize-show");
      showButtons[k].classList.toggle("active", showValue === state.organizeShow);
    }
  }

  function savePermissionMode(mode) {
    state.permissionMode = mode;
    storageSet("artificer.permissionMode", mode);
  }

  function saveCommandExecMode(mode) {
    var next = "ask-some";
    if (mode === "ask") {
      next = "ask-some";
    } else if (mode === "none" || mode === "ask-all" || mode === "ask-some" || mode === "all") {
      next = mode;
    }
    state.commandExecMode = next;
    storageSet("artificer.commandExecMode", next);
  }

  function syncCommandExecModeForWorkspace(workspaceId) {
    var wsId = trim(workspaceId);
    if (!wsId) {
      return Promise.resolve();
    }
    return apiGet("command_policy_get", { workspace_id: wsId })
      .then(function (response) {
        if (!response || !response.success) {
          return;
        }
        saveCommandExecMode(response.mode || "ask-some");
      })
      .catch(function () {
        return null;
      });
  }

  function setCommandExecMode(mode) {
    var next = mode;
    if (next === "ask") {
      next = "ask-some";
    }
    if (next !== "none" && next !== "ask-all" && next !== "ask-some" && next !== "all") {
      next = "ask-some";
    }
    if (next === "all") {
      var ok = window.confirm("Ask none will allow all agent commands without asking. Continue?");
      if (!ok) {
        return Promise.resolve(false);
      }
    }
    saveCommandExecMode(next);
    if (!state.activeWorkspaceId) {
      return Promise.resolve(true);
    }
    return apiPost("command_policy_set", {
      workspace_id: state.activeWorkspaceId,
      mode: next
    })
      .then(function (response) {
        if (!response || !response.success) {
          throw new Error((response && response.error) || "Could not save command policy");
        }
        saveCommandExecMode(response.mode || next);
        return true;
      });
  }

  function saveAgentLoopEnabled(enabled) {
    state.agentLoopEnabled = !!enabled;
    storageSet("artificer.agentLoopEnabled", state.agentLoopEnabled ? "1" : "0");
  }

  function modeFromSlashCommand(commandText) {
    var value = String(commandText || "").toLowerCase().replace(/^\/+/, "");
    if (value === "chat") {
      return "chat";
    }
    if (value === "teacher" || value === "teach" || value === "learn" || value === "study" || value === "tutor") {
      return "teacher";
    }
    if (value === "task" || value === "programming" || value === "program" || value === "code" || value === "dev") {
      return "programming";
    }
    if (value === "pentest" || value === "redteam" || value === "red-team") {
      return "pentest";
    }
    if (value === "security-audit" || value === "security" || value === "audit" || value === "sec-audit") {
      return "security-audit";
    }
    if (value === "report") {
      return "report";
    }
    if (
      value === "text-perfecter" ||
      value === "textperfecter" ||
      value === "perfecter" ||
      value === "perfect" ||
      value === "polish" ||
      value === "refine"
    ) {
      return "text-perfecter";
    }
    if (
      value === "gui-testing" ||
      value === "guitesting" ||
      value === "gui" ||
      value === "ui-testing" ||
      value === "uitesting" ||
      value === "hands-on-testing" ||
      value === "handson-testing" ||
      value === "hands-on" ||
      value === "ux-testing" ||
      value === "uxtesting"
    ) {
      return "gui-testing";
    }
    if (
      value === "assistant" ||
      value === "team" ||
      value === "teams" ||
      value === "autonomous" ||
      value === "autonomy" ||
      value === "endeavor" ||
      value === "endeavour"
    ) {
      return "assistant";
    }
    if (value === "auto" || value === "thinking" || value === "loop") {
      return "auto";
    }
    if (value === "instant" || value === "quick") {
      return "instant";
    }
    return "";
  }

  function normalizeDirectiveSkillId(skillId) {
    var value = trim(String(skillId || "")).toLowerCase();
    if (!value) {
      return "";
    }
    if (!/^[a-z][a-z0-9_-]*$/.test(value)) {
      return "";
    }
    return value;
  }

  function parsePromptExplicitSkillTags(promptText) {
    var text = String(promptText || "");
    if (!text) {
      return [];
    }
    var pattern = /\$([a-z][a-z0-9_-]*)\b/ig;
    var seen = {};
    var skills = [];
    var match = null;
    while ((match = pattern.exec(text))) {
      var normalized = normalizeDirectiveSkillId(match[1] || "");
      if (!normalized || seen[normalized]) {
        continue;
      }
      seen[normalized] = 1;
      skills.push(normalized);
      if (skills.length >= 12) {
        break;
      }
    }
    return skills;
  }

  function mergeSkillIdLists(firstList, secondList) {
    var merged = [];
    var seen = {};

    function append(list) {
      var source = Array.isArray(list) ? list : [];
      for (var i = 0; i < source.length; i += 1) {
        var normalized = normalizeDirectiveSkillId(source[i]);
        if (!normalized || seen[normalized]) {
          continue;
        }
        seen[normalized] = 1;
        merged.push(normalized);
        if (merged.length >= 18) {
          return;
        }
      }
    }

    append(firstList);
    append(secondList);
    return merged;
  }

  function parsePromptModeDirective(promptText) {
    var raw = String(promptText || "");
    var working = raw;
    var matchedMode = "";
    var matchedTag = "";
    var guard = 0;
    while (guard < 3) {
      var match = working.match(/^\s*\/([a-z][a-z0-9_-]*)\b[ \t]*/i);
      if (!match) {
        break;
      }
      var tag = "/" + String(match[1] || "").toLowerCase();
      var mappedMode = modeFromSlashCommand(tag);
      if (!mappedMode) {
        break;
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
        };
      }
      finalizeAllRunningEvents(
        conversationId,
        finalStatus,
        finalStatus === "error" ? finalErrorText || "Run did not complete." : finalErrorText
      );
      if (
        state.busy &&
        String(state.runningWorkspaceId || "") === String(workspaceId || "") &&
        String(state.runningConversationId || "") === String(conversationId || "")
      ) {
        setBusy(false);
      }
      renderUi();
      return true;
    }

    return Promise.race([
      runAgent(workspaceId, conversationId, item.prompt || "", {
        preserveSelection: true,
        attachments: Array.isArray(item.attachments) ? item.attachments : [],
        queueItemId: itemId,
        runMode: normalizeRunMode(item.run_mode || "auto"),
        assistantModeId: item.assistant_mode_id || "",
        computeBudget: normalizeComputeBudget(item.compute_budget || "auto"),
        programmerReview: normalizeProgrammerReviewEnabledValue(item.programmer_review),
        programmerReviewRounds: normalizeProgrammerReviewRoundsValue(item.programmer_review_rounds || 2),
        permissionMode: normalizePermissionModeValue(item.permission_mode || ""),
        commandExecMode: normalizeCommandExecModeValue(item.command_exec_mode || ""),
        explicitSkillIds: Array.isArray(item.explicit_skill_ids) ? item.explicit_skill_ids : [],
        approvalRetry: options.approvalRetry === true,
        pendingEvent: resumedPendingEvent
      })
        .then(function (result) {
          return { kind: "run", result: result || null };
        })
        .catch(function (err) {
          return { kind: "run-error", error: err };
        }),
      queueWatch.promise.then(function (watchInfo) {
        return { kind: "watch", info: watchInfo || null };
      })
    ])
      .then(function (outcome) {
        if (!outcome) {
          return null;
        }
        if (outcome.kind === "run-error") {
          runError = outcome.error;
          if (queueWatch && isRetriableRequestError(runError)) {
            return queueWatch.promise.then(function (watchInfo) {
              if (applyWatchInfo(watchInfo)) {
                runError = null;
              }
              return null;
            });
          }
          return null;
        }
        if (outcome.kind === "watch" && outcome.info) {
          applyWatchInfo(outcome.info);
          return null;
        }
        runResult = outcome.result || null;
        return null;
      })
      .then(function () {
        if (queueFinalizeApplied) {
          return null;
        }
        if (runError) {
          finalStatus = "error";
        } else if (runResult && runResult.awaitingDecision) {
          finalStatus = "awaiting_decision";
        } else if (runResult && runResult.awaitingApproval) {
          finalStatus = "awaiting_approval";
        } else {
          finalStatus = "done";
        }
        finalErrorText = runError && runError.message ? runError.message : "";
        return queueFinish(workspaceId, conversationId, itemId, finalStatus, finalErrorText).then(function (response) {
          queueFinalizeApplied = true;
          return response;
        }).catch(function (queueErr) {
          showError(queueErr);
          setConversationQueueFields(workspaceId, conversationId, {
            running: false,
            done: finalStatus === "done",
            lastStatus: finalStatus
          });
          return null;
        });
      })
      .finally(function () {
        if (queueWatch) {
          queueWatch.stop();
        }
        if (!queueFinalizeApplied) {
          setConversationQueueFields(workspaceId, conversationId, {
            running: false,
            done: finalStatus === "done",
            lastStatus: finalStatus
          });
        }
        finalizeAllRunningEvents(
          conversationId,
          finalStatus,
          finalStatus === "error" ? finalErrorText || "Run did not complete." : finalErrorText
        );
        setBusy(false);
        renderUi();
        loadState()
          .catch(function () {
            return null;
          })
          .then(function () {
            if (state.activeWorkspaceId && state.activeConversationId) {
              return loadConversation({ timeoutMs: 6000 }).catch(function () {
                return null;
              });
            }
            return null;
          })
          .finally(function () {
            renderUi();
          });
      });
  }

  function drainQueuedRuns() {
    if (state.busy) {
      return clearStaleBusyIfNeeded().then(function (cleared) {
        if (cleared) {
          return drainQueuedRuns();
        }
        return null;
      });
    }

    var target = findNextQueuedConversation();
    if (!target) {
      return Promise.resolve();
    }

    return apiPost("queue_take", {
      workspace_id: target.workspaceId,
      conversation_id: target.conversationId
    }, { timeoutMs: 60000 }).then(function (response) {
      if (!response.success) {
        throw new Error(response.error || "Could not fetch queued message");
      }

      if (response.busy) {
        applyQueueStateFromResponse(target.workspaceId, target.conversationId, response);
        return null;
      }

      if (!response.has_item || !response.item) {
        applyQueueStateFromResponse(target.workspaceId, target.conversationId, response);
        return loadState().then(function () {
          return drainQueuedRuns();
        });
      }

      setConversationQueueFields(target.workspaceId, target.conversationId, {
        pending: queueNumber(response.queue_pending),
        running: true,
        done: false,
        firstId: response.queue_first_id || ""
      });

      return executeQueuedItem(target.workspaceId, target.conversationId, normalizeQueueListItem(response.item)).then(function () {
        return drainQueuedRuns();
      });
    });
  }

  function clearStaleBusyIfNeeded() {
    if (!state.busy) {
      return Promise.resolve(false);
    }
    return apiGet("state", {}, { timeoutMs: 18000 })
      .then(function (response) {
        var workspaces = response && Array.isArray(response.workspaces) ? response.workspaces : [];
        var hasQueueRunning = false;
        for (var i = 0; i < workspaces.length; i += 1) {
          var workspace = workspaces[i] || {};
          var conversations = Array.isArray(workspace.conversations) ? workspace.conversations : [];
          for (var j = 0; j < conversations.length; j += 1) {
            if (String(conversations[j] && conversations[j].queue_running || "0") === "1") {
              hasQueueRunning = true;
              break;
            }
          }
          if (hasQueueRunning) {
            break;
          }
        }
        if (!hasQueueRunning) {
          setBusy(false);
          return true;
        }
        return false;
      })
      .catch(function () {
        return false;
      });
  }

  function stopApprovalResumeWatch() {
    if (approvalResumeWatchTimer) {
      clearInterval(approvalResumeWatchTimer);
      approvalResumeWatchTimer = null;
    }
    approvalResumeWatchBusy = false;
    approvalResumeWatchKey = "";
    approvalResumeWatchDeadline = 0;
  }

  function startApprovalResumeWatch(workspaceId, conversationId) {
    var wsId = String(workspaceId || "");
    var convId = String(conversationId || "");
    if (!wsId || !convId) {
      return;
    }

    stopApprovalResumeWatch();
    var watchKey = conversationReadKey(wsId, convId);
    approvalResumeWatchKey = watchKey;
    approvalResumeWatchDeadline = Date.now() + 90000;

    function tick() {
      if (
        approvalResumeWatchKey !== watchKey ||
        approvalResumeWatchBusy
      ) {
        return;
      }
      if (Date.now() > approvalResumeWatchDeadline) {
        stopApprovalResumeWatch();
        return;
      }

      approvalResumeWatchBusy = true;
      apiGet("state", {}, { timeoutMs: 18000 })
        .then(function (response) {
          if (approvalResumeWatchKey !== watchKey) {
            return;
          }

          var conversation = findConversationStateEntry(response, wsId, convId);
          if (!conversation) {
            return;
          }

          var pending = queueNumber(conversation.queue_pending);
          var running = String(conversation.queue_running || "0") === "1";
          syncConversationQueueFromStateEntry(wsId, convId, conversation);
          releaseApprovalAnswerUiPendingIfAdvanced(wsId, convId, conversation);

          if (pending > 0 && !running && !state.busy) {
            state.queueWorkerActive = false;
            kickQueueWorker();
            return;
          }

          if (running || pending > 0) {
            return;
          }

          if (
            state.busy &&
            String(state.runningWorkspaceId || "") === wsId &&
            String(state.runningConversationId || "") === convId
          ) {
            setBusy(false);
          }

          if (
            state.activeWorkspaceId === wsId &&
            state.activeConversationId === convId
          ) {
            loadConversation({ timeoutMs: 6000 }).catch(function () {
              return null;
            });
            renderUi();
            stopApprovalResumeWatch();
            return;
          }

          renderUi();
          stopApprovalResumeWatch();
        })
        .catch(function () {
          return null;
        })
        .finally(function () {
          approvalResumeWatchBusy = false;
        });
    }

    approvalResumeWatchTimer = setInterval(tick, 4000);
    tick();
  }

  function resumeConversationQueueNow(workspaceId, conversationId) {
    var wsId = String(workspaceId || "");
    var convId = String(conversationId || "");
    if (!wsId || !convId) {
      return Promise.resolve(false);
    }

    if (state.busy) {
      return clearStaleBusyIfNeeded().then(function (cleared) {
        if (!cleared && state.busy) {
          return false;
        }
        return resumeConversationQueueNow(wsId, convId);
      });
    }

    return apiPost("queue_take", {
      workspace_id: wsId,
      conversation_id: convId
    }, { timeoutMs: 60000 }).then(function (response) {
      if (!response || !response.success) {
        throw new Error((response && response.error) || "Could not resume queued run");
      }
      applyQueueStateFromResponse(wsId, convId, response);
      if (response.busy || !response.has_item || !response.item) {
        return false;
      }
      setConversationQueueFields(wsId, convId, {
        pending: queueNumber(response.queue_pending),
        running: true,
        done: false,
        firstId: response.queue_first_id || "",
        lastStatus: "running"
      });
      return executeQueuedItem(wsId, convId, normalizeQueueListItem(response.item), { approvalRetry: true }).then(function () {
        return true;
      });
    });
  }

  function kickQueueWorker() {
    if (state.queueWorkerActive) {
      return;
    }

    if (!findNextQueuedConversation()) {
      return;
    }

    state.queueWorkerActive = true;
    drainQueuedRuns()
      .catch(function (err) {
        if (state.activeConversationId) {
          showError(err);
        } else if (window && window.console && typeof window.console.error === "function") {
          window.console.error(err);
        }
      })
      .finally(function () {
        state.queueWorkerActive = false;
        renderUi();
        if (!state.busy && findNextQueuedConversation()) {
          window.setTimeout(function () {
            kickQueueWorker();
          }, 120);
        }
      });
  }

  function steerQueuedMessage(queueItemId, options) {
    var opts = options || {};
    var wsId = String(opts.workspaceId || state.activeWorkspaceId || "");
    var convId = String(opts.conversationId || state.activeConversationId || "");
    var itemId = trim(queueItemId || "");
    if (!wsId || !convId || !itemId) {
      return Promise.resolve();
    }

    return apiPost("queue_steer", {
      workspace_id: wsId,
      conversation_id: convId,
      item_id: itemId
    }).then(function (response) {
      if (!response.success) {
        throw new Error(response.error || "Could not steer queued message");
      }
      applyQueueStateFromResponse(wsId, convId, response);
      if (isQueueEditForConversation(wsId, convId) && String(state.queueEdit.itemId || "") === itemId) {
        clearQueueEditState();
      }
      return loadQueueItems(wsId, convId, { force: true, minIntervalMs: 0 }).catch(function () {
        return null;
      }).then(function () {
        if (opts.interruptRunning && queueStatsForConversation(wsId, convId).running) {
          return stopConversationRun(wsId, convId, { suppressNotice: true }).then(function () {
            showTransientNotice("Steered message injected");
            kickQueueWorker();
          });
        }
        renderUi();
        kickQueueWorker();
        return null;
      });
    });
  }

  function cancelQueuedMessage(queueItemId, options) {
    var opts = options || {};
    var wsId = String(opts.workspaceId || state.activeWorkspaceId || "");
    var convId = String(opts.conversationId || state.activeConversationId || "");
    var itemId = trim(queueItemId || "");
    if (!wsId || !convId || !itemId) {
      return Promise.resolve();
    }

    return apiPost("queue_cancel", {
      workspace_id: wsId,
      conversation_id: convId,
      item_id: itemId
    }).then(function (response) {
      if (!response.success) {
        throw new Error(response.error || "Could not cancel queued message");
      }
      if (response.item_id && state.lastQueuedItemIdByConversation[convId] === response.item_id) {
        delete state.lastQueuedItemIdByConversation[convId];
      }
      applyQueueStateFromResponse(wsId, convId, response);
      if (isQueueEditForConversation(wsId, convId) && String(state.queueEdit.itemId || "") === String(response.item_id || itemId)) {
        clearQueueEditState();
      }
      return loadQueueItems(wsId, convId, { force: true, minIntervalMs: 0 }).catch(function () {
        return null;
      }).then(function () {
        renderUi();
        kickQueueWorker();
        return null;
      });
    });
  }

  function updateQueuedMessage(queueItemId, promptText, options) {
    var opts = options || {};
    var wsId = String(opts.workspaceId || state.activeWorkspaceId || "");
    var convId = String(opts.conversationId || state.activeConversationId || "");
    var itemId = trim(queueItemId || "");
    var nextPrompt = String(promptText || "");
    if (!wsId || !convId || !itemId) {
      return Promise.resolve();
    }
    if (!trim(nextPrompt)) {
      return Promise.reject(new Error("Queued message cannot be empty."));
    }
    return apiPost("queue_update", {
      workspace_id: wsId,
      conversation_id: convId,
      item_id: itemId,
      prompt: nextPrompt
    }).then(function (response) {
      if (!response || !response.success) {
        throw new Error((response && response.error) || "Could not update queued message");
      }
      applyQueueStateFromResponse(wsId, convId, response);
      return loadQueueItems(wsId, convId, { force: true, minIntervalMs: 0 }).catch(function () {
        return null;
      }).then(function () {
        return response;
      });
    });
  }

  function reorderQueuedMessages(workspaceId, conversationId, orderedIds) {
    var wsId = String(workspaceId || "");
    var convId = String(conversationId || "");
    var ids = Array.isArray(orderedIds) ? orderedIds : [];
    if (!wsId || !convId || ids.length < 2) {
      return Promise.resolve();
    }
    return apiPost("queue_reorder", {
      workspace_id: wsId,
      conversation_id: convId,
      item_ids: ids.join(",")
    }).then(function (response) {
      if (!response || !response.success) {
        throw new Error((response && response.error) || "Could not reorder queued messages");
      }
      applyQueueStateFromResponse(wsId, convId, response);
      return loadQueueItems(wsId, convId, { force: true, minIntervalMs: 0 }).catch(function () {
        return null;
      }).then(function () {
        renderUi();
        return response;
      });
    });
  }

  function stopConversationRun(workspaceId, conversationId, options) {
    var opts = options || {};
    var wsId = String(workspaceId || "");
    var convId = String(conversationId || "");
    if (!wsId || !convId) {
      return Promise.resolve();
    }

    return apiPost("queue_stop", {
      workspace_id: wsId,
      conversation_id: convId
    }).then(function (response) {
      if (!response.success) {
        throw new Error(response.error || "Could not stop run");
      }

      if (state.busy && state.runningWorkspaceId === wsId && state.runningConversationId === convId) {
        setBusy(false);
      }
      setAwaitingApprovalState(wsId, convId, false);
      applyQueueStateFromResponse(wsId, convId, response);
      finalizeLatestRunningEvent(convId, "cancelled", "");

      return loadState()
        .catch(function () {
          return null;
        })
        .then(function () {
          if (state.activeWorkspaceId === wsId && state.activeConversationId === convId) {
            return loadConversation().catch(function () {
              return null;
            });
          }
          return null;
        })
        .then(function () {
          if (!opts.suppressNotice) {
            showTransientNotice("Run stopped");
          }
          renderUi();
        });
    });
  }

  function stopTerminalPolling() {
    if (terminalPollTimer) {
      clearInterval(terminalPollTimer);
      terminalPollTimer = null;
    }
    terminalPollBusy = false;
  }

  function appendTerminalDelta(deltaText) {
    var delta = String(deltaText || "");
    if (!delta) {
      return;
    }
    var next = String(state.terminalStreamText || "") + delta;
    if (next.length > 220000) {
      next = next.slice(next.length - 220000);
    }
    state.terminalStreamText = next;
  }

  function pollTerminalSessionOnce() {
    if (!state.terminalOpen || terminalPollBusy) {
      return Promise.resolve();
    }
    var workspaceId = String(state.activeWorkspaceId || "");
    var sessionId = String(state.terminalSessionId || "");
    if (!workspaceId || !sessionId) {
      return Promise.resolve();
    }
    terminalPollBusy = true;
    return apiGet("terminal_session_poll", {
      workspace_id: workspaceId,
      session_id: sessionId,
      offset: String(Number(state.terminalStreamOffset || 0))
    }, { timeoutMs: 12000 })
      .then(function (response) {
        if (!response || !response.success) {
          return;
        }
        if (response.session_changed) {
          state.terminalSessionId = "";
          state.terminalSessionWorkspaceId = "";
          stopTerminalPolling();
          return;
        }
        appendTerminalDelta(response.delta || "");
        state.terminalStreamOffset = Number(response.offset || state.terminalStreamOffset || 0);
        renderTerminal();
      })
      .catch(function () {
        return null;
      })
      .finally(function () {
        terminalPollBusy = false;
      });
  }

  function ensureTerminalSession() {
    if (!state.activeWorkspaceId) {
      return Promise.reject(new Error("Select a project first."));
    }
    if (
      state.terminalSessionId &&
      state.terminalSessionWorkspaceId &&
      state.terminalSessionWorkspaceId === state.activeWorkspaceId
    ) {
      return Promise.resolve(state.terminalSessionId);
    }
    stopTerminalPolling();
    state.terminalSessionId = "";
    state.terminalSessionWorkspaceId = "";
    state.terminalStreamText = "";
    state.terminalStreamOffset = 0;
    state.terminalInputBuffer = "";
    renderTerminal();

    if (terminalSessionStartPromise) {
      return terminalSessionStartPromise;
    }

    terminalSessionStartPromise = apiPost("terminal_session_start", {
      workspace_id: state.activeWorkspaceId
    }, { timeoutMs: 15000 }).then(function (response) {
      if (!response || !response.success) {
        throw new Error((response && response.error) || "Could not start terminal session");
      }
      state.terminalSessionId = String(response.session_id || "");
      state.terminalSessionWorkspaceId = state.activeWorkspaceId;
      state.terminalStreamText = String(response.delta || "");
      state.terminalStreamOffset = Number(response.offset || 0);
      renderTerminal();
      terminalPollTimer = setInterval(function () {
        pollTerminalSessionOnce();
      }, 220);
      return state.terminalSessionId;
    }).finally(function () {
      terminalSessionStartPromise = null;
    });

    return terminalSessionStartPromise;
  }

  function runCommandViaApi(commandText, actionName) {
    if (!state.activeWorkspaceId) {
      return Promise.reject(new Error("Select a project first."));
    }

    var trimmedCommand = trim(commandText);
    if (!trimmedCommand) {
      return Promise.reject(new Error("Command is required."));
    }

    state.terminalBusy = true;
    appendTerminalLine("$ " + trimmedCommand);

    return apiPost(actionName || "terminal_exec", {
      workspace_id: state.activeWorkspaceId,
      command: commandText,
      permission_mode: state.permissionMode
    }).then(function (response) {
      if (!response.success) {
        throw new Error(response.error || "Command failed");
      }

      var output = String(response.output || "");
      if (trim(output)) {
        appendTerminalLine(output);
      }
      appendTerminalLine("[exit " + Number(response.exit_code || 0) + "]");

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
          if (state.diffOpen) {
            return refreshDiff().catch(function () {
              return null;
            });
          }
          return null;
        })
        .then(function () {
          renderUi();
        });
    }).finally(function () {
      state.terminalBusy = false;
      renderTerminal();
    });
  }

  function showError(error) {
    var message = error && error.message ? error.message : String(error);
    var now = Date.now();
    if (state.lastErrorText === message && now - state.lastErrorAt < 1800) {
      return;
    }
    if (
      !state.initialLoadComplete &&
      !state.activeConversationId &&
      !state.terminalOpen &&
      isRetriableRequestError(error)
    ) {
      if (window && window.console && typeof window.console.warn === "function") {
        window.console.warn("Artificer startup retry:", message);
      }
      return;
    }
    state.lastErrorText = message;
    state.lastErrorAt = now;
    if (state.activeConversationId) {
      pushRunEvent(state.activeConversationId, {
        status: "error",
        error: message,
        finished_at: new Date().toISOString()
      });
    } else if (state.terminalOpen) {
      appendTerminalLine("Error: " + message);
    }
    renderUi();
  }

  function openCommitModal(defaultAction) {
    var gitState = activeGitState();
    state.commitModalDefault = defaultAction || "commit";
    el.commitBranchLabel.textContent = gitState.branch || "-";
    el.commitChangesLabel.innerHTML = gitDeltaMarkup(gitState.added, gitState.deleted);
    el.commitIncludeUnstaged.checked = true;
    el.commitMessage.value = "";
    el.commitNextStep.value = state.commitModalDefault === "commit-push" ? "commit-push" : "commit";
    openModal(el.commitModal);
  }

  function performOpenTarget(target) {
    if (!state.activeWorkspaceId) {
      return Promise.reject(new Error("Select a project first."));
    }
    if (target !== "finder" && target !== "terminal" && target !== "textmate") {
      target = "finder";
    }
    state.lastOpenTarget = target;
    storageSet("artificer.lastOpenTarget", target);
    renderUi();
    return apiPost("open_in", {
      workspace_id: state.activeWorkspaceId,
      target: target
    }).then(function (response) {
      if (!response.success) {
        throw new Error(response.error || "Open failed");
      }
      closeAllMenus();
      return response;
    });
  }

  function createRepoForActiveWorkspace() {
    if (!state.activeWorkspaceId) {
      return Promise.reject(new Error("Select a project first."));
    }
    return apiPost("git_init", { workspace_id: state.activeWorkspaceId })
      .then(function (response) {
        if (!response.success) {
          throw new Error(response.error || "git init failed");
        }
        appendTerminalLine(response.message || "Git repository created.");
        return refreshGitStatus();
      })
      .then(function () {
        return refreshBranches().catch(function () {
          return null;
        });
      })
      .then(function () {
        showTransientNotice("Repository created");
        renderUi();
      });
  }

  function performCommitAction(action) {
    if (!state.activeWorkspaceId) {
      return Promise.reject(new Error("Select a project first."));
    }
    if (action !== "commit" && action !== "push" && action !== "commit-push") {
      action = "commit";
    }
    state.lastCommitAction = action;
    storageSet("artificer.lastCommitAction", action);
    renderUi();

    var gitState = activeGitState();
    if (!gitState.is_repo) {
      if (!window.confirm("This project is not a git repo yet. Create one now?")) {
        return Promise.resolve();
      }
      return createRepoForActiveWorkspace().then(function () {
        return performCommitAction(action);
      });
    }

    if (action === "push") {
      return apiPost("git_push", { workspace_id: state.activeWorkspaceId })
        .then(function (response) {
          if (!response.success) {
            throw new Error(response.error || "Push failed");
          }
          appendTerminalLine(response.output || "Push complete.");
          return refreshGitStatus();
        })
        .then(function () {
          return refreshBranches().catch(function () {
            return null;
          });
        })
        .then(function () {
          closeAllMenus();
          renderUi();
        });
    }

    closeAllMenus();
    openCommitModal(action === "commit-push" ? "commit-push" : "commit");
    return Promise.resolve();
  }

  function loadAuthStatus() {
    if (el.gitStatus) {
      el.gitStatus.textContent = "Checking...";
    }
    if (el.sshKeyStatus) {
      el.sshKeyStatus.textContent = "Checking...";
    }

    return apiGet("git_auth_status", {}, { timeoutMs: 12000 }).then(function (response) {
      if (!response.success) {
        throw new Error(response.error || "Failed to load auth status");
      }

      if (el.gitStatus) {
        if (response.has_git) {
          el.gitStatus.textContent = "Installed";
        } else {
          el.gitStatus.textContent = "Not installed";
        }
      }

      if (response.ssh_pub_exists) {
        el.sshKeyStatus.textContent = "SSH key found";
        el.sshPubOutput.value = response.ssh_pub_key || "";
      } else {
        el.sshKeyStatus.textContent = "No SSH key";
        el.sshPubOutput.value = "";
      }

      if (el.selectedSshPath) {
        if (response.selected_ssh_pub_path) {
          el.selectedSshPath.value = response.selected_ssh_pub_path;
        } else {
          el.selectedSshPath.value = "";
          el.selectedSshPath.placeholder = "Using auto-detected SSH key.";
        }
      }
    }).catch(function (error) {
      if (el.gitStatus) {
        el.gitStatus.textContent = "Unavailable";
      }
      if (el.sshKeyStatus) {
        el.sshKeyStatus.textContent = "Unavailable";
      }
      if (el.sshPubOutput) {
        el.sshPubOutput.value = "";
      }
      if (el.selectedSshPath) {
        el.selectedSshPath.value = "";
        el.selectedSshPath.placeholder = "Could not load SSH key status.";
      }
      throw error;
    });
  }

  function loadLlmRuntimeSettings() {
    return apiGet("llm_runtime_settings_get", {}, { timeoutMs: 12000 }).then(function (response) {
      if (!response || !response.success) {
        throw new Error((response && response.error) || "Failed to load LLM runtime settings");
      }
      state.llmUseGpu = response.use_gpu !== false;
      storageSet("artificer.llmUseGpu", state.llmUseGpu ? "1" : "0");
      if (el.llmUseGpuToggle) {
        el.llmUseGpuToggle.checked = !!state.llmUseGpu;
      }
      return response;
    }).catch(function () {
      if (el.llmUseGpuToggle) {
        el.llmUseGpuToggle.checked = !!state.llmUseGpu;
      }
      return null;
    });
  }

  function saveLlmRuntimeSettings(useGpuEnabled) {
    var next = !!useGpuEnabled;
    return apiPost("llm_runtime_settings_set", {
      use_gpu: next ? "1" : "0"
    }, { timeoutMs: 12000 }).then(function (response) {
      if (!response || !response.success) {
        throw new Error((response && response.error) || "Failed to save LLM runtime settings");
      }
      state.llmUseGpu = response.use_gpu !== false;
      storageSet("artificer.llmUseGpu", state.llmUseGpu ? "1" : "0");
      if (el.llmUseGpuToggle) {
        el.llmUseGpuToggle.checked = !!state.llmUseGpu;
      }
      return response;
    });
  }

  function automationDaemonBool(value) {
    if (value === true || value === 1) {
      return true;
    }
    var text = trim(String(value == null ? "" : value)).toLowerCase();
    return text === "1" || text === "true" || text === "yes" || text === "on" || text === "enabled";
  }

  function normalizeAutomationDaemonStatus(response) {
    var source = response && typeof response === "object" ? response : {};
    var method = trim(String(source.method || "")).toLowerCase();
    if (!method) {
      method = "none";
    }
    return {
      supported: automationDaemonBool(source.supported),
      enabled: automationDaemonBool(source.enabled),
      active: automationDaemonBool(source.active),
      method: method,
      label: trim(String(source.label || "")),
      detail: trim(String(source.detail || ""))
    };
  }

  function applyAutomationDaemonStatus(statusValue) {
    var normalized = normalizeAutomationDaemonStatus(statusValue);
    state.automationDaemon.supported = normalized.supported;
    state.automationDaemon.enabled = normalized.enabled;
    state.automationDaemon.active = normalized.active;
    state.automationDaemon.method = normalized.method;
    state.automationDaemon.label = normalized.label;
    state.automationDaemon.detail = normalized.detail;
    if (!normalized.supported) {
      state.automationDaemon.enabled = false;
      state.automationDaemon.active = false;
    }
  }

  function automationDaemonMethodLabel(methodValue) {
    var method = trim(String(methodValue || "")).toLowerCase();
    if (method === "launchd") {
      return "launchd";
    }
    if (method === "systemd") {
      return "systemd user timer";
    }
    if (method === "cron") {
      return "crontab";
    }
    return method || "none";
  }

  function automationDaemonStatusText() {
    var daemon = state.automationDaemon || {};
    if (daemon.error) {
      return String(daemon.error);
    }
    if (!daemon.supported) {
      return "Background scheduler is not supported in this runtime.";
    }
    var enabledText = daemon.enabled ? "enabled" : "disabled";
    var activeText = daemon.active ? "active" : "inactive";
    var methodLabel = automationDaemonMethodLabel(daemon.method);
    var baseText = "Background scheduler is " + enabledText + " (" + activeText + ") via " + methodLabel + ".";
    if (daemon.detail) {
      baseText += " " + daemon.detail;
    }
    if (daemon.lastTickMessage) {
      baseText += " Last tick: " + daemon.lastTickMessage;
    }
    return baseText;
  }

  function renderAutomationDaemonSettings() {
    if (el.automationDaemonToggle) {
      el.automationDaemonToggle.checked = !!state.automationDaemon.enabled;
      el.automationDaemonToggle.disabled = !!state.automationDaemon.loading || !!state.automationDaemon.saving || !state.automationDaemon.supported;
    }
    if (el.automationDaemonStatus) {
      var statusText = automationDaemonStatusText();
      el.automationDaemonStatus.textContent = statusText;
      el.automationDaemonStatus.classList.toggle("error", !!state.automationDaemon.error);
      el.automationDaemonStatus.classList.toggle("status-pending-spinner", !!state.automationDaemon.loading || !!state.automationDaemon.saving || !!state.automationDaemon.ticking);
    }
    if (el.automationDaemonRefreshBtn) {
      var refreshBusy = !!state.automationDaemon.loading || !!state.automationDaemon.saving || !!state.automationDaemon.ticking;
      el.automationDaemonRefreshBtn.disabled = refreshBusy;
      el.automationDaemonRefreshBtn.textContent = state.automationDaemon.loading ? "Refreshing..." : "Refresh scheduler";
    }
    if (el.automationDaemonRunNowBtn) {
      var runBusy = !!state.automationDaemon.loading || !!state.automationDaemon.saving || !!state.automationDaemon.ticking;
      el.automationDaemonRunNowBtn.disabled = runBusy || !state.automationDaemon.supported;
      el.automationDaemonRunNowBtn.textContent = state.automationDaemon.ticking ? "Running tick..." : "Run tick now";
    }
  }

  function loadAutomationDaemonStatus(options) {
    var opts = options || {};
    if (!opts.silent) {
      state.automationDaemon.loading = true;
    }
    if (!opts.preserveError) {
      state.automationDaemon.error = "";
    }
    renderAutomationDaemonSettings();
    return apiGet("automation_daemon_status", {}, { timeoutMs: 12000 }).then(function (response) {
      if (!response || !response.success) {
        throw new Error((response && response.error) || "Failed to load scheduler status");
      }
      applyAutomationDaemonStatus(response);
      state.automationDaemon.error = "";
      return response;
    }).catch(function (error) {
      state.automationDaemon.error = error && error.message ? error.message : "Failed to load scheduler status";
      return null;
    }).finally(function () {
      state.automationDaemon.loading = false;
      renderAutomationDaemonSettings();
    });
  }

  function saveAutomationDaemonEnabled(enabled) {
    state.automationDaemon.saving = true;
    state.automationDaemon.error = "";
    renderAutomationDaemonSettings();
    return apiPost("automation_daemon_set", {
      enabled: enabled ? "1" : "0"
    }, { timeoutMs: 18000 }).then(function (response) {
      if (!response || !response.success) {
        throw new Error((response && response.error) || "Failed to update scheduler");
      }
      applyAutomationDaemonStatus(response);
      state.automationDaemon.error = "";
      return response;
    }).finally(function () {
      state.automationDaemon.saving = false;
      renderAutomationDaemonSettings();
    });
  }

  function runAutomationDaemonTickNow() {
    state.automationDaemon.ticking = true;
    state.automationDaemon.error = "";
    renderAutomationDaemonSettings();
    return apiPost("automation_daemon_tick", {}, { timeoutMs: 45000 }).then(function (response) {
      if (!response || !response.success) {
        throw new Error((response && response.error) || "Scheduler tick failed");
      }
      if (response.automations) {
        applyAutomationsState(response.automations);
      }
      if (Number(response.triggered || 0) > 0 || Number(response.processed || 0) > 0) {
        kickQueueWorker();
      }
      var message = trim(String(response.message || ""));
      if (!message) {
        message = "checked " + String(response.checked || "0") +
          ", triggered " + String(response.triggered || "0") +
          ", processed " + String(response.processed || "0");
      }
      state.automationDaemon.lastTickMessage = message;
      showTransientNotice("Automation tick complete");
      renderUi();
      return response;
    }).finally(function () {
      state.automationDaemon.ticking = false;
      renderAutomationDaemonSettings();
    });
  }

  function defaultSelfImproveRunOptions() {
    return {
      objective: "Improve Artificer's end-to-end self-improvement ability across web research, knowledge integration, planning, architecture, programming, verification, and local admin setup while keeping every improvement reversible and push-ready.",
      competition_enabled: true,
      challenger_model: "",
      sources: {
        papers: true,
        web: true,
        runtime: true,
        repo: true,
        platform: true
      }
    };
  }

  function normalizeSelfImproveRunOptions(value) {
    var defaults = defaultSelfImproveRunOptions();
    var data = value && typeof value === "object" ? value : {};
    var sourceData = data.sources && typeof data.sources === "object" ? data.sources : {};
    var objective = trim(String(data.objective || defaults.objective || ""));
    if (!objective) {
      objective = defaults.objective;
    }
    return {
      objective: objective,
      competition_enabled: data.competition_enabled !== false,
      challenger_model: trim(String(data.challenger_model || "")),
      sources: {
        papers: sourceData.papers !== false,
        web: sourceData.web !== false,
        runtime: sourceData.runtime !== false,
        repo: sourceData.repo !== false,
        platform: sourceData.platform !== false
      }
    };
  }

  function selfImproveRunOptionsPayload(optionsValue) {
    var options = normalizeSelfImproveRunOptions(optionsValue || state.selfImproveRunOptions);
    return {
      objective: trim(String(options.objective || "")),
      competition_enabled: options.competition_enabled ? "1" : "0",
      challenger_model: trim(String(options.challenger_model || "")),
      source_papers: options.sources.papers ? "1" : "0",
      source_web: options.sources.web ? "1" : "0",
      source_runtime: options.sources.runtime ? "1" : "0",
      source_repo: options.sources.repo ? "1" : "0",
      source_platform: options.sources.platform ? "1" : "0"
    };
  }

  function normalizeSelfImproveLastRun(value) {
    var data = value && typeof value === "object" ? value : {};
    return {
      summary: trim(String(data.summary || "")),
      generated_at: trim(String(data.generated_at || "")),
      model: trim(String(data.model || "")),
      papers: Array.isArray(data.papers) ? data.papers : [],
      web_signals: Array.isArray(data.web_signals) ? data.web_signals : [],
      objective: trim(String(data.objective || "")),
      competition_enabled: data.competition_enabled === true,
      winner_lane: trim(String(data.winner_lane || "")),
      winner_model: trim(String(data.winner_model || "")),
      lane_scores: data.lane_scores && typeof data.lane_scores === "object" ? data.lane_scores : {},
      evidence_counts: data.evidence_counts && typeof data.evidence_counts === "object" ? data.evidence_counts : {},
      run_options: data.run_options && typeof data.run_options === "object" ? data.run_options : {},
      lanes: Array.isArray(data.lanes) ? data.lanes : [],
      plugin_ids: Array.isArray(data.plugin_ids) ? data.plugin_ids : []
    };
  }

  function normalizeSelfImprovePlugins(value) {
    var list = Array.isArray(value) ? value : [];
    var clean = [];
    for (var i = 0; i < list.length; i += 1) {
      var item = list[i] || {};
      var pluginId = trim(String(item.id || ""));
      if (!pluginId) {
        continue;
      }
      clean.push({
        id: pluginId,
        name: trim(String(item.name || pluginId)),
        description: trim(String(item.description || "")),
        instructions: trim(String(item.instructions || "")),
        implementation_plan: trim(String(item.implementation_plan || "")),
        rationale: trim(String(item.rationale || "")),
        enabled: item.enabled !== false,
        generated_at: trim(String(item.generated_at || "")),
        source_model: trim(String(item.source_model || "")),
        source_lane: trim(String(item.source_lane || "")),
        risk_level: trim(String(item.risk_level || "medium")),
        paper_refs: Array.isArray(item.paper_refs) ? item.paper_refs : [],
        domain_tags: Array.isArray(item.domain_tags) ? item.domain_tags : [],
        evidence_refs: Array.isArray(item.evidence_refs) ? item.evidence_refs : [],
        admin_actions: Array.isArray(item.admin_actions) ? item.admin_actions : [],
        competition_score: Number(item.competition_score || 0),
        papers: Array.isArray(item.papers) ? item.papers : []
      });
    }
    return clean;
  }

  function renderSelfImproveSettings() {
    if (!el.selfImproveModelSelect || !el.selfImprovePluginsList || !el.selfImproveStatus || !el.selfImproveSummary) {
      return;
    }
    var runOptions = normalizeSelfImproveRunOptions(state.selfImproveRunOptions);
    state.selfImproveRunOptions = runOptions;

    var optionsHtml = "";
    if (!state.models.length) {
      optionsHtml = "<option value=''>No installed models</option>";
    } else {
      for (var i = 0; i < state.models.length; i += 1) {
        var modelName = trim(String(state.models[i] || ""));
        if (!modelName) {
          continue;
        }
        optionsHtml += "<option value='" + escAttr(modelName) + "'>" + escHtml(modelName) + "</option>";
      }
    }
    if (el.selfImproveModelSelect.innerHTML !== optionsHtml) {
      el.selfImproveModelSelect.innerHTML = optionsHtml;
    }
    var selectedModel = trim(String(state.selfImproveModel || ""));
    if (!selectedModel && state.models.length) {
      selectedModel = trim(String(state.models[0] || ""));
    }
    el.selfImproveModelSelect.value = selectedModel;
    if (el.selfImproveModelSelect.value !== selectedModel && el.selfImproveModelSelect.options.length) {
      el.selfImproveModelSelect.value = el.selfImproveModelSelect.options[0].value;
      selectedModel = el.selfImproveModelSelect.value;
    }
    state.selfImproveModel = selectedModel;

    if (el.selfImproveObjectiveInput && el.selfImproveObjectiveInput.value !== runOptions.objective) {
      el.selfImproveObjectiveInput.value = runOptions.objective;
    }
    if (el.selfImproveCompetitionToggle) {
      el.selfImproveCompetitionToggle.checked = !!runOptions.competition_enabled;
    }
    if (el.selfImproveSourcePapers) {
      el.selfImproveSourcePapers.checked = !!(runOptions.sources && runOptions.sources.papers);
    }
    if (el.selfImproveSourceWeb) {
      el.selfImproveSourceWeb.checked = !!(runOptions.sources && runOptions.sources.web);
    }
    if (el.selfImproveSourceRuntime) {
      el.selfImproveSourceRuntime.checked = !!(runOptions.sources && runOptions.sources.runtime);
    }
    if (el.selfImproveSourceRepo) {
      el.selfImproveSourceRepo.checked = !!(runOptions.sources && runOptions.sources.repo);
    }
    if (el.selfImproveSourcePlatform) {
      el.selfImproveSourcePlatform.checked = !!(runOptions.sources && runOptions.sources.platform);
    }

    if (el.selfImproveChallengerModelSelect) {
      var challengerHtml = "<option value=''>Auto challenger</option>";
      if (!state.models.length) {
        challengerHtml += "<option value=''>No installed models</option>";
      } else {
        for (var ci = 0; ci < state.models.length; ci += 1) {
          var challengerModelName = trim(String(state.models[ci] || ""));
          if (!challengerModelName) {
            continue;
          }
          challengerHtml += "<option value='" + escAttr(challengerModelName) + "'>" + escHtml(challengerModelName) + "</option>";
        }
      }
      if (el.selfImproveChallengerModelSelect.innerHTML !== challengerHtml) {
        el.selfImproveChallengerModelSelect.innerHTML = challengerHtml;
      }
      var challengerModel = trim(String(runOptions.challenger_model || ""));
      el.selfImproveChallengerModelSelect.value = challengerModel;
      if (el.selfImproveChallengerModelSelect.value !== challengerModel) {
        el.selfImproveChallengerModelSelect.value = "";
        challengerModel = "";
      }
      runOptions.challenger_model = challengerModel;
      el.selfImproveChallengerModelSelect.disabled = !runOptions.competition_enabled || !!state.selfImproveLoading || !state.models.length;
    }

    if (el.selfImproveRunBtn) {
      el.selfImproveRunBtn.disabled = !!state.selfImproveLoading || !state.selfImproveModel;
      if (state.selfImproveLoading) {
        el.selfImproveRunBtn.textContent = runOptions.competition_enabled ? "Running competition..." : "Self-improving...";
      } else {
        el.selfImproveRunBtn.textContent = runOptions.competition_enabled ? "Run self-improve match" : "Self-improve";
      }
    }

    if (state.selfImproveError) {
      el.selfImproveStatus.textContent = state.selfImproveError;
    } else if (state.selfImproveLoading) {
      el.selfImproveStatus.textContent = runOptions.competition_enabled
        ? "Collecting evidence and running competitive self-improvement lanes..."
        : "Collecting evidence and generating self-improvement plugins...";
    } else if (state.selfImproveLastRun && state.selfImproveLastRun.generated_at) {
      var generatedCount = Array.isArray(state.selfImproveLastRun.plugin_ids) ? state.selfImproveLastRun.plugin_ids.length : 0;
      var winnerText = "";
      if (state.selfImproveLastRun.winner_lane) {
        winnerText = " Winner: " + state.selfImproveLastRun.winner_lane;
        if (state.selfImproveLastRun.winner_model) {
          winnerText += " (" + state.selfImproveLastRun.winner_model + ")";
        }
      }
      if (generatedCount > 0) {
        el.selfImproveStatus.textContent = "Generated " + String(generatedCount) + " plugin" + (generatedCount === 1 ? "" : "s") + " on " + state.selfImproveLastRun.generated_at + (state.selfImproveLastRun.model ? (" using " + state.selfImproveLastRun.model) : "") + winnerText;
      } else {
        el.selfImproveStatus.textContent = "Last generated " + state.selfImproveLastRun.generated_at + (state.selfImproveLastRun.model ? (" using " + state.selfImproveLastRun.model) : "") + winnerText;
      }
    } else {
      el.selfImproveStatus.textContent = "";
    }

    var summaryParts = [];
    if (runOptions.objective) {
      summaryParts.push("Objective: " + runOptions.objective);
    }
    if (state.selfImproveLastRun && state.selfImproveLastRun.summary) {
      summaryParts.push(state.selfImproveLastRun.summary);
    }
    var papers = state.selfImproveLastRun && Array.isArray(state.selfImproveLastRun.papers) ? state.selfImproveLastRun.papers : [];
    var webSignals = state.selfImproveLastRun && Array.isArray(state.selfImproveLastRun.web_signals) ? state.selfImproveLastRun.web_signals : [];
    if (papers.length) {
      summaryParts.push("Research papers: " + String(papers.length));
    }
    if (webSignals.length) {
      summaryParts.push("Web signals: " + String(webSignals.length));
    }
    var evidenceCounts = state.selfImproveLastRun && state.selfImproveLastRun.evidence_counts && typeof state.selfImproveLastRun.evidence_counts === "object"
      ? state.selfImproveLastRun.evidence_counts
      : {};
    var failureCount = Number(evidenceCounts.failure_events || 0);
    var qualityCount = Number(evidenceCounts.quality_entries || 0);
    if (failureCount > 0 || qualityCount > 0) {
      summaryParts.push("Runtime traces: failures " + String(failureCount) + ", score entries " + String(qualityCount));
    }
    el.selfImproveSummary.textContent = summaryParts.join(" ");

    var html = "";
    var plugins = normalizeSelfImprovePlugins(state.selfImprovePlugins);
    if (!plugins.length) {
      html = "<p class='empty-state'>No self-improvement plugins generated yet.</p>";
    } else {
      for (var j = 0; j < plugins.length; j += 1) {
        var plugin = plugins[j];
        html += "<article class='mode-runtime-skill' data-plugin-id='" + escAttr(plugin.id) + "'>";
        html += "<div class='mode-runtime-mode-head'><strong>" + escHtml(plugin.name) + "</strong></div>";
        if (plugin.description) {
          html += "<p class='settings-hint'>" + escHtml(plugin.description) + "</p>";
        }
        if (plugin.instructions) {
          html += "<p class='settings-hint'><strong>Enabled behavior:</strong> " + escHtml(plugin.instructions) + "</p>";
        }
        if (plugin.implementation_plan) {
          html += "<p class='settings-hint'><strong>Plan:</strong> " + escHtml(plugin.implementation_plan) + "</p>";
        }
        if (plugin.rationale) {
          html += "<p class='settings-hint'><strong>Why:</strong> " + escHtml(plugin.rationale) + "</p>";
        }
        if (plugin.paper_refs && plugin.paper_refs.length) {
          html += "<p class='settings-hint'>papers: " + escHtml(plugin.paper_refs.join(" | ")) + "</p>";
        }
        if (plugin.domain_tags && plugin.domain_tags.length) {
          html += "<p class='settings-hint'><strong>Domains:</strong> " + escHtml(plugin.domain_tags.join(" | ")) + "</p>";
        }
        if (plugin.evidence_refs && plugin.evidence_refs.length) {
          html += "<p class='settings-hint'><strong>Evidence refs:</strong> " + escHtml(plugin.evidence_refs.join(" | ")) + "</p>";
        }
        if (plugin.admin_actions && plugin.admin_actions.length) {
          html += "<p class='settings-hint'><strong>Admin/setup:</strong> " + escHtml(plugin.admin_actions.join(" | ")) + "</p>";
        }
        var metadataBits = [];
        if (plugin.source_lane) {
          metadataBits.push("lane " + plugin.source_lane);
        }
        if (plugin.source_model) {
          metadataBits.push("model " + plugin.source_model);
        }
        if (plugin.risk_level) {
          metadataBits.push("risk " + plugin.risk_level);
        }
        if (isFinite(plugin.competition_score) && plugin.competition_score > 0) {
          metadataBits.push("score " + String(plugin.competition_score));
        }
        if (metadataBits.length) {
          html += "<p class='settings-hint'>" + escHtml(metadataBits.join(" | ")) + "</p>";
        }
        html += "<div class='mode-runtime-actions'>";
        html += "<label class='toggle-row' style='margin:0;'><input type='checkbox' data-action='self-improve-plugin-toggle' data-plugin-id='" + escAttr(plugin.id) + "' " + (plugin.enabled ? "checked" : "") + " /> Enabled</label>";
        html += "<button type='button' class='ghost' data-action='self-improve-plugin-delete' data-plugin-id='" + escAttr(plugin.id) + "'>Delete</button>";
        html += "</div>";
        html += "</article>";
      }
    }
    el.selfImprovePluginsList.innerHTML = html;
  }

  function loadSelfImproveSettings() {
    return apiGet("self_improve_settings_get", {}, { timeoutMs: 45000 }).then(function (response) {
      if (!response || !response.success) {
        throw new Error((response && response.error) || "Failed to load self-improvement settings");
      }
      state.selfImproveModel = trim(String(response.selected_model || ""));
      state.selfImproveRunOptions = normalizeSelfImproveRunOptions(response.run_options);
      state.selfImprovePlugins = normalizeSelfImprovePlugins(response.plugins);
      state.selfImproveLastRun = normalizeSelfImproveLastRun(response.last_run);
      state.selfImproveError = "";
      renderSelfImproveSettings();
      return response;
    }).catch(function (error) {
      state.selfImproveError = error && error.message ? error.message : "Failed to load self-improvement settings";
      renderSelfImproveSettings();
      return null;
    });
  }

  function runSelfImprove(modelName) {
    state.selfImproveLoading = true;
    state.selfImproveError = "";
    renderSelfImproveSettings();
    var runOptionsPayload = selfImproveRunOptionsPayload(state.selfImproveRunOptions);
    runOptionsPayload.model = trim(String(modelName || state.selfImproveModel || ""));
    return apiPost("self_improve_run", {
      model: runOptionsPayload.model,
      objective: runOptionsPayload.objective,
      competition_enabled: runOptionsPayload.competition_enabled,
      challenger_model: runOptionsPayload.challenger_model,
      source_papers: runOptionsPayload.source_papers,
      source_web: runOptionsPayload.source_web,
      source_runtime: runOptionsPayload.source_runtime,
      source_repo: runOptionsPayload.source_repo,
      source_platform: runOptionsPayload.source_platform
    }, { timeoutMs: 180000 })
      .then(function (response) {
        if (!response || !response.success) {
          throw new Error((response && response.error) || "Self-improve failed");
        }
        state.selfImproveModel = trim(String(response.selected_model || state.selfImproveModel || ""));
        state.selfImproveRunOptions = normalizeSelfImproveRunOptions(response.run_options || state.selfImproveRunOptions);
        state.selfImprovePlugins = normalizeSelfImprovePlugins(response.plugins);
        state.selfImproveLastRun = normalizeSelfImproveLastRun(response.last_run);
        showTransientNotice(state.selfImproveRunOptions.competition_enabled ? "Self-improvement match complete" : "Self-improvement plugins generated");
        return response;
      })
      .catch(function (error) {
        state.selfImproveError = error && error.message ? error.message : "Self-improve failed";
        throw error;
      })
      .finally(function () {
        state.selfImproveLoading = false;
        renderSelfImproveSettings();
      });
  }

  function saveSelfImproveRunOptions(optionsValue) {
    var options = normalizeSelfImproveRunOptions(optionsValue || state.selfImproveRunOptions);
    var payload = selfImproveRunOptionsPayload(options);
    return apiPost("self_improve_run_options_set", payload, { timeoutMs: 15000 }).then(function (response) {
      if (!response || !response.success) {
        throw new Error((response && response.error) || "Failed to save self-improvement options");
      }
      state.selfImproveRunOptions = normalizeSelfImproveRunOptions(response.run_options || options);
      state.selfImproveError = "";
      renderSelfImproveSettings();
      return response;
    });
  }

  function saveSelfImprovePluginEnabled(pluginId, enabled) {
    return apiPost("self_improve_plugin_set", {
      plugin_id: trim(String(pluginId || "")),
      enabled: enabled ? "1" : "0"
    }, { timeoutMs: 12000 }).then(function (response) {
      if (!response || !response.success) {
        throw new Error((response && response.error) || "Failed to update plugin");
      }
      return loadSelfImproveSettings();
    });
  }

  function deleteSelfImprovePlugin(pluginId) {
    return apiPost("self_improve_plugin_delete", {
      plugin_id: trim(String(pluginId || ""))
    }, { timeoutMs: 12000 }).then(function (response) {
      if (!response || !response.success) {
        throw new Error((response && response.error) || "Failed to delete plugin");
      }
      return loadSelfImproveSettings();
    });
  }

  function dictationBackendLabel(backendName) {
    var backend = trim(String(backendName || ""));
    if (!backend) {
      return "";
    }
    if (backend === "mlx-whisper") {
      return "MLX Whisper";
    }
    if (backend === "parakeet") {
      return "Parakeet";
    }
    if (backend === "ctranslate2-whisper") {
      return "CTranslate2 Whisper";
    }
    return backend;
  }

  function dictationInstallButtonLabel() {
    if (state.dictationInstalled) {
      return "Uninstall dictation";
    }
    return "Install dictation";
  }

  function dictationPreinstallSizeLabel() {
    var info = state.dictationInstallInfo || null;
    var infoBytes = dictationWholeNumber(info && info.download_size_bytes);
    if (infoBytes > 0) {
      return dictationGigabytesLabel(infoBytes, 2) + " GB";
    }
    return dictationGigabytesLabel(DICTATION_PREINSTALL_SIZE_BYTES, 2) + " GB";
  }

  function dictationInstallRunningButtonLabel(job) {
    var action = trim(String(job && job.action ? job.action : ""));
    if (action === "uninstall") {
      return "Uninstalling dictation";
    }
    var phase = trim(String(job && job.phase ? job.phase : ""));
    var backendLabel = dictationInstallBackendLabel(job);
    var pctText = dictationProgressPercentLabel(job && job.progress_pct, job);
    var sizeText = dictationDownloadAmountLabel(job);
    var isDownloadPhase = (phase === "downloading" || phase === "preparing" || phase === "fallback");
    var labelPrefix = isDownloadPhase ?
      "Downloading " + backendLabel + " " :
      "Installing " + backendLabel + " ";
    var label = labelPrefix + pctText + "%";
    if (sizeText && isDownloadPhase) {
      label += " (" + sizeText + ")";
    }
    return label;
  }

  function dictationInstallBackendLabel(job) {
    var label = trim(String(job && job.component_label ? job.component_label : ""));
    if (label) {
      return label;
    }
    var component = trim(String(job && job.component ? job.component : ""));
    if (component) {
      var mapped = dictationBackendLabel(component);
      if (mapped) {
        return mapped;
      }
    }
    return "dictation";
  }

  function dictationProgressPercentLabel(rawValue, job) {
    var fromBytes = dictationProgressFromBytes(job);
    if (fromBytes >= 0) {
      return fromBytes.toFixed(1);
    }
    var status = trim(String(job && job.status ? job.status : ""));
    var phase = trim(String(job && job.phase ? job.phase : ""));
    if (status === "done" || phase === "done") {
      return "100.0";
    }
    return "0.0";
  }

  function dictationProgressFromBytes(job) {
    var totalBytes = dictationWholeNumber(job && job.download_size_bytes);
    var downloadedBytes = dictationWholeNumber(job && job.downloaded_bytes);
    if (totalBytes <= 0 || downloadedBytes < 0) {
      return -1;
    }
    if (downloadedBytes > totalBytes) {
      downloadedBytes = totalBytes;
    }
    var pct = (downloadedBytes * 100) / totalBytes;
    if (!isFinite(pct) || pct < 0) {
      return 0;
    }
    if (pct > 100) {
      pct = 100;
    }
    return pct;
  }

  function dictationDownloadAmountLabel(job) {
    var totalBytes = dictationWholeNumber(job && job.download_size_bytes);
    if (totalBytes <= 0) {
      return "";
    }
    var downloadedBytes = dictationWholeNumber(job && job.downloaded_bytes);
    if (downloadedBytes < 0) {
      return "";
    }
    if (downloadedBytes > totalBytes) {
      downloadedBytes = totalBytes;
    }
    return dictationGigabytesLabel(downloadedBytes, 2) + " of " + dictationGigabytesLabel(totalBytes, 2) + " GB";
  }

  function dictationWholeNumber(rawValue) {
    var text = trim(String(rawValue == null ? "" : rawValue));
    if (!/^[0-9]+$/.test(text)) {
      return -1;
    }
    var parsed = Number(text);
    if (!isFinite(parsed) || parsed < 0) {
      return -1;
    }
    return Math.round(parsed);
  }

  function dictationGigabytesLabel(byteCount, decimals) {
    var bytes = Number(byteCount);
    if (!isFinite(bytes) || bytes < 0) {
      bytes = 0;
    }
    var places = Number(decimals);
    if (!isFinite(places) || places < 0) {
      places = 2;
    }
    if (places > 3) {
      places = 3;
    }
    return (bytes / 1000000000).toFixed(places);
  }

  function dictationShortcutChoices(kind) {
    return kind === "toggle" ? DICTATION_SHORTCUT_TOGGLE_OPTIONS : DICTATION_SHORTCUT_HOLD_OPTIONS;
  }

  function normalizeDictationShortcut(kind, value) {
    var raw = trim(String(value || "")).toLowerCase();
    var options = dictationShortcutChoices(kind);
    for (var i = 0; i < options.length; i += 1) {
      if (raw === String(options[i].value || "")) {
        return raw;
      }
    }
    return "none";
  }

  function dictationShortcutLabel(kind, value) {
    var normalized = normalizeDictationShortcut(kind, value);
    var options = dictationShortcutChoices(kind);
    for (var i = 0; i < options.length; i += 1) {
      if (normalized === String(options[i].value || "")) {
        return String(options[i].label || normalized);
      }
    }
    return "None";
  }

  function dictationShortcutOptionsHtml(kind, selected) {
    var normalized = normalizeDictationShortcut(kind, selected);
    var options = dictationShortcutChoices(kind);
    var html = "";
    for (var i = 0; i < options.length; i += 1) {
      var option = options[i] || {};
      var value = String(option.value || "none");
      var label = String(option.label || value);
      html += "<option value='" + escAttr(value) + "'" + (value === normalized ? " selected" : "") + ">" + escHtml(label) + "</option>";
    }
    return html;
  }

  function normalizeDictationLanguageOptions(rawOptions) {
    var normalized = [];
    var seen = {};
    var hasAuto = false;
    var source = Array.isArray(rawOptions) ? rawOptions : [];
    for (var i = 0; i < source.length; i += 1) {
      var raw = source[i];
      if (!raw || typeof raw !== "object") {
        continue;
      }
      var value = trim(String(raw.value || "")).toLowerCase();
      if (!/^[a-z0-9_-]+$/.test(value)) {
        continue;
      }
      if (seen[value]) {
        continue;
      }
      var label = trim(String(raw.label || ""));
      if (!label) {
        if (value === "auto") {
          label = "Auto-detect";
        } else {
          label = value.toUpperCase();
        }
      }
      seen[value] = true;
      if (value === "auto") {
        hasAuto = true;
      }
      normalized.push({ value: value, label: label });
    }
    if (!hasAuto) {
      normalized.unshift({ value: "auto", label: "Auto-detect" });
    }
    if (!normalized.length) {
      normalized = DICTATION_LANGUAGE_DEFAULT_OPTIONS.slice();
    }
    return normalized;
  }

  function normalizeDictationLanguageValue(value, options) {
    var normalizedValue = trim(String(value || "")).toLowerCase();
    if (!normalizedValue || normalizedValue === "none" || normalizedValue === "default" || normalizedValue === "detect") {
      normalizedValue = "auto";
    }
    var languageOptions = normalizeDictationLanguageOptions(options || state.dictationLanguages);
    for (var i = 0; i < languageOptions.length; i += 1) {
      if (normalizedValue === String(languageOptions[i].value || "")) {
        return normalizedValue;
      }
    }
    return "auto";
  }

  function dictationLanguageLabel(value) {
    var normalizedValue = normalizeDictationLanguageValue(value, state.dictationLanguages);
    var options = normalizeDictationLanguageOptions(state.dictationLanguages);
    for (var i = 0; i < options.length; i += 1) {
      if (normalizedValue === String(options[i].value || "")) {
        return String(options[i].label || normalizedValue);
      }
    }
    return "Auto-detect";
  }

  function dictationLanguageOptionsHtml(selected) {
    var options = normalizeDictationLanguageOptions(state.dictationLanguages);
    var normalizedSelected = normalizeDictationLanguageValue(selected, options);
    var html = "";
    for (var i = 0; i < options.length; i += 1) {
      var option = options[i] || {};
      var value = String(option.value || "");
      var label = String(option.label || value);
      html += "<option value='" + escAttr(value) + "'" + (value === normalizedSelected ? " selected" : "") + ">" + escHtml(label) + "</option>";
    }
    return html;
  }

  function dictationRequestedLanguageParam() {
    var normalized = normalizeDictationLanguageValue(state.dictationLanguage, state.dictationLanguages);
    if (normalized === "auto") {
      return "";
    }
    return normalized;
  }

  function clearDictationShortcutPressState() {
    var keys = Object.keys(dictationShortcutPressState);
    for (var i = 0; i < keys.length; i += 1) {
      var key = keys[i];
      var entry = dictationShortcutPressState[key];
      if (entry && entry.timer) {
        clearTimeout(entry.timer);
      }
      delete dictationShortcutPressState[key];
    }
  }

  function markDictationToggleTriggered(trigger) {
    var name = String(trigger || "");
    if (!name) {
      return;
    }
    dictationShortcutLastToggleAtByTrigger[name] = Date.now();
  }

  function dictationToggleTriggerHandledRecently(trigger, withinMs) {
    var name = String(trigger || "");
    if (!name) {
      return false;
    }
    var windowMs = Number(withinMs || 0);
    if (!isFinite(windowMs) || windowMs < 1) {
      windowMs = 1;
    }
    var lastAt = Number(dictationShortcutLastToggleAtByTrigger[name] || 0);
    return !!lastAt && (Date.now() - lastAt) <= windowMs;
  }

  function dictationShortcutKeyboardTrigger(event) {
    var code = String(event && event.code ? event.code : "");
    var key = String(event && event.key ? event.key : "").toLowerCase();
    var keyCompact = key.replace(/[\s_-]+/g, "");
    if ((code === "KeyM" || key === "m") && !!(event && event.ctrlKey) && !(event && event.metaKey)) {
      return "ctrl-m";
    }
    if (code === "AltLeft" || code === "AltRight" || key === "alt") {
      return "alt";
    }
    if (code === "MetaLeft" || code === "MetaRight" || key === "meta" || key === "command" || key === "os") {
      return "meta";
    }
    if (code === "ShiftLeft" || code === "ShiftRight" || key === "shift") {
      return "shift";
    }
    if (code === "ControlLeft" || code === "ControlRight" || key === "control" || key === "ctrl") {
      return "control";
    }
    if (code === "Space" || key === " ") {
      return "space";
    }
    if (code === "Backslash") {
      return "backslash";
    }
    if (code === "Semicolon") {
      return "semicolon";
    }
    if (code === "Quote") {
      return "quote";
    }
    if (code === "CapsLock" || key === "capslock" || keyCompact === "capslock") {
      return "capslock";
    }
    if (code === "BrowserBack" || keyCompact === "browserback") {
      return "mouse-button-4";
    }
    if (code === "BrowserForward" || keyCompact === "browserforward") {
      return "mouse-button-5";
    }
    if (keyCompact === "xbutton1" || keyCompact === "xf86back") {
      return "mouse-button-4";
    }
    if (keyCompact === "xbutton2" || keyCompact === "xf86forward") {
      return "mouse-button-5";
    }
    if (
      code === "F6" || code === "F7" || code === "F8" || code === "F9" || code === "F10" ||
      code === "F13" || code === "F14" || code === "F15" || code === "F16" || code === "F17" || code === "F18" || code === "F19"
    ) {
      return code.toLowerCase();
    }
    return "";
  }

  function dictationShortcutMouseTrigger(event) {
    var button = Number(event && event.button);
    var which = Number(event && event.which);
    var buttons = Number(event && event.buttons);
    var eventType = String(event && event.type ? event.type : "").toLowerCase();
    var isDownEvent = eventType.indexOf("down") >= 0 || eventType.indexOf("click") >= 0;
    var hasButton = isFinite(button) && button >= 0;
    // Prefer explicit side-button signals first.
    if ((hasButton && button === 3) || (!hasButton && which === 4)) {
      return "mouse-button-4";
    }
    if ((hasButton && button === 4) || (!hasButton && which === 5)) {
      return "mouse-button-5";
    }
    // Fallback for environments that do not expose side-button values in `button`.
    // Use bitwise checks (not equality) so combined button masks still map correctly.
    if (isDownEvent && isFinite(buttons)) {
      if ((buttons & 8) !== 0 && (buttons & 16) === 0) {
        return "mouse-button-4";
      }
      if ((buttons & 16) !== 0 && (buttons & 8) === 0) {
        return "mouse-button-5";
      }
      if ((buttons & 4) !== 0 && (buttons & 24) === 0) {
        return "mouse-wheel-click";
      }
    }
    if ((hasButton && button === 1) || (!hasButton && which === 2)) {
      return "mouse-wheel-click";
    }
    return "";
  }

  function loadDictationStatus(options) {
    var opts = options && typeof options === "object" ? options : {};
    var silent = !!opts.silent;
    state.dictationInstallInfoLoading = true;
    renderDictationInstallSettings();
    return Promise.all([
      apiGet("dictation_status", {}, { timeoutMs: 12000 }),
      apiGet("dictation_install_info", {}, { timeoutMs: 12000 }).catch(function () {
        return null;
      })
    ]).then(function (results) {
      var statusResponse = results[0] || null;
      var infoResponse = results[1] || null;
      if (!statusResponse || !statusResponse.success) {
        throw new Error((statusResponse && statusResponse.error) || "Could not load dictation status");
      }
      var backend = trim(String(statusResponse.backend || ""));
      var preferred = trim(String(statusResponse.preferred || ""));
      var installed = statusResponse.installed === true;
      var languageOptions = normalizeDictationLanguageOptions(statusResponse.languages);
      var selectedLanguage = normalizeDictationLanguageValue(statusResponse.language, languageOptions);
      var combined = statusResponse;
      if (infoResponse && infoResponse.success && infoResponse.download_size_bytes) {
        combined = Object.assign({}, statusResponse, {
          download_size_bytes: infoResponse.download_size_bytes
        });
      }
      state.dictationInstallInfo = combined;
      state.dictationInstalled = installed;
      state.dictationBackend = backend;
      state.dictationPreferredBackend = preferred;
      state.dictationLanguages = languageOptions;
      state.dictationLanguage = selectedLanguage;
      state.dictationInstallError = "";
      storageSet("artificer.dictationLanguage", selectedLanguage);
      if (!installed) {
        dictationPrepareReadyUntil = 0;
        stopDictationPrepareLoop();
      } else if (state.dictationPrewarmEnabled) {
        requestDictationPrepare({ silent: true }).catch(function () {
          return null;
        });
        if (dictationPrepareLoopShouldRun()) {
          startDictationPrepareLoop();
        }
      }
      if (!installed && !state.dictateBusy) {
        state.dictateRecording = false;
        state.dictateSessionId = "";
        setDictationPhase("idle");
      }
      return combined;
    }).catch(function (error) {
      state.dictationInstallInfo = null;
      state.dictationInstallError = error && error.message ? error.message : "Could not load dictation status";
      if (silent) {
        return null;
      }
      state.dictationInstalled = false;
      state.dictationBackend = "";
      state.dictationPreferredBackend = "";
      state.dictationLanguages = DICTATION_LANGUAGE_DEFAULT_OPTIONS.slice();
      state.dictationLanguage = normalizeDictationLanguageValue(storageGet("artificer.dictationLanguage", "auto"), state.dictationLanguages);
      state.dictateRecording = false;
      state.dictateSessionId = "";
      setDictationPhase("idle");
      throw error;
    }).finally(function () {
      state.dictationInstallInfoLoading = false;
      if (!state.dictationInstallBusy) {
        state.dictationInstallCancelling = false;
      }
      renderDictationInstallSettings();
    });
  }

  function dictationHotkeysEnabled() {
    return !!state.dictationInstalled;
  }

  function loadDictationPrewarmSetting() {
    return apiGet("dictation_prewarm_get", {}, { timeoutMs: 12000 }).then(function (response) {
      if (!response || !response.success) {
        throw new Error((response && response.error) || "Could not load dictation prewarm setting");
      }
      var enabled = response.enabled !== false;
      state.dictationPrewarmEnabled = !!enabled;
      storageSet("artificer.dictationPrewarmEnabled", enabled ? "1" : "0");
      if (!enabled) {
        dictationPrepareReadyUntil = 0;
        stopDictationPrepareLoop();
      }
      return enabled;
    }).catch(function () {
      state.dictationPrewarmEnabled = storageGet("artificer.dictationPrewarmEnabled", "1") !== "0";
      return state.dictationPrewarmEnabled;
    });
  }

  function loadDictationLanguageSetting() {
    return apiGet("dictation_language_get", {}, { timeoutMs: 12000 }).then(function (response) {
      if (!response || !response.success) {
        throw new Error((response && response.error) || "Could not load dictation language setting");
      }
      var languageOptions = normalizeDictationLanguageOptions(response.languages);
      var selectedLanguage = normalizeDictationLanguageValue(response.language, languageOptions);
      state.dictationLanguages = languageOptions;
      state.dictationLanguage = selectedLanguage;
      storageSet("artificer.dictationLanguage", selectedLanguage);
      return selectedLanguage;
    }).catch(function () {
      state.dictationLanguages = DICTATION_LANGUAGE_DEFAULT_OPTIONS.slice();
      state.dictationLanguage = normalizeDictationLanguageValue(storageGet("artificer.dictationLanguage", "auto"), state.dictationLanguages);
      return state.dictationLanguage;
    });
  }

  function saveDictationPrewarmSetting(enabled) {
    var next = !!enabled;
    state.dictationPrewarmEnabled = next;
    storageSet("artificer.dictationPrewarmEnabled", next ? "1" : "0");
    if (!next) {
      dictationPrepareReadyUntil = 0;
      stopDictationPrepareLoop();
      return apiPost("dictate_disarm", {}, { timeoutMs: 12000 }).catch(function () {
        return null;
      }).then(function () {
        return apiPost("dictation_prewarm_set", { enabled: "0" }, { timeoutMs: 12000 });
      }).then(function (response) {
        if (!response || !response.success) {
          throw new Error((response && response.error) || "Could not save dictation prewarm setting");
        }
        return false;
      });
    }
    return apiPost("dictation_prewarm_set", { enabled: "1" }, { timeoutMs: 12000 }).then(function (response) {
      if (!response || !response.success) {
        throw new Error((response && response.error) || "Could not save dictation prewarm setting");
      }
      return true;
    });
  }

  function dictationPrepareLoopShouldRun() {
    if (!state.dictationInstalled || !state.dictationPrewarmEnabled || state.dictateRecording || state.dictateBusy) {
      return false;
    }
    if (typeof document === "undefined") {
      return false;
    }
    if (document.hidden || document.visibilityState === "hidden") {
      return false;
    }
    return true;
  }

  function stopDictationPrepareLoop() {
    if (dictationPrepareLoopTimer) {
      clearInterval(dictationPrepareLoopTimer);
      dictationPrepareLoopTimer = null;
    }
  }

  function startDictationPrepareLoop() {
    if (dictationPrepareLoopTimer) {
      return;
    }
    dictationPrepareLoopTimer = setInterval(function () {
      if (!dictationPrepareLoopShouldRun()) {
        stopDictationPrepareLoop();
        return;
      }
      requestDictationPrepare({ silent: true }).catch(function () {
        return null;
      });
    }, 6000);
  }

  function requestDictationPrepare(options) {
    var opts = options && typeof options === "object" ? options : {};
    if (!state.dictationInstalled || !state.dictationPrewarmEnabled || state.dictateRecording || state.dictateBusy) {
      return Promise.resolve(false);
    }
    var now = Date.now();
    if (!opts.force && dictationPrepareReadyUntil && now < dictationPrepareReadyUntil) {
      return Promise.resolve(true);
    }
    if (dictationPreparePromise) {
      return dictationPreparePromise;
    }
    var prepareLanguage = dictationRequestedLanguageParam();
    var preparePayload = {};
    if (prepareLanguage) {
      preparePayload.language = prepareLanguage;
    }
    dictationPreparePromise = apiPost("dictate_prepare", preparePayload, { timeoutMs: 16000 }).then(function (response) {
      if (!response || !response.success) {
        throw new Error((response && response.error) || "Could not prepare dictation");
      }
      dictationPrepareReadyUntil = Date.now() + 18000;
      return true;
    }).catch(function (_error) {
      dictationPrepareReadyUntil = 0;
      return false;
    }).finally(function () {
      dictationPreparePromise = null;
    });
    return dictationPreparePromise;
  }

  function loadDictationShortcutPrefs() {
    var loadSeq = dictationShortcutPrefsLoadSeq + 1;
    dictationShortcutPrefsLoadSeq = loadSeq;
    var revisionAtStart = dictationShortcutPrefsRevision;
    return apiGet("dictation_shortcuts_get", {}, { timeoutMs: 12000 }).then(function (response) {
      if (!response || !response.success) {
        throw new Error((response && response.error) || "Could not load dictation shortcuts");
      }
      if (loadSeq !== dictationShortcutPrefsLoadSeq || revisionAtStart !== dictationShortcutPrefsRevision) {
        return null;
      }
      var holdValue = normalizeDictationShortcut("hold", response.hold);
      var toggleValue = normalizeDictationShortcut("toggle", response.toggle);
      state.dictationShortcutHold = holdValue;
      state.dictationShortcutToggle = toggleValue;
      storageSet("artificer.dictationShortcutHold", holdValue);
      storageSet("artificer.dictationShortcutToggle", toggleValue);
      clearDictationShortcutPressState();
      return { hold: holdValue, toggle: toggleValue };
    });
  }

  function saveDictationShortcutPrefs() {
    dictationShortcutPrefsRevision += 1;
    var holdValue = normalizeDictationShortcut("hold", state.dictationShortcutHold);
    var toggleValue = normalizeDictationShortcut("toggle", state.dictationShortcutToggle);
    return apiPost("dictation_shortcuts_set", {
      hold: holdValue,
      toggle: toggleValue
    }, { timeoutMs: 12000 }).then(function (response) {
      if (!response || !response.success) {
        throw new Error((response && response.error) || "Could not save dictation shortcuts");
      }
      var savedHold = normalizeDictationShortcut("hold", response.hold);
      var savedToggle = normalizeDictationShortcut("toggle", response.toggle);
      state.dictationShortcutHold = savedHold;
      state.dictationShortcutToggle = savedToggle;
      storageSet("artificer.dictationShortcutHold", savedHold);
      storageSet("artificer.dictationShortcutToggle", savedToggle);
      return true;
    });
  }

  function saveDictationShortcutChoice(kind, value) {
    var normalizedKind = kind === "toggle" ? "toggle" : "hold";
    var normalizedValue = normalizeDictationShortcut(normalizedKind, value);
    dictationShortcutPrefsRevision += 1;
    if (normalizedKind === "toggle") {
      state.dictationShortcutToggle = normalizedValue;
      storageSet("artificer.dictationShortcutToggle", normalizedValue);
    } else {
      state.dictationShortcutHold = normalizedValue;
      storageSet("artificer.dictationShortcutHold", normalizedValue);
    }
    if (
      state.dictateHotkeyHoldActive &&
      state.dictateHotkeyHoldTrigger &&
      state.dictateHotkeyHoldTrigger !== state.dictationShortcutHold
    ) {
      state.dictateHotkeyHoldIntent = false;
      stopDictationCapture({ fromHotkey: true, silentNoSpeech: true }).catch(function () {
        return null;
      });
      state.dictateHotkeyHoldActive = false;
      state.dictateHotkeyHoldTrigger = "";
    }
    clearDictationShortcutPressState();
    renderDictationInstallSettings();
    saveDictationShortcutPrefs().catch(function () {
      return null;
    });
  }

  function saveDictationLanguageChoice(value) {
    var normalized = normalizeDictationLanguageValue(value, state.dictationLanguages);
    state.dictationLanguage = normalized;
    storageSet("artificer.dictationLanguage", normalized);
    renderDictationInstallSettings();
    return apiPost("dictation_language_set", {
      language: normalized
    }, { timeoutMs: 12000 }).then(function (response) {
      if (!response || !response.success) {
        throw new Error((response && response.error) || "Could not save dictation language");
      }
      var languageOptions = normalizeDictationLanguageOptions(response.languages);
      var savedLanguage = normalizeDictationLanguageValue(response.language, languageOptions);
      state.dictationLanguages = languageOptions;
      state.dictationLanguage = savedLanguage;
      storageSet("artificer.dictationLanguage", savedLanguage);
      dictationPrepareReadyUntil = 0;
      if (state.dictationInstalled && state.dictationPrewarmEnabled && !state.dictateRecording && !state.dictateBusy) {
        return requestDictationPrepare({ silent: true, force: true }).catch(function () {
          return false;
        }).then(function () {
          return true;
        });
      }
      return true;
    });
  }

  function renderDictationShortcutSettings() {
    if (!el.dictationShortcutRow || !el.dictationHoldShortcut || !el.dictationToggleShortcut) {
      return;
    }
    var showRow = !!state.dictationInstalled;
    el.dictationShortcutRow.classList.toggle("hidden", !showRow);
    if (!showRow) {
      return;
    }
    var holdNormalized = normalizeDictationShortcut("hold", state.dictationShortcutHold);
    var toggleNormalized = normalizeDictationShortcut("toggle", state.dictationShortcutToggle);
    state.dictationShortcutHold = holdNormalized;
    state.dictationShortcutToggle = toggleNormalized;
    var holdHtml = dictationShortcutOptionsHtml("hold", holdNormalized);
    if (el.dictationHoldShortcut.innerHTML !== holdHtml) {
      el.dictationHoldShortcut.innerHTML = holdHtml;
    } else if (String(el.dictationHoldShortcut.value || "") !== holdNormalized) {
      el.dictationHoldShortcut.value = holdNormalized;
    }
    var toggleHtml = dictationShortcutOptionsHtml("toggle", toggleNormalized);
    if (el.dictationToggleShortcut.innerHTML !== toggleHtml) {
      el.dictationToggleShortcut.innerHTML = toggleHtml;
    } else if (String(el.dictationToggleShortcut.value || "") !== toggleNormalized) {
      el.dictationToggleShortcut.value = toggleNormalized;
    }
    var holdLabel = dictationShortcutLabel("hold", holdNormalized);
    var toggleLabel = dictationShortcutLabel("toggle", toggleNormalized);
    el.dictationHoldShortcut.setAttribute("aria-label", "Hold-to-Talk (Press): " + holdLabel);
    el.dictationToggleShortcut.setAttribute("aria-label", "Toggle: " + toggleLabel);
  }

  function renderDictationLanguageSettings() {
    if (!el.dictationLanguageRow || !el.dictationLanguageSelect) {
      return;
    }
    var showRow = !!state.dictationInstalled;
    el.dictationLanguageRow.classList.toggle("hidden", !showRow);
    if (!showRow) {
      return;
    }
    var languageOptions = normalizeDictationLanguageOptions(state.dictationLanguages);
    var selectedLanguage = normalizeDictationLanguageValue(state.dictationLanguage, languageOptions);
    state.dictationLanguages = languageOptions;
    state.dictationLanguage = selectedLanguage;
    var languageHtml = dictationLanguageOptionsHtml(selectedLanguage);
    if (el.dictationLanguageSelect.innerHTML !== languageHtml) {
      el.dictationLanguageSelect.innerHTML = languageHtml;
    } else if (String(el.dictationLanguageSelect.value || "") !== selectedLanguage) {
      el.dictationLanguageSelect.value = selectedLanguage;
    }
    el.dictationLanguageSelect.disabled = !state.dictationInstalled || state.dictationInstallBusy || state.dictateRecording || state.dictateBusy;
    el.dictationLanguageSelect.setAttribute("aria-label", "Dictation language: " + dictationLanguageLabel(selectedLanguage));
  }

  function renderDictationInstallSettings() {
    if (!el.installDictationBtn) {
      renderDictationShortcutSettings();
      renderDictationLanguageSettings();
      return;
    }

    var job = state.dictationInstallJob || null;
    var busy = !!state.dictationInstallBusy;
    var status = String(job && job.status ? job.status : "");
    var action = trim(String(job && job.action ? job.action : ""));
    var showRunning = busy || status === "running";
    var runningInstall = showRunning && action !== "uninstall";
    var showChecking = !showRunning && (!state.dictationInstallReady || state.dictationInstallInfoLoading);
    var showPending = showChecking || !!state.dictationInstallCancelling;
    var buttonLabel = dictationInstallButtonLabel();
    if (state.dictationInstallCancelling) {
      buttonLabel = "Cancelling...";
    } else if (runningInstall) {
      var phase = trim(String(job && job.phase ? job.phase : ""));
      if (!phase) {
        phase = "downloading";
      }
      if (phase === "downloading" || phase === "preparing" || phase === "fallback" || phase === "running") {
        buttonLabel = "Cancel download";
      } else {
        buttonLabel = "Cancel install";
      }
    } else if (showRunning) {
      buttonLabel = dictationInstallRunningButtonLabel(job);
    } else if (showChecking) {
      buttonLabel = "Checking...";
    }

    el.installDictationBtn.textContent = buttonLabel;
    el.installDictationBtn.disabled =
      !state.dictationInstallReady ||
      state.dictationInstallInfoLoading ||
      state.dictationInstallCancelling ||
      (busy && !runningInstall);
    el.installDictationBtn.classList.toggle("ui-pending-spinner", showPending);

    if (el.dictationInstallStatus) {
      var statusText = trim(String(state.dictationInstallError || ""));
      var isError = !!statusText;
      var statusPending = false;
      if (!statusText && state.dictationInstallCancelling) {
        statusText = "Cancelling dictation download...";
        statusPending = true;
      }
      if (!statusText && showRunning) {
        if (runningInstall) {
          statusText = dictationInstallRunningButtonLabel(job);
          statusPending = true;
        } else if (action === "uninstall") {
          statusText = "Uninstalling dictation";
          statusPending = true;
        }
      }
      if (!statusText && state.dictationInstalled) {
        var installedLabel = dictationBackendLabel(state.dictationBackend || "");
        var installedSizeLabel = dictationPreinstallSizeLabel();
        if (installedLabel) {
          if (installedSizeLabel) {
            statusText = "Installed backend: " + installedLabel + " (" + installedSizeLabel + ").";
          } else {
            statusText = "Installed backend: " + installedLabel + ".";
          }
        } else {
          if (installedSizeLabel) {
            statusText = "Dictation is installed (" + installedSizeLabel + ").";
          } else {
            statusText = "Dictation is installed.";
          }
        }
      } else if (!statusText && !state.dictationInstalled && !showChecking) {
        statusText = dictationPreinstallSizeLabel();
      }
      if (statusText) {
        el.dictationInstallStatus.textContent = statusText;
        el.dictationInstallStatus.classList.remove("hidden");
      } else {
        el.dictationInstallStatus.textContent = "";
        el.dictationInstallStatus.classList.add("hidden");
      }
      el.dictationInstallStatus.classList.toggle("status-pending-spinner", statusPending);
      if (isError) {
        el.dictationInstallStatus.classList.add("error");
      } else {
        el.dictationInstallStatus.classList.remove("error");
      }
    }
    if (el.dictationPrewarmRow) {
      var showPrewarm = true;
      el.dictationPrewarmRow.classList.toggle("hidden", !showPrewarm);
      if (el.dictationPrewarmHint) {
        el.dictationPrewarmHint.classList.toggle("hidden", !showPrewarm);
      }
      if (el.dictationPrewarmToggle) {
        el.dictationPrewarmToggle.checked = !!state.dictationPrewarmEnabled;
        el.dictationPrewarmToggle.disabled = !state.dictationInstalled || state.dictationInstallBusy || state.dictateRecording || state.dictateBusy;
      }
    }
    renderDictationShortcutSettings();
    renderDictationLanguageSettings();
  }

  function stopDictationInstallPolling() {
    dictationInstallPollSession += 1;
    if (dictationInstallPollTimer) {
      clearInterval(dictationInstallPollTimer);
      dictationInstallPollTimer = null;
    }
  }

  function pollDictationInstallStatus(jobId, pollSessionId) {
    var id = trim(String(jobId || ""));
    if (!id) {
      return Promise.resolve(null);
    }
    return apiGet("dictation_install_status", { job_id: id }, { timeoutMs: 12000 }).then(function (response) {
      if (typeof pollSessionId === "number" && pollSessionId !== dictationInstallPollSession) {
        return null;
      }
      if (!response || !response.success || !response.job) {
        throw new Error((response && response.error) || "Could not load dictation install status");
      }
      var responseJobId = trim(String(response.job.id || ""));
      var cancelJobId = trim(String(state.dictationInstallCancelJobId || ""));
      var responseStatus = String(response.job.status || "");
      if (cancelJobId && responseJobId === cancelJobId && responseStatus === "running" && state.dictationInstallCancelling) {
        var nowMs = Date.now();
        var startedAtMs = Number(state.dictationInstallCancelRequestedAt || 0);
        if (!isFinite(startedAtMs) || startedAtMs <= 0) {
          startedAtMs = nowMs;
          state.dictationInstallCancelRequestedAt = startedAtMs;
        }
        var elapsedMs = nowMs - startedAtMs;
        if (elapsedMs >= 15000 && Number(state.dictationInstallCancelAttempts || 0) < 2) {
          state.dictationInstallCancelAttempts = 2;
          apiPost("dictation_install_cancel", { job_id: cancelJobId }, { timeoutMs: 12000 }).catch(function () {
            return null;
          });
        }
        if (elapsedMs < 45000) {
          return null;
        }
        state.dictationInstallCancelling = false;
        state.dictationInstallPendingCancel = false;
        state.dictationInstallCancelJobId = "";
        state.dictationInstallCancelRequestedAt = 0;
        state.dictationInstallCancelAttempts = 0;
        state.dictationInstallError = "";
        showTransientNotice("Cancel timed out. Download is still running.");
      }
      var previousJob = state.dictationInstallJob || null;
      var previousAction = trim(String(previousJob && previousJob.action ? previousJob.action : ""));
      state.dictationInstallJob = response.job;
      if (!state.dictationInstallJob.action && previousAction) {
        state.dictationInstallJob.action = previousAction;
      }
      if (!state.dictationInstallJob.action) {
        state.dictationInstallJob.action = "install";
      }
      var status = String(response.job.status || "");
      if (status === "done") {
        stopDictationInstallPolling();
        state.dictationInstallBusy = false;
        state.dictationInstallCancelling = false;
        state.dictationInstallPendingCancel = false;
        if (cancelJobId && responseJobId === cancelJobId) {
          state.dictationInstallCancelJobId = "";
        }
        state.dictationInstallCancelRequestedAt = 0;
        state.dictationInstallCancelAttempts = 0;
        var installedBackend = trim(String(response.job.installed || response.job.component || response.job.backend || ""));
        state.dictationInstalled = true;
        state.dictationBackend = installedBackend;
        state.dictationInstallJob = null;
        state.dictationInstallError = "";
        return loadDictationStatus().then(function (statusResponse) {
          if (!state.dictationInstalled) {
            throw new Error("Dictation install did not complete.");
          }
          var expectedBackend = trim(String(response.job.installed || response.job.component || installedBackend));
          var activeBackend = trim(String((statusResponse && statusResponse.backend) || state.dictationBackend || installedBackend));
          if (expectedBackend && activeBackend && activeBackend !== expectedBackend && !response.job.fallback) {
            throw new Error("Dictation install finished, but " + dictationBackendLabel(expectedBackend) + " is not active.");
          }
          var alreadyInstalled = String(response.job.log || "").toLowerCase().indexOf("already installed") >= 0;
          var backendLabel = dictationBackendLabel(activeBackend);
          if (alreadyInstalled && backendLabel) {
            showTransientNotice("Dictation already installed (" + backendLabel + ")");
          } else if (alreadyInstalled) {
            showTransientNotice("Dictation already installed");
          } else if (response.job.fallback && backendLabel) {
            showTransientNotice("Dictation installed (" + backendLabel + " fallback)");
          } else if (backendLabel) {
            showTransientNotice("Dictation installed (" + backendLabel + ")");
          } else {
            showTransientNotice("Dictation installed");
          }
          renderUi();
          return response.job;
        });
      }
      if (status === "failed") {
        stopDictationInstallPolling();
        state.dictationInstallBusy = false;
        state.dictationInstallCancelling = false;
        state.dictationInstallPendingCancel = false;
        if (cancelJobId && responseJobId === cancelJobId) {
          state.dictationInstallCancelJobId = "";
        }
        state.dictationInstallCancelRequestedAt = 0;
        state.dictationInstallCancelAttempts = 0;
        state.dictationInstallJob = null;
        renderUi();
        var logText = trim(String(response.job.log || ""));
        var tailLine = "";
        if (logText) {
          var logLines = logText.split("\n");
          for (var i = logLines.length - 1; i >= 0; i -= 1) {
            var candidate = trim(logLines[i] || "");
            if (candidate) {
              tailLine = candidate;
              break;
            }
          }
        }
        state.dictationInstallError = tailLine || "Dictation install failed";
        showTransientNotice(state.dictationInstallError);
        throw new Error(state.dictationInstallError);
      }
      if (status === "cancelled") {
        stopDictationInstallPolling();
        state.dictationInstallBusy = false;
        state.dictationInstallCancelling = false;
        state.dictationInstallPendingCancel = false;
        if (cancelJobId && responseJobId === cancelJobId) {
          state.dictationInstallCancelJobId = "";
        }
        state.dictationInstallCancelRequestedAt = 0;
        state.dictationInstallCancelAttempts = 0;
        state.dictationInstallJob = null;
        state.dictationInstallError = "";
        showTransientNotice("Dictation install cancelled");
        renderUi();
        return response.job;
      }
      renderDictationInstallSettings();
      return response.job;
    });
  }

  function recoverDictationInstallAfterCancel(jobId) {
    var id = trim(String(jobId || ""));
    if (!id) {
      return Promise.resolve(null);
    }
    state.dictationInstallBusy = true;
    state.dictationInstallCancelling = true;
    state.dictationInstallPendingCancel = false;
    state.dictationInstallError = "";
    if (!state.dictationInstallCancelJobId) {
      state.dictationInstallCancelJobId = id;
    }
    if (!state.dictationInstallCancelRequestedAt) {
      state.dictationInstallCancelRequestedAt = Date.now();
    }
    state.dictationInstallCancelAttempts = Math.max(1, Number(state.dictationInstallCancelAttempts || 0));
    startDictationInstallPolling(id);
    renderUi();
    return Promise.resolve(null);
  }

  function startDictationInstallPolling(jobId) {
    var id = trim(String(jobId || ""));
    if (!id) {
      return;
    }
    stopDictationInstallPolling();
    var sessionId = dictationInstallPollSession;
    dictationInstallPollTimer = setInterval(function () {
      pollDictationInstallStatus(id, sessionId).catch(function (error) {
        stopDictationInstallPolling();
        state.dictationInstallBusy = false;
        state.dictationInstallCancelling = false;
        state.dictationInstallError = error && error.message ? error.message : "Dictation install failed";
        showTransientNotice(state.dictationInstallError);
        renderUi();
        showError(error);
      });
    }, 1200);
  }

  function installDictationSoftware() {
    if (!state.dictationInstallReady) {
      return Promise.resolve(null);
    }
    if (state.dictationInstallBusy || state.dictationInstallCancelling) {
      return Promise.resolve(null);
    }

    state.dictationInstallBusy = true;
    state.dictationInstallCancelling = false;
    state.dictationInstallPendingCancel = false;
    state.dictationInstallCancelJobId = "";
    state.dictationInstallCancelRequestedAt = 0;
    state.dictationInstallCancelAttempts = 0;
    state.dictationInstallError = "";
    state.dictationInstallJob = {
      status: "running",
      action: "install",
      phase: "downloading",
      progress_pct: "0.0"
    };
    renderUi();

    return apiPost("dictation_install_start", {}, { timeoutMs: 30000 }).then(function (response) {
      if (!response || !response.success || !response.job || !response.job.id) {
        throw new Error((response && response.error) || "Dictation install failed to start");
      }
      state.dictationInstallJob = response.job;
      state.dictationInstallJob.action = "install";
      if (state.dictationInstallPendingCancel) {
        return cancelDictationInstall();
      }
      startDictationInstallPolling(String(response.job.id || ""));
      renderUi();
      return pollDictationInstallStatus(String(response.job.id || ""), dictationInstallPollSession).catch(function (error) {
        stopDictationInstallPolling();
        state.dictationInstallBusy = false;
        state.dictationInstallCancelling = false;
        renderUi();
        throw error;
      });
    }).catch(function (error) {
      stopDictationInstallPolling();
      state.dictationInstallBusy = false;
      state.dictationInstallCancelling = false;
      state.dictationInstallPendingCancel = false;
      state.dictationInstallCancelJobId = "";
      state.dictationInstallCancelRequestedAt = 0;
      state.dictationInstallCancelAttempts = 0;
      state.dictationInstallJob = null;
      state.dictationInstallError = error && error.message ? error.message : "Dictation install failed";
      showTransientNotice(state.dictationInstallError);
      renderUi();
      throw error;
    });
  }

  function cancelDictationInstall() {
    var job = state.dictationInstallJob || null;
    var action = trim(String(job && job.action ? job.action : ""));
    var status = trim(String(job && job.status ? job.status : ""));
    var jobId = trim(String(job && job.id ? job.id : ""));
    if (!state.dictationInstallBusy && !state.dictationInstallPendingCancel && !jobId) {
      return Promise.resolve(null);
    }
    if (state.dictationInstallCancelling && jobId && trim(String(state.dictationInstallCancelJobId || "")) === jobId) {
      return Promise.resolve(null);
    }
    if (action === "uninstall" || (status && status !== "running")) {
      return Promise.resolve(null);
    }
    state.dictationInstallCancelling = true;
    stopDictationInstallPolling();
    state.dictationInstallBusy = true;
    state.dictationInstallError = "";
    if (!state.dictationInstallJob || !state.dictationInstallJob.action) {
      state.dictationInstallJob = {
        status: "running",
        action: "install",
        phase: "downloading",
        progress_pct: "0.0"
      };
    }
    renderUi();

    if (!jobId) {
      state.dictationInstallPendingCancel = true;
      state.dictationInstallCancelling = true;
      state.dictationInstallBusy = true;
      state.dictationInstallError = "";
      state.dictationInstallCancelRequestedAt = 0;
      state.dictationInstallCancelAttempts = 0;
      renderUi();
      return Promise.resolve(null);
    }

    state.dictationInstallPendingCancel = false;
    state.dictationInstallCancelJobId = jobId;
    state.dictationInstallCancelRequestedAt = Date.now();
    state.dictationInstallCancelAttempts = Math.max(1, Number(state.dictationInstallCancelAttempts || 0));
    return apiPost("dictation_install_cancel", { job_id: jobId }, { timeoutMs: 12000 }).then(function (response) {
      if (!response || !response.success) {
        throw new Error((response && response.error) || "Could not cancel dictation install");
      }
      state.dictationInstallBusy = false;
      state.dictationInstallCancelling = false;
      state.dictationInstallPendingCancel = false;
      if (state.dictationInstallCancelJobId === jobId) {
        state.dictationInstallCancelJobId = "";
      }
      state.dictationInstallCancelRequestedAt = 0;
      state.dictationInstallCancelAttempts = 0;
      state.dictationInstallError = "";
      state.dictationInstallJob = null;
      renderUi();
      showTransientNotice("Dictation install cancelled");
      return response;
    }).catch(function (error) {
      var message = error && error.message ? error.message : "";
      state.dictationInstallPendingCancel = false;
      state.dictationInstallError = "";
      state.dictationInstallCancelAttempts = Math.max(1, Number(state.dictationInstallCancelAttempts || 0));
      if (/timed out/i.test(message)) {
        showTransientNotice("Cancel requested. Checking status...");
      } else {
        showTransientNotice("Cancel request sent");
      }
      return recoverDictationInstallAfterCancel(jobId);
    });
  }

  function uninstallDictationSoftware() {
    if (!state.dictationInstallReady) {
      return Promise.resolve(null);
    }
    if (state.dictationInstallBusy) {
      return Promise.resolve(null);
    }

    state.dictationInstallBusy = true;
    state.dictationInstallCancelling = false;
    state.dictationInstallError = "";
    state.dictationInstallJob = {
      status: "running",
      action: "uninstall",
      progress_pct: ""
    };
    renderUi();

    return apiPost("dictation_uninstall", {}, { timeoutMs: 12000 }).then(function (response) {
      if (!response || !response.success) {
        throw new Error((response && response.error) || "Dictation uninstall failed");
      }
      state.dictationInstallBusy = false;
      state.dictationInstallCancelling = false;
      state.dictationInstallJob = null;
      state.dictationInstalled = false;
      state.dictationBackend = "";
      state.dictationPreferredBackend = "";
      state.dictationInstallError = "";
      renderUi();
      showTransientNotice("Dictation uninstalled");
      return loadDictationStatus({ silent: true }).then(function () {
        renderUi();
        return response;
      });
    }).catch(function (error) {
      state.dictationInstallBusy = false;
      state.dictationInstallCancelling = false;
      state.dictationInstallJob = null;
      state.dictationInstallError = error && error.message ? error.message : "Dictation uninstall failed";
      showTransientNotice(state.dictationInstallError);
      renderUi();
      return loadDictationStatus({ silent: true }).then(function () {
        renderUi();
        throw error;
      });
    });
  }

  function toggleDictationSoftware() {
    if (state.dictationInstallBusy) {
      return cancelDictationInstall();
    }
    if (state.dictationInstalled) {
      return uninstallDictationSoftware();
    }
    return installDictationSoftware();
  }

  function loadModeRuntimeState() {
    state.modeRuntimeLoading = true;
    return apiGet("mode_runtime_state", {}, { timeoutMs: 12000 })
      .then(function (response) {
        if (!response || !response.success) {
          throw new Error((response && response.error) || "Failed to load mode runtime state");
        }
        state.modeRuntime = normalizeModeRuntime(response.mode_runtime);
        reconcileAssistantModeId();
        state.modeRuntimeError = "";
        return state.modeRuntime;
      })
      .catch(function (error) {
        state.modeRuntimeError = error && error.message ? error.message : "Mode runtime unavailable";
        return null;
      })
      .finally(function () {
        state.modeRuntimeLoading = false;
        renderModeRuntimeSettings();
      });
  }

  function modeRuntimeUpdate(modeId, patch) {
    var id = trim(String(modeId || ""));
    if (!id) {
      return Promise.resolve(null);
    }
    var payload = {
      mode_id: id
    };
    var source = patch && typeof patch === "object" ? patch : {};
    if (typeof source.enabled !== "undefined") {
      payload.enabled = source.enabled ? "1" : "0";
    }
    if (typeof source.priority !== "undefined") {
      payload.priority = String(source.priority);
    }
    if (typeof source.cadence_sec !== "undefined") {
      payload.cadence_sec = String(source.cadence_sec);
    }
    if (typeof source.interrupt_rights !== "undefined") {
      payload.interrupt_rights = source.interrupt_rights ? "1" : "0";
    }
    if (typeof source.allow_queue_injection !== "undefined") {
      payload.allow_queue_injection = source.allow_queue_injection ? "1" : "0";
    }
    if (typeof source.goal_state !== "undefined") {
      payload.goal_state = String(source.goal_state || "");
    }
    if (typeof source.subscriptions !== "undefined") {
      payload.subscriptions = String(source.subscriptions || "");
    }

    state.modeRuntimeLoading = true;
    renderModeRuntimeSettings();
    return apiPost("mode_runtime_update", payload)
      .then(function (response) {
        if (!response || !response.success) {
          throw new Error((response && response.error) || "Could not update mode runtime");
        }
        state.modeRuntime = normalizeModeRuntime(response.mode_runtime);
        reconcileAssistantModeId();
        state.modeRuntimeError = "";
        return response;
      })
      .catch(function (error) {
        state.modeRuntimeError = error && error.message ? error.message : "Could not update mode runtime";
        throw error;
      })
      .finally(function () {
        state.modeRuntimeLoading = false;
        renderModeRuntimeSettings();
      });
  }

  function modeRuntimeTickNow() {
    state.modeRuntimeLoading = true;
    renderModeRuntimeSettings();
    return apiPost("mode_runtime_tick", {
      workspace_id: state.activeWorkspaceId || "",
      conversation_id: state.activeConversationId || ""
    })
      .then(function (response) {
        if (!response || !response.success) {
          throw new Error((response && response.error) || "Mode runtime tick failed");
        }
        state.modeRuntime = normalizeModeRuntime(response.mode_runtime);
        reconcileAssistantModeId();
        state.modeRuntimeError = "";
        return response;
      })
      .catch(function (error) {
        state.modeRuntimeError = error && error.message ? error.message : "Mode runtime tick failed";
        throw error;
      })
      .finally(function () {
        state.modeRuntimeLoading = false;
        renderModeRuntimeSettings();
      });
  }

  function defaultModeRuntimeTaxonomyQueryFilters() {
    return {
      category: "",
      severity: "",
      surface: "",
      mode: "",
      since_epoch: "0",
      limit: "12"
    };
  }

  function normalizeModeRuntimeTaxonomyQueryFilters(rawFilters) {
    var source = rawFilters && typeof rawFilters === "object" ? rawFilters : {};
    var normalized = defaultModeRuntimeTaxonomyQueryFilters();
    normalized.category = trim(String(source.category || "")).toLowerCase();
    normalized.surface = trim(String(source.surface || "")).toLowerCase();
    normalized.mode = trim(String(source.mode || "")).toLowerCase();
    normalized.severity = trim(String(source.severity || "")).toLowerCase();
    if (
      normalized.severity !== "" &&
      normalized.severity !== "all" &&
      normalized.severity !== "low" &&
      normalized.severity !== "medium" &&
      normalized.severity !== "high"
    ) {
      normalized.severity = "";
    }
    if (normalized.category === "all") {
      normalized.category = "";
    }
    if (normalized.surface === "all") {
      normalized.surface = "";
    }
    if (normalized.mode === "all") {
      normalized.mode = "";
    }
    if (normalized.severity === "all") {
      normalized.severity = "";
    }
    var sinceEpoch = Number(source.since_epoch || source.sinceEpoch || 0);
    if (!isFinite(sinceEpoch) || sinceEpoch < 0) {
      sinceEpoch = 0;
    }
    normalized.since_epoch = String(Math.floor(sinceEpoch));
    var limitValue = Number(source.limit || 12);
    if (!isFinite(limitValue) || limitValue <= 0) {
      limitValue = 12;
    }
    limitValue = Math.floor(limitValue);
    if (limitValue > 250) {
      limitValue = 250;
    }
    normalized.limit = String(limitValue);
    return normalized;
  }

  function modeRuntimeTaxonomyFiltersFromDom() {
    var container = el.modeRuntimeFailureTaxonomy;
    if (!container) {
      return normalizeModeRuntimeTaxonomyQueryFilters(state.modeRuntimeTaxonomyQuery && state.modeRuntimeTaxonomyQuery.filters);
    }
    var categoryInput = container.querySelector("[data-role='mode-runtime-taxonomy-category']");
    var severitySelect = container.querySelector("[data-role='mode-runtime-taxonomy-severity']");
    var surfaceInput = container.querySelector("[data-role='mode-runtime-taxonomy-surface']");
    var modeInput = container.querySelector("[data-role='mode-runtime-taxonomy-mode']");
    var sinceInput = container.querySelector("[data-role='mode-runtime-taxonomy-since-epoch']");
    var limitSelect = container.querySelector("[data-role='mode-runtime-taxonomy-limit']");
    return normalizeModeRuntimeTaxonomyQueryFilters({
      category: categoryInput ? categoryInput.value : "",
      severity: severitySelect ? severitySelect.value : "",
      surface: surfaceInput ? surfaceInput.value : "",
      mode: modeInput ? modeInput.value : "",
      since_epoch: sinceInput ? sinceInput.value : "",
      limit: limitSelect ? limitSelect.value : ""
    });
  }

  function normalizeFailureTaxonomyQueryEvents(rawEvents) {
    var list = Array.isArray(rawEvents) ? rawEvents : [];
    var events = [];
    for (var i = 0; i < list.length; i += 1) {
      var row = list[i];
      if (!row || typeof row !== "object") {
        continue;
      }
      var timestamp = trim(String(row.timestamp || ""));
      var categoryId = trim(String(row.category || ""));
      var actionText = trim(String(row.action || ""));
      var errorText = trim(String(row.error || ""));
      if (!timestamp && !categoryId && !actionText && !errorText) {
        continue;
      }
      events.push({
        timestamp: timestamp,
        category: categoryId,
        category_label: trim(String(row.category_label || categoryId)),
        surface: trim(String(row.surface || "")),
        severity: trim(String(row.severity || "")),
        mode: trim(String(row.mode || "")),
        action: actionText,
        error: errorText,
        hypothesis: trim(String(row.hypothesis || "")),
        next_attempt: trim(String(row.next_attempt || ""))
      });
    }
    return events;
  }

  function modeRuntimeQueryFailureTaxonomy(filterOverrides) {
    var baseFilters = state.modeRuntimeTaxonomyQuery && state.modeRuntimeTaxonomyQuery.filters
      ? state.modeRuntimeTaxonomyQuery.filters
      : defaultModeRuntimeTaxonomyQueryFilters();
    var mergedFilters = Object.assign({}, baseFilters, filterOverrides && typeof filterOverrides === "object" ? filterOverrides : {});
    var normalizedFilters = normalizeModeRuntimeTaxonomyQueryFilters(mergedFilters);
    state.modeRuntimeTaxonomyQuery.filters = normalizedFilters;
    state.modeRuntimeTaxonomyQuery.loading = true;
    state.modeRuntimeTaxonomyQuery.error = "";
    renderModeRuntimeSettings();
    return apiGet("failure_taxonomy_query", normalizedFilters).then(function (response) {
      if (!response || !response.success) {
        throw new Error((response && response.error) || "Could not query failure taxonomy");
      }
      var payload = response.failure_taxonomy_query && typeof response.failure_taxonomy_query === "object"
        ? response.failure_taxonomy_query
        : {};
      var payloadFilters = normalizeModeRuntimeTaxonomyQueryFilters(payload.filters || normalizedFilters);
      state.modeRuntimeTaxonomyQuery.hasQueried = true;
      state.modeRuntimeTaxonomyQuery.filters = payloadFilters;
      state.modeRuntimeTaxonomyQuery.matched_total = trim(String(payload.matched_total || "0"));
      state.modeRuntimeTaxonomyQuery.returned = trim(String(payload.returned || "0"));
      state.modeRuntimeTaxonomyQuery.events = normalizeFailureTaxonomyQueryEvents(payload.events);
      state.modeRuntimeTaxonomyQuery.error = "";
      return response;
    }).catch(function (error) {
      state.modeRuntimeTaxonomyQuery.error = error && error.message ? error.message : "Could not query failure taxonomy";
      throw error;
    }).finally(function () {
      state.modeRuntimeTaxonomyQuery.loading = false;
      renderModeRuntimeSettings();
    });
  }

  function setModeRuntimeSkillResult(text, isError) {
    if (!el.modeRuntimeSkillResult) {
      return;
    }
    var clean = trim(String(text || ""));
    if (!clean) {
      el.modeRuntimeSkillResult.textContent = "";
      el.modeRuntimeSkillResult.classList.add("hidden");
      el.modeRuntimeSkillResult.classList.remove("error");
      return;
    }
    el.modeRuntimeSkillResult.textContent = clean;
    el.modeRuntimeSkillResult.classList.remove("hidden");
    el.modeRuntimeSkillResult.classList.toggle("error", !!isError);
  }

  function modeRuntimeSkillInvoke(modeId, skillId, inputText, capabilitiesCsv) {
    return apiPost("mode_runtime_skill_invoke", {
      mode_id: trim(String(modeId || "")),
      skill_id: trim(String(skillId || "")),
      input: String(inputText || ""),
      capabilities: trim(String(capabilitiesCsv || ""))
    }).then(function (response) {
      if (!response || !response.success) {
        throw new Error((response && response.error) || "Skill invocation failed");
      }
      var result = response.result && typeof response.result === "object" ? response.result : {};
      var summary = trim(String(result.summary || ""));
      var actions = Array.isArray(result.actions) ? result.actions : [];
      var notes = trim(String(result.notes || ""));
      var lines = [];
      lines.push("skill_id: " + String(result.skill_id || skillId));
      lines.push("status: " + String(result.status || "ok"));
      if (summary) {
        lines.push("summary: " + summary);
      }
      if (actions.length) {
        lines.push("actions:");
        for (var i = 0; i < actions.length; i += 1) {
          lines.push("- " + String(actions[i] || ""));
        }
      }
      if (notes) {
        lines.push("notes: " + notes);
      }
      setModeRuntimeSkillResult(lines.join("\n"), false);
      return response;
    });
  }

  function modeRuntimeSkillCreate(payload) {
    var source = payload && typeof payload === "object" ? payload : {};
    return apiPost("mode_runtime_skill_create", {
      skill_id: trim(String(source.skill_id || "")),
      name: trim(String(source.name || "")),
      trigger: trim(String(source.trigger || "")),
      capabilities: trim(String(source.capabilities || "")),
      description: trim(String(source.description || ""))
    }).then(function (response) {
      if (!response || !response.success) {
        throw new Error((response && response.error) || "Could not create skill");
      }
      state.modeRuntime = normalizeModeRuntime(response.mode_runtime);
      reconcileAssistantModeId();
      state.modeRuntimeError = "";
      renderModeRuntimeSettings();
      return response;
    });
  }

  function modeRuntimeSkillInstall(payload) {
    var source = payload && typeof payload === "object" ? payload : {};
    return apiPost("mode_runtime_skill_install", {
      source_path: trim(String(source.source_path || "")),
      skill_id: trim(String(source.skill_id || "")),
      replace: source.replace ? "1" : "0"
    }).then(function (response) {
      if (!response || !response.success) {
        throw new Error((response && response.error) || "Could not install skill");
      }
      state.modeRuntime = normalizeModeRuntime(response.mode_runtime);
      reconcileAssistantModeId();
      state.modeRuntimeError = "";
      renderModeRuntimeSettings();
      return response;
    });
  }

  function modeRuntimeGenerateImprovementProposals() {
    return apiPost("improvement_proposal_generate", {}).then(function (response) {
      if (!response || !response.success) {
        throw new Error((response && response.error) || "Could not generate proposals");
      }
      if (response.mode_runtime) {
        state.modeRuntime = normalizeModeRuntime(response.mode_runtime);
        reconcileAssistantModeId();
        state.modeRuntimeError = "";
        renderModeRuntimeSettings();
      }
      return response;
    });
  }

  function modeRuntimeDecideImprovementProposal(proposalId, decision, noteText) {
    var safeId = trim(String(proposalId || ""));
    var safeDecision = trim(String(decision || "")).toLowerCase();
    if (!safeId) {
      return Promise.reject(new Error("proposal_id is required"));
    }
    if (safeDecision !== "accept" && safeDecision !== "apply" && safeDecision !== "reject") {
      return Promise.reject(new Error("invalid decision"));
    }
    return apiPost("improvement_proposal_decide", {
      proposal_id: safeId,
      decision: safeDecision,
      note: trim(String(noteText || "")),
      manual_confirm: safeDecision === "apply" ? "1" : "0"
    }).then(function (response) {
      if (!response || !response.success) {
        throw new Error((response && response.error) || "Could not update proposal");
      }
      if (response.mode_runtime) {
        state.modeRuntime = normalizeModeRuntime(response.mode_runtime);
        reconcileAssistantModeId();
        state.modeRuntimeError = "";
        renderModeRuntimeSettings();
      }
      return response;
    });
  }

  function modeRuntimePromoteControllerVariant(variantId) {
    var safeId = trim(String(variantId || ""));
    if (!safeId) {
      return Promise.reject(new Error("variant_id is required"));
    }
    return apiPost("controller_variant_promote", {
      variant_id: safeId,
      manual_confirm: "1"
    }).then(function (response) {
      if (!response || !response.success) {
        throw new Error((response && response.error) || "Could not promote controller variant");
      }
      if (response.mode_runtime) {
        state.modeRuntime = normalizeModeRuntime(response.mode_runtime);
        reconcileAssistantModeId();
        state.modeRuntimeError = "";
        renderModeRuntimeSettings();
      }
      return response;
    });
  }

  function modeRuntimeRollbackControllerVariant() {
    return apiPost("controller_variant_rollback", {
      manual_confirm: "1"
    }).then(function (response) {
      if (!response || !response.success) {
        throw new Error((response && response.error) || "Could not rollback controller variant");
      }
      if (response.mode_runtime) {
        state.modeRuntime = normalizeModeRuntime(response.mode_runtime);
        reconcileAssistantModeId();
        state.modeRuntimeError = "";
        renderModeRuntimeSettings();
      }
      return response;
    });
  }

  function renderModeRuntimeSettings() {
    if (!el.modeRuntimeSummary || !el.modeRuntimePanels || !el.modeRuntimeModes || !el.modeRuntimeSkills) {
      return;
    }

    var runtime = normalizeModeRuntime(state.modeRuntime);
    var scheduler = runtime.scheduler || {};
    var cooperation = runtime.cooperation || {};
    var summary = "Scheduler ticks: " + (scheduler.ticks || "0");
    if (scheduler.last_tick_iso) {
      summary += " | last tick: " + scheduler.last_tick_iso;
    }
    summary += " | directives in/out: " + (scheduler.last_directives_received || "0") + "/" + (scheduler.last_directives_emitted || "0");
    if (String(cooperation.pending_total || "0") !== "0") {
      summary += " | pending directives: " + String(cooperation.pending_total || "0");
    }
    if (scheduler.summary) {
      summary += " | " + scheduler.summary;
    }
    if (state.modeRuntimeLoading) {
      summary = "Loading Mode Runtime...";
    } else if (state.modeRuntimeError) {
      summary = state.modeRuntimeError;
    }
    el.modeRuntimeSummary.textContent = summary;

    var panelsHtml = "";
    var panels = Array.isArray(runtime.panels) ? runtime.panels : [];
    var recentDirectives = Array.isArray(cooperation.recent) ? cooperation.recent : [];
    var cooperationPanelHtml = "<section class='mode-runtime-panel mode-runtime-cooperation-panel'>";
    cooperationPanelHtml += "<div class='mode-runtime-panel-head'><strong>Mode Cooperation</strong></div>";
    cooperationPanelHtml += "<p class='settings-hint'>Directive bus for mode-to-mode governance handoffs and coordination.</p>";
    cooperationPanelHtml += "<div class='mode-runtime-metrics'>";
    cooperationPanelHtml += "<span class='mode-runtime-metric'><em>Pending</em><strong>" + escHtml(String(cooperation.pending_total || "0")) + "</strong></span>";
    cooperationPanelHtml += "<span class='mode-runtime-metric'><em>Modes waiting</em><strong>" + escHtml(String(cooperation.modes_with_pending || "0")) + "</strong></span>";
    cooperationPanelHtml += "<span class='mode-runtime-metric'><em>In / Out</em><strong>" + escHtml(String(scheduler.last_directives_received || "0") + " / " + String(scheduler.last_directives_emitted || "0")) + "</strong></span>";
    cooperationPanelHtml += "</div>";
    if (!recentDirectives.length) {
      cooperationPanelHtml += "<p class='settings-hint'>No recent cross-mode directives.</p>";
    } else {
      cooperationPanelHtml += "<div class='mode-runtime-directive-list'>";
      for (var r = 0; r < recentDirectives.length && r < 10; r += 1) {
        var directive = recentDirectives[r] || {};
        var fromMode = trim(String(directive.from_mode || "mode"));
        var toMode = trim(String(directive.to_mode || "mode"));
        var kind = trim(String(directive.kind || "note"));
        var payload = trim(String(directive.payload || ""));
        var stamp = trim(String(directive.timestamp || ""));
        var prefix = fromMode + " -> " + toMode + " [" + kind + "]";
        if (directive.expired) {
          prefix += " (expired)";
        }
        cooperationPanelHtml += "<p class='settings-hint mode-runtime-directive-item'><strong>" + escHtml(prefix) + "</strong>";
        if (payload) {
          cooperationPanelHtml += " " + escHtml(payload);
        }
        if (stamp) {
          cooperationPanelHtml += " <span class='mode-runtime-directive-time'>" + escHtml(stamp) + "</span>";
        }
        cooperationPanelHtml += "</p>";
      }
      cooperationPanelHtml += "</div>";
    }
    cooperationPanelHtml += "</section>";
    if (!panels.length) {
      panelsHtml = cooperationPanelHtml + "<p class='empty-state'>No runtime panels available yet.</p>";
    } else {
      panelsHtml += cooperationPanelHtml;
      for (var i = 0; i < panels.length; i += 1) {
        var panel = panels[i] || {};
        var metrics = Array.isArray(panel.metrics) ? panel.metrics : [];
        panelsHtml += "<section class='mode-runtime-panel'>";
        panelsHtml += "<div class='mode-runtime-panel-head'><strong>" + escHtml(panel.title || panel.id || "Panel") + "</strong></div>";
        if (panel.summary) {
          panelsHtml += "<p class='settings-hint'>" + escHtml(panel.summary) + "</p>";
        }
        if (metrics.length) {
          panelsHtml += "<div class='mode-runtime-metrics'>";
          for (var m = 0; m < metrics.length; m += 1) {
            var metric = metrics[m] || {};
            panelsHtml += "<span class='mode-runtime-metric'><em>" + escHtml(metric.label || "Metric") + "</em><strong>" + escHtml(metric.value || "") + "</strong></span>";
          }
          panelsHtml += "</div>";
        }
        if (panel.stream) {
          panelsHtml += "<p class='settings-hint'>" + escHtml(panel.stream) + "</p>";
        }
        panelsHtml += "</section>";
      }
    }
    el.modeRuntimePanels.innerHTML = panelsHtml;

    var modes = Array.isArray(runtime.modes) ? runtime.modes : [];
    var modesHtml = "";
    if (!modes.length) {
      modesHtml = "<p class='empty-state'>No Teams configured.</p>";
    } else {
      modesHtml += "<section class='mode-runtime-group'><div class='mode-runtime-group-head'><p class='command-rules-group-title'>Teams</p></div>";
      for (var j = 0; j < modes.length; j += 1) {
        var mode = modes[j] || {};
        var modeId = String(mode.id || "");
        if (!modeId) {
          continue;
        }
        var enabledLabel = mode.enabled ? "Disable" : "Enable";
        var enabledNext = mode.enabled ? "0" : "1";
        var injectLabel = mode.allow_queue_injection ? "Queue injection: On" : "Queue injection: Off";
        var injectNext = mode.allow_queue_injection ? "0" : "1";
        var driftValue = trim(String(mode.drift_score || "0.00"));
        var directiveInValue = trim(String(mode.last_directive_count || "0"));
        var directiveOutValue = trim(String(mode.last_directive_emits || "0"));
        var directiveSummaryValue = trim(String(mode.last_directive_summary || "none"));
        var cadenceValue = queueNumber(mode.cadence_sec || 0);
        var priorityValue = queueNumber(mode.priority || 0);
        modesHtml += "<article class='mode-runtime-mode'>";
        modesHtml += "<div class='mode-runtime-mode-head'><strong>" + escHtml(mode.name || modeId) + "</strong><span class='mode-runtime-chip'>" + escHtml(mode.status || "idle") + "</span></div>";
        if (mode.description) {
          modesHtml += "<p class='settings-hint'>" + escHtml(mode.description) + "</p>";
        }
        modesHtml += "<p class='settings-hint'>drift " + escHtml(driftValue) + " | cadence " + escHtml(String(cadenceValue || 0)) + "s | priority " + escHtml(String(priorityValue || 0)) + "</p>";
        modesHtml += "<p class='settings-hint'>directives in " + escHtml(directiveInValue) + " | out " + escHtml(directiveOutValue) + "</p>";
        if (directiveSummaryValue && directiveSummaryValue !== "none") {
          modesHtml += "<p class='settings-hint'>latest directive context: " + escHtml(directiveSummaryValue) + "</p>";
        }
        modesHtml += "<div class='mode-runtime-actions'>";
        modesHtml += "<button type='button' data-action='mode-runtime-use' data-mode-id='" + escAttr(modeId) + "'>Set as Team</button>";
        modesHtml += "<button type='button' data-action='mode-runtime-toggle' data-mode-id='" + escAttr(modeId) + "' data-enabled='" + escAttr(enabledNext) + "'>" + escHtml(enabledLabel) + "</button>";
        modesHtml += "<button type='button' data-action='mode-runtime-injection' data-mode-id='" + escAttr(modeId) + "' data-allow='" + escAttr(injectNext) + "'>" + escHtml(injectLabel) + "</button>";
        modesHtml += "</div>";
        modesHtml += "</article>";
      }
      modesHtml += "</section>";
    }
    el.modeRuntimeModes.innerHTML = modesHtml;

    var skills = Array.isArray(runtime.skills) ? runtime.skills : [];
    var skillsHtml = "";
    if (!skills.length) {
      skillsHtml = "<p class='empty-state'>No Skills configured.</p>";
    } else {
      skillsHtml += "<section class='mode-runtime-group'><div class='mode-runtime-group-head'><p class='command-rules-group-title'>Skills</p></div>";
      for (var k = 0; k < skills.length; k += 1) {
        var skill = skills[k] || {};
        var caps = Array.isArray(skill.capabilities) ? skill.capabilities : [];
        skillsHtml += "<article class='mode-runtime-skill'>";
        skillsHtml += "<div class='mode-runtime-mode-head'><strong>" + escHtml(skill.name || skill.id || "Skill") + "</strong></div>";
        if (skill.description) {
          skillsHtml += "<p class='settings-hint'>" + escHtml(skill.description) + "</p>";
        }
        if (skill.trigger) {
          skillsHtml += "<p class='settings-hint'>trigger: " + escHtml(skill.trigger) + "</p>";
        }
        var fileBadges = [];
        if (skill.files && typeof skill.files === "object") {
          if (skill.files.policy_md) {
            fileBadges.push("policy.md");
          }
          if (skill.files.trigger_yaml) {
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

    if (action === "workspace-drag-handle" || action === "conversation-drag-handle") {
      event.preventDefault();
      event.stopPropagation();
      return;
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
      openAutomationModal("create", "");
      return;
    }

    if (action === "select-automation") {
      if (!automationId) {
        return;
      }
      saveSidebarSection("automations");
      state.activeAutomationId = String(automationId || "");
      renderUi();
      return;
    }

    if (action === "automation-edit") {
      if (!automationId) {
        return;
      }
      event.preventDefault();
      event.stopPropagation();
      openAutomationModal("edit", automationId);
      return;
    }

    if (action === "automation-run-now") {
      if (!automationId) {
        return;
      }
      event.preventDefault();
      event.stopPropagation();
      runWithControlPending(target, function () {
        return runAutomationNow(automationId);
      }).catch(showError);
      return;
    }

    if (action === "automation-delete") {
      if (!automationId) {
        return;
      }
      event.preventDefault();
      event.stopPropagation();
      var existingAutomation = automationById(automationId);
      var label = existingAutomation && existingAutomation.name ? existingAutomation.name : "this automation";
      if (!window.confirm("Delete " + label + "?")) {
        return;
      }
      runWithControlPending(target, function () {
        return deleteAutomationById(automationId);
      }).catch(showError);
      return;
    }

    if (action === "select-triage") {
      saveSidebarSection("threads");
      state.triageOtherInputProposalId = "";
      state.activeTriage = true;
      state.activeWorkspaceId = "";
      state.activeConversationId = "";
      state.activeConversation = null;
      state.activeDraftWorkspaceId = "";
      renderUi();
      return;
    }

    if (action === "triage-open-context") {
      if (workspaceId && conversationId) {
        saveSidebarSection("threads");
        state.triageOtherInputProposalId = "";
        state.activeTriage = false;
        state.activeWorkspaceId = workspaceId;
        state.activeConversationId = conversationId;
        state.activeDraftWorkspaceId = "";
        loadConversation({
          workspaceId: workspaceId,
          conversationId: conversationId
        }).catch(showError);
        renderUi();
      }
      return;
    }

    if (action === "triage-decide") {
      if (!proposalId) {
        return;
      }
      var fixedDecision = trim(String(target.getAttribute("data-decision") || ""));
      var decisionAnswer = fixedDecision || "accepted";
      state.triageOtherInputProposalId = "";
      runWithControlPending(target, function () {
        return triageDecide(proposalId, decisionAnswer).then(function () {
          return loadState();
        }).then(renderUi);
      }).catch(showError);
      return;
    }

    if (action === "triage-decision-other-toggle") {
      if (!proposalId) {
        return;
      }
      if (String(state.triageOtherInputProposalId || "") === String(proposalId)) {
        state.triageOtherInputProposalId = "";
      } else {
        state.triageOtherInputProposalId = String(proposalId || "");
      }
      renderUi();
      return;
    }

    if (action === "triage-decision-other-submit") {
      if (!proposalId) {
        return;
      }
      var otherRow = target.closest("[data-triage-other-row]");
      var otherInput = otherRow ? otherRow.querySelector("[data-triage-other-input]") : null;
      var otherDecision = trim(otherInput ? otherInput.value : "");
      if (!otherDecision) {
        if (otherInput) {
          otherInput.focus();
        }
        return;
      }
      state.triageOtherInputProposalId = "";
      runWithControlPending(target, function () {
        return triageDecide(proposalId, otherDecision).then(function () {
          return loadState();
        }).then(renderUi);
      }).catch(showError);
      return;
    }

    if (action === "triage-suppress-workspace") {
      if (!proposalId) {
        return;
      }
      state.triageOtherInputProposalId = "";
      runWithControlPending(target, function () {
        return triageSuppress(proposalId, "workspace").then(function () {
          return loadState();
        }).then(renderUi);
      }).catch(showError);
      return;
    }

    if (action === "triage-cleanup" || action === "triage-cleanup-guided") {
      closeAllMenus();
      var directive = "";
      if (action === "triage-cleanup-guided") {
        var directivePrompt = window.prompt("Guidance for triage cleanup", "Merge repeats and defer reversible low-impact items.");
        if (directivePrompt === null) {
          return;
        }
        directive = directivePrompt;
      }
      runWithControlPending(target, function () {
        return triageCleanup(directive).then(function (result) {
          var collapsed = Array.isArray(result && result.collapsed) ? result.collapsed : [];
          if (collapsed.length) {
            var lines = [];
            for (var i = 0; i < collapsed.length && i < 6; i += 1) {
              lines.push("- " + String(collapsed[i].summary || "Decision cluster") + " (" + String(collapsed[i].count || 0) + ")");
            }
            window.alert("Cleanup preview:\n" + lines.join("\n"));
          }
          return triageRefresh();
        }).then(renderUi);
      }).catch(showError);
      return;
    }

    if (action === "toggle-workspace") {
      if (workspaceId) {
        setWorkspaceExpanded(workspaceId, !state.expandedWorkspaceIds[workspaceId], { animate: true });
      }
      return;
    }

    if (action === "toggle-workspace-menu") {
      event.preventDefault();
      event.stopPropagation();
      if (state.openWorkspaceMenuWorkspaceId === workspaceId) {
        state.openWorkspaceMenuWorkspaceId = "";
      } else {
        state.openWorkspaceMenuWorkspaceId = workspaceId || "";
      }
      renderUi();
      return;
    }

    if (action === "new-conversation") {
      if (workspaceId) {
        state.pendingArchiveKey = "";
        state.pendingArchiveReadyAt = 0;
        state.pendingArchiveSubmittingKey = "";
        runWithControlPending(target, function () {
          return createDraftForWorkspace(workspaceId);
        }).catch(showError);
      }
      return;
    }

    if (action === "open-workspace-multi_agent") {
      if (!workspaceId) {
        return;
      }
      event.preventDefault();
      event.stopPropagation();
      state.openWorkspaceMenuWorkspaceId = "";
      openMultiAgentModal(workspaceId).catch(showError);
      return;
    }

    if (action === "rename-workspace") {
      if (!workspaceId) {
        return;
      }
      event.preventDefault();
      event.stopPropagation();
      var workspaceToRename = getWorkspaceById(workspaceId);
      var currentName = workspaceToRename && workspaceToRename.name ? workspaceToRename.name : "";
      var nextName = window.prompt("Rename project", currentName);
      if (nextName === null) {
        return;
      }
      runWithControlPending(target, function () {
        return renameWorkspace(workspaceId, nextName);
      }).catch(showError);
      return;
    }

    if (action === "open-workspace-approvals") {
      if (!workspaceId) {
        return;
      }
      event.preventDefault();
      event.stopPropagation();
      state.commandRulesWorkspaceId = workspaceId;
      state.openWorkspaceMenuWorkspaceId = "";
      openSettingsModal().then(function () {
        return loadCommandRules(workspaceId);
      }).catch(showError);
      return;
    }

    if (action === "remove-workspace") {
      if (!workspaceId) {
        return;
      }
      event.preventDefault();
      event.stopPropagation();
      var workspace = getWorkspaceById(workspaceId);
      var label = workspace && workspace.name ? workspace.name : "this project";
      if (!window.confirm("Remove " + label + " and its Artificer thread history?")) {
        return;
      }
      runWithControlPending(target, function () {
        return removeWorkspace(workspaceId);
      }).catch(showError);
      return;
    }

    if (action === "arm-archive-conversation") {
      if (!workspaceId || !conversationId) {
        return;
      }
      event.preventDefault();
      event.stopPropagation();
      var archiveKey = conversationReadKey(workspaceId, conversationId);
      state.pendingArchiveKey = archiveKey;
      state.pendingArchiveReadyAt = Date.now();
      renderUi();
      return;
    }

    if (action === "confirm-archive-conversation") {
      if (!workspaceId || !conversationId) {
        return;
      }
      event.preventDefault();
      event.stopPropagation();
      var key = conversationReadKey(workspaceId, conversationId);
      if (key === state.pendingArchiveSubmittingKey) {
        return;
      }
      if (key !== state.pendingArchiveKey) {
        state.pendingArchiveKey = key;
        state.pendingArchiveReadyAt = Date.now();
      }
      state.pendingArchiveSubmittingKey = key;
      renderUi();
      archiveConversation(workspaceId, conversationId).catch(function (error) {
        state.pendingArchiveSubmittingKey = "";
        renderUi();
        showError(error);
      });
      return;
    }

    if (action === "select-workspace") {
      if (workspaceId) {
        state.activeTriage = false;
        state.pendingArchiveKey = "";
        state.pendingArchiveReadyAt = 0;
        state.pendingArchiveSubmittingKey = "";
        setWorkspaceExpanded(workspaceId, !state.expandedWorkspaceIds[workspaceId], { animate: true });
      }
      return;
    }

    if (action === "select-conversation") {
      if (workspaceId && conversationId) {
        var clickedConversationMeta = !!(
          event.target &&
          event.target.closest &&
          event.target.closest(".meta-age-slot, .thread-archive-wrap")
        );
        if (clickedConversationMeta) {
          return;
        }
        var sameConversationSelected = (
          String(state.activeWorkspaceId || "") === String(workspaceId || "") &&
          String(state.activeConversationId || "") === String(conversationId || "") &&
          !state.activeDraftWorkspaceId
        );
        if (sameConversationSelected) {
          return;
        }
        state.activeTriage = false;
        var selectingDifferentConversation = (
          String(state.activeWorkspaceId || "") !== String(workspaceId || "") ||
          String(state.activeConversationId || "") !== String(conversationId || "")
        );
        if (selectingDifferentConversation) {
          state.pendingArchiveKey = "";
          state.pendingArchiveReadyAt = 0;
          state.pendingArchiveSubmittingKey = "";
        }
        runWithControlPending(target, function () {
          return selectConversation(workspaceId, conversationId);
        }, { spinner: false }).catch(showError);
      }
      return;
    }

    if (action === "select-draft") {
      if (workspaceId) {
        state.activeTriage = false;
        state.pendingArchiveKey = "";
        state.pendingArchiveReadyAt = 0;
        state.pendingArchiveSubmittingKey = "";
        runWithControlPending(target, function () {
          return selectDraft(workspaceId);
        }, { spinner: false }).catch(showError);
      }
    }
  }

  function handleWorkspaceTreeKeydown(event) {
    var target = event.target.closest(".conversation-row[role='button'], .automation-row[role='button']");
    if (!target) {
      return;
    }
    if (event.key !== "Enter" && event.key !== " ") {
      return;
    }
    event.preventDefault();
    target.click();
  }

  function handleWorkspaceTreeChange(event) {
    var target = event.target && event.target.closest ? event.target.closest("[data-action]") : null;
    if (!target) {
      return;
    }
    var action = target.getAttribute("data-action");
    if (action !== "automation-toggle-enabled") {
      return;
    }
    var automationId = target.getAttribute("data-automation-id");
    if (!automationId) {
      return;
    }
    event.preventDefault();
    event.stopPropagation();
    var enabled = !!(target.checked);
    runWithControlPending(target, function () {
      return setAutomationEnabled(automationId, enabled);
    }, { spinner: false }).catch(showError);
  }

  function workspaceTreeDragAllowed() {
    return state.sidebarSection === "threads" && state.organizeMode === "project" && state.organizeShow === "all";
  }

  function clearWorkspaceTreeDragClasses() {
    if (!el.workspaceTree) {
      return;
    }
    var draggingRows = el.workspaceTree.querySelectorAll(".workspace-row.workspace-row-dragging, .conversation-row.conversation-row-dragging");
    for (var i = 0; i < draggingRows.length; i += 1) {
      draggingRows[i].classList.remove("workspace-row-dragging");
      draggingRows[i].classList.remove("conversation-row-dragging");
    }
  }

  function stopWorkspaceTreeDrag() {
    clearWorkspaceTreeDragClasses();
    state.workspaceTreeDrag.active = false;
    state.workspaceTreeDrag.type = "";
    state.workspaceTreeDrag.workspaceId = "";
    state.workspaceTreeDrag.conversationId = "";
  }

  function finalizeWorkspaceOrderFromTreeDom() {
    if (!el.workspaceTree) {
      return;
    }
    var groups = el.workspaceTree.querySelectorAll(".workspace-group[data-workspace-id]");
    var order = [];
    for (var i = 0; i < groups.length; i += 1) {
      var workspaceId = trim(String(groups[i].getAttribute("data-workspace-id") || ""));
      if (workspaceId) {
        order.push(workspaceId);
      }
    }
    state.workspaceOrderIds = normalizeOrderedIdList(order);
  }

  function finalizeConversationOrderFromTreeDom(workspaceId) {
    var wsId = trim(String(workspaceId || ""));
    if (!el.workspaceTree || !wsId) {
      return;
    }
    var group = el.workspaceTree.querySelector(".workspace-group[data-workspace-id='" + escAttr(wsId) + "']");
    if (!group) {
      return;
    }
    var rows = group.querySelectorAll(".conversation-row[data-workspace-id][data-conversation-id]");
    var orderedIds = [];
    for (var i = 0; i < rows.length; i += 1) {
      var rowWorkspaceId = trim(String(rows[i].getAttribute("data-workspace-id") || ""));
      var rowConversationId = trim(String(rows[i].getAttribute("data-conversation-id") || ""));
      if (rowWorkspaceId !== wsId || !rowConversationId) {
        continue;
      }
      orderedIds.push(rowConversationId);
    }
    var current = normalizeOrderedIdList(state.conversationOrderIdsByWorkspace[wsId]);
    for (var j = 0; j < current.length; j += 1) {
      var existing = current[j];
      var found = false;
      for (var k = 0; k < orderedIds.length; k += 1) {
        if (orderedIds[k] === existing) {
          found = true;
          break;
        }
      }
      if (!found) {
        orderedIds.push(existing);
      }
    }
    if (!state.conversationOrderIdsByWorkspace || typeof state.conversationOrderIdsByWorkspace !== "object") {
      state.conversationOrderIdsByWorkspace = {};
    }
    state.conversationOrderIdsByWorkspace[wsId] = normalizeOrderedIdList(orderedIds);
  }

  function onWorkspaceTreeDragStart(event) {
    if (!workspaceTreeDragAllowed()) {
      return;
    }
    event.stopPropagation();
    var handle = event.target.closest("[data-action='workspace-drag-handle'], [data-action='conversation-drag-handle']");
    if (!handle) {
      event.preventDefault();
      return;
    }
    var row = event.target.closest(".workspace-row[data-drag-type='workspace'][data-workspace-id], .conversation-row[data-drag-type='conversation'][data-workspace-id][data-conversation-id]");
    if (!row) {
      event.preventDefault();
      return;
    }
    var dragType = String(row.getAttribute("data-drag-type") || "");
    var workspaceId = trim(String(row.getAttribute("data-workspace-id") || ""));
    var conversationId = trim(String(row.getAttribute("data-conversation-id") || ""));
    if (!workspaceId || (dragType === "conversation" && !conversationId)) {
      event.preventDefault();
      return;
    }
    state.workspaceTreeDrag.active = true;
    state.workspaceTreeDrag.type = dragType;
    state.workspaceTreeDrag.workspaceId = workspaceId;
    state.workspaceTreeDrag.conversationId = conversationId;
    row.classList.add(dragType === "workspace" ? "workspace-row-dragging" : "conversation-row-dragging");
    if (event.dataTransfer) {
      event.dataTransfer.effectAllowed = "move";
      event.dataTransfer.setData("text/plain", dragType + ":" + workspaceId + ":" + conversationId);
    }
  }

  function onWorkspaceTreeDragOver(event) {
    if (!state.workspaceTreeDrag.active || !workspaceTreeDragAllowed() || !el.workspaceTree) {
      return;
    }
    event.preventDefault();
    event.stopPropagation();
    var dragType = String(state.workspaceTreeDrag.type || "");
    if (dragType === "workspace") {
      var overWorkspaceRow = event.target.closest(".workspace-row[data-drag-type='workspace'][data-workspace-id]");
      if (!overWorkspaceRow) {
        return;
      }
      var dragWorkspaceId = String(state.workspaceTreeDrag.workspaceId || "");
      var overWorkspaceId = String(overWorkspaceRow.getAttribute("data-workspace-id") || "");
      if (!dragWorkspaceId || !overWorkspaceId || dragWorkspaceId === overWorkspaceId) {
        return;
      }
      var dragGroup = el.workspaceTree.querySelector(".workspace-group[data-workspace-id='" + escAttr(dragWorkspaceId) + "']");
      var overGroup = el.workspaceTree.querySelector(".workspace-group[data-workspace-id='" + escAttr(overWorkspaceId) + "']");
      if (!dragGroup || !overGroup || dragGroup === overGroup) {
        return;
      }
      var beforePositions = snapshotWorkspaceTreePositions(".workspace-group[data-workspace-id]");
      var overRect = overWorkspaceRow.getBoundingClientRect();
      var insertAfter = event.clientY > (overRect.top + overRect.height * 0.5);
      if (insertAfter) {
        if (overGroup.nextSibling !== dragGroup) {
          el.workspaceTree.insertBefore(dragGroup, overGroup.nextSibling);
        }
      } else {
        el.workspaceTree.insertBefore(dragGroup, overGroup);
      }
      animateWorkspaceTreeFromSnapshot(beforePositions, ".workspace-group[data-workspace-id]");
      return;
    }

    if (dragType === "conversation") {
      var overConversationRow = event.target.closest(".conversation-row[data-drag-type='conversation'][data-workspace-id][data-conversation-id]");
      if (!overConversationRow) {
        return;
      }
      var dragWorkspace = String(state.workspaceTreeDrag.workspaceId || "");
      var dragConversation = String(state.workspaceTreeDrag.conversationId || "");
      var overWorkspace = String(overConversationRow.getAttribute("data-workspace-id") || "");
      var overConversation = String(overConversationRow.getAttribute("data-conversation-id") || "");
      if (
        !dragWorkspace ||
        !dragConversation ||
        dragWorkspace !== overWorkspace ||
        !overConversation ||
        dragConversation === overConversation
      ) {
        return;
      }
      var dragConversationRow = el.workspaceTree.querySelector(".conversation-row[data-workspace-id='" + escAttr(dragWorkspace) + "'][data-conversation-id='" + escAttr(dragConversation) + "']");
      if (!dragConversationRow || dragConversationRow === overConversationRow) {
        return;
      }
      var shell = overConversationRow.closest(".conversation-shell");
      if (!shell || shell !== dragConversationRow.closest(".conversation-shell")) {
        return;
      }
      var beforeConversationPositions = snapshotWorkspaceTreePositions(
        ".conversation-row[data-workspace-id='" + escAttr(dragWorkspace) + "'][data-conversation-id]"
      );
      var overConversationRect = overConversationRow.getBoundingClientRect();
      var insertConversationAfter = event.clientY > (overConversationRect.top + overConversationRect.height * 0.5);
      if (insertConversationAfter) {
        if (overConversationRow.nextSibling !== dragConversationRow) {
          shell.insertBefore(dragConversationRow, overConversationRow.nextSibling);
        }
      } else {
        shell.insertBefore(dragConversationRow, overConversationRow);
      }
      animateWorkspaceTreeFromSnapshot(
        beforeConversationPositions,
        ".conversation-row[data-workspace-id='" + escAttr(dragWorkspace) + "'][data-conversation-id]"
      );
    }
  }

  function onWorkspaceTreeDrop(event) {
    if (!state.workspaceTreeDrag.active || !workspaceTreeDragAllowed()) {
      return;
    }
    event.preventDefault();
    event.stopPropagation();
    var dragType = String(state.workspaceTreeDrag.type || "");
    if (dragType === "workspace") {
      finalizeWorkspaceOrderFromTreeDom();
    } else if (dragType === "conversation") {
      finalizeConversationOrderFromTreeDom(state.workspaceTreeDrag.workspaceId);
    }
    persistWorkspaceOrderingState();
    stopWorkspaceTreeDrag();
    renderUi();
  }

  function onWorkspaceTreeDragEnd() {
    if (!state.workspaceTreeDrag.active) {
      return;
    }
    stopWorkspaceTreeDrag();
  }

  function handleAttachmentStripClick(event) {
    var target = event.target.closest("[data-action]");
    if (!target) {
      return;
    }

    var action = target.getAttribute("data-action");
    var attachmentId = target.getAttribute("data-attachment-id");
    if (!attachmentId) {
      return;
    }

    if (action === "remove-attachment") {
      event.preventDefault();
      event.stopPropagation();
      removePendingAttachmentById(attachmentId);
      return;
    }

    if (action === "preview-attachment") {
      openAttachmentPreview(attachmentId);
    }
  }

  function handleAttachmentStripKeydown(event) {
    if (event.key !== "Enter" && event.key !== " ") {
      return;
    }
    var target = event.target.closest("[data-action='preview-attachment']");
    if (!target) {
      return;
    }
    var attachmentId = target.getAttribute("data-attachment-id");
    if (!attachmentId) {
      return;
    }
    event.preventDefault();
    openAttachmentPreview(attachmentId);
  }

  function updateWorkspaceNamePlaceholderFromPath(pathValue) {
    if (!el.workspaceName) {
      return;
    }
    var fallback = "my project";
    var path = trim(pathValue || "");
    var folderName = path ? basename(path) : "";
    el.workspaceName.placeholder = folderName || fallback;
  }

  function onWorkspaceBrowseClick() {
    if (state.pickingWorkspace) {
      return Promise.resolve();
    }
    function openDirPickerFallback() {
      if (!el.workspaceDirPicker) {
        return false;
      }
      state.awaitingDirPicker = true;
      el.workspaceDirPicker.value = "";
      el.workspaceDirPicker.click();
      return true;
    }

    var browseStartedAt = Date.now();
    state.pickingWorkspace = true;
    state.awaitingDirPicker = false;
    return apiGet("pick_workspace")
      .then(function (picked) {
        if (picked.success && picked.cancelled) {
          var elapsedMs = Date.now() - browseStartedAt;
          if (elapsedMs < 300 && openDirPickerFallback()) {
            return;
          }
          return;
        }

        if (picked.success && picked.path) {
          el.workspacePath.value = picked.path;
          updateWorkspaceNamePlaceholderFromPath(picked.path);
          return;
        }

        if (openDirPickerFallback()) {
          return;
        }

        throw new Error(picked.error || "Could not open folder picker.");
      })
      .catch(function (error) {
        if (openDirPickerFallback()) {
          return;
        }
        throw error;
      })
      .finally(function () {
        if (!state.awaitingDirPicker) {
          state.pickingWorkspace = false;
        }
      });
  }

  function onWorkspaceDirPicked(event) {
    var input = event.target;
    if (!input || !input.files || input.files.length === 0) {
      state.awaitingDirPicker = false;
      state.pickingWorkspace = false;
      return Promise.resolve();
    }

    var firstFile = input.files[0];
    var pickedPath = "";

    if (firstFile.path) {
      pickedPath = dirname(firstFile.path);
    }

    if (!pickedPath) {
      state.awaitingDirPicker = false;
      state.pickingWorkspace = false;
      return Promise.reject(new Error("Folder path unavailable in this browser. Use Browse."));
    }

    el.workspacePath.value = pickedPath;
    updateWorkspaceNamePlaceholderFromPath(pickedPath);
    state.awaitingDirPicker = false;
    state.pickingWorkspace = false;
    return Promise.resolve();
  }

  function onWorkspaceModalSubmit(event) {
    event.preventDefault();
    var path = trim(el.workspacePath.value);
    var name = trim(el.workspaceName.value);
    if (!path) {
      return Promise.reject(new Error("Project path is required."));
    }

    return addWorkspaceByPath(path, name).then(function () {
      el.workspacePath.value = "";
      el.workspaceName.value = "";
      updateWorkspaceNamePlaceholderFromPath("");
      closeModal(el.workspaceModal);
      renderUi();
      refreshAll().catch(showError);
      return null;
    });
  }

  function onWorkspaceDropped(event) {
    event.preventDefault();
    setWorkspaceDropActive(false);
    var droppedPath = extractPathFromDataTransfer(event.dataTransfer);
    if (trim(droppedPath)) {
      return addWorkspaceFromDropCandidate(droppedPath).then(function () {
        return refreshAll();
      });
    }

    el.workspacePath.value = "";
    el.workspaceName.value = "";
    updateWorkspaceNamePlaceholderFromPath("");
    openModal(el.workspaceModal);
    return onWorkspaceBrowseClick().then(function () {
      var pickedPath = trim(el.workspacePath.value);
      if (!pickedPath) {
        closeModal(el.workspaceModal);
        return null;
      }
      return addWorkspaceByPath(pickedPath, trim(el.workspaceName.value)).then(function () {
        el.workspacePath.value = "";
        el.workspaceName.value = "";
        updateWorkspaceNamePlaceholderFromPath("");
        closeModal(el.workspaceModal);
        renderUi();
        refreshAll().catch(showError);
        return null;
      });
    });
  }

  function onComposerDragEnter(event) {
    event.preventDefault();
    state.composerDragDepth += 1;
    setComposerDragActive(true);
  }

  function onComposerDragOver(event) {
    event.preventDefault();
    setComposerDragActive(true);
  }

  function onComposerDragLeave(event) {
    event.preventDefault();
    state.composerDragDepth = Math.max(0, state.composerDragDepth - 1);
    if (state.composerDragDepth === 0) {
      setComposerDragActive(false);
    }
  }

  function onComposerDropped(event) {
    event.preventDefault();
    state.composerDragDepth = 0;
    setComposerDragActive(false);
    var files = event.dataTransfer && event.dataTransfer.files ? event.dataTransfer.files : [];
    addComposerFiles(files);
  }

  function onAttachmentPickerChange(event) {
    var input = event.target;
    var files = input && input.files ? input.files : [];
    addComposerFiles(files);
    if (input) {
      input.value = "";
    }
  }

  function onPromptPaste(event) {
    var clipboard = event.clipboardData;
    if (!clipboard || !clipboard.files || clipboard.files.length < 1) {
      return;
    }
    event.preventDefault();
    addComposerFiles(clipboard.files);
  }

  function appendDictationText(inputEl, text) {
    if (!inputEl) {
      return;
    }
    var insertion = trim(String(text || ""));
    if (!insertion) {
      return;
    }
    var current = String(inputEl.value || "");
    var needsLeadingSpace = current.length > 0 && !/\s$/.test(current);
    var nextText = current + (needsLeadingSpace ? " " : "") + insertion;
    inputEl.value = nextText;
    var caret = nextText.length;
    if (typeof inputEl.setSelectionRange === "function") {
      inputEl.setSelectionRange(caret, caret);
    }
  }

  function appendDictationTextToValue(baseText, text) {
    var current = String(baseText || "");
    var insertion = trim(String(text || ""));
    if (!insertion) {
      return current;
    }
    var needsLeadingSpace = current.length > 0 && !/\s$/.test(current);
    return current + (needsLeadingSpace ? " " : "") + insertion;
  }

  function applyDictationTextToCapturedTarget(text, contextOverride) {
    var dictated = trim(String(text || ""));
    if (!dictated) {
      return false;
    }
    var context = contextOverride && typeof contextOverride === "object"
      ? contextOverride
      : (state.dictateCaptureContext && typeof state.dictateCaptureContext === "object" ? state.dictateCaptureContext : null);
    var targetKey = String(context && context.outgoingKey || state.dictateTargetOutgoingKey || "");
    if (!targetKey) {
      return false;
    }
    var targetWorkspaceId = String(context && context.workspaceId || state.dictateTargetWorkspaceId || "");
    var targetConversationId = String(context && context.conversationId || state.dictateTargetConversationId || "");
    var targetDraftWorkspaceId = String(context && context.draftWorkspaceId || state.dictateTargetDraftWorkspaceId || "");
    var baseText = hasComposerDraftForKey(targetKey)
      ? String(state.composerDraftByKey[targetKey] || "")
      : String(context && context.promptSnapshot || state.dictateTargetPromptSnapshot || "");
    var nextText = appendDictationTextToValue(baseText, dictated);
    setComposerDraftForKey(targetKey, nextText);
    if (targetDraftWorkspaceId) {
      state.draftTextByWorkspace[targetDraftWorkspaceId] = nextText;
      saveDraft(targetDraftWorkspaceId, nextText).catch(showError);
    } else if (targetWorkspaceId && targetConversationId) {
      saveConversationDraft(targetWorkspaceId, targetConversationId, nextText).catch(showError);
    }
    if (activeOutgoingKey() === targetKey && el.runPrompt) {
      if (String(el.runPrompt.value || "") !== nextText) {
        el.runPrompt.value = nextText;
      }
      dispatchInputEvent(el.runPrompt);
      if (typeof el.runPrompt.focus === "function") {
        el.runPrompt.focus();
      }
    }
    return true;
  }

  function clearDictationTargetContext() {
    state.dictateTargetWorkspaceId = "";
    state.dictateTargetConversationId = "";
    state.dictateTargetDraftWorkspaceId = "";
    state.dictateTargetOutgoingKey = "";
    state.dictateTargetPromptSnapshot = "";
    state.dictateCaptureContext = null;
    state.dictateCaptureBySessionId = {};
  }

  function insertTextAtCursor(inputEl, text) {
    appendDictationText(inputEl, text);
  }

  function dispatchInputEvent(inputEl) {
    if (!inputEl || typeof inputEl.dispatchEvent !== "function") {
      return;
    }
    var nextEvent = null;
    if (typeof Event === "function") {
      try {
        nextEvent = new Event("input", { bubbles: true });
      } catch (_err) {
        nextEvent = null;
      }
    }
    if (!nextEvent && typeof document !== "undefined" && document && typeof document.createEvent === "function") {
      nextEvent = document.createEvent("Event");
      nextEvent.initEvent("input", true, true);
    }
    if (nextEvent) {
      inputEl.dispatchEvent(nextEvent);
    }
  }

  function dictateLegacyOneShot() {
    return apiPost("dictate", { duration: "20" }, { timeoutMs: 220000 });
  }

  function startDictationCapture(options) {
    var opts = options && typeof options === "object" ? options : {};
    if (!state.dictationInstalled) {
      return Promise.resolve(false);
    }
    if (state.dictateBusy || state.dictateRecording || !el.runPrompt) {
      return Promise.resolve(false);
    }
    var stopAfterStart = false;
    var requestedStartedAtMs = Number(opts.startedAtMs || Date.now());
    if (!isFinite(requestedStartedAtMs) || requestedStartedAtMs < 0) {
      requestedStartedAtMs = Date.now();
    } else {
      requestedStartedAtMs = Math.floor(requestedStartedAtMs);
    }
    dictationPrepareReadyUntil = 0;
    stopDictationPrepareLoop();
    var captureContext = buildComposerTargetContextFromState();
    if (!captureContext) {
      return Promise.reject(new Error("Choose a thread or draft before starting dictation."));
    }
    state.dictateTargetWorkspaceId = String(captureContext.workspaceId || "");
    state.dictateTargetConversationId = String(captureContext.conversationId || "");
    state.dictateTargetDraftWorkspaceId = String(captureContext.draftWorkspaceId || "");
    state.dictateTargetOutgoingKey = String(captureContext.outgoingKey || "");
    state.dictateTargetPromptSnapshot = String(captureContext.promptSnapshot || "");
    state.dictateCaptureContext = captureContext;
    state.dictateBusy = true;
    setDictationPhase("starting");
    renderUi();
    var startPayload = { requested_started_ms: String(requestedStartedAtMs) };
    var requestedLanguage = dictationRequestedLanguageParam();
    if (requestedLanguage) {
      startPayload.language = requestedLanguage;
    }
    return apiPost("dictate_start", startPayload, { timeoutMs: 30000 })
      .then(function (response) {
        if (!response.success) {
          throw new Error(response.error || "Dictation failed");
        }
        state.dictateRecording = true;
        state.dictateSessionId = trim(String((response.session && response.session.id) || ""));
        registerDictationCaptureForSession(state.dictateSessionId, captureContext);
        state.dictateStartedAt = Date.now();
        state.dictateElapsedMs = 0;
        setDictationPhase("recording");
    if (opts.fromHotkey && opts.holdShortcut && !state.dictateHotkeyHoldIntent) {
          stopAfterStart = true;
        }
        return true;
      })
      .catch(function (error) {
        setDictationPhase("idle");
        clearDictationTargetContext();
        throw error;
      })
      .finally(function () {
        state.dictateBusy = false;
        renderUi();
      })
      .then(function (started) {
        if (!started) {
          return false;
        }
        if (!stopAfterStart) {
          return true;
        }
        return stopDictationCapture({ fromHotkey: true, silentNoSpeech: true })
          .then(function () {
            return false;
          })
          .catch(function () {
            return false;
          });
      });
  }

  function stopDictationCapture(options) {
    if (state.dictateBusy || !state.dictateRecording || !el.runPrompt) {
      return Promise.resolve(false);
    }
    var activeSessionId = trim(String(state.dictateSessionId || ""));
    var captureContext = dictationCaptureContextForSession(activeSessionId);
    state.dictateBusy = true;
    state.dictateRecording = false;
    setDictationPhase("processing");
    renderUi();
    return apiPost("dictate_stop", { session_id: activeSessionId }, { timeoutMs: 220000 })
      .then(function (response) {
        if (!response.success) {
          var responseError = trim(String(response.error || "Dictation failed"));
          if (responseError.toLowerCase() === "no speech detected") {
            return true;
          }
          throw new Error(responseError || "Dictation failed");
        }
        var dictatedText = trim(String(response.text || ""));
        if (!dictatedText) {
          return true;
        }
        if (!applyDictationTextToCapturedTarget(dictatedText, captureContext)) {
          throw new Error("Dictation text captured, but original conversation target is unavailable. No text was inserted into the current thread.");
        }
        return true;
      })
      .finally(function () {
        state.dictateBusy = false;
        clearDictationCaptureContextForSession(activeSessionId);
        state.dictateSessionId = "";
        clearDictationTargetContext();
        setDictationPhase("idle");
        renderUi();
        requestDictationPrepare({ silent: true }).catch(function () {
          return null;
        });
        if (dictationPrepareLoopShouldRun()) {
          startDictationPrepareLoop();
        }
      });
  }

  function toggleDictationCapture(options) {
    if (state.dictateRecording) {
      return stopDictationCapture(options);
    }
    return startDictationCapture(options);
  }

  function beginDictationHotkeyHold(trigger, startedAtMs) {
    if (!dictationHotkeysEnabled()) {
      return;
    }
    if (state.dictateHotkeyHoldIntent && state.dictateHotkeyHoldTrigger === trigger) {
      return;
    }
    state.dictateHotkeyHoldIntent = true;
    state.dictateHotkeyHoldTrigger = String(trigger || "");
    if (state.dictateRecording) {
      return;
    }
    startDictationCapture({ fromHotkey: true, holdShortcut: true, startedAtMs: startedAtMs }).then(function (started) {
      if (started) {
        state.dictateHotkeyHoldActive = true;
      }
      if (!state.dictateHotkeyHoldIntent && state.dictateHotkeyHoldActive) {
        stopDictationCapture({ fromHotkey: true, silentNoSpeech: true }).catch(function () {
          return null;
        }).finally(function () {
          state.dictateHotkeyHoldActive = false;
          state.dictateHotkeyHoldTrigger = "";
        });
      }
    }).catch(showError);
  }

  function endDictationHotkeyHold(trigger) {
    var triggerName = String(trigger || "");
    if (state.dictateHotkeyHoldTrigger && triggerName && state.dictateHotkeyHoldTrigger !== triggerName) {
      return;
    }
    state.dictateHotkeyHoldIntent = false;
    if (!state.dictateHotkeyHoldActive) {
      return;
    }
    state.dictateHotkeyHoldActive = false;
    state.dictateHotkeyHoldTrigger = "";
    stopDictationCapture({ fromHotkey: true, silentNoSpeech: true }).catch(showError);
  }

  function shouldHandleDictationShortcutTrigger(trigger) {
    if (!dictationHotkeysEnabled()) {
      return false;
    }
    if (!trigger || trigger === "none") {
      return false;
    }
    var holdTrigger = normalizeDictationShortcut("hold", state.dictationShortcutHold);
    var toggleTrigger = normalizeDictationShortcut("toggle", state.dictationShortcutToggle);
    return trigger === holdTrigger || trigger === toggleTrigger;
  }

  function onDictationShortcutDown(trigger, event) {
    if (!shouldHandleDictationShortcutTrigger(trigger)) {
      return;
    }
    var holdTrigger = normalizeDictationShortcut("hold", state.dictationShortcutHold);
    var toggleTrigger = normalizeDictationShortcut("toggle", state.dictationShortcutToggle);
    var bothSame = holdTrigger !== "none" && holdTrigger === toggleTrigger;
    if (bothSame && trigger === holdTrigger) {
      if (dictationShortcutPressState[trigger]) {
        return;
      }
      var pressState = {
        downAt: Date.now(),
        holdStarted: false,
        timer: null
      };
      pressState.timer = setTimeout(function () {
        pressState.holdStarted = true;
        beginDictationHotkeyHold(trigger, pressState.downAt);
      }, DICTATION_SHORTCUT_TAP_MS);
      dictationShortcutPressState[trigger] = pressState;
      if (event && typeof event.preventDefault === "function") {
        event.preventDefault();
      }
      if (event && typeof event.stopPropagation === "function") {
        event.stopPropagation();
      }
      return;
    }
    if (trigger === holdTrigger) {
      beginDictationHotkeyHold(trigger, Date.now());
      if (event && typeof event.preventDefault === "function") {
        event.preventDefault();
      }
      if (event && typeof event.stopPropagation === "function") {
        event.stopPropagation();
      }
      return;
    }
    if (trigger === toggleTrigger) {
      var existingPress = dictationShortcutPressState[trigger] || null;
      var isKeyboardEvent = !!(event && String(event.type || "").indexOf("key") === 0);
      if (existingPress) {
        var sinceDown = Date.now() - Number(existingPress.downAt || 0);
        if (isKeyboardEvent && event && event.repeat) {
          if (event && typeof event.preventDefault === "function") {
            event.preventDefault();
          }
          if (event && typeof event.stopPropagation === "function") {
            event.stopPropagation();
          }
          return;
        }
        if (!isKeyboardEvent) {
          if (sinceDown < 110) {
            return;
          }
          if (existingPress.timer) {
            clearTimeout(existingPress.timer);
          }
          delete dictationShortcutPressState[trigger];
        } else if (sinceDown < 110) {
          return;
        } else {
          // Recover if keyup was never observed (Caps Lock and some lock/media keys).
          if (existingPress.timer) {
            clearTimeout(existingPress.timer);
          }
          delete dictationShortcutPressState[trigger];
        }
      }
      var togglePressState = {
        downAt: Date.now(),
        holdStarted: false,
        timer: null
      };
      if (!isKeyboardEvent) {
        // Some side-button drivers do not emit mouseup reliably in WebView.
        // Auto-clear to avoid getting stuck after a single trigger.
        togglePressState.timer = setTimeout(function () {
          delete dictationShortcutPressState[trigger];
        }, 420);
      }
      dictationShortcutPressState[trigger] = togglePressState;
      toggleDictationCapture({ fromHotkey: true, holdShortcut: false, startedAtMs: Date.now() }).catch(showError);
      markDictationToggleTriggered(trigger);
      if (isKeyboardEvent) {
        delete dictationShortcutPressState[trigger];
      }
      if (event && typeof event.preventDefault === "function") {
        event.preventDefault();
      }
      if (event && typeof event.stopPropagation === "function") {
        event.stopPropagation();
      }
    }
  }

  function onDictationShortcutUp(trigger, event) {
    if (!trigger) {
      return;
    }
    var holdTrigger = normalizeDictationShortcut("hold", state.dictationShortcutHold);
    var toggleTrigger = normalizeDictationShortcut("toggle", state.dictationShortcutToggle);
    var bothSame = holdTrigger !== "none" && holdTrigger === toggleTrigger;
    var pressState = dictationShortcutPressState[trigger] || null;
    if (bothSame && trigger === holdTrigger) {
      if (pressState && pressState.timer) {
        clearTimeout(pressState.timer);
      }
      var elapsed = pressState ? Date.now() - Number(pressState.downAt || 0) : 0;
      var holdStarted = !!(pressState && pressState.holdStarted);
      delete dictationShortcutPressState[trigger];
      if (holdStarted) {
        endDictationHotkeyHold(trigger);
      } else if (elapsed <= DICTATION_SHORTCUT_TAP_MS) {
        toggleDictationCapture({ fromHotkey: true, holdShortcut: false, startedAtMs: Number(pressState.downAt || Date.now()) }).catch(showError);
        markDictationToggleTriggered(trigger);
      }
      if (event && typeof event.preventDefault === "function") {
        event.preventDefault();
      }
      if (event && typeof event.stopPropagation === "function") {
        event.stopPropagation();
      }
      return;
    }
    var isKeyboardEvent = !!(event && String(event.type || "").indexOf("key") === 0);
    if (
      isKeyboardEvent &&
      trigger === "capslock" &&
      trigger === toggleTrigger &&
      !dictationToggleTriggerHandledRecently(trigger, 170)
    ) {
      toggleDictationCapture({ fromHotkey: true, holdShortcut: false, startedAtMs: Date.now() }).catch(showError);
      markDictationToggleTriggered(trigger);
      if (event && typeof event.preventDefault === "function") {
        event.preventDefault();
      }
      if (event && typeof event.stopPropagation === "function") {
        event.stopPropagation();
      }
      return;
    }
    if (trigger === holdTrigger) {
      endDictationHotkeyHold(trigger);
      if (event && typeof event.preventDefault === "function") {
        event.preventDefault();
      }
      if (event && typeof event.stopPropagation === "function") {
        event.stopPropagation();
      }
      return;
    }
    if (trigger === toggleTrigger && pressState) {
      if (pressState.timer) {
        clearTimeout(pressState.timer);
      }
      delete dictationShortcutPressState[trigger];
      if (event && typeof event.preventDefault === "function") {
        event.preventDefault();
      }
      if (event && typeof event.stopPropagation === "function") {
        event.stopPropagation();
      }
    }
  }

  function onDictateClick(event) {
    var startedAtMs = arguments.length > 1 ? arguments[1] : Date.now();
    if (event && typeof event.preventDefault === "function") {
      event.preventDefault();
    }
    if (state.dictateBusy) {
      showTransientNotice("Finishing dictation...");
      return Promise.resolve();
    }
    if (!state.dictationInstalled) {
      showTransientNotice("Install dictation in Settings first.");
      return Promise.resolve();
    }
    return toggleDictationCapture({ fromHotkey: false, startedAtMs: startedAtMs });
  }

  function onRunSubmit(event) {
    event.preventDefault();

    var composerKey = activeOutgoingKey();
    var rawPrompt = String(el.runPrompt.value || "");
    var directive = parsePromptModeDirective(rawPrompt);
    if (directive.mode) {
      saveRunMode(directive.mode);
      showTransientNotice("Run mode: " + runModeLabel(directive.mode));
    }
    var prompt = trim(directive.prompt || rawPrompt);
    var queuedRunMode = normalizeRunMode(directive.mode || state.runMode);
    var queuedAssistantMode = queuedRunMode === "assistant" ? normalizeAssistantModeId(state.assistantModeId) : "";
    var queuedComputeBudget = normalizeComputeBudget(state.computeBudget);
    var queuedExplicitSkillIds = Array.isArray(directive.skillIds) ? directive.skillIds : [];
    if (queuedExplicitSkillIds.length) {
      showTransientNotice("Skills: " + queuedExplicitSkillIds.join(", "));
    }
    if (!prompt) {
      if (directive.mode) {
        el.runPrompt.value = "";
        setComposerDraftForKey(composerKey, "");
        if (state.activeDraftWorkspaceId) {
          state.draftTextByWorkspace[state.activeDraftWorkspaceId] = "";
        }
        clearDraftAutosaveTimer();
        renderUi();
      }
      return;
    }

    if (!state.activeWorkspaceId && state.activeConversationId) {
      var resolvedWorkspaceId = findWorkspaceIdForConversation(state.activeConversationId);
      if (resolvedWorkspaceId) {
        state.activeWorkspaceId = resolvedWorkspaceId;
      }
    }

    if (!state.activeConversationId && !state.activeDraftWorkspaceId && state.activeWorkspaceId) {
      state.activeDraftWorkspaceId = state.activeWorkspaceId;
    }

    var queuedPrompt = directive.mode ? trim(rawPrompt) : prompt;
    var pendingKey = activeOutgoingKey();
    var submitOriginKey = String(pendingKey || "");
    var submitWorkspaceId = String(state.activeWorkspaceId || "");
    var submitConversationId = String(state.activeConversationId || "");
    var submitDraftWorkspaceId = String(state.activeDraftWorkspaceId || "");
    var clearWorkspaceId = String(state.activeWorkspaceId || "");
    var clearConversationId = String(state.activeConversationId || "");
    var clearDraftWorkspaceId = String(state.activeDraftWorkspaceId || "");
    var clearPersistPromise = clearPersistedComposerDraft(
      clearWorkspaceId,
      clearConversationId,
      clearDraftWorkspaceId
    ).catch(function () {
      return null;
    });
    var pendingId = addPendingOutgoing(pendingKey, queuedPrompt);
    el.runPrompt.value = "";
    setComposerDraftForKey(pendingKey, "");
    if (state.activeDraftWorkspaceId) {
      state.draftTextByWorkspace[state.activeDraftWorkspaceId] = "";
    }
    renderUi();

    clearDraftAutosaveTimer();

    var queueSubmissionAccepted = false;
    var lastPendingKey = String(pendingKey || "");

    ensureConversationFromDraft(queuedPrompt, {
      draftWorkspaceId: submitDraftWorkspaceId,
      conversationId: submitConversationId
    })
      .then(function (conversationId) {
        var workspaceId = submitDraftWorkspaceId || submitWorkspaceId || String(state.activeWorkspaceId || "");
        if (!workspaceId || !conversationId) {
          throw new Error("Choose a project thread first.");
        }
        markConversationActivity(workspaceId, conversationId);
        var conversationKey = outgoingKeyFor(workspaceId, conversationId, "");
        movePendingOutgoing(pendingKey, conversationKey, pendingId);
        pendingKey = conversationKey;
        lastPendingKey = String(pendingKey || "");
        return uploadPendingAttachments(workspaceId, conversationId).then(function (uploadedAttachments) {
          var attachmentIds = [];
          for (var i = 0; i < uploadedAttachments.length; i += 1) {
            if (uploadedAttachments[i] && uploadedAttachments[i].id) {
              attachmentIds.push(String(uploadedAttachments[i].id));
            }
          }
          return enqueuePromptInConversationOrder(
            workspaceId,
            conversationId,
            queuedPrompt,
            "tail",
            attachmentIds,
            queuedRunMode,
            queuedAssistantMode,
            queuedComputeBudget,
            queuedExplicitSkillIds,
            state.permissionMode,
            state.commandExecMode,
            state.programmerReviewEnabled,
            state.programmerReviewRounds
          ).then(function () {
            queueSubmissionAccepted = true;
            resetComposerAttachments();
            // Start draining immediately; do not wait on follow-up UI fetches.
            kickQueueWorker();
          });
        }).then(function () {
          var userStayedOnOrigin = submitOriginKey && activeOutgoingKey() === submitOriginKey;
          if (!userStayedOnOrigin) {
            return null;
          }
          state.activeWorkspaceId = workspaceId;
          state.activeConversationId = conversationId;
          state.activeDraftWorkspaceId = "";
          state.activeConversationLoadError = "";
          syncSelectionUrl(false);
          return loadConversation().catch(function () {
            return null;
          });
        });
      })
      .then(function () {
        renderUi();
      })
      .catch(function (err) {
        removePendingOutgoing(pendingKey, pendingId);
        if (!queueSubmissionAccepted) {
          var restoreKeys = [String(lastPendingKey || pendingKey || "")];
          if (submitOriginKey && submitOriginKey !== restoreKeys[0]) {
            restoreKeys.push(submitOriginKey);
          }
          if (submitDraftWorkspaceId) {
            var submitDraftKey = outgoingKeyFor("", "", submitDraftWorkspaceId);
            if (submitDraftKey && restoreKeys.indexOf(submitDraftKey) < 0) {
              restoreKeys.push(submitDraftKey);
            }
            state.draftTextByWorkspace[submitDraftWorkspaceId] = queuedPrompt;
          }
          for (var rk = 0; rk < restoreKeys.length; rk += 1) {
            if (restoreKeys[rk]) {
              setComposerDraftForKey(restoreKeys[rk], queuedPrompt);
            }
          }
          var activeKeyNow = String(activeOutgoingKey() || "");
          var shouldRestoreVisiblePrompt = activeKeyNow && restoreKeys.indexOf(activeKeyNow) >= 0;
          if (shouldRestoreVisiblePrompt && !trim(String(el.runPrompt.value || ""))) {
            el.runPrompt.value = queuedPrompt;
          }
          var persistRestoredDraft = function () {
            return persistComposerDraftForKeys(restoreKeys, queuedPrompt).then(function () {
              if (!submitDraftWorkspaceId) {
                return null;
              }
              return saveDraft(submitDraftWorkspaceId, queuedPrompt).catch(function () {
                return null;
              });
            });
          };
          // Write immediately for responsive UX, then re-apply after clear settles
          // so late clear persistence cannot clobber restored content.
          persistRestoredDraft().catch(function () {
            return null;
          });
          clearPersistPromise.then(persistRestoredDraft).catch(function () {
            return null;
          });
        } else {
          kickQueueWorker();
        }
        showError(err);
      })
      .finally(function () {
        renderUi();
      });
  }

  function runningConversationTarget() {
    var workspaceId = trim(state.runningWorkspaceId || "");
    var conversationId = trim(state.runningConversationId || "");
    if (workspaceId && conversationId) {
      return {
        workspaceId: workspaceId,
        conversationId: conversationId
      };
    }
    workspaceId = trim(state.activeWorkspaceId || "");
    conversationId = trim(state.activeConversationId || "");
    if (!workspaceId || !conversationId) {
      return null;
    }
    var activeStats = activeConversationQueueStats();
    if (!activeStats || !activeStats.running) {
      return null;
    }
    return {
      workspaceId: workspaceId,
      conversationId: conversationId
    };
  }

  function stopRunFromComposer() {
    var target = runningConversationTarget();
    if (!target) {
      return Promise.reject(new Error("No active run to stop."));
    }
    return stopConversationRun(target.workspaceId, target.conversationId);
  }

  function onCommitContinue() {
    if (!state.activeWorkspaceId) {
      return Promise.reject(new Error("Select a project first."));
    }

    var includeUnstaged = el.commitIncludeUnstaged.checked ? "1" : "0";
    var message = el.commitMessage.value;
    var nextStep = el.commitNextStep.value === "commit-push" ? "1" : "0";

    return apiPost("git_commit", {
      workspace_id: state.activeWorkspaceId,
      include_unstaged: includeUnstaged,
      message: message,
      push: nextStep
    })
      .then(function (response) {
        if (!response.success) {
          throw new Error(response.error || "Commit failed");
        }
        appendTerminalLine(response.output || "Commit complete.");
        closeModal(el.commitModal);
        return refreshGitStatus();
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
      });
  }

  function openDiffPanel() {
    state.diffOpen = true;
    return refreshDiff().then(function () {
      renderUi();
    });
  }

  function closeDiffPanel() {
    state.diffOpen = false;
    renderUi();
    return Promise.resolve();
  }

  function toggleDiffPanel() {
    if (state.diffOpen) {
      return closeDiffPanel();
    } else {
      return openDiffPanel();
    }
  }

  function focusElementNoScroll(node) {
    if (!node || typeof node.focus !== "function") {
      return;
    }
    try {
      node.focus({ preventScroll: true });
    } catch (_focusError) {
      node.focus();
    }
  }

  function openTerminal() {
    state.terminalOpen = true;
    if (state.activeWorkspaceId) {
      var ws = getWorkspaceById(state.activeWorkspaceId);
      state.terminalCwd = ws ? ws.path : "";
    }
    renderUi();
    ensureTerminalSession().then(function () {
      return pollTerminalSessionOnce();
    }).catch(showError);
    setTimeout(function () {
      if (state.terminalOpen && el.terminalOutput) {
        focusElementNoScroll(el.terminalOutput);
      }
    }, 210);
  }

  function closeTerminal() {
    if (
      document &&
      document.activeElement &&
      el.terminalPanel &&
      el.terminalPanel.contains(document.activeElement) &&
      typeof document.activeElement.blur === "function"
    ) {
      document.activeElement.blur();
    }
    var wsId = String(state.terminalSessionWorkspaceId || state.activeWorkspaceId || "");
    var sessionId = String(state.terminalSessionId || "");
    stopTerminalPolling();
    if (wsId && sessionId) {
      apiPost("terminal_session_stop", {
        workspace_id: wsId,
        session_id: sessionId
      }, { timeoutMs: 5000 }).catch(function () {
        return null;
      });
    }
    state.terminalOpen = false;
    state.terminalSessionId = "";
    state.terminalSessionWorkspaceId = "";
    state.terminalStreamText = "";
    state.terminalStreamOffset = 0;
    state.terminalInputBuffer = "";
    renderUi();
  }

  function toggleTerminal() {
    if (state.terminalOpen) {
      closeTerminal();
    } else {
      openTerminal();
    }
  }

  function bindEvents() {
    function on(node, eventName, handler) {
      if (!node || typeof node.addEventListener !== "function") {
        return;
      }
      node.addEventListener(eventName, handler);
    }

    if (el.attachmentPicker) {
      el.attachmentPicker.setAttribute("accept", attachmentAcceptValue);
    }

    on(el.workspaceTree, "click", function (event) {
      handleWorkspaceTreeClick(event);
    });
    on(el.workspaceTree, "change", function (event) {
      handleWorkspaceTreeChange(event);
    });
    on(el.workspaceTree, "keydown", function (event) {
      handleWorkspaceTreeKeydown(event);
    });
    on(el.workspaceTree, "dragstart", function (event) {
      onWorkspaceTreeDragStart(event);
    });
    on(el.workspaceTree, "dragover", function (event) {
      onWorkspaceTreeDragOver(event);
    });
    on(el.workspaceTree, "drop", function (event) {
      onWorkspaceTreeDrop(event);
    });
    on(el.workspaceTree, "dragend", function () {
      onWorkspaceTreeDragEnd();
    });

    on(el.addWorkspaceBtn, "click", function () {
      openModal(el.workspaceModal);
      setTimeout(function () {
        el.workspaceBrowseBtn.focus();
      }, 0);
    });

    on(el.sidebarNavAutomationsItem, "click", function (event) {
      event.preventDefault();
      saveSidebarSection("automations");
      renderUi();
    });

    on(el.sidebarNavAutomationsItem, "keydown", function (event) {
      if (!event || (event.key !== "Enter" && event.key !== " ")) {
        return;
      }
      event.preventDefault();
      saveSidebarSection("automations");
      renderUi();
    });

    on(el.organizeBtn, "click", function (event) {
      event.preventDefault();
      event.stopPropagation();
      toggleMenu("organize-menu", el.organizeBtn);
    });

    on(el.organizeMenu, "click", function (event) {
      var button = event.target.closest("button[data-organize-mode], button[data-organize-sort], button[data-organize-show]");
      if (!button) {
        return;
      }
      var modeValue = button.getAttribute("data-organize-mode");
      var sortValue = button.getAttribute("data-organize-sort");
      var showValue = button.getAttribute("data-organize-show");
      if (modeValue) {
        saveOrganizeMode(modeValue);
      } else if (sortValue) {
        saveSortMode(sortValue);
      } else if (showValue) {
        saveOrganizeShow(showValue);
      }
      closeAllMenus();
      renderUi();
    });

    on(el.automationModalClose, "click", function () {
      closeAutomationModal();
      renderUi();
    });

    on(el.automationCancelBtn, "click", function () {
      closeAutomationModal();
      renderUi();
    });

    on(el.automationWorkspace, "change", function () {
      var workspaceId = trim(String(el.automationWorkspace.value || ""));
      populateAutomationConversationOptions(workspaceId, "");
      if (el.automationSaveBtn) {
        el.automationSaveBtn.disabled = !workspaceId;
      }
    });

    on(el.automationScheduleKind, "change", function () {
      renderAutomationScheduleHint();
    });

    on(el.automationForm, "submit", function (event) {
      event.preventDefault();
      runWithControlPending(el.automationSaveBtn || event.target, function () {
        return saveAutomationFromModal();
      }).catch(showError);
    });

    on(el.modelStatusBtn, "click", function (event) {
      event.preventDefault();
      event.stopPropagation();
      toggleMenu("models-pane", el.modelStatusBtn);
      if (!el.modelsPane || el.modelsPane.classList.contains("hidden")) {
        return;
      }
      runWithControlPending(el.modelStatusBtn, function () {
        return refreshModelData({ force: true, silent: false })
          .then(function () {
            return null;
          })
          .catch(function () {
            renderUi();
          });
      }, { spinner: false }).catch(function () {
        return null;
      });
    });

    on(el.themePickerBtn, "click", function (event) {
      event.preventDefault();
      event.stopPropagation();
      toggleMenu("theme-picker-menu", el.themePickerBtn);
    });

    on(el.themePickerBtn, "keydown", function (event) {
      if (event.key !== "ArrowUp" && event.key !== "ArrowDown") {
        return;
      }
      event.preventDefault();
      closeAllMenus();
      cycleTheme(event.key === "ArrowUp" ? -1 : 1);
    });

    on(el.themePickerList, "click", function (event) {
      var button = event.target.closest("button[data-theme-name]");
      if (!button) {
        return;
      }
      var themeName = button.getAttribute("data-theme-name");
      applyTheme(themeName);
      closeAllMenus();
      renderThemePicker();
      if (el.themePickerBtn) {
        el.themePickerBtn.focus();
      }
    });

    on(el.modelsBoxList, "click", function (event) {
      var uninstallBtn = event.target.closest("button[data-action='uninstall-model'][data-model-name]");
      if (uninstallBtn) {
        var uninstallModel = uninstallBtn.getAttribute("data-model-name");
        if (!window.confirm("Are you sure you want to uninstall " + uninstallModel + "?")) {
          return;
        }
        runWithControlPending(uninstallBtn, function () {
          return startModelUninstall(uninstallModel);
        }).catch(showError);
        return;
      }
      var installBtn = event.target.closest("button[data-action='install-model'][data-model-name]");
      if (installBtn) {
        var installModel = installBtn.getAttribute("data-model-name");
        runWithControlPending(installBtn, function () {
          return startModelInstall(installModel);
        }).catch(showError);
        return;
      }
      var button = event.target.closest("button[data-model-name]");
      if (!button) {
        return;
      }
      var modelName = button.getAttribute("data-model-name");
      runWithControlPending(button, function () {
        return applyModelSelection(modelName).then(function () {
          closeAllMenus();
          renderUi();
        });
      }).catch(showError);
    });

    on(el.modelPickerBtn, "click", function (event) {
      event.preventDefault();
      event.stopPropagation();
      toggleMenu("model-picker-menu", el.modelPickerBtn);
    });

    on(el.modelPickerList, "click", function (event) {
      var button = event.target.closest("button[data-model-name]");
      if (!button) {
        return;
      }
      var modelName = button.getAttribute("data-model-name");
      runWithControlPending(button, function () {
        return applyModelSelection(modelName)
          .then(function () {
            closeAllMenus();
            renderUi();
          });
      }).catch(showError);
    });

    on(el.runModeBtn, "click", function (event) {
      event.preventDefault();
      event.stopPropagation();
      toggleMenu("run-mode-menu", el.runModeBtn);
    });

    on(el.runModeMenu, "click", function (event) {
      var moreToggle = event.target.closest("button[data-action='run-mode-more-toggle']");
      if (moreToggle) {
        state.runModeMoreExpanded = !state.runModeMoreExpanded;
        renderUi();
        return;
      }
      var assistantModeItem = event.target.closest("button[data-assistant-mode-id]");
      if (assistantModeItem) {
        saveRunMode("assistant");
        saveAssistantModeId(assistantModeItem.getAttribute("data-assistant-mode-id") || "");
        state.runModeMoreExpanded = false;
        closeAllMenus();
        renderUi();
        return;
      }
      var item = event.target.closest("button[data-run-mode]");
      if (!item) {
        return;
      }
      var nextMode = normalizeRunMode(item.getAttribute("data-run-mode"));
      saveRunMode(nextMode);
      if (nextMode === "assistant") {
        state.runModeMoreExpanded = true;
        renderUi();
        return;
      }
      if (nextMode !== "assistant") {
        state.runModeMoreExpanded = false;
      }
      closeAllMenus();
      renderUi();
    });

    on(el.agentLoopToggle, "click", function () {
      saveAgentLoopEnabled(!state.agentLoopEnabled);
      renderUi();
    });

    on(el.reasoningMenuBtn, "click", function (event) {
      event.preventDefault();
      event.stopPropagation();
      toggleMenu("reasoning-menu", el.reasoningMenuBtn);
    });

    on(el.reasoningMenu, "click", function (event) {
      var item = event.target.closest("button[data-reasoning]");
      if (!item) {
        return;
      }
      saveReasoningEffort(item.getAttribute("data-reasoning"));
      closeAllMenus();
      renderUi();
    });

    on(el.computeMenuBtn, "click", function (event) {
      event.preventDefault();
      event.stopPropagation();
      toggleMenu("compute-menu", el.computeMenuBtn);
    });

    on(el.computeMenu, "click", function (event) {
      var item = event.target.closest("button[data-compute-budget]");
      if (!item) {
        return;
      }
      saveComputeBudget(item.getAttribute("data-compute-budget"));
      closeAllMenus();
      renderUi();
    });

    on(el.workspaceModalClose, "click", function () {
      closeModal(el.workspaceModal);
    });

    on(el.workspaceCancelBtn, "click", function () {
      closeModal(el.workspaceModal);
    });

    on(el.workspaceModal, "click", function (event) {
      if (event.target === el.workspaceModal && !state.pickingWorkspace) {
        closeModal(el.workspaceModal);
      }
    });

    on(el.workspaceForm, "submit", function (event) {
      event.preventDefault();
      var submitter = event.submitter || (el.workspaceForm && el.workspaceForm.querySelector("button[type='submit']"));
      runWithControlPending(submitter, function () {
        return onWorkspaceModalSubmit(event);
      }).catch(showError);
    });

    on(el.workspaceBrowseBtn, "click", function () {
      runWithControlPending(el.workspaceBrowseBtn, function () {
        return onWorkspaceBrowseClick();
      }).catch(showError);
    });

    on(el.workspacePath, "input", function () {
      updateWorkspaceNamePlaceholderFromPath(el.workspacePath.value);
    });

    on(el.workspaceDirPicker, "change", function (event) {
      onWorkspaceDirPicked(event).catch(showError);
    });

    window.addEventListener("focus", function () {
      if (state.awaitingDirPicker) {
        window.setTimeout(function () {
          if (!state.awaitingDirPicker) {
            return;
          }
          state.awaitingDirPicker = false;
          state.pickingWorkspace = false;
        }, 0);
      }
      if (state.initialLoadComplete) {
        refreshModelData({ force: true, silent: true }).then(function (updated) {
          if (updated) {
            renderUi();
          }
        }).catch(function () {
          return null;
        });
      }
    });

    window.addEventListener("popstate", function () {
      navigateToRouteSelection().catch(showError);
    });

    window.addEventListener("mousemove", function (event) {
      onPaneDragMove(event);
    });

    window.addEventListener("mouseup", function () {
      stopPaneDrag();
    });

    window.addEventListener("blur", function () {
      stopPaneDrag();
    });

    window.addEventListener("resize", function () {
      applyPaneWidths();
      updateToolbarCompaction();
    });

    document.addEventListener("mouseover", function (event) {
      var target = event.target.closest("[data-tooltip]");
      if (!target) {
        hideTooltip();
        return;
      }
      scheduleTooltipFor(target);
    });

    document.addEventListener("focusin", function (event) {
      var target = event.target.closest("[data-tooltip]");
      if (!target) {
        hideTooltip();
        return;
      }
      scheduleTooltipFor(target);
    });

    document.addEventListener("mousemove", function (event) {
      if (!tooltipTarget || !tooltipEl || tooltipEl.getAttribute("aria-hidden") === "true") {
        return;
      }
      positionTooltip(tooltipTarget);
      if (!tooltipTarget.contains(event.target) && event.target !== tooltipTarget) {
        hideTooltip();
      }
    });

    document.addEventListener("mouseout", function (event) {
      if (!tooltipTarget) {
        return;
      }
      if (tooltipTarget.contains(event.relatedTarget)) {
        return;
      }
      hideTooltip();
    });

    document.addEventListener("focusout", function (event) {
      if (!tooltipTarget) {
        return;
      }
      if (tooltipTarget.contains(event.relatedTarget)) {
        return;
      }
      hideTooltip();
    });

    on(el.workspacePanel, "dragenter", function (event) {
      event.preventDefault();
      setWorkspaceDropActive(true);
    });

    on(el.workspacePanel, "dragover", function (event) {
      event.preventDefault();
      setWorkspaceDropActive(true);
    });

    on(el.workspacePanel, "dragleave", function (event) {
      if (!el.workspacePanel.contains(event.relatedTarget)) {
        setWorkspaceDropActive(false);
      }
    });

    on(el.workspacePanel, "drop", function (event) {
      runWithControlPending(el.workspacePanel, function () {
        return onWorkspaceDropped(event);
      }, { spinner: false }).catch(showError);
    });

    if (el.threadsResizer) {
      on(el.threadsResizer, "mousedown", function (event) {
        startPaneDrag("threads", event);
      });
    }

    if (el.diffResizer) {
      on(el.diffResizer, "mousedown", function (event) {
        startPaneDrag("diff", event);
      });
    }

    if (el.modelsPaneResizer) {
      on(el.modelsPaneResizer, "mousedown", function (event) {
        if (!el.modelsPane || el.modelsPane.classList.contains("hidden")) {
          return;
        }
        startPaneDrag("models", event);
      });
    }

    on(el.openMainBtn, "click", function () {
      runWithControlPending(el.openMainBtn, function () {
        return performOpenTarget(state.lastOpenTarget);
      }).catch(showError);
    });

    if (el.workspacePathWidget) {
      on(el.workspacePathWidget, "click", function (event) {
        var ws = activeWorkspace();
        if (!ws || !ws.path) {
          return;
        }
        if (event && Number(event.detail || 0) >= 2) {
          if (pathWidgetClickTimer) {
            clearTimeout(pathWidgetClickTimer);
            pathWidgetClickTimer = null;
          }
          runWithControlPending(el.workspacePathWidget, function () {
            return performOpenTarget("finder");
          }, { spinner: false }).catch(showError);
          return;
        }
        if (pathWidgetClickTimer) {
          clearTimeout(pathWidgetClickTimer);
          pathWidgetClickTimer = null;
        }
        pathWidgetClickTimer = setTimeout(function () {
          pathWidgetClickTimer = null;
          copyTextToClipboard(ws.path).then(function (ok) {
            if (!ok) {
              throw new Error("Could not copy path.");
            }
            showTransientNotice("Path copied");
          }).catch(function (error) {
            showError(error);
          });
        }, 220);
      });

      on(el.workspacePathWidget, "dblclick", function (event) {
        event.preventDefault();
        if (pathWidgetClickTimer) {
          clearTimeout(pathWidgetClickTimer);
          pathWidgetClickTimer = null;
        }
        runWithControlPending(el.workspacePathWidget, function () {
          return performOpenTarget("finder");
        }, { spinner: false }).catch(showError);
      });
    }

    on(el.openMenuBtn, "click", function (event) {
      event.preventDefault();
      event.stopPropagation();
      toggleMenu("open-menu", el.openMenuBtn);
    });

    on(el.openMenu, "click", function (event) {
      var item = event.target.closest("button[data-open-target]");
      if (!item || !state.activeWorkspaceId) {
        return;
      }
      var target = item.getAttribute("data-open-target");
      runWithControlPending(item, function () {
        return performOpenTarget(target);
      }).catch(showError);
    });

    if (el.triageCleanupMainBtn) {
      on(el.triageCleanupMainBtn, "click", function (event) {
        handleWorkspaceTreeClick(event);
      });
    }

    if (el.triageCleanupMenuBtn) {
      on(el.triageCleanupMenuBtn, "click", function (event) {
        event.preventDefault();
        event.stopPropagation();
        toggleMenu("triage-cleanup-menu", el.triageCleanupMenuBtn);
      });
    }

    if (el.triageCleanupMenu) {
      on(el.triageCleanupMenu, "click", function (event) {
        var cleanupItem = event.target.closest("button[data-action^='triage-cleanup']");
        if (!cleanupItem) {
          return;
        }
        handleWorkspaceTreeClick(event);
      });
    }

    on(el.branchMenuBtn, "click", function (event) {
      event.preventDefault();
      event.stopPropagation();
      if (!state.activeWorkspaceId) {
        return;
      }
      var gitState = activeGitState();
      if (!gitState.is_repo) {
        runWithControlPending(el.branchMenuBtn, function () {
          return createRepoForActiveWorkspace();
        }).catch(showError);
        return;
      }
      runWithControlPending(el.branchMenuBtn, function () {
        return refreshBranches().finally(function () {
          renderBranchMenu();
          toggleMenu("branch-menu", el.branchMenuBtn);
        });
      }, { spinner: false }).catch(showError);
    });

    on(el.branchMenuList, "click", function (event) {
      var actionItem = event.target.closest("button[data-branch-action]");
      if (actionItem) {
        var branchAction = actionItem.getAttribute("data-branch-action");
        if (branchAction === "create-repo") {
          runWithControlPending(actionItem, function () {
            return createRepoForActiveWorkspace();
          })
            .then(function () {
              closeAllMenus();
            })
            .catch(showError);
        }
        return;
      }

      var item = event.target.closest("button[data-branch-select]");
      if (!item || !state.activeWorkspaceId) {
        return;
      }
      var branch = item.getAttribute("data-branch-select");
      runWithControlPending(item, function () {
        return apiPost("git_checkout_branch", {
          workspace_id: state.activeWorkspaceId,
          branch: branch,
          create: "0"
        })
          .then(function (response) {
            if (!response.success) {
              throw new Error(response.error || "Branch checkout failed");
            }
            appendTerminalLine(response.output || ("Checked out " + branch));
            return refreshGitStatus();
          })
          .then(function () {
            return refreshBranches();
          })
          .then(function () {
            closeAllMenus();
            renderUi();
          });
      }).catch(showError);
    });

    on(el.branchCreateForm, "submit", function (event) {
      event.preventDefault();
      if (!state.activeWorkspaceId) {
        return;
      }
      var branchName = trim(el.branchCreateInput.value);
      if (!branchName) {
        return;
      }
      var submitter = event.submitter || el.branchCreateSubmit;
      runWithControlPending(submitter, function () {
        return apiPost("git_checkout_branch", {
          workspace_id: state.activeWorkspaceId,
          branch: branchName,
          create: "1"
        })
          .then(function (response) {
            if (!response.success) {
              throw new Error(response.error || "Branch create failed");
            }
            appendTerminalLine(response.output || ("Created branch " + branchName));
            el.branchCreateInput.value = "";
            if (el.branchCreateSubmit) {
              el.branchCreateSubmit.disabled = true;
            }
            return refreshGitStatus();
          })
          .then(function () {
            return refreshBranches();
          })
          .then(function () {
            closeAllMenus();
            renderUi();
          });
      }).catch(showError);
    });

    on(el.branchCreateInput, "input", function () {
      if (!el.branchCreateSubmit) {
        return;
      }
      el.branchCreateSubmit.disabled = trim(el.branchCreateInput.value) === "";
    });

    on(el.commitMainBtn, "click", function () {
      runWithControlPending(el.commitMainBtn, function () {
        return performCommitAction(state.lastCommitAction);
      }, { spinner: false }).catch(showError);
    });

    on(el.commitMenuBtn, "click", function (event) {
      event.preventDefault();
      event.stopPropagation();
      toggleMenu("commit-menu", el.commitMenuBtn);
    });

    on(el.commitMenu, "click", function (event) {
      var item = event.target.closest("button[data-commit-action]");
      if (!item) {
        return;
      }
      var action = item.getAttribute("data-commit-action");
      runWithControlPending(item, function () {
        return performCommitAction(action);
      }, { spinner: false }).catch(showError);
    });

    on(el.commitModalClose, "click", function () {
      closeModal(el.commitModal);
    });

    on(el.commitModal, "click", function (event) {
      if (event.target === el.commitModal) {
        closeModal(el.commitModal);
      }
    });

    on(el.commitContinueBtn, "click", function () {
      runWithControlPending(el.commitContinueBtn, function () {
        return onCommitContinue();
      }).catch(showError);
    });

    on(el.permissionsMenuBtn, "click", function (event) {
      event.preventDefault();
      event.stopPropagation();
      toggleMenu("permissions-menu", el.permissionsMenuBtn);
    });

    on(el.permissionsMenu, "click", function (event) {
      var commandItem = event.target.closest("button[data-command-exec]");
      if (commandItem) {
        var commandMode = commandItem.getAttribute("data-command-exec");
        runWithControlPending(commandItem, function () {
          return setCommandExecMode(commandMode)
            .then(function () {
              closeAllMenus();
              renderUi();
            });
        }).catch(showError);
        return;
      }

      var item = event.target.closest("button[data-permission]");
      if (!item) {
        return;
      }
      var permission = item.getAttribute("data-permission");
      savePermissionMode(permission);
      closeAllMenus();
      renderUi();
    });

    if (el.networkToggleBtn) {
      on(el.networkToggleBtn, "click", function (event) {
        event.preventDefault();
        var enabled = !state.networkAccess;
        saveNetworkAccess(enabled);
        if (!enabled) {
          saveWebAccess(false);
        }
        renderUi();
      });
    }

    if (el.webToggleBtn) {
      on(el.webToggleBtn, "click", function (event) {
        event.preventDefault();
        if (!state.networkAccess) {
          saveNetworkAccess(true);
        }
        saveWebAccess(!state.webAccess);
        renderUi();
      });
    }

    on(el.runActionBtn, "click", function () {
      openModal(el.runActionModal);
      setTimeout(function () {
        el.runActionCommand.focus();
      }, 0);
    });

    on(el.runActionClose, "click", function () {
      closeModal(el.runActionModal);
    });

    on(el.runActionModal, "click", function (event) {
      if (event.target === el.runActionModal) {
        closeModal(el.runActionModal);
      }
    });

    on(el.runActionForm, "submit", function (event) {
      event.preventDefault();
      var commandText = el.runActionCommand.value;
      if (!trim(commandText)) {
        return;
      }
      var submitter = event.submitter || (el.runActionForm && el.runActionForm.querySelector("button[type='submit']"));
      runWithControlPending(submitter, function () {
        openTerminal();
        return runCommandViaApi(commandText, "run_action")
          .then(function () {
            closeModal(el.runActionModal);
            el.runActionCommand.value = "";
          });
      }).catch(showError);
    });

    on(el.settingsBtn, "click", function () {
      runWithControlPending(el.settingsBtn, function () {
        return openSettingsModal();
      }, { spinner: false }).catch(showError);
    });

    on(el.settingsCloseBtn, "click", function () {
      closeModal(el.settingsModal);
    });

    on(el.selfImproveRunBtn, "click", function () {
      runWithControlPending(el.selfImproveRunBtn, function () {
        return runSelfImprove(el.selfImproveModelSelect ? el.selfImproveModelSelect.value : state.selfImproveModel);
      }, { spinner: false }).catch(showError);
    });

    on(el.selfImproveModelSelect, "change", function () {
      state.selfImproveModel = trim(String(el.selfImproveModelSelect.value || ""));
      state.selfImproveError = "";
      renderSelfImproveSettings();
    });

    on(el.selfImproveObjectiveInput, "input", function () {
      state.selfImproveRunOptions = normalizeSelfImproveRunOptions(state.selfImproveRunOptions);
      state.selfImproveRunOptions.objective = trim(String(el.selfImproveObjectiveInput.value || ""));
      state.selfImproveError = "";
      renderSelfImproveSettings();
    });

    on(el.selfImproveObjectiveInput, "blur", function () {
      state.selfImproveRunOptions = normalizeSelfImproveRunOptions(state.selfImproveRunOptions);
      state.selfImproveRunOptions.objective = trim(String(el.selfImproveObjectiveInput.value || ""));
      saveSelfImproveRunOptions(state.selfImproveRunOptions).catch(showError);
    });

    on(el.selfImproveCompetitionToggle, "change", function () {
      state.selfImproveRunOptions = normalizeSelfImproveRunOptions(state.selfImproveRunOptions);
      state.selfImproveRunOptions.competition_enabled = !!el.selfImproveCompetitionToggle.checked;
      if (!state.selfImproveRunOptions.competition_enabled) {
        state.selfImproveRunOptions.challenger_model = "";
      }
      state.selfImproveError = "";
      renderSelfImproveSettings();
      saveSelfImproveRunOptions(state.selfImproveRunOptions).catch(showError);
    });

    on(el.selfImproveChallengerModelSelect, "change", function () {
      state.selfImproveRunOptions = normalizeSelfImproveRunOptions(state.selfImproveRunOptions);
      state.selfImproveRunOptions.challenger_model = trim(String(el.selfImproveChallengerModelSelect.value || ""));
      state.selfImproveError = "";
      renderSelfImproveSettings();
      saveSelfImproveRunOptions(state.selfImproveRunOptions).catch(showError);
    });

    on(el.selfImproveSourcePapers, "change", function () {
      state.selfImproveRunOptions = normalizeSelfImproveRunOptions(state.selfImproveRunOptions);
      state.selfImproveRunOptions.sources.papers = !!el.selfImproveSourcePapers.checked;
      renderSelfImproveSettings();
      saveSelfImproveRunOptions(state.selfImproveRunOptions).catch(showError);
    });

    on(el.selfImproveSourceWeb, "change", function () {
      state.selfImproveRunOptions = normalizeSelfImproveRunOptions(state.selfImproveRunOptions);
      state.selfImproveRunOptions.sources.web = !!el.selfImproveSourceWeb.checked;
      renderSelfImproveSettings();
      saveSelfImproveRunOptions(state.selfImproveRunOptions).catch(showError);
    });

    on(el.selfImproveSourceRuntime, "change", function () {
      state.selfImproveRunOptions = normalizeSelfImproveRunOptions(state.selfImproveRunOptions);
      state.selfImproveRunOptions.sources.runtime = !!el.selfImproveSourceRuntime.checked;
      renderSelfImproveSettings();
      saveSelfImproveRunOptions(state.selfImproveRunOptions).catch(showError);
    });

    on(el.selfImproveSourceRepo, "change", function () {
      state.selfImproveRunOptions = normalizeSelfImproveRunOptions(state.selfImproveRunOptions);
      state.selfImproveRunOptions.sources.repo = !!el.selfImproveSourceRepo.checked;
      renderSelfImproveSettings();
      saveSelfImproveRunOptions(state.selfImproveRunOptions).catch(showError);
    });

    on(el.selfImproveSourcePlatform, "change", function () {
      state.selfImproveRunOptions = normalizeSelfImproveRunOptions(state.selfImproveRunOptions);
      state.selfImproveRunOptions.sources.platform = !!el.selfImproveSourcePlatform.checked;
      renderSelfImproveSettings();
      saveSelfImproveRunOptions(state.selfImproveRunOptions).catch(showError);
    });

    if (el.multi_agentModalClose) {
      on(el.multi_agentModalClose, "click", function () {
        closeModal(el.multi_agentModal);
      });
    }

    if (el.multi_agentCharter) {
      on(el.multi_agentCharter, "input", function () {
        var wsId = trim(String(state.commandRulesWorkspaceId || state.activeWorkspaceId || ""));
        if (!wsId) {
          return;
        }
        scheduleMultiAgentCharterSave(wsId, 700);
      });
      on(el.multi_agentCharter, "blur", function () {
        var wsId = trim(String(state.commandRulesWorkspaceId || state.activeWorkspaceId || ""));
        if (!wsId) {
          return;
        }
        scheduleMultiAgentCharterSave(wsId, 0);
      });
    }

    on(el.settingsModal, "click", function (event) {
      var deleteBtn = event.target && event.target.closest
        ? event.target.closest("button[data-action='delete-command-rule'][data-rule-scope][data-rule-index]")
        : null;
      if (deleteBtn) {
        var wsDeleteId = String(state.commandRulesWorkspaceId || "");
        var deleteScope = deleteBtn.getAttribute("data-rule-scope") || "";
        var deleteIndex = deleteBtn.getAttribute("data-rule-index") || "";
        runWithControlPending(deleteBtn, function () {
          return deleteCommandRule(wsDeleteId, deleteScope, deleteIndex);
        }, { spinner: false }).catch(showError);
        return;
      }
      var clearBtn = event.target && event.target.closest
        ? event.target.closest("button[data-action='clear-command-rules'][data-rule-scope]")
        : null;
      if (clearBtn) {
        var wsClearId = String(state.commandRulesWorkspaceId || "");
        var clearScope = clearBtn.getAttribute("data-rule-scope") || "";
        if (!wsClearId || !clearScope) {
          return;
        }
        var confirmText = clearScope === "remember"
          ? "Clear all remembered approval rules for this project?"
          : "Clear all one-time approval rules for this project?";
        if (!window.confirm(confirmText)) {
          return;
        }
        runWithControlPending(clearBtn, function () {
          return clearCommandRules(wsClearId, clearScope);
        }, { spinner: false }).catch(showError);
        return;
      }
      var selfImproveDeleteBtn = event.target && event.target.closest
        ? event.target.closest("button[data-action='self-improve-plugin-delete'][data-plugin-id]")
        : null;
      if (selfImproveDeleteBtn) {
        var pluginDeleteId = trim(String(selfImproveDeleteBtn.getAttribute("data-plugin-id") || ""));
        if (!pluginDeleteId) {
          return;
        }
        if (!window.confirm("Delete this self-improvement plugin?")) {
          return;
        }
        runWithControlPending(selfImproveDeleteBtn, function () {
          return deleteSelfImprovePlugin(pluginDeleteId);
        }, { spinner: false }).catch(showError);
        return;
      }
      var modeToggleBtn = event.target && event.target.closest
        ? event.target.closest("button[data-action='mode-runtime-toggle'][data-mode-id][data-enabled]")
        : null;
      if (modeToggleBtn) {
        var modeToggleId = modeToggleBtn.getAttribute("data-mode-id") || "";
        var modeToggleEnabled = modeToggleBtn.getAttribute("data-enabled") === "1";
        runWithControlPending(modeToggleBtn, function () {
          return modeRuntimeUpdate(modeToggleId, { enabled: modeToggleEnabled });
        }, { spinner: false }).catch(showError);
        return;
      }
      var modeInjectionBtn = event.target && event.target.closest
        ? event.target.closest("button[data-action='mode-runtime-injection'][data-mode-id][data-allow]")
        : null;
      if (modeInjectionBtn) {
        var modeInjectionId = modeInjectionBtn.getAttribute("data-mode-id") || "";
        var modeInjectionAllow = modeInjectionBtn.getAttribute("data-allow") === "1";
        runWithControlPending(modeInjectionBtn, function () {
          return modeRuntimeUpdate(modeInjectionId, { allow_queue_injection: modeInjectionAllow });
        }, { spinner: false }).catch(showError);
        return;
      }
      var taxonomyQueryBtn = event.target && event.target.closest
        ? event.target.closest("button[data-action='mode-runtime-taxonomy-query']")
        : null;
      if (taxonomyQueryBtn) {
        var taxonomyFilters = modeRuntimeTaxonomyFiltersFromDom();
        runWithControlPending(taxonomyQueryBtn, function () {
          return modeRuntimeQueryFailureTaxonomy(taxonomyFilters).then(function () {
            var shownCount = Number(state.modeRuntimeTaxonomyQuery.returned || 0);
            if (!isFinite(shownCount) || shownCount < 0) {
              shownCount = 0;
            }
            showTransientNotice("Failure query returned " + String(shownCount) + " event" + (shownCount === 1 ? "" : "s"));
          });
        }, { spinner: false }).catch(showError);
        return;
      }
      var taxonomyQueryResetBtn = event.target && event.target.closest
        ? event.target.closest("button[data-action='mode-runtime-taxonomy-query-reset']")
        : null;
      if (taxonomyQueryResetBtn) {
        runWithControlPending(taxonomyQueryResetBtn, function () {
          return modeRuntimeQueryFailureTaxonomy(defaultModeRuntimeTaxonomyQueryFilters()).then(function () {
            showTransientNotice("Failure query filters reset");
          });
        }, { spinner: false }).catch(showError);
        return;
      }
      var proposalGenerateBtn = event.target && event.target.closest
        ? event.target.closest("button[data-action='mode-runtime-proposal-generate']")
        : null;
      if (proposalGenerateBtn) {
        runWithControlPending(proposalGenerateBtn, function () {
          return modeRuntimeGenerateImprovementProposals().then(function (response) {
            var created = response && response.result && Array.isArray(response.result.created) ? response.result.created : [];
            showTransientNotice(
              created.length
                ? ("Generated " + String(created.length) + " proposal" + (created.length === 1 ? "" : "s"))
                : "No new proposals generated"
            );
          });
        }, { spinner: false }).catch(showError);
        return;
      }
      var proposalDecisionBtn = event.target && event.target.closest
        ? event.target.closest("button[data-action='mode-runtime-proposal-decision'][data-proposal-id][data-decision]")
        : null;
      if (proposalDecisionBtn) {
        var proposalId = trim(String(proposalDecisionBtn.getAttribute("data-proposal-id") || ""));
        var proposalDecision = trim(String(proposalDecisionBtn.getAttribute("data-decision") || "")).toLowerCase();
        if (!proposalId || !proposalDecision) {
          return;
        }
        if (proposalDecision === "apply") {
          var applyConfirmed = window.confirm("Apply this proposal state? This does not auto-edit pipelines.");
          if (!applyConfirmed) {
            return;
          }
        }
        runWithControlPending(proposalDecisionBtn, function () {
          return modeRuntimeDecideImprovementProposal(proposalId, proposalDecision).then(function () {
            var decisionLabel = proposalDecision === "apply"
              ? "applied"
              : (proposalDecision === "accept" ? "accepted" : "rejected");
            showTransientNotice("Proposal " + decisionLabel);
          });
        }, { spinner: false }).catch(showError);
        return;
      }
      var controllerPromoteBtn = event.target && event.target.closest
        ? event.target.closest("button[data-action='mode-runtime-controller-promote'][data-variant-id]")
        : null;
      if (controllerPromoteBtn) {
        var promoteVariantId = trim(String(controllerPromoteBtn.getAttribute("data-variant-id") || ""));
        if (!promoteVariantId) {
          return;
        }
        if (!window.confirm("Promote this controller variant to active?")) {
          return;
        }
        runWithControlPending(controllerPromoteBtn, function () {
          return modeRuntimePromoteControllerVariant(promoteVariantId).then(function () {
            showTransientNotice("Controller variant promoted");
          });
        }, { spinner: false }).catch(showError);
        return;
      }
      var controllerRollbackBtn = event.target && event.target.closest
        ? event.target.closest("button[data-action='mode-runtime-controller-rollback']")
        : null;
      if (controllerRollbackBtn) {
        if (!window.confirm("Rollback controller variant to previous active?")) {
          return;
        }
        runWithControlPending(controllerRollbackBtn, function () {
          return modeRuntimeRollbackControllerVariant().then(function () {
            showTransientNotice("Controller variant rolled back");
          });
        }, { spinner: false }).catch(showError);
        return;
      }
      var modeUseBtn = event.target && event.target.closest
        ? event.target.closest("button[data-action='mode-runtime-use'][data-mode-id]")
        : null;
      if (modeUseBtn) {
        saveRunMode("assistant");
        saveAssistantModeId(modeUseBtn.getAttribute("data-mode-id") || "");
        if (el.assistantModeSelect) {
          el.assistantModeSelect.value = state.assistantModeId;
        }
        closeModal(el.settingsModal);
        renderUi();
        showTransientNotice("Team updated");
        return;
      }
      var skillQuickBtn = event.target && event.target.closest
        ? event.target.closest("button[data-action='mode-runtime-skill-quick'][data-skill-id]")
        : null;
      if (skillQuickBtn) {
        var quickSkillId = trim(String(skillQuickBtn.getAttribute("data-skill-id") || ""));
        if (el.modeRuntimeSkillSelect) {
          el.modeRuntimeSkillSelect.value = quickSkillId;
        }
        if (el.modeRuntimeSkillInput) {
          el.modeRuntimeSkillInput.focus();
        }
        showTransientNotice("Skill ready: " + quickSkillId);
        return;
      }
      if (event.target === el.settingsModal) {
        closeModal(el.settingsModal);
      }
    });

    on(el.settingsModal, "change", function (event) {
      var selfImproveToggle = event.target && event.target.closest
        ? event.target.closest("input[type='checkbox'][data-action='self-improve-plugin-toggle'][data-plugin-id]")
        : null;
      if (!selfImproveToggle) {
        return;
      }
      var pluginToggleId = trim(String(selfImproveToggle.getAttribute("data-plugin-id") || ""));
      if (!pluginToggleId) {
        return;
      }
      saveSelfImprovePluginEnabled(pluginToggleId, !!selfImproveToggle.checked).catch(showError);
    });

    if (el.multi_agentModal) {
      on(el.multi_agentModal, "click", function (event) {
        var triageActionBtn = event.target && event.target.closest
          ? event.target.closest("[data-action^='triage-']")
          : null;
        if (triageActionBtn) {
          handleWorkspaceTreeClick(event);
          return;
        }
        var residentOptionsBtn = event.target && event.target.closest
          ? event.target.closest("button[data-action='multi_agent-resident-options-toggle'][data-resident-id]")
          : null;
        if (residentOptionsBtn) {
          var rowSelectBtn = residentOptionsBtn.closest("[data-resident-id]");
          if (rowSelectBtn) {
            var selectedWsId = trim(String(state.commandRulesWorkspaceId || state.activeWorkspaceId || ""));
            var selectedId = trim(String(rowSelectBtn.getAttribute("data-resident-id") || ""));
            if (selectedWsId && selectedId) {
              state.multiAgentSelectedResidentIdByWorkspace[selectedWsId] = selectedId;
            }
          }
          var optResidentId = residentOptionsBtn.getAttribute("data-resident-id") || "";
          var optionsWsId = trim(String(state.commandRulesWorkspaceId || state.activeWorkspaceId || ""));
          if (!optResidentId || !optionsWsId) {
            return;
          }
          if (state.multiAgentOpenResidentOptionsByWorkspace[optionsWsId] === optResidentId) {
            state.multiAgentOpenResidentOptionsByWorkspace[optionsWsId] = "";
          } else {
            state.multiAgentOpenResidentOptionsByWorkspace[optionsWsId] = optResidentId;
          }
          renderMultiAgentModal();
          return;
        }
        var residentQuickToggleBtn = event.target && event.target.closest
          ? event.target.closest("button[data-action='multi_agent-resident-quick-toggle'][data-workspace-id][data-resident-id]")
          : null;
        if (residentQuickToggleBtn) {
          var quickWsId = residentQuickToggleBtn.getAttribute("data-workspace-id") || "";
          var quickResidentId = residentQuickToggleBtn.getAttribute("data-resident-id") || "";
          if (!quickWsId || !quickResidentId || !el.multi_agentModal) {
            return;
          }
          var quickEnableInputs = el.multi_agentModal.querySelectorAll("input[data-action='multi_agent-resident-enable'][data-workspace-id][data-resident-id]");
          for (var qei = 0; qei < quickEnableInputs.length; qei += 1) {
            if (
              String(quickEnableInputs[qei].getAttribute("data-workspace-id") || "") === String(quickWsId) &&
              String(quickEnableInputs[qei].getAttribute("data-resident-id") || "") === String(quickResidentId)
            ) {
              quickEnableInputs[qei].click();
              break;
            }
          }
          return;
        }
        var residentOpenModelBtn = event.target && event.target.closest
          ? event.target.closest("button[data-action='multi_agent-resident-open-model'][data-workspace-id][data-resident-id]")
          : null;
        if (residentOpenModelBtn) {
          var modelWsId = residentOpenModelBtn.getAttribute("data-workspace-id") || "";
          var modelResidentId = residentOpenModelBtn.getAttribute("data-resident-id") || "";
          if (!modelWsId || !modelResidentId) {
            return;
          }
          state.multiAgentOpenResidentOptionsByWorkspace[modelWsId] = modelResidentId;
          renderMultiAgentModal();
          setTimeout(function () {
            if (!el.multi_agentModal) {
              return;
            }
            var modelSelects = el.multi_agentModal.querySelectorAll("select[data-action='multi_agent-resident-model'][data-workspace-id][data-resident-id]");
            for (var msi = 0; msi < modelSelects.length; msi += 1) {
              if (
                String(modelSelects[msi].getAttribute("data-workspace-id") || "") === String(modelWsId) &&
                String(modelSelects[msi].getAttribute("data-resident-id") || "") === String(modelResidentId)
              ) {
                modelSelects[msi].focus();
                break;
              }
            }
          }, 0);
          return;
        }

        var residentRow = event.target && event.target.closest
          ? event.target.closest("[data-action='multi_agent-resident-select'][data-workspace-id][data-resident-id]")
          : null;
        if (residentRow) {
          if (event.target && event.target.closest && event.target.closest("input, select, button, label, textarea, a, summary")) {
            return;
          }
          var rowWsId = residentRow.getAttribute("data-workspace-id") || "";
          var rowResidentId = residentRow.getAttribute("data-resident-id") || "";
          if (rowWsId && rowResidentId) {
            state.multiAgentSelectedResidentIdByWorkspace[rowWsId] = rowResidentId;
            renderMultiAgentModal();
          }
          return;
        }

        var commitmentStatusBtn = event.target && event.target.closest
          ? event.target.closest("button[data-action='multi_agent-commitment-status'][data-workspace-id][data-entry-id][data-status]")
          : null;
        if (commitmentStatusBtn) {
          var commitmentWsId = commitmentStatusBtn.getAttribute("data-workspace-id") || "";
          var commitmentEntryId = commitmentStatusBtn.getAttribute("data-entry-id") || "";
          var commitmentStatus = commitmentStatusBtn.getAttribute("data-status") || "";
          runWithControlPending(commitmentStatusBtn, function () {
            return apiPost("multi_agent_commitment_update", {
              workspace_id: commitmentWsId,
              entry_id: commitmentEntryId,
              status: commitmentStatus
            }).then(function (response) {
              if (!response || !response.success) {
                throw new Error((response && response.error) || "Could not update commitment status");
              }
              state.workspaceMultiAgentById[commitmentWsId] = response.workspace_multi_agent || state.workspaceMultiAgentById[commitmentWsId] || null;
              return loadState();
            }).then(renderUi);
          }).catch(showError);
          return;
        }

        var logDeleteBtn = event.target && event.target.closest
          ? event.target.closest("button[data-action='multi_agent-log-delete'][data-workspace-id][data-log-kind][data-entry-id]")
          : null;
        if (logDeleteBtn) {
          var deleteWsId = logDeleteBtn.getAttribute("data-workspace-id") || "";
          var logKind = logDeleteBtn.getAttribute("data-log-kind") || "";
          var entryId = logDeleteBtn.getAttribute("data-entry-id") || "";
          runWithControlPending(logDeleteBtn, function () {
            return apiPost("multi_agent_log_delete", {
              workspace_id: deleteWsId,
              log_kind: logKind,
              entry_id: entryId
            }).then(function (response) {
              if (!response || !response.success) {
                throw new Error((response && response.error) || "Could not delete entry");
              }
              state.workspaceMultiAgentById[deleteWsId] = response.workspace_multi_agent || state.workspaceMultiAgentById[deleteWsId] || null;
              return loadState();
            }).then(renderUi);
          }).catch(showError);
          return;
        }

        if (event.target === el.multi_agentModal) {
          closeModal(el.multi_agentModal);
        }
      });

      on(el.multi_agentModal, "change", function (event) {
        var allResidentsToggleInput = event.target && event.target.closest
          ? event.target.closest("#multi_agent-toggle-all-residents")
          : null;
        if (allResidentsToggleInput) {
          var wsAll = trim(String(state.commandRulesWorkspaceId || state.activeWorkspaceId || ""));
          if (!wsAll) {
            return;
          }
          var nextEnabled = !!allResidentsToggleInput.checked;
          multiAgentSetAllResidentsEnabled(wsAll, nextEnabled).catch(showError);
          return;
        }

        var toggleInput = event.target && event.target.closest
          ? event.target.closest("#multi_agent-toggle-context-sharing, #multi_agent-toggle-amendments, #multi_agent-toggle-commitments, #multi_agent-toggle-policies")
          : null;
        if (toggleInput) {
          var wsId = trim(String(state.commandRulesWorkspaceId || state.activeWorkspaceId || ""));
          if (!wsId) {
            return;
          }
          if (!state.workspaceMultiAgentById[wsId] || typeof state.workspaceMultiAgentById[wsId] !== "object") {
            state.workspaceMultiAgentById[wsId] = {};
          }
          if (!state.workspaceMultiAgentById[wsId].toggles || typeof state.workspaceMultiAgentById[wsId].toggles !== "object") {
            state.workspaceMultiAgentById[wsId].toggles = {};
          }
          var contextSharingOn = el.multi_agentToggleContextSharing && el.multi_agentToggleContextSharing.checked ? 1 : 0;
          var amendmentsOn = el.multi_agentToggleAmendments && el.multi_agentToggleAmendments.checked ? 1 : 0;
          var attentionOn = el.multi_agentTogglePolicies && el.multi_agentTogglePolicies.checked ? 1 : 0;
          if (!contextSharingOn) {
            amendmentsOn = 0;
            attentionOn = 0;
          }
          state.workspaceMultiAgentById[wsId].toggles.context_sharing = contextSharingOn;
          state.workspaceMultiAgentById[wsId].toggles.amendments = amendmentsOn;
          state.workspaceMultiAgentById[wsId].toggles.interpretation_log = state.workspaceMultiAgentById[wsId].toggles.amendments;
          state.workspaceMultiAgentById[wsId].toggles.commitments = el.multi_agentToggleCommitments && el.multi_agentToggleCommitments.checked ? 1 : 0;
          state.workspaceMultiAgentById[wsId].toggles.attention_policies = attentionOn;
          state.multiAgentGovernanceSavingByWorkspace[wsId] = true;
          multiAgentSectionVisibilitySync();
          renderMultiAgentModal();
          saveMultiAgentGovernanceFromControls(wsId)
            .then(function (updated) {
              if (updated && typeof updated === "object") {
                state.workspaceMultiAgentById[wsId] = updated;
              }
              state.multiAgentGovernanceSavingByWorkspace[wsId] = false;
              renderUi();
            })
            .catch(function (error) {
              state.multiAgentGovernanceSavingByWorkspace[wsId] = false;
              loadWorkspaceMultiAgent(wsId).finally(function () {
                renderUi();
                showError(error);
              });
            });
          return;
        }

        var residentEnableInput = event.target && event.target.closest
          ? event.target.closest("input[data-action='multi_agent-resident-enable'][data-workspace-id][data-resident-id]")
          : null;
        if (residentEnableInput) {
          var wsEnable = residentEnableInput.getAttribute("data-workspace-id") || "";
          var residentEnableId = residentEnableInput.getAttribute("data-resident-id") || "";
          if (wsEnable && residentEnableId) {
            state.multiAgentSelectedResidentIdByWorkspace[wsEnable] = residentEnableId;
          }
          var checked = !!residentEnableInput.checked;
          var modelSelect = null;
          var visibleInput = null;
          if (el.multi_agentModal) {
            var residentModelSelects = el.multi_agentModal.querySelectorAll("select[data-action='multi_agent-resident-model'][data-workspace-id][data-resident-id]");
            for (var rms = 0; rms < residentModelSelects.length; rms += 1) {
              if (
                String(residentModelSelects[rms].getAttribute("data-workspace-id") || "") === String(wsEnable) &&
                String(residentModelSelects[rms].getAttribute("data-resident-id") || "") === String(residentEnableId)
              ) {
                modelSelect = residentModelSelects[rms];
                break;
              }
            }
            var residentVisibleInputs = el.multi_agentModal.querySelectorAll("input[data-action='multi_agent-resident-visible'][data-workspace-id][data-resident-id]");
            for (var rvi = 0; rvi < residentVisibleInputs.length; rvi += 1) {
              if (
                String(residentVisibleInputs[rvi].getAttribute("data-workspace-id") || "") === String(wsEnable) &&
                String(residentVisibleInputs[rvi].getAttribute("data-resident-id") || "") === String(residentEnableId)
              ) {
                visibleInput = residentVisibleInputs[rvi];
                break;
              }
            }
          }
          var selectedModel = trim(String(modelSelect && modelSelect.value || ""));
          var showInThreads = !!(visibleInput && visibleInput.checked);
          var residentState = state.workspaceMultiAgentById[wsEnable];
          var existingResidents = Array.isArray(residentState && residentState.residents) ? residentState.residents : [];
          var alreadyExists = false;
          for (var ri = 0; ri < existingResidents.length; ri += 1) {
            if (String(existingResidents[ri] && existingResidents[ri].id || "") === residentEnableId) {
              alreadyExists = true;
              break;
            }
          }
          var enablePromise = null;
          if (checked && !alreadyExists) {
            enablePromise = apiPost("multi_agent_resident_spawn", {
              workspace_id: wsEnable,
              resident_id: residentEnableId,
              visible: showInThreads ? "1" : "0",
              background: showInThreads ? "0" : "1",
              reserve_compute: "0",
              model: selectedModel
            });
          } else {
            var updatePayload = {
              workspace_id: wsEnable,
              resident_id: residentEnableId,
              enabled: checked ? "1" : "0",
              visible: showInThreads ? "1" : "0",
              background: showInThreads ? "0" : "1"
            };
            if (selectedModel) {
              updatePayload.model = selectedModel;
            }
            enablePromise = apiPost("multi_agent_resident_update", updatePayload);
          }
          enablePromise.then(function (response) {
            if (!response || !response.success) {
              throw new Error((response && response.error) || "Could not update agent role");
            }
            state.workspaceMultiAgentById[wsEnable] = response.workspace_multi_agent || state.workspaceMultiAgentById[wsEnable] || null;
            return loadState();
          }).then(renderUi).catch(showError);
          return;
        }

        var residentVisibleInput = event.target && event.target.closest
          ? event.target.closest("input[data-action='multi_agent-resident-visible'][data-workspace-id][data-resident-id]")
          : null;
        if (residentVisibleInput) {
          var wsVisible = residentVisibleInput.getAttribute("data-workspace-id") || "";
          var residentVisibleId = residentVisibleInput.getAttribute("data-resident-id") || "";
          if (wsVisible && residentVisibleId) {
            state.multiAgentSelectedResidentIdByWorkspace[wsVisible] = residentVisibleId;
          }
          var showThreads = residentVisibleInput.checked ? "1" : "0";
          var localWorkspace = state.workspaceMultiAgentById[wsVisible];
          if (localWorkspace && Array.isArray(localWorkspace.residents)) {
            for (var lri = 0; lri < localWorkspace.residents.length; lri += 1) {
              if (String(localWorkspace.residents[lri] && localWorkspace.residents[lri].id || "") === String(residentVisibleId)) {
                localWorkspace.residents[lri].visible = showThreads === "1";
                localWorkspace.residents[lri].background = showThreads !== "1";
                break;
              }
            }
            state.workspaceMultiAgentById[wsVisible] = localWorkspace;
            renderUi();
          }
          apiPost("multi_agent_resident_update", {
            workspace_id: wsVisible,
            resident_id: residentVisibleId,
            visible: showThreads,
            background: showThreads === "1" ? "0" : "1"
          }).then(function (response) {
            if (!response || !response.success) {
              throw new Error((response && response.error) || "Could not update agent visibility");
            }
            state.workspaceMultiAgentById[wsVisible] = response.workspace_multi_agent || state.workspaceMultiAgentById[wsVisible] || null;
            return loadState();
          }).then(renderUi).catch(function (error) {
            loadWorkspaceMultiAgent(wsVisible).finally(function () {
              renderUi();
              showError(error);
            });
          });
          return;
        }

        var residentModelSelect = event.target && event.target.closest
          ? event.target.closest("select[data-action='multi_agent-resident-model'][data-workspace-id][data-resident-id]")
          : null;
        if (residentModelSelect) {
          var wsModel = residentModelSelect.getAttribute("data-workspace-id") || "";
          var residentModelId = residentModelSelect.getAttribute("data-resident-id") || "";
          if (wsModel && residentModelId) {
            state.multiAgentSelectedResidentIdByWorkspace[wsModel] = residentModelId;
          }
          var modelValue = trim(String(residentModelSelect.value || ""));
          apiPost("multi_agent_resident_update", {
            workspace_id: wsModel,
            resident_id: residentModelId,
            model_present: "1",
            model: modelValue
          }).then(function (response) {
            if (!response || !response.success) {
              throw new Error((response && response.error) || "Could not update agent model");
            }
            state.workspaceMultiAgentById[wsModel] = response.workspace_multi_agent || state.workspaceMultiAgentById[wsModel] || null;
            return loadState();
          }).then(renderUi).catch(showError);
        }
      });
    }

    if (el.commandRulesWorkspace) {
      on(el.commandRulesWorkspace, "change", function () {
        var wsId = trim(el.commandRulesWorkspace.value || "");
        state.commandRulesWorkspaceId = wsId;
        loadCommandRules(wsId).catch(showError);
      });
    }

    on(el.refreshAuthBtn, "click", function () {
      runWithControlPending(el.refreshAuthBtn, function () {
        return loadAuthStatus();
      }).catch(showError);
    });

    if (el.automationDaemonRefreshBtn) {
      on(el.automationDaemonRefreshBtn, "click", function () {
        runWithControlPending(el.automationDaemonRefreshBtn, function () {
          return loadAutomationDaemonStatus();
        }, { spinner: false }).catch(showError);
      });
    }

    if (el.automationDaemonRunNowBtn) {
      on(el.automationDaemonRunNowBtn, "click", function () {
        runWithControlPending(el.automationDaemonRunNowBtn, function () {
          return runAutomationDaemonTickNow().then(function () {
            return loadAutomationDaemonStatus({ silent: true, preserveError: true });
          });
        }, { spinner: false }).catch(showError);
      });
    }

    if (el.automationDaemonToggle) {
      on(el.automationDaemonToggle, "change", function () {
        var requested = !!el.automationDaemonToggle.checked;
        var previous = !!state.automationDaemon.enabled;
        state.automationDaemon.enabled = requested;
        renderAutomationDaemonSettings();
        runWithControlPending(el.automationDaemonToggle, function () {
          return saveAutomationDaemonEnabled(requested).then(function () {
            return loadAutomationDaemonStatus({ silent: true, preserveError: true });
          });
        }, { spinner: false }).catch(function (error) {
          state.automationDaemon.enabled = previous;
          renderAutomationDaemonSettings();
          showError(error);
        });
      });
    }

    if (el.installDictationBtn) {
      on(el.installDictationBtn, "click", function (event) {
        if (event) {
          event.preventDefault();
        }
        var activeJob = state.dictationInstallJob || null;
        var activeJobStatus = trim(String(activeJob && activeJob.status ? activeJob.status : ""));
        var activeJobAction = trim(String(activeJob && activeJob.action ? activeJob.action : ""));
        var runningInstallVisible =
          activeJob &&
          activeJobAction !== "uninstall" &&
          (activeJobStatus === "running" || (!activeJobStatus && state.dictationInstallBusy));
        var buttonText = trim(String((el.installDictationBtn && el.installDictationBtn.textContent) || "")).toLowerCase();
        var cancelIntent = state.dictationInstallBusy || runningInstallVisible || buttonText.indexOf("cancel") === 0;

        if (state.dictationInstallCancelling) {
          showTransientNotice("Cancelling dictation download...");
          return;
        }

        // Flip to cancelling visuals immediately on click, before async work.
        if (cancelIntent) {
          state.dictationInstallCancelling = true;
          state.dictationInstallPendingCancel = false;
          if (el.installDictationBtn) {
            el.installDictationBtn.textContent = "Cancelling...";
            el.installDictationBtn.disabled = true;
            el.installDictationBtn.classList.add("ui-pending-spinner");
          }
          if (el.dictationInstallStatus) {
            el.dictationInstallStatus.textContent = "Cancelling dictation download...";
            el.dictationInstallStatus.classList.remove("hidden");
            el.dictationInstallStatus.classList.remove("error");
            el.dictationInstallStatus.classList.add("status-pending-spinner");
          }
          renderUi();
          setTimeout(function () {
            cancelDictationInstall().catch(showError);
          }, 0);
          return;
        }
        toggleDictationSoftware().catch(showError);
      });
    }
    if (el.dictationHoldShortcut) {
      on(el.dictationHoldShortcut, "change", function () {
        saveDictationShortcutChoice("hold", el.dictationHoldShortcut.value);
      });
    }
    if (el.dictationToggleShortcut) {
      on(el.dictationToggleShortcut, "change", function () {
        saveDictationShortcutChoice("toggle", el.dictationToggleShortcut.value);
      });
    }
    if (el.dictationLanguageSelect) {
      on(el.dictationLanguageSelect, "change", function () {
        saveDictationLanguageChoice(el.dictationLanguageSelect.value).then(function () {
          renderDictationInstallSettings();
        }).catch(function (error) {
          showError(error);
          loadDictationLanguageSetting().finally(function () {
            renderDictationInstallSettings();
          });
        });
      });
    }
    if (el.dictationPrewarmToggle) {
      on(el.dictationPrewarmToggle, "change", function () {
        var nextEnabled = !!el.dictationPrewarmToggle.checked;
        saveDictationPrewarmSetting(nextEnabled).then(function () {
          if (nextEnabled) {
            requestDictationPrepare({ silent: true, force: true }).catch(function () {
              return null;
            });
            if (dictationPrepareLoopShouldRun()) {
              startDictationPrepareLoop();
            }
          } else {
            dictationPrepareReadyUntil = 0;
            stopDictationPrepareLoop();
          }
          renderDictationInstallSettings();
        }).catch(function (error) {
          showError(error);
          loadDictationPrewarmSetting().finally(function () {
            renderDictationInstallSettings();
          });
        });
      });
    }

    if (el.programmerReviewToggle) {
      on(el.programmerReviewToggle, "change", function () {
        saveProgrammerReviewEnabled(!!el.programmerReviewToggle.checked);
        renderProgrammingSettings();
      });
    }

    if (el.programmerReviewRounds) {
      on(el.programmerReviewRounds, "change", function () {
        saveProgrammerReviewRounds(el.programmerReviewRounds.value);
        renderProgrammingSettings();
      });
    }

    if (el.modeRuntimeTickBtn) {
      on(el.modeRuntimeTickBtn, "click", function () {
        runWithControlPending(el.modeRuntimeTickBtn, function () {
          return modeRuntimeTickNow();
        }, { spinner: false }).catch(showError);
      });
    }

    if (el.assistantModeApplyBtn) {
      on(el.assistantModeApplyBtn, "click", function () {
        var selectedModeId = trim(String((el.assistantModeSelect && el.assistantModeSelect.value) || ""));
        saveRunMode("assistant");
        saveAssistantModeId(selectedModeId);
        renderUi();
        showTransientNotice(selectedModeId ? "Default team applied" : "General team applied");
      });
    }

    if (el.modeRuntimeSkillInvokeForm) {
      on(el.modeRuntimeSkillInvokeForm, "submit", function (event) {
        event.preventDefault();
        var skillId = trim(String((el.modeRuntimeSkillSelect && el.modeRuntimeSkillSelect.value) || ""));
        if (!skillId) {
          setModeRuntimeSkillResult("Select a skill first.", true);
          return;
        }
        var modeId = trim(String((el.modeRuntimeSkillMode && el.modeRuntimeSkillMode.value) || "")) || "assistant";
        var inputText = String((el.modeRuntimeSkillInput && el.modeRuntimeSkillInput.value) || "");
        var capabilitiesCsv = trim(String((el.modeRuntimeSkillCapabilities && el.modeRuntimeSkillCapabilities.value) || ""));
        runWithControlPending(el.modeRuntimeSkillInvokeBtn || event.submitter, function () {
          setModeRuntimeSkillResult("Invoking skill...", false);
          return modeRuntimeSkillInvoke(modeId, skillId, inputText, capabilitiesCsv);
        }, { spinner: false }).catch(function (error) {
          setModeRuntimeSkillResult(error && error.message ? error.message : String(error), true);
        });
      });
    }

    if (el.modeRuntimeSkillCreateForm) {
      on(el.modeRuntimeSkillCreateForm, "submit", function (event) {
        event.preventDefault();
        var payload = {
          skill_id: trim(String((el.modeRuntimeSkillCreateId && el.modeRuntimeSkillCreateId.value) || "")),
          name: trim(String((el.modeRuntimeSkillCreateName && el.modeRuntimeSkillCreateName.value) || "")),
          trigger: trim(String((el.modeRuntimeSkillCreateTrigger && el.modeRuntimeSkillCreateTrigger.value) || "")),
          capabilities: trim(String((el.modeRuntimeSkillCreateCapabilities && el.modeRuntimeSkillCreateCapabilities.value) || "")),
          description: trim(String((el.modeRuntimeSkillCreateDescription && el.modeRuntimeSkillCreateDescription.value) || ""))
        };
        if (!payload.skill_id) {
          setModeRuntimeSkillResult("Provide a new skill id.", true);
          return;
        }
        runWithControlPending(el.modeRuntimeSkillCreateBtn || event.submitter, function () {
          return modeRuntimeSkillCreate(payload).then(function () {
            showTransientNotice("Skill created: " + payload.skill_id);
            setModeRuntimeSkillResult("Created skill bundle " + payload.skill_id + ".", false);
            if (el.modeRuntimeSkillCreateForm) {
              el.modeRuntimeSkillCreateForm.reset();
            }
          });
        }, { spinner: false }).catch(function (error) {
          setModeRuntimeSkillResult(error && error.message ? error.message : String(error), true);
        });
      });
    }

    if (el.modeRuntimeSkillInstallForm) {
      on(el.modeRuntimeSkillInstallForm, "submit", function (event) {
        event.preventDefault();
        var payload = {
          source_path: trim(String((el.modeRuntimeSkillInstallSource && el.modeRuntimeSkillInstallSource.value) || "")),
          skill_id: trim(String((el.modeRuntimeSkillInstallId && el.modeRuntimeSkillInstallId.value) || "")),
          replace: String((el.modeRuntimeSkillInstallReplace && el.modeRuntimeSkillInstallReplace.value) || "0") === "1"
        };
        if (!payload.source_path) {
          setModeRuntimeSkillResult("Provide a source folder path.", true);
          return;
        }
        runWithControlPending(el.modeRuntimeSkillInstallBtn || event.submitter, function () {
          return modeRuntimeSkillInstall(payload).then(function (response) {
            var installedId = trim(String((response && response.skill_id) || payload.skill_id || ""));
            showTransientNotice("Skill installed" + (installedId ? ": " + installedId : ""));
            setModeRuntimeSkillResult("Installed skill bundle " + (installedId || "from source") + ".", false);
            if (el.modeRuntimeSkillInstallForm) {
              el.modeRuntimeSkillInstallForm.reset();
            }
          });
        }, { spinner: false }).catch(function (error) {
          setModeRuntimeSkillResult(error && error.message ? error.message : String(error), true);
        });
      });
    }

    if (el.githubUsername) {
      on(el.githubUsername, "input", function () {
        state.githubUsername = trim(el.githubUsername.value);
        storageSet("artificer.githubUsername", state.githubUsername);
      });
    }

    if (el.llmUseGpuToggle) {
      on(el.llmUseGpuToggle, "change", function () {
        var requested = !!el.llmUseGpuToggle.checked;
        var previous = !!state.llmUseGpu;
        state.llmUseGpu = requested;
        storageSet("artificer.llmUseGpu", requested ? "1" : "0");
        runWithControlPending(el.llmUseGpuToggle, function () {
          return saveLlmRuntimeSettings(requested);
        }, { spinner: false }).catch(function (error) {
          state.llmUseGpu = previous;
          storageSet("artificer.llmUseGpu", previous ? "1" : "0");
          el.llmUseGpuToggle.checked = previous;
          showError(error);
        });
      });
    }

    on(el.generateSshBtn, "click", function () {
      runWithControlPending(el.generateSshBtn, function () {
        return apiPost("git_generate_ssh", { email: trim(el.sshEmail.value) })
          .then(function (response) {
            if (!response.success) {
              throw new Error(response.error || "Could not generate SSH key");
            }
            el.sshPubOutput.value = response.ssh_pub_key || "";
            el.sshKeyStatus.textContent = "SSH key ready";
          });
      }).catch(showError);
    });

    if (el.chooseSshBtn) {
      on(el.chooseSshBtn, "click", function () {
        runWithControlPending(el.chooseSshBtn, function () {
          return apiPost("git_choose_ssh_key", {})
            .then(function (response) {
              if (!response.success) {
                throw new Error(response.error || "Could not choose SSH key");
              }
              if (response.cancelled) {
                return null;
              }
              if (el.selectedSshPath) {
                el.selectedSshPath.value = response.selected_ssh_pub_path || "";
              }
              if (el.sshPubOutput && typeof response.selected_ssh_pub_key !== "undefined") {
                el.sshPubOutput.value = response.selected_ssh_pub_key || "";
              }
              if (el.sshKeyStatus) {
                el.sshKeyStatus.textContent = response.selected_ssh_pub_path ? "Custom SSH key selected" : "SSH key found";
              }
              return null;
            });
        }).catch(showError);
      });
    }

    if (el.clearSshBtn) {
      on(el.clearSshBtn, "click", function () {
        runWithControlPending(el.clearSshBtn, function () {
          return apiPost("git_clear_ssh_key", {})
            .then(function (response) {
              if (!response.success) {
                throw new Error(response.error || "Could not clear SSH key selection");
              }
              return loadAuthStatus();
            });
        }).catch(showError);
      });
    }

    on(el.terminalToggleBtn, "click", function () {
      toggleTerminal();
    });

    if (el.terminalPanel) {
      on(el.terminalPanel, "click", function () {
        if (el.terminalOutput) {
          focusElementNoScroll(el.terminalOutput);
        }
      });
    }

    on(el.terminalPanel, "keydown", function (event) {
      if (!state.terminalOpen) {
        return;
      }
      if (event.metaKey || event.ctrlKey) {
        return;
      }
      if (event.altKey) {
        return;
      }

      if (event.key === "Enter") {
        event.preventDefault();
        var commandText = String(state.terminalInputBuffer || "");
        state.terminalInputBuffer = "";
        renderTerminal();
        if (!trim(commandText)) {
          return;
        }
        state.terminalBusy = true;
        renderTerminal();
        ensureTerminalSession()
          .then(function () {
            return apiPost("terminal_session_input", {
              workspace_id: state.activeWorkspaceId,
              session_id: state.terminalSessionId,
              input: commandText + "\n"
            }, { timeoutMs: 10000 });
          })
          .then(function (response) {
            if (!response || !response.success) {
              throw new Error((response && response.error) || "Could not send terminal input");
            }
            return pollTerminalSessionOnce();
          })
          .finally(function () {
            state.terminalBusy = false;
            renderTerminal();
          })
          .catch(showError);
        return;
      }

      if (event.key === "Backspace") {
        event.preventDefault();
        state.terminalInputBuffer = String(state.terminalInputBuffer || "").slice(0, -1);
        renderTerminal();
        return;
      }

      if (event.key === "Escape") {
        event.preventDefault();
        state.terminalInputBuffer = "";
        renderTerminal();
        return;
      }

      if (event.key === "Tab") {
        event.preventDefault();
        state.terminalInputBuffer += "  ";
        renderTerminal();
        return;
      }

      if (event.key && event.key.length === 1) {
        event.preventDefault();
        state.terminalInputBuffer += event.key;
        renderTerminal();
      }
    });

    on(el.terminalPanel, "paste", function (event) {
      if (!state.terminalOpen) {
        return;
      }
      var text = event.clipboardData && event.clipboardData.getData ? event.clipboardData.getData("text") : "";
      if (!text) {
        return;
      }
      event.preventDefault();
      var chunk = String(text).replace(/\r?\n/g, " ");
      state.terminalInputBuffer += chunk;
      renderTerminal();
    });

    on(el.changesBtn, "click", function () {
      if (!state.activeWorkspaceId) {
        showError(new Error("Select a project first."));
        return;
      }
      runWithControlPending(el.changesBtn, function () {
        return toggleDiffPanel();
      }, { spinner: false }).catch(showError);
    });

    on(el.diffCloseBtn, "click", function () {
      closeDiffPanel();
    });

    on(el.runForm, "submit", function (event) {
      onRunSubmit(event);
    });
    on(el.runBtn, "click", function (event) {
      if (!el.runForm || (el.runBtn && el.runBtn.disabled)) {
        return;
      }
      event.preventDefault();
      if (typeof el.runForm.requestSubmit === "function") {
        el.runForm.requestSubmit(el.runBtn);
      } else {
        onRunSubmit(event);
      }
    });
    on(el.runBtn, "contextmenu", function (event) {
      event.preventDefault();
      toggleMenu("send-menu", el.runBtn);
    });
    if (el.sendMenuQueueBtn) {
      on(el.sendMenuQueueBtn, "click", function (event) {
        event.preventDefault();
        closeAllMenus();
        if (!el.runForm || (el.runBtn && el.runBtn.disabled)) {
          return;
        }
        if (typeof el.runForm.requestSubmit === "function") {
          el.runForm.requestSubmit(el.runBtn);
        } else {
          onRunSubmit(event);
        }
      });
    }
    if (el.sendMenuStopBtn) {
      on(el.sendMenuStopBtn, "click", function (event) {
        event.preventDefault();
        closeAllMenus();
        runWithControlPending(el.sendMenuStopBtn, function () {
          return stopRunFromComposer();
        }).catch(showError);
      });
    }

    on(el.decisionRequestInlineClose, "click", function () {
      var info = activeDecisionRequestInfo();
      if (info) {
        state.decisionInlineDismissedKey = info.marker;
      }
      if (el.decisionRequestInline) {
        el.decisionRequestInline.classList.add("hidden");
      }
    });

    on(el.decisionRequestOptions, "change", function () {
      updateDecisionOtherVisibility();
    });

    on(el.decisionRequestOtherInput, "input", function () {
      if (!el.decisionRequestOptions) {
        return;
      }
      var otherRadio = el.decisionRequestOptions.querySelector("input[name='decision-request-choice'][value='other']");
      if (otherRadio) {
        otherRadio.checked = true;
      }
      updateDecisionOtherVisibility();
    });

    on(el.decisionRequestForm, "submit", function (event) {
      event.preventDefault();
      var submitter = event.submitter || el.decisionRequestSubmit;
      runWithControlPending(submitter, function () {
        return submitDecisionRequest();
      }).catch(showError);
    });

    if (el.attachBtn && el.attachmentPicker) {
      on(el.attachBtn, "click", function () {
        el.attachmentPicker.click();
      });
      on(el.attachmentPicker, "change", function (event) {
        try {
          onAttachmentPickerChange(event);
        } catch (error) {
          showError(error);
        }
      });
    }

    if (el.dictateBtn) {
      on(el.dictateBtn, "mouseenter", function () {
        requestDictationPrepare({ silent: true }).catch(function () {
          return null;
        });
      });
      on(el.dictateBtn, "focus", function () {
        requestDictationPrepare({ silent: true }).catch(function () {
          return null;
        });
        startDictationPrepareLoop();
      });
      on(el.dictateBtn, "blur", function () {
        if (!dictationPrepareLoopShouldRun()) {
          stopDictationPrepareLoop();
        }
      });
      on(el.dictateBtn, "mousedown", function (event) {
        if (event && event.button !== 0) {
          return;
        }
        var startedAtMs = Date.now();
        dictatePointerHandledAt = Date.now();
        onDictateClick(event, startedAtMs).catch(showError);
      });
      on(el.dictateBtn, "click", function (event) {
        if (Date.now() - dictatePointerHandledAt < 420) {
          if (event && typeof event.preventDefault === "function") {
            event.preventDefault();
          }
          return;
        }
        onDictateClick(event, Date.now()).catch(showError);
      });
    }
    if (el.dictationStopBtn) {
      on(el.dictationStopBtn, "pointerdown", function (event) {
        if (event && event.pointerType === "mouse" && event.button !== 0) {
          return;
        }
        dictateStopPointerHandledAt = Date.now();
        if (event && typeof event.preventDefault === "function") {
          event.preventDefault();
        }
        if (event && typeof event.stopPropagation === "function") {
          event.stopPropagation();
        }
        if (state.dictateBusy) {
          return;
        }
        stopDictationCapture({ fromHotkey: false }).catch(showError);
      });
      on(el.dictationStopBtn, "click", function (event) {
        if (Date.now() - dictateStopPointerHandledAt < 420) {
          if (event && typeof event.preventDefault === "function") {
            event.preventDefault();
          }
          return;
        }
        if (event) {
          event.preventDefault();
        }
        if (state.dictateBusy) {
          return;
        }
        stopDictationCapture({ fromHotkey: false }).catch(showError);
      });
    }

    if (el.attachmentStrip) {
      on(el.attachmentStrip, "click", function (event) {
        handleAttachmentStripClick(event);
      });
      on(el.attachmentStrip, "keydown", function (event) {
        handleAttachmentStripKeydown(event);
      });
    }

    if (el.runForm) {
      on(el.runForm, "dragenter", function (event) {
        onComposerDragEnter(event);
      });
      on(el.runForm, "dragover", function (event) {
        onComposerDragOver(event);
      });
      on(el.runForm, "dragleave", function (event) {
        onComposerDragLeave(event);
      });
      on(el.runForm, "drop", function (event) {
        try {
          onComposerDropped(event);
        } catch (error) {
          showError(error);
        }
      });
    }

    on(el.chatLog, "click", function (event) {
      var automationAction = event.target.closest(
        "[data-action='open-threads'], [data-action='automation-new'], [data-action='select-automation'], [data-action^='automation-']"
      );
      if (automationAction) {
        handleWorkspaceTreeClick(event);
        return;
      }
      var triageAction = event.target.closest("[data-action^='triage-']");
      if (triageAction) {
        handleWorkspaceTreeClick(event);
        return;
      }
      var stopBtn = event.target.closest("[data-action='stop-run'][data-workspace-id][data-conversation-id]");
      if (stopBtn) {
        event.preventDefault();
        var stopWorkspaceId = stopBtn.getAttribute("data-workspace-id") || "";
        var stopConversationId = stopBtn.getAttribute("data-conversation-id") || "";
        runWithControlPending(stopBtn, function () {
          return stopConversationRun(stopWorkspaceId, stopConversationId);
        }).catch(showError);
        return;
      }

      var retryLoadBtn = event.target.closest("[data-action='retry-load-conversation']");
      if (retryLoadBtn) {
        event.preventDefault();
        if (state.activeWorkspaceId && state.activeConversationId) {
          state.activeConversationLoadError = "";
          runWithControlPending(retryLoadBtn, function () {
            return loadConversation({
              workspaceId: state.activeWorkspaceId,
              conversationId: state.activeConversationId,
              showLoading: true,
              applyComposerDraft: true,
              timeoutMs: 15000
            }).then(function () {
              renderUi();
            });
          }, { spinner: false }).catch(showError);
        }
        return;
      }

      var copyBtn = event.target.closest("[data-action='copy-user-message']");
      if (!copyBtn) {
        return;
      }
      event.preventDefault();
      var text = copyBtn.getAttribute("data-copy-text") || "";
      copyTextToClipboard(text).then(function () {
        copyBtn.classList.add("copied");
        showTransientNotice("Copied text", { transparent: true });
        window.setTimeout(function () {
          copyBtn.classList.remove("copied");
        }, 900);
      });
    });

    on(el.chatLog, "keydown", function (event) {
      var key = event && event.key;
      if ((key === "Enter" || key === " ") && event.target && event.target.closest) {
        var automationRow = event.target.closest(".automation-row[role='button']");
        if (automationRow) {
          event.preventDefault();
          automationRow.click();
          return;
        }
      }
      if ((event && event.key) !== "Enter") {
        return;
      }
      var otherInput = event.target && event.target.closest ? event.target.closest("[data-triage-other-input]") : null;
      if (!otherInput) {
        return;
      }
      event.preventDefault();
      var proposalId = String(otherInput.getAttribute("data-triage-other-input") || "");
      if (!proposalId) {
        return;
      }
      var submitBtn = el.chatLog.querySelector("button[data-action='triage-decision-other-submit'][data-proposal-id='" + proposalId + "']");
      if (submitBtn) {
        submitBtn.click();
      }
    });

    on(el.chatLog, "change", function (event) {
      var automationToggle = event.target && event.target.closest ? event.target.closest("[data-action='automation-toggle-enabled']") : null;
      if (!automationToggle) {
        return;
      }
      handleWorkspaceTreeChange(event);
    });

    if (el.chatLog) {
      el.chatLog.addEventListener("toggle", function (event) {
        var panel = event.target;
        if (panel && panel.matches && panel.matches("details.run-activity-digest[data-digest-event-id]")) {
          var digestEventId = String(panel.getAttribute("data-digest-event-id") || "");
          if (digestEventId) {
            state.runDigestOpenByEventId[digestEventId] = panel.open ? 1 : 0;
          }
          return;
        }
        if (!panel || !panel.matches || !panel.matches("details.run-details[data-event-id]")) {
          return;
        }
        var eventId = String(panel.getAttribute("data-event-id") || "");
        if (!eventId) {
          return;
        }
        state.runDetailsOpenByEventId[eventId] = panel.open ? 1 : 0;
        if (panel.open) {
          var preview = panel.querySelector(".run-live-feed");
          if (preview) {
            preview.scrollTop = preview.scrollHeight;
            state.runStreamAutoFollowByEventId[eventId] = true;
            state.runStreamScrollTopByEventId[eventId] = preview.scrollTop;
          }
        }
      }, true);
      el.chatLog.addEventListener("scroll", function (event) {
        var target = event && event.target;
        if (!target || !target.classList || !target.classList.contains("run-live-feed")) {
          return;
        }
        var panel = target.closest("details.run-details.run-thinking[data-event-id]");
        if (!panel) {
          return;
        }
        var eventId = String(panel.getAttribute("data-event-id") || "");
        if (!eventId) {
          return;
        }
        state.runStreamScrollTopByEventId[eventId] = Number(target.scrollTop || 0);
        state.runStreamAutoFollowByEventId[eventId] = isElementScrollAtBottom(target, 8);
      }, true);
    }

    on(el.chatLog, "scroll", function () {
      state.chatAutoScroll = isChatAtBottom();
      updateChatJumpButton();
    });

    on(el.chatJumpBottomBtn, "click", function () {
      jumpChatToBottom();
    });

    if (el.queueTray) {
      function clearQueueDragUi() {
        if (!el.queueTrayList) {
          return;
        }
        var rows = el.queueTrayList.querySelectorAll(".queue-item");
        for (var i = 0; i < rows.length; i += 1) {
          rows[i].classList.remove("queue-item-dragging");
          rows[i].classList.remove("queue-item-drop-target");
        }
      }

      function clearQueueDragState() {
        state.queueDrag.active = false;
        state.queueDrag.workspaceId = "";
        state.queueDrag.conversationId = "";
        state.queueDrag.itemId = "";
        clearQueueDragUi();
      }

      on(el.queueTray, "dragstart", function (event) {
        var handle = event.target.closest("[data-action='queue-drag-handle'][data-queue-item-id]");
        if (!handle) {
          event.preventDefault();
          return;
        }
        var row = handle.closest(".queue-item[data-queue-item-id]");
        var wsId = String(state.activeWorkspaceId || "");
        var convId = String(state.activeConversationId || "");
        var itemId = String(handle.getAttribute("data-queue-item-id") || "");
        if (!row || !wsId || !convId || !itemId || state.queueEdit.itemId) {
          event.preventDefault();
          return;
        }
        state.queueDrag.active = true;
        state.queueDrag.workspaceId = wsId;
        state.queueDrag.conversationId = convId;
        state.queueDrag.itemId = itemId;
        row.classList.add("queue-item-dragging");
        if (event.dataTransfer) {
          event.dataTransfer.effectAllowed = "move";
          event.dataTransfer.setData("text/plain", itemId);
        }
      });

      on(el.queueTray, "dragover", function (event) {
        if (!state.queueDrag.active || !el.queueTrayList) {
          return;
        }
        var overRow = event.target.closest(".queue-item[data-queue-item-id]");
        if (!overRow || overRow.classList.contains("queue-item-editing")) {
          return;
        }
        var draggingId = String(state.queueDrag.itemId || "");
        var overId = String(overRow.getAttribute("data-queue-item-id") || "");
        if (!draggingId || !overId || draggingId === overId) {
          return;
        }
        event.preventDefault();
        clearQueueDragUi();
        overRow.classList.add("queue-item-drop-target");
        var dragRow = el.queueTrayList.querySelector(".queue-item[data-queue-item-id='" + escAttr(draggingId) + "']");
        if (!dragRow || dragRow === overRow) {
          return;
        }
        var rect = overRow.getBoundingClientRect();
        var insertAfter = event.clientY > rect.top + (rect.height / 2);
        if (insertAfter) {
          if (overRow.nextSibling !== dragRow) {
            el.queueTrayList.insertBefore(dragRow, overRow.nextSibling);
          }
        } else {
          el.queueTrayList.insertBefore(dragRow, overRow);
        }
      });

      on(el.queueTray, "drop", function (event) {
        if (!state.queueDrag.active || !el.queueTrayList) {
          return;
        }
        event.preventDefault();
        var wsId = String(state.queueDrag.workspaceId || "");
        var convId = String(state.queueDrag.conversationId || "");
        var orderedIds = [];
        var rows = el.queueTrayList.querySelectorAll(".queue-item[data-queue-item-id]:not(.queue-item-editing)");
        for (var i = 0; i < rows.length; i += 1) {
          orderedIds.push(String(rows[i].getAttribute("data-queue-item-id") || ""));
        }
        clearQueueDragState();
        if (orderedIds.length > 1) {
          reorderQueuedMessages(wsId, convId, orderedIds).catch(showError);
        }
      });

      on(el.queueTray, "dragend", function () {
        clearQueueDragState();
      });

      on(el.queueTray, "click", function (event) {
        var wsId = String(state.activeWorkspaceId || "");
        var convId = String(state.activeConversationId || "");
        if (!wsId || !convId) {
          return;
        }

        var dragHandle = event.target.closest("[data-action='queue-drag-handle'][data-queue-item-id]");
        if (dragHandle) {
          event.preventDefault();
          return;
        }

        var steerBtn = event.target.closest("[data-action='queue-steer-item'][data-queue-item-id]");
        if (steerBtn) {
          event.preventDefault();
          clearQueueEditPostSaveHold(wsId, convId);
          var steerItemId = steerBtn.getAttribute("data-queue-item-id") || "";
          runWithControlPending(steerBtn, function () {
            return steerQueuedMessage(steerItemId, {
              workspaceId: wsId,
              conversationId: convId,
              interruptRunning: true
            });
          }).catch(showError);
          return;
        }

        var trashBtn = event.target.closest("[data-action='queue-trash-item'][data-queue-item-id]");
        if (trashBtn) {
          event.preventDefault();
          clearQueueEditPostSaveHold(wsId, convId);
          var trashItemId = trashBtn.getAttribute("data-queue-item-id") || "";
          runWithControlPending(trashBtn, function () {
            return cancelQueuedMessage(trashItemId, {
              workspaceId: wsId,
              conversationId: convId
            });
          }).catch(showError);
          return;
        }

        var editBtn = event.target.closest("[data-action='queue-edit-item'][data-queue-item-id]");
        if (editBtn) {
          event.preventDefault();
          var editItemId = editBtn.getAttribute("data-queue-item-id") || "";
          var queueItems = queueItemsForConversation(wsId, convId);
          var editPrompt = "";
          for (var i = 0; i < queueItems.length; i += 1) {
            if (String((queueItems[i] && queueItems[i].id) || "") === String(editItemId)) {
              editPrompt = String((queueItems[i] && queueItems[i].prompt) || "");
              break;
            }
          }
          beginQueueItemEdit(wsId, convId, editItemId, editPrompt);
          renderUi();
          setTimeout(function () {
            var field = el.queueTray.querySelector("textarea[data-action='queue-edit-input'][data-queue-item-id='" + escAttr(editItemId) + "']");
            if (field) {
              field.focus();
              field.selectionStart = field.value.length;
              field.selectionEnd = field.value.length;
            }
          }, 0);
          return;
        }

        var saveBtn = event.target.closest("[data-action='queue-edit-save'][data-queue-item-id]");
        if (saveBtn) {
          event.preventDefault();
          var saveItemId = saveBtn.getAttribute("data-queue-item-id") || "";
          if (!isQueueEditForConversation(wsId, convId) || String(state.queueEdit.itemId || "") !== String(saveItemId)) {
            return;
          }
          if (state.queueEdit.saving) {
            return;
          }
          state.queueEdit.saving = true;
          var savedPrompt = String(state.queueEdit.draftText || "");
          renderUi();
          updateQueuedMessage(saveItemId, state.queueEdit.draftText, {
            workspaceId: wsId,
            conversationId: convId
          })
            .then(function () {
              armQueueEditPostSaveHold(wsId, convId, saveItemId, savedPrompt, 900);
              clearQueueEditState();
              showTransientNotice("Queued message updated");
              renderUi();
              kickQueueWorker();
            })
            .catch(function (error) {
              state.queueEdit.saving = false;
              renderUi();
              showError(error);
            });
          return;
        }

        var cancelBtn = event.target.closest("[data-action='queue-edit-cancel'][data-queue-item-id]");
        if (cancelBtn) {
          event.preventDefault();
          clearQueueEditState();
          renderUi();
          kickQueueWorker();
        }
      });

      on(el.queueTray, "input", function (event) {
        var input = event.target.closest("textarea[data-action='queue-edit-input'][data-queue-item-id]");
        if (!input) {
          return;
        }
        var itemId = String(input.getAttribute("data-queue-item-id") || "");
        if (!itemId || String(state.queueEdit.itemId || "") !== itemId) {
          return;
        }
        state.queueEdit.draftText = String(input.value || "");
      });

      on(el.queueTray, "keydown", function (event) {
        var input = event.target.closest("textarea[data-action='queue-edit-input'][data-queue-item-id]");
        if (!input) {
          return;
        }
        var itemId = String(input.getAttribute("data-queue-item-id") || "");
        if (!itemId || String(state.queueEdit.itemId || "") !== itemId) {
          return;
        }
        if (event.key === "Escape") {
          event.preventDefault();
          clearQueueEditState();
          renderUi();
          kickQueueWorker();
          return;
        }
        if (event.key === "Enter" && (event.metaKey || event.ctrlKey)) {
          event.preventDefault();
          if (state.queueEdit.saving) {
            return;
          }
          var editWsId = String(state.activeWorkspaceId || "");
          var editConvId = String(state.activeConversationId || "");
          state.queueEdit.saving = true;
          var savedPrompt = String(state.queueEdit.draftText || "");
          renderUi();
          updateQueuedMessage(itemId, state.queueEdit.draftText, {
            workspaceId: editWsId,
            conversationId: editConvId
          })
            .then(function () {
              armQueueEditPostSaveHold(
                editWsId,
                editConvId,
                itemId,
                savedPrompt,
                900
              );
              clearQueueEditState();
              showTransientNotice("Queued message updated");
              renderUi();
              kickQueueWorker();
            })
            .catch(function (error) {
              state.queueEdit.saving = false;
              renderUi();
              showError(error);
            });
        }
      });
    }

    if (el.runTodoMonitor) {
      el.runTodoMonitor.addEventListener("toggle", function () {
        if (!state.activeWorkspaceId || !state.activeConversationId) {
          return;
        }
        var todoKey = queueConversationKey(state.activeWorkspaceId, state.activeConversationId);
        if (!todoKey) {
          return;
        }
        state.runTodoMonitorOpenByConversation[todoKey] = el.runTodoMonitor.open ? 1 : 0;
      });
    }

    if (el.runTerminalMonitor) {
      el.runTerminalMonitor.addEventListener("toggle", function () {
        if (!state.activeWorkspaceId || !state.activeConversationId) {
          return;
        }
        var key = queueConversationKey(state.activeWorkspaceId, state.activeConversationId);
        if (!key) {
          return;
        }
        state.runTerminalMonitorOpenByConversation[key] = el.runTerminalMonitor.open ? 1 : 0;
      });
    }

    if (el.runTerminalMonitorStop) {
      on(el.runTerminalMonitorStop, "click", function (event) {
        event.preventDefault();
        event.stopPropagation();
        var wsId = String(el.runTerminalMonitorStop.dataset.workspaceId || state.activeWorkspaceId || "");
        var convId = String(el.runTerminalMonitorStop.dataset.conversationId || state.activeConversationId || "");
        if (!wsId || !convId) {
          return;
        }
        runWithControlPending(el.runTerminalMonitorStop, function () {
          return stopConversationRun(wsId, convId);
        }).catch(showError);
      });
    }

    if (el.queueSteerBtn) {
      on(el.queueSteerBtn, "click", function () {
        var fallbackItemId = trim((el.queueSteerBtn && el.queueSteerBtn.dataset.queueItemId) || "");
        runWithControlPending(el.queueSteerBtn, function () {
          return steerQueuedMessage(fallbackItemId, {
            workspaceId: state.activeWorkspaceId,
            conversationId: state.activeConversationId,
            interruptRunning: true
          });
        }).catch(showError);
      });
    }

    if (el.queueCancelBtn) {
      on(el.queueCancelBtn, "click", function () {
        var fallbackItemId = trim((el.queueCancelBtn && el.queueCancelBtn.dataset.queueItemId) || "");
        runWithControlPending(el.queueCancelBtn, function () {
          return cancelQueuedMessage(fallbackItemId, {
            workspaceId: state.activeWorkspaceId,
            conversationId: state.activeConversationId
          });
        }).catch(showError);
      });
    }

    on(el.runPrompt, "input", function () {
      rememberActiveComposerDraft();
      if (state.activeDraftWorkspaceId) {
        state.draftTextByWorkspace[state.activeDraftWorkspaceId] = el.runPrompt.value;
      }
      saveComposerDraftDebounced();
      renderRunButton();
    });

    on(el.runPrompt, "focus", function () {
      requestDictationPrepare({ silent: true }).catch(function () {
        return null;
      });
      startDictationPrepareLoop();
    });

    on(el.runPrompt, "blur", function () {
      if (!dictationPrepareLoopShouldRun()) {
        stopDictationPrepareLoop();
      }
    });

    on(el.runPrompt, "paste", function (event) {
      try {
        onPromptPaste(event);
      } catch (error) {
        showError(error);
      }
    });

    on(el.runPrompt, "keydown", function (event) {
      var key = String((event && event.key) || "").toLowerCase();
      if ((event.metaKey || event.ctrlKey) && !event.altKey) {
        if (
          (!event.shiftKey && (key === "a" || key === "c" || key === "x" || key === "v" || key === "z" || key === "y")) ||
          (event.shiftKey && key === "z")
        ) {
          // Keep native textarea editing shortcuts intact.
          if (typeof event.stopPropagation === "function") {
            event.stopPropagation();
          }
          return;
        }
      }
      if (event.key !== "Enter") {
        return;
      }
      if ((event.metaKey || event.ctrlKey) && event.shiftKey) {
        event.preventDefault();
        stopRunFromComposer().catch(showError);
        return;
      }
      if (event.shiftKey || event.altKey) {
        return;
      }

      var hasModifier = !!(event.metaKey || event.ctrlKey);
      var text = String(el.runPrompt.value || "");
      var hasNewline = text.indexOf("\n") >= 0;

      if (!hasModifier && hasNewline) {
        return;
      }

      event.preventDefault();
      if (el.runForm && typeof el.runForm.requestSubmit === "function") {
        el.runForm.requestSubmit();
      } else if (el.runForm) {
        onRunSubmit(event);
      }
    });

    function isEditableTarget(target) {
      var node = target && target.nodeType === 3 ? target.parentElement : target;
      if (!node || typeof node.closest !== "function") {
        return false;
      }
      if (node.closest("textarea, input, [contenteditable='true'], [contenteditable=''], [contenteditable]:not([contenteditable='false'])")) {
        return true;
      }
      return false;
    }

    function shouldBlockSideMouseButtonDefaultInEditable(event, trigger) {
      var triggerName = String(trigger || "");
      if (triggerName !== "mouse-button-4" && triggerName !== "mouse-button-5") {
        return false;
      }
      return isEditableTarget(event && event.target);
    }

    function shouldPreserveEditableShortcut(event) {
      if (!isEditableTarget(event && event.target)) {
        return false;
      }
      var key = String((event && event.key) || "").toLowerCase();
      var code = String((event && event.code) || "");
      var meta = !!(event && event.metaKey);
      var ctrl = !!(event && event.ctrlKey);
      var alt = !!(event && event.altKey);
      var shift = !!(event && event.shiftKey);
      if ((meta || ctrl) && !alt && !shift && (key === "a" || key === "c" || key === "x" || key === "v" || key === "z" || key === "y")) {
        return true;
      }
      if (meta && !ctrl && !alt && shift && key === "z") {
        return true;
      }
      if (meta && ctrl && !alt && !shift && (code === "Space" || key === " ")) {
        return true;
      }
      if (ctrl && !meta && !alt && !shift && (code === "Period" || key === ".")) {
        return true;
      }
      return false;
    }

    function shouldPreserveEditableDictationModifier(event, trigger) {
      if (!isEditableTarget(event && event.target)) {
        return false;
      }
      var t = String(trigger || "");
      if (t === "meta" || t === "control" || t === "alt" || t === "shift") {
        return true;
      }
      return false;
    }

    document.addEventListener("click", function (event) {
      if (Date.now() < suppressMenuCloseUntilMs) {
        return;
      }
      if (!event.target || typeof event.target.closest !== "function") {
        closeAllMenus();
        return;
      }
      if (event.target.closest(".modal-card")) {
        return;
      }
      if (
        event.target.closest("#model-status-btn") ||
        event.target.closest(".menu-anchor") ||
        event.target.closest(".models-pane") ||
        event.target.closest(".models-box") ||
        event.target.closest("#organize-menu") ||
        event.target.closest("#organize-btn") ||
        event.target.closest(".workspace-menu-trigger") ||
        event.target.closest("[data-workspace-menu]") ||
        event.target.closest("[data-triage-other-row]")
      ) {
        return;
      }
      if (state.triageOtherInputProposalId) {
        state.triageOtherInputProposalId = "";
      }
      state.openWorkspaceMenuWorkspaceId = "";
      closeAllMenus();
      renderUi();
    });

    document.addEventListener("keydown", function (event) {
      if (shouldPreserveEditableShortcut(event)) {
        return;
      }
      var dictationKeyTrigger = dictationShortcutKeyboardTrigger(event);
      if (shouldPreserveEditableDictationModifier(event, dictationKeyTrigger)) {
        return;
      }
      if (dictationKeyTrigger) {
        if (!event.repeat) {
          onDictationShortcutDown(dictationKeyTrigger, event);
        }
      }
      if (
        (event.metaKey || event.ctrlKey) &&
        !event.altKey &&
        !event.shiftKey &&
        String(event.key || "").toLowerCase() === "a"
      ) {
        if (!isEditableTarget(event.target)) {
          event.preventDefault();
          if (window.getSelection) {
            var selectAll = window.getSelection();
            if (selectAll && !selectAll.isCollapsed) {
              selectAll.removeAllRanges();
            }
          }
        }
        return;
      }

      if (event.key !== "Escape") {
        return;
      }

      if (window.getSelection) {
        var selection = window.getSelection();
        if (selection && !selection.isCollapsed) {
          event.preventDefault();
          selection.removeAllRanges();
          return;
        }
      }

      if (state.pickingWorkspace) {
        return;
      }

      if (!el.runActionModal.classList.contains("hidden")) {
        closeModal(el.runActionModal);
        return;
      }
      if (!el.automationModal.classList.contains("hidden")) {
        closeAutomationModal();
        return;
      }
      if (!el.commitModal.classList.contains("hidden")) {
        closeModal(el.commitModal);
        return;
      }
      if (!el.settingsModal.classList.contains("hidden")) {
        closeModal(el.settingsModal);
        return;
      }
      if (!el.commandApprovalModal.classList.contains("hidden")) {
        closeModal(el.commandApprovalModal);
        return;
      }
      if (pendingCommandApproval && typeof pendingCommandApproval.cancel === "function") {
        pendingCommandApproval.cancel(new Error("Command approval cancelled"));
        return;
      }
      if (!el.workspaceModal.classList.contains("hidden")) {
        closeModal(el.workspaceModal);
        return;
      }

      closeAllMenus();
    });

    document.addEventListener("keyup", function (event) {
      if (shouldPreserveEditableShortcut(event)) {
        return;
      }
      var dictationKeyTrigger = dictationShortcutKeyboardTrigger(event);
      if (shouldPreserveEditableDictationModifier(event, dictationKeyTrigger)) {
        return;
      }
      if (!dictationKeyTrigger) {
        return;
      }
      onDictationShortcutUp(dictationKeyTrigger, event);
    }, true);

    document.addEventListener("pointerdown", function (event) {
      var dictationMouseTrigger = dictationShortcutMouseTrigger(event);
      if (!dictationMouseTrigger) {
        return;
      }
      if (shouldBlockSideMouseButtonDefaultInEditable(event, dictationMouseTrigger)) {
        event.preventDefault();
        event.stopPropagation();
      }
      onDictationShortcutDown(dictationMouseTrigger, event);
    }, true);

    document.addEventListener("pointerup", function (event) {
      var dictationMouseTrigger = dictationShortcutMouseTrigger(event);
      if (!dictationMouseTrigger) {
        return;
      }
      if (shouldBlockSideMouseButtonDefaultInEditable(event, dictationMouseTrigger)) {
        event.preventDefault();
        event.stopPropagation();
      }
      onDictationShortcutUp(dictationMouseTrigger, event);
    }, true);

    document.addEventListener("mousedown", function (event) {
      var dictationMouseTrigger = dictationShortcutMouseTrigger(event);
      if (!dictationMouseTrigger) {
        return;
      }
      if (shouldBlockSideMouseButtonDefaultInEditable(event, dictationMouseTrigger)) {
        event.preventDefault();
        event.stopPropagation();
      }
      onDictationShortcutDown(dictationMouseTrigger, event);
    }, true);

    document.addEventListener("mouseup", function (event) {
      var dictationMouseTrigger = dictationShortcutMouseTrigger(event);
      if (!dictationMouseTrigger) {
        return;
      }
      if (shouldBlockSideMouseButtonDefaultInEditable(event, dictationMouseTrigger)) {
        event.preventDefault();
        event.stopPropagation();
      }
      onDictationShortcutUp(dictationMouseTrigger, event);
    }, true);

    document.addEventListener("auxclick", function (event) {
      var dictationMouseTrigger = dictationShortcutMouseTrigger(event);
      if (!dictationMouseTrigger) {
        return;
      }
      if (shouldBlockSideMouseButtonDefaultInEditable(event, dictationMouseTrigger)) {
        event.preventDefault();
        event.stopPropagation();
      }
      if (dictationMouseTrigger === "mouse-wheel-click") {
        if (state.dictateHotkeyHoldIntent && (state.dictateHotkeyHoldTrigger === "mouse-button-4" || state.dictateHotkeyHoldTrigger === "mouse-button-5")) {
          onDictationShortcutUp(state.dictateHotkeyHoldTrigger, event);
          event.preventDefault();
          event.stopPropagation();
        }
        return;
      }
      if (!shouldHandleDictationShortcutTrigger(dictationMouseTrigger)) {
        return;
      }
      var holdTrigger = normalizeDictationShortcut("hold", state.dictationShortcutHold);
      var toggleTrigger = normalizeDictationShortcut("toggle", state.dictationShortcutToggle);
      var bothSame = holdTrigger !== "none" && holdTrigger === toggleTrigger;
      var hasPressState = !!dictationShortcutPressState[dictationMouseTrigger];
      var holdActive = state.dictateHotkeyHoldIntent && state.dictateHotkeyHoldTrigger === dictationMouseTrigger;
      if (bothSame && dictationMouseTrigger === holdTrigger) {
        if (hasPressState || holdActive) {
          onDictationShortcutUp(dictationMouseTrigger, event);
        } else if (!dictationToggleTriggerHandledRecently(dictationMouseTrigger, 260)) {
          toggleDictationCapture({ fromHotkey: true, holdShortcut: false, startedAtMs: Date.now() }).catch(showError);
          markDictationToggleTriggered(dictationMouseTrigger);
        }
        event.preventDefault();
        event.stopPropagation();
        return;
      }
      if (dictationMouseTrigger === holdTrigger && dictationMouseTrigger !== toggleTrigger) {
        if (holdActive) {
          onDictationShortcutUp(dictationMouseTrigger, event);
        }
        event.preventDefault();
        event.stopPropagation();
        return;
      }
      if (dictationMouseTrigger === toggleTrigger && dictationMouseTrigger !== holdTrigger) {
        if (hasPressState) {
          onDictationShortcutUp(dictationMouseTrigger, event);
        } else if (!dictationToggleTriggerHandledRecently(dictationMouseTrigger, 260)) {
          onDictationShortcutDown(dictationMouseTrigger, event);
          onDictationShortcutUp(dictationMouseTrigger, event);
        }
        event.preventDefault();
        event.stopPropagation();
        return;
      }
      if (holdActive) {
        onDictationShortcutUp(dictationMouseTrigger, event);
      }
      event.preventDefault();
      event.stopPropagation();
    }, true);

    document.addEventListener("visibilitychange", function () {
      if (dictationPrepareLoopShouldRun()) {
        requestDictationPrepare({ silent: true }).catch(function () {
          return null;
        });
        startDictationPrepareLoop();
        return;
      }
      stopDictationPrepareLoop();
    });

    window.addEventListener("focus", function () {
      if (!dictationPrepareLoopShouldRun()) {
        return;
      }
      requestDictationPrepare({ silent: true }).catch(function () {
        return null;
      });
      startDictationPrepareLoop();
    });

    window.addEventListener("blur", function () {
      clearDictationShortcutPressState();
      endDictationHotkeyHold("");
      stopDictationPrepareLoop();
    });
  }

  window.addEventListener("beforeunload", function () {
    var unloadWorkspaceId = String(state.terminalSessionWorkspaceId || state.activeWorkspaceId || "");
    var unloadSessionId = String(state.terminalSessionId || "");
    stopTerminalPolling();
    if (unloadWorkspaceId && unloadSessionId) {
      apiPost("terminal_session_stop", {
        workspace_id: unloadWorkspaceId,
        session_id: unloadSessionId
      }, { timeoutMs: 1200 }).catch(function () {
        return null;
      });
    }
    if (liveRunTickTimer) {
      clearInterval(liveRunTickTimer);
      liveRunTickTimer = null;
    }
    persistPendingOutgoingNow();
    stopModelInstallPolling();
    stopModelAutoRefreshLoop();
    stopAutomationsTickLoop();
    stopRunEventHealLoop();
    stopPendingOutgoingReconcileLoop();
    stopApprovalResumeWatch();
    clearDictationUiTicker();
    stopDictationWaveMonitor();
    stopDictationPrepareLoop();
    clearDictationShortcutPressState();
    clearPendingAttachments();
  });

  try {
    hydrateWorkspaceStateFromCache();
  } catch (cacheErr) {
    if (window && window.console && typeof window.console.warn === "function") {
      window.console.warn("Artificer cache hydrate failed:", cacheErr);
    }
  }

  try {
    pruneExpiredPendingOutgoing();
  } catch (pendingErr) {
    if (window && window.console && typeof window.console.warn === "function") {
      window.console.warn("Artificer pending outgoing hydrate failed:", pendingErr);
    }
  }

  try {
    bindEvents();
  } catch (bindErr) {
    if (window && window.console && typeof window.console.error === "function") {
      window.console.error("Artificer bindEvents failed:", bindErr);
    }
  }

  try {
    renderUi();
  } catch (renderErr) {
    if (window && window.console && typeof window.console.error === "function") {
      window.console.error("Artificer renderUi failed:", renderErr);
    }
  }

  var artificerBootReadySent = false;
  function signalArtificerBootReady() {
    if (artificerBootReadySent) {
      return;
    }
    artificerBootReadySent = true;
    if (typeof window !== "undefined") {
      window.__artificerBooted = true;
    }
    notifyHostBoot("ready", {});
    if (!(window && window.wizardry && typeof window.wizardry.rpc === "function")) {
      return;
    }
    requestAnimationFrame(function () {
      requestAnimationFrame(function () {
        window.wizardry.rpc("bridge.exec", { argv: ["__wizardry_host_boot_ready"] }).catch(function () {
          return null;
        });
      });
    });
  }

  refreshAll()
    .catch(function (error) {
      if (!isRetriableRequestError(error)) {
        throw error;
      }
      return waitMs(320).then(function () {
        return refreshAll();
      });
    })
    .then(function () {
      kickQueueWorker();
      startModelAutoRefreshLoop();
      startAutomationsTickLoop();
      startRunEventHealLoop();
      startPendingOutgoingReconcileLoop();
      signalArtificerBootReady();
    })
    .catch(function (error) {
      state.initialLoadComplete = true;
      startAutomationsTickLoop();
      startRunEventHealLoop();
      startPendingOutgoingReconcileLoop();
      state.queueWorkerActive = false;
      kickQueueWorker();
      showError(error);
      signalArtificerBootReady();
    });
})();
