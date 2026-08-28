/// `.mtl` material libraries: loading them for an [ObjLoader], parsing their
/// text, and mapping a record onto the shared material abstraction.
///
/// **A part of `obj_loader.dart`, not a file of its own.** `_toSurfaceMaterial`
/// and `_loadMaterialLibraries` are steps of `ObjLoader.load`'s pipeline, and
/// `parseMtl` shares the private text helpers (`_logicalLines`, `_toDouble`)
/// declared in `obj_loader.dart` with that pipeline. A `part` lets the material
/// phase live in its own file without making those helpers public.
part of 'obj_loader.dart';

extension _ObjMaterials on ObjLoader {
  /// Maps a `.mtl` record onto the shared material abstraction.
  ///
  /// OBJ predates physically based shading, so this is explicitly approximate:
  /// `Kd` becomes the base colour, the Phong exponent becomes roughness, and a
  /// bright neutral `Ks` is the only hint of metalness available. Doing it here
  /// rather than in the renderer keeps one conversion in one place.
  Future<SurfaceMaterial> _toSurfaceMaterial(
    MtlMaterial source,
    List<EncodedImage> images,
    AssetUriResolver? resolveUri,
    List<String> warnings,
  ) async {
    TextureBinding? baseColorTexture;
    final path = source.diffuseTexturePath;
    if (path != null) {
      if (resolveUri == null) {
        warnings.add(
          'Material "${source.name}" needs texture "$path" but no URI resolver '
          'was supplied.',
        );
      } else {
        try {
          final bytes = await resolveUri(path);
          baseColorTexture = TextureBinding(imageIndex: images.length);
          images.add(EncodedImage(bytes: bytes, name: path));
        } catch (error) {
          warnings.add('Could not load texture "$path": $error');
        }
      }
    }

    final diffuse = source.diffuse;
    return SurfaceMaterial(
      name: source.name,
      baseColor: Vector4(
        diffuse?.x ?? 1.0,
        diffuse?.y ?? 1.0,
        diffuse?.z ?? 1.0,
        source.opacity,
      ),
      metallic: source.approximateMetallic,
      roughness: source.approximateRoughness,
      baseColorTexture: baseColorTexture,
      alphaMode: source.opacity < 1.0
          ? SurfaceAlphaMode.blend
          : SurfaceAlphaMode.opaque,
    );
  }

  Future<Map<String, MtlMaterial>> _loadMaterialLibraries(
    List<String> libraries,
    AssetUriResolver? resolveUri,
    List<String> warnings,
  ) async {
    final result = <String, MtlMaterial>{};
    if (libraries.isEmpty) return result;

    if (resolveUri == null) {
      warnings.add(
        'The file references ${libraries.join(', ')} but no URI resolver was '
        'supplied, so materials were not loaded.',
      );
      return result;
    }

    for (final library in libraries) {
      try {
        final bytes = await resolveUri(library);
        result.addAll(parseMtl(utf8.decode(bytes, allowMalformed: true)));
      } catch (error) {
        warnings.add('Could not load material library "$library": $error');
      }
    }
    return result;
  }
}

/// Parses a `.mtl` library.
///
/// Exposed separately because it is a self-contained text format, which makes it
/// testable without constructing an OBJ file around it.
Map<String, MtlMaterial> parseMtl(String text) {
  final result = <String, MtlMaterial>{};

  String? name;
  Vector3? diffuse;
  Vector3? specular;
  double? exponent;
  var opacity = 1.0;
  String? diffuseTexture;

  void flush() {
    final current = name;
    if (current == null) return;
    result[current] = MtlMaterial(
      name: current,
      diffuse: diffuse,
      specular: specular,
      specularExponent: exponent,
      opacity: opacity,
      diffuseTexturePath: diffuseTexture,
    );
  }

  for (final rawLine in _logicalLines(text)) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) continue;

    final tokens = line.split(RegExp(r'\s+'));
    final keyword = tokens.first;
    final args = tokens.sublist(1);

    switch (keyword) {
      case 'newmtl':
        flush();
        name = args.isEmpty ? '' : args.join(' ');
        diffuse = null;
        specular = null;
        exponent = null;
        opacity = 1.0;
        diffuseTexture = null;

      case 'Kd':
        diffuse = _toVector3(args);

      case 'Ks':
        specular = _toVector3(args);

      case 'Ns':
        if (args.isNotEmpty) exponent = _toDouble(args[0]);

      case 'd':
        if (args.isNotEmpty) opacity = _toDouble(args[0]);

      case 'Tr':
        // Transparency is the complement of opacity, and files use one or the
        // other.
        if (args.isNotEmpty) opacity = 1.0 - _toDouble(args[0]);

      case 'map_Kd':
        // Options such as `-s 1 1 1` may precede the filename; the path is the
        // last token that is not an option value.
        if (args.isNotEmpty) diffuseTexture = args.last;
    }
  }
  flush();

  return result;
}

Vector3? _toVector3(List<String> args) {
  if (args.length < 3) return null;
  return Vector3(_toDouble(args[0]), _toDouble(args[1]), _toDouble(args[2]));
}
