import 'package:drift/drift.dart' show Value;
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/database.dart';
import '../data/settings_repository.dart';
import '../services/whatsapp/meta_client.dart';

sealed class SettingsEvent extends Equatable {
  const SettingsEvent();
  @override
  List<Object?> get props => const [];
}

class SettingsRequested extends SettingsEvent {
  const SettingsRequested();
}

class GymInfoSaved extends SettingsEvent {
  const GymInfoSaved({
    required this.gymName,
    required this.phone,
    required this.address,
    required this.receiptPrefix,
    required this.receiptFooter,
  });

  final String gymName;
  final String? phone;
  final String? address;
  final String receiptPrefix;
  final String receiptFooter;

  @override
  List<Object?> get props =>
      [gymName, phone, address, receiptPrefix, receiptFooter];
}

class WhatsAppSettingsSaved extends SettingsEvent {
  const WhatsAppSettingsSaved({
    required this.provider,
    required this.mockFails,
    this.phoneNumberId,
    this.accessToken,
    this.businessAccountId,
    this.businessNumber,
    required this.receiptTemplate,
    required this.receiptTemplateLanguage,
    this.welcomeTemplate,
    required this.welcomeTemplateLanguage,
  });

  final WhatsAppProviderKind provider;
  final bool mockFails;
  final String? phoneNumberId;
  final String? accessToken;
  final String? businessAccountId;
  final String? businessNumber;

  /// The approved template a receipt is sent as, and the language it was
  /// registered under. Never blank — the form substitutes the defaults.
  final String receiptTemplate;
  final String receiptTemplateLanguage;

  /// The approved template a welcome message is sent as, if the gym has
  /// registered one. Null — unlike [receiptTemplate] — keeps the free-text
  /// welcome message the app has always sent; see
  /// `GymSettings.whatsappWelcomeTemplate`.
  final String? welcomeTemplate;
  final String welcomeTemplateLanguage;

  @override
  List<Object?> get props => [
        provider,
        mockFails,
        phoneNumberId,
        accessToken,
        businessAccountId,
        receiptTemplate,
        receiptTemplateLanguage,
        welcomeTemplate,
        welcomeTemplateLanguage,
      ];
}

class ReminderSettingsSaved extends SettingsEvent {
  const ReminderSettingsSaved({
    required this.autoSend,
    required this.daysBefore,
    required this.onDueDate,
    required this.daysAfter,
    required this.sendFromHour,
    required this.sendUntilHour,
    required this.maxPerRun,
    this.template,
    required this.templateLanguage,
    this.paymentInstructions,
  });

  final bool autoSend;

  /// Comma-separated, already validated by the form — see
  /// `domain/reminder_schedule.dart`'s `parseOffsetDays`/`formatOffsetDays`.
  final String daysBefore;
  final bool onDueDate;
  final String daysAfter;
  final int sendFromHour;
  final int sendUntilHour;
  final int maxPerRun;
  final String? template;
  final String templateLanguage;
  final String? paymentInstructions;

  @override
  List<Object?> get props => [
        autoSend,
        daysBefore,
        onDueDate,
        daysAfter,
        sendFromHour,
        sendUntilHour,
        maxPerRun,
        template,
        templateLanguage,
        paymentInstructions,
      ];
}

/// Verifies Meta credentials without sending anything.
class WhatsAppCredentialsTested extends SettingsEvent {
  const WhatsAppCredentialsTested({this.phoneNumberId, this.accessToken});

  final String? phoneNumberId;
  final String? accessToken;

  @override
  List<Object?> get props => [phoneNumberId, accessToken];
}

class PasswordChangeRequested extends SettingsEvent {
  const PasswordChangeRequested({
    required this.userId,
    required this.currentPassword,
    required this.newPassword,
    required this.confirmPassword,
  });

  final int userId;
  final String currentPassword;
  final String newPassword;
  final String confirmPassword;

  @override
  List<Object?> get props => [userId, currentPassword, newPassword];
}

class PlanSaved extends SettingsEvent {
  const PlanSaved({
    this.id,
    required this.name,
    required this.durationMonths,
    required this.priceMinor,
    required this.isActive,
    this.description,
    this.actorId,
  });

  final int? id;
  final String name;
  final int durationMonths;
  final int priceMinor;
  final bool isActive;
  final String? description;

  /// Who is signed in. A plan price change re-prices open bills across the
  /// roster, so the log has to be able to say who did it.
  final int? actorId;

  /// The same event, attributed. The dialog that builds it has no access to
  /// the signed-in user; the screen that shows the dialog does.
  PlanSaved by(int? actorId) => PlanSaved(
        id: id,
        name: name,
        durationMonths: durationMonths,
        priceMinor: priceMinor,
        isActive: isActive,
        description: description,
        actorId: actorId,
      );

  @override
  List<Object?> get props =>
      [id, name, durationMonths, priceMinor, isActive, description, actorId];
}

class PlanActiveToggled extends SettingsEvent {
  const PlanActiveToggled(this.id, this.active);
  final int id;
  final bool active;
  @override
  List<Object?> get props => [id, active];
}

enum SettingsStatus { loading, ready, saving }

class SettingsState extends Equatable {
  const SettingsState({
    this.status = SettingsStatus.loading,
    this.settings,
    this.plans = const [],
    this.message,
    this.testing = false,
    this.testResult,
    this.passwordError,
    this.passwordChanged = false,
  });

  final SettingsStatus status;
  final GymSetting? settings;
  final List<MembershipPlan> plans;
  final String? message;
  final bool testing;
  final MetaVerification? testResult;
  final String? passwordError;
  final bool passwordChanged;

  SettingsState copyWith({
    SettingsStatus? status,
    GymSetting? settings,
    List<MembershipPlan>? plans,
    String? message,
    bool? testing,
    MetaVerification? testResult,
    bool clearTestResult = false,
    String? passwordError,
    bool? passwordChanged,
  }) =>
      SettingsState(
        status: status ?? this.status,
        settings: settings ?? this.settings,
        plans: plans ?? this.plans,
        message: message,
        testing: testing ?? this.testing,
        testResult: clearTestResult ? null : (testResult ?? this.testResult),
        passwordError: passwordError,
        passwordChanged: passwordChanged ?? false,
      );

  @override
  List<Object?> get props => [
        status,
        settings,
        plans.length,
        message,
        testing,
        testResult?.summary,
        passwordError,
        passwordChanged,
      ];
}

class SettingsBloc extends Bloc<SettingsEvent, SettingsState> {
  SettingsBloc(this._repository) : super(const SettingsState()) {
    on<SettingsRequested>((_, emit) => _load(emit));
    on<GymInfoSaved>(_onSaveGymInfo);
    on<WhatsAppSettingsSaved>(_onSaveWhatsApp);
    on<PlanSaved>(_onSavePlan);
    on<PlanActiveToggled>(_onTogglePlan);
    on<WhatsAppCredentialsTested>(_onTestCredentials);
    on<PasswordChangeRequested>(_onChangePassword);
    on<ReminderSettingsSaved>(_onSaveReminderSettings);
  }

  final SettingsRepository _repository;

  Future<void> _load(Emitter<SettingsState> emit, {String? message}) async {
    emit(SettingsState(
      status: SettingsStatus.ready,
      settings: await _repository.get(),
      plans: await _repository.plans(),
      message: message,
    ));
  }

  Future<void> _onSaveGymInfo(
    GymInfoSaved event,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.update(GymSettingsCompanion(
      gymName: Value(event.gymName),
      phone: Value(event.phone),
      address: Value(event.address),
      receiptPrefix: Value(event.receiptPrefix.toUpperCase()),
      receiptFooterMessage: Value(event.receiptFooter),
    ));
    await _load(emit, message: 'Gym details saved.');
  }

  Future<void> _onSaveWhatsApp(
    WhatsAppSettingsSaved event,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.update(GymSettingsCompanion(
      whatsappProvider: Value(event.provider),
      whatsappMockFails: Value(event.mockFails),
      whatsappPhoneNumberId: Value(event.phoneNumberId),
      whatsappAccessToken: Value(event.accessToken),
      whatsappBusinessAccountId: Value(event.businessAccountId),
      whatsappBusinessNumber: Value(event.businessNumber),
      whatsappReceiptTemplate: Value(event.receiptTemplate),
      whatsappReceiptTemplateLanguage: Value(event.receiptTemplateLanguage),
      whatsappWelcomeTemplate: Value(event.welcomeTemplate),
      whatsappWelcomeTemplateLanguage: Value(event.welcomeTemplateLanguage),
    ));
    await _load(emit, message: 'WhatsApp settings saved.');
  }

  Future<void> _onSaveReminderSettings(
    ReminderSettingsSaved event,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.update(GymSettingsCompanion(
      reminderAutoSend: Value(event.autoSend),
      reminderDaysBefore: Value(event.daysBefore),
      reminderOnDueDate: Value(event.onDueDate),
      reminderDaysAfter: Value(event.daysAfter),
      reminderSendFromHour: Value(event.sendFromHour),
      reminderSendUntilHour: Value(event.sendUntilHour),
      reminderMaxPerRun: Value(event.maxPerRun),
      whatsappReminderTemplate: Value(event.template),
      whatsappReminderTemplateLanguage: Value(event.templateLanguage),
      paymentInstructions: Value(event.paymentInstructions),
    ));
    await _load(emit, message: 'Reminder settings saved.');
  }

  Future<void> _onTestCredentials(
    WhatsAppCredentialsTested event,
    Emitter<SettingsState> emit,
  ) async {
    emit(state.copyWith(testing: true, clearTestResult: true));

    final result = await _repository.testWhatsAppCredentials(
      phoneNumberId: event.phoneNumberId,
      accessToken: event.accessToken,
    );

    emit(state.copyWith(testing: false, testResult: result));
  }

  Future<void> _onChangePassword(
    PasswordChangeRequested event,
    Emitter<SettingsState> emit,
  ) async {
    if (event.newPassword != event.confirmPassword) {
      emit(state.copyWith(passwordError: 'The new passwords do not match.'));
      return;
    }

    final error = await _repository.changePassword(
      userId: event.userId,
      currentPassword: event.currentPassword,
      newPassword: event.newPassword,
    );

    if (error != null) {
      emit(state.copyWith(passwordError: error));
      return;
    }

    emit(state.copyWith(
        passwordChanged: true, message: 'Password updated.'));
  }

  Future<void> _onSavePlan(PlanSaved event, Emitter<SettingsState> emit) async {
    await _repository.savePlan(
      id: event.id,
      name: event.name,
      description: event.description,
      durationMonths: event.durationMonths,
      priceMinor: event.priceMinor,
      isActive: event.isActive,
      actorId: event.actorId,
    );
    await _load(emit, message: 'Plan saved.');
  }

  Future<void> _onTogglePlan(
    PlanActiveToggled event,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.setPlanActive(event.id, event.active);

    if (event.active) {
      await _load(emit, message: 'Plan activated.');
      return;
    }

    // Members stay on a plan the gym has stopped selling, and they still have
    // to be editable and billable. Say so rather than letting the owner think
    // deactivating a plan moved everybody off it.
    final inUse = await _repository.planInUse(event.id);
    await _load(emit,
        message: inUse
            ? 'Plan deactivated. Members already on it keep it — '
                'it just stops being offered to new ones.'
            : 'Plan deactivated.');
  }
}
