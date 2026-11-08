import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../../core/auth/backend_session.dart';
import '../../../core/auth/cloud_status.dart';
import '../../../core/db/tables/tables.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../router.dart';
import '../../../core/notifications/alert_rules.dart';
import '../../../theme.dart';
import '../../widget/home_widget_bridge.dart';

final appLockEnabledProvider = StateProvider<bool>((ref) => false);

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  List<LocalAlert>? _evaluatedAlerts;

  @override
  Widget build(BuildContext context) {
    ref.watch(dbTickProvider);
    final db = ref.watch(appDatabaseProvider);
    final meId = ref.watch(currentUserIdProvider);
    final locale = ref.watch(appLocaleProvider);
    final hideAmounts = ref.watch(hideAmountsProvider);
    final l10n = AppLocalizations.of(context);

    final hh = db.household;
    final defaultSplit = hh?.defaultSplitPct ?? 50;

    return Scaffold(
      appBar: AppBar(
          leading: BackButton(onPressed: () => AppShell.goBackOrHome(context)),
          title: Text(l10n.settings)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (ref.watch(productionModeProvider))
            const CloudStatusCard()
          else
            Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(l10n.t('Demo • local data • cloud sync unavailable',
                    'Demó • helyi adatok • felhőszinkron nem elérhető'))),
          DuoSection(
            child: Padding(
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.t('Language & Formatting', 'Nyelv és formátum'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, children: [
                    for (final language in [
                      ('en', 'English'),
                      ('hu', 'Magyar')
                    ])
                      ChoiceChip(
                          label: Text(language.$2),
                          selected: locale.startsWith(language.$1),
                          onSelected: (_) {
                            ref.read(appLocaleProvider.notifier).state =
                                language.$1;
                            if (ref.read(productionModeProvider)) {
                              final profile = db.findProfile(meId);
                              if (profile != null) {
                                db.upsertProfile(Profile.fromJson({
                                  ...profile.toJson(),
                                  'locale': language.$1
                                }));
                              }
                            }
                          }),
                  ]),
                  const SizedBox(height: 16),
                  Text(l10n.t(
                      'Reports use HUF. Accounts and goals keep their own currency.',
                      'A jelentések HUF-ban jelennek meg. A számlák és célok megtartják saját pénznemüket.')),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          DuoSection(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.visibility_off_outlined),
                  title: Text(l10n.t(
                      'Hide amounts (Privacy mask)', 'Összegek elrejtése')),
                  subtitle: Text(
                    l10n.t(
                      'Masks amounts in summaries and activity. Opening an editor reveals its values.',
                      'Elrejti az összegeket az összesítésekben és tevékenységekben. A szerkesztő megnyitásakor az értékek láthatók.',
                    ),
                  ),
                  value: hideAmounts,
                  onChanged: (v) {
                    ref.read(hideAmountsProvider.notifier).state = v;
                    HomeWidgetBridge.buildSnapshot(
                      db: db,
                      meId: meId,
                      hideAmounts: v,
                      now: DateTime.now(),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          DuoSection(
            child: Padding(
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.t('Sharing defaults', 'Megosztási alapbeállítások'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.t(
                      'Default Together Split: $defaultSplit% / ${100 - defaultSplit}%',
                      'Alapértelmezett közös megosztás: $defaultSplit% / ${100 - defaultSplit}%',
                    ),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Slider(
                    value: defaultSplit.toDouble(),
                    min: 0,
                    max: 100,
                    divisions: 20,
                    label: '$defaultSplit%',
                    onChanged: hh == null
                        ? null
                        : (v) {
                            db.upsertHousehold(
                              Household(
                                id: hh.id,
                                name: hh.name,
                                baseCurrency: hh.baseCurrency,
                                defaultSplitPct: v.round(),
                                inviteCode: hh.inviteCode,
                                emergencyFundMonths: hh.emergencyFundMonths,
                                createdAt: hh.createdAt,
                              ),
                            );
                          },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          DuoCard(
            padding: const EdgeInsets.all(16),
            child: Padding(
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.t('Local Reminders & Alerts',
                        'Helyi értesítések és emlékeztetők'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.t(
                      'Checks local demo data when requested. These are previews, not scheduled notifications.',
                      'Kérésre ellenőrzi a helyi demóadatokat. Ezek előnézetek, nem ütemezett értesítések.',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: () {
                      setState(() {
                        _evaluatedAlerts = evaluateAlertRules(
                          db: db,
                          meId: meId,
                          now: DateTime.now(),
                        );
                      });
                    },
                    icon: const Icon(Icons.notifications_active_outlined),
                    label: Text(l10n.t(
                        'Check Alert Rules Now', 'Szabályok ellenőrzése most')),
                  ),
                  if (_evaluatedAlerts != null) ...[
                    const SizedBox(height: 8),
                    if (_evaluatedAlerts!.isEmpty)
                      Text(l10n.t('No active alerts.', 'Nincs aktív riasztás.'))
                    else
                      for (final a in _evaluatedAlerts!)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading:
                              const Icon(Icons.notification_important_outlined),
                          title: Text(l10n.isHu ? a.titleHu : a.titleEn),
                          subtitle: Text(hideAmounts
                              ? l10n.t('Details hidden by privacy mask.',
                                  'A részleteket az adatvédelmi maszk elrejti.')
                              : (l10n.isHu ? a.bodyHu : a.bodyEn)),
                        ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          DuoSection(
            child: Padding(
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.t('App updates', 'Alkalmazásfrissítések'),
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(l10n.t(
                      'Install updates from the official Duo Wallet download page. Automatic update checking is not available in this version.',
                      'A frissítéseket a Duo Wallet hivatalos letöltési oldaláról telepítheted. Ez a verzió még nem keres automatikusan frissítéseket.')),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
