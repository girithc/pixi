# Pixi

A macOS computer-use agent that drives your Mac the way a human does — it sees the screen, moves the mouse, clicks, types, and presses keys — and falls back to native levers (opening apps, System Settings deep links, AppleScript, Accessibility actions) when those are more precise.

Trigger it from anywhere with a global hotkey:
- **⌥K** — type a command (Spotlight-style panel)
- **⌥␣** — speak a command (listen mode on the cursor buddy)

Pixi runs a vision-driven loop: capture the screen → a multimodal LLM picks the next action(s) → execute → repeat until the goal is done. Every step is traced and inspectable in the in-app **Interactions** tab.

> Status: experimental. Works best on tasks with a clear UI target. Vision grounding can be imprecise; prefer Accessibility-backed actions where available. Not affiliated with Apple, Fireworks AI, or OpenAI.

## Features

- **Human-like input** via CGEvent: click, type, key shortcuts, scroll.
- **Native actions** that don't need vision: `open_app`, `open_settings` (deep links), `applescript`.
- **Accessibility-precise actions**: `ax_press`, `ax_set_value` — act on real AX elements by role + title, no coordinate guessing.
- **Vision fallback**: `vision_click` locates an element by goal when it's not in the AX tree (web content, custom UI).
- **On-demand inventory**: `list_apps` (tiered running/installed), `list_running_apps`, `list_tools`.
- **Observability**: every workflow step (capture, vision, tool, memory) is traced with status + latency; expand any interaction to see the screenshot, target overlay, and per-step cards. Copy an interaction to clipboard.
- **Per-interaction memory** + per-thread **checkpointer** (LangGraph-style state snapshots).
- **Voice path**: mic capture → OpenAI batch transcription → same workflow.
- **Secure secrets**: API keys stored in the macOS Keychain, never in UserDefaults or source.

## Requirements

- macOS 26.0+ (Tahoe)
- Xcode 16+ (builds via file-system-synchronized groups)
- A **Fireworks AI** API key (vision + reasoning LLMs)
- An **OpenAI** API key (STT)

## Permissions

Pixi needs three TCC permissions (prompted on first use, also toggleable in Settings → Permissions):

| Permission | Used for |
|---|---|
| Screen Recording | capturing the screen for the vision loop |
| Accessibility | `ax_press` / `ax_set_value` precise element actions |
| Microphone | voice commands (Option+Space) |

Restart Pixi after granting Screen Recording or Accessibility — TCC only re-checks on launch.

## Build & run

```bash
git clone <repo-url> pixi
cd pixi
open pixi.xcodeproj
```

In Xcode: pick the **pixi** scheme, ⌘R to run. The app is **not sandboxed** (audio-input entitlement only), so network, keychain, Accessibility, and subprocess (`open`, `osascript`) access work without extra entitlements.

## Configure

1. Open Pixi → **Settings**.
2. Enter your **Fireworks AI** and **OpenAI** keys (stored in Keychain).
3. Pick models:
   - **STT** — `gpt-4o-transcribe` (default) / `gpt-4o-mini-transcribe`
   - **Vision LLM** — Qwen 3.7 Plus (default) / Kimi k2.7 code / Minimax M3
   - **Reasoning LLM** — Qwen 3.7 Plus (default) / Kimi k2.7 code / Minimax M3 / GLM 5.2
4. Grant the TCC permissions above.

Keys and model picks persist across restarts.

## Usage

- Press **⌥K**, type e.g. `open System Settings`, Enter.
- Press **⌥␣**, speak e.g. `play les champs élysées on spotify`, press Enter.
- Watch the **Interactions** tab to inspect what Pixi saw, what it did, and why.

Examples that work well:
- `open Terminal`
- `search for nyc best tourist attractions in financial district on reddit`
- `set volume to 50`
- `open the Bluetooth settings`

## Architecture

```
pixi/
  Components/        SwiftUI app shell + observability UI
    ContentView, Sidebar, MainContent, SettingsView, InteractionsView,
    CursorBuddy, InputSpacePanel, HotkeyManager, Permissions, …
  ai/
    Workflow.swift      vision-driven computer-use loop (perceive → reason → act → trace)
    AITrace.swift       chain/trace store (powers Interactions)
    Checkpointer.swift  per-thread state snapshots
    AppSettings.swift   persisted model picks + Fireworks model-id registry
    KeychainStore.swift API key storage
    engines/            pure HTTP transports (VisionLLM, ReasoningLLM, STT, EngineError)
    capture/            ScreenCapture (ScreenCaptureKit), AccessibilityTree
    audio/              AudioRecorder (AVAudioEngine mic → caf)
    grounding/          Target + parser, OverlayWindow (inspect overlay)
    actions/            one file per tool + ToolRegistry + CGInput
```

**The loop** (`ai/Workflow.swift`): each turn captures the screen + an Accessibility snapshot, sends them to the vision LLM with the tool manifest, parses a JSON batch of actions, executes them in sequence without re-perceiving between sub-steps, traces + checkpoints, and repeats until `done` or the step budget is hit. Loop detection stops immediate back-to-back repeats; memory is per-interaction.

**One file per tool** (`ai/actions/`) so a bug maps to a single file. Tools log their own trace step via the registry.

## Apple APIs used

ScreenCaptureKit (capture), ApplicationServices/Accessibility (read + act on UI), CoreGraphics/CGEvent (mouse + keyboard input), AppKit/NSWorkspace (apps, windows, pasteboard), AVFoundation (mic), Security (keychain), Carbon (global hotkeys), SwiftUI (UI + state).

## Contributing

Contributions welcome. Keep every file under 200 lines (see `AGENTS.md`). Open an issue first for non-trivial changes, then a PR against `main`. Build clean (`xcodebuild -project pixi.xcodeproj -scheme pixi build`) before submitting.

## License

MIT — see [LICENSE](LICENSE).
