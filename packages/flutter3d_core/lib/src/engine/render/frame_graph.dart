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

import 'resource_desc.dart';

part 'frame_graph_compile.dart';
part 'frame_graph_snapshot.dart';

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
  /// Version [version] of the resource [id].
  const ResourceVersion(this.id, this.version);

  /// The resource this is a version of.
  final ResourceId id;

  /// Which write produced it: nought for what the engine handed in, one for
  /// the first write in the frame, and up from there.
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
  /// Lets a subclass be const.
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

  /// Whether the device this frame is drawn on can run the pass at all —
  /// `gfx-50n`.
  ///
  /// **Separate from [isActive] because the two answer different questions,
  /// and a caller needs to tell them apart.** An inactive pass is a pass the
  /// frame was told not to run; an unsupported one is a pass this device
  /// cannot run whatever anybody asks. The first is answered by changing a
  /// setting and the second is not answered at all, so reporting them the
  /// same way sends somebody looking through their own configuration for a
  /// limit that belongs to their hardware.
  ///
  /// What it exists for so far: a pass that reads the surface buffer needs a
  /// second colour attachment, and `GraphicsDevice.maxColorAttachments` is
  /// one on Impeller's OpenGL ES path — where opening one aborts the process
  /// rather than failing. The buffer is still declared and the scene pass
  /// still writes it where it can; what this decides is whether the reader is
  /// in the frame.
  ///
  /// Asked once at compile, beside [isActive], and reported as
  /// [PassSkip.unsupported].
  bool get isSupported => true;

  /// Whether what the node runs with is ready this frame: false while a
  /// pipeline, a kernel or a placement it waits for is still loading.
  ///
  /// **A registration is synchronous, a load is not.** A node is added at
  /// once and its work loads behind it (`RendererSteps.addComputeStep`
  /// places a step while the frame goes on); until the load is done the
  /// node is left out of the frame as [PassSkip.pending], and whatever only
  /// read what it writes is culled with it, as for a pass that cannot run.
  /// The frame after the load is done has it.
  ///
  /// Asked once at compile, beside [isActive] and [isSupported].
  bool get isReady => true;

  /// Lets go of what the node holds on a device: called once, when the
  /// registration that put it in a frame is cancelled, after no frame in
  /// flight can still be using it.
  ///
  /// Empty here, since most nodes hold nothing of their own between frames.
  /// A node that keeps a texture, a buffer or a pipeline across frames
  /// overrides it — the one teardown verb a node has.
  void dispose() {}

  /// Declares what this node touches, into [builder]: what [FrameGraph.compile]
  /// works the frame out from (1.0).
  ///
  /// **The whole declaration, where the getters are the short one.** By
  /// default it hands [builder] [reads], [optionalReads], [writes] and
  /// [keeps], so a node that only names resources keeps doing it with the
  /// getters. A node that makes resources of its own — a plugin's scratch
  /// target, the second and third colour attachments of a pass with several
  /// outputs — declares them here with [FrameGraphBuilder.create], and the
  /// graph knows how to make each before the node runs, when it stops being
  /// needed, and that a texture whose lifetime ended earlier in the frame
  /// may stand behind it (`FrameResources.alias`). A node that asks where it
  /// runs (a compute step) says so with [FrameGraphBuilder.place].
  ///
  /// Called once per compile, before anything is ordered; a node answers
  /// the same for the same frame, as the getters do.
  ///
  /// **`FrameResources.declare` from inside `execute` stays, as the
  /// documented exception**: a node whose resource's size or format it only
  /// knows once it runs. Such a resource still has to be named here — a
  /// write the graph has not seen is one nobody can read — and is made the
  /// first time it is asked for.
  void setup(FrameGraphBuilder builder) {
    reads.forEach(builder.read);
    optionalReads.forEach(builder.readIfProduced);
    writes.forEach(builder.write);
    keeps.forEach(builder.keep);
  }
}

/// What a node is handed in [FrameGraphNode.setup]: where it says what it
/// reads, writes, keeps and makes.
///
/// One object that can gain members, rather than a list of parameters that
/// grows: a later minor that lets a node declare something new (a buffer's
/// size, a view mask) adds a method here and breaks no node.
final class FrameGraphBuilder {
  FrameGraphBuilder._(this.node);

  /// The name of the node declaring, for its messages.
  final String node;

  // Made at the first declaration of each kind, so a node that declares
  // two things costs two lists, not six: this runs for every node of every
  // frame.
  List<ResourceId>? _reads;
  List<ResourceId>? _optionalReads;
  List<ResourceId>? _writes;
  List<ResourceId>? _keeps;
  List<ResourceDesc>? _created;
  PlacementRequest? _placement;

  /// The node needs [id] produced before it runs; see
  /// [FrameGraphNode.reads].
  void read(ResourceId id) => (_reads ??= <ResourceId>[]).add(id);

  /// The node samples [id] if the frame produces it; see
  /// [FrameGraphNode.optionalReads].
  void readIfProduced(ResourceId id) =>
      (_optionalReads ??= <ResourceId>[]).add(id);

  /// The node produces [id] fresh this frame; see [FrameGraphNode.writes].
  void write(ResourceId id) => (_writes ??= <ResourceId>[]).add(id);

  /// The node maintains [id] across frames; see [FrameGraphNode.keeps].
  void keep(ResourceId id) => (_keeps ??= <ResourceId>[]).add(id);

  /// The node makes [desc]'s resource and writes it, and hands back its id.
  ///
  /// **A plugin's resource, made by the graph.** The frame knows its size and
  /// format before the node runs, holds a texture for it from its first use
  /// to its last reader, and, with `FrameResources.alias` on, lends it a
  /// texture another resource of the same description finished with earlier
  /// in the frame. Several created resources are how a node declares a pass
  /// with several colour outputs: one per attachment, each opened with
  /// `FrameResources.texture` and handed to the pass it begins.
  ///
  /// [desc]'s id is namespaced like every name a plugin brings:
  /// `<pluginId>.<name>`.
  ResourceId create(ResourceDesc desc) {
    (_created ??= <ResourceDesc>[]).add(desc);
    write(desc.id);
    return desc.id;
  }

  /// The node asks where it runs, with [request]: a compute step's executor
  /// is picked at compile by the graph's [FramePlacer], and the node reads
  /// the answer with [CompiledFrameGraph.placementOf]. A node no placer can
  /// place does not run, and is reported as [PassSkip.unsupported].
  void place(PlacementRequest request) => _placement = request;

  /// What was declared, as the compile reads it. The lists are the
  /// builder's own, which nothing else holds: copying them would be a
  /// second allocation per list per node per frame.
  NodeDeclarations _declarations() => NodeDeclarations._(
    reads: _reads ?? const <ResourceId>[],
    optionalReads: _optionalReads ?? const <ResourceId>[],
    writes: _writes ?? const <ResourceId>[],
    keeps: _keeps ?? const <ResourceId>[],
    created: _created ?? const <ResourceDesc>[],
    placement: _placement,
  );
}

/// What one node declared in [FrameGraphNode.setup], as the compile read it.
final class NodeDeclarations {
  const NodeDeclarations._({
    required this.reads,
    required this.optionalReads,
    required this.writes,
    required this.keeps,
    required this.created,
    required this.placement,
  });

  /// What [node] declared, through its [FrameGraphNode.setup].
  factory NodeDeclarations.of(FrameGraphNode node) {
    final builder = FrameGraphBuilder._(node.name);
    node.setup(builder);
    return builder._declarations();
  }

  /// The resources the node needs; a missing one culls it.
  final List<ResourceId> reads;

  /// The resources the node reads when they are there and does without when
  /// they are not.
  final List<ResourceId> optionalReads;

  /// Every write, the created resources' among them.
  final List<ResourceId> writes;

  /// The resources the node maintains across frames rather than producing
  /// fresh.
  final List<ResourceId> keeps;

  /// The resources the node makes, each also among [writes].
  final List<ResourceDesc> created;

  /// Where the node asked to run, or null for the frame's own device.
  final PlacementRequest? placement;
}

/// What a node asks of where it runs: a compute step's wish for the
/// device's own compute, a sidecar, or the CPU.
///
/// **The seam a placement plugs into, and nothing more here.** The kinds of
/// request and of answer belong to the compute work that defines them; the
/// graph only carries a request from [FrameGraphBuilder.place] to the
/// [FramePlacer] and the answer to [CompiledFrameGraph.placementOf].
abstract base class PlacementRequest {
  /// Lets a subclass be const.
  const PlacementRequest();

  /// What the request is called in a report or an error.
  String get name;
}

/// What a [FramePlacer] is asked about one node.
final class FramePlacementContext {
  const FramePlacementContext._(this.node, this.request, this.declarations);

  /// The node asking.
  final FrameGraphNode node;

  /// What it asked for.
  final PlacementRequest request;

  /// Everything it declared, for a placer that weighs what it reads and
  /// writes.
  final NodeDeclarations declarations;
}

/// Picks where each node that asked to be placed runs, once per compile.
///
/// Handed to [FrameGraph.compile]. Answers the placement a node reads back
/// with [CompiledFrameGraph.placementOf], or null when nothing this frame can
/// run the node — which drops it as [PassSkip.unsupported].
abstract base class FramePlacer {
  /// Lets a subclass be const.
  const FramePlacer();

  /// What [place] answers for a node whose placement is still being
  /// loaded: the node is left out of this frame as [PassSkip.pending], not
  /// as [PassSkip.unsupported], and asked again at the next compile.
  static const Object pending = _PendingPlacement();

  /// Where [context]'s node runs, [pending] while that is still being
  /// worked out, or null when nowhere can.
  Object? place(FramePlacementContext context);
}

final class _PendingPlacement {
  const _PendingPlacement();

  @override
  String toString() => 'FramePlacer.pending';
}

/// A node that threw while it ran, and whose it was: what a frame reports
/// for a quarantined pass ([PassSkip.failed]).
///
/// **The frame goes on, and says whose pass broke.** A node a plugin or the
/// application placed that throws from its `execute` is taken out of the
/// frames that follow, until its registration is made again (the plugin
/// switched off and on); the rest of the frame is drawn, and what only read
/// the node's output is culled or does without, as for a pass that did not
/// run.
final class NodeFailure {
  /// [node] threw [error] at [stackTrace], in a pass [owner] placed.
  const NodeFailure({
    required this.node,
    required this.owner,
    required this.error,
    required this.stackTrace,
    this.plugin,
  });

  /// The node's name.
  final String node;

  /// Who placed it, as a person reads it: `plugin "acme.glow"`, or `the
  /// application`.
  final String owner;

  /// The id of the plugin that placed it, or null for the application's.
  final String? plugin;

  /// What it threw.
  final Object error;

  /// Where.
  final StackTrace stackTrace;

  @override
  String toString() => '"$node" of $owner threw: $error';
}

/// Why a pass that was registered did not run — `gfx-39n`.
///
/// The compile has always computed all four of these and then thrown the
/// distinction away into a bare list of nodes, which is one answer where
/// there are four. They are not interchangeable, and the difference is what a
/// caller needs: [settings] means the frame did what it was told, [disabled]
/// means somebody said so by name, [unconsumed] means the pass ran for nobody
/// and is the *graph* being clever, and [starved] means something upstream
/// could not run and this is the consequence rather than the cause.
///
/// **It reports what happened, not what was asked.** A per-pass switch that
/// only reads back its own input answers "did I ask for this"; the frame's
/// skip list answers "did it run, and if not, why". This engine has one
/// caller for whom that is not a nicety: an agent handed a 256-pixel picture
/// cannot look at it and infer that the occlusion it asked for was dropped
/// because nothing consumed it.
///
/// A [starved] pass is the one to read first when a frame is wrong, because
/// it names a consequence and some other pass is the cause.
/// **A final class with const instances rather than an enum**, which
/// `tool/structure.dart` insists on for a published package and is right to.
/// The fifth reason arrived — [unsupported], a pass refused for a capability
/// the device lacks, which is exactly the candidate this note named before it
/// existed — and it arrived without breaking an exhaustive `switch` anybody
/// had written, which is the whole of the argument. `TonemapCurve` and
/// `LightingModel` have the same shape for the same reason.
final class PassSkip {
  const PassSkip._(this.name);

  /// The name it is written down as.
  final String name;

  /// The node's own [FrameGraphNode.isActive] said there was nothing to do —
  /// bloom at zero intensity, occlusion switched off in the settings.
  static const PassSkip settings = PassSkip._('settings');

  /// A caller named it in [FrameGraph.compile]'s `disabled`. The renderer's
  /// own frames never do: a step is switched off through
  /// `RenderSettings.without`, and reported as [switchedOff].
  static const PassSkip disabled = PassSkip._('disabled');

  /// It could have run, and nothing downstream wanted what it produces.
  static const PassSkip unconsumed = PassSkip._('unconsumed');

  /// Something it reads unconditionally was not produced this frame, so it
  /// could not run. The cause is upstream; this is the effect. Like a pass
  /// that is off, it takes no version: a pass after it that reads what it
  /// would have drawn over in place reads what the pass before it left.
  static const PassSkip starved = PassSkip._('starved');

  /// The device cannot run it — `gfx-50n`, and the fifth reason the note
  /// above predicted.
  ///
  /// **The only one of the five that no setting will change.** The other four
  /// describe a decision about this frame; this describes the machine. A
  /// caller who gets it should stop looking through their configuration: the
  /// pass is absent on this device and will be absent on the next frame too.
  ///
  /// So far it means one thing — the pass reads the surface buffer and the
  /// device opens a single colour attachment. See
  /// `GraphicsDevice.maxColorAttachments`, whose documentation says what
  /// happens on the backend where the answer is one and why it is not a
  /// probe.
  static const PassSkip unsupported = PassSkip._('unsupported');

  /// The pass belongs to a `RenderStep` the caller switched off through
  /// `RenderSettings.without` or `RenderSettings.only`.
  ///
  /// **A narrower [settings], not a different mechanism.** The step was
  /// switched off by changing its own setting, and the pass is inactive for
  /// exactly the reason a pass off by default is. What this adds is who said
  /// so: a frame built with `without({RenderStep.bloom})` reports its bloom
  /// as switched off, and a frame that never asked for light shafts reports
  /// them as [settings], so a caller reading the list can tell the steps they
  /// removed from the ones that were never on.
  ///
  /// A step that has no pass of its own — the tone curve, the grade, the
  /// distance fog, all of them arithmetic inside another pass — is reported
  /// under the step's own name with this reason, in `FrameResult.skipped`.
  static const PassSkip switchedOff = PassSkip._('switched off');

  /// Something the frame was asked for and did not give, which is not a
  /// pass at all: the polygon mode, a coverage mode, the multisampling, a
  /// cube shadow row. Only `FrameResult.skipped` reports it, under the names
  /// in `FrameResult.declinedNames`.
  ///
  /// **The same four facts `FrameResult` already carried as fields**, each
  /// its own convention — `wireframeDeclined`, `alphaToCoverageDeclined`,
  /// `antiAliasing.msaaDeclined`, `shadowsDenied`. They stay; this lists
  /// them where everything else that did not happen is listed, so a caller
  /// walking `skipped` (or a `RenderListener` handed it entry by entry)
  /// meets them without knowing four field names.
  ///
  /// Not [unsupported]: two of the four are the frame's decision rather
  /// than the device's — multisampling given up because a pass reads the
  /// surface buffer, a light refused a row because the atlas was full — and
  /// a caller can change both.
  static const PassSkip declined = PassSkip._('declined');

  /// What the pass runs with is still loading — a kernel being placed, a
  /// pipeline being built ([FrameGraphNode.isReady] false, or a
  /// [FramePlacer] answering [FramePlacer.pending]). The frame after the
  /// load is done has it; nothing needs changing.
  static const PassSkip pending = PassSkip._('pending');

  /// The pass threw when it ran and is quarantined: left out of every frame
  /// until the registration that placed it is made again.
  /// [SkippedPass.failure] says what it threw and whose it was.
  static const PassSkip failed = PassSkip._('failed');

  /// All of them, in the order a reader should try them: the three a caller
  /// asked for, then the two the frame decided, then the two the device or
  /// the frame refused, then the one that waits and the one that broke.
  static const List<PassSkip> values = <PassSkip>[
    settings,
    switchedOff,
    disabled,
    unconsumed,
    starved,
    unsupported,
    declined,
    pending,
    failed,
  ];

  /// The reason called [name], or null for one this version does not know.
  static PassSkip? byName(String name) {
    for (final reason in values) {
      if (reason.name == name) return reason;
    }
    return null;
  }

  @override
  String toString() => 'PassSkip.$name';
}

/// A registered pass that did not run, and why.
///
/// A class rather than a record, so it can later say more (what it would
/// have read) without breaking a reader.
final class SkippedPass {
  /// A skip of the pass [name] for [reason], with the [failure] that caused
  /// it when there was one.
  const SkippedPass({required this.name, required this.reason, this.failure});

  /// The pass's name.
  final String name;

  /// Why it did not run.
  final PassSkip reason;

  /// For a [PassSkip.failed] pass, what it threw and whose it was; null
  /// for every other reason.
  final NodeFailure? failure;

  @override
  bool operator ==(Object other) =>
      other is SkippedPass &&
      other.name == name &&
      other.reason == reason &&
      identical(other.failure, failure);

  @override
  int get hashCode => Object.hash(name, reason);

  @override
  String toString() => failure == null
      ? 'SkippedPass($name, $reason)'
      : 'SkippedPass($name, $reason, ${failure!.owner})';
}

/// A graph that failed to compile, with the reason a person can act on.
final class FrameGraphError extends Error {
  /// An error carrying [message].
  FrameGraphError(this.message);

  /// What went wrong, worded for a person to act on.
  final String message;
  @override
  String toString() => 'FrameGraphError: $message';
}

/// The result: the nodes to run, in order, what was dropped, and how long each
/// resource has to stay alive.
final class CompiledFrameGraph {
  const CompiledFrameGraph._(
    this._lastUse,
    this._readers,
    this._bindings,
    this._current,
    this._kept, {
    required this.order,
    required this.culled,
    required this.outputs,
    this.skipped = const <SkippedPass>[],
    this._created = const <String, ResourceDesc>{},
    this._placements = const <String, Object>{},
  });

  final Map<String, ResourceDesc> _created;
  final Map<String, Object> _placements;

  /// How to make each resource a surviving node declared with
  /// [FrameGraphBuilder.create], in the order the nodes run.
  ///
  /// `FrameResources` declares every one of them before the first node, so a
  /// plugin's resource is made at its first use and goes back at its last
  /// like any of the engine's.
  Iterable<ResourceDesc> get created => _created.values;

  /// How to make [id], when a surviving node created it; null otherwise.
  ResourceDesc? descriptorOf(ResourceId id) => _created[id.name];

  /// Where the node called [name] runs, as the [FramePlacer] answered, or
  /// null for a node that asked nothing (it runs on the frame's device).
  T? placementOf<T extends Object>(String name) => switch (_placements[name]) {
    final T placement => placement,
    _ => null,
  };

  /// Nodes to execute, earliest first.
  final List<FrameGraphNode> order;

  /// Nodes left out, whatever the reason.
  ///
  /// Kept rather than discarded so the reason a pass did not run is
  /// answerable. A pass that silently stops running is the kind of thing that
  /// gets debugged twice.
  ///
  /// The doc comment above said exactly that before [skipped] existed, and the
  /// list could not deliver it: it recorded *that* a pass was left out and
  /// nothing about why, so the four cases the compile distinguishes arrived as
  /// one. Kept as it was, in registration order, because callers count it and
  /// map it to names; [skipped] is the same nodes with the answer attached.
  final List<FrameGraphNode> culled;

  /// The same passes as [culled], each with why it did not run — `gfx-39n`.
  final List<SkippedPass> skipped;

  /// This graph written down for a tool: the passes that ran with the
  /// versions they read and wrote, the ones that did not with why, and the
  /// outputs — as JSON or Mermaid through [FrameGraphSnapshot].
  FrameGraphSnapshot snapshot() => _snapshotOf(this);

  /// Why [name] did not run, or null if it ran or was never registered.
  PassSkip? skipReason(String name) {
    for (final entry in skipped) {
      if (entry.name == name) return entry.reason;
    }
    return null;
  }

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
  ///
  /// The engine reads [resources], because a pass cares which resources exist
  /// and not how many times each was rewritten. This is for a tool drawing the
  /// graph — a frame debugger that wants a node per version and an edge per
  /// read, which is the picture that shows where a pass is waiting.
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
  /// A version at a time, because that is the whole point: `hdr_color@0` goes
  /// back after its last reader even though `hdr_color@1` is still live.
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
