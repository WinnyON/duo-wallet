import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/l10n/generated/app_localizations.dart';
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

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      ShellRoute(
        builder: (context, state, child) => AppShell(
          location: state.uri.path,
          child: child,
        ),
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/transactions',
            builder: (context, state) => const TransactionsScreen(),
          ),
          GoRoute(
            path: '/accounts',
            builder: (context, state) => const AccountsScreen(),
          ),
          GoRoute(
            path: '/stats',
            builder: (context, state) => const StatsScreen(),
          ),
          GoRoute(
            path: '/budgets',
            builder: (context, state) => const BudgetsScreen(),
          ),
          GoRoute(
            path: '/settle-up',
            builder: (context, state) => const SettleUpScreen(),
          ),
          GoRoute(
            path: '/goals',
            builder: (context, state) => const GoalsScreen(),
          ),
          GoRoute(
            path: '/savings',
            builder: (context, state) => const SavingsScreen(),
          ),
          GoRoute(
            path: '/recurring',
            builder: (context, state) => const RecurringScreen(),
          ),
          GoRoute(
            path: '/history',
            builder: (context, state) => const HistoryScreen(),
          ),
          GoRoute(
            path: '/categories',
            builder: (context, state) => const CategoriesScreen(),
          ),
          GoRoute(
            path: '/activity',
            builder: (context, state) => const ActivityScreen(),
          ),
          GoRoute(
            path: '/export',
            builder: (context, state) => const ExportScreen(),
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) => const SettingsScreen(),
          ),
          GoRoute(
            path: '/auth',
            builder: (context, state) => const AuthScreen(),
          ),
        ],
      ),
    ],
  );
});

class AppShell extends StatelessWidget {
  final String location;
  final Widget child;

  const AppShell({super.key, required this.location, required this.child});

  static const _tabs = ['/', '/transactions', '/accounts', '/stats', '/settle-up'];

  int _selectedIndex() {
    final idx = _tabs.indexOf(location);
    return idx >= 0 ? idx : 0;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      drawer: Drawer(
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              ListTile(
                title: Text(
                  l10n.appName,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                subtitle: Text(
                  l10n.t('Private Couple Finance', 'Privát páros pénzügyek'),
                ),
              ),
              const Divider(),
              _navTile(context, '/', Icons.dashboard_outlined, l10n.dashboard),
              _navTile(context, '/transactions', Icons.receipt_long_outlined, l10n.transactions),
              _navTile(context, '/accounts', Icons.account_balance_wallet_outlined, l10n.accounts),
              _navTile(context, '/budgets', Icons.pie_chart_outline, l10n.budgets),
              _navTile(context, '/stats', Icons.bar_chart_outlined, l10n.stats),
              _navTile(context, '/history', Icons.calendar_month_outlined, l10n.history),
              _navTile(context, '/settle-up', Icons.handshake_outlined, l10n.settleUp),
              _navTile(context, '/recurring', Icons.autorenew_outlined, l10n.recurring),
              _navTile(context, '/savings', Icons.trending_up_outlined, l10n.savings),
              _navTile(context, '/goals', Icons.flag_outlined, l10n.goals),
              _navTile(context, '/categories', Icons.category_outlined, l10n.t('Categories', 'Kategóriák')),
              _navTile(context, '/activity', Icons.notifications_none_outlined, l10n.activity),
              _navTile(context, '/export', Icons.download_outlined, l10n.exportBackup),
              _navTile(context, '/auth', Icons.people_outline, l10n.t('Household & Profile', 'Háztartás és profil')),
              _navTile(context, '/settings', Icons.settings_outlined, l10n.settings),
            ],
          ),
        ),
      ),
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex(),
        onDestinationSelected: (i) => context.go(_tabs[i]),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.dashboard_outlined),
            label: l10n.dashboard,
          ),
          NavigationDestination(
            icon: const Icon(Icons.receipt_long_outlined),
            label: l10n.transactions,
          ),
          NavigationDestination(
            icon: const Icon(Icons.account_balance_wallet_outlined),
            label: l10n.accounts,
          ),
          NavigationDestination(
            icon: const Icon(Icons.bar_chart_outlined),
            label: l10n.stats,
          ),
          NavigationDestination(
            icon: const Icon(Icons.handshake_outlined),
            label: l10n.settleUp,
          ),
        ],
      ),
    );
  }

  Widget _navTile(BuildContext context, String path, IconData icon, String label) {
    final selected = location == path;
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      selected: selected,
      onTap: () {
        Navigator.of(context).pop();
        context.go(path);
      },
    );
  }
}
