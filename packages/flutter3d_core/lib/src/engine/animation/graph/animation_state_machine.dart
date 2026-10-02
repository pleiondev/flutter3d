import 'package:flutter3d_core/formats.dart';

import '../animation_target.dart';
import 'animation_parameters.dart';

/// How a [CompareCondition] measures a number parameter against its value.
///
/// **Constants of a class rather than an enum**, for the reason
/// [AnimationParameterType] is: "at least" and "at most" are the obvious
/// next two, and adding them should not break anybody's `switch`.
final class AnimationComparison {
  const AnimationComparison._(this.name, this._test, {this.exact = false});

  final String name;
  final bool Function(double actual, num value) _test;

  /// Whether this asks for exact equality — which a float parameter reached
  /// by arithmetic almost never meets, and so is refused on one.
  final bool exact;

  static const AnimationComparison greater = AnimationComparison._(
    'greater',
    _greater,
  );
  static const AnimationComparison less = AnimationComparison._('less', _less);
  static const AnimationComparison equals = AnimationComparison._(
    'equals',
    _equals,
    exact: true,
  );
  static const AnimationComparison notEquals = AnimationComparison._(
    'notEquals',
    _notEquals,
    exact: true,
  );

  bool test(double actual, num value) => _test(actual, value);

  static bool _greater(double actual, num value) => actual > value;
  static bool _less(double actual, num value) => actual < value;
  static bool _equals(double actual, num value) => actual == value;
  static bool _notEquals(double actual, num value) => actual != value;

  @override
  String toString() => name;
}

/// One test a transition makes against the graph's parameters.
///
/// **Named by parameter, resolved once.** A condition is data — the shape a
/// `.f3d` will store and an MCP tool will build — so it names its parameter;
/// `AnimationGraph` resolves the name to an index when it is built, and a
/// name the schema lacks is one of [AnimationStateMachine.problems] rather
/// than a condition that is silently never true.
sealed class AnimationCondition {
  const AnimationCondition(this.parameter);

  final String parameter;
}

/// A float or integer parameter against a number.
final class CompareCondition extends AnimationCondition {
  const CompareCondition(super.parameter, this.comparison, this.value);

  final AnimationComparison comparison;
  final num value;

  bool holds(double actual) => comparison.test(actual, value);
}

/// A boolean parameter being [value].
final class BoolCondition extends AnimationCondition {
  const BoolCondition(super.parameter, {this.value = true});

  final bool value;
}

/// A trigger parameter being set — and consumed when the transition fires.
final class TriggerCondition extends AnimationCondition {
  const TriggerCondition(super.parameter);
}

/// A state: which clip plays while the graph is in it, and how.
final class AnimationState {
  const AnimationState({
    required this.name,
    required this.clip,
    this.speed = 1.0,
    this.wrap = AnimationWrap.loop,
  });

  final String name;

  /// The [AnimationClip.name] this state plays.
  ///
  /// A name rather than an index into the clip list, because the list is
  /// whatever order a file's exporter wrote; a re-export that sorts the clips
  /// must not move a character from idling to dying.
  final String clip;

  /// Playback rate, zero or more. Zero holds the first frame.
  final double speed;

  final AnimationWrap wrap;
}

/// A way out of one state into another.
///
/// **Fires when every condition holds and the exit time, if any, has
/// passed.** The conditions are a conjunction; an "or" is two transitions,
/// which is also how it reads in a graph editor.
final class AnimationTransition {
  AnimationTransition({
    required this.from,
    required this.to,
    List<AnimationCondition> conditions = const <AnimationCondition>[],
    this.duration = 0.0,
    this.priority = 0,
    this.exitTime,
  }) : conditions = List<AnimationCondition>.unmodifiable(conditions);

  /// The state this transition leaves, by name.
  final String from;

  /// The state it enters, by name.
  final String to;

  final List<AnimationCondition> conditions;

  /// The crossfade, in seconds; zero cuts.
  final double duration;

  /// Which of several transitions that could fire on the same step does.
  ///
  /// Higher first, and declaration order between equals — so the answer to
  /// "hit and jump on the same step" is written down rather than left to
  /// whichever was added first by accident.
  final int priority;

  /// How far through [from]'s clip the graph must be, as a fraction of the
  /// clip's length, before this transition may fire; null for no such wait.
  ///
  /// **Counted from entering the state, not from the last loop**: 0.8 on a
  /// looping clip is true from 80% of the first cycle on. 1.0 on a `once`
  /// clip is "when it has finished". Combined with conditions as an "and",
  /// so an attack that may be cancelled only late in its swing is an exit
  /// time and a trigger on one transition.
  final double? exitTime;
}

/// The states, transitions and parameters of one animation graph — what a
/// file stores and an editor edits. `AnimationGraph` is what runs it.
///
/// **The definition is checked as a whole, and asked rather than trusted.**
/// [problems] lists everything wrong with it at once, in words a person or
/// an agent can act on; `AnimationGraph` refuses to be built over a
/// definition that has any.
final class AnimationStateMachine {
  AnimationStateMachine({
    required this.parameters,
    required List<AnimationState> states,
    required List<AnimationTransition> transitions,
    String? entry,
  }) : states = List<AnimationState>.unmodifiable(states),
       transitions = List<AnimationTransition>.unmodifiable(transitions),
       entry = entry ?? (states.isEmpty ? '' : states.first.name);

  final AnimationParameterSchema parameters;
  final List<AnimationState> states;
  final List<AnimationTransition> transitions;

  /// The state the graph starts in: the first one unless named.
  final String entry;

  /// Where the state called [name] sits in [states], or -1.
  int indexOfState(String name) => states.indexWhere((s) => s.name == name);

  /// Everything that would stop this definition running over [clips]; empty
  /// when it can.
  List<String> problems(List<AnimationClip> clips) {
    final clipNames = <String>{for (final clip in clips) ?clip.name};
    final stateNames = <String>{for (final s in states) s.name};
    String? duplicate(Iterable<String> names, String what) {
      final seen = <String>{};
      final twice = names.where((n) => !seen.add(n)).toSet();
      return twice.isEmpty
          ? null
          : 'More than one $what is called ${_listed(twice, '')}; names are '
                'how everything else refers to them, so each must be unique.';
    }

    return <String>[
      ?duplicate(parameters.parameters.map((p) => p.name), 'parameter'),
      ?duplicate(states.map((s) => s.name), 'state'),
      if (states.isEmpty)
        'There are no states; a graph has to be in one. Add at least one.',
      if (states.isNotEmpty && !stateNames.contains(entry))
        'The entry state `$entry` is not one of the states.',
      for (final s in states) ...[
        ?_if(
          !clipNames.contains(s.clip),
          'State `${s.name}` plays clip `${s.clip}`, which is not among '
          '${_listed(clipNames, 'the clips (none is named)')}.',
        ),
        ?_if(
          !s.speed.isFinite || s.speed < 0.0,
          'State `${s.name}` has speed ${s.speed}; it must be finite and not '
          'negative, or its exit times could never be reached.',
        ),
      ],
      for (final t in transitions) ..._transitionProblems(t, stateNames),
    ];
  }

  /// [message] when [failed]; a collection `if` would do, but would hold a
  /// message split over lines as adjacent strings in the list itself.
  static String? _if(bool failed, String message) => failed ? message : null;

  static String _listed(Iterable<String> names, String whenNone) =>
      names.isEmpty ? whenNone : names.map((n) => '`$n`').join(', ');

  List<String> _transitionProblems(
    AnimationTransition t,
    Set<String> stateNames,
  ) {
    final label = '`${t.from}` → `${t.to}`';
    return <String>[
      if (!stateNames.contains(t.from))
        'Transition $label leaves `${t.from}`, which is not a state.',
      if (!stateNames.contains(t.to))
        'Transition $label enters `${t.to}`, which is not a state.',
      ?_if(
        !t.duration.isFinite || t.duration < 0.0,
        'Transition $label fades over ${t.duration} s; use zero to cut or a '
        'positive number of seconds.',
      ),
      if (t.exitTime case final exit? when !exit.isFinite || exit < 0.0)
        'Transition $label has exit time $exit; it must be finite, from 0 up.',
      ?_if(
        t.conditions.isEmpty && t.exitTime == null,
        'Transition $label has neither a condition nor an exit time, so it '
        'would fire on the first step in `${t.from}` and the state would '
        'never play. Give it one or the other.',
      ),
      for (final c in t.conditions) ?_conditionProblem(c, label),
    ];
  }

  String? _conditionProblem(AnimationCondition condition, String label) {
    final parameter = parameters[condition.parameter];
    if (parameter == null) {
      return 'Transition $label tests `${condition.parameter}`, which is not '
          'a parameter.';
    }
    final type = parameter.type;
    final wrong = 'Transition $label tests ${type.name} `${parameter.name}`';
    final instead = 'Use a ${_conditionFor(type)}.';
    final isNumber =
        type == AnimationParameterType.float ||
        type == AnimationParameterType.integer;
    return switch (condition) {
      CompareCondition(:final comparison)
          when comparison.exact && type == AnimationParameterType.float =>
        '$wrong for exact equality, which a float reached by arithmetic '
            'almost never meets. Compare with greater or less.',
      CompareCondition() when !isNumber => '$wrong against a number. $instead',
      BoolCondition() when type != AnimationParameterType.boolean =>
        '$wrong as a boolean. $instead',
      TriggerCondition() when type != AnimationParameterType.trigger =>
        '$wrong as a trigger. $instead',
      _ => null,
    };
  }

  static String _conditionFor(AnimationParameterType type) =>
      type == AnimationParameterType.boolean
      ? 'BoolCondition'
      : type == AnimationParameterType.trigger
      ? 'TriggerCondition'
      : 'CompareCondition';
}
