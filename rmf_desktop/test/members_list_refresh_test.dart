import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/bloc/auth_bloc.dart';
import 'package:rich_man_fitness/bloc/member_detail_bloc.dart';
import 'package:rich_man_fitness/bloc/members_bloc.dart';
import 'package:rich_man_fitness/data/audit_repository.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/member_repository.dart';
import 'package:rich_man_fitness/data/payment_repository.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/services/billing_cycle_service.dart';
import 'package:rich_man_fitness/services/whatsapp/member_welcome_service.dart';
import 'package:rich_man_fitness/services/whatsapp/mock_client.dart';
import 'package:rich_man_fitness/theme/app_theme.dart';
import 'package:rich_man_fitness/ui/members/members_screen.dart';

/// Holds back the answer to one search term until the test releases it, so
/// an older query can be made to finish after a newer one.
class _SlowSearchRepository extends MemberRepository {
  _SlowSearchRepository(super.db, {required this.slowTerm});

  final String slowTerm;
  final release = Completer<void>();

  @override
  Future<({List<MemberRow> rows, Map<MemberFilter, int> counts})>
      listWithCounts({
    String? search,
    MemberFilter filter = MemberFilter.all,
    DateTime? now,
  }) async {
    final result =
        await super.listWithCounts(search: search, filter: filter, now: now);
    if (search == slowTerm) await release.future;
    return result;
  }
}

/// The Members list keeping up with what happens elsewhere: BUG-021 (stale
/// after the detail screen changes something) and BUG-029's search race,
/// from the 1 Oct 2026 audit.
void main() {
  late AppDatabase db;
  late MemberRepository members;
  late int planId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedDatabase(db);
    members = MemberRepository(db);
    planId = (await (db.select(db.membershipPlans)
              ..where((p) => p.name.equals('Monthly')))
            .getSingle())
        .id;
  });

  tearDown(() async => db.close());

  Future<int> join(String name, String phone) => members.create(
        fullName: name,
        phone: phone,
        planId: planId,
        joiningDate: DateTime.utc(2026, 1, 1),
      );

  group('MembersBloc', () {
    test('a slower, older search cannot overwrite a newer one', () async {
      await join('Ali Khan', '+923000000001');
      await join('Bilal Ahmed', '+923000000002');

      final repository = _SlowSearchRepository(db, slowTerm: 'a');
      final bloc = MembersBloc(repository);
      addTearDown(bloc.close);

      bloc.add(const MembersSearchSubmitted('a'));
      bloc.add(const MembersSearchSubmitted('bilal'));
      await bloc.stream.firstWhere((s) =>
          s.status == MembersStatus.ready && s.search == 'bilal');

      // Now the query for "a", which matches both, finally comes back.
      repository.release.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(bloc.state.search, 'bilal');
      expect(bloc.state.rows.map((r) => r.member.fullName), ['Bilal Ahmed'],
          reason: 'the list must answer the search box above it');
    });
  });

  group('MemberDetailBloc', () {
    Future<MemberDetailBloc> detailFor(int id) async {
      final bloc = MemberDetailBloc(
        memberRepository: members,
        paymentRepository: PaymentRepository(db),
        memberId: id,
        actorId: (await db.select(db.users).getSingle()).id,
      );
      addTearDown(bloc.close);
      return bloc;
    }

    test('an ordinary load reports nothing changed', () async {
      final bloc = await detailFor(await join('Ali Khan', '+923000000001'));

      bloc.add(const MemberDetailRequested());
      final ready = await bloc.stream
          .firstWhere((s) => s.status == MemberDetailStatus.ready);

      expect(ready.changed, isFalse);
    });

    test('a reload after a change reports it, and keeps reporting it',
        () async {
      final bloc = await detailFor(await join('Ali Khan', '+923000000001'));
      bloc.add(const MemberDetailRequested());
      await bloc.stream
          .firstWhere((s) => s.status == MemberDetailStatus.ready);

      bloc.add(const MemberDetailRequested(afterChange: true));
      await bloc.stream.firstWhere((s) => s.changed);

      // An identical state is not re-emitted, so there is nothing to wait for
      // on the stream; give the reload time to run instead.
      bloc.add(const MemberDetailRequested());
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(bloc.state.status, MemberDetailStatus.ready);
      expect(bloc.state.changed, isTrue,
          reason: 'a later plain reload does not undo the change');
    });
  });

  group('the Members screen', () {
    Future<void> pumpMembers(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final admin = await db.select(db.users).getSingle();
      final audit = AuditRepository(db);

      await tester.pumpWidget(MultiRepositoryProvider(
        providers: [
          RepositoryProvider<AppDatabase>.value(value: db),
          RepositoryProvider<AuditRepository>.value(value: audit),
          RepositoryProvider<MemberRepository>(
              create: (_) => MemberRepository(db, audit: audit)),
          RepositoryProvider<PaymentRepository>(
              create: (_) => PaymentRepository(db)),
          RepositoryProvider<BillingCycleService>(
              create: (_) => BillingCycleService(db, audit: audit)),
          RepositoryProvider<MemberWelcomeService>(
              create: (_) => MemberWelcomeService(
                    db: db,
                    clientFactory: () async => MockWhatsAppClient(),
                  )),
        ],
        child: BlocProvider<AuthBloc>(
          create: (_) => AuthBloc(db, restored: admin),
          child: MaterialApp(
            theme: buildDarkTheme(),
            home: const Scaffold(body: MembersScreen()),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('an edit made from the detail screen shows in the list on '
        'the way back', (tester) async {
      await join('Ali Khan', '+923000000001');
      await pumpMembers(tester);
      expect(find.text('Ali Khan'), findsOneWidget);

      await tester.tap(find.text('Ali Khan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Full name *'), 'Ali Raza Khan');
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      // Back on the detail screen, which has reloaded; now back to the list.
      expect(find.text('Ali Raza Khan'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      expect(find.byType(MembersScreen), findsOneWidget);
      expect(find.text('Ali Raza Khan'), findsOneWidget,
          reason: 'the list reloads when the detail screen changed anything');
      expect(find.text('Ali Khan'), findsNothing);
    });

    testWidgets('just looking at a member does not reload the list',
        (tester) async {
      await join('Ali Khan', '+923000000001');
      await pumpMembers(tester);

      await tester.tap(find.text('Ali Khan'));
      await tester.pumpAndSettle();

      // Renamed behind the screen's back: only a reload would show it.
      await (db.update(db.members)).write(
          const MembersCompanion(fullName: Value('Changed Elsewhere')));

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      expect(find.text('Ali Khan'), findsOneWidget,
          reason: 'nothing was changed here, so nothing asks for a reload');
    });
  });
}
