import 'dart:math';

import 'package:logging/logging.dart';

import '../../data/database.dart';
import '../../domain/phone.dart';
import 'whatsapp_client.dart';

final _log = Logger('whatsapp');

/// Development provider. Nothing leaves the machine — it records a realistic
/// success so the whole payment → receipt → WhatsApp flow can be built and
/// exercised without Meta credentials.
///
/// [forceFailure] makes it fail on demand, which is how the
/// "WhatsApp failed / Retry" path gets tested.
class MockWhatsAppClient implements WhatsAppClient {
  MockWhatsAppClient({this.forceFailure = false});

  final bool forceFailure;

  @override
  WhatsAppProviderKind get kind => WhatsAppProviderKind.mock;

  @override
  Future<WhatsAppSendResult> send(WhatsAppSendInput input) async {
    // A little latency so loading states behave like the real thing.
    await Future<void>.delayed(const Duration(milliseconds: 400));

    if (forceFailure) {
      return const WhatsAppSendFailure(
          'Simulated failure (mock provider set to always fail)');
    }

    // Mirror the real provider's rejection of unusable numbers.
    if (!isValidPhone(input.to)) {
      return WhatsAppSendFailure('Invalid recipient number: ${input.to}');
    }
    if (input.imageBytes.isEmpty) {
      return const WhatsAppSendFailure('Receipt image was empty');
    }

    _log.info('[mock] would send ${input.fileName} '
        '(${input.imageBytes.length} bytes) to ${input.to}');

    return WhatsAppSendSuccess(_messageId());
  }

  @override
  Future<WhatsAppSendResult> sendText(WhatsAppTextInput input) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));

    if (forceFailure) {
      return const WhatsAppSendFailure(
          'Simulated failure (mock provider set to always fail)');
    }

    if (!isValidPhone(input.to)) {
      return WhatsAppSendFailure('Invalid recipient number: ${input.to}');
    }
    if (input.body.trim().isEmpty) {
      return const WhatsAppSendFailure('Message body was empty');
    }

    _log.info('[mock] would send a ${input.body.length}-character message '
        'to ${input.to}');

    return WhatsAppSendSuccess(_messageId());
  }

  @override
  Future<WhatsAppSendResult> sendTemplate(WhatsAppTemplateInput input) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));

    if (forceFailure) {
      return const WhatsAppSendFailure(
          'Simulated failure (mock provider set to always fail)');
    }

    if (!isValidPhone(input.to)) {
      return WhatsAppSendFailure('Invalid recipient number: ${input.to}');
    }
    if (input.templateName.trim().isEmpty) {
      return const WhatsAppSendFailure('No template name was configured');
    }
    // Mirrors Meta: a template with an image header is rejected without one.
    if (input.hasHeaderImage && input.headerImageBytes!.isEmpty) {
      return const WhatsAppSendFailure('Receipt image was empty');
    }

    _log.info('[mock] would send template ${input.templateName} '
        '(${input.languageCode}) with ${input.bodyParams.length} '
        'parameters to ${input.to}');

    return WhatsAppSendSuccess(_messageId());
  }

  static String _messageId() =>
      'mock.${Random().nextInt(1 << 32).toRadixString(16)}';
}
