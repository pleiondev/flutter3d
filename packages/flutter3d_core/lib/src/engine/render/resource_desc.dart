import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import 'frame_graph.dart';

/// How large a resource is, relative to the frame or in its own right.
///
/// **An open set, read through a visitor** (1.0): a size a later minor adds
/// — a fraction of one view of several, a size taken from another resource
/// — or a plugin's own arrives at [ResourceSizeVisitor.visitUnknown], so
/// code that reads the kinds with [accept] keeps compiling. What every size
/// answers is [resolve], which is all the frame graph asks of one.
///
/// Extendable outside this package, and stays so through 1.x.
abstract base class ResourceSize {
  const ResourceSize();

  /// The size in pixels, given the frame's.
  (int, int) resolve(int frameWidth, int frameHeight);

  /// Hands this size to the [visitor]'s method for its kind;
  /// [ResourceSizeVisitor.visitUnknown] by default.
  R accept<R>(ResourceSizeVisitor<R> visitor) => visitor.visitUnknown(this);
}

/// Something that reads every kind of [ResourceSize]: a tool that writes a
/// frame's resources down, an inspector.
///
/// One abstract method per kind 1.0 knows; a kind added later arrives with
/// a default body that hands it to [visitUnknown], as
/// `MaterialExpressionVisitor` explains for the material language.
abstract base class ResourceSizeVisitor<R> {
  const ResourceSizeVisitor();

  R visitFrameFraction(FrameFraction size);
  R visitAbsolutePixels(AbsolutePixels size);

  /// What a kind this visitor has no method for answers.
  R visitUnknown(ResourceSize size);
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

  @override
  R accept<R>(ResourceSizeVisitor<R> visitor) =>
      visitor.visitFrameFraction(this);
}

/// A fixed size, for anything whose extent is its own business — a shadow
/// atlas is the same size whatever the window is doing.
final class AbsolutePixels extends ResourceSize {
  const AbsolutePixels(this.width, this.height);

  final int width;
  final int height;

  @override
  (int, int) resolve(int frameWidth, int frameHeight) => (width, height);

  @override
  R accept<R>(ResourceSizeVisitor<R> visitor) =>
      visitor.visitAbsolutePixels(this);
}

/// Where the pixels behind a bound resource came from.
///
/// `FrameResources.tryTexture` answers "is there a texture", which used to be
/// the only question available and is not the same question. A shadow map that
/// was not drawn this frame and a shadow atlas that deliberately holds an
/// earlier frame's pixels both come back as a texture, and they mean opposite
/// things: the first is stale and must not be sampled, the second is exactly
/// what the sampler is for. See [FrameGraphNode.keeps].
///
/// A class with constants rather than an enum, so a value added in a minor
/// release does not break a `switch` written against it: [name] is what a
/// file or a snapshot writes, and [byName] reads it back.
final class ResourceOrigin {
  const ResourceOrigin._(this.name);

  /// A node drew it during this frame. Absent means nothing produced it, and a
  /// reader that can do without has to.
  static const ResourceOrigin drawn = ResourceOrigin._('drawn');

  /// A node maintains it across frames. It is valid to sample, and some or all
  /// of it predates this frame — deliberately.
  static const ResourceOrigin kept = ResourceOrigin._('kept');

  /// Every value this version names, in declaration order. A later version
  /// appends; nothing is removed or renamed within a major.
  static const List<ResourceOrigin> values = <ResourceOrigin>[drawn, kept];

  /// The value called [name], or null for a name this version does not know,
  /// which is what a file written by a later version can carry.
  static ResourceOrigin? byName(String name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  /// The stable name, and the wire name: what a file, a report or a snapshot
  /// writes for this value. Never renamed within a major.
  final String name;

  @override
  String toString() => 'ResourceOrigin.$name';
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

  RenderTargetDescriptor resolve(int frameWidth, int frameHeight) {
    final (width, height) = size.resolve(frameWidth, frameHeight);
    return RenderTargetDescriptor(
      width: width,
      height: height,
      format: format,
      sampleCount: sampleCount,
      storageMode: storageMode,
    );
  }
}
