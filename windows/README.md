# DesktopPet for Windows

A desktop pet that floats on your screen and reacts in real time to your AI
coding agents (Claude Code, Codex, Gemini CLI, Cursor, opencode, Windsurf,
Antigravity, GitHub Copilot, Kiro CLI). Windows port of the macOS app, built with
[Tauri](https://tauri.app) so it stays small (~10 MB) and reuses the same pet
catalog + hook model.

> Status: feature-complete, builds on CI (`.msi` + NSIS `.exe`). Not yet
> validated on a real Windows machine, and not code-signed (see
> [SmartScreen](#smartscreen-no-code-signing-cert) below).

## Install

WebView2 is preinstalled on Windows 10/11, so there are no other prerequisites.

### Scoop (recommended , no SmartScreen prompt)

```powershell
scoop bucket add desktoppet https://github.com/Imzl-zl/desktop-pet
scoop install desktoppet
```

Scoop downloads the portable build straight from the GitHub release, so the
browser/SmartScreen download warning never appears.

### winget

```powershell
winget install Imzl-zl.DesktopPet
```

### Manual installer

Download `DesktopPet_<version>_x64-setup.exe` from the
[releases](https://github.com/Imzl-zl/desktop-pet/releases) page. It installs
per-user (no admin/UAC prompt). See [SmartScreen](#smartscreen-no-code-signing-cert)
for the one-time "Run anyway" step.

## SmartScreen (no code-signing cert)

The installer is **not code-signed** (a cert costs money), so Windows SmartScreen
may show *"Windows protected your PC"* on first run of the downloaded `.exe`.
It is safe to bypass:

1. Click **More info**.
2. Click **Run anyway**.

To avoid the prompt entirely, install via **Scoop** or **winget** (above) , those
paths don't trigger SmartScreen.

## How it works

```
agent hook  ──(stdin JSON)──►  desktoppet.exe hook --agent <kind>
                                      │  POST /event
                                      ▼
                          localhost:47628 (Rust listener in the running app)
                                      │  emit "agent-event"
                                      ▼
                          pet overlay window (Tauri webview, canvas sprite)
```

- The same binary doubles as the hook CLI: `desktoppet hook --agent claude` reads
  the agent's hook payload on stdin and POSTs it to the running app. It always
  exits 0 so it never blocks an agent (Copilot PreToolUse is fail-closed).
- Hook configs are written to Windows paths (`%USERPROFILE%\.claude\settings.json`,
  `\.codex\hooks.json`, ...) , identical formats to the macOS app.
- Pets come from the public CDN (`pets.thenightwatcher.online/manifest.json`),
  rendered from the 8x9 spritesheet (8 frames per state row).
- The transparent overlay is **click-through**: only the pet's opaque rect
  captures the mouse, so the empty area lets clicks reach the apps below. Drag
  the pet to move it; its position is remembered across restarts.

## Features (parity with macOS)

- 9 agents, same hook formats as macOS.
- Pet picker (search / random) + "use your own spritesheet".
- Bubble customization: theme (dark/light/system), opacity, font size/family,
  themed phrases, per-agent custom messages, idle chatter toggle.
- Multi-agent bubble (shows every active session at once) with a live elapsed
  clock and per-tool live activity text (file being edited, command description).
- Live preview in Settings, desktop notifications + chimes, autostart,
  auto-update (Tauri updater, minisign-signed).
- i18n: English / Tiếng Việt / 简体中文 with a runtime language switcher.

## Develop

```bash
cd windows
npm install
npm run tauri dev      # runs on macOS too (dev); click-through is Windows-only
```

## Build (on Windows)

```bash
npm install
npm run tauri build    # NSIS installer + MSI in src-tauri/target/release/bundle
```

## Build via CI (no Windows machine needed)

`.github/workflows/windows-build.yml` builds the installers on `windows-latest`:

- Run it manually from the **Actions** tab (workflow_dispatch) , the `.msi` and
  `.exe` are uploaded as artifacts.
- Push a tag like `win-v0.1.0` to also attach the installers, the portable
  Scoop zip, and the signed updater manifest to a GitHub release.

## Agents

| Agent          | Config file                                  | Notes |
|----------------|----------------------------------------------|-------|
| Claude Code    | `~/.claude/settings.json`                    | works once installed |
| Codex          | `~/.codex/hooks.json` + `config.toml`        | run `/hooks` → `t` once to trust |
| Gemini CLI     | `~/.gemini/settings.json`                    | |
| Cursor         | `~/.cursor/hooks.json`                        | |
| opencode       | `~/.config/opencode/plugin/desktoppet.js`      | JS plugin |
| Windsurf       | `~/.codeium/windsurf/hooks.json`             | no "needs input" alerts |
| Antigravity    | `~/.gemini/config/hooks.json`                | no "needs input" alerts |
| GitHub Copilot | `~/.copilot/hooks/desktoppet.json`             | Copilot CLI |
| Kiro CLI       | `~/.kiro/agents/default.json`                | hooks the default agent |

## Publishing the package manifests

After a `win-v*` release is published:

```bash
node scripts/fill-package-hashes.mjs win-v0.1.0
```

This fills the version + SHA256 into `packaging/scoop/desktoppet.json` and
`packaging/winget/*`. Then:

- **Scoop**: this repo doubles as the bucket , the manifest at
  `windows/packaging/scoop/desktoppet.json`. (Point the bucket subdir or copy it to
  a `bucket/` folder as Scoop expects.)
- **winget**: submit `packaging/winget/*` as a PR to
  [microsoft/winget-pkgs](https://github.com/microsoft/winget-pkgs).
