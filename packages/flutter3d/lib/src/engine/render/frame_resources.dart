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

/// The textures a frame's nodes read and write, acquired late and released
/// early.
///
/// Acquired on first use rather than up front, so a node the graph culled costs
/// no texture at all — the saving the culling promised, actually taken. And
/// released the moment [CompiledFrameGraph.releasedAfter] says nothing else
/// wants them, which is what lets two passes that never overlap share one.
final class FrameResources {
  FrameResources({
    required this.pool,
    required this.graph,
    required this.frameWidth,
    required this.frameHeight,
  });

  final RenderTargetPool pool;
  final CompiledFrameGraph graph;
  final int frameWidth;
  final int frameHeight;

  final Map<String, ResourceDesc> _declared = <String, ResourceDesc>{};
  final Map<String, gpu.Texture> _live = <String, gpu.Texture>{};
  final Set<String> _external = <String>{};

  /// Says how to make [desc.id] if anything asks for it.
  void declare(ResourceDesc desc) => _declared[desc.id.name] = desc;

  /// Hands in a texture the engine owns — the swapchain image, the frame's
  /// colour target. Never released here, because it was never acquired here.
  void provide(ResourceId id, gpu.Texture texture) {
    _live[id.name] = texture;
    _external.add(id.name);
  }

  /// The texture for [id], acquiring it on first ask.
  gpu.Texture texture(ResourceId id) {
    final existing = _live[id.name];
    if (existing != null) return existing;

    final desc = _declared[id.name];
    if (desc == null) {
      throw FrameGraphError(
        'a pass asked for "$id", which is neither declared nor provided. The '
        'graph accepted it because some node writes it — this is the other '
        'half of that promise, and the two are declared in different places',
      );
    }

    final texture = pool.acquire(desc.resolve(frameWidth, frameHeight));
    _live[id.name] = texture;
    return texture;
  }

  /// Hands back whatever the node at [index] was the last to touch.
  void endNode(int index) {
    for (final id in graph.releasedAfter(index)) {
      if (_external.contains(id.name)) continue;
      final texture = _live.remove(id.name);
      if (texture != null) pool.release(texture);
    }
  }

  /// Hands back anything still held, for a frame that ended early.
  ///
  /// A pass that threw halfway leaves textures lent out, and the pool has no
  /// other way to learn they are free. Without this a failing frame leaks one
  /// set of targets per attempt.
  void releaseAll() {
    for (final entry in _live.entries) {
      if (_external.contains(entry.key)) continue;
      pool.release(entry.value);
    }
    _live.removeWhere((name, _) => !_external.contains(name));
  }
}
