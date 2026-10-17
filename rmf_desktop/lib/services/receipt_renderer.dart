import 'dart:typed_data';

import 'package:flutter/material.dart' show Color;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../theme/branding_config.dart';
import '../theme/theme_preset.dart';

/// Everything printed on a receipt, already formatted for display.
class ReceiptData {
  const ReceiptData({
    required this.gymName,
    required this.receiptNumber,
    required this.paymentDate,
    required this.memberName,
    required this.memberCode,
    required this.membershipLabel,
    required this.billingPeriod,
    required this.paymentMethod,
    required this.amountLabel,
    required this.footerMessage,
    this.referenceNumber,
    this.gymPhone,
    this.gymAddress,
    this.branding = const BrandingConfig(),
    this.logoBytes,
  });

  final String gymName;
  final String receiptNumber;
  final String paymentDate;
  final String memberName;
  final int memberCode;
  final String membershipLabel;
  final String billingPeriod;
  final String paymentMethod;
  final String amountLabel;
  final String footerMessage;
  final String? referenceNumber;
  final String? gymPhone;
  final String? gymAddress;

  /// The gym's brand colours and which layout to draw. Defaulted so every
  /// existing caller and test keeps rendering the classic crimson receipt
  /// without being changed.
  final BrandingConfig branding;

  /// The gym's logo, already read and validated, or null when none is set.
  ///
  /// Passed as bytes rather than a path so the renderer stays a pure function
  /// of its input — it does no file IO, which is what keeps `buildPdf`
  /// unit-testable without a filesystem.
  final Uint8List? logoBytes;
}

/// The colours one receipt is drawn with.
///
/// Derived from the active [ThemePreset] so a receipt matches the app the owner
/// is looking at. The surfaces stay dark, as the gym's existing receipts are —
/// only the brand accents move — so a receipt sent today sits consistently
/// beside one sent last year in the Receipts screen.
class _ReceiptPalette {
  _ReceiptPalette(ThemePreset preset)
      : brand = _toPdf(preset.primary),
        onBrand = _toPdf(preset.onAccent),
        brandText = _toPdf(preset.accentText),
        ink = _toPdf(preset.backgroundDark),
        surface = _toPdf(preset.surfaceDark);

  final PdfColor brand;

  /// What reads on top of [brand] — black for the bright brands, white for the
  /// dark ones. The whole reason [ThemePreset.onAccent] exists.
  final PdfColor onBrand;

  /// The brand as text on a dark surface, which [brand] itself is often too
  /// dark to serve as.
  final PdfColor brandText;

  final PdfColor ink;
  final PdfColor surface;

  // Borders, body text and the PAID badge are brand-independent: a receipt's
  // readability should not depend on which colour the gym picked, and green
  // means paid in every theme.
  static const border = PdfColor.fromInt(0xFF26262D);
  static const text = PdfColor.fromInt(0xFFF5F5F7);
  static const muted = PdfColor.fromInt(0xFF8B8B98);
  static const paid = PdfColor.fromInt(0xFF4ADE80);
  static const paidBg = PdfColor.fromInt(0xFF14311F);

  static PdfColor _toPdf(Color c) => PdfColor.fromInt(c.toARGB32());
}

class RenderedReceipt {
  const RenderedReceipt({required this.pdf, required this.png});

  final Uint8List pdf;
  final Uint8List png;
}

// Phone-shaped so it fills the frame when opened in WhatsApp.
const _pageWidth = 360.0;
const _pageHeight = 640.0;

// The receipt's colours moved into _ReceiptPalette, which derives the brand
// ones from the gym's chosen theme. Surfaces and body text kept their values.

/// Builds the receipt once as a PDF, then rasterises that same page to PNG.
///
/// Deriving both outputs from one layout means the image sent over WhatsApp and
/// the PDF the owner files away can never drift apart.
class ReceiptRenderer {
  Future<RenderedReceipt> render(ReceiptData data) async {
    final pdfBytes = await buildPdf(data);
    final png = await rasterise(pdfBytes);
    return RenderedReceipt(pdf: pdfBytes, png: png);
  }

  /// Pure PDF generation — no platform channels, so this is unit testable.
  ///
  /// The three templates differ in their header and amount treatment only. The
  /// field list, the page size and the dark surface are shared, so whichever
  /// the gym picks, a receipt still carries exactly the same information and
  /// still reads in a WhatsApp thread.
  Future<Uint8List> buildPdf(ReceiptData data) async {
    final doc = pw.Document();
    final palette = _ReceiptPalette(data.branding.effectivePreset);
    final logo = data.logoBytes == null
        ? null
        : pw.MemoryImage(data.logoBytes!);

    doc.addPage(
      pw.Page(
        pageFormat: const PdfPageFormat(_pageWidth, _pageHeight),
        build: (context) => pw.Container(
          color: palette.ink,
          padding: const pw.EdgeInsets.all(24),
          // Expanded/Spacer are avoided here: nested flex inside a fixed-size
          // PDF page makes children grow to fill the page rather than hug their
          // content, which silently swallows the whole layout.
          child: pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Column(
                mainAxisSize: pw.MainAxisSize.min,
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  _header(data, palette, logo),
                  pw.SizedBox(height: 14),
                  if (data.branding.receiptTemplate != ReceiptTemplate.modern)
                    pw.Container(
                      height: 1,
                      color: data.branding.receiptTemplate ==
                              ReceiptTemplate.minimal
                          ? _ReceiptPalette.border
                          : palette.brand,
                    ),
                  pw.SizedBox(height: 14),
                  _field('RECEIPT NO', data.receiptNumber),
                  _field('DATE', data.paymentDate),
                  _field('MEMBER', '${data.memberName}  (#${data.memberCode})'),
                  _field('MEMBERSHIP', data.membershipLabel),
                  _field('BILLING PERIOD', data.billingPeriod),
                  _field('PAYMENT METHOD', data.paymentMethod),
                  if (data.referenceNumber != null &&
                      data.referenceNumber!.trim().isNotEmpty)
                    _field('REFERENCE NO', data.referenceNumber!),
                ],
              ),
              _amountBlock(
                data.amountLabel,
                palette,
                data.branding.receiptTemplate,
              ),
              pw.Column(
                mainAxisSize: pw.MainAxisSize.min,
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.Container(height: 1, color: _ReceiptPalette.border),
                  pw.SizedBox(height: 12),
                  _footer(data, palette),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    return doc.save();
  }

  /// Converts the PDF to a PNG. Uses the platform rasteriser, so it only works
  /// inside a running app (not a plain unit test).
  Future<Uint8List> rasterise(Uint8List pdfBytes, {double dpi = 150}) async {
    await for (final page in Printing.raster(pdfBytes, dpi: dpi)) {
      return page.toPng();
    }
    throw StateError('The receipt PDF produced no pages to rasterise.');
  }

  /// The gym's mark and name.
  ///
  /// `classic` keeps the centred stack the gym's existing receipts use.
  /// `modern` fills a band with the brand colour — the one place a receipt
  /// carries the brand as a surface rather than as an accent, which is why
  /// [_ReceiptPalette.onBrand] matters: on the Gold or Emerald presets, white
  /// text in this band would be unreadable.
  /// `minimal` left-aligns and drops the colour entirely.
  pw.Widget _header(
    ReceiptData data,
    _ReceiptPalette palette,
    pw.MemoryImage? logo,
  ) {
    switch (data.branding.receiptTemplate) {
      case ReceiptTemplate.modern:
        return pw.Container(
          decoration: pw.BoxDecoration(
            color: palette.brand,
            borderRadius: pw.BorderRadius.circular(10),
          ),
          padding: const pw.EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              if (logo != null) ...[
                // Height-constrained so a tall logo cannot push the fields off
                // a fixed-height page; the aspect ratio is preserved by the
                // image widget itself, never stretched.
                pw.Image(logo, height: 34, fit: pw.BoxFit.contain),
                pw.SizedBox(height: 8),
              ],
              pw.Text(
                data.gymName.toUpperCase(),
                style: pw.TextStyle(
                  color: palette.onBrand,
                  fontSize: 17,
                  fontWeight: pw.FontWeight.bold,
                  letterSpacing: 1.4,
                ),
                textAlign: pw.TextAlign.center,
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'PAYMENT RECEIPT',
                style: pw.TextStyle(
                  color: palette.onBrand,
                  fontSize: 9,
                  letterSpacing: 2.5,
                ),
              ),
            ],
          ),
        );

      case ReceiptTemplate.minimal:
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            if (logo != null) ...[
              pw.Image(logo, height: 26, fit: pw.BoxFit.contain),
              pw.SizedBox(height: 10),
            ],
            pw.Text(
              data.gymName,
              style: pw.TextStyle(
                color: _ReceiptPalette.text,
                fontSize: 16,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 0.2,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Payment receipt',
              style: const pw.TextStyle(
                  color: _ReceiptPalette.muted, fontSize: 10),
            ),
          ],
        );

      case ReceiptTemplate.classic:
        return pw.Column(
          children: [
            if (logo != null) ...[
              pw.Image(logo, height: 32, fit: pw.BoxFit.contain),
              pw.SizedBox(height: 10),
            ],
            pw.Text(
              data.gymName.toUpperCase(),
              style: pw.TextStyle(
                color: _ReceiptPalette.text,
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 1.5,
              ),
              textAlign: pw.TextAlign.center,
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              'PAYMENT RECEIPT',
              style: pw.TextStyle(
                  color: palette.brandText, fontSize: 10, letterSpacing: 3),
            ),
          ],
        );
    }
  }

  pw.Widget _field(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 10),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(label,
                style: pw.TextStyle(
                    color: _ReceiptPalette.muted, fontSize: 7, letterSpacing: 1)),
            pw.SizedBox(height: 2),
            pw.Text(value,
                style: const pw.TextStyle(
                    color: _ReceiptPalette.text, fontSize: 12)),
          ],
        ),
      );

  /// The headline figure.
  ///
  /// `minimal` drops the panel and rules the amount off with a hairline
  /// instead; the other two keep the raised panel. The amount itself is always
  /// the brand colour as *text* ([_ReceiptPalette.brandText]) rather than the
  /// raw brand, which on the darker presets would barely separate from the
  /// panel behind it.
  pw.Widget _amountBlock(
    String amountLabel,
    _ReceiptPalette palette,
    ReceiptTemplate template,
  ) =>
      pw.Container(
        decoration: template == ReceiptTemplate.minimal
            // Hairline rules above and below, no panel. No borderRadius here:
            // the pdf package asserts a radius is only valid on a *uniform*
            // border, and a top/bottom-only border with one crashes the render.
            ? const pw.BoxDecoration(
                border: pw.Border(
                  top: pw.BorderSide(color: _ReceiptPalette.border),
                  bottom: pw.BorderSide(color: _ReceiptPalette.border),
                ),
              )
            : pw.BoxDecoration(
                color: palette.surface,
                borderRadius: pw.BorderRadius.circular(10),
              ),
        padding: const pw.EdgeInsets.symmetric(vertical: 16),
        child: pw.Column(
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            pw.Text('AMOUNT PAID',
                style: pw.TextStyle(
                    color: _ReceiptPalette.muted, fontSize: 8, letterSpacing: 2)),
            pw.SizedBox(height: 4),
            pw.Text(
              amountLabel,
              style: pw.TextStyle(
                  color: palette.brandText,
                  fontSize: 26,
                  fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 10),
            // Wrapped so the pill hugs its label instead of stretching to the
            // full width of the card.
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                pw.Container(
                  decoration: pw.BoxDecoration(
                    color: _ReceiptPalette.paidBg,
                    // Not 999: unlike Flutter, the pdf package does not clamp
                    // the radius to half the height, and an oversized value
                    // paints a huge shape over the rest of the page.
                    borderRadius: pw.BorderRadius.circular(9),
                  ),
                  padding: const pw.EdgeInsets.symmetric(
                      horizontal: 14, vertical: 5),
                  child: pw.Text('PAID',
                      style: pw.TextStyle(
                          color: _ReceiptPalette.paid,
                          fontSize: 9,
                          letterSpacing: 2,
                          fontWeight: pw.FontWeight.bold)),
                ),
              ],
            ),
          ],
        ),
      );

  pw.Widget _footer(ReceiptData data, _ReceiptPalette palette) => pw.Column(
        children: [
          pw.Text(data.footerMessage,
              style: const pw.TextStyle(
                  color: _ReceiptPalette.text, fontSize: 9),
              textAlign: pw.TextAlign.center),
          if (data.gymPhone != null) ...[
            pw.SizedBox(height: 4),
            pw.Text(data.gymPhone!,
                style: const pw.TextStyle(
                    color: _ReceiptPalette.muted, fontSize: 8)),
          ],
          if (data.gymAddress != null) ...[
            pw.SizedBox(height: 2),
            pw.Text(data.gymAddress!,
                style: const pw.TextStyle(
                    color: _ReceiptPalette.muted, fontSize: 8),
                textAlign: pw.TextAlign.center),
          ],
        ],
      );
}
