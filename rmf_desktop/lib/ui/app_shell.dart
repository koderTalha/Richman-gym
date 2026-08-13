import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/auth_bloc.dart';
import '../theme/app_theme.dart';
import 'dashboard_screen.dart';
import 'members/members_screen.dart';
import 'payments/payments_screen.dart';
import 'receipts/receipts_screen.dart';
import 'settings/settings_screen.dart';
import 'whatsapp/whatsapp_screen.dart';

class NavDestination {
  const NavDestination(this.label, this.icon, this.builder, {this.enabled = true});

  final String label;
  final IconData icon;
  final WidgetBuilder builder;

  /// Screens land incrementally; disabled entries render dimmed rather than as
  /// dead links or empty "coming soon" pages.
  final bool enabled;
}

final navDestinations = <NavDestination>[
  NavDestination('Dashboard', Icons.space_dashboard_outlined,
      (_) => const DashboardScreen()),
  NavDestination('Members', Icons.people_outline, (_) => const MembersScreen()),
  NavDestination('Payments', Icons.payments_outlined,
      (_) => const PaymentsScreen()),
  NavDestination('Receipts', Icons.receipt_long_outlined,
      (_) => const ReceiptsScreen()),
  NavDestination('WhatsApp', Icons.chat_outlined,
      (_) => const WhatsAppScreen()),
  NavDestination('Reports', Icons.bar_chart_outlined, (_) => const SizedBox(),
      enabled: false),
  NavDestination('Settings', Icons.settings_outlined,
      (_) => const SettingsScreen()),
];

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthBloc>().state.user;

    return Scaffold(
      body: Row(
        children: [
          _Sidebar(
            selectedIndex: _index,
            onSelect: (i) => setState(() => _index = i),
          ),
          Expanded(
            child: Column(
              children: [
                _TopBar(userName: user?.name ?? 'Admin',
                    userEmail: user?.email ?? ''),
                Expanded(
                  child: Container(
                    color: AppColors.ink950,
                    child: navDestinations[_index].builder(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.selectedIndex, required this.onSelect});

  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 232,
      decoration: const BoxDecoration(
        color: AppColors.ink900,
        border: Border(right: BorderSide(color: AppColors.ink800)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.ink800)),
            ),
            child: RichText(
              text: const TextSpan(
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                  color: AppColors.ink50,
                ),
                children: [
                  TextSpan(text: 'RICH MAN'),
                  TextSpan(
                    text: ' FITNESS',
                    style: TextStyle(color: AppColors.crimson500),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
              itemCount: navDestinations.length,
              itemBuilder: (context, i) {
                final item = navDestinations[i];
                final selected = i == selectedIndex;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Material(
                    color: selected
                        ? AppColors.crimson500.withValues(alpha: .12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: item.enabled ? () => onSelect(i) : null,
                      child: Opacity(
                        opacity: item.enabled ? 1 : .35,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          child: Row(
                            children: [
                              Icon(
                                item.icon,
                                size: 18,
                                color: selected
                                    ? AppColors.crimson400
                                    : AppColors.ink400,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                item.label,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: selected
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  color: selected
                                      ? AppColors.crimson400
                                      : AppColors.ink200,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(10),
            child: TextButton.icon(
              onPressed: () =>
                  context.read<AuthBloc>().add(const AuthSignOutRequested()),
              icon: const Icon(Icons.logout, size: 16),
              label: const Text('Log out'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.ink400,
                alignment: Alignment.centerLeft,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.userName, required this.userEmail});

  final String userName;
  final String userEmail;

  @override
  Widget build(BuildContext context) {
    final initial = userName.trim().isEmpty
        ? 'A'
        : userName.trim()[0].toUpperCase();

    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: AppColors.ink900,
        border: Border(bottom: BorderSide(color: AppColors.ink800)),
      ),
      child: Row(
        children: [
          const Spacer(),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(userName,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.ink50)),
              Text(userEmail, style: kMutedStyle),
            ],
          ),
          const SizedBox(width: 12),
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.crimson500,
            child: Text(
              initial,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}
