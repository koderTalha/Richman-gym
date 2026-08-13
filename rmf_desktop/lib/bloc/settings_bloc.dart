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
  });

  final WhatsAppProviderKind provider;
  final bool mockFails;
  final String? phoneNumberId;
  final String? accessToken;
  final String? businessAccountId;
  final String? businessNumber;

  @override
  List<Object?> get props =>
      [provider, mockFails, phoneNumberId, accessToken, businessAccountId];
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
  });

  final int? id;
  final String name;
  final int durationMonths;
  final int priceMinor;
  final bool isActive;
  final String? description;

  @override
  List<Object?> get props =>
      [id, name, durationMonths, priceMinor, isActive, description];
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
    ));
    await _load(emit, message: 'WhatsApp settings saved.');
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
    );
    await _load(emit, message: 'Plan saved.');
  }

  Future<void> _onTogglePlan(
    PlanActiveToggled event,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.setPlanActive(event.id, event.active);
    await _load(emit,
        message: event.active ? 'Plan activated.' : 'Plan deactivated.');
  }
}
