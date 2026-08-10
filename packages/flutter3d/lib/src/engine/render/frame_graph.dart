/// Deciding which passes run, in what order, and which do not run at all.
///
/// Free of any GPU type on purpose, like the shadow slot allocator beside it:
/// ordering, culling and the diagnostics are list arithmetic with edge cases
/// worth testing, and none of it needs a device to answer.
///
/// The whole point of the exercise is that a pass declares what it touches
/// instead of being wired into `render()` by hand. `RenderSettings` grew a
/// `needsSurfaceBuffer` getter because one feature needed a buffer another
/// feature filled, and the only place to express that was a boolean computed
/// from settings. Ten features later that is ten booleans and an ordering
/// nobody can see. Here it is a read and a write.
library;

/// Something a node reads or writes, addressed by name.
///
/// A name rather than an object because the producer and the consumer are in
/// different packages and must not have to share a reference — the extension
/// model is the reason this exists at all. Declared rather than looked up, so
/// a name nobody produces is a build-time error instead of a null at frame 90.
extension type const ResourceId(String name) {}

/// A pass, and the only thing an extension has to implement to become one.
abstract base class FrameGraphNode {
  const FrameGraphNode();

  /// Shown in errors and in the profiler. Unique within a graph.
  String get name;

  /// What this node needs to have been produced before it runs.
  List<ResourceId> get reads => const <ResourceId>[];

  /// What this node produces. A node that writes nothing is only kept if
  /// something explicitly asks for it — see [FrameGraph.compile].
  List<ResourceId> get writes => const <ResourceId>[];

  /// Whether there is anything to do this frame.
  ///
  /// Asked once at compile, not per frame, so a node with nothing to say costs
  /// no pass setup — and so its outputs count as unproduced, which correctly
  /// culls anything that existed only to consume them.
  bool get isActive => true;
}

/// A graph that failed to compile, with the reason a person can act on.
final class FrameGraphError extends Error {
  FrameGraphError(this.message);
  final String message;
  @override
  String toString() => 'FrameGraphError: $message';
}

/// The result: the nodes to run, in order, what was dropped, and how long each
/// resource has to stay alive.
final class CompiledFrameGraph {
  const CompiledFrameGraph(
    this._lastUse, {
    required this.order,
    required this.culled,
  });

  /// Nodes to execute, earliest first.
  final List<FrameGraphNode> order;

  /// Nodes left out because nothing wanted what they produce.
  ///
  /// Kept rather than discarded so the reason a pass did not run is
  /// answerable. A pass that silently stops running is the kind of thing that
  /// gets debugged twice.
  final List<FrameGraphNode> culled;

  final Map<String, int> _lastUse;

  /// The last position in [order] that touches [id], or null if nothing does.
  ///
  /// What a texture can be handed back after. Computed here, where the order
  /// is already known, rather than by the allocator — it is the same arithmetic
  /// and this is the half that can be tested without a device.
  ///
  /// Two passes that never overlap can then share one texture, which is the
  /// difference between a bloom chain costing five targets and costing two.
  int? lastUseOf(ResourceId id) => _lastUse[id.name];

  /// Resources this frame touches at all, in no particular order.
  Iterable<ResourceId> get resources =>
      _lastUse.keys.map((name) => ResourceId(name));

  /// What can go back to the pool once the node at [index] has run.
  ///
  /// The counterpart of [lastUseOf], and the form the allocator actually wants:
  /// it walks the order and asks after each step rather than searching for a
  /// resource's last reader itself. Deliberately still pure — the release
  /// *decision* is arithmetic and the release *call* touches a device, and
  /// keeping them apart is what makes the decision testable.
  List<ResourceId> releasedAfter(int index) => <ResourceId>[
        for (final entry in _lastUse.entries)
          if (entry.value == index) ResourceId(entry.key),
      ];
}

/// Collects nodes, then works out the frame.
///
/// Registration order is meaningful and deliberately so: two nodes that both
/// write one resource — bloom adding to a target the composite also writes —
/// have no dependency between them to derive, and *something* has to decide.
/// The alternative is a priority number per node, which is the thing this was
/// meant to replace.
final class FrameGraph {
  final List<FrameGraphNode> _nodes = <FrameGraphNode>[];
  final Set<String> _external = <String>{};

  /// Registers a resource the engine provides rather than a node: the frame's
  /// colour target, the scene depth, the swapchain image.
  void addExternal(ResourceId id) => _external.add(id.name);

  void addNode(FrameGraphNode node) {
    for (final existing in _nodes) {
      if (existing.name == node.name) {
        throw FrameGraphError(
          'two nodes are called "${node.name}"; names appear in errors and in '
          'the profiler, so they have to tell the two apart',
        );
      }
    }
    _nodes.add(node);
  }

  void clear() {
    _nodes.clear();
    _external.clear();
  }

  int get length => _nodes.length;

  /// Works out which nodes run and in what order to produce [outputs].
  ///
  /// Throws [FrameGraphError] for anything a person can fix: a resource nobody
  /// produces, a cycle, a requested output that does not exist. All of it at
  /// compile rather than mid-frame, which is the difference between a message
  /// naming two passes and a blank screen.
  CompiledFrameGraph compile({required List<ResourceId> outputs}) {
    // Known at all, whether or not it runs this frame. The difference between
    // this and the active set is the difference between a misspelled name and
    // a feature somebody switched off, and those must not report the same way.
    final known = <String>{..._external};
    for (final node in _nodes) {
      for (final id in node.writes) {
        known.add(id.name);
      }
    }

    for (final node in _nodes) {
      for (final id in node.reads) {
        if (known.contains(id.name)) continue;
        throw FrameGraphError(
          '"${node.name}" reads "$id", which nothing writes and which is not '
          'registered as external. Either a pass is missing or the name is '
          'misspelled — both look identical at runtime, which is why this is '
          'checked here',
        );
      }
    }
    for (final id in outputs) {
      if (known.contains(id.name)) continue;
      throw FrameGraphError('the frame asks for "$id", which nothing produces');
    }

    final active = _nodes.where((n) => n.isActive).toList();

    // A node whose input exists in principle but is not produced this frame
    // cannot run, and neither can anything downstream of it. Switching bloom
    // off has to remove the passes that only fed it, not raise an error and
    // not leave them drawing into a texture nobody reads. Iterated to a fixed
    // point because dropping one node can starve the next.
    final runnable = List<bool>.filled(active.length, true);
    for (var changed = true; changed;) {
      changed = false;
      final produced = <String>{..._external};
      for (var i = 0; i < active.length; i++) {
        if (!runnable[i]) continue;
        for (final id in active[i].writes) {
          produced.add(id.name);
        }
      }
      for (var i = 0; i < active.length; i++) {
        if (!runnable[i]) continue;
        for (final id in active[i].reads) {
          if (produced.contains(id.name)) continue;
          runnable[i] = false;
          changed = true;
          break;
        }
      }
    }

    final writers = <String, List<int>>{};
    for (var i = 0; i < active.length; i++) {
      if (!runnable[i]) continue;
      for (final id in active[i].writes) {
        writers.putIfAbsent(id.name, () => <int>[]).add(i);
      }
    }

    // Edges, as indices into `active`.
    final edges = List<Set<int>>.generate(active.length, (_) => <int>{});
    for (var i = 0; i < active.length; i++) {
      if (!runnable[i]) continue;
      for (final id in active[i].reads) {
        for (final w in writers[id.name] ?? const <int>[]) {
          // Every writer of what this node reads, wherever it was registered —
          // a consumer declared before its producer is the ordinary case and
          // deriving the order is the whole point. Only the node itself is
          // excluded: read-modify-write on one resource is how anything
          // accumulates into a target, and a self-edge would report it as a
          // loop.
          if (w != i) edges[i].add(w);
        }
      }
      // Two writers of one resource run in registration order.
      for (final id in active[i].writes) {
        for (final w in writers[id.name] ?? const <int>[]) {
          if (w < i) edges[i].add(w);
        }
      }
    }

    final keep = _reachable(writers, edges, outputs);

    final order = <FrameGraphNode>[];
    final state = List<int>.filled(active.length, 0); // 0 new, 1 open, 2 done
    final stack = <String>[];

    void visit(int i) {
      if (state[i] == 2) return;
      if (state[i] == 1) {
        throw FrameGraphError(
          'these passes depend on each other in a loop: '
          '${stack.join(" -> ")} -> ${active[i].name}',
        );
      }
      state[i] = 1;
      stack.add(active[i].name);
      // Sorted so independent nodes keep registration order, which makes the
      // frame reproducible and therefore golden-testable.
      final deps = edges[i].toList()..sort();
      for (final d in deps) {
        if (keep.contains(d)) visit(d);
      }
      stack.removeLast();
      state[i] = 2;
      order.add(active[i]);
    }

    for (var i = 0; i < active.length; i++) {
      if (keep.contains(i)) visit(i);
    }

    final kept = order.toSet();
    final culled = <FrameGraphNode>[
      for (final node in _nodes)
        if (!kept.contains(node)) node,
    ];

    final lastUse = <String, int>{};
    for (var i = 0; i < order.length; i++) {
      for (final id in order[i].reads) {
        lastUse[id.name] = i;
      }
      for (final id in order[i].writes) {
        lastUse[id.name] = i;
      }
    }

    return CompiledFrameGraph(lastUse, order: order, culled: culled);
  }

  /// Everything the requested outputs actually depend on.
  ///
  /// Walking back from what the frame asks for, rather than running everything
  /// registered. This is what makes a post effect nobody enabled cost nothing
  /// at all, instead of costing a pass that writes a texture nobody samples.
  Set<int> _reachable(
    Map<String, List<int>> writers,
    List<Set<int>> edges,
    List<ResourceId> outputs,
  ) {
    final keep = <int>{};
    final pending = <int>[];
    for (final id in outputs) {
      for (final w in writers[id.name] ?? const <int>[]) {
        if (keep.add(w)) pending.add(w);
      }
    }
    while (pending.isNotEmpty) {
      final i = pending.removeLast();
      for (final d in edges[i]) {
        if (keep.add(d)) pending.add(d);
      }
    }
    return keep;
  }
}
