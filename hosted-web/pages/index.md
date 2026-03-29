---
title: ""
pagetitle: "Artificer"
---
<link rel="stylesheet" href="/static/style.css?v=20260325-selfimprovecomp1" />
<link id="artificer-theme-stylesheet" rel="stylesheet" href="/static/themes/psionic.css" />
<div class="artificer-shell" id="artificer-shell">
<aside class="workspace-sidebar" id="workspace-dropzone" tabindex="0">
<div id="organize-menu" class="floating-menu organize-menu hidden" role="menu" aria-label="Organize menu">
<p class="organize-title">Organize</p>
<button type="button" data-organize-mode="project"><span>By project</span><span class="check" aria-hidden="true">&check;</span></button>
<button type="button" data-organize-mode="chrono"><span>Chronological list</span><span class="check" aria-hidden="true">&check;</span></button>
<div class="menu-sep"></div>
<p class="organize-group">Sort by</p>
<button type="button" data-organize-sort="created"><span>Created</span><span class="check" aria-hidden="true">&check;</span></button>
<button type="button" data-organize-sort="updated"><span>Updated</span><span class="check" aria-hidden="true">&check;</span></button>
<div class="menu-sep"></div>
<p class="organize-group">Show</p>
<button type="button" data-organize-show="all"><span>All threads</span><span class="check" aria-hidden="true">&check;</span></button>
<button type="button" data-organize-show="relevant"><span>Relevant</span><span class="check" aria-hidden="true">&check;</span></button>
<button type="button" data-organize-show="running"><span>Running</span><span class="check" aria-hidden="true">&check;</span></button>
</div>
<div class="workspace-drag-strip" aria-hidden="true"></div>
<div id="sidebar-nav-list" class="sidebar-nav-list" role="listbox" aria-label="Sidebar views">
<div id="sidebar-nav-automations-item" class="sidebar-nav-item" role="option" tabindex="0" aria-selected="false" title="Open automations">
<span class="sidebar-nav-item-icon" aria-hidden="true"><svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"><circle cx="8" cy="8.2" r="5.2"></circle><path d="M8 5.6v2.8l1.8 1"></path></svg></span>
<span class="sidebar-nav-item-label">Automations</span>
<span id="sidebar-nav-automations-count" class="sidebar-nav-item-count">0</span>
</div>
</div>
<div class="workspace-tree-section-head workspace-tree-main-head">
<span id="workspace-tree-title">Threads</span>
<div class="workspace-head-actions">
<button id="add-workspace-btn" class="icon-btn" type="button" aria-label="New project" title="New project"><span aria-hidden="true"><svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M1.7 5.2h4l1.3 1.6h7.3v6.2H1.7z"/><path d="M11.8 2.8v2.4"/><path d="M10.6 4h2.4"/></svg></span></button>
<button id="organize-btn" class="icon-btn" type="button" aria-label="Organize projects" title="Organize threads"><span aria-hidden="true"><svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"><path d="M2.5 4h11"/><path d="M3.8 8h8.4"/><path d="M5.1 12h5.8"/></svg></span></button>
</div>
</div>
<div id="workspace-tree" class="workspace-tree"></div>
<div id="models-pane" class="models-pane hidden">
<div id="models-pane-resizer" class="models-pane-resizer" aria-hidden="true"></div>
<div class="models-box" id="models-box" role="dialog" aria-label="Available models">
<div id="models-box-head" class="models-box-head"><span class="models-title">Ollama Models</span></div>
<div id="models-box-list" class="models-box-list"></div>
</div>
</div>
<div class="workspace-sidebar-footer">
<button id="settings-btn" class="footer-row footer-gear" type="button" aria-label="Settings" title="Settings"><svg class="footer-gear-glyph" viewBox="0 0 14 14" aria-hidden="true" focusable="false"><path d="M14 8.3V5.73l-1.58-.264c-.117-.44-.292-.848-.496-1.2l.93-1.285-1.81-1.84-1.31.908c-.371-.205-.781-.38-1.187-.497L8.288 0H5.72l-.263 1.578c-.437.117-.816.293-1.196.497L2.979 1.17 1.141 2.98l.934 1.287c-.2.38-.376.79-.493 1.228L.004 5.73V8.3l1.575.264c.117.438.292.818.496 1.198l-.93 1.315 1.809 1.813 1.312-.938c.38.205.787.38 1.224.497l.26 1.55h2.566l.263-1.58c.408-.117.817-.293 1.196-.497l1.315.935 1.81-1.812-.935-1.315c.203-.38.38-.76.495-1.2L14 8.305zM7 9.704c-1.488 0-2.683-1.2-2.683-2.69S5.542 4.327 7 4.327s2.683 1.198 2.683 2.69c0 1.49-1.195 2.688-2.683 2.688z" fill="currentColor"/></svg></button>
<div class="menu-anchor footer-theme-anchor">
<button id="theme-picker-btn" class="footer-row footer-theme-btn" type="button" aria-haspopup="menu" aria-expanded="false" title="Select theme">Psionic</button>
<div id="theme-picker-menu" class="floating-menu hidden" role="menu" aria-label="Theme selector">
<div id="theme-picker-list" class="menu-list"></div>
</div>
</div>
<button id="model-status-btn" class="footer-row footer-model" type="button" aria-haspopup="dialog" aria-expanded="false" title="Installed Ollama models">Checking models...</button>
</div>
</aside>
<div id="threads-resizer" class="pane-resizer threads-resizer" aria-hidden="true"></div>

<main class="main-shell">
<header class="toolbar">
<div class="toolbar-left">
<h2 id="chat-title" class="toolbar-title">No thread</h2>
<button id="workspace-path-widget" class="path-widget" type="button" title="No project selected" aria-label="Project path"></button>
</div>
<div class="toolbar-right">
<div id="triage-toolbar-actions" class="menu-anchor split-anchor triage-toolbar-actions hidden">
<div class="split-btn">
<button id="triage-cleanup-main-btn" class="toolbar-btn split-main" type="button" data-action="triage-cleanup" title="Recompress current triage decisions">Cleanup...</button>
<button id="triage-cleanup-menu-btn" class="toolbar-btn split-caret" type="button" aria-haspopup="menu" aria-expanded="false" aria-label="Cleanup menu" title="Cleanup options"><span aria-hidden="true">&#9662;</span></button>
</div>
<div id="triage-cleanup-menu" class="floating-menu hidden" role="menu" aria-label="Cleanup options">
<button type="button" data-action="triage-cleanup-guided">Cleanup with guidance...</button>
</div>
</div>
<button id="run-action-btn" class="toolbar-btn run-play-btn" type="button" aria-label="Run action" title="Run action">
<span aria-hidden="true">&#9654;</span>
</button>
<div class="menu-anchor split-anchor">
<div class="split-btn">
<button id="open-main-btn" class="toolbar-btn split-main" type="button" title="Open current project"></button>
<button id="open-menu-btn" class="toolbar-btn split-caret" type="button" aria-haspopup="menu" aria-expanded="false" aria-label="Open menu" title="Choose open target"><span aria-hidden="true">&#9662;</span></button>
</div>
<div id="open-menu" class="floating-menu hidden" role="menu" aria-label="Open in">
<button type="button" data-open-target="finder" title="Open in Finder"><span class="menu-icon app-icon finder-icon" aria-hidden="true"></span><span>Finder</span></button>
<button type="button" data-open-target="terminal" title="Open in Terminal"><span class="menu-icon app-icon terminal-app-icon" aria-hidden="true"><svg viewBox="0 0 16 16" fill="none"><rect x="1.2" y="2" width="13.6" height="12" rx="2.2" fill="#181B2A" stroke="#454A66" stroke-width="1"/><path d="M4 6.1l2 1.9L4 9.9" stroke="#D8DEFF" stroke-width="1.2" stroke-linecap="round" stroke-linejoin="round"/><path d="M7.8 10h4.2" stroke="#D8DEFF" stroke-width="1.2" stroke-linecap="round"/></svg></span><span>Terminal</span></button>
<button type="button" data-open-target="textmate" title="Open in TextMate"><span class="menu-icon app-icon textmate-icon" aria-hidden="true"><svg viewBox="0 0 16 16" fill="none"><circle cx="8" cy="8" r="6.3" fill="#F5ECFF" stroke="#A669D8" stroke-width="1"/><path d="M8 3.2l1.2 2.2 2.3-.8-.9 2.2 2.2 1.2-2.2 1.2.9 2.2-2.3-.8L8 12.8l-1.2-2.2-2.3.8.9-2.2L3.2 8l2.2-1.2-.9-2.2 2.3.8L8 3.2z" fill="#B84FE8"/></svg></span><span>TextMate</span></button>
</div>
</div>
<div class="menu-anchor split-anchor">
<div class="split-btn">
<button id="commit-main-btn" class="toolbar-btn split-main" type="button" title="Primary commit action"></button>
<button id="commit-menu-btn" class="toolbar-btn split-caret" type="button" aria-haspopup="menu" aria-expanded="false" aria-label="Commit menu" title="Choose commit action"><span aria-hidden="true">&#9662;</span></button>
</div>
<div id="commit-menu" class="floating-menu hidden" role="menu" aria-label="Commit actions">
<button type="button" data-commit-action="commit" title="Create commit"><span class="menu-icon" aria-hidden="true">&#10227;</span><span>Commit</span></button>
<button type="button" data-commit-action="push" title="Push current branch"><span class="menu-icon" aria-hidden="true">&#10548;</span><span>Push</span></button>
<button type="button" data-commit-action="commit-push" title="Commit and push"><span class="menu-icon" aria-hidden="true">&#10549;</span><span>Commit and push</span></button>
</div>
</div>
<span class="toolbar-divider commit-terminal-divider" aria-hidden="true"></span>
<button id="terminal-toggle-btn" class="toolbar-btn terminal-icon-btn" type="button" aria-label="Terminal" title="Toggle terminal">
<span aria-hidden="true"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="4" width="18" height="15" rx="2"></rect><path d="M8 10l2 2-2 2"></path><path d="M12.5 15h4"></path></svg></span>
</button>
<button id="changes-btn" class="toolbar-btn changes-btn" type="button" title="Open diff panel"><span class="git-delta"><span class="git-add">+0</span> <span class="git-del">-0</span></span></button>
</div>
</header>

<section class="chat-shell">
<div id="command-approval-inline" class="command-approval-inline hidden" role="region" aria-label="Command approval request">
<div class="command-approval-inline-head">
<strong>Command approval required</strong>
<button id="command-approval-inline-close" class="icon-btn ghost" type="button" aria-label="Close command approval">&times;</button>
</div>
<p id="command-approval-inline-text" class="settings-hint">The agent requested a command.</p>
<pre id="command-approval-inline-command" class="terminal-output"></pre>
<label for="command-approval-inline-match-mode">Remember rule type</label>
<select id="command-approval-inline-match-mode">
<option value="exact">Exact command</option>
<option value="regex">Regex pattern</option>
</select>
<label for="command-approval-inline-pattern">Remember pattern</label>
<input id="command-approval-inline-pattern" placeholder="^git([[:space:]].*)?$" />
<div class="modal-actions two-col">
<button id="command-approval-inline-allow-once" type="button">Allow once</button>
<button id="command-approval-inline-deny-once" class="ghost" type="button">Deny once</button>
</div>
<div class="modal-actions two-col">
<button id="command-approval-inline-allow-remember" type="button">Allow + remember</button>
<button id="command-approval-inline-deny-remember" class="ghost" type="button">Deny + remember</button>
</div>
</div>
<div id="decision-request-inline" class="decision-request-inline hidden" role="region" aria-label="Decision request">
<div class="decision-request-head">
<strong>Decision required</strong>
<button id="decision-request-inline-close" class="icon-btn ghost" type="button" aria-label="Hide decision request">&times;</button>
</div>
<p id="decision-request-inline-question" class="decision-request-question"></p>
<form id="decision-request-form" class="decision-request-form">
<div id="decision-request-options" class="decision-request-options"></div>
<div id="decision-request-other-wrap" class="decision-request-other-wrap hidden">
<label for="decision-request-other-input">Other</label>
<input id="decision-request-other-input" placeholder="Type your decision" />
</div>
<div class="modal-actions">
<button id="decision-request-submit" type="submit">Submit decision</button>
</div>
</form>
</div>
<div id="chat-log" class="chat-log"></div>
<button id="chat-jump-bottom-btn" class="chat-jump-bottom hidden" type="button" aria-label="Jump to latest message">
<span aria-hidden="true">&darr;</span>
</button>
<form id="run-form" class="run-form">
<textarea id="run-prompt" rows="4" placeholder="Enter instructions"></textarea>
<div id="attachment-strip" class="attachment-strip hidden" aria-live="polite"></div>
<details id="run-todo-monitor" class="run-todo-monitor hidden">
<summary>
<span id="run-todo-monitor-label">0 out of 0 tasks completed</span>
</summary>
<ol id="run-todo-monitor-list" class="run-todo-monitor-list"></ol>
</details>
<div id="queue-tray" class="queue-tray hidden" aria-live="polite">
<div id="queue-tray-list" class="queue-tray-list"></div>
</div>
<details id="run-terminal-monitor" class="run-terminal-monitor hidden">
<summary>
<span id="run-terminal-monitor-label">Running 1 terminal</span>
<button id="run-terminal-monitor-stop" class="run-terminal-monitor-stop" type="button" aria-label="Stop active run">Stop</button>
</summary>
<pre id="run-terminal-monitor-output" class="terminal-output run-terminal-monitor-output"></pre>
</details>
<div id="composer-row" class="composer-row">
<button id="attach-btn" class="attach-btn" type="button" aria-label="Attach files" title="Attach files">+</button>
<input id="attachment-picker" type="file" multiple hidden />
<div class="menu-anchor model-anchor">
<button id="model-picker-btn" class="model-picker-btn" type="button" aria-haspopup="menu" aria-expanded="false" title="Select model">Select model</button>
<div id="model-picker-menu" class="floating-menu hidden" role="menu" aria-label="Model selector">
<div id="model-picker-list" class="model-picker-list"></div>
</div>
</div>
<div class="menu-anchor run-mode-anchor">
<button id="run-mode-btn" class="run-mode-btn" type="button" aria-haspopup="menu" aria-expanded="false" title="Run mode">Auto/Thinking</button>
<div id="run-mode-menu" class="floating-menu hidden" role="menu" aria-label="Run mode selector">
<p class="menu-title">Run mode</p>
<button type="button" class="run-mode-item" data-run-mode="instant"><span class="run-mode-row"><span class="run-mode-name">Instant</span><span class="check" aria-hidden="true">&check;</span></span><span class="run-mode-blurb hidden">Single-pass reply.</span></button>
<button type="button" class="run-mode-item" data-run-mode="auto"><span class="run-mode-row"><span class="run-mode-name">Auto/Thinking</span><span class="check" aria-hidden="true">&check;</span></span><span class="run-mode-blurb hidden">Balanced loop.</span></button>
<button type="button" class="run-mode-item" data-run-mode="programming"><span class="run-mode-row"><span class="run-mode-name">Programming</span><span class="check" aria-hidden="true">&check;</span></span><span class="run-mode-blurb hidden">Build and verify code.</span></button>
<button type="button" class="run-mode-item" data-run-mode="pentest"><span class="run-mode-row"><span class="run-mode-name">Pentest</span><span class="check" aria-hidden="true">&check;</span></span><span class="run-mode-blurb hidden">Adversarial exploit-path testing and mitigation.</span></button>
<button type="button" class="run-mode-item" data-run-mode="security-audit"><span class="run-mode-row"><span class="run-mode-name">Security Audit</span><span class="check" aria-hidden="true">&check;</span></span><span class="run-mode-blurb hidden">Systematic hardening and risk remediation.</span></button>
<button type="button" class="run-mode-item" data-run-mode="chat"><span class="run-mode-row"><span class="run-mode-name">Chat</span><span class="check" aria-hidden="true">&check;</span></span><span class="run-mode-blurb hidden">Conversation-first help.</span></button>
<button type="button" class="run-mode-item" data-run-mode="teacher"><span class="run-mode-row"><span class="run-mode-name">Teacher</span><span class="check" aria-hidden="true">&check;</span></span><span class="run-mode-blurb hidden">Adaptive tutoring.</span></button>
<button type="button" class="run-mode-item" data-run-mode="report"><span class="run-mode-row"><span class="run-mode-name">Report</span><span class="check" aria-hidden="true">&check;</span></span><span class="run-mode-blurb hidden">Investigate and summarize.</span></button>
<button type="button" class="run-mode-item" data-run-mode="text-perfecter"><span class="run-mode-row"><span class="run-mode-name">Text Perfecter</span><span class="check" aria-hidden="true">&check;</span></span><span class="run-mode-blurb hidden">Perfect text and content with deep research.</span></button>
<button type="button" class="run-mode-item" data-run-mode="gui-testing"><span class="run-mode-row"><span class="run-mode-name">GUI Testing</span><span class="check" aria-hidden="true">&check;</span></span><span class="run-mode-blurb hidden">Hands-on automation with strict UX quality gates.</span></button>
<button type="button" class="run-mode-item" data-run-mode="assistant"><span class="run-mode-row"><span class="run-mode-name">Team</span><span class="check" aria-hidden="true">&check;</span></span><span class="run-mode-blurb hidden">Run with a globally configured LLM team.</span></button>
<div class="menu-sep"></div>
<button id="run-mode-more-toggle" type="button" data-action="run-mode-more-toggle" aria-expanded="false"><span>Team &rsaquo;</span><span class="run-mode-more-caret" aria-hidden="true">&#8250;</span></button>
<div id="run-mode-more-list" class="run-mode-more-list hidden"></div>
</div>
</div>
<div class="menu-anchor composer-reasoning-anchor">
<button id="reasoning-menu-btn" class="reasoning-btn" type="button" aria-haspopup="menu" aria-expanded="false" title="Reasoning depth (not time limit)"><span class="menu-icon reasoning-brain-icon" aria-hidden="true"><svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.35" stroke-linecap="round" stroke-linejoin="round"><path d="M5.1 3.2c-.9 0-1.8.7-1.8 1.8 0 .4.1.8.4 1.1-.7.4-1.1 1-1.1 1.8 0 1.2.9 2.1 2.1 2.1.1 1.1 1 1.9 2.1 1.9 1 0 1.8-.6 2.1-1.5.2.9 1.1 1.5 2.1 1.5 1.1 0 2-.8 2.1-1.9 1.2 0 2.1-.9 2.1-2.1 0-.8-.4-1.4-1.1-1.8.2-.3.4-.7.4-1.1 0-1-.8-1.8-1.8-1.8-.4 0-.8.1-1.1.4-.4-.8-1.2-1.3-2.1-1.3-.9 0-1.7.5-2.1 1.3-.3-.2-.7-.4-1.1-.4z"></path><path d="M6.3 5.8c-.6.2-.9.6-.9 1.1"></path><path d="M8 5.4v4.3"></path><path d="M9.8 5.9c.6.2.9.6.9 1.1"></path><path d="M6.4 8.6c.4.4 1 .6 1.6.6"></path><path d="M9.6 8.6c-.4.4-1 .6-1.6.6"></path></svg></span><span>Medium</span></button>
<div id="reasoning-menu" class="floating-menu hidden" role="menu" aria-label="Reasoning effort">
<p class="menu-title">Reasoning depth</p>
<button type="button" data-reasoning="low"><span class="menu-icon reasoning-brain-icon" aria-hidden="true"><svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.35" stroke-linecap="round" stroke-linejoin="round"><path d="M5.1 3.2c-.9 0-1.8.7-1.8 1.8 0 .4.1.8.4 1.1-.7.4-1.1 1-1.1 1.8 0 1.2.9 2.1 2.1 2.1.1 1.1 1 1.9 2.1 1.9 1 0 1.8-.6 2.1-1.5.2.9 1.1 1.5 2.1 1.5 1.1 0 2-.8 2.1-1.9 1.2 0 2.1-.9 2.1-2.1 0-.8-.4-1.4-1.1-1.8.2-.3.4-.7.4-1.1 0-1-.8-1.8-1.8-1.8-.4 0-.8.1-1.1.4-.4-.8-1.2-1.3-2.1-1.3-.9 0-1.7.5-2.1 1.3-.3-.2-.7-.4-1.1-.4z"></path><path d="M6.3 5.8c-.6.2-.9.6-.9 1.1"></path><path d="M8 5.4v4.3"></path><path d="M9.8 5.9c.6.2.9.6.9 1.1"></path><path d="M6.4 8.6c.4.4 1 .6 1.6.6"></path><path d="M9.6 8.6c-.4.4-1 .6-1.6.6"></path></svg></span><span>Low</span><span class="check" aria-hidden="true">&check;</span></button>
<button type="button" data-reasoning="medium"><span class="menu-icon reasoning-brain-icon" aria-hidden="true"><svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.35" stroke-linecap="round" stroke-linejoin="round"><path d="M5.1 3.2c-.9 0-1.8.7-1.8 1.8 0 .4.1.8.4 1.1-.7.4-1.1 1-1.1 1.8 0 1.2.9 2.1 2.1 2.1.1 1.1 1 1.9 2.1 1.9 1 0 1.8-.6 2.1-1.5.2.9 1.1 1.5 2.1 1.5 1.1 0 2-.8 2.1-1.9 1.2 0 2.1-.9 2.1-2.1 0-.8-.4-1.4-1.1-1.8.2-.3.4-.7.4-1.1 0-1-.8-1.8-1.8-1.8-.4 0-.8.1-1.1.4-.4-.8-1.2-1.3-2.1-1.3-.9 0-1.7.5-2.1 1.3-.3-.2-.7-.4-1.1-.4z"></path><path d="M6.3 5.8c-.6.2-.9.6-.9 1.1"></path><path d="M8 5.4v4.3"></path><path d="M9.8 5.9c.6.2.9.6.9 1.1"></path><path d="M6.4 8.6c.4.4 1 .6 1.6.6"></path><path d="M9.6 8.6c-.4.4-1 .6-1.6.6"></path></svg></span><span>Medium</span><span class="check" aria-hidden="true">&check;</span></button>
<button type="button" data-reasoning="high"><span class="menu-icon reasoning-brain-icon" aria-hidden="true"><svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.35" stroke-linecap="round" stroke-linejoin="round"><path d="M5.1 3.2c-.9 0-1.8.7-1.8 1.8 0 .4.1.8.4 1.1-.7.4-1.1 1-1.1 1.8 0 1.2.9 2.1 2.1 2.1.1 1.1 1 1.9 2.1 1.9 1 0 1.8-.6 2.1-1.5.2.9 1.1 1.5 2.1 1.5 1.1 0 2-.8 2.1-1.9 1.2 0 2.1-.9 2.1-2.1 0-.8-.4-1.4-1.1-1.8.2-.3.4-.7.4-1.1 0-1-.8-1.8-1.8-1.8-.4 0-.8.1-1.1.4-.4-.8-1.2-1.3-2.1-1.3-.9 0-1.7.5-2.1 1.3-.3-.2-.7-.4-1.1-.4z"></path><path d="M6.3 5.8c-.6.2-.9.6-.9 1.1"></path><path d="M8 5.4v4.3"></path><path d="M9.8 5.9c.6.2.9.6.9 1.1"></path><path d="M6.4 8.6c.4.4 1 .6 1.6.6"></path><path d="M9.6 8.6c-.4.4-1 .6-1.6.6"></path></svg></span><span>High</span><span class="check" aria-hidden="true">&check;</span></button>
<button type="button" data-reasoning="extra-high"><span class="menu-icon reasoning-brain-icon" aria-hidden="true"><svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.35" stroke-linecap="round" stroke-linejoin="round"><path d="M5.1 3.2c-.9 0-1.8.7-1.8 1.8 0 .4.1.8.4 1.1-.7.4-1.1 1-1.1 1.8 0 1.2.9 2.1 2.1 2.1.1 1.1 1 1.9 2.1 1.9 1 0 1.8-.6 2.1-1.5.2.9 1.1 1.5 2.1 1.5 1.1 0 2-.8 2.1-1.9 1.2 0 2.1-.9 2.1-2.1 0-.8-.4-1.4-1.1-1.8.2-.3.4-.7.4-1.1 0-1-.8-1.8-1.8-1.8-.4 0-.8.1-1.1.4-.4-.8-1.2-1.3-2.1-1.3-.9 0-1.7.5-2.1 1.3-.3-.2-.7-.4-1.1-.4z"></path><path d="M6.3 5.8c-.6.2-.9.6-.9 1.1"></path><path d="M8 5.4v4.3"></path><path d="M9.8 5.9c.6.2.9.6.9 1.1"></path><path d="M6.4 8.6c.4.4 1 .6 1.6.6"></path><path d="M9.6 8.6c-.4.4-1 .6-1.6.6"></path></svg></span><span>Extra High</span><span class="check" aria-hidden="true">&check;</span></button>
</div>
</div>
<div class="menu-anchor composer-compute-anchor">
<button id="compute-menu-btn" class="compute-btn" type="button" aria-haspopup="menu" aria-expanded="false" title="Compute/time budget"><span class="menu-icon compute-clock-icon" aria-hidden="true"><svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.35" stroke-linecap="round" stroke-linejoin="round"><circle cx="8" cy="8" r="5.6"></circle><path d="M8 4.9v3.4l2.2 1.4"></path></svg></span><span>Auto</span></button>
<div id="compute-menu" class="floating-menu hidden" role="menu" aria-label="Compute budget">
<p class="menu-title">Compute/time budget</p>
<button type="button" data-compute-budget="auto"><span class="menu-icon compute-clock-icon" aria-hidden="true"><svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.35" stroke-linecap="round" stroke-linejoin="round"><circle cx="8" cy="8" r="5.6"></circle><path d="M8 4.9v3.4l2.2 1.4"></path></svg></span><span>Auto</span><span class="check" aria-hidden="true">&check;</span></button>
<button type="button" data-compute-budget="quick"><span class="menu-icon compute-clock-icon" aria-hidden="true"><svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.35" stroke-linecap="round" stroke-linejoin="round"><circle cx="8" cy="8" r="5.6"></circle><path d="M8 4.9v3.4l2.2 1.4"></path></svg></span><span>Instant</span><span class="check" aria-hidden="true">&check;</span></button>
<button type="button" data-compute-budget="standard"><span class="menu-icon compute-clock-icon" aria-hidden="true"><svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.35" stroke-linecap="round" stroke-linejoin="round"><circle cx="8" cy="8" r="5.6"></circle><path d="M8 4.9v3.4l2.2 1.4"></path></svg></span><span>Standard</span><span class="check" aria-hidden="true">&check;</span></button>
<button type="button" data-compute-budget="long"><span class="menu-icon compute-clock-icon" aria-hidden="true"><svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.35" stroke-linecap="round" stroke-linejoin="round"><circle cx="8" cy="8" r="5.6"></circle><path d="M8 4.9v3.4l2.2 1.4"></path></svg></span><span>Long-term</span><span class="check" aria-hidden="true">&check;</span></button>
<button type="button" data-compute-budget="until-complete"><span class="menu-icon compute-clock-icon" aria-hidden="true"><svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.35" stroke-linecap="round" stroke-linejoin="round"><circle cx="8" cy="8" r="5.6"></circle><path d="M8 4.9v3.4l2.2 1.4"></path></svg></span><span>Until Complete</span><span class="check" aria-hidden="true">&check;</span></button>
</div>
</div>
<div class="menu-anchor send-menu-anchor">
<button id="dictate-btn" class="dictate-btn hidden" type="button" aria-label="Dictate prompt" title="Dictate prompt"><span aria-hidden="true"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><rect x="9" y="3" width="6" height="11" rx="3"></rect><path d="M6 11a6 6 0 0 0 12 0"></path><path d="M12 17v4"></path><path d="M9 21h6"></path></svg></span></button>
<button id="run-btn" class="run-fab" type="submit" aria-label="Run agent" title="Send message" aria-haspopup="menu" aria-expanded="false" data-tooltip="Send message. Right-click for Queue/Stop options."><span aria-hidden="true">&uarr;</span></button>
<div id="send-menu" class="floating-menu hidden send-menu" role="menu" aria-label="Send options">
<button id="send-menu-queue-btn" type="button" data-action="send-menu-queue"><span>Queue</span><span class="shortcut">Enter</span></button>
<button id="send-menu-stop-btn" type="button" data-action="send-menu-stop"><span>Stop</span><span class="shortcut">&#8984;&#8679;Enter</span></button>
</div>
</div>
<div id="dictation-mode" class="dictation-mode hidden" aria-live="polite">
<div id="dictation-wave" class="dictation-wave" aria-hidden="true"></div>
<span id="dictation-timer" class="dictation-timer">0:00</span>
<button id="dictation-stop-btn" class="dictation-stop-btn" type="button" aria-label="Stop dictation"><span class="dictation-stop-icon" aria-hidden="true"></span></button>
</div>
</div>
<div class="session-row">
<div class="menu-anchor">
<button id="permissions-menu-btn" class="toolbar-btn compact-btn" type="button" aria-haspopup="menu" aria-expanded="false" title="Default permissions"><span class="menu-icon mono-icon" aria-hidden="true"><svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"><path d="M8 1.6l4.6 1.8v3.7c0 3-1.7 5.4-4.6 7.2-2.9-1.8-4.6-4.2-4.6-7.2V3.4L8 1.6z"/></svg></span><span>Default permissions</span></button>
<div id="permissions-menu" class="floating-menu hidden" role="menu" aria-label="Permissions menu">
<button type="button" data-permission="default"><span class="menu-icon mono-icon" aria-hidden="true"><svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"><path d="M8 1.6l4.6 1.8v3.7c0 3-1.7 5.4-4.6 7.2-2.9-1.8-4.6-4.2-4.6-7.2V3.4L8 1.6z"/></svg></span><span>Default permissions</span></button>
<button type="button" data-permission="workspace-write"><span class="menu-icon mono-icon" aria-hidden="true"><svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"><path d="M3.1 12.9l2.9-.6 6-6-2.3-2.3-6 6z"/><path d="M8.9 3.7l2.3 2.3"/></svg></span><span>Project write</span></button>
<button type="button" data-permission="read-only"><span class="menu-icon mono-icon" aria-hidden="true"><svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"><path d="M1.8 8s2.3-3.6 6.2-3.6S14.2 8 14.2 8s-2.3 3.6-6.2 3.6S1.8 8 1.8 8z"/><circle cx="8" cy="8" r="1.7"/></svg></span><span>Read only</span></button>
<button type="button" data-permission="full-access"><span class="menu-icon mono-icon" aria-hidden="true"><svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"><circle cx="8" cy="8" r="1.6"/><path d="M8 2.3v1.3"/><path d="M8 12.4v1.3"/><path d="M2.3 8h1.3"/><path d="M12.4 8h1.3"/><path d="M3.9 3.9l.9.9"/><path d="M11.2 11.2l.9.9"/><path d="M12.1 3.9l-.9.9"/><path d="M4.8 11.2l-.9.9"/></svg></span><span>Full access</span></button>
<div class="menu-sep"></div>
<p class="menu-title">Command execution</p>
<div class="command-exec-control" role="group" aria-label="Command execution mode">
<button type="button" data-command-exec="none">None</button>
<button type="button" data-command-exec="ask-all">Ask all</button>
<button type="button" data-command-exec="ask-some">Ask some</button>
<button type="button" data-command-exec="all">Ask none</button>
</div>
<div class="menu-sep"></div>
<div class="perm-toggle-row">
<button id="network-toggle-btn" class="perm-access-toggle" type="button" aria-pressed="false" aria-label="Toggle network access" title="Toggle network access">
<span class="perm-toggle-text">Network access</span>
<span class="loop-track" aria-hidden="true"><span class="loop-knob"></span></span>
</button>
</div>
<div class="perm-toggle-row">
<button id="web-toggle-btn" class="perm-access-toggle" type="button" aria-pressed="false" aria-label="Toggle web access" title="Toggle web access">
<span class="perm-toggle-text">Web access</span>
<span class="loop-track" aria-hidden="true"><span class="loop-knob"></span></span>
</button>
</div>
<div class="perm-toggle-row">
<button id="reflexive-knowledge-toggle-btn" class="perm-access-toggle" type="button" aria-pressed="false" aria-label="Toggle reflexive knowledge" title="Allow Artificer to reason about and explain its own architecture.">
<span class="perm-toggle-text">Reflexive knowledge</span>
<span class="loop-track" aria-hidden="true"><span class="loop-knob"></span></span>
</button>
</div>
<div class="perm-toggle-row">
<button id="self-actuation-toggle-btn" class="perm-access-toggle" type="button" aria-pressed="false" aria-label="Toggle self actuation" title="Allow Artificer to create projects, threads, and automations in-app through mediated commands.">
<span class="perm-toggle-text">Self-actuation</span>
<span class="loop-track" aria-hidden="true"><span class="loop-knob"></span></span>
</button>
</div>
</div>

<div id="command-approval-modal" class="modal hidden" role="dialog" aria-modal="true" aria-labelledby="command-approval-title">
<div class="modal-card">
<div class="modal-head">
<h3 id="command-approval-title">Command approval required</h3>
<button id="command-approval-close" class="icon-btn ghost" type="button" aria-label="Close command approval">&times;</button>
</div>
<div class="stack">
<p id="command-approval-text" class="settings-hint">The agent requested a command.</p>
<pre id="command-approval-command" class="terminal-output"></pre>
<label for="command-approval-match-mode">Remember rule type</label>
<select id="command-approval-match-mode">
<option value="exact">Exact command</option>
<option value="regex">Regex pattern</option>
</select>
<label for="command-approval-pattern">Remember pattern</label>
<input id="command-approval-pattern" placeholder="^git([[:space:]].*)?$" />
</div>
<div class="modal-actions two-col">
<button id="command-approval-allow-once" type="button">Allow once</button>
<button id="command-approval-deny-once" class="ghost" type="button">Deny once</button>
</div>
<div class="modal-actions two-col">
<button id="command-approval-allow-remember" type="button">Allow + remember</button>
<button id="command-approval-deny-remember" class="ghost" type="button">Deny + remember</button>
</div>
</div>
</div>
</div>
<div class="menu-anchor branch-anchor">
<button id="branch-menu-btn" class="toolbar-btn compact-btn" type="button" aria-haspopup="menu" aria-expanded="false" title="Git branch and repository">No repo</button>
<div id="branch-menu" class="floating-menu hidden" role="menu" aria-label="Branch menu">
<div id="branch-menu-list" class="menu-list"></div>
<div class="menu-sep"></div>
<form id="branch-create-form" class="inline-form">
<input id="branch-create-input" placeholder="new-branch" />
<button id="branch-create-submit" type="submit" disabled>Create</button>
</form>
</div>
</div>
<div class="context-anchor">
<span id="context-window-btn" class="context-window-indicator" aria-label="Context window" title="Context window information will display here.">
<svg viewBox="0 0 16 16" aria-hidden="true"><circle cx="8" cy="8" r="5.4"></circle></svg>
</span>
</div>
</div>
</form>
</section>
</main>

<aside id="diff-panel" class="diff-panel hidden" aria-label="Git diff panel">
<div id="diff-resizer" class="pane-resizer diff-resizer" aria-hidden="true"></div>
<div class="diff-panel-head">
<h3>Uncommitted changes</h3>
<button id="diff-close-btn" class="icon-btn" type="button" aria-label="Close diff panel">&times;</button>
</div>
<div id="diff-summary" class="diff-summary">No changes.</div>
<div id="diff-view" class="diff-view"></div>
</aside>

<section id="terminal-panel" class="terminal-panel hidden" aria-label="Terminal panel">
<pre id="terminal-output" class="terminal-output" tabindex="0" aria-label="Terminal output"></pre>
</section>
</div>

<div id="workspace-modal" class="modal hidden" role="dialog" aria-modal="true" aria-labelledby="workspace-modal-title">
<div class="modal-card">
<div class="modal-head">
<h3 id="workspace-modal-title">Add Project</h3>
<button id="workspace-modal-close" class="icon-btn ghost" type="button" aria-label="Close add project form">&times;</button>
</div>
<form id="workspace-form" class="stack">
<label for="workspace-path">Folder path</label>
<div class="browse-row">
<input id="workspace-path" name="workspace-path" placeholder="/absolute/path/to/project" required />
<button id="workspace-browse-btn" type="button">Browse</button>
</div>
<input id="workspace-dir-picker" type="file" webkitdirectory directory hidden />
<label for="workspace-name">Label (optional)</label>
<input id="workspace-name" name="workspace-name" placeholder="my project" />
<div class="modal-actions">
<button id="workspace-cancel-btn" class="ghost" type="button">Cancel</button>
<button id="workspace-add-submit" class="ctx-workspace" type="submit">Add Project</button>
</div>
</form>
</div>
</div>

<div id="automation-modal" class="modal hidden" role="dialog" aria-modal="true" aria-labelledby="automation-modal-title">
<div class="modal-card automation-modal-card">
<div class="modal-head">
<h3 id="automation-modal-title">Automation</h3>
<button id="automation-modal-close" class="icon-btn ghost" type="button" aria-label="Close automation form">&times;</button>
</div>
<form id="automation-form" class="stack automation-form">
<label for="automation-name">Name</label>
<input id="automation-name" name="automation-name" placeholder="Daily project health check" required />
<label for="automation-workspace">Project</label>
<select id="automation-workspace" name="automation-workspace" required></select>
<label for="automation-conversation">Thread (optional)</label>
<select id="automation-conversation" name="automation-conversation"></select>
<label for="automation-prompt">Task prompt</label>
<textarea id="automation-prompt" rows="6" placeholder="Inspect the repository, summarize current status, and list the most important next actions." required></textarea>
<div class="automation-schedule-grid">
<label class="automation-inline-field" for="automation-schedule-kind">
<span>Schedule type</span>
<select id="automation-schedule-kind" name="automation-schedule-kind">
<option value="interval">Interval</option>
<option value="cron">Cron</option>
<option value="once">One time</option>
</select>
</label>
<label class="automation-inline-field" for="automation-schedule-value">
<span>Schedule value</span>
<input id="automation-schedule-value" name="automation-schedule-value" placeholder="15m" required />
</label>
</div>
<p id="automation-schedule-hint" class="settings-hint">Interval examples: <code>15m</code>, <code>1h</code>, <code>86400</code>.</p>
<label class="toggle-row"><input id="automation-enabled" type="checkbox" checked /> Enabled</label>
<label class="toggle-row"><input id="automation-allow-self-reschedule" type="checkbox" /> Allow assistant to set its next run via <code>NEXT_RUN:</code></label>
<label class="automation-inline-field" for="automation-next-run">
<span>Next run override (optional)</span>
<input id="automation-next-run" name="automation-next-run" type="datetime-local" />
</label>
<div class="modal-actions">
<button id="automation-save-btn" type="submit">Save automation</button>
<button id="automation-cancel-btn" class="ghost" type="button">Cancel</button>
</div>
</form>
</div>
</div>

<div id="commit-modal" class="modal hidden" role="dialog" aria-modal="true" aria-labelledby="commit-modal-title">
<div class="modal-card">
<div class="modal-head">
<h3 id="commit-modal-title">Commit your changes</h3>
<button id="commit-modal-close" class="icon-btn ghost" type="button" aria-label="Close commit dialog">&times;</button>
</div>
<div class="stack">
<div class="info-row"><span>Branch</span><strong id="commit-branch-label">-</strong></div>
<div class="info-row"><span>Changes</span><strong id="commit-changes-label"><span class="git-delta"><span class="git-add">+0</span> <span class="git-del">-0</span></span></strong></div>
<label class="toggle-row"><input id="commit-include-unstaged" type="checkbox" checked /> Include unstaged</label>
<label for="commit-message">Commit message</label>
<textarea id="commit-message" rows="3" placeholder="Leave blank to autogenerate a commit message."></textarea>
<label for="commit-next-step">Next step</label>
<select id="commit-next-step">
<option value="commit">Commit</option>
<option value="commit-push">Commit and push</option>
</select>
</div>
<div class="modal-actions">
<button id="commit-continue-btn" type="button">Continue</button>
</div>
</div>
</div>

<div id="run-action-modal" class="modal hidden" role="dialog" aria-modal="true" aria-labelledby="run-action-title">
<div class="modal-card">
<div class="modal-head">
<h3 id="run-action-title">Run Action</h3>
<button id="run-action-close" class="icon-btn ghost" type="button" aria-label="Close run action dialog">&times;</button>
</div>
<form id="run-action-form" class="stack">
<label for="run-action-command">Command to run</label>
<textarea id="run-action-command" rows="4" placeholder="eg: npm install&#10;npm test"></textarea>
<div class="modal-actions">
<button type="submit">Save and run</button>
</div>
</form>
</div>
</div>

<div id="settings-modal" class="modal hidden" role="dialog" aria-modal="true" aria-labelledby="settings-title">
<div class="modal-card">
<div class="modal-head">
<h3 id="settings-title">Settings</h3>
<button id="settings-close-btn" class="icon-btn ghost" type="button" aria-label="Close settings">&times;</button>
</div>
<div class="stack">
<div class="info-row"><span>Git</span><strong id="git-status">Checking...</strong></div>
<div class="info-row"><span>SSH key</span><strong id="ssh-key-status">Checking...</strong></div>
<label class="toggle-row" title="Use Ollama GPU acceleration when available on this system">
<input id="llm-use-gpu-toggle" type="checkbox" checked /> Use GPU acceleration for LLMs
</label>
<p class="settings-hint">Applies to Ollama inference on macOS (Metal) and Linux (CUDA/ROCm when available).</p>
<div class="settings-sep"></div>
<div class="settings-rules">
<div class="settings-rules-head">
<strong>Automations</strong>
</div>
<label class="toggle-row" title="Run due automations in the background even when no Artificer tab is open.">
<input id="automation-daemon-toggle" type="checkbox" /> Enable background scheduler
</label>
<p id="automation-daemon-status" class="settings-hint"></p>
<div class="modal-actions modal-actions-compact automation-daemon-actions">
<button id="automation-daemon-refresh-btn" type="button">Refresh scheduler</button>
<button id="automation-daemon-run-now-btn" type="button">Run tick now</button>
</div>
</div>
<div class="modal-actions modal-actions-compact dictation-install-row">
<button id="install-dictation-btn" type="button" class="ui-pending-spinner" disabled>Checking...</button>
<p id="dictation-install-status" class="settings-hint hidden"></p>
</div>
<div id="dictation-shortcut-row" class="dictation-shortcut-row hidden">
<label class="dictation-shortcut-field" for="dictation-hold-shortcut"><span>Hold-to-Talk (Press)</span><select id="dictation-hold-shortcut"></select></label>
<label class="dictation-shortcut-field" for="dictation-toggle-shortcut"><span>Toggle</span><select id="dictation-toggle-shortcut"></select></label>
</div>
<div class="settings-sep"></div>
<div class="settings-rules">
<div class="settings-rules-head">
<strong>Programming mode</strong>
</div>
<label class="toggle-row" title="Run a built-in code reviewer pass after implementation verification in Programming mode.">
<input id="programmer-review-toggle" type="checkbox" checked /> Programmer does code reviews
</label>
<label class="settings-inline-field" for="programmer-review-rounds">
<span>Max review rounds</span>
<select id="programmer-review-rounds">
<option value="1">1</option>
<option value="2" selected>2</option>
<option value="3">3</option>
<option value="4">4</option>
</select>
</label>
<p id="programmer-review-hint" class="settings-hint">Programming mode will run reviewer passes for high-signal issues only.</p>
</div>
<div class="settings-sep"></div>
<div class="settings-rules">
<div class="settings-rules-head">
<strong>Self-improvement</strong>
</div>
<p class="settings-hint">Runs a competitive self-improvement match, scores both lanes, and stores the best merged plugin set as reversible runtime guidance.</p>
<label class="self-improve-objective-field" for="self-improve-objective">
<span>Improvement objective</span>
<input id="self-improve-objective" type="text" placeholder="Improve Artificer self-improvement quality across research, planning, architecture, coding, and admin setup." />
</label>
<label class="toggle-row" title="Run a challenger lane and score both outputs before storing plugins.">
<input id="self-improve-competition-toggle" type="checkbox" checked /> Run challenger competition lane
</label>
<div class="self-improve-run-row">
<label class="self-improve-compact-field" for="self-improve-model-select"><span>Primary model</span><select id="self-improve-model-select"></select></label>
<label class="self-improve-compact-field" for="self-improve-challenger-model-select"><span>Challenger model</span><select id="self-improve-challenger-model-select"></select></label>
<button id="self-improve-run-btn" type="button">Run self-improve match</button>
</div>
<div class="self-improve-sources" role="group" aria-label="Self-improve evidence sources">
<label class="toggle-row" title="Use academic papers from arXiv and Crossref."><input id="self-improve-source-papers" type="checkbox" checked /> Papers</label>
<label class="toggle-row" title="Use non-paper web signals from engineering communities."><input id="self-improve-source-web" type="checkbox" checked /> Web signals</label>
<label class="toggle-row" title="Use mode-runtime telemetry, scorecards, and proposal traces."><input id="self-improve-source-runtime" type="checkbox" checked /> Runtime telemetry</label>
<label class="toggle-row" title="Use repository and release-surface signals from this Artificer checkout."><input id="self-improve-source-repo" type="checkbox" checked /> Repo signals</label>
<label class="toggle-row" title="Use cross-platform tool and scheduler capability checks."><input id="self-improve-source-platform" type="checkbox" checked /> Platform checks</label>
</div>
<div id="self-improve-status" class="settings-hint"></div>
<div id="self-improve-summary" class="settings-hint"></div>
<div id="self-improve-plugins-list" class="command-rules-list"></div>
</div>
<div class="settings-sep"></div>
<label for="github-username">GitHub username (optional)</label>
<input id="github-username" placeholder="your-github-username" />
<label for="ssh-email">SSH key email/comment (optional)</label>
<input id="ssh-email" placeholder="you@example.com" />
<div class="modal-actions two-col">
<button id="refresh-auth-btn" type="button">Refresh status</button>
<button id="generate-ssh-btn" type="button">Generate SSH key</button>
</div>
<div class="modal-actions two-col">
<button id="choose-ssh-btn" type="button">Choose existing SSH key</button>
<button id="clear-ssh-btn" class="ghost" type="button">Use auto-detected key</button>
</div>
<label for="selected-ssh-path">Selected SSH key</label>
<input id="selected-ssh-path" readonly placeholder="Using auto-detected SSH key." />
<label for="ssh-pub-output">SSH public key</label>
<textarea id="ssh-pub-output" rows="3" readonly placeholder="No SSH key detected yet."></textarea>
<p class="settings-hint">Git over SSH uses your key. GitHub username/email is optional metadata.</p>
<p class="settings-links"><a href="https://github.com/settings/keys" target="_blank" rel="noopener">GitHub SSH keys</a> <span aria-hidden="true">&middot;</span> <a href="https://cli.github.com/manual/gh_auth_login" target="_blank" rel="noopener">GitHub auth docs</a></p>
<div class="settings-sep"></div>
<div class="settings-rules">
<div class="settings-rules-head">
<strong>Command approvals</strong>
</div>
<div id="command-rules-global-list" class="command-rules-list"></div>
<label for="command-rules-workspace">Project</label>
<select id="command-rules-workspace"></select>
<div id="command-rules-status" class="settings-hint"></div>
<div id="command-rules-list" class="command-rules-list"></div>
</div>
<div class="settings-sep"></div>
<div class="settings-rules">
<div class="settings-rules-head">
<strong>Teams + Runtime + Skills</strong>
<button id="mode-runtime-tick-btn" type="button">Tick scheduler</button>
</div>
<div id="mode-runtime-summary" class="settings-hint"></div>
<div id="mode-runtime-panels" class="mode-runtime-panels"></div>
<div id="mode-runtime-modes" class="mode-runtime-modes"></div>
<div id="mode-runtime-skills" class="mode-runtime-skills"></div>
<div id="mode-runtime-failure-taxonomy" class="mode-runtime-failure-taxonomy"></div>
<div id="mode-runtime-improvement-proposals" class="mode-runtime-improvement-proposals"></div>
<div id="mode-runtime-controller-variants" class="mode-runtime-controller-variants"></div>
<div id="mode-runtime-quality-scorecard" class="mode-runtime-quality-scorecard"></div>
<div class="mode-runtime-manager">
<p class="settings-hint">Teams are global. Use run mode <strong>Team</strong> then pick <strong>Team &rsaquo; Team name</strong> inline while composing.</p>
<label for="assistant-mode-select">Default team</label>
<div class="mode-runtime-inline">
<select id="assistant-mode-select"></select>
<button id="assistant-mode-apply-btn" type="button">Set default team</button>
</div>
<div class="settings-sep"></div>
<form id="mode-runtime-skill-invoke-form" class="stack compact">
<label for="mode-runtime-skill-select">Invoke skill</label>
<select id="mode-runtime-skill-select"></select>
<label for="mode-runtime-skill-mode">Authorized by mode</label>
<select id="mode-runtime-skill-mode"></select>
<label for="mode-runtime-skill-capabilities">Capability override (optional CSV)</label>
<input id="mode-runtime-skill-capabilities" placeholder="filesystem,network" />
<label for="mode-runtime-skill-input">Skill input</label>
<textarea id="mode-runtime-skill-input" rows="3" placeholder="What should this skill do?"></textarea>
<div class="modal-actions">
<button id="mode-runtime-skill-invoke-btn" type="submit">Invoke skill</button>
</div>
</form>
<pre id="mode-runtime-skill-result" class="terminal-output hidden"></pre>
<details class="mode-runtime-admin">
<summary>Create or install skill bundles</summary>
<form id="mode-runtime-skill-create-form" class="stack compact">
<label for="mode-runtime-skill-create-id">New skill id</label>
<input id="mode-runtime-skill-create-id" placeholder="my-skill-id" />
<label for="mode-runtime-skill-create-name">Name</label>
<input id="mode-runtime-skill-create-name" placeholder="My Skill" />
<label for="mode-runtime-skill-create-trigger">Trigger</label>
<input id="mode-runtime-skill-create-trigger" placeholder="when manually invoked" />
<label for="mode-runtime-skill-create-capabilities">Capabilities (CSV)</label>
<input id="mode-runtime-skill-create-capabilities" placeholder="filesystem" />
<label for="mode-runtime-skill-create-description">Description</label>
<input id="mode-runtime-skill-create-description" placeholder="What this skill does." />
<div class="modal-actions">
<button id="mode-runtime-skill-create-btn" type="submit">Create skill</button>
</div>
</form>
<form id="mode-runtime-skill-install-form" class="stack compact">
<label for="mode-runtime-skill-install-source">Install skill from folder</label>
<input id="mode-runtime-skill-install-source" placeholder="/absolute/path/to/skill-bundle" />
<label for="mode-runtime-skill-install-id">Override id (optional)</label>
<input id="mode-runtime-skill-install-id" placeholder="optional-skill-id" />
<label for="mode-runtime-skill-install-replace">Replace existing skill if id already exists</label>
<select id="mode-runtime-skill-install-replace">
<option value="0">No</option>
<option value="1">Yes</option>
</select>
<div class="modal-actions">
<button id="mode-runtime-skill-install-btn" type="submit">Install skill</button>
</div>
</form>
</details>
</div>
</div>
</div>
</div>
</div>

<div id="multi_agent-modal" class="modal hidden" role="dialog" aria-modal="true" aria-labelledby="multi_agent-title">
<div class="modal-card">
<div class="modal-head">
<div class="modal-head-title">
<h3 id="multi_agent-title">Manage agents</h3>
<span id="multi_agent-project-label" class="multi-agent-project-label">No project selected</span>
</div>
<p id="multi_agent-status" class="multi-agent-status-badge" aria-live="polite"></p>
<button id="multi_agent-modal-close" class="icon-btn ghost" type="button" aria-label="Close agent settings">&times;</button>
</div>
<div class="stack">
<label class="toggle-row" title="Share project instructions and context across agent roles"><input id="multi_agent-toggle-context-sharing" type="checkbox" checked /> Agent context sharing</label>
<label for="multi_agent-charter" title="Shared instructions that guide all agents in this project.">Project instructions</label>
<textarea id="multi_agent-charter" rows="5" placeholder="Instructions for all agents in this project"></textarea>

<div class="settings-rules">
<div class="settings-rules-head"><strong>Agent team</strong></div>
<p id="multi_agent-roles-hint" class="settings-hint">Turn built-in specialist agents on or off. Use each row menu for model and visibility.</p>
<label class="toggle-row" title="Enable or disable all agent team roles in this project"><input id="multi_agent-toggle-all-residents" type="checkbox" /> Enable all agents</label>
<div id="multi_agent-residents-list" class="command-rules-list resident-listbox" role="listbox"></div>
</div>

<div class="settings-rules">
<label class="toggle-row" title="Lets agents propose updates to project instructions and interpretation notes"><input id="multi_agent-toggle-amendments" type="checkbox" checked /> Instruction updates</label>
<div id="multi_agent-section-amendments" class="multi-agent-section">
<details class="multi-agent-collapse" open>
<summary><span id="multi_agent-amendments-summary">Instruction updates</span></summary>
<div class="multi-agent-frame">
<div id="multi_agent-amendments-list" class="command-rules-list"></div>
</div>
</details>
<details class="multi-agent-collapse" open>
<summary><span id="multi_agent-interpretation-summary">Interpretation notes</span></summary>
<div class="multi-agent-frame">
<div id="multi_agent-interpretation-list" class="command-rules-list"></div>
</div>
</details>
</div>

<label class="toggle-row" title="Tracks commitments agents make in this project"><input id="multi_agent-toggle-commitments" type="checkbox" checked /> Commitment tracking</label>
<div id="multi_agent-section-commitments" class="multi-agent-section">
<details class="multi-agent-collapse" open>
<summary><span id="multi_agent-commitments-summary">Commitments</span></summary>
<div class="multi-agent-frame">
<div id="multi_agent-commitments-list" class="command-rules-list"></div>
</div>
</details>
</div>

<label class="toggle-row" title="Tracks recurring don't-ask choices"><input id="multi_agent-toggle-policies" type="checkbox" checked /> Decision filters</label>
<div id="multi_agent-section-policies" class="multi-agent-section">
<details class="multi-agent-collapse" open>
<summary><span id="multi_agent-policies-summary">Decision filters</span></summary>
<div class="multi-agent-frame">
<div id="multi_agent-policies-list" class="command-rules-list"></div>
</div>
</details>
</div>
</div>
</div>
</div>
</div>

<script>
(function loadArtificerRuntime() {
  var launchKey = "";
  var versionTag = "20260326-runtime-modules1";
  var modules = [
    "01-boot-and-storage.js",
    "01b-runtime-state-and-automation.js",
    "02-runtime-core.js",
    "02b-runtime-core-tail.js",
    "03-ui-and-rendering.js",
    "03b-ui-and-rendering-tail.js",
    "04-dictation-wave.js",
    "04b-dictation-wave-tail.js",
    "05-api-and-state-sync.js",
    "05b-api-and-state-sync-tail.js",
    "06-queue-and-automation.js",
    "06b-queue-and-automation-tail.js",
    "07-settings-and-actions.js",
    "07b-settings-and-actions-tail.js",
    "08-event-bindings-and-boot.js",
    "08b-event-bindings-and-boot-tail.js"
  ];
  try {
    var search = new URLSearchParams(window.location.search || "");
    launchKey = String(search.get("launch") || "");
  } catch (_err) {
    launchKey = "";
  }
  if (!launchKey) {
    launchKey = String(Date.now());
  }

  function loadBundleFallback() {
    var script = document.createElement("script");
    script.src = "/static/artificer-app.js?v=" + encodeURIComponent(versionTag) + "&launch=" + encodeURIComponent(launchKey);
    document.body.appendChild(script);
  }

  if (typeof fetch !== "function") {
    loadBundleFallback();
    return;
  }

  function loadModule(index, chunks) {
    if (index >= modules.length) {
      var runtimeScript = document.createElement("script");
      runtimeScript.text = chunks.join("\n");
      document.body.appendChild(runtimeScript);
      return;
    }
    var moduleUrl = "/static/artificer-app-modules/" + modules[index] + "?v=" + encodeURIComponent(versionTag) + "&launch=" + encodeURIComponent(launchKey);
    fetch(moduleUrl, { cache: "no-store" })
      .then(function (response) {
        if (!response.ok) {
          throw new Error("failed module " + modules[index] + ": " + response.status);
        }
        return response.text();
      })
      .then(function (sourceText) {
        chunks.push(sourceText);
        loadModule(index + 1, chunks);
      })
      .catch(function (error) {
        console.error("failed to load Artificer runtime modules", error);
        loadBundleFallback();
      });
  }

  loadModule(0, []);
})();
</script>
