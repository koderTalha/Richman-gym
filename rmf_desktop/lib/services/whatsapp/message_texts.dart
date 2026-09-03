/// Every message this app sends a member, written in one place.
///
/// They live here rather than beside the code that sends them so the wording
/// can be read, reviewed and changed without hunting through services: the gym
/// owner's members read these, and "what exactly do we say to people" should
/// never mean grepping for a string literal.
///
/// The gym's name is passed in rather than hard coded — it comes from the
/// settings row, so a gym that renames itself renames itself everywhere.
library;

import '../../domain/dates.dart';

/// The note a member is sent once, when they are added to the gym.
///
/// [memberName] and [memberCode] are optional so the message degrades to the
/// plain version rather than printing "null" if a caller has neither.
String welcomeMessage({
  required String gymName,
  String? memberName,
  int? memberCode,
}) {
  final greeting = (memberName == null || memberName.trim().isEmpty)
      ? 'Welcome!'
      : 'Welcome, ${memberName.trim()}!';

  return [
    '*$gymName*',
    '',
    '$greeting You have successfully been added as a member. '
        'We are happy to have you with us.',
    if (memberCode != null) ...[
      '',
      'Your member ID is #$memberCode.',
    ],
  ].join('\n');
}

/// The values that fill the `welcome_member` template's `{{1}}`…`{{4}}`.
///
/// Order is the contract with the template registered in Meta's Business
/// Manager and cannot be rearranged here alone:
///
///   1. member name  2. member code  3. plan name  4. valid until
///
/// Used instead of [welcomeMessage] when the gym has registered a welcome
/// template — see [GymSettings.whatsappWelcomeTemplate] and
/// `MemberWelcomeService`. Unlike the free-text message, every field here is
/// required: a template parameter cannot be blank, so there is no equivalent
/// of [welcomeMessage]'s degrade-to-plain-greeting behaviour.
List<String> welcomeTemplateParams({
  required String memberName,
  required int memberCode,
  required String planName,
  required DateTime validUntil,
}) =>
    [
      memberName,
      '$memberCode',
      planName,
      formatDayMonthYear(validUntil),
    ].map(flattenTemplateParam).toList();

/// The caption that travels with a receipt image.
String receiptCaption({
  required String gymName,
  required String receiptNumber,
  required String memberName,
  required String periodLabel,
  required String amountLabel,
}) =>
    [
      '*$gymName* — Payment Receipt',
      '',
      'Receipt: $receiptNumber',
      'Member: $memberName',
      'Period: $periodLabel',
      'Amount: $amountLabel',
      '',
      'Thank you for your payment.',
    ].join('\n');

/// The values that fill the `payment_receipt` template's `{{1}}`…`{{4}}`.
///
/// Order is the contract with the template registered in Meta's Business
/// Manager and cannot be rearranged here alone:
///
///   1. member name   2. amount   3. billing period   4. receipt number
///
/// Meta rejects a parameter containing a newline, a tab, or a run of four or
/// more spaces, so every value is flattened to single-spaced text first. That
/// is why this is separate from [receiptCaption], which is free prose and may
/// wrap however it likes.
List<String> receiptTemplateParams({
  required String memberName,
  required String amountLabel,
  required String periodLabel,
  required String receiptNumber,
}) =>
    [memberName, amountLabel, periodLabel, receiptNumber]
        .map(flattenTemplateParam)
        .toList();

/// The values that fill a payment-reminder template's `{{1}}`…`{{5}}`.
///
/// Order is the contract with whatever template the owner registers in Meta's
/// Business Manager under [GymSettings.whatsappReminderTemplate] and cannot be
/// rearranged here alone:
///
///   1. member name  2. amount due  3. due date  4. gym name
///   5. payment instructions
///
/// [paymentInstructions] is the owner's own words for how to pay — "Cash at
/// the counter, or Easypaisa to 0300-1234567" — and is optional: a gym that
/// has not filled it in still sends a complete, readable reminder, just
/// without a fifth line.
List<String> reminderTemplateParams({
  required String memberName,
  required String amountLabel,
  required String dueDateLabel,
  required String gymName,
  String? paymentInstructions,
}) =>
    [
      memberName,
      amountLabel,
      dueDateLabel,
      gymName,
      paymentInstructions ?? '—',
    ].map(flattenTemplateParam).toList();

/// Collapses every run of whitespace to a single space and trims the result.
///
/// An empty value becomes "—": Meta rejects an empty parameter outright, and a
/// dash is what the rest of the app already prints for a missing detail.
String flattenTemplateParam(String value) {
  final flattened = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  return flattened.isEmpty ? '—' : flattened;
}
