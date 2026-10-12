/// The renderer's half of a scene binding (D37): the kinds of node a
/// component can be shown as, and the registry that turns a
/// `SceneBindingSpec` into nodes.
library;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show
        PluginException,
        PluginScope,
        Registration,
        BindingInterpolation,
        SceneBindingRegistry,
        SceneBindingSpec;

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show MaterialParameters;

import 'scene_node.dart';

/// What a [SceneNodeKind] is told about one entity's component: one object
/// that can gain members — the entity's other components, the view — rather
/// than a list of parameters that grows.
final class SceneBindingContext {
  const SceneBindingContext({
    required this.binding,
    required this.entity,
    required this.fields,
    this.previous,
    this.alpha = 1.0,
    this.node,
  });

  /// The binding being applied.
  final SceneBinding binding;

  /// The entity, by its id in the simulation.
  final int entity;

  /// The component's fields as its codec writes them, this step.
  final Map<String, Object?> fields;

  /// The same fields the step before, or null for the first; what a
  /// [SceneBindingSpec.interpolation] of `linear` blends from.
  final Map<String, Object?>? previous;

  /// How far the frame is between [previous] and [fields], nought to one.
  final double alpha;

  /// The node that stands for the entity, once [SceneNodeKind.create] made
  /// it: what [SceneNodeKind.update] brings up to date. Null while it is
  /// being made.
  final SceneNode? node;

  /// [name]'s value, blended between the two steps as the binding says: the
  /// numbers of [fields] and [previous] mixed by [alpha] under `linear`,
  /// [fields]' alone otherwise or where either is not a number.
  Object? field(String name) {
    final now = fields[name];
    final before = previous?[name];
    if (binding.spec.interpolation != BindingInterpolation.linear ||
        now is! num ||
        before is! num) {
      return now;
    }
    return before + (now - before) * alpha;
  }
}

/// A kind of node a scene binding makes (D37): `f3d.mesh`, `f3d.light` and
/// the engine's other kinds, or a plugin's own, named `<namespace>.<kind>`.
///
/// The set is open, and stays so: a kind is a name in [SceneBindings], not
/// a value of a type. Extendable outside this package through 1.x.
abstract base class SceneNodeKind {
  const SceneNodeKind();

  /// The kind's name, as a binding names it.
  String get name;

  /// The node that stands for [context]'s entity, made when it gains the
  /// component.
  SceneNode create(SceneBindingContext context);

  /// Brings [SceneBindingContext.node] up to [context]'s fields, every
  /// frame the entity has the component. By default it does nothing more
  /// than [SceneBinding.applyParameters].
  void update(SceneBindingContext context) {}
}

/// A binding as the renderer holds it: its spec, and the kind of node its
/// spec names.
final class SceneBinding {
  const SceneBinding(this.spec, this.kind);

  final SceneBindingSpec spec;
  final SceneNodeKind kind;

  /// Sets [parameters] from [context]'s fields as [spec] maps them, field to
  /// parameter: each field that holds a number, a list of numbers or a
  /// value a parameter takes.
  void applyParameters(
    MaterialParameters parameters,
    SceneBindingContext context,
  ) {
    for (final MapEntry(key: field, value: parameter)
        in spec.parameters.entries) {
      final value = context.field(field);
      if (value == null) continue;
      parameters.setNamed(parameter, value is int ? value.toDouble() : value);
    }
  }
}

/// The scene bindings of one renderer, and the kinds of node they make
/// (D37). The [SceneBindingRegistry] the plugin API names, filled.
///
/// Reached by a plugin as `host.registry<SceneBindingRegistry>()` (or this
/// type), a companion of the render steps; the `Scene3D` widgets and the
/// game's visuals drive it, one entity at a time.
final class SceneBindings extends SceneBindingRegistry {
  /// A renderer's, with no binding and no kind.
  SceneBindings() : _store = _BindingStore(), _scope = null;

  SceneBindings._scoped(this._store, this._scope);

  final _BindingStore _store;
  final PluginScope? _scope;

  @override
  List<SceneBindingSpec> get bindings =>
      List<SceneBindingSpec>.unmodifiable(_store.specs);

  /// Every kind of node registered, in the order it was.
  List<SceneNodeKind> get kinds =>
      List<SceneNodeKind>.unmodifiable(_store.kinds);

  /// The kind called [name], or null.
  SceneNodeKind? kindNamed(String name) {
    for (final kind in _store.kinds) {
      if (kind.name == name) return kind;
    }
    return null;
  }

  /// [component]'s binding with its kind resolved, or null when it has no
  /// binding or its kind is not registered (yet).
  SceneBinding? resolve(String component) {
    final spec = bindingOf(component);
    if (spec == null) return null;
    final kind = kindNamed(spec.nodeKind);
    return kind == null ? null : SceneBinding(spec, kind);
  }

  /// Makes [kind] one a binding may name, until the result is cancelled.
  /// Through a plugin's view, a [PluginException] for a kind named outside
  /// its namespace; an [ArgumentError] for a name another kind has.
  Registration addKind(SceneNodeKind kind) {
    _inNamespace(kind.name, 'the node kind');
    if (kindNamed(kind.name) != null) {
      throw ArgumentError.value(
        kind.name,
        'kind',
        'another node kind has this name',
      );
    }
    return _tracked(_store.kinds, kind);
  }

  @override
  Registration add(SceneBindingSpec spec) {
    if (bindingOf(spec.component) != null) {
      throw ArgumentError.value(
        spec.component,
        'spec',
        'this component is already bound',
      );
    }
    return _tracked(_store.specs, spec);
  }

  void _inNamespace(String name, String what) {
    final problem = _scope?.manifest.nameProblem(name, what: what);
    if (problem != null) throw PluginException(problem);
  }

  Registration _tracked<T>(List<T> into, T value) {
    into.add(value);
    final registration = Registration(() => into.remove(value));
    _scope?.track(registration);
    return registration;
  }

  @override
  SceneBindings forPlugin(PluginScope scope) =>
      SceneBindings._scoped(_store, scope);
}

final class _BindingStore {
  final List<SceneBindingSpec> specs = <SceneBindingSpec>[];
  final List<SceneNodeKind> kinds = <SceneNodeKind>[];
}
