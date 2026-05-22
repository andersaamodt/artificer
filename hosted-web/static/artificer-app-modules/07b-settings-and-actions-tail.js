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
    var row = event.target.closest(".workspace-row[data-drag-type='workspace'][data-workspace-id], .conversation-row[data-drag-type='conversation'][data-workspace-id][data-conversation-id]");
    if (!row) {
      event.preventDefault();
      return;
    }
    var dragType = String(row.getAttribute("data-drag-type") || "");
    if (dragType !== "workspace") {
      event.preventDefault();
      return;
    }
    if (event.target.closest("button, a, input, select, textarea, label, [role='button']")) {
      event.preventDefault();
      return;
    }
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
    return apiGet("pick_workspace", {}, { timeoutMs: 900000 })
      .then(function (picked) {
        if (picked.success && picked.cancelled) {
          var elapsedMs = Date.now() - browseStartedAt;
          if (elapsedMs < 300 && openDirPickerFallback()) {
            return;
          }
          return;
        }

        var pickedPath = trim(String(
          (picked && (picked.path || picked.workspace_path || picked.selected_path)) || ""
        ));
        if (picked.success && pickedPath) {
          el.workspacePath.value = pickedPath;
          updateWorkspaceNamePlaceholderFromPath(pickedPath);
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
            state.programmerReviewRounds,
            state.reflexiveKnowledge,
            state.selfActuation
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
