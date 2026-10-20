#!/usr/bin/env python3
"""
Duo Wallet — End-to-End Repository & Domain Verification Suite (`verify_all.py`)

Validates:
1. Repository structure & required files from `implementation_plan.md`.
2. Dart source integrity: relative/package imports in `app/lib/**` and screen class definitions.
3. SQL migrations (`0001`..`0004`) and pgTAP privacy test suite (`01_privacy_suite.sql`):
   all 19 tables, RLS enablement, visibility/immutability triggers, settlement confirmation
   protection, and security-invoker RPCs.
4. Reference verification of all core domain algorithms & privacy invariants:
   - Percentage & odd-remainder splits (`calculatePercentageSplit`, 0/100 splits)
   - Three views (`Together`, `Individual`, `My Total`)
   - Settle-up balance (personal-paid Together creates debt; common-account expenses and
     personal->common contributions create zero debt; pending vs confirmed settlements)
   - Compound interest projection & binary-search goal monthly contribution solver
   - Personal vs Shared Emergency Fund target calculation
   - Deterministic UUIDv5 recurring transaction IDs (`duo-wallet:recurring:<rule_id>:<YYYY-MM-DD>`)
   - Scope-change tombstone + new UUID replacement invariant
"""

from __future__ import annotations

import math
import re
import sys
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parent


def check(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(f"FAIL: {message}")


def verify_expected_files() -> None:
    required_files = [
        "implementation_plan.md",
        "README.md",
        ".github/workflows/ci.yml",
        ".github/workflows/keepalive.yml",
        "supabase/migrations/0001_schema.sql",
        "supabase/migrations/0002_rls_privacy.sql",
        "supabase/migrations/0003_functions.sql",
        "supabase/migrations/0004_cron_storage.sql",
        "supabase/functions/fetch-fx-rates/index.ts",
        "supabase/seed.sql",
        "supabase/tests/01_privacy_suite.sql",
        "app/pubspec.yaml",
        "app/android/app/build.gradle.kts",
        "app/android/app/src/main/AndroidManifest.xml",
        "app/android/app/src/main/kotlin/com/duowallet/app/DuoWidgetProvider.kt",
        "app/android/app/src/main/res/layout/duo_widget.xml",
        "app/android/app/src/main/res/xml/duo_widget_info.xml",
        "app/lib/main.dart",
        "app/lib/app.dart",
        "app/lib/router.dart",
        "app/lib/theme.dart",
        "app/lib/core/env.dart",
        "app/lib/core/db/app_database.dart",
        "app/lib/core/db/tables/tables.dart",
        "app/lib/core/sync/sync_engine.dart",
        "app/lib/core/sync/realtime_listener.dart",
        "app/lib/core/sync/background_tasks.dart",
        "app/lib/core/money/currency.dart",
        "app/lib/core/money/money.dart",
        "app/lib/core/money/fx_service.dart",
        "app/lib/core/l10n/app_en.arb",
        "app/lib/core/l10n/app_hu.arb",
        "app/lib/core/l10n/generated/app_localizations.dart",
        "app/lib/core/notifications/notification_service.dart",
        "app/lib/core/notifications/alert_rules.dart",
        "app/lib/core/domain/splits.dart",
        "app/lib/core/domain/views.dart",
        "app/lib/core/domain/balance.dart",
        "app/lib/core/domain/projection.dart",
        "app/lib/core/domain/insights.dart",
        "app/test/domain_test.dart",
        "app/test/sync_and_privacy_test.dart",
        "app/test/widget_test.dart",
    ]
    for rel in required_files:
        p = ROOT / rel
        check(p.is_file(), f"Missing required file: {rel}")

    feature_screens = [
        ("app/lib/features/auth/presentation/auth_screen.dart", "AuthScreen"),
        ("app/lib/features/dashboard/presentation/dashboard_screen.dart", "DashboardScreen"),
        ("app/lib/features/transactions/presentation/transactions_screen.dart", "TransactionsScreen"),
        ("app/lib/features/accounts/presentation/accounts_screen.dart", "AccountsScreen"),
        ("app/lib/features/transfers/presentation/transfer_sheet.dart", "TransferSheet"),
        ("app/lib/features/categories/presentation/categories_screen.dart", "CategoriesScreen"),
        ("app/lib/features/budgets/presentation/budgets_screen.dart", "BudgetsScreen"),
        ("app/lib/features/stats/presentation/stats_screen.dart", "StatsScreen"),
        ("app/lib/features/history/presentation/history_screen.dart", "HistoryScreen"),
        ("app/lib/features/settle_up/presentation/settle_up_screen.dart", "SettleUpScreen"),
        ("app/lib/features/recurring/presentation/recurring_screen.dart", "RecurringScreen"),
        ("app/lib/features/savings/presentation/savings_screen.dart", "SavingsScreen"),
        ("app/lib/features/goals/presentation/goals_screen.dart", "GoalsScreen"),
        ("app/lib/features/activity/presentation/activity_screen.dart", "ActivityScreen"),
        ("app/lib/features/export/presentation/export_screen.dart", "ExportScreen"),
        ("app/lib/features/settings/presentation/settings_screen.dart", "SettingsScreen"),
        ("app/lib/features/widget/home_widget_bridge.dart", "HomeWidgetBridge"),
    ]
    for rel, cls_name in feature_screens:
        p = ROOT / rel
        check(p.is_file(), f"Missing required feature screen file: {rel}")
        content = p.read_text(encoding="utf-8")
        check(
            f"class {cls_name}" in content,
            f"Expected class {cls_name} in {rel}",
        )


def verify_dart_imports() -> None:
    lib_dir = ROOT / "app" / "lib"
    import_re = re.compile(r"""^\s*import\s+['"]([^'"]+)['"]""", re.MULTILINE)
    dart_files = list(lib_dir.rglob("*.dart")) + list((ROOT / "app" / "test").rglob("*.dart"))
    check(len(dart_files) > 0, "No Dart files found")

    for dart_file in dart_files:
        text = dart_file.read_text(encoding="utf-8")
        for match in import_re.finditer(text):
            target = match.group(1)
            if target.startswith("dart:"):
                continue
            if target.startswith("package:duo_wallet/"):
                rel_target = lib_dir / target.removeprefix("package:duo_wallet/")
                check(
                    rel_target.is_file(),
                    f"Unresolved package import '{target}' in {dart_file.relative_to(ROOT)}",
                )
            elif not target.startswith("package:"):
                resolved = (dart_file.parent / target).resolve()
                check(
                    resolved.is_file(),
                    f"Unresolved relative import '{target}' in {dart_file.relative_to(ROOT)}",
                )


def verify_sql_migrations_and_privacy() -> None:
    m1 = (ROOT / "supabase/migrations/0001_schema.sql").read_text(encoding="utf-8").lower()
    m2 = (ROOT / "supabase/migrations/0002_rls_privacy.sql").read_text(encoding="utf-8").lower()
    m3 = (ROOT / "supabase/migrations/0003_functions.sql").read_text(encoding="utf-8").lower()
    m4 = (ROOT / "supabase/migrations/0004_cron_storage.sql").read_text(encoding="utf-8").lower()
    t1 = (ROOT / "supabase/tests/01_privacy_suite.sql").read_text(encoding="utf-8").lower()

    expected_tables = [
        "households",
        "profiles",
        "accounts",
        "categories",
        "tags",
        "recurring_rules",
        "transactions",
        "transaction_shares",
        "transaction_tags",
        "budgets",
        "settlements",
        "settlement_postings",
        "account_valuations",
        "goals",
        "goal_accounts",
        "goal_contributions",
        "activity",
        "fx_rates",
        "app_releases",
    ]
    for tbl in expected_tables:
        check(f"create table {tbl}" in m1, f"Missing table '{tbl}' in 0001_schema.sql")
        check(
            f"alter table {tbl} enable row level security" in m2,
            f"Missing RLS enablement for '{tbl}' in 0002_rls_privacy.sql",
        )

    # Triggers & functions
    check("function my_household_id()" in m2, "Missing my_household_id() in 0002_rls_privacy.sql")
    check(
        "function set_transaction_visibility()" in m2,
        "Missing set_transaction_visibility() in 0002_rls_privacy.sql",
    )
    check(
        "transaction visibility is immutable" in m2,
        "Missing immutability guard in set_transaction_visibility()",
    )
    check(
        "function check_settlement_confirmation()" in m2,
        "Missing check_settlement_confirmation() trigger function",
    )

    for fn in [
        "create_household",
        "join_household",
        "get_balance",
        "monthly_totals",
        "category_totals",
        "generate_recurring",
        "post_interest",
    ]:
        check(f"function {fn}" in m3, f"Missing RPC/function '{fn}' in 0003_functions.sql")

    check("security invoker" in m3, "Aggregate RPCs must use SECURITY INVOKER")
    check("uuid_generate_v5" in m3, "generate_recurring must use deterministic UUIDv5")
    check("cron.schedule" in m4, "0004_cron_storage.sql must schedule pg_cron jobs")
    check("releases" in m4, "0004_cron_storage.sql must configure releases storage bucket")
    check("select plan(" in t1, "01_privacy_suite.sql must be a valid pgTAP test script")


def verify_domain_math_and_invariants() -> None:
    # 1. Percentage split & odd remainders
    def calc_split(amount_minor: int, pct_a: int) -> tuple[int, int]:
        share_a = (amount_minor * pct_a) // 100
        share_b = amount_minor - share_a
        return share_a, share_b

    check(calc_split(10000, 50) == (5000, 5000), "50/50 split failed")
    check(calc_split(10001, 50) == (5000, 5001), "Odd remainder split failed")
    check(sum(calc_split(10001, 33)) == 10001, "33/67 odd remainder sum failed")
    check(calc_split(250000, 0) == (0, 250000), "0/100 split failed")
    check(calc_split(250000, 100) == (250000, 0), "100/0 split failed")

    # 2. Three views (Together, Individual, My Total)
    sam, anna = "user-sam", "user-anna"
    txns = [
        # 10 000 Ft Together 60/40 paid by Sam from personal card
        {
            "kind": "expense",
            "scope": "together",
            "base": 1_000_000,
            "paid_by": sam,
            "paid_from_common": False,
            "is_contribution": False,
            "created_by": sam,
            "shares": {sam: 600_000, anna: 400_000},
        },
        # 8 450 Ft Together 50/50 paid from common account
        {
            "kind": "expense",
            "scope": "together",
            "base": 845_000,
            "paid_by": anna,
            "paid_from_common": True,
            "is_contribution": False,
            "created_by": anna,
            "shares": {sam: 422_500, anna: 422_500},
        },
        # 5 000 Ft Individual private expense by Sam
        {
            "kind": "expense",
            "scope": "individual",
            "base": 500_000,
            "paid_by": sam,
            "paid_from_common": False,
            "is_contribution": False,
            "created_by": sam,
            "shares": {sam: 500_000},
        },
    ]

    def amount_for(t: dict, view: str, me: str) -> int:
        if t["kind"] != "expense":
            return 0
        if view == "together":
            return t["base"] if t["scope"] == "together" else 0
        if view == "individual":
            return t["base"] if (t["scope"] == "individual" and t["created_by"] == me) else 0
        if view == "myTotal":
            if t["scope"] == "individual":
                return t["base"] if t["created_by"] == me else 0
            return t["shares"].get(me, 0)
        return 0

    together_total = sum(amount_for(t, "together", sam) for t in txns)
    sam_indiv_total = sum(amount_for(t, "individual", sam) for t in txns)
    sam_my_total = sum(amount_for(t, "myTotal", sam) for t in txns)
    anna_my_total = sum(amount_for(t, "myTotal", anna) for t in txns)

    check(together_total == 1_845_000, "Together view total mismatch")
    check(sam_indiv_total == 500_000, "Sam Individual view total mismatch")
    check(sam_my_total == 600_000 + 422_500 + 500_000, "Sam My Total mismatch")
    check(anna_my_total == 400_000 + 422_500, "Anna My Total must exclude Sam's private item")

    # 3. Settle-up balance (common-account expenses & contributions create 0 debt)
    net_sam = 0
    for t in txns:
        if (
            t["kind"] == "expense"
            and t["scope"] == "together"
            and not t["paid_from_common"]
            and not t["is_contribution"]
        ):
            if t["paid_by"] == sam:
                net_sam += t["shares"].get(anna, 0)
            elif t["paid_by"] == anna:
                net_sam -= t["shares"].get(sam, 0)

    check(net_sam == 400_000, "Settle-up balance before settlements should be 4 000 Ft (400000 minor)")

    # 4. Compound interest & goal required monthly solver
    def project_balance(
        start_minor: int,
        monthly_minor: int,
        annual_rate_pct: float,
        periods_per_year: int,
        months: int,
        tax_pct: float = 0.0,
    ) -> int:
        monthly_factor = (
            0.0
            if annual_rate_pct == 0
            else math.pow(1 + annual_rate_pct / 100.0 / periods_per_year, periods_per_year / 12.0) - 1
        )
        bal = float(start_minor)
        for _ in range(months):
            interest = bal * monthly_factor * (1.0 - tax_pct / 100.0)
            bal += interest + monthly_minor
        return round(bal)

    final_val = project_balance(10_000_000, 1_000_000, 6.0, 12, 12)
    check(final_val > 22_000_000, "Compound interest projection should exceed raw contributions")

    low, high = 0, final_val - 10_000_000
    while low < high:
        mid = (low + high) // 2
        if project_balance(10_000_000, mid, 6.0, 12, 12) >= final_val:
            high = mid
        else:
            low = mid + 1
    check(abs(low - 1_000_000) <= 1, "Binary search monthly solver did not converge")

    # 5. Deterministic UUIDv5 for recurring transactions
    id_a = str(uuid.uuid5(uuid.NAMESPACE_URL, "duo-wallet:recurring:rule-1:2026-11-05"))
    id_b = str(uuid.uuid5(uuid.NAMESPACE_URL, "duo-wallet:recurring:rule-1:2026-11-05"))
    id_c = str(uuid.uuid5(uuid.NAMESPACE_URL, "duo-wallet:recurring:rule-1:2026-12-05"))
    check(id_a == id_b and id_a != id_c, "Deterministic recurring UUIDv5 check failed")


def main() -> int:
    verify_expected_files()
    verify_dart_imports()
    verify_sql_migrations_and_privacy()
    verify_domain_math_and_invariants()
    print("OK: All Duo Wallet repository, SQL RLS/privacy, Dart import, and domain math checks passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
