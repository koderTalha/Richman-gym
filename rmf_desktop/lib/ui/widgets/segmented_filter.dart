import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// One option in a [SegmentedFilter].
class SegmentOption<T> {
  const SegmentOption({
    required this.value,
    required this.label,
    this.count,
    this.icon,
  });

  final T value;
  final String label;

  /// Shown muted beside the label, as the handoff's "All 697" does.
  final int? count;

  final IconData? icon;
}

/// The handoff's segmented control: one inset track holding the options, the
/// selected one raised out of it.
///
/// Replaces the `ChoiceChip` row the screens used before. Chips read as a set
/// of independent toggles — several could plausibly be on at once — where this
/// reads as one choice among several, which is what a status filter and a
/// settings tab both are.
class SegmentedFilter<T> extends StatelessWidget {
  const SegmentedFilter({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelect,
  });

  final List<SegmentOption<T>> options;
  final T selected;
  final ValueChanged<T> onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      decoration: BoxDecoration(
        color: palette.surfaceOverlay,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: palette.border),
      ),
      padding: const EdgeInsets.all(3),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final option in options)
            _Segment<T>(
              option: option,
              selected: option.value == selected,
              onTap: () => onSelect(option.value),
            ),
        ],
      ),
    );
  }
}

class _Segment<T> extends StatefulWidget {
  const _Segment({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final SegmentOption<T> option;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_Segment<T>> createState() => _SegmentState<T>();
}

class _SegmentState<T> extends State<_Segment<T>> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final selected = widget.selected;

    return Semantics(
      button: true,
      selected: selected,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 11),
            decoration: BoxDecoration(
              color: selected ? palette.surfaceRaised : Colors.transparent,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(
                color: selected ? palette.borderStrong : Colors.transparent,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.option.icon != null) ...[
                  Icon(
                    widget.option.icon,
                    size: 14,
                    color: selected
                        ? palette.textPrimary
                        : palette.textSecondary,
                  ),
                  const SizedBox(width: 7),
                ],
                Text(
                  widget.option.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight:
                        selected ? FontWeight.w500 : FontWeight.w400,
                    color: selected
                        ? palette.textPrimary
                        : (_hovered
                            ? palette.textPrimary
                            : palette.textSecondary),
                  ),
                ),
                if (widget.option.count != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    '${widget.option.count}',
                    style: TextStyle(
                      fontSize: 12,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: palette.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
