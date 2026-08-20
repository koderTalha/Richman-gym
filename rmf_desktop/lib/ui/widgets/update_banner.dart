import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/update_bloc.dart';
import '../../data/database.dart';
import '../../theme/app_theme.dart';

/// A slim strip above the screen content when a new version is waiting.
///
/// Deliberately not a dialog: the owner may be halfway through taking a
/// payment, and nothing about a release being available is urgent enough to
/// stop that.
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key});

  /// Closes the app once the installer is running.
  ///
  /// The database is closed first: the installer replaces the program while
  /// this process is going away, and leaving SQLite to be terminated
  /// mid-checkpoint is not a risk worth taking with the gym's only copy.
  static Future<void> _standAside(BuildContext context) async {
    final db = context.read<AppDatabase>();
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    try {
      await db.close();
    } finally {
      exit(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<UpdateBloc, UpdateState>(
      listenWhen: (a, b) =>
          a.status != b.status && b.status == UpdateStatus.launched,
      listener: (context, state) => _standAside(context),
      builder: (context, state) {
        final update = state.available;

        if (state.status == UpdateStatus.installing ||
            state.status == UpdateStatus.launched) {
          return _Strip(
            tone: _Tone.busy,
            child: Row(
              children: [
                const SizedBox(
                  height: 14,
                  width: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    switch (state.status) {
                      UpdateStatus.launched =>
                        'Installing — the app will reopen on the new version.',
                      _ => state.progress == null
                          ? 'Backing up before updating…'
                          : 'Downloading version '
                              '${update?.version} — '
                              '${(state.progress! * 100).round()}%',
                    },
                    style: TextStyle(
                        fontSize: 13, color: context.palette.textPrimary),
                  ),
                ),
                if (state.progress != null)
                  SizedBox(
                    width: 160,
                    child: LinearProgressIndicator(
                      value: state.progress,
                      minHeight: 4,
                    ),
                  ),
              ],
            ),
          );
        }

        if (!state.showBanner || update == null) {
          return const SizedBox.shrink();
        }

        return _Strip(
          tone: _Tone.info,
          child: Row(
            children: [
              Icon(Icons.system_update_alt,
                  size: 16, color: context.palette.accentText),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Version ${update.version} is available — '
                  'this copy is ${update.current}.',
                  style: TextStyle(
                      fontSize: 13, color: context.palette.textPrimary),
                ),
              ),
              TextButton(
                onPressed: () =>
                    context.read<UpdateBloc>().add(const UpdateDismissed()),
                child: const Text('Later'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => context
                    .read<UpdateBloc>()
                    .add(const UpdateInstallRequested()),
                child: const Text('Install now'),
              ),
            ],
          ),
        );
      },
    );
  }
}

enum _Tone { info, busy }

class _Strip extends StatelessWidget {
  const _Strip({required this.tone, required this.child});

  final _Tone tone;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: switch (tone) {
          _Tone.info => context.palette.accent.withValues(alpha: .10),
          _Tone.busy => context.palette.surfaceRaised,
        },
        border: Border(bottom: BorderSide(color: context.palette.border)),
      ),
      child: child,
    );
  }
}
