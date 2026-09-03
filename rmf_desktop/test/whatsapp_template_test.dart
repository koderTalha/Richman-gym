import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rich_man_fitness/services/whatsapp/message_texts.dart';
import 'package:rich_man_fitness/services/whatsapp/meta_client.dart';
import 'package:rich_man_fitness/services/whatsapp/whatsapp_client.dart';

/// The payload a receipt travels in.
///
/// These assertions are the contract with the template approved in Meta's
/// Business Manager, and they are checked here rather than discovered in
/// production because the API answers a malformed template send with HTTP 200
/// and a message id, and only declines to deliver it. Nothing downstream of
/// this file would notice.
void main() {
  /// Returns the decoded body of the POST to /messages.
  Future<Map<String, dynamic>> sendAndCapture(
    WhatsAppTemplateInput input, {
    http.Response Function(http.Request)? messagesResponse,
  }) async {
    final requests = <http.Request>[];

    final client = MetaWhatsAppClient(
      phoneNumberId: '1234567890',
      accessToken: 'token',
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/media')) {
          return http.Response(jsonEncode({'id': 'MEDIA-42'}), 200);
        }
        return messagesResponse?.call(request) ??
            http.Response(
              jsonEncode({
                'messages': [
                  {'id': 'wamid.1'},
                ],
              }),
              200,
            );
      }),
    );

    await client.sendTemplate(input);

    final post = requests.firstWhere((r) => r.url.path.endsWith('/messages'));
    return jsonDecode(post.body) as Map<String, dynamic>;
  }

  WhatsAppTemplateInput receipt({
    String memberName = 'Ali Raza',
    List<int>? image,
  }) =>
      WhatsAppTemplateInput(
        to: '+923000000022',
        templateName: 'payment_receipt',
        languageCode: 'en',
        bodyParams: receiptTemplateParams(
          memberName: memberName,
          amountLabel: 'PKR 3,000',
          periodLabel: 'September 2026',
          receiptNumber: 'RMF-2026-000001',
        ),
        headerImageBytes:
            image == null ? null : Uint8List.fromList(image),
        headerImageFileName: 'RMF-2026-000001.png',
      );

  test('a receipt is sent as a template, naming the approved template and '
      'its language', () async {
    final body = await sendAndCapture(receipt(image: [0x89, 0x50]));

    expect(body['type'], 'template');
    // Not '+923000000022': Meta expects the number without the leading plus.
    expect(body['to'], '923000000022');

    final template = body['template'] as Map<String, dynamic>;
    expect(template['name'], 'payment_receipt');
    // en and en_US are different templates as far as Meta is concerned.
    expect((template['language'] as Map)['code'], 'en');
  });

  test('the header carries the media id the receipt image was uploaded as',
      () async {
    final body = await sendAndCapture(receipt(image: [0x89, 0x50]));

    final components =
        (body['template'] as Map)['components'] as List<dynamic>;
    final header = components.firstWhere((c) => c['type'] == 'header')
        as Map<String, dynamic>;
    final parameter = (header['parameters'] as List).single as Map;

    expect(parameter['type'], 'image');
    // The id from the /media upload, not the bytes: a template header cannot
    // carry an image inline.
    expect((parameter['image'] as Map)['id'], 'MEDIA-42');
  });

  test('the body parameters fill the placeholders in the approved order',
      () async {
    final body = await sendAndCapture(receipt(image: [0x89, 0x50]));

    final components =
        (body['template'] as Map)['components'] as List<dynamic>;
    final bodyComponent = components.firstWhere((c) => c['type'] == 'body')
        as Map<String, dynamic>;
    final values = (bodyComponent['parameters'] as List)
        .map((p) => (p as Map)['text'])
        .toList();

    // {{1}} name, {{2}} amount, {{3}} period, {{4}} receipt number. Reordering
    // these silently sends the member someone else's numbers.
    expect(values, [
      'Ali Raza',
      'PKR 3,000',
      'September 2026',
      'RMF-2026-000001',
    ]);
  });

  test('a parameter containing newlines is flattened before it is sent',
      () async {
    // Meta rejects a parameter holding a newline, a tab, or four or more
    // consecutive spaces, and a hand-edited member row can hold any of them.
    final body =
        await sendAndCapture(receipt(memberName: ' Ali\n\tRaza    Khan '));

    final components =
        (body['template'] as Map)['components'] as List<dynamic>;
    final bodyComponent = components.firstWhere((c) => c['type'] == 'body')
        as Map<String, dynamic>;
    final name = ((bodyComponent['parameters'] as List).first as Map)['text'];

    expect(name, 'Ali Raza Khan');
  });

  test('a text-only template sends no header component', () async {
    final body = await sendAndCapture(receipt());

    final components =
        (body['template'] as Map)['components'] as List<dynamic>;
    expect(components.any((c) => c['type'] == 'header'), isFalse);
    expect(components.any((c) => c['type'] == 'body'), isTrue);
  });

  test('a rejected template is reported as a failure, not as a send',
      () async {
    final client = MetaWhatsAppClient(
      phoneNumberId: '1234567890',
      accessToken: 'token',
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/media')) {
          return http.Response(jsonEncode({'id': 'MEDIA-42'}), 200);
        }
        // What Meta answers when the name or language does not match an
        // approved template — the mistake this app can most easily make.
        return http.Response(
          jsonEncode({
            'error': {
              'message': 'Template name does not exist in the translation',
              'code': 132001,
            },
          }),
          400,
        );
      }),
    );

    final result = await client.sendTemplate(receipt(image: [0x89, 0x50]));

    expect(result, isA<WhatsAppSendFailure>());
    expect((result as WhatsAppSendFailure).error,
        contains('Template name does not exist'));
  });
}
