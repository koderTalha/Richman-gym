import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/update_bloc.dart';
import '../../services/update/update_service.dart';
import '../../theme/app_theme.dart';

/// The connection indicator in the top bar. Named so a test can find it
/// without matching on an icon that may change.
const appShellConnectionKey = Key('app-shell-connection');

/// The dot over the icon when a release is waiting.
const connectionUpdateDotKey = Key('app-shell-connection-dot');

/// Whether this computer is reaching GitHub, and whether a release is waiting.
///
/// Both questions used to have the same answer on screen: nothing. "No update"
/// and "this thing has never once connected" were indistinguishable, which is
/// what left the gym unsure whether the updater worked at all.
///
/// It reports the **last check** rather than pinging anything of its own —
/// nothing here opens a socket, and a till does not need a heartbeat to the
/// internet. Tapping it runs a fresh check, which is what makes it an answer
/// instead of a decoration.
///
/// The distinction worth the extra branch: a rate limit or an error *from*
/// GitHub means the connection is fine and GitHub is not. Drawing that as
/// "offline" would send the owner to reset a router that was never the
/// problem, so only a genuinely unreachable GitHub shows as disconnected.
class ConnectionStatusIcon extends StatelessWidget {
  const ConnectionStatusIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<UpdateBloc, UpdateState>(
      builder: (context, state) {
        final look = _lookFor(state, context);

        return Tooltip(
          message: look.message,
          child: IconButton(
            key: appShellConnectionKey,
            onPressed: state.busy
                ? null
                : () => context
                    .read<UpdateBloc>()
                    .add(const UpdateCheckRequested(force: true)),
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(look.icon, size: 20, color: look.color),
                if (look.showDot)
                  Positioned(
                    right: -1,
                    top: -1,
                    child: Container(
                      key: connectionUpdateDotKey,
                      height: 8,
                      width: 8,
                      decoration: BoxDecoration(
                        color: context.palette.accent,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: context.palette.surfaceRaised,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  _Look _lookFor(UpdateState state, BuildContext context) {
    final palette = context.palette;
    final checked = state.lastCheckedAt;
    final when = checked == null
        ? ''
        : ' Checked at ${checked.hour.toString().padLeft(2, '0')}:'
            '${checked.minute.toString().padLeft(2, '0')}.';

    if (state.status == UpdateStatus.checking) {
      return _Look(
        icon: Icons.wifi_find,
        color: palette.textMuted,
        message: 'Checking GitHub for a new version…',
      );
    }

    // The only failure that is actually about the connection.
    if (state.failureKind == UpdateFailureKind.offline) {
      return _Look(
        icon: Icons.wifi_off,
        color: palette.expired,
        message: 'No internet connection — this computer could not reach '
            'GitHub, so it cannot tell whether a new version has been '
            'published.\n\nEverything else in the app works normally.\n\n'
            'Click to try again.',
      );
    }

    switch (state.status) {
      case UpdateStatus.available:
        final update = state.available!;
        return _Look(
          icon: Icons.wifi,
          color: palette.accentText,
          showDot: true,
          message: 'Connected. Version ${update.version} has been published — '
              'this copy is ${update.current}.$when\n\n'
              '${state.canInstall ? 'Open Settings to install it.' : 'This app '
                  'can only install updates on Windows.'}',
        );

      case UpdateStatus.upToDate:
        return _Look(
          icon: Icons.wifi,
          color: palette.paid,
          message: 'Connected to GitHub. No new version has been published — '
              'this is the latest version.$when\n\nClick to check again.',
        );

      case UpdateStatus.installing || UpdateStatus.launched:
        return _Look(
          icon: Icons.wifi,
          color: palette.accentText,
          message: 'Connected. Installing the update…',
        );

      case UpdateStatus.failed:
        // Reached only for failures that are not about the connection: GitHub
        // answered, or refused to, and that is a different problem.
        return _Look(
          icon: Icons.wifi,
          color: palette.due,
          message: 'Connected to the internet, but the update check did not '
              'complete.\n\n${state.error ?? ''}$when\n\nClick to try again.',
        );

      case UpdateStatus.idle || UpdateStatus.checking:
        return _Look(
          icon: Icons.wifi_find,
          color: palette.textMuted,
          message: checked == null
              ? 'Not checked yet — this computer has not asked GitHub whether '
                  'a new version has been published.\n\nClick to check now.'
              : 'Connected.$when\n\nClick to check again.',
        );
    }
  }
}

class _Look {
  const _Look({
    required this.icon,
    required this.color,
    required this.message,
    this.showDot = false,
  });

  final IconData icon;
  final Color color;
  final String message;
  final bool showDot;
}
