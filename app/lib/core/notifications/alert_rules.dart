import '../db/app_database.dart';
import '../db/tables/tables.dart';
import '../domain/views.dart';

class LocalAlert {
  final String dedupKey;
  final String titleEn;
  final String titleHu;
  final String bodyEn;
  final String bodyHu;

  const LocalAlert({
    required this.dedupKey,
    required this.titleEn,
    required this.titleHu,
    required this.bodyEn,
    required this.bodyHu,
  });
}

/// Evaluates local reminder & threshold rules from visible data only:
/// - Budget thresholds (50%, 80%, 100%)
/// - Settlement waiting for confirmation
/// - Upcoming recurring bills
/// - Goal milestones (50%, 100%)
List<LocalAlert> evaluateAlertRules({
  required AppDatabase db,
  required String meId,
  required DateTime now,
}) {
  final alerts = <LocalAlert>[];
  final monthKey = '${now.year}-${now.month.toString().padLeft(2, '0')}';

  // 1. Budgets (50 / 80 / 100%)
  for (final b in db.budgets) {
    if (b.scope == Scope.individual && b.ownerId != meId) continue;
    final view =
        b.scope == Scope.together ? ExpenseView.together : ExpenseView.myTotal;
    var spent = 0;
    for (final t in db.transactions) {
      if (t.occurredOn.year == now.year && t.occurredOn.month == now.month) {
        if (b.categoryId == null || t.categoryId == b.categoryId) {
          spent += amountFor(t, view, meId);
        }
      }
    }
    if (b.amountMinor <= 0) continue;
    final ratio = spent / b.amountMinor;
    for (final threshold in [100, 80, 50]) {
      if (ratio >= threshold / 100.0) {
        final labelEn = b.scope == Scope.together ? 'Together budget' : 'My budget';
        final labelHu = b.scope == Scope.together ? 'Közös keret' : 'Saját keret';
        alerts.add(
          LocalAlert(
            dedupKey: 'budget_${b.id}_${monthKey}_$threshold',
            titleEn: '$labelEn reached $threshold%',
            titleHu: '$labelHu elérte a $threshold%-ot',
            bodyEn: 'You have used ${(ratio * 100).round()}% of your monthly budget.',
            bodyHu: 'A havi keret ${(ratio * 100).round()}%-át felhasználtad.',
          ),
        );
        break;
      }
    }
  }

  // 2. Pending settlements waiting for my confirmation
  for (final s in db.settlements) {
    if (s.rejectedBy != null || s.isConfirmed) continue;
    final needsMyConfirm =
        (s.fromUser == meId && !s.fromConfirmed) ||
        (s.toUser == meId && !s.toConfirmed);
    if (needsMyConfirm) {
      alerts.add(
        LocalAlert(
          dedupKey: 'settlement_confirm_${s.id}',
          titleEn: 'Settlement awaiting your confirmation',
          titleHu: 'Elszámolás jóváhagyásra vár',
          bodyEn: 'Tap to review and confirm the proposed settlement.',
          bodyHu: 'Koppints a javasolt elszámolás áttekintéséhez és jóváhagyásához.',
        ),
      );
    }
  }

  // 3. Goal milestones (50% / 100%)
  for (final g in db.goals) {
    if (!g.isShared && g.ownerId != meId) continue;
    if (g.targetAmountMinor <= 0) continue;
    final pct = (g.savedAmountMinor * 100) ~/ g.targetAmountMinor;
    if (pct >= 100 || pct >= 50) {
      final mile = pct >= 100 ? 100 : 50;
      alerts.add(
        LocalAlert(
          dedupKey: 'goal_${g.id}_$mile',
          titleEn: '${g.name} reached $mile%!',
          titleHu: '${g.name} elérte a $mile%-ot!',
          bodyEn: 'Great progress toward your goal.',
          bodyHu: 'Remek haladás a kitűzött cél felé.',
        ),
      );
    }
  }

  return alerts;
}
