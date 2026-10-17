import 'dart:io';

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Which of the two hero slots a photograph is filling.
///
/// The slots differ in how the picture is blended into the panel behind it,
/// which is the only reason this is not a single widget with a path.
enum BrandPhotoSlot {
  /// The sign-in art panel: full-bleed behind the wordmark.
  login,

  /// The dashboard hero band: the right-hand side, fading into the gradient.
  dashboard,
}

/// The gym's own photograph behind a hero panel, or nothing at all.
///
/// The handoff is explicit that an empty photo slot renders *nothing* — no
/// dashed "Drop an image" frame, no grey box. The prototype's placeholder
/// chrome exists so a designer can see where a picture goes; shipping it would
/// put an editing affordance on the owner's dashboard and on a sign-in screen
/// that is shown before anybody has authenticated. A gym that has not supplied
/// a photograph sees the drawn brand artwork instead, which is a finished look
/// rather than an unfilled slot.
///
/// The picture is darkened towards the panel colour rather than drawn at full
/// strength: every one of these slots has text over it, and a photograph
/// straight off a phone is bright enough to take the greeting's contrast below
/// the threshold the rest of the app is held to.
class BrandPhoto extends StatelessWidget {
  const BrandPhoto({super.key, required this.path, required this.slot});

  /// Absolute path to the photograph, or null when the gym has not set one.
  final String? path;

  final BrandPhotoSlot slot;

  @override
  Widget build(BuildContext context) {
    final photoPath = path;
    if (photoPath == null) return const SizedBox.shrink();

    final palette = context.palette;

    final image = Image.file(
      File(photoPath),
      fit: BoxFit.cover,
      // A file the owner deleted from outside the app falls back to the drawn
      // artwork rather than Flutter's grey broken-image box.
      errorBuilder: (context, error, stack) => const SizedBox.shrink(),
      // The frame is painted the moment the bytes are ready rather than fading
      // in: this sits behind the sign-in form and the dashboard greeting, and a
      // fade would read as the screen still loading.
      gaplessPlayback: true,
    );

    return switch (slot) {
      // Full-bleed, dimmed, with a wash of the panel colour from the left so
      // the wordmark in the bottom corner stays readable over whatever was
      // photographed there.
      BrandPhotoSlot.login => Stack(
          fit: StackFit.expand,
          children: [
            Opacity(opacity: 0.55, child: image),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomLeft,
                  end: Alignment.topRight,
                  colors: [
                    palette.surfaceBase.withValues(alpha: 0.92),
                    palette.surfaceBase.withValues(alpha: 0.25),
                  ],
                ),
              ),
            ),
          ],
        ),
      // The handoff's dashboard band: the photograph occupies the right 58% and
      // the base colour is drawn over its left edge, so the picture resolves
      // out of the gradient instead of starting at a hard vertical seam.
      BrandPhotoSlot.dashboard => Stack(
          fit: StackFit.expand,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: FractionallySizedBox(
                widthFactor: 0.58,
                child: Opacity(opacity: 0.55, child: image),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  // Opaque for the first 38% — where the greeting sits — then
                  // clearing, which is the overlay the handoff specifies.
                  stops: const [0.0, 0.38, 1.0],
                  colors: [
                    palette.surfaceBase,
                    palette.surfaceBase,
                    palette.surfaceBase.withValues(alpha: 0.15),
                  ],
                ),
              ),
            ),
          ],
        ),
    };
  }
}
