# LLM Usage

<!-- impeccable:product-schema 1 -->

## Platform
macOS native

## Stack
SwiftUI, Swift Package Manager, Foundation. No third-party dependencies.

## Users
Developer using Codex CLI and Claude Code CLI on a Mac.

## Product Purpose
See remaining provider allowances in the menu bar and inspect token consumption by day, week and model in a compact panel.

## Operating Context
Local CLI logs supply this Mac's token activity. Codex app-server supplies account quota snapshots. Claude Code statusline can supply allowance snapshots during CLI activity.

## Brand Commitments
App display name: LLM Usage. Code name: LLMUsage. Menu bar labels spell out Codex and Claude. User chose a concise panel using native macOS styling.

## Capabilities and Constraints
Quota and tokens are distinct. Unknown values must not appear as zero. Show data freshness. No conversation content or credentials are copied into the app's storage. Daily statistics use the Mac's local calendar; quota resets use provider timestamps. Existing CLI settings must be preserved.

## Open Decisions
Distribution and signing are not yet decided. MVP assumes macOS 14+.
