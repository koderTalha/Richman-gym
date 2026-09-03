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

/// Collapses every run of whitespace to a single space and trims the result.
///
/// An empty value becomes "—": Meta rejects an empty parameter outright, and a
/// dash is what the rest of the app already prints for a missing detail.
String flattenTemplateParam(String value) {
  final flattened = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  return flattened.isEmpty ? '—' : flattened;
}
