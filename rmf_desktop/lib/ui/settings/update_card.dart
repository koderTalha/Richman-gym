import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:url_launcher/url_launcher.dart';

import '../../bloc/update_bloc.dart';
import '../../domain/dates.dart';
import '../../services/update/update_service.dart';
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
                      if (state.canInstall)
                        FilledButton(
                          onPressed: state.busy
                              ? null
                              : () =>
                                  bloc.add(const UpdateInstallRequested()),
                          child: Text('Install ${update.version}'),
                        )
                      else
                        // The installer is a Windows .exe. Elsewhere the
                        // release is still worth knowing about, so the card
                        // offers the download rather than a button that could
                        // only fail.
                        OutlinedButton(
                          onPressed: () => launchUrl(update.installerUrl),
                          child: Text('Download ${update.version}'),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(state.error!,
                          style: TextStyle(
                              fontSize: 13, color: context.palette.expired)),
                      if (_hintFor(state.failureKind) != null) ...[
                        const SizedBox(height: 6),
                        Text(_hintFor(state.failureKind)!,
                            style: TextStyle(
                                fontSize: 12.5,
                                height: 1.4,
                                color: context.palette.textSecondary)),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              _Diagnostics(state: state, endpoint: bloc.releasesEndpoint),
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
            : state.canInstall
                ? 'Version ${state.available!.version} is available.'
                : 'Version ${state.available!.version} is available. This app '
                    'can only install updates on Windows.',
        UpdateStatus.installing => 'Installing…',
        UpdateStatus.launched =>
          'The installer is running. The app will reopen shortly.',
        UpdateStatus.failed => 'The last check did not complete.',
        UpdateStatus.idle => 'Updates are checked once a day when the app '
            'opens. Today: ${formatDayMonthYear(DateTime.now())}.',
      };

  /// What the owner can actually do about a failure.
  ///
  /// The message above says what happened; this says whose problem it is.
  /// Written for somebody standing at a gym counter, not for a developer
  /// reading a stack trace — three of these are nothing to do with them and
  /// saying so plainly stops a working till being treated as a broken one.
  static String? _hintFor(UpdateFailureKind? kind) => switch (kind) {
        UpdateFailureKind.offline =>
          'The app could not reach github.com. Check this computer\'s internet '
              'connection, or any firewall that might be blocking it. Nothing '
              'else about the app is affected.',
        UpdateFailureKind.rateLimited =>
          'This is GitHub limiting how often it answers, not a fault here. It '
              'clears by itself — try again later.',
        UpdateFailureKind.noReleases =>
          'No release has been published for this app yet, so there is nothing '
              'to update to.',
        UpdateFailureKind.unusableRelease =>
          'A release exists but cannot be offered. The usual cause is a '
              'release published without its .sha256 checksum file beside the '
              'installer — the app will not run an installer it cannot verify. '
              'Whoever publishes the release can fix this by attaching it.',
        UpdateFailureKind.unknownCurrentVersion =>
          'The app could not read its own version number, so it cannot tell '
              'whether a release is newer. Reinstalling from the latest '
              'installer usually fixes this.',
        UpdateFailureKind.unsupported =>
          'Updates can only be installed on Windows.',
        UpdateFailureKind.serverError ||
        UpdateFailureKind.malformedResponse =>
          'GitHub answered, but not with something the app could use. This is '
              'usually temporary.',
        null => null,
      };
}

/// The facts somebody needs to work out why updating is not behaving.
///
/// Deliberately always on screen rather than behind a developer switch: when
/// the gym reports "it does not connect", this is the panel they can read down
/// the phone, and every line of it is something they would otherwise be asked
/// to guess at.
class _Diagnostics extends StatelessWidget {
  const _Diagnostics({required this.state, required this.endpoint});

  final UpdateState state;
  final String endpoint;

  @override
  Widget build(BuildContext context) {
    final checked = state.lastCheckedAt;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.palette.surfaceBase,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('UPDATE DIAGNOSTICS', style: labelStyleOf(context)),
          const SizedBox(height: 8),
          _Line(
            label: 'Last successful check',
            value: checked == null
                ? 'Never — GitHub has not answered on this computer yet'
                : '${formatDayMonthYear(checked)} at '
                    '${checked.hour.toString().padLeft(2, '0')}:'
                    '${checked.minute.toString().padLeft(2, '0')}',
          ),
          _Line(
            label: 'Can install updates',
            value: state.canInstall ? 'Yes' : 'No — Windows only',
          ),
          if (state.available != null)
            _Line(
              label: 'Latest release found',
              value: state.available!.version.toString(),
            ),
          if (state.failureKind != null)
            _Line(label: 'Last problem', value: _kindLabel(state.failureKind!)),
          _Line(label: 'Release feed', value: endpoint),
        ],
      ),
    );
  }

  static String _kindLabel(UpdateFailureKind kind) => switch (kind) {
        UpdateFailureKind.unsupported => 'Not supported on this platform',
        UpdateFailureKind.unknownCurrentVersion => 'Installed version unreadable',
        UpdateFailureKind.offline => 'Could not reach GitHub',
        UpdateFailureKind.rateLimited => 'Rate limited by GitHub',
        UpdateFailureKind.noReleases => 'No published release',
        UpdateFailureKind.serverError => 'GitHub returned an error',
        UpdateFailureKind.malformedResponse => 'Unreadable answer from GitHub',
        UpdateFailureKind.unusableRelease => 'Release cannot be used',
      };
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 170,
            child: Text(label,
                style: TextStyle(
                    fontSize: 12.5, color: context.palette.textMuted)),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                  fontSize: 12.5, color: context.palette.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
