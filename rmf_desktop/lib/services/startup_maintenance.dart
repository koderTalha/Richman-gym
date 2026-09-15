import '../data/cycle_repricing.dart';
import '../data/database.dart';
import 'billing_maintenance.dart';
import 'billing_reconciliation.dart';

/// What opening the app does to the books, in one place.
///
/// Two callers need it and must not drift apart: `main()` on launch, and the
/// Reload button in the top bar. A member added at the counter has no billing
/// cycle until this runs, so without the button the only way to see them read
/// DUE was to quit the app and open it again.
///
/// Every step is idempotent — running this twice in a row changes nothing the
/// first run did not already change — which is what makes it safe to hang off
/// a button the owner can press as often as they like.
Future<void> runStartupMaintenance(AppDatabase db, {DateTime? now}) async {
  // Rolls each active membership into the current billing cycle, so members
  // who owe this month read DUE rather than looking like lapsed memberships.
  await BillingMaintenance(db).ensureCurrentPeriods(now: now);

  // Carries a fee change through to cycles nobody has paid into yet, before
  // the owner can record a payment against one still holding the old figure.
  // That is the whole of the fix for the fee-rise treadmill: once the new fee
  // has been paid into a cycle priced at the old one, the difference has
  // already spilled into the next cycle and no automatic correction is safe.
  // See `cycle_repricing.dart`.
  //
  // Placed after the roll above so a cycle opened this minute is included, and
  // before the report below so it never names a member this has just put
  // right.
  await repriceAllOpenCycles(db, now: now);

  // Points at members an earlier release left permanently owing money after a
  // fee rise. Reports only, and only once per member — the rows it finds are
  // indistinguishable from a genuine arrears payment, so the correction is the
  // owner's to make. See `billing_reconciliation.dart`.
  await reportBillingDiscrepancies(db, now: now);
}
