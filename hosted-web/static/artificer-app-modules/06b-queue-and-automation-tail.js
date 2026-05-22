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
