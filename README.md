# Lelock OS 🦄

**The AI-Native Operating System**  
*"I got work to do."*

## What Is This?

Lelock OS is a self-contained, self-expanding AI development environment. Start with a terminal. Login to your AI. Ask for an operating system. It builds one.

**The new Arch Linux** — except your AI is the architect.

## Current Status: Phase 1 (Foundation)

- ✅ SwiftUI macOS app
- ✅ Terminal emulator with shell execution
- ✅ Built-in commands (cd, pwd, clear, help, env, export)
- ✅ Command history (up/down arrows)
- ✅ Ada Marie command stubs
- ⬜ AI agent integration (Phase 2)
- ⬜ Git operations (Phase 3)
- ⬜ Self-expansion engine (Phase 5)
- ⬜ iPad/iOS port (Phase 6)
- ⬜ watchOS companion (Phase 7)

## Build & Run

```bash
swift build
.build/debug/LelokOS
```

## Architecture

- **macOS**: Native `Process()` + `/bin/zsh` for real shell
- **iPadOS/iOS** (coming): `ios_system` framework for sandboxed commands
- **watchOS** (coming): Companion app with status + mini Ada chat
- **Sync**: SwiftData + CloudKit across all devices

## Built By

Kit Olivas & Ada Marie 💙🦄  
March 30, 2026
