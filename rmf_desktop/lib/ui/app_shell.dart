import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show TableUpdate, TableUpdateQuery;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logging/logging.dart';

import '../bloc/auth_bloc.dart';
import '../bloc/branding_cubit.dart';
import '../bloc/theme_cubit.dart';
import '../data/database.dart';
import '../data/member_repository.dart';
import '../services/reminder_service.dart';
import '../services/startup_maintenance.dart';
import '../theme/app_theme.dart';
import 'appearance/appearance_screen.dart';
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

/// How often the automatic reminder run is tried again while the app stays
/// open.
///
/// It used to be tried once per launch, and only then: a launch before sending
/// hours sent nothing all day, and on the 1st — when most legacy members fall
/// due at once — everything past the per-run cap waited for the next launch
/// and was by then superseded. Hourly is often enough that a morning launch
/// still sends once the gym opens, and rare enough that the per-run cap still
/// means something. Every run is hours-aware, capped and single-flight; see
/// `ReminderService.runAutoSend`.
const reminderRunInterval = Duration(hours: 1);

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
  NavDestination('Members', Icons.people_outline,
      (context) => MembersScreen(
          initialFilter: ShellNavigator.maybeOf(context)?.pendingFilter)),
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
  NavDestination('Appearance', Icons.palette_outlined,
      (_) => const AppearanceScreen()),
  NavDestination('Settings', Icons.settings_outlined,
      (_) => const SettingsScreen()),
];

/// Lets a screen send the owner somewhere else in the shell.
///
/// The dashboard's attention cards are the reason this exists: "319 payments
/// due → View list" has to land on Members *already filtered to Due*, or the
/// owner is left to set the filter themselves, which is the busywork the
/// redesign is meant to remove.
///
/// Deliberately not a router: this app navigates by sidebar index held in
/// [_AppShellState], and introducing go_router to pass one enum would be a far
/// larger change than the need justifies.
class ShellNavigator extends InheritedWidget {
  const ShellNavigator({
    super.key,
    required this.openMembers,
    required this.openReminders,
    required this.setLeaveGuard,
    required this.pendingFilter,
    required super.child,
  });

  /// Opens the Members screen, optionally with a filter already applied.
  final void Function({MemberFilter? filter}) openMembers;

  /// Opens the Reminders screen.
  ///
  /// The dashboard's "Send reminders" goes here rather than sending from the
  /// card. Messaging several hundred members is irreversible and costs the gym
  /// money per message, so the owner chooses who to send to on a screen built
  /// for exactly that, instead of a button press they cannot take back.
  final VoidCallback openReminders;

  /// Lets the screen on show veto leaving it, or clears the veto with null.
  ///
  /// Settings uses this so unsaved edits are not thrown away by a sidebar
  /// click or a Reload, both of which rebuild the screen from scratch. The
  /// guard answers whether it is all right to go.
  final void Function(Future<bool> Function()? guard) setLeaveGuard;

  /// The filter the Members screen should open with, if it was reached from a
  /// dashboard card. Read once, as the screen is built.
  final MemberFilter? pendingFilter;

  static ShellNavigator? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellNavigator>();

  /// The navigator without subscribing to it — for initState and dispose,
  /// where a dependency cannot be registered.
  static ShellNavigator? read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ShellNavigator>();

  @override
  bool updateShouldNotify(ShellNavigator old) =>
      pendingFilter != old.pendingFilter;
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  /// A filter the Members screen should open with, set by whoever navigated
  /// there (the dashboard's attention cards). Cleared once consumed, so
  /// returning to Members from the sidebar shows everything again rather than
  /// silently keeping a filter the owner did not choose this time.
  MemberFilter? _pendingFilter;

  static final _membersIndex =
      navDestinations.indexWhere((d) => d.label == 'Members');
  static final _remindersIndex =
      navDestinations.indexWhere((d) => d.label == 'Reminders');

  void _openMembers({MemberFilter? filter}) {
    setState(() {
      _index = _membersIndex;
      _pendingFilter = filter;
    });
  }

  void _openReminders() => setState(() => _index = _remindersIndex);

  /// Set by a screen holding unsaved work. Asked before anything that would
  /// rebuild that screen and lose it.
  Future<bool> Function()? _leaveGuard;

  void _setLeaveGuard(Future<bool> Function()? guard) => _leaveGuard = guard;

  /// True when nothing objects to the current screen being replaced.
  Future<bool> _mayLeave() async {
    final guard = _leaveGuard;
    if (guard == null) return true;
    return guard();
  }

  Future<void> _select(int i) async {
    // Re-selecting the screen on show does not rebuild it, so there is
    // nothing for the guard to protect — and it still clears a filter.
    if (i != _index && (!await _mayLeave() || !mounted)) return;
    setState(() {
      _index = i;
      _pendingFilter = null;
    });
  }

  /// Keys the subtree holding whichever screen is showing. Bumping it throws
  /// that screen away and builds a fresh one, which re-creates its bloc and
  /// re-fires the load event the bloc is created with — so one mechanism
  /// reloads every screen, rather than each bloc needing a refresh event of
  /// its own.
  int _reloadToken = 0;

  bool _reloading = false;

  Timer? _reminderTimer;

  @override
  void initState() {
    super.initState();
    _reminderTimer =
        Timer.periodic(reminderRunInterval, (_) => _runAutomaticReminders());
  }

  @override
  void dispose() {
    _reminderTimer?.cancel();
    super.dispose();
  }

  /// Starts an automatic reminder run in the background.
  ///
  /// Not awaited: up to a full per-run cap of WhatsApp calls must not hold the
  /// Reload button, or anything else, hostage. Read as nullable so a shell
  /// built without the service — in a test — simply has no automatic run.
  void _runAutomaticReminders() {
    if (!mounted) return;
    final reminders = context.read<ReminderService?>();
    if (reminders == null) return;
    unawaited(reminders.runAutoSend());
  }

  Future<void> _reload() async {
    if (_reloading) return;
    // Reload rebuilds the screen on show, which would throw away unsaved
    // settings as surely as navigating away.
    if (!await _mayLeave() || !mounted) return;

    // Read before the first await: the context must not be used across an
    // async gap.
    final db = context.read<AppDatabase>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _reloading = true);

    try {
      await runStartupMaintenance(db);
      if (mounted) setState(() => _reloadToken++);
      // What opening the app does, after the billing roll so a cycle that
      // has only just opened is reminded about too.
      _runAutomaticReminders();
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

    return ShellNavigator(
      openMembers: _openMembers,
      openReminders: _openReminders,
      setLeaveGuard: _setLeaveGuard,
      pendingFilter: _pendingFilter,
      child: Scaffold(
      body: Row(
        children: [
          _Sidebar(
            selectedIndex: _index,
            // Choosing Members from the sidebar means "show me the members",
            // so any filter a dashboard card left behind is dropped.
            onSelect: _select,
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
                    child: _PageEntrance(
                      // The pending filter joins the key so that asking for
                      // Members twice with different filters rebuilds the
                      // screen rather than reusing the first one's state. The
                      // index is in it so every new screen plays its entrance.
                      key: ValueKey(
                          '$_index/$_reloadToken/${_pendingFilter?.name}'),
                      child: navDestinations[_index].builder(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }
}

/// The gym's logo in the sidebar header, or nothing when none is set.
///
/// Watches [BrandingCubit] so an upload appears immediately rather than after a
/// restart. Sized by height with `BoxFit.contain`, so a wide mark and a square
/// one both sit correctly and neither is stretched.
class _SidebarLogo extends StatelessWidget {
  const _SidebarLogo();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<BrandingCubit, BrandingState>(
      // Only the logo path matters here; a theme preview must not rebuild the
      // image and make it flicker.
      buildWhen: (a, b) => a.draft.logoPath != b.draft.logoPath,
      builder: (context, state) {
        final path = state.draft.logoPath;
        if (path == null) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 44, maxWidth: 192),
            child: Image.file(
              File(path),
              fit: BoxFit.contain,
              alignment: Alignment.centerLeft,
              // A deleted or unreadable file must not put a broken-image box in
              // the sidebar — the wordmark below is enough on its own.
              errorBuilder: (context, error, stack) => const SizedBox.shrink(),
            ),
          ),
        );
      },
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
      width: 216,
      decoration: BoxDecoration(
        color: context.palette.sidebar,
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // The gym's own mark, above the wordmark. Absent when no logo
                // is configured, so the header collapses back to exactly what
                // it looked like before this feature existed.
                const _SidebarLogo(),
                RichText(
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
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
              itemCount: navDestinations.length,
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: _NavItem(
                  item: navDestinations[i],
                  selected: i == selectedIndex,
                  onTap: () => onSelect(i),
                  badge: navDestinations[i].label == 'Reminders'
                      ? const _DueBadge()
                      : null,
                ),
              ),
            ),
          ),
          const _WhatsAppModeLine(),
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
              // Not Colors.white: this sits on the brand colour, and on the
              // brighter presets (gold, emerald, orange) white is unreadable.
              style: TextStyle(
                  color: context.palette.onAccent,
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
/// the app and opening it again — and then the automatic reminder run, as
/// opening the app does.
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

/// One row of the sidebar, per the handoff: a hover tint, and for the screen
/// on show a brand-tinted fill with a 2px bar down its left edge.
class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.item,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final NavDestination item;
  final bool selected;
  final VoidCallback onTap;

  /// Drawn at the right edge — the Reminders count.
  final Widget? badge;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final item = widget.item;
    final selected = widget.selected;
    final enabled = item.enabled;

    final background = selected
        ? palette.accent.withValues(alpha: 0.14)
        : (_hovered && enabled ? palette.surfaceRaised : Colors.transparent);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: Semantics(
        button: true,
        selected: selected,
        enabled: enabled,
        child: GestureDetector(
          onTap: enabled ? widget.onTap : null,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(8),
              // The handoff's inset left bar, as a border on one side so it
              // follows the rounded corner rather than poking out of it.
              border: selected
                  ? Border(left: BorderSide(color: palette.accent, width: 2))
                  : null,
            ),
            child: Opacity(
              opacity: enabled ? 1 : 0.6,
              child: Row(
                children: [
                  Icon(
                    item.icon,
                    size: 17,
                    color: selected
                        ? palette.accentText
                        : (enabled ? palette.textSecondary : palette.textMuted),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item.label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            selected ? FontWeight.w500 : FontWeight.w400,
                        color: selected || _hovered && enabled
                            ? palette.textPrimary
                            : (enabled
                                ? palette.textSecondary
                                : palette.textMuted),
                      ),
                    ),
                  ),
                  if (!enabled)
                    Text('SOON',
                        style: TextStyle(
                            fontSize: 10,
                            letterSpacing: 0.6,
                            color: palette.textMuted))
                  else if (widget.badge != null)
                    widget.badge!,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// How many members are due, beside Reminders.
///
/// Recounted whenever a table that decides who is due changes, so recording a
/// payment or adding a member moves the number without a Reload. The count is
/// the same join the Members screen runs, so a burst of writes — a payment
/// writes several tables at once — is coalesced into one recount rather than
/// one per row: while a count is running, further changes only mark it stale,
/// and it runs once more when it finishes. No timer, so nothing is left
/// pending when the screen goes away.
class _DueBadge extends StatefulWidget {
  const _DueBadge();

  @override
  State<_DueBadge> createState() => _DueBadgeState();
}

class _DueBadgeState extends State<_DueBadge> {
  StreamSubscription<Set<TableUpdate>>? _changes;
  int? _due;
  bool _counting = false;
  bool _stale = false;

  @override
  void initState() {
    super.initState();
    final db = context.read<AppDatabase>();
    _changes = db
        .tableUpdates(TableUpdateQuery.onAllTables([
          db.members,
          db.memberships,
          db.membershipPeriods,
          db.payments,
          db.paymentAllocations,
        ]))
        .listen((_) => _recount());
    _recount();
  }

  Future<void> _recount() async {
    if (_counting) {
      _stale = true;
      return;
    }
    _counting = true;
    try {
      do {
        _stale = false;
        final counts = await context.read<MemberRepository>().filterCounts();
        if (!mounted) return;
        setState(() => _due = counts[MemberFilter.due] ?? 0);
      } while (_stale && mounted);
    } catch (_) {
      // A badge is a convenience. If the count cannot be read the Reminders
      // screen still can, so this stays quiet rather than surfacing an error.
    } finally {
      _counting = false;
    }
  }

  @override
  void dispose() {
    _changes?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final due = _due;
    if (due == null || due == 0) return const SizedBox.shrink();
    final palette = context.palette;

    return Container(
      key: const Key('reminders-due-badge'),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        color: palette.dueBg,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        '$due',
        style: TextStyle(
          fontSize: 11,
          color: palette.due,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// Which WhatsApp provider the app is set to, above Log out.
///
/// The handoff draws a pulsing "WhatsApp connected". The app does not check
/// that — it sends when asked and records what happened — so this says what
/// it does know instead: whether messages are going out through Meta or are
/// only being logged in mock mode. Mock mode is the one worth noticing, since
/// it means members are not getting their receipts, so it is drawn in amber.
class _WhatsAppModeLine extends StatefulWidget {
  const _WhatsAppModeLine();

  @override
  State<_WhatsAppModeLine> createState() => _WhatsAppModeLineState();
}

class _WhatsAppModeLineState extends State<_WhatsAppModeLine> {
  StreamSubscription<Set<TableUpdate>>? _changes;
  WhatsAppProviderKind? _provider;

  @override
  void initState() {
    super.initState();
    // Re-read when the settings row changes, so a switch to Meta in Settings
    // shows here straight away. tableUpdates rather than a watch query: a
    // watch query leaves a cache timer behind when it is cancelled, which
    // every widget test that shows the shell would then trip over.
    final db = context.read<AppDatabase>();
    _changes = db
        .tableUpdates(TableUpdateQuery.onTable(db.gymSettings))
        .listen((_) => _read());
    _read();
  }

  Future<void> _read() async {
    try {
      final db = context.read<AppDatabase>();
      final row = await db.select(db.gymSettings).getSingleOrNull();
      if (mounted) setState(() => _provider = row?.whatsappProvider);
    } catch (_) {
      // A status line, not a control: if it cannot be read it stays hidden.
    }
  }

  @override
  void dispose() {
    _changes?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    final provider = _provider;
    if (provider == null) return const SizedBox.shrink();
    final live = provider == WhatsAppProviderKind.meta;

    return Padding(
      key: const Key('whatsapp-mode-line'),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: live ? palette.paid : palette.due,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              live ? 'WhatsApp via Meta' : 'WhatsApp in mock mode',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: live ? palette.textMuted : palette.due,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The handoff's page transition: a screen fades in while rising 8px.
///
/// An entrance only, not a cross-fade. A cross-fade keeps the screen being
/// left alive for its duration, and two Settings screens side by side would
/// both claim the leave guard and both load their bloc. The sidebar is outside
/// this, so it never moves.
class _PageEntrance extends StatelessWidget {
  const _PageEntrance({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return child;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 8 * (1 - t)), child: child),
      ),
    );
  }
}
