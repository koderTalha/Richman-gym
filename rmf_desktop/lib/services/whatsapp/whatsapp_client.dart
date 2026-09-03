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

/// A message with no attachment — the welcome note a new member is sent.
///
/// Separate from [WhatsAppSendInput] rather than an image input with empty
/// bytes: Meta treats the two as different message types, and a provider that
/// cannot send one must not be able to silently send the other.
class WhatsAppTextInput {
  const WhatsAppTextInput({required this.to, required this.body});

  /// Recipient in E.164 form, e.g. +923000000022.
  final String to;
  final String body;
}

/// A pre-approved message template, which is the only thing Meta accepts for a
/// conversation the business starts.
///
/// Free-form text and images are limited to the 24-hour window that opens when
/// the member last messaged the gym. A receipt is sent the moment a payment is
/// recorded, which is almost never inside that window, so receipts travel as a
/// template instead. The template's wording lives in Meta's Business Manager
/// and is approved there; all this carries is which template to use and the
/// values that fill its placeholders.
class WhatsAppTemplateInput {
  const WhatsAppTemplateInput({
    required this.to,
    required this.templateName,
    required this.languageCode,
    this.bodyParams = const [],
    this.headerImageBytes,
    this.headerImageFileName,
  });

  /// Recipient in E.164 form, e.g. +923000000022.
  final String to;

  /// The template's name as registered with Meta, e.g. `payment_receipt`.
  final String templateName;

  /// Must match the language the template was registered under exactly —
  /// `en` and `en_US` are different templates as far as Meta is concerned, and
  /// the wrong one comes back as "template does not exist".
  final String languageCode;

  /// Fills `{{1}}`, `{{2}}` … in the template body, in order.
  final List<String> bodyParams;

  /// The image for a template whose header is an image. Uploaded at send time,
  /// because the picture differs per member — only the sample Meta reviewed is
  /// fixed. Null for a text-only template.
  final Uint8List? headerImageBytes;
  final String? headerImageFileName;

  bool get hasHeaderImage => headerImageBytes != null;
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

  /// Sends a plain text message. Never throws — every provider reports its own
  /// failures as [WhatsAppSendFailure], because the callers are all recording
  /// something that has already happened.
  Future<WhatsAppSendResult> sendText(WhatsAppTextInput input);

  /// Sends an approved template, which is what a business-initiated message
  /// has to be. Same contract as the others: it never throws.
  Future<WhatsAppSendResult> sendTemplate(WhatsAppTemplateInput input);
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
