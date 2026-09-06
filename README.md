# XcodeSentinel

**Keep your Xcode AI coding while you sleep.**

Claude, GitHub Copilot, and other AI assistants in Xcode stop when you hit a usage limit  
or when they're waiting for your next instruction.

XcodeSentinel lets you schedule prompts to any AI chat panel in Xcode —  
so you can start a long coding session before bed and let it continue  
after your usage window resets.

Free. Open source. No cloud. No subscription.

[⬇ Download .dmg](https://github.com/isitest1/XcodeSentinel/releases/latest/download/XcodeSentinel.dmg) · [Website](https://isitest1.github.io/XcodeSentinel/en/) · [Getting Started](https://isitest1.github.io/XcodeSentinel/en/getting-started.html)

---

## The Problem

You kick off a long Claude (or Copilot) coding session in Xcode at 11 PM.  
The 5-hour usage limit resets at 4 AM — but you'll be asleep.  
Without help, the session sits frozen until you open your laptop in the morning.

Same thing happens when the AI is waiting for a "Continue" — and you're not there to click it.

## What XcodeSentinel Does

Schedule a message (e.g. `"Please continue."`) for 4:10 AM.  
At that time, XcodeSentinel types it into the AI panel in Xcode and sends it.  
The session resumes. You wake up to a finished build.

---

## Features

- **Scheduled sends** — any message, any time, repeat daily / weekdays / once
- **Screen-lock aware** — holds a display assertion so scheduled sends fire overnight
- **Execution log** — every attempt logged with timestamp and outcome (Sent / Failed / Deferred)
- **Away notifications** — Webhook support with ntfy / Pushover / Discord / Slack presets
- **AX Inspector** — dump any window's Accessibility tree to JSON for bug reports and fixtures

## Requirements

- macOS 15 (Sequoia) or later
- Xcode with an AI integration enabled (Claude, GitHub Copilot, etc.)
- Accessibility permission — no Screen Recording needed

## Install

1. [Download the .dmg](https://github.com/isitest1/XcodeSentinel/releases/latest/download/XcodeSentinel.dmg)
2. Drag **XcodeSentinel** to Applications and launch it
3. Grant **Accessibility** permission in System Settings → Privacy & Security → Accessibility

XcodeSentinel lives in the menu bar — no Dock icon.  
Full setup guide: [isitest1.github.io/XcodeSentinel/en/getting-started.html](https://isitest1.github.io/XcodeSentinel/en/getting-started.html)

## Why Xcode Panels Only?

This app works with any AI chat panel **inside Xcode** (Claude, GitHub Copilot, etc.)
that exposes an Accessibility API text input.
Detection patterns live in `Patterns.json` and can be extended for any AI integration.

Terminal-based tools (Codex CLI, Claude Code CLI) and VS Code extensions are out of scope —
those run outside Xcode and have their own auto-continue features built in.

## Limitations

**This app does not bypass or extend any usage limit.**  
It only sends a pre-written message after the limit has already cleared.

- Does not auto-respond to permission prompts or Claude's questions — notification only
- Does not send anything when the session state is unclear — notification only
- Never transmits chat text or source code to any external service

## Why Not on the Mac App Store?

An app that drives another app via the Accessibility API cannot run inside the App Sandbox.  
Distribution is via GitHub Releases only — Developer ID signed and notarized.

## If Detection Breaks After an Xcode Update

Xcode's Accessibility tree structure is undocumented and can change with any update.

1. Open the built-in **AX Inspector** and export the window tree to JSON
2. File a [GitHub Issue](https://github.com/isitest1/XcodeSentinel/issues) with the JSON attached — check for project names / paths first
3. Detection patterns live in `Patterns.json` — many fixes don't require a rebuild

## Development

| Work | Where |
|---|---|
| Edit code, `SentinelCore` build + tests, site preview | VS Code Dev Container (Linux) |
| App build, run, AX testing, signing, DMG | Host macOS (Xcode) |

The Dev Container is a Linux container — macOS apps cannot be built inside it by design.  
`SentinelCore` (pure logic, no macOS dependencies) is tested on Linux in CI.  
See [docs/development.md](docs/development.md).

```sh
# Inside Dev Container
swift test --package-path Packages/SentinelCore --parallel
python3 -m http.server 8080 --directory docs/site   # site preview
```

## License

MIT — see [LICENSE](LICENSE).

> Not an official Anthropic or Apple product.
