import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/database.dart';
import '../../data/settings_repository.dart';
import '../../services/diagnostics/send_to_developer.dart';
import '../send_to_developer_dialog.dart';

/// Where the owner reaches for help: a sealed copy of the data and logs, sent
/// straight to the developer instead of waiting for a visit to copy a backup
/// off this machine.
class SendToDeveloperCard extends StatelessWidget {
  const SendToDeveloperCard({super.key, required this.card});

  /// The shared card chrome from the settings screen.
  final Widget Function({
    required String title,
    String? subtitle,
    required Widget child,
  }) card;

  Future<void> _open(BuildContext context) {
    final settings = context.read<SettingsRepository>();
    final sender = SendToDeveloper.installed(
      snapshot: vacuumSnapshot(context.read<AppDatabase>()),
      gymName: () async => (await settings.get()).gymName,
    );
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SendToDeveloperDialog(
        configured: sender.isConfigured,
        send: (note) => sender.send(note: note),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return card(
      title: 'Get help',
      subtitle: 'Something not right? Send the developer a locked copy of '
          'the data and the app\'s logs, so it can be looked into without a '
          'visit.',
      child: Row(
        children: [
          FilledButton.icon(
            onPressed: () => _open(context),
            icon: const Icon(Icons.support_agent_outlined, size: 16),
            label: const Text('Send to developer…'),
          ),
        ],
      ),
    );
  }
}
