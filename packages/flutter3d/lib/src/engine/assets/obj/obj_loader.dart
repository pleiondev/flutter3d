import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import '../../geometry/geometry.dart';
import '../asset_resolver.dart';
import '../model_document.dart';
import 'obj_document.dart';

// The per-line dispatch below is the top of the decode pipeline. Building
// mesh data from the corners it parses, and loading `.mtl` material
// libraries, are each their own file, but every phase shares the private text
// helpers at the bottom of this file, so they are `part`s of this library
// rather than files that import it — see each part's doc comment for why.
part 'obj_loader_materials.dart';
part 'obj_surface_builder.dart';

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
/// Like the glTF layer, this depends on neither a graphics backend, `dart:io` nor
/// `dart:ui`: sibling files arrive through an [AssetUriResolver].
///
/// OBJ is a text format with no version and plenty of dialects, so the parser is
/// permissive by design — unknown directives are recorded as warnings and
/// skipped rather than treated as errors. That holds for the `.mtl` half too:
/// see [parseMtl], which reports its own once each.
final class ObjLoader {
  ObjLoader({
    this.layout = VertexLayout.standard,
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
