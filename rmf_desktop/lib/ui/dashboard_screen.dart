import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/branding_cubit.dart';
import '../bloc/dashboard_bloc.dart';
import '../data/database.dart' show WhatsAppStatus;
import '../data/member_repository.dart';
import '../data/payment_repository.dart';
import '../data/receipt_repository.dart';
import '../domain/money.dart';
import '../domain/payment_method.dart';
import '../domain/phone.dart';
import '../theme/app_theme.dart';
import 'app_shell.dart' show ShellNavigator;
import 'members/member_detail_screen.dart';
import 'payments/advance_payment_dialog.dart';
import 'payments/payment_history_table.dart' show formatShortDate;
import 'widgets/attention_card.dart';
import 'widgets/brand_photo.dart';
import 'widgets/count_up.dart';
import 'widgets/fade_rise.dart';
import 'widgets/page_scaffold.dart';
import 'widgets/rotating_rings.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => DashboardBloc(
        memberRepository: context.read<MemberRepository>(),
        paymentRepository: context.read<PaymentRepository>(),
        receiptRepository: context.read<ReceiptRepository>(),
      )..add(const DashboardRequested()),
      child: const _DashboardView(),
    );
  }
}

/// The owner's first screen, ordered the way the handoff asks for.
///
/// What needs action comes first, with the next step attached; the totals that
/// are merely interesting come after; the full tables stay one click away. The
/// previous version gave seven figures identical weight in a row of identical
/// boxes, so the number that mattered — 319 members owing money — looked
/// exactly like the number that did not.
class _DashboardView extends StatelessWidget {
  const _DashboardView();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DashboardBloc, DashboardState>(
      builder: (context, state) {
        if (state.status == DashboardStatus.loading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state.status == DashboardStatus.failed) {
          return Center(
            child: Text('Could not load the dashboard: ${state.error}',
                style: TextStyle(color: context.palette.expired)),
          );
        }

        final due = state.mostOverdue;
        final expiring = state.expiringSoon;

        return PageScaffold(
          hero: const _HeroBand(),
          title: _greeting(),
          subtitle: _Summary(
            dueCount: due.length,
            revenueMonthMinor: state.revenueMonthMinor,
          ),
          actions: [
            GhostButton(
              label: 'Refresh',
              icon: Icons.refresh,
              onPressed: () => context
                  .read<DashboardBloc>()
                  .add(const DashboardRequested()),
            ),
          ],
          children: [
            _AttentionRow(state: state, due: due, expiring: expiring),
            const SizedBox(height: 22),
            _SecondaryStats(state: state),
            const SizedBox(height: 22),
            _Lists(state: state, due: due),
          ],
        );
      },
    );
  }

  /// "Good evening, Owner" — time-aware, as the handoff specifies.
  static String _greeting() {
    final hour = DateTime.now().hour;
    final part = hour < 12
        ? 'morning'
        : hour < 17
            ? 'afternoon'
            : 'evening';
    return 'Good $part, Owner';
  }
}

/// The artwork behind the greeting: a brand-tinted wash, the gym's photograph
/// if it has one, and the rotating rings bleeding off the top right.
///
/// The handoff's hero band. Nothing here is interactive — the greeting and the
/// attention cards are laid out over it by [PageScaffold].
class _HeroBand extends StatelessWidget {
  const _HeroBand();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          // 120°, per the handoff: the tint sits in the top-left behind the
          // greeting and clears before the right edge where the photo goes.
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: const [0.0, 0.7],
          colors: [
            Color.lerp(palette.surfaceRaised, palette.accent, 0.08)!,
            palette.surfaceBase,
          ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          BlocBuilder<BrandingCubit, BrandingState>(
            buildWhen: (a, b) =>
                a.draft.dashboardPhotoPath != b.draft.dashboardPhotoPath,
            builder: (context, state) => BrandPhoto(
              path: state.draft.dashboardPhotoPath,
              slot: BrandPhotoSlot.dashboard,
            ),
          ),
          const Positioned(
            right: -60,
            top: -90,
            child: RotatingRings(size: 380),
          ),
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.dueCount, required this.revenueMonthMinor});

  final int dueCount;
  final int revenueMonthMinor;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Text.rich(
      TextSpan(
        children: [
          const TextSpan(text: 'You have '),
          TextSpan(
            text: '$dueCount payment${dueCount == 1 ? '' : 's'} due',
            style: TextStyle(color: palette.due, fontWeight: FontWeight.w500),
          ),
          const TextSpan(text: ', and '),
          TextSpan(
            text: formatMinorUnits(revenueMonthMinor),
            style: TextStyle(color: palette.textSecondary),
          ),
          const TextSpan(text: ' has come in this month.'),
        ],
      ),
    );
  }
}

/// The three things that might need doing today.
class _AttentionRow extends StatelessWidget {
  const _AttentionRow({
    required this.state,
    required this.due,
    required this.expiring,
  });

  final DashboardState state;
  final List<MemberRow> due;
  final List<MemberRow> expiring;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final shell = ShellNavigator.maybeOf(context);

    // The handoff's responsive grid: at least 240px a column, which on a
    // 1240-wide content area gives three and collapses gracefully below that.
    return LayoutBuilder(
      builder: (context, constraints) {
        // 300, not the handoff's 240: at 240 the three cards fit arithmetically
        // but their own contents (a 38px figure beside a unit, an icon beside a
        // sentence) do not, and the row overflows. 300 is the width at which
        // the cards actually hold what they carry.
        const minWidth = 300.0;
        const gap = 12.0;
        final columns =
            ((constraints.maxWidth + gap) / (minWidth + gap)).floor().clamp(1, 3);

        final oldest = due.isEmpty ? null : due.first.paidUntil;
        final daysLate = oldest == null
            ? null
            : DateTime.now().difference(oldest).inDays;

        final cards = <Widget>[
            AttentionCard(
                icon: Icons.error_outline,
                label: 'Payments due',
                value: due.length,
                unit: due.isEmpty
                    ? null
                    : 'member${due.length == 1 ? '' : 's'}'
                        '${daysLate != null && daysLate > 0 ? ' · oldest $daysLate days late' : ''}',
                tone: due.isEmpty
                    ? AttentionTone.clear
                    : AttentionTone.warning,
                detail: due.isEmpty
                    ? Row(
                        children: [
                          Icon(Icons.check, size: 14, color: palette.paid),
                          const SizedBox(width: 6),
                          // Flexible, or a narrow card overflows this row
                          // rather than wrapping the sentence.
                          Flexible(
                            child: Text('Nobody is overdue. Good work.',
                                style: TextStyle(
                                    fontSize: 12, color: palette.paid)),
                          ),
                        ],
                      )
                    : null,
                actions: due.isEmpty
                    ? const []
                    : [
                        // The handoff's primary next step. It opens the
                        // Reminders screen rather than sending from here:
                        // messaging hundreds of members costs money per
                        // message and cannot be recalled, so the owner picks
                        // who to chase on the screen built for it.
                        AccentButton(
                          label: 'Send reminders',
                          icon: Icons.send_outlined,
                          compact: true,
                          onPressed: shell?.openReminders,
                        ),
                        GhostButton(
                          label: 'View list',
                          compact: true,
                          onPressed: () =>
                              shell?.openMembers(filter: MemberFilter.due),
                        ),
                      ],
            ),
            AttentionCard(
                icon: Icons.hourglass_bottom_outlined,
                label: 'Expiring in 7 days',
                value: expiring.length,
                tone: AttentionTone.neutral,
                onTap: () =>
                    shell?.openMembers(filter: MemberFilter.expiringSoon),
                detail: Text(
                  expiring.isEmpty
                      ? 'Nothing lapses this week.'
                      : 'Review members →',
                  style: TextStyle(
                    fontSize: 12,
                    color: expiring.isEmpty
                        ? palette.textMuted
                        : palette.accentText,
                  ),
                ),
            ),
            AttentionCard(
                icon: Icons.chat_outlined,
                label: 'Failed WhatsApp',
                value: state.failedWhatsApp,
                tone: state.failedWhatsApp == 0
                    ? AttentionTone.clear
                    : AttentionTone.warning,
                detail: Row(
                  children: [
                    Icon(
                      state.failedWhatsApp == 0
                          ? Icons.check
                          : Icons.error_outline,
                      size: 14,
                      color: state.failedWhatsApp == 0
                          ? palette.paid
                          : palette.due,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        state.failedWhatsApp == 0
                            ? 'All receipts delivered'
                            : 'Retry from the WhatsApp screen',
                        style: TextStyle(
                          fontSize: 12,
                          color: state.failedWhatsApp == 0
                              ? palette.paid
                              : palette.due,
                        ),
                      ),
                    ),
                  ],
                ),
            ),
        ];

        // A Row of Expanded children rather than a Wrap: Wrap sizes each child
        // to its own content, so the card with fewer lines came out narrower
        // than its neighbours. Expanded makes the columns equal by
        // construction, and stretch gives them a common height.
        if (columns < 3) {
          // Two columns would leave one card alone on a second row looking
          // like an afterthought, so below three the cards stack.
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(height: gap),
                FadeRise(index: i, child: cards[i]),
              ],
            ],
          );
        }
        // Expanded gives the three cards equal widths; `stretch` would give
        // them a common height too, but a Row inside a scroll view has no
        // bounded height to stretch into, and IntrinsicHeight measures
        // intrinsic *widths* that ignore Expanded and overflow a narrow
        // window. So the cards size to their own content, which is what the
        // handoff's mock shows anyway.
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < cards.length; i++) ...[
              if (i > 0) const SizedBox(width: gap),
              Expanded(child: FadeRise(index: i, child: cards[i])),
            ],
          ],
        );
      },
    );
  }
}

/// Revenue and membership totals — context, not calls to action.
class _SecondaryStats extends StatelessWidget {
  const _SecondaryStats({required this.state});

  final DashboardState state;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final total = state.members.length;
    final active = state.activeCount;
    final fraction = total == 0 ? 0.0 : active / total;

    return Wrap(
      spacing: 40,
      runSpacing: 20,
      children: [
        // The money counts up in minor units and is formatted each frame, so
        // the separators land where they finally will rather than the figure
        // reflowing as it passes each thousand.
        CountUp(
          value: state.revenueMonthMinor,
          builder: (context, animated) => StatFigure(
            label: 'Revenue this month',
            value: formatMinorUnits(animated.round()),
          ),
        ),
        CountUp(
          value: state.revenueTodayMinor,
          builder: (context, animated) => StatFigure(
            label: 'Today',
            value: formatMinorUnits(animated.round()),
            hint: '· ${state.paymentsToday} '
                'payment${state.paymentsToday == 1 ? '' : 's'}',
          ),
        ),
        SizedBox(
          width: 300,
          child: CountUp(
            value: active,
            builder: (context, animated) => StatFigure(
              label: 'Active members',
              value: '${animated.round()}',
              hint: 'of $total',
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                // The bar fills in step with the figure above it, so the two
                // tell the same story at the same moment.
                child: CountUp(
                  value: fraction,
                  builder: (context, filled) => ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: filled.toDouble(),
                      minHeight: 3,
                      backgroundColor: palette.borderStrong,
                      valueColor: AlwaysStoppedAnimation(palette.accent),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Most overdue beside recent payments — who to chase, and what just landed.
class _Lists extends StatelessWidget {
  const _Lists({required this.state, required this.due});

  final DashboardState state;
  final List<MemberRow> due;

  @override
  Widget build(BuildContext context) {
    final shell = ShellNavigator.maybeOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Side by side when there is room for two 380px panels, stacked below.
        final sideBySide = constraints.maxWidth >= 788;
        final overdue = PanelCard(
          title: 'Most overdue',
          trailing: due.isEmpty
              ? null
              : PanelLink(
                  label: 'All due →',
                  onTap: () => shell?.openMembers(filter: MemberFilter.due),
                ),
          child: _OverdueList(rows: due.take(6).toList()),
        );
        final recent = PanelCard(
          title: 'Recent payments',
          child: state.recent.isEmpty
              ? const _EmptyRow(message: 'No payments recorded yet.')
              : _RecentPayments(rows: state.recent.take(6).toList()),
        );

        if (!sideBySide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [overdue, const SizedBox(height: 16), recent],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: overdue),
            const SizedBox(width: 16),
            Expanded(child: recent),
          ],
        );
      },
    );
  }
}

class _OverdueList extends StatelessWidget {
  const _OverdueList({required this.rows});

  final List<MemberRow> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const _EmptyRow(message: 'Nobody is overdue. Good work.');
    }

    return Column(
      children: [
        for (var i = 0; i < rows.length; i++)
          // After the attention cards have landed, as the handoff orders it.
          FadeRise(
            index: i,
            baseDelay: const Duration(milliseconds: 250),
            child: _OverdueRow(row: rows[i], showDivider: i > 0),
          ),
      ],
    );
  }
}

/// One overdue member: initials, name, how late, and a way to settle it.
class _OverdueRow extends StatefulWidget {
  const _OverdueRow({required this.row, required this.showDivider});

  final MemberRow row;
  final bool showDivider;

  @override
  State<_OverdueRow> createState() => _OverdueRowState();
}

class _OverdueRowState extends State<_OverdueRow> {
  bool _hovered = false;

  Future<void> _record() async {
    final bloc = context.read<DashboardBloc>();
    final recorded =
        await showAdvancePaymentDialog(context, member: widget.row);
    // The counts, the overdue list and today's revenue all move with one
    // payment, so the whole dashboard is re-read rather than patched.
    if (recorded == true) bloc.add(const DashboardRequested());
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final member = widget.row.member;
    final until = widget.row.paidUntil;
    final late = until == null
        ? null
        : DateTime.now().difference(until).inDays;

    return Column(
      children: [
        if (widget.showDivider) Divider(height: 1, color: palette.border),
        MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => MemberDetailScreen(memberId: member.id),
            )),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              color: _hovered ? palette.surfaceRaised : Colors.transparent,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              child: Row(
                children: [
                  InitialsAvatar(name: member.fullName),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          member.fullName,
                          style: TextStyle(
                              fontSize: 13, color: palette.textPrimary),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '#${member.memberCode} · ${formatPhoneForDisplay(member.phone)}',
                          style: TextStyle(
                              fontSize: 11, color: palette.textMuted),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (late != null && late > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: palette.dueBg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      child: Text(
                        '$late day${late == 1 ? '' : 's'} late',
                        style: TextStyle(fontSize: 11, color: palette.due),
                      ),
                    ),
                  ],
                  const SizedBox(width: 4),
                  // Its own tap target inside the row: the row opens the
                  // profile, this goes straight to taking the money.
                  TextButton(
                    onPressed: _record,
                    style: TextButton.styleFrom(
                      foregroundColor: palette.accentText,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 4),
                      minimumSize: const Size(0, 28),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                    child: const Text('Record'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyRow extends StatelessWidget {
  const _EmptyRow({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      child: Text(
        message,
        style: TextStyle(fontSize: 13, color: context.palette.textMuted),
      ),
    );
  }
}

/// The last few payments, as the handoff lists them: who paid, the receipt and
/// how, the amount and day, and whether the receipt reached WhatsApp.
///
/// Not the full payment table: that has seven columns built for the Payments
/// screen, and squeezed into half the dashboard it truncated everything.
class _RecentPayments extends StatelessWidget {
  const _RecentPayments({required this.rows});

  final List<PaymentRow> rows;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Column(
      children: [
        for (var i = 0; i < rows.length; i++)
          FadeRise(
            index: i,
            baseDelay: const Duration(milliseconds: 300),
            child: Column(
              children: [
                if (i > 0) Divider(height: 1, color: palette.border),
                _RecentPaymentRow(row: rows[i]),
              ],
            ),
          ),
      ],
    );
  }
}

class _RecentPaymentRow extends StatelessWidget {
  const _RecentPaymentRow({required this.row});

  final PaymentRow row;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final status = row.whatsAppStatus;
    final delivered = status == WhatsAppStatus.sent ||
        status == WhatsAppStatus.delivered ||
        status == WhatsAppStatus.read;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(row.member.fullName,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(fontSize: 13, color: palette.textPrimary)),
                Text(
                  [
                    ?row.receipt?.receiptNumber,
                    paymentMethodLabel(row.payment.method),
                  ].join(' · '),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: palette.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatMinorUnits(row.payment.amountMinor),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: palette.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Text(formatShortDate(row.payment.paymentDate),
                  style: TextStyle(fontSize: 11, color: palette.textMuted)),
            ],
          ),
          const SizedBox(width: 12),
          // Only a tick for a receipt that actually went: a failed or queued
          // send must not look like a delivered one.
          SizedBox(
            width: 16,
            child: delivered
                ? Tooltip(
                    message: 'Receipt sent on WhatsApp',
                    child: Icon(Icons.done_all, size: 15, color: palette.paid),
                  )
                : status == WhatsAppStatus.failed
                    ? Tooltip(
                        message: 'WhatsApp send failed',
                        child: Icon(Icons.error_outline,
                            size: 15, color: palette.due),
                      )
                    : null,
          ),
        ],
      ),
    );
  }
}
