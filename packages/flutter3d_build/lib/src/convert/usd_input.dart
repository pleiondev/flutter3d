/// USD: a `.usda` layer, a `.usdz` package, or a binary layer through
/// `usdcat`. The layer's meshes become one `.f3d`, its UsdPreviewSurface
/// materials `.fmat` files, and its prims a prefab; a prim that references
/// another file becomes an instance of that file's prefab.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_core/geometry.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:vector_math/vector_math.dart';

import '../build_exceptions.dart';
import 'assembler.dart';
import 'confine.dart';
import 'context.dart';
import 'external.dart';
import 'materials.dart';
import 'output.dart';
import 'polygon_mesh.dart';
import 'report.dart';
import 'scene.dart';
import 'surface_inputs.dart';
import 'usda.dart';
import 'zip_reader.dart';

/// The extensions read as USD.
const Set<String> usdExtensions = <String>{'.usda', '.usd', '.usdc', '.usdz'};

/// Converts the USD file [source] into [context]'s plan: its own prefab,
/// every file it references as a nested one, and a level document placing
/// the first.
Future<void> convertUsdInput(
  String source,
  ConvertContext context,
  ConvertReport report,
) async {
  final reader = _UsdReader(context, report);
  final id = await reader.layerPrefab(source, primary: true);
  if (id == null) return;
  final level = levelDocument(
    name: id,
    prefabs: reader.prefabs,
    materials: reader.materials,
    prefix: context.assetPrefix,
    report: report,
  );
  final path = context.plan.addText(
    '${safeFileName(stemOf(source))}${OutputLayout.level}',
    level,
    owner: report.input,
  );
  report.written.add(path);
}

/// A layer as read, with where its relative paths resolve.
final class _Layer {
  _Layer(
    this.layer,
    this.directory,
    this.archive,
    this.archiveBase, {
    required this.root,
    required this.report,
  });

  final UsdLayer layer;
  final String directory;

  /// What a path the layer names has to stay inside: the input's directory,
  /// or the upload's (see `confine.dart`).
  final String root;

  /// Hears a path refused for leaving [root].
  final ConvertReport report;

  /// The package's entries, for a layer read out of a `.usdz`.
  final Map<String, Uint8List>? archive;

  /// The root layer's directory inside the archive.
  final String archiveBase;

  /// The bytes of [path] relative to this layer, or null.
  Uint8List? read(String path) {
    final clean = path.startsWith('./') ? path.substring(2) : path;
    final entries = archive;
    if (entries != null) {
      final inside = archiveBase.isEmpty ? clean : '$archiveBase/$clean';
      final found = entries[inside] ?? entries[clean];
      if (found != null) return found;
    }
    final resolved = resolveFile(path);
    if (resolved == null) return null;
    final file = File(resolved);
    return file.existsSync() ? file.readAsBytesSync() : null;
  }

  /// The absolute file [path] names, for a reference to another layer; null,
  /// and said in [report], when it is outside [root].
  String? resolveFile(String path) {
    final resolved = resolveInside(path, directory: directory, root: root);
    if (resolved == null) report.drop(path, outsideMessage(path, root));
    return resolved;
  }

  /// From the layer's own axes and units to the engine's: Y up, metres.
  Matrix4 get toEngine {
    final scale = layer.metersPerUnit;
    final units = Matrix4.diagonal3Values(scale, scale, scale);
    return layer.upAxis == 'Z'
        ? Matrix4.rotationX(-math.pi / 2) * units
        : units;
  }
}

final class _UsdReader {
  _UsdReader(this.context, this.report);

  final ConvertContext context;
  final ConvertReport report;

  /// Every prefab this conversion made, the input's first.
  final List<ScenePrefab> prefabs = <ScenePrefab>[];
  final List<SceneMaterial> materials = <SceneMaterial>[];

  /// Absolute layer path to its prefab id and the matrix that took it to
  /// the engine's frame.
  final Map<String, (String, Matrix4)> _layers = <String, (String, Matrix4)>{};
  final Set<String> _reading = <String>{};

  /// What every layer of this conversion reads inside: the context's root,
  /// or the input layer's directory, set when the input is read. A layer it
  /// references one directory down still reads `../wood.png` beside the
  /// input; nothing reads above it.
  late final String root;

  /// Converts the layer at [source] and returns its prefab's id, or null
  /// with the reason in [report].
  Future<String?> layerPrefab(String source, {required bool primary}) async {
    if (primary) root = context.root ?? File(source).absolute.parent.path;
    final key = File(source).absolute.path;
    final known = _layers[key];
    if (known != null) return known.$1;
    if (_reading.contains(key)) {
      report.drop('reference to $source', 'the layer references itself');
      return null;
    }
    _reading.add(key);
    try {
      final layer = await _load(source);
      if (layer == null) return null;
      final id = _uniqueId(safeFileName(stemOf(source)));
      _layers[key] = (id, layer.toEngine);
      // Reserved first so the input's prefab leads the document even though
      // its references are converted while it is read.
      final slot = prefabs.length;
      prefabs.add(ScenePrefab(id, const <SceneItem>[]));
      final roots = await _convertLayer(layer, id, primary: primary);
      prefabs[slot] = ScenePrefab(id, roots);
      return id;
    } finally {
      _reading.remove(key);
    }
  }

  String _uniqueId(String base) {
    final taken = prefabs.map((ScenePrefab p) => p.id).toSet();
    if (!taken.contains(base)) return base;
    for (var n = 2; ; n++) {
      if (!taken.contains('$base-$n')) return '$base-$n';
    }
  }

  Future<_Layer?> _load(String source) async {
    final file = File(source);
    if (!file.existsSync()) {
      report.fail('no such file: $source');
      return null;
    }
    final bytes = file.readAsBytesSync();
    final directory = file.parent.path;
    try {
      if (extensionOf(source) == '.usdz') {
        final entries = readZip(bytes);
        if (entries.isEmpty) {
          report.fail('the package is empty');
          return null;
        }
        final rootName = entries.keys.first;
        final base = directoryOf(rootName);
        final rootBytes = entries[rootName]!;
        report.map('usdz: root layer "$rootName", ${entries.length} entries');
        final layer = isUsdCrate(rootBytes)
            ? _throughUsdcat(rootBytes)
            : parseUsda(utf8.decode(rootBytes, allowMalformed: true));
        return _Layer(
          layer,
          directory,
          entries,
          base,
          root: root,
          report: report,
        );
      }
      final layer = isUsdCrate(bytes)
          ? _throughUsdcat(bytes)
          : parseUsda(utf8.decode(bytes, allowMalformed: true));
      return _Layer(layer, directory, null, '', root: root, report: report);
    } on MissingToolException catch (error) {
      report.fail(error.message, as: ConvertOutcome.missingTool);
      return null;
    } on SourceFormatException catch (error) {
      report.fail('could not read $source: ${error.message}');
      return null;
    } on FormatException catch (error) {
      // A number the token pattern let through that `double.parse` still
      // refuses.
      report.fail('could not read $source: ${error.message}');
      return null;
    }
  }

  UsdLayer _throughUsdcat(Uint8List crate) {
    if (!context.externalTools) {
      throw const MissingToolException(
        'a binary USD layer (crate) is read through usdcat, and this '
        'converter runs no external program; save the layer as .usda',
      );
    }
    final work = Directory.systemTemp.createTempSync('flutter3d_usd_');
    try {
      final input = File('${work.path}/layer.usdc')..writeAsBytesSync(crate);
      final text = usdcToUsda(input.path, work);
      report.map('binary layer -> text through usdcat');
      return parseUsda(File(text).readAsStringSync());
    } finally {
      work.deleteSync(recursive: true);
    }
  }

  Future<List<SceneItem>> _convertLayer(
    _Layer layer,
    String id, {
    required bool primary,
  }) async {
    final usd = layer.layer;
    final toEngine = layer.toEngine;
    if (usd.upAxis == 'Z') report.map('$id: upAxis Z -> Y');
    if (!usd.saysMetersPerUnit) {
      report.warn(
        '$id: the layer does not say metersPerUnit; USD\'s default, '
        'centimetres, is assumed',
      );
    } else if (usd.metersPerUnit != 1.0) {
      report.map('$id: metersPerUnit ${usd.metersPerUnit} -> metres');
    }

    final assembler = DocumentAssembler();
    final instances = <SceneItem>[];
    final skipped = <String, int>{};
    final materialKeys = <String>{};

    Future<void> walk(
      UsdPrim prim,
      Matrix4 parentWorld,
      int? parentNode,
    ) async {
      if (prim.specifier != 'def') {
        skipped['${prim.specifier} prims'] =
            (skipped['${prim.specifier} prims'] ?? 0) + 1;
        return;
      }
      if (_word(prim['visibility']) == 'invisible') {
        skipped['invisible prims'] = (skipped['invisible prims'] ?? 0) + 1;
        return;
      }
      final type = prim.typeName;
      if (const <String>{'Material', 'Shader', 'NodeGraph'}.contains(type)) {
        return;
      }
      if (_isUnsupportedType(type)) {
        skipped['$type prims'] = (skipped['$type prims'] ?? 0) + 1;
        return;
      }
      final (local, resets) = _localMatrix(prim);
      final world = resets ? local : parentWorld * local;

      // A reference to another file: that file's prefab, placed here.
      final reference = _referenceOf(prim);
      if (reference != null) {
        if (reference.path.isEmpty) {
          final target = reference.target == null
              ? null
              : usd.find(reference.target!.text);
          if (target == null) {
            report.drop(
              prim.path,
              'its internal reference resolves to nothing',
            );
          } else {
            for (final child in target.children) {
              await walk(child, world, parentNode);
            }
          }
          return;
        }
        // Refused and said by `resolveFile` when it leaves the root.
        final file = layer.resolveFile(reference.path);
        if (file == null) return;
        final nested = await layerPrefab(file, primary: false);
        if (nested == null) {
          report.drop(
            prim.path,
            'its reference ${reference.path} did not convert',
          );
          return;
        }
        // Each layer is converted in its own units and axes, which is what
        // its author meant; USD itself composes the referenced numbers
        // unscaled. The placement is this layer's, seen in the engine's
        // frame.
        final nestedToEngine = _layers[File(file).absolute.path]!.$2;
        if (!_sameFrame(nestedToEngine, toEngine)) {
          report.warn(
            '${prim.path}: ${reference.path} has other units or another up '
            'axis than this layer; each is converted in its own, where USD '
            'would compose the referenced numbers unscaled',
          );
        }
        instances.add(
          SceneItem(
            name: prim.name,
            local: toEngine.multiplied(world)
              ..multiply(Matrix4.inverted(toEngine)),
            instance: NestedInstance(nested),
          ),
        );
        if (reference.target != null) {
          report.warn(
            '${prim.path}: the reference names ${reference.target}; the whole '
            'layer is placed',
          );
        }
        if (prim.children.isNotEmpty) {
          report.drop(
            '${prim.path}\'s own children',
            'they are opinions over the referenced layer, which is placed '
                'as it is',
          );
        }
        return;
      }

      final node = assembler.node(
        prim.name,
        parentNode == null ? toEngine * local : local,
        parent: parentNode,
      );
      final engineWorld = toEngine * world;
      final mesh = _meshOf(prim, id);
      if (mesh != null) {
        final material = _bindMaterial(
          prim,
          layer,
          id,
          assembler,
          materialKeys,
        );
        assembler.surface(
          node,
          mesh.$1,
          engineWorld,
          material: material,
          name: prim.name,
          authored: mesh.$2,
        );
      }
      for (final child in prim.children) {
        await walk(child, world, node);
      }
    }

    for (final prim in usd.prims) {
      await walk(prim, Matrix4.identity(), null);
    }
    for (final MapEntry(:key, :value) in skipped.entries) {
      report.drop('$id: $value $key', _skipReason(key));
    }

    final roots = <SceneItem>[];
    if (!assembler.isEmpty) {
      final relative = primary ? '$id.f3d' : '${OutputLayout.models}/$id.f3d';
      try {
        final path = await context.planModel(
          assembler.build(),
          relative,
          report,
        );
        roots.add(SceneItem(name: id, asset: path));
      } on Object catch (error) {
        report.fail('the model of $id did not convert: $error');
      }
    }
    roots.addAll(instances);
    if (roots.isEmpty) report.warn('$id: nothing drawable in the layer');
    return roots;
  }

  static bool _sameFrame(Matrix4 a, Matrix4 b) {
    for (var i = 0; i < 16; i++) {
      if ((a.storage[i] - b.storage[i]).abs() > 1e-9) return false;
    }
    return true;
  }

  static bool _isUnsupportedType(String type) =>
      type.endsWith('Light') ||
      type == 'Camera' ||
      type.startsWith('Skel') ||
      type == 'Points' ||
      type == 'BasisCurves' ||
      type == 'NurbsCurves' ||
      type == 'NurbsPatch' ||
      type == 'PointInstancer' ||
      type == 'Volume';

  static String _skipReason(String what) => switch (what) {
    'over prims' ||
    'class prims' => 'composition is not evaluated; only def prims are read',
    'invisible prims' => 'they are not drawn',
    _ when what.contains('Light') =>
      'lights are not converted; place level lights for them',
    'Camera prims' => 'cameras are not converted',
    _ when what.startsWith('Skel') =>
      'skeletons and skinning are not read from USD; export glTF for them',
    'PointInstancer prims' => 'instancers are not expanded',
    _ => 'this prim type is not converted',
  };

  /// The prim's xformOps, in `xformOpOrder`, as one matrix, and whether it
  /// resets the stack (ignores its parents).
  (Matrix4, bool) _localMatrix(UsdPrim prim) {
    final order = prim['xformOpOrder'];
    var matrix = Matrix4.identity();
    var resets = false;
    if (order is! List) {
      if (prim.properties.keys.any((String k) => k.startsWith('xformOp:'))) {
        report.warn(
          '${prim.path}: xformOps with no xformOpOrder are not applied',
        );
      }
      return (matrix, false);
    }
    for (final entry in order) {
      var name = switch (entry) {
        final String s => s,
        final UsdWord w => w.word,
        _ => '',
      };
      if (name == '!resetXformStack!') {
        resets = true;
        matrix = Matrix4.identity();
        continue;
      }
      var invert = false;
      if (name.startsWith('!invert!')) {
        invert = true;
        name = name.substring('!invert!'.length);
      }
      final op = _op(name, prim[name], prim.path);
      matrix = matrix * (invert ? Matrix4.inverted(op) : op);
    }
    return (matrix, resets);
  }

  Matrix4 _op(String name, Object? value, String where) {
    final kind = name.split(':').length > 1 ? name.split(':')[1] : name;
    final v = _numbers(value);
    double at(int i, double fallback) => i < v.length ? v[i] : fallback;
    double rad(double degrees) => degrees * math.pi / 180.0;
    Matrix4 axis(String a, double degrees) => switch (a) {
      'X' => Matrix4.rotationX(rad(degrees)),
      'Y' => Matrix4.rotationY(rad(degrees)),
      _ => Matrix4.rotationZ(rad(degrees)),
    };
    switch (kind) {
      case 'translate':
        return Matrix4.translationValues(at(0, 0), at(1, 0), at(2, 0));
      case 'scale':
        return Matrix4.diagonal3Values(at(0, 1), at(1, 1), at(2, 1));
      case 'rotateX' || 'rotateY' || 'rotateZ':
        return axis(kind.substring(6), at(0, 0));
      case 'orient':
        // GfQuat is written real part first.
        final q = Quaternion(at(1, 0), at(2, 0), at(3, 0), at(0, 1));
        return Matrix4.compose(Vector3.zero(), q.normalized(), Vector3.all(1));
      case 'transform':
        if (v.length >= 16) return Matrix4.fromList(v.sublist(0, 16));
        return Matrix4.identity();
      default:
        if (kind.startsWith('rotate') && kind.length == 9) {
          // rotateXYZ: X first, then Y, then Z.
          final axes = kind.substring(6);
          var m = Matrix4.identity();
          for (var i = 0; i < 3; i++) {
            final angle = at('XYZ'.indexOf(axes[i]), 0);
            m = axis(axes[i], angle) * m;
          }
          return m;
        }
        report.warn('$where: the xformOp "$name" is not read');
        return Matrix4.identity();
    }
  }

  /// Every number in [value], flattened: `(1, 2, 3)`, `((1,0),(0,1))`.
  static List<double> _numbers(Object? value) => switch (value) {
    final double d => <double>[d],
    final bool b => <double>[b ? 1.0 : 0.0],
    final List<Object?> list => <double>[for (final e in list) ..._numbers(e)],
    _ => const <double>[],
  };

  static String? _word(Object? value) => switch (value) {
    final String s => s,
    final UsdWord w => w.word,
    _ => null,
  };

  UsdAsset? _referenceOf(UsdPrim prim) {
    for (final key in const <String>['references', 'payload']) {
      final value = prim.metadata[key];
      final first = value is List ? value.firstOrNull : value;
      if (value is List && value.length > 1) {
        report.warn(
          '${prim.path}: only the first of ${value.length} $key is placed',
        );
      }
      if (first is UsdAsset) return first;
      if (first is UsdPath) return UsdAsset('', target: first);
    }
    return null;
  }

  /// The prim's geometry, and which attributes the source authored.
  (MeshData, Set<String>)? _meshOf(UsdPrim prim, String id) {
    switch (prim.typeName) {
      case 'Mesh':
        return _polygonMesh(prim);
      case 'Cube':
        final size = _numbers(prim['size']).firstOrNull ?? 2.0;
        return (
          CuboidShape(size: Vector3.all(size)).build(),
          {'position', 'normal', 'texcoord'},
        );
      case 'Sphere':
        final radius = _numbers(prim['radius']).firstOrNull ?? 1.0;
        return (
          SphereShape(radius: radius).build(),
          {'position', 'normal', 'texcoord'},
        );
      case 'Cylinder' || 'Cone' || 'Capsule':
        final radius =
            _numbers(prim['radius']).firstOrNull ??
            (prim.typeName == 'Capsule' ? 0.5 : 1.0);
        final height =
            _numbers(prim['height']).firstOrNull ??
            (prim.typeName == 'Capsule' ? 1.0 : 2.0);
        final Shape shape = switch (prim.typeName) {
          'Cylinder' => CylinderShape(
            radiusTop: radius,
            radiusBottom: radius,
            height: height,
          ),
          'Cone' => ConeShape(radius: radius, height: height),
          _ => CapsuleShape(radius: radius, height: height),
        };
        if (prim.typeName == 'Capsule') {
          report.warn(
            '${prim.path}: a capsule\'s height is read as the engine\'s capsule height',
          );
        }
        final turn = switch (_word(prim['axis']) ?? 'Z') {
          'X' => Matrix4.rotationZ(-math.pi / 2),
          'Y' => Matrix4.identity(),
          _ => Matrix4.rotationX(math.pi / 2),
        };
        return (
          shape.build().transformed(turn),
          {'position', 'normal', 'texcoord'},
        );
      case '' || 'Xform' || 'Scope':
        return null;
      default:
        report.drop(prim.path, 'a ${prim.typeName} prim is not converted');
        return null;
    }
  }

  (MeshData, Set<String>)? _polygonMesh(UsdPrim prim) {
    final points = _vectors3(prim['points']);
    final counts = _numbers(
      prim['faceVertexCounts'],
    ).map((d) => d.toInt()).toList();
    final indices = _numbers(
      prim['faceVertexIndices'],
    ).map((d) => d.toInt()).toList();
    if (points.isEmpty || counts.isEmpty) {
      report.drop(prim.path, 'the mesh has no points or faces');
      return null;
    }
    if (prim.properties.containsKey('subdivisionScheme') &&
        _word(prim['subdivisionScheme']) != 'none') {
      report.warn('${prim.path}: drawn as its control cage, not subdivided');
    }
    final normalsProperty =
        prim.properties['primvars:normals'] ?? prim.properties['normals'];
    final normals = normalsProperty == null
        ? null
        : PolygonAttribute<Vector3>(
            _vectors3(normalsProperty.value),
            _rate(normalsProperty.metadata['interpolation'], prim.path),
            indices: _indices(prim, normalsProperty.name),
          );
    final uvProperty = _uvProperty(prim);
    final uvs = uvProperty == null
        ? null
        : PolygonAttribute<Vector2>(
            <Vector2>[
              for (final uv in _vectors2(uvProperty.value))
                Vector2(uv.x, 1.0 - uv.y),
            ],
            _rate(uvProperty.metadata['interpolation'], prim.path),
            indices: _indices(prim, uvProperty.name),
          );
    final colourProperty = prim.properties['primvars:displayColor'];
    final colors = colourProperty == null
        ? null
        : PolygonAttribute<Vector4>(
            <Vector4>[
              for (final c in _vectors3(colourProperty.value))
                Vector4(c.x, c.y, c.z, 1.0),
            ],
            _rate(
              colourProperty.metadata['interpolation'] ?? 'constant',
              prim.path,
            ),
            indices: _indices(prim, colourProperty.name),
          );
    try {
      final mesh = PolygonMesh(
        points: points,
        counts: counts,
        indices: indices,
        normals: normals,
        uvs: uvs,
        colors: colors,
        flipWinding: _word(prim['orientation']) == 'leftHanded',
      ).build();
      return (
        mesh,
        <String>{
          'position',
          if (normals != null) 'normal',
          if (uvs != null) 'texcoord',
          if (colors != null) 'color',
        },
      );
    } on SourceFormatException catch (error) {
      report.drop(prim.path, error.message);
      return null;
    } on FormatException catch (error) {
      report.drop(prim.path, error.message);
      return null;
    }
  }

  UsdProperty? _uvProperty(UsdPrim prim) {
    for (final name in const <String>[
      'primvars:st',
      'primvars:st0',
      'primvars:UVMap',
      'primvars:uv',
    ]) {
      final p = prim.properties[name];
      if (p != null) return p;
    }
    return prim.properties.values
        .where(
          (UsdProperty p) =>
              p.typeName.startsWith('texCoord2') &&
              !p.name.endsWith(':indices'),
        )
        .firstOrNull;
  }

  List<int>? _indices(UsdPrim prim, String name) {
    final value = prim['$name:indices'];
    if (value == null) return null;
    return _numbers(value).map((d) => d.toInt()).toList();
  }

  AttributeRate _rate(Object? interpolation, String where) =>
      switch (_word(interpolation)) {
        'vertex' || 'varying' => AttributeRate.point,
        'faceVarying' => AttributeRate.corner,
        'uniform' => AttributeRate.face,
        'constant' => AttributeRate.constant,
        null => AttributeRate.point,
        final other => () {
          report.warn('$where: interpolation "$other" read as per point');
          return AttributeRate.point;
        }(),
      };

  static List<Vector3> _vectors3(Object? value) => <Vector3>[
    if (value is List)
      for (final e in value)
        if (_numbers(e) case final n when n.length >= 3)
          Vector3(n[0], n[1], n[2]),
  ];

  static List<Vector2> _vectors2(Object? value) => <Vector2>[
    if (value is List)
      for (final e in value)
        if (_numbers(e) case final n when n.length >= 2) Vector2(n[0], n[1]),
  ];

  /// The material index [prim] wears in [assembler], planning its `.fmat`
  /// the first time it is seen.
  int? _bindMaterial(
    UsdPrim prim,
    _Layer layer,
    String id,
    DocumentAssembler assembler,
    Set<String> planned,
  ) {
    final binding = prim['material:binding'];
    final path = switch (binding) {
      final UsdPath p => p.text,
      final List<Object?> l when l.firstOrNull is UsdPath =>
        (l.first! as UsdPath).text,
      _ => null,
    };
    final twoSided = prim['doubleSided'] == true || prim['doubleSided'] == 1.0;
    if (path == null) {
      final color = _vectors3(prim['primvars:displayColor']);
      final key = color.length == 1 ? 'displayColor:${color.first}' : 'default';
      return assembler.material('$key:$twoSided', () {
        final c = color.length == 1 ? color.first : Vector3.all(0.8);
        return MaterialSource(
          '${id}_${color.length == 1 ? 'displayColor' : 'default'}',
          SurfaceMaterial(
            name: 'displayColor',
            baseColor: LinearColor.fromSrgb(
              linearToSrgb(c.x),
              linearToSrgb(c.y),
              linearToSrgb(c.z),
              1.0,
            ),
            doubleSided: twoSided,
          ),
        );
      });
    }
    final material = layer.layer.find(path);
    if (material == null) {
      report.drop('${prim.path} material $path', 'no such prim in the layer');
      return null;
    }
    final source = _materialSource(material, layer, id);
    final materialId = '${source.id}${twoSided ? '_twosided' : ''}';
    final shaped = MaterialSource(
      materialId,
      twoSided
          ? copySurface(source.surface, doubleSided: true, name: materialId)
          : source.surface,
      images: source.images,
    );
    if (planned.add(materialId) && context.writeMaterials) {
      if (!context.materials.containsKey(materialId)) {
        final planned = planMaterial(
          shaped,
          context.plan,
          owner: report.input,
          report: report,
        );
        context.materials[materialId] = planned;
      }
      materials.add(context.materials[materialId]!);
    }
    return assembler.material(materialId, () => shaped);
  }

  MaterialSource _materialSource(
    UsdPrim material,
    _Layer layer,
    String layerId,
  ) {
    final id = '${layerId}_${material.name}';
    final shader = _surfaceShader(material);
    if (shader == null) {
      report.drop('material ${material.path}', 'it has no surface shader');
      return MaterialSource(id, SurfaceMaterial(name: id));
    }
    final shaderId = _word(shader['info:id']) ?? '';
    final vocabulary = switch (shaderId) {
      'UsdPreviewSurface' => ShadingVocabulary.previewSurface,
      final String s when s.contains('standard_surface') =>
        ShadingVocabulary.standardSurface,
      _ => null,
    };
    if (vocabulary == null) {
      report.drop(
        'material ${material.path}',
        'the shader "$shaderId" is not one the engine maps; a grey surface stands in',
      );
      return MaterialSource(id, SurfaceMaterial(name: id));
    }
    final inputs = <String, InputValue>{};
    for (final property in shader.properties.values) {
      if (!property.name.startsWith('inputs:')) continue;
      var name = property.name.substring('inputs:'.length);
      final connected = name.endsWith('.connect');
      if (connected) name = name.substring(0, name.length - '.connect'.length);
      if (connected) {
        final target = property.value;
        final targetPath = switch (target) {
          final UsdPath p => p.text,
          final List<Object?> l when l.firstOrNull is UsdPath =>
            (l.first! as UsdPath).text,
          _ => null,
        };
        if (targetPath != null) inputs[name] = _upstream(targetPath, layer, 0);
      } else if (!inputs.containsKey(name) && property.value != null) {
        final numbers = _numbers(property.value);
        if (numbers.isNotEmpty) inputs[name] = ConstantInput(numbers);
      }
    }
    return surfaceFromInputs(id, inputs, vocabulary, report);
  }

  UsdPrim? _surfaceShader(UsdPrim material) {
    for (final key in const <String>[
      'outputs:surface.connect',
      'outputs:mtlx:surface.connect',
    ]) {
      final value = material[key];
      final path = switch (value) {
        final UsdPath p => p.text,
        final List<Object?> l when l.firstOrNull is UsdPath =>
          (l.first! as UsdPath).text,
        _ => null,
      };
      if (path != null) {
        final prim = material.find(path.split('.').first);
        if (prim != null) return prim;
      }
    }
    return material.children
        .where((UsdPrim c) => c.typeName == 'Shader')
        .firstOrNull;
  }

  /// What the output at [path] (`/Mat/Tex.outputs:rgb`) gives.
  InputValue _upstream(String path, _Layer layer, int depth) {
    final dot = path.indexOf('.');
    final primPath = dot < 0 ? path : path.substring(0, dot);
    final output = dot < 0
        ? ''
        : path.substring(dot + 1).replaceFirst('outputs:', '');
    final prim = layer.layer.find(primPath);
    if (prim == null || depth > 8) return const GraphInput('a missing node');
    final shaderId = _word(prim['info:id']) ?? prim.typeName;
    if (shaderId == 'UsdUVTexture' ||
        shaderId.startsWith('ND_image') ||
        shaderId.startsWith('ND_tiledimage')) {
      final file = prim['inputs:file'];
      final asset = file is UsdAsset
          ? file.path
          : (file is String ? file : null);
      if (asset == null) return const GraphInput('an image node with no file');
      final scale = _numbers(prim['inputs:scale']);
      return TextureInput(
        asset.substring(asset.lastIndexOf('/') + 1),
        layer.read(asset),
        channel: output.isEmpty || output == 'out' ? 'rgb' : output,
        scale: scale.isEmpty ? null : scale,
        wrapS: _wrap(_word(prim['inputs:wrapS'])),
        wrapT: _wrap(_word(prim['inputs:wrapT'])),
      );
    }
    // Something else: find the nearest image above it for the fallback.
    InputValue? fallback;
    for (final property in prim.properties.values) {
      if (property.name.endsWith('.connect')) {
        final target = property.value;
        if (target is UsdPath) {
          final up = _upstream(target.text, layer, depth + 1);
          if (up is TextureInput) {
            fallback = up;
            break;
          }
          if (up is GraphInput && up.fallback != null) fallback ??= up.fallback;
        }
      }
    }
    return GraphInput('a $shaderId node', fallback: fallback);
  }

  static TextureWrap _wrap(String? word) => switch (word) {
    'clamp' => TextureWrap.clampToEdge,
    'mirror' => TextureWrap.mirroredRepeat,
    _ => TextureWrap.repeat,
  };
}
