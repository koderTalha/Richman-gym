import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

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
}

class RenderedReceipt {
  const RenderedReceipt({required this.pdf, required this.png});

  final Uint8List pdf;
  final Uint8List png;
}

// Phone-shaped so it fills the frame when opened in WhatsApp.
const _pageWidth = 360.0;
const _pageHeight = 640.0;

const _ink = PdfColor.fromInt(0xFF0B0B0D);
const _surface = PdfColor.fromInt(0xFF17171B);
const _border = PdfColor.fromInt(0xFF26262D);
const _text = PdfColor.fromInt(0xFFF5F5F7);
const _muted = PdfColor.fromInt(0xFF8B8B98);
const _crimson = PdfColor.fromInt(0xFFE11D2E);
const _paid = PdfColor.fromInt(0xFF4ADE80);
const _paidBg = PdfColor.fromInt(0xFF14311F);

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
  Future<Uint8List> buildPdf(ReceiptData data) async {
    final doc = pw.Document();

    doc.addPage(
      pw.Page(
        pageFormat: const PdfPageFormat(_pageWidth, _pageHeight),
        build: (context) => pw.Container(
          color: _ink,
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
                  _header(data),
                  pw.SizedBox(height: 14),
                  pw.Container(height: 1, color: _border),
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
              _amountBlock(data.amountLabel),
              pw.Column(
                mainAxisSize: pw.MainAxisSize.min,
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.Container(height: 1, color: _border),
                  pw.SizedBox(height: 12),
                  _footer(data),
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

  pw.Widget _header(ReceiptData data) => pw.Column(
        children: [
          pw.Text(
            data.gymName.toUpperCase(),
            style: pw.TextStyle(
              color: _text,
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
                color: _crimson, fontSize: 10, letterSpacing: 3),
          ),
        ],
      );

  pw.Widget _field(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 10),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(label,
                style: pw.TextStyle(
                    color: _muted, fontSize: 7, letterSpacing: 1)),
            pw.SizedBox(height: 2),
            pw.Text(value, style: const pw.TextStyle(color: _text, fontSize: 12)),
          ],
        ),
      );

  pw.Widget _amountBlock(String amountLabel) => pw.Container(
        decoration: pw.BoxDecoration(
          color: _surface,
          borderRadius: pw.BorderRadius.circular(10),
        ),
        padding: const pw.EdgeInsets.symmetric(vertical: 16),
        child: pw.Column(
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            pw.Text('AMOUNT PAID',
                style: pw.TextStyle(
                    color: _muted, fontSize: 8, letterSpacing: 2)),
            pw.SizedBox(height: 4),
            pw.Text(
              amountLabel,
              style: pw.TextStyle(
                  color: _crimson, fontSize: 26, fontWeight: pw.FontWeight.bold),
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
                    color: _paidBg,
                    // Not 999: unlike Flutter, the pdf package does not clamp
                    // the radius to half the height, and an oversized value
                    // paints a huge shape over the rest of the page.
                    borderRadius: pw.BorderRadius.circular(9),
                  ),
                  padding: const pw.EdgeInsets.symmetric(
                      horizontal: 14, vertical: 5),
                  child: pw.Text('PAID',
                      style: pw.TextStyle(
                          color: _paid,
                          fontSize: 9,
                          letterSpacing: 2,
                          fontWeight: pw.FontWeight.bold)),
                ),
              ],
            ),
          ],
        ),
      );

  pw.Widget _footer(ReceiptData data) => pw.Column(
        children: [
          pw.Text(data.footerMessage,
              style: const pw.TextStyle(color: _text, fontSize: 9),
              textAlign: pw.TextAlign.center),
          if (data.gymPhone != null) ...[
            pw.SizedBox(height: 4),
            pw.Text(data.gymPhone!,
                style: const pw.TextStyle(color: _muted, fontSize: 8)),
          ],
          if (data.gymAddress != null) ...[
            pw.SizedBox(height: 2),
            pw.Text(data.gymAddress!,
                style: const pw.TextStyle(color: _muted, fontSize: 8),
                textAlign: pw.TextAlign.center),
          ],
        ],
      );
}
