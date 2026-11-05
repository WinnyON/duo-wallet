import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/generated/app_localizations.dart';
import 'backend_session.dart';

class CloudStatusCard extends ConsumerWidget {
  const CloudStatusCard({super.key, this.compact = false});
  final bool compact;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(backendSessionProvider);
    final l = AppLocalizations.of(context);
    final pending = session.db.pendingOutbox.length;
    final status = session.localSaveFailed
        ? l.t('Secure local storage failed. Keep the app open and retry.',
            'A biztonságos helyi mentés nem sikerült. Tartsd nyitva az alkalmazást és próbáld újra.')
        : session.error != null
            ? l.t(
                'Sync needs attention. Your changes remain queued on this device.',
                'A szinkronizálás figyelmet igényel. A módosítások az eszközön sorban állnak.')
            : session.syncing
                ? l.t('Syncing securely…', 'Biztonságos szinkronizálás…')
                : pending > 0
                    ? l.t('$pending changes waiting to sync',
                        '$pending módosítás vár szinkronizálásra')
                    : session.lastSyncedAt != null
                        ? l.t('Cloud up to date', 'Felhő naprakész')
                        : l.t(
                            'Local data saved securely; waiting for cloud connection',
                            'Helyi adatok biztonságosan mentve; várakozás a felhőkapcsolatra');
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(12),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(status, style: Theme.of(context).textTheme.bodySmall),
              if (!compact) ...[
                Text(session.user?.email ?? ''),
                Text(l.t(
                    'Email verified. Passwords are managed by Supabase Auth.',
                    'E-mail megerősítve. A jelszavakat a Supabase Auth kezeli.')),
                if (session.db.household?.inviteCode != null)
                  TextButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(
                            text: session.db.household!.inviteCode!));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(l.t('Invite code copied',
                                  'Meghívókód másolva'))));
                        }
                      },
                      icon: const Icon(Icons.copy),
                      label: Text(l.t('Copy partner invite code',
                          'Párom meghívókódjának másolása'))),
              ],
              Wrap(spacing: 8, children: [
                TextButton(
                    onPressed: session.syncing ? null : session.syncNow,
                    child: Text(l.t('Sync now', 'Szinkronizálás most'))),
                if (!compact)
                  TextButton(
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                                    title: Text(
                                        l.t('Sign out?', 'Kijelentkezel?')),
                                    content: Text(l.t(
                                        'Queued changes stay encrypted for your next sign-in. Financial data is hidden immediately after signing out.',
                                        'A sorban álló módosítások titkosítva megmaradnak a következő bejelentkezésedig. Kijelentkezés után a pénzügyi adatok azonnal eltűnnek.')),
                                    actions: [
                                      TextButton(
                                          onPressed: () =>
                                              Navigator.pop(ctx, false),
                                          child: Text(l.t('Cancel', 'Mégse'))),
                                      FilledButton(
                                          onPressed: () =>
                                              Navigator.pop(ctx, true),
                                          child: Text(
                                              l.t('Sign out', 'Kijelentkezés')))
                                    ]));
                        if (confirmed == true) await session.signOut();
                      },
                      child: Text(l.t('Sign out', 'Kijelentkezés'))),
              ]),
            ])));
  }
}
