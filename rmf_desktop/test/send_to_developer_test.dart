import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/services/diagnostics/diagnostics_crypto.dart';
import 'package:rich_man_fitness/services/diagnostics/send_to_developer.dart';

final _endpoint =
    Uri.parse('https://script.google.com/macros/s/test-deployment/exec');
final _echo = Uri.parse(
    'https://script.googleusercontent.com/macros/echo?user_content_key=abc');

void main() {
  late Directory workspace;
  late File liveDb;
  late AppDatabase db;
  late DiagnosticsKeyPair developer;

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('rmf-diagnostics-test');
    liveDb = File(p.join(workspace.path, 'richmanfitness.sqlite'));
    db = AppDatabase.forTesting(NativeDatabase(liveDb));
    developer = await DiagnosticsKeyPair.generate();

    await db.into(db.members).insert(MembersCompanion.insert(
          memberCode: 311,
          fullName: 'Member Three Eleven',
          phone: '+923000000311',
          joiningDate: DateTime.utc(2026, 1, 1),
        ));

    final logs = Directory(p.join(workspace.path, 'logs'))..createSync();
    File(p.join(logs.path, 'app-2026-09-30.log'))
        .writeAsStringSync('yesterday INFO  app  --- session started ---\n');
    File(p.join(logs.path, 'app-2026-10-01.log'))
        .writeAsStringSync('today SEVERE payment Record Payment failed\n');
  });

  tearDown(() async {
    await db.close();
    if (await workspace.exists()) await workspace.delete(recursive: true);
  });

  /// Stands in for Google: the web app answers a POST with a redirect to the
  /// page holding its reply, exactly as a deployed Apps Script does.
  MockClient google({
    required List<http.Request> received,
    Object reply = const {'ok': true, 'file': 'https://drive.google.com/x'},
    int postStatus = 302,
    String? replyBody,
  }) =>
      MockClient((request) async {
        received.add(request);
        if (request.method == 'POST') {
          return http.Response('', postStatus,
              headers: {'location': _echo.toString()});
        }
        return http.Response(replyBody ?? jsonEncode(reply), 200,
            headers: {'content-type': 'application/json'});
      });

  SendToDeveloper sender(http.Client client, {Uri? endpoint}) =>
      SendToDeveloper(
        snapshot: vacuumSnapshot(db),
        supportDirectory: () async => workspace,
        endpoint: endpoint ?? _endpoint,
        developerPublicKey: developer.publicKey,
        appVersion: () async => '2.2.0',
        gymName: () async => 'Rich Man Fitness',
        httpClient: client,
        clock: () => DateTime(2026, 10, 1, 14, 32),
      );

  Future<Archive> openUpload(http.Request post) async {
    final body = jsonDecode(post.body) as Map<String, dynamic>;
    final sealed = base64Decode(body['data'] as String);
    final zip = await openDiagnostics(sealed, developer.privateKey);
    return ZipDecoder().decodeBytes(zip);
  }

  test('sends a sealed bundle the developer can open', () async {
    final received = <http.Request>[];

    final result = await sender(google(received: received))
        .send(note: 'Payment for member 311 shows due');

    expect(result, isA<DiagnosticsSent>());
    expect((result as DiagnosticsSent).reference, 'RMF-20261001-1432');

    final post = received.firstWhere((r) => r.method == 'POST');
    expect(post.url, _endpoint);
    final body = jsonDecode(post.body) as Map<String, dynamic>;
    expect(body['format'], 'rmf-diagnostics-1');
    expect(body['name'], 'RMF-20261001-1432.rmfdiag');
    expect(body['gym'], 'Rich Man Fitness');
    expect(body['version'], '2.2.0');
    // What goes to Google in the clear is only what the email subject needs.
    expect(post.body, isNot(contains('Payment for member 311')));
    expect(post.body, isNot(contains('+923000000311')));
  });

  test('the bundle holds a readable database, the logs and the note',
      () async {
    final received = <http.Request>[];
    await sender(google(received: received))
        .send(note: 'Payment for member 311 shows due');

    final archive =
        await openUpload(received.firstWhere((r) => r.method == 'POST'));
    final names = archive.files.map((f) => f.name).toSet();

    expect(names, containsAll([
      'info.json',
      'database/richmanfitness.sqlite',
      'logs/app-2026-09-30.log',
      'logs/app-2026-10-01.log',
    ]));

    final info = jsonDecode(utf8.decode(
            archive.findFile('info.json')!.content as List<int>))
        as Map<String, dynamic>;
    expect(info['note'], 'Payment for member 311 shows due');
    expect(info['appVersion'], '2.2.0');
    expect(info['reference'], 'RMF-20261001-1432');
    expect(info['source'], 'settings');

    // The snapshot opens and holds the member, i.e. it is the real data.
    final copy = File(p.join(workspace.path, 'received.sqlite'))
      ..writeAsBytesSync(archive
          .findFile('database/richmanfitness.sqlite')!
          .content as List<int>);
    final opened = AppDatabase.forTesting(NativeDatabase(copy));
    addTearDown(opened.close);
    final members = await opened.select(opened.members).get();
    expect(members.single.fullName, 'Member Three Eleven');
  });

  test('the Meta access token is not in the copy that is sent', () async {
    // The bundle is sealed, but once unpacked on the developer's Mac it is an
    // ordinary file, and the token in it would keep sending as the gym from
    // anywhere (audit SEC-006).
    const token = 'EAAG-live-token-that-works-from-anywhere-311';
    await seedDatabase(db);
    await db.update(db.gymSettings).write(const GymSettingsCompanion(
          whatsappPhoneNumberId: Value('1234567890'),
          whatsappAccessToken: Value(token),
        ));

    final received = <http.Request>[];
    await sender(google(received: received)).send(note: '');

    final archive =
        await openUpload(received.firstWhere((r) => r.method == 'POST'));
    final bytes = archive
        .findFile('database/richmanfitness.sqlite')!
        .content as List<int>;
    expect(latin1.decode(bytes, allowInvalid: true), isNot(contains(token)),
        reason: 'not even in the page\'s free space, where an UPDATE '
            'would otherwise leave the old value');

    final copy = File(p.join(workspace.path, 'received.sqlite'))
      ..writeAsBytesSync(bytes);
    final opened = AppDatabase.forTesting(NativeDatabase(copy));
    addTearDown(opened.close);
    final settings = await opened.select(opened.gymSettings).getSingle();
    expect(settings.whatsappAccessToken, isNull);
    expect(settings.whatsappPhoneNumberId, '1234567890',
        reason: 'only the secret is taken out');

    // And the gym's own copy is untouched.
    expect((await db.select(db.gymSettings).getSingle()).whatsappAccessToken,
        token);
  });

  test('leaves no snapshot behind on this computer', () async {
    final before = workspace
        .listSync(recursive: true)
        .map((e) => p.relative(e.path, from: workspace.path))
        .toSet();

    await sender(google(received: [])).send(note: '');

    final after = workspace
        .listSync(recursive: true)
        .map((e) => p.relative(e.path, from: workspace.path))
        // Drift's own sidecars come and go with the open connection.
        .where((n) => !n.endsWith('-wal') && !n.endsWith('-shm'))
        .toSet();
    expect(after.difference(before), isEmpty);
  });

  test('a copy of an unopenable database is sent as the files on disk',
      () async {
    await db.close();
    File('${liveDb.path}-wal').writeAsStringSync('pending writes');
    final received = <http.Request>[];

    final result = await SendToDeveloper(
      snapshot: rawFileSnapshot(liveDb),
      supportDirectory: () async => workspace,
      endpoint: _endpoint,
      developerPublicKey: developer.publicKey,
      appVersion: () async => '2.2.0',
      gymName: () async => null,
      httpClient: google(received: received),
      clock: () => DateTime(2026, 10, 1, 14, 32),
    ).send(note: 'App will not open', source: 'startup-failure',
        startupError: 'SqliteException(26): file is not a database');

    expect(result, isA<DiagnosticsSent>());
    final post = received.firstWhere((r) => r.method == 'POST');
    final archive = await openUpload(post);
    expect(archive.files.map((f) => f.name), containsAll([
      'database/richmanfitness.sqlite',
      'database/richmanfitness.sqlite-wal',
    ]));
    final info = jsonDecode(utf8.decode(
            archive.findFile('info.json')!.content as List<int>))
        as Map<String, dynamic>;
    expect(info['source'], 'startup-failure');
    expect(info['startupError'], contains('file is not a database'));
    expect((jsonDecode(post.body) as Map)['gym'], 'Unknown gym');

    // Reopened so tearDown's close has something to close.
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  group('when it cannot be sent', () {
    test('a build without an upload address says so, and sends nothing',
        () async {
      final received = <http.Request>[];
      final s = SendToDeveloper(
        snapshot: vacuumSnapshot(db),
        supportDirectory: () async => workspace,
        endpoint: null,
        developerPublicKey: developer.publicKey,
        appVersion: () async => '2.2.0',
        gymName: () async => 'Rich Man Fitness',
        httpClient: google(received: received),
      );

      expect(s.isConfigured, isFalse);
      final result = await s.send(note: '');
      expect(result, isA<DiagnosticsFailed>());
      expect(received, isEmpty);
    });

    test('the script refusing the file is reported with its reason',
        () async {
      final result = await sender(google(
        received: [],
        reply: const {'ok': false, 'error': 'Daily limit reached'},
      )).send(note: '');

      expect(result, isA<DiagnosticsFailed>());
      expect((result as DiagnosticsFailed).message,
          contains('Daily limit reached'));
    });

    test('a sign-in page instead of a reply means the script is not public',
        () async {
      final result = await sender(google(
        received: [],
        replyBody: '<!DOCTYPE html><html><title>Sign in</title></html>',
      )).send(note: '');

      expect(result, isA<DiagnosticsFailed>());
      expect((result as DiagnosticsFailed).message, contains('Anyone'));
    });

    test('an error status from Google is not mistaken for success', () async {
      final result = await sender(google(received: [], postStatus: 500))
          .send(note: '');

      expect(result, isA<DiagnosticsFailed>());
    });

    test('no internet is said in plain words', () async {
      final result = await sender(MockClient((_) async =>
              throw const SocketException('Failed host lookup: '
                  "'script.google.com'")))
          .send(note: '');

      expect(result, isA<DiagnosticsFailed>());
      expect((result as DiagnosticsFailed).message, contains('internet'));
    });
  });
}
