/// Turning a graph's declared resources into actual textures.
///
/// Its own file, and the only part of the frame graph that knows what a GPU is.
/// `frame_graph.dart` decides *what* runs, in what order, and when a texture
/// stops being needed — all of it arithmetic, all of it unit-tested. This is
/// the thin layer that acts on those answers, and it is thin on purpose: the
/// bugs live in the decisions, and the decisions are next door where a test can
/// reach them.
///
/// It names `gpu.PixelFormat` rather than inventing a format enum of its own.
/// Web is a goal and a second backend would want that abstraction, but there is
/// no second backend to design it against yet, and a seam drawn without one is
/// almost always drawn in the wrong place. When web arrives, this file is where
/// it goes.
library;

import 'package:flutter_gpu/gpu.dart' as gpu;

import '../gpu/render_target_pool.dart';
import 'frame_graph.dart';

/// How large a resource is, relative to the frame or in its own right.
sealed class ResourceSize {
  const ResourceSize();

  /// The size in pixels, given the frame's.
  (int, int) resolve(int frameWidth, int frameHeight);
}

/// A fraction of the frame: full size at one, half at two.
///
/// A divisor rather than a scale factor because that is what a bloom chain
/// actually is, and because integer division is the only thing that gives the
/// same answer on every frame at every window size.
final class FrameFraction extends ResourceSize {
  const FrameFraction([this.divisor = 1]) : assert(divisor >= 1);

  final int divisor;

  @override
  (int, int) resolve(int frameWidth, int frameHeight) {
    // Never below one pixel: a chain taken far enough would otherwise ask for
    // a zero-sized texture, and that is a driver error rather than an
    // exception. The pool's `scaled` guards the same way for the same reason.
    final w = frameWidth ~/ divisor;
    final h = frameHeight ~/ divisor;
    return (w < 1 ? 1 : w, h < 1 ? 1 : h);
  }
}

/// A fixed size, for anything whose extent is its own business — a shadow
/// atlas is the same size whatever the window is doing.
final class AbsolutePixels extends ResourceSize {
  const AbsolutePixels(this.width, this.height);

  final int width;
  final int height;

  @override
  (int, int) resolve(int frameWidth, int frameHeight) => (width, height);
}

/// Where the pixels behind a bound resource came from.
///
/// [FrameResources.tryTexture] answers "is there a texture", which used to be
/// the only question available and is not the same question. A shadow map that
/// was not drawn this frame and a shadow atlas that deliberately holds an
/// earlier frame's pixels both come back as a texture, and they mean opposite
/// things: the first is stale and must not be sampled, the second is exactly
/// what the sampler is for. See [FrameGraphNode.keeps].
enum ResourceOrigin {
  /// A node drew it during this frame. Absent means nothing produced it, and a
  /// reader that can do without has to.
  drawn,

  /// A node maintains it across frames. It is valid to sample, and some or all
  /// of it predates this frame — deliberately.
  kept,
}

/// What a node is asking for when it writes a resource.
final class ResourceDesc {
  const ResourceDesc({
    required this.id,
    required this.format,
    this.size = const FrameFraction(),
    this.sampleCount = 1,
    this.storageMode = gpu.StorageMode.devicePrivate,
  });

  final ResourceId id;
  final gpu.PixelFormat format;
  final ResourceSize size;
  final int sampleCount;

  /// `deviceTransient` is tile memory: cheaper, and unreadable afterwards. A
  /// resource another node declares a read on must not be transient, which is
  /// a rule the graph could check and does not yet.
  final gpu.StorageMode storageMode;

  RenderTargetSpec resolve(int frameWidth, int frameHeight) {
    final (width, height) = size.resolve(frameWidth, frameHeight);
    return RenderTargetSpec(
      width: width,
      height: height,
      format: format,
      sampleCount: sampleCount,
      storageMode: storageMode,
    );
  }
}

/// Where a frame's textures come from, and where they go back to.
///
/// An interface rather than a [RenderTargetPool] because **a texture cannot go
/// straight back to the pool when the last pass stops reading it.** The GPU is
/// still working through this frame's command buffers; handing the texture
/// back immediately lets the pool lend it to the next acquirer while the
/// hardware is reading it, and the result is an intermittent wrong picture —
/// the hardest kind of defect to trace back to its cause.
///
/// The renderer already knew this and defers releases by a full ring of frames
/// in flight. [FrameResources] released straight to the pool until the shadow
/// passes were read closely enough to notice, which is the argument for
/// reading working code before replacing it.
abstract interface class FrameTextureSource {
  gpu.Texture acquire(RenderTargetSpec spec);

  /// Gives a texture up. The implementation decides *when* it is safe to reuse.
  void release(gpu.Texture texture);
}

/// A source that returns textures to the pool at once.
///
/// For tests and for anything that is not inside a frame in flight. Using this
/// from a renderer is the bug described on [FrameTextureSource].
final class ImmediateTextureSource implements FrameTextureSource {
  const ImmediateTextureSource(this.pool);

  final RenderTargetPool pool;

  @override
  gpu.Texture acquire(RenderTargetSpec spec) => pool.acquire(spec);

  @override
  void release(gpu.Texture texture) => pool.release(texture);
}

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
  });

  final FrameTextureSource source;
  final CompiledFrameGraph graph;
  final int frameWidth;
  final int frameHeight;

  final Map<String, ResourceDesc> _declared = <String, ResourceDesc>{};
  final Map<ResourceVersion, gpu.Texture> _live =
      <ResourceVersion, gpu.Texture>{};
  final Set<ResourceVersion> _external = <ResourceVersion>{};

  /// Scratch the node running right now asked for, freed when it ends.
  final List<gpu.Texture> _scratch = <gpu.Texture>[];

  /// Which node is running, as an index into [CompiledFrameGraph.order], or -1
  /// between nodes.
  ///
  /// Versions are what a node sees rather than what the frame currently holds:
  /// the pass that reads `hdr_colour` and writes it back has to be handed two
  /// different textures under one name, and which two depends on where in the
  /// order it sits.
  int _node = -1;

  /// Says how to make [desc.id] if anything asks for it.
  void declare(ResourceDesc desc) => _declared[desc.id.name] = desc;

  /// Hands in a texture the engine owns — the swapchain image, the frame's
  /// colour target, or a long-lived buffer a node writes into rather than
  /// allocating. Never released here, because it was never acquired here.
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
  void provide(ResourceId id, gpu.Texture texture) {
    final key = ResourceVersion(id, _writeVersionFor(id));
    _live[key] = texture;
    _external.add(key);
  }

  /// The texture for [id] as the running node sees it, acquiring it on first
  /// ask.
  ///
  /// A node that reads [id] gets the version it consumes; a node that only
  /// writes it gets the version it produces, which is the first pooled
  /// allocation this layer performs for anybody. A node that does both gets its
  /// input, and hands its output back with [provide].
  gpu.Texture texture(ResourceId id) {
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

    final texture = source.acquire(desc.resolve(frameWidth, frameHeight));
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
  gpu.Texture? tryTexture(ResourceId id) =>
      _live[ResourceVersion(id, _versionFor(id))];

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
  gpu.Texture transient(RenderTargetSpec spec) {
    final texture = source.acquire(spec);
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
      source.release(texture);
    }
    for (final texture in _scratch) {
      source.release(texture);
    }
    _scratch.clear();
    _node = -1;
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
    final given = <gpu.Texture>[];
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
    var version = graph.currentVersionOf(id);
    while (version > 0 && !_live.containsKey(ResourceVersion(id, version))) {
      version--;
    }
    return version;
  }

  /// Which version a [provide] binds. Zero outside a node: that is the frame's
  /// own texture, handed in before anything has run.
  int _writeVersionFor(ResourceId id) =>
      _node < 0 ? 0 : graph.writeVersionOf(_node, id) ?? 0;
}
