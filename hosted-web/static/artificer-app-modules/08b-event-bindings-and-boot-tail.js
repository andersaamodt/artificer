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
    flushDurableUiStateWritesNow();
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
      // Keep model data self-healing even when initial state bootstrap fails.
      startModelAutoRefreshLoop();
      refreshModelData({ force: true, silent: false }).catch(function () {
        return null;
      });
      startAutomationsTickLoop();
      startRunEventHealLoop();
      startPendingOutgoingReconcileLoop();
      state.queueWorkerActive = false;
      kickQueueWorker();
      showError(error);
      signalArtificerBootReady();
    });
})();
