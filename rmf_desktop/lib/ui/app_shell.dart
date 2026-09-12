import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logging/logging.dart';

import '../bloc/auth_bloc.dart';
import '../bloc/theme_cubit.dart';
import '../data/database.dart';
import '../services/startup_maintenance.dart';
import '../theme/app_theme.dart';
import 'dashboard_screen.dart';
import 'logs/logs_screen.dart';
import 'members/members_screen.dart';
import 'payments/payments_screen.dart';
import 'receipts/receipts_screen.dart';
import 'reminders/reminders_screen.dart';
import 'settings/settings_screen.dart';
import 'widgets/connection_status.dart';
import 'widgets/update_banner.dart';
import 'whatsapp/whatsapp_screen.dart';

final _log = Logger('shell');

/// The top bar's Reload button. Named so a test can find it without matching
/// on its icon: several screens carry a refresh icon of their own.
const appShellReloadKey = Key('app-shell-reload');

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
  NavDestination('Reminders', Icons.notifications_active_outlined,
      (_) => const RemindersScreen()),
  NavDestination('WhatsApp', Icons.chat_outlined,
      (_) => const WhatsAppScreen()),
  NavDestination('Logs', Icons.article_outlined, (_) => const LogsScreen()),
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

  /// Keys the subtree holding whichever screen is showing. Bumping it throws
  /// that screen away and builds a fresh one, which re-creates its bloc and
  /// re-fires the load event the bloc is created with — so one mechanism
  /// reloads every screen, rather than each bloc needing a refresh event of
  /// its own.
  int _reloadToken = 0;

  bool _reloading = false;

  Future<void> _reload() async {
    if (_reloading) return;

    // Read before the first await: the context must not be used across an
    // async gap.
    final db = context.read<AppDatabase>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _reloading = true);

    try {
      await runStartupMaintenance(db);
      if (mounted) setState(() => _reloadToken++);
    } catch (error, stack) {
      // A reload that quietly did nothing is worse than one that says so: the
      // owner would go on reading a screen they believe is up to date.
      _log.severe('Reload failed', error, stack);
      if (mounted) {
        messenger.showSnackBar(const SnackBar(
            content: Text('Could not reload. See the Logs screen.')));
      }
    } finally {
      if (mounted) setState(() => _reloading = false);
    }
  }

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
                _TopBar(
                  userName: user?.name ?? 'Admin',
                  userEmail: user?.email ?? '',
                  onReload: _reload,
                  reloading: _reloading,
                ),
                // Sits under the top bar, above whichever screen is showing,
                // so it is visible from anywhere without covering anything.
                const UpdateBanner(),
                Expanded(
                  child: Container(
                    color: context.palette.surfaceBase,
                    child: KeyedSubtree(
                      key: ValueKey(_reloadToken),
                      child: navDestinations[_index].builder(context),
                    ),
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
  const _TopBar({
    required this.userName,
    required this.userEmail,
    required this.onReload,
    required this.reloading,
  });

  final String userName;
  final String userEmail;
  final VoidCallback onReload;
  final bool reloading;

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
          // Left of Reload: whether this computer is reaching GitHub, and
          // whether a release is waiting. Both used to look like silence.
          const ConnectionStatusIcon(),
          _ReloadButton(onPressed: onReload, busy: reloading),
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

/// Does what opening the app does, then rebuilds the screen on show.
///
/// Deliberately not called Refresh: the Dashboard, Logs and Reminders screens
/// already carry a Refresh button, and those re-read what is on screen. This
/// one runs the billing roll first, so a member added at the counter a moment
/// ago gets the cycle that makes them read DUE — which until now meant quitting
/// the app and opening it again.
class _ReloadButton extends StatelessWidget {
  const _ReloadButton({required this.onPressed, required this.busy});

  final VoidCallback onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: appShellReloadKey,
      // Null while it runs, so a second press cannot start the work again
      // underneath the first.
      onPressed: busy ? null : onPressed,
      tooltip: 'Reload',
      icon: busy
          ? SizedBox(
              height: 20,
              width: 20,
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: context.palette.textMuted,
                ),
              ),
            )
          : Icon(Icons.refresh, size: 20, color: context.palette.textMuted),
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
