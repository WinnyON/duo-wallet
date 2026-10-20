import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/tables/tables.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/money/currency.dart';
import '../../../core/money/money.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _emailCtrl = TextEditingController(text: 'sam@duowallet.local');
  final _passwordCtrl = TextEditingController(text: '••••••••');
  final _householdNameCtrl = TextEditingController();
  final _inviteCodeCtrl = TextEditingController();
  final _displayNameCtrl = TextEditingController();
  final _contributionCtrl = TextEditingController();

  bool _isSignUp = false;
  bool _signedIn = true;
  String _selectedColor = '#4F46E5';
  String? _loadedUserId;

  static const _palette = [
    ('#4F46E5', 'Indigo'),
    ('#EC4899', 'Pink'),
    ('#10B981', 'Emerald'),
    ('#F59E0B', 'Amber'),
    ('#3B82F6', 'Blue'),
    ('#EF4444', 'Red'),
  ];

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _householdNameCtrl.dispose();
    _inviteCodeCtrl.dispose();
    _displayNameCtrl.dispose();
    _contributionCtrl.dispose();
    super.dispose();
  }

  void _syncProfileFields(Profile? profile, Household? hh) {
    if (profile == null || _loadedUserId == profile.id) return;
    _loadedUserId = profile.id;
    _displayNameCtrl.text = profile.displayName;
    _selectedColor = profile.color;
    final contribMajor = (profile.monthlyCommonContributionMinor ?? 0) ~/ 100;
    _contributionCtrl.text = contribMajor > 0 ? contribMajor.toString() : '';
    _householdNameCtrl.text = hh?.name ?? 'Sam & Anna';
    _inviteCodeCtrl.text = hh?.inviteCode ?? 'DUO-2026';
  }

  Color _parseHex(String hex) {
    final clean = hex.replaceAll('#', '');
    final val = int.tryParse('FF$clean', radix: 16) ?? 0xFF4F46E5;
    return Color(val);
  }

  void _switchDemoUser(String targetUserId) {
    final db = ref.read(appDatabaseProvider);
    final partnerId = targetUserId == 'user-sam' ? 'user-anna' : 'user-sam';
    ref.read(currentUserIdProvider.notifier).state = targetUserId;
    ref.read(partnerUserIdProvider.notifier).state = partnerId;
    final p = db.findProfile(targetUserId);
    if (p != null) {
      setState(() {
        _loadedUserId = null;
        _syncProfileFields(p, db.household);
      });
    }
  }

  void _saveProfile(AppDatabase db, Profile? existing) {
    final l10n = AppLocalizations.of(context);
    final meId = ref.read(currentUserIdProvider);
    final locale = ref.read(appLocaleProvider);
    final contribMajor =
        int.tryParse(_contributionCtrl.text.replaceAll(' ', '')) ?? 0;

    final updated = Profile(
      id: meId,
      householdId: db.household?.id ?? 'hh-default-001',
      displayName: _displayNameCtrl.text.trim().isEmpty
          ? (existing?.displayName ?? 'User')
          : _displayNameCtrl.text.trim(),
      color: _selectedColor,
      locale: locale,
      monthlyCommonContributionMinor: contribMajor > 0
          ? contribMajor * 100
          : null,
      updatedAt: DateTime.now(),
    );
    db.upsertProfile(updated);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.t('Profile saved', 'Profil mentve')),
      ),
    );
  }

  void _createOrUpdateHousehold(AppDatabase db) {
    final l10n = AppLocalizations.of(context);
    final existing = db.household;
    final name = _householdNameCtrl.text.trim().isEmpty
        ? 'Duo Household'
        : _householdNameCtrl.text.trim();
    final code = _inviteCodeCtrl.text.trim().isEmpty
        ? 'DUO-${DateTime.now().year}'
        : _inviteCodeCtrl.text.trim().toUpperCase();

    final hh = Household(
      id: existing?.id ?? const Uuid().v4(),
      name: name,
      baseCurrency: existing?.baseCurrency ?? CurrencyCode.huf,
      defaultSplitPct: existing?.defaultSplitPct ?? 50,
      inviteCode: code,
      emergencyFundMonths: existing?.emergencyFundMonths ?? 6,
      createdAt: existing?.createdAt ?? DateTime.now(),
    );
    db.upsertHousehold(hh);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          l10n.t(
            'Household updated (Invite: $code)',
            'Háztartás frissítve (Kód: $code)',
          ),
        ),
      ),
    );
  }

  void _joinByInviteCode(AppDatabase db) {
    final l10n = AppLocalizations.of(context);
    final code = _inviteCodeCtrl.text.trim().toUpperCase();
    if (db.profiles.length >= 2 &&
        code == (db.household?.inviteCode ?? 'DUO-2026')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.t(
              'Connected to household "${db.household?.name}" (2/2 members active). Sign-ups closed for 3rd member.',
              'Csatlakoztatva a "${db.household?.name}" háztartáshoz (2/2 tag aktív). Harmadik tag nem léphet be.',
            ),
          ),
        ),
      );
      return;
    }
    _createOrUpdateHousehold(db);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(dbTickProvider);
    final l10n = AppLocalizations.of(context);
    final db = ref.watch(appDatabaseProvider);
    final meId = ref.watch(currentUserIdProvider);
    final locale = ref.watch(appLocaleProvider);
    final hideAmounts = ref.watch(hideAmountsProvider);

    final meProfile = db.findProfile(meId);
    final hh = db.household;
    _syncProfileFields(meProfile, hh);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.t('Household & Profile', 'Háztartás és profil')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Active user / Privacy simulator card
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.verified_user_outlined),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l10n.t(
                            'Active Phone Session (Privacy Test Switch)',
                            'Aktív telefon munkamenet (Privát nézet teszt)',
                          ),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.t(
                      'Switch between Sam and Anna to verify that private accounts, individual expenses, and personal budgets/goals are strictly isolated per user.',
                      'Válts Sam és Anna között, hogy ellenőrizd: a privát számlák, egyéni kiadások és saját keretek szigorúan el vannak különítve.',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'user-sam',
                        icon: Icon(Icons.person),
                        label: Text('Sam'),
                      ),
                      ButtonSegment(
                        value: 'user-anna',
                        icon: Icon(Icons.person_outline),
                        label: Text('Anna'),
                      ),
                    ],
                    selected: {meId},
                    onSelectionChanged: (sel) => _switchDemoUser(sel.first),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Profile Editor Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.t('My Profile', 'Saját profil'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _displayNameCtrl,
                    decoration: InputDecoration(
                      labelText: l10n.t('Display Name', 'Megjelenített név'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.t('Avatar Color', 'Szín'),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: _palette.map((c) {
                      final selected = _selectedColor == c.$1;
                      return ChoiceChip(
                        avatar: CircleAvatar(backgroundColor: _parseHex(c.$1)),
                        label: Text(c.$2),
                        selected: selected,
                        onSelected: (_) => setState(() => _selectedColor = c.$1),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.t('App Language', 'Alkalmazás nyelve'),
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'en', label: Text('EN')),
                          ButtonSegment(value: 'hu', label: Text('HU')),
                        ],
                        selected: {locale.startsWith('hu') ? 'hu' : 'en'},
                        onSelectionChanged: (sel) {
                          ref.read(appLocaleProvider.notifier).state = sel.first;
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _contributionCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: l10n.t(
                        'Agreed Monthly Common Contribution (HUF)',
                        'Vállalt havi közös befizetés (Ft)',
                      ),
                      helperText: l10n.t(
                        'Tracked in Common Account cash-flow; never affects Settle-Up debt.',
                        'A közös számla cash-flow-ban követve; nem befolyásolja az elszámolást.',
                      ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => _saveProfile(db, meProfile),
                    icon: const Icon(Icons.save_outlined),
                    label: Text(l10n.t('Save Profile', 'Profil mentése')),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Household & Invite Code Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        l10n.t('Household (2 Members Max)', 'Háztartás (max. 2 tag)'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Chip(
                        avatar: const Icon(Icons.lock_outline, size: 16),
                        label: Text('${db.profiles.length}/2'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  for (final p in db.profiles)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: _parseHex(p.color),
                        foregroundColor: Colors.white,
                        child: Text(
                          p.displayName.isNotEmpty ? p.displayName[0] : '?',
                        ),
                      ),
                      title: Text(
                        '${p.displayName} ${p.id == meId ? "(${l10n.t("You", "Te")})" : ""}',
                      ),
                      subtitle: Text(
                        l10n.t(
                          'Agreed monthly contribution: ${Money(p.monthlyCommonContributionMinor ?? 0).format(locale: locale, hideAmounts: hideAmounts)}',
                          'Vállalt havi befizetés: ${Money(p.monthlyCommonContributionMinor ?? 0).format(locale: locale, hideAmounts: hideAmounts)}',
                        ),
                      ),
                    ),
                  const Divider(),
                  TextField(
                    controller: _householdNameCtrl,
                    decoration: InputDecoration(
                      labelText: l10n.t('Household Name', 'Háztartás neve'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _inviteCodeCtrl,
                    decoration: InputDecoration(
                      labelText: l10n.t('Invite Code', 'Meghívókód'),
                      border: const OutlineInputBorder(),
                      suffixIcon: const Icon(Icons.vpn_key_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: () => _createOrUpdateHousehold(db),
                        icon: const Icon(Icons.home_outlined),
                        label: Text(
                          l10n.t(
                            'Create / Update Household',
                            'Háztartás létrehozása / mentése',
                          ),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _joinByInviteCode(db),
                        icon: const Icon(Icons.group_add_outlined),
                        label: Text(
                          l10n.t('Join by Code', 'Csatlakozás kóddal'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Cloud Auth Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        l10n.t('Supabase Auth & Sync', 'Supabase belépés és szinkron'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Chip(
                        label: Text(
                          _signedIn
                              ? l10n.t('Connected', 'Csatlakozva')
                              : l10n.t('Offline Mode', 'Offline mód'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: l10n.t('Email', 'E-mail cím'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passwordCtrl,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: l10n.t('Password', 'Jelszó'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      FilledButton(
                        onPressed: () {
                          setState(() => _signedIn = true);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                _isSignUp
                                    ? l10n.t('Account registered', 'Fiók regisztrálva')
                                    : l10n.t('Signed in', 'Bejelentkezve'),
                              ),
                            ),
                          );
                        },
                        child: Text(
                          _isSignUp
                              ? l10n.t('Sign Up', 'Regisztráció')
                              : l10n.t('Sign In', 'Bejelentkezés'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      TextButton(
                        onPressed: () => setState(() => _isSignUp = !_isSignUp),
                        child: Text(
                          _isSignUp
                              ? l10n.t(
                                  'Already have an account? Sign In',
                                  'Már van fiókod? Belépés',
                                )
                              : l10n.t(
                                  'Need an account? Sign Up',
                                  'Nincs még fiókod? Regisztráció',
                                ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
