import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import '../../geometry/geometry.dart';
import '../asset_resolver.dart';
import '../model_document.dart';
import 'obj_document.dart';

/// How to fill in normals that the file does not provide.
enum ObjNormals {
  /// Average the face normals meeting at each vertex, weighted by face area.
  ///
  /// The default, and the right one for OBJ: unlike glTF, the format prescribes
  /// nothing here, real-world files routinely omit `vn`, and the geometry they
  /// omit it for is usually curved. Flat shading on a teapot looks broken.
  smooth,

  /// One normal per face, which requires splitting shared vertices.
  flat,

  /// Leave normals at zero.
  none,
}

/// Decodes Wavefront OBJ, optionally with its `.mtl` material libraries.
///
/// Like the glTF layer, this depends on neither flutter_gpu, `dart:io` nor
/// `dart:ui`: sibling files arrive through an [AssetUriResolver].
///
/// OBJ is a text format with no version and plenty of dialects, so the parser is
/// permissive by design — unknown directives are recorded as warnings and
/// skipped rather than treated as errors.
final class ObjLoader {
  ObjLoader({
    this.layout = VertexLayout.positionNormalTexcoord,
    this.normals = ObjNormals.smooth,
    this.splitByGroup = true,
    this.flipTexcoordV = true,
  });

  final VertexLayout layout;

  /// What to do when the file has no `vn` records.
  final ObjNormals normals;

  /// Whether `g`, `o` and `usemtl` start a new surface.
  ///
  /// On by default so a multi-material file yields one draw per material. Turn it
  /// off to merge everything into a single mesh.
  final bool splitByGroup;

  /// OBJ texture space has its origin at the bottom left, while our sampling and
  /// glTF both put it at the top left, so V is flipped by default. This is the
  /// single most common cause of upside-down textures on OBJ imports.
  final bool flipTexcoordV;

  Future<ObjDocument> load(
    Uint8List bytes, {
    AssetUriResolver? resolveUri,
  }) async {
    final warnings = <String>[];
    final text = utf8.decode(bytes, allowMalformed: true);

    final positions = <double>[];
    final texcoords = <double>[];
    final normalData = <double>[];

    final builders = <_SurfaceBuilder>[];
    var current = _SurfaceBuilder(name: null, materialName: null);
    builders.add(current);

    final materialLibraries = <String>[];
    final unknownDirectives = <String>{};

    for (final rawLine in _logicalLines(text)) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;

      final tokens = line.split(RegExp(r'\s+'));
      final keyword = tokens.first;
      final args = tokens.sublist(1);

      switch (keyword) {
        case 'v':
          // A fourth component is a rational weight, used only by free-form
          // surfaces; ignoring it is what every polygon importer does.
          if (args.length < 3) {
            warnings.add('Vertex with ${args.length} components skipped.');
            continue;
          }
          positions
            ..add(_toDouble(args[0]))
            ..add(_toDouble(args[1]))
            ..add(_toDouble(args[2]));

        case 'vt':
          final u = args.isNotEmpty ? _toDouble(args[0]) : 0.0;
          final v = args.length > 1 ? _toDouble(args[1]) : 0.0;
          texcoords
            ..add(u)
            ..add(flipTexcoordV ? 1.0 - v : v);

        case 'vn':
          if (args.length < 3) continue;
          normalData
            ..add(_toDouble(args[0]))
            ..add(_toDouble(args[1]))
            ..add(_toDouble(args[2]));

        case 'f':
          _addFace(args, current, positions, texcoords, normalData, warnings);

        case 'g':
        case 'o':
          if (!splitByGroup) continue;
          final name = args.isEmpty ? null : args.join(' ');
          current = _startSurface(
            builders,
            current,
            name: name,
            materialName: current.materialName,
          );

        case 'usemtl':
          final name = args.isEmpty ? null : args.join(' ');
          if (!splitByGroup) {
            current.materialName ??= name;
            continue;
          }
          current = _startSurface(
            builders,
            current,
            name: current.name,
            materialName: name,
          );

        case 'mtllib':
          materialLibraries.addAll(args);

        case 's':
        case 'vp':
        case 'l':
        case 'p':
          // Smoothing groups, parameter-space vertices, lines and points: valid
          // OBJ that produces no triangles here.
          break;

        default:
          unknownDirectives.add(keyword);
      }
    }

    if (unknownDirectives.isNotEmpty) {
      warnings.add(
        'Ignored unsupported directives: ${unknownDirectives.join(', ')}.',
      );
    }

    final raw = await _loadMaterialLibraries(
      materialLibraries,
      resolveUri,
      warnings,
    );

    // Convert to the shared material abstraction, resolving `map_Kd` into an
    // image index so consumers never see a filesystem path.
    final images = <EncodedImage>[];
    final materialNames = <String>[];
    final materials = <SurfaceMaterial>[];
    final indexByName = <String, int>{};

    for (final entry in raw.entries) {
      indexByName[entry.key] = materials.length;
      materialNames.add(entry.key);
      materials.add(
        await _toSurfaceMaterial(entry.value, images, resolveUri, warnings),
      );
    }

    final surfaces = <ModelSurface>[];
    for (final builder in builders) {
      if (builder.isEmpty) continue;
      final name = builder.materialName;
      surfaces.add(
        ModelSurface(
          mesh: builder.build(
            layout: layout,
            positions: positions,
            texcoords: texcoords,
            normalData: normalData,
            normalMode: normals,
          ),
          name: builder.name,
          materialIndex: name == null ? null : indexByName[name],
        ),
      );
      if (name != null && !indexByName.containsKey(name)) {
        warnings.add('usemtl "$name" was never defined in a material library.');
      }
    }

    if (surfaces.isEmpty) {
      warnings.add('The file contained no triangles.');
    }

    return ObjDocument(
      surfaces: surfaces,
      materials: materials,
      materialNames: materialNames,
      images: images,
      warnings: warnings,
    );
  }

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

  _SurfaceBuilder _startSurface(
    List<_SurfaceBuilder> builders,
    _SurfaceBuilder current, {
    String? name,
    String? materialName,
  }) {
    // Reuse the current builder while it is still empty, so a file that declares
    // `g` and `usemtl` back to back does not produce an empty surface between
    // them.
    if (current.isEmpty) {
      return current
        ..name = name
        ..materialName = materialName;
    }
    final next = _SurfaceBuilder(name: name, materialName: materialName);
    builders.add(next);
    return next;
  }

  /// Parses one `f` record, fanning polygons into triangles.
  void _addFace(
    List<String> args,
    _SurfaceBuilder surface,
    List<double> positions,
    List<double> texcoords,
    List<double> normalData,
    List<String> warnings,
  ) {
    if (args.length < 3) {
      warnings.add('Face with ${args.length} vertices skipped.');
      return;
    }

    final corners = <_Corner>[];
    for (final token in args) {
      final corner = _parseCorner(
        token,
        positionCount: positions.length ~/ 3,
        texcoordCount: texcoords.length ~/ 2,
        normalCount: normalData.length ~/ 3,
      );
      if (corner == null) {
        warnings.add('Malformed face vertex "$token" skipped.');
        return;
      }
      corners.add(corner);
    }

    // Fan from the first corner. OBJ polygons are expected to be planar and
    // convex, which is what makes a fan sufficient.
    for (var i = 1; i + 1 < corners.length; i++) {
      surface.addTriangle(corners[0], corners[i], corners[i + 1]);
    }
  }

  /// Parses `v`, `v/vt`, `v//vn` or `v/vt/vn`, resolving 1-based and negative
  /// indices to 0-based ones.
  _Corner? _parseCorner(
    String token, {
    required int positionCount,
    required int texcoordCount,
    required int normalCount,
  }) {
    final parts = token.split('/');
    final position = _resolveIndex(parts[0], positionCount);
    if (position == null) return null;

    int? texcoord;
    if (parts.length > 1 && parts[1].isNotEmpty) {
      texcoord = _resolveIndex(parts[1], texcoordCount);
    }
    int? normal;
    if (parts.length > 2 && parts[2].isNotEmpty) {
      normal = _resolveIndex(parts[2], normalCount);
    }

    return _Corner(position, texcoord, normal);
  }

  /// OBJ indices are 1-based; a negative index counts back from the most recent
  /// element, which is how streamed files reference vertices they just declared.
  int? _resolveIndex(String text, int count) {
    final value = int.tryParse(text);
    if (value == null || value == 0) return null;
    final index = value > 0 ? value - 1 : count + value;
    if (index < 0 || index >= count) return null;
    return index;
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

/// Splits text into lines, joining those continued with a trailing backslash.
Iterable<String> _logicalLines(String text) {
  final result = <String>[];
  final buffer = StringBuffer();

  for (final raw in text.split('\n')) {
    final line = raw.endsWith('\r') ? raw.substring(0, raw.length - 1) : raw;
    if (line.endsWith(r'\')) {
      buffer.write(line.substring(0, line.length - 1));
      buffer.write(' ');
      continue;
    }
    buffer.write(line);
    result.add(buffer.toString());
    buffer.clear();
  }
  if (buffer.isNotEmpty) result.add(buffer.toString());

  return result;
}

double _toDouble(String text) => double.tryParse(text) ?? 0.0;

Vector3? _toVector3(List<String> args) {
  if (args.length < 3) return null;
  return Vector3(
    _toDouble(args[0]),
    _toDouble(args[1]),
    _toDouble(args[2]),
  );
}

/// One face corner: indices into the position, texcoord and normal streams.
///
/// OBJ indexes each attribute independently, so a renderable vertex is a unique
/// combination of the three. That is why decoding needs a dedup map rather than a
/// straight copy.
final class _Corner {
  const _Corner(this.position, this.texcoord, this.normal);

  final int position;
  final int? texcoord;
  final int? normal;
}

/// Accumulates the triangles of one surface and turns them into a [MeshData].
final class _SurfaceBuilder {
  _SurfaceBuilder({this.name, this.materialName});

  String? name;
  String? materialName;

  final List<_Corner> _corners = <_Corner>[];

  bool get isEmpty => _corners.isEmpty;

  void addTriangle(_Corner a, _Corner b, _Corner c) {
    _corners
      ..add(a)
      ..add(b)
      ..add(c);
  }

  MeshData build({
    required VertexLayout layout,
    required List<double> positions,
    required List<double> texcoords,
    required List<double> normalData,
    required ObjNormals normalMode,
  }) {
    final hasFileNormals = normalData.isNotEmpty &&
        _corners.any((corner) => corner.normal != null);
    // Flat shading needs one normal per face, so vertices cannot be shared.
    final split = !hasFileNormals && normalMode == ObjNormals.flat;

    final builder = MeshBuilder(
      layout,
      reserveVertices: split ? _corners.length : _corners.length ~/ 2,
      reserveIndices: _corners.length,
    );

    final position = Vector3.zero();
    final normal = Vector3.zero();
    final texcoord = Vector2.zero();

    void writeVertex(_Corner corner) {
      final p = corner.position * 3;
      position.setValues(positions[p], positions[p + 1], positions[p + 2]);

      final t = corner.texcoord;
      if (t != null && t * 2 + 1 < texcoords.length) {
        texcoord.setValues(texcoords[t * 2], texcoords[t * 2 + 1]);
      } else {
        texcoord.setZero();
      }

      final n = corner.normal;
      if (n != null && n * 3 + 2 < normalData.length) {
        normal.setValues(
          normalData[n * 3],
          normalData[n * 3 + 1],
          normalData[n * 3 + 2],
        );
      } else {
        normal.setZero();
      }
    }

    if (split) {
      final a = Vector3.zero();
      final b = Vector3.zero();
      final c = Vector3.zero();
      final faceNormal = Vector3.zero();

      for (var i = 0; i + 2 < _corners.length; i += 3) {
        _readPosition(positions, _corners[i].position, a);
        _readPosition(positions, _corners[i + 1].position, b);
        _readPosition(positions, _corners[i + 2].position, c);
        (b - a).crossInto(c - a, faceNormal);
        if (faceNormal.length2 > 0.0) faceNormal.normalize();

        final base = builder.vertexCount;
        for (var k = 0; k < 3; k++) {
          writeVertex(_corners[i + k]);
          normal.setFrom(faceNormal);
          builder.addVertex(
            position: position,
            normal: normal,
            texcoord: texcoord,
          );
        }
        builder.addTriangle(base, base + 1, base + 2);
      }

      return builder.build();
    }

    // Deduplicate by the (position, texcoord, normal) triple, which is the unit
    // OBJ actually addresses.
    final lookup = <int, int>{};
    final indices = <int>[];

    for (final corner in _corners) {
      final key = _cornerKey(corner);
      var index = lookup[key];
      if (index == null) {
        writeVertex(corner);
        index = builder.addVertex(
          position: position,
          normal: normal,
          texcoord: texcoord,
        );
        lookup[key] = index;
      }
      indices.add(index);
    }

    for (var i = 0; i + 2 < indices.length; i += 3) {
      builder.addTriangle(indices[i], indices[i + 1], indices[i + 2]);
    }

    final mesh = builder.build();
    if (!hasFileNormals && normalMode == ObjNormals.smooth) {
      _accumulateSmoothNormals(mesh);
    }
    return mesh;
  }

  static void _readPosition(List<double> positions, int index, Vector3 out) {
    final o = index * 3;
    out.setValues(positions[o], positions[o + 1], positions[o + 2]);
  }

  /// Packs the three indices into one int for the dedup map.
  ///
  /// 21 bits each covers two million of each attribute, far past anything an OBJ
  /// file carries; beyond that the key is still unique per position, so the worst
  /// case is extra shared vertices, never wrong geometry.
  static int _cornerKey(_Corner corner) {
    final t = (corner.texcoord ?? 0) & 0x1FFFFF;
    final n = (corner.normal ?? 0) & 0x1FFFFF;
    return (corner.position & 0x1FFFFF) | (t << 21) | (n << 42);
  }

  /// Area-weighted vertex normals, computed in place.
  ///
  /// Unnormalized cross products are accumulated, so each face contributes in
  /// proportion to its area — the standard approach, and the reason a large
  /// smooth face is not outvoted by a cluster of slivers next to it.
  static void _accumulateSmoothNormals(MeshData mesh) {
    final stride = mesh.layout.floatsPerVertex;
    final normalOffset = mesh.layout.floatOffsetOf(VertexLayout.normal.name);
    if (normalOffset < 0) return;

    for (var o = normalOffset; o < mesh.vertices.length; o += stride) {
      mesh.vertices[o] = 0.0;
      mesh.vertices[o + 1] = 0.0;
      mesh.vertices[o + 2] = 0.0;
    }

    final a = Vector3.zero();
    final b = Vector3.zero();
    final c = Vector3.zero();
    final faceNormal = Vector3.zero();

    for (var i = 0; i + 2 < mesh.indices.length; i += 3) {
      final i0 = mesh.indices[i];
      final i1 = mesh.indices[i + 1];
      final i2 = mesh.indices[i + 2];
      mesh.positionAt(i0, a);
      mesh.positionAt(i1, b);
      mesh.positionAt(i2, c);
      (b - a).crossInto(c - a, faceNormal);

      for (final index in <int>[i0, i1, i2]) {
        final o = index * stride + normalOffset;
        mesh.vertices[o] += faceNormal.x;
        mesh.vertices[o + 1] += faceNormal.y;
        mesh.vertices[o + 2] += faceNormal.z;
      }
    }

    for (var o = normalOffset; o < mesh.vertices.length; o += stride) {
      final x = mesh.vertices[o];
      final y = mesh.vertices[o + 1];
      final z = mesh.vertices[o + 2];
      final length = math.sqrt(x * x + y * y + z * z);
      if (length <= 0.0) continue;
      mesh.vertices[o] = x / length;
      mesh.vertices[o + 1] = y / length;
      mesh.vertices[o + 2] = z / length;
    }
  }
}
