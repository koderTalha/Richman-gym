import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logging/logging.dart';

import '../data/database.dart';
import '../data/member_repository.dart';
import '../services/import_service.dart';
import '../services/ledger_import.dart';
import '../services/spreadsheet_reader.dart';

final _log = Logger('import');

sealed class ImportEvent extends Equatable {
  const ImportEvent();
  @override
  List<Object?> get props => const [];
}

class ImportOptionsRequested extends ImportEvent {
  const ImportOptionsRequested();
}

class ImportFileRequested extends ImportEvent {
  const ImportFileRequested();
}

class ImportSheetSelected extends ImportEvent {
  const ImportSheetSelected(this.sheet);
  final String sheet;
  @override
  List<Object?> get props => [sheet];
}

class ImportYearChanged extends ImportEvent {
  const ImportYearChanged(this.year);
  final int year;
  @override
  List<Object?> get props => [year];
}

class ImportPlanChanged extends ImportEvent {
  const ImportPlanChanged(this.planId);
  final int planId;
  @override
  List<Object?> get props => [planId];
}

class ImportCommitted extends ImportEvent {
  const ImportCommitted(this.recordedById);
  final int recordedById;
  @override
  List<Object?> get props => [recordedById];
}

class ImportState extends Equatable {
  const ImportState({
    this.busy = false,
    this.fileName,
    this.sheets = const {},
    this.selectedSheet,
    this.year,
    this.plans = const [],
    this.planId,
    this.parsed,
    this.summary,
    this.error,
  });

  final bool busy;
  final String? fileName;
  final Map<String, List<List<String?>>> sheets;
  final String? selectedSheet;
  final int? year;
  final List<MembershipPlan> plans;
  final int? planId;
  final ParsedLedger? parsed;
  final ImportSummary? summary;
  final String? error;

  ImportState copyWith({
    bool? busy,
    String? fileName,
    Map<String, List<List<String?>>>? sheets,
    String? selectedSheet,
    int? year,
    List<MembershipPlan>? plans,
    int? planId,
    ParsedLedger? parsed,
    bool clearParsed = false,
    ImportSummary? summary,
    String? error,
  }) =>
      ImportState(
        busy: busy ?? this.busy,
        fileName: fileName ?? this.fileName,
        sheets: sheets ?? this.sheets,
        selectedSheet: selectedSheet ?? this.selectedSheet,
        year: year ?? this.year,
        plans: plans ?? this.plans,
        planId: planId ?? this.planId,
        parsed: clearParsed ? null : (parsed ?? this.parsed),
        summary: summary ?? this.summary,
        error: error,
      );

  @override
  List<Object?> get props => [
        busy,
        fileName,
        sheets.keys.toList(),
        selectedSheet,
        year,
        planId,
        parsed?.rows.length,
        parsed?.year,
        summary?.paymentsCreated,
        error,
      ];
}

class ImportBloc extends Bloc<ImportEvent, ImportState> {
  ImportBloc({
    required MemberRepository memberRepository,
    required AppDatabase database,
  })  : _members = memberRepository,
        _db = database,
        super(ImportState(year: DateTime.now().year)) {
    on<ImportOptionsRequested>(_onLoadOptions);
    on<ImportFileRequested>(_onPickFile);
    on<ImportSheetSelected>(_onSelectSheet);
    on<ImportYearChanged>(_onYearChanged);
    on<ImportPlanChanged>((e, emit) => emit(state.copyWith(planId: e.planId)));
    on<ImportCommitted>(_onCommit);
  }

  final MemberRepository _members;
  final AppDatabase _db;

  Future<void> _onLoadOptions(
    ImportOptionsRequested event,
    Emitter<ImportState> emit,
  ) async {
    final plans = await _members.plans();
    emit(state.copyWith(
      plans: plans,
      planId: plans.isEmpty ? null : plans.first.id,
    ));
  }

  Future<void> _onPickFile(
    ImportFileRequested event,
    Emitter<ImportState> emit,
  ) async {
    // Only the formats the parser can actually read. Offering ".xls" here
    // meant the owner picked one and got an error that read like their ledger
    // was damaged, when nothing was wrong with it at all.
    const typeGroup = XTypeGroup(
      label: 'Excel / CSV',
      extensions: readableExtensions,
    );
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null) return;

    emit(state.copyWith(busy: true, summary: null));

    try {
      final bytes = await File(file.path).readAsBytes();

      // Off the interface thread: a year's ledger is megabytes of XML, and
      // unzipping and walking it froze the window for as long as it took.
      final sheets = await compute(
        readSpreadsheet,
        SpreadsheetSource(fileName: file.name, bytes: bytes),
      );

      emit(state.copyWith(busy: false, fileName: file.name, sheets: sheets));

      if (sheets.isNotEmpty) {
        add(ImportSheetSelected(sheets.keys.first));
      } else {
        emit(state.copyWith(
            error: 'That file has no sheets in it to import.'));
      }
    } on UnreadableSpreadsheet catch (e) {
      _log.warning('Unreadable import file: ${file.name} — ${e.message}');
      emit(state.copyWith(busy: false, error: e.message));
    } catch (e, s) {
      _log.severe('Reading the import file failed', e, s);
      emit(state.copyWith(busy: false, error: 'Could not read that file: $e'));
    }
  }

  void _onSelectSheet(ImportSheetSelected event, Emitter<ImportState> emit) {
    final rows = state.sheets[event.sheet] ?? const <List<String?>>[];
    final year = yearFromSheetName(event.sheet) ?? state.year!;
    final detected = detectMapping(rows);

    if (detected == null) {
      emit(state.copyWith(
        selectedSheet: event.sheet,
        year: year,
        clearParsed: true,
        error: 'Could not find a header row with a Name column '
            'in "${event.sheet}".',
      ));
      return;
    }

    emit(state.copyWith(
      selectedSheet: event.sheet,
      year: year,
      parsed: parseLedger(
        rows: rows,
        headerRow: detected.headerRow,
        mapping: detected.mapping,
        year: year,
      ),
    ));
  }

  void _onYearChanged(ImportYearChanged event, Emitter<ImportState> emit) {
    final sheet = state.selectedSheet;
    if (sheet == null) {
      emit(state.copyWith(year: event.year));
      return;
    }

    final rows = state.sheets[sheet] ?? const <List<String?>>[];
    final detected = detectMapping(rows);
    if (detected == null) {
      emit(state.copyWith(year: event.year));
      return;
    }

    emit(state.copyWith(
      year: event.year,
      parsed: parseLedger(
        rows: rows,
        headerRow: detected.headerRow,
        mapping: detected.mapping,
        year: event.year,
      ),
    ));
  }

  Future<void> _onCommit(
    ImportCommitted event,
    Emitter<ImportState> emit,
  ) async {
    final ledger = state.parsed;
    final planId = state.planId;
    if (ledger == null || planId == null) return;

    emit(state.copyWith(busy: true));
    try {
      final summary = await ImportService(_db).commit(
        ledger: ledger,
        planId: planId,
        recordedById: event.recordedById,
      );
      emit(state.copyWith(busy: false, summary: summary));
    } catch (e, s) {
      _log.severe('Import failed', e, s);
      emit(state.copyWith(busy: false, error: 'Import failed: $e'));
    }
  }
}
