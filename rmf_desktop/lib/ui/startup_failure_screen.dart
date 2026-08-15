import 'package:flutter/material.dart';

import '../services/backup_service.dart';
import '../theme/app_theme.dart';

/// Shown instead of the app when startup fails.
///
/// The alternative is what used to happen: `runApp` never runs, the window
/// opens blank and stays blank, and the only record of why is a log file the
/// owner does not know exists. A gym counter machine has nobody to read a
/// stack trace, so this says what happened in plain words and names the one
/// thing that usually fixes it — the copy of the database kept aside when a
/// restore replaced it.
class StartupFailureApp extends StatelessWidget {
  const StartupFailureApp({super.key, required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rich Man Fitness',
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      home: _StartupFailureScreen(error: error),
    );
  }
}

class _StartupFailureScreen extends StatelessWidget {
  const _StartupFailureScreen({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline,
                    size: 36, color: context.palette.expired),
                const SizedBox(height: 16),
                Text(
                  'Rich Man Fitness could not open your data',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: context.palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Nothing has been deleted. The database file could not be '
                  'read, which most often means a restore replaced it with a '
                  'file this version cannot open.',
                  style: TextStyle(
                      fontSize: 14, color: context.palette.textSecondary),
                ),
                const SizedBox(height: 20),
                Text('WHAT TO DO', style: labelStyleOf(context)),
                const SizedBox(height: 8),
                _Step(
                  number: 1,
                  text: 'Close the app and reopen it. A restore is applied '
                      'once, so a second attempt often gets further.',
                ),
                _Step(
                  number: 2,
                  text: 'If it still will not open, the database from before '
                      'the restore is beside the current one, named '
                      '"richmanfitness.sqlite.replaced-…". Rename it back to '
                      '"richmanfitness.sqlite".',
                ),
                _Step(
                  number: 3,
                  text: 'Send the log file in the "logs" folder to whoever '
                      'supports this app. It records exactly what failed.',
                ),
                const SizedBox(height: 20),
                FutureBuilder<String>(
                  future: _databaseLocation(),
                  builder: (context, snapshot) => snapshot.data == null
                      ? const SizedBox.shrink()
                      : _Mono(label: 'DATABASE', value: snapshot.data!),
                ),
                const SizedBox(height: 12),
                _Mono(label: 'ERROR', value: '$error'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Future<String> _databaseLocation() async {
    try {
      return (await BackupService.liveDatabaseFile()).path;
    } catch (_) {
      return '';
    }
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 20,
            child: Text('$number.',
                style: TextStyle(
                    fontSize: 13, color: context.palette.textMuted)),
          ),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    fontSize: 13, color: context.palette.textSecondary)),
          ),
        ],
      ),
    );
  }
}

class _Mono extends StatelessWidget {
  const _Mono({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: labelStyleOf(context)),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: context.palette.surfaceRaised,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: context.palette.border),
          ),
          child: SelectableText(
            value,
            style: TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              color: context.palette.textMuted,
            ),
          ),
        ),
      ],
    );
  }
}
