import 'package:bcrypt/bcrypt.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/data/settings_repository.dart';

void main() {
  late AppDatabase db;
  late SettingsRepository repo;
  late int userId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedDatabase(db,
        adminPassword: 'OriginalPass1', includeSampleMembers: false);
    repo = SettingsRepository(db);
    userId = (await db.select(db.users).getSingle()).id;
  });

  tearDown(() => db.close());

  Future<String> currentHash() async =>
      (await db.select(db.users).getSingle()).passwordHash;

  test('changes the password when the current one is correct', () async {
    final error = await repo.changePassword(
      userId: userId,
      currentPassword: 'OriginalPass1',
      newPassword: 'BrandNewPass2',
    );

    expect(error, isNull);
    expect(BCrypt.checkpw('BrandNewPass2', await currentHash()), isTrue);
  });

  test('the old password stops working afterwards', () async {
    await repo.changePassword(
      userId: userId,
      currentPassword: 'OriginalPass1',
      newPassword: 'BrandNewPass2',
    );

    expect(BCrypt.checkpw('OriginalPass1', await currentHash()), isFalse);
  });

  test('rejects a wrong current password and leaves the hash untouched',
      () async {
    final before = await currentHash();

    final error = await repo.changePassword(
      userId: userId,
      currentPassword: 'NotThePassword',
      newPassword: 'BrandNewPass2',
    );

    expect(error, 'The current password is incorrect.');
    expect(await currentHash(), before);
  });

  test('rejects a new password shorter than 8 characters', () async {
    final before = await currentHash();

    final error = await repo.changePassword(
      userId: userId,
      currentPassword: 'OriginalPass1',
      newPassword: 'short',
    );

    expect(error, contains('at least 8'));
    expect(await currentHash(), before);
  });

  test('stores a hash, never the plaintext', () async {
    await repo.changePassword(
      userId: userId,
      currentPassword: 'OriginalPass1',
      newPassword: 'BrandNewPass2',
    );

    final hash = await currentHash();
    expect(hash, isNot(contains('BrandNewPass2')));
    expect(hash.startsWith(r'$2'), isTrue);
  });

  test('reports a missing account rather than throwing', () async {
    final error = await repo.changePassword(
      userId: 9999,
      currentPassword: 'OriginalPass1',
      newPassword: 'BrandNewPass2',
    );

    expect(error, 'That account no longer exists.');
  });

  test('refuses to verify Meta credentials when fields are empty', () async {
    final result = await repo.testWhatsAppCredentials();

    expect(result.ok, isFalse);
    expect(result.summary, contains('Phone Number ID'));
  });
}
