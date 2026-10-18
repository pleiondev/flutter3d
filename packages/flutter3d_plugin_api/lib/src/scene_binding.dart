import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show DocumentFormatException, Registration;

import 'registration.dart';

/// How a bound node follows its component between two simulation steps.
///
/// An open set (S0): a class with constants, so a way a later minor adds (a
/// spline, an extrapolation) breaks no `switch`. [name] is the wire name a
/// `.f3dplugin`'s `bindings:` section writes.
final class BindingInterpolation {
  const BindingInterpolation._(this.name);

  /// The node shows the last step's value until the next arrives.
  static const BindingInterpolation step = BindingInterpolation._('step');

  /// The node is blended between the last two steps' values by how far the
  /// frame is between them — what a rendered body wants at a fixed step.
  static const BindingInterpolation linear = BindingInterpolation._('linear');

  /// Every interpolation this build knows, in the order a tool lists them.
  static const List<BindingInterpolation> values = <BindingInterpolation>[
    step,
    linear,
  ];

  /// The value called [name], or null for one this version does not know.
  static BindingInterpolation? byName(String name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  /// The stable name, and the wire name.
  final String name;

  @override
  String toString() => 'BindingInterpolation.$name';
}

/// When a bound node is made and taken away.
///
/// An open set (S0), as [BindingInterpolation] is.
final class BindingLifetime {
  const BindingLifetime._(this.name);

  /// Made when an entity gains the component, taken away when it loses it
  /// or is despawned.
  static const BindingLifetime component = BindingLifetime._('component');

  /// Made when an entity gains the component and kept, hidden, until the
  /// entity is despawned: for a component that comes and goes often (a
  /// status effect) and a node that is costly to make.
  static const BindingLifetime entity = BindingLifetime._('entity');

  /// Every lifetime this build knows, in the order a tool lists them.
  static const List<BindingLifetime> values = <BindingLifetime>[
    component,
    entity,
  ];

  /// The value called [name], or null for one this version does not know.
  static BindingLifetime? byName(String name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  /// The stable name, and the wire name.
  final String name;

  @override
  String toString() => 'BindingLifetime.$name';
}

/// How a component of the simulation is shown in the scene (D37): which
/// kind of node stands for an entity that has it, with what material, which
/// of its fields drive which of the material's parameters, how the node
/// follows the steps and when it is made.
///
/// **The data half, which a `.f3dplugin`'s `bindings:` section writes and a
/// Dart plugin registers alike.** It names everything by id — the
/// component's (`ComponentCodec.id`), the node kind's, the material's, the
/// parameters' — so it stands without the renderer's types, and a server
/// that replays a run reads it and makes nothing. The renderer's half,
/// `SceneBinding` in `flutter3d_core`, is what turns it into nodes.
///
/// The node kind is an open name: `f3d.mesh`, `f3d.light` and the others
/// the engine's `SceneBindings` knows, or `<namespace>.<kind>` for a kind a
/// plugin adds there.
final class SceneBindingSpec {
  /// A binding of [component] to a node of [nodeKind]: blended between steps
  /// ([BindingInterpolation.linear]) and made and dropped with the component
  /// ([BindingLifetime.component]) unless told otherwise.
  const SceneBindingSpec({
    required this.component,
    required this.nodeKind,
    this.material,
    this.parameters = const <String, String>{},
    this.interpolation = BindingInterpolation.linear,
    this.lifetime = BindingLifetime.component,
    this.extra = const <String, Object?>{},
  });

  /// Reads one entry of a `bindings:` section. Throws a
  /// [DocumentFormatException] naming what is wrong; keys this build does
  /// not know go to [extra].
  factory SceneBindingSpec.fromJson(Map<String, Object?> json) {
    String text(String key) => switch (json[key]) {
      final String value when value.isNotEmpty => value,
      _ => throw DocumentFormatException('a binding names no "$key"'),
    };
    final component = text('component');
    final what = 'the binding of "$component"';
    final parameters = switch (json['parameters']) {
      null => const <String, String>{},
      final Map<Object?, Object?> map
          when map.keys.every((k) => k is String) &&
              map.values.every((v) => v is String) =>
        Map<String, String>.unmodifiable(map.cast<String, String>()),
      _ => throw DocumentFormatException(
        '$what: "parameters" is not a map from a field to a parameter',
      ),
    };
    T named<T>(String key, T fallback, T? Function(String) byName) =>
        switch (json[key]) {
          null => fallback,
          final String name =>
            byName(name) ??
                (throw DocumentFormatException(
                  '$what: "$key" is "$name", which this build does not know',
                )),
          _ => throw DocumentFormatException('$what: "$key" is not a name'),
        };
    return SceneBindingSpec(
      component: component,
      nodeKind: text('node'),
      material: switch (json['material']) {
        null => null,
        final String material => material,
        _ => throw DocumentFormatException('$what: "material" is not a name'),
      },
      parameters: parameters,
      interpolation: named(
        'interpolation',
        BindingInterpolation.linear,
        BindingInterpolation.byName,
      ),
      lifetime: named(
        'lifetime',
        BindingLifetime.component,
        BindingLifetime.byName,
      ),
      extra: Map<String, Object?>.unmodifiable(<String, Object?>{
        for (final entry in json.entries)
          if (!_known.contains(entry.key)) entry.key: entry.value,
      }),
    );
  }

  static const Set<String> _known = <String>{
    'component',
    'node',
    'material',
    'parameters',
    'interpolation',
    'lifetime',
  };

  /// The component an entity has for this binding to show it: its codec's
  /// id.
  final String component;

  /// The kind of node that stands for it: `f3d.mesh`, or a plugin's own.
  final String nodeKind;

  /// The material the node is drawn with, by id — a material file of the
  /// plugin's or the project's, a material in the catalogue — or null for
  /// the node kind's own.
  final String? material;

  /// Which of the component's fields drives which of the material's
  /// parameters, field to `ParameterKey` name: `{"temperature":
  /// "glowStrength"}`.
  final Map<String, String> parameters;

  /// How the node follows the component between steps.
  final BindingInterpolation interpolation;

  /// When the node is made and taken away.
  final BindingLifetime lifetime;

  /// Keys this build does not know, kept as they were read.
  final Map<String, Object?> extra;

  /// The entry as a `bindings:` section writes it.
  Map<String, Object?> toJson() => <String, Object?>{
    ...extra,
    'component': component,
    'node': nodeKind,
    'material': ?material,
    if (parameters.isNotEmpty) 'parameters': parameters,
    if (interpolation != BindingInterpolation.linear)
      'interpolation': interpolation.name,
    if (lifetime != BindingLifetime.component) 'lifetime': lifetime.name,
  };

  @override
  String toString() => 'SceneBindingSpec($component → $nodeKind)';
}

/// Where scene bindings are registered: the data plugin's `bindings:`
/// section and a Dart plugin alike (D37). Filled by the renderer's
/// `SceneBindings` in `flutter3d_core`; an engine that draws nothing has
/// none, and a binding's install notes that rather than failing.
///
/// Made by the engine: `base`, so a member added in a later minor arrives
/// with a default.
abstract base class SceneBindingRegistry extends PluginRegistry {
  /// For the engine's registry, which extends this.
  const SceneBindingRegistry();

  /// Makes [spec] how its component is shown, until the result is
  /// cancelled. A second binding of one component is refused: a component
  /// is shown one way, and a plugin that shows another's differently
  /// replaces the kind of node, not the binding.
  Registration add(SceneBindingSpec spec);

  /// Every binding registered, in the order it was.
  List<SceneBindingSpec> get bindings;

  /// The binding of [component], or null.
  SceneBindingSpec? bindingOf(String component) {
    for (final spec in bindings) {
      if (spec.component == component) return spec;
    }
    return null;
  }

  @override
  SceneBindingRegistry forPlugin(PluginScope scope);
}
