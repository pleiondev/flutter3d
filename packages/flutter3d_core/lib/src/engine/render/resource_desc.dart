import 'package:flutter3d_hardware/flutter3d_hardware.dart';

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
/// `FrameResources.tryTexture` answers "is there a texture", which used to be
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
    this.storageMode = StorageMode.devicePrivate,
  });

  final ResourceId id;
  final TextureFormat format;
  final ResourceSize size;
  final int sampleCount;

  /// `deviceTransient` is tile memory: cheaper, and unreadable afterwards. A
  /// resource another node declares a read on must not be transient, and
  /// `FrameResources.declare` now refuses one that is.
  final StorageMode storageMode;

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
