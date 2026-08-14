import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/auth_bloc.dart';
import '../bloc/theme_cubit.dart';
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
                    color: context.palette.surfaceBase,
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
      decoration: BoxDecoration(
        color: context.palette.surfaceRaised,
        border: Border(right: BorderSide(color: context.palette.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: context.palette.border)),
            ),
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                  color: context.palette.textPrimary,
                ),
                children: [
                  const TextSpan(text: 'RICH MAN'),
                  TextSpan(
                    text: ' FITNESS',
                    style: TextStyle(color: context.palette.accent),
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
                        ? context.palette.accent.withValues(alpha: .12)
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
                                    ? context.palette.accentText
                                    : context.palette.textMuted,
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
                                      ? context.palette.accentText
                                      : context.palette.textSecondary,
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
                foregroundColor: context.palette.textMuted,
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
      decoration: BoxDecoration(
        color: context.palette.surfaceRaised,
        border: Border(bottom: BorderSide(color: context.palette.border)),
      ),
      child: Row(
        children: [
          const Spacer(),
          const _ThemeToggle(),
          const SizedBox(width: 16),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(userName,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: context.palette.textPrimary)),
              Text(userEmail, style: mutedStyleOf(context)),
            ],
          ),
          const SizedBox(width: 12),
          CircleAvatar(
            radius: 18,
            backgroundColor: context.palette.accent,
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

/// Switches between the light and dark schemes. The choice is written to the
/// settings row, so it survives a restart.
class _ThemeToggle extends StatelessWidget {
  const _ThemeToggle();

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeCubit>().state == ThemeMode.dark;

    return IconButton(
      onPressed: () => context.read<ThemeCubit>().toggle(),
      // Names the destination, not the current state: pressing it is what the
      // label has to describe.
      tooltip: isDark ? 'Switch to light theme' : 'Switch to dark theme',
      icon: Icon(
        isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
        size: 20,
        color: context.palette.textMuted,
      ),
    );
  }
}
