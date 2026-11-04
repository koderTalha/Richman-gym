import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/database.dart';
import '../../domain/money.dart';
import '../../services/payment_inactivity_service.dart';
import '../../theme/app_theme.dart';
import '../payments/payment_history_table.dart';

/// Why a member is inactive, when the app deactivated them for missed
/// payments, and every earlier time it did.
///
/// Nothing at all for a member it never has — which is almost everybody.
class MissedPaymentPanel extends StatefulWidget {
  const MissedPaymentPanel({
    super.key,
    required this.member,
    required this.onReactivate,
  });

  final Member member;
  final VoidCallback onReactivate;

  @override
  State<MissedPaymentPanel> createState() => _MissedPaymentPanelState();
}

class _MissedPaymentPanelState extends State<MissedPaymentPanel> {
  late Future<List<DeactivationEpisode>> _history = _load();

  /// Read as nullable so a tree built without the service — in a widget
  /// test — simply shows no panel.
  Future<List<DeactivationEpisode>> _load() async =>
      await context
          .read<PaymentInactivityService?>()
          ?.historyFor(widget.member.id) ??
      const [];

  @override
  void didUpdateWidget(MissedPaymentPanel old) {
    super.didUpdateWidget(old);
    // Reactivating closes the episode; read it again so the panel says so.
    if (old.member.deactivatedAt != widget.member.deactivatedAt) {
      _history = _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<DeactivationEpisode>>(
      future: _history,
      builder: (context, snapshot) {
        final history = snapshot.data ?? const <DeactivationEpisode>[];
        if (history.isEmpty) return const SizedBox.shrink();

        final open = history.first.isOpen && widget.member.deactivatedAt != null
            ? history.first
            : null;
        final earlier = [
          for (final e in history)
            if (e != open) e,
        ];

        return Padding(
          padding: const EdgeInsets.only(top: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (open != null)
                _OpenEpisode(episode: open, onReactivate: widget.onReactivate),
              if (earlier.isNotEmpty) ...[
                if (open != null) const SizedBox(height: 12),
                _EarlierEpisodes(episodes: earlier),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _OpenEpisode extends StatelessWidget {
  const _OpenEpisode({required this.episode, required this.onReactivate});

  final DeactivationEpisode episode;
  final VoidCallback onReactivate;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final row = episode.row;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.inactiveBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Wraps rather than overflowing: on a narrow window the button
          // drops under the heading instead of squeezing it.
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.event_busy_outlined,
                      size: 18, color: palette.inactive),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      'Inactive — missed payments',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: palette.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              OutlinedButton.icon(
                onPressed: onReactivate,
                icon: const Icon(Icons.person_outline, size: 16),
                label: const Text('Reactivate'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Deactivated by the app after the bill due '
            '${formatCalendarDate(row.firstMissedDue)} went '
            '${row.graceDays} days unpaid. What that lapse billed was '
            'written off; payments and receipts are unchanged. Reactivating '
            'asks whether they kept coming: if so the write-off is taken '
            'back, otherwise billing starts afresh from the day they returned.',
            style: mutedStyleOf(context),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 28,
            runSpacing: 12,
            children: [
              _Fact(
                  label: 'Last paid until',
                  value: formatCalendarDate(row.lastPaidUntil)),
              _Fact(
                  label: 'First missed due',
                  value: formatCalendarDate(row.firstMissedDue)),
              _Fact(
                  label: 'Deactivated on',
                  value: formatCalendarDate(row.deactivatedOn)),
              _Fact(
                  label: 'Written off',
                  value: formatMinorUnits(row.waivedMinor)),
              if (row.olderArrearsMinor > 0)
                _Fact(
                  label: 'Older months still owed',
                  value: formatMinorUnits(row.olderArrearsMinor),
                  tone: palette.due,
                ),
            ],
          ),
          if (episode.waivers.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final w in episode.waivers)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'Written off: ${formatCalendarDate(w.periodStart)} to '
                  '${formatCalendarDate(w.periodEnd)} · '
                  '${formatMinorUnits(w.amountMinor)}',
                  style: TextStyle(fontSize: 12, color: palette.textMuted),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _EarlierEpisodes extends StatelessWidget {
  const _EarlierEpisodes({required this.episodes});

  final List<DeactivationEpisode> episodes;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: palette.surfaceOverlay,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Earlier missed-payment deactivations',
              style: labelStyleOf(context)),
          const SizedBox(height: 6),
          for (final e in episodes)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Deactivated ${formatCalendarDate(e.row.deactivatedOn)}'
                '${e.row.reactivatedAt == null ? '' : e.row.reinstated ? ', reinstated ${formatShortDate(e.row.reactivatedAt)} '
                    '(kept coming — write-off taken back)' : ', reactivated '
                    '${formatShortDate(e.row.reactivatedAt)}'}'
                ' · ${formatMinorUnits(e.row.waivedMinor)} '
                '${e.row.reinstated ? 'restored' : 'written off'} '
                'from the bill due ${formatCalendarDate(e.row.firstMissedDue)}',
                style: TextStyle(fontSize: 13, color: palette.textSecondary),
              ),
            ),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value, this.tone});

  final String label;
  final String value;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: labelStyleOf(context)),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: tone ?? context.palette.textPrimary,
          ),
        ),
      ],
    );
  }
}
