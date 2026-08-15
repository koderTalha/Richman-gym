import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/bloc/member_form_bloc.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/member_repository.dart';
import 'package:rich_man_fitness/data/seed.dart';

/// Relatives share a phone number: the elder brother asked to be put on the
/// younger one's. Once the importer can create two members on one number, the
/// rest of the app has to cope with that too — a lookup by number alone is no
/// longer a lookup for one person.
void main() {
  late AppDatabase db;
  late MemberRepository members;
  late int planId;

  const sharedPhone = '+923000000001';

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedDatabase(db);
    members = MemberRepository(db);
    planId = (await (db.select(db.membershipPlans)
              ..where((p) => p.name.equals('Monthly')))
            .getSingle())
        .id;

    await members.create(
      fullName: 'Younger Brother',
      phone: sharedPhone,
      planId: planId,
      joiningDate: DateTime.utc(2026, 1, 1),
    );
  });

  tearDown(() async => db.close());

  group('MemberRepository.findByPhoneAndName', () {
    test('picks the right person out of a shared number', () async {
      await members.create(
        fullName: 'Elder Brother',
        phone: sharedPhone,
        planId: planId,
        joiningDate: DateTime.utc(2026, 1, 1),
      );

      final elder = await members.findByPhoneAndName(
          phone: sharedPhone, fullName: '  elder   BROTHER ');

      expect(elder?.fullName, 'Elder Brother',
          reason: 'two members on this number, and neither lookup may throw');
    });

    test('returns null for a name nobody on that number uses', () async {
      final none = await members.findByPhoneAndName(
          phone: sharedPhone, fullName: 'Someone Else');

      expect(none, isNull);
    });
  });

  group('adding a member by hand', () {
    Future<MemberFormState> submit(
      String fullName, {
      bool confirmSharedPhone = false,
    }) async {
      final bloc = MemberFormBloc(repository: members);
      bloc.add(const MemberFormLoaded());
      await bloc.stream.firstWhere((s) => s.status == MemberFormStatus.ready);

      bloc.add(MemberFormSubmitted(
        fullName: fullName,
        rawPhone: sharedPhone,
        planId: planId,
        joiningDate: DateTime.utc(2026, 1, 1),
        confirmSharedPhone: confirmSharedPhone,
      ));
      final result = await bloc.stream.firstWhere((s) =>
          s.status == MemberFormStatus.saved ||
          s.status == MemberFormStatus.failed ||
          s.status == MemberFormStatus.confirmSharedPhone);
      await bloc.close();
      return result;
    }

    test('a relative on the same number is accepted, once confirmed', () async {
      final result =
          await submit('Elder Brother', confirmSharedPhone: true);

      expect(result.status, MemberFormStatus.saved, reason: result.error);
      expect((await db.select(db.members).get()).length, 2);
    });

    // A shared number is legitimate; a mistyped one looks identical from here,
    // and silently accepting it points somebody else's receipts at the wrong
    // handset for good. So the operator is shown whose number it is first.
    test('a new name on a number in use asks before saving', () async {
      final result = await submit('Elder Brother');

      expect(result.status, MemberFormStatus.confirmSharedPhone);
      expect(result.sharingPhone.map((m) => m.fullName), ['Younger Brother'],
          reason: 'the operator has to be told whose number it already is');
      expect((await db.select(db.members).get()).length, 1,
          reason: 'nothing is written until they confirm');
    });

    test('a number nobody else has needs no confirmation', () async {
      final bloc = MemberFormBloc(repository: members);
      addTearDown(bloc.close);
      bloc.add(const MemberFormLoaded());
      await bloc.stream.firstWhere((s) => s.status == MemberFormStatus.ready);

      bloc.add(MemberFormSubmitted(
        fullName: 'Nobody Else',
        rawPhone: '+923000000099',
        planId: planId,
        joiningDate: DateTime.utc(2026, 1, 1),
      ));

      final result = await bloc.stream.firstWhere((s) =>
          s.status == MemberFormStatus.saved ||
          s.status == MemberFormStatus.failed ||
          s.status == MemberFormStatus.confirmSharedPhone);

      expect(result.status, MemberFormStatus.saved, reason: result.error);
    });

    test('the same person on the same number is rejected', () async {
      final result = await submit('younger brother');

      expect(result.status, MemberFormStatus.failed);
      expect(result.error, contains('Younger Brother'));
      expect((await db.select(db.members).get()).length, 1);
    });

    test('confirming does not override the same-person check', () async {
      final result = await submit('younger brother', confirmSharedPhone: true);

      expect(result.status, MemberFormStatus.failed,
          reason: 'a duplicate is a duplicate however it was confirmed');
      expect((await db.select(db.members).get()).length, 1);
    });
  });

  group('editing a member on a deactivated plan', () {
    test('the plan they are on is still offered', () async {
      final legacyId = await db.into(db.membershipPlans).insert(
          MembershipPlansCompanion.insert(
              name: 'Legacy Yearly', durationMonths: 12, priceMinor: 2000000));

      final memberId = await members.create(
        fullName: 'On A Retired Plan',
        phone: '+923000000077',
        planId: legacyId,
        joiningDate: DateTime.utc(2026, 1, 1),
      );

      // The gym stops selling it. The member is still on it.
      await (db.update(db.membershipPlans)..where((p) => p.id.equals(legacyId)))
          .write(const MembershipPlansCompanion(isActive: Value(false)));

      final offered = await members.plansFor(memberId);

      expect(offered.map((p) => p.id), contains(legacyId),
          reason: 'a plan missing from its own dropdown makes the member '
              'uneditable — even to correct their phone number');
      expect(await members.plansFor(null), isNot(contains(legacyId)),
          reason: 'but it is not offered to new members');
    });
  });
}
