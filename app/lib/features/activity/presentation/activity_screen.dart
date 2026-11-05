import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/db/app_database.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/money/money.dart';
import '../../../theme.dart';
import '../../../router.dart';

class ActivityScreen extends ConsumerWidget {
  const ActivityScreen({super.key});

  IconData _iconForEvent(String eventType) => switch (eventType) {
        'expense_added' => Icons.receipt_long_outlined,
        'settlement_proposed' => Icons.send_outlined,
        'settlement_confirmed' => Icons.check_circle_outline_rounded,
        'goal_milestone' => Icons.flag_outlined,
        'contribution_added' => Icons.account_balance_outlined,
        _ => Icons.notifications_none_outlined,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(dbTickProvider);
    final db = ref.watch(appDatabaseProvider);
    final hideAmounts = ref.watch(hideAmountsProvider);
    final l10n = AppLocalizations.of(context);
    final localeStr = l10n.locale.languageCode;

    final sharedEventTypes = {
      'expense_added',
      'settlement_proposed',
      'settlement_confirmed',
      'goal_milestone',
      'contribution_added',
    };
    final activities = db.activities
        .where((a) => sharedEventTypes.contains(a.eventType))
        .toList();

    return Scaffold(
      appBar: AppBar(
          leading: IconButton(
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              icon: const Icon(Icons.arrow_back),
              onPressed: () => AppShell.goBackOrHome(context)),
          title: Text(l10n.activity)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const DuoIconBox(Icons.lock_outline),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l10n.t(
                        'Only shared events appear here (Together expenses, settlements, shared goals, and common-account contributions). Private actions never generate activity entries.',
                        'Itt csak a közös események jelennek meg (Közös kiadások, elszámolások, közös célok és befizetések). A privát műveletek nem kerülnek a hírfolyamba.',
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (activities.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  l10n.t(
                    'No shared activity yet.',
                    'Még nincs közös aktivitás.',
                  ),
                ),
              ),
            ),
          for (final act in activities)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: MerchantAvatar(
                  name: act.eventType,
                  icon: _iconForEvent(act.eventType),
                ),
                title: Text(
                  activityDisplaySummary(act,
                      locale: localeStr, hideAmounts: hideAmounts),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(DateFormat.yMMMd(localeStr)
                          .add_Hm()
                          .format(act.createdAt)),
                      if (act.amountMinor != null)
                        Text(
                            Money(act.amountMinor!, act.currency).format(
                                locale: localeStr, hideAmounts: hideAmounts),
                            style: Theme.of(context).textTheme.titleSmall),
                    ]),
              ),
            ),
        ],
      ),
    );
  }
}
