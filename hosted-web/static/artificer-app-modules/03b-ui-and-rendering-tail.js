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
