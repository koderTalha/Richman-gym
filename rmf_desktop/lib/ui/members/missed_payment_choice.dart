import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/auth_bloc.dart';
import '../../data/member_repository.dart';
import '../../domain/money.dart';
import '../../services/billing_cycle_service.dart';
import '../../services/payment_inactivity_service.dart';
import '../../theme/app_theme.dart';
import '../payments/payment_history_table.dart';
import 'restart_billing_action.dart';

enum _Choice { keptComing, returning }

/// Brings back a member the app deactivated for missed payments, after asking
/// the one question the app cannot answer for itself: were they coming all
/// along?
///
/// There is no attendance, so a member who kept training but could not pay
/// looks exactly like one who left. The owner knows which, and says so here —
/// before any money is taken, because the answer decides where it goes:
///
/// - **Kept coming.** The write-off is taken back and those months are owed
///   again, so a payment of "October and November" settles October and
///   November. See `PaymentInactivityService.reinstate`.
/// - **Coming back after a gap.** The write-off stands and billing restarts
///   from the day they came back — the ordinary reactivation.
///
/// Returns true once the member is active again either way; false if the
/// owner cancelled or the app refused, with the reason shown.
Future<bool> resolveMissedPaymentLapse(
  BuildContext context, {
  required MemberRow member,
}) async {
  final episode = member.missedPaymentDeactivation;
  if (episode == null) return false;

  final inactivity = context.read<PaymentInactivityService>();
  final members = context.read<MemberRepository>();
  final cycles = context.read<BillingCycleService>();
  final actorId = context.read<AuthBloc>().state.user!.id;

  final choice = await showDialog<_Choice>(
    context: context,
    builder: (_) => _ChoiceDialog(member: member),
  );
  if (choice == null || !context.mounted) return false;

  switch (choice) {
    case _Choice.keptComing:
      final result =
          await inactivity.reinstate(memberId: member.id, actorId: actorId);
      if (!context.mounted) return result is MemberReinstated;
      switch (result) {
        case MemberReinstated(:final restoredMinor):
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${member.member.fullName} is active again. '
                '${formatMinorUnits(restoredMinor)} is owed again.'),
          ));
          return true;
        case ReinstateRefused(:final reason):
          await _showRefusal(context, reason);
          return false;
      }

    case _Choice.returning:
      final restart = await showRestartBillingDialog(
        context,
        member: member,
        reactivate: true,
      );
      if (restart == null) return false;
      await members.setActive(member.id, true, actorId: actorId);
      final from = restart.from;
      if (from != null) {
        // As on the member screen: a refused restart still leaves them
        // active, with the reason shown.
        final result = await cycles.restartBilling(
            memberId: member.id, from: from, actorId: actorId);
        if (result is BillingRestartRefused && context.mounted) {
          await _showRefusal(context, result.reason);
        }
      }
      return true;
  }
}

Future<void> _showRefusal(BuildContext context, String reason) =>
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: dialogContext.palette.surfaceRaised,
        title: const Text('Not changed'),
        content: Text(reason, style: mutedStyleOf(dialogContext)),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );

class _ChoiceDialog extends StatelessWidget {
  const _ChoiceDialog({required this.member});

  final MemberRow member;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final episode = member.missedPaymentDeactivation!;
    final name = member.member.fullName;
    final written = formatMinorUnits(episode.waivedMinor);

    return AlertDialog(
      backgroundColor: palette.surfaceRaised,
      title: Text('Was $name still coming?'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'The app deactivated $name on '
                '${formatCalendarDate(episode.deactivatedOn)} because the '
                'bill due ${formatCalendarDate(episode.firstMissedDue)} went '
                '${episode.graceDays} days unpaid, and wrote off $written. '
                'It cannot tell whether they were training in that time — '
                'only you can.',
                style: TextStyle(fontSize: 13, color: palette.textPrimary),
              ),
              const SizedBox(height: 16),
              _Option(
                icon: Icons.fitness_center,
                title: 'Yes, kept coming — restore $written',
                body: 'The written-off months are owed again, and the '
                    'payment you take next settles them first, oldest month '
                    'first.',
                onTap: () => Navigator.of(context).pop(_Choice.keptComing),
              ),
              const SizedBox(height: 10),
              _Option(
                icon: Icons.login,
                title: 'No, coming back after a gap — start fresh',
                body: 'The written-off months stay written off. Billing '
                    'starts again from the day they came back.',
                onTap: () => Navigator.of(context).pop(_Choice.returning),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          style: keepButtonStyleOf(context),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: palette.surfaceOverlay,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: palette.borderStrong),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: palette.accentText),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: palette.textPrimary)),
                    const SizedBox(height: 4),
                    Text(body, style: mutedStyleOf(context)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: palette.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
