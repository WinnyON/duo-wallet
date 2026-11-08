# Separation refinement — beta.5

A small refinement to the beta.4 light design. The palette, page structure, typography and navigation are retained.

| Before | After | Why |
| --- | --- | --- |
| Section rules painted underneath opaque white Material children | Rules painted in the foreground | Restore the intended separators across lists and dense pages |
| Common-account contribution controls blend into account list | One white bordered summary card | Keep the balance, pledge controls and contribution action together |
| Account balance/action overview blends into history | One white bordered overview card | Distinguish actions from historical entries |
| Emergency-fund instructions and month control blend into goals | One white bordered configuration card | Separate configuration from goal records |
| Export and backup controls run together | A white bordered card for each workflow | Clarify which controls belong to reporting versus backup |
| Reminder description, action and results blend into Settings | One white bordered reminder card | Group the action and its output |
| Recurring Edit looks like adjacent descriptive text | Outlined Edit button; tertiary actions remain text | Make the editing affordance visible without adding more filled actions |

All other ordinary lists and summaries remain unboxed. Existing primary-action backgrounds remain unchanged; no additional filled-button styles or dependencies were introduced.

Validation: analysis clean; 68 tests passed and one opt-in live-backend integration test skipped. All 16 routes checked with English/Hungarian, widths down to 320 dp, large text up to 200%, empty/extreme records and keyboard sheets. [Rendered evidence](separation-refinement/) was visually reviewed for account overview, account detail, goals, reporting, recurring items, transactions and settings. Screenshots use demo fixtures and contain no new production data.
