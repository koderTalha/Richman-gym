import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/data/cycle_repricing.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/member_repository.dart';
import 'package:rich_man_fitness/domain/member_status.dart';

/// Runs the re-pricing sweep against a copy of a real gym database and reports
/// what it would change. Nothing is written to the file you point it at — the
/// copy is made here.
///
///     DB=~/Downloads/database.sqlite fvm flutter test tool/verify_on_owner_db.dart
void main() {
  test('re-pricing sweep against a real database', () async {
    final source = File(Platform.environment['DB'] ??
        '${Platform.environment['HOME']}/Downloads/database.sqlite');
    if (!await source.exists()) {
      // ignore: avoid_print
      print('No database at ${source.path} — set DB=<path>.');
      return;
    }

    final work = await Directory.systemTemp.createTemp('rmf-verify');
    addTearDown(() => work.delete(recursive: true));
    // Bytes rather than File.copy, which carries the source's permissions —
    // a read-only original would give SQLite a database it cannot write.
    final copy = File('${work.path}/copy.sqlite');
    await copy.writeAsBytes(await source.readAsBytes());

    final db = AppDatabase.forTesting(NativeDatabase(copy));
    addTearDown(db.close);
    final members = MemberRepository(db);

    final at = DateTime.now().toUtc();

    Future<Map<MemberStatus, int>> tally() async {
      final counts = <MemberStatus, int>{};
      for (final row in await members.list(now: at)) {
        counts[row.status] = (counts[row.status] ?? 0) + 1;
      }
      return counts;
    }

    final before = await tally();
    final beforeDue = await members.list(filter: MemberFilter.due, now: at);

    final repriced = await repriceAllOpenCycles(db, now: at);

    final after = await tally();
    final afterDue = await members.list(filter: MemberFilter.due, now: at);

    final fixed = beforeDue
        .map((r) => r.id)
        .toSet()
        .difference(afterDue.map((r) => r.id).toSet());

    // ignore: avoid_print
    print('''

Database: ${source.path}
Cycles re-priced: $repriced

              before   after
  PAID        ${'${before[MemberStatus.paid] ?? 0}'.padLeft(6)}  ${'${after[MemberStatus.paid] ?? 0}'.padLeft(6)}
  DUE         ${'${before[MemberStatus.due] ?? 0}'.padLeft(6)}  ${'${after[MemberStatus.due] ?? 0}'.padLeft(6)}
  EXPIRED     ${'${before[MemberStatus.expired] ?? 0}'.padLeft(6)}  ${'${after[MemberStatus.expired] ?? 0}'.padLeft(6)}
  INACTIVE    ${'${before[MemberStatus.inactive] ?? 0}'.padLeft(6)}  ${'${after[MemberStatus.inactive] ?? 0}'.padLeft(6)}

Members who stop showing as owing money: ${fixed.length}
''');

    for (final row in beforeDue.where((r) => fixed.contains(r.id)).take(12)) {
      // ignore: avoid_print
      print('  #${row.member.memberCode}  ${row.member.fullName}  '
          '(was owing ${((row.outstandingMinor ?? 0) / 100).toStringAsFixed(0)})');
    }
  });
}
