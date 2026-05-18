# Claude Usage Bot

A small macOS overlay bot that shows your Claude Code usage in a speech bubble.
Reads `~/.claude/projects/**/*.jsonl` directly — no API key, no network calls.

Inspired by [FreeRoamer](https://github.com/munolee/FreeRoamer)'s overlay-panel
pattern.

## Run

```sh
swift run claudeusagebot
```

Quit from the menu bar icon, or `Ctrl+C` if running through SwiftPM.

Click the mascot to pop a speech bubble showing today's token usage and cost
estimate. The mascot's color reflects today's load:

- calm orange — under 200K tokens today
- busy yellow — 200K–1M
- alarmed red — over 1M

The menu bar item exposes:

- 지금 보여줘 (`⌘S`) — force the bubble open
- 새로고침 (`⌘R`) — re-scan transcripts immediately
- 숨기기 / 보이기 (`⌘P`) — hide/show the mascot
- Quit (`⌘Q`)

## Build the App Bundle

```sh
./scripts/package-app.sh
open .build/release/ClaudeUsageBot.app
```

## Test

```sh
swift test
```

## Project Structure

```
Sources/
  ClaudeUsageCore/         Pure logic — testable, no AppKit
    UsageRecord.swift      One assistant message's token usage
    UsageReader.swift      JSONL transcript parser
    UsageAggregator.swift  Today / 7-day / all-time rollups, dedupe by messageId
    Pricing.swift          Per-model $/MTok lookup
    UsageFormatter.swift   "1.2M tokens", "$0.42" helpers
  claudeusagebot/          AppKit executable
    AppMain.swift          AppDelegate, status menu
    OverlayController.swift Borderless NSPanel, anchored bottom-right
    MascotView.swift       Programmatic mascot (round head, antenna, eyes, mouth)
    SpeechBubbleView.swift Rounded bubble with tail
    UsagePoller.swift      30-second refresh on background queue
Tests/
  ClaudeUsageCoreTests/    XCTest suite for parser, aggregator, pricing
```

## Pricing notes

Per-million-token rates in `Pricing.swift` are best-effort — adjust them when
Anthropic publishes new tiers. Unknown models contribute zero to the cost
estimate but still count toward token totals.
