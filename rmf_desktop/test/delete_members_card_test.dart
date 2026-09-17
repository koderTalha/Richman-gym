import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/bloc/auth_bloc.dart';
import 'package:rich_man_fitness/data/audit_repository.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/member_repository.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/services/member_purge_service.dart';
import 'package:rich_man_fitness/services/receipt_storage.dart';
import 'package:rich_man_fitness/theme/app_theme.dart';
import 'package:rich_man_fitness/ui/settings/delete_members_card.dart';

class _FakeStorage extends ReceiptStorage {
  _FakeStorage(this._dir);
  final Directory _dir;

  @override
  Future<Directory> root() async => _dir;
}

const _counts = MemberDataCounts(
  members: 20,
  memberships: 20,
  billingCycles: 46,
  payments: 31,
  paymentTotalMinor: 1700000,
  receipts: 31,
  whatsAppMessages: 12,
  reminders: 4,
  notes: 2,
  pricingRecords: 46,
  membershipChanges: 3,
  paymentAllocations: 31,
);

/// The guard in front of the only button in the app that deletes money nobody
/// singled out first.
///
/// Deleting one member's payments asks for that member's name. This deletes
/// every member there is, so the name of any one of them would be the wrong
/// question — it asks instead for a phrase that appears nowhere else and says
/// what is about to happen.
void main() {
  group('the confirmation dialog', () {
    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildDarkTheme(),
        home: const Scaffold(
          body: DeleteMembersConfirmDialog(counts: _counts),
        ),
      ));
    }

    FilledButton confirm(WidgetTester tester) =>
        tester.widget<FilledButton>(find.byKey(deleteMembersConfirmKey));

    testWidgets('says exactly what is about to go', (tester) async {
      await pump(tester);

      expect(find.text('20'), findsWidgets, reason: 'the member count');
      expect(find.textContaining('Rs. 17,000'), findsOneWidget);
      expect(find.textContaining('cannot be undone'), findsOneWidget);
      expect(find.textContaining('Take a backup first'), findsOneWidget);
    });

    testWidgets('starts disabled', (tester) async {
      await pump(tester);

      expect(confirm(tester).onPressed, isNull);
    });

    testWidgets('stays disabled for anything but the phrase', (tester) async {
      await pump(tester);

      for (final wrong in ['yes', 'DELETE', 'delete members data', 'MEMBERS']) {
        await tester.enterText(find.byType(TextField), wrong);
        await tester.pump();
        expect(confirm(tester).onPressed, isNull, reason: '"$wrong" armed it');
      }
    });

    testWidgets('stays disabled for the phrase in lower case', (tester) async {
      await pump(tester);

      await tester.enterText(find.byType(TextField), 'delete members');
      await tester.pump();

      expect(confirm(tester).onPressed, isNull,
          reason: 'the capitals are the whole of what makes this harder to '
              'type than "yes"');
    });

    testWidgets('the exact phrase arms it, stray spaces forgiven',
        (tester) async {
      await pump(tester);

      await tester.enterText(find.byType(TextField), '  DELETE MEMBERS ');
      await tester.pump();

      expect(confirm(tester).onPressed, isNotNull);
    });

    testWidgets('the other button keeps everything', (tester) async {
      await pump(tester);

      expect(find.widgetWithText(TextButton, 'Keep everything'), findsOneWidget);
    });
  });

  group('the card', () {
    late Directory workspace;
    late AppDatabase db;
    late int adminId;

    setUp(() async {
      workspace = await Directory.systemTemp.createTemp('rmf-purge-card');
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await seedDatabase(db);
      adminId = (await db.select(db.users).getSingle()).id;
    });

    tearDown(() async {
      await db.close();
      if (await workspace.exists()) await workspace.delete(recursive: true);
    });

    Future<void> addMember() async {
      await MemberRepository(db).create(
        fullName: 'Ali Raza',
        phone: '+923000000001',
        planId: (await (db.select(db.membershipPlans)
                  ..where((p) => p.name.equals('Monthly')))
                .getSingle())
            .id,
        joiningDate: DateTime.utc(2026, 1, 1),
      );
    }

    Future<void> pumpCard(WidgetTester tester) async {
      final admin = await db.select(db.users).getSingle();

      await tester.pumpWidget(MultiRepositoryProvider(
        providers: [
          RepositoryProvider<AppDatabase>.value(value: db),
          RepositoryProvider<AuditRepository>(
              create: (_) => AuditRepository(db)),
          RepositoryProvider<ReceiptStorage>(
              create: (_) => _FakeStorage(workspace)),
        ],
        child: BlocProvider<AuthBloc>(
          create: (_) => AuthBloc(db, restored: admin),
          child: MaterialApp(
            theme: buildDarkTheme(),
            home: Scaffold(
              body: SingleChildScrollView(
                child: DeleteMembersCard(
                  card: ({required title, subtitle, required child}) =>
                      Column(children: [Text(title), child]),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('names what it will delete and what it will keep',
        (tester) async {
      await addMember();
      await pumpCard(tester);

      expect(find.text('Delete all members data'), findsWidgets);
      expect(find.textContaining('cannot be undone'), findsOneWidget);
      expect(
          find.textContaining('Membership plans, gym settings'), findsOneWidget);
    });

    testWidgets('one press is not enough — it asks first', (tester) async {
      await addMember();
      await pumpCard(tester);

      await tester.tap(find.byKey(deleteMembersOpenKey));
      await tester.pumpAndSettle();

      expect(find.byType(DeleteMembersConfirmDialog), findsOneWidget);
      expect(await db.select(db.members).get(), hasLength(1),
          reason: 'opening the question must not answer it');
    });

    testWidgets('backing out of the dialog deletes nothing', (tester) async {
      await addMember();
      await pumpCard(tester);

      await tester.tap(find.byKey(deleteMembersOpenKey));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Keep everything'));
      await tester.pumpAndSettle();

      expect(await db.select(db.members).get(), hasLength(1));
    });

    testWidgets('typing the phrase and confirming empties the members',
        (tester) async {
      await addMember();
      await pumpCard(tester);

      await tester.tap(find.byKey(deleteMembersOpenKey));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), deleteMembersConfirmPhrase);
      await tester.pump();
      await tester.tap(find.byKey(deleteMembersConfirmKey));
      await tester.pumpAndSettle();

      expect(await db.select(db.members).get(), isEmpty);
      expect(await db.select(db.membershipPlans).get(), isNotEmpty);
      expect(find.textContaining('were deleted'), findsOneWidget);
    });

    testWidgets('the owner who pressed it is recorded', (tester) async {
      await addMember();
      await pumpCard(tester);

      await tester.tap(find.byKey(deleteMembersOpenKey));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), deleteMembersConfirmPhrase);
      await tester.pump();
      await tester.tap(find.byKey(deleteMembersConfirmKey));
      await tester.pumpAndSettle();

      final logged = (await db.select(db.auditEvents).get())
          .where((e) => e.action == AuditAction.memberDataPurged);
      expect(logged, hasLength(1));
      expect(logged.single.actorId, adminId);
    });

    testWidgets('the counts on screen fall to nothing afterwards',
        (tester) async {
      await addMember();
      await pumpCard(tester);
      expect(find.text('1'), findsWidgets, reason: 'one member');

      await tester.tap(find.byKey(deleteMembersOpenKey));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), deleteMembersConfirmPhrase);
      await tester.pump();
      await tester.tap(find.byKey(deleteMembersConfirmKey));
      await tester.pumpAndSettle();

      expect(find.text('No member data to delete'), findsOneWidget);
      expect(
        tester
            .widget<ButtonStyleButton>(find.byKey(deleteMembersOpenKey))
            .onPressed,
        isNull,
      );
    });

    testWidgets('with no members at all the button will not open',
        (tester) async {
      await pumpCard(tester);

      expect(find.text('No member data to delete'), findsOneWidget);

      await tester.tap(find.byKey(deleteMembersOpenKey), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.byType(DeleteMembersConfirmDialog), findsNothing);
    });
  });
}
