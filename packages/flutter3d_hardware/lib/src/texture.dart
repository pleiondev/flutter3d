/// A texture the engine can hold, pass around and describe without naming a
/// backend.
///
/// **Nothing here may import a graphics API** — `tool/structure.dart` holds it.
/// See
/// `graphics/formats.dart` for why the directory exists.
library;

import 'format_info.dart';
import 'formats.dart';
import 'render_target_pool.dart';
import 'resources.dart';

/// A texture some backend owns, described in the engine's own vocabulary.
///
/// The type `gpu.Texture` used to be is the one that made resource management
/// untestable: it cannot be constructed without a device, so every layer that
/// merely *held* textures — the pool, the frame's resources — needed a running
/// GPU to be exercised at all. This carries the description instead of the
/// object, and keeps the object in [backend] where only the backend layer
/// looks.
///
/// ## Identity is the contract
///
/// Deliberately **no** `==` or `hashCode`. Two places key on textures by
/// identity and both would break under value equality:
///
///  * `RenderTargetPool` records what it has lent out. Two interchangeable
///    textures have identical descriptions by definition — that is what makes
///    them interchangeable — so value equality would make the pool believe it
///    had lent one texture twice, and returning either would return both.
///  * `FrameResources` releases by identity, because a pass that writes the
///    resource it read produces a *second version standing on the same
///    texture*, and that texture goes back to the pool exactly once.
///
/// So: `identical(a, b)` must mean the same underlying texture, and one
/// underlying texture must never acquire two handles. The second half is what
/// `createGpuTexture` in `gpu/gpu_texture.dart` is for — it creates the texture
/// and its one handle in the same expression, so no call site ever holds a bare
/// backend texture it could wrap a second time.
///
/// ## Why the description is carried rather than asked for
///
/// The pool keys on exactly [width], [height], [format], [sampleCount] and
/// [storageMode]; the post passes read [width] and [height] to set a viewport.
/// Every one of those would otherwise be a downcast to the backend type at the
/// use site, which is the same coupling in a less visible place.
final class TextureHandle {
  TextureHandle._(
    this._release, {
    required this.backend,
    required this.width,
    required this.height,
    required this.format,
    this.sampleCount = 1,
    this.storageMode = StorageMode.devicePrivate,
    this.type = TextureType.texture2D,
    TextureDimension? dimension,
    int? depthOrArrayLayers,
    this.mipLevelCount = 1,
    this.usage = TextureUsage.standard,
  }) : dimension =
           dimension ??
           (type == TextureType.textureCube
               ? TextureDimension.cube
               : TextureDimension.d2),
       depthOrArrayLayers =
           depthOrArrayLayers ?? (type == TextureType.textureCube ? 6 : 1);

  final void Function(TextureHandle)? _release;

  /// Gives this back to the device that made it, once: what `dispose` means
  /// on every handle. A second call does nothing. A handle a backend made
  /// without naming its device (a test's fake) has nothing to give back.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _release?.call(this);
  }

  /// Whether [dispose] has run.
  bool get isDisposed => _disposed;
  bool _disposed = false;

  /// The shape a view of it binds as — derived from [type] for every texture
  /// made before 1.0, so a handle built the old way answers correctly.
  final TextureDimension dimension;

  /// Layers, counted as `TextureDescriptor.depthOrArrayLayers` counts them:
  /// six for a cube, six per cube of a cube array, the layer count of an
  /// array, the depth of a 3D texture, one for a 2D texture. A handle that
  /// does not say gets six when [type] is a cube and one otherwise, so the
  /// pre-1.0 creators answer the same way the descriptor does.
  final int depthOrArrayLayers;

  /// Levels counting the base, as the creator was asked for them. One for
  /// every handle that does not say — which is what the pool's targets are.
  final int mipLevelCount;

  /// What it may be used for. [TextureUsage.standard] unless made through
  /// `GraphicsDevice.createTexture` with something narrower.
  final TextureUsage usage;

  /// The backend's own object for this texture.
  ///
  /// `Object` rather than a type parameter or a subclass, because every layer
  /// above the backend must be able to hold a handle without knowing what is in
  /// here, and a type parameter would spread through every one of them. Only
  /// `gpu/gpu_texture.dart` reads it; a test's fake handle puts whatever it
  /// likes here and nothing off-device ever looks.
  final Object backend;

  final int width;
  final int height;
  final TextureFormat format;
  final int sampleCount;

  /// `deviceTransient` is tile memory: it cannot be sampled, so a transient
  /// texture may be an attachment and may never be bound. Carried here so the
  /// engine can say that at its own call site rather than finding out inside
  /// the backend.
  final StorageMode storageMode;

  /// What shape this is: a plain 2D image, or six faces sampled by direction.
  ///
  /// Here and **not** on `RenderTargetDescriptor`, which is deliberate. That spec is
  /// the key of the render target pool's map, and two textures with equal specs
  /// are by definition interchangeable — so a cube that matched a 2D target on
  /// every other field would be lent out in its place, and nothing about the
  /// resulting picture would say why. Cubes are created directly and never come
  /// from the pool.
  final TextureType type;

  /// How many faces this texture has: six for a cube, one otherwise.
  int get sliceCount => type == TextureType.textureCube ? 6 : 1;

  /// What this texture holds, in bytes: every level of [mipLevelCount],
  /// every layer of [depthOrArrayLayers], every sample.
  ///
  /// **What the texels need, never what a driver allocates.** A device pads
  /// rows, aligns levels and keeps tiles of its own, and none of the
  /// backends says by how much, so this is the floor a budget is set
  /// against. A compressed format is counted in its blocks, a level smaller
  /// than one block as one block. [TextureFormat.unknown] counts nothing.
  int get estimatedBytes {
    final layers = depthOrArrayLayers < 1 ? 1 : depthOrArrayLayers;
    final levels = mipLevelCount < 1 ? 1 : mipLevelCount;
    final compressed = format.isCompressed ? format.blockLayout : null;
    final perTexel = format.bytesPerTexel;
    int levelBytes(int level) {
      final w = width >> level < 1 ? 1 : width >> level;
      final h = height >> level < 1 ? 1 : height >> level;
      return switch (compressed) {
        final TextureBlockLayout block =>
          ((w + block.blockWidth - 1) ~/ block.blockWidth) *
              ((h + block.blockHeight - 1) ~/ block.blockHeight) *
              block.bytesPerBlock,
        null => w * h * perTexel,
      };
    }

    return Iterable<int>.generate(
          levels,
          levelBytes,
        ).fold(0, (int sum, int bytes) => sum + bytes) *
        layers *
        (sampleCount < 1 ? 1 : sampleCount);
  }

  @override
  String toString() =>
      'TextureHandle(${width}x$height, ${format.name}, '
      'x$sampleCount, ${storageMode.name})';
}

/// A [TextureHandle] over a backend's own [backend] texture — for a backend's
/// implementation of `GraphicsDevice`, from `package:flutter3d_hardware/
/// backend.dart`. Application code never makes a handle; a device hands one
/// out. [owner] is the device whose `releaseTexture` the handle's `dispose`
/// calls.
TextureHandle wrapTexture({
  required Object backend,
  required int width,
  required int height,
  required TextureFormat format,
  int sampleCount = 1,
  StorageMode storageMode = StorageMode.devicePrivate,
  TextureType type = TextureType.texture2D,
  TextureDimension? dimension,
  int? depthOrArrayLayers,
  int mipLevelCount = 1,
  TextureUsage usage = TextureUsage.standard,
  TextureAllocator? owner,
}) => TextureHandle._(
  owner?.releaseTexture,
  backend: backend,
  width: width,
  height: height,
  format: format,
  sampleCount: sampleCount,
  storageMode: storageMode,
  type: type,
  dimension: dimension,
  depthOrArrayLayers: depthOrArrayLayers,
  mipLevelCount: mipLevelCount,
  usage: usage,
);
