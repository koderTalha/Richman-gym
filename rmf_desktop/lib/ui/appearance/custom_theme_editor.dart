import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/branding_cubit.dart';
import '../../theme/app_theme.dart';
import '../../theme/branding_config.dart';

/// Lets the owner mix their own colours.
///
/// Six roles, each a hex field with a swatch that opens a picker. Editing any
/// of them switches the configuration to `custom` and previews it, so the
/// effect is visible on the real app behind the screen rather than in a
/// thumbnail.
class CustomThemeEditor extends StatelessWidget {
  const CustomThemeEditor({super.key, required this.state});

  final BrandingState state;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final cubit = context.read<BrandingCubit>();
    final custom = state.draft.custom;
    final base = state.draft.basePreset;

    void setColour(CustomColors updated) {
      cubit.preview(state.draft.copyWith(
        presetId: BrandingConfig.customId,
        custom: updated,
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _ColourField(
              label: 'Primary brand colour',
              value: custom.primary,
              fallback: base.primary,
              onChanged: (c) => setColour(custom.copyWith(primary: c)),
            ),
            _ColourField(
              label: 'Accent colour',
              value: custom.accent,
              fallback: base.accentText,
              onChanged: (c) => setColour(custom.copyWith(accent: c)),
            ),
            _ColourField(
              label: 'Application background',
              value: custom.background,
              fallback: base.backgroundDark,
              onChanged: (c) => setColour(custom.copyWith(background: c)),
            ),
            _ColourField(
              label: 'Sidebar background',
              value: custom.sidebar,
              fallback: base.sidebarDark,
              onChanged: (c) => setColour(custom.copyWith(sidebar: c)),
            ),
            _ColourField(
              label: 'Card background',
              value: custom.surface,
              fallback: base.surfaceDark,
              onChanged: (c) => setColour(custom.copyWith(surface: c)),
            ),
            _ColourField(
              label: 'Primary text',
              value: custom.textPrimary,
              fallback: palette.textPrimary,
              onChanged: (c) => setColour(custom.copyWith(textPrimary: c)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _ContrastNotice(state: state),
      ],
    );
  }
}

/// Tells the owner, in plain words, whether their colours are readable.
///
/// Advisory rather than blocking: the app guarantees a readable *button label*
/// by flipping it to black or white automatically, so a poor brand colour
/// cannot make the app unusable. What it cannot fix is a background the owner
/// has set too close to their text, so that is what this warns about.
class _ContrastNotice extends StatelessWidget {
  const _ContrastNotice({required this.state});

  final BrandingState state;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final preset = state.draft.effectivePreset;
    final textOnBackground = contrastRatio(
      state.draft.custom.textPrimary ?? palette.textPrimary,
      preset.backgroundDark,
    );
    final readable = textOnBackground >= 4.5;

    return Container(
      decoration: BoxDecoration(
        color: readable ? palette.paidBg : palette.dueBg,
        borderRadius: BorderRadius.circular(9),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Icon(
            readable ? Icons.check_circle_outline : Icons.warning_amber_rounded,
            size: 18,
            color: readable ? palette.paid : palette.due,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              readable
                  ? 'Text on your background reads at '
                      '${textOnBackground.toStringAsFixed(1)}:1 — comfortably '
                      'readable.'
                  : 'Text on your background reads at '
                      '${textOnBackground.toStringAsFixed(1)}:1, below the '
                      '4.5:1 needed to stay legible. Try a darker background '
                      'or lighter text.',
              style: TextStyle(fontSize: 12, color: palette.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// A hex field and a swatch that opens a colour picker.
class _ColourField extends StatefulWidget {
  const _ColourField({
    required this.label,
    required this.value,
    required this.fallback,
    required this.onChanged,
  });

  final String label;

  /// The owner's override, or null when they have not set this role.
  final Color? value;

  /// Shown greyed when [value] is null, so the field communicates "this is what
  /// you will get" rather than sitting empty.
  final Color fallback;

  final ValueChanged<Color> onChanged;

  @override
  State<_ColourField> createState() => _ColourFieldState();
}

class _ColourFieldState extends State<_ColourField> {
  late final TextEditingController _controller =
      TextEditingController(text: _text);

  String get _text =>
      widget.value == null ? '' : formatHexColor(widget.value!);

  @override
  void didUpdateWidget(_ColourField old) {
    super.didUpdateWidget(old);
    // Follow the model when it changes underneath us (the owner picked a preset
    // while this field was on screen), but never while they are mid-type —
    // rewriting the field on every keystroke moves the caret.
    if (widget.value != old.value && !_hasFocus) {
      _controller.text = _text;
    }
  }

  bool _hasFocus = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _commit(String raw) {
    final parsed = parseHexColor(raw);
    // Silently ignored while incomplete: the owner types `#2563EB` one
    // character at a time, and five of those six states are not yet a colour.
    if (parsed != null) widget.onChanged(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final effective = widget.value ?? widget.fallback;

    return SizedBox(
      width: 232,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.label,
            style: TextStyle(fontSize: 12, color: palette.textSecondary),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _SwatchButton(
                colour: effective,
                isDefault: widget.value == null,
                onPicked: (c) {
                  _controller.text = formatHexColor(c);
                  widget.onChanged(c);
                },
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Focus(
                  onFocusChange: (has) => _hasFocus = has,
                  child: TextField(
                    controller: _controller,
                    onChanged: _commit,
                    onSubmitted: _commit,
                    style: TextStyle(fontSize: 13, color: palette.textPrimary),
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(7),
                      FilteringTextInputFormatter.allow(
                          RegExp(r'[#0-9a-fA-F]')),
                    ],
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: formatHexColor(widget.fallback),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 10),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The colour well. Opens a small palette of shades rather than a full picker:
/// a gym owner choosing a brand colour has a colour in mind, and a hue/
/// saturation wheel is a worse way to reach a specific hex than typing it.
class _SwatchButton extends StatelessWidget {
  const _SwatchButton({
    required this.colour,
    required this.isDefault,
    required this.onPicked,
  });

  final Color colour;
  final bool isDefault;
  final ValueChanged<Color> onPicked;

  static const _shades = <Color>[
    Color(0xFFE11D2E), Color(0xFFFF334F), Color(0xFFF97316),
    Color(0xFFD4A72C), Color(0xFF10B981), Color(0xFF0891B2),
    Color(0xFF2563EB), Color(0xFF7C3AED), Color(0xFFDB2777),
    Color(0xFF0B0B0D), Color(0xFF17171B), Color(0xFFF5F5F7),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Tooltip(
      message: isDefault ? 'Default — click to choose' : 'Click to change',
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: () async {
          final picked = await showDialog<Color>(
            context: context,
            builder: (context) => _ShadeDialog(shades: _shades),
          );
          if (picked != null) onPicked(picked);
        },
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: colour,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: isDefault ? palette.borderStrong : palette.border,
              // Dashed is not available on a Border, so "unset" is shown as a
              // heavier outline plus the tooltip.
              width: isDefault ? 2 : 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _ShadeDialog extends StatelessWidget {
  const _ShadeDialog({required this.shades});

  final List<Color> shades;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return AlertDialog(
      backgroundColor: palette.surfaceRaised,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Text('Choose a colour',
          style: TextStyle(fontSize: 17, color: palette.textPrimary)),
      content: SizedBox(
        width: 260,
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final shade in shades)
              InkWell(
                borderRadius: BorderRadius.circular(7),
                onTap: () => Navigator.of(context).pop(shade),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: shade,
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: palette.border),
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
