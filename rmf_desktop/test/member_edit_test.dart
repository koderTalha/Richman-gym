import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/bloc/member_form_bloc.dart';
import 'package:rich_man_fitness/data/audit_repository.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/member_repository.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/services/import_service.dart';
import 'package:rich_man_fitness/services/ledger_import.dart';
import 'package:rich_man_fitness/services/member_purge_service.dart';
import 'package:rich_man_fitness/services/receipt_storage.dart';

/// Records what the form actually hands the repository, so a test can look
/// at the save itself rather than at what the repository later made of it.
class _CapturingRepository extends MemberRepository {
  _CapturingRepository(super.db);

  DateTime? effectiveFrom;
  bool effectiveFromPassed = false;

  @override
  Future<void> update({
    required int id,
    required String fullName,
    required String phone,
    String? phoneRaw,
    String? email,
    String? gender,
    String? address,
    String? emergencyContact,
    required int planId,
    int? feeOverrideMinor,
    required DateTime joiningDate,
    int? actorId,
    DateTime? now,
    DateTime? effectiveFrom,
    String? changeReason,
  }) {
    this.effectiveFrom = effectiveFrom;
    effectiveFromPassed = true;
    return super.update(
      id: id,
      fullName: fullName,
      phone: phone,
      phoneRaw: phoneRaw,
      email: email,
      gender: gender,
      address: address,
      emergencyContact: emergencyContact,
      planId: planId,
      feeOverrideMinor: feeOverrideMinor,
      joiningDate: joiningDate,
      actorId: actorId,
      now: now,
      effectiveFrom: effectiveFrom,
      changeReason: changeReason,
    );
  }
}

/// Editing an existing member through the form: the fixes from the 1 Oct 2026
/// audit — BUG-027 (phoneless members), BUG-029 (the shared-phone question on
/// every save, member-code reuse), BUG-028 (profile edits audited) and
/// BUG-003(b) (the effective date stored a day early).
void main() {
  late AppDatabase db;
  late MemberRepository members;
  late int adminId;
  late int planId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedDatabase(db);
    members = MemberRepository(db);
    adminId = (await db.select(db.users).getSingle()).id;
    planId = (await (db.select(db.membershipPlans)
              ..where((p) => p.name.equals('Monthly')))
            .getSingle())
        .id;
  });

  tearDown(() async => db.close());

  Future<Member> member(int id) =>
      (db.select(db.members)..where((m) => m.id.equals(id))).getSingle();

  /// Opens the form on [memberId] (or a new member), submits [submitted] and
  /// returns the state it settles on.
  Future<MemberFormState> submit(
    MemberFormSubmitted submitted, {
    int? memberId,
    MemberRepository? repository,
  }) async {
    final bloc =
        MemberFormBloc(repository: repository ?? members, memberId: memberId);
    addTearDown(bloc.close);
    bloc.add(const MemberFormLoaded());
    await bloc.stream.firstWhere((s) => s.status == MemberFormStatus.ready);

    bloc.add(submitted);
    return bloc.stream.firstWhere((s) =>
        s.status == MemberFormStatus.saved ||
        s.status == MemberFormStatus.failed ||
        s.status == MemberFormStatus.confirmSharedPhone);
  }

  /// An edit that re-submits [m] exactly as stored, with [changes] applied.
  MemberFormSubmitted resubmit(
    Member m, {
    String? fullName,
    String? rawPhone,
    String? address,
    int? feeOverrideMinor,
    DateTime? joiningDate,
    DateTime? effectiveFrom,
    int? planIdOverride,
  }) =>
      MemberFormSubmitted(
        fullName: fullName ?? m.fullName,
        rawPhone: rawPhone ?? m.phoneRaw ?? m.phone,
        planId: planIdOverride ?? planId,
        joiningDate: joiningDate ?? m.joiningDate,
        email: m.email,
        gender: m.gender,
        address: address ?? m.address,
        emergencyContact: m.emergencyContact,
        feeOverrideMinor: feeOverrideMinor,
        actorId: adminId,
        effectiveFrom: effectiveFrom,
      );

  group('a member imported with no phone (BUG-027)', () {
    Future<Member> importPhoneless() async {
      final sheet = <List<String?>>[
        ['Enroll.', 'Name', 'Contact Detail', 'Jan', 'Feb'],
        ['2', 'No Phone Member', '-', '3000', '3000'],
      ];
      final detected = detectMapping(sheet)!;
      await ImportService(db).commit(
        ledger: parseLedger(
            rows: sheet,
            headerRow: detected.headerRow,
            mapping: detected.mapping,
            year: 2026),
        planId: planId,
        recordedById: adminId,
        now: DateTime.utc(2026, 3, 1),
      );
      final imported = await db.select(db.members).getSingle();
      expect(imported.phone, '', reason: 'precondition: stored phoneless');
      return imported;
    }

    test('the owner can change their fee without inventing a number',
        () async {
      final m = await importPhoneless();

      // What the form prefills: phoneRaw ("-"), the only thing on file.
      final done = await submit(
          resubmit(m, feeOverrideMinor: 200000),
          memberId: m.id);

      expect(done.status, MemberFormStatus.saved, reason: done.error ?? '');
      expect((await member(m.id)).phone, '');
    });

    test('a blank phone field keeps them phoneless', () async {
      final m = await importPhoneless();

      final done = await submit(
          resubmit(m, rawPhone: '', fullName: 'No Phone Member Renamed'),
          memberId: m.id);

      expect(done.status, MemberFormStatus.saved, reason: done.error ?? '');
      final after = await member(m.id);
      expect(after.phone, '');
      expect(after.phoneRaw, isNull);
      expect(after.fullName, 'No Phone Member Renamed');
    });

    test('a number typed in is still checked', () async {
      final m = await importPhoneless();

      final done =
          await submit(resubmit(m, rawPhone: '0300-12'), memberId: m.id);

      expect(done.status, MemberFormStatus.failed);
      expect((await member(m.id)).phone, '');
    });

    test('a real number typed in is saved', () async {
      final m = await importPhoneless();

      final done =
          await submit(resubmit(m, rawPhone: '0300-1234567'), memberId: m.id);

      expect(done.status, MemberFormStatus.saved, reason: done.error ?? '');
      expect((await member(m.id)).phone, '+923001234567');
    });

    test('a new member still needs a phone', () async {
      final done = await submit(MemberFormSubmitted(
        fullName: 'Brand New',
        rawPhone: '',
        planId: planId,
        joiningDate: DateTime.utc(2026, 1, 1),
      ));

      expect(done.status, MemberFormStatus.failed);
      expect(await db.select(db.members).get(), isEmpty);
    });
  });

  group('the shared-phone question (BUG-029)', () {
    const shared = '+923000000001';
    late int youngerId;
    late int elderId;

    setUp(() async {
      youngerId = await members.create(
        fullName: 'Younger Brother',
        phone: shared,
        planId: planId,
        joiningDate: DateTime.utc(2026, 1, 1),
      );
      elderId = await members.create(
        fullName: 'Elder Brother',
        phone: shared,
        planId: planId,
        joiningDate: DateTime.utc(2026, 1, 1),
      );
    });

    test('is not asked again when the number did not change', () async {
      final m = await member(elderId);

      final done =
          await submit(resubmit(m, address: 'Street 4'), memberId: elderId);

      expect(done.status, MemberFormStatus.saved, reason: done.error ?? '');
      expect((await member(elderId)).address, 'Street 4');
    });

    test('is not asked when the number is unchanged but typed differently',
        () async {
      final m = await member(elderId);

      final done = await submit(
          resubmit(m, rawPhone: '0300 0000001', address: 'Street 5'),
          memberId: elderId);

      expect(done.status, MemberFormStatus.saved, reason: done.error ?? '');
    });

    test('is still asked when the edit moves them onto someone\'s number',
        () async {
      final otherId = await members.create(
        fullName: 'Unrelated Member',
        phone: '+923000000077',
        planId: planId,
        joiningDate: DateTime.utc(2026, 1, 1),
      );
      final m = await member(otherId);

      final done =
          await submit(resubmit(m, rawPhone: shared), memberId: otherId);

      expect(done.status, MemberFormStatus.confirmSharedPhone);
      expect(done.sharingPhone.map((s) => s.id),
          unorderedEquals([youngerId, elderId]));
      expect((await member(otherId)).phone, '+923000000077',
          reason: 'nothing is written until they confirm');
    });

    test('renaming onto the other person on the number is still refused',
        () async {
      final m = await member(elderId);

      final done = await submit(resubmit(m, fullName: 'younger brother'),
          memberId: elderId);

      expect(done.status, MemberFormStatus.failed);
      expect(done.error, contains('Younger Brother'));
    });
  });

  group('the effective date (BUG-003 b)', () {
    test('is the calendar day picked, as a UTC day, like the joining date',
        () async {
      final studentId = await db.into(db.membershipPlans).insert(
          MembershipPlansCompanion.insert(
              name: 'Student', durationMonths: 1, priceMinor: 250000));
      final id = await members.create(
        fullName: 'Fee Change Member',
        phone: '+923001234000',
        planId: planId,
        joiningDate: DateTime.utc(2026, 1, 1),
      );
      final capturing = _CapturingRepository(db);

      // Exactly what showDatePicker returns: a local midnight. On the gym's
      // UTC+5 clock its instant is 9 Sep 19:00 UTC.
      final done = await submit(
        resubmit(await member(id),
            planIdOverride: studentId, effectiveFrom: DateTime(2026, 9, 10)),
        memberId: id,
        repository: capturing,
      );

      expect(done.status, MemberFormStatus.saved, reason: done.error ?? '');
      expect(capturing.effectiveFrom, DateTime.utc(2026, 9, 10));
      expect(capturing.effectiveFrom!.isUtc, isTrue);

      final change = await db.select(db.membershipChanges).getSingle();
      expect(change.effectiveFrom.toUtc(), DateTime.utc(2026, 9, 10));
    });

    test('stays null — today — when the owner was not asked', () async {
      final id = await members.create(
        fullName: 'Ordinary Edit',
        phone: '+923001234001',
        planId: planId,
        joiningDate: DateTime.utc(2026, 1, 1),
      );
      final capturing = _CapturingRepository(db);

      await submit(resubmit(await member(id), address: 'Somewhere'),
          memberId: id, repository: capturing);

      expect(capturing.effectiveFromPassed, isTrue);
      expect(capturing.effectiveFrom, isNull);
    });
  });

  group('profile edits are audited (BUG-028)', () {
    late int id;

    setUp(() async {
      id = await members.create(
        fullName: 'Ali Khan',
        phone: '+923001112222',
        planId: planId,
        joiningDate: DateTime.utc(2026, 1, 1),
      );
    });

    Future<List<AuditEvent>> updates() => (db.select(db.auditEvents)
          ..where((e) => e.action.equals(AuditAction.memberUpdated)))
        .get();

    test('names each field that moved, before and after', () async {
      await members.update(
        id: id,
        fullName: 'Ali Raza Khan',
        phone: '+923003334444',
        email: 'ali@example.com',
        gender: 'Male',
        address: 'Street 9',
        emergencyContact: '03009998888',
        planId: planId,
        joiningDate: DateTime.utc(2026, 2, 15),
        actorId: adminId,
      );

      final event = (await updates()).single;
      expect(event.memberId, id);
      expect(event.actorId, adminId);
      expect(event.category, AuditCategory.member);
      expect(event.summary, contains('Ali Raza Khan'));

      final lines = event.detail!.split('\n');
      expect(lines, [
        'Name: "Ali Khan" → "Ali Raza Khan"',
        'Phone: ••••2222 → ••••4444',
        'Email: — → "ali@example.com"',
        'Gender: Not specified → Male',
        'Address: — → "Street 9"',
        'Emergency contact: — → ••••8888',
        'Joining date: 01 Jan 2026 → 15 Feb 2026',
      ]);
      expect(event.detail, isNot(contains('3003334444')),
          reason: 'numbers are masked in the log, as everywhere else');
    });

    test('a joining-date edit on its own is recorded', () async {
      await members.update(
        id: id,
        fullName: 'Ali Khan',
        phone: '+923001112222',
        planId: planId,
        joiningDate: DateTime.utc(2026, 9, 25),
      );

      expect((await updates()).single.detail,
          'Joining date: 01 Jan 2026 → 25 Sep 2026');
    });

    test('a save that changed nothing writes nothing', () async {
      await members.update(
        id: id,
        fullName: 'Ali Khan',
        phone: '+923001112222',
        email: '  ',
        planId: planId,
        joiningDate: DateTime.utc(2026, 1, 1),
      );

      expect(await updates(), isEmpty,
          reason: 'a blank field and a missing one are the same nothing');
    });

    test('a fee change alone is the fee row\'s, not repeated here', () async {
      await members.update(
        id: id,
        fullName: 'Ali Khan',
        phone: '+923001112222',
        planId: planId,
        feeOverrideMinor: 123400,
        joiningDate: DateTime.utc(2026, 1, 1),
      );

      expect(await updates(), isEmpty);
      final fee = await (db.select(db.auditEvents)
            ..where((e) => e.action.equals(AuditAction.memberFeeChanged)))
          .get();
      expect(fee, hasLength(1));
    });
  });

  group('member codes are not handed out twice (BUG-029)', () {
    Future<int> add(String name, String phone) => members.create(
          fullName: name,
          phone: phone,
          planId: planId,
          joiningDate: DateTime.utc(2026, 1, 1),
        );

    test('deleting the newest member does not free their code', () async {
      await add('First', '+923000000011');
      final second = await add('Second', '+923000000012');
      final secondCode = (await member(second)).memberCode;

      await members.deleteMember(id: second, actorId: adminId);
      final third = await add('Third', '+923000000013');

      expect((await member(third)).memberCode, secondCode + 1,
          reason: 'the audit log already says "member #$secondCode" about '
              'somebody else');
    });

    test('numbering starts again after "delete all members data"', () async {
      final only = await add('Only', '+923000000021');
      await members.deleteMember(id: only, actorId: adminId);
      await add('Another', '+923000000022');

      await MemberPurgeService(
        db: db,
        storage: ReceiptStorage(),
        audit: AuditRepository(db),
      ).purgeAll(actorId: adminId);

      final fresh = await add('Fresh Start', '+923000000023');
      expect((await member(fresh)).memberCode, 1);
    });
  });
}
