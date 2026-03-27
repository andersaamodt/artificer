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
