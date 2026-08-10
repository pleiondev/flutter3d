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

/// A resource as it stands between one write of it and the next.
///
/// The graph names *logical* resources — "the lit scene" — but a pass that
/// modifies one almost always writes its result into a different texture,
/// because a texture cannot be sampled and written in the same pass.
/// Reflections read the lit scene and produce a second one; every ping-pong
/// effect does the same. Versioning is how the name keeps meaning "the lit
/// scene" while the texture behind it changes: each write produces a new
/// version, each read is bound to whichever version was current where the
/// reader was registered, and an edge runs from the producer of a version to
/// its consumers rather than from every writer of a name to every reader of it.
///
/// Zero is what the engine handed in: an external resource, or nothing at all.
/// The first write produces one.
final class ResourceVersion {
  const ResourceVersion(this.id, this.version);

  final ResourceId id;
  final int version;

  @override
  bool operator ==(Object other) =>
      other is ResourceVersion &&
      other.id.name == id.name &&
      other.version == version;

  @override
  int get hashCode => Object.hash(id.name, version);

  @override
  String toString() => '${id.name}@$version';
}

/// Which version of each name one node reads and writes.
///
/// Held per position in [CompiledFrameGraph.order] rather than per node, since
/// that is the index everything else in the compiled result is keyed on.
final class _NodeBindings {
  const _NodeBindings(this.reads, this.writes);

  /// Hard and optional reads together: the distinction matters for culling,
  /// and by this point culling has happened.
  final Map<String, int> reads;
  final Map<String, int> writes;
}

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
    this._readers,
    this._bindings,
    this._current, {
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

  final Map<ResourceVersion, int> _lastUse;
  final Set<String> _readers;
  final List<_NodeBindings> _bindings;
  final Map<String, int> _current;

  /// The last position in [order] that touches [id], or null if nothing does.
  ///
  /// What a texture can be handed back after. Computed here, where the order
  /// is already known, rather than by the allocator — it is the same arithmetic
  /// and this is the half that can be tested without a device.
  ///
  /// Two passes that never overlap can then share one texture, which is the
  /// difference between a bloom chain costing five targets and costing two.
  ///
  /// The *name's* last use, which is the last use of its last version. A frame
  /// that writes a resource twice wants [retiredAfter] instead: the point of
  /// versioning is that the first texture behind a name can go back to the pool
  /// while the second one is still being drawn into.
  int? lastUseOf(ResourceId id) {
    int? last;
    for (final entry in _lastUse.entries) {
      if (entry.key.id.name != id.name) continue;
      if (last == null || entry.value > last) last = entry.value;
    }
    return last;
  }

  /// Resources this frame touches at all, in no particular order.
  Iterable<ResourceId> get resources => <ResourceId>{
        for (final key in _lastUse.keys) key.id,
      };

  /// The same, with each version told apart.
  Iterable<ResourceVersion> get resourceVersions => _lastUse.keys;

  /// The version of [id] the node at [index] reads, or null if it declares no
  /// read of it.
  int? readVersionOf(int index, ResourceId id) => _bindings[index].reads[id.name];

  /// The version of [id] the node at [index] produces, or null if it writes
  /// none.
  int? writeVersionOf(int index, ResourceId id) =>
      _bindings[index].writes[id.name];

  /// What the node at [index] writes, in the order it declared them.
  Iterable<ResourceId> writtenBy(int index) =>
      _bindings[index].writes.keys.map((name) => ResourceId(name));

  /// The newest version of [id] the whole frame produces; zero when no node
  /// writes it and the engine's own texture is all there is.
  int currentVersionOf(ResourceId id) => _current[id.name] ?? 0;

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
  ///
  /// A version at a time, because that is the whole point: `hdr_colour@0` goes
  /// back after its last reader even though `hdr_colour@1` is still live.
  List<ResourceVersion> retiredAfter(int index) => <ResourceVersion>[
        for (final entry in _lastUse.entries)
          if (entry.value == index) entry.key,
      ];

  /// [retiredAfter] with the versions dropped — the names whose last use this
  /// step was, each named once however many versions of it died here.
  List<ResourceId> releasedAfter(int index) => <ResourceId>{
        for (final entry in _lastUse.entries)
          if (entry.value == index) entry.key.id,
      }.toList();
}

/// Collects nodes, then works out the frame.
///
/// Registration order is meaningful and deliberately so: two nodes that both
/// write one resource — bloom adding to a target the composite also writes —
/// have no dependency between them to derive, and *something* has to decide.
/// The alternative is a priority number per node, which is the thing this was
/// meant to replace.
///
/// It is also where [ResourceVersion]s come from. Each write in registration
/// order produces the next version of a name and each read binds to the version
/// current at that moment, so a chain of passes over one target is a chain of
/// versions and the order falls out of it rather than being special-cased.
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

    // A node that is switched off does not consume a version, which is the one
    // place this departs from a literal reading of "versions are assigned in
    // registration order". It has to: a chain of read-modify-write passes with
    // an inactive link in the middle would otherwise leave every pass after it
    // reading a version nobody produces, and the whole chain would be culled
    // because one optional effect was off.
    final active = _nodes.where((n) => n.isActive).toList();

    // Versions, in registration order rather than in the order the frame turns
    // out to run. Nothing else would be stable: the order is derived from these
    // bindings, so deriving the bindings from the order would be circular.
    final current = <String, int>{};
    final reads = <Map<String, int>>[];
    final hardReads = <Map<String, int>>[];
    final writes = <Map<String, int>>[];
    for (final node in active) {
      final read = <String, int>{};
      final hard = <String, int>{};
      for (final id in node.reads) {
        final version = current[id.name] ?? 0;
        read[id.name] = version;
        hard[id.name] = version;
      }
      for (final id in node.optionalReads) {
        read[id.name] ??= current[id.name] ?? 0;
      }
      // Reads first, then writes: a node that does both consumes v and
      // produces v+1, which is what "read-modify-write" means and what the
      // edge rule used to approximate with a special case for a node reading
      // what it also writes.
      final write = <String, int>{};
      for (final id in node.writes) {
        final version = (current[id.name] ?? 0) + 1;
        current[id.name] = version;
        write[id.name] = version;
      }
      reads.add(read);
      hardReads.add(hard);
      writes.add(write);
    }

    // A consumer registered before its producer binds to version zero, which
    // exists only for an external resource. That is the ordinary case — the
    // whole point of the graph is that registration order need not be run
    // order — so such a read means "the resource as the frame finally leaves
    // it" and binds to the last version instead.
    void resolveForwardReferences(Map<String, int> bindings) {
      for (final name in bindings.keys.toList()) {
        if (bindings[name] != 0 || _external.contains(name)) continue;
        final last = current[name] ?? 0;
        if (last > 0) bindings[name] = last;
      }
    }

    for (var i = 0; i < active.length; i++) {
      resolveForwardReferences(reads[i]);
      resolveForwardReferences(hardReads[i]);
    }

    final producer = <ResourceVersion, int>{};
    for (var i = 0; i < active.length; i++) {
      writes[i].forEach((name, version) {
        producer[ResourceVersion(ResourceId(name), version)] = i;
      });
    }

    // A node whose input exists in principle but is not produced this frame
    // cannot run, and neither can anything downstream of it. Switching bloom
    // off has to remove the passes that only fed it, not raise an error and
    // not leave them drawing into a texture nobody reads. Iterated to a fixed
    // point because dropping one node can starve the next.
    final runnable = List<bool>.filled(active.length, true);
    bool produced(String name, int version) {
      // Version zero is the engine's own texture, and only exists if the
      // engine said so.
      if (version == 0) return _external.contains(name);
      final index = producer[ResourceVersion(ResourceId(name), version)];
      return index != null && runnable[index];
    }

    for (var changed = true; changed;) {
      changed = false;
      for (var i = 0; i < active.length; i++) {
        if (!runnable[i]) continue;
        for (final entry in hardReads[i].entries) {
          if (produced(entry.key, entry.value)) continue;
          runnable[i] = false;
          changed = true;
          break;
        }
      }
      // optionalReads deliberately do not appear here: an absent one is the
      // frame saying "not this time", not a reason to drop the pass.
    }

    // Edges, as indices into `active`. One rule now, where there used to be
    // two and a special case: a consumer of a version depends on that version's
    // producer.
    final edges = List<Set<int>>.generate(active.length, (_) => <int>{});
    for (var i = 0; i < active.length; i++) {
      if (!runnable[i]) continue;
      reads[i].forEach((name, version) {
        final p = producer[ResourceVersion(ResourceId(name), version)];
        if (p != null && p != i && runnable[p]) edges[i].add(p);
      });
      // And a version depends on the one before it, which is where two passes
      // accumulating into a single target get their order: there is no
      // dependency between them to derive, so registration order decides, and
      // the version chain is that order written down.
      writes[i].forEach((name, version) {
        final p = producer[ResourceVersion(ResourceId(name), version - 1)];
        if (p != null && p != i && runnable[p]) edges[i].add(p);
      });
    }

    final keep = _reachable(producer, runnable, current, edges, outputs);

    final order = <FrameGraphNode>[];
    final orderOf = <int>[]; // index into `active`, per position in `order`
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
      orderOf.add(i);
    }

    for (var i = 0; i < active.length; i++) {
      if (keep.contains(i)) visit(i);
    }

    final kept = order.toSet();
    final culled = <FrameGraphNode>[
      for (final node in _nodes)
        if (!kept.contains(node)) node,
    ];

    final bindings = <_NodeBindings>[];
    final lastUse = <ResourceVersion, int>{};
    for (var position = 0; position < order.length; position++) {
      final i = orderOf[position];
      bindings.add(_NodeBindings(reads[i], writes[i]));
      // Ascending, so the later of two touches wins — and a version's readers
      // always run after its producer, because that is the edge that put them
      // in this order.
      reads[i].forEach((name, version) {
        lastUse[ResourceVersion(ResourceId(name), version)] = position;
      });
      writes[i].forEach((name, version) {
        lastUse[ResourceVersion(ResourceId(name), version)] = position;
      });
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
      bindings,
      current,
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
    Map<ResourceVersion, int> producer,
    List<bool> runnable,
    Map<String, int> current,
    List<Set<int>> edges,
    List<ResourceId> outputs,
  ) {
    final keep = <int>{};
    final pending = <int>[];
    for (final id in outputs) {
      // The newest version anybody actually produced. Walking down rather than
      // taking the last version outright, because the pass that would have
      // written it may have starved — and then the output is whatever the last
      // surviving writer left, not nothing at all.
      for (var version = current[id.name] ?? 0; version > 0; version--) {
        final w = producer[ResourceVersion(id, version)];
        if (w == null || !runnable[w]) continue;
        if (keep.add(w)) pending.add(w);
        break;
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
