import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:printing/printing.dart';

import '../../bloc/receipts_bloc.dart';
import '../../data/receipt_repository.dart';
import '../../domain/money.dart';
import '../../services/receipt_storage.dart';
import '../../services/record_payment_service.dart';
import '../../theme/app_theme.dart';
import '../payments/payment_history_table.dart';
import '../widgets/status_badge.dart';

class ReceiptsScreen extends StatelessWidget {
  const ReceiptsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => ReceiptsBloc(
        repository: context.read<ReceiptRepository>(),
        service: context.read<RecordPaymentService>(),
      )..add(const ReceiptsRequested()),
      child: const _ReceiptsView(),
    );
  }
}

class _ReceiptsView extends StatefulWidget {
  const _ReceiptsView();

  @override
  State<_ReceiptsView> createState() => _ReceiptsViewState();
}

class _ReceiptsViewState extends State<_ReceiptsView> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<ReceiptsBloc, ReceiptsState>(
      listenWhen: (a, b) => b.message != null && a.message != b.message,
      listener: (context, state) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(state.message!)));
      },
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: BlocBuilder<ReceiptsBloc, ReceiptsState>(
          builder: (context, state) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Receipts',
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: context.palette.textPrimary)),
                    const SizedBox(height: 4),
                    Text(
                        '${state.rows.length} '
                        '${state.rows.length == 1 ? "receipt" : "receipts"}',
                        style: mutedStyleOf(context)),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    SizedBox(
                      width: 340,
                      child: TextField(
                        controller: _searchController,
                        decoration: const InputDecoration(
                          hintText: 'Search receipt number, member, or phone…',
                          prefixIcon: Icon(Icons.search, size: 18),
                          isDense: true,
                        ),
                        onSubmitted: (v) => context
                            .read<ReceiptsBloc>()
                            .add(ReceiptsSearchSubmitted(v)),
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        children: ReceiptFilter.values.map((f) {
                          final selected = f == state.filter;
                          return ChoiceChip(
                            label: Text(f.label),
                            selected: selected,
                            showCheckmark: false,
                            backgroundColor: Colors.transparent,
                            selectedColor:
                                context.palette.accent.withValues(alpha: .14),
                            labelStyle: TextStyle(
                              fontSize: 12,
                              color: selected
                                  ? context.palette.accentText
                                  : context.palette.textMuted,
                            ),
                            side: BorderSide(
                                color: selected
                                    ? Colors.transparent
                                    : context.palette.border),
                            onSelected: (_) => context
                                .read<ReceiptsBloc>()
                                .add(ReceiptsFilterChanged(f)),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Expanded(
                  child: switch (state.status) {
                    ReceiptsStatus.loading =>
                      const Center(child: CircularProgressIndicator()),
                    ReceiptsStatus.failed => Center(
                        child: Text('Could not load receipts: ${state.error}',
                            style: TextStyle(color: context.palette.expired))),
                    ReceiptsStatus.ready => state.rows.isEmpty
                        ? Center(
                            child: Text(
                                'No receipts yet. Record a payment to generate one.',
                                style: mutedStyleOf(context)))
                        : ListView.separated(
                            itemCount: state.rows.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, i) => _ReceiptCard(
                              row: state.rows[i],
                              resending:
                                  state.resendingId == state.rows[i].receipt.id,
                            ),
                          ),
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ReceiptCard extends StatelessWidget {
  const _ReceiptCard({required this.row, required this.resending});

  final ReceiptRow row;
  final bool resending;

  Future<void> _view(BuildContext context) async {
    final bytes =
        await context.read<ReceiptStorage>().read(row.receipt.pngPath);
    if (bytes == null || !context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: InteractiveViewer(child: Image.memory(bytes)),
      ),
    );
  }

  Future<void> _print(BuildContext context) async {
    final path = row.receipt.pdfPath;
    if (path == null) return;
    final bytes = await context.read<ReceiptStorage>().read(path);
    if (bytes == null) return;
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: row.receipt.receiptNumber,
    );
  }

  @override
  Widget build(BuildContext context) {
    final failed = row.whatsAppStatus == null ||
        row.latestMessage?.errorMessage != null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.palette.surfaceRaised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(row.receipt.receiptNumber,
                        style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                            color: context.palette.textPrimary)),
                    const SizedBox(height: 2),
                    Text('${row.member.fullName} · ${row.member.phone}',
                        style: TextStyle(
                            fontSize: 13, color: context.palette.textSecondary)),
                    const SizedBox(height: 2),
                    Text(
                      '${row.periodLabel} · '
                      '${paymentMethodLabel(row.payment.method)} · '
                      '${formatShortDate(row.payment.paymentDate)}',
                      style: mutedStyleOf(context),
                    ),
                    if (row.latestMessage?.errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(row.latestMessage!.errorMessage!,
                            style: TextStyle(
                                fontSize: 11, color: context.palette.expired)),
                      ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(formatMinorUnits(row.payment.amountMinor),
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: context.palette.accentText)),
                  const SizedBox(height: 6),
                  WhatsAppStatusBadge(status: row.whatsAppStatus),
                ],
              ),
            ],
          ),
          const Divider(height: 20),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () => _view(context),
                icon: const Icon(Icons.visibility_outlined, size: 15),
                label: const Text('View'),
                style: _compact,
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => _print(context),
                icon: const Icon(Icons.print_outlined, size: 15),
                label: const Text('Print / Save PDF'),
                style: _compact,
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: resending
                    ? null
                    : () => context
                        .read<ReceiptsBloc>()
                        .add(ReceiptResendRequested(row.receipt.id)),
                icon: resending
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send_outlined, size: 15),
                label: Text(resending
                    ? 'Sending…'
                    : failed
                        ? 'Send WhatsApp'
                        : 'Resend WhatsApp'),
                style: _compact,
              ),
            ],
          ),
        ],
      ),
    );
  }

  static final _compact = OutlinedButton.styleFrom(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    textStyle: const TextStyle(fontSize: 12),
  );
}
