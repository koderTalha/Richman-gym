import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/auth_bloc.dart';
import '../../bloc/historical_review_bloc.dart';
import '../../data/database.dart';
import '../../domain/money.dart';
import '../../services/historical_pricing_review.dart';
import '../../theme/app_theme.dart';

/// Where the owner rules on a month that ended while carrying a price the
/// member had, by then, already been moved off.
///
/// Every row here is a **candidate**, not an accusation: the database cannot
/// tell a member who genuinely owed the old, higher price apart from one whose
/// cycle simply opened before a plan change caught up with it. Both leave the
/// identical rows. This screen exists so a human — who can ask the member, or
/// simply remembers what was agreed — makes that call instead of the app
/// guessing. See `services/historical_pricing_review.dart`.
///
/// Deliberately reached from Settings rather than the sidebar: this is an
/// occasional, owner-initiated action on old business, not something the
/// gym's day-to-day runs through.
class HistoricalReviewScreen extends StatelessWidget {
  const HistoricalReviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => HistoricalReviewBloc(
        db: context.read<AppDatabase>(),
        actorId: context.read<AuthBloc>().state.user?.id,
      )..add(const HistoricalReviewRequested()),
      child: const _HistoricalReviewView(),
    );
  }
}

class _HistoricalReviewView extends StatefulWidget {
  const _HistoricalReviewView();

  @override
  State<_HistoricalReviewView> createState() => _HistoricalReviewViewState();
}

class _HistoricalReviewViewState extends State<_HistoricalReviewView> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<HistoricalReviewBloc, HistoricalReviewState>(
      listenWhen: (a, b) => b.message != null && a.message != b.message,
      listener: (context, state) => ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(state.message!))),
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(
            backgroundColor: context.palette.surfaceRaised,
            title: const Text('Historical Billing Review'),
          ),
          body: switch (state.status) {
            HistoricalReviewStatus.loading =>
              const Center(child: CircularProgressIndicator()),
            HistoricalReviewStatus.failed => Center(
                child: Text(state.error ?? 'Could not load the review.',
                    style: TextStyle(color: context.palette.expired)),
              ),
            HistoricalReviewStatus.ready => state.isEmpty
                ? _EmptyState()
                : ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      Text(
                        'These months ended while still asking for a price '
                        "the member's record suggests they had already moved "
                        'away from. Nothing here has been changed — check '
                        'each one and decide.',
                        style: mutedStyleOf(context),
                      ),
                      const SizedBox(height: 16),
                      _SearchAndFilter(
                        controller: _searchController,
                        state: state,
                      ),
                      const SizedBox(height: 16),
                      if (state.noMatches)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: Text(
                              'No months match "${state.searchTerm}"'
                              '${state.planFilter == null ? '' : ' on ${state.planFilter}'}.',
                              style: mutedStyleOf(context),
                            ),
                          ),
                        )
                      else
                        for (final candidate in state.visibleCandidates)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: _CandidateCard(candidate: candidate),
                          ),
                    ],
                  ),
          },
        );
      },
    );
  }
}

/// The search box and plan chips, in the same shape the Members screen uses
/// for the same job — a text field filtered live rather than on submit,
/// because everything here is already loaded in memory and there is no query
/// to wait on.
class _SearchAndFilter extends StatelessWidget {
  const _SearchAndFilter({required this.controller, required this.state});

  final TextEditingController controller;
  final HistoricalReviewState state;

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<HistoricalReviewBloc>();
    final plans = state.plansInCandidates;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 280,
          child: TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: 'Search member name or code…',
              prefixIcon: const Icon(Icons.search, size: 18),
              isDense: true,
              suffixIcon: state.searchTerm.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear, size: 16),
                      onPressed: () {
                        controller.clear();
                        bloc.add(const HistoricalReviewSearchChanged(''));
                      },
                    ),
            ),
            onChanged: (v) =>
                bloc.add(HistoricalReviewSearchChanged(v)),
          ),
        ),
        if (plans.length > 1) ...[
          const SizedBox(width: 20),
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final plan in [null, ...plans])
                  _PlanChip(
                    label: plan ?? 'All plans',
                    selected: state.planFilter == plan,
                    onSelected: () =>
                        bloc.add(HistoricalReviewPlanFilterChanged(plan)),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _PlanChip extends StatelessWidget {
  const _PlanChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      backgroundColor: Colors.transparent,
      selectedColor: context.palette.accent.withValues(alpha: .14),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        color: selected ? context.palette.accentText : context.palette.textMuted,
      ),
      side: BorderSide(
        color: selected ? Colors.transparent : context.palette.border,
      ),
      onSelected: (_) => onSelected(),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.fact_check_outlined,
                size: 40, color: context.palette.textMuted),
            const SizedBox(height: 12),
            Text('Nothing needs review right now.',
                style: TextStyle(
                    fontSize: 14, color: context.palette.textSecondary)),
            const SizedBox(height: 6),
            Text(
              'A month appears here only when it ended still billing a price '
              'the member had, by then, been moved off.',
              textAlign: TextAlign.center,
              style: mutedStyleOf(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _CandidateCard extends StatelessWidget {
  const _CandidateCard({required this.candidate});

  final HistoricalPricingCandidate candidate;

  Future<void> _correct(BuildContext context) async {
    final bloc = context.read<HistoricalReviewBloc>();
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _ReasonDialog(
        title: 'Correct to ${formatMinorUnits(candidate.currentFeeMinor)}?',
        confirmLabel: 'Correct the bill',
        defaultReason: candidate.evidence.isNotEmpty
            ? candidate.evidence.first
            : 'Billed under a plan the member had already left.',
      ),
    );
    if (reason == null) return;

    bloc.add(HistoricalReviewCorrected(
      periodId: candidate.period.id,
      correctedAmountMinor: candidate.currentFeeMinor,
      reason: reason,
    ));
  }

  Future<void> _keep(BuildContext context) async {
    final bloc = context.read<HistoricalReviewBloc>();
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _ReasonDialog(
        title: 'Keep the original bill?',
        confirmLabel: 'Keep it',
        defaultReason: 'The member genuinely owed this amount.',
      ),
    );
    if (reason == null) return;

    bloc.add(HistoricalReviewKept(
      periodId: candidate.period.id,
      reason: reason,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${candidate.member.fullName} '
                  '(#${candidate.member.memberCode})',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: palette.textPrimary),
                ),
              ),
              Text(candidate.periodLabel, style: mutedStyleOf(context)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _Figure(
                  label: 'Original bill',
                  value: formatMinorUnits(candidate.billedMinor),
                  color: palette.textPrimary),
              _Figure(
                  label: 'Paid',
                  value: formatMinorUnits(candidate.collectedMinor),
                  color: palette.textSecondary),
              _Figure(
                  label: 'Outstanding',
                  value: formatMinorUnits(candidate.outstandingMinor),
                  color: palette.due),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Current plan: ${candidate.currentPlanName} — '
            '${formatMinorUnits(candidate.currentFeeMinor)}',
            style: TextStyle(fontSize: 12.5, color: palette.textSecondary),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: palette.surfaceBase,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('POTENTIAL ISSUE', style: labelStyleOf(context)),
                const SizedBox(height: 4),
                for (final line in candidate.evidence)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(line,
                        style: TextStyle(
                            fontSize: 12.5,
                            height: 1.4,
                            color: palette.textSecondary)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Was this month meant to be billed at '
            '${formatMinorUnits(candidate.currentFeeMinor)}?',
            style: TextStyle(fontSize: 13, color: palette.textPrimary),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              OutlinedButton(
                onPressed: () => _keep(context),
                child: Text('Keep ${formatMinorUnits(candidate.billedMinor)}'),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: () => _correct(context),
                child: Text(
                    'Correct to ${formatMinorUnits(candidate.currentFeeMinor)}'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: labelStyleOf(context)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  fontSize: 13.5, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}

/// Asked before either action commits — the owner's reasoning is what makes
/// the decision explainable later, and neither the correction nor keeping the
/// bill is a button that should go through silently. Pre-filled with the
/// evidence already shown, since the common case is "yes, that is exactly
/// why", not a blank field the owner has to compose from scratch.
class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({
    required this.title,
    required this.confirmLabel,
    required this.defaultReason,
  });

  final String title;
  final String confirmLabel;
  final String defaultReason;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  late final _controller = TextEditingController(text: widget.defaultReason);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.palette.surfaceRaised,
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: TextField(
          controller: _controller,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Reason'),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final reason = _controller.text.trim();
            Navigator.of(context)
                .pop(reason.isEmpty ? widget.defaultReason : reason);
          },
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
