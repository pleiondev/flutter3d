/// Decodes `skins` into engine skeletons.
///
/// **A part of `gltf_loader.dart`, not a file of its own**, for the same
/// reason as the rest of this pipeline's phases: it reads the private JSON
/// helpers (`_mapList`, `_intList`, `_asInt`, ...) declared at the bottom of
/// `gltf_loader.dart`, and those stay unexported by staying in the same
/// library.
part of 'gltf_loader.dart';

extension _GltfSkins on GltfLoader {
  // -------------------------------------------------------------------- skins

  /// Joints are node indices, which is what makes skinning and animation
  /// independent: the player writes node transforms and the skin reads them, so
  /// neither feature has to know the other exists.
  List<ModelSkin> _decodeSkins(
    Map<String, Object?> json,
    GltfAccessorReader reader,
    int nodeCount,
    List<String> warnings,
  ) {
    final skins = _mapList(json['skins']);
    if (skins.isEmpty) return const <ModelSkin>[];

    final result = <ModelSkin>[];
    for (var i = 0; i < skins.length; i++) {
      final skin = skins[i];
      final label = 'skins[$i]';
      final joints = _intList(skin['joints']);

      if (joints.isEmpty) {
        warnings.add('$label has no joints; skipped.');
        continue;
      }
      final outOfRange = joints.where((j) => j < 0 || j >= nodeCount);
      if (outOfRange.isNotEmpty) {
        warnings.add(
          '$label names joints ${outOfRange.join(', ')}, which are not nodes; '
          'skipped.',
        );
        continue;
      }

      // The spec allows the matrices to be absent, meaning every one is
      // identity — a skeleton already at the origin in bind pose.
      final accessor = _asInt(skin['inverseBindMatrices']);
      final matrices = <Matrix4>[];
      if (accessor == null) {
        for (var j = 0; j < joints.length; j++) {
          matrices.add(Matrix4.identity());
        }
      } else {
        final floats = reader.readAsFloats(accessor);
        if (floats.length < joints.length * 16) {
          warnings.add(
            '$label has ${joints.length} joints but only '
            '${floats.length ~/ 16} inverse bind matrices; skipped.',
          );
          continue;
        }
        for (var j = 0; j < joints.length; j++) {
          // Column-major in the file and column-major in vector_math, so the
          // sixteen floats go straight in.
          final storage = Float32List(16);
          for (var e = 0; e < 16; e++) {
            storage[e] = floats[j * 16 + e];
          }
          matrices.add(Matrix4.fromFloat32List(storage));
        }
      }

      final skeleton = _asInt(skin['skeleton']);
      final name = skin['name'];
      result.add(
        ModelSkin(
          name: name is String ? name : null,
          joints: joints,
          inverseBindMatrices: matrices,
          skeletonRoot:
              skeleton != null && skeleton >= 0 && skeleton < nodeCount
              ? skeleton
              : null,
        ),
      );
    }
    return result;
  }
}
