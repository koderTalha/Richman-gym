import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rich_man_fitness/services/whatsapp/meta_client.dart';
import 'package:rich_man_fitness/services/whatsapp/whatsapp_client.dart';

/// The welcome message goes out as a plain text message, which is a different
/// Meta message type from the receipt image and has its own envelope.
void main() {
  late List<http.Request> requests;

  MetaWhatsAppClient clientAnswering(String body, {int status = 200}) {
    requests = [];
    return MetaWhatsAppClient(
      phoneNumberId: '1234567890',
      accessToken: 'a-token-that-must-never-be-logged',
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response(body, status);
      }),
    );
  }

  const ok = '{"messages":[{"id":"wamid.text.1"}]}';

  test('posts a text message with the body it was given', () async {
    final result = await clientAnswering(ok).sendText(
      const WhatsAppTextInput(to: '+923000000022', body: 'Welcome!'),
    );

    expect(result, isA<WhatsAppSendSuccess>());
    expect((result as WhatsAppSendSuccess).externalMessageId, 'wamid.text.1');

    final sent = jsonDecode(requests.single.body) as Map<String, dynamic>;
    expect(sent['messaging_product'], 'whatsapp');
    expect(sent['type'], 'text');
    expect((sent['text'] as Map)['body'], 'Welcome!');
    expect((sent['text'] as Map)['preview_url'], false);
  });

  test('strips the leading + Meta will not accept', () async {
    await clientAnswering(ok).sendText(
      const WhatsAppTextInput(to: '+923000000022', body: 'hi'),
    );

    final sent = jsonDecode(requests.single.body) as Map<String, dynamic>;
    expect(sent['to'], '923000000022');
  });

  test('reports Meta\'s own reason for a refusal', () async {
    // What Meta answers outside the 24-hour customer service window.
    final result = await clientAnswering(
      '{"error":{"message":"Message failed to send because more than 24 hours '
      'have passed since the customer last replied","code":131047}}',
      status: 400,
    ).sendText(const WhatsAppTextInput(to: '+923000000022', body: 'hi'));

    expect(result, isA<WhatsAppSendFailure>());
    expect((result as WhatsAppSendFailure).error, contains('24 hours'));
    expect(result.error, isNot(contains('a-token-that-must-never-be-logged')));
  });

  test('a 200 with no message id is still a failure', () async {
    final result = await clientAnswering('{"messages":[]}').sendText(
      const WhatsAppTextInput(to: '+923000000022', body: 'hi'),
    );

    expect(result, isA<WhatsAppSendFailure>());
  });

  test('a body that is not JSON is reported, not thrown', () async {
    final result = await clientAnswering('<html>502</html>', status: 502)
        .sendText(const WhatsAppTextInput(to: '+923000000022', body: 'hi'));

    expect(result, isA<WhatsAppSendFailure>());
  });

  test('the token travels in the header, never in the body', () async {
    await clientAnswering(ok).sendText(
      const WhatsAppTextInput(to: '+923000000022', body: 'hi'),
    );

    expect(requests.single.headers['Authorization'],
        'Bearer a-token-that-must-never-be-logged');
    expect(requests.single.body,
        isNot(contains('a-token-that-must-never-be-logged')));
  });
}
