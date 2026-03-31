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
    var next = normalizePermissionModeValue(mode) || "default";
    state.permissionMode = next;
    storageSet("artificer.permissionMode", next);
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
