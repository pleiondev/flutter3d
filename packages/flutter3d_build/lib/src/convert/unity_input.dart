/// Unity's text assets: a `.prefab` or a `.unity` scene becomes a prefab
/// of a level document, a nested prefab instance an instance row with its
/// overrides, every mesh the model file it came from (found through the
/// project's `.meta` files), and every `.mat` an `.fmat`.
///
/// **Axes.** Unity is left-handed, Y up, metres; the engine is right-handed,
/// Y up, metres. Every transform is mirrored through Z — a position's z and
/// a rotation's x and y change sign — which is the same placement seen in
/// the other hand. A model Unity imported was mirrored through X on the way
/// in, and the engine's `.f3d` of the same file was not, so a model row
/// carries a half turn about Y on top: mirror through Z after mirror
/// through X is that turn.
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter3d_core/formats.dart';
import 'package:vector_math/vector_math.dart';

import 'context.dart';
import 'materials.dart';
import 'model_input.dart' show modelExtensions;
import 'output.dart';
import 'report.dart';
import 'scene.dart';
import 'unity_material.dart';
import 'unity_yaml.dart';

/// The extensions read as Unity assets.
const Set<String> unityExtensions = <String>{'.prefab', '.unity', '.mat'};

/// The GUID Unity's built-in meshes and materials live under.
const String _builtInExtra = '0000000000000000e000000000000000';

/// Converts the Unity asset [source] into [context]'s plan.
Future<void> convertUnityInput(
  String source,
  ConvertContext context,
  ConvertReport report,
) async {
  final index = UnityAssetIndex.around(source);
  report.map(
    'project ${index.root}: ${index.length} assets indexed by their .meta',
  );
  final reader = _UnityReader(context, report, index);
  if (extensionOf(source) == '.mat') {
    reader.material(source);
    return;
  }
  final id = await reader.prefab(source);
  if (id == null) return;
  final level = levelDocument(
    name: id,
    prefabs: reader.prefabs,
    materials: reader.materials.values.toList(),
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

/// Unity's frame to the engine's: a mirror through Z.
final Matrix4 _mirrorZ = Matrix4.diagonal3Values(1.0, 1.0, -1.0);

/// What a converted prefab exposes to an instance of it: its root
/// transform's file ID, and each object's row name by file ID.
final class _PrefabFacts {
  const _PrefabFacts(this.id, this.rootTransform, this.rows);

  final String id;
  final int? rootTransform;

  /// File ID of a GameObject or any of its components to the name its row
  /// has in the prefab.
  final Map<int, String> rows;
}

final class _UnityReader {
  _UnityReader(this.context, this.report, this.index);

  final ConvertContext context;
  final ConvertReport report;
  final UnityAssetIndex index;

  final List<ScenePrefab> prefabs = <ScenePrefab>[];
  final Map<String, SceneMaterial> materials = <String, SceneMaterial>{};
  final Map<String, _PrefabFacts> _converted = <String, _PrefabFacts>{};
  final Set<String> _reading = <String>{};

  /// The `.mat` at [path], planned once; its level id.
  String? material(String path) {
    final key = File(path).absolute.path;
    final known = materials[key];
    if (known != null) return known.id;
    final source = readUnityMaterial(path, index, report);
    if (source == null) return null;
    final id = _uniqueMaterialId(source.id);
    final planned = planMaterial(
      MaterialSource(id, source.surface, images: source.images),
      context.plan,
      owner: report.input,
      report: report,
    );
    materials[key] = planned;
    return planned.id;
  }

  String _uniqueMaterialId(String base) {
    final taken = materials.values.map((SceneMaterial m) => m.id).toSet();
    if (!taken.contains(base)) return base;
    for (var n = 2; ; n++) {
      if (!taken.contains('$base-$n')) return '$base-$n';
    }
  }

  /// The `.prefab` or `.unity` at [path] as a prefab; its id.
  Future<String?> prefab(String path) async => (await _prefab(path))?.id;

  Future<_PrefabFacts?> _prefab(String path) async {
    final key = File(path).absolute.path;
    final known = _converted[key];
    if (known != null) return known;
    if (_reading.contains(key)) {
      report.drop('prefab $path', 'it contains itself');
      return null;
    }
    _reading.add(key);
    try {
      final Map<int, UnityObject> objects;
      try {
        objects = parseUnityYaml(File(path).readAsStringSync());
      } on Object catch (error) {
        report.fail('could not read $path: $error');
        return null;
      }
      final id = _uniqueId(safeFileName(stemOf(path)));
      final slot = prefabs.length;
      prefabs.add(ScenePrefab(id, const <SceneItem>[]));
      final scene = _Scene(this, objects, path);
      final roots = await scene.roots();
      prefabs[slot] = ScenePrefab(id, roots);
      scene.reportSkipped(id);
      final facts = _PrefabFacts(id, scene.rootTransform, scene.rowNames);
      _converted[key] = facts;
      return facts;
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
}

/// One file's objects, turned into scene items.
final class _Scene {
  _Scene(this.reader, this.objects, this.path);

  final _UnityReader reader;
  final Map<int, UnityObject> objects;
  final String path;

  ConvertReport get report => reader.report;

  /// The root transform, for a `.prefab`.
  int? rootTransform;

  /// Row names by the file ID of a GameObject or any of its components.
  final Map<int, String> rowNames = <int, String>{};
  final Map<String, int> _names = <String, int>{};
  final Map<String, int> _skipped = <String, int>{};

  void _skip(String what) => _skipped[what] = (_skipped[what] ?? 0) + 1;

  void reportSkipped(String id) {
    for (final MapEntry(:key, :value) in _skipped.entries) {
      report.drop('$id: $value $key', switch (key) {
        'lights' => 'lights are not converted; place level lights for them',
        'cameras' => 'cameras are not converted',
        'scripts' => 'MonoBehaviours are behaviour, not content',
        'skinned meshes' =>
          'drawn as their model at rest; skinning comes with the model\'s own '
              'skin, not the renderer\'s bones',
        'inactive objects' => 'they are not drawn in Unity either',
        _ => 'not converted',
      });
    }
  }

  String _uniqueName(String name) {
    final seen = _names[name] ?? 0;
    _names[name] = seen + 1;
    return seen == 0 ? name : '$name.$seen';
  }

  Future<List<SceneItem>> roots() async {
    final items = <SceneItem>[];
    final transforms = objects.values.where(_isTransform).toList();
    for (final transform in transforms) {
      if (transform.stripped) continue;
      final father = unityRef(transform['m_Father'])?.fileId ?? 0;
      if (father != 0) continue;
      if (path.endsWith('.prefab')) rootTransform ??= transform.fileId;
      final item = await _transformItem(transform);
      if (item != null) items.add(item);
    }
    for (final instance in objects.values.where(
      (UnityObject o) => o.classId == UnityClass.prefabInstance,
    )) {
      final modification = instance['m_Modification'];
      final parent = modification is Map
          ? unityRef(modification['m_TransformParent'])?.fileId ?? 0
          : 0;
      if (parent != 0) continue;
      final item = await _instanceItem(instance);
      if (item != null) items.add(item);
    }
    return items;
  }

  static bool _isTransform(UnityObject o) =>
      o.classId == UnityClass.transform ||
      o.classId == UnityClass.rectTransform;

  /// [transform]'s local matrix, in the engine's frame.
  static Matrix4 _local(Map<String, Object?> fields) {
    final p = fields['m_LocalPosition'];
    final r = fields['m_LocalRotation'];
    final s = fields['m_LocalScale'];
    final position = p is Map
        ? Vector3(_n(p['x'], 0), _n(p['y'], 0), _n(p['z'], 0))
        : Vector3.zero();
    final rotation = r is Map
        ? Quaternion(_n(r['x'], 0), _n(r['y'], 0), _n(r['z'], 0), _n(r['w'], 1))
        : Quaternion.identity();
    final scale = s is Map
        ? Vector3(_n(s['x'], 1), _n(s['y'], 1), _n(s['z'], 1))
        : Vector3.all(1.0);
    final unity = Matrix4.compose(position, rotation.normalized(), scale);
    return _mirrorZ.multiplied(unity)..multiply(_mirrorZ);
  }

  static double _n(Object? v, double fallback) =>
      v is num ? v.toDouble() : fallback;

  Future<SceneItem?> _transformItem(UnityObject transform) async {
    final gameObjectRef = unityRef(transform['m_GameObject']);
    final gameObject = objects[gameObjectRef?.fileId];
    final name = '${gameObject?['m_Name'] ?? 'GameObject'}';
    if (gameObject != null && gameObject['m_IsActive'] == 0) {
      _skip('inactive objects');
      return null;
    }
    final rowName = _uniqueName(safeFileName(name));
    final components = <UnityObject>[
      if (gameObject?['m_Component'] case final List<Object?> list)
        for (final entry in list)
          if (entry is Map)
            if (objects[unityRef(entry['component'])?.fileId]
                case final UnityObject c)
              c,
    ];
    rowNames[transform.fileId] = rowName;
    if (gameObject != null) rowNames[gameObject.fileId] = rowName;
    for (final c in components) {
      rowNames[c.fileId] = rowName;
    }

    final children = <SceneItem>[];
    final drawn = await _drawnBy(components, rowName);
    if (drawn != null) children.add(drawn);
    for (final c in components) {
      switch (c.classId) {
        case UnityClass.light:
          _skip('lights');
        case UnityClass.camera:
          _skip('cameras');
        case UnityClass.monoBehaviour:
          _skip('scripts');
      }
    }
    if (transform['m_Children'] case final List<Object?> list) {
      for (final entry in list) {
        final child = objects[unityRef(entry)?.fileId];
        if (child == null) continue;
        if (child.stripped) {
          final item = await _strippedChild(child);
          if (item != null) children.add(item);
          continue;
        }
        final item = await _transformItem(child);
        if (item != null) children.add(item);
      }
    }
    // Instances whose parent is this transform and that the children list
    // does not name (Unity 2018.3 on writes them only on the instance).
    for (final instance in objects.values.where(
      (UnityObject o) => o.classId == UnityClass.prefabInstance,
    )) {
      final modification = instance['m_Modification'];
      final parent = modification is Map
          ? unityRef(modification['m_TransformParent'])?.fileId
          : null;
      if (parent != transform.fileId) continue;
      final already =
          (transform['m_Children'] is List) &&
          (transform['m_Children']! as List).any((Object? e) {
            final child = objects[unityRef(e)?.fileId];
            return child != null &&
                child.stripped &&
                unityRef(child['m_PrefabInstance'])?.fileId == instance.fileId;
          });
      if (already) continue;
      final item = await _instanceItem(instance);
      if (item != null) children.add(item);
    }
    return SceneItem(
      name: rowName,
      local: _local(transform.fields),
      children: children,
    );
  }

  /// A stripped transform under one of ours: the root of a prefab instance,
  /// or an inner transform of one that this file hung objects on.
  Future<SceneItem?> _strippedChild(UnityObject stripped) async {
    final instance = objects[unityRef(stripped['m_PrefabInstance'])?.fileId];
    if (instance == null) return null;
    return _instanceItem(instance);
  }

  /// What a GameObject's components draw: a model row (with its half turn,
  /// see the library comment) or a primitive.
  Future<SceneItem?> _drawnBy(
    List<UnityObject> components,
    String rowName,
  ) async {
    final filter = components
        .where((UnityObject c) => c.classId == UnityClass.meshFilter)
        .firstOrNull;
    final skinned = components
        .where((UnityObject c) => c.classId == UnityClass.skinnedMeshRenderer)
        .firstOrNull;
    final renderer = components
        .where((UnityObject c) => c.classId == UnityClass.meshRenderer)
        .firstOrNull;
    final meshRef = unityRef((filter ?? skinned)?['m_Mesh']);
    if (meshRef == null || meshRef.fileId == 0) return null;
    if (skinned != null) _skip('skinned meshes');
    if ((renderer ?? skinned)?['m_Enabled'] == 0) return null;
    final materialIds = <String?>[
      if ((renderer ?? skinned)?['m_Materials'] case final List<Object?> list)
        for (final m in list) _materialId(unityRef(m)),
    ];

    if (meshRef.guid == _builtInExtra) {
      final shape = _builtInShape(meshRef.fileId, rowName);
      if (shape == null) return null;
      return SceneItem(
        name: rowName,
        shape: shape,
        properties: <String, Object?>{
          if (materialIds.firstOrNull case final String m) 'material': m,
        },
      );
    }
    final asset = reader.index.path(meshRef.guid);
    if (asset == null) {
      report.drop(
        '$rowName\'s mesh',
        'its model (guid ${meshRef.guid}) has no .meta in the project',
      );
      return null;
    }
    if (!modelExtensions.contains(extensionOf(asset))) {
      report.drop(
        '$rowName\'s mesh',
        '${extensionOf(asset)} (${_relative(asset)}) is not a model format '
            'this converts',
      );
      return null;
    }
    final model = await _meshModel(asset, meshRef.fileId, rowName);
    if (model == null) return null;
    final import = reader.index.modelImport(asset);
    return SceneItem(
      name: rowName,
      local:
          Matrix4.rotationY(math.pi) *
          Matrix4.diagonal3Values(import.scale, import.scale, import.scale),
      asset: model,
      materials: materialIds.any((String? m) => m != null)
          ? materialIds
          : const <String?>[],
    );
  }

  /// The `.f3d` for mesh [fileId] of [asset]: the whole model when the
  /// file holds one mesh or the name is unknown, and only that mesh's
  /// surfaces otherwise.
  Future<String?> _meshModel(String asset, int fileId, String rowName) async {
    final whole = await reader.context.modelFile(asset, report);
    if (whole == null) return null;
    final (wholePath, document) = whole;
    final meshName = reader.index.modelImport(asset).meshes[fileId];
    final meshNames = <String>{
      for (final s in document.surfaces) s.meshName ?? s.name ?? '',
    };
    if (meshNames.length <= 1 || meshName == null) {
      if (meshNames.length > 1) {
        report.warn(
          '$rowName names mesh $fileId of ${_relative(asset)}, which the '
          '.meta does not name; the whole model is drawn',
        );
      }
      return wholePath;
    }
    final picked = <int>[
      for (var i = 0; i < document.surfaces.length; i++)
        if ((document.surfaces[i].meshName ?? document.surfaces[i].name) ==
            meshName)
          i,
    ];
    if (picked.isEmpty) {
      report.warn(
        '$rowName names mesh "$meshName" of ${_relative(asset)}, which the '
        'model does not hold by that name; the whole model is drawn',
      );
      return wholePath;
    }
    final relative =
        '${OutputLayout.models}/${safeFileName(stemOf(asset))}_${safeFileName(meshName)}.f3d';
    try {
      return await reader.context.planModel(
        subsetDocument(document, picked),
        relative,
        report,
      );
    } on Object catch (error) {
      report.drop('$rowName\'s mesh "$meshName"', 'it did not convert: $error');
      return null;
    }
  }

  String _relative(String asset) => asset.startsWith('${reader.index.root}/')
      ? asset.substring(reader.index.root.length + 1)
      : asset;

  PrimitiveShape? _builtInShape(int fileId, String rowName) {
    switch (fileId) {
      case 10202:
        return PrimitiveShape.box(Vector3.all(1.0));
      case 10207:
        return const PrimitiveShape.sphere(0.5);
      case 10206:
        return const PrimitiveShape.cylinder(0.5, 2.0);
      case 10208:
        report.warn('$rowName: Unity\'s capsule is drawn as a cylinder');
        return const PrimitiveShape.cylinder(0.5, 2.0);
      case 10209:
        report.warn('$rowName: Unity\'s plane is drawn as a thin box');
        return PrimitiveShape.box(Vector3(10.0, 0.01, 10.0));
      case 10210:
        report.warn('$rowName: Unity\'s quad is drawn as a thin box');
        return PrimitiveShape.box(Vector3(1.0, 1.0, 0.01));
      default:
        report.drop('$rowName\'s mesh', 'built-in mesh $fileId is not known');
        return null;
    }
  }

  String? _materialId(UnityRef? ref) {
    if (ref == null || ref.fileId == 0) return null;
    if (ref.guid == '0000000000000000f000000000000000') return null;
    final asset = reader.index.path(ref.guid);
    if (asset == null) {
      report.drop('material ${ref.guid}', 'it has no .meta in the project');
      return null;
    }
    if (extensionOf(asset) != '.mat') {
      report.drop(
        'material ${_relative(asset)}',
        'a material inside a model file stays the model\'s own',
      );
      return null;
    }
    return reader.material(asset);
  }

  /// A prefab instance: an instance row of its source when the source is a
  /// `.prefab`, a model row when it is a model file.
  Future<SceneItem?> _instanceItem(UnityObject instance) async {
    final sourceRef = unityRef(instance['m_SourcePrefab']);
    final source = reader.index.path(sourceRef?.guid);
    final modification = instance['m_Modification'];
    final modifications = <Map<Object?, Object?>>[
      if (modification is Map)
        if (modification['m_Modifications'] case final List<Object?> list)
          for (final m in list)
            if (m is Map) m,
    ];
    if (source == null) {
      report.drop(
        'prefab instance ${instance.fileId}',
        'its source (guid ${sourceRef?.guid}) has no .meta in the project',
      );
      return null;
    }
    if (modification is Map) {
      for (final key in const <String>[
        'm_RemovedComponents',
        'm_RemovedGameObjects',
        'm_AddedGameObjects',
        'm_AddedComponents',
      ]) {
        if (modification[key] case final List<Object?> list
            when list.isNotEmpty) {
          report.drop(
            'prefab instance of ${_relative(source)}: $key',
            'structural changes to an instance are not converted',
          );
        }
      }
    }

    final extension = extensionOf(source);
    _PrefabFacts? facts;
    String? model;
    if (extension == '.prefab') {
      facts = await reader._prefab(source);
      if (facts == null) return null;
    } else if (modelExtensions.contains(extension)) {
      model = (await reader.context.modelFile(source, report))?.$1;
      if (model == null) return null;
    } else {
      report.drop(
        'prefab instance of ${_relative(source)}',
        'not a prefab or a model',
      );
      return null;
    }

    // The root transform's own modifications place the instance; Unity
    // writes every one of them for the root. For a model, whose transforms
    // this cannot read, the root is the target with the most of them.
    final rootTarget =
        facts?.rootTransform ?? _busiestTransformTarget(modifications);
    final placement = <String, Object?>{};
    var name = stemOf(source);
    final overrides = <String, Map<String, Object?>>{};
    for (final m in modifications) {
      final target = unityRef(m['target'])?.fileId;
      final property = '${m['propertyPath']}';
      final value = m['value'];
      if (property == 'm_Name' && value != null) {
        name = '$value';
        continue;
      }
      if (target == rootTarget &&
          (property.startsWith('m_LocalPosition.') ||
              property.startsWith('m_LocalRotation.') ||
              property.startsWith('m_LocalScale.'))) {
        final dot = property.indexOf('.');
        final field = property.substring(0, dot);
        final axis = property.substring(dot + 1);
        (placement[field] ??= <String, Object?>{}) as Map<String, Object?>;
        (placement[field]! as Map<String, Object?>)[axis] = value is num
            ? value.toDouble()
            : double.tryParse('$value');
        continue;
      }
      if (const <String>{
        'm_RootOrder',
        'm_LocalEulerAnglesHint.x',
        'm_LocalEulerAnglesHint.y',
        'm_LocalEulerAnglesHint.z',
      }.contains(property)) {
        continue;
      }
      final row = facts?.rows[target];
      final materialSlot = RegExp(
        r'^m_Materials\.Array\.data\[(\d+)\]$',
      ).firstMatch(property);
      if (row != null && materialSlot != null) {
        final id = _materialId(unityRef(m['objectReference']));
        if (id != null) {
          final slot = int.parse(materialSlot.group(1)!);
          final keys = overrides.putIfAbsent(row, () => <String, Object?>{});
          final list = <String?>[...?(keys['materials'] as List<String?>?)];
          while (list.length <= slot) {
            list.add(null);
          }
          list[slot] = id;
          keys['materials'] = list;
          continue;
        }
      }
      report.drop(
        'override $property${row == null ? '' : ' on "$row"'} of an instance '
        'of ${_relative(source)}',
        row == null
            ? 'it addresses an object the converted prefab has no row for'
            : 'a level overrides a row\'s own keys, and this one has no '
                  'counterpart',
      );
    }

    final rowName = _uniqueName(safeFileName(name));
    rowNames[instance.fileId] = rowName;
    final local = _local(placement);
    if (model != null) {
      final import = reader.index.modelImport(source);
      return SceneItem(
        name: '$rowName.group',
        local: local,
        children: <SceneItem>[
          SceneItem(
            name: rowName,
            local:
                Matrix4.rotationY(math.pi) *
                Matrix4.diagonal3Values(
                  import.scale,
                  import.scale,
                  import.scale,
                ),
            asset: model,
          ),
        ],
      );
    }
    report.map(
      'prefab instance "$rowName" of ${_relative(source)}'
      '${overrides.isEmpty ? '' : ' with ${overrides.length} overridden rows'}',
    );
    return SceneItem(
      name: rowName,
      local: local,
      instance: NestedInstance(facts!.id, overrides: overrides),
    );
  }

  static int? _busiestTransformTarget(
    List<Map<Object?, Object?>> modifications,
  ) {
    final counts = <int, int>{};
    for (final m in modifications) {
      final property = '${m['propertyPath']}';
      if (!property.startsWith('m_Local')) continue;
      final target = unityRef(m['target'])?.fileId;
      if (target != null) counts[target] = (counts[target] ?? 0) + 1;
    }
    if (counts.isEmpty) return null;
    return (counts.entries.toList()..sort(
          (a, b) => b.value != a.value
              ? b.value.compareTo(a.value)
              : a.key.compareTo(b.key),
        ))
        .first
        .key;
  }
}

/// [document] cut down to [surfaces], with only the materials and images
/// they use, each surface placed at its own origin: the one mesh of a model
/// file a Unity `MeshFilter` names.
ModelDocument subsetDocument(ModelDocument document, List<int> surfaces) {
  final materialOrder = <int>[];
  final kept = <ModelSurface>[];
  for (final index in surfaces) {
    final surface = document.surfaces[index];
    final material = surface.materialIndex;
    int? remapped;
    if (material != null) {
      var at = materialOrder.indexOf(material);
      if (at < 0) {
        materialOrder.add(material);
        at = materialOrder.length - 1;
      }
      remapped = at;
    }
    kept.add(
      ModelSurface(
        mesh: surface.mesh,
        materialIndex: remapped,
        name: surface.name,
        meshName: surface.meshName,
        authoredAttributes: surface.authoredAttributes,
        flipWinding: surface.flipWinding,
      ),
    );
  }
  final sources = <MaterialSource>[
    for (final m in materialOrder)
      ...materialsOfDocument(
        PlainModelDocument(
          materials: <SurfaceMaterial>[document.materials[m]],
          images: document.images,
        ),
        'subset',
      ),
  ];
  final images = <EncodedImage>[];
  final materials = <SurfaceMaterial>[];
  for (final source in sources) {
    final offset = images.length;
    for (final image in source.images) {
      images.add(
        EncodedImage(
          bytes: image.bytes,
          name: image.name,
          mimeType: mimeTypeOf(image.name),
          sourceUri: image.name,
        ),
      );
    }
    materials.add(
      copySurface(
        shiftSurfaceImages(source.surface, offset),
        name: source.surface.name,
      ),
    );
  }
  return PlainModelDocument(
    surfaces: kept,
    materials: <SurfaceMaterial>[
      for (var i = 0; i < materials.length; i++)
        copySurface(
          materials[i],
          name: document.materials[materialOrder[i]].name,
        ),
    ],
    images: images,
    nodes: <ModelNode>[
      ModelNode(
        name: kept.first.meshName ?? kept.first.name,
        surfaces: <int>[for (var i = 0; i < kept.length; i++) i],
      ),
    ],
    warnings: document.warnings,
  );
}
