import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../bloc/logs_bloc.dart';
import '../../data/audit_repository.dart';
import '../../data/database.dart';
import '../../domain/dates.dart';
import '../../theme/app_theme.dart';

/// What the app did, in the owner's words.
///
/// The gym's computer is not one anybody can attach a debugger to, and "it
/// deleted something it should not have" is not a question the database file
/// answers on its own. Four tabs: everything that happened, receipt sends,
/// only what went wrong, and the raw file log underneath it all.
class LogsScreen extends StatelessWidget {
  const LogsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => LogsBloc(audit: context.read<AuditRepository>())
        ..add(const LogsRequested()),
      child: const _LogsView(),
    );
  }
}

class _LogsView extends StatefulWidget {
  const _LogsView();

  @override
  State<_LogsView> createState() => _LogsViewState();
}

class _LogsViewState extends State<_LogsView> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _search() =>
      context.read<LogsBloc>().add(LogsSearchSubmitted(_searchController.text));

  Future<void> _openLogFolder() async {
    final bloc = context.read<LogsBloc>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final dir = await bloc.logDirectory();
      await launchUrl(Uri.file(dir.path));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('The log folder could not be opened.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: BlocBuilder<LogsBloc, LogsState>(
        builder: (context, state) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Heading(state: state),
              const SizedBox(height: 18),
              _Tabs(
                selected: state.tab,
                onSelect: (tab) =>
                    context.read<LogsBloc>().add(LogsTabSelected(tab)),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  if (!state.tab.readsFile) ...[
                    SizedBox(
                      width: 340,
                      child: TextField(
                        controller: _searchController,
                        decoration: const InputDecoration(
                          hintText: 'Search member, receipt, or action…',
                          prefixIcon: Icon(Icons.search, size: 18),
                          isDense: true,
                        ),
                        onSubmitted: (_) => _search(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton(
                        onPressed: _search, child: const Text('Search')),
                  ],
                  const Spacer(),
                  if (state.tab.readsFile)
                    OutlinedButton.icon(
                      onPressed: _openLogFolder,
                      icon: const Icon(Icons.folder_open_outlined, size: 16),
                      label: const Text('Open log folder'),
                    ),
                  const SizedBox(width: 10),
                  IconButton(
                    tooltip: 'Refresh',
                    onPressed: () =>
                        context.read<LogsBloc>().add(const LogsRequested()),
                    icon: const Icon(Icons.refresh, size: 18),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(child: _Content(state: state)),
            ],
          );
        },
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading({required this.state});

  final LogsState state;

  @override
  Widget build(BuildContext context) {
    final shown = state.tab.readsFile ? state.lines.length : state.events.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Logs',
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: context.palette.textPrimary)),
        const SizedBox(height: 4),
        Text(
          switch (state.status) {
            LogsStatus.loading => 'Reading…',
            LogsStatus.failed => state.error ?? 'The log could not be read.',
            LogsStatus.ready => state.tab.readsFile
                ? '$shown recent lines'
                : '$shown of ${state.total} '
                    '${state.total == 1 ? 'entry' : 'entries'} shown',
          },
          style: mutedStyleOf(context),
        ),
      ],
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({required this.selected, required this.onSelect});

  final LogsTab selected;
  final ValueChanged<LogsTab> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.palette.border)),
      ),
      child: Row(
        children: [
          for (final tab in LogsTab.values)
            InkWell(
              onTap: () => onSelect(tab),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      width: 2,
                      color: tab == selected
                          ? context.palette.accent
                          : Colors.transparent,
                    ),
                  ),
                ),
                child: Text(
                  tab.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        tab == selected ? FontWeight.w600 : FontWeight.w400,
                    color: tab == selected
                        ? context.palette.accentText
                        : context.palette.textSecondary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({required this.state});

  final LogsState state;

  @override
  Widget build(BuildContext context) {
    if (state.status == LogsStatus.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.tab.readsFile) {
      return state.lines.isEmpty
          ? const _Empty(message: 'Nothing has been written to the log yet.')
          : _TechnicalLog(lines: state.lines);
    }

    if (state.events.isEmpty) {
      return _Empty(
        message: switch (state.tab) {
          LogsTab.errors => 'Nothing has gone wrong.',
          LogsTab.whatsapp => 'No receipt sends have been recorded yet.',
          _ => 'Nothing has been recorded yet.',
        },
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: context.palette.surfaceRaised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.palette.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListView.separated(
        // One extra row when there is another page still to fetch.
        itemCount: state.events.length + (state.hasMore ? 1 : 0),
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, i) => i == state.events.length
            ? _LoadMore(loading: state.loadingMore)
            : _EventRow(event: state.events[i]),
      ),
    );
  }
}

class _LoadMore extends StatelessWidget {
  const _LoadMore({required this.loading});

  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Center(
        child: loading
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2))
            : TextButton(
                onPressed: () =>
                    context.read<LogsBloc>().add(const LogsMoreRequested()),
                child: const Text('Load older entries'),
              ),
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});

  final AuditEvent event;

  @override
  Widget build(BuildContext context) {
    final detail = event.detail;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 128, child: _Timestamp(at: event.createdAt)),
          SizedBox(width: 108, child: _CategoryChip(category: event.category)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(event.summary,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: context.palette.textPrimary)),
                const SizedBox(height: 2),
                Text(
                  [
                    auditActionLabel(event.action),
                    if (event.actorName != null) 'by ${event.actorName}',
                    if (event.receiptNumber != null) event.receiptNumber!,
                  ].join(' · '),
                  style: mutedStyleOf(context),
                ),
                if (detail != null && detail.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  for (final line in detail.split('\n'))
                    Text(line,
                        style: TextStyle(
                            fontSize: 12,
                            height: 1.45,
                            color: context.palette.textSecondary)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          _OutcomeBadge(outcome: event.outcome),
        ],
      ),
    );
  }
}

class _Timestamp extends StatelessWidget {
  const _Timestamp({required this.at});

  final DateTime at;

  @override
  Widget build(BuildContext context) {
    // Stored as an instant; read on the gym's own clock.
    final local = at.toLocal();
    final time = '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(time,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: context.palette.textPrimary)),
        Text(formatDayMonthYear(local), style: mutedStyleOf(context)),
      ],
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.category});

  final AuditCategory category;

  @override
  Widget build(BuildContext context) {
    final label = switch (category) {
      AuditCategory.member => 'Member',
      AuditCategory.payment => 'Payment',
      AuditCategory.receipt => 'Receipt',
      AuditCategory.whatsapp => 'WhatsApp',
      AuditCategory.billing => 'Billing',
      AuditCategory.update => 'Update',
    };

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: context.palette.surfaceBase,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: context.palette.border),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: context.palette.textSecondary)),
      ),
    );
  }
}

class _OutcomeBadge extends StatelessWidget {
  const _OutcomeBadge({required this.outcome});

  final AuditOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final (label, fg, bg) = switch (outcome) {
      AuditOutcome.success =>
        ('Done', context.palette.paid, context.palette.paidBg),
      AuditOutcome.refused =>
        ('Refused', context.palette.due, context.palette.dueBg),
      AuditOutcome.failed =>
        ('Failed', context.palette.expired, context.palette.expiredBg),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(label,
          style:
              TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
    );
  }
}

class _TechnicalLog extends StatelessWidget {
  const _TechnicalLog({required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.palette.surfaceRaised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.palette.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Scrollbar(
        child: ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: lines.length,
          itemBuilder: (context, i) => SelectableText(
            lines[i],
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              fontFamily: 'monospace',
              color: context.palette.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.palette.border),
      ),
      alignment: Alignment.center,
      child: Text(message, style: mutedStyleOf(context)),
    );
  }
}

/// The machine name of an action, in words.
///
/// The stored `action` is the stable key the log is queried by; this is what the
/// owner reads. Anything unrecognised falls back to the key rather than to
/// nothing, so a release that starts logging something new stays legible before
/// this switch catches up.
String auditActionLabel(String action) => switch (action) {
      AuditAction.memberDeleted => 'Member deleted',
      AuditAction.memberDeleteRefused => 'Deletion refused',
      AuditAction.memberDeactivated => 'Member deactivated',
      AuditAction.memberReactivated => 'Member reactivated',
      AuditAction.paymentEdited => 'Payment edited',
      AuditAction.paymentDeleted => 'Payment deleted',
      AuditAction.paymentEditRefused => 'Edit refused',
      AuditAction.billingMonthBlocked => 'Billing month rejected',
      AuditAction.billingMonthConfirmed => 'Warnings confirmed',
      AuditAction.receiptResaveFailed => 'Receipt not saved',
      AuditAction.receiptRenderFailed => 'Receipt not generated',
      AuditAction.receiptFilesOrphaned => 'Receipt files left behind',
      AuditAction.updateAvailable => 'Update available',
      AuditAction.updateInstalling => 'Installing update',
      AuditAction.updateVerifyFailed => 'Update failed verification',
      AuditAction.updateBackupFailed => 'Update stopped, backup failed',
      AuditAction.whatsAppResendRequested => 'Resend requested',
      AuditAction.whatsAppSent => 'Receipt sent',
      AuditAction.whatsAppFailed => 'Send failed',
      _ => action,
    };
