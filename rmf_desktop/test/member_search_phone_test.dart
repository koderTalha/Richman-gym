import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/member_repository.dart';
import 'package:rich_man_fitness/data/seed.dart';

/// The Members search box says "Search name, phone, or member ID", but phones
/// are stored as E.164 (+92...) and the term used to be matched as typed — so
/// the way the owner actually writes a number (03xx..., 0300-..., the form's
/// own hint) found nobody. BUG-020 in the 1 Oct 2026 audit.
void main() {
  late AppDatabase db;
  late MemberRepository members;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedDatabase(db);
    members = MemberRepository(db);
    final planId = (await db.select(db.membershipPlans).get()).first.id;
    await members.create(
      fullName: 'Searchable Member',
      phone: '+923001234567',
      phoneRaw: '0300-1234567',
      planId: planId,
      joiningDate: DateTime.utc(2026, 1, 1),
    );
    await members.create(
      fullName: 'Someone Else',
      phone: '+923339876543',
      planId: planId,
      joiningDate: DateTime.utc(2026, 1, 1),
    );
  });

  tearDown(() async => db.close());

  Future<List<String>> namesFound(String typed) async =>
      (await members.list(search: typed))
          .map((r) => r.member.fullName)
          .toList();

  for (final typed in [
    '03001234567',
    '0300-1234567',
    '0300 1234567',
    '+92 300 1234567',
    '+923001234567',
    '923001234567',
    '00923001234567',
  ]) {
    test('finds the member when the phone is typed as "$typed"', () async {
      expect(await namesFound(typed), ['Searchable Member']);
    });
  }

  test('part of a number, written the owner\'s way, still finds them',
      () async {
    expect(await namesFound('0300-123'), ['Searchable Member']);
    expect(await namesFound('1234567'), ['Searchable Member']);
  });

  test('a name search is unaffected, and matches no phone', () async {
    expect(await namesFound('searchable'), ['Searchable Member']);
    expect(await namesFound('else'), ['Someone Else']);
  });

  test('a term with no digits does not match every phone', () async {
    expect(await namesFound('-'), isEmpty);
    expect(await namesFound('()'), isEmpty);
  });

  test('a typed % is still a literal, not a wildcard', () async {
    expect(await namesFound('%'), isEmpty);
  });

  test('a member code still finds that member', () async {
    final code = (await members.list())
        .singleWhere((r) => r.member.fullName == 'Someone Else')
        .member
        .memberCode;
    expect(await namesFound('$code'), contains('Someone Else'));
  });
}
