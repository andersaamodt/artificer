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

          html += "<div class='conversation-row" + activeConv + "' role='button' tabindex='0' title='Open thread' data-action='select-conversation' data-workspace-id='" + escHtml(workspaceId) + "' data-conversation-id='" + escHtml(conversation.id) + "'>";
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
        if (!installedSizeLabel) {
          installedSizeLabel = "Size unavailable";
        }
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
        html += "<span class='catalog-size catalog-size-right'>" + escHtml(installedSizeLabel) + "</span>";
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
        if (!sizeLabel) {
          sizeLabel = "Size unavailable";
        }
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
        html += "<span class='catalog-size catalog-size-right'>" + escHtml(sizeLabel) + "</span>";
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
