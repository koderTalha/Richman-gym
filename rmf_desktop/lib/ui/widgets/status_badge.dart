import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../domain/member_status.dart';
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
      MemberStatus.paid => (AppColors.paid, AppColors.paidBg),
      MemberStatus.due => (AppColors.due, AppColors.dueBg),
      MemberStatus.expired => (AppColors.expired, AppColors.expiredBg),
      MemberStatus.inactive => (AppColors.inactive, AppColors.inactiveBg),
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
      return const StatusBadge(
        label: 'Not sent',
        fg: AppColors.ink600,
        bg: AppColors.ink800,
      );
    }

    final (label, fg, bg) = switch (status!) {
      WhatsAppStatus.queued => ('Queued', AppColors.inactive, AppColors.inactiveBg),
      WhatsAppStatus.sent => ('Sent', AppColors.due, AppColors.dueBg),
      WhatsAppStatus.delivered => ('Delivered', AppColors.paid, AppColors.paidBg),
      WhatsAppStatus.read => ('Read', AppColors.paid, AppColors.paidBg),
      WhatsAppStatus.failed => ('Failed', AppColors.expired, AppColors.expiredBg),
    };
    return StatusBadge(label: label, fg: fg, bg: bg);
  }
}
