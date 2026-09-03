import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/bloc/member_form_bloc.dart';
import 'package:rich_man_fitness/data/audit_repository.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/member_repository.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/domain/billing_cycle.dart';
import 'package:rich_man_fitness/services/whatsapp/member_welcome_service.dart';
import 'package:rich_man_fitness/services/whatsapp/message_texts.dart';
import 'package:rich_man_fitness/services/whatsapp/whatsapp_client.dart';

/// Records what it was asked to send, and can be told to fail or to hang.
class _RecordingClient implements WhatsAppClient {
  _RecordingClient({this.failWith, this.throwOnSend = false, this.gate});

  final String? failWith;
  final bool throwOnSend;

  /// Held open to keep a send in flight, so a second one arriving mid-flight
  /// can be tested.
  final Completer<void>? gate;

  final texts = <WhatsAppTextInput>[];
  final templates = <WhatsAppTemplateInput>[];

  @override
  WhatsAppProviderKind get kind => WhatsAppProviderKind.mock;

  @override
  Future<WhatsAppSendResult> send(WhatsAppSendInput input) async =>
      const WhatsAppSendSuccess('stub.image');

  @override
  Future<WhatsAppSendResult> sendText(WhatsAppTextInput input) async {
    texts.add(input);
    if (gate != null) await gate!.future;
    if (throwOnSend) throw StateError('the provider exploded');
    final failure = failWith;
    return failure == null
        ? WhatsAppSendSuccess('stub.text.${texts.length}')
        : WhatsAppSendFailure(failure);
  }

  @override
  Future<WhatsAppSendResult> sendTemplate(WhatsAppTemplateInput input) async {
    templates.add(input);
    if (throwOnSend) throw StateError('the provider exploded');
    final failure = failWith;
    return failure == null
        ? WhatsAppSendSuccess('stub.template.${templates.length}')
        : WhatsAppSendFailure(failure);
  }
}

/// A new member is greeted once, after they are saved, and never at the cost of
/// the member record itself.
void main() {
  late AppDatabase db;
  late MemberRepository members;
  late AuditRepository audit;
  late int monthlyPlanId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedDatabase(db);
    audit = AuditRepository(db);
    members = MemberRepository(db, audit: audit);
    monthlyPlanId = (await (db.select(db.membershipPlans)
              ..where((p) => p.name.equals('Monthly')))
            .getSingle())
        .id;
  });

  tearDown(() => db.close());

  MemberWelcomeService serviceWith(WhatsAppClient client) =>
      MemberWelcomeService(
        db: db,
        clientFactory: () async => client,
        audit: audit,
      );

  Future<int> addMember({
    String name = 'Ali Raza',
    String phone = '+923001234567',
    String? phoneRaw,
  }) =>
      members.create(
        fullName: name,
        phone: phone,
        phoneRaw: phoneRaw,
        planId: monthlyPlanId,
        joiningDate: DateTime.utc(2026, 8, 1),
      );

  Future<List<AuditEvent>> welcomeEvents() async =>
      (await db.select(db.auditEvents).get())
          .where((e) => e.action.startsWith('whatsapp.welcome'))
          .toList();

  group('the message itself', () {
    test('goes to the member on their own number, in E.164', () async {
      final client = _RecordingClient();
      final memberId = await addMember(phone: '+923001234567');

      final outcome = await serviceWith(client).sendWelcome(memberId: memberId);

      expect(outcome, isA<WelcomeSent>());
      expect(client.texts.single.to, '+923001234567');
    });

    test('normalizes a number typed the way the gym writes them', () async {
      final client = _RecordingClient();
      // What MemberRepository stores for "0300-1234567" typed into the form.
      final memberId =
          await addMember(phone: '+923001234567', phoneRaw: '0300-1234567');

      await serviceWith(client).sendWelcome(memberId: memberId);

      expect(client.texts.single.to, '+923001234567',
          reason: 'Meta will not accept the local form');
    });

    test('is the one welcome text, carrying the gym name', () async {
      final client = _RecordingClient();
      final memberId = await addMember(name: 'Ali Raza');

      await serviceWith(client).sendWelcome(memberId: memberId);

      final body = client.texts.single.body;
      expect(body, contains('Rich Man Fitness'));
      expect(body, contains('successfully been added as a member'));
      expect(
        body,
        welcomeMessage(
          gymName: 'Rich Man Fitness',
          memberName: 'Ali Raza',
          memberCode: 1,
        ),
        reason: 'the wording lives in message_texts.dart, not in the service',
      );
    });

    test('follows the gym name when the owner renames the gym', () async {
      await (db.update(db.gymSettings)..where((s) => s.id.equals(1)))
          .write(const GymSettingsCompanion(gymName: Value('Iron House')));

      final client = _RecordingClient();
      await serviceWith(client).sendWelcome(memberId: await addMember());

      expect(client.texts.single.body, contains('Iron House'));
    });
  });

  group('exactly one welcome per member', () {
    test('a second attempt sends nothing', () async {
      final client = _RecordingClient();
      final service = serviceWith(client);
      final memberId = await addMember();

      expect(await service.sendWelcome(memberId: memberId), isA<WelcomeSent>());
      final second = await service.sendWelcome(memberId: memberId);

      expect(second, isA<WelcomeSkipped>());
      expect(client.texts, hasLength(1));
    });

    test('a fresh service still knows, because the log remembers', () async {
      final first = _RecordingClient();
      await serviceWith(first).sendWelcome(memberId: await addMember());

      final second = _RecordingClient();
      final again = await serviceWith(second)
          .sendWelcome(memberId: (await db.select(db.members).getSingle()).id);

      expect(again, isA<WelcomeSkipped>());
      expect(second.texts, isEmpty,
          reason: 'restarting the app must not re-greet every member');
    });

    test('two sends racing each other produce one message', () async {
      final gate = Completer<void>();
      final client = _RecordingClient(gate: gate);
      final service = serviceWith(client);
      final memberId = await addMember();

      // The second submit arrives while the first is still waiting on the
      // provider — before any audit row exists to notice it.
      final first = service.sendWelcome(memberId: memberId);
      final second = await service.sendWelcome(memberId: memberId);
      gate.complete();

      expect(await first, isA<WelcomeSent>());
      expect(second, isA<WelcomeSkipped>());
      expect(client.texts, hasLength(1));
    });

    test('a failed send is not treated as already sent', () async {
      final failing = _RecordingClient(failWith: 'temporary outage');
      final memberId = await addMember();

      expect(await serviceWith(failing).sendWelcome(memberId: memberId),
          isA<WelcomeFailed>());

      final retrying = _RecordingClient();
      expect(await serviceWith(retrying).sendWelcome(memberId: memberId),
          isA<WelcomeSent>(),
          reason: 'the member has still never been greeted');
    });
  });

  group('when the message cannot be sent', () {
    test('an unusable number is refused before an API call is spent', () async {
      final client = _RecordingClient();
      // Written straight to the table: the form will not accept this, but an
      // imported row can hold anything.
      final memberId = await addMember(phone: 'NILL');

      final outcome = await serviceWith(client).sendWelcome(memberId: memberId);

      expect(outcome, isA<WelcomeFailed>());
      expect(client.texts, isEmpty);
      expect(await db.select(db.members).get(), hasLength(1),
          reason: 'the member is not the thing that went wrong');
    });

    test('a provider that throws is reported, not propagated', () async {
      final memberId = await addMember();

      final outcome = await serviceWith(_RecordingClient(throwOnSend: true))
          .sendWelcome(memberId: memberId);

      expect(outcome, isA<WelcomeFailed>());
    });

    test('an unconfigured provider is reported without naming a token',
        () async {
      final service = MemberWelcomeService(
        db: db,
        clientFactory: () async =>
            throw StateError('WhatsApp is set to Meta but is missing: '
                'Access token'),
        audit: audit,
      );

      final outcome = await service.sendWelcome(memberId: await addMember());

      expect(outcome, isA<WelcomeFailed>());
      final detail = (await welcomeEvents()).single.detail ?? '';
      expect(detail, contains('Access token'));
      expect(detail, isNot(contains('Bearer')));
    });

    test('the log records the failure without the full number', () async {
      final memberId = await addMember(phone: '+923001234567');

      await serviceWith(_RecordingClient(failWith: 'HTTP 401'))
          .sendWelcome(memberId: memberId);

      final event = (await welcomeEvents()).single;
      expect(event.action, AuditAction.whatsAppWelcomeFailed);
      expect(event.outcome, AuditOutcome.failed);
      expect(event.summary, contains('••••4567'));
      expect(event.summary, isNot(contains('+923001234567')));
    });

    test('a member who no longer exists is not a crash', () async {
      expect(await serviceWith(_RecordingClient()).sendWelcome(memberId: 9999),
          isA<WelcomeFailed>());
    });
  });

  group('the Add Member form', () {
    MemberFormBloc formFor(WhatsAppClient client, {int? memberId}) =>
        MemberFormBloc(
          repository: members,
          memberId: memberId,
          welcome: serviceWith(client),
        );

    MemberFormSubmitted submission({
      String name = 'Ali Raza',
      String phone = '0300-1234567',
      bool confirmSharedPhone = false,
    }) =>
        MemberFormSubmitted(
          fullName: name,
          rawPhone: phone,
          planId: monthlyPlanId,
          joiningDate: DateTime(2026, 8, 1),
          confirmSharedPhone: confirmSharedPhone,
        );

    Future<MemberFormState> submit(
      MemberFormBloc bloc,
      MemberFormSubmitted event,
    ) async {
      bloc.add(const MemberFormLoaded());
      bloc.add(event);
      return bloc.stream.firstWhere((s) =>
          s.status == MemberFormStatus.saved ||
          s.status == MemberFormStatus.failed ||
          s.status == MemberFormStatus.confirmSharedPhone);
    }

    test('greets a new member once they are saved', () async {
      final client = _RecordingClient();
      final bloc = formFor(client);

      final state = await submit(bloc, submission());

      expect(state.status, MemberFormStatus.saved);
      expect(state.welcome, isA<WelcomeSent>());
      expect(await db.select(db.members).get(), hasLength(1));
      expect(client.texts.single.to, '+923001234567',
          reason: 'the form normalizes what was typed before it is stored');
      await bloc.close();
    });

    test('keeps the member when the message fails', () async {
      final client = _RecordingClient(failWith: 'Meta says no');
      final bloc = formFor(client);

      final state = await submit(bloc, submission());

      expect(state.status, MemberFormStatus.saved,
          reason: 'a messaging failure must never lose a member');
      expect(state.welcome, isA<WelcomeFailed>());
      expect(await db.select(db.members).get(), hasLength(1));
      await bloc.close();
    });

    test('a member who is never saved is never greeted', () async {
      final client = _RecordingClient();
      final bloc = formFor(client);

      final state = await submit(bloc, submission(phone: 'NILL'));

      expect(state.status, MemberFormStatus.failed);
      expect(await db.select(db.members).get(), isEmpty);
      expect(client.texts, isEmpty);
      await bloc.close();
    });

    test('editing a member sends nothing', () async {
      final existing = await addMember();
      final client = _RecordingClient();
      final bloc = formFor(client, memberId: existing);

      final state = await submit(bloc, submission(name: 'Ali Raza Khan'));

      expect(state.status, MemberFormStatus.saved);
      expect(state.welcome, isNull);
      expect(client.texts, isEmpty);
      await bloc.close();
    });

    test('a double-clicked Save creates one member and sends one message',
        () async {
      final client = _RecordingClient();
      final bloc = formFor(client);

      bloc.add(const MemberFormLoaded());
      bloc.add(submission());
      bloc.add(submission());

      await bloc.stream
          .firstWhere((s) => s.status == MemberFormStatus.saved);
      // Let anything the second event might still be doing finish.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(await db.select(db.members).get(), hasLength(1));
      expect(client.texts, hasLength(1));
      expect(await welcomeEvents(), hasLength(1));
      await bloc.close();
    });

    test('a form with no messaging wired up still saves the member', () async {
      final bloc = MemberFormBloc(repository: members);

      final state = await submit(bloc, submission());

      expect(state.status, MemberFormStatus.saved);
      expect(state.welcome, isNull);
      expect(await db.select(db.members).get(), hasLength(1));
      await bloc.close();
    });
  });

  group('the welcome template', () {
    Future<void> registerTemplate({String name = 'welcome_member'}) =>
        (db.update(db.gymSettings)..where((s) => s.id.equals(1))).write(
          GymSettingsCompanion(whatsappWelcomeTemplate: Value(name)),
        );

    test('free text is still sent when no template is registered', () async {
      final client = _RecordingClient();

      await serviceWith(client).sendWelcome(memberId: await addMember());

      expect(client.texts, hasLength(1));
      expect(client.templates, isEmpty);
    });

    test('sends the registered template instead of free text, with the '
        'right placeholders', () async {
      await registerTemplate();
      final client = _RecordingClient();
      final memberId =
          await addMember(name: 'Ali Raza', phone: '+923001234567');

      final outcome = await serviceWith(client).sendWelcome(memberId: memberId);

      expect(outcome, isA<WelcomeSent>());
      expect(client.texts, isEmpty,
          reason: 'a registered template replaces free text, not adds to it');
      final sent = client.templates.single;
      expect(sent.to, '+923001234567');
      expect(sent.templateName, 'welcome_member');
      expect(sent.languageCode, 'en');

      // "Valid until" is the last day covered by the member's first cycle —
      // one month on from a 1 Aug joining date, on the Monthly plan.
      final firstCycle = firstCycleFor(
        joiningDate: DateTime.utc(2026, 8, 1),
        durationMonths: 1,
      );
      expect(
        sent.bodyParams,
        welcomeTemplateParams(
          memberName: 'Ali Raza',
          memberCode: 1,
          planName: 'Monthly',
          validUntil: firstCycle.end.subtract(const Duration(days: 1)),
        ),
      );
    });

    test('follows a non-default template language', () async {
      await (db.update(db.gymSettings)..where((s) => s.id.equals(1))).write(
        const GymSettingsCompanion(
          whatsappWelcomeTemplate: Value('welcome_member'),
          whatsappWelcomeTemplateLanguage: Value('en_US'),
        ),
      );
      final client = _RecordingClient();

      await serviceWith(client).sendWelcome(memberId: await addMember());

      expect(client.templates.single.languageCode, 'en_US');
    });

    test('a member with no active plan fails cleanly rather than guessing '
        'a date', () async {
      await registerTemplate();
      final client = _RecordingClient();
      final memberId = await addMember();
      // Simulates a membership closed before the welcome message ever went
      // out — the one way a member created through the normal form (which
      // always assigns a plan) can end up without an open one.
      await (db.update(db.memberships)..where((m) => m.memberId.equals(memberId)))
          .write(MembershipsCompanion(endDate: Value(DateTime.utc(2026, 8, 2))));

      final outcome = await serviceWith(client).sendWelcome(memberId: memberId);

      expect(outcome, isA<WelcomeFailed>());
      expect(client.templates, isEmpty);
      expect(await db.select(db.members).get(), hasLength(1),
          reason: 'the member is not the thing that went wrong');
    });

    test('a failed template send is recorded like any other failure',
        () async {
      await registerTemplate();
      final client = _RecordingClient(failWith: 'template does not exist');

      final outcome =
          await serviceWith(client).sendWelcome(memberId: await addMember());

      expect(outcome, isA<WelcomeFailed>());
      final event = (await welcomeEvents()).single;
      expect(event.action, AuditAction.whatsAppWelcomeFailed);
      expect(event.detail, contains('template does not exist'));
    });
  });

  group('the log', () {
    test('records a successful welcome against the member', () async {
      final memberId = await addMember(name: 'Ali Raza');

      await serviceWith(_RecordingClient()).sendWelcome(memberId: memberId);

      final event = (await welcomeEvents()).single;
      expect(event.action, AuditAction.whatsAppWelcomeSent);
      expect(event.outcome, AuditOutcome.success);
      expect(event.category, AuditCategory.whatsapp);
      expect(event.memberId, memberId);
      expect(event.memberName, 'Ali Raza');
    });
  });
}
