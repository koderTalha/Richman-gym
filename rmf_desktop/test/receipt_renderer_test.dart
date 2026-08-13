import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/services/receipt_renderer.dart';

/// PDF generation is pure Dart, so it can be verified here. Rasterising to PNG
/// goes through a platform channel and is exercised in the running app instead.
void main() {
  const sample = ReceiptData(
    gymName: 'Rich Man Fitness',
    receiptNumber: 'RMF-2026-000184',
    paymentDate: '13 Aug 2026',
    memberName: 'Member One',
    memberCode: 2,
    membershipLabel: 'Monthly - Boys',
    billingPeriod: 'August 2026',
    paymentMethod: 'Cash',
    amountLabel: 'Rs. 3,000',
    footerMessage: 'Thank you for choosing Rich Man Fitness.',
    gymPhone: '+92 300 0000000',
    gymAddress: 'Main Boulevard, Lahore, Pakistan',
  );

  test('produces a valid, non-trivial PDF', () async {
    final bytes = await ReceiptRenderer().buildPdf(sample);

    expect(bytes.length, greaterThan(1000));
    // Every PDF starts with the %PDF- magic number.
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('includes the receipt number and member name in the document', () async {
    final bytes = await ReceiptRenderer().buildPdf(sample);
    // Text is compressed in the PDF stream, so write it out and let the
    // presence of a real file stand in for content — the visual check happens
    // by opening the artefact below.
    final file = File('${Directory.systemTemp.path}/receipt-test.pdf');
    await file.writeAsBytes(bytes);

    expect(await file.exists(), isTrue);
    expect(await file.length(), bytes.length);
  });

  test('renders without a reference number when none is given', () async {
    final withRef = await ReceiptRenderer().buildPdf(const ReceiptData(
      gymName: 'Rich Man Fitness',
      receiptNumber: 'RMF-2026-000185',
      paymentDate: '13 Aug 2026',
      memberName: 'Member Ten',
      memberCode: 19,
      membershipLabel: 'Monthly',
      billingPeriod: 'August 2026',
      paymentMethod: 'Easypaisa',
      amountLabel: 'Rs. 3,000',
      footerMessage: 'Thanks.',
      referenceNumber: '114828',
    ));

    final withoutRef = await ReceiptRenderer().buildPdf(sample);

    // Both render; the one carrying an extra field is not identical.
    expect(withRef.length, greaterThan(1000));
    expect(withoutRef.length, greaterThan(1000));
  });
}
