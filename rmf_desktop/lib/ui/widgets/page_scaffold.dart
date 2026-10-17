import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// The page frame every screen sits in, per the handoff.
///
/// One place for the measurements the handoff specifies — content filling the
/// full width beside the sidebar, padding 28/32/48, a 26px title with a muted
/// subtitle, and actions on the right — so the screens cannot drift apart
/// from each other the way they had before this existed.
class PageScaffold extends StatelessWidget {
  const PageScaffold({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    required this.children,
    this.maxWidth = double.infinity,
    this.hero,
  });

  final String title;

  /// The line under the title — counts, totals, or what the screen is for.
  /// A [Widget] rather than a string because several screens colour part of it
  /// (the amber "319 due" in the members header, for instance).
  final Widget? subtitle;

  final List<Widget> actions;
  final List<Widget> children;
  /// Unbounded by default: the owner decided against a capped column with an
  /// empty gutter on the right, so pages use the whole window. Kept as a
  /// parameter for a screen that genuinely reads better narrow.
  final double maxWidth;

  /// Artwork drawn behind the title, full-bleed to the window edges.
  ///
  /// Only the dashboard uses one. When it is present the header sits inside the
  /// band and the content below rises into it, which is the overlap the handoff
  /// asks for; without it the page keeps its plain header, so every other
  /// screen is unchanged.
  final Widget? hero;

  /// How far the content rises into the hero band. The handoff's −34.
  static const _heroOverlap = 34.0;

  /// The band's height, per the handoff. The header is laid out inside it.
  static const _heroHeight = 210.0;

  @override
  Widget build(BuildContext context) {
    if (hero != null) return _withHero(context);

    return _plain(context);
  }

  /// The dashboard's layout: a full-bleed band with the greeting inside it, and
  /// the content pulled up over its lower edge.
  Widget _withHero(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The band is _heroHeight tall, but grows if the greeting needs more
          // room: on a narrow window the summary sentence wraps onto a second
          // and third line, and a fixed box would clip it. The artwork
          // stretches to whatever height the header settles on.
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: _heroHeight),
            child: Stack(
              children: [
                // Not StackFit.expand: that would size the stack to the
                // artwork rather than to the text laid over it. Positioned.fill
                // stretches the artwork to the header's height instead.
                Positioned.fill(child: hero!),
                // The greeting is laid out over the artwork rather than inside
                // it, so the two can be measured independently.
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 24, 32, _heroOverlap),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxWidth),
                      child: _header(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Transform.translate(
            offset: const Offset(0, -_heroOverlap),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 48 - _heroOverlap),
              child: Align(
                alignment: Alignment.topLeft,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _plain(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 48),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context),
              const SizedBox(height: 22),
              ...children,
            ],
          ),
        ),
      ),
    );
  }

  /// The title, its subtitle and the action buttons — identical in both
  /// layouts, so the dashboard's greeting is set exactly like every other
  /// screen's heading rather than being a second implementation of it.
  Widget _header(BuildContext context) {
    final palette = context.palette;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: TextStyle(
                  // The handoff sets the dashboard greeting larger than a page
                  // title: it is the one heading that is a sentence addressed
                  // to the owner rather than the name of a screen.
                  fontSize: hero != null ? 30 : 26,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.5,
                  color: palette.textPrimary,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                DefaultTextStyle(
                  style: TextStyle(
                    fontSize: hero != null ? 14 : 13,
                    color: hero != null
                        ? palette.textSecondary
                        : palette.textMuted,
                  ),
                  child: subtitle!,
                ),
              ],
            ],
          ),
        ),
        if (actions.isNotEmpty) ...[
          const SizedBox(width: 16),
          Wrap(spacing: 8, children: actions),
        ],
      ],
    );
  }
}

/// A bordered container with an optional header row — the handoff's list and
/// table container (`surf2`, 1px `line`, radius 10, clipped).
class PanelCard extends StatelessWidget {
  const PanelCard({
    super.key,
    this.title,
    this.trailing,
    required this.child,
    this.padded = false,
  });

  final String? title;

  /// The "All due →" style link on the right of the header.
  final Widget? trailing;

  final Widget child;

  /// Panels holding a table manage their own row padding; ones holding prose
  /// want it applied for them.
  final bool padded;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      decoration: BoxDecoration(
        color: palette.surfaceOverlay,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title!,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: palette.textPrimary,
                      ),
                    ),
                  ),
                  ?trailing,
                ],
              ),
            ),
          Padding(
            padding: padded
                ? const EdgeInsets.fromLTRB(16, 0, 16, 16)
                : EdgeInsets.zero,
            child: child,
          ),
        ],
      ),
    );
  }
}

/// The handoff's "All due →" link: accent text, no underline, 12px.
class PanelLink extends StatelessWidget {
  const PanelLink({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: Text(
          label,
          style: TextStyle(fontSize: 12, color: context.palette.accentText),
        ),
      ),
    );
  }
}

/// Uppercase caption over a figure — the handoff's secondary stat.
class StatFigure extends StatelessWidget {
  const StatFigure({
    super.key,
    required this.label,
    required this.value,
    this.hint,
    this.tone,
    this.child,
  });

  final String label;
  final String value;

  /// The quieter half of a value, like "· 0 payments".
  final String? hint;

  final Color? tone;

  /// Anything that belongs under the figure, such as the active-members bar.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 0.66,
            color: palette.textMuted,
          ),
        ),
        const SizedBox(height: 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w500,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: tone ?? palette.textPrimary,
              ),
            ),
            if (hint != null) ...[
              const SizedBox(width: 6),
              Text(
                hint!,
                style: TextStyle(fontSize: 12, color: palette.textMuted),
              ),
            ],
          ],
        ),
        ?child,
      ],
    );
  }
}

/// A member's initials in a circle, as the handoff's list rows use.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({
    super.key,
    required this.name,
    this.size = 30,
    this.onAccent = false,
  });

  final String name;
  final double size;

  /// Draw in the brand colour (the profile header) rather than as a neutral
  /// list avatar.
  final bool onAccent;

  static String initialsOf(String name) {
    // Bracketed qualifiers like "(Night)" are part of several real member
    // names in this gym's ledger and are not part of the person's initials.
    final cleaned = name.replaceAll(RegExp(r'\(.*?\)'), ' ').trim();
    final words = cleaned.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    if (words.isEmpty) return '?';
    return words.take(2).map((w) => w[0].toUpperCase()).join();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: onAccent
            ? palette.accent.withValues(alpha: 0.14)
            : palette.surfaceRaised,
        shape: BoxShape.circle,
        border: Border.all(
            color: onAccent ? Colors.transparent : palette.borderStrong),
      ),
      child: Text(
        initialsOf(name),
        style: TextStyle(
          fontSize: size * 0.36,
          fontWeight: FontWeight.w600,
          color: onAccent ? palette.accentText : palette.textSecondary,
        ),
      ),
    );
  }
}

/// The handoff's primary action: an accent outline on a transparent fill,
/// never a solid block of colour.
class AccentButton extends StatelessWidget {
  const AccentButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.compact = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    final style = OutlinedButton.styleFrom(
      foregroundColor: palette.accentText,
      side: BorderSide(color: palette.accent),
      padding: compact
          ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
          : const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      textStyle: TextStyle(
        fontSize: compact ? 12 : 13,
        fontWeight: FontWeight.w500,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );

    if (icon == null) {
      return OutlinedButton(onPressed: onPressed, style: style, child: Text(label));
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: style,
      icon: Icon(icon, size: compact ? 14 : 16),
      label: Text(label),
    );
  }
}

/// A quiet secondary action: no border, hover tint only.
class GhostButton extends StatelessWidget {
  const GhostButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.compact = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    final style = TextButton.styleFrom(
      foregroundColor: palette.textSecondary,
      padding: compact
          ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
          : const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      textStyle: TextStyle(fontSize: compact ? 12 : 13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );

    if (icon == null) {
      return TextButton(onPressed: onPressed, style: style, child: Text(label));
    }
    return TextButton.icon(
      onPressed: onPressed,
      style: style,
      icon: Icon(icon, size: compact ? 14 : 16),
      label: Text(label),
    );
  }
}
