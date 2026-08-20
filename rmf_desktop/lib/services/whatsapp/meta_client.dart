import 'dart:convert';

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
      final mediaId = await _uploadMedia(input);
      return await _sendImage(input, mediaId);
    } catch (e, s) {
      _log.severe('WhatsApp send failed', e, s);
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

  Future<String> _uploadMedia(WhatsAppSendInput input) async {
    final request = http.MultipartRequest('POST', _uri('media'))
      ..headers['Authorization'] = 'Bearer $accessToken'
      ..fields['messaging_product'] = 'whatsapp'
      ..fields['type'] = '$_receiptMediaType'
      // The part itself must carry the type too. Left off, multipart defaults
      // to application/octet-stream and Meta rejects the upload with error 100
      // even though the `type` field above is correct.
      ..files.add(http.MultipartFile.fromBytes(
        'file',
        input.imageBytes,
        filename: input.fileName,
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
  ) async {
    final response = await _http.post(
      _uri('messages'),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'messaging_product': 'whatsapp',
        'recipient_type': 'individual',
        // Meta expects the number without the leading "+".
        'to': input.to.replaceFirst(RegExp(r'^\+'), ''),
        'type': 'image',
        'image': {'id': mediaId, 'caption': input.caption},
      }),
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

  String? _errorMessage(Map<String, dynamic> body) {
    final error = body['error'];
    if (error is Map<String, dynamic>) return error['message'] as String?;
    return null;
  }
}
