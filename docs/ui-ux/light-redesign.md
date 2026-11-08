# Light UI redesign — November 8, 2026

The requested direction is light-only, white content surfaces, stronger functional colors, fewer cards and moderate corners. These are product decisions; standards establish accessibility and interaction constraints rather than prescribing a blue palette or one universal radius.

## Research and applied rules

- [Android accessibility guidance](https://developer.android.com/guide/topics/ui/accessibility/views/apps-views): interactive targets at least 48 × 48 dp. Filled, outlined and text buttons share a 48 dp minimum, standard density and content padding; longer or enlarged labels can grow vertically. Transfer uses the same native outlined button as other secondary actions.
- [WCAG text contrast](https://www.w3.org/WAI/WCAG21/Understanding/contrast-minimum): normal text at least 4.5:1. Automated tests cover primary actions, secondary text and positive data on white. State is also expressed with labels, icons and selected navigation rules.
- [Nielsen Norman Group on cards](https://www.nngroup.com/articles/cards-component/): cards group a discrete concept; predictable aligned lists are easier to scan for specific records. Transactions, accounts, settings and planning content now use unboxed sections. A contained settlement summary remains because it presents a single balance and its action.
- [Wathan and Schoger’s primary article](https://medium.com/refactoring-ui/7-practical-tips-for-cheating-at-design-40c736799886): build hierarchy through weight and contrast, reduce box/border noise, and distinguish primary, secondary and tertiary actions. Apply one solid cobalt main action, outlined secondary actions and text links. Keep figures aligned with tabular numerals.
- [Refactoring UI book and tutorial overview](https://refactoringui.com/): use a constrained scale for spacing, sizing and typography, leave room between related groups, and use deliberate action hierarchy. The public article and book overview were read; the paid book and screencasts were not accessed. The authors’ [YouTube channel](https://www.youtube.com/steveschoger) was checked but browser access did not expose video contents; no claim is made to have watched those videos.
- [Nielsen Norman Group on progress feedback](https://www.nngroup.com/articles/progress-indicators/): feedback should help users understand an operation. For this app, routine background polling is silent; queued writes and failures remain visible, and Settings retains manual sync.

## Visual system

| Role | Value |
| --- | --- |
| Page, sections, fields, ordinary content | White `#FFFFFF` |
| Primary action / selection / information | Cobalt `#1645D8` |
| Text | Ink `#142033` |
| Secondary text | Slate `#475569` |
| Contained settlement summary | Navy `#102A56` with white text |
| Positive / expense / warning | `#087443` / `#C62828` / `#9A4A00` |
| Controls / summary / sheet corners | 8 / 12 / 16 dp |
| Spacing | 4, 8, 12, 16, 20, 24, 32 dp |

The white backgrounds are deliberate. Divider and input-outline colors are structural marks, not gray card fills. Primary and secondary controls have no decorative elevation. The bottom navigation uses a blue active icon and rule rather than a pastel pill.

## Review

| Before | After | Why |
| --- | --- | --- |
| System-controlled light/dark mode | Light-only, including devices set to dark | Explicit product preference |
| Pink actions, gray wells and large rounded wrappers | White surfaces, cobalt actions, restrained corners | Clearer contrast and visual hierarchy |
| Home repeats budgets, goals, insights and activity in separate cards | Home focuses on spend, settlement, accounts and recent transactions; other features stay in their dedicated screens and menu | Reduce competing information |
| Small custom Transfer pill with a large surrounding tap wrapper | Native outlined control with consistent dimensions | Match its visible affordance to the target |
| Floating Home action can cover balances | Inline Add and Transfer actions | Keep account content visible |
| Every remote snapshot can schedule a fresh sync | Debounced sync is scheduled only when local writes are queued | Stop a feedback loop rather than masking its symptoms |
| Idle/syncing text constantly changes on Home | No routine polling text; actionable failures and pending changes remain | Stable layout with meaningful feedback |

## Verification

- 68 tests passed; one opt-in hosted-backend integration test skipped.
- All 16 routes rendered in English and Hungarian, narrow screens down to 320 dp and up to 200% text. Empty and extreme-data states checked across all routes.
- Dedicated tests cover light-only behavior on dark-system devices, white surfaces, Transfer height and corner shape, readable semantic colors, and remote-notification versus local-edit sync scheduling.
- [Rendered screens](light-redesign/) use real SDK fonts. Screenshots show isolated demo fixtures, not real account data. Dark-system captures remain light.
- No physical Android device or TalkBack session was available; those behaviors remain unverified. The suite does not send email or change production account/financial data.
