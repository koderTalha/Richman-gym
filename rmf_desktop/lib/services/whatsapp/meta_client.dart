import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:logging/logging.dart';

import '../../data/database.dart';
import 'whatsapp_client.dart';

final _log = Logger('whatsapp');

const _graphVersion = 'v21.0';
final _receiptMediaType = MediaType('image', 'png');

/// Result of checking Meta credentials without sending a message.
class MetaVerification {
  const MetaVerification._({
    required this.ok,
    this.businessName,
    this.displayPhoneNumber,
    this.qualityRating,
    this.error,
  });

  factory MetaVerification.success({
    String? businessName,
    String? displayPhoneNumber,
    String? qualityRating,
  }) =>
      MetaVerification._(
        ok: true,
        businessName: businessName,
        displayPhoneNumber: displayPhoneNumber,
        qualityRating: qualityRating,
      );

  factory MetaVerification.failure(String error) =>
      MetaVerification._(ok: false, error: error);

  final bool ok;
  final String? businessName;
  final String? displayPhoneNumber;
  final String? qualityRating;
  final String? error;

  String get summary => ok
      ? [
          if (businessName != null) businessName,
          if (displayPhoneNumber != null) displayPhoneNumber,
        ].whereType<String>().join(' · ')
      : error ?? 'Unknown error';
}

/// Official Meta WhatsApp Business Cloud API client.
///
/// Sending an image takes two calls: upload the bytes to /media to get a media
/// id, then reference that id in /messages. That avoids needing the receipt to
/// be reachable at a public URL, which matters because this app runs locally on
/// the gym's own machine with no public address.
class MetaWhatsAppClient implements WhatsAppClient {
  MetaWhatsAppClient({
    required this.phoneNumberId,
    required this.accessToken,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final String phoneNumberId;
  final String accessToken;
  final http.Client _http;

  @override
  WhatsAppProviderKind get kind => WhatsAppProviderKind.meta;

  Uri _uri(String path) =>
      Uri.parse('https://graph.facebook.com/$_graphVersion/$phoneNumberId/$path');

  @override
  Future<WhatsAppSendResult> send(WhatsAppSendInput input) async {
    try {
      final mediaId = await _uploadMedia(input.imageBytes, input.fileName);
      return await _sendImage(input, mediaId);
    } catch (e, s) {
      _log.severe('WhatsApp send failed', e, s);
      return WhatsAppSendFailure('$e');
    }
  }

  /// One text message, no attachment.
  ///
  /// Meta only accepts free-form messages inside the 24-hour window that opens
  /// when the member last messaged the business; outside it the API answers
  /// with error 131047 and the message is not delivered. That is reported like
  /// any other send failure rather than hidden, because the alternative — a
  /// pre-approved message template — is something the owner has to create in
  /// Meta's Business Manager first, and nothing in this app can conjure one.
  @override
  Future<WhatsAppSendResult> sendText(WhatsAppTextInput input) async {
    try {
      return await _postMessage({
        'messaging_product': 'whatsapp',
        'recipient_type': 'individual',
        'to': _recipient(input.to),
        'type': 'text',
        // preview_url off: the welcome message is plain prose, and a link
        // preview card is not something the gym asked to send.
        'text': {'preview_url': false, 'body': input.body},
      });
    } catch (e, s) {
      _log.severe('WhatsApp text send failed', e, s);
      return WhatsAppSendFailure('$e');
    }
  }

  /// One template message.
  ///
  /// This is the path a receipt takes. Unlike [send] and [sendText] it does not
  /// depend on the member having messaged the gym recently: an approved
  /// template is the one thing Meta accepts for a conversation the business
  /// starts, and it is delivered whether or not a 24-hour window is open.
  ///
  /// A template whose header is an image needs the picture uploaded first, the
  /// same two-step dance a plain image message does — the sample Meta approved
  /// is only a sample, and the real receipt is supplied per send.
  @override
  Future<WhatsAppSendResult> sendTemplate(WhatsAppTemplateInput input) async {
    try {
      String? headerMediaId;
      if (input.hasHeaderImage) {
        headerMediaId = await _uploadMedia(
          input.headerImageBytes!,
          input.headerImageFileName ?? 'receipt.png',
        );
      }

      final components = <Map<String, Object?>>[
        if (headerMediaId != null)
          {
            'type': 'header',
            'parameters': [
              {'type': 'image', 'image': {'id': headerMediaId}},
            ],
          },
        if (input.bodyParams.isNotEmpty)
          {
            'type': 'body',
            'parameters': [
              for (final value in input.bodyParams)
                {'type': 'text', 'text': value},
            ],
          },
      ];

      return await _postMessage({
        'messaging_product': 'whatsapp',
        'recipient_type': 'individual',
        'to': _recipient(input.to),
        'type': 'template',
        'template': {
          'name': input.templateName,
          'language': {'code': input.languageCode},
          // Omitted entirely when empty: Meta rejects an empty components list
          // rather than reading it as "this template takes no parameters".
          if (components.isNotEmpty) 'components': components,
        },
      });
    } catch (e, s) {
      _log.severe('WhatsApp template send failed', e, s);
      return WhatsAppSendFailure('$e');
    }
  }

  /// Checks the credentials without sending anything, by reading the phone
  /// number's own record. Lets the owner confirm the values they pasted are
  /// correct before relying on them for real receipts.
  Future<MetaVerification> verifyCredentials() async {
    try {
      final response = await _http.get(
        Uri.parse('https://graph.facebook.com/$_graphVersion/$phoneNumberId'
            '?fields=verified_name,display_phone_number,quality_rating'),
        headers: {'Authorization': 'Bearer $accessToken'},
      );

      final body = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode != 200) {
        return MetaVerification.failure(
            _errorMessage(body) ?? 'HTTP ${response.statusCode}');
      }

      return MetaVerification.success(
        businessName: body['verified_name'] as String?,
        displayPhoneNumber: body['display_phone_number'] as String?,
        qualityRating: body['quality_rating'] as String?,
      );
    } catch (e, s) {
      _log.severe('WhatsApp credential check failed', e, s);
      return MetaVerification.failure('$e');
    }
  }

  Future<String> _uploadMedia(Uint8List bytes, String fileName) async {
    final request = http.MultipartRequest('POST', _uri('media'))
      ..headers['Authorization'] = 'Bearer $accessToken'
      ..fields['messaging_product'] = 'whatsapp'
      ..fields['type'] = '$_receiptMediaType'
      // The part itself must carry the type too. Left off, multipart defaults
      // to application/octet-stream and Meta rejects the upload with error 100
      // even though the `type` field above is correct.
      ..files.add(http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: fileName,
        contentType: _receiptMediaType,
      ));

    final response =
        await http.Response.fromStream(await _http.send(request));
    final body = jsonDecode(response.body) as Map<String, dynamic>;

    final id = body['id'] as String?;
    if (response.statusCode != 200 || id == null) {
      throw Exception(_errorMessage(body) ??
          'Media upload failed (HTTP ${response.statusCode})');
    }
    return id;
  }

  Future<WhatsAppSendResult> _sendImage(
    WhatsAppSendInput input,
    String mediaId,
  ) =>
      _postMessage({
        'messaging_product': 'whatsapp',
        'recipient_type': 'individual',
        'to': _recipient(input.to),
        'type': 'image',
        'image': {'id': mediaId, 'caption': input.caption},
      });

  /// Posts one message payload to /messages and reads the id back out of it.
  ///
  /// Shared by every message type: the envelope, the error handling and the
  /// "a 200 without a message id is still a failure" rule are the same whether
  /// what is being sent is a receipt image or a line of text.
  Future<WhatsAppSendResult> _postMessage(Map<String, Object?> payload) async {
    final response = await _http.post(
      _uri('messages'),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(payload),
    );

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final messages = body['messages'] as List<dynamic>?;
    final messageId = messages == null || messages.isEmpty
        ? null
        : (messages.first as Map<String, dynamic>)['id'] as String?;

    if (response.statusCode != 200 || messageId == null) {
      return WhatsAppSendFailure(_errorMessage(body) ??
          'Send failed (HTTP ${response.statusCode})');
    }
    return WhatsAppSendSuccess(messageId);
  }

  /// Meta expects the number without the leading "+".
  static String _recipient(String e164) =>
      e164.replaceFirst(RegExp(r'^\+'), '');

  String? _errorMessage(Map<String, dynamic> body) {
    final error = body['error'];
    if (error is Map<String, dynamic>) return error['message'] as String?;
    return null;
  }
}
