/// Godot's text scenes and resources: a `.tscn` becomes a prefab of a level
/// document — a `MeshInstance3D` a model or primitive row, an instanced
/// scene a nested prefab — and a `StandardMaterial3D` or `ORMMaterial3D`,
/// in a `.tres` or inside a scene, an `.fmat`.
///
/// Godot's frame is the engine's — right-handed, Y up, metres — so nothing
/// is mirrored or scaled on the way.
library;

import 'dart:io';

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:vector_math/vector_math.dart';

import 'context.dart';
import 'godot_text.dart';
import 'materials.dart';
import 'model_input.dart' show modelExtensions;
import 'output.dart';
import 'report.dart';
import 'scene.dart';
import 'texture_files.dart';

/// The extensions read as Godot text.
const Set<String> godotExtensions = <String>{'.tscn', '.tres'};

/// Converts the Godot file [source] into [context]'s plan.
Future<void> convertGodotInput(
  String source,
  ConvertContext context,
  ConvertReport report,
) async {
  final reader = _GodotReader(context, report, _projectRoot(source));
  if (extensionOf(source) == '.tres') {
    reader.resourceFile(source);
    return;
  }
  final id = await reader.scene(source);
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

/// The directory `res://` names: the nearest one above [file] holding a
/// `project.godot`, or [file]'s own.
String _projectRoot(String file) {
  final start = File(file).absolute.parent;
  for (var at = start; at.parent.path != at.path; at = at.parent) {
    if (File('${at.path}/project.godot').existsSync()) return at.path;
  }
  return start.path;
}

/// A resource a file declares: its type, and its path or properties.
final class _Resource {
  const _Resource(this.type, {this.path, this.properties = const {}});

  final String type;
  final String? path;
  final Map<String, Object?> properties;
}

/// One file's resources, by id.
final class _Resources {
  _Resources(this.external, this.internal);

  final Map<String, _Resource> external;
  final Map<String, _Resource> internal;

  _Resource? resolve(Object? value) {
    if (value is! GodotCall || value.arguments.isEmpty) return null;
    final id = switch (value.arguments.first) {
      final String s => s,
      final double d => '${d.toInt()}',
      _ => null,
    };
    return switch (value.name) {
      'ExtResource' => external[id],
      'SubResource' => internal[id],
      _ => null,
    };
  }
}

final class _GodotReader {
  _GodotReader(this.context, this.report, this.root);

  final ConvertContext context;
  final ConvertReport report;
  final String root;

  final List<ScenePrefab> prefabs = <ScenePrefab>[];
  final Map<String, SceneMaterial> materials = <String, SceneMaterial>{};
  final Map<String, String> _scenes = <String, String>{};
  final Set<String> _reading = <String>{};
  final Map<String, int> _skipped = <String, int>{};

  String file(String resPath) =>
      resPath.startsWith('res://') ? '$root/${resPath.substring(6)}' : resPath;

  String _relative(String path) =>
      path.startsWith('$root/') ? path.substring(root.length + 1) : path;

  void _skip(String what) => _skipped[what] = (_skipped[what] ?? 0) + 1;

  (List<GodotSection>, _Resources)? _read(String path) {
    final List<GodotSection> sections;
    try {
      sections = parseGodotText(File(path).readAsStringSync());
    } on Object catch (error) {
      report.fail('could not read $path: $error');
      return null;
    }
    final external = <String, _Resource>{};
    final internal = <String, _Resource>{};
    for (final section in sections) {
      final id = section.text('id');
      if (id == null) continue;
      final type = section.text('type') ?? '';
      if (section.kind == 'ext_resource') {
        external[id] = _Resource(type, path: section.text('path'));
      } else if (section.kind == 'sub_resource') {
        internal[id] = _Resource(type, properties: section.properties);
      }
    }
    return (sections, _Resources(external, internal));
  }

  /// A `.tres`: a material written as `.fmat`; anything else reported.
  void resourceFile(String path) {
    final read = _read(path);
    if (read == null) return;
    final (sections, resources) = read;
    final header = sections.where((s) => s.kind == 'gd_resource').firstOrNull;
    final body = sections.where((s) => s.kind == 'resource').firstOrNull;
    final type = header?.text('type') ?? '';
    if (body == null || !_isMaterial(type)) {
      report.fail('$type is not a material this converts');
      return;
    }
    _material(
      File(path).absolute.path,
      _Resource(type, properties: body.properties),
      resources,
      safeFileName(stemOf(path)),
    );
  }

  static bool _isMaterial(String type) => const <String>{
    'StandardMaterial3D',
    'ORMMaterial3D',
    'SpatialMaterial',
  }.contains(type);

  /// A scene as a prefab; its id.
  Future<String?> scene(String path) async {
    final key = File(path).absolute.path;
    final known = _scenes[key];
    if (known != null) return known;
    if (_reading.contains(key)) {
      report.drop('scene $path', 'it instances itself');
      return null;
    }
    _reading.add(key);
    try {
      final read = _read(path);
      if (read == null) return null;
      final (sections, resources) = read;
      final id = _uniqueId(safeFileName(stemOf(path)));
      final slot = prefabs.length;
      prefabs.add(ScenePrefab(id, const <SceneItem>[]));
      final roots = await _nodes(sections, resources, id);
      prefabs[slot] = ScenePrefab(id, roots);
      for (final MapEntry(:key, :value) in _skipped.entries) {
        report.drop('$id: $value $key', _skipReason(key));
      }
      _skipped.clear();
      _scenes[key] = id;
      return id;
    } finally {
      _reading.remove(key);
    }
  }

  static String _skipReason(String what) => switch (what) {
    'lights' => 'lights are not converted; place level lights for them',
    'cameras' => 'cameras are not converted',
    'hidden nodes' => 'they are not drawn',
    'CSG nodes' => 'constructive geometry is not evaluated; bake it to a mesh',
    'particles' => 'particles are not converted; write them as .f3dfx',
    'mesh resources' =>
      'ArrayMesh data inside a scene is not read; save the mesh as glTF',
    _ => 'not converted',
  };

  String _uniqueId(String base) {
    final taken = prefabs.map((ScenePrefab p) => p.id).toSet();
    if (!taken.contains(base)) return base;
    for (var n = 2; ; n++) {
      if (!taken.contains('$base-$n')) return '$base-$n';
    }
  }

  Future<List<SceneItem>> _nodes(
    List<GodotSection> sections,
    _Resources resources,
    String prefabId,
  ) async {
    final names = <String, int>{};
    String unique(String name) {
      final seen = names[name] ?? 0;
      names[name] = seen + 1;
      return seen == 0 ? name : '$name.$seen';
    }

    // Path in the scene ("." for the root, "A/B") to the item made for it,
    // and to the row name inside an instanced scene for editable children.
    final items = <String, SceneItem>{};
    final instances = <String, (SceneItem, String)>{};
    final roots = <SceneItem>[];
    for (final section in sections.where((s) => s.kind == 'node')) {
      final name = section.text('name') ?? 'Node';
      final parent = section.text('parent');
      final path = parent == null
          ? '.'
          : (parent == '.' ? name : '$parent/$name');
      final props = section.properties;

      // A node under an instanced scene that has no type of its own changes
      // a node of that scene: an override.
      final instanceAbove = parent == null
          ? null
          : instances.entries
                .where((e) => parent == e.key || parent.startsWith('${e.key}/'))
                .lastOrNull;
      if (instanceAbove != null &&
          section.attributes['type'] == null &&
          section.attributes['instance'] == null) {
        _override(instanceAbove.value.$1, name, props, resources);
        continue;
      }

      if (props['visible'] == false) {
        _skip('hidden nodes');
        continue;
      }
      final item = await _node(section, unique(safeFileName(name)), resources);
      if (item == null) continue;
      if (item.instance != null) instances[path] = (item, path);
      items[path] = item;
      if (parent == null) {
        roots.add(item);
      } else {
        final above = items[parent];
        if (above == null) {
          report.drop('node $path', 'its parent "$parent" was not converted');
        } else {
          above.children.add(item);
        }
      }
    }
    return roots;
  }

  /// [props] set on node [name] of the scene [instance] places.
  void _override(
    SceneItem instance,
    String name,
    Map<String, Object?> props,
    _Resources resources,
  ) {
    final nested = instance.instance!;
    for (final MapEntry(:key, :value) in props.entries) {
      final slot = RegExp(r'^surface_material_override/(\d+)$').firstMatch(key);
      if (slot != null || key == 'material_override') {
        final id = _materialFor(value, resources);
        if (id != null) {
          final keys = nested.overrides.putIfAbsent(
            name,
            () => <String, Object?>{},
          );
          final list = <String?>[...?(keys['materials'] as List<String?>?)];
          final at = slot == null ? 0 : int.parse(slot.group(1)!);
          while (list.length <= at) {
            list.add(null);
          }
          list[at] = id;
          keys['materials'] = list;
          continue;
        }
      }
      report.drop(
        'override $key on "$name" of an instance of ${nested.prefab}',
        'a level overrides a row\'s own keys, and this one has no counterpart',
      );
    }
  }

  Future<SceneItem?> _node(
    GodotSection section,
    String rowName,
    _Resources resources,
  ) async {
    final type = section.text('type') ?? '';
    final props = section.properties;
    final local = _transform(props);

    final instanced = resources.resolve(section.attributes['instance']);
    if (instanced != null) {
      final path = file(instanced.path ?? '');
      final extension = extensionOf(path);
      if (extension == '.tscn') {
        final nested = await scene(path);
        if (nested == null) return null;
        report.map('instanced scene "$rowName" -> prefab "$nested"');
        return SceneItem(
          name: rowName,
          local: local,
          instance: NestedInstance(
            nested,
            overrides: <String, Map<String, Object?>>{},
          ),
        );
      }
      if (modelExtensions.contains(extension)) {
        final model = (await context.modelFile(path, report))?.$1;
        if (model == null) return null;
        return SceneItem(name: rowName, local: local, asset: model);
      }
      report.drop(
        'instance "$rowName"',
        '${_relative(path)} is not a scene or a model',
      );
      return null;
    }

    switch (type) {
      case 'MeshInstance3D' || 'MeshInstance':
        return _meshInstance(rowName, local, props, resources);
      case 'OmniLight3D' ||
          'SpotLight3D' ||
          'DirectionalLight3D' ||
          'OmniLight' ||
          'SpotLight' ||
          'DirectionalLight':
        _skip('lights');
      case 'Camera3D' || 'Camera':
        _skip('cameras');
      case 'GPUParticles3D' ||
          'CPUParticles3D' ||
          'Particles' ||
          'CPUParticles':
        _skip('particles');
      case final String t when t.startsWith('CSG'):
        _skip('CSG nodes');
    }
    // Everything else — Node3D, bodies, collision shapes — is a group: its
    // transform carries its children.
    return SceneItem(name: rowName, local: local);
  }

  static Matrix4 _transform(Map<String, Object?> props) {
    final transform = props['transform'];
    if (transform is GodotCall &&
        (transform.name == 'Transform3D' || transform.name == 'Transform')) {
      final n = transform.numbers;
      if (n.length >= 12) {
        // The basis written row by row, then the origin.
        return Matrix4(
          n[0],
          n[3],
          n[6],
          0.0, //
          n[1],
          n[4],
          n[7],
          0.0, //
          n[2],
          n[5],
          n[8],
          0.0, //
          n[9],
          n[10],
          n[11],
          1.0,
        );
      }
    }
    Vector3 vector(String key, double fallback) => switch (props[key]) {
      final GodotCall c when c.numbers.length >= 3 => Vector3(
        c.numbers[0],
        c.numbers[1],
        c.numbers[2],
      ),
      _ => Vector3.all(fallback),
    };
    final position = vector('position', 0.0);
    final scale = vector('scale', 1.0);
    final rotation = switch (props['quaternion']) {
      final GodotCall c when c.numbers.length >= 4 => Quaternion(
        c.numbers[0],
        c.numbers[1],
        c.numbers[2],
        c.numbers[3],
      ),
      _ => () {
        // Godot's default rotation order is YXZ: Y applied last.
        final e = vector('rotation', 0.0);
        return Quaternion.axisAngle(Vector3(0, 1, 0), e.y) *
            Quaternion.axisAngle(Vector3(1, 0, 0), e.x) *
            Quaternion.axisAngle(Vector3(0, 0, 1), e.z);
      }(),
    };
    return Matrix4.compose(position, rotation, scale);
  }

  Future<SceneItem?> _meshInstance(
    String rowName,
    Matrix4 local,
    Map<String, Object?> props,
    _Resources resources,
  ) async {
    final mesh = resources.resolve(props['mesh']);
    if (mesh == null) return SceneItem(name: rowName, local: local);
    final slots = <String?>[
      _materialFor(props['material_override'], resources) ??
          _materialFor(props['surface_material_override/0'], resources) ??
          _materialFor(mesh.properties['material'], resources),
    ];
    for (var i = 1; props.containsKey('surface_material_override/$i'); i++) {
      slots.add(_materialFor(props['surface_material_override/$i'], resources));
    }
    if (mesh.path case final String path) {
      final source = file(path);
      if (!modelExtensions.contains(extensionOf(source))) {
        _skip('mesh resources');
        return SceneItem(name: rowName, local: local);
      }
      final model = (await context.modelFile(source, report))?.$1;
      if (model == null) return null;
      return SceneItem(
        name: rowName,
        local: local,
        asset: model,
        materials: slots.any((String? s) => s != null)
            ? slots
            : const <String?>[],
      );
    }
    final shape = _primitive(mesh, rowName);
    if (shape == null) {
      _skip('mesh resources');
      return SceneItem(name: rowName, local: local);
    }
    return SceneItem(
      name: rowName,
      local: local,
      shape: shape,
      properties: <String, Object?>{
        if (slots.first case final String m) 'material': m,
      },
    );
  }

  PrimitiveShape? _primitive(_Resource mesh, String rowName) {
    double number(String key, double fallback) =>
        switch (mesh.properties[key]) {
          final double d => d,
          _ => fallback,
        };
    Vector3 size(Vector3 fallback) => switch (mesh.properties['size']) {
      final GodotCall c when c.numbers.length >= 3 => Vector3(
        c.numbers[0],
        c.numbers[1],
        c.numbers[2],
      ),
      final GodotCall c when c.numbers.length == 2 => Vector3(
        c.numbers[0],
        0.01,
        c.numbers[1],
      ),
      _ => fallback,
    };
    switch (mesh.type) {
      case 'BoxMesh' || 'CubeMesh':
        return PrimitiveShape.box(size(Vector3.all(1.0)));
      case 'SphereMesh':
        return PrimitiveShape.sphere(number('radius', 0.5));
      case 'CylinderMesh':
        final top = number('top_radius', 0.5);
        final bottom = number('bottom_radius', 0.5);
        if (top != bottom) {
          report.warn(
            '$rowName: a tapered cylinder is drawn with its mean radius',
          );
        }
        return PrimitiveShape.cylinder(
          (top + bottom) / 2,
          number('height', 2.0),
        );
      case 'CapsuleMesh':
        report.warn('$rowName: a capsule is drawn as a cylinder');
        return PrimitiveShape.cylinder(
          number('radius', 0.5),
          number('height', 2.0),
        );
      case 'PlaneMesh':
        report.warn('$rowName: a plane is drawn as a thin box');
        return PrimitiveShape.box(size(Vector3(2.0, 0.01, 2.0)));
      case 'QuadMesh':
        report.warn('$rowName: a quad is drawn as a thin box');
        final s = size(Vector3(1.0, 0.01, 1.0));
        return PrimitiveShape.box(Vector3(s.x, s.z, 0.01));
      default:
        return null;
    }
  }

  /// The level material [value] names, planned the first time.
  String? _materialFor(Object? value, _Resources resources) {
    final resource = resources.resolve(value);
    if (resource == null) return null;
    if (resource.path case final String path) {
      final source = file(path);
      final key = File(source).absolute.path;
      if (materials[key] case final SceneMaterial known) return known.id;
      if (extensionOf(source) != '.tres') {
        report.drop(
          'material ${_relative(source)}',
          'only .tres materials are read',
        );
        return null;
      }
      final read = _read(source);
      if (read == null) return null;
      final (sections, inner) = read;
      final body = sections.where((s) => s.kind == 'resource').firstOrNull;
      final type =
          sections
              .where((s) => s.kind == 'gd_resource')
              .firstOrNull
              ?.text('type') ??
          '';
      if (body == null || !_isMaterial(type)) {
        report.drop('material ${_relative(source)}', '$type is not converted');
        return null;
      }
      return _material(
        key,
        _Resource(type, properties: body.properties),
        inner,
        safeFileName(stemOf(source)),
      );
    }
    if (!_isMaterial(resource.type)) {
      report.drop(
        'a ${resource.type}',
        'only StandardMaterial3D and ORMMaterial3D are converted',
      );
      return null;
    }
    final key = 'sub:${identityHashCode(resource)}';
    if (materials[key] case final SceneMaterial known) return known.id;
    final name = switch (resource.properties['resource_name']) {
      final String s when s.isNotEmpty => s,
      _ => '${prefabs.lastOrNull?.id ?? 'scene'}_material${materials.length}',
    };
    return _material(key, resource, resources, safeFileName(name));
  }

  /// Plans [material] and returns its level id.
  String? _material(
    String key,
    _Resource material,
    _Resources resources,
    String id,
  ) {
    final source = godotMaterial(id, material.type, material.properties, (
      Object? v,
    ) {
      final r = resources.resolve(v);
      final path = r?.path;
      return path == null ? null : file(path);
    }, report);
    final planned = planMaterial(
      source,
      context.plan,
      owner: report.input,
      report: report,
    );
    materials[key] = planned;
    return planned.id;
  }
}

/// A `StandardMaterial3D`, `ORMMaterial3D` or Godot 3 `SpatialMaterial` as
/// the engine's surface. [texturePath] turns a property's resource
/// reference into a file path.
MaterialSource godotMaterial(
  String id,
  String type,
  Map<String, Object?> props,
  String? Function(Object? value) texturePath,
  ConvertReport report,
) {
  double number(String key, double fallback) => switch (props[key]) {
    final double d => d,
    final bool b => b ? 1.0 : 0.0,
    _ => fallback,
  };
  bool flag(String key) => props[key] == true;
  Vector4 color(String key, Vector4 fallback) => switch (props[key]) {
    final GodotCall c when c.numbers.length >= 3 => Vector4(
      c.numbers[0],
      c.numbers[1],
      c.numbers[2],
      c.numbers.length > 3 ? c.numbers[3] : 1.0,
    ),
    _ => fallback,
  };

  final images = <MaterialImage>[];
  final loaded = <String, MaterialImage?>{};
  MaterialImage? image(String key) {
    final path = texturePath(props[key]);
    if (path == null) return null;
    return loaded.putIfAbsent(path, () => loadTextureFile(path, report));
  }

  int add(MaterialImage i) {
    final at = images.indexWhere((MaterialImage m) => m.name == i.name);
    if (at >= 0) return at;
    images.add(i);
    return images.length - 1;
  }

  final uvScale = switch (props['uv1_scale']) {
    final GodotCall c when c.numbers.length >= 2 => Vector2(
      c.numbers[0],
      c.numbers[1],
    ),
    _ => Vector2(1.0, 1.0),
  };
  final uvOffset = switch (props['uv1_offset']) {
    final GodotCall c when c.numbers.length >= 2 => Vector2(
      c.numbers[0],
      c.numbers[1],
    ),
    _ => Vector2.zero(),
  };
  final transform =
      uvScale.x == 1.0 &&
          uvScale.y == 1.0 &&
          uvOffset.x == 0.0 &&
          uvOffset.y == 0.0
      ? null
      : TextureTransform(offset: uvOffset, scale: uvScale);
  TextureBinding? bind(MaterialImage? i) => i == null
      ? null
      : TextureBinding(imageIndex: add(i), transform: transform);

  final albedo = image('albedo_texture');
  final orm = type == 'ORMMaterial3D' ? image('orm_texture') : null;

  TextureBinding? metalRough;
  TextureBinding? occlusion;
  var metallic = number('metallic', 0.0);
  var roughness = number('roughness', 1.0);
  if (orm != null) {
    metalRough = bind(orm);
    occlusion = bind(orm);
    report.map('material "$id" orm_texture -> occlusion, roughness and metal');
  } else {
    final metal = image('metallic_texture');
    final rough = image('roughness_texture');
    if (metal != null || rough != null) {
      final metalChannel = number('metallic_texture_channel', 0).toInt();
      final roughChannel = number('roughness_texture_channel', 0).toInt();
      if (metal != null &&
          rough != null &&
          metal.name == rough.name &&
          metalChannel == 2 &&
          roughChannel == 1) {
        metalRough = bind(metal);
      } else {
        final packed = packChannels(
          '${id}_mr.png',
          green: rough == null
              ? null
              : (image: rough, channel: roughChannel, invert: false),
          blue: metal == null
              ? null
              : (image: metal, channel: metalChannel, invert: false),
        );
        if (packed != null) {
          metalRough = bind(packed);
          if (rough == null) roughness = 1.0;
          if (metal == null) metallic = 1.0;
          // A missing map is white in the pack, so its factor carries it.
          report.map(
            'material "$id" metallic/roughness maps -> ${packed.name}',
          );
        } else {
          report.drop(
            'material "$id" metallic/roughness maps',
            'they could not be decoded',
          );
        }
      }
    }
    if (flag('ao_enabled')) {
      final ao = image('ao_texture');
      final channel = number('ao_texture_channel', 0).toInt();
      if (ao != null && channel == 0) {
        occlusion = bind(ao);
      } else if (ao != null) {
        final packed = packChannels(
          '${id}_ao.png',
          red: (image: ao, channel: channel, invert: false),
        );
        if (packed != null) occlusion = bind(packed);
      }
    }
  }

  final normal = flag('normal_enabled') || props.containsKey('normal_texture')
      ? image('normal_texture')
      : null;
  final emissionOn = flag('emission_enabled');
  final emission = emissionOn
      ? color('emission', Vector4(0, 0, 0, 1))
      : Vector4(0, 0, 0, 1);
  final emissionTexture = emissionOn ? image('emission_texture') : null;
  final energy = number(
    'emission_energy_multiplier',
    number('emission_energy', 1.0),
  );

  final transparency = number(
    'transparency',
    flag('flags_transparent') ? 1 : 0,
  ).toInt();
  final alphaMode = switch (transparency) {
    1 || 4 => SurfaceAlphaMode.blend,
    2 || 3 => SurfaceAlphaMode.mask,
    _ => SurfaceAlphaMode.opaque,
  };
  if (transparency == 3) {
    report.warn('material "$id": alpha hash is drawn as a cut-out');
  }
  final cull = number('cull_mode', number('params_cull_mode', 0)).toInt();
  if (cull == 1) {
    report.warn('material "$id": front-face culling is drawn as back-face');
  }
  final unlit = number('shading_mode', 1) == 0 || flag('flags_unshaded');

  for (final key in const <String>[
    'rim_enabled',
    'subsurf_scatter_enabled',
    'refraction_enabled',
    'detail_enabled',
    'heightmap_enabled',
    'backlight_enabled',
    'anisotropy_enabled',
  ]) {
    if (flag(key)) {
      report.drop(
        'material "$id" ${key.replaceAll('_enabled', '')}',
        'not converted',
      );
    }
  }

  final coat = flag('clearcoat_enabled') ? number('clearcoat', 1.0) : 0.0;
  final surface = SurfaceMaterial(
    name: id,
    baseColor: _fromSrgb(color('albedo_color', Vector4(1.0, 1.0, 1.0, 1.0))),
    baseColorTexture: bind(albedo),
    metallic: metallic,
    roughness: roughness,
    metallicRoughnessTexture: metalRough,
    occlusionTexture: occlusion,
    normalTexture: bind(normal),
    normalScale: number('normal_scale', 1.0),
    emissive: emissionTexture != null && emission.xyz.length2 == 0.0
        ? LinearColor.white
        : LinearColor(emission.x, emission.y, emission.z),
    emissiveStrength: energy,
    emissiveTexture: bind(emissionTexture),
    alphaMode: alphaMode,
    alphaCutoff: number('alpha_scissor_threshold', 0.5),
    doubleSided: cull == 2,
    unlit: unlit,
    extensions: coat > 0.0
        ? MaterialExtensions(
            clearcoat: coat,
            clearcoatRoughness: number('clearcoat_roughness', 0.5),
          )
        : null,
  );
  report.map('material "$id" ($type) -> ${unlit ? 'unlit' : 'metal-rough'}');
  return MaterialSource(id, surface, images: images);
}

/// A `Vector4` holding a colour sRGB-encoded, as the linear colour it names.
LinearColor _fromSrgb(Vector4 c) => LinearColor.fromSrgb(c.x, c.y, c.z, c.w);
