import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/member_repository.dart';
import '../domain/payment_inactivity.dart';
import '../services/payment_inactivity_service.dart';
import '../theme/app_theme.dart';
import 'members/member_detail_screen.dart';
import 'payments/advance_payment_dialog.dart';
import 'payments/payment_history_table.dart' show formatCalendarDate;
import 'widgets/page_scaffold.dart';

/// Members the missed-payment rule will deactivate within the week unless
/// they pay, soonest first — the chance to talk to someone who is still
/// training but behind, before the app takes them for gone.
///
/// Shown only while the rule is switched on and somebody is on the list.
class DeactivatingSoonPanel extends StatefulWidget {
  const DeactivatingSoonPanel({super.key, required this.refreshKey, this.onChanged});

  /// Anything that changes when the dashboard reloads; the list is read again
  /// whenever it does.
  final Object refreshKey;

  /// Called after a payment is recorded from the list.
  final VoidCallback? onChanged;

  @override
  State<DeactivatingSoonPanel> createState() => _DeactivatingSoonPanelState();
}

class _DeactivatingSoonPanelState extends State<DeactivatingSoonPanel> {
  late Future<List<InactivityCase>> _upcoming = _load();

  /// Read as nullable so a dashboard built without the service — in a widget
  /// test — simply has no panel.
  Future<List<InactivityCase>> _load() async {
    final service = context.read<PaymentInactivityService?>();
    if (service == null || !await service.isEnabled()) return const [];
    return (await service.preview()).upcoming;
  }

  @override
  void didUpdateWidget(DeactivatingSoonPanel old) {
    super.didUpdateWidget(old);
    if (!identical(old.refreshKey, widget.refreshKey)) _upcoming = _load();
  }

  Future<void> _record(int memberId) async {
    final row = await context.read<MemberRepository>().byId(memberId);
    if (row == null || !mounted) return;
    final recorded = await showAdvancePaymentDialog(context, member: row);
    if (recorded == true) {
      widget.onChanged?.call();
      setState(() => _upcoming = _load());
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<InactivityCase>>(
      future: _upcoming,
      builder: (context, snapshot) {
        final cases = snapshot.data ?? const <InactivityCase>[];
        if (cases.isEmpty) return const SizedBox.shrink();
        final palette = context.palette;

        return Padding(
          padding: const EdgeInsets.only(top: 22),
          child: PanelCard(
            title: 'Deactivating this week unless they pay',
            child: Column(
              children: [
                for (var i = 0; i < cases.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: palette.border),
                  _Row(
                    item: cases[i],
                    onOpen: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) =>
                          MemberDetailScreen(memberId: cases[i].member.id),
                    )),
                    onRecord: () => _record(cases[i].member.id),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.item, required this.onOpen, required this.onRecord});

  final InactivityCase item;
  final VoidCallback onOpen;
  final VoidCallback onRecord;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final verdict = item.verdict as PaymentInactivityGrace;
    final member = item.member;

    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '#${member.memberCode} ${member.fullName}',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: palette.textPrimary),
                  ),
                  Text(
                    'Unpaid since ${formatCalendarDate(verdict.firstMissedDue)}'
                    ' · deactivated on ${formatCalendarDate(verdict.deadline)}',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: palette.due),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: onRecord,
              style: TextButton.styleFrom(
                foregroundColor: palette.accentText,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                minimumSize: const Size(0, 28),
                textStyle: const TextStyle(fontSize: 12),
              ),
              child: const Text('Record'),
            ),
          ],
        ),
      ),
    );
  }
}
