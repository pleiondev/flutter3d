part of 'scene_widgets.dart';

/// The simulation's components, shown as the renderer's scene bindings say
/// (D37): one node for every entity that has a bound component, made when
/// it gains it, brought up to date every frame, and taken away as the
/// binding's lifetime says.
///
/// ```dart
/// Scene3D(
///   onSceneCreated: (controller) => controller.renderer.sceneBindings
///     ..addKind(const EmberKind())
///     ..add(const SceneBindingSpec(
///       component: 'acme.heat',
///       nodeKind: 'acme.ember',
///       parameters: <String, String>{'temperature': 'glow'},
///     )),
///   children: const <Widget>[Binding3D()],
/// )
/// ```
///
/// **Read from the published state.** The entities and their components are
/// what the simulation published ([PublishedState.components], each as its
/// codec wrote it), so the nodes follow the simulation wherever it runs —
/// in the view's loop or in an isolate — and nothing here reaches into the
/// world. The bindings are the renderer's (`Renderer.sceneBindings`), where
/// a plugin's `install` and a data plugin's `bindings:` section put them; a
/// component with no binding, or with one whose kind of node is not
/// registered yet, is not shown.
///
/// **Per entity, each frame:**
///
/// * the binding's kind makes the node (`SceneNodeKind.create`) the first
///   time the entity is seen with the component, and it is hung from where
///   this widget stands — the scene's root, directly under a [Scene3D];
/// * a node made as a [MeshNode] is drawn with the material the binding
///   names, looked up through [materials] by id, when both are given;
/// * the node stands where the entity's published position is
///   ([PublishedState.positions]), blended between the last two steps when
///   the binding's interpolation is `linear`, and the kind brings it up to
///   the component's fields (`SceneNodeKind.update`), blended the same way;
/// * the fields the binding maps drive the node's own material parameters
///   (`MeshNode.parameters`, `SceneBinding.applyParameters`);
/// * an entity that lost the component loses its node under the
///   `component` lifetime; under `entity` the node is hidden and kept while
///   the entity still publishes anything (another component, a position),
///   and shown again when the component comes back.
///
/// [components] narrows what is shown to the components named; null shows
/// every bound one. [simulation] is the one read: null reads the
/// [Scene3D]'s own (`Flutter3dEngine.simulation`), and a [SceneWidgetsMount],
/// which has no loop, needs one named.
final class Binding3D extends StatefulWidget {
  const Binding3D({
    super.key,
    this.components,
    this.simulation,
    this.materials,
  });

  /// The component ids shown (`ComponentCodec.id`); null shows every one
  /// the renderer has a binding for.
  final Set<String>? components;

  /// The simulation whose published state is shown; null is the
  /// [Scene3D]'s.
  final SimulationHandle? simulation;

  /// The material a binding names by id (`SceneBindingSpec.material`), for
  /// the nodes made as meshes; null, or an answer of null, leaves the
  /// material the kind gave the node.
  final engine.RenderMaterial? Function(String id)? materials;

  @override
  State<Binding3D> createState() => _Binding3DState();
}

/// One node a binding made, and what it was made by.
final class _Bound {
  _Bound(this.binding, this.node);

  final SceneBinding binding;
  final SceneNode node;

  /// Whether this widget hid [node] for a component its entity lost: shown
  /// again when the component comes back, and otherwise left as a game set
  /// it.
  bool hidden = false;
}

class _Binding3DState extends State<Binding3D> implements _Animated {
  _Scene3DScope? _scope;

  /// The nodes made, by component id and the entity's packed number.
  final Map<(String, int), _Bound> _nodes = <(String, int), _Bound>{};

  SimulationHandle? _source;
  Registration? _listening;

  /// The newest state published, and the one before it: what the binding
  /// blends between.
  PublishedState? _current;
  PublishedState? _previous;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = _Scene3DScope.of(context);
    final before = _scope;
    _scope = scope;
    if (!identical(before?.host, scope.host)) {
      before?.host.animated.remove(this);
      scope.host.animated.add(this);
    }
    if (before != null && !identical(before.parent, scope.parent)) {
      // Moved by a keyed reparent: the nodes follow.
      for (final bound in _nodes.values) {
        bound.node.removeFromParent();
        scope.parent.add(bound.node);
      }
    }
    _listen();
  }

  @override
  void didUpdateWidget(Binding3D oldWidget) {
    super.didUpdateWidget(oldWidget);
    _listen();
  }

  /// Follows the simulation the widget names now, from its newest state.
  void _listen() {
    final source = widget.simulation ?? _scope?.host.simulation;
    if (identical(source, _source)) return;
    _listening?.cancel();
    _source = source;
    _previous = null;
    _current = source?.published;
    _listening = source?.onPublished((PublishedState state) {
      _previous = _current;
      _current = state;
    });
  }

  @override
  void advance(double seconds) {
    final scope = _scope;
    final state = _current;
    if (scope == null || state == null || !mounted) return;
    // The loop's place between its last two steps belongs to the loop the
    // scene runs; a simulation named here is shown at its newest step.
    final alpha = widget.simulation == null ? scope.host.alpha : 1.0;
    final bindings = scope.host.renderer.sceneBindings;
    final only = widget.components;
    final seen = <(String, int)>{};
    for (final MapEntry(key: id, value: rows) in state.components.entries) {
      if (only != null && !only.contains(id)) continue;
      final binding = bindings.resolve(id);
      if (binding == null) continue;
      final before = _previous?.components[id];
      for (final MapEntry(key: entity, value: data) in rows.entries) {
        final key = (id, entity.packed);
        seen.add(key);
        final fields = _fieldsOf(data);
        final previous = before != null && before.containsKey(entity)
            ? _fieldsOf(before[entity])
            : null;
        final bound = _nodes[key] ??= _make(
          scope,
          binding,
          entity,
          fields,
          previous,
          alpha,
        );
        final node = bound.node;
        if (bound.hidden) {
          bound.hidden = false;
          node.isVisible = true;
        }
        _place(node, binding, entity, state, alpha);
        final context = SceneBindingContext(
          binding: bound.binding,
          entity: entity.packed,
          fields: fields,
          previous: previous,
          alpha: alpha,
          node: node,
        );
        bound.binding.kind.update(context);
        if (node is MeshNode && bound.binding.spec.parameters.isNotEmpty) {
          bound.binding.applyParameters(
            node.parameters ??= MaterialParameters(),
            context,
          );
        }
      }
    }
    _forgetGone(seen, state);
  }

  _Bound _make(
    _Scene3DScope scope,
    SceneBinding binding,
    Entity entity,
    Map<String, Object?> fields,
    Map<String, Object?>? previous,
    double alpha,
  ) {
    final node = binding.kind.create(
      SceneBindingContext(
        binding: binding,
        entity: entity.packed,
        fields: fields,
        previous: previous,
        alpha: alpha,
      ),
    );
    final named = binding.spec.material;
    final lookUp = widget.materials;
    if (node is MeshNode && named != null && lookUp != null) {
      if (lookUp(named) case final material?) node.material = material;
    }
    scope.parent.add(node);
    return _Bound(binding, node);
  }

  /// Puts [node] where [entity] is, when it publishes a position.
  void _place(
    SceneNode node,
    SceneBinding binding,
    Entity entity,
    PublishedState state,
    double alpha,
  ) {
    final now = state.positions[entity];
    if (now == null) return;
    final before = _previous?.positions[entity];
    final at =
        before == null ||
            binding.spec.interpolation != BindingInterpolation.linear
        ? now
        : WorldPosition.lerp(before, now, alpha);
    node.setPositionFrom(_scope!.host.scene.toScene(at));
  }

  /// Takes away or hides the nodes whose entity did not show its component
  /// in [state], as each binding's lifetime says.
  void _forgetGone(Set<(String, int)> seen, PublishedState state) {
    if (_nodes.length == seen.length) return;
    final present = <int>{
      for (final entity in state.positions.keys) entity.packed,
      for (final rows in state.components.values)
        for (final entity in rows.keys) entity.packed,
    };
    _nodes.removeWhere(((String, int) key, _Bound bound) {
      if (seen.contains(key)) return false;
      if (bound.binding.spec.lifetime == BindingLifetime.entity &&
          present.contains(key.$2)) {
        bound
          ..hidden = true
          ..node.isVisible = false;
        return false;
      }
      bound.node.removeFromParent();
      return true;
    });
  }

  /// A component as its codec wrote it, as fields: an object's own, or one
  /// field called `value` for a codec that writes a bare number or list.
  static Map<String, Object?> _fieldsOf(Object? data) => switch (data) {
    final Map<Object?, Object?> map => <String, Object?>{
      for (final MapEntry(:key, :value) in map.entries) '$key': value,
    },
    _ => <String, Object?>{'value': data},
  };

  @override
  void dispose() {
    _listening?.cancel();
    _scope?.host.animated.remove(this);
    for (final bound in _nodes.values) {
      bound.node.removeFromParent();
    }
    _nodes.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
