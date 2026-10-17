import 'package:flutter/material.dart';

/// A [MaterialApp.builder] that switches reduced motion on for everything
/// below it.
///
/// The dashboard's decorative rings turn once a minute, forever. That is
/// deliberate in the app and fatal in a test: `pumpAndSettle` waits for the
/// frame loop to fall quiet, and an endless animation never lets it. Passing
/// this as a screen's `builder` is how a widget test says "I am not here to
/// watch the scenery" — the rings stand still and everything else behaves
/// normally.
///
/// It has to be the app's `builder` rather than a wrapper around the
/// [MaterialApp]: the app builds its own [MediaQuery] from the view, so
/// anything wrapped around the outside is overridden before a screen ever sees
/// it. `copyWith` so the rest of the media data — size, text scale, padding —
/// is whatever the test harness set.
///
/// `flutter_test` does *not* do this for you: its fake accessibility features
/// default `disableAnimations` to false, so a screen under test animates
/// exactly as it would on the owner's machine unless it is told otherwise.
Widget stillMotion(BuildContext context, Widget? child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: true),
      child: child ?? const SizedBox.shrink(),
    );
