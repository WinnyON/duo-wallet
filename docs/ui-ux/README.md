Latest: [beta.5 separation refinement](separation-refinement.md) restores visible rules and adds a few purposeful white cards, with [updated screenshots](separation-refinement/).

The current light-only redesign is documented in [light-redesign.md](light-redesign.md), with [new screen captures](light-redesign/). Earlier before/after captures below are historical and show the superseded theme.

# UI/UX evidence

See the [detailed audit](../ui-ux-audit.md), [implementation plan](../ui-ux-implementation-plan.md), and [implementation status](../ui-ux-implementation-status.md).

| Surface | Before | After |
| --- | --- | --- |
| Dashboard | [English](before/en_dashboard.png) | [English](after/en_dashboard.png) |
| Dashboard, dark | [English](before/en_dashboard_dark.png) | [English](after/en_dashboard_dark.png) |
| Transactions | [Hungarian](before/hu_transactions.png) | [Hungarian](after/hu_transactions.png) |
| Profile | [Hungarian](before/hu_auth.png) | [Hungarian](after/hu_auth.png) |
| Goals | [English](before/en_goals.png) | [English](after/en_goals.png) |
| Export | [English](before/en_export.png) | [English](after/en_export.png) |

The before folder preserves the original audit captures and collecting render log. The after folder contains 34 final real-font, real-shadow screenshots across English and Hungarian routes and dark dashboards.

[Full test result: 50 passed](test-results.txt). [Analyzer and whitespace results](analyzer-results.txt).

The tests include 80 route/configuration visits, 32 empty/extreme-data route visits, five dark-dashboard checks and two simulated-keyboard sheet scenarios. They do not establish physical-device, TalkBack, backend or durable-storage readiness; see the implementation status for those limits.
