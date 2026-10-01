import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/settings_repository.dart';
import 'package:rich_man_fitness/services/reminder_service.dart';
import 'package:rich_man_fitness/theme/app_theme.dart';
import 'package:rich_man_fitness/ui/reminders/reminders_screen.dart';

/// A service whose queue build throws until told otherwise.
class _BrokenService extends ReminderService {
  _BrokenService(AppDatabase db)
      : super(db: db, clientFactory: () async => throw UnimplementedError());

  bool broken = true;

  @override
  Future<List<ReminderCandidate>> buildQueue({DateTime? now}) async {
    if (broken) throw StateError('database is locked');
    return const [];
  }
}

/// What the Reminders screen shows when it cannot do its job, and when what
/// it does would not reach anybody.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.into(db.gymSettings).insert(GymSettingsCompanion.insert());
  });

  tearDown(() => db.close());

  Future<void> pump(WidgetTester tester, ReminderService service) async {
    await tester.pumpWidget(MultiRepositoryProvider(
      providers: [
        RepositoryProvider<SettingsRepository>.value(
            value: SettingsRepository(db)),
        RepositoryProvider<ReminderService>.value(value: service),
      ],
      child: MaterialApp(
        theme: buildDarkTheme(),
        home: const Scaffold(body: RemindersScreen()),
      ),
    ));
    await tester.pumpAndSettle();
  }

  ReminderService working() => ReminderService(
      db: db, clientFactory: () async => throw UnimplementedError());

  testWidgets('a queue that cannot be built says so instead of spinning',
      (tester) async {
    final service = _BrokenService(db);
    await pump(tester, service);

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('could not be loaded'), findsOneWidget);

    service.broken = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(find.textContaining('could not be loaded'), findsNothing);
    expect(find.text('Nobody is due or overdue right now.'), findsOneWidget);
  });

  testWidgets('warns that Mock mode records reminders without sending them',
      (tester) async {
    await pump(tester, working());
    expect(find.byKey(remindersMockWarningKey), findsOneWidget);
  });

  testWidgets('says nothing about Mock mode once Meta is selected',
      (tester) async {
    await (db.update(db.gymSettings)..where((s) => s.id.equals(1))).write(
        const GymSettingsCompanion(
            whatsappProvider: Value(WhatsAppProviderKind.meta)));

    await pump(tester, working());
    expect(find.byKey(remindersMockWarningKey), findsNothing);
  });
}
