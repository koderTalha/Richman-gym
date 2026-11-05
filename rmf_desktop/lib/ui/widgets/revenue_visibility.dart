import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/revenue_visibility_cubit.dart';
import '../../theme/app_theme.dart';

/// What a hidden amount shows instead.
const revenueMask = '••••••';

/// [text], or [revenueMask] in its place while [obscured], cross-fading
/// between the two.
///
/// Both are always laid out, one on top of the other, so the space taken is
/// the wider of the two whichever is showing: hiding a figure does not pull
/// the hint beside it or the rest of a sentence sideways. The hidden one is
/// kept out of the semantics tree, or a screen reader would read the amount
/// the owner just hid.
class ObscuredText extends StatelessWidget {
  const ObscuredText({
    super.key,
    required this.text,
    required this.obscured,
    this.style,
  });

  final String text;
  final bool obscured;
  final TextStyle? style;

  static const _fade = Duration(milliseconds: 180);

  @override
  Widget build(BuildContext context) {
    Widget layer(String value, {required bool shown}) => ExcludeSemantics(
          excluding: !shown,
          child: AnimatedOpacity(
            opacity: shown ? 1 : 0,
            duration: _fade,
            child: Text(value, style: style),
          ),
        );

    return Stack(
      alignment: AlignmentDirectional.centerStart,
      children: [
        layer(text, shown: !obscured),
        layer(revenueMask, shown: obscured),
      ],
    );
  }
}

/// The one eye that hides or shows every revenue figure at once, through
/// [RevenueVisibilityCubit].
///
/// It sits at the right end of the dashboard's stats row, after all the
/// figures rather than beside any one of them: an eye next to a single figure
/// reads as if it hid only that one, and it governs both revenue stats and the
/// greeting's figure. Drawn like an icon-only [GhostButton] — same colour,
/// corner and hover wash — with the tooltip as its label for the mouse and for
/// a screen reader.
class RevenueVisibilityButton extends StatelessWidget {
  const RevenueVisibilityButton({super.key});

  @override
  Widget build(BuildContext context) {
    final visible = context.watch<RevenueVisibilityCubit>().state;
    final label = visible ? 'Hide revenue' : 'Show revenue';

    return IconButton(
      onPressed: context.read<RevenueVisibilityCubit>().toggle,
      tooltip: label,
      iconSize: 16,
      style: IconButton.styleFrom(
        foregroundColor: context.palette.textSecondary,
        minimumSize: const Size.square(44),
        // Padded to 48 like the TextButton beside it, so the two line up.
        tapTargetSize: MaterialTapTargetSize.padded,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 150),
        child: Icon(
          visible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          key: ValueKey(visible),
        ),
      ),
    );
  }
}
