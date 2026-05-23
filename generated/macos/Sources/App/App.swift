// Generated from templates/macos/App.swift.template. Regenerate with scripts/render-native-desktop.sh.
import AppKit
import AVFoundation
import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

private let fallbackProjectDir = "/Users/andersaamodt/git/artificer"
private let appDisplayName = "Artificer"
private let voiceAutomationCaptureSeconds: TimeInterval = 2.2
private let voiceAutomationLoopPauseNanoseconds: UInt64 = 80_000_000
private let voiceAutomationMeterPollNanoseconds: UInt64 = 50_000_000
private let voiceAutomationSpeechThresholdDecibels: Float = -45.0
private let voiceAutomationTrailingSilenceSeconds: TimeInterval = 0.45
private let voiceAutomationMinimumCaptureSeconds: TimeInterval = 0.7

private func waitForVoiceAutomationCaptureWindow(_ recorder: AVAudioRecorder, maxSeconds: TimeInterval) async -> TimeInterval {
  let startedAt = Date()
  var heardSpeech = false
  var lastSpeechAt = startedAt
  let maxDuration = max(1.0, maxSeconds)
  while !Task.isCancelled {
    recorder.updateMeters()
    let now = Date()
    let elapsed = now.timeIntervalSince(startedAt)
    if recorder.averagePower(forChannel: 0) > voiceAutomationSpeechThresholdDecibels {
      heardSpeech = true
      lastSpeechAt = now
    }
    if heardSpeech,
       elapsed >= voiceAutomationMinimumCaptureSeconds,
       now.timeIntervalSince(lastSpeechAt) >= voiceAutomationTrailingSilenceSeconds {
      return elapsed
    }
    if elapsed >= maxDuration {
      return elapsed
    }
    try? await Task.sleep(nanoseconds: voiceAutomationMeterPollNanoseconds)
  }
  return Date().timeIntervalSince(startedAt)
}

@main
struct ArtificerNativeApp: App {
  @StateObject private var model: ArtificerModel
  private let statusItemController: ArtificerStatusItemController
  @Environment(\.openWindow) private var openWindow

  init() {
    let launchModel = ArtificerModel()
    launchModel.loadDesktopPrefsForLaunch()
    launchModel.syncVoiceAutomationLoop()
    statusItemController = ArtificerStatusItemController(model: launchModel)
    _model = StateObject(wrappedValue: launchModel)
  }

  var body: some Scene {
    WindowGroup("Artificer") {
      RootView(model: model)
        .frame(minWidth: 1120, minHeight: 720)
        .font(.system(size: 14))
        .task {
          await model.bootstrap()
        }
    }
    .commands {
      CommandGroup(replacing: .newItem) {
        Button("New Session") {
          Task { await model.createSession() }
        }
        .keyboardShortcut("n")
        Button("Add Workspace...") {
          model.chooseWorkspaceFolder()
        }
        .keyboardShortcut("o")
        Button("Attach File...") {
          model.chooseAttachments()
        }
        .keyboardShortcut("u", modifiers: [.command])
      }
      CommandGroup(after: .saveItem) {
        Button("Refresh") {
          Task { await model.refreshAll() }
        }
        .keyboardShortcut("r")
        Button("Run Next Queue Item") {
          Task { await model.runNext() }
        }
        .keyboardShortcut(.return, modifiers: [.command])
        Button("Dictate") {
          Task { await model.toggleDictation() }
        }
        .keyboardShortcut("d", modifiers: [.command, .shift])
        Button("Open Hosted Artificer") {
          Task { await model.openHostedArtificer() }
        }
      }
      CommandGroup(replacing: .appSettings) {
        Button("Preferences...") {
          openWindow(id: "preferences")
        }
        .keyboardShortcut(",", modifiers: [.command])
      }
      CommandMenu("Automation") {
        Toggle("Launch Background Runtime at Startup", isOn: Binding(
          get: { model.daemonStatus?.enabled ?? false },
          set: { nextValue in
            Task { await model.setAutomationDaemonEnabled(nextValue) }
          }
        ))
        Toggle("Show Menu Bar Icon", isOn: Binding(
          get: { model.menuBarIconEnabled },
          set: { nextValue in
            Task { await model.setMenuBarIconEnabled(nextValue) }
          }
        ))
        Divider()
        Button((model.daemonStatus?.paused ?? false) ? "Resume Runtime" : "Pause Runtime") {
          Task { await model.toggleAutomationDaemonPaused() }
        }
        .disabled(!(model.daemonStatus?.enabled ?? false))
        Button("Run Due Automations") {
          Task { await model.daemon("automation-daemon-tick") }
        }
        .disabled(!(model.daemonStatus?.enabled ?? false))
      }
    }

    Window("Preferences", id: "preferences") {
      SettingsView(model: model)
        .frame(width: 780, height: 560)
    }
    .windowResizability(.contentSize)
  }
}

private func artificerMenuBarImage() -> NSImage? {
  let side: CGFloat = 18
  let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
    let minX = rect.minX
    let maxX = rect.maxX
    let minY = rect.minY
    let maxY = rect.maxY
    let midX = rect.midX
    let strokeWidth: CGFloat = 2.0
    let topPadding = max(2.0, floor(side * 0.14 * 2.0) / 2.0)
    let bottomPadding = max(0.5, floor(side * 0.02 * 2.0) / 2.0)
    let topY = ceil((maxY - topPadding) * 2.0) / 2.0
    let maxSegmentByWidth = floor(min(midX - minX, maxX - midX) * 2.0) / 2.0
    let maxSegmentByHeight = floor(((topY - (minY + bottomPadding)) / 5.0) * 2.0) / 2.0
    let segment = max(1.5, min(maxSegmentByWidth, maxSegmentByHeight))
    let bottomFootY = topY - segment * 5.0

    let upperTop = NSPoint(x: midX, y: topY)
    let upperLeft = NSPoint(x: midX - segment, y: topY - segment)
    let upperRight = NSPoint(x: midX + segment, y: topY - segment)
    let sharedUpperBottom = NSPoint(x: midX, y: topY - segment * 2.0)
    let lowerLeft = NSPoint(x: midX - segment, y: topY - segment * 3.0)
    let lowerRight = NSPoint(x: midX + segment, y: topY - segment * 3.0)
    let lowerBottom = NSPoint(x: midX, y: topY - segment * 4.0)
    let leftFoot = NSPoint(x: midX - segment, y: bottomFootY)
    let rightFoot = NSPoint(x: midX + segment, y: bottomFootY)

    let capTip = NSBezierPath()
    capTip.move(to: upperLeft)
    capTip.line(to: upperTop)
    capTip.line(to: upperRight)

    let upperCross = NSBezierPath()
    upperCross.move(to: upperLeft)
    upperCross.line(to: sharedUpperBottom)
    upperCross.line(to: lowerRight)

    let upperCrossMirror = NSBezierPath()
    upperCrossMirror.move(to: upperRight)
    upperCrossMirror.line(to: sharedUpperBottom)
    upperCrossMirror.line(to: lowerLeft)

    let lowerCross = NSBezierPath()
    lowerCross.move(to: lowerLeft)
    lowerCross.line(to: lowerBottom)
    lowerCross.line(to: rightFoot)

    let lowerCrossMirror = NSBezierPath()
    lowerCrossMirror.move(to: lowerRight)
    lowerCrossMirror.line(to: lowerBottom)
    lowerCrossMirror.line(to: leftFoot)

    NSColor.black.setStroke()
    for path in [capTip, upperCross, upperCrossMirror, lowerCross, lowerCrossMirror] {
      path.lineWidth = strokeWidth
      path.lineJoinStyle = .miter
      path.lineCapStyle = .butt
      path.miterLimit = 12.0
      path.stroke()
    }
    return true
  }
  image.isTemplate = true
  return image
}

@MainActor
private final class ArtificerStatusItemController: NSObject {
  private let model: ArtificerModel
  private var statusItem: NSStatusItem?
  private var cancellables: Set<AnyCancellable> = []

  init(model: ArtificerModel) {
    self.model = model
    super.init()
    model.$menuBarIconEnabled
      .receive(on: RunLoop.main)
      .sink { [weak self] enabled in
        self?.setVisible(enabled)
      }
      .store(in: &cancellables)
    model.objectWillChange
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in
        self?.refreshMenu()
      }
      .store(in: &cancellables)
    DispatchQueue.main.async { [weak self] in
      self?.setVisible(model.menuBarIconEnabled)
    }
  }

  private func setVisible(_ visible: Bool) {
    if visible {
      installStatusItem()
    } else if let item = statusItem {
      NSStatusBar.system.removeStatusItem(item)
      statusItem = nil
    }
  }

  private func installStatusItem() {
    if statusItem == nil {
      let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
      item.button?.toolTip = "Artificer"
      item.button?.imagePosition = .imageOnly
      item.button?.image = artificerMenuBarImage()
      item.button?.image?.isTemplate = true
      statusItem = item
    }
    refreshMenu()
  }

  private func refreshMenu() {
    guard let item = statusItem else { return }
    let menu = NSMenu()
    menu.addItem(NSMenuItem(title: "Open Artificer", action: #selector(openArtificer), keyEquivalent: ""))
    menu.addItem(NSMenuItem(title: "Open Hosted Artificer", action: #selector(openHostedArtificer), keyEquivalent: ""))
    menu.addItem(.separator())
    let pauseTitle = (model.daemonStatus?.paused ?? false) ? "Resume Runtime" : "Pause Runtime"
    let pauseItem = NSMenuItem(title: pauseTitle, action: #selector(toggleAutomationDaemonPaused), keyEquivalent: "")
    pauseItem.isEnabled = model.daemonStatus?.enabled ?? false
    menu.addItem(pauseItem)
    let tickItem = NSMenuItem(title: "Run Due Automations", action: #selector(runAutomationTick), keyEquivalent: "")
    tickItem.isEnabled = model.daemonStatus?.enabled ?? false
    menu.addItem(tickItem)
    menu.addItem(.separator())
    menu.addItem(NSMenuItem(title: "Hide Menu Bar Icon", action: #selector(hideMenuBarIcon), keyEquivalent: ""))
    menu.addItem(.separator())
    menu.addItem(NSMenuItem(title: "Quit Artificer", action: #selector(quitArtificer), keyEquivalent: ""))
    for item in menu.items {
      item.target = self
    }
    item.menu = menu
  }

  @objc private func openArtificer() {
    NSApp.activate(ignoringOtherApps: true)
  }

  @objc private func openHostedArtificer() {
    Task { await model.openHostedArtificer() }
  }

  @objc private func toggleAutomationDaemonPaused() {
    Task { await model.toggleAutomationDaemonPaused() }
  }

  @objc private func runAutomationTick() {
    Task { await model.daemon("automation-daemon-tick") }
  }

  @objc private func hideMenuBarIcon() {
    Task { await model.setMenuBarIconEnabled(false) }
  }

  @objc private func quitArtificer() {
    NSApp.terminate(nil)
  }
}

private struct RootView: View {
  @ObservedObject var model: ArtificerModel
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    NavigationSplitView {
      WorkspaceSidebar(model: model)
        .navigationSplitViewColumnWidth(min: 300, ideal: 340, max: 460)
    } detail: {
      if model.showingAutomations {
        AutomationsDetailView(model: model)
      } else {
        SessionDetailView(model: model)
      }
    }
    .toolbar {
      ToolbarItem(placement: .navigation) {
        ProjectPathToolbarItem(model: model)
      }
      ToolbarItemGroup(placement: .primaryAction) {
        OpenProjectToolbarMenu(model: model)
        GitBranchToolbarMenu(model: model)
        GitChangesToolbarButton(model: model)
        CommitToolbarMenu(model: model)
        FloatingIconButton(title: "Terminal panel", systemImage: "terminal", disabled: model.selectedProjectID == nil || model.isBusy) {
          model.showingTerminalPanel = true
          Task { await model.startTerminalSession() }
        }
        ThemeToolbarMenu(model: model)
        FloatingIconButton(title: "Models", systemImage: "shippingbox", disabled: model.isBusy) {
          model.showingModelsPanel = true
          Task { await model.loadModelData() }
        }
        FloatingIconButton(title: "Refresh", systemImage: "arrow.clockwise", disabled: model.isBusy) {
          Task { await model.refreshAll() }
        }
        FloatingIconButton(title: "New thread", systemImage: "plus.message", disabled: model.selectedProjectID == nil || model.isBusy) {
          Task { await model.createSession() }
        }
        FloatingIconButton(title: "Add project", systemImage: "folder.badge.plus", disabled: model.isBusy) {
          model.chooseWorkspaceFolder()
        }
        FloatingIconButton(title: "Run next item", systemImage: "play.fill", disabled: model.selectedSessionID == nil || model.isBusy) {
          Task { await model.runNext() }
        }
        FloatingIconButton(title: "Open hosted Artificer", systemImage: "safari") {
          Task { await model.openHostedArtificer() }
        }
        FloatingIconButton(title: "Preferences", systemImage: "gearshape") {
          openWindow(id: "preferences")
        }
      }
    }
    .tint(model.themeAccentColor)
    .accentColor(model.themeAccentColor)
    .sheet(isPresented: $model.showingGitDiff) {
      GitDiffSheet(model: model)
        .frame(minWidth: 720, minHeight: 520)
    }
    .sheet(isPresented: $model.showingCommitDialog) {
      CommitSheet(model: model)
        .frame(minWidth: 440, minHeight: 310)
    }
    .sheet(isPresented: $model.showingBranchDialog) {
      BranchSheet(model: model)
        .frame(minWidth: 380, minHeight: 180)
    }
    .sheet(isPresented: $model.showingQueueTray) {
      QueueTraySheet(model: model)
        .frame(minWidth: 620, minHeight: 430)
    }
    .sheet(isPresented: $model.showingTerminalPanel) {
      TerminalPanelSheet(model: model)
        .frame(minWidth: 720, minHeight: 460)
    }
    .sheet(isPresented: $model.showingModelsPanel) {
      ModelQuickPanel(model: model)
        .frame(minWidth: 620, minHeight: 460)
    }
    .safeAreaInset(edge: .bottom) {
      StatusBar(model: model)
    }
  }
}

private struct ProjectPathToolbarItem: View {
  @ObservedObject var model: ArtificerModel

  var body: some View {
    HStack(spacing: 6) {
      if let project = model.selectedProject {
        Button {
          model.copySelectedProjectPath()
        } label: {
          HStack(spacing: 6) {
            Image(systemName: project.pathExists ? "folder" : "folder.badge.questionmark")
              .font(.system(size: 12, weight: .semibold))
            Text(model.projectPathDisplayName(project))
              .font(.system(size: 12))
              .lineLimit(1)
              .truncationMode(.middle)
          }
          .padding(.horizontal, 9)
          .frame(height: 28)
          .frame(maxWidth: 260, alignment: .leading)
          .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
          .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Click to copy path: \(project.path)")
        .accessibilityLabel(Text("Project path \(project.path)"))

        OpenProjectToolbarMenu(model: model, compact: true)
      }
    }
    .frame(minWidth: 1, maxWidth: 330, minHeight: 30, idealHeight: 30, maxHeight: 30, alignment: .leading)
  }
}

private struct OpenProjectToolbarMenu: View {
  @ObservedObject var model: ArtificerModel
  var compact = false

  var body: some View {
    Menu {
      Button {
        Task { await model.openProjectTarget("finder") }
      } label: {
        Label("Finder", systemImage: "folder")
      }
      Button {
        Task { await model.openProjectTarget("terminal") }
      } label: {
        Label("Terminal", systemImage: "terminal")
      }
      Button {
        Task { await model.openProjectTarget("textmate") }
      } label: {
        Label("TextMate", systemImage: "doc.text")
      }
    } label: {
      FloatingIconMenuLabel(title: compact ? "Open project" : "Open", systemImage: compact ? "arrow.up.forward.app" : "square.and.arrow.up")
    }
    .menuStyle(.borderlessButton)
    .fixedSize(horizontal: true, vertical: true)
    .help("Open project")
    .disabled(model.selectedProject?.pathExists != true || model.isBusy)
  }
}

private struct GitBranchToolbarMenu: View {
  @ObservedObject var model: ArtificerModel

  var body: some View {
    Menu {
      if model.gitStatus.isRepo {
        if model.gitBranches.isEmpty {
          Button {
            Task { await model.loadGitStatusAndBranches() }
          } label: {
            Label("Refresh branches", systemImage: "arrow.clockwise")
          }
        } else {
          ForEach(model.gitBranches) { branch in
            Button {
              Task { await model.checkoutBranch(branch.name) }
            } label: {
              HStack {
                Text(branch.name)
                if branch.current {
                  Image(systemName: "checkmark")
                }
              }
            }
          }
          Divider()
        }
        Button {
          model.branchNameDraft = ""
          model.showingBranchDialog = true
        } label: {
          Label("Create branch", systemImage: "plus")
        }
      } else {
        Text("No Git repository")
        Button {
          Task { await model.loadGitStatusAndBranches() }
        } label: {
          Label("Refresh", systemImage: "arrow.clockwise")
        }
      }
    } label: {
      FloatingIconMenuLabel(title: model.gitBranchTitle, systemImage: "arrow.triangle.branch")
    }
    .menuStyle(.borderlessButton)
    .fixedSize(horizontal: true, vertical: true)
    .help(model.gitBranchTitle)
    .disabled(model.selectedProjectID == nil || model.isBusy)
    .task(id: model.selectedProjectID) {
      await model.loadGitStatusAndBranches()
    }
  }
}

private struct GitChangesToolbarButton: View {
  @ObservedObject var model: ArtificerModel

  var body: some View {
    Button {
      Task {
        await model.loadGitDiff()
        model.showingGitDiff = true
      }
    } label: {
      ZStack(alignment: .topTrailing) {
        Image(systemName: "plusminus")
          .font(.system(size: 14, weight: .semibold))
          .frame(width: 30, height: 30)
          .contentShape(Circle())
        if model.gitStatus.changes > 0 {
          Text("\(model.gitStatus.changes)")
            .font(.system(size: 9, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(model.themeContrastColor)
            .padding(.horizontal, 4)
            .frame(minWidth: 16, minHeight: 16)
            .background(model.themeAccentColor)
            .clipShape(Capsule())
            .offset(x: 4, y: -3)
        }
      }
    }
    .buttonStyle(.plain)
    .foregroundStyle(model.gitStatus.changes > 0 ? model.themeAccentColor : Color.secondary)
    .shadow(color: Color.black.opacity(model.gitStatus.changes > 0 ? 0.13 : 0), radius: 7, x: 0, y: 3)
    .frame(width: 34, height: 30)
    .help(model.gitChangesTitle)
    .accessibilityLabel(Text(model.gitChangesTitle))
    .disabled(model.selectedProjectID == nil || !model.gitStatus.isRepo || model.isBusy)
  }
}

private struct CommitToolbarMenu: View {
  @ObservedObject var model: ArtificerModel

  var body: some View {
    Menu {
      Button {
        model.prepareCommit(pushAfter: false)
      } label: {
        Label("Commit", systemImage: "checkmark.seal")
      }
      Button {
        Task { await model.pushGitChanges() }
      } label: {
        Label("Push", systemImage: "arrow.up.circle")
      }
      Button {
        model.prepareCommit(pushAfter: true)
      } label: {
        Label("Commit and push", systemImage: "arrow.up.doc")
      }
    } label: {
      FloatingIconMenuLabel(title: "Commit actions", systemImage: "arrow.up.doc")
    }
    .menuStyle(.borderlessButton)
    .fixedSize(horizontal: true, vertical: true)
    .help("Commit actions")
    .disabled(model.selectedProjectID == nil || !model.gitStatus.isRepo || model.isBusy)
  }
}

private struct ThemeToolbarMenu: View {
  @ObservedObject var model: ArtificerModel

  var body: some View {
    Menu {
      ForEach(AppTheme.available) { theme in
        Button {
          Task { await model.setTheme(theme.id) }
        } label: {
          HStack {
            ThemeSwatch(theme: theme)
            Text(theme.name)
            if theme.id == model.selectedThemeID {
              Image(systemName: "checkmark")
            }
          }
        }
      }
    } label: {
      FloatingIconMenuLabel(title: "Theme", systemImage: "paintpalette")
    }
    .menuStyle(.borderlessButton)
    .fixedSize(horizontal: true, vertical: true)
    .help("Theme")
  }
}

private struct FloatingIconMenuLabel: View {
  let title: String
  let systemImage: String
  @State private var isHovering = false

  var body: some View {
    Image(systemName: systemImage)
      .font(.system(size: 14, weight: .semibold))
      .foregroundStyle(isHovering ? Color.primary : Color.secondary)
      .frame(width: 30, height: 30)
      .contentShape(Circle())
      .background(isHovering ? Color(nsColor: .controlBackgroundColor).opacity(0.92) : Color.clear)
      .clipShape(Circle())
      .shadow(color: isHovering ? Color.black.opacity(0.18) : Color.clear, radius: 8, x: 0, y: 4)
      .onHover { isHovering = $0 }
      .accessibilityLabel(Text(title))
  }
}

private struct FloatingIconButton: View {
  enum Prominence {
    case plain
    case accent
  }

  let title: String
  let systemImage: String
  var disabled = false
  var prominence: Prominence = .plain
  var size: CGFloat = 30
  let action: () -> Void

  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.system(size: prominence == .accent ? 15 : 14, weight: .semibold))
        .frame(width: size, height: size)
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .foregroundStyle(foregroundColor)
    .background(backgroundShape)
    .clipShape(Circle())
    .shadow(color: isHovering && !disabled ? Color.black.opacity(0.18) : Color.clear, radius: 8, x: 0, y: 4)
    .frame(width: size, height: size)
    .onHover { isHovering = $0 }
    .help(title)
    .accessibilityLabel(Text(title))
    .disabled(disabled)
    .opacity(disabled ? 0.45 : 1)
  }

  @ViewBuilder private var backgroundShape: some View {
    if prominence == .accent {
      Circle()
        .fill(Color.accentColor)
    } else if isHovering && !disabled {
      Circle()
        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.92))
    } else {
      Circle()
        .fill(Color.clear)
    }
  }

  private var foregroundColor: Color {
    if prominence == .accent {
      return accentContrastColor()
    }
    return isHovering && !disabled ? Color.primary : Color.secondary
  }
}

private func accentContrastColor() -> Color {
  let nsColor = NSColor.controlAccentColor.usingColorSpace(.deviceRGB) ?? NSColor.controlAccentColor
  let luminance = 0.2126 * Double(nsColor.redComponent)
    + 0.7152 * Double(nsColor.greenComponent)
    + 0.0722 * Double(nsColor.blueComponent)
  return luminance > 0.58 ? .black : .white
}

private func copyToPasteboard(_ text: String) {
  NSPasteboard.general.clearContents()
  NSPasteboard.general.setString(text, forType: .string)
}

private struct AppTheme: Identifiable {
  let id: String
  let name: String
  let accent: Color
  let contrast: Color

  static let available: [AppTheme] = [
    AppTheme(id: "system", name: "System", accent: Color.accentColor, contrast: accentContrastColor()),
    AppTheme(id: "artificer", name: "Artificer", accent: Color(red: 0.19, green: 0.41, blue: 0.86), contrast: .white),
    AppTheme(id: "ink", name: "Ink", accent: Color(red: 0.08, green: 0.09, blue: 0.11), contrast: .white),
    AppTheme(id: "moss", name: "Moss", accent: Color(red: 0.18, green: 0.48, blue: 0.36), contrast: .white),
    AppTheme(id: "ember", name: "Ember", accent: Color(red: 0.76, green: 0.24, blue: 0.16), contrast: .white)
  ]

  static func resolved(_ id: String) -> AppTheme {
    available.first { $0.id == id } ?? available[0]
  }
}

private struct ThemeSwatch: View {
  let theme: AppTheme

  var body: some View {
    Circle()
      .fill(theme.accent)
      .frame(width: 12, height: 12)
      .overlay(
        Circle()
          .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
      )
  }
}

private struct WorkspaceSidebar: View {
  @ObservedObject var model: ArtificerModel

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text("Threads")
          .font(.headline)
          .lineLimit(1)
        Spacer()
        Button {
          model.chooseWorkspaceFolder()
        } label: {
          Image(systemName: "folder.badge.plus")
        }
        .help("New project")
        .disabled(model.isBusy)
        Button {
          Task { await model.refreshAll() }
        } label: {
          Image(systemName: "line.3.horizontal.decrease")
        }
        .help("Refresh")
        .disabled(model.isBusy)
      }
      .buttonStyle(.borderless)
      .padding(.horizontal, 12)
      .padding(.vertical, 10)

      Divider()

      AutomationSidebarRow(model: model)
        .padding(.horizontal, 8)
        .padding(.vertical, 8)

      Divider()

      ScrollView {
        LazyVStack(alignment: .leading, spacing: 4) {
          if model.projects.isEmpty {
            EmptySidebarState(model: model)
          } else {
            ForEach(model.projects) { project in
              WorkspaceTreeGroup(model: model, project: project)
            }
          }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

      Divider()
      HStack(alignment: .center, spacing: 8) {
        OpenPreferencesButton()
        RuntimeHealthView(model: model)
      }
      .padding(12)
      .padding(.bottom, 28)
    }
  }
}

private struct AutomationSidebarRow: View {
  @ObservedObject var model: ArtificerModel

  var body: some View {
    Button {
      Task { await model.selectAutomationsPanel() }
    } label: {
      HStack(spacing: 8) {
        Image(systemName: model.voiceAutomationsEnabled ? "waveform.circle.fill" : "clock.arrow.circlepath")
          .foregroundStyle(model.voiceAutomationsEnabled ? Color.accentColor : Color.secondary)
          .frame(width: 18)
        VStack(alignment: .leading, spacing: 2) {
          Text("Automations")
            .font(.system(size: 13, weight: .semibold))
          Text(model.voiceAutomationStatus?.status ?? "background runtime")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        Spacer()
        if model.voiceAutomationsEnabled {
          Circle()
            .fill(Color.green)
            .frame(width: 7, height: 7)
        }
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 7)
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
      .background(model.showingAutomations ? Color.accentColor.opacity(0.13) : Color.clear)
      .clipShape(RoundedRectangle(cornerRadius: 7))
    }
    .buttonStyle(.plain)
    .help("Automations")
  }
}

private struct OpenPreferencesButton: View {
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    Button {
      openWindow(id: "preferences")
    } label: {
      Image(systemName: "gearshape")
    }
    .help("Preferences")
    .buttonStyle(.borderless)
  }
}

private struct WorkspaceTreeGroup: View {
  @ObservedObject var model: ArtificerModel
  let project: Project

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 6) {
        Image(systemName: model.isProjectExpanded(project.id) ? "chevron.down" : "chevron.right")
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(.secondary)
          .frame(width: 10)
        Image(systemName: model.isProjectExpanded(project.id) ? "folder.fill" : "folder")
          .foregroundColor(project.pathExists ? .secondary : .orange)
          .frame(width: 16)
        Text(project.name)
          .font(.system(size: 13, weight: project.id == model.selectedProjectID ? .semibold : .regular))
          .lineLimit(1)
          .truncationMode(.tail)
        Spacer(minLength: 6)
        ZStack {
          Text("\(model.sessionsByProject[project.id]?.count ?? project.sessionCount)")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .opacity(model.creatingSessionProjectIDs.contains(project.id) ? 0 : 1)
          ProgressView()
            .controlSize(.mini)
            .opacity(model.creatingSessionProjectIDs.contains(project.id) ? 1 : 0)
        }
        .frame(width: 28)
        Button {
          Task { await model.createSession(in: project.id) }
        } label: {
          Image(systemName: "square.and.pencil")
            .font(.system(size: 12))
            .frame(width: 16, height: 16)
        }
        .help("New thread")
        .buttonStyle(.plain)
        .disabled(model.isBusy || model.creatingSessionProjectIDs.contains(project.id))
      }
      .frame(height: 28)
      .padding(.horizontal, 6)
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
      .background(project.id == model.selectedProjectID && model.selectedSessionID == nil ? Color.accentColor.opacity(0.13) : Color.clear)
      .clipShape(RoundedRectangle(cornerRadius: 7))
      .onTapGesture {
        Task { await model.toggleProject(project.id) }
      }

      if model.isProjectExpanded(project.id) {
        let sessions = model.sessionsByProject[project.id] ?? []
        if sessions.isEmpty {
          Text("No threads")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(height: 24)
            .padding(.leading, 40)
        } else {
          ForEach(sessions) { session in
            SessionTreeRow(model: model, project: project, session: session)
          }
        }
      }
    }
  }
}

private struct SessionTreeRow: View {
  @ObservedObject var model: ArtificerModel
  let project: Project
  let session: SessionSummary
  @State private var isHovering = false

  var body: some View {
    HStack(spacing: 7) {
      Circle()
        .fill(indicatorColor)
        .frame(width: 7, height: 7)
      Text(session.title.isEmpty ? session.id : session.title)
        .font(.system(size: 13))
        .lineLimit(1)
        .truncationMode(.tail)
      SessionStatusPill(session: session)
      Spacer(minLength: 6)
      let showingArchive = isHovering || model.pendingArchiveSessionKey == model.archiveKey(projectID: project.id, sessionID: session.id)
      ZStack(alignment: .trailing) {
        Text(relativeUpdated)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .opacity(showingArchive ? 0 : 1)
          .frame(maxWidth: .infinity, alignment: .trailing)
        Button {
          Task { await model.requestOrConfirmArchive(projectID: project.id, sessionID: session.id) }
        } label: {
          Image(systemName: model.pendingArchiveSessionKey == model.archiveKey(projectID: project.id, sessionID: session.id) ? "checkmark" : "archivebox")
            .frame(width: 16, height: 16)
        }
        .help(model.pendingArchiveSessionKey == model.archiveKey(projectID: project.id, sessionID: session.id) ? "Confirm archive" : "Archive thread")
        .buttonStyle(.plain)
        .foregroundColor(model.pendingArchiveSessionKey == model.archiveKey(projectID: project.id, sessionID: session.id) ? .red : .secondary)
        .opacity(showingArchive ? 1 : 0)
        .allowsHitTesting(showingArchive)
      }
      .frame(width: 78, height: 20, alignment: .trailing)
    }
    .frame(height: 28)
    .padding(.leading, 34)
    .padding(.trailing, 6)
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
    .background(session.id == model.selectedSessionID && project.id == model.selectedProjectID ? Color.accentColor.opacity(0.13) : Color.clear)
    .clipShape(RoundedRectangle(cornerRadius: 7))
    .onTapGesture {
      Task { await model.selectSession(projectID: project.id, sessionID: session.id) }
    }
    .onHover { isHovering = $0 }
  }

  private var indicatorColor: Color {
    if session.queue.running > 0 { return .green }
    if session.queue.pending > 0 { return .orange }
    if session.queue.done > 0 { return .blue.opacity(0.75) }
    return .secondary.opacity(0.55)
  }

  private var relativeUpdated: String {
    guard session.updated > 0 else { return "" }
    let date = Date(timeIntervalSince1970: TimeInterval(session.updated))
    return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
  }
}

private struct SessionStatusPill: View {
  let session: SessionSummary

  var body: some View {
    if let label = statusLabel {
      Text(label)
        .font(.caption2)
        .foregroundStyle(statusColor)
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .background(statusColor.opacity(0.14))
        .clipShape(Capsule())
        .lineLimit(1)
    }
  }

  private var statusLabel: String? {
    if session.queue.running > 0 { return "Running" }
    if session.queue.pending > 0 { return session.queue.pending == 1 ? "Queued" : "\(session.queue.pending) queued" }
    if session.queue.lastStatus == "awaiting_approval" { return "Approval" }
    if session.queue.lastStatus == "awaiting_decision" { return "Decision" }
    return nil
  }

  private var statusColor: Color {
    if session.queue.running > 0 { return .green }
    if session.queue.pending > 0 { return .orange }
    if session.queue.lastStatus == "awaiting_approval" || session.queue.lastStatus == "awaiting_decision" { return .purple }
    return .secondary
  }
}

private struct EmptySidebarState: View {
  @ObservedObject var model: ArtificerModel

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("No projects")
        .font(.subheadline)
      Button {
        model.chooseWorkspaceFolder()
      } label: {
        Label("Add project", systemImage: "folder.badge.plus")
      }
      .buttonStyle(.bordered)
    }
    .padding(8)
  }
}

private struct RuntimeHealthView: View {
  @ObservedObject var model: ArtificerModel

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Label(model.coreReady ? "Core runtime ready" : "Core runtime missing", systemImage: model.coreReady ? "checkmark.circle" : "exclamationmark.triangle")
        .foregroundColor(model.coreReady ? .secondary : .orange)
      if let health = model.health {
        Text("Model: \(health.defaultModel)")
        Text("Installed models: \(health.installedModelCount)")
      } else {
        Text(model.resolvedCoreRoot.isEmpty ? "Set the Artificer core root in Preferences." : model.resolvedCoreRoot)
          .lineLimit(2)
      }
    }
    .font(.footnote)
  }
}

private struct SessionDetailView: View {
  @ObservedObject var model: ArtificerModel

  var body: some View {
    VStack(spacing: 0) {
      DetailHeader(model: model)
      Divider()

      if model.selectedSession == nil {
        EmptyStateView(title: "No Session Selected", systemImage: "message", detail: "Select or create a session.")
      } else {
        if let session = model.selectedSession {
          SessionAttentionStrip(model: model, session: session)
          RunTraceSummaryView(model: model, session: session)
          QueueInlineBar(model: model, session: session)
        }
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(model.selectedSession?.messages ?? []) { message in
              MessageView(message: message)
            }
            if (model.selectedSession?.messages ?? []).isEmpty {
              EmptyStateView(title: "Empty Session", systemImage: "text.bubble", detail: "Send a prompt to start the transcript.")
              .padding(.top, 80)
            }
          }
          .padding(16)
        }
        Divider()
        ComposerView(model: model)
      }
    }
  }
}

private struct DetailHeader: View {
  @ObservedObject var model: ArtificerModel

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 8) {
          Text(model.selectedSession?.title ?? "Artificer")
            .font(.title3)
            .lineLimit(1)
          if model.isSelectedSessionLoading {
            ProgressView()
              .controlSize(.small)
          }
        }
        HStack(spacing: 10) {
          if let session = model.selectedSession {
            Label(session.model, systemImage: "cpu")
            Label("pending \(session.queue.pending)", systemImage: "tray")
            Label("running \(session.queue.running)", systemImage: "play.circle")
          } else {
            Text("Native runtime console")
          }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
      }
      Spacer()
      FloatingIconButton(title: "Queue tray", systemImage: "tray.full", disabled: model.selectedSessionID == nil || model.isBusy) {
        model.showingQueueTray = true
        Task { await model.loadQueueItems() }
      }
      FloatingIconButton(title: "Refresh thread", systemImage: "arrow.clockwise", disabled: model.selectedSessionID == nil || model.isBusy) {
        Task { await model.loadSelectedSession() }
      }
    }
    .padding(12)
  }
}

private struct SessionAttentionStrip: View {
  @ObservedObject var model: ArtificerModel
  let session: SessionDetail

  var body: some View {
    VStack(spacing: 8) {
      if let request = session.approvalRequest {
        CommandApprovalCard(model: model, request: request)
      }
      if let request = session.decisionRequest {
        DecisionRequestCard(model: model, request: request)
      }
    }
    .padding(.horizontal, 12)
    .padding(.top, session.hasAttention ? 10 : 0)
  }
}

private struct CommandApprovalCard: View {
  @ObservedObject var model: ArtificerModel
  let request: ApprovalRequest

  @State private var matchMode = "exact"
  @State private var pattern = ""

  var body: some View {
    AttentionPanel(title: "Command approval", systemImage: "terminal", tone: .orange) {
      VStack(alignment: .leading, spacing: 8) {
        if !request.reason.isEmpty {
          Text(request.reason)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        Text(request.command)
          .font(.system(.footnote, design: .monospaced))
          .textSelection(.enabled)
          .padding(8)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(Color(nsColor: .textBackgroundColor))
          .clipShape(RoundedRectangle(cornerRadius: 7))

        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Picker("Rule type", selection: $matchMode) {
            Text("Exact command").tag("exact")
            Text("Regex pattern").tag("regex")
          }
          .pickerStyle(.menu)
          .frame(width: 154, alignment: .leading)
          TextField("Remember pattern", text: $pattern)
            .textFieldStyle(.roundedBorder)
            .font(.system(.footnote, design: .monospaced))
            .disabled(matchMode == "exact")
        }
        .font(.footnote)

        HStack(spacing: 8) {
          Button("Allow once") {
            Task { await model.answerApproval(decision: "allow", scope: "once", command: request.command) }
          }
          Button("Deny once") {
            Task { await model.answerApproval(decision: "deny", scope: "once", command: request.command) }
          }
          Button("Allow + remember") {
            Task { await model.answerApproval(decision: "allow", scope: "remember", matchMode: matchMode, pattern: pattern, command: request.command) }
          }
          Button("Deny + remember") {
            Task { await model.answerApproval(decision: "deny", scope: "remember", matchMode: matchMode, pattern: pattern, command: request.command) }
          }
        }
        .buttonStyle(.bordered)
        .fixedSize(horizontal: false, vertical: true)
      }
      .onAppear {
        resetPatternIfNeeded(force: true)
      }
      .onChange(of: request.command) { _ in
        resetPatternIfNeeded(force: true)
      }
      .onChange(of: matchMode) { _ in
        resetPatternIfNeeded(force: false)
      }
    }
  }

  private func resetPatternIfNeeded(force: Bool) {
    if force || matchMode == "exact" || pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      pattern = request.command
    }
  }
}

private struct DecisionRequestCard: View {
  @ObservedObject var model: ArtificerModel
  let request: DecisionRequest

  @State private var otherAnswer = ""

  var body: some View {
    AttentionPanel(title: "Decision needed", systemImage: "questionmark.bubble", tone: .blue) {
      VStack(alignment: .leading, spacing: 9) {
        Text(request.question)
          .font(.callout)
          .textSelection(.enabled)
        FlowHStack(items: request.options) { option in
          Button(option) {
            Task { await model.answerDecision(option) }
          }
          .buttonStyle(.borderedProminent)
          .fixedSize(horizontal: true, vertical: true)
        }
        HStack(spacing: 8) {
          TextField("Other", text: $otherAnswer)
            .textFieldStyle(.roundedBorder)
          Button {
            Task { await model.answerDecision(otherAnswer) }
          } label: {
            Label("Submit decision", systemImage: "arrow.up.circle")
          }
          .buttonStyle(.bordered)
          .disabled(otherAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
    }
  }
}

private struct AttentionPanel<Content: View>: View {
  enum Tone {
    case orange
    case blue

    var color: Color {
      switch self {
      case .orange: return .orange
      case .blue: return .blue
      }
    }
  }

  let title: String
  let systemImage: String
  let tone: Tone
  let content: Content

  init(title: String, systemImage: String, tone: Tone, @ViewBuilder content: () -> Content) {
    self.title = title
    self.systemImage = systemImage
    self.tone = tone
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label(title, systemImage: systemImage)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(tone.color)
      content
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(tone.color.opacity(0.10))
    .clipShape(RoundedRectangle(cornerRadius: 8))
  }
}

private struct RunTraceSummaryView: View {
  @ObservedObject var model: ArtificerModel
  let session: SessionDetail

  var body: some View {
    if let event = session.latestRunEvent {
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 8) {
          Label(runStatusLabel(event.status), systemImage: runStatusIcon(event.status))
            .font(.system(size: 13, weight: .semibold))
          if let started = session.trace.runningStartedAt, !started.isEmpty {
            Text(started)
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
          Spacer()
          if event.hasGitChanges {
            Button {
              model.gitDiff = GitDiffResponse(success: true, isRepo: true, added: event.changeSummary.added, deleted: event.changeSummary.deleted, diff: event.gitDiff)
              model.showingGitDiff = true
            } label: {
              Label("\(event.changeSummary.files.count) files", systemImage: "plusminus")
            }
            .buttonStyle(.borderless)
          }
        }
        if !event.streamTextPreview.isEmpty {
          Text(event.streamTextPreview)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(3)
            .textSelection(.enabled)
        }
        if !event.plan.isEmpty {
          Text(event.plan)
            .font(.footnote)
            .lineLimit(4)
            .textSelection(.enabled)
        }
        if let taskStatus = event.taskStatus, taskStatus.total > 0 {
          RunTaskStatusView(taskStatus: taskStatus, isRunning: event.status == "running")
        }
        if event.hasGitChanges {
          RunChangesMiniCard(summary: event.changeSummary)
        }
      }
      .padding(10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color(nsColor: .controlBackgroundColor).opacity(0.58))
      .clipShape(RoundedRectangle(cornerRadius: 8))
      .padding(.horizontal, 12)
      .padding(.top, 8)
    }
  }
}

private struct RunTaskStatusView: View {
  let taskStatus: RunTaskStatus
  let isRunning: Bool

  var body: some View {
    DisclosureGroup {
      VStack(alignment: .leading, spacing: 6) {
        ForEach(taskStatus.tasks.prefix(18)) { task in
          HStack(alignment: .top, spacing: 7) {
            Image(systemName: task.done ? "checkmark.circle.fill" : task.status == "active" ? "arrow.triangle.2.circlepath.circle" : "circle")
              .font(.system(size: 12, weight: .semibold))
              .foregroundStyle(task.done ? Color.green : task.status == "active" ? Color.accentColor : Color.secondary)
              .frame(width: 14)
            Text(task.text)
              .font(.caption)
              .foregroundStyle(task.done ? .secondary : .primary)
              .strikethrough(task.done, color: .secondary)
              .lineLimit(2)
          }
        }
      }
      .padding(.top, 6)
    } label: {
      HStack(spacing: 8) {
        Label(taskStatus.summaryText, systemImage: "checklist")
          .font(.caption)
          .foregroundStyle(.secondary)
        if isRunning {
          ProgressView()
            .controlSize(.mini)
        }
      }
    }
    .padding(8)
    .background(Color(nsColor: .textBackgroundColor))
    .clipShape(RoundedRectangle(cornerRadius: 7))
  }
}

private struct RunChangesMiniCard: View {
  let summary: RunChangeSummary

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack(spacing: 8) {
        Text("Changes made this run")
          .font(.caption)
          .foregroundStyle(.secondary)
        Text("+\(summary.added)")
          .font(.caption.monospacedDigit())
          .foregroundStyle(.green)
        Text("-\(summary.deleted)")
          .font(.caption.monospacedDigit())
          .foregroundStyle(.red)
      }
      ForEach(summary.files.prefix(5), id: \.self) { path in
        Text(path)
          .font(.system(size: 11, design: .monospaced))
          .lineLimit(1)
          .truncationMode(.middle)
      }
    }
    .padding(8)
    .background(Color(nsColor: .textBackgroundColor))
    .clipShape(RoundedRectangle(cornerRadius: 7))
  }
}

private struct QueueInlineBar: View {
  @ObservedObject var model: ArtificerModel
  let session: SessionDetail

  var body: some View {
    if session.queue.pending > 0 || session.queue.running > 0 || session.queue.lastStatus == "awaiting_approval" || session.queue.lastStatus == "awaiting_decision" {
      HStack(spacing: 8) {
        Label(queueLabel, systemImage: session.queue.running > 0 ? "play.circle" : "tray")
          .font(.footnote)
          .foregroundStyle(.secondary)
        Spacer()
        if session.queue.running > 0 {
          Button {
            Task { await model.stopQueueRun() }
          } label: {
            Label("Stop", systemImage: "stop.fill")
          }
          .buttonStyle(.bordered)
          .fixedSize()
        }
        Button {
          model.showingQueueTray = true
          Task { await model.loadQueueItems() }
        } label: {
          Label("Queue", systemImage: "tray.full")
        }
        .buttonStyle(.bordered)
        .fixedSize()
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(Color(nsColor: .controlBackgroundColor).opacity(0.42))
    }
  }

  private var queueLabel: String {
    var parts: [String] = []
    if session.queue.pending > 0 { parts.append("\(session.queue.pending) queued") }
    if session.queue.running > 0 { parts.append("\(session.queue.running) running") }
    if !session.queue.lastStatus.isEmpty { parts.append(session.queue.lastStatus.replacingOccurrences(of: "_", with: " ")) }
    return parts.isEmpty ? "Queue" : parts.joined(separator: " · ")
  }
}

private struct MessageView: View {
  let message: Message

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(message.role.capitalized)
        .font(.footnote)
        .foregroundStyle(.secondary)
      ZStack(alignment: .topTrailing) {
        Text(message.content)
          .textSelection(.enabled)
          .font(message.role == "tool" ? .system(.body, design: .monospaced) : .body)
          .padding(10)
          .padding(.trailing, 30)
          .frame(maxWidth: .infinity, alignment: .leading)
        FloatingIconButton(title: "Copy message", systemImage: "doc.on.doc", size: 26) {
          copyToPasteboard(message.content)
        }
        .padding(5)
      }
      .background(message.role == "user" ? Color.accentColor.opacity(0.10) : Color(nsColor: .textBackgroundColor))
      .clipShape(RoundedRectangle(cornerRadius: 8))
    }
  }
}

private struct EmptyStateView: View {
  let title: String
  let systemImage: String
  let detail: String

  var body: some View {
    VStack(spacing: 10) {
      Image(systemName: systemImage)
        .font(.largeTitle)
        .foregroundStyle(.secondary)
      Text(title)
        .font(.title3)
      Text(detail)
        .font(.callout)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

private struct FlowHStack<Content: View>: View {
  let items: [String]
  let content: (String) -> Content

  init(items: [String], @ViewBuilder content: @escaping (String) -> Content) {
    self.items = items
    self.content = content
  }

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(items, id: \.self) { item in
          content(item)
        }
      }
      .padding(.vertical, 1)
    }
  }
}

private struct GitDiffSheet: View {
  @ObservedObject var model: ArtificerModel

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 10) {
        Label(model.gitStatus.branch.isEmpty ? "Git changes" : model.gitStatus.branch, systemImage: "plusminus")
          .font(.headline)
        Spacer()
        Text("+\(model.gitDiff.added) -\(model.gitDiff.deleted)")
          .font(.system(.callout, design: .monospaced))
          .foregroundStyle(.secondary)
        FloatingIconButton(title: "Close diff", systemImage: "xmark", size: 26) {
          model.showingGitDiff = false
        }
        Button {
          Task { await model.loadGitDiff() }
        } label: {
          Label("Refresh", systemImage: "arrow.clockwise")
        }
        .buttonStyle(.bordered)
        .fixedSize()
      }
      if !model.gitDiff.diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        ScrollView {
          DiffTextView(diff: model.gitDiff.diff)
            .padding(10)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
      } else {
        EmptyStateView(title: "No Changes", systemImage: "checkmark.circle", detail: "The working tree has no diff to show.")
      }
      HStack {
        Spacer()
        Button {
          model.prepareCommit(pushAfter: false)
        } label: {
          Label("Commit", systemImage: "checkmark.seal")
        }
        .buttonStyle(.borderedProminent)
        .fixedSize()
        .disabled(model.gitStatus.changes == 0)
      }
    }
    .padding(16)
    .task {
      await model.loadGitDiff()
    }
  }
}

private struct DiffTextView: View {
  let diff: String

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(Array(diffLines.enumerated()), id: \.offset) { _, line in
        Text(line.isEmpty ? " " : line)
          .foregroundStyle(color(for: line))
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .font(.system(size: 12, design: .monospaced))
    .textSelection(.enabled)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var diffLines: [String] {
    diff.components(separatedBy: .newlines)
  }

  private func color(for line: String) -> Color {
    if line.hasPrefix("+++") || line.hasPrefix("---") { return Color.accentColor }
    if line.hasPrefix("@@") { return .purple }
    if line.hasPrefix("+") { return .green }
    if line.hasPrefix("-") { return .red }
    if line.hasPrefix("diff ") || line.hasPrefix("index ") { return .secondary }
    return .primary
  }
}

private struct CommitSheet: View {
  @ObservedObject var model: ArtificerModel

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label(model.commitPushAfter ? "Commit and push" : "Commit", systemImage: model.commitPushAfter ? "arrow.up.doc" : "checkmark.seal")
        .font(.headline)
      HStack(spacing: 10) {
        Text(model.gitStatus.branch.isEmpty ? "No branch" : model.gitStatus.branch)
          .font(.footnote)
          .foregroundStyle(.secondary)
        Text("+\(model.gitStatus.added) -\(model.gitStatus.deleted)")
          .font(.footnote.monospacedDigit())
          .foregroundStyle(.secondary)
      }
      Toggle("Include unstaged changes", isOn: $model.commitIncludeUnstaged)
        .fixedSize()
      TextEditor(text: $model.commitMessage)
        .font(.body)
        .frame(minHeight: 90)
        .overlay(
          RoundedRectangle(cornerRadius: 8)
            .stroke(Color.secondary.opacity(0.18))
        )
      HStack {
        Spacer()
        Button("Cancel") {
          model.showingCommitDialog = false
        }
        .fixedSize()
        Button {
          Task { await model.commitGitChanges() }
        } label: {
          Label(model.commitPushAfter ? "Commit and push" : "Commit", systemImage: model.commitPushAfter ? "arrow.up.doc" : "checkmark")
        }
        .buttonStyle(.borderedProminent)
        .fixedSize()
        .disabled(model.isBusy)
      }
    }
    .padding(16)
  }
}

private struct BranchSheet: View {
  @ObservedObject var model: ArtificerModel

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label("Create branch", systemImage: "arrow.triangle.branch")
        .font(.headline)
      TextField("codex/native-parity", text: $model.branchNameDraft)
        .textFieldStyle(.roundedBorder)
      HStack {
        Spacer()
        Button("Cancel") {
          model.showingBranchDialog = false
        }
        .fixedSize()
        Button {
          Task { await model.createBranch() }
        } label: {
          Label("Create", systemImage: "plus")
        }
        .buttonStyle(.borderedProminent)
        .fixedSize()
        .disabled(model.branchNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isBusy)
      }
    }
    .padding(16)
  }
}

private struct QueueTraySheet: View {
  @ObservedObject var model: ArtificerModel
  @State private var drafts: [String: String] = [:]

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Label("Queue", systemImage: "tray.full")
          .font(.headline)
        Spacer()
        FloatingIconButton(title: "Close queue", systemImage: "xmark", size: 26) {
          model.showingQueueTray = false
        }
        Button {
          Task { await model.loadQueueItems() }
        } label: {
          Label("Refresh", systemImage: "arrow.clockwise")
        }
        .buttonStyle(.bordered)
        .fixedSize()
        if (model.selectedSession?.queue.running ?? 0) > 0 {
          Button {
            Task { await model.stopQueueRun() }
          } label: {
            Label("Stop", systemImage: "stop.fill")
          }
          .buttonStyle(.bordered)
          .fixedSize()
        }
      }
      if model.queueItems.isEmpty {
        EmptyStateView(title: "Queue Empty", systemImage: "tray", detail: "No pending items for this thread.")
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 10) {
            ForEach(Array(model.queueItems.enumerated()), id: \.element.id) { index, item in
              QueueItemEditor(model: model, item: item, canMoveUp: index > 0, canMoveDown: index < model.queueItems.count - 1, text: Binding(
                get: { drafts[item.id] ?? item.prompt },
                set: { drafts[item.id] = $0 }
              ))
            }
          }
        }
      }
    }
    .padding(16)
    .task {
      await model.loadQueueItems()
    }
  }
}

private struct QueueItemEditor: View {
  @ObservedObject var model: ArtificerModel
  let item: QueueItem
  let canMoveUp: Bool
  let canMoveDown: Bool
  @Binding var text: String

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(item.order.isEmpty ? item.id : item.order)
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
        Spacer()
        Text([item.runMode, item.computeBudget, item.commandExecMode].filter { !$0.isEmpty }.joined(separator: " · "))
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      TextEditor(text: $text)
        .font(.body)
        .frame(minHeight: 72)
        .overlay(
          RoundedRectangle(cornerRadius: 7)
            .stroke(Color.secondary.opacity(0.14))
        )
      HStack {
        FloatingIconButton(title: "Move earlier", systemImage: "arrow.up", disabled: !canMoveUp || model.isBusy, size: 26) {
          Task { await model.moveQueueItem(item.id, direction: -1) }
        }
        FloatingIconButton(title: "Move later", systemImage: "arrow.down", disabled: !canMoveDown || model.isBusy, size: 26) {
          Task { await model.moveQueueItem(item.id, direction: 1) }
        }
        Spacer()
        Button {
          Task { await model.updateQueueItem(item.id, prompt: text) }
        } label: {
          Label("Save", systemImage: "checkmark")
        }
        .buttonStyle(.bordered)
        .fixedSize()
        Button {
          Task { await model.cancelQueueItem(item.id) }
        } label: {
          Label("Cancel item", systemImage: "xmark")
        }
        .buttonStyle(.bordered)
        .fixedSize()
      }
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(nsColor: .controlBackgroundColor).opacity(0.56))
    .clipShape(RoundedRectangle(cornerRadius: 8))
  }
}

private struct TerminalPanelSheet: View {
  @ObservedObject var model: ArtificerModel

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Label(model.terminalRunning ? "Terminal running" : "Terminal", systemImage: "terminal")
          .font(.headline)
        Spacer()
        FloatingIconButton(title: "Close terminal", systemImage: "xmark", size: 26) {
          model.showingTerminalPanel = false
        }
        Button {
          Task { await model.startTerminalSession() }
        } label: {
          Label("Start", systemImage: "play.fill")
        }
        .buttonStyle(.bordered)
        .fixedSize()
        Button {
          Task { await model.pollTerminalSession() }
        } label: {
          Label("Poll", systemImage: "arrow.clockwise")
        }
        .buttonStyle(.bordered)
        .fixedSize()
        Button {
          Task { await model.stopTerminalSession() }
        } label: {
          Label("Stop", systemImage: "stop.fill")
        }
        .buttonStyle(.bordered)
        .fixedSize()
        .disabled(model.terminalSessionID.isEmpty)
      }
      ScrollView {
        Text(model.terminalOutput.isEmpty ? "No terminal output yet." : model.terminalOutput)
          .font(.system(size: 12, design: .monospaced))
          .foregroundStyle(model.terminalOutput.isEmpty ? .secondary : .primary)
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(10)
      }
      .background(Color(nsColor: .textBackgroundColor))
      .clipShape(RoundedRectangle(cornerRadius: 8))
      HStack(spacing: 8) {
        TextField("Command", text: $model.terminalInput)
          .textFieldStyle(.roundedBorder)
          .onSubmit {
            Task { await model.sendTerminalInput() }
          }
          .disabled(model.terminalSessionID.isEmpty || !model.terminalRunning)
        FloatingIconButton(
          title: "Send terminal input",
          systemImage: "arrow.turn.down.left",
          disabled: model.terminalSessionID.isEmpty || !model.terminalRunning || model.terminalInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          prominence: .accent
        ) {
          Task { await model.sendTerminalInput() }
        }
      }
    }
    .padding(16)
    .task {
      if model.terminalSessionID.isEmpty {
        await model.startTerminalSession()
      }
    }
  }
}

private struct ModelQuickPanel: View {
  @ObservedObject var model: ArtificerModel

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Label("Models", systemImage: "shippingbox")
          .font(.headline)
        Spacer()
        FloatingIconButton(title: "Close models", systemImage: "xmark", size: 26) {
          model.showingModelsPanel = false
        }
        Button {
          Task { await model.loadModelData() }
        } label: {
          Label("Refresh", systemImage: "arrow.clockwise")
        }
        .buttonStyle(.bordered)
        .fixedSize()
      }
      HStack(alignment: .top, spacing: 14) {
        ModelColumn(title: "Installed", entries: model.installedModels) { name in
          Button {
            Task { await model.setSelectedSessionModel(name) }
          } label: {
            Label(modelDisplayName(name), systemImage: name == model.activeComposerModel ? "checkmark.circle.fill" : "cpu")
          }
          .buttonStyle(.borderless)
          .fixedSize(horizontal: true, vertical: true)
        }
        ModelCatalogColumn(model: model)
      }
      if !model.modelInstallMessage.isEmpty {
        Text(model.modelInstallMessage)
          .font(.footnote)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }
    }
    .padding(16)
    .task {
      await model.loadModelData()
    }
  }
}

private struct ModelColumn<RowContent: View>: View {
  let title: String
  let entries: [String]
  let row: (String) -> RowContent

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.subheadline)
        .foregroundStyle(.secondary)
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 6) {
          if entries.isEmpty {
            Text("None")
              .font(.footnote)
              .foregroundStyle(.secondary)
          } else {
            ForEach(entries, id: \.self) { entry in
              row(entry)
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
  }
}

private struct ModelCatalogColumn: View {
  @ObservedObject var model: ArtificerModel

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Available")
        .font(.subheadline)
        .foregroundStyle(.secondary)
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 8) {
          if model.installableCatalogEntries.isEmpty {
            Text("Catalog is current")
              .font(.footnote)
              .foregroundStyle(.secondary)
          } else {
            ForEach(model.installableCatalogEntries) { entry in
              HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                  Text(modelDisplayName(entry.name))
                    .font(.footnote)
                  Text(entry.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                }
                Spacer()
                Button {
                  Task { await model.installModel(entry.name) }
                } label: {
                  Text(model.installLabel(for: entry.name))
                }
                .buttonStyle(.bordered)
                .fixedSize()
                .disabled(model.isInstallingModel(entry.name))
              }
            }
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
  }
}

private struct AutomationsDetailView: View {
  @ObservedObject var model: ArtificerModel

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Automations")
            .font(.title3)
          Text(automationSubtitle)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        Spacer()
        Button {
          Task { await model.loadAutomations() }
        } label: {
          Label("Refresh", systemImage: "arrow.clockwise")
        }
        .disabled(model.isBusy)
        Button {
          Task { await model.daemon("automation-daemon-tick") }
        } label: {
          Label("Run Due Automations", systemImage: "play.fill")
        }
        .disabled(!(model.daemonStatus?.enabled ?? false) || model.isBusy)
      }
      .padding(12)

      Divider()

      HSplitView {
        AutomationCreatePane(model: model)
          .frame(minWidth: 280, idealWidth: 340, maxWidth: 420, maxHeight: .infinity)
        AutomationListPane(model: model)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .task {
      await model.loadAutomations()
      await model.loadDaemonStatus()
      await model.loadDesktopPrefs()
      await model.loadVoiceAutomationStatus()
    }
  }

  private var automationSubtitle: String {
    if let daemon = model.daemonStatus {
      return "Background runtime: \(daemon.status). \(model.automations.count) automation\(model.automations.count == 1 ? "" : "s")."
    }
    return "\(model.automations.count) automation\(model.automations.count == 1 ? "" : "s")."
  }
}

private struct AutomationCreatePane: View {
  @ObservedObject var model: ArtificerModel

  var body: some View {
    Form {
      Section("Add Automation") {
        TextField("Name", text: $model.automationDraftName)
        Picker("Project", selection: Binding(
          get: { model.automationDraftProjectID.isEmpty ? (model.selectedProjectID ?? "") : model.automationDraftProjectID },
          set: { model.automationDraftProjectID = $0 }
        )) {
          Text("Select project").tag("")
          ForEach(model.projects) { project in
            Text(project.name).tag(project.id)
          }
        }
        Picker("Thread", selection: Binding(
          get: { model.automationDraftSessionID.isEmpty ? (model.selectedSessionID ?? "") : model.automationDraftSessionID },
          set: { model.automationDraftSessionID = $0 }
        )) {
          Text("Select thread").tag("")
          ForEach(model.automationDraftSessions) { session in
            Text(session.title.isEmpty ? session.id : session.title).tag(session.id)
          }
        }
        Picker("Schedule", selection: $model.automationDraftScheduleKind) {
          Text("Interval").tag("interval")
          Text("Daily").tag("daily")
        }
        TextField(model.automationDraftScheduleKind == "daily" ? "09:00" : "1h", text: $model.automationDraftScheduleValue)
        TextEditor(text: $model.automationDraftPrompt)
          .font(.body)
          .frame(minHeight: 120)
        Toggle("Enabled", isOn: $model.automationDraftEnabled)
        Toggle("Allow self-reschedule", isOn: $model.automationDraftAllowSelfReschedule)
        Toggle("Set first run time", isOn: $model.automationDraftUsesNextRun)
        if model.automationDraftUsesNextRun {
          DatePicker("First run", selection: $model.automationDraftNextRunDate, displayedComponents: [.date, .hourAndMinute])
            .frame(maxWidth: 280, alignment: .leading)
        }
        Picker("Run mode", selection: $model.automationDraftRunMode) {
          ForEach(model.runModes, id: \.self) { mode in
            Text(mode).tag(mode)
          }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: 220, alignment: .leading)
        Picker("Compute", selection: $model.automationDraftComputeBudget) {
          ForEach(model.computeBudgets, id: \.self) { budget in
            Text(budget).tag(budget)
          }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: 180, alignment: .leading)
        Picker("Commands", selection: $model.automationDraftCommandExecMode) {
          ForEach(model.commandExecModes, id: \.self) { mode in
            Text(mode).tag(mode)
          }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: 180, alignment: .leading)
        Picker("Permission", selection: $model.automationDraftPermissionMode) {
          ForEach(model.permissionModes, id: \.self) { mode in
            Text(mode).tag(mode)
          }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: 180, alignment: .leading)
        Toggle("Programmer review", isOn: $model.automationDraftProgrammerReview)
        Picker("Review rounds", selection: $model.automationDraftProgrammerReviewRounds) {
          ForEach(1...4, id: \.self) { round in
            Text("\(round)").tag(round)
          }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: 160, alignment: .leading)
        Button {
          Task { await model.createAutomationFromDraft() }
        } label: {
          Label("Add Automation", systemImage: "plus.circle")
        }
        .disabled(!model.canCreateAutomation || model.isBusy)
      }
    }
    .formStyle(.grouped)
    .padding(.vertical, 8)
    .onChange(of: model.automationDraftProjectID) { projectID in
      Task { await model.loadAutomationDraftSessions(projectID: projectID) }
    }
  }
}

private struct AutomationListPane: View {
  @ObservedObject var model: ArtificerModel

  var body: some View {
    Group {
      if model.automations.isEmpty {
        EmptyStateView(title: "No Automations", systemImage: "clock.badge.questionmark", detail: "Add an automation from the form.")
      } else {
        List(model.automations) { automation in
          AutomationListRow(model: model, automation: automation)
        }
        .listStyle(.inset)
      }
    }
  }
}

private struct AutomationListRow: View {
  @ObservedObject var model: ArtificerModel
  let automation: AutomationItem

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        VStack(alignment: .leading, spacing: 3) {
          Text(automation.name)
            .font(.headline)
          Text(automation.scheduleText.isEmpty ? automation.scheduleKind : automation.scheduleText)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Toggle("", isOn: Binding(
          get: { automation.enabled },
          set: { enabled in
            Task { await model.toggleAutomation(automation, enabled: enabled) }
          }
        ))
        .labelsHidden()
      }
      HStack(spacing: 10) {
        Label(automation.workspaceName.isEmpty ? automation.workspaceID : automation.workspaceName, systemImage: "folder")
        Label(automation.conversationTitle.isEmpty ? automation.conversationID : automation.conversationTitle, systemImage: "text.bubble")
      }
      .font(.caption)
      .foregroundStyle(.secondary)
      HStack(spacing: 10) {
        if !automation.runMode.isEmpty {
          Label(automation.runMode, systemImage: "slider.horizontal.3")
        }
        if !automation.commandExecMode.isEmpty {
          Label(automation.commandExecMode, systemImage: "terminal")
        }
        if automation.allowSelfReschedule {
          Label("self-reschedule", systemImage: "calendar.badge.clock")
        }
        if !automation.nextRunISO.isEmpty {
          Label(automation.nextRunISO, systemImage: "calendar")
        }
      }
      .font(.caption)
      .foregroundStyle(.secondary)
      if !automation.prompt.isEmpty {
        Text(automation.prompt)
          .font(.callout)
          .lineLimit(3)
      }
      HStack {
        Button {
          Task { await model.runAutomationNow(automation) }
        } label: {
          Label("Run Now", systemImage: "play.fill")
        }
        .disabled(model.isBusy)
        Spacer()
        if !automation.lastStatus.isEmpty {
          Text(automation.lastStatus)
            .font(.caption)
            .foregroundColor(automation.lastError.isEmpty ? .secondary : .red)
        }
      }
    }
    .padding(.vertical, 6)
  }
}

private struct ComposerView: View {
  @ObservedObject var model: ArtificerModel

  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      ZStack(alignment: .topLeading) {
        TextEditor(text: $model.prompt)
          .font(.body)
          .frame(minHeight: 78, idealHeight: 96, maxHeight: 116)
          .scrollContentBackground(.hidden)
          .padding(.horizontal, 8)
          .padding(.vertical, 6)

        if model.prompt.isEmpty {
          Text("Ask Artificer, attach files, or queue work for the selected session.")
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .allowsHitTesting(false)
        }
      }
      .background(model.isComposerDropTargeted ? Color.accentColor.opacity(0.06) : Color(nsColor: .textBackgroundColor))
      .clipShape(RoundedRectangle(cornerRadius: 14))
      .overlay {
        RoundedRectangle(cornerRadius: 14)
          .stroke(model.isComposerDropTargeted ? Color.accentColor.opacity(0.75) : Color.secondary.opacity(0.20), lineWidth: model.isComposerDropTargeted ? 2 : 1)
      }
      .onDrop(of: [UTType.fileURL], isTargeted: $model.isComposerDropTargeted) { providers in
        model.handleDroppedAttachments(providers)
      }

      if !model.pendingAttachments.isEmpty {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            ForEach(model.pendingAttachments) { attachment in
              AttachmentChip(attachment: attachment) {
                model.removeAttachment(attachment)
              }
            }
          }
        }
      }

      if model.isDictating {
        DictationWaveView(levels: model.dictationLevels, elapsed: model.dictationElapsedText)
      }

      HStack(alignment: .center, spacing: 8) {
        FloatingIconButton(title: "Attach files", systemImage: "paperclip", disabled: model.selectedSessionID == nil || model.isBusy || model.isDictating) {
          model.chooseAttachments()
        }

        ComposerOptionsBar(model: model)

        Spacer(minLength: 4)

        FloatingIconButton(
          title: model.isDictating ? "Stop dictation" : "Dictate prompt",
          systemImage: model.isDictating ? "stop.fill" : "mic.fill",
          disabled: model.selectedSessionID == nil || (model.isBusy && !model.isDictating)
        ) {
          Task { await model.toggleDictation() }
        }

        FloatingIconButton(title: "Queue prompt", systemImage: "tray.and.arrow.down", disabled: !model.canSendPrompt) {
          Task { await model.sendPrompt(runAfterQueue: false) }
        }

        FloatingIconButton(
          title: "Send and run",
          systemImage: "arrow.up",
          disabled: !model.canSendPrompt,
          prominence: .accent,
          size: 34
        ) {
          Task { await model.sendPrompt(runAfterQueue: true) }
        }
        .keyboardShortcut(.return, modifiers: [.command])
      }
    }
    .padding(12)
    .padding(.bottom, 28)
    .onChange(of: model.prompt) { nextPrompt in
      model.updateActivePromptDraft(nextPrompt)
    }
  }
}

private struct ComposerOptionsBar: View {
  @ObservedObject var model: ArtificerModel

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 7) {
        ComposerModelMenu(model: model)
        ComposerOptionMenu(systemImage: "slider.horizontal.3", title: "Run mode", selection: $model.runMode, values: model.runModes)
        ComposerOptionMenu(systemImage: "brain.head.profile", title: "Reasoning depth", selection: $model.reasoningEffort, values: model.reasoningEfforts)
        ComposerOptionMenu(systemImage: "clock", title: "Compute budget", selection: $model.computeBudget, values: model.computeBudgets)
        ComposerOptionMenu(systemImage: "terminal", title: "Command execution", selection: $model.commandExecMode, values: model.commandExecModes)
        ComposerOptionMenu(systemImage: "shield", title: "Permission mode", selection: $model.permissionMode, values: model.permissionModes)
        ComposerToggleIconButton(title: "Network access", systemImage: "network", isOn: $model.networkAccessEnabled)
        ComposerToggleIconButton(title: "Web access", systemImage: "globe", isOn: $model.webAccessEnabled)
        ComposerToggleIconButton(title: "Programmer review", systemImage: "checkmark.seal", isOn: $model.programmerReview)
        ComposerToggleIconButton(title: "Reflexive knowledge", systemImage: "brain.head.profile", isOn: $model.reflexiveKnowledge)
        ComposerToggleIconButton(title: "Self-actuation", systemImage: "wand.and.stars", isOn: $model.selfActuation)
        ComposerContextBadge(model: model)
      }
      .padding(.vertical, 2)
    }
    .frame(minHeight: 34)
  }
}

private struct ComposerContextBadge: View {
  @ObservedObject var model: ArtificerModel

  var body: some View {
    HStack(spacing: 5) {
      Image(systemName: "rectangle.stack")
        .font(.system(size: 12, weight: .semibold))
      Text(model.activeContextWindowLabel)
        .font(.system(size: 12))
        .lineLimit(1)
    }
    .foregroundStyle(.secondary)
    .padding(.horizontal, 6)
    .frame(height: 28)
    .help("Context window")
  }
}

private struct ComposerModelMenu: View {
  @ObservedObject var model: ArtificerModel

  var body: some View {
    Menu {
      if model.installedModels.isEmpty {
        Button("Refresh models") {
          Task { await model.loadModelData() }
        }
      } else {
        ForEach(model.installedModels, id: \.self) { modelName in
          Button {
            Task { await model.setSelectedSessionModel(modelName) }
          } label: {
            HStack {
              Text(modelDisplayName(modelName))
              if modelName == model.activeComposerModel {
                Image(systemName: "checkmark")
              }
            }
          }
        }
      }
    } label: {
      ComposerOptionLabel(systemImage: "cpu", text: modelDisplayName(model.activeComposerModel.isEmpty ? "Select model" : model.activeComposerModel))
    }
    .menuStyle(.borderlessButton)
    .fixedSize(horizontal: true, vertical: true)
    .help("Select model")
    .disabled(model.selectedSessionID == nil || model.isBusy)
  }
}

private struct ComposerOptionMenu: View {
  let systemImage: String
  let title: String
  @Binding var selection: String
  let values: [String]

  var body: some View {
    Menu {
      ForEach(values, id: \.self) { value in
        Button {
          selection = value
        } label: {
          HStack {
            Text(composerOptionDisplayName(value))
            if selection == value {
              Image(systemName: "checkmark")
            }
          }
        }
      }
    } label: {
      ComposerOptionLabel(systemImage: systemImage, text: composerOptionDisplayName(selection))
    }
    .menuStyle(.borderlessButton)
    .fixedSize(horizontal: true, vertical: true)
    .help(title)
  }
}

private struct ComposerOptionLabel: View {
  let systemImage: String
  let text: String

  var body: some View {
    HStack(spacing: 5) {
      Image(systemName: systemImage)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.secondary)
      Text(text)
        .font(.system(size: 12))
        .lineLimit(1)
      Image(systemName: "chevron.down")
        .font(.system(size: 8, weight: .semibold))
        .foregroundStyle(.tertiary)
    }
    .padding(.horizontal, 6)
    .frame(height: 28)
    .contentShape(Capsule())
  }
}

private struct ComposerToggleIconButton: View {
  let title: String
  let systemImage: String
  @Binding var isOn: Bool

  var body: some View {
    Button {
      isOn.toggle()
    } label: {
      Image(systemName: systemImage)
        .font(.system(size: 13, weight: .semibold))
        .frame(width: 28, height: 28)
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
    .background(isOn ? Color.accentColor.opacity(0.12) : Color.clear)
    .clipShape(Circle())
    .help(title)
    .accessibilityLabel(Text(title))
    .accessibilityValue(Text(isOn ? "On" : "Off"))
  }
}

private func modelDisplayName(_ modelName: String) -> String {
  let trimmed = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !trimmed.isEmpty else { return "Select model" }
  let parts = trimmed.split(separator: ":", maxSplits: 1).map(String.init)
  guard let first = parts.first, !first.isEmpty else { return trimmed }
  return first
}

private func runStatusLabel(_ status: String) -> String {
  switch status {
  case "running": return "Running"
  case "done": return "Done"
  case "error": return "Error"
  case "cancelled": return "Cancelled"
  case "awaiting_decision": return "Decision needed"
  case "awaiting_approval": return "Approval needed"
  default:
    return status.isEmpty ? "Run trace" : status.replacingOccurrences(of: "_", with: " ").capitalized
  }
}

private func runStatusIcon(_ status: String) -> String {
  switch status {
  case "running": return "play.circle"
  case "done": return "checkmark.circle"
  case "error": return "exclamationmark.triangle"
  case "cancelled": return "stop.circle"
  case "awaiting_decision": return "questionmark.bubble"
  case "awaiting_approval": return "terminal"
  default: return "list.bullet.rectangle"
  }
}

private func normalizedTaskStatus(_ status: String) -> String {
  switch status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
  case "done", "completed", "complete", "finished":
    return "done"
  case "active", "in-progress", "in_progress", "working":
    return "active"
  default:
    return "pending"
  }
}

private func composerOptionDisplayName(_ value: String) -> String {
  switch value {
  case "instant": return "Instant"
  case "auto": return "Auto/Thinking"
  case "programming": return "Programming"
  case "pentest": return "Pentest"
  case "security-audit": return "Security Audit"
  case "chat": return "Chat"
  case "teacher": return "Teacher"
  case "report": return "Report"
  case "text-perfecter": return "Text Perfecter"
  case "gui-testing": return "GUI Testing"
  case "assistant": return "Team"
  case "quick": return "Instant"
  case "standard": return "Standard"
  case "long": return "Long-term"
  case "until-complete": return "Until Complete"
  case "ask-some": return "Ask some"
  case "all": return "Ask none"
  case "none": return "None"
  case "default": return "Default permissions"
  case "ask": return "Ask"
  case "never": return "Never"
  default:
    return value
      .split(separator: "-")
      .map { part in part.prefix(1).uppercased() + String(part.dropFirst()) }
      .joined(separator: " ")
  }
}

private struct AttachmentChip: View {
  let attachment: PendingAttachment
  let remove: () -> Void

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: attachment.kind == "image" ? "photo" : "doc")
      Text(attachment.name)
        .lineLimit(1)
      Text(attachment.sizeLabel)
        .foregroundStyle(.secondary)
      Button {
        remove()
      } label: {
        Image(systemName: "xmark.circle.fill")
      }
      .buttonStyle(.plain)
      .help("Remove attachment")
    }
    .font(.footnote)
    .padding(.horizontal, 8)
    .padding(.vertical, 5)
    .background(Color(nsColor: .controlBackgroundColor))
    .clipShape(RoundedRectangle(cornerRadius: 8))
  }
}

private struct DictationWaveView: View {
  let levels: [Double]
  let elapsed: String

  private var bars: [Double] {
    let usable = levels.suffix(24)
    if usable.isEmpty {
      return Array(repeating: 0.08, count: 24)
    }
    let prefix = Array(repeating: 0.08, count: max(0, 24 - usable.count))
    return prefix + usable
  }

  var body: some View {
    HStack(spacing: 10) {
      Label("Recording", systemImage: "mic.fill")
        .foregroundColor(.red)
      HStack(alignment: .center, spacing: 3) {
        ForEach(Array(bars.enumerated()), id: \.offset) { _, level in
          RoundedRectangle(cornerRadius: 2)
            .fill(Color.accentColor)
            .frame(width: 4, height: max(4, 34 * CGFloat(level)))
            .animation(.easeOut(duration: 0.14), value: level)
        }
      }
      .frame(height: 38)
      Text(elapsed)
        .font(.system(.footnote, design: .monospaced))
        .foregroundStyle(.secondary)
    }
    .font(.footnote)
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(Color.red.opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: 8))
  }
}

private struct StatusBar: View {
  @ObservedObject var model: ArtificerModel

  var body: some View {
    HStack(spacing: 14) {
      if model.isBusy {
        ProgressView()
          .controlSize(.small)
      }
      Text(model.statusMessage)
        .lineLimit(1)
      Spacer()
      if let daemon = model.daemonStatus {
        Label(daemon.status, systemImage: daemon.enabled ? "timer" : "timer.circle")
        Text("queued \(daemon.taskPending)")
      }
      if !model.lastError.isEmpty {
        Text(model.lastError)
          .foregroundStyle(.red)
          .lineLimit(1)
        Button {
          copyToPasteboard(model.lastError)
          model.statusMessage = "Error copied."
        } label: {
          Image(systemName: "doc.on.doc")
            .font(.system(size: 11, weight: .semibold))
            .frame(width: 22, height: 22)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help("Copy error")
        .accessibilityLabel(Text("Copy error"))
      }
    }
    .font(.footnote)
    .padding(.horizontal, 12)
    .padding(.vertical, 7)
    .background(.bar)
  }
}

private struct SettingsView: View {
  @ObservedObject var model: ArtificerModel

  var body: some View {
    VStack(spacing: 0) {
      PreferencesTabStrip(selection: $model.preferencesTab)
      Divider()
      selectedPane
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .background(Color(nsColor: .windowBackgroundColor))
    .onAppear {
      if !preferencesTabs.contains(where: { $0.id == model.preferencesTab }) {
        model.preferencesTab = "general"
      }
    }
    .task {
      await model.loadPreferences()
    }
  }

  @ViewBuilder
  private var selectedPane: some View {
    switch model.preferencesTab {
    case "voice-control":
      VoiceControlPreferencesTab(model: model)
    case "automations":
      AutomationsPreferencesTab(model: model)
    case "self-improve":
      SelfImprovePreferencesTab(model: model)
    case "runtime":
      RuntimePreferencesTab(model: model)
    case "mobile":
      MobilePreferencesTab(model: model)
    case "git":
      GitPreferencesTab(model: model)
    default:
      GeneralPreferencesTab(model: model)
    }
  }
}

private struct PreferencesTabDescriptor: Identifiable {
  let id: String
  let title: String
  let systemImage: String
}

private let preferencesTabs = [
  PreferencesTabDescriptor(id: "general", title: "General", systemImage: "gearshape"),
  PreferencesTabDescriptor(id: "voice-control", title: "Voice Control", systemImage: "waveform.circle"),
  PreferencesTabDescriptor(id: "automations", title: "Automations", systemImage: "clock.arrow.circlepath"),
  PreferencesTabDescriptor(id: "self-improve", title: "Self-improve", systemImage: "wand.and.stars"),
  PreferencesTabDescriptor(id: "runtime", title: "Runtime", systemImage: "slider.horizontal.3"),
  PreferencesTabDescriptor(id: "mobile", title: "Mobile", systemImage: "iphone"),
  PreferencesTabDescriptor(id: "git", title: "Git", systemImage: "arrow.triangle.branch")
]

private struct PreferencesTabStrip: View {
  @Binding var selection: String

  var body: some View {
    HStack(alignment: .center, spacing: 6) {
      ForEach(preferencesTabs) { tab in
        Button {
          selection = tab.id
        } label: {
          VStack(spacing: 4) {
            Image(systemName: tab.systemImage)
              .font(.system(size: 17, weight: .medium))
              .frame(height: 20)
            Text(tab.title)
              .font(.caption)
              .lineLimit(1)
          }
          .foregroundStyle(selection == tab.id ? Color.accentColor : Color.primary)
          .frame(minWidth: 74)
          .padding(.horizontal, 6)
          .padding(.vertical, 7)
          .background(
            RoundedRectangle(cornerRadius: 8)
              .fill(selection == tab.id ? Color.accentColor.opacity(0.14) : Color.clear)
          )
          .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help(tab.title)
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 14)
    .padding(.top, 10)
    .padding(.bottom, 8)
    .background(.bar)
  }
}

private struct GeneralPreferencesTab: View {
  @ObservedObject var model: ArtificerModel
  @State private var pendingUninstallModel = ""

  var body: some View {
    PreferencesPane {
      PreferencesSection("Models") {
        Toggle("Use GPU acceleration for LLMs", isOn: Binding(
          get: { model.llmUseGpu },
          set: { nextValue in
            Task { await model.saveLlmRuntimeSettings(useGpu: nextValue) }
          }
        ))
        Picker("Default model", selection: Binding(
          get: { model.selectedDefaultModel },
          set: { nextValue in
            Task { await model.saveLlmRuntimeSettings(defaultModel: nextValue) }
          }
        )) {
          Text(model.health?.defaultModel ?? "Runtime default").tag("")
          ForEach(model.installedModels, id: \.self) { modelName in
            Text(modelName).tag(modelName)
          }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: 280, alignment: .leading)
        Toggle("Generate compact thread titles", isOn: Binding(
          get: { model.smartConversationTitles },
          set: { nextValue in
            Task { await model.saveLlmRuntimeSettings(smartTitles: nextValue) }
          }
        ))
        if !model.modelInstallMessage.isEmpty {
          Text(model.modelInstallMessage)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        VStack(alignment: .leading, spacing: 8) {
          Text("Installed")
            .font(.subheadline.weight(.semibold))
          if model.installedModels.isEmpty {
            Text("No local models installed.")
              .font(.footnote)
              .foregroundStyle(.secondary)
          } else {
            ForEach(model.installedModels, id: \.self) { modelName in
              HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                  Text(modelName)
                    .font(.body)
                    .textSelection(.enabled)
                  if let entry = model.catalogEntry(named: modelName), !entry.description.isEmpty {
                    Text(entry.description)
                      .font(.caption)
                      .foregroundStyle(.secondary)
                      .fixedSize(horizontal: false, vertical: true)
                  }
                }
                Spacer(minLength: 12)
                if modelName == model.selectedDefaultModel || (model.selectedDefaultModel.isEmpty && modelName == model.health?.defaultModel) {
                  Text("Default")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                  Button("Make Default") {
                    Task { await model.saveLlmRuntimeSettings(defaultModel: modelName) }
                  }
                }
                Button(pendingUninstallModel == modelName ? "Confirm Uninstall" : "Uninstall") {
                  if pendingUninstallModel == modelName {
                    pendingUninstallModel = ""
                    Task { await model.uninstallModel(modelName) }
                  } else {
                    pendingUninstallModel = modelName
                  }
                }
              }
              .buttonStyle(.bordered)
            }
          }
        }
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Text("Install")
              .font(.subheadline.weight(.semibold))
            Button("Refresh") { Task { await model.loadModelData() } }
              .buttonStyle(.bordered)
          }
          let installable = model.installableCatalogEntries
          if installable.isEmpty {
            Text("No additional curated models are available right now.")
              .font(.footnote)
              .foregroundStyle(.secondary)
          } else {
            ForEach(installable) { entry in
              ModelCatalogRow(model: model, entry: entry)
            }
          }
        }
        if let job = model.modelInstallJob {
          ModelInstallStatusView(job: job, log: model.modelInstallLog)
        }
      }
      PreferencesSection("Dictation") {
        if let status = model.dictationStatus {
          SettingsInfoRow(title: "Backend", value: status.installed ? status.backendLabel : "Not installed")
          SettingsInfoRow(title: "Language", value: status.language)
        }
        Picker("Language", selection: Binding(
          get: { model.dictationLanguage },
          set: { nextValue in
            Task { await model.setDictationLanguage(nextValue) }
          }
        )) {
          ForEach(model.dictationLanguages) { language in
            Text(language.label).tag(language.value)
          }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: 240, alignment: .leading)
        Toggle("Keep dictation warm", isOn: Binding(
          get: { model.dictationPrewarmEnabled },
          set: { nextValue in
            Task { await model.setDictationPrewarm(nextValue) }
          }
        ))
        HStack {
          Picker("Hold-to-talk", selection: Binding(
            get: { model.dictationHoldShortcut },
            set: { nextValue in
              Task { await model.setDictationShortcuts(hold: nextValue, toggle: model.dictationToggleShortcut) }
            }
          )) {
            ForEach(model.dictationShortcutOptions, id: \.self) { option in
              Text(model.dictationShortcutLabel(option)).tag(option)
            }
          }
          .pickerStyle(.menu)
          .frame(maxWidth: 190, alignment: .leading)
          Picker("Toggle", selection: Binding(
            get: { model.dictationToggleShortcut },
            set: { nextValue in
              Task { await model.setDictationShortcuts(hold: model.dictationHoldShortcut, toggle: nextValue) }
            }
          )) {
            ForEach(model.dictationShortcutOptions, id: \.self) { option in
              Text(model.dictationShortcutLabel(option)).tag(option)
            }
          }
          .pickerStyle(.menu)
          .frame(maxWidth: 160, alignment: .leading)
        }
        if !model.dictationInstallMessage.isEmpty {
          Text(model.dictationInstallMessage)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        HStack {
          Button("Check") { Task { await model.loadDictationStatus() } }
          Button(model.isDictationInstalling ? "Installing..." : "Install") {
            Task { await model.installDictation() }
          }
          .disabled(model.isDictationInstalling)
          Button("Cancel") {
            Task { await model.cancelDictationInstall() }
          }
          .disabled(model.dictationInstallJobID.isEmpty)
        }
        .buttonStyle(.bordered)
      }
    }
  }
}

private struct ModelCatalogRow: View {
  @ObservedObject var model: ArtificerModel
  let entry: ModelCatalogEntry

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 6) {
          Text(entry.name)
            .font(.body)
            .textSelection(.enabled)
          if !entry.sizeLabel.isEmpty {
            Text(entry.sizeLabel)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        if !entry.description.isEmpty {
          Text(entry.description)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      Spacer(minLength: 12)
      Button(model.installLabel(for: entry.name)) {
        Task { await model.installModel(entry.name) }
      }
      .buttonStyle(.borderedProminent)
      .disabled(model.isInstallingModel(entry.name))
    }
  }
}

private struct ModelInstallStatusView: View {
  let job: ModelInstallJob
  let log: String

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        Text("\(job.model) \(job.statusLabel)")
          .font(.subheadline.weight(.semibold))
        if let progress = job.progressFraction {
          ProgressView(value: progress, total: 1)
            .frame(width: 120)
        }
      }
      if !log.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        ScrollView {
          Text(log)
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 120)
      }
    }
    .padding(.top, 4)
  }
}

private struct AutomationsPreferencesTab: View {
  @ObservedObject var model: ArtificerModel

  var body: some View {
    PreferencesPane {
      PreferencesSection("Automations") {
        Toggle("Launch background runtime at startup", isOn: Binding(
          get: { model.daemonStatus?.enabled ?? false },
          set: { nextValue in
            Task { await model.setAutomationDaemonEnabled(nextValue) }
          }
        ))
        Toggle("Show menu bar icon", isOn: Binding(
          get: { model.menuBarIconEnabled },
          set: { nextValue in
            Task { await model.setMenuBarIconEnabled(nextValue) }
          }
        ))
        if let daemon = model.daemonStatus {
          SettingsInfoRow(title: "Status", value: daemon.status)
          SettingsInfoRow(title: "Method", value: daemon.method)
          SettingsInfoRow(title: "Pending", value: "\(daemon.taskPending)")
        } else {
          Text("Automation status has not loaded yet.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        HStack {
          Button("Run Due Automations") { Task { await model.daemon("automation-daemon-tick") } }
            .disabled(!(model.daemonStatus?.enabled ?? false))
          Button((model.daemonStatus?.paused ?? false) ? "Resume Runtime" : "Pause Runtime") {
            Task { await model.toggleAutomationDaemonPaused() }
          }
          .disabled(!(model.daemonStatus?.enabled ?? false))
        }
        .buttonStyle(.bordered)
      }
      PreferencesSection("Programming Mode") {
        Toggle("Programmer does code reviews", isOn: $model.programmerReview)
        Picker("Max review rounds", selection: $model.programmerReviewRounds) {
          ForEach(1...4, id: \.self) { round in
            Text("\(round)").tag(round)
          }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: 180, alignment: .leading)
      }
    }
  }
}

private struct VoiceControlPreferencesTab: View {
  @ObservedObject var model: ArtificerModel

  var body: some View {
    PreferencesPane {
      PreferencesSection("Voice Control") {
        Toggle("Voice automations", isOn: Binding(
          get: { model.voiceAutomationsEnabled },
          set: { nextValue in
            Task { await model.setDesktopPref("voice_automations", enabled: nextValue) }
          }
        ))
        Text("Listens continuously for automation phrases. Audio is handled locally by Artificer's voice-recognition system.")
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        VStack(alignment: .leading, spacing: 8) {
          Toggle("Play sound when command is recognized", isOn: Binding(
            get: { model.voiceRecognitionSoundEnabled },
            set: { nextValue in
              Task { await model.setDesktopPref("voice_automation_sound", enabled: nextValue) }
            }
          ))
          Toggle("Use built-in Mac voice commands", isOn: Binding(
            get: { model.voiceBuiltinCommandsEnabled },
            set: { nextValue in
              Task { await model.setDesktopPref("voice_builtin_commands", enabled: nextValue) }
            }
          ))
          Text("Includes app switching, window controls, keyboard shortcuts, scrolling, numbered targets, pointer movement, and reading the current notification aloud.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
          VStack(alignment: .leading, spacing: 6) {
            Toggle("Allow dictation into the frontmost app", isOn: Binding(
              get: { model.voiceDictationCommandsEnabled },
              set: { nextValue in
                Task { await model.setDesktopPref("voice_dictation_commands", enabled: nextValue) }
              }
            ))
            Text("Say Start dictation to type recognized speech into the active app, and Stop dictation to return to commands.")
              .font(.caption)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
          .padding(.leading, 18)
          .disabled(!model.voiceBuiltinCommandsEnabled)
        }
        .padding(.leading, 18)
        .disabled(!model.voiceAutomationsEnabled)
        VStack(alignment: .leading, spacing: 6) {
          Text("Voice Commands")
            .font(.subheadline)
          Text("Separate phrases with commas. Matching ignores case and punctuation.")
            .font(.caption)
            .foregroundStyle(.secondary)
          VoiceLocalActionEditor(
            title: "Local action 1",
            name: $model.voiceLocalAction1Name,
            command: $model.voiceLocalAction1Command,
            phrases: $model.voiceLocalAction1Phrases
          )
          VoiceLocalActionEditor(
            title: "Local action 2",
            name: $model.voiceLocalAction2Name,
            command: $model.voiceLocalAction2Command,
            phrases: $model.voiceLocalAction2Phrases
          )
          Button("Save Local Actions") {
            Task { await model.saveVoiceCommandPhrases() }
          }
          .disabled(!model.canSaveVoiceCommandPhrases)
          VoiceCommandExampleRow(title: "Local action", example: "Set a name, shell command, and comma-separated phrases.")
          VoiceCommandExampleRow(title: "Switch apps", example: "switch to Safari, open Calendar, quit Notes")
          VoiceCommandExampleRow(title: "Read notification", example: "read it, read that aloud, what did that notification say")
          VoiceCommandExampleRow(title: "Use the screen", example: "show numbers, click 3, show grid, scroll down")
          VoiceCommandExampleRow(title: "Dictate", example: "start dictation, dictate hello comma world, stop dictation")
          VoiceCommandExampleRow(title: "Ask Artificer", example: "artificer summarize this thread, ask artificer check the build")
          VoiceCommandExampleRow(title: "Action prompt", example: "hey artificer turn this into a pull request")
        }
        .padding(.leading, 18)
        VStack(alignment: .leading, spacing: 8) {
          Toggle("Allow voice phrases to ask Artificer", isOn: Binding(
            get: { model.voiceLlmPromptsEnabled },
            set: { nextValue in
              Task { await model.setDesktopPref("voice_automation_llm_prompts", enabled: nextValue) }
            }
          ))
          Toggle("Allow voice-triggered Artificer actions", isOn: Binding(
            get: { model.voiceLlmActionsEnabled },
            set: { nextValue in
              Task { await model.setDesktopPref("voice_automation_llm_actions", enabled: nextValue) }
            }
          ))
          .disabled(!model.voiceLlmPromptsEnabled)
        }
        .padding(.leading, 18)
        .disabled(!model.voiceAutomationsEnabled)
        if let voice = model.voiceAutomationStatus {
          SettingsInfoRow(title: "Voice", value: voice.status)
          if !voice.message.isEmpty {
            Text(voice.message)
              .font(.caption)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
    }
  }
}

private struct SelfImprovePreferencesTab: View {
  @ObservedObject var model: ArtificerModel

  var body: some View {
    PreferencesPane {
      PreferencesSection("Self-improve Match") {
        Picker("Primary model", selection: $model.selfImproveSelectedModel) {
          if model.installedModels.isEmpty {
            Text("No installed models").tag("")
          } else {
            ForEach(model.installedModels, id: \.self) { modelName in
              Text(modelName).tag(modelName)
            }
          }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: 280, alignment: .leading)
        Toggle("Run challenger lane", isOn: Binding(
          get: { model.selfImproveCompetitionEnabled },
          set: { nextValue in
            Task { await model.saveSelfImproveOptions(competitionEnabled: nextValue) }
          }
        ))
        Picker("Challenger", selection: Binding(
          get: { model.selfImproveChallengerModel },
          set: { nextValue in
            Task { await model.saveSelfImproveOptions(challengerModel: nextValue) }
          }
        )) {
          Text("Auto challenger").tag("")
          ForEach(model.installedModels, id: \.self) { modelName in
            Text(modelName).tag(modelName)
          }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: 280, alignment: .leading)
        .disabled(!model.selfImproveCompetitionEnabled)
        TextEditor(text: $model.selfImproveObjective)
          .font(.body)
          .frame(minHeight: 72, maxHeight: 110)
          .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
        HStack {
          Button("Save Options") { Task { await model.saveSelfImproveOptions() } }
          Button(model.isSelfImproveRunning ? "Running..." : (model.selfImproveCompetitionEnabled ? "Run Match" : "Run Self-improve")) {
            Task { await model.runSelfImprove() }
          }
          .buttonStyle(.borderedProminent)
          .disabled(model.isSelfImproveRunning || model.selfImproveSelectedModel.isEmpty)
          Button("Refresh") { Task { await model.loadSelfImproveSettings() } }
        }
        .buttonStyle(.bordered)
        if !model.selfImproveStatus.isEmpty {
          Text(model.selfImproveStatus)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        if !model.selfImproveSummary.isEmpty {
          Text(model.selfImproveSummary)
            .font(.footnote)
            .fixedSize(horizontal: false, vertical: true)
        }
        if model.selfImprovePluginCount > 0 {
          Text("Active plugins: \(model.selfImprovePluginCount)")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }
      PreferencesSection("Evidence Sources") {
        Toggle("Codex Desktop work checks", isOn: Binding(
          get: { model.codexWorkCheckEnabled },
          set: { nextValue in
            Task { await model.saveSelfImproveOptions(codexWorkCheckEnabled: nextValue) }
          }
        ))
        Toggle("Papers", isOn: Binding(
          get: { model.selfImproveSourcePapers },
          set: { nextValue in Task { await model.saveSelfImproveOptions(sourcePapers: nextValue) } }
        ))
        Toggle("Web signals", isOn: Binding(
          get: { model.selfImproveSourceWeb },
          set: { nextValue in Task { await model.saveSelfImproveOptions(sourceWeb: nextValue) } }
        ))
        Toggle("Runtime telemetry", isOn: Binding(
          get: { model.selfImproveSourceRuntime },
          set: { nextValue in Task { await model.saveSelfImproveOptions(sourceRuntime: nextValue) } }
        ))
        Toggle("Repo signals", isOn: Binding(
          get: { model.selfImproveSourceRepo },
          set: { nextValue in Task { await model.saveSelfImproveOptions(sourceRepo: nextValue) } }
        ))
        Toggle("Platform checks", isOn: Binding(
          get: { model.selfImproveSourcePlatform },
          set: { nextValue in Task { await model.saveSelfImproveOptions(sourcePlatform: nextValue) } }
        ))
      }
    }
  }
}

private struct RuntimePreferencesTab: View {
  @ObservedObject var model: ArtificerModel

  var body: some View {
    PreferencesPane {
      PreferencesSection("Artificer Core") {
        TextField("Artificer core root", text: $model.coreRootDraft)
          .textFieldStyle(.roundedBorder)
        HStack {
          Button("Choose...") {
            model.chooseCoreRoot()
          }
          Button("Save") {
            Task { await model.saveCoreRoot() }
          }
          Button("Probe") {
            Task { await model.refreshDoctor() }
          }
        }
        .buttonStyle(.bordered)
        Text(model.resolvedCoreRoot.isEmpty ? "No core root resolved." : "Resolved: \(model.resolvedCoreRoot)")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
          .textSelection(.enabled)
      }
      PreferencesSection("Storage") {
        if let daemon = model.daemonStatus {
          SettingsInfoRow(title: "State root", value: daemon.stateRoot)
          SettingsInfoRow(title: "Log", value: daemon.logPath)
        }
      }
    }
  }
}

private struct VoiceLocalActionEditor: View {
  let title: String
  @Binding var name: String
  @Binding var command: String
  @Binding var phrases: String

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
      HStack(spacing: 8) {
        TextField("Name", text: $name)
          .textFieldStyle(.roundedBorder)
          .frame(maxWidth: 180)
        TextField("Command", text: $command)
          .textFieldStyle(.roundedBorder)
          .frame(maxWidth: 280)
      }
      TextField("Phrases", text: $phrases)
        .textFieldStyle(.roundedBorder)
        .frame(maxWidth: 468)
    }
  }
}

private struct VoiceCommandExampleRow: View {
  let title: String
  let example: String

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Text(title)
        .foregroundStyle(.secondary)
        .frame(width: 112, alignment: .leading)
      Text(example)
        .textSelection(.enabled)
        .lineLimit(2)
    }
    .font(.caption)
  }
}

private struct MobilePreferencesTab: View {
  @ObservedObject var model: ArtificerModel

  var body: some View {
    PreferencesPane {
      PreferencesSection("Bridge") {
        Toggle("Enable Mobile bridge", isOn: Binding(
          get: { model.mobileBridgeEnabled },
          set: { nextValue in
            Task { await model.setDesktopPref("mobile_bridge", enabled: nextValue) }
          }
        ))
        Toggle("Advertise on local network", isOn: Binding(
          get: { model.mobileLanEnabled },
          set: { nextValue in
            Task { await model.setDesktopPref("mobile_lan", enabled: nextValue) }
          }
        ))
        Toggle("Tor hidden service", isOn: Binding(
          get: { model.mobileTorEnabled },
          set: { nextValue in
            Task { await model.setDesktopPref("mobile_tor", enabled: nextValue) }
          }
        ))
        HStack {
          Button("Install Tor") { Task { await model.installMobileTor() } }
          Button("Restart Bridge") { Task { await model.restartMobileBridge() } }
            .disabled(!model.mobileBridgeEnabled)
          Button("Refresh") { Task { await model.loadMobileStatus() } }
        }
        .buttonStyle(.bordered)
        if let mobile = model.mobileStatus {
          SettingsInfoRow(title: "Local", value: mobile.localURL)
          if !mobile.lanURL.isEmpty {
            SettingsInfoRow(title: "IP", value: mobile.lanURL)
          }
          SettingsInfoRow(title: "Tor", value: mobile.torAddress.isEmpty ? (mobile.torEnabled ? "Starting..." : "Off") : "http://\(mobile.torAddress)")
          SettingsInfoRow(title: "Pairing token", value: mobile.pairingToken)
          SettingsInfoRow(title: "State", value: mobile.running ? "Running" : "Stopped")
        } else {
          Text("Mobile bridge status has not loaded yet.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }
      PreferencesSection("Permissions") {
        Toggle("Allow command execution from mobile", isOn: Binding(
          get: { model.mobileAllowExecute },
          set: { nextValue in
            Task { await model.setDesktopPref("mobile_allow_execute", enabled: nextValue) }
          }
        ))
        Toggle("Allow self-actuation from mobile", isOn: Binding(
          get: { model.mobileAllowSelfActuation },
          set: { nextValue in
            Task { await model.setDesktopPref("mobile_allow_self_actuation", enabled: nextValue) }
          }
        ))
        .disabled(!model.mobileAllowExecute)
      }
    }
    .task {
      await model.loadMobileStatus()
    }
  }
}

private struct GitPreferencesTab: View {
  @ObservedObject var model: ArtificerModel

  var body: some View {
    PreferencesPane {
      PreferencesSection("Workflow Policy") {
        Picker("Dirty repo", selection: Binding(
          get: { model.gitWorkflowPolicy },
          set: { nextValue in
            Task { await model.setGitRuntimeSettings(workflowPolicy: nextValue, ambiguityPolicy: model.gitAmbiguityPolicy) }
          }
        )) {
          Text("Managed").tag("managed")
          Text("Frequent commits").tag("frequent-commits")
          Text("Commit once").tag("commit-once")
          Text("Manual").tag("manual")
        }
        .pickerStyle(.menu)
        .frame(maxWidth: 240, alignment: .leading)
        Picker("Ambiguity", selection: Binding(
          get: { model.gitAmbiguityPolicy },
          set: { nextValue in
            Task { await model.setGitRuntimeSettings(workflowPolicy: model.gitWorkflowPolicy, ambiguityPolicy: nextValue) }
          }
        )) {
          Text("Ask when ambiguous").tag("ask")
          Text("Preserve unrelated changes").tag("preserve")
          Text("Snapshot all").tag("snapshot-all")
        }
        .pickerStyle(.menu)
        .frame(maxWidth: 240, alignment: .leading)
      }
    }
  }
}

private struct PreferencesPane<Content: View>: View {
  let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        content
      }
      .frame(maxWidth: 640, alignment: .leading)
      .padding(.top, 14)
      .padding(.bottom, 18)
      .padding(.horizontal, 18)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

private struct PreferencesSection<Content: View>: View {
  let title: String
  let content: Content

  init(_ title: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title)
        .font(.headline)
      content
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct SettingsInfoRow: View {
  let title: String
  let value: String

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      Text(title)
        .foregroundStyle(.secondary)
        .frame(width: 76, alignment: .leading)
      Text(value)
        .lineLimit(1)
        .truncationMode(.middle)
        .textSelection(.enabled)
    }
    .font(.footnote)
  }
}

@MainActor
private final class ArtificerModel: ObservableObject {
  @Published var projects: [Project] = []
  @Published var sessions: [SessionSummary] = []
  @Published var selectedSession: SessionDetail?
  @Published var automations: [AutomationItem] = []
  @Published var daemonStatus: DaemonStatus?
  @Published var health: RuntimeHealth?
  @Published var showingAutomations = false
  @Published var preferencesTab = "general"
  @Published var selectedProjectID: String?
  @Published var selectedSessionID: String?
  @Published var sessionsByProject: [String: [SessionSummary]] = [:]
  @Published var expandedProjectIDs: Set<String> = []
  @Published var pendingArchiveSessionKey = ""
  @Published var creatingSessionProjectIDs: Set<String> = []
  @Published var loadingSessionKey = ""
  @Published var prompt = ""
  @Published var promptDraftsBySessionKey: [String: String] = [:]
  @Published var statusMessage = "Ready"
  @Published var lastError = ""
  @Published var isBusy = false
  @Published var coreRootDraft = ""
  @Published var resolvedCoreRoot = ""
  @Published var coreReady = false
  @Published var isComposerDropTargeted = false
  @Published var pendingAttachments: [PendingAttachment] = []
  @Published var dictationStatus: DictationStatus?
  @Published var isDictating = false
  @Published var dictationSessionID = ""
  @Published var dictationLevels: [Double] = []
  @Published var dictationStartedAt: Date?
  @Published var dictationInstallJobID = ""
  @Published var dictationInstallMessage = ""
  @Published var isDictationInstalling = false
  @Published var codexWorkCheckEnabled = false
  @Published var selfImproveObjective = ""
  @Published var selfImproveSelectedModel = ""
  @Published var selfImproveChallengerModel = ""
  @Published var selfImproveCompetitionEnabled = true
  @Published var selfImproveSourcePapers = true
  @Published var selfImproveSourceWeb = true
  @Published var selfImproveSourceRuntime = true
  @Published var selfImproveSourceRepo = true
  @Published var selfImproveSourcePlatform = true
  @Published var selfImproveStatus = ""
  @Published var selfImproveSummary = ""
  @Published var selfImprovePluginCount = 0
  @Published var isSelfImproveRunning = false
  @Published var menuBarIconEnabled = false
  @Published var voiceAutomationsEnabled = false
  @Published var voiceRecognitionSoundEnabled = false
  @Published var voiceBuiltinCommandsEnabled = true
  @Published var voiceDictationCommandsEnabled = true
  @Published var voiceLlmPromptsEnabled = false
  @Published var voiceLlmActionsEnabled = false
  @Published var voiceLocalAction1Name = ""
  @Published var voiceLocalAction1Command = ""
  @Published var voiceLocalAction1Phrases = ""
  @Published var voiceLocalAction2Name = ""
  @Published var voiceLocalAction2Command = ""
  @Published var voiceLocalAction2Phrases = ""
  @Published var voiceAutomationStatus: VoiceAutomationStatus?
  @Published var mobileBridgeEnabled = false
  @Published var mobileTorEnabled = false
  @Published var mobileLanEnabled = false
  @Published var mobileAllowExecute = false
  @Published var mobileAllowSelfActuation = false
  @Published var mobileStatus: MobileBridgeStatus?
  @Published var installedModels: [String] = []
  @Published var modelCatalog: [ModelCatalogEntry] = []
  @Published var modelInstallJob: ModelInstallJob?
  @Published var modelInstallLog = ""
  @Published var modelInstallMessage = ""
  @Published var llmUseGpu = true
  @Published var selectedDefaultModel = ""
  @Published var smartConversationTitles = true
  @Published var dictationPrewarmEnabled = true
  @Published var dictationLanguage = "auto"
  @Published var dictationLanguages: [DictationLanguageOption] = [DictationLanguageOption(value: "auto", label: "Auto")]
  @Published var dictationHoldShortcut = "none"
  @Published var dictationToggleShortcut = "none"
  @Published var gitWorkflowPolicy = "managed"
  @Published var gitAmbiguityPolicy = "preserve"
  @Published var selectedThemeID = "system"
  @Published var showingGitDiff = false
  @Published var showingCommitDialog = false
  @Published var showingBranchDialog = false
  @Published var showingQueueTray = false
  @Published var showingTerminalPanel = false
  @Published var showingModelsPanel = false
  @Published var gitStatus = GitStatus()
  @Published var gitBranches: [GitBranch] = []
  @Published var gitDiff = GitDiffResponse()
  @Published var commitMessage = ""
  @Published var commitIncludeUnstaged = true
  @Published var commitPushAfter = false
  @Published var branchNameDraft = ""
  @Published var queueItems: [QueueItem] = []
  @Published var terminalSessionID = ""
  @Published var terminalOutput = ""
  @Published var terminalInput = ""
  @Published var terminalOffset = 0
  @Published var terminalRunning = false
  @Published var networkAccessEnabled = false
  @Published var webAccessEnabled = false
  @Published var automationDraftName = ""
  @Published var automationDraftPrompt = ""
  @Published var automationDraftScheduleKind = "interval"
  @Published var automationDraftScheduleValue = "1h"
  @Published var automationDraftProjectID = ""
  @Published var automationDraftSessionID = ""
  @Published var automationDraftEnabled = true
  @Published var automationDraftAllowSelfReschedule = false
  @Published var automationDraftUsesNextRun = false
  @Published var automationDraftNextRunDate = Date().addingTimeInterval(3600)
  @Published var automationDraftRunMode = "assistant"
  @Published var automationDraftComputeBudget = "auto"
  @Published var automationDraftCommandExecMode = "ask-some"
  @Published var automationDraftPermissionMode = "default"
  @Published var automationDraftProgrammerReview = true
  @Published var automationDraftProgrammerReviewRounds = 2

  @Published var runMode = "auto"
  @Published var reasoningEffort = "medium"
  @Published var computeBudget = "auto"
  @Published var commandExecMode = "ask-some"
  @Published var permissionMode = "default"
  @Published var programmerReview = true
  @Published var programmerReviewRounds = 2
  @Published var selfActuation = false
  @Published var reflexiveKnowledge = false
  private var voiceAutomationLoopTask: Task<Void, Never>?
  private var voiceAutomationRecorder: AVAudioRecorder?

  let runModes = ["instant", "auto", "programming", "pentest", "security-audit", "chat", "teacher", "report", "text-perfecter", "gui-testing", "assistant"]
  let reasoningEfforts = ["low", "medium", "high", "extra-high"]
  let computeBudgets = ["auto", "quick", "standard", "long", "until-complete"]
  let commandExecModes = ["ask-some", "all", "none"]
  let permissionModes = ["default", "ask", "never"]
  let dictationShortcutOptions = ["none", "space", "right-option", "left-option", "right-command", "left-command", "mouse-back", "mouse-forward", "mouse-wheel-click"]

  var installableCatalogEntries: [ModelCatalogEntry] {
    modelCatalog.filter { entry in
      !installedModels.contains(entry.name)
    }
  }

  var selectedProject: Project? {
    projects.first { $0.id == selectedProjectID }
  }

  var selectedTheme: AppTheme {
    AppTheme.resolved(selectedThemeID)
  }

  var themeAccentColor: Color {
    selectedTheme.accent
  }

  var themeContrastColor: Color {
    selectedTheme.contrast
  }

  var gitBranchTitle: String {
    if !gitStatus.isRepo { return "No repo" }
    if gitStatus.branch.isEmpty { return "Git branch" }
    var parts = [gitStatus.branch]
    if gitStatus.ahead > 0 { parts.append("ahead \(gitStatus.ahead)") }
    if gitStatus.behind > 0 { parts.append("behind \(gitStatus.behind)") }
    return parts.joined(separator: " · ")
  }

  var gitChangesTitle: String {
    guard gitStatus.isRepo else { return "No Git repository" }
    if gitStatus.changes == 0 { return "No uncommitted changes" }
    return "\(gitStatus.changes) changed files, +\(gitStatus.added) -\(gitStatus.deleted)"
  }

  var activeComposerModel: String {
    if let sessionModel = selectedSession?.model.trimmingCharacters(in: .whitespacesAndNewlines), !sessionModel.isEmpty {
      return sessionModel
    }
    if !selectedDefaultModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return selectedDefaultModel
    }
    if let defaultModel = health?.defaultModel.trimmingCharacters(in: .whitespacesAndNewlines), !defaultModel.isEmpty {
      return defaultModel
    }
    return installedModels.first ?? ""
  }

  var activeContextWindowLabel: String {
    let active = activeComposerModel
    if let entry = catalogEntry(named: active), !entry.contextK.isEmpty {
      return "\(entry.contextK)k"
    }
    return "Context"
  }

  var automationDraftSessions: [SessionSummary] {
    let projectID = automationDraftProjectID.isEmpty ? (selectedProjectID ?? "") : automationDraftProjectID
    return sessionsByProject[projectID] ?? (projectID == selectedProjectID ? sessions : [])
  }

  var canCreateAutomation: Bool {
    let projectID = automationDraftProjectID.isEmpty ? (selectedProjectID ?? "") : automationDraftProjectID
    let sessionID = automationDraftSessionID.isEmpty ? (selectedSessionID ?? "") : automationDraftSessionID
    return !projectID.isEmpty
      && !sessionID.isEmpty
      && !automationDraftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !automationDraftPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !automationDraftScheduleValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var canSaveVoiceCommandPhrases: Bool {
    voiceLocalActionIsComplete(name: voiceLocalAction1Name, command: voiceLocalAction1Command, phrases: voiceLocalAction1Phrases) &&
      voiceLocalActionIsComplete(name: voiceLocalAction2Name, command: voiceLocalAction2Command, phrases: voiceLocalAction2Phrases)
  }

  var hasVoiceLocalAction1: Bool {
    voiceLocalActionIsConfigured(name: voiceLocalAction1Name, command: voiceLocalAction1Command, phrases: voiceLocalAction1Phrases)
  }

  var hasVoiceLocalAction2: Bool {
    voiceLocalActionIsConfigured(name: voiceLocalAction2Name, command: voiceLocalAction2Command, phrases: voiceLocalAction2Phrases)
  }

  private func voiceLocalActionIsConfigured(name: String, command: String, phrases: String) -> Bool {
    !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
      !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
      !phrases.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private func voiceLocalActionIsComplete(name: String, command: String, phrases: String) -> Bool {
    if !voiceLocalActionIsConfigured(name: name, command: command, phrases: phrases) {
      return true
    }
    return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
      !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
      !phrases.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var isSelectedSessionLoading: Bool {
    guard let selectedProjectID, let selectedSessionID else { return false }
    return loadingSessionKey == archiveKey(projectID: selectedProjectID, sessionID: selectedSessionID)
  }

  func isProjectExpanded(_ projectID: String) -> Bool {
    expandedProjectIDs.contains(projectID)
  }

  func projectPathDisplayName(_ project: Project) -> String {
    let basename = URL(fileURLWithPath: project.path).lastPathComponent
    if !basename.isEmpty {
      return basename
    }
    return project.name
  }

  func copySelectedProjectPath() {
    guard let path = selectedProject?.path, !path.isEmpty else { return }
    copyToPasteboard(path)
    statusMessage = "Project path copied."
  }

  func openSelectedProjectFolder() {
    guard let path = selectedProject?.path, !path.isEmpty else { return }
    NSWorkspace.shared.open(URL(fileURLWithPath: path, isDirectory: true))
    statusMessage = "Opening project folder."
  }

  func openProjectTarget(_ target: String) async {
    guard let projectID = selectedProjectID else { return }
    let result = await runBackend("open-project-target", projectID, target)
    if let response = decode(GenericSuccessResponse.self, from: result), response.success {
      statusMessage = "Opening \(target)."
    }
  }

  func loadGitStatusAndBranches() async {
    guard let projectID = selectedProjectID else {
      gitStatus = GitStatus()
      gitBranches = []
      return
    }
    let statusResult = await runBackend("git-status", [projectID], trackBusy: false)
    if let response = decode(GitStatusResponse.self, from: statusResult) {
      gitStatus = response.status
    }
    let branchesResult = await runBackend("git-branches", [projectID], trackBusy: false)
    if let response = decode(GitBranchesResponse.self, from: branchesResult) {
      gitBranches = response.branches
    }
  }

  func loadGitDiff() async {
    guard let projectID = selectedProjectID else {
      gitDiff = GitDiffResponse()
      return
    }
    let result = await runBackend("git-diff", [projectID], trackBusy: false)
    if let response = decode(GitDiffResponse.self, from: result) {
      gitDiff = response
    }
    await loadGitStatusAndBranches()
  }

  func checkoutBranch(_ branch: String) async {
    guard let projectID = selectedProjectID else { return }
    let result = await runBackend("git-checkout-branch", projectID, branch, "0")
    if let response = decode(GitBranchMutationResponse.self, from: result), response.success {
      statusMessage = response.output.isEmpty ? "Checked out \(response.branch)." : response.output
      await loadGitStatusAndBranches()
    }
  }

  func createBranch() async {
    let branch = branchNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let projectID = selectedProjectID, !branch.isEmpty else { return }
    let result = await runBackend("git-checkout-branch", projectID, branch, "1")
    if let response = decode(GitBranchMutationResponse.self, from: result), response.success {
      showingBranchDialog = false
      branchNameDraft = ""
      statusMessage = response.output.isEmpty ? "Created \(response.branch)." : response.output
      await loadGitStatusAndBranches()
    }
  }

  func prepareCommit(pushAfter: Bool) {
    commitPushAfter = pushAfter
    commitIncludeUnstaged = true
    commitMessage = ""
    showingCommitDialog = true
  }

  func commitGitChanges() async {
    guard let projectID = selectedProjectID else { return }
    let result = await runBackend(
      "git-commit",
      projectID,
      commitIncludeUnstaged ? "1" : "0",
      commitMessage,
      commitPushAfter ? "1" : "0"
    )
    if let response = decode(GitOutputResponse.self, from: result), response.success {
      showingCommitDialog = false
      commitMessage = ""
      statusMessage = response.output.isEmpty ? "Git commit completed." : response.output
      await loadGitDiff()
    }
  }

  func pushGitChanges() async {
    guard let projectID = selectedProjectID else { return }
    let result = await runBackend("git-push", projectID)
    if let response = decode(GitOutputResponse.self, from: result), response.success {
      statusMessage = response.output.isEmpty ? "Git push completed." : response.output
      await loadGitStatusAndBranches()
    }
  }

  func loadQueueItems() async {
    guard let projectID = selectedProjectID, let sessionID = selectedSessionID else {
      queueItems = []
      return
    }
    let result = await runBackend("queue-list", [projectID, sessionID, "40"], trackBusy: false)
    if let response = decode(QueueItemsResponse.self, from: result) {
      queueItems = response.items
    }
  }

  func updateQueueItem(_ itemID: String, prompt: String) async {
    guard let projectID = selectedProjectID, let sessionID = selectedSessionID else { return }
    let result = await runBackend("queue-update", projectID, sessionID, itemID, prompt)
    if let response = decode(GenericSuccessResponse.self, from: result), response.success {
      statusMessage = "Queued item updated."
      await loadQueueItems()
      await loadSelectedSession(status: nil, trackBusy: false)
    }
  }

  func cancelQueueItem(_ itemID: String) async {
    guard let projectID = selectedProjectID, let sessionID = selectedSessionID else { return }
    let result = await runBackend("queue-cancel", projectID, sessionID, itemID)
    if let response = decode(QueueCancelResponse.self, from: result), response.success {
      statusMessage = response.cancelled ? "Queued item cancelled." : "Queued item was already gone."
      await loadQueueItems()
      await loadSelectedSession(status: nil, trackBusy: false)
    }
  }

  func moveQueueItem(_ itemID: String, direction: Int) async {
    guard let projectID = selectedProjectID, let sessionID = selectedSessionID else { return }
    guard let currentIndex = queueItems.firstIndex(where: { $0.id == itemID }) else { return }
    let targetIndex = max(0, min(queueItems.count - 1, currentIndex + direction))
    guard currentIndex != targetIndex else { return }

    var reorderedItems = queueItems
    let item = reorderedItems.remove(at: currentIndex)
    reorderedItems.insert(item, at: targetIndex)
    queueItems = reorderedItems

    let itemIDs = reorderedItems.map(\.id).joined(separator: ",")
    let result = await runBackend("queue-reorder", projectID, sessionID, itemIDs)
    if let response = decode(GenericSuccessResponse.self, from: result), response.success {
      statusMessage = "Queue reordered."
      await loadQueueItems()
      await loadSelectedSession(status: nil, trackBusy: false)
    } else {
      await loadQueueItems()
    }
  }

  func stopQueueRun() async {
    guard let projectID = selectedProjectID, let sessionID = selectedSessionID else { return }
    let result = await runBackend("queue-stop", projectID, sessionID)
    if let response = decode(QueueStopResponse.self, from: result), response.success {
      statusMessage = response.stopped ? "Run stopped." : "No active run to stop."
      await loadQueueItems()
      await loadSelectedSession(status: nil, trackBusy: false)
    }
  }

  func answerApproval(decision: String, scope: String, matchMode: String = "exact", pattern: String = "", command: String) async {
    guard let projectID = selectedProjectID, let sessionID = selectedSessionID else { return }
    let normalizedMatchMode = matchMode == "regex" ? "regex" : "exact"
    let trimmedPattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
    let rulePattern = normalizedMatchMode == "regex" && !trimmedPattern.isEmpty ? trimmedPattern : command
    let result = await runBackend("approval-answer", projectID, sessionID, decision, scope, normalizedMatchMode, rulePattern, command)
    if let response = decode(GenericSuccessResponse.self, from: result), response.success {
      statusMessage = decision == "allow" ? "Command approved." : "Command denied."
      await loadSelectedSession(status: nil, trackBusy: false)
      await loadQueueItems()
    }
  }

  func answerDecision(_ answer: String) async {
    guard let projectID = selectedProjectID, let sessionID = selectedSessionID else { return }
    let result = await runBackend("decision-answer", projectID, sessionID, answer)
    if let response = decode(GenericSuccessResponse.self, from: result), response.success {
      statusMessage = "Decision queued."
      await loadSelectedSession(status: nil, trackBusy: false)
      await loadQueueItems()
    }
  }

  func startTerminalSession() async {
    guard let projectID = selectedProjectID else { return }
    let result = await runBackend("terminal-session-start", projectID)
    if let response = decode(TerminalSessionResponse.self, from: result), response.success {
      terminalSessionID = response.sessionID
      terminalRunning = response.running
      terminalOffset = response.offset
      if !response.delta.isEmpty {
        terminalOutput += response.delta
      }
      statusMessage = "Terminal session ready."
    }
  }

  func pollTerminalSession() async {
    guard let projectID = selectedProjectID, !terminalSessionID.isEmpty else { return }
    let result = await runBackend("terminal-session-poll", [projectID, terminalSessionID, "\(terminalOffset)"], trackBusy: false)
    if let response = decode(TerminalSessionResponse.self, from: result), response.success {
      if response.sessionChanged {
        terminalSessionID = ""
        terminalRunning = false
        terminalOffset = 0
        return
      }
      terminalRunning = response.running
      terminalOffset = response.offset
      if !response.delta.isEmpty {
        terminalOutput += response.delta
      }
    }
  }

  func sendTerminalInput() async {
    guard let projectID = selectedProjectID, !terminalSessionID.isEmpty else { return }
    let command = terminalInput.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !command.isEmpty else { return }
    let result = await runBackend("terminal-session-input", projectID, terminalSessionID, "\(command)\n")
    if let response = decode(GenericSuccessResponse.self, from: result), response.success {
      terminalInput = ""
      statusMessage = "Terminal input sent."
      await pollTerminalSession()
    }
  }

  func stopTerminalSession() async {
    guard let projectID = selectedProjectID, !terminalSessionID.isEmpty else { return }
    let result = await runBackend("terminal-session-stop", projectID, terminalSessionID)
    if let response = decode(GenericSuccessResponse.self, from: result), response.success {
      terminalSessionID = ""
      terminalRunning = false
      terminalInput = ""
      statusMessage = "Terminal stopped."
    }
  }

  func setTheme(_ themeID: String) async {
    selectedThemeID = AppTheme.resolved(themeID).id
    let result = await runBackend("desktop-value-set", "theme_id", selectedThemeID)
    if decode(DesktopPrefsResponse.self, from: result) != nil {
      statusMessage = "Theme updated."
    }
  }

  func archiveKey(projectID: String, sessionID: String) -> String {
    "\(projectID):\(sessionID)"
  }

  private var activePromptDraftKey: String? {
    guard let selectedProjectID, let selectedSessionID else { return nil }
    return archiveKey(projectID: selectedProjectID, sessionID: selectedSessionID)
  }

  func updateActivePromptDraft(_ text: String) {
    guard let key = activePromptDraftKey else { return }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      promptDraftsBySessionKey.removeValue(forKey: key)
    } else {
      promptDraftsBySessionKey[key] = text
    }
  }

  func preserveCurrentPromptDraft() {
    updateActivePromptDraft(prompt)
  }

  func restorePromptDraft(for session: SessionDetail) {
    let key = archiveKey(projectID: session.workspaceID, sessionID: session.id)
    if let localDraft = promptDraftsBySessionKey[key] {
      prompt = localDraft
    } else {
      prompt = session.draft
      updateActivePromptDraft(session.draft)
    }
  }

  func clearPromptDraft(projectID: String, sessionID: String) {
    promptDraftsBySessionKey.removeValue(forKey: archiveKey(projectID: projectID, sessionID: sessionID))
  }

  func dictationShortcutLabel(_ value: String) -> String {
    switch value {
    case "space": return "Space"
    case "right-option": return "Right Option"
    case "left-option": return "Left Option"
    case "right-command": return "Right Command"
    case "left-command": return "Left Command"
    case "mouse-back": return "Mouse Back"
    case "mouse-forward": return "Mouse Forward"
    case "mouse-wheel-click": return "Wheel Click"
    default: return "None"
    }
  }

  var canSendPrompt: Bool {
    selectedSessionID != nil && !isBusy && !isDictating && (!prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingAttachments.isEmpty)
  }

  var dictationElapsedText: String {
    guard let dictationStartedAt else { return "0:00" }
    let seconds = max(0, Int(Date().timeIntervalSince(dictationStartedAt)))
    return "\(seconds / 60):" + String(format: "%02d", seconds % 60)
  }

  func bootstrap() async {
    syncVoiceAutomationLoop()
    await refreshDoctor()
    await refreshAll()
    syncVoiceAutomationLoop()
  }

  func refreshAll() async {
    await loadHealth()
    await loadModelData()
    await loadLlmRuntimeSettings()
    await loadProjects()
    await loadDaemonStatus()
    await loadAutomations()
    await loadDesktopPrefs()
    await loadVoiceAutomationStatus()
    await loadMobileStatus()
    await loadDictationStatus()
    await loadDictationPreferences()
    await loadSelfImproveSettings()
    await loadGitRuntimeSettings()
    await loadGitStatusAndBranches()
  }

  func loadPreferences() async {
    await loadHealth()
    await loadModelData()
    await loadLlmRuntimeSettings()
    await loadDaemonStatus()
    await loadDesktopPrefs()
    await loadVoiceAutomationStatus()
    await loadMobileStatus()
    await loadDictationStatus()
    await loadDictationPreferences()
    await loadSelfImproveSettings()
    await loadGitRuntimeSettings()
    await loadGitStatusAndBranches()
  }

  func refreshDoctor() async {
    let result = await runBackend("doctor")
    guard let doctor = decode(DoctorResponse.self, from: result) else { return }
    coreReady = doctor.coreReady
    resolvedCoreRoot = doctor.coreRoot
    if coreRootDraft.isEmpty {
      coreRootDraft = doctor.coreRoot
    }
    statusMessage = doctor.coreReady ? "Core runtime resolved." : "Core runtime missing."
  }

  func loadHealth() async {
    let result = await runBackend("health", trackBusy: false)
    if let response = decode(HealthResponse.self, from: result) {
      health = response.runtime
      statusMessage = "Runtime health loaded."
    }
  }

  func loadModels() async {
    let result = await runBackend("models", trackBusy: false)
    if let response = decode(ModelsResponse.self, from: result) {
      installedModels = response.models
    }
  }

  func loadModelCatalog() async {
    let result = await runBackend("model-catalog", trackBusy: false)
    if let response = decode(ModelCatalogResponse.self, from: result) {
      modelCatalog = response.available
      if let running = response.installs.first(where: { $0.status == "running" }) {
        modelInstallJob = running
        modelInstallMessage = running.statusLabel
      }
    }
  }

  func loadModelData() async {
    await loadModels()
    await loadModelCatalog()
  }

  func catalogEntry(named modelName: String) -> ModelCatalogEntry? {
    modelCatalog.first { $0.name == modelName }
  }

  func isInstallingModel(_ modelName: String) -> Bool {
    modelInstallJob?.model == modelName && modelInstallJob?.status == "running"
  }

  func installLabel(for modelName: String) -> String {
    guard let job = modelInstallJob, job.model == modelName else { return "Install" }
    return job.status == "running" ? job.statusLabel : "Retry"
  }

  func installModel(_ modelName: String) async {
    modelInstallMessage = "Starting install for \(modelName)..."
    let result = await runBackend("model-install-start", modelName)
    guard let response = decode(ModelInstallStartResponse.self, from: result), response.success else {
      modelInstallMessage = "Model install failed to start."
      return
    }
    modelInstallJob = response.job
    modelInstallLog = ""
    modelInstallMessage = response.job.statusLabel
    await pollModelInstall(jobID: response.job.id)
  }

  func pollModelInstall(jobID: String) async {
    guard !jobID.isEmpty else { return }
    for _ in 0..<240 {
      let result = await runBackend("model-install-status", jobID, trackBusy: false)
      guard let response = decode(ModelInstallStatusResponse.self, from: result), response.success else {
        modelInstallMessage = "Model install status is unavailable."
        return
      }
      modelInstallJob = response.job
      modelInstallLog = response.job.log
      modelInstallMessage = response.job.statusLabel
      if response.job.status == "done" || response.job.status == "failed" {
        await loadModelData()
        await loadHealth()
        return
      }
      try? await Task.sleep(nanoseconds: 1_200_000_000)
    }
  }

  func uninstallModel(_ modelName: String) async {
    modelInstallMessage = "Uninstalling \(modelName)..."
    let result = await runBackend("model-uninstall", modelName)
    if decode(GenericSuccessResponse.self, from: result) != nil {
      if selectedDefaultModel == modelName {
        selectedDefaultModel = ""
      }
      await loadModelData()
      await loadHealth()
      modelInstallMessage = "Uninstalled \(modelName)."
    } else {
      modelInstallMessage = "Model uninstall failed."
    }
  }

  func loadLlmRuntimeSettings() async {
    let result = await runBackend("llm-runtime-settings-get", trackBusy: false)
    if let response = decode(LlmRuntimeSettingsResponse.self, from: result) {
      llmUseGpu = response.useGpu
      selectedDefaultModel = response.selectedDefaultModel
      smartConversationTitles = response.smartTitles
    }
  }

  func saveLlmRuntimeSettings(useGpu: Bool? = nil, defaultModel: String? = nil, smartTitles: Bool? = nil) async {
    let nextUseGpu = useGpu ?? llmUseGpu
    let nextDefaultModel = defaultModel ?? selectedDefaultModel
    let nextSmartTitles = smartTitles ?? smartConversationTitles
    let result = await runBackend(
      "llm-runtime-settings-set",
      nextUseGpu ? "1" : "0",
      nextDefaultModel,
      nextSmartTitles ? "1" : "0"
    )
    if let response = decode(LlmRuntimeSettingsResponse.self, from: result) {
      llmUseGpu = response.useGpu
      selectedDefaultModel = response.selectedDefaultModel
      smartConversationTitles = response.smartTitles
      await loadHealth()
      statusMessage = "Model settings saved."
    }
  }

  func loadProjects() async {
    let prior = selectedProjectID
    let result = await runBackend("projects", trackBusy: false)
    guard let response = decode(ProjectsResponse.self, from: result) else { return }
    projects = response.projects.filter { $0.pathExists }.sorted { left, right in
      left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
    }
    if let prior, projects.contains(where: { $0.id == prior }) {
      selectedProjectID = prior
    } else {
      selectedProjectID = projects.first?.id
    }
    if let selectedProjectID {
      expandedProjectIDs.insert(selectedProjectID)
    }
    await loadAllSessions(status: "Threads loaded.")
    await loadGitStatusAndBranches()
  }

  func loadAllSessions(status nextStatus: String? = "Session loaded.") async {
    let projectOrder = projects.sorted { left, right in
      if left.id == selectedProjectID { return true }
      if right.id == selectedProjectID { return false }
      if left.sessionCount != right.sessionCount { return left.sessionCount < right.sessionCount }
      return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
    }
    let hydratedProjectIDs = Set(projects.map(\.id))
    let visibleProjectIDs = expandedProjectIDs.union(selectedProjectID.map { Set([$0]) } ?? [])
    var nextSessionsByProject = sessionsByProject.filter { key, _ in
      projects.contains { $0.id == key }
    }
    sessionsByProject = nextSessionsByProject
    for project in projectOrder where hydratedProjectIDs.contains(project.id) && visibleProjectIDs.contains(project.id) {
      if let sortedSessions = await loadProjectSessions(project.id, trackBusy: false) {
        nextSessionsByProject[project.id] = sortedSessions
        sessionsByProject = nextSessionsByProject
        if project.id == selectedProjectID {
          sessions = sortedSessions
        }
      }
    }
    await loadSessionsForSelection(status: nextStatus)
  }

  func loadProjectSessions(_ projectID: String, trackBusy: Bool = true) async -> [SessionSummary]? {
    let result = await runBackend("sessions", [projectID], trackBusy: trackBusy)
    guard let response = decode(SessionsResponse.self, from: result) else { return nil }
    return response.sessions.sorted { left, right in
      left.updated > right.updated
    }
  }

  func loadSessionsForSelection(status nextStatus: String? = "Session loaded.") async {
    guard let projectID = selectedProjectID else {
      sessions = []
      selectedSessionID = nil
      selectedSession = nil
      return
    }
    sessions = sessionsByProject[projectID] ?? []
    if sessionsByProject[projectID] == nil {
      guard let loadedSessions = await loadProjectSessions(projectID) else { return }
      sessions = loadedSessions
      sessionsByProject[projectID] = loadedSessions
    } else if isProjectExpanded(projectID) {
      if let loadedSessions = await loadProjectSessions(projectID, trackBusy: false) {
        sessions = loadedSessions
        sessionsByProject[projectID] = loadedSessions
      }
    }
    if let selectedSessionID, sessions.contains(where: { $0.id == selectedSessionID }) {
      await loadSelectedSession(status: nextStatus)
    } else {
      preserveCurrentPromptDraft()
      selectedSessionID = sessions.first?.id
      await loadSelectedSession(status: nextStatus)
    }
  }

  func loadSelectedSession(status nextStatus: String? = "Session loaded.", trackBusy: Bool = true) async {
    guard let projectID = selectedProjectID, let sessionID = selectedSessionID else {
      selectedSession = nil
      return
    }
    let key = archiveKey(projectID: projectID, sessionID: sessionID)
    loadingSessionKey = key
    let result = await runBackend("session", [projectID, sessionID], trackBusy: trackBusy)
    if loadingSessionKey == key {
      loadingSessionKey = ""
    }
    guard let response = decode(SessionResponse.self, from: result) else { return }
    guard selectedProjectID == projectID, selectedSessionID == sessionID else { return }
    selectedSession = response.session
    restorePromptDraft(for: response.session)
    await saveSelectedVoiceTarget(projectID: projectID, sessionID: sessionID)
    await loadQueueItems()
    if let nextStatus {
      statusMessage = nextStatus
    }
  }

  func createSession() async {
    await createSession(in: selectedProjectID)
  }

  func createSession(in projectID: String?) async {
    guard let projectID else { return }
    guard !creatingSessionProjectIDs.contains(projectID) else { return }
    preserveCurrentPromptDraft()
    showingAutomations = false
    selectedProjectID = projectID
    expandedProjectIDs.insert(projectID)
    let title = "Native session \(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short))"
    let modelName = health?.defaultModel ?? ""
    let temporarySession = SessionSummary(
      id: "creating-\(UUID().uuidString)",
      workspaceID: projectID,
      title: title,
      model: modelName,
      updated: Int(Date().timeIntervalSince1970),
      queue: QueueState()
    )
    creatingSessionProjectIDs.insert(projectID)
    upsertSession(temporarySession, in: projectID, replacing: nil)
    sessions = sessionsByProject[projectID] ?? []
    selectedSessionID = temporarySession.id
    selectedSession = SessionDetail(summary: temporarySession)
    prompt = ""
    statusMessage = "Creating thread..."

    let result = await runBackend("session-create", [projectID, title, modelName], trackBusy: false)
    creatingSessionProjectIDs.remove(projectID)
    guard let response = decode(SessionResponse.self, from: result) else {
      removeSession(temporarySession.id, from: projectID)
      if selectedSessionID == temporarySession.id {
        selectedSessionID = nil
        selectedSession = nil
      }
      statusMessage = "Thread creation failed."
      return
    }
    let createdSummary = response.session.summary
    upsertSession(createdSummary, in: projectID, replacing: temporarySession.id)
    sessions = sessionsByProject[projectID] ?? []
    selectedSessionID = response.session.id
    selectedSession = response.session
    prompt = ""
    await saveSelectedVoiceTarget(projectID: projectID, sessionID: response.session.id)
    statusMessage = "Session created."
  }

  private func upsertSession(_ session: SessionSummary, in projectID: String, replacing oldSessionID: String?) {
    var list = sessionsByProject[projectID] ?? []
    if let oldSessionID {
      list.removeAll { $0.id == oldSessionID }
    }
    list.removeAll { $0.id == session.id }
    list.insert(session, at: 0)
    sessionsByProject[projectID] = list.sorted { left, right in
      left.updated > right.updated
    }
  }

  private func removeSession(_ sessionID: String, from projectID: String) {
    var list = sessionsByProject[projectID] ?? []
    list.removeAll { $0.id == sessionID }
    sessionsByProject[projectID] = list
    if selectedProjectID == projectID {
      sessions = list
    }
  }

  func selectProject(_ projectID: String) async {
    preserveCurrentPromptDraft()
    showingAutomations = false
    selectedProjectID = projectID
    selectedSessionID = nil
    selectedSession = nil
    prompt = ""
    pendingArchiveSessionKey = ""
    if let loadedSessions = await loadProjectSessions(projectID, trackBusy: false) {
      sessions = loadedSessions
      sessionsByProject[projectID] = loadedSessions
    } else {
      sessions = sessionsByProject[projectID] ?? []
    }
    await loadGitStatusAndBranches()
  }

  func toggleProject(_ projectID: String) async {
    preserveCurrentPromptDraft()
    showingAutomations = false
    selectedProjectID = projectID
    pendingArchiveSessionKey = ""
    if expandedProjectIDs.contains(projectID) {
      expandedProjectIDs.remove(projectID)
      sessions = sessionsByProject[projectID] ?? []
      return
    }
    expandedProjectIDs.insert(projectID)
    if sessionsByProject[projectID] == nil {
      statusMessage = "Loading threads..."
    }
    if let loadedSessions = await loadProjectSessions(projectID, trackBusy: false) {
      sessions = loadedSessions
      sessionsByProject[projectID] = loadedSessions
      statusMessage = "Threads loaded."
    } else {
      sessions = sessionsByProject[projectID] ?? []
    }
    await loadGitStatusAndBranches()
  }

  func selectSession(projectID: String, sessionID: String) async {
    preserveCurrentPromptDraft()
    showingAutomations = false
    selectedProjectID = projectID
    selectedSessionID = sessionID
    pendingArchiveSessionKey = ""
    if let summary = (sessionsByProject[projectID] ?? []).first(where: { $0.id == sessionID }) {
      selectedSession = SessionDetail(summary: summary)
    }
    statusMessage = "Opening thread..."
    await loadSelectedSession(status: "Thread opened.", trackBusy: false)
    await saveSelectedVoiceTarget(projectID: projectID, sessionID: sessionID)
    await loadGitStatusAndBranches()
  }

  func setSelectedSessionModel(_ modelName: String) async {
    let trimmedModel = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let projectID = selectedProjectID, let sessionID = selectedSessionID, !trimmedModel.isEmpty else { return }
    let result = await runBackend("session-set-model", projectID, sessionID, trimmedModel)
    guard decode(GenericSuccessResponse.self, from: result) != nil else { return }
    if let detail = selectedSession {
      selectedSession = SessionDetail(
        id: detail.id,
        workspaceID: detail.workspaceID,
        title: detail.title,
        model: trimmedModel,
        updated: Int(Date().timeIntervalSince1970),
        queue: detail.queue,
        decisionRequest: detail.decisionRequest,
        approvalRequest: detail.approvalRequest,
        trace: detail.trace,
        messages: detail.messages,
        draft: detail.draft
      )
    }
    if var list = sessionsByProject[projectID], let index = list.firstIndex(where: { $0.id == sessionID }) {
      let existing = list[index]
      list[index] = SessionSummary(
        id: existing.id,
        workspaceID: existing.workspaceID,
        title: existing.title,
        model: trimmedModel,
        updated: Int(Date().timeIntervalSince1970),
        queue: existing.queue
      )
      sessionsByProject[projectID] = list
      if selectedProjectID == projectID {
        sessions = list
      }
    }
    statusMessage = "Model updated."
  }

  func requestOrConfirmArchive(projectID: String, sessionID: String) async {
    let key = archiveKey(projectID: projectID, sessionID: sessionID)
    if pendingArchiveSessionKey != key {
      pendingArchiveSessionKey = key
      statusMessage = "Archive armed. Click checkmark to confirm."
      return
    }
    let result = await runBackend("session-archive", projectID, sessionID)
    if decode(GenericSuccessResponse.self, from: result) != nil {
      pendingArchiveSessionKey = ""
      if selectedProjectID == projectID && selectedSessionID == sessionID {
        selectedSessionID = nil
        selectedSession = nil
      }
      await loadAllSessions(status: nil)
      statusMessage = "Thread archived."
    }
  }

  func sendPrompt(runAfterQueue: Bool) async {
    var text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let projectID = selectedProjectID, let sessionID = selectedSessionID, !text.isEmpty || !pendingAttachments.isEmpty else { return }
    if text.isEmpty {
      text = "Please review the attached file(s)."
    }
    let attachmentIDs = pendingAttachments.map(\.id).joined(separator: ",")
    let result = await runBackend(
      "session-message",
      projectID,
      sessionID,
      text,
      runMode,
      computeBudget,
      commandExecMode,
      permissionMode,
      programmerReview ? "1" : "0",
      "\(programmerReviewRounds)",
      reflexiveKnowledge ? "1" : "0",
      selfActuation ? "1" : "0",
      attachmentIDs,
      reasoningEffort
    )
    guard decode(SessionResponse.self, from: result) != nil else { return }
    clearPromptDraft(projectID: projectID, sessionID: sessionID)
    prompt = ""
    pendingAttachments.removeAll()
    statusMessage = runAfterQueue ? "Prompt queued; running next item." : "Prompt queued."
    if runAfterQueue {
      await runNext(statusWhileRunning: "Prompt queued; running next item.", statusWhenDone: "Prompt queued; run-next completed.")
    } else {
      await loadAllSessions(status: nil)
      await loadQueueItems()
      statusMessage = "Prompt queued."
    }
  }

  func runNext(statusWhileRunning: String = "Running next item...", statusWhenDone: String = "Run-next completed.") async {
    guard let projectID = selectedProjectID, let sessionID = selectedSessionID else { return }
    statusMessage = statusWhileRunning
    let result = await runBackend("session-run-next", projectID, sessionID)
    if decode(SessionResponse.self, from: result) != nil {
      await loadAllSessions(status: nil)
      await loadQueueItems()
      await loadGitStatusAndBranches()
      statusMessage = statusWhenDone
    }
  }

  func loadAutomations() async {
    let result = await runBackend("automations")
    guard let response = decode(AutomationsResponse.self, from: result) else { return }
    automations = response.automations.items
  }

  func selectAutomationsPanel() async {
    showingAutomations = true
    if automationDraftProjectID.isEmpty, let selectedProjectID {
      automationDraftProjectID = selectedProjectID
    }
    if automationDraftSessionID.isEmpty, let selectedSessionID {
      automationDraftSessionID = selectedSessionID
    }
    await loadAutomationDraftSessions(projectID: automationDraftProjectID)
    await loadAutomations()
    await loadDaemonStatus()
  }

  func loadAutomationDraftSessions(projectID: String) async {
    guard !projectID.isEmpty else { return }
    if let loadedSessions = await loadProjectSessions(projectID, trackBusy: false) {
      sessionsByProject[projectID] = loadedSessions
      if automationDraftSessionID.isEmpty || !loadedSessions.contains(where: { $0.id == automationDraftSessionID }) {
        automationDraftSessionID = loadedSessions.first?.id ?? ""
      }
      if projectID == selectedProjectID {
        sessions = loadedSessions
      }
    }
  }

  func createAutomationFromDraft() async {
    let projectID = automationDraftProjectID.isEmpty ? (selectedProjectID ?? "") : automationDraftProjectID
    let sessionID = automationDraftSessionID.isEmpty ? (selectedSessionID ?? "") : automationDraftSessionID
    let name = automationDraftName.trimmingCharacters(in: .whitespacesAndNewlines)
    let promptText = automationDraftPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
    let scheduleValue = automationDraftScheduleValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !projectID.isEmpty, !sessionID.isEmpty, !name.isEmpty, !promptText.isEmpty, !scheduleValue.isEmpty else { return }
    let result = await runBackend(
      "automation-upsert",
      projectID,
      sessionID,
      name,
      promptText,
      automationDraftScheduleKind,
      scheduleValue,
      automationDraftEnabled ? "1" : "0",
      automationDraftAllowSelfReschedule ? "1" : "0",
      automationDraftRunMode,
      automationDraftComputeBudget,
      automationDraftCommandExecMode,
      automationDraftPermissionMode,
      automationDraftProgrammerReview ? "1" : "0",
      "\(automationDraftProgrammerReviewRounds)",
      automationDraftUsesNextRun ? "\(Int(automationDraftNextRunDate.timeIntervalSince1970))" : ""
    )
    if decode(GenericSuccessResponse.self, from: result) != nil || decode(AutomationMutationResponse.self, from: result) != nil {
      automationDraftName = ""
      automationDraftPrompt = ""
      automationDraftUsesNextRun = false
      statusMessage = "Automation added."
      await loadAutomations()
    }
  }

  func toggleAutomation(_ automation: AutomationItem, enabled: Bool) async {
    let result = await runBackend("automation-toggle", automation.id, enabled ? "1" : "0")
    if decode(GenericSuccessResponse.self, from: result) != nil || decode(AutomationMutationResponse.self, from: result) != nil {
      statusMessage = enabled ? "Automation enabled." : "Automation disabled."
      await loadAutomations()
    }
  }

  func runAutomationNow(_ automation: AutomationItem) async {
    let result = await runBackend("automation-run", automation.id)
    if decode(GenericSuccessResponse.self, from: result) != nil || decode(AutomationMutationResponse.self, from: result) != nil {
      statusMessage = "Automation queued."
      await loadAutomations()
    }
  }

  func loadDaemonStatus() async {
    let result = await runBackend("automation-daemon-status")
    if let daemon = decode(DaemonStatus.self, from: result) {
      daemonStatus = daemon
    }
  }

  func loadDesktopPrefs() async {
    let result = await runBackend("desktop-prefs-get", trackBusy: false)
    if let prefs = decode(DesktopPrefsResponse.self, from: result) {
      menuBarIconEnabled = prefs.menuBarIcon
      voiceAutomationsEnabled = prefs.voiceAutomations
      voiceRecognitionSoundEnabled = prefs.voiceRecognitionSound
      voiceBuiltinCommandsEnabled = prefs.voiceBuiltinCommands
      voiceDictationCommandsEnabled = prefs.voiceDictationCommands
      voiceLlmPromptsEnabled = prefs.voiceLlmPrompts
      voiceLlmActionsEnabled = prefs.voiceLlmActions
      loadVoiceLocalActions(from: prefs)
      selectedThemeID = AppTheme.resolved(prefs.themeID).id
      mobileBridgeEnabled = prefs.mobileBridge
      mobileTorEnabled = prefs.mobileTor
      mobileLanEnabled = prefs.mobileLan
      mobileAllowExecute = prefs.mobileAllowExecute
      mobileAllowSelfActuation = prefs.mobileAllowSelfActuation
      syncVoiceAutomationLoop()
    }
  }

  func loadDesktopPrefsForLaunch() {
    let environment = ProcessInfo.processInfo.environment
    let home = FileManager.default.homeDirectoryForCurrentUser
    let configRoot: URL
    if let xdgConfigHome = environment["XDG_CONFIG_HOME"], !xdgConfigHome.isEmpty {
      configRoot = URL(fileURLWithPath: xdgConfigHome, isDirectory: true)
    } else {
      configRoot = home.appendingPathComponent(".config", isDirectory: true)
    }
    let prefsURL = configRoot
      .appendingPathComponent("artificer", isDirectory: true)
      .appendingPathComponent("ui-prefs.env")
    guard let content = try? String(contentsOf: prefsURL, encoding: .utf8) else {
      return
    }
    let prefs = parseLaunchDesktopPrefs(content)
    if let value = prefs["menu_bar_icon"] {
      menuBarIconEnabled = desktopLaunchBool(value)
    }
    if let value = prefs["voice_automations"] {
      voiceAutomationsEnabled = desktopLaunchBool(value)
    }
    if let value = prefs["voice_automation_sound"] {
      voiceRecognitionSoundEnabled = desktopLaunchBool(value)
    }
    if let value = prefs["voice_builtin_commands"] {
      voiceBuiltinCommandsEnabled = desktopLaunchBool(value)
    }
    if let value = prefs["voice_dictation_commands"] {
      voiceDictationCommandsEnabled = desktopLaunchBool(value)
    }
    if let value = prefs["voice_automation_llm_prompts"] {
      voiceLlmPromptsEnabled = desktopLaunchBool(value)
    }
    if let value = prefs["voice_automation_llm_actions"] {
      voiceLlmActionsEnabled = desktopLaunchBool(value)
    }
    voiceLocalAction1Name = prefs["voice_local_action_1_name"] ?? voiceLocalAction1Name
    voiceLocalAction1Command = prefs["voice_local_action_1_command"] ?? voiceLocalAction1Command
    voiceLocalAction1Phrases = prefs["voice_local_action_1_phrases"] ?? voiceLocalAction1Phrases
    voiceLocalAction2Name = prefs["voice_local_action_2_name"] ?? voiceLocalAction2Name
    voiceLocalAction2Command = prefs["voice_local_action_2_command"] ?? voiceLocalAction2Command
    voiceLocalAction2Phrases = prefs["voice_local_action_2_phrases"] ?? voiceLocalAction2Phrases
    selectedThemeID = AppTheme.resolved(prefs["theme_id"] ?? selectedThemeID).id
    if let value = prefs["mobile_bridge"] {
      mobileBridgeEnabled = desktopLaunchBool(value)
    }
    if let value = prefs["mobile_tor"] {
      mobileTorEnabled = desktopLaunchBool(value)
    }
    if let value = prefs["mobile_lan"] {
      mobileLanEnabled = desktopLaunchBool(value)
    }
    if let value = prefs["mobile_allow_execute"] {
      mobileAllowExecute = desktopLaunchBool(value)
    }
    if let value = prefs["mobile_allow_self_actuation"] {
      mobileAllowSelfActuation = desktopLaunchBool(value)
    }
  }

  func setDesktopPref(_ key: String, enabled: Bool) async {
    let result = await runBackend("desktop-prefs-set", key, enabled ? "1" : "0")
    if let prefs = decode(DesktopPrefsResponse.self, from: result) {
      menuBarIconEnabled = prefs.menuBarIcon
      voiceAutomationsEnabled = prefs.voiceAutomations
      voiceRecognitionSoundEnabled = prefs.voiceRecognitionSound
      voiceBuiltinCommandsEnabled = prefs.voiceBuiltinCommands
      voiceDictationCommandsEnabled = prefs.voiceDictationCommands
      voiceLlmPromptsEnabled = prefs.voiceLlmPrompts
      voiceLlmActionsEnabled = prefs.voiceLlmActions
      loadVoiceLocalActions(from: prefs)
      selectedThemeID = AppTheme.resolved(prefs.themeID).id
      mobileBridgeEnabled = prefs.mobileBridge
      mobileTorEnabled = prefs.mobileTor
      mobileLanEnabled = prefs.mobileLan
      mobileAllowExecute = prefs.mobileAllowExecute
      mobileAllowSelfActuation = prefs.mobileAllowSelfActuation
      syncVoiceAutomationLoop()
      await loadVoiceAutomationStatus()
      await loadMobileStatus()
    }
  }

  func syncVoiceAutomationLoop() {
    if voiceAutomationsEnabled {
      guard voiceAutomationLoopTask == nil else { return }
      appendVoiceAutomationLog("native loop starting")
      requestMicrophoneAccessForVoiceAutomations()
      voiceAutomationLoopTask = Task.detached { [weak self] in
        while !Task.isCancelled {
          guard let self else { return }
          await self.runVoiceAutomationLoopTickDetached()
          try? await Task.sleep(nanoseconds: voiceAutomationLoopPauseNanoseconds)
        }
      }
    } else {
      appendVoiceAutomationLog("native loop stopping")
      voiceAutomationLoopTask?.cancel()
      voiceAutomationLoopTask = nil
    }
  }

  func runVoiceAutomationLoopTick() async {
    guard voiceAutomationsEnabled else {
      syncVoiceAutomationLoop()
      return
    }
    if isDictating {
      return
    }
    guard let audioURL = await captureVoiceAutomationAudio(seconds: voiceAutomationCaptureSeconds) else {
      return
    }
    defer { try? FileManager.default.removeItem(at: audioURL) }
    let transcribeResult = await runBackend("dictation-transcribe-file", audioURL.path, dictationLanguage, trackBusy: false)
    guard let transcription = decode(DictationTranscribeResponse.self, from: transcribeResult), transcription.success else {
      if let data = transcribeResult.stdout.data(using: .utf8),
         let apiError = try? JSONDecoder().decode(APIErrorResponse.self, from: data),
         !apiError.error.isEmpty {
        appendVoiceAutomationLog("native transcription failed: \(apiError.error)")
      } else if !transcribeResult.stderr.isEmpty {
        appendVoiceAutomationLog("native transcription failed: \(transcribeResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
      } else {
        appendVoiceAutomationLog("native transcription failed")
      }
      let handleResult = await runBackend("voice-automations-handle-text", "", trackBusy: false)
      if let status = decode(VoiceAutomationStatus.self, from: handleResult) {
        voiceAutomationStatus = status
      }
      return
    }
    let handleResult = await runBackend("voice-automations-handle-text", transcription.text, trackBusy: false)
    if let status = decode(VoiceAutomationStatus.self, from: handleResult) {
      voiceAutomationStatus = status
    }
  }

  func requestMicrophoneAccessForVoiceAutomations() {
    if #available(macOS 14.0, *) {
      if AVAudioApplication.shared.recordPermission == .undetermined {
        appendVoiceAutomationLog("native microphone authorization requesting on main actor")
        AVAudioApplication.requestRecordPermission { [weak self] granted in
          self?.appendVoiceAutomationLog("native microphone authorization result \(granted ? "granted" : "denied")")
        }
      }
    }
  }

  nonisolated func runVoiceAutomationLoopTickDetached() async {
    guard voiceAutomationEnabledFromDisk() else {
      return
    }
    guard let processingLockURL = acquireVoiceAutomationProcessingLock() else {
      return
    }
    guard let audioURL = await captureVoiceAutomationAudioDetached(seconds: voiceAutomationCaptureSeconds) else {
      releaseVoiceAutomationProcessingLock(processingLockURL)
      return
    }
    Task.detached { [weak self] in
      await self?.processVoiceAutomationAudioDetached(audioURL, processingLockURL: processingLockURL)
    }
  }

  nonisolated func processVoiceAutomationAudioDetached(_ audioURL: URL, processingLockURL: URL) async {
    defer {
      try? FileManager.default.removeItem(at: audioURL)
      releaseVoiceAutomationProcessingLock(processingLockURL)
    }
    let transcribeResult = await Backend.run(action: "dictation-transcribe-file", arguments: [audioURL.path, "auto"])
    guard
      transcribeResult.exitCode == 0,
      let transcribeData = transcribeResult.stdout.data(using: .utf8),
      let transcription = try? JSONDecoder().decode(DictationTranscribeResponse.self, from: transcribeData),
      transcription.success
    else {
      if
        let data = transcribeResult.stdout.data(using: .utf8),
        let apiError = try? JSONDecoder().decode(APIErrorResponse.self, from: data),
        !apiError.error.isEmpty
      {
        appendVoiceAutomationLog("native transcription failed: \(apiError.error)")
      } else if !transcribeResult.stderr.isEmpty {
        appendVoiceAutomationLog("native transcription failed: \(transcribeResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
      } else {
        appendVoiceAutomationLog("native transcription failed")
      }
      let handleResult = await Backend.run(action: "voice-automations-handle-text", arguments: [""])
      if
        handleResult.exitCode == 0,
        let data = handleResult.stdout.data(using: .utf8),
        let status = try? JSONDecoder().decode(VoiceAutomationStatus.self, from: data)
      {
        await MainActor.run {
          voiceAutomationStatus = status
        }
      }
      return
    }

    let handleResult = await Backend.run(action: "voice-automations-handle-text", arguments: [transcription.text])
    if
      handleResult.exitCode == 0,
      let data = handleResult.stdout.data(using: .utf8),
      let status = try? JSONDecoder().decode(VoiceAutomationStatus.self, from: data)
    {
      await MainActor.run {
        voiceAutomationStatus = status
      }
    }
  }

  nonisolated func voiceAutomationEnabledFromDisk() -> Bool {
    let prefsURL = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".config", isDirectory: true)
      .appendingPathComponent("artificer", isDirectory: true)
      .appendingPathComponent("ui-prefs.env")
    guard let content = try? String(contentsOf: prefsURL, encoding: .utf8) else {
      return false
    }
    for rawLine in content.components(separatedBy: .newlines) {
      let line = rawLine.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
      guard line.hasPrefix("voice_automations=") else { continue }
      let value = String(line.dropFirst("voice_automations=".count)).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      return ["1", "true", "yes", "on", "enabled"].contains(value)
    }
    return false
  }

  nonisolated func voiceAutomationProcessingLockURL() -> URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".local", isDirectory: true)
      .appendingPathComponent("state", isDirectory: true)
      .appendingPathComponent("artificer-native", isDirectory: true)
      .appendingPathComponent("voice-automations", isDirectory: true)
      .appendingPathComponent("native-transcription.lock", isDirectory: true)
  }

  nonisolated func acquireVoiceAutomationProcessingLock() -> URL? {
    let lockURL = voiceAutomationProcessingLockURL()
    do {
      try FileManager.default.createDirectory(at: lockURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try FileManager.default.createDirectory(at: lockURL, withIntermediateDirectories: false)
      return lockURL
    } catch {
      return nil
    }
  }

  nonisolated func releaseVoiceAutomationProcessingLock(_ lockURL: URL) {
    try? FileManager.default.removeItem(at: lockURL)
  }

  nonisolated func captureVoiceAutomationAudioDetached(seconds: TimeInterval) async -> URL? {
    let allowed = await requestMicrophoneAccessDetached()
    guard allowed else {
      appendVoiceAutomationLog("native microphone access denied")
      return nil
    }

    let captureDir = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".local", isDirectory: true)
      .appendingPathComponent("state", isDirectory: true)
      .appendingPathComponent("artificer-native", isDirectory: true)
      .appendingPathComponent("voice-automations", isDirectory: true)
      .appendingPathComponent("native-capture", isDirectory: true)
    do {
      try FileManager.default.createDirectory(at: captureDir, withIntermediateDirectories: true)
    } catch {
      appendVoiceAutomationLog("native capture directory failed: \(error.localizedDescription)")
      return nil
    }

    let audioURL = captureDir.appendingPathComponent("voice-\(UUID().uuidString).wav")
    let settings: [String: Any] = [
      AVFormatIDKey: Int(kAudioFormatLinearPCM),
      AVSampleRateKey: 16_000.0,
      AVNumberOfChannelsKey: 1,
      AVLinearPCMBitDepthKey: 16,
      AVLinearPCMIsFloatKey: false,
      AVLinearPCMIsBigEndianKey: false
    ]

    do {
      let recorder = try AVAudioRecorder(url: audioURL, settings: settings)
      recorder.isMeteringEnabled = true
      recorder.prepareToRecord()
      guard recorder.record() else {
        appendVoiceAutomationLog("native recorder did not start")
        return nil
      }
      appendVoiceAutomationLog("native recorder started")
      let elapsed = await waitForVoiceAutomationCaptureWindow(recorder, maxSeconds: seconds)
      recorder.stop()
      let size = ((try? FileManager.default.attributesOfItem(atPath: audioURL.path)[.size] as? NSNumber)?.intValue) ?? 0
      guard size > 44 else {
        try? FileManager.default.removeItem(at: audioURL)
        appendVoiceAutomationLog("native recorder captured no audio")
        return nil
      }
      appendVoiceAutomationLog("native recorder captured \(size) bytes in \(String(format: "%.2f", elapsed))s")
      return audioURL
    } catch {
      try? FileManager.default.removeItem(at: audioURL)
      appendVoiceAutomationLog("native recorder failed: \(error.localizedDescription)")
      return nil
    }
  }

  nonisolated func requestMicrophoneAccessDetached() async -> Bool {
    appendVoiceAutomationLog("native microphone authorization check")
    if #available(macOS 14.0, *) {
      switch AVAudioApplication.shared.recordPermission {
      case .granted:
        appendVoiceAutomationLog("native microphone already authorized")
        return true
      case .undetermined:
        appendVoiceAutomationLog("native microphone authorization requesting")
        return await withCheckedContinuation { continuation in
          AVAudioApplication.requestRecordPermission { granted in
            self.appendVoiceAutomationLog("native microphone authorization result \(granted ? "granted" : "denied")")
            continuation.resume(returning: granted)
          }
        }
      default:
        appendVoiceAutomationLog("native microphone authorization not allowed")
        return false
      }
    } else {
      switch AVCaptureDevice.authorizationStatus(for: .audio) {
      case .authorized:
        appendVoiceAutomationLog("native microphone already authorized")
        return true
      case .notDetermined:
        appendVoiceAutomationLog("native microphone authorization requesting")
        return await withCheckedContinuation { continuation in
          AVCaptureDevice.requestAccess(for: .audio) { granted in
            self.appendVoiceAutomationLog("native microphone authorization result \(granted ? "granted" : "denied")")
            continuation.resume(returning: granted)
          }
        }
      default:
        appendVoiceAutomationLog("native microphone authorization not allowed")
        return false
      }
    }
  }

  func captureVoiceAutomationAudio(seconds: TimeInterval) async -> URL? {
    let allowed = await requestMicrophoneAccess()
    guard allowed else {
      appendVoiceAutomationLog("native microphone access denied")
      lastError = "Microphone access is required for voice automations."
      statusMessage = "Voice automations need microphone access."
      return nil
    }

    let captureDir = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".local", isDirectory: true)
      .appendingPathComponent("state", isDirectory: true)
      .appendingPathComponent("artificer-native", isDirectory: true)
      .appendingPathComponent("voice-automations", isDirectory: true)
      .appendingPathComponent("native-capture", isDirectory: true)
    do {
      try FileManager.default.createDirectory(at: captureDir, withIntermediateDirectories: true)
    } catch {
      appendVoiceAutomationLog("native capture directory failed: \(error.localizedDescription)")
      lastError = "Could not create voice capture directory: \(error.localizedDescription)"
      return nil
    }

    let audioURL = captureDir.appendingPathComponent("voice-\(UUID().uuidString).wav")
    let settings: [String: Any] = [
      AVFormatIDKey: Int(kAudioFormatLinearPCM),
      AVSampleRateKey: 16_000.0,
      AVNumberOfChannelsKey: 1,
      AVLinearPCMBitDepthKey: 16,
      AVLinearPCMIsFloatKey: false,
      AVLinearPCMIsBigEndianKey: false
    ]

    do {
      let recorder = try AVAudioRecorder(url: audioURL, settings: settings)
      recorder.isMeteringEnabled = true
      recorder.prepareToRecord()
      voiceAutomationRecorder = recorder
      guard recorder.record() else {
        voiceAutomationRecorder = nil
        appendVoiceAutomationLog("native recorder did not start")
        lastError = "Voice automation recording did not start."
        return nil
      }
      appendVoiceAutomationLog("native recorder started")
      let elapsed = await waitForVoiceAutomationCaptureWindow(recorder, maxSeconds: seconds)
      recorder.stop()
      voiceAutomationRecorder = nil
      let size = ((try? FileManager.default.attributesOfItem(atPath: audioURL.path)[.size] as? NSNumber)?.intValue) ?? 0
      guard size > 44 else {
        try? FileManager.default.removeItem(at: audioURL)
        appendVoiceAutomationLog("native recorder captured no audio")
        lastError = "Voice automation recording captured no audio."
        return nil
      }
      appendVoiceAutomationLog("native recorder captured \(size) bytes in \(String(format: "%.2f", elapsed))s")
      return audioURL
    } catch {
      voiceAutomationRecorder = nil
      try? FileManager.default.removeItem(at: audioURL)
      appendVoiceAutomationLog("native recorder failed: \(error.localizedDescription)")
      lastError = "Voice automation recording failed: \(error.localizedDescription)"
      return nil
    }
  }

  nonisolated func appendVoiceAutomationLog(_ message: String) {
    let logURL = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".local", isDirectory: true)
      .appendingPathComponent("state", isDirectory: true)
      .appendingPathComponent("artificer-native", isDirectory: true)
      .appendingPathComponent("voice-automations", isDirectory: true)
      .appendingPathComponent("voice-automations.log")
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let line = "\(timestamp) \(message)\n"
    do {
      try FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      if let data = line.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: logURL.path),
           let handle = try? FileHandle(forWritingTo: logURL) {
          try handle.seekToEnd()
          try handle.write(contentsOf: data)
          try handle.close()
        } else {
          try data.write(to: logURL)
        }
      }
    } catch {
      // Best-effort diagnostics only.
    }
  }

  func requestMicrophoneAccess() async -> Bool {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized:
      return true
    case .notDetermined:
      return await withCheckedContinuation { continuation in
        AVCaptureDevice.requestAccess(for: .audio) { granted in
          continuation.resume(returning: granted)
        }
      }
    default:
      return false
    }
  }

  func loadVoiceAutomationStatus() async {
    let result = await runBackend("voice-automations-status", trackBusy: false)
    if let status = decode(VoiceAutomationStatus.self, from: result) {
      voiceAutomationStatus = status
    }
  }

  func setDesktopValue(_ key: String, value: String) async {
    let result = await runBackend("desktop-value-set", key, value)
    if let prefs = decode(DesktopPrefsResponse.self, from: result) {
      loadVoiceLocalActions(from: prefs)
      statusMessage = "Voice commands saved."
      await loadVoiceAutomationStatus()
    }
  }

  func saveVoiceCommandPhrases() async {
    guard canSaveVoiceCommandPhrases else {
      statusMessage = "Each configured local action needs a name, command, and phrases."
      return
    }
    await setDesktopValue("voice_local_action_1_name", value: voiceLocalAction1Name.trimmingCharacters(in: .whitespacesAndNewlines))
    await setDesktopValue("voice_local_action_1_command", value: voiceLocalAction1Command.trimmingCharacters(in: .whitespacesAndNewlines))
    await setDesktopValue("voice_local_action_1_phrases", value: voiceLocalAction1Phrases.trimmingCharacters(in: .whitespacesAndNewlines))
    await setDesktopValue("voice_local_action_2_name", value: voiceLocalAction2Name.trimmingCharacters(in: .whitespacesAndNewlines))
    await setDesktopValue("voice_local_action_2_command", value: voiceLocalAction2Command.trimmingCharacters(in: .whitespacesAndNewlines))
    await setDesktopValue("voice_local_action_2_phrases", value: voiceLocalAction2Phrases.trimmingCharacters(in: .whitespacesAndNewlines))
  }

  private func loadVoiceLocalActions(from prefs: DesktopPrefsResponse) {
    voiceLocalAction1Name = prefs.voiceLocalAction1Name
    voiceLocalAction1Command = prefs.voiceLocalAction1Command
    voiceLocalAction1Phrases = prefs.voiceLocalAction1Phrases
    voiceLocalAction2Name = prefs.voiceLocalAction2Name
    voiceLocalAction2Command = prefs.voiceLocalAction2Command
    voiceLocalAction2Phrases = prefs.voiceLocalAction2Phrases
  }

  func loadMobileStatus() async {
    let result = await runBackend("mobile-status", trackBusy: false)
    if let status = decode(MobileBridgeStatus.self, from: result) {
      mobileStatus = status
    }
  }

  func restartMobileBridge() async {
    let result = await runBackend("mobile-restart")
    if let status = decode(MobileBridgeStatus.self, from: result) {
      mobileStatus = status
      statusMessage = "Mobile bridge restarted."
    }
  }

  func installMobileTor() async {
    let result = await runBackend("mobile-install-tor")
    if decode(GenericSuccessResponse.self, from: result) != nil {
      statusMessage = "Tor install checked."
      await loadMobileStatus()
    }
  }

  func saveSelectedVoiceTarget(projectID: String, sessionID: String) async {
    _ = await runBackend("desktop-selection-set", projectID, sessionID, trackBusy: false)
  }

  func daemon(_ action: String) async {
    let result = await runBackend(action)
    if let daemon = decode(DaemonStatus.self, from: result) {
      daemonStatus = daemon
      statusMessage = "Automation daemon: \(daemon.status)."
    }
  }

  func setAutomationDaemonEnabled(_ enabled: Bool) async {
    await daemon(enabled ? "automation-daemon-enable" : "automation-daemon-disable")
    await setDesktopPref("background_mode", enabled: enabled || menuBarIconEnabled)
  }

  func setMenuBarIconEnabled(_ enabled: Bool) async {
    await setDesktopPref("menu_bar_icon", enabled: enabled)
    await setDesktopPref("background_mode", enabled: enabled || (daemonStatus?.enabled ?? false))
    statusMessage = enabled ? "Menu bar icon enabled." : "Menu bar icon disabled."
  }

  func toggleAutomationDaemonPaused() async {
    if daemonStatus?.paused ?? false {
      await daemon("automation-daemon-resume")
    } else {
      await daemon("automation-daemon-pause")
    }
  }

  func openHostedArtificer() async {
    let result = await runBackend("open-web")
    if let response = decode(OpenWebResponse.self, from: result) {
      statusMessage = "Opened \(response.url)"
    }
  }

  func loadDictationStatus() async {
    let result = await runBackend("dictation-status", trackBusy: false)
    if let response = decode(DictationStatus.self, from: result) {
      dictationStatus = response
      dictationLanguage = response.language
      if response.installed {
        dictationInstallMessage = "Dictation ready: \(response.backendLabel)."
      } else if dictationInstallMessage.isEmpty {
        dictationInstallMessage = "Install Artificer's local voice-recognition system before recording."
      }
    }
  }

  func loadDictationPreferences() async {
    let languageResult = await runBackend("dictation-language-get", trackBusy: false)
    if let response = decode(DictationLanguageResponse.self, from: languageResult) {
      dictationLanguage = response.language
      if !response.languages.isEmpty {
        dictationLanguages = response.languages
      }
    }
    let prewarmResult = await runBackend("dictation-prewarm-get", trackBusy: false)
    if let response = decode(DictationPrewarmResponse.self, from: prewarmResult) {
      dictationPrewarmEnabled = response.enabled
    }
    let shortcutsResult = await runBackend("dictation-shortcuts-get", trackBusy: false)
    if let response = decode(DictationShortcutsResponse.self, from: shortcutsResult) {
      dictationHoldShortcut = response.hold
      dictationToggleShortcut = response.toggle
    }
  }

  func setDictationLanguage(_ language: String) async {
    let result = await runBackend("dictation-language-set", language)
    if let response = decode(DictationLanguageResponse.self, from: result) {
      dictationLanguage = response.language
      if !response.languages.isEmpty {
        dictationLanguages = response.languages
      }
      statusMessage = "Dictation language saved."
    }
  }

  func setDictationPrewarm(_ enabled: Bool) async {
    let result = await runBackend("dictation-prewarm-set", enabled ? "1" : "0")
    if let response = decode(DictationPrewarmResponse.self, from: result) {
      dictationPrewarmEnabled = response.enabled
      statusMessage = enabled ? "Dictation prewarm enabled." : "Dictation prewarm disabled."
    }
  }

  func setDictationShortcuts(hold: String, toggle: String) async {
    let result = await runBackend("dictation-shortcuts-set", hold, toggle)
    if let response = decode(DictationShortcutsResponse.self, from: result) {
      dictationHoldShortcut = response.hold
      dictationToggleShortcut = response.toggle
      statusMessage = "Dictation shortcuts saved."
    }
  }

  func loadSelfImproveSettings() async {
    let result = await runBackend("self-improve-settings", trackBusy: false)
    guard let response = decode(SelfImproveSettingsResponse.self, from: result) else { return }
    applySelfImproveResponse(response)
  }

  func setCodexWorkCheckEnabled(_ enabled: Bool) async {
    let result = await runBackend("self-improve-codex-work-check-set", enabled ? "1" : "0")
    guard let response = decode(SelfImproveRunOptionsResponse.self, from: result) else { return }
    applySelfImproveOptions(response.runOptions)
    statusMessage = codexWorkCheckEnabled ? "Codex work checks enabled." : "Codex work checks disabled."
  }

  func saveSelfImproveOptions(
    objective: String? = nil,
    competitionEnabled: Bool? = nil,
    challengerModel: String? = nil,
    codexWorkCheckEnabled nextCodexWorkCheckEnabled: Bool? = nil,
    sourcePapers: Bool? = nil,
    sourceWeb: Bool? = nil,
    sourceRuntime: Bool? = nil,
    sourceRepo: Bool? = nil,
    sourcePlatform: Bool? = nil
  ) async {
    let nextObjective = objective ?? selfImproveObjective
    let nextCompetition = competitionEnabled ?? selfImproveCompetitionEnabled
    let nextChallenger = challengerModel ?? selfImproveChallengerModel
    let nextCodex = nextCodexWorkCheckEnabled ?? codexWorkCheckEnabled
    let nextPapers = sourcePapers ?? selfImproveSourcePapers
    let nextWeb = sourceWeb ?? selfImproveSourceWeb
    let nextRuntime = sourceRuntime ?? selfImproveSourceRuntime
    let nextRepo = sourceRepo ?? selfImproveSourceRepo
    let nextPlatform = sourcePlatform ?? selfImproveSourcePlatform
    let result = await runBackend(
      "self-improve-run-options-set",
      nextObjective,
      nextCompetition ? "1" : "0",
      nextChallenger,
      nextCodex ? "1" : "0",
      nextPapers ? "1" : "0",
      nextWeb ? "1" : "0",
      nextRuntime ? "1" : "0",
      nextRepo ? "1" : "0",
      nextPlatform ? "1" : "0"
    )
    guard let response = decode(SelfImproveRunOptionsResponse.self, from: result) else { return }
    applySelfImproveOptions(response.runOptions)
    selfImproveStatus = "Self-improve options saved."
  }

  func runSelfImprove() async {
    guard !selfImproveSelectedModel.isEmpty else { return }
    isSelfImproveRunning = true
    selfImproveStatus = selfImproveCompetitionEnabled ? "Running self-improve match..." : "Running self-improve..."
    let result = await runBackend(
      "self-improve-run",
      selfImproveSelectedModel,
      selfImproveObjective,
      selfImproveCompetitionEnabled ? "1" : "0",
      selfImproveChallengerModel,
      codexWorkCheckEnabled ? "1" : "0",
      selfImproveSourcePapers ? "1" : "0",
      selfImproveSourceWeb ? "1" : "0",
      selfImproveSourceRuntime ? "1" : "0",
      selfImproveSourceRepo ? "1" : "0",
      selfImproveSourcePlatform ? "1" : "0"
    )
    isSelfImproveRunning = false
    guard let response = decode(SelfImproveRunResponse.self, from: result), response.success else {
      selfImproveStatus = "Self-improve run failed."
      return
    }
    applySelfImproveResponse(response)
    selfImproveStatus = "Self-improve run completed."
  }

  private func applySelfImproveResponse(_ response: SelfImproveSettingsResponse) {
    selfImproveSelectedModel = response.selectedModel.isEmpty ? (installedModels.first ?? "") : response.selectedModel
    applySelfImproveOptions(response.runOptions)
    selfImproveSummary = response.lastRun.summary
    selfImprovePluginCount = response.pluginInventory.activeCount
    if !response.lastRun.generatedAt.isEmpty {
      selfImproveStatus = "Last run: \(response.lastRun.generatedAt)"
    }
  }

  private func applySelfImproveResponse(_ response: SelfImproveRunResponse) {
    selfImproveSelectedModel = response.selectedModel.isEmpty ? selfImproveSelectedModel : response.selectedModel
    applySelfImproveOptions(response.runOptions)
    selfImproveSummary = response.lastRun.summary
    selfImprovePluginCount = response.pluginInventory.activeCount
    if !response.lastRun.generatedAt.isEmpty {
      selfImproveStatus = "Last run: \(response.lastRun.generatedAt)"
    }
  }

  private func applySelfImproveOptions(_ options: SelfImproveRunOptions) {
    selfImproveObjective = options.objective
    selfImproveCompetitionEnabled = options.competitionEnabled
    selfImproveChallengerModel = options.challengerModel
    codexWorkCheckEnabled = options.codexWorkCheckEnabled
    selfImproveSourcePapers = options.sources.papers
    selfImproveSourceWeb = options.sources.web
    selfImproveSourceRuntime = options.sources.runtime
    selfImproveSourceRepo = options.sources.repo
    selfImproveSourcePlatform = options.sources.platform
  }

  func loadGitRuntimeSettings() async {
    let result = await runBackend("git-runtime-settings-get", trackBusy: false)
    if let response = decode(GitRuntimeSettingsResponse.self, from: result) {
      gitWorkflowPolicy = response.workflowPolicy
      gitAmbiguityPolicy = response.ambiguityPolicy
    }
  }

  func setGitRuntimeSettings(workflowPolicy: String, ambiguityPolicy: String) async {
    let result = await runBackend("git-runtime-settings-set", workflowPolicy, ambiguityPolicy)
    if let response = decode(GitRuntimeSettingsResponse.self, from: result) {
      gitWorkflowPolicy = response.workflowPolicy
      gitAmbiguityPolicy = response.ambiguityPolicy
      statusMessage = "Git policy saved."
    }
  }

  func installDictation() async {
    let result = await runBackend("dictation-install-start")
    guard let response = decode(DictationInstallStartResponse.self, from: result) else { return }
    dictationInstallJobID = response.job.id
    isDictationInstalling = response.job.status == "running"
    dictationInstallMessage = "Installing dictation: \(response.job.phase)."
    Task { await pollDictationInstall(jobID: response.job.id) }
  }

  func cancelDictationInstall() async {
    let jobID = dictationInstallJobID
    guard !jobID.isEmpty else { return }
    _ = await runBackend("dictation-install-cancel", jobID)
    dictationInstallJobID = ""
    isDictationInstalling = false
    dictationInstallMessage = "Dictation install cancelled."
    await loadDictationStatus()
  }

  private func pollDictationInstall(jobID: String) async {
    while dictationInstallJobID == jobID {
      let result = await runBackend("dictation-install-status", [jobID], trackBusy: false)
      guard let response = decode(DictationInstallStatusResponse.self, from: result) else { return }
      let progress = response.job.progressPct.isEmpty ? "" : " \(response.job.progressPct)%"
      dictationInstallMessage = "Installing dictation: \(response.job.phase)\(progress)."
      isDictationInstalling = response.job.status == "running"
      if response.job.status != "running" {
        dictationInstallJobID = ""
        if response.job.status == "done" {
          dictationInstallMessage = "Dictation installed."
          await loadDictationStatus()
        } else {
          dictationInstallMessage = "Dictation install \(response.job.status)."
        }
        return
      }
      try? await Task.sleep(nanoseconds: 1_000_000_000)
    }
  }

  func toggleDictation() async {
    if isDictating {
      await stopDictation()
    } else {
      await startDictation()
    }
  }

  func startDictation() async {
    await loadDictationStatus()
    if let dictationStatus, !dictationStatus.installed {
      lastError = "Artificer's local voice-recognition system is not installed."
      statusMessage = "Dictation unavailable."
      return
    }
    let result = await runBackend("dictation-start", dictationStatus?.language ?? "auto")
    guard let response = decode(DictationStartResponse.self, from: result) else { return }
    isDictating = true
    dictationSessionID = response.session.id
    dictationStartedAt = Date()
    dictationLevels = []
    statusMessage = "Dictation recording."
    Task { await pollDictationLevels(sessionID: response.session.id) }
  }

  func stopDictation() async {
    let sessionID = dictationSessionID
    guard !sessionID.isEmpty else {
      isDictating = false
      return
    }
    let result = await runBackend("dictation-stop", sessionID)
    isDictating = false
    dictationSessionID = ""
    dictationStartedAt = nil
    dictationLevels = []
    if let response = decode(DictationStopResponse.self, from: result) {
      let dictated = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
      if !dictated.isEmpty {
        if prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          prompt = dictated
        } else {
          prompt += "\n" + dictated
        }
      }
      statusMessage = "Dictation captured."
    }
  }

  private func pollDictationLevels(sessionID: String) async {
    while isDictating && dictationSessionID == sessionID {
      let result = await runBackend("dictation-levels", [sessionID], trackBusy: false)
      if let response = decode(DictationLevelsResponse.self, from: result), response.sessionID == sessionID || response.sessionID.isEmpty {
        if response.levels.isEmpty {
          dictationLevels = Array((dictationLevels + [response.level]).suffix(24))
        } else {
          dictationLevels = Array(response.levels.suffix(24))
        }
      }
      try? await Task.sleep(nanoseconds: 180_000_000)
    }
  }

  func chooseAttachments() {
    guard selectedSessionID != nil else { return }
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = true
    panel.prompt = "Attach"
    if panel.runModal() == .OK {
      let urls = panel.urls
      Task {
        for url in urls {
          await uploadAttachment(url)
        }
      }
    }
  }

  func handleDroppedAttachments(_ providers: [NSItemProvider]) -> Bool {
    guard selectedSessionID != nil else { return false }
    let fileProviders = providers.filter { provider in
      provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
    }
    guard !fileProviders.isEmpty else { return false }

    for provider in fileProviders {
      provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
        let url: URL?
        if let data = item as? Data {
          url = URL(dataRepresentation: data, relativeTo: nil)
        } else if let droppedURL = item as? URL {
          url = droppedURL
        } else if let droppedURL = item as? NSURL {
          url = droppedURL as URL
        } else if let string = item as? String, let parsedURL = URL(string: string), parsedURL.isFileURL {
          url = parsedURL
        } else {
          url = nil
        }
        guard let url else { return }
        Task {
          await self.uploadAttachment(url)
        }
      }
    }
    return true
  }

  func uploadAttachment(_ url: URL) async {
    guard let projectID = selectedProjectID, let sessionID = selectedSessionID else { return }
    let result = await runBackend("attachment-upload", projectID, sessionID, url.path)
    guard let response = decode(AttachmentUploadResponse.self, from: result) else { return }
    pendingAttachments.append(response.attachment)
    statusMessage = "Attached \(response.attachment.name)."
  }

  func removeAttachment(_ attachment: PendingAttachment) {
    pendingAttachments.removeAll { $0.id == attachment.id }
  }

  func saveCoreRoot() async {
    let root = coreRootDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !root.isEmpty else { return }
    let result = await runBackend("prefs-set-core-root", root)
    if let prefs = decode(PrefsResponse.self, from: result) {
      resolvedCoreRoot = prefs.coreRoot
      coreRootDraft = prefs.coreRoot
      statusMessage = "Core root saved."
      await refreshAll()
    }
  }

  func chooseCoreRoot() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.prompt = "Use Core"
    if panel.runModal() == .OK, let url = panel.url {
      coreRootDraft = url.path
    }
  }

  func chooseWorkspaceFolder() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.prompt = "Add Workspace"
    if panel.runModal() == .OK, let url = panel.url {
      Task {
        await addWorkspace(path: url.path, name: url.lastPathComponent)
      }
    }
  }

  func addWorkspace(path: String, name: String) async {
    let result = await runBackend("project-add", path, name, commandExecMode)
    if decode(ProjectMutationResponse.self, from: result) != nil {
      statusMessage = "Workspace added."
      await loadProjects()
    }
  }

  private func runBackend(_ action: String, _ args: String...) async -> CommandResult {
    await runBackend(action, args)
  }

  private func runBackend(_ action: String, _ args: [String]) async -> CommandResult {
    await runBackend(action, args, trackBusy: true)
  }

  private func runBackend(_ action: String, _ args: String..., trackBusy: Bool) async -> CommandResult {
    await runBackend(action, args, trackBusy: trackBusy)
  }

  private func runBackend(_ action: String, _ args: [String] = [], trackBusy: Bool) async -> CommandResult {
    if trackBusy {
      isBusy = true
      lastError = ""
    }
    defer {
      if trackBusy {
        isBusy = false
      }
    }
    let result = await Backend.run(action: action, arguments: args)
    if result.exitCode != 0 {
      lastError = result.summary
      statusMessage = "\(action) failed."
    }
    return result
  }

  private func decode<T: Decodable>(_ type: T.Type, from result: CommandResult) -> T? {
    guard result.exitCode == 0, let data = result.stdout.data(using: .utf8) else {
      if !result.stderr.isEmpty { lastError = result.stderr }
      return nil
    }
    do {
      return try JSONDecoder().decode(type, from: data)
    } catch {
      if let apiError = try? JSONDecoder().decode(APIErrorResponse.self, from: data), !apiError.success {
        lastError = apiError.error.isEmpty ? "Backend request failed." : apiError.error
        statusMessage = lastError
        return nil
      }
      lastError = "Could not parse backend response: \(error.localizedDescription)"
      return nil
    }
  }
}

private enum Backend {
  static func run(action: String, arguments: [String]) async -> CommandResult {
    await Task.detached(priority: .userInitiated) {
      guard let script = scriptURL() else {
        return CommandResult(exitCode: 127, stdout: "", stderr: "artificer-native-backend.sh was not found.")
      }
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/bin/sh")
      process.arguments = [script.path, action] + arguments

      let outputPipe = Pipe()
      let errorPipe = Pipe()
      process.standardOutput = outputPipe
      process.standardError = errorPipe

      do {
        try process.run()
        process.waitUntilExit()
      } catch {
        return CommandResult(exitCode: 127, stdout: "", stderr: "Failed to run backend: \(error.localizedDescription)")
      }

      let stdout = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
      let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
      return CommandResult(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
    }.value
  }

  private static func scriptURL() -> URL? {
    let fileManager = FileManager.default
    let environment = ProcessInfo.processInfo.environment
    if let override = environment["ARTIFICER_NATIVE_BACKEND"], !override.isEmpty {
      let url = URL(fileURLWithPath: (override as NSString).standardizingPath)
      if fileManager.fileExists(atPath: url.path) { return url }
    }

    let absolute = URL(fileURLWithPath: fallbackProjectDir, isDirectory: true)
      .appendingPathComponent("scripts", isDirectory: true)
      .appendingPathComponent("artificer-native-backend.sh")
    if fileManager.fileExists(atPath: absolute.path) { return absolute }

    var seeds = [fileManager.currentDirectoryPath]
    if let executablePath = Bundle.main.executablePath {
      seeds.append((executablePath as NSString).deletingLastPathComponent)
    }
    seeds.append(Bundle.main.bundlePath)
    if let resourcePath = Bundle.main.resourcePath {
      seeds.append(resourcePath)
    }

    for seed in seeds {
      for ancestor in ancestorPaths(for: seed) {
        let candidate = URL(fileURLWithPath: ancestor, isDirectory: true)
          .appendingPathComponent("scripts", isDirectory: true)
          .appendingPathComponent("artificer-native-backend.sh")
        if fileManager.fileExists(atPath: candidate.path) {
          return candidate
        }
      }
    }
    return nil
  }

  private static func ancestorPaths(for path: String) -> [String] {
    var results: [String] = []
    var current = (path as NSString).standardizingPath
    while !current.isEmpty {
      results.append(current)
      let parent = (current as NSString).deletingLastPathComponent
      if parent == current { break }
      current = parent
    }
    return results
  }
}

private struct CommandResult: Sendable {
  let exitCode: Int32
  let stdout: String
  let stderr: String

  var summary: String {
    let text = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
    if !text.isEmpty { return text }
    return stdout.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

private struct DoctorResponse: Decodable {
  let success: Bool
  let coreRoot: String
  let coreReady: Bool

  enum CodingKeys: String, CodingKey {
    case success
    case coreRoot = "core_root"
    case coreReady = "core_ready"
  }
}

private struct PrefsResponse: Decodable {
  let success: Bool
  let coreRoot: String

  enum CodingKeys: String, CodingKey {
    case success
    case coreRoot = "core_root"
  }
}

private struct HealthResponse: Decodable {
  let success: Bool
  let runtime: RuntimeHealth
}

private struct ModelsResponse: Decodable {
  let success: Bool
  let models: [String]
}

private struct ModelCatalogResponse: Decodable {
  let success: Bool
  let available: [ModelCatalogEntry]
  let installs: [ModelInstallJob]
}

private struct ModelCatalogEntry: Identifiable, Decodable, Hashable {
  let id: String
  let name: String
  let description: String
  let sizeGB: String
  let contextK: String

  enum CodingKeys: String, CodingKey {
    case name, description
    case sizeGB = "size_gb"
    case contextK = "context_k"
  }

  var sizeLabel: String {
    guard !sizeGB.isEmpty else { return "" }
    return "\(sizeGB) GB"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    name = (try? container.decode(String.self, forKey: .name)) ?? ""
    description = (try? container.decode(String.self, forKey: .description)) ?? ""
    sizeGB = container.decodeFlexibleString(forKey: .sizeGB)
    contextK = container.decodeFlexibleString(forKey: .contextK)
    id = name
  }
}

private struct ModelInstallStartResponse: Decodable {
  let success: Bool
  let job: ModelInstallJob
}

private struct ModelInstallStatusResponse: Decodable {
  let success: Bool
  let job: ModelInstallJob
}

private struct ModelInstallJob: Identifiable, Decodable, Hashable {
  let id: String
  let model: String
  let status: String
  let phase: String
  let progressPct: String
  let log: String

  enum CodingKeys: String, CodingKey {
    case id, model, status, phase, log
    case progressPct = "progress_pct"
  }

  var progressFraction: Double? {
    guard let value = Double(progressPct), value >= 0 else { return nil }
    return min(value / 100, 1)
  }

  var statusLabel: String {
    if status == "done" { return "installed" }
    if status == "failed" { return "failed" }
    if phase == "downloading", let progress = progressFraction {
      return "downloading \(Int(progress * 100))%"
    }
    if !phase.isEmpty && phase != "running" { return phase }
    return "installing"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = (try? container.decode(String.self, forKey: .id)) ?? ""
    model = (try? container.decode(String.self, forKey: .model)) ?? ""
    status = (try? container.decode(String.self, forKey: .status)) ?? ""
    phase = (try? container.decode(String.self, forKey: .phase)) ?? ""
    progressPct = container.decodeFlexibleString(forKey: .progressPct)
    log = (try? container.decode(String.self, forKey: .log)) ?? ""
  }
}

private struct LlmRuntimeSettingsResponse: Decodable {
  let success: Bool
  let useGpu: Bool
  let smartTitles: Bool
  let selectedDefaultModel: String
  let defaultModel: String

  enum CodingKeys: String, CodingKey {
    case success
    case useGpu = "use_gpu"
    case smartTitles = "smart_titles"
    case selectedDefaultModel = "selected_default_model"
    case defaultModel = "default_model"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    success = (try? container.decode(Bool.self, forKey: .success)) ?? true
    useGpu = container.decodeFlexibleBool(forKey: .useGpu)
    smartTitles = container.decodeFlexibleBool(forKey: .smartTitles)
    selectedDefaultModel = (try? container.decode(String.self, forKey: .selectedDefaultModel)) ?? ""
    defaultModel = (try? container.decode(String.self, forKey: .defaultModel)) ?? ""
  }
}

private struct RuntimeHealth: Decodable {
  let defaultModel: String
  let installedModelCount: Int

  enum CodingKeys: String, CodingKey {
    case defaultModel = "default_model"
    case installedModelCount = "installed_model_count"
  }
}

private struct ProjectsResponse: Decodable {
  let success: Bool
  let projects: [Project]
}

private struct ProjectMutationResponse: Decodable {
  let success: Bool
}

private struct GenericSuccessResponse: Decodable {
  let success: Bool
}

private struct GitStatusResponse: Decodable {
  let success: Bool
  let isRepo: Bool
  let branch: String
  let ahead: Int
  let behind: Int
  let added: Int
  let deleted: Int
  let changes: Int
  let stagedChanges: Int
  let unstagedChanges: Int

  enum CodingKeys: String, CodingKey {
    case success, branch, ahead, behind, added, deleted, changes
    case isRepo = "is_repo"
    case stagedChanges = "staged_changes"
    case unstagedChanges = "unstaged_changes"
  }

  var status: GitStatus {
    GitStatus(
      isRepo: isRepo,
      branch: branch,
      ahead: ahead,
      behind: behind,
      added: added,
      deleted: deleted,
      changes: changes,
      stagedChanges: stagedChanges,
      unstagedChanges: unstagedChanges
    )
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    success = (try? container.decode(Bool.self, forKey: .success)) ?? true
    isRepo = container.decodeFlexibleBool(forKey: .isRepo)
    branch = (try? container.decode(String.self, forKey: .branch)) ?? ""
    ahead = container.decodeFlexibleInt(forKey: .ahead)
    behind = container.decodeFlexibleInt(forKey: .behind)
    added = container.decodeFlexibleInt(forKey: .added)
    deleted = container.decodeFlexibleInt(forKey: .deleted)
    changes = container.decodeFlexibleInt(forKey: .changes)
    stagedChanges = container.decodeFlexibleInt(forKey: .stagedChanges)
    unstagedChanges = container.decodeFlexibleInt(forKey: .unstagedChanges)
  }
}

private struct GitStatus: Hashable {
  let isRepo: Bool
  let branch: String
  let ahead: Int
  let behind: Int
  let added: Int
  let deleted: Int
  let changes: Int
  let stagedChanges: Int
  let unstagedChanges: Int

  init(isRepo: Bool = false, branch: String = "", ahead: Int = 0, behind: Int = 0, added: Int = 0, deleted: Int = 0, changes: Int = 0, stagedChanges: Int = 0, unstagedChanges: Int = 0) {
    self.isRepo = isRepo
    self.branch = branch
    self.ahead = ahead
    self.behind = behind
    self.added = added
    self.deleted = deleted
    self.changes = changes
    self.stagedChanges = stagedChanges
    self.unstagedChanges = unstagedChanges
  }
}

private struct GitBranchesResponse: Decodable {
  let success: Bool
  let isRepo: Bool
  let branches: [GitBranch]

  enum CodingKeys: String, CodingKey {
    case success, branches
    case isRepo = "is_repo"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    success = (try? container.decode(Bool.self, forKey: .success)) ?? true
    isRepo = container.decodeFlexibleBool(forKey: .isRepo)
    branches = (try? container.decode([GitBranch].self, forKey: .branches)) ?? []
  }
}

private struct GitBranch: Identifiable, Decodable, Hashable {
  var id: String { name }
  let name: String
  let current: Bool

  enum CodingKeys: String, CodingKey {
    case name, current
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    name = (try? container.decode(String.self, forKey: .name)) ?? ""
    current = container.decodeFlexibleBool(forKey: .current)
  }
}

private struct GitDiffResponse: Decodable {
  let success: Bool
  let isRepo: Bool
  let added: Int
  let deleted: Int
  let diff: String

  enum CodingKeys: String, CodingKey {
    case success, added, deleted, diff
    case isRepo = "is_repo"
  }

  init(success: Bool = true, isRepo: Bool = false, added: Int = 0, deleted: Int = 0, diff: String = "") {
    self.success = success
    self.isRepo = isRepo
    self.added = added
    self.deleted = deleted
    self.diff = diff
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    success = (try? container.decode(Bool.self, forKey: .success)) ?? true
    isRepo = container.decodeFlexibleBool(forKey: .isRepo)
    added = container.decodeFlexibleInt(forKey: .added)
    deleted = container.decodeFlexibleInt(forKey: .deleted)
    diff = (try? container.decode(String.self, forKey: .diff)) ?? ""
  }
}

private struct GitOutputResponse: Decodable {
  let success: Bool
  let output: String
}

private struct GitBranchMutationResponse: Decodable {
  let success: Bool
  let branch: String
  let output: String
}

private struct QueueItemsResponse: Decodable {
  let success: Bool
  let items: [QueueItem]
}

private struct QueueItem: Identifiable, Decodable, Hashable {
  let id: String
  let order: String
  let prompt: String
  let runMode: String
  let computeBudget: String
  let commandExecMode: String
  let permissionMode: String

  enum CodingKeys: String, CodingKey {
    case id, order, prompt
    case runMode = "run_mode"
    case computeBudget = "compute_budget"
    case commandExecMode = "command_exec_mode"
    case permissionMode = "permission_mode"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = (try? container.decode(String.self, forKey: .id)) ?? UUID().uuidString
    order = (try? container.decode(String.self, forKey: .order)) ?? ""
    prompt = (try? container.decode(String.self, forKey: .prompt)) ?? ""
    runMode = (try? container.decode(String.self, forKey: .runMode)) ?? ""
    computeBudget = (try? container.decode(String.self, forKey: .computeBudget)) ?? ""
    commandExecMode = (try? container.decode(String.self, forKey: .commandExecMode)) ?? ""
    permissionMode = (try? container.decode(String.self, forKey: .permissionMode)) ?? ""
  }
}

private struct QueueCancelResponse: Decodable {
  let success: Bool
  let cancelled: Bool
}

private struct QueueStopResponse: Decodable {
  let success: Bool
  let stopped: Bool
  let forced: Bool
}

private struct TerminalSessionResponse: Decodable {
  let success: Bool
  let sessionID: String
  let sessionChanged: Bool
  let running: Bool
  let delta: String
  let offset: Int

  enum CodingKeys: String, CodingKey {
    case success, running, delta, offset
    case sessionID = "session_id"
    case sessionChanged = "session_changed"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    success = (try? container.decode(Bool.self, forKey: .success)) ?? true
    sessionID = (try? container.decode(String.self, forKey: .sessionID)) ?? ""
    sessionChanged = container.decodeFlexibleBool(forKey: .sessionChanged)
    running = container.decodeFlexibleBool(forKey: .running)
    delta = (try? container.decode(String.self, forKey: .delta)) ?? ""
    offset = container.decodeFlexibleInt(forKey: .offset)
  }
}

private struct Project: Identifiable, Decodable, Hashable {
  let id: String
  let name: String
  let path: String
  let pathExists: Bool
  let sessionCount: Int

  enum CodingKeys: String, CodingKey {
    case id, name, path
    case pathExists = "path_exists"
    case sessionCount = "session_count"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    name = (try? container.decode(String.self, forKey: .name)) ?? id
    path = (try? container.decode(String.self, forKey: .path)) ?? ""
    pathExists = container.decodeFlexibleBool(forKey: .pathExists)
    sessionCount = container.decodeFlexibleInt(forKey: .sessionCount)
  }
}

private struct SessionsResponse: Decodable {
  let success: Bool
  let sessions: [SessionSummary]
}

private struct SessionResponse: Decodable {
  let success: Bool
  let session: SessionDetail
}

private struct SessionSummary: Identifiable, Decodable, Hashable {
  let id: String
  let workspaceID: String
  let title: String
  let model: String
  let updated: Int
  let queue: QueueState

  enum CodingKeys: String, CodingKey {
    case id, title, model, updated, queue
    case workspaceID = "workspace_id"
  }

  init(id: String, workspaceID: String, title: String, model: String, updated: Int, queue: QueueState) {
    self.id = id
    self.workspaceID = workspaceID
    self.title = title
    self.model = model
    self.updated = updated
    self.queue = queue
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    workspaceID = (try? container.decode(String.self, forKey: .workspaceID)) ?? ""
    title = (try? container.decode(String.self, forKey: .title)) ?? id
    model = (try? container.decode(String.self, forKey: .model)) ?? ""
    updated = container.decodeFlexibleInt(forKey: .updated)
    queue = (try? container.decode(QueueState.self, forKey: .queue)) ?? QueueState()
  }
}

private struct SessionDetail: Identifiable, Decodable, Hashable {
  let id: String
  let workspaceID: String
  let title: String
  let model: String
  let updated: Int
  let queue: QueueState
  let decisionRequest: DecisionRequest?
  let approvalRequest: ApprovalRequest?
  let trace: RunTrace
  let messages: [Message]
  let draft: String

  enum CodingKeys: String, CodingKey {
    case id, title, model, updated, queue, messages, trace, draft
    case workspaceID = "workspace_id"
    case decisionRequest = "decision_request"
    case approvalRequest = "approval_request"
  }

  init(id: String, workspaceID: String, title: String, model: String, updated: Int, queue: QueueState, decisionRequest: DecisionRequest? = nil, approvalRequest: ApprovalRequest? = nil, trace: RunTrace = RunTrace(), messages: [Message], draft: String = "") {
    self.id = id
    self.workspaceID = workspaceID
    self.title = title
    self.model = model
    self.updated = updated
    self.queue = queue
    self.decisionRequest = decisionRequest
    self.approvalRequest = approvalRequest
    self.trace = trace
    self.messages = messages
    self.draft = draft
  }

  init(summary: SessionSummary, messages: [Message] = []) {
    self.init(
      id: summary.id,
      workspaceID: summary.workspaceID,
      title: summary.title,
      model: summary.model,
      updated: summary.updated,
      queue: summary.queue,
      decisionRequest: nil,
      approvalRequest: nil,
      trace: RunTrace(),
      messages: messages,
      draft: ""
    )
  }

  var summary: SessionSummary {
    SessionSummary(id: id, workspaceID: workspaceID, title: title, model: model, updated: updated, queue: queue)
  }

  var hasAttention: Bool {
    decisionRequest != nil || approvalRequest != nil
  }

  var latestRunEvent: RunEvent? {
    trace.events.reversed().first { event in
      event.hasDisplayContent
    }
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    workspaceID = (try? container.decode(String.self, forKey: .workspaceID)) ?? ""
    title = (try? container.decode(String.self, forKey: .title)) ?? id
    model = (try? container.decode(String.self, forKey: .model)) ?? ""
    updated = container.decodeFlexibleInt(forKey: .updated)
    queue = (try? container.decode(QueueState.self, forKey: .queue)) ?? QueueState()
    decisionRequest = try? container.decodeIfPresent(DecisionRequest.self, forKey: .decisionRequest)
    approvalRequest = try? container.decodeIfPresent(ApprovalRequest.self, forKey: .approvalRequest)
    trace = (try? container.decode(RunTrace.self, forKey: .trace)) ?? RunTrace()
    messages = (try? container.decode([Message].self, forKey: .messages)) ?? []
    draft = (try? container.decode(String.self, forKey: .draft)) ?? ""
  }
}

private struct QueueState: Decodable, Hashable {
  let pending: Int
  let running: Int
  let done: Int
  let lastStatus: String

  enum CodingKeys: String, CodingKey {
    case pending, running, done
    case lastStatus = "last_status"
  }

  init(pending: Int = 0, running: Int = 0, done: Int = 0, lastStatus: String = "") {
    self.pending = pending
    self.running = running
    self.done = done
    self.lastStatus = lastStatus
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    pending = container.decodeFlexibleInt(forKey: .pending)
    running = container.decodeFlexibleInt(forKey: .running)
    done = container.decodeFlexibleInt(forKey: .done)
    lastStatus = (try? container.decode(String.self, forKey: .lastStatus)) ?? ""
  }
}

private struct Message: Identifiable, Decodable, Hashable {
  let id = UUID()
  let role: String
  let content: String

  enum CodingKeys: String, CodingKey {
    case role, content
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    role = (try? container.decode(String.self, forKey: .role)) ?? "assistant"
    content = (try? container.decode(String.self, forKey: .content)) ?? ""
  }
}

private struct ApprovalRequest: Decodable, Hashable {
  let command: String
  let reason: String

  enum CodingKeys: String, CodingKey {
    case command, reason
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    command = (try? container.decode(String.self, forKey: .command)) ?? ""
    reason = (try? container.decode(String.self, forKey: .reason)) ?? ""
  }
}

private struct DecisionRequest: Decodable, Hashable {
  let question: String
  let options: [String]

  enum CodingKeys: String, CodingKey {
    case question, options
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    question = (try? container.decode(String.self, forKey: .question)) ?? ""
    options = (try? container.decode([String].self, forKey: .options)) ?? []
  }
}

private struct RunTrace: Decodable, Hashable {
  let activeStreamSession: String
  let runningEventID: String
  let runningStartedAt: String?
  let events: [RunEvent]

  enum CodingKeys: String, CodingKey {
    case activeStreamSession = "active_stream_session"
    case runningEventID = "running_event_id"
    case runningStartedAt = "running_started_at"
    case events
  }

  init(activeStreamSession: String = "", runningEventID: String = "", runningStartedAt: String? = nil, events: [RunEvent] = []) {
    self.activeStreamSession = activeStreamSession
    self.runningEventID = runningEventID
    self.runningStartedAt = runningStartedAt
    self.events = events
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    activeStreamSession = (try? container.decode(String.self, forKey: .activeStreamSession)) ?? ""
    runningEventID = (try? container.decode(String.self, forKey: .runningEventID)) ?? ""
    runningStartedAt = try? container.decodeIfPresent(String.self, forKey: .runningStartedAt)
    events = (try? container.decode([RunEvent].self, forKey: .events)) ?? []
  }
}

private struct RunEvent: Identifiable, Decodable, Hashable {
  let id: String
  let status: String
  let streamText: String
  let plan: String
  let assistant: String
  let gitStatus: String
  let gitDiff: String
  let failures: String
  let sessionLog: String
  let state: String
  let commands: [RunCommand]
  let taskStatus: RunTaskStatus?

  enum CodingKeys: String, CodingKey {
    case id, status, plan, assistant, failures, state, commands
    case streamText = "stream_text"
    case gitStatus = "git_status"
    case gitDiff = "git_diff"
    case sessionLog = "session_log"
    case taskStatus = "task_status"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = (try? container.decode(String.self, forKey: .id)) ?? UUID().uuidString
    status = (try? container.decode(String.self, forKey: .status)) ?? ""
    streamText = (try? container.decode(String.self, forKey: .streamText)) ?? ""
    plan = (try? container.decode(String.self, forKey: .plan)) ?? ""
    assistant = (try? container.decode(String.self, forKey: .assistant)) ?? ""
    gitStatus = (try? container.decode(String.self, forKey: .gitStatus)) ?? ""
    gitDiff = (try? container.decode(String.self, forKey: .gitDiff)) ?? ""
    failures = (try? container.decode(String.self, forKey: .failures)) ?? ""
    sessionLog = (try? container.decode(String.self, forKey: .sessionLog)) ?? ""
    state = (try? container.decode(String.self, forKey: .state)) ?? ""
    commands = (try? container.decode([RunCommand].self, forKey: .commands)) ?? []
    taskStatus = try? container.decodeIfPresent(RunTaskStatus.self, forKey: .taskStatus)
  }

  var hasDisplayContent: Bool {
    !status.isEmpty || !streamText.isEmpty || !plan.isEmpty || !assistant.isEmpty || hasGitChanges || !commands.isEmpty || !failures.isEmpty || (taskStatus?.total ?? 0) > 0
  }

  var hasGitChanges: Bool {
    !gitDiff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !gitStatus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var streamTextPreview: String {
    let trimmed = streamText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return assistant.trimmingCharacters(in: .whitespacesAndNewlines) }
    return trimmed
  }

  var changeSummary: RunChangeSummary {
    RunChangeSummary(statusText: gitStatus, diffText: gitDiff)
  }
}

private struct RunTaskStatus: Decodable, Hashable {
  let tasks: [RunTask]
  let completed: Int
  let total: Int
  let source: String

  enum CodingKeys: String, CodingKey {
    case tasks, completed, total, source
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let decodedTasks = (try? container.decode([RunTask].self, forKey: .tasks)) ?? []
    tasks = decodedTasks.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    let decodedCompleted = container.decodeFlexibleInt(forKey: .completed)
    completed = decodedCompleted > 0 ? decodedCompleted : tasks.filter(\.done).count
    let decodedTotal = container.decodeFlexibleInt(forKey: .total)
    total = decodedTotal > 0 ? decodedTotal : tasks.count
    source = (try? container.decode(String.self, forKey: .source)) ?? "backend"
  }

  var summaryText: String {
    "\(completed) out of \(total) task\(total == 1 ? "" : "s") completed"
  }
}

private struct RunTask: Identifiable, Decodable, Hashable {
  let id: String
  let text: String
  let status: String
  let done: Bool

  enum CodingKeys: String, CodingKey {
    case id, text, title, label, status, done
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let decodedID = (try? container.decode(String.self, forKey: .id)) ?? ""
    let decodedText = container.decodeFlexibleString(forKey: .text)
    let fallbackTitle = container.decodeFlexibleString(forKey: .title)
    let fallbackLabel = container.decodeFlexibleString(forKey: .label)
    text = !decodedText.isEmpty ? decodedText : (!fallbackTitle.isEmpty ? fallbackTitle : fallbackLabel)
    status = normalizedTaskStatus((try? container.decode(String.self, forKey: .status)) ?? "")
    done = container.decodeFlexibleBool(forKey: .done) || status == "done"
    id = decodedID.isEmpty ? text : decodedID
  }
}

private struct RunCommand: Decodable, Hashable {
  let command: String
  let status: String

  enum CodingKeys: String, CodingKey {
    case command, status
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    command = (try? container.decode(String.self, forKey: .command)) ?? ""
    status = (try? container.decode(String.self, forKey: .status)) ?? ""
  }
}

private struct RunChangeSummary: Hashable {
  let added: Int
  let deleted: Int
  let files: [String]

  init(statusText: String, diffText: String) {
    var nextAdded = 0
    var nextDeleted = 0
    var seen = Set<String>()
    var nextFiles: [String] = []
    for rawLine in diffText.split(separator: "\n", omittingEmptySubsequences: false) {
      let line = String(rawLine)
      if line.hasPrefix("diff --git ") {
        let parts = line.split(separator: " ")
        if let last = parts.last {
          let path = String(last).replacingOccurrences(of: "b/", with: "")
          if !path.isEmpty && !seen.contains(path) {
            seen.insert(path)
            nextFiles.append(path)
          }
        }
      } else if line.hasPrefix("+") && !line.hasPrefix("+++") {
        nextAdded += 1
      } else if line.hasPrefix("-") && !line.hasPrefix("---") {
        nextDeleted += 1
      }
    }
    if nextFiles.isEmpty {
      for rawLine in statusText.split(separator: "\n") {
        let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
        guard trimmed.count > 3 else { continue }
        let path = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        if !path.isEmpty && !seen.contains(path) {
          seen.insert(path)
          nextFiles.append(path)
        }
      }
    }
    added = nextAdded
    deleted = nextDeleted
    files = nextFiles
  }
}

private struct AutomationsResponse: Decodable {
  let success: Bool
  let automations: AutomationCollection
}

private struct AutomationCollection: Decodable {
  let items: [AutomationItem]
}

private struct AutomationItem: Identifiable, Decodable, Hashable {
  let id: String
  let name: String
  let workspaceID: String
  let workspaceName: String
  let conversationID: String
  let conversationTitle: String
  let prompt: String
  let scheduleKind: String
  let scheduleText: String
  let allowSelfReschedule: Bool
  let nextRunISO: String
  let runMode: String
  let computeBudget: String
  let commandExecMode: String
  let permissionMode: String
  let enabled: Bool
  let lastStatus: String
  let lastError: String

  enum CodingKeys: String, CodingKey {
    case id, name, prompt, enabled
    case workspaceID = "workspace_id"
    case workspaceName = "workspace_name"
    case conversationID = "conversation_id"
    case conversationTitle = "conversation_title"
    case scheduleKind = "schedule_kind"
    case scheduleText = "schedule_text"
    case allowSelfReschedule = "allow_self_reschedule"
    case nextRunISO = "next_run_iso"
    case runMode = "run_mode"
    case computeBudget = "compute_budget"
    case commandExecMode = "command_exec_mode"
    case permissionMode = "permission_mode"
    case lastStatus = "last_status"
    case lastError = "last_error"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = (try? container.decode(String.self, forKey: .id)) ?? UUID().uuidString
    name = (try? container.decode(String.self, forKey: .name)) ?? id
    workspaceID = (try? container.decode(String.self, forKey: .workspaceID)) ?? ""
    workspaceName = (try? container.decode(String.self, forKey: .workspaceName)) ?? ""
    conversationID = (try? container.decode(String.self, forKey: .conversationID)) ?? ""
    conversationTitle = (try? container.decode(String.self, forKey: .conversationTitle)) ?? ""
    prompt = (try? container.decode(String.self, forKey: .prompt)) ?? ""
    scheduleKind = (try? container.decode(String.self, forKey: .scheduleKind)) ?? ""
    scheduleText = (try? container.decode(String.self, forKey: .scheduleText)) ?? ""
    allowSelfReschedule = container.decodeFlexibleBool(forKey: .allowSelfReschedule)
    nextRunISO = (try? container.decode(String.self, forKey: .nextRunISO)) ?? ""
    runMode = (try? container.decode(String.self, forKey: .runMode)) ?? ""
    computeBudget = (try? container.decode(String.self, forKey: .computeBudget)) ?? ""
    commandExecMode = (try? container.decode(String.self, forKey: .commandExecMode)) ?? ""
    permissionMode = (try? container.decode(String.self, forKey: .permissionMode)) ?? ""
    enabled = container.decodeFlexibleBool(forKey: .enabled)
    lastStatus = (try? container.decode(String.self, forKey: .lastStatus)) ?? ""
    lastError = (try? container.decode(String.self, forKey: .lastError)) ?? ""
  }
}

private struct AutomationMutationResponse: Decodable {
  let success: Bool
}

private struct DaemonStatus: Decodable {
  let success: Bool
  let enabled: Bool
  let paused: Bool
  let status: String
  let method: String
  let stateRoot: String
  let logPath: String
  let taskPending: Int

  enum CodingKeys: String, CodingKey {
    case success, enabled, paused, status, method
    case stateRoot = "state_root"
    case logPath = "log_path"
    case taskPending = "task_pending"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    success = (try? container.decode(Bool.self, forKey: .success)) ?? true
    enabled = container.decodeFlexibleBool(forKey: .enabled)
    paused = container.decodeFlexibleBool(forKey: .paused)
    status = (try? container.decode(String.self, forKey: .status)) ?? "unknown"
    method = (try? container.decode(String.self, forKey: .method)) ?? "none"
    stateRoot = (try? container.decode(String.self, forKey: .stateRoot)) ?? ""
    logPath = (try? container.decode(String.self, forKey: .logPath)) ?? ""
    taskPending = container.decodeFlexibleInt(forKey: .taskPending)
  }
}

private struct DesktopPrefsResponse: Decodable {
  let success: Bool
  let backgroundMode: Bool
  let menuBarIcon: Bool
  let voiceAutomations: Bool
  let voiceRecognitionSound: Bool
  let voiceBuiltinCommands: Bool
  let voiceDictationCommands: Bool
  let voiceLlmPrompts: Bool
  let voiceLlmActions: Bool
  let voiceLocalAction1Name: String
  let voiceLocalAction1Command: String
  let voiceLocalAction1Phrases: String
  let voiceLocalAction2Name: String
  let voiceLocalAction2Command: String
  let voiceLocalAction2Phrases: String
  let themeID: String
  let mobileBridge: Bool
  let mobileTor: Bool
  let mobileLan: Bool
  let mobileAllowExecute: Bool
  let mobileAllowSelfActuation: Bool

  enum CodingKeys: String, CodingKey {
    case success
    case backgroundMode = "background_mode"
    case menuBarIcon = "menu_bar_icon"
    case voiceAutomations = "voice_automations"
    case voiceRecognitionSound = "voice_automation_sound"
    case voiceBuiltinCommands = "voice_builtin_commands"
    case voiceDictationCommands = "voice_dictation_commands"
    case voiceLlmPrompts = "voice_automation_llm_prompts"
    case voiceLlmActions = "voice_automation_llm_actions"
    case voiceLocalAction1Name = "voice_local_action_1_name"
    case voiceLocalAction1Command = "voice_local_action_1_command"
    case voiceLocalAction1Phrases = "voice_local_action_1_phrases"
    case voiceLocalAction2Name = "voice_local_action_2_name"
    case voiceLocalAction2Command = "voice_local_action_2_command"
    case voiceLocalAction2Phrases = "voice_local_action_2_phrases"
    case themeID = "theme_id"
    case mobileBridge = "mobile_bridge"
    case mobileTor = "mobile_tor"
    case mobileLan = "mobile_lan"
    case mobileAllowExecute = "mobile_allow_execute"
    case mobileAllowSelfActuation = "mobile_allow_self_actuation"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    success = (try? container.decode(Bool.self, forKey: .success)) ?? true
    backgroundMode = container.decodeFlexibleBool(forKey: .backgroundMode)
    menuBarIcon = container.decodeFlexibleBool(forKey: .menuBarIcon)
    voiceAutomations = container.decodeFlexibleBool(forKey: .voiceAutomations)
    voiceRecognitionSound = container.decodeFlexibleBool(forKey: .voiceRecognitionSound)
    voiceBuiltinCommands = container.decodeFlexibleBool(forKey: .voiceBuiltinCommands, defaultValue: true)
    voiceDictationCommands = container.decodeFlexibleBool(forKey: .voiceDictationCommands, defaultValue: true)
    voiceLlmPrompts = container.decodeFlexibleBool(forKey: .voiceLlmPrompts)
    voiceLlmActions = container.decodeFlexibleBool(forKey: .voiceLlmActions)
    voiceLocalAction1Name = (try? container.decode(String.self, forKey: .voiceLocalAction1Name)) ?? ""
    voiceLocalAction1Command = (try? container.decode(String.self, forKey: .voiceLocalAction1Command)) ?? ""
    voiceLocalAction1Phrases = (try? container.decode(String.self, forKey: .voiceLocalAction1Phrases)) ?? ""
    voiceLocalAction2Name = (try? container.decode(String.self, forKey: .voiceLocalAction2Name)) ?? ""
    voiceLocalAction2Command = (try? container.decode(String.self, forKey: .voiceLocalAction2Command)) ?? ""
    voiceLocalAction2Phrases = (try? container.decode(String.self, forKey: .voiceLocalAction2Phrases)) ?? ""
    themeID = (try? container.decode(String.self, forKey: .themeID)) ?? "system"
    mobileBridge = container.decodeFlexibleBool(forKey: .mobileBridge)
    mobileTor = container.decodeFlexibleBool(forKey: .mobileTor)
    mobileLan = container.decodeFlexibleBool(forKey: .mobileLan)
    mobileAllowExecute = container.decodeFlexibleBool(forKey: .mobileAllowExecute)
    mobileAllowSelfActuation = container.decodeFlexibleBool(forKey: .mobileAllowSelfActuation)
  }
}

private struct MobileBridgeStatus: Decodable {
  let success: Bool
  let enabled: Bool
  let running: Bool
  let bindHost: String
  let port: String
  let localURL: String
  let lanURL: String
  let torEnabled: Bool
  let torRunning: Bool
  let torAddress: String
  let pairingToken: String
  let allowExecute: Bool
  let allowSelfActuation: Bool
  let configFile: String
  let stateDir: String

  enum CodingKeys: String, CodingKey {
    case success, enabled, running, port
    case bindHost = "bind_host"
    case localURL = "local_url"
    case lanURL = "lan_url"
    case torEnabled = "tor_enabled"
    case torRunning = "tor_running"
    case torAddress = "tor_address"
    case pairingToken = "pairing_token"
    case allowExecute = "allow_execute"
    case allowSelfActuation = "allow_self_actuation"
    case configFile = "config_file"
    case stateDir = "state_dir"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    success = (try? container.decode(Bool.self, forKey: .success)) ?? true
    enabled = container.decodeFlexibleBool(forKey: .enabled)
    running = container.decodeFlexibleBool(forKey: .running)
    bindHost = (try? container.decode(String.self, forKey: .bindHost)) ?? "127.0.0.1"
    port = (try? container.decode(String.self, forKey: .port)) ?? "8765"
    localURL = (try? container.decode(String.self, forKey: .localURL)) ?? ""
    lanURL = (try? container.decode(String.self, forKey: .lanURL)) ?? ""
    torEnabled = container.decodeFlexibleBool(forKey: .torEnabled)
    torRunning = container.decodeFlexibleBool(forKey: .torRunning)
    torAddress = (try? container.decode(String.self, forKey: .torAddress)) ?? ""
    pairingToken = (try? container.decode(String.self, forKey: .pairingToken)) ?? ""
    allowExecute = container.decodeFlexibleBool(forKey: .allowExecute)
    allowSelfActuation = container.decodeFlexibleBool(forKey: .allowSelfActuation)
    configFile = (try? container.decode(String.self, forKey: .configFile)) ?? ""
    stateDir = (try? container.decode(String.self, forKey: .stateDir)) ?? ""
  }
}

private struct VoiceAutomationStatus: Decodable {
  let success: Bool
  let enabled: Bool
  let active: Bool
  let status: String
  let message: String
  let lastPhrase: String
  let lastAction: String
  let logPath: String

  enum CodingKeys: String, CodingKey {
    case success, enabled, active, status, message
    case lastPhrase = "last_phrase"
    case lastAction = "last_action"
    case logPath = "log_path"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    success = (try? container.decode(Bool.self, forKey: .success)) ?? true
    enabled = container.decodeFlexibleBool(forKey: .enabled)
    active = container.decodeFlexibleBool(forKey: .active)
    status = (try? container.decode(String.self, forKey: .status)) ?? "unknown"
    message = (try? container.decode(String.self, forKey: .message)) ?? ""
    lastPhrase = (try? container.decode(String.self, forKey: .lastPhrase)) ?? ""
    lastAction = (try? container.decode(String.self, forKey: .lastAction)) ?? ""
    logPath = (try? container.decode(String.self, forKey: .logPath)) ?? ""
  }
}

private struct OpenWebResponse: Decodable {
  let success: Bool
  let url: String
}

private struct APIErrorResponse: Decodable {
  let success: Bool
  let error: String

  enum CodingKeys: String, CodingKey {
    case success, error
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    success = (try? container.decode(Bool.self, forKey: .success)) ?? true
    error = (try? container.decode(String.self, forKey: .error)) ?? ""
  }
}

private struct AttachmentUploadResponse: Decodable {
  let success: Bool
  let attachment: PendingAttachment
}

private struct PendingAttachment: Identifiable, Decodable, Hashable {
  let id: String
  let name: String
  let mime: String
  let kind: String
  let size: Int

  var sizeLabel: String {
    if size >= 1_048_576 {
      return String(format: "%.1f MB", Double(size) / 1_048_576.0)
    }
    if size >= 1024 {
      return String(format: "%.0f KB", Double(size) / 1024.0)
    }
    return "\(size) B"
  }

  enum CodingKeys: String, CodingKey {
    case id, name, mime, kind, size
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = (try? container.decode(String.self, forKey: .id)) ?? UUID().uuidString
    name = (try? container.decode(String.self, forKey: .name)) ?? id
    mime = (try? container.decode(String.self, forKey: .mime)) ?? ""
    kind = (try? container.decode(String.self, forKey: .kind)) ?? "document"
    size = container.decodeFlexibleInt(forKey: .size)
  }
}

private struct DictationStatus: Decodable {
  let success: Bool
  let installed: Bool
  let backend: String
  let backendLabel: String
  let language: String

  enum CodingKeys: String, CodingKey {
    case success, installed, backend, language
    case backendLabel = "backend_label"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    success = (try? container.decode(Bool.self, forKey: .success)) ?? true
    installed = container.decodeFlexibleBool(forKey: .installed)
    backend = (try? container.decode(String.self, forKey: .backend)) ?? ""
    backendLabel = (try? container.decode(String.self, forKey: .backendLabel)) ?? backend
    language = (try? container.decode(String.self, forKey: .language)) ?? "auto"
  }
}

private struct DictationLanguageResponse: Decodable {
  let success: Bool
  let language: String
  let languages: [DictationLanguageOption]

  enum CodingKeys: String, CodingKey {
    case success, language, languages
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    success = (try? container.decode(Bool.self, forKey: .success)) ?? true
    language = (try? container.decode(String.self, forKey: .language)) ?? "auto"
    languages = (try? container.decode([DictationLanguageOption].self, forKey: .languages)) ?? [DictationLanguageOption(value: "auto", label: "Auto")]
  }
}

private struct DictationLanguageOption: Identifiable, Decodable, Hashable {
  let value: String
  let label: String

  var id: String { value }

  enum CodingKeys: String, CodingKey {
    case value, label
  }

  init(value: String, label: String) {
    self.value = value
    self.label = label
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    value = (try? container.decode(String.self, forKey: .value)) ?? "auto"
    label = (try? container.decode(String.self, forKey: .label)) ?? value
  }
}

private struct DictationPrewarmResponse: Decodable {
  let success: Bool
  let enabled: Bool

  enum CodingKeys: String, CodingKey {
    case success, enabled
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    success = (try? container.decode(Bool.self, forKey: .success)) ?? true
    enabled = container.decodeFlexibleBool(forKey: .enabled)
  }
}

private struct DictationShortcutsResponse: Decodable {
  let success: Bool
  let hold: String
  let toggle: String

  enum CodingKeys: String, CodingKey {
    case success, hold, toggle
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    success = (try? container.decode(Bool.self, forKey: .success)) ?? true
    hold = (try? container.decode(String.self, forKey: .hold)) ?? "none"
    toggle = (try? container.decode(String.self, forKey: .toggle)) ?? "none"
  }
}

private struct DictationInstallStartResponse: Decodable {
  let success: Bool
  let job: DictationInstallJob
}

private struct GitRuntimeSettingsResponse: Decodable {
  let success: Bool
  let workflowPolicy: String
  let ambiguityPolicy: String

  enum CodingKeys: String, CodingKey {
    case success
    case workflowPolicy = "workflow_policy"
    case ambiguityPolicy = "ambiguity_policy"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    success = (try? container.decode(Bool.self, forKey: .success)) ?? true
    workflowPolicy = (try? container.decode(String.self, forKey: .workflowPolicy)) ?? "managed"
    ambiguityPolicy = (try? container.decode(String.self, forKey: .ambiguityPolicy)) ?? "preserve"
  }
}

private struct SelfImproveSettingsResponse: Decodable {
  let success: Bool
  let selectedModel: String
  let runOptions: SelfImproveRunOptions
  let lastRun: SelfImproveLastRun
  let pluginInventory: SelfImprovePluginInventory

  enum CodingKeys: String, CodingKey {
    case success
    case selectedModel = "selected_model"
    case runOptions = "run_options"
    case lastRun = "last_run"
    case pluginInventory = "plugin_inventory"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    success = (try? container.decode(Bool.self, forKey: .success)) ?? true
    selectedModel = (try? container.decode(String.self, forKey: .selectedModel)) ?? ""
    runOptions = (try? container.decode(SelfImproveRunOptions.self, forKey: .runOptions)) ?? SelfImproveRunOptions()
    lastRun = (try? container.decode(SelfImproveLastRun.self, forKey: .lastRun)) ?? SelfImproveLastRun()
    pluginInventory = (try? container.decode(SelfImprovePluginInventory.self, forKey: .pluginInventory)) ?? SelfImprovePluginInventory()
  }
}

private struct SelfImproveRunResponse: Decodable {
  let success: Bool
  let selectedModel: String
  let runOptions: SelfImproveRunOptions
  let lastRun: SelfImproveLastRun
  let pluginInventory: SelfImprovePluginInventory

  enum CodingKeys: String, CodingKey {
    case success
    case selectedModel = "selected_model"
    case runOptions = "run_options"
    case lastRun = "last_run"
    case pluginInventory = "plugin_inventory"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    success = (try? container.decode(Bool.self, forKey: .success)) ?? true
    selectedModel = (try? container.decode(String.self, forKey: .selectedModel)) ?? ""
    runOptions = (try? container.decode(SelfImproveRunOptions.self, forKey: .runOptions)) ?? SelfImproveRunOptions()
    lastRun = (try? container.decode(SelfImproveLastRun.self, forKey: .lastRun)) ?? SelfImproveLastRun()
    pluginInventory = (try? container.decode(SelfImprovePluginInventory.self, forKey: .pluginInventory)) ?? SelfImprovePluginInventory()
  }
}

private struct SelfImproveRunOptionsResponse: Decodable {
  let success: Bool
  let runOptions: SelfImproveRunOptions

  enum CodingKeys: String, CodingKey {
    case success
    case runOptions = "run_options"
  }
}

private struct SelfImproveRunOptions: Decodable {
  let objective: String
  let competitionEnabled: Bool
  let challengerModel: String
  let codexWorkCheckEnabled: Bool
  let sources: SelfImproveSources

  enum CodingKeys: String, CodingKey {
    case objective
    case competitionEnabled = "competition_enabled"
    case challengerModel = "challenger_model"
    case codexWorkCheckEnabled = "codex_work_check_enabled"
    case sources
  }

  init(
    objective: String = "",
    competitionEnabled: Bool = true,
    challengerModel: String = "",
    codexWorkCheckEnabled: Bool = false,
    sources: SelfImproveSources = SelfImproveSources()
  ) {
    self.objective = objective
    self.competitionEnabled = competitionEnabled
    self.challengerModel = challengerModel
    self.codexWorkCheckEnabled = codexWorkCheckEnabled
    self.sources = sources
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    objective = (try? container.decode(String.self, forKey: .objective)) ?? ""
    competitionEnabled = container.decodeFlexibleBool(forKey: .competitionEnabled)
    challengerModel = (try? container.decode(String.self, forKey: .challengerModel)) ?? ""
    codexWorkCheckEnabled = container.decodeFlexibleBool(forKey: .codexWorkCheckEnabled)
    sources = (try? container.decode(SelfImproveSources.self, forKey: .sources)) ?? SelfImproveSources()
  }
}

private struct SelfImproveSources: Decodable {
  let papers: Bool
  let web: Bool
  let runtime: Bool
  let repo: Bool
  let platform: Bool

  enum CodingKeys: String, CodingKey {
    case papers, web, runtime, repo, platform
  }

  init(papers: Bool = true, web: Bool = true, runtime: Bool = true, repo: Bool = true, platform: Bool = true) {
    self.papers = papers
    self.web = web
    self.runtime = runtime
    self.repo = repo
    self.platform = platform
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    papers = container.decodeFlexibleBool(forKey: .papers)
    web = container.decodeFlexibleBool(forKey: .web)
    runtime = container.decodeFlexibleBool(forKey: .runtime)
    repo = container.decodeFlexibleBool(forKey: .repo)
    platform = container.decodeFlexibleBool(forKey: .platform)
  }
}

private struct SelfImproveLastRun: Decodable {
  let summary: String
  let generatedAt: String

  enum CodingKeys: String, CodingKey {
    case summary
    case generatedAt = "generated_at"
  }

  init(summary: String = "", generatedAt: String = "") {
    self.summary = summary
    self.generatedAt = generatedAt
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    summary = (try? container.decode(String.self, forKey: .summary)) ?? ""
    generatedAt = (try? container.decode(String.self, forKey: .generatedAt)) ?? ""
  }
}

private struct SelfImprovePluginInventory: Decodable {
  let activeCount: Int

  enum CodingKeys: String, CodingKey {
    case activeCount = "active_count"
  }

  init(activeCount: Int = 0) {
    self.activeCount = activeCount
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    activeCount = container.decodeFlexibleInt(forKey: .activeCount)
  }
}

private struct DictationInstallJob: Decodable {
  let id: String
  let status: String
  let phase: String

  enum CodingKeys: String, CodingKey {
    case id, status, phase
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = (try? container.decode(String.self, forKey: .id)) ?? ""
    status = (try? container.decode(String.self, forKey: .status)) ?? ""
    phase = (try? container.decode(String.self, forKey: .phase)) ?? ""
  }
}

private struct DictationInstallStatusResponse: Decodable {
  let success: Bool
  let job: DictationInstallStatusJob
}

private struct DictationInstallStatusJob: Decodable {
  let status: String
  let phase: String
  let progressPct: String

  enum CodingKeys: String, CodingKey {
    case status, phase
    case progressPct = "progress_pct"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    status = (try? container.decode(String.self, forKey: .status)) ?? "unknown"
    phase = (try? container.decode(String.self, forKey: .phase)) ?? status
    if let value = try? container.decode(String.self, forKey: .progressPct) {
      progressPct = value
    } else if let value = try? container.decode(Int.self, forKey: .progressPct) {
      progressPct = String(value)
    } else {
      progressPct = ""
    }
  }
}

private struct DictationStartResponse: Decodable {
  let success: Bool
  let session: DictationSession
}

private struct DictationSession: Decodable {
  let id: String
  let status: String
  let backend: String
}

private struct DictationStopResponse: Decodable {
  let success: Bool
  let sessionID: String
  let text: String
  let backend: String

  enum CodingKeys: String, CodingKey {
    case success, text, backend
    case sessionID = "session_id"
  }
}

private struct DictationTranscribeResponse: Decodable {
  let success: Bool
  let text: String
  let backend: String
}

private struct DictationLevelsResponse: Decodable {
  let success: Bool
  let level: Double
  let levels: [Double]
  let sessionID: String

  enum CodingKeys: String, CodingKey {
    case success, level, levels
    case sessionID = "session_id"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    success = (try? container.decode(Bool.self, forKey: .success)) ?? true
    level = container.decodeFlexibleDouble(forKey: .level)
    levels = (try? container.decode([Double].self, forKey: .levels)) ?? []
    sessionID = (try? container.decode(String.self, forKey: .sessionID)) ?? ""
  }
}

private func parseLaunchDesktopPrefs(_ content: String) -> [String: String] {
  var prefs: [String: String] = [:]
  for rawLine in content.components(separatedBy: .newlines) {
    let line = rawLine.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
    guard !line.isEmpty, let separator = line.firstIndex(of: "=") else {
      continue
    }
    let key = String(line[..<separator])
    let value = String(line[line.index(after: separator)...])
    prefs[key] = value
  }
  return prefs
}

private func desktopLaunchBool(_ value: String) -> Bool {
  ["1", "true", "yes", "on", "enabled"].contains(value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
}

private extension KeyedDecodingContainer {
  func decodeFlexibleString(forKey key: Key) -> String {
    if let value = try? decode(String.self, forKey: key) { return value }
    if let value = try? decode(Int.self, forKey: key) { return String(value) }
    if let value = try? decode(Double.self, forKey: key) { return String(value) }
    if let value = try? decode(Bool.self, forKey: key) { return value ? "1" : "0" }
    return ""
  }

  func decodeFlexibleInt(forKey key: Key) -> Int {
    if let value = try? decode(Int.self, forKey: key) { return value }
    if let value = try? decode(String.self, forKey: key), let intValue = Int(value) { return intValue }
    if let value = try? decode(Bool.self, forKey: key) { return value ? 1 : 0 }
    return 0
  }

  func decodeFlexibleDouble(forKey key: Key) -> Double {
    if let value = try? decode(Double.self, forKey: key) { return value }
    if let value = try? decode(Int.self, forKey: key) { return Double(value) }
    if let value = try? decode(String.self, forKey: key), let doubleValue = Double(value) { return doubleValue }
    return 0
  }

  func decodeFlexibleBool(forKey key: Key, defaultValue: Bool = false) -> Bool {
    if let value = try? decode(Bool.self, forKey: key) { return value }
    if let value = try? decode(Int.self, forKey: key) { return value != 0 }
    if let value = try? decode(String.self, forKey: key) {
      return ["1", "true", "yes", "enabled", "ready"].contains(value.lowercased())
    }
    return defaultValue
  }
}
