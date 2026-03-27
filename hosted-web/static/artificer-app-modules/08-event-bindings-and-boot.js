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

    on(el.modelsBoxHead, "click", function (event) {
      event.preventDefault();
      event.stopPropagation();
      if (el.modelsPane && !el.modelsPane.classList.contains("hidden")) {
        closeAllMenus();
      }
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
