import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart' show Brightness;
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/services/receipt_renderer.dart';
import 'package:rich_man_fitness/theme/branding_config.dart';
import 'package:rich_man_fitness/theme/theme_preset.dart';

/// The Ticket receipt. Rasterising needs the platform, so these check the PDF;
/// set RECEIPT_DUMP_DIR to also write each case out for a visual check.
void main() {
  // The Ticket reads Manrope from the asset bundle.
  TestWidgetsFlutterBinding.ensureInitialized();

  const ticket = BrandingConfig(receiptTemplate: ReceiptTemplate.ticket);
  final renderer = ReceiptRenderer();
  final dumpDir = Platform.environment['RECEIPT_DUMP_DIR'];

  final logoPath = Platform.environment['RECEIPT_DUMP_LOGO'];
  final Uint8List? logo =
      logoPath == null ? null : File(logoPath).readAsBytesSync();

  ReceiptData data({
    Brightness brightness = Brightness.dark,
    BrandingConfig branding = ticket,
    String memberName = 'Member One',
    String billingPeriod = 'October 2026 (paid late)',
    String amountLabel = 'Rs. 2,500',
    String? reference,
  }) =>
      ReceiptData(
        gymName: 'Rich Man Fitness',
        receiptNumber: 'RMF-2026-000365',
        paymentDate: '05 Nov 2026',
        memberName: memberName,
        memberCode: 606,
        membershipLabel: 'Student Package',
        billingPeriod: billingPeriod,
        paymentMethod: 'Cash',
        amountLabel: amountLabel,
        referenceNumber: reference,
        footerMessage: 'Thank you for choosing Rich Man Fitness.',
        gymPhone: '+92 300 0000000',
        // Long enough to test the footer's shrink-to-fit.
        gymAddress: 'Plaza No. 00, Example Block, Main Boulevard Road, Lahore',
        branding: branding,
        logoBytes: logo,
        brightness: brightness,
      );

  Future<Uint8List> build(String name, ReceiptData d) async {
    final bytes = await renderer.buildPdf(d);
    if (dumpDir != null) {
      await File('$dumpDir/$name.pdf').writeAsBytes(bytes);
    }
    return bytes;
  }

  test('renders a valid PDF in dark and in light', () async {
    final dark = await build('dark', data());
    final light = await build('light', data(brightness: Brightness.light));

    for (final bytes in [dark, light]) {
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(bytes.length, greaterThan(10000),
          reason: 'Manrope is embedded, so a real page is well over 10 KB');
    }
    expect(dark, isNot(equals(light)),
        reason: 'the Ticket follows the app mode');
  });

  test('the page is the design canvas, 540 × 960 pt', () async {
    final text = String.fromCharCodes(await build('size', data()));
    expect(text, contains('/MediaBox[0 0 540 960]'));
  });

  test('every brand renders, in both modes', () async {
    for (final preset in ThemePreset.all) {
      for (final mode in Brightness.values) {
        final bytes = await build(
          'preset-${preset.id}-${mode.name}',
          data(
            brightness: mode,
            branding: BrandingConfig(
              presetId: preset.id,
              receiptTemplate: ReceiptTemplate.ticket,
            ),
          ),
        );
        expect(bytes.length, greaterThan(10000),
            reason: '${preset.name} / ${mode.name}');
      }
    }
  });

  test('long values and a seven-figure amount still lay out', () async {
    // A layout overflow in the pdf package throws during save, so finishing
    // is the assertion.
    final bytes = await build(
      'long',
      data(
        memberName: 'Test Member With An Unusually Long Full Name Here',
        amountLabel: 'Rs. 1,000,000',
        billingPeriod: 'October 2026 – March 2027 (paid in advance)',
        reference: 'TXN-0099887766554433',
      ),
    );
    expect(bytes.length, greaterThan(10000));
  });

  test('on-time payments and a reference number render', () async {
    final bytes = await build(
      'reference',
      data(billingPeriod: 'November 2026', reference: '114828'),
    );
    expect(bytes.length, greaterThan(10000));
  });

  test('the stored theme mode maps to the receipt brightness', () {
    expect(ReceiptData.brightnessFor('light'), Brightness.light);
    expect(ReceiptData.brightnessFor('dark'), Brightness.dark);
    // Unknown or missing is dark, as the app reads the same column.
    expect(ReceiptData.brightnessFor(null), Brightness.dark);
    expect(ReceiptData.brightnessFor('system'), Brightness.dark);
  });
}
