import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../../core/auth/backend_session.dart';
import '../../../core/auth/cloud_status.dart';
import '../../../core/db/tables/tables.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../router.dart';
import '../../../core/money/money.dart';
import '../../../theme.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _nameFocus = FocusNode();
  final _amountFocus = FocusNode();
  final _urlFocus = FocusNode();
  final _householdFocus = FocusNode();
  final _nameField = GlobalKey<FormFieldState<String>>();
  final _amountField = GlobalKey<FormFieldState<String>>();
  final _urlField = GlobalKey<FormFieldState<String>>();
  final _householdField = GlobalKey<FormFieldState<String>>();
  final _name = TextEditingController();
  final _contribution = TextEditingController();
  final _url = TextEditingController();
  final _householdName = TextEditingController();
  String? _loaded;
  String _color = '#4F46E5';
  String _avatar = 'initials';
  String _initial = '';
  bool _discardAuthorized = false;
  String get _draft => [
        _name.text,
        _contribution.text,
        _url.text,
        _householdName.text,
        _color,
        _avatar
      ].join('\u0000');
  bool get _dirty => _draft != _initial;

  void _load(Profile? profile, Household? household, String id) {
    if (_loaded == id) return;
    _loaded = id;
    _name.text = profile?.displayName ?? '';
    _contribution.text = profile?.monthlyCommonContributionMinor == null
        ? ''
        : ((profile!.monthlyCommonContributionMinor!) / 100).toStringAsFixed(2);
    _url.text = profile?.avatarUrl ?? '';
    _householdName.text = household?.name ?? '';
    _color = profile?.color ?? '#4F46E5';
    _avatar = profile?.avatarType ?? 'initials';
    _initial = _draft;
  }

  @override
  void dispose() {
    for (final controller in [_name, _contribution, _url, _householdName]) {
      controller.dispose();
    }
    for (final node in [_nameFocus, _amountFocus, _urlFocus, _householdFocus]) {
      node.dispose();
    }
    super.dispose();
  }

  void _save(AppDatabase db, Profile? profile) {
    if (!_form.currentState!.validate()) {
      for (final field in [
        (_urlField, _urlFocus),
        (_nameField, _nameFocus),
        (_amountField, _amountFocus),
        (_householdField, _householdFocus)
      ]) {
        if (field.$1.currentState?.hasError ?? false) {
          field.$2.requestFocus();
          Scrollable.ensureVisible(field.$1.currentContext!, alignment: .2);
          break;
        }
      }
      return;
    }
    final household = db.household;
    if (household == null) return;
    db.upsertProfile(Profile(
      id: ref.read(currentUserIdProvider),
      householdId: profile?.householdId ?? household.id,
      displayName: _name.text.trim(),
      color: _color,
      locale: ref.read(appLocaleProvider),
      monthlyCommonContributionMinor: _contribution.text.trim().isEmpty
          ? null
          : (parsePositiveAmount(_contribution.text, allowZero: true)! * 100)
              .round(),
      avatarType: _avatar,
      avatarUrl: _url.text.trim().isEmpty ? null : _url.text.trim(),
      updatedAt: DateTime.now(),
    ));
    db.upsertHousehold(Household(
        id: household.id,
        name: _householdName.text.trim(),
        baseCurrency: household.baseCurrency,
        defaultSplitPct: household.defaultSplitPct,
        inviteCode: household.inviteCode,
        emergencyFundMonths: household.emergencyFundMonths,
        createdAt: household.createdAt));
    setState(() => _initial = _draft);
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l10n.t('Local profile saved', 'Helyi profil mentve'))));
  }

  Future<void> _close() async {
    if (await confirmDiscardChanges(context, dirty: _dirty) && mounted) {
      setState(() => _discardAuthorized = true);
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) AppShell.goBackOrHome(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(dbTickProvider);
    final db = ref.watch(appDatabaseProvider);
    final id = ref.watch(currentUserIdProvider);
    final profile = db.findProfile(id);
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(appLocaleProvider);
    final hidden = ref.watch(hideAmountsProvider);
    _load(profile, db.household, id);
    final colors = [
      ('#4F46E5', l10n.t('Indigo', 'Indigó')),
      ('#EC4899', l10n.t('Pink', 'Rózsaszín')),
      ('#10B981', l10n.t('Emerald', 'Smaragd')),
      ('#F59E0B', l10n.t('Amber', 'Borostyán')),
      ('#3B82F6', l10n.t('Blue', 'Kék')),
      ('#EF4444', l10n.t('Red', 'Piros'))
    ];
    return PopScope(
      canPop: !_dirty || _discardAuthorized,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        appBar: AppBar(
            leading: BackButton(onPressed: _close),
            title: Text(l10n.t('Household & Profile', 'Háztartás és profil'))),
        body: Form(
            key: _form,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              if (ref.watch(productionModeProvider))
                const CloudStatusCard()
              else
                Card(
                    child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  l10n.t('Demo • local data',
                                      'Demó • helyi adatok'),
                                  style:
                                      Theme.of(context).textTheme.titleMedium),
                              const SizedBox(height: 8),
                              Text(l10n.t(
                                  'Changes affect this local demo. Sign-in, joining a household and cloud sync are unavailable. Data is not a durable backup.',
                                  'A módosítások a helyi demót érintik. A belépés, a háztartáshoz csatlakozás és a felhőszinkron nem elérhető. Az adatok nem tartós biztonsági mentések.')),
                            ]))),
              const SizedBox(height: 12),
              Card(
                  child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(l10n.t('My profile', 'Saját profil'),
                                style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 16),
                            UserAvatar(
                                avatarType: _avatar,
                                avatarUrl: _url.text,
                                name: _name.text,
                                size: 64,
                                color: Color(int.tryParse(
                                        _color.replaceFirst('#', 'FF'),
                                        radix: 16) ??
                                    0xFF4F46E5)),
                            const SizedBox(height: 12),
                            Wrap(spacing: 8, runSpacing: 8, children: [
                              for (final choice in [
                                ('initials', l10n.t('Initials', 'Monogram')),
                                ('man', l10n.t('Face 1', 'Arc 1')),
                                ('woman', l10n.t('Face 2', 'Arc 2')),
                                ('image', l10n.t('Photo URL', 'Kép URL'))
                              ])
                                ChoiceChip(
                                    label: Text(choice.$2),
                                    selected: _avatar == choice.$1,
                                    onSelected: (_) =>
                                        setState(() => _avatar = choice.$1)),
                            ]),
                            if (_avatar == 'image') ...[
                              const SizedBox(height: 12),
                              TextFormField(
                                  key: _urlField,
                                  focusNode: _urlFocus,
                                  controller: _url,
                                  onChanged: (_) => setState(() {}),
                                  decoration: InputDecoration(
                                      labelText: l10n.t('Optional photo URL',
                                          'Opcionális kép URL')),
                                  validator: (text) {
                                    if (text == null || text.trim().isEmpty) {
                                      return null;
                                    }
                                    final uri = Uri.tryParse(text.trim());
                                    return uri != null &&
                                            ['http', 'https']
                                                .contains(uri.scheme) &&
                                            uri.host.isNotEmpty
                                        ? null
                                        : l10n.t('Enter a valid web address.',
                                            'Adj meg érvényes webcímet.');
                                  }),
                            ],
                            const SizedBox(height: 12),
                            TextFormField(
                                key: _nameField,
                                focusNode: _nameFocus,
                                controller: _name,
                                onChanged: (_) => setState(() {}),
                                decoration: InputDecoration(
                                    labelText: l10n.t(
                                        'Display name', 'Megjelenített név')),
                                validator: (value) => value == null ||
                                        value.trim().isEmpty
                                    ? l10n.t(
                                        'Enter a name.', 'Adj meg egy nevet.')
                                    : null),
                            const SizedBox(height: 12),
                            Wrap(spacing: 8, runSpacing: 8, children: [
                              for (final color in colors)
                                ChoiceChip(
                                    label: Text(color.$2),
                                    selected: _color == color.$1,
                                    onSelected: (_) =>
                                        setState(() => _color = color.$1))
                            ]),
                            const SizedBox(height: 12),
                            TextFormField(
                                key: _amountField,
                                focusNode: _amountFocus,
                                controller: _contribution,
                                onChanged: (_) => setState(() {}),
                                keyboardType: const TextInputType.numberWithOptions(
                                    decimal: true),
                                decoration: InputDecoration(
                                    labelText: l10n.t(
                                        'Monthly common contribution (HUF)',
                                        'Havi közös befizetés (HUF)'),
                                    helperText: l10n.t(
                                        'Optional agreement; does not change debt.',
                                        'Opcionális megállapodás; nem módosítja a tartozást.')),
                                validator: (value) => value == null ||
                                        value.trim().isEmpty ||
                                        parsePositiveAmount(value, allowZero: true) !=
                                            null
                                    ? null
                                    : l10n.t(
                                        'Enter a valid non-negative amount.',
                                        'Adj meg érvényes, nem negatív összeget.')),
                            const SizedBox(height: 12),
                            Text(l10n.t('Language', 'Nyelv')),
                            Wrap(spacing: 8, children: [
                              for (final language in [
                                ('en', 'English'),
                                ('hu', 'Magyar')
                              ])
                                ChoiceChip(
                                    label: Text(language.$2),
                                    selected: locale.startsWith(language.$1),
                                    onSelected: (_) => ref
                                        .read(appLocaleProvider.notifier)
                                        .state = language.$1)
                            ]),
                          ]))),
              const SizedBox(height: 12),
              Card(
                  child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(l10n.t('Local household', 'Helyi háztartás'),
                                style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 12),
                            TextFormField(
                                key: _householdField,
                                focusNode: _householdFocus,
                                controller: _householdName,
                                onChanged: (_) => setState(() {}),
                                decoration: InputDecoration(
                                    labelText: l10n.t(
                                        'Household name', 'Háztartás neve')),
                                validator: (value) =>
                                    value == null || value.trim().isEmpty
                                        ? l10n.t('Enter a household name.',
                                            'Add meg a háztartás nevét.')
                                        : null),
                            for (final member in db.profiles)
                              ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(member.displayName),
                                  subtitle: Text(Money(member
                                              .monthlyCommonContributionMinor ??
                                          0)
                                      .format(
                                          locale: locale,
                                          hideAmounts: hidden))),
                            Text(l10n.t(
                                ref.watch(productionModeProvider)
                                    ? 'Share this household’s invite code with your partner to join securely.'
                                    : 'Joining by invite code is unavailable in this demo.',
                                ref.watch(productionModeProvider)
                                    ? 'A párod a háztartás meghívókódjával csatlakozhat biztonságosan.'
                                    : 'A meghívókódos csatlakozás ebben a demóban nem elérhető.')),
                          ]))),
              const SizedBox(height: 12),
              FilledButton.icon(
                  onPressed: db.household == null || !_dirty
                      ? null
                      : () => _save(db, profile),
                  icon: const Icon(Icons.save_outlined),
                  label: Text(l10n.t(
                      'Save local changes', 'Helyi módosítások mentése'))),
              if (db.household == null)
                Text(l10n.t('No local household is available.',
                    'Nem érhető el helyi háztartás.')),
              const SizedBox(height: 12),
              if (!ref.watch(productionModeProvider))
                Card(
                    child: ExpansionTile(
                        title: Text(l10n.t('Demo tools', 'Demó eszközök')),
                        subtitle: Text(l10n.t('Switch local test identity',
                            'Helyi tesztfelhasználó váltása')),
                        children: [
                      for (final member in db.profiles)
                        ListTile(
                            title: Text(member.displayName),
                            selected: id == member.id,
                            onTap: () async {
                              if (id == member.id ||
                                  !await confirmDiscardChanges(context,
                                      dirty: _dirty) ||
                                  !mounted) {
                                return;
                              }
                              ref.read(currentUserIdProvider.notifier).state =
                                  member.id;
                              final other =
                                  db.profiles.where((p) => p.id != member.id);
                              if (other.isNotEmpty) {
                                ref.read(partnerUserIdProvider.notifier).state =
                                    other.first.id;
                              }
                              setState(() => _loaded = null);
                            }),
                    ])),
            ])),
      ),
    );
  }
}
