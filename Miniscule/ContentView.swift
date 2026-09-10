// 
//  ContentView.swift
//  Miniscule
//

import SwiftUI
import SwiftTerm
import AppKit
import ServiceManagement

// MARK: - CWD helper (proc_pidinfo, no bridging header needed)

@_silgen_name("proc_pidinfo")
private func __proc_pidinfo(
    _ pid: Int32, _ flavor: Int32, _ arg: UInt64,
    _ buffer: UnsafeMutableRawPointer?, _ buffersize: Int32
) -> Int32

/// Returns the cwd of the given process via PROC_PIDVNODEPATHINFO (flavor 9).
/// Struct layout on 64-bit macOS: vnode_info = 152 bytes → path starts at offset 152.
private func cwdForPid(_ pid: pid_t) -> String? {
    guard pid > 0 else { return nil }
    let bufferSize = 2352
    let pathOffset  = 152
    var buffer = [UInt8](repeating: 0, count: bufferSize)
    let ret = buffer.withUnsafeMutableBytes { ptr in
        __proc_pidinfo(pid, 9, 0, ptr.baseAddress, Int32(bufferSize))
    }
    guard ret > 0 else { return nil }
    return buffer.withUnsafeBytes { ptr in
        let p = ptr.baseAddress!.advanced(by: pathOffset).assumingMemoryBound(to: CChar.self)
        let s = String(cString: p)
        return s.isEmpty ? nil : s
    }
}

// MARK: - TerminalApp

fileprivate struct TerminalApp: Identifiable {
    let name: String
    let bundleId: String
    var id: String { bundleId }
    var url: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) }
    var isInstalled: Bool { url != nil }
}

fileprivate let knownTerminals: [TerminalApp] = [
    TerminalApp(name: "Terminal",  bundleId: "com.apple.Terminal"),
    TerminalApp(name: "iTerm2",    bundleId: "com.googlecode.iterm2"),
    TerminalApp(name: "Ghostty",   bundleId: "com.mitchellh.ghostty"),
    TerminalApp(name: "Warp",      bundleId: "dev.warp.Warp-Stable"),
    TerminalApp(name: "Alacritty", bundleId: "io.alacritty"),
]

// MARK: - TerminalProcessDelegate

fileprivate final class TerminalProcessDelegate: NSObject, LocalProcessTerminalViewDelegate {
    var currentDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path
    var onDirectoryChange: ((String) -> Void)?

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        guard let dir = directory, !dir.isEmpty else { return }
        if let url = URL(string: dir), url.scheme == "file" {
            currentDirectory = url.path
        } else {
            currentDirectory = dir
        }
        onDirectoryChange?(currentDirectory)
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {}
}

// MARK: - TerminalTab

/// One terminal session. Created only by TerminalStore.
@Observable
final class TerminalTab: Identifiable {
    let id = UUID()

    @ObservationIgnored let terminalView: LocalProcessTerminalView
    @ObservationIgnored fileprivate let processDelegate: TerminalProcessDelegate

    var title: String = "~"

    @ObservationIgnored private var cwdTimer: Timer?

    fileprivate init(theme: TerminalTheme, fontSize: CGFloat, opacity: Double = 1.0) {
        terminalView    = LocalProcessTerminalView(frame: .zero)
        processDelegate = TerminalProcessDelegate()

        terminalView.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        terminalView.processDelegate = processDelegate

        let shell   = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        var env     = ProcessInfo.processInfo.environment
        env["TERM"]      = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        let envList = env.map { "\($0.key)=\($0.value)" }
        let home    = FileManager.default.homeDirectoryForCurrentUser.path
        terminalView.startProcess(executable: shell, args: ["-l"],
                                  environment: envList, currentDirectory: home)
        applyTheme(theme, opacity: opacity)

        // Poll cwd every second via proc_pidinfo — reliable regardless of shell config.
        cwdTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let pid = self.terminalView.process.shellPid
            guard let dir = cwdForPid(pid) else { return }
            let name = URL(fileURLWithPath: dir).lastPathComponent
            let label = name.isEmpty ? "~" : name
            if self.title != label {
                DispatchQueue.main.async { self.title = label }
            }
        }
    }

    deinit { cwdTimer?.invalidate() }

    fileprivate func applyTheme(_ theme: TerminalTheme, opacity: Double = 1.0) {
        // Always use a fully transparent background on the SwiftTerm view itself.
        // The visible background color + opacity are rendered by the SwiftUI ZStack
        // layer beneath, which lets the opacity slider and glass effect work correctly.
        terminalView.nativeBackgroundColor = .clear
        terminalView.nativeForegroundColor = theme.foreground
        terminalView.installColors(theme.makeSwiftTermColors())
        // SwiftTerm's built-in NSScroller draws its knob from the effective appearance,
        // not the theme color, so a dark scroller on a light custom background (or vice
        // versa) becomes unreadable unless we force it to match here.
        terminalView.appearance = NSAppearance(named: theme.background.isLightColor ? .aqua : .darkAqua)
    }
}

// MARK: - WindowSize

enum WindowSize: String, CaseIterable, Identifiable {
    case mini   = "mini"
    case medium = "medium"
    case large  = "large"
    case full   = "full"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .mini:   return "S"
        case .medium: return "M"
        case .large:  return "L"
        case .full:   return "F"
        }
    }

    var helpText: String {
        switch self {
        case .mini:   return "Mini (400 × 240)"
        case .medium: return "Medium (620 × 420)"
        case .large:  return "Large (820 × 540)"
        case .full:   return "Full Screen"
        }
    }

    var terminalSize: CGSize {
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 877)
        switch self {
        case .mini:
            return CGSize(width: min(400, screen.width * 0.9), height: min(240, screen.height * 0.9))
        case .medium:
            return CGSize(width: min(620, screen.width * 0.9), height: min(420, screen.height * 0.9))
        case .large:
            return CGSize(width: min(820, screen.width * 0.9), height: min(540, screen.height * 0.9))
        case .full:
            let width  = min(screen.width * 0.65, 1000)
            let height = screen.height * 0.85 - 36
            return CGSize(width: width, height: height)
        }
    }
}

// MARK: - TerminalStore

@Observable
final class TerminalStore {
    var tabs: [TerminalTab] = []
    var activeTabIndex: Int = 0

    var activeTab: TerminalTab { tabs[min(activeTabIndex, tabs.count - 1)] }

    /// Whether the active background reads as light — used to pick toolbar chrome that
    /// stays visible against an arbitrary theme background, independent of system
    /// light/dark mode (a Solarized Light user wants light chrome even in system dark mode).
    var isLightBackground: Bool {
        let bg = currentTheme.id == "custom" ? customBackground : currentTheme.background
        return bg.isLightColor
    }

    var currentTheme: TerminalTheme {
        didSet {
            UserDefaults.standard.set(currentTheme.id, forKey: "themeId")
            tabs.forEach { $0.applyTheme(currentTheme, opacity: backgroundOpacity) }
        }
    }

    var fontSize: CGFloat {
        didSet {
            UserDefaults.standard.set(Double(fontSize), forKey: "fontSize")
            tabs.forEach {
                $0.terminalView.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
            }
        }
    }

    var windowSize: WindowSize {
        didSet { UserDefaults.standard.set(windowSize.rawValue, forKey: "windowSize") }
    }

    /// 0.0 = fully transparent background, 1.0 = fully opaque.
    var backgroundOpacity: Double {
        didSet { UserDefaults.standard.set(backgroundOpacity, forKey: "backgroundOpacity") }
    }

    var customBackground: NSColor {
        didSet {
            saveColor(customBackground, forKey: "customBackground")
            if currentTheme.id == "custom" {
                currentTheme = .custom(background: customBackground, foreground: customForeground)
            }
        }
    }

    var customForeground: NSColor {
        didSet {
            saveColor(customForeground, forKey: "customForeground")
            if currentTheme.id == "custom" {
                currentTheme = .custom(background: customBackground, foreground: customForeground)
            }
        }
    }

    var hasSeenWelcome: Bool = false

    init() {
        let savedId      = UserDefaults.standard.string(forKey: "themeId") ?? "classic"
        let savedFontSz  = CGFloat(UserDefaults.standard.double(forKey: "fontSize"))
        let size         = savedFontSz > 0 ? savedFontSz : 12
        let savedWinId   = UserDefaults.standard.string(forKey: "windowSize") ?? "medium"
        let savedWinSize = WindowSize(rawValue: savedWinId) ?? .medium
        let savedOpacity = UserDefaults.standard.object(forKey: "backgroundOpacity") as? Double ?? 1.0
        let savedBg      = TerminalStore.loadColor(forKey: "customBackground") ?? .init(hex: 0x1C1C1C)
        let savedFg      = TerminalStore.loadColor(forKey: "customForeground") ?? .init(hex: 0xF0F0F0)

        customBackground = savedBg
        customForeground = savedFg

        let savedTheme: TerminalTheme
        if savedId == "custom" {
            savedTheme = .custom(background: savedBg, foreground: savedFg)
        } else {
            savedTheme = TerminalTheme.all.first(where: { $0.id == savedId }) ?? .classic
        }

        currentTheme      = savedTheme
        fontSize          = size
        windowSize        = savedWinSize
        backgroundOpacity = savedOpacity
        tabs              = [TerminalTab(theme: savedTheme, fontSize: size)]
    }

    private func saveColor(_ color: NSColor, forKey key: String) {
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: false) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private static func loadColor(forKey key: String) -> NSColor? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data)
    }

    func addTab() {
        tabs.append(TerminalTab(theme: currentTheme, fontSize: fontSize, opacity: backgroundOpacity))
        activeTabIndex = tabs.count - 1
    }

    func removeTab(at index: Int) {
        guard tabs.count > 1 else { return }
        tabs.remove(at: index)
        if activeTabIndex >= tabs.count { activeTabIndex = tabs.count - 1 }
    }

    fileprivate var installedTerminals: [TerminalApp] {
        knownTerminals.filter(\.isInstalled)
    }

    fileprivate func openCurrentDirectory(in terminal: TerminalApp) {
        guard let appURL = terminal.url else { return }
        let shellPid = activeTab.terminalView.process.shellPid
        let dir = cwdForPid(shellPid) ?? activeTab.processDelegate.currentDirectory

        if terminal.bundleId == "com.mitchellh.ghostty" {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            task.arguments = ["-n", "-a", appURL.path, "--args",
                              "--working-directory=\(dir)"]
            try? task.run()
        } else {
            let dirURL = URL(fileURLWithPath: dir)
            NSWorkspace.shared.open([dirURL], withApplicationAt: appURL,
                                     configuration: .init(), completionHandler: nil)
        }
    }
}

// MARK: - WindowPinController

/// Keeps the MenuBarExtra window on top of other windows when pinned.
/// The system normally hides the window the moment it loses focus; when
/// pinned we float it and re-order it front whenever it tries to go away.
@Observable
final class WindowPinController {
    var isPinned: Bool = false {
        didSet { apply() }
    }

    @ObservationIgnored private weak var window: NSWindow?
    @ObservationIgnored private var resignObserver: Any?
    @ObservationIgnored private var defaultLevel: NSWindow.Level = .statusBar

    func attach(_ window: NSWindow) {
        guard self.window !== window else { return }
        self.window = window
        defaultLevel = window.level

        if let observer = resignObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: window, queue: .main
        ) { [weak self] _ in
            guard let self, self.isPinned, let window = self.window else { return }
            // The system orders the panel out right after resign — bring it back.
            DispatchQueue.main.async { window.orderFrontRegardless() }
        }
        apply()
    }

    private func apply() {
        guard let window else { return }
        if isPinned {
            window.level = .floating
            window.hidesOnDeactivate = false
            window.collectionBehavior.insert([.canJoinAllSpaces, .fullScreenAuxiliary])
            window.orderFrontRegardless()
        } else {
            window.level = defaultLevel
        }
    }

    deinit {
        if let observer = resignObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

// MARK: - WindowAccessor

/// Invisible view that hands the hosting NSWindow to a callback.
private struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window { onWindow(window) }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window { onWindow(window) }
        }
    }
}

// MARK: - ContentView

struct ContentView: View {
    @Environment(TerminalStore.self) var store
    @State private var showSettings = false
    @State private var showOpenMenu = false
    @State private var pinController = WindowPinController()

    var body: some View {
        ZStack {
            if store.hasSeenWelcome {
                terminalContent
                    .transition(.opacity)
            } else {
                WelcomeView(size: store.windowSize.terminalSize) {
                    store.hasSeenWelcome = true
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: store.hasSeenWelcome)
        .background(WindowAccessor { pinController.attach($0) })
    }

    // MARK: Terminal content

    private var terminalContent: some View {
        let ts = store.windowSize.terminalSize
        return VStack(spacing: 0) {
            toolbar
            ZStack {
                // Read customBackground directly so SwiftUI re-renders on every change.
                // (TerminalTheme equality is id-only, so "custom" → "custom" would be skipped.)
                let bg = store.currentTheme.id == "custom"
                    ? store.customBackground
                    : store.currentTheme.background
                Color(bg)
                    .opacity(store.backgroundOpacity)
                TerminalWrapper(view: store.activeTab.terminalView)
                    .id(store.activeTab.id)
                    .padding(8)
            }
            .frame(width: ts.width, height: ts.height)
        }
        .animation(.spring(duration: 0.35, bounce: 0.1), value: store.windowSize)
        .onAppear { focusActiveTab() }
        .onChange(of: store.activeTabIndex) { _, _ in focusActiveTab() }
    }

    private var toolbarIcon: NSImage {
        guard let icon = NSImage(named: "Miniscule Menu Icon") else {
            return NSImage(systemSymbolName: "terminal", accessibilityDescription: nil) ?? NSImage()
        }
        let size = NSSize(width: 14, height: 14)
        let scaled = NSImage(size: size, flipped: false) { rect in
            icon.draw(in: rect, from: .zero, operation: .copy, fraction: 1.0)
            return true
        }
        scaled.isTemplate = true
        return scaled
    }

    /// Chrome color for elements drawn directly against the terminal theme's
    /// background (e.g. the toolbar), which is independent of system light/dark mode.
    private func toolbarChrome(_ opacity: Double) -> SwiftUI.Color {
        (store.isLightBackground ? SwiftUI.Color.black : SwiftUI.Color.white).opacity(opacity)
    }

    private var toolbarPrimary: SwiftUI.Color { toolbarChrome(0.85) }
    private var toolbarSecondary: SwiftUI.Color { toolbarChrome(0.5) }

    /// Bakes `color` into an SF Symbol's pixels and marks it non-template.
    /// `Menu`'s borderless-button label on macOS ignores `.foregroundStyle`
    /// and always recolors template images to the system label color, so a
    /// plain `Image(systemName:)` inside `openButton`'s dropdown case would
    /// keep flipping to system-appearance black/white instead of matching
    /// the terminal theme. Pre-tinting sidesteps that recoloring entirely.
    private func tintedSymbol(_ name: String, pointSize: CGFloat, weight: NSFont.Weight, color: SwiftUI.Color) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return NSImage() }
        let tinted = NSImage(size: symbol.size, flipped: false) { rect in
            NSColor(color).set()
            rect.fill()
            symbol.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1.0)
            return true
        }
        tinted.isTemplate = false
        return tinted
    }

    private func focusActiveTab() {
        DispatchQueue.main.async {
            let tv = store.activeTab.terminalView
            tv.window?.makeFirstResponder(tv)
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        let ts   = store.windowSize.terminalSize
        let mini = store.windowSize == .mini
        return HStack(spacing: 0) {

            // App icon + title
            HStack(spacing: 5) {
                Image(nsImage: toolbarIcon)
                    .renderingMode(.template)
                if !mini {
                    Text("Miniscule")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                }
            }
            .foregroundStyle(toolbarSecondary)
            .padding(.leading, 10)
            .padding(.trailing, 6)

            // Tabs
            HStack(spacing: 2) {
                ForEach(Array(store.tabs.enumerated()), id: \.element.id) { index, tab in
                    tabPill(index: index, tab: tab)
                }
            }

            // New tab
            Button { store.addTab() } label: {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 24, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(toolbarSecondary)
            .help("New Tab")
            .padding(.leading, 2)

            Spacer(minLength: 4)

            // Open in external terminal
            openButton

            // Lock (keep window on top)
            Button { pinController.isPinned.toggle() } label: {
                Image(systemName: pinController.isPinned ? "lock.fill" : "lock.open")
                    .font(.system(size: 10, weight: .medium))
                    .frame(width: 26, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(pinController.isPinned ? Color.accentColor : toolbarSecondary)
            .help(pinController.isPinned
                  ? "Unlock — Miniscule hides when you click away"
                  : "Lock — keep Miniscule on top of other windows")

            // Settings
            Button { showSettings.toggle() } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 10, weight: .medium))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(toolbarSecondary)
            .help("Settings")
            .popover(isPresented: $showSettings, arrowEdge: .top) {
                SettingsView()
                    .environment(store)
            }

            Spacer().frame(width: 4)
        }
        .frame(width: ts.width, height: 36)
        .background {
            let bg = store.currentTheme.id == "custom"
                ? store.customBackground
                : store.currentTheme.background
            Color(bg).opacity(max(store.backgroundOpacity, 0.15))
        }
    }

    private func tabPill(index: Int, tab: TerminalTab) -> some View {
        let isActive = index == store.activeTabIndex
        return HStack(spacing: 3) {
            Text(tab.title)
                .font(.system(size: 10, design: .monospaced))
                .lineLimit(1)
                .frame(maxWidth: 72)
            if store.tabs.count > 1 {
                Button {
                    store.removeTab(at: index)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .bold))
                        .frame(width: 12, height: 12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(isActive ? 0.8 : 0.4)
            }
        }
        .padding(.horizontal, 7)
        .frame(height: 22)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isActive ? toolbarChrome(0.12) : toolbarChrome(0.03))
        )
        .foregroundStyle(isActive ? toolbarPrimary : toolbarSecondary)
        .contentShape(Rectangle())
        .onTapGesture { store.activeTabIndex = index }
        .animation(.spring(duration: 0.2), value: isActive)
    }

    @ViewBuilder
    private var openButton: some View {
        let installed = store.installedTerminals
        if !installed.isEmpty {
            let openIcon = tintedSymbol("arrow.up.right.square", pointSize: 10, weight: .medium, color: toolbarSecondary)
            if installed.count == 1 {
                Button { store.openCurrentDirectory(in: installed[0]) } label: {
                    Image(nsImage: openIcon)
                        .renderingMode(.original)
                        .frame(width: 26, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open in \(installed[0].name)")
            } else {
                // A SwiftUI `Menu` draws its own disclosure chevron via
                // AppKit's NSPopUpButton cell, which — like `Menu`'s label —
                // ignores `.foregroundStyle` and always renders in the
                // system label color. Building the dropdown from a plain
                // `Button` + `.popover` instead lets us draw a chevron from
                // the same pre-tinted-pixels path as the rest of the toolbar.
                let chevronIcon = tintedSymbol("chevron.down", pointSize: 7, weight: .bold, color: toolbarSecondary)
                Button { showOpenMenu.toggle() } label: {
                    HStack(spacing: 2) {
                        Image(nsImage: openIcon)
                            .renderingMode(.original)
                        Image(nsImage: chevronIcon)
                            .renderingMode(.original)
                    }
                    .frame(width: 34, height: 28)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open in terminal…")
                .popover(isPresented: $showOpenMenu, arrowEdge: .top) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(installed) { app in
                            Button {
                                store.openCurrentDirectory(in: app)
                                showOpenMenu = false
                            } label: {
                                Text(app.name)
                                    .font(.system(size: 12))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                        }
                    }
                    .frame(minWidth: 160)
                    .padding(.vertical, 4)
                }
            }
            toolbarDivider
        }
    }

    private var toolbarDivider: some View {
        Divider()
            .frame(height: 14)
            .padding(.horizontal, 4)
    }
}

// MARK: - WelcomeView

struct WelcomeView: View {
    var size: CGSize
    var onDismiss: () -> Void

    @State private var showContent = false
    @State private var typedText   = ""
    @State private var cursorOn    = true
    @State private var typingTask: Task<Void, Never>? = nil

    private let commands = [
        "git status",
        "npm run dev",
        "ls -la",
        "python3 manage.py runserver",
        "docker ps",
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                Image(nsImage: {
                    guard let icon = NSImage(named: "Miniscule Menu Icon") else {
                        return NSImage(systemSymbolName: "terminal.fill", accessibilityDescription: nil) ?? NSImage()
                    }
                    let size = NSSize(width: 72, height: 72)
                    let scaled = NSImage(size: size, flipped: false) { rect in
                        icon.draw(in: rect, from: .zero, operation: .copy, fraction: 1.0)
                        return true
                    }
                    scaled.isTemplate = false
                    return scaled
                }())
                .renderingMode(.original)
                .opacity(showContent ? 1 : 0)
                .scaleEffect(showContent ? 1 : 0.8)

                VStack(spacing: 6) {
                    Text("Miniscule")
                        .font(.system(size: 30, weight: .bold, design: .monospaced))
                    Text("Your terminal, right in the menu bar.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .opacity(showContent ? 1 : 0)

                HStack(spacing: 0) {
                    Text("% ")
                        .foregroundStyle(.green)
                    Text(typedText)
                    Rectangle()
                        .frame(width: 7, height: 14)
                        .opacity(cursorOn ? 1 : 0)
                }
                .font(.system(size: 13, design: .monospaced))
                .frame(width: min(size.width - 80, 280), alignment: .leading)
                .opacity(showContent ? 1 : 0)
            }

            Spacer()

            Button("Open Terminal  →") {
                typingTask?.cancel()
                onDismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.bottom, 36)
            .opacity(showContent ? 1 : 0)
        }
        .frame(width: size.width, height: size.height + 36)
        .onAppear {
            withAnimation(.spring(duration: 0.7, bounce: 0.3)) { showContent = true }
            typingTask = Task { await runTypingLoop() }
            Task { await blinkCursor() }
        }
        .onDisappear { typingTask?.cancel() }
    }

    private func runTypingLoop() async {
        try? await Task.sleep(for: .milliseconds(700))
        while !Task.isCancelled {
            for command in commands {
                if Task.isCancelled { return }
                for char in command {
                    if Task.isCancelled { return }
                    typedText.append(char)
                    try? await Task.sleep(for: .milliseconds(75))
                }
                try? await Task.sleep(for: .milliseconds(1100))
                while !typedText.isEmpty {
                    if Task.isCancelled { return }
                    typedText.removeLast()
                    try? await Task.sleep(for: .milliseconds(35))
                }
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
    }

    private func blinkCursor() async {
        while true {
            try? await Task.sleep(for: .milliseconds(500))
            withAnimation(.linear(duration: 0.01)) { cursorOn.toggle() }
        }
    }
}

// MARK: - TerminalWrapper

struct TerminalWrapper: NSViewRepresentable {
    let view: LocalProcessTerminalView

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        // Allow the Metal layer to composite transparently over whatever is behind it.
        view.layer?.isOpaque = false
        view.layer?.backgroundColor = NSColor.clear.cgColor
        return view
    }
    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {}
}
