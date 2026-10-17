import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/branding_cubit.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_preset.dart';
import 'custom_theme_editor.dart';
import 'gym_branding_card.dart';
import 'gym_photos_card.dart';
import 'receipt_style_card.dart';
import 'theme_card.dart';

/// Where the owner changes how the app and its receipts look.
///
/// Three independent choices, as the brief asks: the application theme, the
/// gym logo, and the receipt template. They are deliberately not coupled —
/// picking Ocean Teal does not change the receipt layout, and uploading a logo
/// does not touch either.
///
/// The theme section previews: clicking a card repaints the whole app
/// immediately, and nothing is written until Apply. Cancel puts back whatever
/// is on disk. The logo and receipt sections save on the spot, because there is
/// nothing to preview in place for either.
class AppearanceScreen extends StatelessWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return BlocBuilder<BrandingCubit, BrandingState>(
      builder: (context, state) {
        return Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(32, 28, 32, 120),
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Appearance',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.5,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Your gym colours, logo, photos and receipt style.',
                      style: TextStyle(fontSize: 13, color: palette.textMuted),
                    ),
                    const SizedBox(height: 24),
                    _Section(
                      title: 'Theme presets',
                      description:
                          'Pick a brand to see it applied straight away. '
                          'Nothing is saved until you choose Apply.',
                      child: _PresetGrid(state: state),
                    ),
                    const SizedBox(height: 20),
                    _Section(
                      title: 'Custom theme',
                      description:
                          'Mix your own. Any colour you leave blank keeps the '
                          'default.',
                      child: CustomThemeEditor(state: state),
                    ),
                    const SizedBox(height: 20),
                    _Section(
                      title: 'Gym branding',
                      description:
                          'The logo appears above RICH MAN FITNESS in the '
                          'sidebar and on every new receipt.',
                      child: GymBrandingCard(state: state),
                    ),
                    const SizedBox(height: 20),
                    _Section(
                      title: 'Gym photos',
                      description:
                          'Your own photography on the sign-in screen and the '
                          'dashboard. Leave one empty to keep the drawn brand '
                          'artwork.',
                      child: GymPhotosCard(state: state),
                    ),
                    const SizedBox(height: 20),
                    _Section(
                      title: 'Receipt style',
                      description:
                          'Applies to receipts from now on. Receipts already '
                          'sent are never redrawn.',
                      child: ReceiptStyleCard(state: state),
                    ),
                  ],
                ),
              ),
            ),
            if (state.isPreviewing) const _PreviewBar(),
          ],
        );
      },
    );
  }
}

class _PresetGrid extends StatelessWidget {
  const _PresetGrid({required this.state});

  final BrandingState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<BrandingCubit>();

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final preset in ThemePreset.all)
          ThemeCard(
            preset: preset,
            selected: state.draft.presetId == preset.id,
            active: state.saved.presetId == preset.id,
            onTap: () => cubit.preview(
              state.draft.copyWith(presetId: preset.id),
            ),
          ),
      ],
    );
  }
}

/// The floating Apply / Cancel bar, shown only while a preview is live.
///
/// Modelled on the unsaved-changes bar in Settings so the two read the same
/// way: the owner should not have to learn a second idiom for "you have
/// changed something and not kept it yet".
class _PreviewBar extends StatelessWidget {
  const _PreviewBar();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final cubit = context.read<BrandingCubit>();
    final messenger = ScaffoldMessenger.of(context);

    return Positioned(
      left: 32,
      right: 32,
      bottom: 20,
      child: Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: double.infinity,
          child: Container(
            decoration: BoxDecoration(
              color: palette.surfaceRaised,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: palette.borderStrong),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x59000000),
                  blurRadius: 24,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(18, 10, 12, 10),
            child: Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: palette.due,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Previewing — not saved yet',
                    style:
                        TextStyle(fontSize: 13, color: palette.textPrimary),
                  ),
                ),
                TextButton(
                  onPressed: cubit.cancelPreview,
                  style: TextButton.styleFrom(
                      foregroundColor: palette.textSecondary),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () async {
                    final saved = await cubit.apply();
                    messenger.showSnackBar(SnackBar(
                      content: Text(saved
                          ? 'Appearance saved'
                          : 'Could not save the appearance. See the Logs '
                              'screen.'),
                    ));
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: palette.accentText,
                    side: BorderSide(color: palette.accent),
                    backgroundColor: palette.accent.withValues(alpha: 0.14),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                  ),
                  child: const Text('Apply'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A titled block, matching the card pattern Settings already uses.
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.description,
    required this.child,
  });

  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: palette.surfaceOverlay,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            description,
            style: TextStyle(fontSize: 12, color: palette.textMuted),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}
