//
//  SettingsView.swift
//  Miniscule
//

import SwiftUI
import AppKit
import ServiceManagement

// MARK: - SettingsView

struct SettingsView: View {
    @Environment(TerminalStore.self) var store

    @State private var isQuitHovering = false

    private var isCustomTheme: Bool { store.currentTheme.id == "custom" }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            sectionHeader("Appearance")
            card {
                VStack(alignment: .leading, spacing: 14) {
                    themeRow

                    if isCustomTheme {
                        customColorRows
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .top)),
                                removal: .opacity
                            ))
                    }

                    row("Opacity") { opacityControl }
                    row("Font Size") { fontSizeControl }
                }
            }

            sectionHeader("Window")
            card {
                VStack(alignment: .leading, spacing: 14) {
                    row("Size") { windowSizePicker }
                    row("Open at Login") { loginToggle }
                }
            }

            Divider()
            quitFooter
        }
        .padding(16)
        .frame(width: 320)
        .animation(.spring(duration: 0.25, bounce: 0.15), value: isCustomTheme)
    }

    // MARK: Appearance controls

    private var themeRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Theme")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                ForEach(TerminalTheme.all) { theme in
                    let isActive = theme.id == store.currentTheme.id
                    Button { store.currentTheme = theme } label: {
                        Circle()
                            .fill(theme.swatch)
                            .frame(width: 18, height: 18)
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.primary.opacity(isActive ? 0.9 : 0),
                                                  lineWidth: 1.5)
                                    .padding(-2)
                            )
                    }
                    .buttonStyle(.plain)
                    .animation(.spring(duration: 0.2), value: isActive)
                }

                // Custom theme swatch — half bg / half fg split circle
                Button {
                    store.currentTheme = .custom(
                        background: store.customBackground,
                        foreground: store.customForeground
                    )
                } label: {
                    ZStack {
                        SwiftUI.Color(store.customBackground)
                        HStack(spacing: 0) {
                            SwiftUI.Color.clear.frame(width: 9)
                            SwiftUI.Color(store.customForeground).frame(width: 9)
                        }
                    }
                    .frame(width: 18, height: 18)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .strokeBorder(Color.primary.opacity(isCustomTheme ? 0.9 : 0),
                                          lineWidth: 1.5)
                            .padding(-2)
                    )
                }
                .buttonStyle(.plain)
                .help("Custom")
                .animation(.spring(duration: 0.2), value: isCustomTheme)

                Spacer(minLength: 0)
            }
        }
    }

    private var customColorRows: some View {
        VStack(alignment: .leading, spacing: 10) {
            row("Background") {
                HexColorPicker(label: "Background", color: Binding(
                    get: { store.customBackground },
                    set: { store.customBackground = $0 }
                ))
            }
            row("Text") {
                HexColorPicker(label: "Text", color: Binding(
                    get: { store.customForeground },
                    set: { store.customForeground = $0 }
                ))
            }
        }
    }

    private var opacityControl: some View {
        @Bindable var store = store
        return HStack(spacing: 8) {
            Slider(value: $store.backgroundOpacity, in: 0.0...1.0, step: 0.05)
                .frame(width: 130)
            Text("\(Int(store.backgroundOpacity * 100))%")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .trailing)
        }
    }

    private var fontSizeControl: some View {
        HStack(spacing: 0) {
            Button { store.fontSize = max(8, store.fontSize - 1) } label: {
                Image(systemName: "minus")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Text("\(Int(store.fontSize))")
                .font(.system(size: 12, design: .monospaced))
                .frame(width: 26, alignment: .center)

            Button { store.fontSize = min(24, store.fontSize + 1) } label: {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
    }

    // MARK: Window controls

    private var windowSizePicker: some View {
        @Bindable var store = store
        return Picker("", selection: $store.windowSize) {
            ForEach(WindowSize.allCases) { ws in
                Text(ws.label).tag(ws)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(width: 148)
        .help("S: 400×240 · M: 620×420 · L: 820×540 · F: Full Screen")
    }

    private var loginToggle: some View {
        Toggle("", isOn: Binding(
            get: { SMAppService.mainApp.status == .enabled },
            set: { enable in
                if enable { try? SMAppService.mainApp.register() }
                else      { try? SMAppService.mainApp.unregister() }
            }
        ))
        .labelsHidden()
        .toggleStyle(.switch)
        .controlSize(.small)
    }

    // MARK: Footer

    private var quitFooter: some View {
        Button {
            NSApp.terminate(nil)
        } label: {
            Text("Quit Miniscule")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isQuitHovering ? Color.red : Color.secondary)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isQuitHovering = hovering }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 2)
    }

    // MARK: Layout helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .kerning(0.8)
            .foregroundStyle(.secondary.opacity(0.75))
            .padding(.leading, 2)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
    }

    private func row<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            content()
        }
    }
}

// MARK: - HexColorPicker

/// Inline hex color input that stays inside the popover — avoids NSColorPanel stealing focus.
struct HexColorPicker: View {
    let label: String
    @Binding var color: NSColor

    @State private var hexText: String = ""
    @State private var isEditing = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            // Live color swatch
            RoundedRectangle(cornerRadius: 4)
                .fill(SwiftUI.Color(color))
                .frame(width: 24, height: 24)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))

            // Hex field
            HStack(spacing: 4) {
                Text("#")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                TextField("", text: $hexText)
                    .font(.system(size: 11, design: .monospaced))
                    .textFieldStyle(.plain)
                    .frame(width: 68)
                    .focused($focused)
                    .onAppear { hexText = color.hexString }
                    .onChange(of: color) { _, newColor in
                        if !focused { hexText = newColor.hexString }
                    }
                    .onChange(of: hexText) { _, newHex in
                        let clean = newHex.trimmingCharacters(in: .init(charactersIn: "#"))
                        if clean.count == 6, let parsed = NSColor(hexString: clean) {
                            color = parsed
                        }
                    }
                    .onSubmit {
                        hexText = color.hexString
                        focused = false
                    }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.07)))
        }
    }
}

extension NSColor {
    var hexString: String {
        guard let rgb = usingColorSpace(.sRGB) else { return "000000" }
        return String(format: "%02X%02X%02X",
                      Int(rgb.redComponent * 255),
                      Int(rgb.greenComponent * 255),
                      Int(rgb.blueComponent * 255))
    }

    convenience init?(hexString: String) {
        let hex = hexString.trimmingCharacters(in: .init(charactersIn: "#"))
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        self.init(hex: value)
    }
}
