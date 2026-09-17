import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/update/connection_diagnostics.dart';
import '../../theme/app_theme.dart';

/// The layered answer to "why won't it connect", for whoever the owner is on
/// the phone with when the everyday update check is not enough.
///
/// One sentence in `UpdateCard`'s failure banner already says what went
/// wrong; this is for the next question, which is always "so what do I do
/// about it" — a checklist that shows exactly where the chain from this
/// computer to GitHub breaks, and a button to copy the technical detail
/// behind it rather than someone typing an error message off the screen.
class ConnectionTestDialog extends StatefulWidget {
  const ConnectionTestDialog({super.key, required this.run});

  /// Runs the diagnostic. Injected rather than importing `UpdateService`
  /// directly, so this dialog does not need to know how one is built.
  final Future<ConnectionTestReport> Function() run;

  @override
  State<ConnectionTestDialog> createState() => _ConnectionTestDialogState();
}

class _ConnectionTestDialogState extends State<ConnectionTestDialog> {
  Future<ConnectionTestReport>? _future;

  @override
  void initState() {
    super.initState();
    _future = widget.run();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return AlertDialog(
      backgroundColor: palette.surfaceRaised,
      title: const Text('Connection Test'),
      content: SizedBox(
        width: 420,
        child: FutureBuilder<ConnectionTestReport>(
          future: _future,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final report = snapshot.data!;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final layer in report.layers) _LayerLine(layer: layer),
                const SizedBox(height: 14),
                Text(
                  report.summary,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: report.allPassed ? palette.paid : palette.due,
                  ),
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            final report = await _future;
            if (report == null) return;
            await Clipboard.setData(
                ClipboardData(text: report.toClipboardText()));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Details copied.')),
              );
            }
          },
          child: const Text('Copy Details'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _LayerLine extends StatelessWidget {
  const _LayerLine({required this.layer});
  final LayerResult layer;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    final (icon, color) = !layer.applicable
        ? (Icons.remove, palette.textMuted)
        : layer.passed
            ? (Icons.check, palette.paid)
            : (Icons.close, palette.expired);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              layer.label,
              style: TextStyle(fontSize: 13.5, color: palette.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
