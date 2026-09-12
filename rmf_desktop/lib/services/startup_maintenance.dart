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
/// Both steps are idempotent — running this twice in a row changes nothing the
/// first run did not already change — which is what makes it safe to hang off
/// a button the owner can press as often as they like.
Future<void> runStartupMaintenance(AppDatabase db, {DateTime? now}) async {
  // Rolls each active membership into the current billing cycle, so members
  // who owe this month read DUE rather than looking like lapsed memberships.
  await BillingMaintenance(db).ensureCurrentPeriods(now: now);

  // Points at members an earlier release left permanently owing money after a
  // fee rise. Reports only, and only once per member — the rows it finds are
  // indistinguishable from a genuine arrears payment, so the correction is the
  // owner's to make. See `billing_reconciliation.dart`.
  await reportBillingDiscrepancies(db, now: now);
}
