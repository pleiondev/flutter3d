/// A texture the engine can hold, pass around and describe without naming a
/// backend.
///
/// **Nothing in `graphics/` may import `flutter_gpu`** —
/// `test/graphics_is_backend_free_test.dart` enforces it. See
/// `graphics/formats.dart` for why the directory exists.
library;

import 'formats.dart';

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
  TextureHandle({
    required this.backend,
    required this.width,
    required this.height,
    required this.format,
    this.sampleCount = 1,
    this.storageMode = StorageMode.devicePrivate,
    this.type = TextureType.texture2D,
  });

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
  /// Here and **not** on `RenderTargetSpec`, which is deliberate. That spec is
  /// the key of the render target pool's map, and two textures with equal specs
  /// are by definition interchangeable — so a cube that matched a 2D target on
  /// every other field would be lent out in its place, and nothing about the
  /// resulting picture would say why. Cubes are created directly and never come
  /// from the pool.
  final TextureType type;

  /// How many faces this texture has: six for a cube, one otherwise.
  int get sliceCount => type == TextureType.textureCube ? 6 : 1;

  @override
  String toString() => 'TextureHandle(${width}x$height, ${format.name}, '
      'x$sampleCount, ${storageMode.name})';
}
