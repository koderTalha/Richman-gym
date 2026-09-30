import 'package:flutter/material.dart';

import '../services/diagnostics/send_to_developer.dart';
import '../theme/app_theme.dart';

/// Asks what went wrong, then sends the developer a sealed copy of the data
/// and logs. Shared by Settings and the screen shown when the app cannot open
/// its data — the second being exactly when a copy is most needed and least
/// easy to fetch by hand.
class SendToDeveloperDialog extends StatefulWidget {
  const SendToDeveloperDialog({
    super.key,
    required this.send,
    required this.configured,
  });

  /// Injected rather than building a [SendToDeveloper] here, so the dialog
  /// does not need to know which snapshot the caller can take.
  final Future<DiagnosticsResult> Function(String note) send;

  /// False in a build made without the upload address; see
  /// [SendToDeveloper.configuredEndpoint].
  final bool configured;

  @override
  State<SendToDeveloperDialog> createState() => _SendToDeveloperDialogState();
}

class _SendToDeveloperDialogState extends State<SendToDeveloperDialog> {
  final _note = TextEditingController();
  bool _sending = false;
  DiagnosticsResult? _result;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _result = null;
    });
    final result = await widget.send(_note.text.trim());
    if (!mounted) return;
    setState(() {
      _sending = false;
      _result = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final result = _result;
    final sent = result is DiagnosticsSent;

    return AlertDialog(
      backgroundColor: palette.surfaceRaised,
      title: const Text('Send to developer'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sends the developer a copy of this gym\'s data — members, '
              'payments and settings — and the app\'s recent logs, so a '
              'problem can be looked into without a visit. It is locked '
              'before it leaves this computer, and only the developer can '
              'open it.',
              style: mutedStyleOf(context),
            ),
            const SizedBox(height: 16),
            if (!widget.configured)
              _Banner(
                text: 'This copy of the app cannot send: it was built without '
                    'the developer\'s upload address. Use "Back up now" and '
                    'send the folder instead.',
                color: palette.expired,
                background: palette.expiredBg,
              )
            else if (sent)
              _Banner(
                text: 'Sent. The reference is ${result.reference} — give the '
                    'developer this if they ask which one.',
                color: palette.paid,
                background: palette.paidBg,
              )
            else ...[
              Text('WHAT WENT WRONG?', style: labelStyleOf(context)),
              const SizedBox(height: 6),
              TextField(
                controller: _note,
                enabled: !_sending,
                autofocus: true,
                minLines: 2,
                maxLines: 5,
                maxLength: 1000,
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'e.g. A member\'s payment still shows as due',
                ),
              ),
              if (result is DiagnosticsFailed) ...[
                const SizedBox(height: 8),
                _Banner(
                  text: result.message,
                  color: palette.expired,
                  background: palette.expiredBg,
                ),
              ],
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(),
          child: Text(sent || !widget.configured ? 'Close' : 'Cancel'),
        ),
        if (widget.configured && !sent)
          FilledButton.icon(
            onPressed: _sending ? null : _send,
            icon: _sending
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_outlined, size: 16),
            label: Text(_sending
                ? 'Sending…'
                : result is DiagnosticsFailed
                    ? 'Try again'
                    : 'Send'),
          ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.text,
    required this.color,
    required this.background,
  });

  final String text;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 12.5)),
    );
  }
}
