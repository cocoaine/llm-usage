# LLM Usage repository guidance

## Product contract

This is a macOS 14+ SwiftUI menu-bar utility built with Swift Package Manager. The display name is **LLM Usage** and the executable/package name is `LLMUsage`. The status-bar label must spell out `Codex` and `Claude`; do not replace them with initials.

The compact native panel shows provider quota remaining and reset times first, followed by this Mac's local token totals for today or the latest seven local calendar days and model totals. Quota is account data; token activity is local-log data. Never derive quota remaining, reset time, cost, billing, or subscription entitlement from token totals. Unknown data is an em dash, never zero.

## Data and privacy rules

- Keep dependencies limited to SwiftUI, AppKit, and Foundation unless the user approves a new dependency.
- Do not store, display, send, or log prompt/response content, credentials, or API keys. Claude allowance storage may contain only parsed allowance windows and collection metadata.
- Codex account lookup is best effort. On a failed lookup, retain a non-empty prior snapshot, clearly label its actual source, and show its age. Do not let an empty or expired snapshot erase data or become a full allowance.
- Claude statusline installation must require an explicit UI action. It must back up a settings file before writing it and refuse to replace an existing unrelated statusline. Never execute user-provided statusline commands automatically.
- Local CLI log formats are unofficial and can change. Token aggregation must have deterministic deduplication, must be bounded to the requested time span, and must tolerate malformed lines.

## Layout and behavior

- Preserve concise native macOS styling: system typography, semantic colors, native controls, 380 pt panel width, no ornamental dashboard cards.
- Start quota refresh at launch and repeat it every 60 seconds independently of whether the panel is open. A visible spinner represents in-progress work. Avoid full weekly JSONL directory scans at every timer tick; retain in-memory data and scan on launch, manual refresh, and a bounded interval.
- An expired reset timestamp means the quota is stale and needs a fresh record. Show `갱신 필요`; never render it as newly reset or fresh.

## Module boundaries

- Organize growing code by responsibility, not by file type or an arbitrary line count. Keep app entry, lifecycle, and shared state in `Sources/LLMUsage/App`; provider UI in `Features/Quotas`; token summaries in `Features/Tokens`; and Claude setup UI in `Features/Connection`.
- Separate UI composition, domain aggregation, and data I/O when their responsibilities differ. Split a multipurpose file once that separation makes a feature easier to inspect or test, but do not create a file for every tiny helper.

## Ownership and validation

- `Sources/UsageCore` owns collectors and parsers; changes require focused `UsageCoreTests` coverage.
- `Sources/LLMUsage/App`, `Sources/LLMUsage/Features`, `Sources/LLMUsage/Support`, `Resources`, `Scripts`, and documentation own app presentation, lifecycle, and packaging.
- Use `apply_patch` for local source/document edits and preserve unrelated work in a dirty tree.
- Run the narrowest relevant checks, then the package test suite for cross-target changes:

```zsh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export CLANG_MODULE_CACHE_PATH=/private/tmp/llmusage-clang-cache
export SWIFT_MODULECACHE_PATH=/private/tmp/llmusage-swift-module-cache
swift build --disable-sandbox --cache-path /private/tmp/llmusage-swift-cache
swift test --disable-sandbox --cache-path /private/tmp/llmusage-swift-cache
./Scripts/build-app.sh
```

The user asked that substantive implementation be delegated to subagents. For non-trivial changes, the lead delegates bounded work, reviews the actual diff, and uses an independent review or test pass proportional to risk. Git remotes and push URLs must use HTTPS, never SSH.
