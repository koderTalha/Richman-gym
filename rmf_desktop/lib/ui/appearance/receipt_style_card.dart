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
    ReceiptTemplate.ticket: 'Big amount card and a tear-off ticket. '
        'Follows light or dark mode.',
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
                        ReceiptTemplate.ticket => 'Ticket',
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
    if (template == ReceiptTemplate.ticket) {
      return _TicketThumb(
        preset: preset,
        light: Theme.of(context).brightness == Brightness.light,
      );
    }
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

/// The Ticket in miniature: brand bar, the amount card in the brand colour,
/// and the ticket with its tear line.
///
/// Drawn in the mode the app is in right now, because that is the mode a
/// receipt made right now will be drawn in — the one template that follows
/// light/dark rather than always being dark.
class _TicketThumb extends StatelessWidget {
  const _TicketThumb({required this.preset, required this.light});

  final ThemePreset preset;
  final bool light;

  @override
  Widget build(BuildContext context) {
    // The receipt's own tokens (see receipt_ticket.dart), not the app's.
    final background = light ? const Color(0xFFEEF2F7) : const Color(0xFF0F172A);
    final surface = light ? Colors.white : const Color(0xFF17233F);
    final border = light ? const Color(0xFFE2E8F0) : const Color(0xFF26334F);
    final ink = light ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final muted = light ? const Color(0xFFCBD5E1) : const Color(0xFF334155);

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 104,
        width: double.infinity,
        color: background,
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Brand bar: logo tile, name, receipt number.
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: border, width: 0.5),
                  ),
                ),
                const SizedBox(width: 4),
                Container(height: 4, width: 44, color: ink),
                const Spacer(),
                Container(height: 3, width: 22, color: muted),
              ],
            ),
            const SizedBox(height: 5),
            // Amount card.
            Container(
              height: 24,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(
                color: preset.primary,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Container(height: 8, width: 40, color: preset.onAccent),
            ),
            const SizedBox(height: 5),
            // Ticket: field rows, tear line, footer.
            Expanded(
              child: Container(
                padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: border, width: 0.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final width in [46.0, 30.0]) ...[
                      Row(
                        children: [
                          Container(
                              width: 3, height: 3, color: preset.primary),
                          const SizedBox(width: 3),
                          Container(height: 3, width: width, color: muted),
                        ],
                      ),
                      const SizedBox(height: 4),
                    ],
                    const Spacer(),
                    Container(height: 0.5, color: border),
                    const SizedBox(height: 3),
                    Center(
                      child: Container(height: 3, width: 50, color: muted),
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
