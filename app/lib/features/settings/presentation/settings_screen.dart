import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/tables/tables.dart';
import '../../../core/env.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/money/currency.dart';
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
  String? _updaterStatus;
  List<LocalAlert>? _evaluatedAlerts;

  @override
  Widget build(BuildContext context) {
    ref.watch(dbTickProvider);
    final db = ref.watch(appDatabaseProvider);
    final meId = ref.watch(currentUserIdProvider);
    final locale = ref.watch(appLocaleProvider);
    final displayCurrency = ref.watch(displayCurrencyProvider);
    final hideAmounts = ref.watch(hideAmountsProvider);
    final appLock = ref.watch(appLockEnabledProvider);
    final themeMode = ref.watch(themeModeProvider);
    final l10n = AppLocalizations.of(context);

    final hh = db.household;
    final defaultSplit = hh?.defaultSplitPct ?? 50;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settings)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.t('Language & Formatting', 'Nyelv és formátum'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'en', label: Text('English (EN)')),
                      ButtonSegment(value: 'hu', label: Text('Magyar (HU)')),
                    ],
                    selected: {locale},
                    onSelectionChanged: (s) {
                      ref.read(appLocaleProvider.notifier).state = s.first;
                    },
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.t('Display Currency (Reports)', 'Megjelenítési pénznem'),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<CurrencyCode>(
                    segments: const [
                      ButtonSegment(value: CurrencyCode.huf, label: Text('HUF (Ft)')),
                      ButtonSegment(value: CurrencyCode.eur, label: Text('EUR (€)')),
                      ButtonSegment(value: CurrencyCode.ron, label: Text('RON (lei)')),
                    ],
                    selected: {displayCurrency},
                    onSelectionChanged: (s) {
                      ref.read(displayCurrencyProvider.notifier).state = s.first;
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.visibility_off_outlined),
                  title: Text(l10n.t('Hide amounts (Privacy mask)', 'Összegek elrejtése')),
                  subtitle: Text(
                    l10n.t(
                      'Masks balances on screens and the Android home-screen widget (••••)',
                      'Elrejti az egyenlegeket a képernyőn és a kezdőképernyő widgeten (••••)',
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
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.fingerprint),
                  title: Text(l10n.t('App Lock (Biometric / PIN)', 'Alkalmazászár (Ujjlenyomat / PIN)')),
                  subtitle: Text(
                    l10n.t(
                      'Require fingerprint or device PIN when unlocking Duo Wallet',
                      'Ujjlenyomat vagy PIN kód kérése megnyitáskor',
                    ),
                  ),
                  value: appLock,
                  onChanged: (v) => ref.read(appLockEnabledProvider.notifier).state = v,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.t('Theme & Appearance', 'Téma és megjelenés'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<ThemeMode>(
                    segments: [
                      ButtonSegment(
                        value: ThemeMode.system,
                        label: Text(l10n.t('System', 'Rendszer')),
                      ),
                      ButtonSegment(
                        value: ThemeMode.light,
                        label: Text(l10n.t('Light', 'Világos')),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        label: Text(l10n.t('Dark', 'Sötét')),
                      ),
                    ],
                    selected: {themeMode},
                    onSelectionChanged: (s) {
                      ref.read(themeModeProvider.notifier).state = s.first;
                    },
                  ),
                  const SizedBox(height: 16),
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
                    onChanged: (v) {
                      if (hh == null) return;
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
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.t('Local Reminders & Alerts', 'Helyi értesítések és emlékeztetők'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.t(
                      'Evaluated locally after background sync (budget 50/80/100%, pending settlements, goal milestones).',
                      'Szinkronizálás után helyben kiértékelt szabályok (keret 50/80/100%, függő elszámolás, célok).',
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
                    label: Text(l10n.t('Check Alert Rules Now', 'Szabályok ellenőrzése most')),
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
                          leading: const Icon(Icons.notification_important_outlined),
                          title: Text(l10n.isHu ? a.titleHu : a.titleEn),
                          subtitle: Text(l10n.isHu ? a.bodyHu : a.bodyEn),
                        ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.t('In-App APK Updater (Sideload)', 'Alkalmazáson belüli APK frissítő'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Manifest: ${Env.releaseManifestUrl}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _updaterStatus = Env.isConfigured
                            ? l10n.t(
                                'Up to date (v1.0.0+1 — signed with release keystore).',
                                'Naprakész (v1.0.0+1 — kiadási kulccsal aláírva).',
                              )
                            : l10n.t(
                                'Offline / Demo mode: v1.0.0+1 installed. Configure RELEASE_MANIFEST_URL to enable OTA APK updates.',
                                'Offline / Demó mód: v1.0.0+1 telepítve.',
                              );
                      });
                    },
                    icon: const Icon(Icons.system_update_outlined),
                    label: Text(l10n.t('Check for APK Updates', 'APK frissítés keresése')),
                  ),
                  if (_updaterStatus != null) ...[
                    const SizedBox(height: 8),
                    Text(_updaterStatus!, style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
