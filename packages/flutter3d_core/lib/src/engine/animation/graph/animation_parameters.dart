import 'dart:typed_data';

/// What kind of value an animation graph parameter holds — N1.
///
/// **A class with four constants rather than an enum**, so that a fifth kind
/// — a vector for a 2D blend space is the likely one — is an addition rather
/// than a break in every `switch` somebody wrote against the four.
final class AnimationParameterType {
  const AnimationParameterType._(this.name, this.writer);

  final String name;

  /// The [AnimationParameters] call that writes this kind, named in a
  /// refusal so the caller is told what to call instead.
  final String writer;

  /// A real number: a speed, a lean, an aim angle.
  static const AnimationParameterType float = AnimationParameterType._(
    'float',
    'setFloat',
  );

  /// A whole number: a weapon slot, a combo stage.
  static const AnimationParameterType integer = AnimationParameterType._(
    'integer',
    'setInteger',
  );

  /// On or off, and stays where it is put: grounded, crouching, armed.
  static const AnimationParameterType boolean = AnimationParameterType._(
    'boolean',
    'setBool',
  );

  /// On until a transition uses it, then off: attack, jump, hit.
  ///
  /// **Kept until it is consumed, not cleared at the end of the step.** An
  /// attack pressed in the middle of a swing whose transition waits for an
  /// exit time is the buffered input a player expects to see land; a trigger
  /// that lasted one step would be dropped on the floor. A caller who wants
  /// the opposite calls [AnimationParameters.resetTrigger].
  static const AnimationParameterType trigger = AnimationParameterType._(
    'trigger',
    'fire',
  );

  @override
  String toString() => name;
}

/// One named parameter in a graph's schema, with the value it starts at.
final class AnimationParameter {
  const AnimationParameter.float(this.name, {this.initial = 0.0})
    : type = AnimationParameterType.float;

  const AnimationParameter.integer(this.name, {int initial = 0})
    : type = AnimationParameterType.integer,
      initial = initial + 0.0;

  const AnimationParameter.boolean(this.name, {bool initial = false})
    : type = AnimationParameterType.boolean,
      initial = initial ? 1.0 : 0.0;

  const AnimationParameter.trigger(this.name)
    : type = AnimationParameterType.trigger,
      initial = 0.0;

  final String name;
  final AnimationParameterType type;

  /// The starting value as stored: see [AnimationParameters.values].
  final double initial;
}

/// The parameters a graph has, by name and type — the only ones a write may
/// name.
///
/// **A schema rather than a map that grows on first write.** A misspelt
/// `"grounded"` written into a map that accepts anything is a parameter
/// nobody reads, and the character never lands; written against a schema it
/// is a refusal naming the parameters there are.
final class AnimationParameterSchema {
  AnimationParameterSchema(List<AnimationParameter> parameters)
    : parameters = List<AnimationParameter>.unmodifiable(parameters),
      _index = <String, int>{
        // Reversed so the first of two same-named parameters wins; the
        // duplicate itself is one of `AnimationStateMachine.problems`.
        for (final (i, p) in parameters.indexed.toList().reversed) p.name: i,
      };

  final List<AnimationParameter> parameters;
  final Map<String, int> _index;

  /// Where [name] sits in [parameters], or -1.
  int indexOf(String name) => _index[name] ?? -1;

  /// The parameter called [name], or null.
  AnimationParameter? operator [](String name) => switch (_index[name]) {
    final i? => parameters[i],
    null => null,
  };
}

/// What a parameter write did: written, or refused and why.
///
/// **A refusal is returned, not thrown.** A game writing a parameter every
/// step and an agent writing one over MCP both want to know what went wrong,
/// and neither wants its step unwound because a name was misspelt.
final class ParameterWrite {
  const ParameterWrite._(this.refusal);

  static const ParameterWrite done = ParameterWrite._(null);

  /// What was asked, why it could not be, and what to do instead; null when
  /// the value was written.
  final String? refusal;

  bool get written => refusal == null;

  @override
  String toString() => refusal ?? 'written';
}

/// The current values of a graph's parameters, held to its schema.
///
/// **Every value is a double in one typed list**, booleans and triggers as
/// 0 and 1 and integers exactly. That keeps the state a graph carries to one
/// array a snapshot can copy and a digest can hash, with the type kept where
/// it is checked — at the write — rather than in the storage.
final class AnimationParameters {
  AnimationParameters(this.schema)
    : _values = Float64List.fromList(<double>[
        for (final p in schema.parameters) p.initial,
      ]);

  final AnimationParameterSchema schema;
  final Float64List _values;

  /// Every value, index-aligned with [AnimationParameterSchema.parameters].
  List<double> get values => _values.asUnmodifiableView();

  /// The value at [index], for a caller that resolved the name once.
  double valueAt(int index) => _values[index];

  ParameterWrite setFloat(String name, double value) => value.isFinite
      ? _write(name, AnimationParameterType.float, 'setFloat', value)
      : ParameterWrite._(
          'Cannot set `$name` to $value: a parameter holds a finite number, '
          'and every comparison against NaN or infinity answers the same '
          'thing whatever the threshold. Clamp it first.',
        );

  ParameterWrite setInteger(String name, int value) => _write(
    name,
    AnimationParameterType.integer,
    'setInteger',
    value.toDouble(),
  );

  ParameterWrite setBool(String name, bool value) => _write(
    name,
    AnimationParameterType.boolean,
    'setBool',
    value ? 1.0 : 0.0,
  );

  /// Sets the trigger [name]; it stays set until a transition consumes it.
  ParameterWrite fire(String name) =>
      _write(name, AnimationParameterType.trigger, 'fire', 1.0);

  /// Clears the trigger [name] without anything having used it.
  ParameterWrite resetTrigger(String name) =>
      _write(name, AnimationParameterType.trigger, 'resetTrigger', 0.0);

  /// Clears the trigger at [index] — what a transition does to the triggers
  /// it fired on.
  void consumeTriggerAt(int index) => _values[index] = 0.0;

  /// Every parameter back to its schema's initial value.
  void reset() {
    for (final (i, p) in schema.parameters.indexed) {
      _values[i] = p.initial;
    }
  }

  ParameterWrite _write(
    String name,
    AnimationParameterType type,
    String call,
    double value,
  ) {
    final index = schema.indexOf(name);
    if (index < 0) {
      final known = schema.parameters.map((p) => '`${p.name}`').join(', ');
      return ParameterWrite._(
        'No parameter `$name` in this graph. '
        '${known.isEmpty ? 'It has none.' : 'It has $known.'}',
      );
    }
    final actual = schema.parameters[index].type;
    if (actual != type) {
      return ParameterWrite._(
        '`$name` is a ${actual.name} parameter, and $call writes a '
        '${type.name}. Call ${actual.writer} instead.',
      );
    }
    _values[index] = value;
    return ParameterWrite.done;
  }
}
