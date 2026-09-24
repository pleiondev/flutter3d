/// Turning a graph's declared resources into actual textures.
///
/// Its own file, and the part of the frame graph that owns textures.
/// `frame_graph.dart` decides *what* runs, in what order, and when a texture
/// stops being needed — all of it arithmetic, all of it unit-tested. This is
/// the thin layer that acts on those answers, and it is thin on purpose: the
/// bugs live in the decisions, and the decisions are next door where a test can
/// reach them.
///
/// **No backend import, and that is now checked.** A resource is described in
/// the engine's own vocabulary — `TextureFormat` and `StorageMode` from
/// `graphics/formats.dart` — and what comes back is a [TextureHandle], which
/// carries a texture's description without carrying any backend's type for it.
/// The translation happens where the texture is actually created, in
/// `gpu/gpu_texture.dart`.
///
/// The thinness was, until that handle existed, unfalsifiable: the release
/// rules below could only be checked by reading them or by a golden image
/// noticing a frame later, because nothing here could be constructed off a
/// device. `test/frame_resources_test.dart` is what the handle bought.
library;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import 'frame_graph.dart';
import 'frame_texture_source.dart';
import 'resource_desc.dart';

// Re-exported so every existing import of this file keeps seeing
// `ResourceDesc`, `ResourceOrigin`, `FrameTextureSource` and friends without
// change: they moved out because they are independent value types with no
// claim on `FrameResources`' private state, not because anything using them
// should now import three files instead of one.
export 'frame_texture_source.dart';
export 'resource_desc.dart';

/// The textures a frame's nodes read and write, acquired late and released
/// early.
///
/// Acquired on first use rather than up front, so a node the graph culled costs
/// no texture at all — the saving the culling promised, actually taken. And
/// released the moment [CompiledFrameGraph.retiredAfter] says nothing else
/// wants them, which is what lets two passes that never overlap share one.
///
/// Keyed on [ResourceVersion] rather than on the name, which is the difference
/// between a chain that works and a leak. A pass that writes the resource it
/// read produces a second texture under the same name; keyed on the name, the
/// first one is simply forgotten and never handed back.
final class FrameResources {
  FrameResources({
    required this.source,
    required this.graph,
    required this.frameWidth,
    required this.frameHeight,
    this.alias = false,
    this.onRetire,
  });

  final FrameTextureSource source;
  final CompiledFrameGraph graph;
  final int frameWidth;
  final int frameHeight;

  /// Whether a texture whose lifetime has ended is lent again within this
  /// frame — `H7`.
  ///
  /// **Off, a frame holds one texture per resource it touched.** Everything
  /// retired goes to [source], which is right about *across* frames — the GPU
  /// may still be reading it — and needlessly cautious *within* one: the
  /// passes of a frame reach the queue in the order they were encoded, so a
  /// target whose last reader has been encoded can be drawn over by any later
  /// pass, and the queue orders the draw after the read. Readbacks are queued
  /// the same way — `GraphicsDevice.readback` promises the copy lands behind
  /// the pass that filled the texture, and so ahead of whatever the next
  /// owner draws.
  ///
  /// On, a retired texture waits in a free list of its own spec for the rest
  /// of the frame, and [texture] and [transient] take from there before they
  /// ask the source. The lifetimes are intervals over the graph's order —
  /// first use at the first ask, last use at [CompiledFrameGraph.retiredAfter]
  /// — and taking any free texture of the right spec at each first use, in
  /// order, is the greedy colouring of those intervals, which for intervals is
  /// optimal: a frame holds exactly as many textures of a spec as it ever has
  /// live at once. Everything still in the free lists goes to [source] after
  /// the last node, so the ring of frames in flight defers them as before.
  ///
  /// Off by default, because the recorded frames were drawn without it and a
  /// pass that loads a target instead of clearing it would now load another
  /// resource's pixels rather than a previous frame's. None of the built-in
  /// passes does, and `transient_aliasing_test.dart` holds that by poisoning
  /// every texture as its lifetime ends.
  final bool alias;

  /// Told about every texture whose lifetime in this frame has just ended,
  /// before anything else can be handed it.
  ///
  /// For tests: a hook that fills the texture with garbage turns a pass that
  /// reads a resource after its last declared use — or loads a target it
  /// never wrote — into a changed picture instead of a picture that happens
  /// to be right because the pixels were still there.
  final void Function(TextureHandle texture)? onRetire;

  /// Textures retired this frame and free to be lent again before it ends,
  /// by spec. Empty unless [alias] is on.
  final Map<RenderTargetSpec, List<TextureHandle>> _reusable =
      <RenderTargetSpec, List<TextureHandle>>{};

  /// A texture for [spec]: one retired earlier this frame when there is one,
  /// otherwise the source's.
  TextureHandle _acquire(RenderTargetSpec spec) {
    final free = _reusable[spec];
    return free != null && free.isNotEmpty
        ? free.removeLast()
        : source.acquire(spec);
  }

  /// Ends a texture's lifetime in this frame.
  ///
  /// [key] is the version that retired, or null for a node's scratch. The
  /// newest version of a frame output is never lent again: it is read after
  /// the last node, from outside the graph, by whoever asked for the output,
  /// so its lifetime has not ended and [onRetire] is not told.
  void _retire(TextureHandle texture, [ResourceVersion? key]) {
    final isOutput =
        key != null &&
        graph.outputs.any((id) => id.name == key.id.name) &&
        key.version == graph.currentVersionOf(key.id);
    if (!isOutput) onRetire?.call(texture);
    if (!alias || isOutput) {
      source.release(texture);
      return;
    }
    (_reusable[RenderTargetSpec.of(texture)] ??= <TextureHandle>[]).add(
      texture,
    );
  }

  /// Hands whatever is waiting in the free lists to [source].
  void _flushReusable() {
    for (final free in _reusable.values) {
      free.forEach(source.release);
    }
    _reusable.clear();
  }

  final Map<String, ResourceDesc> _declared = <String, ResourceDesc>{};
  final Map<ResourceVersion, TextureHandle> _live =
      <ResourceVersion, TextureHandle>{};
  final Set<ResourceVersion> _external = <ResourceVersion>{};

  /// Scratch the node running right now asked for, freed when it ends.
  final List<TextureHandle> _scratch = <TextureHandle>[];

  /// Which node is running, as an index into [CompiledFrameGraph.order], or -1
  /// between nodes.
  ///
  /// Versions are what a node sees rather than what the frame currently holds:
  /// the pass that reads `hdr_colour` and writes it back has to be handed two
  /// different textures under one name, and which two depends on where in the
  /// order it sits.
  int _node = -1;

  /// Says how to make `desc.id` if anything asks for it.
  ///
  /// Refuses a transient resource something declares a read on. `deviceTransient`
  /// is tile memory: it exists for the duration of the pass that writes it and
  /// is unreadable afterwards, so a later node's read would sample whatever the
  /// tile happens to hold. On a tiler that is a wrong picture with nothing
  /// logged; on a desktop backend that lies about the storage mode it might
  /// even work, which is worse, because then it works everywhere it is tested
  /// and fails on the hardware the mode exists for.
  ///
  /// The check lives here rather than in `frame_graph.dart` deliberately: that
  /// file knows nothing about GPUs — no `StorageMode`, no `TextureFormat`, no
  /// device — and 31 tests exercise it without one. This class is the only
  /// place that holds both halves, the descriptions and the compiled graph.
  ///
  /// Fires never today: every transient allocation goes through [transient],
  /// which is unnamed by construction and so cannot be read by anyone. It is
  /// insurance against the next `ResourceDesc` somebody writes.
  void declare(ResourceDesc desc) {
    if (desc.storageMode == StorageMode.deviceTransient &&
        graph.isRead(desc.id)) {
      throw StateError(
        '"${desc.id.name}" is declared deviceTransient and something reads it. '
        'Tile memory does not survive the pass that wrote it, so the reader '
        'would sample whatever is left there. Either drop the storage mode to '
        'devicePrivate, or stop reading it.',
      );
    }
    _declared[desc.id.name] = desc;
  }

  /// Hands in a texture the engine owns — the swapchain image, the frame's
  /// colour target, or a long-lived buffer a node writes into rather than
  /// allocating. Never released here, because it was never acquired here —
  /// unless it is the node's own [transient], which stays pooled and retires
  /// with the version it now stands for.
  ///
  /// Called between nodes it binds the frame's *input*, version zero. Called
  /// from inside a node it binds that node's output, which is how a pass that
  /// produces a texture of its own — reflections into the renderer's own
  /// target — puts its result behind the name the next reader will use.
  ///
  /// The same call for a written and for a maintained resource, and
  /// deliberately so: which of the two it is was already settled by what the
  /// node declared, and a second way of saying it here is a second knob that
  /// can disagree with the first. What the declaration changes is when the call
  /// is *required* — see [endNode] — and what [originOf] tells a reader.
  ///
  /// A pooled texture this replaces — one the node took through [texture]
  /// before deciding to hand in its own — goes back to the source here. It is
  /// in nobody else's hands, and once the key names the provided texture no
  /// retirement would ever find it again.
  void provide(ResourceId id, TextureHandle texture) {
    final key = ResourceVersion(id, _writeVersionFor(id));
    final replaced = _live[key];
    // **The node's own scratch, handed in as its output, is still pooled** —
    // the way every post effect produces its new version: it cannot sample and
    // write one texture, so it draws into a [transient] and provides that. It
    // used to count as the engine's own and go back with the node's scratch
    // when the node ended, while the graph still named it and later nodes
    // read it. The ring of frames in flight hid that; a texture lent again
    // within the frame — `H7` — would be drawn over under its reader. So it
    // leaves the scratch and retires with its version instead.
    final scratch = _scratch.indexWhere((other) => identical(other, texture));
    if (scratch >= 0) _scratch.removeAt(scratch);
    final wasExternal = scratch >= 0
        ? _external.remove(key)
        : !_external.add(key);
    _live[key] = texture;
    if (replaced == null || wasExternal || identical(replaced, texture)) return;
    if (_live.values.any((other) => identical(other, replaced))) return;
    _retire(replaced);
  }

  /// The texture for [id] as the running node sees it, acquiring it on first
  /// ask.
  ///
  /// A node that reads [id] gets the version it consumes; a node that only
  /// writes it gets the version it produces, which is the first pooled
  /// allocation this layer performs for anybody. A node that does both gets its
  /// input, and hands its output back with [provide].
  TextureHandle texture(ResourceId id) {
    final key = ResourceVersion(id, _versionFor(id));
    final existing = _live[key];
    if (existing != null) return existing;

    final desc = _declared[id.name];
    if (desc == null) {
      throw FrameGraphError(
        'a pass asked for "$key", which is neither declared nor provided. The '
        'graph accepted it because some node writes it — this is the other '
        'half of that promise, and the two are declared in different places',
      );
    }

    final texture = _acquire(desc.resolve(frameWidth, frameHeight));
    _live[key] = texture;
    return texture;
  }

  /// The texture behind [id], or null when no surviving node produced one.
  ///
  /// What a reader that can do without asks. Never allocates: a culled effect
  /// must cost nothing, and a caller that wants a texture regardless wants
  /// [texture].
  ///
  /// A texture here does **not** mean this frame drew one — see [originOf].
  TextureHandle? tryTexture(ResourceId id) =>
      _live[ResourceVersion(id, _versionFor(id))];

  /// The texture behind a frame *output*, once every node has run.
  ///
  /// The one read that legitimately happens outside a node, and the only one:
  /// the frame itself has finished, and what it asks for is the newest version
  /// of a name rather than the version some node was entitled to see. Every
  /// other read from outside a node is closed on purpose — see [_versionFor] —
  /// because a node reading a name it never declared would be handed whatever
  /// was lying around.
  ///
  /// This exists because the renderer used to return its own `_ldrColor` field
  /// as the finished frame, which is the texture the composite happens to draw
  /// into. Nothing was wrong with the picture while the composite was last;
  /// what was wrong was that it was last *by assumption*. A pass registered
  /// after it would draw a correct image into a new version of `frame`, and the
  /// caller would be handed the composite's output regardless — the effect
  /// running, costing its time, and being invisible. That is the worst failure
  /// available here, because everything about it looks like it works.
  ///
  /// The newest version *anything actually bound*, walking down from the
  /// newest the graph assigned. A writer that starved still took a version
  /// number at compile, and the graph keeps the last surviving writer instead
  /// — see `FrameGraph._reachable` — so the frame's picture is behind an
  /// earlier version, not missing.
  TextureHandle? output(ResourceId id) {
    for (var version = graph.currentVersionOf(id); version >= 0; version--) {
      final texture = _live[ResourceVersion(id, version)];
      if (texture != null) return texture;
    }
    return null;
  }

  /// Whether the texture [tryTexture] would hand back was drawn this frame or
  /// is maintained across frames; null when there is no texture at all.
  ///
  /// The other half of [tryTexture], and the reason the two are separate calls:
  /// a consumer that only needs something to sample takes the texture and stops
  /// there, and one whose answer depends on how old the pixels are — a temporal
  /// effect, a debug overlay, anything accumulating — can ask without the
  /// producer having to tell it out of band.
  ResourceOrigin? originOf(ResourceId id) {
    final key = ResourceVersion(id, _versionFor(id));
    if (!_live.containsKey(key)) return null;
    return graph.isKeptVersion(key)
        ? ResourceOrigin.kept
        : ResourceOrigin.drawn;
  }

  /// A texture for the running node's own working storage.
  ///
  /// Everything below the top of a bloom chain is this: real GPU memory that no
  /// other pass will ever name, so the graph has nothing to say about it — but
  /// it must still come from the frame's own source, because a pass hands its
  /// scratch back while the command buffers that read it are in flight. Doing
  /// that through [FrameTextureSource] is what makes the deferral automatic
  /// rather than something each call site has to remember.
  TextureHandle transient(RenderTargetSpec spec) {
    final texture = _acquire(spec);
    _scratch.add(texture);
    return texture;
  }

  /// Says which node is about to run, so [texture] can answer in its terms.
  ///
  /// And settles what a pass that reads a resource and writes it back produces,
  /// which is the common case and must not need saying: it drew **into the
  /// texture it was given**, so the new version starts out behind the same one.
  /// An overlay draws over the scene in place; only a pass that cannot — one
  /// that samples what it writes, like reflections — produces a second texture,
  /// and that one says so with [provide].
  void beginNode(int index) {
    _node = index;
    for (final id in graph.writtenBy(index)) {
      final written = graph.writeVersionOf(index, id);
      final read = graph.readVersionOf(index, id);
      if (written == null || read == null) continue;
      final from = ResourceVersion(id, read);
      final texture = _live[from];
      if (texture == null) continue;
      final target = ResourceVersion(id, written);
      _live[target] = texture;
      // Whoever owns the texture still owns it. Losing this is how the frame's
      // own colour target would end up handed to the pool.
      if (_external.contains(from)) _external.add(target);
    }
  }

  /// Whether the running node declared [id] at all.
  ///
  /// Answers a question rather than handing out a texture, which is why it is
  /// not a way back to the fallback that was just closed. It exists so a bundle
  /// of optional inputs can be assembled without asking for names this node
  /// never claimed — asking for one is an error, and deriving a bundle should
  /// not mean guessing which names are safe to ask about.
  bool declares(ResourceId id) {
    if (_node < 0 || _node >= graph.order.length) return false;
    final node = graph.order[_node];
    bool named(List<ResourceId> list) =>
        list.any((other) => other.name == id.name);
    return named(node.reads) ||
        named(node.optionalReads) ||
        named(node.writes) ||
        named(node.keeps);
  }

  /// Hands back whatever the node at [index] was the last to touch, and all of
  /// its scratch.
  ///
  /// It also holds the node to the promise a [FrameGraphNode.keeps] makes. A
  /// maintained resource must be bound whether or not the node drew anything —
  /// that is the whole difference between keeping and writing — and a node that
  /// provides it only on the frames it drew has silently turned it back into a
  /// write. Caught here, naming the node, rather than as a reader finding
  /// nothing several passes later and doing without.
  void endNode(int index) {
    for (final id in graph.keptBy(index)) {
      final version = graph.writeVersionOf(index, id);
      if (version == null) continue;
      if (_live.containsKey(ResourceVersion(id, version))) continue;
      throw FrameGraphError(
        '"${graph.order[index].name}" declares that it keeps "${id.name}" and '
        'left it unbound. A maintained resource is provided on every frame the '
        'node runs, drawn into or not — that a frame which drew nothing still '
        'has something worth sampling is the whole of what keeping means. A '
        'resource that is only there when the pass drew is a write',
      );
    }
    for (final key in graph.retiredAfter(index)) {
      if (_external.contains(key)) continue;
      final texture = _live.remove(key);
      if (texture == null) continue;
      // A later version of the same name may still be this very texture — an
      // in-place pass produced no new one — and it goes back when the last
      // version standing on it does, not when the first one retires.
      if (_live.values.any((other) => identical(other, texture))) continue;
      _retire(texture, key);
    }
    for (final texture in _scratch) {
      _retire(texture);
    }
    _scratch.clear();
    _node = -1;
    // Nothing after the last node can take from the free lists, so what is
    // left in them goes to the source for the ring to defer.
    if (index == graph.order.length - 1) _flushReusable();
  }

  /// Hands back anything still held, for a frame that ended early.
  ///
  /// A pass that threw halfway leaves textures lent out, and the pool has no
  /// other way to learn they are free. Without this a failing frame leaks one
  /// set of targets per attempt.
  void releaseAll() {
    // By identity rather than by version, because two versions of one name can
    // stand on the same texture when a pass modified it in place, and handing
    // one texture back twice corrupts the pool's idea of what it has lent.
    final given = <TextureHandle>[];
    for (final entry in _live.entries) {
      if (_external.contains(entry.key)) continue;
      if (given.any((other) => identical(other, entry.value))) continue;
      given.add(entry.value);
      source.release(entry.value);
    }
    _live.removeWhere((key, _) => !_external.contains(key));
    for (final texture in _scratch) {
      source.release(texture);
    }
    _scratch.clear();
    _flushReusable();
  }

  /// Which version of [id] the running node reads, writes, or — for a name it
  /// never declared — finds lying around.
  ///
  /// The undeclared case is the newest version anything has actually put a
  /// texture behind, which is what "the resource, right now" used to mean
  /// before there were versions. It is also all that can be said about a node
  /// that never told the graph it wanted this resource: a node that cares
  /// declares a read, and then gets exactly the version it was ordered after.
  int _versionFor(ResourceId id) {
    if (_node >= 0) {
      final read = graph.readVersionOf(_node, id);
      if (read != null) return read;
      final written = graph.writeVersionOf(_node, id);
      if (written != null) return written;
    }
    // Nothing legitimate reaches here any more, and that is the point.
    //
    // A node that declared neither a read nor a write of this name is asking
    // for something it never told the graph it wanted: it would be handed
    // whatever happened to be lying around, ordered after nothing, and the
    // declarations would be advice rather than a contract.
    //
    // There used to be an exception for reads from outside any node — the
    // frame's own — and closing it was a measurement rather than a decision.
    // Breaking the path on purpose named only tests, which built a node's frame
    // without entering the node first. The engine enters one before every read.
    // An API hole kept open for the convenience of tests is the wrong way round.
    {
      // Declared, but its producer was culled — an optional read of a resource
      // no surviving node writes. That is the case optionalReads exists for,
      // and the answer is "nothing", not an error. Asked of the node's own
      // declarations rather than of its resolved bindings, because a binding
      // is exactly what a culled producer leaves missing.
      // Both bounds. A read from outside any node arrives as -1, and checking
      // only the upper one turned a clear message into a RangeError from inside
      // the resource layer.
      final node = _node >= 0 && _node < graph.order.length
          ? graph.order[_node]
          : null;
      final declared =
          node != null &&
          (node.reads.any((other) => other.name == id.name) ||
              node.optionalReads.any((other) => other.name == id.name) ||
              node.writes.any((other) => other.name == id.name) ||
              node.keeps.any((other) => other.name == id.name));
      if (!declared) {
        throw FrameGraphError(
          _node < 0
              ? 'something outside any node asked for "${id.name}". Every read '
                    'belongs to a node, and the node has to declare it.'
              : 'node ${node?.name ?? _node} asked for "${id.name}" without '
                    'declaring it. Add it to reads or optionalReads.',
        );
      }
      return graph.currentVersionOf(id);
    }
  }

  /// Which version a [provide] binds. Zero outside a node: that is the frame's
  /// own texture, handed in before anything has run.
  int _writeVersionFor(ResourceId id) =>
      _node < 0 ? 0 : graph.writeVersionOf(_node, id) ?? 0;
}
