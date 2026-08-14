import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logging/logging.dart';

import 'log_file_sink.dart';

/// Wires the root logger to its sinks and installs the handlers that catch
/// errors nobody remembered to catch.
///
/// Individual files create their own logger the usual way:
///
/// ```dart
/// final _log = Logger('backup');
/// _log.severe('snapshot failed', error, stack);
/// ```
///
/// Call [initLogging] once, inside the same zone as [runApp] — see main.dart.
Future<LogFileSink> initLogging({LogFileSink? sink}) async {
  // Everything while developing; INFO and worse on the gym's machine, so the
  // file stays readable and small.
  Logger.root.level = kDebugMode ? Level.ALL : Level.INFO;

  final fileSink = sink ?? LogFileSink();
  await fileSink.open();

  Logger.root.onRecord.listen((record) {
    final line = formatRecord(record);
    // The console is only attached during development; in release this would
    // be written to nowhere at some cost, so skip it.
    if (kDebugMode) {
      developer.log(
        record.message,
        time: record.time,
        level: record.level.value,
        name: record.loggerName,
        error: record.error,
        stackTrace: record.stackTrace,
      );
    }
    fileSink.write(line);
  });

  Bloc.observer = const LoggingBlocObserver();
  installCrashHandlers();

  Logger('app').info('--- session started (${kDebugMode ? 'debug' : 'release'}) ---');
  return fileSink;
}

/// One line per record, with the error and stack indented beneath it so a
/// reader can tell where one entry ends and the next begins.
String formatRecord(LogRecord record) {
  final t = record.time;
  final stamp = '${t.year.toString().padLeft(4, '0')}-'
      '${t.month.toString().padLeft(2, '0')}-'
      '${t.day.toString().padLeft(2, '0')} '
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}.'
      '${t.millisecond.toString().padLeft(3, '0')}';

  final buffer = StringBuffer()
    ..write('$stamp ${record.level.name.padRight(7)} ')
    ..write('${record.loggerName.padRight(10)} ')
    ..write(record.message);

  if (record.error != null) {
    buffer.write('\n    ${record.error}');
  }
  if (record.stackTrace != null) {
    for (final frame in record.stackTrace.toString().trimRight().split('\n')) {
      buffer.write('\n    $frame');
    }
  }
  return buffer.toString();
}

/// Routes framework and async errors into the log.
///
/// Without these, an exception thrown outside a bloc handler — a bad build, a
/// failed future with no catch — only ever reaches the console, which nobody is
/// watching on the gym's computer.
void installCrashHandlers() {
  final log = Logger('crash');

  final previousOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    log.severe(
      details.summary.toString(),
      details.exception,
      details.stack,
    );
    // Keep the red screen and console output during development.
    previousOnError?.call(details);
  };

  // Errors that escape the framework entirely, e.g. an unawaited future.
  PlatformDispatcher.instance.onError = (error, stack) {
    log.severe('Uncaught platform error', error, stack);
    return true;
  };
}

/// Runs [body] with a zone-level handler, the last net for anything the two
/// handlers above do not see.
Future<void> runGuarded(Future<void> Function() body) {
  final completer = Completer<void>();
  runZonedGuarded(
    () async {
      await body();
      if (!completer.isCompleted) completer.complete();
    },
    (error, stack) {
      Logger('crash').severe('Uncaught zone error', error, stack);
      if (!completer.isCompleted) completer.completeError(error, stack);
    },
  );
  return completer.future;
}

/// Logs bloc failures only.
///
/// Deliberately not an event/transition tracer: every keystroke in a search box
/// is an event, and AuthSignInRequested carries the admin's password.
class LoggingBlocObserver extends BlocObserver {
  const LoggingBlocObserver();

  @override
  void onError(BlocBase<dynamic> bloc, Object error, StackTrace stackTrace) {
    Logger('bloc').severe('${bloc.runtimeType} failed', error, stackTrace);
    super.onError(bloc, error, stackTrace);
  }
}
