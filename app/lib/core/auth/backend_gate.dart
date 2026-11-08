import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../l10n/generated/app_localizations.dart';
import 'backend_session.dart';
import 'password_policy.dart';

class BackendGate extends ConsumerWidget {
  const BackendGate({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(backendSessionProvider);
    final l = AppLocalizations.of(context);
    if (session.loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!session.configured) {
      return Scaffold(
          body: SafeArea(
              child: Center(
                  child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(l.t(
                          'Cloud connection is not configured. Start Duo Wallet with its Supabase project URL and publishable key. Demo mode must be selected explicitly.',
                          'Nincs beállítva a felhőkapcsolat. A Duo Wallet indításához Supabase projekt URL és publikus kulcs szükséges. A demó módot külön kell kiválasztani.'))))));
    }
    if (session.recovery) return const EmailAuthScreen(recovery: true);
    if (!session.verified) return const EmailAuthScreen();
    if (session.db.household == null) {
      if (session.error != null) {
        return Scaffold(
            body: SafeArea(
                child: Center(
                    child: Padding(
                        padding: const EdgeInsets.all(24),
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(l.t(
                              'Your data could not be loaded. Retry the secure connection.',
                              'Nem sikerült betölteni az adatokat. Próbáld újra a biztonságos kapcsolódást.')),
                          FilledButton(
                              onPressed: session.retryLoad,
                              child: Text(l.t('Retry', 'Újra'))),
                          TextButton(
                              onPressed: session.signOut,
                              child: Text(l.t('Sign out', 'Kijelentkezés'))),
                        ])))));
      }
      return const HouseholdSetupScreen();
    }
    return child;
  }
}

class EmailAuthScreen extends ConsumerStatefulWidget {
  const EmailAuthScreen({super.key, this.recovery = false});
  final bool recovery;
  @override
  ConsumerState<EmailAuthScreen> createState() => _EmailAuthScreenState();
}

class _EmailAuthScreenState extends ConsumerState<EmailAuthScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _register = false, _busy = false, _showPassword = false;
  String? _status;
  bool _failed = false;
  static const redirect = 'com.duowallet.app://auth/callback';
  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    final backend = ref.read(backendSessionProvider);
    final auth = backend.client!.auth;
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      if (widget.recovery) {
        await auth.updateUser(UserAttributes(password: _password.text));
        backend.recovery = false;
        await backend.retryLoad();
      } else if (_register) {
        await auth
            .signUp(
                email: _email.text.trim(),
                password: _password.text,
                emailRedirectTo: redirect)
            .timeout(const Duration(seconds: 20));
        if (mounted) {
          setState(() {
            _failed = false;
            _status = AppLocalizations.of(context).t(
                'Check your inbox and spam folder for a confirmation link. Already registered? Sign in, or use Forgot password to get back into your account.',
                'Keresd a megerősítő linket a beérkező levelek és a spam között. Már regisztráltál? Jelentkezz be, vagy válaszd az Elfelejtetted a jelszavad? lehetőséget.');
          });
        }
      } else {
        await auth
            .signInWithPassword(
                email: _email.text.trim(), password: _password.text)
            .timeout(const Duration(seconds: 20));
      }
      if (mounted) {
        _password.clear();
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _failed = true;
          _status = _authError(error);
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _authError(Object error) {
    final l = AppLocalizations.of(context);
    final code = error is AuthException ? error.code : null;
    if (code == 'over_email_send_rate_limit' ||
        code == 'over_request_rate_limit' ||
        (error is AuthException && error.statusCode == '429')) {
      return l.t(
          'Too many attempts. Wait a minute before trying again. If emails still do not arrive, contact support.',
          'Túl sok próbálkozás. Várj egy percet, majd próbáld újra. Ha továbbra sem érkezik e-mail, kérj segítséget.');
    }
    if (code == 'email_not_confirmed') {
      return l.t(
          'Confirm your email first. Check spam, or tap Resend confirmation email.',
          'Előbb erősítsd meg az e-mail-címed. Nézd meg a spam mappát, vagy kérj új megerősítő e-mailt.');
    }
    if (code == 'invalid_credentials') {
      return l.t(
          'Email or password is incorrect. Try again or reset your password.',
          'Hibás e-mail-cím vagy jelszó. Próbáld újra, vagy állítsd vissza a jelszavad.');
    }
    if (code == 'weak_password') {
      return l.t(
          'This password was rejected. Use at least 8 characters or try a different password.',
          'A jelszót a rendszer elutasította. Használj legalább 8 karaktert, vagy válassz másik jelszót.');
    }
    if (code == 'unexpected_failure' ||
        (error is AuthException && error.statusCode == '500')) {
      return l.t(
          'The server could not complete the request. Email delivery may be unavailable. Please try again later.',
          'A szerver nem tudta teljesíteni a kérést. Az e-mail-küldés nem biztos, hogy elérhető. Próbáld újra később.');
    }
    if (error is TimeoutException) {
      return l.t(
          'The request timed out. Check your connection. If you requested an email, check your inbox before retrying.',
          'A kérés túllépte az időkorlátot. Ellenőrizd a kapcsolatot. Ha e-mailt kértél, újabb próbálkozás előtt nézd meg a beérkező leveleket.');
    }
    return l.t(
        'Could not connect. Check your internet connection and try again.',
        'Nem sikerült kapcsolódni. Ellenőrizd az internetkapcsolatot, majd próbáld újra.');
  }

  Future<void> _reset({bool confirmation = false}) async {
    final l = AppLocalizations.of(context);
    if (_busy || !isValidEmail(_email.text)) {
      setState(() {
        _failed = true;
        _status = l.t('Enter your email address first.',
            'Előbb add meg az e-mail-címed.');
      });
      return;
    }
    setState(() => _busy = true);
    try {
      final auth = ref.read(backendSessionProvider).client!.auth;
      if (confirmation) {
        await auth
            .resend(
                type: OtpType.signup,
                email: _email.text.trim(),
                emailRedirectTo: redirect)
            .timeout(const Duration(seconds: 20));
      } else {
        await auth
            .resetPasswordForEmail(_email.text.trim(), redirectTo: redirect)
            .timeout(const Duration(seconds: 20));
      }
      if (mounted) {
        setState(() {
          _failed = false;
          _status = l.t(
              confirmation
                  ? 'If the account needs confirmation, an email will arrive shortly. Open the link on this device.'
                  : 'If the address is registered, a password-reset email will arrive shortly. Open the link on this device.',
              confirmation
                  ? 'Ha a fiók megerősítésre vár, hamarosan e-mailt kapsz. A linket ezen az eszközön nyisd meg.'
                  : 'Ha a cím regisztrálva van, hamarosan jelszó-visszaállító e-mailt kapsz. A linket ezen az eszközön nyisd meg.');
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _failed = true;
          _status = _authError(error);
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
        body: SafeArea(
            child: Center(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: ListView(
                      padding: const EdgeInsets.all(24),
                      shrinkWrap: true,
                      children: [
                        Text('Duo Wallet',
                            style: Theme.of(context).textTheme.headlineMedium),
                        const SizedBox(height: 12),
                        Text(
                            widget.recovery
                                ? l.t(
                                    'Set a new password', 'Új jelszó megadása')
                                : _register
                                    ? l.t('Create your account',
                                        'Fiók létrehozása')
                                    : l.t('Sign in securely',
                                        'Biztonságos bejelentkezés'),
                            style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 20),
                        AutofillGroup(
                            child: Form(
                                key: _form,
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      if (!widget.recovery)
                                        TextFormField(
                                            controller: _email,
                                            enabled: !_busy,
                                            keyboardType:
                                                TextInputType.emailAddress,
                                            autofillHints: const [
                                              AutofillHints.email
                                            ],
                                            autocorrect: false,
                                            decoration: InputDecoration(
                                                labelText:
                                                    l.t('Email', 'E-mail')),
                                            validator: (v) => isValidEmail(
                                                    v ?? '')
                                                ? null
                                                : l.t(
                                                    'Enter a valid email address.',
                                                    'Adj meg érvényes e-mail-címet.')),
                                      const SizedBox(height: 16),
                                      TextFormField(
                                          controller: _password,
                                          enabled: !_busy,
                                          obscureText: !_showPassword,
                                          autocorrect: false,
                                          enableSuggestions: false,
                                          autofillHints: [
                                            widget.recovery || _register
                                                ? AutofillHints.newPassword
                                                : AutofillHints.password
                                          ],
                                          decoration: InputDecoration(
                                              labelText:
                                                  l.t('Password', 'Jelszó'),
                                              helperText: widget.recovery ||
                                                      _register
                                                  ? l.t(
                                                      'At least 8 characters. No special characters required.',
                                                      'Legalább 8 karakter. Különleges karakter nem szükséges.')
                                                  : null,
                                              helperMaxLines: 3,
                                              errorMaxLines: 4,
                                              suffixIcon: IconButton(
                                                  tooltip: l.t(
                                                      'Show or hide password',
                                                      'Jelszó megjelenítése vagy elrejtése'),
                                                  onPressed: () => setState(
                                                      () => _showPassword =
                                                          !_showPassword),
                                                  icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility))),
                                          validator: (v) {
                                            if (!(widget.recovery ||
                                                _register)) {
                                              return (v ?? '').isNotEmpty
                                                  ? null
                                                  : l.t('Enter your password.',
                                                      'Add meg a jelszavad.');
                                            }
                                            return isStrongPassword(v ?? '')
                                                ? null
                                                : l.t(
                                                    'Use at least 8 characters. Very long passwords may need to be shortened.',
                                                    'Legalább 8 karakter szükséges. A nagyon hosszú jelszót rövidítsd le.');
                                          }),
                                      const SizedBox(height: 20),
                                      FilledButton(
                                          onPressed: _busy ? null : _submit,
                                          child: Text(_busy
                                              ? l.t('Please wait…',
                                                  'Kérlek várj…')
                                              : widget.recovery
                                                  ? l.t('Save password',
                                                      'Jelszó mentése')
                                                  : _register
                                                      ? l.t('Create account',
                                                          'Fiók létrehozása')
                                                      : l.t('Sign in',
                                                          'Bejelentkezés'))),
                                    ]))),
                        if (_status != null)
                          Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Semantics(
                                  liveRegion: true,
                                  child: Text(_status!,
                                      style: TextStyle(
                                          color: _failed
                                              ? Theme.of(context)
                                                  .colorScheme
                                                  .error
                                              : null)))),
                        if (!widget.recovery) ...[
                          TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => setState(() {
                                        _register = !_register;
                                        _status = null;
                                        _password.clear();
                                        _form.currentState?.reset();
                                      }),
                              child: Text(_register
                                  ? l.t('Already have an account? Sign in',
                                      'Már van fiókod? Jelentkezz be')
                                  : l.t('Create an account',
                                      'Fiók létrehozása'))),
                          TextButton(
                              onPressed: _busy ? null : _reset,
                              child: Text(l.t('Forgot password?',
                                  'Elfelejtetted a jelszavad?'))),
                          TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => _reset(confirmation: true),
                              child: Text(l.t('Resend confirmation email',
                                  'Megerősítő e-mail újraküldése'))),
                        ],
                        if (widget.recovery)
                          TextButton(
                              onPressed: _busy
                                  ? null
                                  : ref.read(backendSessionProvider).signOut,
                              child: Text(l.t('Sign out', 'Kijelentkezés'))),
                      ],
                    )))));
  }
}

class HouseholdSetupScreen extends ConsumerStatefulWidget {
  const HouseholdSetupScreen({super.key});
  @override
  ConsumerState<HouseholdSetupScreen> createState() =>
      _HouseholdSetupScreenState();
}

class _HouseholdSetupScreenState extends ConsumerState<HouseholdSetupScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(),
      _household = TextEditingController(),
      _code = TextEditingController();
  bool _join = false, _busy = false;
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    _household.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(backendSessionProvider).onboard(
          displayName: _name.text,
          householdName: _household.text,
          inviteCode: _join ? _code.text : null,
          locale: AppLocalizations.of(context).locale.languageCode);
    } catch (_) {
      if (mounted) {
        setState(() => _error = AppLocalizations.of(context).t(
            'Could not connect the household. Check the invite code and connection, then retry.',
            'Nem sikerült kapcsolódni a háztartáshoz. Ellenőrizd a meghívókódot és a kapcsolatot, majd próbáld újra.'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    String? requiredName(String? v) =>
        (v?.trim().isNotEmpty ?? false) && v!.trim().length <= 80
            ? null
            : l.t('Enter 1–80 characters.', 'Adj meg 1–80 karaktert.');
    return Scaffold(
        appBar: AppBar(title: Text(l.t('Your household', 'A háztartásod'))),
        body: ListView(padding: const EdgeInsets.all(24), children: [
          Text(l.t(
              'Email verified. Create a private household or join your partner using their invite code.',
              'E-mail megerősítve. Hozz létre privát háztartást, vagy csatlakozz párodhoz a meghívókódjával.')),
          const SizedBox(height: 16),
          Wrap(spacing: 8, children: [
            ChoiceChip(
                label: Text(l.t('Create household', 'Háztartás létrehozása')),
                selected: !_join,
                onSelected:
                    _busy ? null : (_) => setState(() => _join = false)),
            ChoiceChip(
                label: Text(l.t('Join partner', 'Csatlakozás a páromhoz')),
                selected: _join,
                onSelected: _busy ? null : (_) => setState(() => _join = true))
          ]),
          Form(
              key: _form,
              child: Column(children: [
                TextFormField(
                    controller: _name,
                    decoration: InputDecoration(
                        labelText: l.t('Display name', 'Megjelenített név')),
                    validator: requiredName),
                const SizedBox(height: 16),
                if (_join)
                  TextFormField(
                      controller: _code,
                      autocorrect: false,
                      decoration: InputDecoration(
                          labelText: l.t('Invite code', 'Meghívókód')),
                      validator: requiredName)
                else
                  TextFormField(
                      controller: _household,
                      decoration: InputDecoration(
                          labelText: l.t('Household name', 'Háztartás neve')),
                      validator: requiredName),
                const SizedBox(height: 20),
                FilledButton(
                    onPressed: _busy ? null : _save,
                    child: Text(_busy
                        ? l.t('Connecting…', 'Kapcsolódás…')
                        : l.t('Continue', 'Folytatás'))),
              ])),
          if (_error != null)
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          TextButton(
              onPressed:
                  _busy ? null : ref.read(backendSessionProvider).signOut,
              child: Text(l.t('Sign out', 'Kijelentkezés'))),
        ]));
  }
}
