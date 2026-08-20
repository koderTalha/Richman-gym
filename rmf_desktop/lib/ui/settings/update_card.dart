import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/update_bloc.dart';
import '../../domain/dates.dart';
import '../../theme/app_theme.dart';

/// Where the owner can see which version they are on and reach for an update
/// deliberately, rather than waiting for the banner to appear.
class UpdateCard extends StatelessWidget {
  const UpdateCard({super.key, required this.card});

  /// The shared card chrome from the settings screen.
  final Widget Function({
    required String title,
    String? subtitle,
    required Widget child,
  }) card;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<UpdateBloc, UpdateState>(
      builder: (context, state) {
        final bloc = context.read<UpdateBloc>();
        final update = state.available;

        return card(
          title: 'Updates',
          subtitle: 'Installing an update takes a backup first, checks the '
              'download against its published checksum, and reopens the app on '
              'the new version.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('INSTALLED VERSION',
                            style: labelStyleOf(context)),
                        const SizedBox(height: 4),
                        Text(bloc.currentVersion.toString(),
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: context.palette.textPrimary)),
                        const SizedBox(height: 6),
                        Text(_statusLine(state, context),
                            style: mutedStyleOf(context)),
                      ],
                    ),
                  ),
                  if (state.status == UpdateStatus.installing ||
                      state.status == UpdateStatus.launched)
                    const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else ...[
                    OutlinedButton(
                      onPressed: state.busy
                          ? null
                          : () => bloc.add(
                              const UpdateCheckRequested(force: true)),
                      child: Text(state.status == UpdateStatus.checking
                          ? 'Checking…'
                          : 'Check for updates'),
                    ),
                    if (update != null) ...[
                      const SizedBox(width: 10),
                      FilledButton(
                        onPressed: state.busy
                            ? null
                            : () =>
                                bloc.add(const UpdateInstallRequested()),
                        child: Text('Install ${update.version}'),
                      ),
                    ],
                  ],
                ],
              ),
              if (state.progress != null &&
                  state.status == UpdateStatus.installing) ...[
                const SizedBox(height: 14),
                LinearProgressIndicator(value: state.progress, minHeight: 4),
              ],
              if (state.status == UpdateStatus.failed &&
                  state.error != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.palette.expiredBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(state.error!,
                      style: TextStyle(
                          fontSize: 13, color: context.palette.expired)),
                ),
              ],
              if (update?.notes != null && update!.notes!.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text("WHAT'S NEW IN ${update.version}",
                    style: labelStyleOf(context)),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.palette.surfaceBase,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: context.palette.border),
                  ),
                  child: Text(update.notes!,
                      style: TextStyle(
                          fontSize: 12.5,
                          height: 1.5,
                          color: context.palette.textSecondary)),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  String _statusLine(UpdateState state, BuildContext context) =>
      switch (state.status) {
        UpdateStatus.checking => 'Checking for a newer version…',
        UpdateStatus.upToDate => 'This is the latest version.',
        UpdateStatus.available => state.dismissed
            ? 'Version ${state.available!.version} is available — you chose to '
                'install it later.'
            : 'Version ${state.available!.version} is available.',
        UpdateStatus.installing => 'Installing…',
        UpdateStatus.launched =>
          'The installer is running. The app will reopen shortly.',
        UpdateStatus.failed => 'The last check did not complete.',
        UpdateStatus.idle => 'Updates are checked once a day when the app '
            'opens. Today: ${formatDayMonthYear(DateTime.now())}.',
      };
}
