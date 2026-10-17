/// What an engine says about itself while it runs: one [EngineLog] per
/// engine, with levels, listeners and a hook for a crash reporter.
library;

import 'registration.dart';

/// How much a [LogRecord] matters, from [trace] to [error].
///
/// **An open set with wire names, not an enum**, so a level added in a minor
/// release breaks no `switch`, and a record written to a file names its
/// level by [name], which a rename of the Dart constant does not move.
final class LogLevel implements Comparable<LogLevel> {
  const LogLevel._(this.name, this.severity);

  /// What only someone tracing one path through the engine wants: every
  /// step of it.
  static const LogLevel trace = LogLevel._('trace', 100);

  /// What helps while developing: a cache missed, a pipeline built late.
  static const LogLevel debug = LogLevel._('debug', 200);

  /// What happened and went well: a device opened, a level loaded.
  static const LogLevel info = LogLevel._('info', 300);

  /// What went less well than it should and was got round: a backend that
  /// would not start, so another one draws.
  static const LogLevel warning = LogLevel._('warning', 400);

  /// What failed: a device lost for good, a callback that threw.
  static const LogLevel error = LogLevel._('error', 500);

  /// The levels the engine names, from the least to the most severe.
  static const List<LogLevel> values = <LogLevel>[
    trace,
    debug,
    info,
    warning,
    error,
  ];

  /// The level named [name] on the wire, or null when this build names no
  /// such level (absent).
  static LogLevel? byName(String name) {
    for (final level in values) {
      if (level.name == name) return level;
    }
    return null;
  }

  /// The word a file or a tool writes for this level.
  final String name;

  /// Where the level sits: a higher number is more severe. Only the order
  /// means anything.
  final int severity;

  /// Whether this level is at least as severe as [other].
  bool isAtLeast(LogLevel other) => severity >= other.severity;

  @override
  int compareTo(LogLevel other) => severity.compareTo(other.severity);

  @override
  bool operator ==(Object other) =>
      other is LogLevel && other.name == name && other.severity == severity;

  @override
  int get hashCode => Object.hash(name, severity);

  @override
  String toString() => name;
}

/// One thing an [EngineLog] was told.
final class LogRecord {
  const LogRecord({
    required this.level,
    required this.message,
    required this.sequence,
    this.source = '',
    this.error,
    this.stackTrace,
    this.time,
  });

  /// How much it matters.
  final LogLevel level;

  /// What happened, as a sentence.
  final String message;

  /// Which part of the engine said it — `flutter3d_app.view`, a plugin's id
  /// — or empty when nobody said.
  final String source;

  /// What was thrown, when something was.
  final Object? error;

  /// Where it was thrown, when something was.
  final StackTrace? stackTrace;

  /// When the log was told, by its clock; null for a log made without one.
  ///
  /// **A clock is handed in, never read here**: this package is under the
  /// simulation, which reads no wall clock, so the view gives its log one
  /// and a log inside a step gives none.
  final DateTime? time;

  /// The record's place among everything its log was told, from nought:
  /// the order, whatever the clock says.
  final int sequence;

  @override
  String toString() =>
      '[${level.name}]${source.isEmpty ? '' : ' $source:'} $message'
      '${error == null ? '' : ' ($error)'}';
}

/// Told every record an [EngineLog] keeps.
typedef LogListener = void Function(LogRecord record);

/// Told an error nothing caught, with where it was thrown: what a crash
/// reporter (Crashlytics, Sentry, a file of one's own) is wired to.
typedef CrashReporter = void Function(CrashContext crash);

/// What a [CrashReporter] is told: the error, where it was thrown, and the
/// record the log kept of it.
///
/// **One object, so a minor can hand a reporter more** — the frame the
/// error came out of, the plugin that threw it — without breaking a
/// reporter written against 1.0.
final class CrashContext {
  const CrashContext({
    required this.error,
    required this.stackTrace,
    required this.record,
  });

  /// What was thrown.
  final Object error;

  /// Where it was thrown.
  final StackTrace stackTrace;

  /// The record [EngineLog.reportCrash] kept of it.
  final LogRecord record;
}

/// An engine's log: what the engine says about itself, by level, to whoever
/// listens, and the errors nothing caught, to a crash reporter.
///
/// **One per engine, never one per process** (no global mutable state): a
/// `Flutter3dView` makes one or is handed one, and two engines in one
/// isolate log apart. Nothing is printed unless a listener prints it.
///
/// ```dart
/// final log = EngineLog(level: LogLevel.debug, clock: DateTime.now);
/// log.listen((record) => debugPrint('$record'));
/// log.onCrash((crash) => crashlytics.recordError(crash.error, crash.stackTrace));
/// ```
final class EngineLog {
  /// A log keeping records at [level] and above, stamped by [clock] when one
  /// is given.
  EngineLog({this.level = LogLevel.info, DateTime Function()? clock})
    // A named parameter may not be private.
    // ignore: prefer_initializing_formals
    : _clock = clock;

  /// The least severe level kept; a record below it is dropped before any
  /// listener sees it. Settable while the engine runs.
  LogLevel level;

  final DateTime Function()? _clock;
  final List<LogListener> _listeners = <LogListener>[];
  final List<CrashReporter> _reporters = <CrashReporter>[];
  int _sequence = 0;

  /// Whether a record at [at] would be kept: what a caller asks before
  /// building an expensive message.
  bool isLogged(LogLevel at) => at.isAtLeast(level);

  /// Whether anything listens for crashes.
  bool get hasCrashReporter => _reporters.isNotEmpty;

  /// Tells [listener] every record kept from now until the registration is
  /// cancelled.
  Registration listen(LogListener listener) {
    _listeners.add(listener);
    return Registration(() => _listeners.remove(listener));
  }

  /// Tells [reporter] every error [reportCrash] is handed, until the
  /// registration is cancelled.
  Registration onCrash(CrashReporter reporter) {
    _reporters.add(reporter);
    return Registration(() => _reporters.remove(reporter));
  }

  /// Keeps [message] at [at], from [source], with what was thrown when
  /// something was; the record, or null when [at] is below [level].
  LogRecord? log(
    LogLevel at,
    String message, {
    String source = '',
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (!isLogged(at)) return null;
    final record = LogRecord(
      level: at,
      message: message,
      sequence: _sequence++,
      source: source,
      error: error,
      stackTrace: stackTrace,
      time: _clock?.call(),
    );
    for (final listener in List<LogListener>.of(_listeners)) {
      listener(record);
    }
    return record;
  }

  /// [log] at [LogLevel.trace].
  void trace(String message, {String source = ''}) =>
      log(LogLevel.trace, message, source: source);

  /// [log] at [LogLevel.debug].
  void debug(String message, {String source = ''}) =>
      log(LogLevel.debug, message, source: source);

  /// [log] at [LogLevel.info].
  void info(String message, {String source = ''}) =>
      log(LogLevel.info, message, source: source);

  /// [log] at [LogLevel.warning].
  void warning(
    String message, {
    String source = '',
    Object? error,
    StackTrace? stackTrace,
  }) => log(
    LogLevel.warning,
    message,
    source: source,
    error: error,
    stackTrace: stackTrace,
  );

  /// [log] at [LogLevel.error].
  void error(
    String message, {
    String source = '',
    Object? error,
    StackTrace? stackTrace,
  }) => log(
    LogLevel.error,
    message,
    source: source,
    error: error,
    stackTrace: stackTrace,
  );

  /// An error nothing caught: kept at [LogLevel.error] whatever [level] is,
  /// and handed to every crash reporter with its record.
  LogRecord reportCrash(
    Object error,
    StackTrace stackTrace, {
    String source = '',
    String? message,
  }) {
    final record = LogRecord(
      level: LogLevel.error,
      message: message ?? 'uncaught: $error',
      sequence: _sequence++,
      source: source,
      error: error,
      stackTrace: stackTrace,
      time: _clock?.call(),
    );
    for (final listener in List<LogListener>.of(_listeners)) {
      listener(record);
    }
    final crash = CrashContext(
      error: error,
      stackTrace: stackTrace,
      record: record,
    );
    for (final reporter in List<CrashReporter>.of(_reporters)) {
      reporter(crash);
    }
    return record;
  }
}
