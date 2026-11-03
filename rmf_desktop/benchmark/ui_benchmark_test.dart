// How much the Members and Payments screens build and animate when a list
// arrives. Run on purpose, like perf_benchmark_test.dart:
//
//     flutter test benchmark/ui_benchmark_test.dart --dart-define=PERF_LABEL=before
//
// Widget tests run in debug mode, so the milliseconds are larger than on the
// counter PC; what is comparable between two runs is their ratio, and the
// counts — rows built and entrance animations started — are exact.
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/member_repository.dart';
import 'package:rich_man_fitness/data/payment_repository.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/theme/app_theme.dart';
import 'package:rich_man_fitness/ui/members/members_screen.dart';
import 'package:rich_man_fitness/ui/payments/payments_screen.dart';
import 'package:rich_man_fitness/ui/widgets/fade_rise.dart';

const _label = String.fromEnvironment('PERF_LABEL', defaultValue: 'run');

Future<void> _seed(AppDatabase db, int count) async {
  await seedDatabase(db);
  final admin = (await db.select(db.users).getSingle()).id;
  final plan = (await db.select(db.membershipPlans).get()).first;
  await db.batch((b) {
    for (var i = 1; i <= count; i++) {
      b.insert(
          db.members,
          MembersCompanion.insert(
            id: Value(i),
            memberCode: i,
            fullName: 'Test Member $i',
            phone: '+92300${1000000 + i}',
            joiningDate: DateTime.utc(2026, 1, 1),
          ));
      b.insert(
          db.memberships,
          MembershipsCompanion.insert(
              id: Value(i),
              memberId: i,
              planId: plan.id,
              startDate: DateTime.utc(2026, 1, 1)));
      b.insert(
          db.membershipPeriods,
          MembershipPeriodsCompanion.insert(
            id: Value(i),
            membershipId: i,
            periodStart: DateTime.utc(2026, 10, 1),
            periodEnd: DateTime.utc(2026, 11, 1),
            expectedAmountMinor: plan.priceMinor,
          ));
      b.insert(
          db.payments,
          PaymentsCompanion.insert(
            memberId: i,
            membershipPeriodId: Value(i),
            amountMinor: plan.priceMinor,
            method: PaymentMethod.cash,
            paymentDate: DateTime(2026, 10, 1 + i % 28, 10),
            recordedById: admin,
            idempotencyKey: 'ui-$i',
          ));
    }
  });
}

void main() {
  for (final count in const [600, 2000]) {
    for (final screen in const ['Members', 'Payments']) {
      testWidgets('$screen with $count members', (tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final db = AppDatabase.forTesting(NativeDatabase.memory());
        await tester.runAsync(() => _seed(db, count));

        var rowBuilds = 0;
        final frames = <Duration>[];
        void onTimings(List<FrameTiming> t) {}
        SchedulerBinding.instance.addTimingsCallback(onTimings);

        await tester.pumpWidget(MultiRepositoryProvider(
          providers: [
            RepositoryProvider<AppDatabase>.value(value: db),
            RepositoryProvider<MemberRepository>(
                create: (_) => MemberRepository(db)),
            RepositoryProvider<PaymentRepository>(
                create: (_) => PaymentRepository(db)),
          ],
          child: MaterialApp(
            theme: buildDarkTheme(),
            home: Scaffold(
              body: screen == 'Members'
                  ? const MembersScreen()
                  : const PaymentsScreen(),
            ),
          ),
        ));

        // Let the query finish; then time the frames that draw the list and
        // play its entrance, a second's worth at 60 fps.
        for (var i = 0; i < 30; i++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 5)));
          await tester.pump();
          if (find.textContaining('Test Member').evaluate().isNotEmpty) break;
        }
        final sw = Stopwatch()..start();
        for (var i = 0; i < 60; i++) {
          final f = Stopwatch()..start();
          await tester.pump(const Duration(milliseconds: 16));
          frames.add(f.elapsed);
        }
        sw.stop();
        rowBuilds = find
            .textContaining('Test Member', skipOffstage: false)
            .evaluate()
            .length;
        final animations =
            find.byType(FadeRise, skipOffstage: false).evaluate().length;
        frames.sort();
        // ignore: avoid_print
        print('UI\t$_label\t$screen\t$count\t'
            'first second of frames ${sw.elapsedMilliseconds} ms\t'
            'worst frame ${frames.last.inMilliseconds} ms\t'
            'rows built $rowBuilds\tentrance animations $animations');

        SchedulerBinding.instance.removeTimingsCallback(onTimings);
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(db.close);
      }, timeout: const Timeout(Duration(minutes: 5)));
    }
  }
}
