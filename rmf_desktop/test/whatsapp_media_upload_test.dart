import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rich_man_fitness/services/whatsapp/meta_client.dart';
import 'package:rich_man_fitness/services/whatsapp/whatsapp_client.dart';

void main() {
  test('media upload declares the image MIME type on the file part', () async {
    final requests = <http.Request>[];

    final client = MetaWhatsAppClient(
      phoneNumberId: '1234567890',
      accessToken: 'token',
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/media')) {
          return http.Response(jsonEncode({'id': 'MEDIA-1'}), 200);
        }
        return http.Response(
          jsonEncode({
            'messages': [
              {'id': 'wamid.1'},
            ],
          }),
          200,
        );
      }),
    );

    final result = await client.send(WhatsAppSendInput(
      to: '+923000000022',
      caption: 'Receipt',
      imageBytes: Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]),
      fileName: 'RMF-0001.png',
    ));

    expect(result, isA<WhatsAppSendSuccess>());

    final upload = requests.firstWhere((r) => r.url.path.endsWith('/media'));
    final body = latin1.decode(upload.bodyBytes).toLowerCase();

    // Meta rejects the upload with error #100 unless the "file" part itself
    // carries an accepted content type; the multipart default is octet-stream.
    expect(body, contains('content-type: image/png'));
    expect(body, isNot(contains('application/octet-stream')));
  });
}
