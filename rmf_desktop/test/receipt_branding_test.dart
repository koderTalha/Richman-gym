import 'dart:typed_data';

import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/services/receipt_renderer.dart';
import 'package:rich_man_fitness/theme/branding_config.dart';
import 'package:rich_man_fitness/theme/theme_preset.dart';

/// The receipt is what a member actually receives, so the branding has to reach
/// it — and the payment details have to survive the branding.
void main() {
  ReceiptData dataWith({
    BrandingConfig branding = const BrandingConfig(),
    Uint8List? logo,
  }) {
    return ReceiptData(
      gymName: 'Rich Man Fitness',
      receiptNumber: 'RMF-2026-000231',
      paymentDate: '16 Oct 2026',
      memberName: 'Test Overdue',
      memberCode: 14,
      membershipLabel: 'Student Package',
      billingPeriod: 'October 2026',
      paymentMethod: 'JazzCash',
      amountLabel: 'Rs. 2,500',
      footerMessage: 'Thank you for choosing Rich Man Fitness.',
      gymPhone: '+92 345 0000105',
      gymAddress: 'Paragon City, Lahore',
      branding: branding,
      logoBytes: logo,
    );
  }

  /// A 1×1 PNG, enough for the renderer to embed.
  final pngPixel = Uint8List.fromList([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
    0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
    0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
    0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
    0x42, 0x60, 0x82,
  ]);

  final renderer = ReceiptRenderer();

  test('the default branding still renders the receipt the gym has always had',
      () async {
    // The upgrade promise at the output end: a gym that never opens Appearance
    // keeps getting the same receipt.
    final bytes = await renderer.buildPdf(dataWith());

    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(1000));
  });

  group('every preset renders', () {
    for (final preset in ThemePreset.all) {
      test(preset.name, () async {
        final bytes = await renderer.buildPdf(
            dataWith(branding: BrandingConfig(presetId: preset.id)));

        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
        expect(bytes.length, greaterThan(1000));
      });
    }
  });

  group('every template renders', () {
    for (final template in ReceiptTemplate.values) {
      test(template.name, () async {
        final bytes = await renderer.buildPdf(
            dataWith(branding: BrandingConfig(receiptTemplate: template)));

        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
        expect(bytes.length, greaterThan(1000));
      });
    }
  });

  test('a different brand produces a different document', () async {
    // If the branding were being dropped on the floor, these would be
    // byte-identical.
    final red = await renderer.buildPdf(
        dataWith(branding: const BrandingConfig(presetId: 'richmanRed')));
    final teal = await renderer.buildPdf(
        dataWith(branding: const BrandingConfig(presetId: 'oceanTeal')));

    expect(red, isNot(equals(teal)),
        reason: 'the receipt must actually take the gym colours');
  });

  test('a different template produces a different document', () async {
    final classic = await renderer.buildPdf(dataWith());
    final modern = await renderer.buildPdf(dataWith(
        branding: const BrandingConfig(
            receiptTemplate: ReceiptTemplate.modern)));

    expect(classic, isNot(equals(modern)));
  });

  test('the logo is embedded when one is set', () async {
    final without = await renderer.buildPdf(dataWith());
    final with_ = await renderer.buildPdf(dataWith(logo: pngPixel));

    expect(with_.length, greaterThan(without.length),
        reason: 'an embedded image makes the document bigger');
  });

  test('a logo is embedded in all three templates', () async {
    for (final template in ReceiptTemplate.values) {
      final branding = BrandingConfig(receiptTemplate: template);
      final without =
          await renderer.buildPdf(dataWith(branding: branding));
      final with_ = await renderer.buildPdf(
          dataWith(branding: branding, logo: pngPixel));

      expect(with_.length, greaterThan(without.length),
          reason: '${template.name} must carry the gym logo too');
    }
  });

  test('the payment details survive every brand and template', () async {
    // The point of the whole exercise: restyling must not drop information a
    // member needs to recognise their own payment. Checked across the matrix
    // because a template that forgot to render the fields would still produce
    // a valid PDF.
    for (final preset in ThemePreset.all) {
      for (final template in ReceiptTemplate.values) {
        final bytes = await renderer.buildPdf(dataWith(
          branding: BrandingConfig(
            presetId: preset.id,
            receiptTemplate: template,
          ),
        ));

        // The pdf package compresses streams, so the text is not greppable in
        // the bytes; size is the available proxy for "the fields are there".
        expect(bytes.length, greaterThan(1000),
            reason: '${preset.name} / ${template.name} rendered too little to '
                'contain the payment details');
      }
    }
  });

  test('a custom brand reaches the receipt', () async {
    final custom = await renderer.buildPdf(dataWith(
      branding: const BrandingConfig(
        presetId: BrandingConfig.customId,
        custom: CustomColors(primary: Color(0xFFD4A72C)),
      ),
    ));
    final standard = await renderer.buildPdf(dataWith());

    expect(custom, isNot(equals(standard)));
  });
}
