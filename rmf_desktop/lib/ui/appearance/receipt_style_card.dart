import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/branding_cubit.dart';
import '../../theme/app_theme.dart';
import '../../theme/branding_config.dart';
import '../../theme/theme_preset.dart';

/// Picks which layout new receipts are drawn with.
///
/// Each option shows a miniature of the real thing, drawn in the gym's current
/// brand colours — the same colours the PDF will use, so the preview is honest
/// about what the member will receive.
class ReceiptStyleCard extends StatelessWidget {
  const ReceiptStyleCard({super.key, required this.state});

  final BrandingState state;

  static const _descriptions = {
    ReceiptTemplate.classic: 'Centred header, the layout your existing '
        'receipts use.',
    ReceiptTemplate.modern: 'Brand-coloured header band with the logo.',
    ReceiptTemplate.minimal: 'Quiet type and hairline rules.',
  };

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final cubit = context.read<BrandingCubit>();
    final messenger = ScaffoldMessenger.of(context);
    final preset = state.draft.effectivePreset;

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final template in ReceiptTemplate.values)
          _TemplateOption(
            template: template,
            preset: preset,
            description: _descriptions[template]!,
            selected: state.draft.receiptTemplate == template,
            onTap: () async {
              final saved = await cubit.applyNow(
                state.draft.copyWith(receiptTemplate: template),
              );
              messenger.showSnackBar(SnackBar(
                content: Text(saved
                    ? 'Receipt style saved'
                    : 'Could not save the receipt style. See the Logs '
                        'screen.'),
              ));
            },
          ),
        SizedBox(
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Receipts already generated keep the look they were sent with. '
              'Only new receipts use this style.',
              style: TextStyle(fontSize: 12, color: palette.textMuted),
            ),
          ),
        ),
      ],
    );
  }
}

class _TemplateOption extends StatelessWidget {
  const _TemplateOption({
    required this.template,
    required this.preset,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  final ReceiptTemplate template;
  final ThemePreset preset;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        splashFactory: NoSplash.splashFactory,
        child: Container(
          width: 180,
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
              _ReceiptThumb(template: template, preset: preset),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      switch (template) {
                        ReceiptTemplate.classic => 'Classic',
                        ReceiptTemplate.modern => 'Modern',
                        ReceiptTemplate.minimal => 'Minimal',
                      },
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: palette.textPrimary,
                      ),
                    ),
                  ),
                  if (selected)
                    Icon(Icons.check_circle,
                        size: 16, color: palette.accentText),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: TextStyle(fontSize: 11, color: palette.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small, deliberately abstract rendering of each receipt layout.
///
/// Not a real PDF render: rasterising three receipts on every rebuild of this
/// screen would be slow and would need a live payment to render. The shapes
/// match what [ReceiptRenderer] actually draws — header treatment, rule,
/// fields, amount panel — which is what the owner is choosing between.
class _ReceiptThumb extends StatelessWidget {
  const _ReceiptThumb({required this.template, required this.preset});

  final ReceiptTemplate template;
  final ThemePreset preset;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 104,
        width: double.infinity,
        color: preset.backgroundDark,
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: template == ReceiptTemplate.minimal
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.center,
          children: [
            if (template == ReceiptTemplate.modern)
              Container(
                width: double.infinity,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: preset.primary,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Container(height: 4, width: 54, color: preset.onAccent),
              )
            else ...[
              Container(
                height: 5,
                width: template == ReceiptTemplate.minimal ? 54 : 70,
                color: Colors.white.withValues(alpha: 0.85),
              ),
              const SizedBox(height: 4),
              Container(
                height: 3,
                width: 38,
                color: template == ReceiptTemplate.minimal
                    ? Colors.white24
                    : preset.accentText,
              ),
            ],
            const SizedBox(height: 7),
            if (template != ReceiptTemplate.modern)
              Container(
                height: 1,
                color: template == ReceiptTemplate.minimal
                    ? Colors.white12
                    : preset.primary,
              ),
            const SizedBox(height: 7),
            // Field rows.
            for (var i = 0; i < 2; i++) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Container(height: 3, width: 62, color: Colors.white24),
              ),
              const SizedBox(height: 5),
            ],
            const Spacer(),
            // Amount block.
            Container(
              width: double.infinity,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: template == ReceiptTemplate.minimal
                    ? null
                    : preset.surfaceDark,
                borderRadius: BorderRadius.circular(4),
                border: template == ReceiptTemplate.minimal
                    ? const Border(
                        top: BorderSide(color: Colors.white12),
                        bottom: BorderSide(color: Colors.white12),
                      )
                    : null,
              ),
              child: Container(height: 6, width: 46, color: preset.accentText),
            ),
          ],
        ),
      ),
    );
  }
}
