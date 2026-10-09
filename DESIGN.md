# LLM Usage design

Native macOS utility panel, Operate mode. User confirmed concise platform styling.

- System typography: 13 pt body, 11 pt secondary, 17 pt semibold title. Tabular numbers for usage.
- Adaptive system window background and semantic primary/secondary foregrounds.
- 380 pt panel width, 18 pt outer inset, 12 pt group spacing, 20 pt section separation.
- Quota rows are the primary content: service name, remaining percentage, native progress bar, reset time.
- Dividers separate provider rows and token summaries; no nested cards or ornamental charts.
- Native segmented control chooses today or recent seven calendar days. Model totals sort descending.
- Controls: refresh, Claude connection instructions, quit. Keyboard and VoiceOver labels describe the action.
- Empty, stale, failed and loading states remain explicit. Missing quota is an em dash.
- The status item opens an AppKit transient popover anchored below the menu bar. Its native arrow and system appearance/disappearance animation provide the panel's visual connection to the status item; Reduce Motion disables that animation.
