import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:rich_man_fitness/bloc/settings_bloc.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/data/settings_repository.dart';
import 'package:rich_man_fitness/domain/receipt_number.dart';
import 'package:rich_man_fitness/services/receipt_storage.dart';

class _FakeStorage extends ReceiptStorage {
  _FakeStorage(this._dir);
  final Directory _dir;

  @override
  Future<Directory> root() async => _dir;
}

/// The receipt prefix typed in Settings becomes part of a file name —
/// `ReceiptStorage.save('$receiptNumber.png')` — so it used to be able to
/// write receipts outside the receipts folder, where backups never look, or
/// (with a character Windows forbids) make every payment fail to record,
/// because the receipt is written before the payment commits (audit SEC-005).
///
/// Two guards: Settings refuses an unsafe prefix, and the storage refuses a
/// path outside its folder whatever prefix produced it — one saved by an
/// earlier release, say, or brought back by a restore.
void main() {
  const escaping = [r'..\..\..\Desktop\X', '../../X', r'C:\Temp\X', '/tmp/X'];

  group('Settings', () {
    late AppDatabase db;
    late SettingsRepository repo;
    late SettingsBloc bloc;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await seedDatabase(db, adminPassword: 'OwnersOwnSecret9');
      repo = SettingsRepository(db);
      bloc = SettingsBloc(repo);
    });

    tearDown(() async {
      await bloc.close();
      await db.close();
    });

    Future<SettingsState> save(String prefix) async {
      bloc.add(GymInfoSaved(
        gymName: 'Rich Man Fitness',
        phone: null,
        address: null,
        receiptPrefix: prefix,
        receiptFooter: '',
      ));
      return bloc.stream.firstWhere((s) => s.message != null);
    }

    test('refuses a receipt prefix that is not a safe file name', () async {
      final before = (await repo.get()).receiptPrefix;

      // ':' is illegal in a Windows file name.
      final state = await save('RMF:2026');

      expect((await repo.get()).receiptPrefix, before,
          reason: 'an unsafe prefix must be rejected, not saved');
      expect(state.message, receiptPrefixRejected,
          reason: 'and the owner is told why, on the existing snackbar');
    });

    test('refuses every prefix that could leave the receipts folder',
        () async {
      final before = (await repo.get()).receiptPrefix;
      for (final prefix in [
        ...escaping,
        '',
        '   ',
        'RMF 2026',
        'RMF?',
        'ELEVENCHARS',
      ]) {
        expect(normalizeReceiptPrefix(prefix), isNull, reason: '"$prefix"');
      }

      await save('../../X');
      expect((await repo.get()).receiptPrefix, before);
    });

    test('the other gym details are not half-saved alongside a refusal',
        () async {
      final before = (await repo.get()).gymName;
      bloc.add(const GymInfoSaved(
        gymName: 'Renamed Gym',
        phone: null,
        address: null,
        receiptPrefix: 'R/F',
        receiptFooter: '',
      ));
      await bloc.stream.firstWhere((s) => s.message != null);

      expect((await repo.get()).gymName, before);
    });

    test('says so again when the same bad prefix is tried twice', () async {
      await save('R/F');
      final second = await save('R/F');
      expect(second.message, receiptPrefixRejected);
    });

    test('a good prefix is tidied and saved', () async {
      final state = await save('  rmf2 ');

      expect(state.message, 'Gym details saved.');
      expect((await repo.get()).receiptPrefix, 'RMF2');
    });
  });

  group('ReceiptStorage', () {
    late Directory workspace;
    late Directory root;
    late ReceiptStorage storage;

    setUp(() async {
      workspace = await Directory.systemTemp.createTemp('rmf-receipt-prefix');
      root = Directory(p.join(workspace.path, 'data', 'receipts'))
        ..createSync(recursive: true);
      storage = _FakeStorage(root);
    });

    tearDown(() async {
      if (await workspace.exists()) await workspace.delete(recursive: true);
    });

    List<String> everythingOutsideRoot() => workspace
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => f.path)
        .where((path) => !p.isWithin(root.path, path))
        .toList();

    test('a receipt number can never name a file outside the receipts folder',
        () async {
      for (final prefix in escaping) {
        final number = formatReceiptNumber(prefix, 2026, 1);
        await expectLater(
          storage.save('$number.png', Uint8List.fromList([1, 2, 3])),
          throwsArgumentError,
          reason: 'prefix "$prefix" produced $number',
        );
      }

      expect(everythingOutsideRoot(), isEmpty,
          reason: 'nothing may be written before the refusal');
    });

    test('a name Windows would refuse, or read as a hidden stream, is refused '
        'on every computer', () async {
      for (final prefix in ['RMF:2026', 'RMF?', 'R"F', 'R|F']) {
        final number = formatReceiptNumber(prefix, 2026, 1);
        await expectLater(
          storage.save('$number.png', Uint8List.fromList([1])),
          throwsArgumentError,
          reason: number,
        );
      }
      expect(root.listSync(), isEmpty);
    });

    test('an ordinary receipt is still saved where it belongs', () async {
      final number = formatReceiptNumber('RMF', 2026, 184);
      final path =
          await storage.save('$number.png', Uint8List.fromList([1, 2, 3]));

      expect(path, 'RMF-2026-000184.png');
      expect(File(p.join(root.path, path)).readAsBytesSync(), [1, 2, 3]);
    });
  });
}
