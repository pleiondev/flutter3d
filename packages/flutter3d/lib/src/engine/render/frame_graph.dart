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
  ///
  /// A read that nothing produces this frame starves the node: it is culled,
  /// and so is anything that only fed it. That is right for a composite that
  /// cannot work without a colour, and wrong for everything in [optionalReads].
  List<ResourceId> get reads => const <ResourceId>[];

  /// What this node will sample if the frame happens to produce it.
  ///
  /// The distinction the first real frame description forced. The scene samples
  /// shadow maps, but a scene culled because shadows were switched off would
  /// draw nothing at all — so it cannot be a [reads]. Yet leaving the maps
  /// undeclared culls the shadow passes instead, since nothing would want what
  /// they produce. Both readings of "reads" are wrong and the missing word is
  /// this one.
  ///
  /// An optional read orders the node after the producer and keeps that
  /// producer alive, and never starves the node when the producer is absent.
  /// The shader already works this way: it looks up an atlas row and treats
  /// "no row" as a value rather than as a failure.
  List<ResourceId> get optionalReads => const <ResourceId>[];

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
    this._lastUse,
    this._readers, {
    required this.order,
    required this.culled,
    required this.outputs,
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
  final Set<String> _readers;

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

  /// What the frame was asked to produce.
  final List<ResourceId> outputs;

  /// Whether anything consumes [id] — a surviving pass, or the caller.
  ///
  /// The question a producer actually wants answered before it allocates. A
  /// resource read by no pass but requested as a frame output still has to
  /// exist: an application reading the surface buffer is a consumer the graph
  /// cannot see, and expressing it as a sink node does not work, because a node
  /// that writes nothing is unreachable from the outputs and is culled.
  bool isConsumed(ResourceId id) =>
      isRead(id) || outputs.any((o) => o.name == id.name);

  /// Whether any pass that survived reads [id].
  ///
  /// What replaces a hand-computed `needsSurfaceBuffer`. A producer can always
  /// declare that it *can* write something and let this decide whether it is
  /// worth attaching: with no reader the resource is never asked for, so
  /// [FrameResources] never allocates it and the write costs nothing.
  ///
  /// The alternative — a conditional write — cannot be expressed by a graph
  /// where reads are validated, and trying to model it that way is what this
  /// method was written to replace.
  bool isRead(ResourceId id) => _readers.contains(id.name);

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
      for (final id in <ResourceId>[...node.reads, ...node.optionalReads]) {
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
      // optionalReads deliberately do not appear here: an absent one is the
      // frame saying "not this time", not a reason to drop the pass.
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
      final alsoWrites = <String>{
        for (final id in active[i].writes) id.name,
      };
      for (final id in <ResourceId>[
        ...active[i].reads,
        ...active[i].optionalReads,
      ]) {
        // A node that reads a resource it also writes is a link in a chain,
        // not a consumer of one: two overlays compositing onto the same colour
        // each read it and write it back, and "depend on every writer" makes
        // them depend on each other. Their order is the registration order the
        // write rule below already imposes, so the read adds nothing.
        if (alsoWrites.contains(id.name)) continue;
        for (final w in writers[id.name] ?? const <int>[]) {
          // For anything else, every writer wherever it was registered: a
          // consumer declared before its producer is the ordinary case and
          // deriving that order is the whole point.
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
      for (final id in <ResourceId>[
        ...order[i].reads,
        ...order[i].optionalReads,
      ]) {
        lastUse[id.name] = i;
      }
      for (final id in order[i].writes) {
        lastUse[id.name] = i;
      }
    }

    final readers = <String>{
      for (final node in order) ...<String>[
        for (final id in node.reads) id.name,
        for (final id in node.optionalReads) id.name,
      ],
    };

    return CompiledFrameGraph(
      lastUse,
      readers,
      order: order,
      culled: culled,
      outputs: List<ResourceId>.unmodifiable(outputs),
    );
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
