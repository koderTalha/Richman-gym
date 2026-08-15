import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logging/logging.dart';

import '../data/member_repository.dart';
import '../data/payment_repository.dart';
import '../data/receipt_repository.dart';
import '../domain/member_status.dart';

final _log = Logger('dashboard');

sealed class DashboardEvent extends Equatable {
  const DashboardEvent();
  @override
  List<Object?> get props => const [];
}

class DashboardRequested extends DashboardEvent {
  const DashboardRequested();
}

enum DashboardStatus { loading, ready, failed }

class DashboardState extends Equatable {
  const DashboardState({
    this.status = DashboardStatus.loading,
    this.members = const [],
    this.recent = const [],
    this.revenueTodayMinor = 0,
    this.revenueMonthMinor = 0,
    this.paymentsToday = 0,
    this.failedWhatsApp = 0,
    this.error,
  });

  final DashboardStatus status;
  final List<MemberRow> members;
  final List<PaymentRow> recent;
  final int revenueTodayMinor;
  final int revenueMonthMinor;
  final int paymentsToday;

  /// Receipts whose most recent send attempt failed and needs a retry.
  final int failedWhatsApp;
  final String? error;

  int get activeCount =>
      members.where((m) => m.status != MemberStatus.inactive).length;

  List<MemberRow> get dueMembers => members
      .where((m) =>
          m.status == MemberStatus.due || m.status == MemberStatus.expired)
      .toList();

  @override
  List<Object?> get props => [
        status,
        members.length,
        recent.length,
        revenueTodayMinor,
        revenueMonthMinor,
        paymentsToday,
        failedWhatsApp,
        error,
      ];
}

class DashboardBloc extends Bloc<DashboardEvent, DashboardState> {
  DashboardBloc({
    required MemberRepository memberRepository,
    required PaymentRepository paymentRepository,
    required ReceiptRepository receiptRepository,
    DateTime Function()? clock,
  })  : _members = memberRepository,
        _payments = paymentRepository,
        _receipts = receiptRepository,
        _clock = clock ?? DateTime.now,
        super(const DashboardState()) {
    on<DashboardRequested>((_, emit) => _load(emit));
  }

  final MemberRepository _members;
  final PaymentRepository _payments;
  final ReceiptRepository _receipts;

  /// Injectable so "today's revenue" can be tested on a fixed day.
  final DateTime Function() _clock;

  Future<void> _load(Emitter<DashboardState> emit) async {
    emit(const DashboardState(status: DashboardStatus.loading));
    try {
      // "Today" and "this month" mean the gym's calendar, not UTC's, and a
      // payment is a moment in time rather than a UTC-anchored cycle boundary.
      // Building these bounds as UTC out of local calendar fields shifted the
      // window by the timezone offset, which put a payment dated the 1st into
      // the previous month's revenue.
      final now = _clock();
      final todayStart = DateTime(now.year, now.month, now.day);
      final tomorrow = DateTime(now.year, now.month, now.day + 1);
      final monthStart = DateTime(now.year, now.month, 1);
      final nextMonth = DateTime(now.year, now.month + 1, 1);

      emit(DashboardState(
        status: DashboardStatus.ready,
        members: await _members.list(),
        recent: await _payments.history(limit: 8),
        revenueTodayMinor:
            await _payments.totalMinorBetween(todayStart, tomorrow),
        revenueMonthMinor:
            await _payments.totalMinorBetween(monthStart, nextMonth),
        paymentsToday: await _payments.countBetween(todayStart, tomorrow),
        failedWhatsApp: await _receipts.failedCount(),
      ));
    } catch (e, s) {
      _log.severe('Loading dashboard failed', e, s);
      emit(DashboardState(status: DashboardStatus.failed, error: '$e'));
    }
  }
}
