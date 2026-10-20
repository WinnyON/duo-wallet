import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/db/app_database.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/money/money.dart';

class ActivityScreen extends ConsumerWidget {
  const ActivityScreen({super.key});

  IconData _iconForEvent(String eventType) => switch (eventType) {
    'expense_added' => Icons.receipt_long_outlined,
    'settlement_proposed' => Icons.send_outlined,
    'settlement_confirmed' => Icons.handshake_outlined,
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
      appBar: AppBar(title: Text(l10n.activity)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.lock_outline, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.t(
                        'Only shared 👥 events appear here (Together expenses, settlements, shared goals, and common-account contributions). Private actions never generate activity entries.',
                        'Itt csak a közös 👥 események jelennek meg (Közös kiadások, elszámolások, közös célok és befizetések). A privát műveletek nem kerülnek a hírfolyamba.',
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
                leading: CircleAvatar(
                  child: Icon(_iconForEvent(act.eventType)),
                ),
                title: Text(act.localizedSummary(localeStr)),
                subtitle: Text(
                  DateFormat('yyyy-MM-dd HH:mm').format(act.createdAt),
                ),
                trailing: act.amountMinor != null
                    ? Text(
                        Money(act.amountMinor!, act.currency).format(
                          locale: localeStr,
                          hideAmounts: hideAmounts,
                        ),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      )
                    : null,
              ),
            ),
        ],
      ),
    );
  }
}
