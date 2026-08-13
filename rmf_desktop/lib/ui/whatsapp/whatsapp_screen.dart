import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/whatsapp_bloc.dart';
import '../../data/database.dart';
import '../../data/receipt_repository.dart';
import '../../data/settings_repository.dart';
import '../../services/record_payment_service.dart';
import '../../services/whatsapp/whatsapp_client.dart';
import '../../theme/app_theme.dart';
import '../widgets/status_badge.dart';

class WhatsAppScreen extends StatelessWidget {
  const WhatsAppScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => WhatsAppBloc(
        repository: context.read<ReceiptRepository>(),
        settings: context.read<SettingsRepository>(),
        service: context.read<RecordPaymentService>(),
      )..add(const WhatsAppRequested()),
      child: const _WhatsAppView(),
    );
  }
}

const _filters = <WhatsAppStatus?>[
  null,
  WhatsAppStatus.sent,
  WhatsAppStatus.delivered,
  WhatsAppStatus.read,
  WhatsAppStatus.failed,
];

String _filterLabel(WhatsAppStatus? status) => switch (status) {
      null => 'All',
      WhatsAppStatus.queued => 'Queued',
      WhatsAppStatus.sent => 'Sent',
      WhatsAppStatus.delivered => 'Delivered',
      WhatsAppStatus.read => 'Read',
      WhatsAppStatus.failed => 'Failed',
    };

class _WhatsAppView extends StatelessWidget {
  const _WhatsAppView();

  @override
  Widget build(BuildContext context) {
    return BlocListener<WhatsAppBloc, WhatsAppState>(
      listenWhen: (a, b) => b.message != null && a.message != b.message,
      listener: (context, state) => ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(state.message!))),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: BlocBuilder<WhatsAppBloc, WhatsAppState>(
          builder: (context, state) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('WhatsApp',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.ink50)),
                const SizedBox(height: 16),
                if (state.config != null) _ProviderCard(config: state.config!),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  children: _filters.map((f) {
                    final selected = f == state.filter;
                    return ChoiceChip(
                      label: Text(_filterLabel(f)),
                      selected: selected,
                      showCheckmark: false,
                      backgroundColor: Colors.transparent,
                      selectedColor:
                          AppColors.crimson500.withValues(alpha: .14),
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
                      onSelected: (_) => context
                          .read<WhatsAppBloc>()
                          .add(WhatsAppFilterChanged(f)),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: switch (state.status) {
                    WhatsAppScreenStatus.loading =>
                      const Center(child: CircularProgressIndicator()),
                    WhatsAppScreenStatus.failed => Center(
                        child: Text('Could not load messages: ${state.error}',
                            style: const TextStyle(color: AppColors.expired))),
                    WhatsAppScreenStatus.ready => state.rows.isEmpty
                        ? const Center(
                            child: Text('No WhatsApp messages in this view.',
                                style: kMutedStyle))
                        : ListView.separated(
                            itemCount: state.rows.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, i) => _MessageCard(
                              row: state.rows[i],
                              retrying: state.retryingReceiptId ==
                                  state.rows[i].message.receiptId,
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

class _ProviderCard extends StatelessWidget {
  const _ProviderCard({required this.config});

  final WhatsAppConfig config;

  @override
  Widget build(BuildContext context) {
    final isMock = config.kind != WhatsAppProviderKind.meta;

    return Container(
      padding: const EdgeInsets.all(16),
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
              _Info(
                label: 'Provider',
                value: isMock ? 'Mock (development)' : 'Meta Cloud API',
              ),
              const SizedBox(width: 40),
              _Info(
                label: 'Status',
                value: config.isConfigured ? 'Connected' : 'Not configured',
                color:
                    config.isConfigured ? AppColors.paid : AppColors.expired,
              ),
              if (config.maskedPhoneNumberId != null) ...[
                const SizedBox(width: 40),
                _Info(
                    label: 'Phone number ID',
                    value: config.maskedPhoneNumberId!),
              ],
            ],
          ),
          if (isMock) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.ink950,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.ink800),
              ),
              child: const Text(
                'Mock mode records realistic results but nothing leaves this '
                'machine. Switch to Meta in Settings and add credentials to '
                'deliver real messages.',
                style: kMutedStyle,
              ),
            ),
          ],
          if (!config.isConfigured && config.missing.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Missing: ${config.missing.join(", ")}',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.expired)),
          ],
        ],
      ),
    );
  }
}

class _Info extends StatelessWidget {
  const _Info({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: kLabelStyle),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: color ?? AppColors.ink50)),
      ],
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.row, required this.retrying});

  final WhatsAppMessageRow row;
  final bool retrying;

  @override
  Widget build(BuildContext context) {
    final message = row.message;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.ink900,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.ink800),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${row.member.fullName} · ${message.phone}',
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.ink50)),
                const SizedBox(height: 2),
                Text(
                  '${row.receipt.receiptNumber}'
                  '${message.attemptNumber > 1 ? " · attempt ${message.attemptNumber}" : ""}',
                  style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: AppColors.ink400),
                ),
                if (message.externalMessageId != null)
                  Text(message.externalMessageId!,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.ink600)),
                if (message.errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(message.errorMessage!,
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.expired)),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              WhatsAppStatusBadge(status: message.status),
              if (message.status == WhatsAppStatus.failed) ...[
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: retrying
                      ? null
                      : () => context
                          .read<WhatsAppBloc>()
                          .add(WhatsAppRetryRequested(message.receiptId)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                  child: Text(retrying ? 'Retrying…' : 'Retry'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
