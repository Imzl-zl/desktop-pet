# Contributing to DesktopPet

Thanks for your interest in improving DesktopPet! Contributions of all sizes are welcome.

## Getting started

```bash
git clone https://github.com/Imzl-zl/desktop-pet.git
cd desktoppet
swift build          # build
swift test           # run the test suite
./scripts/build-app.sh release   # produce DesktopPet.app
open build/DesktopPet.app
```

Requires macOS 13+ and a recent Swift toolchain (Swift 6 / Xcode 15+).

## Project layout

- `Sources/DesktopPetCore/` — pure, testable core: session state, event model, hook
  parsing/installing, the Unix-socket server. No AppKit/SwiftUI here.
- `Sources/App/` — the macOS app: menu bar, floating pet, Settings, controllers.
- `Tests/DesktopPetCoreTests/` — unit tests for the core.
- `scripts/` — app packaging and asset generation.

The split keeps logic (Core) independent of UI so it stays unit-testable.

## Guidelines

- Keep changes focused; match the surrounding style.
- Add or update tests in `DesktopPetCore` for any behavior change.
- Run `swift test` before opening a PR; CI must stay green.
- Conventional commit messages (`feat:`, `fix:`, `docs:`, `refactor:`...).

## Pets

DesktopPet bundles no pet art. Pets use the open Codex pet-pack format
(`pet.json` + an 8×9 spritesheet) and are added at runtime via Browse or import.
Please do not commit pet assets to this repository.

## Reporting issues

Open an issue with steps to reproduce, your macOS version, and which agent
(Claude Code / Codex / Gemini CLI) you were running.
