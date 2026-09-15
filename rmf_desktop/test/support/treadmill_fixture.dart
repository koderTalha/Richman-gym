import 'package:drift/drift.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/member_repository.dart';
import 'package:rich_man_fitness/services/billing_maintenance.dart';
import 'package:rich_man_fitness/services/record_payment_service.dart';

/// Rs. 1,500 and Rs. 2,500, in minor units.
const treadmillOldFee = 150000;
const treadmillNewFee = 250000;

/// Builds the member the gym reported, in the state their screen showed.
///
/// The owner's real sequence, on a build predating v1.3.0:
///
///  1. a Student plan sold at Rs. 1,500,
///  2. a few months collected at that price,
///  3. the plan's price edited to Rs. 2,500 in Settings — which, before
///     `cycle_repricing.dart` shipped on 2026-09-12, changed the column and
///     nothing else, leaving the cycle the member was already in at Rs. 1,500,
///  4. Rs. 2,500 collected in full every month afterwards.
///
/// [raisePrice] writes the plan price directly for exactly that reason: going
/// through `SettingsRepository.savePlan` would re-price the open cycle and the
/// bug would never start. This is a deliberate simulation of the older release.
///
/// Leaves the member with the September cycle holding Rs. 1,000 and owing
/// Rs. 1,500, which is what "Overdue since 01 Sep 2026 — Rs. 1,500" is.
Future<int> buildTreadmilledMember({
  required AppDatabase db,
  required MemberRepository members,
  required RecordPaymentService payments,
  required int adminId,
  required int planId,
}) async {
  Future<void> payOn(int memberId, DateTime day, int amountMinor) =>
      payments.recordAdvancePayment(AdvancePaymentInput(
        memberId: memberId,
        amountMinor: amountMinor,
        method: PaymentMethod.cash,
        paymentDate: day,
        sendWhatsApp: false,
        recordedById: adminId,
        idempotencyKey: 'seed-$memberId-${day.toIso8601String()}',
      ));

  final memberId = await members.create(
    fullName: 'Abdul Qadir',
    phone: '+923254097472',
    planId: planId,
    joiningDate: DateTime.utc(2026, 1, 1),
  );

  // Jan-Mar: billed and paid at Rs. 1,500.
  for (var month = 1; month <= 3; month++) {
    final on = DateTime.utc(2026, month, 4);
    await BillingMaintenance(db).ensureCurrentPeriods(now: on);
    await payOn(memberId, on, treadmillOldFee);
  }

  // April's cycle opens at Rs. 1,500...
  await BillingMaintenance(db)
      .ensureCurrentPeriods(now: DateTime.utc(2026, 4, 1));

  // ...and only then is the price edited, by a release that did not carry it
  // through to bills nobody had issued.
  await (db.update(db.membershipPlans)..where((p) => p.id.equals(planId)))
      .write(const MembershipPlansCompanion(
          priceMinor: Value(treadmillNewFee)));

  // Apr-Aug: Rs. 2,500 handed over in full, every month.
  for (final on in [
    DateTime.utc(2026, 4, 4),
    DateTime.utc(2026, 5, 4),
    DateTime.utc(2026, 6, 4),
    DateTime.utc(2026, 7, 3),
    DateTime.utc(2026, 8, 4),
  ]) {
    await BillingMaintenance(db).ensureCurrentPeriods(now: on);
    await payOn(memberId, on, treadmillNewFee);
  }

  await BillingMaintenance(db)
      .ensureCurrentPeriods(now: DateTime.utc(2026, 9, 1));
  return memberId;
}
