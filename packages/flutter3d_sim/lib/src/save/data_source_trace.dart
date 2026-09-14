/// Thrown when a [DataSourceTrace] cannot be read back at all.
final class DataSourceTraceFormatException implements Exception {
  const DataSourceTraceFormatException(this.message);

  final String message;

  @override
  String toString() => 'DataSourceTraceFormatException: $message';
}

/// What every `edu_data_source` a run read gave, one fixed step at a time —
/// `edu-00` §9's "значение из источника... становится вводом для этого
/// шага ленты", written down the same way [InputTape] writes down a
/// controller: dense, one entry per step, so a replay reads the exact value
/// a run saw rather than a value recomputed from a clock that has since
/// moved on.
///
/// **Why a trace of its own, next to [InputTape], rather than folded into
/// it.** [InputTape] is keyed to [GameAction] — a vocabulary this package
/// owns and every game shares. A sensor reading has no action behind it and
/// invents no new one: `edu-00` deliberately keeps the engine's input
/// vocabulary closed to controllers and gives external values their own,
/// parallel, additive channel — the same reasoning [Demo]'s own
/// [DigestTrace] already sits beside [InputTape] rather than inside it.
final class DataSourceTrace {
  DataSourceTrace() : _steps = <int>[], _values = <Map<String, Object?>>[];

  DataSourceTrace._parts(this._steps, this._values);

  final List<int> _steps;
  final List<Map<String, Object?>> _values;

  /// The step numbers recorded, in order and strictly increasing —
  /// [record] enforces both, the same discipline [InputTapeRecorder] holds
  /// its own frames to.
  List<int> get steps => List<int>.unmodifiable(_steps);

  /// How many steps this trace holds.
  int get length => _steps.length;

  /// Every binding this run resolved at [step] — what [resolveBindings]
  /// returned, kept exactly rather than re-derived.
  void record(int step, Map<String, Object?> resolvedBindings) {
    if (_steps.isNotEmpty && step <= _steps.last) {
      throw ArgumentError.value(
        step,
        'step',
        'a data source trace is recorded forward only — the last step was '
            '${_steps.last}',
      );
    }
    _steps.add(step);
    _values.add(Map<String, Object?>.unmodifiable(resolvedBindings));
  }

  /// What was recorded at exactly [step], or null if nothing was.
  Map<String, Object?>? valueAt(int step) {
    final index = _steps.indexOf(step);
    if (index < 0) return null;
    return _values[index];
  }

  /// The first recorded step whose own [path]'s value satisfies [test], or
  /// null if none ever did — `ls-i-02`'s own "an engineer... scrubs the
  /// timeline to the moment the lesson named," the same shape
  /// [DigestTrace.divergenceFrom] already answers for a checkpoint
  /// mismatch, here for a reading crossing a threshold rather than two
  /// runs disagreeing.
  int? firstStepWhere(String path, bool Function(Object? value) test) {
    for (var i = 0; i < _steps.length; i++) {
      if (test(_values[i][path])) return _steps[i];
    }
    return null;
  }

  /// A new trace: this one's own history up to and including [step], then
  /// whatever [continuation] resolves for every step after it and up to
  /// [throughStep] — a "what if", branched at [step] without touching this
  /// trace at all. [continuation] is a plain function rather than a second
  /// [DataSourceRegistry] because branching is a property of the trace, not
  /// of who is asking for one: the caller already knows which source it
  /// swapped and for what.
  DataSourceTrace branchAt(
    int step,
    int throughStep,
    Map<String, Object?> Function(int step) continuation,
  ) {
    final branch = DataSourceTrace();
    for (var i = 0; i < _steps.length; i++) {
      if (_steps[i] > step) break;
      branch.record(_steps[i], _values[i]);
    }
    for (var s = step + 1; s <= throughStep; s++) {
      branch.record(s, continuation(s));
    }
    return branch;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'steps': List<int>.of(_steps),
    'values': _values.map((v) => Map<String, Object?>.of(v)).toList(),
  };

  factory DataSourceTrace.fromJson(Map<String, Object?> json) {
    final rawSteps = json['steps'];
    final rawValues = json['values'];
    if (rawSteps is! List || rawValues is! List) {
      throw const DataSourceTraceFormatException(
        'the trace has no steps or no values',
      );
    }
    if (rawSteps.length != rawValues.length) {
      throw const DataSourceTraceFormatException(
        'the trace has a different number of steps and values',
      );
    }
    final steps = <int>[];
    final values = <Map<String, Object?>>[];
    for (var i = 0; i < rawSteps.length; i++) {
      final step = rawSteps[i];
      final value = rawValues[i];
      if (step is! num || value is! Map) {
        throw const DataSourceTraceFormatException(
          'an entry is not a step number and a value map',
        );
      }
      steps.add(step.toInt());
      values.add(Map<String, Object?>.unmodifiable(value));
    }
    return DataSourceTrace._parts(steps, values);
  }
}
