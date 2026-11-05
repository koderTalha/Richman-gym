import 'package:flutter/material.dart' show Brightness, Color, Colors;
import 'package:flutter/services.dart' show ByteData, rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'receipt_renderer.dart';

/// The Ticket receipt: brand bar, the amount on a card in the brand colour,
/// and the details on a tear-off ticket.
///
/// Built from the 1080 × 1920 design handed over as a Flutter widget, and
/// redrawn here with the `pdf` package rather than used as a widget, so it
/// goes through the same pipeline as the other templates: one PDF, rasterised
/// to the PNG that WhatsApp sends, so the filed copy and the sent copy can
/// never disagree. The page is the design's logical canvas, 540 × 960 pt;
/// rasterised at [dpi] it is exactly 1080 × 1920 px.
///
/// The design's numbers are kept as written. Where the `pdf` package behaves
/// differently from Flutter, the difference is absorbed here instead of in
/// the numbers — see [_Line] for line height, and [_mix] for transparency.
class TicketReceipt {
  TicketReceipt._();

  static const pageWidth = 540.0;
  static const pageHeight = 960.0;

  /// 540 pt × 144 / 72 = 1080 px.
  static const dpi = 144.0;

  static Future<pw.Page> page(ReceiptData data) async {
    final fonts = await TicketFonts.load();
    final p = _Palette.resolve(data);
    final logo =
        data.logoBytes == null ? null : pw.MemoryImage(data.logoBytes!);

    return pw.Page(
      pageFormat: const PdfPageFormat(pageWidth, pageHeight),
      build: (context) => pw.Container(
        color: p.background,
        padding: const pw.EdgeInsets.all(32),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            _brandBar(data, p, fonts, logo),
            pw.SizedBox(height: 24),
            _amountCard(data, p, fonts),
            pw.SizedBox(height: 24),
            pw.Expanded(child: _ticket(data, p, fonts)),
          ],
        ),
      ),
    );
  }
}

/// Manrope, embedded in the PDF. Read from the app bundle (see pubspec), so a
/// receipt renders identically with no network — the gym counter is offline
/// as often as not.
class TicketFonts {
  TicketFonts._(this.medium, this.semiBold, this.bold, this.extraBold);

  final pw.Font medium;
  final pw.Font semiBold;
  final pw.Font bold;
  final pw.Font extraBold;

  static List<ByteData>? _cache;

  static Future<TicketFonts> load() async {
    var data = _cache;
    if (data == null) {
      data = [
        for (final weight in const ['Medium', 'SemiBold', 'Bold', 'ExtraBold'])
          await rootBundle.load('assets/fonts/Manrope-$weight.ttf'),
      ];
      _cache = data;
    }
    // Fresh font objects per document: a pw.Font binds itself to the first
    // document it is drawn into.
    return TicketFonts._(
      pw.Font.ttf(data[0]),
      pw.Font.ttf(data[1]),
      pw.Font.ttf(data[2]),
      pw.Font.ttf(data[3]),
    );
  }
}

// ---------------------------------------------------------------------------
// Colour
// ---------------------------------------------------------------------------

PdfColor _pdf(Color c) => PdfColor.fromInt(c.toARGB32());

/// [fg] at [opacity] over [bg], as one opaque colour.
///
/// The design specifies several colours as translucent ("white @ 10%",
/// "amber @ 12%"). PDF fills drawn by the `pdf` package ignore alpha, so each
/// is pre-composited over the one surface it actually sits on.
PdfColor _mix(Color fg, Color bg, double opacity) =>
    _pdf(Color.lerp(bg, fg, opacity)!);

/// The design's colour tokens, resolved from the app's light/dark mode and
/// the gym's brand.
class _Palette {
  _Palette({
    required this.background,
    required this.surface,
    required this.border,
    required this.text,
    required this.muted,
    required this.icon,
    required this.accent,
    required this.accentRaw,
    required this.onAccent,
    required this.onAccentRaw,
    required this.lateTag,
    required this.advanceTag,
    required this.lightShadow,
  });

  final PdfColor background;
  final PdfColor surface;
  final PdfColor border;
  final PdfColor text;
  final PdfColor muted;
  final PdfColor icon;
  final PdfColor accent;
  final Color accentRaw;
  final PdfColor onAccent;
  final Color onAccentRaw;
  final _Tag lateTag;
  final _Tag advanceTag;

  /// The ticket's lift in light mode. Dark mode has none, by design.
  final bool lightShadow;

  // Fixed in every theme.
  static const logoTile = Color(0xFF0F172A);
  static const pill = PdfColors.white;
  static const paidText = Color(0xFF15803D);

  factory _Palette.resolve(ReceiptData data) {
    final preset = data.branding.effectivePreset;
    // The brand colour and what reads on it come from the gym's preset, not
    // from the design's luminance rule: the preset's onAccent is already
    // what the app's own buttons use, so receipt and app agree.
    final accent = preset.primary;
    final onAccent = preset.onAccent;

    if (data.brightness == Brightness.light) {
      const surface = Color(0xFFFFFFFF);
      return _Palette(
        background: _pdf(const Color(0xFFEEF2F7)),
        surface: _pdf(surface),
        border: _pdf(const Color(0xFFE2E8F0)),
        text: _pdf(const Color(0xFF0F172A)),
        muted: _pdf(const Color(0xFF64748B)),
        icon: _pdf(accent),
        accent: _pdf(accent),
        accentRaw: accent,
        onAccent: _pdf(onAccent),
        onAccentRaw: onAccent,
        lateTag: _Tag(
          bg: _pdf(const Color(0xFFFEF3C7)),
          border: _pdf(const Color(0xFFFCD34D)),
          text: _pdf(const Color(0xFF92400E)),
        ),
        advanceTag: _Tag(
          bg: _pdf(const Color(0xFFDCFCE7)),
          border: _pdf(const Color(0xFF86EFAC)),
          text: _pdf(const Color(0xFF166534)),
        ),
        lightShadow: true,
      );
    }

    const surface = Color(0xFF17233F);
    const amber = Color(0xFFFBBF24);
    const green = Color(0xFF4ADE80);
    return _Palette(
      background: _pdf(const Color(0xFF0F172A)),
      surface: _pdf(surface),
      border: _pdf(const Color(0xFF26334F)),
      text: _pdf(const Color(0xFFF8FAFC)),
      muted: _pdf(const Color(0xFF94A3B8)),
      icon: _pdf(const Color(0xFF94A3B8)),
      accent: _pdf(accent),
      accentRaw: accent,
      onAccent: _pdf(onAccent),
      onAccentRaw: onAccent,
      lateTag: _Tag(
        bg: _mix(amber, surface, 0.12),
        border: _mix(amber, surface, 0.30),
        text: _pdf(amber),
      ),
      advanceTag: _Tag(
        bg: _mix(green, surface, 0.12),
        border: _mix(green, surface, 0.30),
        text: _pdf(green),
      ),
      lightShadow: false,
    );
  }
}

class _Tag {
  const _Tag({required this.bg, required this.border, required this.text});
  final PdfColor bg;
  final PdfColor border;
  final PdfColor text;
}

/// "#RRGGBB" for an SVG attribute. Not [PdfColor.toHex], which appends the
/// alpha ("#RRGGBBAA") — a form SVG reads as a different colour entirely.
String _hex(PdfColor c) =>
    '#${(c.toInt() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

// ---------------------------------------------------------------------------
// Type
// ---------------------------------------------------------------------------

// Manrope's vertical metrics (hhea, per em): what both Flutter and the pdf
// package lay a line out from.
const _ascent = 2132 / 2000;
const _descent = 600 / 2000;

/// A line of text in a box [lineHeight] tall, with the baseline where Flutter
/// puts it for the same `TextStyle.height`.
///
/// The design sets most text at `height: 1`, a line exactly as tall as the
/// font size. The pdf package has no equivalent — it always lays a line out
/// 1.37 × the size for Manrope — so without this every label would be a
/// third taller than designed and the ticket would overflow the page. Flutter
/// shares the change in height between ascent and descent in proportion to
/// them; this does the same, letting the glyphs overhang the box exactly as
/// they do on screen.
class _Line extends pw.SingleChildWidget {
  _Line({
    required this.lineHeight,
    required this.fontSize,
    required pw.Widget child,
  }) : super(child: child);

  final double lineHeight;
  final double fontSize;

  @override
  void layout(
    pw.Context context,
    pw.BoxConstraints constraints, {
    bool parentUsesSize = false,
  }) {
    child!.layout(
      context,
      pw.BoxConstraints(
          minWidth: constraints.minWidth, maxWidth: constraints.maxWidth),
      parentUsesSize: true,
    );
    final natural = child!.box!;
    box = constraints.constrainRect(width: natural.width, height: lineHeight);
    // Natural line: baseline at ascent × size from the top. Wanted: at
    // ascent / (ascent + descent) of the box. y runs upward in a PDF.
    final dy = _descent * (lineHeight / (_ascent + _descent) - fontSize);
    child!.box = PdfRect(0, dy, natural.width, natural.height);
  }

  @override
  void paint(pw.Context context) {
    super.paint(context);
    paintChild(context);
  }
}

pw.TextStyle _style(
  pw.Font font,
  double size,
  PdfColor color, {
  double letterSpacingEm = 0,
}) =>
    pw.TextStyle(
      font: font,
      fontSize: size,
      color: color,
      letterSpacing: size * letterSpacingEm,
    );

/// One line of text, at the design's [height] multiple when it gives one.
pw.Widget _text(
  String text,
  pw.Font font,
  double size,
  PdfColor color, {
  double letterSpacingEm = 0,
  double? height,
  pw.TextAlign? align,
}) {
  final widget = pw.Text(
    text,
    maxLines: 1,
    softWrap: false,
    textAlign: align,
    style: _style(font, size, color, letterSpacingEm: letterSpacingEm),
  );
  if (height == null) return widget;
  return _Line(lineHeight: size * height, fontSize: size, child: widget);
}

/// [text] cut to the width available, ending in "…" when it did not fit.
///
/// Field values are one line by design. A 40-character member name must not
/// push the column beside it off the ticket.
pw.Widget _ellipsized(
  String text,
  pw.Font font,
  double size,
  PdfColor color, {
  double? height,
}) =>
    pw.LayoutBuilder(builder: (context, constraints) {
      final max = constraints?.maxWidth ?? double.infinity;
      final pdfFont = font.getFont(context);
      double width(String s) => pdfFont.stringMetrics(s).advanceWidth * size;

      var shown = text;
      if (width(shown) > max) {
        while (shown.isNotEmpty && width('$shown…') > max) {
          shown = shown.substring(0, shown.length - 1);
        }
        shown = '${shown.trimRight()}…';
      }
      return _text(shown, font, size, color, height: height);
    });

// ---------------------------------------------------------------------------
// Icons — Lucide outlines, drawn as SVG so they stay vector in the PDF
// ---------------------------------------------------------------------------

pw.Widget _icon(String body, PdfColor color, double size) => pw.SvgImage(
      width: size,
      height: size,
      svg: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" '
          'fill="none" stroke="${_hex(color)}" stroke-width="2" '
          'stroke-linecap="round" stroke-linejoin="round">$body</svg>',
    );

const _checkCircle = '<circle cx="12" cy="12" r="10"/>'
    '<path d="M9 12l2 2l4 -4"/>';
const _phone = '<path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 '
    '1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 '
    '4.11 2h3a2 2 0 0 1 2 1.72 12.84 12.84 0 0 0 .7 2.81 2 2 0 0 1-.45 '
    '2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45 12.84 '
    '12.84 0 0 0 2.81.7A2 2 0 0 1 22 16.92z"/>';
const _mapPin = '<path d="M20 10c0 6-8 12-8 12s-8-6-8-12a8 8 0 0 1 16 0Z"/>'
    '<circle cx="12" cy="10" r="3"/>';

// ---------------------------------------------------------------------------
// 1. Brand bar
// ---------------------------------------------------------------------------

pw.Widget _brandBar(
  ReceiptData data,
  _Palette p,
  TicketFonts f,
  pw.MemoryImage? logo,
) =>
    pw.Row(
      children: [
        // No logo, no tile: an empty dark square would read as a broken image.
        if (logo != null) ...[
          pw.Container(
            width: 60,
            height: 60,
            alignment: pw.Alignment.center,
            decoration: pw.BoxDecoration(
              color: _pdf(_Palette.logoTile),
              borderRadius: pw.BorderRadius.circular(15),
              border: pw.Border.all(
                color: _mix(Colors.white, _Palette.logoTile, 0.10),
                width: 0.5,
              ),
              boxShadow: const [
                pw.BoxShadow(
                  color: PdfColor(0.008, 0.024, 0.09, 0.55),
                  offset: PdfPoint(0, 5),
                  blurRadius: 12,
                  spreadRadius: -7,
                ),
              ],
            ),
            child: pw.SizedBox(
              width: 43,
              height: 43,
              child: pw.Image(logo, fit: pw.BoxFit.contain),
            ),
          ),
          pw.SizedBox(width: 14),
        ],
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pw.FittedBox(
                fit: pw.BoxFit.scaleDown,
                alignment: pw.Alignment.centerLeft,
                child: _text(data.gymName.toUpperCase(), f.extraBold, 22,
                    p.text,
                    letterSpacingEm: 0.02, height: 1),
              ),
              pw.SizedBox(height: 6),
              _text('PAYMENT RECEIPT', f.bold, 11, p.muted,
                  letterSpacingEm: 0.3, height: 1),
            ],
          ),
        ),
        pw.SizedBox(width: 12),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            _text('RECEIPT NO', f.bold, 10, p.muted,
                letterSpacingEm: 0.18, height: 1),
            pw.SizedBox(height: 6),
            _text(data.receiptNumber, f.bold, 14, p.text, height: 1),
          ],
        ),
      ],
    );

// ---------------------------------------------------------------------------
// 2. Amount card
// ---------------------------------------------------------------------------

/// Splits "Rs. 2,500" into the currency and the figure, which the design sets
/// at different sizes. A format with no space prints whole, as the figure.
(String?, String) _splitAmount(String label) {
  final space = label.indexOf(' ');
  if (space <= 0) return (null, label);
  return (label.substring(0, space), label.substring(space + 1));
}

pw.Widget _amountCard(ReceiptData data, _Palette p, TicketFonts f) {
  final (currency, figure) = _splitAmount(data.amountLabel);
  final radius = pw.BorderRadius.circular(20);

  return pw.Container(
    decoration: pw.BoxDecoration(
      color: p.accent,
      borderRadius: radius,
      boxShadow: [
        pw.BoxShadow(
          color: PdfColor(p.accent.red, p.accent.green, p.accent.blue, 0.55),
          offset: const PdfPoint(0, 15),
          blurRadius: 30,
          spreadRadius: -17,
        ),
      ],
    ),
    child: pw.Container(
      decoration: pw.BoxDecoration(
        borderRadius: radius,
        // The soft sheen, top right. White at 16% fading out by 55% of the
        // way, pre-mixed onto the brand colour.
        gradient: pw.RadialGradient(
          center: pw.Alignment.topRight,
          radius: 1.2,
          colors: [_mix(Colors.white, p.accentRaw, 0.16), p.accent],
          stops: const [0, 0.55],
        ),
      ),
      padding: const pw.EdgeInsets.fromLTRB(32, 32, 32, 38),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Row(
            children: [
              pw.Expanded(
                child: _text('AMOUNT PAID', f.bold, 12,
                    _mix(p.onAccentRaw, p.accentRaw, 0.82),
                    letterSpacingEm: 0.26),
              ),
              _paidPill(f),
            ],
          ),
          pw.SizedBox(height: 26),
          pw.FittedBox(
            fit: pw.BoxFit.scaleDown,
            alignment: pw.Alignment.centerLeft,
            // One RichText so the currency and the figure share a baseline.
            child: _Line(
              lineHeight: 98 * 0.95,
              fontSize: 98,
              child: pw.RichText(
                maxLines: 1,
                softWrap: false,
                text: pw.TextSpan(children: [
                  if (currency != null)
                    pw.TextSpan(
                      // The space stands in for the design's 10 pt gap.
                      text: '$currency ',
                      style: _style(f.bold, 32,
                          _mix(p.onAccentRaw, p.accentRaw, 0.85)),
                    ),
                  pw.TextSpan(
                    text: figure,
                    style: _style(f.extraBold, 98, p.onAccent,
                        letterSpacingEm: -0.03),
                  ),
                ]),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Every receipt this app issues is for money taken, so the pill is always
/// PAID. The design's partial and pending states have no payment behind them.
pw.Widget _paidPill(TicketFonts f) {
  const lineHeight = 12 * 1.2;
  const height = lineHeight + 12;
  final colour = _pdf(_Palette.paidText);
  return pw.Container(
    height: height,
    padding: const pw.EdgeInsets.fromLTRB(9, 6, 12, 6),
    decoration: const pw.BoxDecoration(
      color: _Palette.pill,
      // Exactly half the height. The pdf package does not clamp an oversized
      // radius the way Flutter does; 999 would paint over the page.
      borderRadius: pw.BorderRadius.all(pw.Radius.circular(height / 2)),
      boxShadow: [
        pw.BoxShadow(
          color: PdfColor(0.008, 0.024, 0.09, 0.4),
          offset: PdfPoint(0, 3),
          blurRadius: 8,
          spreadRadius: -4,
        ),
      ],
    ),
    child: pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        _icon(_checkCircle, colour, 14),
        pw.SizedBox(width: 5),
        _text('PAID', f.extraBold, 12, colour,
            letterSpacingEm: 0.2, height: 1.2),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// 3. Ticket
// ---------------------------------------------------------------------------

const _tearHeight = 28.0;
const _footerHeight = 120.0;
const _ticketRadius = 20.0;
const _notchRadius = 14.0;

/// The billing period without the timing note, and the tag that replaces it.
///
/// The note rides inside the period label ("October 2026 (paid late)")
/// because that label is parameter 3 of the Meta-approved `payment_receipt`
/// template, and changing that template's parameters takes receipts off the
/// air until Meta re-approves it. So the callers keep sending one string, and
/// this is the one place that turns the suffix into the design's tag.
(String, String?, bool) _splitTiming(String period) {
  const late = ' (paid late)';
  const advance = ' (paid in advance)';
  if (period.endsWith(late)) {
    return (period.substring(0, period.length - late.length), 'PAID LATE',
        true);
  }
  if (period.endsWith(advance)) {
    return (
      period.substring(0, period.length - advance.length),
      'PAID IN ADVANCE',
      false,
    );
  }
  return (period, null, false);
}

pw.Widget _ticket(ReceiptData data, _Palette p, TicketFonts f) {
  final (period, tag, isLate) = _splitTiming(data.billingPeriod);
  final reference = data.referenceNumber?.trim();
  final hasReference = reference != null && reference.isNotEmpty;

  final content = pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.Expanded(
        child: pw.Padding(
          padding: const pw.EdgeInsets.fromLTRB(32, 32, 32, 20),
          child: pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              _group(
                'MEMBER',
                p,
                f,
                left: _field('Member Name', data.memberName, p, f),
                right: _field('Member ID', '#${data.memberCode}', p, f),
                below: _field('Membership', data.membershipLabel, p, f),
              ),
              pw.SizedBox(height: 40),
              _group(
                'PAYMENT',
                p,
                f,
                left: _field('Payment Date', data.paymentDate, p, f),
                // A bank or wallet reference is how a member proves a
                // transfer, so it is printed, under the method it belongs to.
                // Not as a column beside the period: with a timing tag there
                // too, the period itself got cut to "Octob…".
                right: _field('Payment Method', data.paymentMethod, p, f,
                    note: hasReference ? 'Ref $reference' : null),
                below: _field(
                  'Billing Period',
                  period,
                  p,
                  f,
                  tag: tag,
                  tagColours: isLate ? p.lateTag : p.advanceTag,
                ),
              ),
            ],
          ),
        ),
      ),
      pw.SizedBox(
        height: _tearHeight,
        child: pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 26),
          child: pw.Center(
            child: pw.CustomPaint(
              size: const PdfPoint(double.infinity, 1.5),
              painter: (canvas, size) => canvas
                ..setStrokeColor(p.border)
                ..setLineWidth(size.y)
                ..setLineDashPattern([4.5, 4.5])
                ..moveTo(0, size.y / 2)
                ..lineTo(size.x, size.y / 2)
                ..strokePath(),
            ),
          ),
        ),
      ),
      pw.SizedBox(height: _footerHeight, child: _footer(data, p, f)),
    ],
  );

  return pw.Container(
    // The shadow alone. It is filled with the page colour, so the only thing
    // that shows of this box is its blur — including through the notches,
    // where a fill in the ticket's colour would close them up.
    decoration: pw.BoxDecoration(
      color: p.background,
      borderRadius: pw.BorderRadius.circular(_ticketRadius),
      boxShadow: p.lightShadow
          ? const [
              pw.BoxShadow(
                color: PdfColor(0.059, 0.09, 0.165, 0.25),
                offset: PdfPoint(0, 12),
                blurRadius: 24,
                spreadRadius: -16,
              ),
            ]
          : null,
    ),
    child: pw.CustomPaint(
      painter: (canvas, size) => _paintTicket(canvas, size, p),
      child: content,
    ),
  );
}

/// The ticket outline: a rounded rectangle with a semicircle cut into each
/// side at the tear line. Drawn as one path rather than as circles painted
/// over the card, so the border follows the notch and the notch shows the
/// page in either theme.
void _paintTicket(PdfGraphics canvas, PdfPoint size, _Palette p) {
  // y runs upward from the bottom of the ticket.
  final w = size.x;
  final h = size.y;
  const r = _ticketRadius;
  const n = _notchRadius;
  const cy = _footerHeight + _tearHeight / 2;
  // Control-point distance for a quarter circle drawn as one cubic.
  const k = 0.5523;

  canvas
    ..setFillColor(p.surface)
    ..setStrokeColor(p.border)
    ..setLineWidth(0.5)
    ..moveTo(r, 0)
    ..lineTo(w - r, 0)
    ..curveTo(w - r + k * r, 0, w, r - k * r, w, r)
    ..lineTo(w, cy - n)
    ..curveTo(w - k * n, cy - n, w - n, cy - k * n, w - n, cy)
    ..curveTo(w - n, cy + k * n, w - k * n, cy + n, w, cy + n)
    ..lineTo(w, h - r)
    ..curveTo(w, h - r + k * r, w - r + k * r, h, w - r, h)
    ..lineTo(r, h)
    ..curveTo(r - k * r, h, 0, h - r + k * r, 0, h - r)
    ..lineTo(0, cy + n)
    ..curveTo(k * n, cy + n, n, cy + k * n, n, cy)
    ..curveTo(n, cy - k * n, k * n, cy - n, 0, cy - n)
    ..lineTo(0, r)
    ..curveTo(0, r - k * r, r - k * r, 0, r, 0)
    ..closePath()
    ..fillAndStrokePath();
}

pw.Widget _pair(pw.Widget left, pw.Widget right) => pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(child: left),
        pw.SizedBox(width: 24),
        pw.Expanded(child: right),
      ],
    );

pw.Widget _group(
  String title,
  _Palette p,
  TicketFonts f, {
  required pw.Widget left,
  required pw.Widget right,
  required pw.Widget below,
}) =>
    pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Row(
          children: [
            pw.Container(
              width: 6,
              height: 6,
              decoration: pw.BoxDecoration(
                color: p.accent,
                borderRadius: pw.BorderRadius.circular(2),
              ),
            ),
            pw.SizedBox(width: 8),
            _text(title, f.extraBold, 10.5, p.muted,
                letterSpacingEm: 0.22, height: 1),
            pw.SizedBox(width: 8),
            pw.Expanded(child: pw.Container(height: 0.5, color: p.border)),
          ],
        ),
        pw.SizedBox(height: 20),
        _pair(left, right),
        pw.SizedBox(height: 28),
        below,
      ],
    );

pw.Widget _field(
  String label,
  String value,
  _Palette p,
  TicketFonts f, {
  String? tag,
  _Tag? tagColours,
  String? note,
}) =>
    pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        _text(label, f.semiBold, 12, p.muted, height: 1.3),
        pw.SizedBox(height: 7),
        pw.Row(
          children: [
            pw.Flexible(
              child: _ellipsized(value, f.bold, 20, p.text, height: 1.15),
            ),
            if (tag != null && tagColours != null) ...[
              pw.SizedBox(width: 8),
              _tag(tag, tagColours, f),
            ],
          ],
        ),
        if (note != null) ...[
          pw.SizedBox(height: 5),
          _ellipsized(note, f.medium, 12, p.muted, height: 1.3),
        ],
      ],
    );

pw.Widget _tag(String label, _Tag c, TicketFonts f) {
  const height = 9.5 * 1.2 + 8;
  return pw.Container(
    height: height,
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: pw.BoxDecoration(
      color: c.bg,
      borderRadius:
          const pw.BorderRadius.all(pw.Radius.circular(height / 2)),
      border: pw.Border.all(color: c.border, width: 0.5),
    ),
    child: _text(label, f.extraBold, 9.5, c.text,
        letterSpacingEm: 0.1, height: 1.2),
  );
}

pw.Widget _footer(ReceiptData data, _Palette p, TicketFonts f) {
  final phone = data.gymPhone?.trim();
  final address = data.gymAddress?.trim();
  return pw.Padding(
    padding: const pw.EdgeInsets.fromLTRB(32, 0, 32, 10),
    child: pw.Column(
      mainAxisAlignment: pw.MainAxisAlignment.center,
      children: [
        pw.FittedBox(
          fit: pw.BoxFit.scaleDown,
          child: _text(data.footerMessage, f.bold, 15, p.text, height: 1.3),
        ),
        if (phone != null && phone.isNotEmpty) ...[
          pw.SizedBox(height: 10),
          _contactLine(_phone, phone, p, f),
        ],
        if (address != null && address.isNotEmpty) ...[
          pw.SizedBox(height: 6),
          _contactLine(_mapPin, address, p, f),
        ],
      ],
    ),
  );
}

pw.Widget _contactLine(String icon, String text, _Palette p, TicketFonts f) =>
    pw.FittedBox(
      fit: pw.BoxFit.scaleDown,
      child: pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          _icon(icon, p.icon, 12),
          pw.SizedBox(width: 6),
          _text(text, f.medium, 12, p.muted, height: 1.4),
        ],
      ),
    );
