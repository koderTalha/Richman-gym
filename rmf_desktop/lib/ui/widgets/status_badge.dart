import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../domain/member_status.dart';
import '../../domain/payment_timing.dart';
import '../../theme/app_theme.dart';

class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.label, required this.fg, required this.bg});

  final String label;
  final Color fg;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: .6,
        ),
      ),
    );
  }
}

class MemberStatusBadge extends StatelessWidget {
  const MemberStatusBadge({super.key, required this.status});

  final MemberStatus status;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = switch (status) {
      MemberStatus.paid => (context.palette.paid, context.palette.paidBg),
      MemberStatus.due => (context.palette.due, context.palette.dueBg),
      MemberStatus.expired => (context.palette.expired, context.palette.expiredBg),
      MemberStatus.inactive => (context.palette.inactive, context.palette.inactiveBg),
    };
    return StatusBadge(label: status.label, fg: fg, bg: bg);
  }
}

class WhatsAppStatusBadge extends StatelessWidget {
  const WhatsAppStatusBadge({super.key, required this.status});

  final WhatsAppStatus? status;

  @override
  Widget build(BuildContext context) {
    if (status == null) {
      return StatusBadge(
        label: 'Not sent',
        fg: context.palette.textHint,
        bg: context.palette.border,
      );
    }

    final (label, fg, bg) = switch (status!) {
      WhatsAppStatus.queued => ('Queued', context.palette.inactive, context.palette.inactiveBg),
      WhatsAppStatus.sent => ('Sent', context.palette.due, context.palette.dueBg),
      WhatsAppStatus.delivered => ('Delivered', context.palette.paid, context.palette.paidBg),
      WhatsAppStatus.read => ('Read', context.palette.paid, context.palette.paidBg),
      WhatsAppStatus.failed => ('Failed', context.palette.expired, context.palette.expiredBg),
    };
    return StatusBadge(label: label, fg: fg, bg: bg);
  }
}

/// Why a payment's date and the period it bought do not match.
///
/// Rendered only for a payment that is genuinely early or late. An on-time
/// payment gets nothing at all: a badge on every row is a badge nobody reads,
/// and the two cases worth noticing would be lost among the rest.
class PaymentTimingBadge extends StatelessWidget {
  const PaymentTimingBadge({super.key, required this.timing});

  final PaymentTiming timing;

  @override
  Widget build(BuildContext context) {
    if (!timing.isNoteworthy) return const SizedBox.shrink();

    // Advance borrows the paid colours — money in early is good news. Late
    // borrows the due colours rather than the expired ones: the fee did
    // arrive, so this is the same amber as a member who owes, not the red of
    // a lapsed membership.
    final (fg, bg) = switch (timing) {
      PaymentTiming.advance => (context.palette.paid, context.palette.paidBg),
      PaymentTiming.late => (context.palette.due, context.palette.dueBg),
      PaymentTiming.onTime =>
        (context.palette.inactive, context.palette.inactiveBg),
    };
    return StatusBadge(label: timing.label, fg: fg, bg: bg);
  }
}
