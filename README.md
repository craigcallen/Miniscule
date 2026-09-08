# Miniscule

A minuscule terminal for your menu bar.

![Platform](https://img.shields.io/badge/platform-macOS-lightgrey)
![Swift](https://img.shields.io/badge/swift-5.9-orange)
![License](https://img.shields.io/github/license/craigcallen/Miniscule)

Miniscule lives in your menu bar and gives you instant access to a full terminal session without leaving your current workflow.

> Miniscule started as a rename/fork of [Termini](https://github.com/ModernProgrammer/Termini) by Diego Bustamante (MIT licensed — see [LICENSE](LICENSE)). Branding assets (icons, screenshots) still carry over from that origin and need to be replaced with Miniscule's own.

## Features

**Welcome screen** — An animated splash screen on first launch with a typing demo.

**Multi-tab sessions** — Open multiple terminal tabs in a single window. Each tab tracks the current working directory and displays it as the tab title, updated in real time via `proc_pidinfo`.

**Themes** — Choose from six built-in color schemes: Classic, Dracula, Nord, Solarized, Gruvbox, and Matrix. A custom theme option lets you set your own background and foreground colors via hex input.

**Adjustable opacity** — Slide the background opacity from fully transparent to fully opaque, useful for keeping the terminal visible over other windows.

**Font size control** — Increase or decrease the terminal font size (8–24pt) from the settings popover.

**Window sizes** — Four preset sizes to fit your screen: Mini (400×240), Medium (620×420), Large (820×540), and Full Screen.

**Open in external terminal** — Instantly open the active tab's current directory in any installed terminal app (Terminal.app, iTerm2, Ghostty, Warp, Alacritty).

**Login item** — Optionally launch Miniscule automatically at login via the Settings popover.

## Installation

### Download (recommended)

1. Go to the [latest release](https://github.com/craigcallen/Miniscule/releases/latest).
2. Download `Miniscule.dmg` and open it.
3. Drag **Miniscule** into the `Applications` folder shown in the window.
4. Launch it from `/Applications` — Miniscule appears in your menu bar.

The download is a universal build (Apple Silicon + Intel) and is notarized by Apple, so it opens without a Gatekeeper warning.

### Build from source

Requirements:

- macOS (Apple Silicon or Intel)
- Xcode 15+
- [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) (resolved automatically as a Swift Package dependency)

Open `Miniscule.xcodeproj` in Xcode and build the `Miniscule` scheme. The app will appear in your menu bar on launch.
