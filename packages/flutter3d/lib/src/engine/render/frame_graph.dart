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

part 'frame_graph_compile.dart';

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

  /// What this node produces, fresh, this frame.
  ///
  /// A node that writes nothing is only kept if something explicitly asks for
  /// it — see [FrameGraph.compile]. A write is a promise about *this* frame:
  /// nothing was there before the node ran, and what is there afterwards is
  /// what the node drew.
  List<ResourceId> get writes => const <ResourceId>[];

  /// What this node **maintains** across frames rather than producing fresh.
  ///
  /// The distinction the point-light atlas forced, and it is a different
  /// promise from [writes] rather than a weaker one. The directional shadow map
  /// is redrawn from nothing every frame, so a frame in which that pass gave up
  /// has no map at all and a reader must be told so. The cube atlas is a
  /// running total: it is *loaded* rather than cleared, a tile is blanked by
  /// drawing over it, and a tile the scheduler left out deliberately holds the
  /// picture an earlier frame put there. Most frames it draws nothing, and the
  /// pixels still stand for exactly what the scene is about to sample.
  ///
  /// Declared as a write, that was a half-truth on every frame the pass skipped
  /// — and versioning could not fix it, because versions chain *within* a
  /// frame and this resource is read-modify-write *across* them.
  ///
  /// For scheduling it behaves exactly like a write: it produces the next
  /// version of the name, orders readers after it, and takes the node with it
  /// when [isActive] is false — an atlas nobody is maintaining is an atlas
  /// nobody should sample. What it adds is a promise the graph enforces from
  /// the other end: a maintained resource is bound **whether or not the node
  /// drew**, and a consumer can ask which of the two it got through
  /// `FrameResources.originOf`.
  ///
  /// A name may not appear in both [writes] and [keeps]: the two say opposite
  /// things about the same pixels, and [FrameGraph.compile] rejects it.
  List<ResourceId> get keeps => const <ResourceId>[];

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
    this._current,
    this._kept, {
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

  /// Every version some node declared it [FrameGraphNode.keeps] rather than
  /// writes.
  ///
  /// A version rather than a name, so that a frame where one node maintains a
  /// resource and a later one redraws it outright can still tell the two apart
  /// — and so the answer needs no search for whoever produced it.
  final Set<ResourceVersion> _kept;

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
  int? readVersionOf(int index, ResourceId id) =>
      _bindings[index].reads[id.name];

  /// The version of [id] the node at [index] produces, or null if it writes
  /// none.
  int? writeVersionOf(int index, ResourceId id) =>
      _bindings[index].writes[id.name];

  /// What the node at [index] writes, in the order it declared them.
  ///
  /// Maintained resources are here too: for everything that follows from
  /// producing a version — ordering, lifetime, which texture a name stands on —
  /// a keep *is* a write, and only the promise about the pixels differs.
  Iterable<ResourceId> writtenBy(int index) =>
      _bindings[index].writes.keys.map((name) => ResourceId(name));

  /// What the node at [index] maintains across frames.
  ///
  /// A subset of [writtenBy]. What the resource layer checks the node against
  /// when it finishes: a maintained resource that is not bound is a node that
  /// broke its half of the promise, and the alternative to catching it here is
  /// a reader three passes later finding nothing and quietly doing without.
  Iterable<ResourceId> keptBy(int index) => <ResourceId>[
    for (final entry in _bindings[index].writes.entries)
      if (isKeptVersion(ResourceVersion(ResourceId(entry.key), entry.value)))
        ResourceId(entry.key),
  ];

  /// Whether [version] is maintained across frames rather than drawn by this
  /// one.
  ///
  /// The question `tryTexture` alone could never answer: a bound texture used
  /// to mean only "some node put a texture here", and a consumer had no way to
  /// tell a picture this frame drew from one an earlier frame left.
  bool isKeptVersion(ResourceVersion version) => _kept.contains(version);

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
