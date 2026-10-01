import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/bloc/settings_bloc.dart';
import 'package:rich_man_fitness/data/database.dart';

/// Equatable builds toString() from props, so an event carrying a password
/// or the Meta token would print it verbatim anywhere it is printed — a bloc
/// failure log, a debugger, a crash report (audit SEC-006). Nothing prints
/// these today; this keeps it that way when something starts to.
/// `AuthSignInRequested` set the pattern.
void main() {
  const token = 'EAAG-meta-access-token-that-works-off-site';

  test('a password change prints none of its passwords', () {
    const event = PasswordChangeRequested(
      userId: 7,
      currentPassword: 'OwnersOwnSecret9',
      newPassword: 'BrandNewPass2',
      confirmPassword: 'BrandNewPass2',
    );

    final printed = event.toString();
    expect(printed, contains('userId: 7'));
    expect(printed, isNot(contains('OwnersOwnSecret9')));
    expect(printed, isNot(contains('BrandNewPass2')));
  });

  test('saving WhatsApp settings does not print the access token', () {
    const event = WhatsAppSettingsSaved(
      provider: WhatsAppProviderKind.meta,
      mockFails: false,
      phoneNumberId: '1234567890',
      accessToken: token,
      receiptTemplate: 'payment_receipt',
      receiptTemplateLanguage: 'en',
      welcomeTemplateLanguage: 'en',
    );

    final printed = event.toString();
    expect(printed, isNot(contains(token)));
    expect(printed, contains('1234567890'),
        reason: 'what is not secret is still useful to see');
  });

  test('testing the credentials does not print the access token', () {
    const event = WhatsAppCredentialsTested(
        phoneNumberId: '1234567890', accessToken: token);

    expect(event.toString(), isNot(contains(token)));
  });

  test('equality still tells two different secrets apart', () {
    // Redacting the printout must not make two attempts look the same to
    // the bloc, which would drop the second as a duplicate.
    expect(
      const WhatsAppCredentialsTested(accessToken: 'one'),
      isNot(const WhatsAppCredentialsTested(accessToken: 'two')),
    );
  });
}
