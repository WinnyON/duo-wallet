import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/l10n/generated/app_localizations.dart';
import 'features/accounts/presentation/account_details_screen.dart';
import 'features/accounts/presentation/accounts_screen.dart';
import 'features/activity/presentation/activity_screen.dart';
import 'features/auth/presentation/auth_screen.dart';
import 'features/budgets/presentation/budgets_screen.dart';
import 'features/categories/presentation/categories_screen.dart';
import 'features/dashboard/presentation/dashboard_screen.dart';
import 'features/export/presentation/export_screen.dart';
import 'features/goals/presentation/goals_screen.dart';
import 'features/history/presentation/history_screen.dart';
import 'features/recurring/presentation/recurring_screen.dart';
import 'features/savings/presentation/savings_screen.dart';
import 'features/settings/presentation/settings_screen.dart';
import 'features/settle_up/presentation/settle_up_screen.dart';
import 'features/stats/presentation/stats_screen.dart';
import 'features/transactions/presentation/transactions_screen.dart';
import 'theme.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => AppShell(
          location: state.uri.path,
          navigationShell: navigationShell,
          child: navigationShell,
        ),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
                path: '/',
                builder: (context, state) => const DashboardScreen()),
            GoRoute(
                path: '/budgets',
                builder: (context, state) => const BudgetsScreen()),
            GoRoute(
                path: '/goals',
                builder: (context, state) => GoalsScreen(
                    initialScope:
                        state.uri.queryParameters['scope'] ?? 'shared')),
            GoRoute(
                path: '/savings',
                builder: (context, state) => const SavingsScreen()),
            GoRoute(
                path: '/recurring',
                builder: (context, state) => const RecurringScreen()),
            GoRoute(
                path: '/history',
                builder: (context, state) => const HistoryScreen()),
            GoRoute(
                path: '/categories',
                builder: (context, state) => const CategoriesScreen()),
            GoRoute(
                path: '/activity',
                builder: (context, state) => const ActivityScreen()),
            GoRoute(
                path: '/export',
                builder: (context, state) => const ExportScreen()),
            GoRoute(
                path: '/settings',
                builder: (context, state) => const SettingsScreen()),
            GoRoute(
                path: '/auth', builder: (context, state) => const AuthScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: '/transactions',
                builder: (context, state) => const TransactionsScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: '/accounts',
                builder: (context, state) => const AccountsScreen()),
            GoRoute(
                path: '/accounts/:id',
                builder: (context, state) => AccountDetailsScreen(
                    accountId: state.pathParameters['id']!)),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: '/stats',
                builder: (context, state) => const StatsScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: '/settle-up',
                builder: (context, state) => const SettleUpScreen()),
          ]),
        ],
      ),
    ],
  );
});

final GlobalKey<ScaffoldState> appShellScaffoldKey = GlobalKey<ScaffoldState>();

class AppShell extends StatelessWidget {
  final String location;
  final Widget child;
  final StatefulNavigationShell? navigationShell;

  const AppShell(
      {super.key,
      required this.location,
      required this.child,
      this.navigationShell});

  static const _tabs = [
    '/',
    '/transactions',
    '/accounts',
    '/stats',
    '/settle-up'
  ];

  int _selectedIndex() {
    final idx = _tabs.indexOf(location);
    return idx >= 0 ? idx : 0;
  }

  static void goBackOrHome(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  static void openDrawer(BuildContext context) {
    final state = appShellScaffoldKey.currentState ?? Scaffold.maybeOf(context);
    state?.openDrawer();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final duo = context.duo;
    final scheme = Theme.of(context).colorScheme;
    final selectedIdx = _selectedIndex();
    final isTabRoute = _tabs.contains(location);

    final items =
        <({String path, IconData icon, IconData activeIcon, String label})>[
      (
        path: '/',
        icon: Icons.dashboard_outlined,
        activeIcon: Icons.dashboard_rounded,
        label: l10n.t('Home', 'Kezdő'),
      ),
      (
        path: '/transactions',
        icon: Icons.receipt_long_outlined,
        activeIcon: Icons.receipt_long_rounded,
        label: l10n.t('Entries', 'Tételek'),
      ),
      (
        path: '/accounts',
        icon: Icons.account_balance_wallet_outlined,
        activeIcon: Icons.account_balance_wallet_rounded,
        label: l10n.accounts,
      ),
      (
        path: '/stats',
        icon: Icons.show_chart_rounded,
        activeIcon: Icons.show_chart_rounded,
        label: l10n.t('Statistics', 'Elemzés'),
      ),
      (
        path: '/settle-up',
        icon: Icons.handshake_outlined,
        activeIcon: Icons.handshake_rounded,
        label: l10n.t('Settle', 'Rendezés'),
      ),
    ];

    return PopScope(
      canPop: context.canPop() || location == '/',
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !isTabRoute) return;
        goBackOrHome(context);
      },
      child: Scaffold(
        key: appShellScaffoldKey,
        extendBody: false,
        drawer: Drawer(
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                ListTile(
                  title: Text(
                    l10n.appName,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  subtitle: Text(
                    l10n.t('Demo • local data', 'Demó • helyi adatok'),
                  ),
                ),
                const SizedBox(height: 8),
                _navTile(
                    context, '/', Icons.dashboard_outlined, l10n.dashboard),
                _navTile(context, '/transactions', Icons.receipt_long_outlined,
                    l10n.transactions),
                _navTile(context, '/accounts',
                    Icons.account_balance_wallet_outlined, l10n.accounts),
                _navTile(
                    context, '/budgets', Icons.pie_chart_outline, l10n.budgets),
                _navTile(
                    context, '/stats', Icons.show_chart_rounded, l10n.stats),
                _navTile(context, '/history', Icons.calendar_month_outlined,
                    l10n.history),
                _navTile(context, '/settle-up', Icons.handshake_outlined,
                    l10n.settleUp),
                _navTile(context, '/recurring', Icons.autorenew_outlined,
                    l10n.recurring),
                _navTile(context, '/savings', Icons.trending_up_outlined,
                    l10n.savings),
                _navTile(context, '/goals', Icons.flag_outlined, l10n.goals),
                _navTile(context, '/categories', Icons.category_outlined,
                    l10n.t('Categories', 'Kategóriák')),
                _navTile(context, '/activity',
                    Icons.notifications_none_outlined, l10n.activity),
                _navTile(context, '/export', Icons.download_outlined,
                    l10n.exportBackup),
                _navTile(context, '/auth', Icons.people_outline,
                    l10n.t('Household & Profile', 'Háztartás és profil')),
                _navTile(context, '/settings', Icons.settings_outlined,
                    l10n.settings),
              ],
            ),
          ),
        ),
        body: child,
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: scheme.surface,
            border: Border(
              top: BorderSide(color: duo.hairline, width: 1),
            ),
          ),
          child: SafeArea(
            top: false,
            child: LayoutBuilder(builder: (context, constraints) {
              final large = MediaQuery.textScalerOf(context).scale(12) >= 16;
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (var i = 0; i < items.length; i++)
                    SizedBox(
                      width: large ? 112 : constraints.maxWidth / items.length,
                      child: Semantics(
                        selected: isTabRoute && i == selectedIdx,
                        child: TextButton(
                          onPressed: () => navigationShell?.goBranch(i),
                          style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 10, horizontal: 2)),
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                color: isTabRoute && i == selectedIdx
                                    ? scheme.primary.withValues(alpha: .14)
                                    : null,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                  isTabRoute && i == selectedIdx
                                      ? items[i].activeIcon
                                      : items[i].icon,
                                  color: isTabRoute && i == selectedIdx
                                      ? scheme.primary
                                      : duo.icon),
                            ),
                            const SizedBox(height: 4),
                            Text(items[i].label,
                                style: TextStyle(
                                    fontSize: 12, color: scheme.onSurface)),
                          ]),
                        ),
                      ),
                    ),
                ]),
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _navTile(
      BuildContext context, String path, IconData icon, String label) {
    final selected = location == path;
    return ListTile(
      leading: Icon(icon,
          color: selected ? Theme.of(context).colorScheme.primary : null),
      title: Text(label),
      selected: selected,
      onTap: () {
        Navigator.of(context).pop();
        if (location == path) return;
        final index = _tabs.indexOf(path);
        if (index >= 0 && navigationShell != null) {
          navigationShell!.goBranch(index);
        } else {
          context.push(path);
        }
      },
    );
  }
}
