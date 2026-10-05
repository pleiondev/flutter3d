import '../../../formats/animation/animation_clip.dart';
import '../../../formats/model_document.dart';
import '../animation_target.dart';
import 'animation_parameters.dart';
import 'animation_state_machine.dart';

/// An [AnimationStateMachine] as JSON, and back — the shape a model file
/// keeps its animation graphs in and an agent's tool builds one from.
///
/// **Plain JSON, every field named.** States, clips and parameters by name,
/// as the machine itself names them, so a file stays readable and a
/// definition edited by hand or by a tool says what it means. Defaults are
/// left out on the way out and filled in on the way in.
///
/// **Read loudly.** [decode] throws a [FormatException] naming where in
/// the JSON the shape is wrong — `states[2].blend.points[0].at is "fast",
/// not a number` — rather than reading a typo as a default. What is the
/// right shape but a wrong machine (a clip the model lacks, a state no
/// transition names) is `AnimationStateMachine.problems`, asked once the
/// clips are known.
abstract final class AnimationGraphJson {
  /// The key a document's root `extras` keeps its graphs under, by name:
  /// `{"animationGraphs": {"monster": {...}, ...}}`.
  static const String extrasKey = 'animationGraphs';

  /// [machine] as JSON.
  static Map<String, Object?> encode(AnimationStateMachine machine) =>
      <String, Object?>{
        'parameters': <Object?>[
          for (final p in machine.parameters.parameters)
            <String, Object?>{
              'name': p.name,
              'type': p.type.name,
              if (p.initial != 0.0) 'initial': p.initial,
            },
        ],
        'entry': machine.entry,
        'states': <Object?>[for (final s in machine.states) _encodeState(s)],
        'transitions': <Object?>[
          for (final t in machine.transitions) _encodeTransition(t),
        ],
      };

  /// The machine [json] describes; a [FormatException] for a wrong shape.
  static AnimationStateMachine decode(Object? json) {
    final at = _At('');
    final map = at.map(json);
    final parameters = at.key('parameters').list(map['parameters']);
    final states = at.key('states').list(map['states']);
    return AnimationStateMachine(
      parameters: AnimationParameterSchema(<AnimationParameter>[
        for (final (i, p) in parameters.indexed)
          _decodeParameter(at.key('parameters').index(i), p),
      ]),
      states: <AnimationState>[
        for (final (i, s) in states.indexed)
          _decodeState(at.key('states').index(i), s),
      ],
      transitions: <AnimationTransition>[
        for (final (i, t)
            in at
                .key('transitions')
                .list(map['transitions'] ?? const <Object?>[])
                .indexed)
          _decodeTransition(at.key('transitions').index(i), t),
      ],
      entry: at.key('entry').stringOr(map['entry'], null),
    );
  }

  /// Every graph [asset]'s root `extras` keeps, by name — none for a
  /// document that keeps none. A graph that does not read throws, naming
  /// it.
  static Map<String, AnimationStateMachine> graphsIn(DocumentAsset? asset) {
    final kept = asset?.extras?[extrasKey];
    if (kept == null) return const <String, AnimationStateMachine>{};
    final at = _At(extrasKey);
    return <String, AnimationStateMachine>{
      for (final MapEntry(:key, :value) in at.map(kept).entries)
        key: _decodeNamed(key, value),
    };
  }

  /// [extras] with [graphs] kept in it under [extrasKey], replacing what
  /// was there; everything else in [extras] as it was.
  static Map<String, Object?> keep(
    Map<String, Object?>? extras,
    Map<String, AnimationStateMachine> graphs,
  ) => <String, Object?>{
    ...?extras,
    extrasKey: <String, Object?>{
      for (final MapEntry(:key, :value) in graphs.entries) key: encode(value),
    },
  };

  static AnimationStateMachine _decodeNamed(String name, Object? json) {
    try {
      return decode(json);
    } on FormatException catch (error) {
      throw FormatException('graph "$name": ${error.message}');
    }
  }

  static Map<String, Object?> _encodeState(AnimationState s) =>
      <String, Object?>{
        'name': s.name,
        if (s.clip.isNotEmpty) 'clip': s.clip,
        if (s.blend case final blend?)
          'blend': <String, Object?>{
            'parameter': blend.parameter,
            'across': ?blend.across,
            'points': <Object?>[
              for (final p in blend.points)
                <String, Object?>{
                  'at': p.at,
                  if (blend.across != null) 'y': p.y,
                  'clip': p.clip,
                },
            ],
          },
        if (s.speed != 1.0) 'speed': s.speed,
        if (s.wrap != AnimationWrap.loop) 'wrap': s.wrap.name,
        if (s.markers.isNotEmpty)
          'markers': <Object?>[
            for (final m in s.markers)
              <String, Object?>{'at': m.at, 'name': m.name},
          ],
      };

  static Map<String, Object?> _encodeTransition(AnimationTransition t) =>
      <String, Object?>{
        'from': t.from,
        'to': t.to,
        if (t.conditions.isNotEmpty)
          'conditions': <Object?>[
            for (final c in t.conditions) _encodeCondition(c),
          ],
        if (t.duration != 0.0) 'duration': t.duration,
        if (t.priority != 0) 'priority': t.priority,
        'exitTime': ?t.exitTime,
      };

  static Map<String, Object?> _encodeCondition(AnimationCondition c) =>
      switch (c) {
        CompareCondition(:final comparison, :final value) => <String, Object?>{
          'parameter': c.parameter,
          'compare': comparison.name,
          'value': value,
        },
        BoolCondition(:final value) => <String, Object?>{
          'parameter': c.parameter,
          'is': value,
        },
        TriggerCondition() => <String, Object?>{
          'parameter': c.parameter,
          'trigger': true,
        },
      };

  static const List<AnimationParameterType> _types = <AnimationParameterType>[
    AnimationParameterType.float,
    AnimationParameterType.integer,
    AnimationParameterType.boolean,
    AnimationParameterType.trigger,
  ];

  static const List<AnimationComparison> _comparisons = <AnimationComparison>[
    AnimationComparison.greater,
    AnimationComparison.less,
    AnimationComparison.equals,
    AnimationComparison.notEquals,
  ];

  static AnimationParameter _decodeParameter(_At at, Object? json) {
    final map = at.map(json);
    final name = at.key('name').string(map['name']);
    final type = at.key('type').oneOf(
      map['type'],
      <String, AnimationParameterType>{for (final t in _types) t.name: t},
    );
    final initial = at.key('initial').numberOr(map['initial'], 0.0);
    if (type == AnimationParameterType.float) {
      return AnimationParameter.float(name, initial: initial);
    }
    if (type == AnimationParameterType.integer) {
      return AnimationParameter.integer(name, initial: initial.round());
    }
    if (type == AnimationParameterType.boolean) {
      return AnimationParameter.boolean(name, initial: initial != 0.0);
    }
    return AnimationParameter.trigger(name);
  }

  static AnimationState _decodeState(_At at, Object? json) {
    final map = at.map(json);
    final blend = map['blend'];
    return AnimationState(
      name: at.key('name').string(map['name']),
      clip: at.key('clip').stringOr(map['clip'], '') ?? '',
      blend: blend == null ? null : _decodeBlend(at.key('blend'), blend),
      speed: at.key('speed').numberOr(map['speed'], 1.0),
      wrap: at.key('wrap').oneOf(
        map['wrap'] ?? AnimationWrap.loop.name,
        <String, AnimationWrap>{
          for (final w in AnimationWrap.values) w.name: w,
        },
      ),
      markers: <AnimationMarker>[
        for (final (i, m)
            in at
                .key('markers')
                .list(map['markers'] ?? const <Object?>[])
                .indexed)
          _decodeMarker(at.key('markers').index(i), m),
      ],
    );
  }

  static AnimationMarker _decodeMarker(_At at, Object? json) {
    final map = at.map(json);
    return AnimationMarker(
      at.key('at').number(map['at']),
      at.key('name').string(map['name']),
    );
  }

  static AnimationBlendSpace _decodeBlend(_At at, Object? json) {
    final map = at.map(json);
    final points = at.key('points').list(map['points']);
    return AnimationBlendSpace(
      at.key('parameter').string(map['parameter']),
      <BlendPoint>[
        for (final (i, p) in points.indexed)
          _decodePoint(at.key('points').index(i), p),
      ],
      across: at.key('across').stringOr(map['across'], null),
    );
  }

  static BlendPoint _decodePoint(_At at, Object? json) {
    final map = at.map(json);
    return BlendPoint(
      at.key('at').number(map['at']),
      at.key('clip').string(map['clip']),
      y: at.key('y').numberOr(map['y'], 0.0),
    );
  }

  static AnimationTransition _decodeTransition(_At at, Object? json) {
    final map = at.map(json);
    final exitTime = map['exitTime'];
    return AnimationTransition(
      from: at.key('from').string(map['from']),
      to: at.key('to').string(map['to']),
      conditions: <AnimationCondition>[
        for (final (i, c)
            in at
                .key('conditions')
                .list(map['conditions'] ?? const <Object?>[])
                .indexed)
          _decodeCondition(at.key('conditions').index(i), c),
      ],
      duration: at.key('duration').numberOr(map['duration'], 0.0),
      priority: at.key('priority').numberOr(map['priority'], 0.0).round(),
      exitTime: exitTime == null ? null : at.key('exitTime').number(exitTime),
    );
  }

  static AnimationCondition _decodeCondition(_At at, Object? json) {
    final map = at.map(json);
    final parameter = at.key('parameter').string(map['parameter']);
    if (map.containsKey('compare')) {
      final value = map['value'];
      if (value is! num) {
        throw FormatException('${at.key('value')} is $value, not a number');
      }
      return CompareCondition(
        parameter,
        at.key('compare').oneOf(map['compare'], <String, AnimationComparison>{
          for (final c in _comparisons) c.name: c,
        }),
        value,
      );
    }
    if (map.containsKey('is')) {
      final value = map['is'];
      if (value is! bool) {
        throw FormatException('${at.key('is')} is $value, not true or false');
      }
      return BoolCondition(parameter, value: value);
    }
    if (map['trigger'] == true) return TriggerCondition(parameter);
    throw FormatException(
      '$at says none of "compare", "is" or "trigger": true',
    );
  }
}

/// Where in the JSON a reader is, for its complaints.
final class _At {
  _At(this.path);

  final String path;

  _At key(String name) => _At(path.isEmpty ? name : '$path.$name');

  _At index(int i) => _At('$path[$i]');

  Never _wrong(Object? value, String wanted) => throw FormatException(
    '${path.isEmpty ? 'the graph' : path} is '
    '${value is String ? '"$value"' : value}, not $wanted',
  );

  Map<String, Object?> map(Object? value) =>
      value is Map<String, Object?> ? value : _wrong(value, 'an object');

  List<Object?> list(Object? value) =>
      value is List<Object?> ? value : _wrong(value, 'a list');

  String string(Object? value) =>
      value is String && value.isNotEmpty ? value : _wrong(value, 'a name');

  String? stringOr(Object? value, String? otherwise) =>
      value == null ? otherwise : string(value);

  double number(Object? value) =>
      value is num ? value.toDouble() : _wrong(value, 'a number');

  double numberOr(Object? value, double otherwise) =>
      value == null ? otherwise : number(value);

  T oneOf<T>(Object? value, Map<String, T> choices) =>
      choices[value] ?? _wrong(value, 'one of ${choices.keys.join(', ')}');

  @override
  String toString() => path;
}
