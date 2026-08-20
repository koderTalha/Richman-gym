import 'package:logging/logging.dart';

final _log = Logger('payments');

/// A refusal with a message written for the gym owner.
///
/// Thrown where the app declines to do something for a reason the owner can act
/// on — no plan assigned, a billing month that cannot be right. Distinct from a
/// crash, and the only kind of exception whose text is safe to put on screen.
class PaymentRuleException implements Exception {
  const PaymentRuleException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Anything thrown, reduced to one sentence the owner can read.
///
/// Everything else — a SQLite constraint, a socket timeout, a null in a place
/// there should not be one — is genuinely not their problem and tells them
/// nothing they can use. It goes to the log, with its stack; they get a
/// sentence and a place to look.
///
/// Logging happens here rather than at each call site, so the diagnostic and
/// the message the owner sees cannot drift apart, and so neither is written
/// twice.
String describeSaveError(
  Object error, {
  StackTrace? stack,
  String? whileDoing,
}) {
  final context = whileDoing == null ? '' : ' $whileDoing';

  if (error is PaymentRuleException) {
    // Not a fault: the app declined on purpose, and the owner is being told
    // why. Recorded at info so a run of refusals is still visible.
    _log.info('Refused$context: ${error.message}');
    return error.message;
  }

  _log.severe('Unhandled failure$context', error, stack);

  return 'Something went wrong$context. '
      'Nothing was lost — check the Logs screen for the details.';
}
