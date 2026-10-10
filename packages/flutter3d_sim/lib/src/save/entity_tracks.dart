import 'first_differing_path.dart';
import 'snapshot.dart';

/// Where in a snapshot the entities are, and what their components are
/// called.
///
/// **A reading of the save, not a second save.** A snapshot is whatever a
/// genre's `save()` wrote, and the engine does not know an entity from a
/// field; what it can be told is where to look. Two shapes cover what the
/// repository writes: [EntityLayout.ecs] for an `EcsWorld.save()`, which is
/// component-major (`components.Health.7`), and [EntityLayout.rows] for a
/// genre that writes one row per entity (`monsters[3].hp`). Both answer the
/// same thing — entity, then component, then value — so a track and a
/// divergence name an entity the same way whichever wrote it.
final class EntityLayout {
  const EntityLayout._(this._read);

  /// An `EcsWorld.save()` found under [at] in the snapshot — the empty list
  /// when the snapshot is the world itself. Entities are named by their
  /// index, components by the name they were registered under.
  factory EntityLayout.ecs([List<String> at = const <String>[]]) =>
      EntityLayout._((data) {
        final world = _descend(data, at);
        final components = world is Map ? world['components'] : null;
        if (components is! Map) return const <String, Map<String, Object?>>{};
        final entities = <String, Map<String, Object?>>{};
        for (final MapEntry(key: component, value: rows)
            in components.entries) {
          if (rows is! Map) continue;
          for (final MapEntry(key: entity, :value) in rows.entries) {
            (entities['$entity'] ??= <String, Object?>{})['$component'] = value;
          }
        }
        return entities;
      });

  /// One row per entity under [key]: a list, whose entities are named by
  /// index, or a map, named by key. Each row's own fields are its
  /// components; a row that is not a map is one component called `value`.
  factory EntityLayout.rows(String key) => EntityLayout._((data) {
    final rows = data[key];
    final named = switch (rows) {
      final List<Object?> list => <String, Object?>{
        for (var i = 0; i < list.length; i++) '$i': list[i],
      },
      final Map<Object?, Object?> map => <String, Object?>{
        for (final MapEntry(:key, :value) in map.entries) '$key': value,
      },
      _ => const <String, Object?>{},
    };
    return <String, Map<String, Object?>>{
      for (final MapEntry(key: entity, :value) in named.entries)
        entity: value is Map
            ? <String, Object?>{
                for (final MapEntry(:key, value: field) in value.entries)
                  '$key': field,
              }
            : <String, Object?>{'value': value},
    };
  });

  final Map<String, Map<String, Object?>> Function(Map<String, Object?> data)
  _read;

  /// Entity name to component name to value, for one snapshot.
  Map<String, Map<String, Object?>> entitiesOf(Snapshot snapshot) =>
      _read(snapshot.data);

  /// Every (entity, component) that differs between [a] and [b], in entity
  /// and then component order — present on one side only counts.
  List<EntityComponent> differences(Snapshot a, Snapshot b) {
    final left = entitiesOf(a);
    final right = entitiesOf(b);
    return <EntityComponent>[
      for (final entity in _sorted(<String>{...left.keys, ...right.keys}))
        for (final component in _sorted(<String>{
          ...?left[entity]?.keys,
          ...?right[entity]?.keys,
        }))
          if (_differs(left[entity], right[entity], component))
            EntityComponent(entity, component),
    ];
  }

  static bool _differs(
    Map<String, Object?>? a,
    Map<String, Object?>? b,
    String component,
  ) =>
      (a?.containsKey(component) ?? false) !=
          (b?.containsKey(component) ?? false) ||
      firstDifferingPath(a?[component], b?[component]) != null;

  /// This layout, reading the document found under [path] in a snapshot
  /// rather than the snapshot itself: a loop's capture holds each part
  /// under its id, so a run's own save stepped through a `RunLoop` is
  /// `layout.under(RunLoop.savePath)`. A snapshot with nothing there has no
  /// entities.
  EntityLayout under(List<String> path) => EntityLayout._((data) {
    final inner = _descend(data, path);
    return inner is Map
        ? _read(inner.cast<String, Object?>())
        : const <String, Map<String, Object?>>{};
  });

  static Object? _descend(Object? value, List<String> path) =>
      path.fold(value, (node, key) => node is Map ? node[key] : null);
}

/// One component of one entity, named as an [EntityLayout] names them.
final class EntityComponent {
  const EntityComponent(this.entity, this.component);

  final String entity;
  final String component;

  Map<String, Object?> toJson() => <String, Object?>{
    'entity': entity,
    'component': component,
  };

  @override
  bool operator ==(Object other) =>
      other is EntityComponent &&
      other.entity == entity &&
      other.component == component;

  @override
  int get hashCode => Object.hash(entity, component);

  @override
  String toString() => '$entity.$component';
}

/// A component's value from [step] on, until the next sample says otherwise.
final class TrackSample {
  const TrackSample(this.step, this.value, {this.present = true});

  final int step;

  /// What the component held; meaningless when not [present].
  final Object? value;

  /// False from the step the entity lost the component, or was despawned.
  final bool present;

  Map<String, Object?> toJson() => <String, Object?>{
    'step': step,
    if (present) 'value': value else 'absent': true,
  };
}

/// What every entity's components did over a run, one lane per component.
///
/// **Changes, not samples.** A lane holds a sample only at the steps its
/// value changed, so a thousand steps of a door that never moved is one
/// entry, and the steps at which something did happen are exactly the marks
/// a scrubber wants to draw. Observing every step costs a snapshot read per
/// step and nothing per entity that stood still.
final class EntityTracks {
  EntityTracks(this.layout);

  final EntityLayout layout;

  final Map<String, Map<String, List<TrackSample>>> _lanes =
      <String, Map<String, List<TrackSample>>>{};

  int? _first;
  int? _last;

  /// The first and last step observed, or null before the first.
  ({int first, int last})? get span => switch ((_first, _last)) {
    (final int first, final int last) => (first: first, last: last),
    _ => null,
  };

  /// Reads [snapshot] as the state at [step]. Steps must arrive in order; a
  /// step at or before the last one observed is ignored, since a lane holds
  /// one history and a second pass over it would write the same marks twice.
  void observe(int step, Snapshot snapshot) {
    final last = _last;
    if (last != null && step <= last) return;
    _first ??= step;
    _last = step;
    final entities = layout.entitiesOf(snapshot);
    for (final MapEntry(key: entity, value: components) in entities.entries) {
      final lanes = _lanes[entity] ??= <String, List<TrackSample>>{};
      for (final MapEntry(key: component, :value) in components.entries) {
        final lane = lanes[component] ??= <TrackSample>[];
        final previous = lane.isEmpty ? null : lane.last;
        if (previous == null ||
            !previous.present ||
            firstDifferingPath(previous.value, value) != null) {
          lane.add(TrackSample(step, value));
        }
      }
    }
    // A lane whose component is gone this step closes with an absent sample,
    // so a despawn reads as the step it happened rather than as the value
    // the component last had, held forever.
    for (final MapEntry(key: entity, value: lanes) in _lanes.entries) {
      for (final MapEntry(key: component, value: lane) in lanes.entries) {
        if (lane.last.present &&
            !(entities[entity]?.containsKey(component) ?? false)) {
          lane.add(TrackSample(step, null, present: false));
        }
      }
    }
  }

  /// Every entity seen, in name order.
  List<String> get entities => _sorted(_lanes.keys);

  /// Every component [entity] was seen with, in name order.
  List<String> componentsOf(String entity) =>
      _sorted(_lanes[entity]?.keys ?? const <String>[]);

  /// The changes on one lane, oldest first; empty for a lane never seen.
  List<TrackSample> samples(String entity, String component) =>
      List<TrackSample>.unmodifiable(
        _lanes[entity]?[component] ?? const <TrackSample>[],
      );

  /// The sample in force at [step]: the last change at or before it, or
  /// null when the lane had not started yet.
  TrackSample? at(String entity, String component, int step) => samples(
    entity,
    component,
  ).lastWhereOrNull((sample) => sample.step <= step);

  /// Every lane, for a panel across a wire: `{first, last, entities: {name:
  /// {component: [{step, value} | {step, absent}]}}}`.
  Map<String, Object?> toJson() => <String, Object?>{
    'first': _first,
    'last': _last,
    'entities': <String, Object?>{
      for (final entity in entities)
        entity: <String, Object?>{
          for (final component in componentsOf(entity))
            component: <Map<String, Object?>>[
              for (final sample in samples(entity, component)) sample.toJson(),
            ],
        },
    },
  };
}

List<String> _sorted(Iterable<String> names) => names.toList()..sort();

extension<T> on List<T> {
  T? lastWhereOrNull(bool Function(T) test) {
    for (var i = length - 1; i >= 0; i--) {
      if (test(this[i])) return this[i];
    }
    return null;
  }
}
