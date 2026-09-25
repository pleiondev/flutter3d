/// [FrameGraph]: collects [FrameGraphNode]s, then works out the frame.
///
/// **A part of `frame_graph.dart`, not a file of its own.** `compile()`
/// builds a `List<_NodeBindings>` and hands it straight to
/// [CompiledFrameGraph]'s constructor — `_NodeBindings` is private because
/// nothing outside this module has any business touching per-node version
/// bindings directly, and that privacy only survives a split if both sides
/// share the library. A `part` does that without making the type public just
/// to name it in two files.
part of 'frame_graph.dart';

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

  /// Node names this graph refuses to switch off, and why each one.
  ///
  /// Not a matter of taste: every other node degrades correctly when it is
  /// suppressed, and these three do not. `scene` and `composite` are the sole
  /// producers of the frame itself, and the renderer's own fallback would hand
  /// a caller a texture holding whatever was in it last rather than an error.
  /// `object ids` answers picks that have already been taken off the queue, so
  /// suppressing it leaves a click awaiting an answer that will never come.
  ///
  /// A caller that wants a frame without the composite wants `tonemap: false`
  /// and an exposure of one — `RenderSettings.forMeasurement` is that request
  /// said properly — not a graph with a hole where the picture was.
  static const Set<String> undisableable = <String>{
    'scene',
    'composite',
    'object ids',
  };

  /// Works out which nodes run and in what order to produce [outputs].
  ///
  /// Throws [FrameGraphError] for anything a person can fix: a resource nobody
  /// produces, a cycle, a requested output that does not exist. All of it at
  /// compile rather than mid-frame, which is the difference between a message
  /// naming two passes and a blank screen.
  CompiledFrameGraph compile({
    required List<ResourceId> outputs,
    Set<String> disabled = const <String>{},
  }) {
    // Known at all, whether or not it runs this frame. The difference between
    // this and the active set is the difference between a misspelled name and
    // a feature somebody switched off, and those must not report the same way.
    final known = <String>{..._external};
    for (final node in _nodes) {
      for (final id in <ResourceId>[...node.writes, ...node.keeps]) {
        known.add(id.name);
      }
      // Two opposite promises about one name. Checked here rather than trusted,
      // because the reader that would suffer is in another package and the
      // symptom — a texture that is sometimes this frame's and sometimes not —
      // is the kind that gets diagnosed as a driver problem.
      for (final id in node.keeps) {
        if (!node.writes.any((w) => w.name == id.name)) continue;
        throw FrameGraphError(
          '"${node.name}" both writes and keeps "$id". A write says the pixels '
          'are this frame\'s and a keep says they may not be; one name cannot '
          'mean both',
        );
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

    // A name nobody carries, checked here for the same reason a misspelled
    // resource is: at runtime the two are identical pictures. A caller who
    // typed 'fxaa' for the node called 'antialias' would otherwise get exactly
    // the frame they asked to change, and conclude the switch does nothing.
    //
    // The registered names are listed sorted, not in the disabled set's order
    // or the registration order, so the message is stable enough to assert on.
    final registered = <String>{for (final node in _nodes) node.name};
    for (final name in disabled) {
      if (registered.contains(name)) continue;
      throw FrameGraphError(
        'nothing registered is called "$name", so switching it off would '
        'change nothing and look like it worked. Registered this frame: '
        '${(registered.toList()..sort()).join(", ")}',
      );
    }
    for (final name in disabled) {
      if (!undisableable.contains(name)) continue;
      throw FrameGraphError(
        '"$name" cannot be switched off: it is the only thing that produces '
        'the frame, or the only thing that answers a request already taken. '
        'For a frame whose bytes are the numbers rather than a photograph of '
        'them, ask for that instead — see RenderSettings.forMeasurement',
      );
    }

    // A node that is switched off does not consume a version, which is the one
    // place this departs from a literal reading of "versions are assigned in
    // registration order". It has to: a chain of read-modify-write passes with
    // an inactive link in the middle would otherwise leave every pass after it
    // reading a version nobody produces, and the whole chain would be culled
    // because one optional effect was off.
    // `gfx-37n` adds the second clause, and it belongs exactly here rather
    // than at `addNode`: `known` above is built over every registered node
    // including the inactive ones, so a suppressed producer keeps its name
    // known and a read of it still compiles. Unregistering instead would make
    // the reader's own declaration conditional — the branch moved rather than
    // deleted, which is the thing the registration block argues against.
    // `gfx-50n` adds the third clause, beside rather than inside `isActive`:
    // a pass this device cannot run is dropped the same way, and the reason
    // it is reported by is the one thing about it a caller cannot fix.
    final active = _nodes
        .where((n) => n.isActive && n.supported && !disabled.contains(n.name))
        .toList();

    // Versions, in registration order rather than in the order the frame turns
    // out to run. Nothing else would be stable: the order is derived from these
    // bindings, so deriving the bindings from the order would be circular.
    final current = <String, int>{};
    final reads = <Map<String, int>>[];
    final hardReads = <Map<String, int>>[];
    final writes = <Map<String, int>>[];
    final kept = <ResourceVersion>{};
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
      //
      // Keeps are versioned exactly like writes, and deliberately in the same
      // pass: a maintained resource is still produced by the node that
      // maintains it, so a reader binds to that version and is ordered after
      // it. Only the promise about the pixels differs, and that is recorded
      // beside the version rather than changing how it is assigned.
      final write = <String, int>{};
      for (final id in node.writes) {
        final version = (current[id.name] ?? 0) + 1;
        current[id.name] = version;
        write[id.name] = version;
      }
      for (final id in node.keeps) {
        final version = (current[id.name] ?? 0) + 1;
        current[id.name] = version;
        write[id.name] = version;
        kept.add(ResourceVersion(id, version));
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

    // Write-after-read, added only now because it orders and must not keep:
    // the in-place writer of v+1 does not need a reader of v, so that reader
    // stays out of the reachability walk above. The edge is needed at all
    // because a pass that reads a resource and writes it back draws into the
    // texture it read ([FrameResources.beginNode]), so v and v+1 stand on one
    // texture, and a reader of v scheduled after that pass would sample v+1's
    // pixels. A graph that renames on every write and runs in setup order
    // (O'Donnell, "FrameGraph", GDC 2017) cannot meet the hazard; one that
    // reorders has to say it as an edge. A registration that also forces the
    // reader after the writer now comes out as the loop it is, instead of as a
    // silently wrong read.
    for (var i = 0; i < active.length; i++) {
      if (!runnable[i]) continue;
      reads[i].forEach((name, version) {
        final p = producer[ResourceVersion(ResourceId(name), version + 1)];
        if (p == null || p == i || !runnable[p]) return;
        if (reads[p][name] == version) edges[p].add(i);
      });
    }

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

    final survived = order.toSet();
    final culled = <FrameGraphNode>[
      for (final node in _nodes)
        if (!survived.contains(node)) node,
    ];

    // `gfx-39n`. Every one of these four facts was already computed above and
    // then discarded; this reads them back off the same structures rather than
    // deriving anything a second time, so a reason cannot disagree with the
    // frame it describes. The order of the tests is the order of causes: a
    // node named by a caller is disabled even though `isActive` was never
    // asked, and a starved node is reported as starved rather than as
    // unconsumed, because the two answers send a reader to different places.
    final activeIndex = <FrameGraphNode, int>{
      for (var i = 0; i < active.length; i++) active[i]: i,
    };
    final skipped = <SkippedPass>[
      for (final node in culled)
        (
          name: node.name,
          reason: switch (activeIndex[node]) {
            // The order inside this arm is the order of causes too. A caller
            // who named a pass gets told so even on a device that could not
            // have run it, because that is the answer about what they did;
            // `unsupported` comes next, ahead of `settings`, since a device
            // that cannot run a pass makes its settings beside the point.
            null => switch (node) {
              _ when disabled.contains(node.name) => PassSkip.disabled,
              _ when !node.supported => PassSkip.unsupported,
              _ => PassSkip.settings,
            },
            final i when !runnable[i] => PassSkip.starved,
            final i when !keep.contains(i) => PassSkip.unconsumed,
            // Runnable, kept, and yet not in `order` — unreachable unless the
            // walk itself dropped a node, which would be a bug in `visit`
            // rather than a decision about this frame. Reported as starved
            // because that is the reading that sends somebody upstream.
            _ => PassSkip.starved,
          },
        ),
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
      kept,
      order: order,
      culled: culled,
      outputs: List<ResourceId>.unmodifiable(outputs),
      skipped: List<SkippedPass>.unmodifiable(skipped),
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
