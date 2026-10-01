import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rich_man_fitness/services/whatsapp/meta_client.dart';
import 'package:rich_man_fitness/services/whatsapp/whatsapp_client.dart';

/// A call to Meta that never comes back.
///
/// `package:http` waits forever by default, and recording a payment awaits
/// its receipt send — so a half-open connection left the payment dialog
/// spinning after the payment itself had already been saved. Every call is
/// now bounded, and running out of time reads as a failure the owner can
/// understand rather than as silence.
void main() {
  const short = Duration(milliseconds: 50);

  /// Answers nothing, ever.
  MetaWhatsAppClient stalled() => MetaWhatsAppClient(
        phoneNumberId: '1234567890',
        accessToken: 'token',
        timeout: short,
        httpClient:
            MockClient((_) => Completer<http.Response>().future),
      );

  const template = WhatsAppTemplateInput(
    to: '+923000000022',
    templateName: 'payment_reminder',
    languageCode: 'en',
    bodyParams: ['Ali Raza'],
  );

  test('a template send that never answers fails, and says it timed out',
      () async {
    final result = await stalled().sendTemplate(template).timeout(
        const Duration(seconds: 5),
        onTimeout: () => fail('the client itself never gave up'));

    expect(result, isA<WhatsAppSendFailure>());
    expect((result as WhatsAppSendFailure).error, contains('did not answer'));
  });

  test('a receipt whose image upload stalls fails rather than hanging',
      () async {
    final result = await stalled()
        .sendTemplate(WhatsAppTemplateInput(
          to: '+923000000022',
          templateName: 'payment_receipt',
          languageCode: 'en',
          headerImageBytes: Uint8List.fromList([1, 2, 3]),
        ))
        .timeout(const Duration(seconds: 5),
            onTimeout: () => fail('the client itself never gave up'));

    expect(result, isA<WhatsAppSendFailure>());
  });

  test('a text send and a credential check are bounded too', () async {
    final client = stalled();
    final text = await client
        .sendText(const WhatsAppTextInput(to: '+923000000022', body: 'Hi'))
        .timeout(const Duration(seconds: 5),
            onTimeout: () => fail('the text send never gave up'));
    expect(text, isA<WhatsAppSendFailure>());

    final check = await client.verifyCredentials().timeout(
        const Duration(seconds: 5),
        onTimeout: () => fail('the credential check never gave up'));
    expect(check.ok, isFalse);
    expect(check.error, contains('did not answer'));
  });

  test('a dead connection is named as one', () async {
    final client = MetaWhatsAppClient(
      phoneNumberId: '1234567890',
      accessToken: 'token',
      httpClient: MockClient(
          (_) async => throw const SocketException('Network is unreachable')),
    );

    final result = await client.sendTemplate(template);
    expect((result as WhatsAppSendFailure).error,
        contains('Could not reach WhatsApp'));
  });

  test("Meta's own error text is still passed through", () async {
    final client = MetaWhatsAppClient(
      phoneNumberId: '1234567890',
      accessToken: 'token',
      httpClient: MockClient((_) async => http.Response(
          jsonEncode({
            'error': {'message': 'Template name does not exist'},
          }),
          400)),
    );

    final result = await client.sendTemplate(template);
    expect((result as WhatsAppSendFailure).error,
        'Template name does not exist');
  });
}
