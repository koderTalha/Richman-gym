import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/database.dart';
import '../data/receipt_repository.dart';
import '../data/settings_repository.dart';
import '../services/record_payment_service.dart';
import '../services/whatsapp/whatsapp_client.dart';

sealed class WhatsAppEvent extends Equatable {
  const WhatsAppEvent();
  @override
  List<Object?> get props => const [];
}

class WhatsAppRequested extends WhatsAppEvent {
  const WhatsAppRequested();
}

class WhatsAppFilterChanged extends WhatsAppEvent {
  const WhatsAppFilterChanged(this.status);
  final WhatsAppStatus? status;
  @override
  List<Object?> get props => [status];
}

class WhatsAppRetryRequested extends WhatsAppEvent {
  const WhatsAppRetryRequested(this.receiptId);
  final int receiptId;
  @override
  List<Object?> get props => [receiptId];
}

enum WhatsAppScreenStatus { loading, ready, failed }

class WhatsAppState extends Equatable {
  const WhatsAppState({
    this.status = WhatsAppScreenStatus.loading,
    this.rows = const [],
    this.filter,
    this.config,
    this.retryingReceiptId,
    this.message,
    this.error,
  });

  final WhatsAppScreenStatus status;
  final List<WhatsAppMessageRow> rows;
  final WhatsAppStatus? filter;
  final WhatsAppConfig? config;
  final int? retryingReceiptId;
  final String? message;
  final String? error;

  WhatsAppState copyWith({
    WhatsAppScreenStatus? status,
    List<WhatsAppMessageRow>? rows,
    WhatsAppStatus? filter,
    bool clearFilter = false,
    WhatsAppConfig? config,
    int? retryingReceiptId,
    bool clearRetrying = false,
    String? message,
    String? error,
  }) =>
      WhatsAppState(
        status: status ?? this.status,
        rows: rows ?? this.rows,
        filter: clearFilter ? null : (filter ?? this.filter),
        config: config ?? this.config,
        retryingReceiptId:
            clearRetrying ? null : (retryingReceiptId ?? this.retryingReceiptId),
        message: message,
        error: error,
      );

  @override
  List<Object?> get props => [
        status,
        rows.length,
        filter,
        config?.kind,
        config?.isConfigured,
        retryingReceiptId,
        message,
        error,
      ];
}

class WhatsAppBloc extends Bloc<WhatsAppEvent, WhatsAppState> {
  WhatsAppBloc({
    required ReceiptRepository repository,
    required SettingsRepository settings,
    required RecordPaymentService service,
  })  : _repository = repository,
        _settings = settings,
        _service = service,
        super(const WhatsAppState()) {
    on<WhatsAppRequested>((_, emit) => _load(emit));
    on<WhatsAppFilterChanged>((event, emit) {
      emit(state.copyWith(
          filter: event.status, clearFilter: event.status == null));
      return _load(emit);
    });
    on<WhatsAppRetryRequested>(_onRetry);
  }

  final ReceiptRepository _repository;
  final SettingsRepository _settings;
  final RecordPaymentService _service;

  Future<void> _load(Emitter<WhatsAppState> emit) async {
    emit(state.copyWith(status: WhatsAppScreenStatus.loading));
    try {
      emit(state.copyWith(
        status: WhatsAppScreenStatus.ready,
        rows: await _repository.messages(status: state.filter),
        config: await _settings.whatsAppConfig(),
        clearRetrying: true,
      ));
    } catch (e) {
      emit(state.copyWith(status: WhatsAppScreenStatus.failed, error: '$e'));
    }
  }

  Future<void> _onRetry(
    WhatsAppRetryRequested event,
    Emitter<WhatsAppState> emit,
  ) async {
    emit(state.copyWith(retryingReceiptId: event.receiptId));

    final outcome = await _service.resend(event.receiptId);
    final message = switch (outcome) {
      WhatsAppSent() => 'Receipt sent on WhatsApp.',
      WhatsAppFailed(:final error) => 'Send failed: $error',
      WhatsAppNotRequested() => null,
    };

    emit(state.copyWith(message: message, clearRetrying: true));
    await _load(emit);
  }
}
