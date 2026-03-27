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
