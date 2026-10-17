import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'count_up.dart';

/// How urgent an attention card is, which decides its label colour.
enum AttentionTone {
  /// Money is owed. Amber, the colour this app already uses for DUE.
  warning,

  /// Worth doing before it becomes a problem.
  neutral,

  /// Nothing to do. Green, with a tick.
  clear,
}

/// One thing that needs the owner's attention, with the action that resolves
/// it.
///
/// The handoff's organising idea: every number on the dashboard used to carry
/// the same weight, so the owner could not tell what to do next. These sit
/// above the totals and each one offers its own next step, rather than leaving
/// the owner to work out which screen to open.
class AttentionCard extends StatefulWidget {
  const AttentionCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.unit,
    this.detail,
    this.tone = AttentionTone.neutral,
    this.actions = const [],
    this.onTap,
  });

  final IconData icon;
  final String label;

  /// The figure itself. A number rather than a formatted string so the card
  /// can count it up on arrival — see [CountUp].
  final int value;

  /// What the figure counts ("members"), beside it in muted text.
  final String? unit;

  /// A line under the figure, for cards with no buttons.
  final Widget? detail;

  final AttentionTone tone;

  /// Buttons along the bottom. The first should be the obvious next step.
  final List<Widget> actions;

  /// Makes the whole card tappable, for cards whose action is just "go look".
  final VoidCallback? onTap;

  @override
  State<AttentionCard> createState() => _AttentionCardState();
}

class _AttentionCardState extends State<AttentionCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    final toneColour = switch (widget.tone) {
      AttentionTone.warning => palette.due,
      AttentionTone.neutral => palette.textSecondary,
      AttentionTone.clear => palette.paid,
    };

    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      // The handoff lifts a card 2px on hover rather than brightening it.
      transform: Matrix4.translationValues(0, _hovered ? -2 : 0, 0),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: _hovered ? 0.45 : 0.35),
            blurRadius: _hovered ? 28 : 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(widget.icon, size: 15, color: toneColour),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  widget.label,
                  style: TextStyle(fontSize: 12, color: toneColour),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              CountUp(
                value: widget.value,
                builder: (context, animated) => Text(
                  '${animated.round()}',
                  style: TextStyle(
                    fontSize: 38,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -1.1,
                    height: 1.05,
                    // Tabular figures matter more here than anywhere: without
                    // them a counting number changes width on every frame and
                    // the text beside it jitters.
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: palette.textPrimary,
                  ),
                ),
              ),
              if (widget.unit != null) ...[
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    widget.unit!,
                    style: TextStyle(fontSize: 12, color: palette.textMuted),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
          if (widget.detail != null) ...[
            const SizedBox(height: 10),
            widget.detail!,
          ],
          if (widget.actions.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: widget.actions),
          ],
        ],
      ),
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: widget.onTap == null
          ? MouseCursor.defer
          : SystemMouseCursors.click,
      child: widget.onTap == null
          ? card
          : GestureDetector(onTap: widget.onTap, child: card),
    );
  }
}
