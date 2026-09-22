/// The project's material table, uploaded.
///
/// **A pool beside the scene rather than a material on each node, for the same
/// reason the table is on the project rather than on the object.** Nine bolts
/// painted one steel are nine nodes pointing at one [Material]; darkening the
/// steel rebuilds one material and re-uploads nothing. Building a material per
/// node instead would upload the atlas nine times and make a single recolour
/// into nine rebuilds.
///
/// **Uploading is asynchronous and drawing is not, which is why this is a pool
/// and not a function.** `uploadEncodedImage` decodes a PNG, and a frame cannot
/// wait for that. So the pool is filled once — when a file is opened, and again
/// when a material changes — and `SceneSync` reads it synchronously. Between the
/// two, objects draw in clay: one frame of the wrong colour is a better answer
/// than a frame that did not happen.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' as engine show Material;
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:vector_math/vector_math.dart';

/// One built material, and the version of the project material it was built
/// from.
typedef _Built = ({engine.Material material, int version});

/// Materials a scene can draw with, built from a project's table.
final class MaterialPool {
  MaterialPool({required this.device});

  final GraphicsDevice device;

  final Map<int, _Built> _built = <int, _Built>{};

  /// Uploaded images, keyed by **the bytes' own content hash, and by whether
  /// a mip chain was asked for**. A chain is part of the texture rather than
  /// of the sampler, so two materials sampling one atlas differently must not
  /// be handed whichever answer the first of them happened to ask for.
  ///
  /// Keyed by content rather than by table index so that two different rows
  /// of `project.images` holding the same bytes — a texture imported twice,
  /// or split across two glTF images that happened to encode identically —
  /// upload once. A roughness slider dragged across a hundred materials that
  /// all point at one shared image must not decode that image a hundred
  /// times.
  final Map<(int, bool), TextureHandle?> _textures =
      <(int, bool), TextureHandle?>{};

  /// A cheap, collision-resistant-enough stand-in for the bytes themselves:
  /// two images this pool ever sees differing only where this hash agrees
  /// would need a deliberately crafted collision, not an accident.
  static int _contentHash(Uint8List bytes) =>
      Object.hash(bytes.length, Object.hashAll(bytes));

  /// What could not be decoded, in sentences, for the status line.
  final List<String> warnings = <String>[];

  /// The material for [slot], or null when nothing has been built for it.
  ///
  /// Null rather than a default, so the caller decides what an unpainted object
  /// looks like. The viewport paints it in clay; an exporter would want to know
  /// there was nothing there.
  engine.Material? operator [](int? slot) =>
      slot == null ? null : _built[slot]?.material;

  /// The texture this pool uploaded for [ModelProject.images] row [index],
  /// or null when nothing has been uploaded for it.
  ///
  /// **`pro-pt-03` asks this so a paint stroke can write into the texture
  /// already on the device.** The pool keys by the bytes' own hash, which is
  /// what makes two identical images share one upload — and also what makes
  /// a repainted image look like a different one. A caller that has just
  /// changed those bytes needs the handle from *before* the change, which is
  /// why this takes the project as it stands and hashes what is in it now.
  TextureHandle? textureForImage(ModelProject project, int index) {
    if (index < 0 || index >= project.images.length) return null;
    final int hash = _contentHash(project.images[index].bytes);
    for (final bool mips in <bool>[true, false]) {
      final TextureHandle? found = _textures[(hash, mips)];
      if (found != null) return found;
    }
    return null;
  }

  /// The material an object is drawn with, by its first slot.
  engine.Material? forObject(ModelObject object) =>
      this[object.materialSlots.isEmpty ? null : object.materialSlots.first];

  /// Brings the pool to [project]'s table, and answers how many materials it
  /// had to build.
  ///
  /// The count is what a test asserts on: it must be zero on a second call with
  /// an unchanged project, because a modeller that rebuilt its materials on
  /// every edit would decode every texture again on every drag.
  Future<int> refresh(ModelProject project) async {
    var built = 0;
    final materials = project.materials;

    Future<TextureHandle?> textureFor(
      int index,
      TextureSampling sampling,
    ) async {
      if (index < 0 || index >= project.images.length) return null;
      final bytes = project.images[index].bytes;
      final key = (_contentHash(bytes), sampling.useMipmaps);
      if (_textures.containsKey(key)) return _textures[key];

      final uploaded = await uploadEncodedImage(
        device,
        bytes,
        decodeImage: defaultImageDecoder,
        sampling: sampling,
        report: (String message) => warnings.add('image $index: $message'),
      );
      if (uploaded == null) {
        warnings.add(
          'image $index could not be read; the material falls back to its '
          'colour',
        );
      }
      _textures[key] = uploaded;
      return uploaded;
    }

    for (var slot = 0; slot < materials.length; slot++) {
      final ProjectMaterial each = materials[slot];
      if (_built[slot]?.version == each.version) continue;
      _built[slot] = (
        material: await bindSurfaceMaterial(
          each.surface,
          textureFor: textureFor,
        ),
        version: each.version,
      );
      built++;
    }

    // A table that shrank — an undone import, a deleted material — leaves rows
    // behind that no slot can name. They are dropped rather than kept, because
    // a slot number reused by a later material would otherwise be answered with
    // the old paint.
    for (final int slot in _built.keys.toList()) {
      if (slot >= materials.length) _built.remove(slot);
    }

    return built;
  }

  /// Gives back every texture this uploaded.
  ///
  /// Called when a project is closed. The materials go with it: an
  /// `engine.Material` holding a released handle is a material that samples
  /// whatever the driver put there next.
  void dispose() {
    for (final TextureHandle? handle in _textures.values) {
      if (handle != null) device.releaseTexture(handle);
    }
    _textures.clear();
    _built.clear();
  }
}

/// What an object with no material is drawn in.
///
/// The colour of unpainted clay: a shape being judged by its form rather than
/// its surface, which is what a modeller is for.
engine.Material clay() => engine.Material(
  name: 'clay',
  lighting: LightingModel.pbr,
  baseColor: Vector4(0.72, 0.70, 0.67, 1.0),
  roughness: 0.65,
);
