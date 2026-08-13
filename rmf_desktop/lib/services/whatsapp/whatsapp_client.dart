import 'dart:typed_data';

import '../../data/database.dart';

class WhatsAppSendInput {
  const WhatsAppSendInput({
    required this.to,
    required this.caption,
    required this.imageBytes,
    required this.fileName,
  });

  /// Recipient in E.164 form, e.g. +923000000022.
  final String to;
  final String caption;
  final Uint8List imageBytes;
  final String fileName;
}

sealed class WhatsAppSendResult {
  const WhatsAppSendResult();
}

class WhatsAppSendSuccess extends WhatsAppSendResult {
  const WhatsAppSendSuccess(this.externalMessageId);
  final String externalMessageId;
}

class WhatsAppSendFailure extends WhatsAppSendResult {
  const WhatsAppSendFailure(this.error);
  final String error;
}

abstract class WhatsAppClient {
  WhatsAppProviderKind get kind;
  Future<WhatsAppSendResult> send(WhatsAppSendInput input);
}

/// Provider configuration, reported to the UI without ever exposing the token.
class WhatsAppConfig {
  const WhatsAppConfig({
    required this.kind,
    this.phoneNumberId,
    this.accessToken,
  });

  final WhatsAppProviderKind kind;
  final String? phoneNumberId;
  final String? accessToken;

  bool get isConfigured {
    if (kind != WhatsAppProviderKind.meta) return true;
    return (phoneNumberId?.isNotEmpty ?? false) &&
        (accessToken?.isNotEmpty ?? false);
  }

  List<String> get missing {
    if (kind != WhatsAppProviderKind.meta) return const [];
    return [
      if (phoneNumberId?.isEmpty ?? true) 'Phone number ID',
      if (accessToken?.isEmpty ?? true) 'Access token',
    ];
  }

  /// Safe to render; the token itself is never surfaced.
  String? get maskedPhoneNumberId {
    final id = phoneNumberId;
    if (id == null || id.length < 4) return null;
    return '••••${id.substring(id.length - 4)}';
  }
}
