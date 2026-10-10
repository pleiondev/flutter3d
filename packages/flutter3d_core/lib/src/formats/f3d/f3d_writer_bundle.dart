/// Writes what makes a `.f3d` a whole asset: lights, cameras and the nodes
/// that carry them, each material's lighting model, material language
/// programs, prefab documents and files carried whole.
///
/// **A part of `f3d_writer.dart`, not a file of its own**, for the reason the
/// other parts give: every writer here calls the string and blob helpers
/// declared on `F3dWriter`.
part of 'f3d_writer.dart';

extension _F3dWriteBundle on F3dWriter {
  (Uint8List, int) _writeLights() {
    final lights = document.lights;
    final table = Uint8List(lights.length * F3dRecord.light);
    final view = ByteData.view(table.buffer);
    for (var i = 0; i < lights.length; i++) {
      final light = lights[i];
      final o = i * F3dRecord.light;
      final (nameOffset, nameLength) = _string(light.name);
      // The type by an explicit number, never the enum's index: a value
      // added or reordered later must not change what a file says.
      view
        ..setUint32(o, switch (light.type) {
          ModelLightType.directional => 0,
          ModelLightType.point => 1,
          ModelLightType.spot => 2,
        }, Endian.little)
        ..setFloat32(o + 4, light.color.r, Endian.little)
        ..setFloat32(o + 8, light.color.g, Endian.little)
        ..setFloat32(o + 12, light.color.b, Endian.little)
        ..setFloat32(o + 16, light.intensity, Endian.little)
        ..setFloat32(o + 20, light.range ?? 0.0, Endian.little)
        ..setFloat32(o + 24, light.innerConeAngle, Endian.little)
        ..setFloat32(o + 28, light.outerConeAngle, Endian.little)
        ..setUint32(o + 32, nameOffset, Endian.little)
        ..setUint32(o + 36, nameLength, Endian.little)
        ..setUint32(o + 40, light.range == null ? 0 : 1, Endian.little);
    }
    return (table, lights.length);
  }

  (Uint8List, int) _writeCameras() {
    final cameras = document.cameras;
    final table = Uint8List(cameras.length * F3dRecord.camera);
    final view = ByteData.view(table.buffer);
    for (var i = 0; i < cameras.length; i++) {
      final camera = cameras[i];
      final o = i * F3dRecord.camera;
      final (nameOffset, nameLength) = _string(camera.name);
      final (kind, a, b, near, far, flags) = switch (camera.projection) {
        ModelPerspectiveCamera(
          :final yfov,
          :final aspectRatio,
          :final znear,
          :final zfar,
        ) =>
          (
            0,
            yfov,
            aspectRatio ?? 0.0,
            znear,
            zfar ?? 0.0,
            (aspectRatio == null ? 0 : 1) | (zfar == null ? 0 : 2),
          ),
        ModelOrthographicCamera(
          :final xmag,
          :final ymag,
          :final znear,
          :final zfar,
        ) =>
          (1, xmag, ymag, znear, zfar, 3),
      };
      view
        ..setUint32(o, kind, Endian.little)
        ..setFloat32(o + 4, a, Endian.little)
        ..setFloat32(o + 8, b, Endian.little)
        ..setFloat32(o + 12, near, Endian.little)
        ..setFloat32(o + 16, far, Endian.little)
        ..setUint32(o + 20, flags, Endian.little)
        ..setUint32(o + 24, nameOffset, Endian.little)
        ..setUint32(o + 28, nameLength, Endian.little);
    }
    return (table, cameras.length);
  }

  (Uint8List, int) _writeNodeAttachments() {
    final nodes = document.nodes;
    final carrying = <int>[
      for (var i = 0; i < nodes.length; i++)
        if (nodes[i].lightIndex != null || nodes[i].cameraIndex != null) i,
    ];
    final table = Uint8List(carrying.length * F3dRecord.nodeAttachment);
    final view = ByteData.view(table.buffer);
    for (final (r, node) in carrying.indexed) {
      final o = r * F3dRecord.nodeAttachment;
      view
        ..setUint32(o, node, Endian.little)
        ..setInt32(o + 4, nodes[node].lightIndex ?? -1, Endian.little)
        ..setInt32(o + 8, nodes[node].cameraIndex ?? -1, Endian.little);
    }
    return (table, carrying.length);
  }

  (Uint8List, int) _writeMaterialLighting() {
    final materials = document.materials;
    final lit = <int>[
      for (var i = 0; i < materials.length; i++)
        if (materials[i].lightingModel != null) i,
    ];
    final table = Uint8List(lit.length * F3dRecord.materialLighting);
    final view = ByteData.view(table.buffer);
    for (final (r, material) in lit.indexed) {
      final o = r * F3dRecord.materialLighting;
      final (offset, length) = _string(
        jsonEncode(writeLightingJson(materials[material].lightingModel!)),
      );
      view
        ..setUint32(o, material, Endian.little)
        ..setUint32(o + 4, offset, Endian.little)
        ..setUint32(o + 8, length, Endian.little);
    }
    return (table, lit.length);
  }

  /// [texts] as name and text pairs in the strings section, in its order.
  (Uint8List, int) _writeNamedTexts(Map<String, String> texts) {
    final table = Uint8List(texts.length * F3dRecord.namedText);
    final view = ByteData.view(table.buffer);
    for (final (i, MapEntry(:key, :value)) in texts.entries.indexed) {
      final o = i * F3dRecord.namedText;
      final (nameOffset, nameLength) = _string(key);
      final (textOffset, textLength) = _string(value);
      view
        ..setUint32(o, nameOffset, Endian.little)
        ..setUint32(o + 4, nameLength, Endian.little)
        ..setUint32(o + 8, textOffset, Endian.little)
        ..setUint32(o + 12, textLength, Endian.little);
    }
    return (table, texts.length);
  }

  (Uint8List, int) _writePrograms() => _writeNamedTexts(programs);

  (Uint8List, int) _writePrefabs() => _writeNamedTexts(<String, String>{
    for (final MapEntry(:key, :value) in prefabs.entries)
      key: jsonEncode(value),
  });

  (Uint8List, int) _writeFiles() {
    final table = Uint8List(files.length * F3dRecord.file);
    final view = ByteData.view(table.buffer);
    for (final (i, MapEntry(:key, :value)) in files.entries.indexed) {
      final o = i * F3dRecord.file;
      final (pathOffset, pathLength) = _string(key);
      view
        ..setUint32(o, pathOffset, Endian.little)
        ..setUint32(o + 4, pathLength, Endian.little)
        ..setUint32(o + 8, _blobAppend(value), Endian.little)
        ..setUint32(o + 12, value.lengthInBytes, Endian.little);
    }
    return (table, files.length);
  }
}
