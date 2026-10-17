import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/theme_preset.dart';

/// One selectable brand, drawn in its own colours.
///
/// The swatch is a miniature of the app — sidebar, surface and a filled button
/// — rather than a circle of the brand colour, because what the owner is
/// choosing is how the whole screen will look, not a dot. The button inside the
/// preview uses the preset's own `onAccent`, so a brand that needs black text
/// shows black text here too.
class ThemeCard extends StatelessWidget {
  const ThemeCard({
    super.key,
    required this.preset,
    required this.selected,
    required this.active,
    required this.onTap,
  });

  final ThemePreset preset;

  /// Highlighted because the owner has clicked it in this session.
  final bool selected;

  /// Marked as the theme actually saved on disk.
  final bool active;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Semantics(
      button: true,
      selected: selected,
      label: '${preset.name} theme',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        splashFactory: NoSplash.splashFactory,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 196,
          decoration: BoxDecoration(
            color: palette.surfaceRaised,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? palette.accent : palette.border,
              width: selected ? 2 : 1,
            ),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _Swatch(preset: preset),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      preset.name,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: palette.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (active)
                    Icon(Icons.check_circle,
                        size: 16, color: palette.accentText),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                active ? 'Currently applied' : preset.description,
                style: TextStyle(fontSize: 11, color: palette.textMuted),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A miniature of the app in [preset]'s colours.
class _Swatch extends StatelessWidget {
  const _Swatch({required this.preset});

  final ThemePreset preset;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: 74,
        child: Row(
          children: [
            // Sidebar.
            Container(
              width: 26,
              color: preset.sidebarDark,
              padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(height: 4, color: preset.primary),
                  const SizedBox(height: 5),
                  Container(height: 3, color: Colors.white24),
                  const SizedBox(height: 4),
                  Container(height: 3, color: Colors.white12),
                ],
              ),
            ),
            // Content.
            Expanded(
              child: Container(
                color: preset.backgroundDark,
                padding: const EdgeInsets.all(7),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 18,
                      decoration: BoxDecoration(
                        color: preset.surfaceDark,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const Spacer(),
                    // The filled button, in the preset's own label colour —
                    // this is the pair that fails WCAG on five of the seven
                    // brands if it is left as white.
                    Container(
                      height: 16,
                      width: 56,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: preset.primary,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Container(
                        height: 3,
                        width: 26,
                        color: preset.onAccent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
