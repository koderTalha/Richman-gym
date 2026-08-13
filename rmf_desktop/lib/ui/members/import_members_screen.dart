import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/auth_bloc.dart';
import '../../bloc/import_bloc.dart';
import '../../data/database.dart';
import '../../data/member_repository.dart';
import '../../domain/money.dart';
import '../../services/import_service.dart';
import '../../services/ledger_import.dart';
import '../../theme/app_theme.dart';

/// Import wizard for the owner's existing Excel ledger.
///
/// Steps: pick file -> choose sheet, year, plan and section -> preview the
/// pivoted result -> commit.
class ImportMembersScreen extends StatelessWidget {
  const ImportMembersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => ImportBloc(
        memberRepository: context.read<MemberRepository>(),
        database: context.read<AppDatabase>(),
      )..add(const ImportOptionsRequested()),
      child: const _ImportView(),
    );
  }
}

class _ImportView extends StatelessWidget {
  const _ImportView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.ink900,
        title: const Text('Import Members from Excel'),
      ),
      body: BlocBuilder<ImportBloc, ImportState>(
        builder: (context, state) {
          final bloc = context.read<ImportBloc>();

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (state.summary != null)
                      _SummaryCard(
                        summary: state.summary!,
                        onDone: () => Navigator.of(context).pop(true),
                      )
                    else ...[
                      _StepCard(
                        step: 1,
                        title: 'Choose the ledger file',
                        child: Row(
                          children: [
                            FilledButton.icon(
                              onPressed: state.busy
                                  ? null
                                  : () => bloc.add(const ImportFileRequested()),
                              icon: const Icon(Icons.folder_open, size: 18),
                              label: const Text('Choose file…'),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                state.fileName ??
                                    'No file selected (.xlsx, .xls, .csv)',
                                style: kMutedStyle,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (state.sheets.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _StepCard(
                          step: 2,
                          title: 'Choose the sheet and confirm the details',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: state.sheets.keys.map((name) {
                                  final selected = name == state.selectedSheet;
                                  return ChoiceChip(
                                    label: Text(name),
                                    selected: selected,
                                    showCheckmark: false,
                                    backgroundColor: Colors.transparent,
                                    selectedColor: AppColors.crimson500
                                        .withValues(alpha: .14),
                                    labelStyle: TextStyle(
                                      fontSize: 12,
                                      color: selected
                                          ? AppColors.crimson400
                                          : AppColors.ink400,
                                    ),
                                    side: BorderSide(
                                        color: selected
                                            ? Colors.transparent
                                            : AppColors.ink800),
                                    onSelected: (_) =>
                                        bloc.add(ImportSheetSelected(name)),
                                  );
                                }).toList(),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  SizedBox(
                                    width: 160,
                                    child: TextFormField(
                                      key: ValueKey(
                                          'year-${state.selectedSheet}'),
                                      initialValue: '${state.year}',
                                      decoration: const InputDecoration(
                                          labelText: 'Year of this sheet',
                                          isDense: true),
                                      keyboardType: TextInputType.number,
                                      onChanged: (v) {
                                        final parsed = int.tryParse(v);
                                        if (parsed != null &&
                                            parsed > 2000 &&
                                            parsed < 2100) {
                                          bloc.add(ImportYearChanged(parsed));
                                        }
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  SizedBox(
                                    width: 220,
                                    child: DropdownButtonFormField<int>(
                                      initialValue: state.planId,
                                      decoration: const InputDecoration(
                                          labelText: 'Assign plan',
                                          isDense: true),
                                      items: state.plans
                                          .map((p) => DropdownMenuItem(
                                              value: p.id, child: Text(p.name)))
                                          .toList(),
                                      onChanged: (v) => v == null
                                          ? null
                                          : bloc.add(ImportPlanChanged(v)),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (state.parsed != null) ...[
                        const SizedBox(height: 16),
                        _StepCard(
                          step: 3,
                          title: 'Preview',
                          child: _Preview(ledger: state.parsed!),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            FilledButton(
                              onPressed:
                                  (state.busy || state.parsed!.valid.isEmpty)
                                      ? null
                                      : () {
                                          final userId = context
                                              .read<AuthBloc>()
                                              .state
                                              .user!
                                              .id;
                                          bloc.add(ImportCommitted(userId));
                                        },
                              child: Text(state.busy
                                  ? 'Importing…'
                                  : 'Import ${state.parsed!.valid.length} members'),
                            ),
                            const SizedBox(width: 12),
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(false),
                              child: const Text('Cancel'),
                            ),
                          ],
                        ),
                      ],
                    ],
                    if (state.error != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.expiredBg,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(state.error!,
                            style: const TextStyle(
                                color: AppColors.expired, fontSize: 13)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard(
      {required this.step, required this.title, required this.child});

  final int step;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.ink900,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.ink800),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: AppColors.crimson500,
                child: Text('$step',
                    style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white,
                        fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 10),
              Text(title,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink50)),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.ledger});

  final ParsedLedger ledger;

  @override
  Widget build(BuildContext context) {
    final sample = ledger.valid.take(8).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 24,
          runSpacing: 8,
          children: [
            _Stat(label: 'Members to import', value: '${ledger.valid.length}'),
            _Stat(label: 'Payments to create', value: '${ledger.totalPayments}'),
            _Stat(
              label: 'Without a phone',
              value: '${ledger.withoutPhone}',
              tone: ledger.withoutPhone == 0 ? null : AppColors.due,
            ),
            _Stat(
              label: 'Rows skipped',
              value: '${ledger.invalid.length}',
              tone: ledger.invalid.isEmpty ? null : AppColors.expired,
            ),
            _Stat(label: 'Year', value: '${ledger.year}'),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          'Historical payments are imported without sending any WhatsApp '
          'receipts. Re-importing the same sheet will not duplicate anything.',
          style: kMutedStyle,
        ),
        if (ledger.paymentsUsingPlanFee > 0) ...[
          const SizedBox(height: 6),
          Text(
            '${ledger.paymentsUsingPlanFee} paid months show ### instead of a '
            'figure (the Excel column is too narrow). These will be recorded at '
            'the plan fee. Widen those columns in Excel first if the amounts '
            'differ from the standard fee.',
            style: const TextStyle(fontSize: 12, color: AppColors.due),
          ),
        ],
        if (ledger.withoutPhone > 0) ...[
          const SizedBox(height: 6),
          Text(
            '${ledger.withoutPhone} members have no phone number. They will '
            'still be imported — they just cannot receive WhatsApp receipts '
            'until a number is added.',
            style: const TextStyle(fontSize: 12, color: AppColors.due),
          ),
        ],
        const SizedBox(height: 16),
        if (sample.isNotEmpty) ...[
          const Text('FIRST ROWS', style: kLabelStyle),
          const SizedBox(height: 8),
          ...sample.map((row) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(row.name,
                          style: const TextStyle(
                              fontSize: 13, color: AppColors.ink50)),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        row.normalizedPhone ?? 'no phone',
                        style: TextStyle(
                          fontSize: 12,
                          color: row.hasPhone
                              ? AppColors.ink400
                              : AppColors.due,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        '${row.payments.length} payments · '
                        '${formatMinorUnits(row.totalMinor)}',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.ink200),
                      ),
                    ),
                  ],
                ),
              )),
        ],
        if (ledger.invalid.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('ROWS THAT WILL BE SKIPPED', style: kLabelStyle),
          const SizedBox(height: 8),
          ...ledger.invalid.take(6).map((row) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'Row ${row.sourceRow}: '
                  '${row.name.isEmpty ? "(no name)" : row.name} — '
                  '${row.problems.join(", ")}',
                  style: const TextStyle(fontSize: 12, color: AppColors.due),
                ),
              )),
        ],
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.tone});

  final String label;
  final String value;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: kLabelStyle),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: tone ?? AppColors.ink50)),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary, required this.onDone});

  final ImportSummary summary;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.paidBg.withValues(alpha: .4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.paid.withValues(alpha: .3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Import complete',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.ink50)),
          const SizedBox(height: 14),
          _line('${summary.membersCreated} members imported'),
          _line('${summary.membersMatched} existing members matched by phone'),
          _line('${summary.paymentsCreated} historical payments created'),
          if (summary.paymentsSkipped > 0)
            _line('${summary.paymentsSkipped} payments already existed, skipped'),
          if (summary.rowsNeedingAttention > 0)
            _line('${summary.rowsNeedingAttention} rows skipped, need attention',
                tone: AppColors.due),
          const SizedBox(height: 20),
          FilledButton(onPressed: onDone, child: const Text('Done')),
        ],
      ),
    );
  }

  Widget _line(String text, {Color? tone}) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: TextStyle(fontSize: 13, color: tone ?? AppColors.ink200)),
      );
}
