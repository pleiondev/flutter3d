/// A scene as a converter reads it — a tree of placed things — and how it
/// becomes a level document with prefabs.
///
/// Every reader (glTF, USD, Unity, Godot) builds the same few types here, in
/// the engine's frame: right-handed, Y up, metres. What differs between the
/// formats is how they get there; what a level document can say is decided
/// once, below.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter3d_core/formats.dart' show SurfaceMaterial;
import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart'
    show EntityDef, EntityTypes, Level, LevelMaterial, Prefab, PrefabOverrides;
import 'package:vector_math/vector_math.dart';

import 'report.dart';

/// The entity type a level draws a converted model with:
/// `flutter3d_app`'s `ModelVisuals`, which reads the file named by `asset`.
const String kModelEntityType = 'model';

/// The entity type a level draws a primitive shape with: `flutter3d_app`'s
/// `PropVisuals` — `shape` (`box`, `sphere`, `cylinder`) and its size.
const String kPropEntityType = 'prop';

/// A primitive a source names instead of a mesh: Unity's built-in cube,
/// Godot's `BoxMesh`, a USD `Cube` prim.
final class PrimitiveShape {
  const PrimitiveShape.box(this.size)
    : shape = 'box',
      radius = null,
      height = null;

  const PrimitiveShape.sphere(double this.radius)
    : shape = 'sphere',
      size = null,
      height = null;

  const PrimitiveShape.cylinder(double this.radius, double this.height)
    : shape = 'cylinder',
      size = null;

  /// `box`, `sphere` or `cylinder`: the three `PropVisuals` draws.
  final String shape;

  /// A box's edge lengths, metres.
  final Vector3? size;

  /// A sphere's or cylinder's radius, metres.
  final double? radius;

  /// A cylinder's height, metres.
  final double? height;

  /// This shape with as much of [scale] taken into its own size as it can
  /// hold, and the scale that is left: all of it for a box, an even scale
  /// for a sphere, an even one across for a cylinder.
  (PrimitiveShape, Vector3) scaled(Vector3 scale) {
    bool near(double a, double b) => (a - b).abs() < 1e-6;
    switch (shape) {
      case 'box':
        return (
          PrimitiveShape.box(
            Vector3(size!.x * scale.x, size!.y * scale.y, size!.z * scale.z),
          ),
          Vector3.all(1.0),
        );
      case 'sphere' when near(scale.x, scale.y) && near(scale.y, scale.z):
        return (PrimitiveShape.sphere(radius! * scale.x), Vector3.all(1.0));
      case 'cylinder' when near(scale.x, scale.z):
        return (
          PrimitiveShape.cylinder(radius! * scale.x, height! * scale.y),
          Vector3.all(1.0),
        );
      default:
        return (this, scale);
    }
  }

  Map<String, Object?> toProperties() => <String, Object?>{
    'shape': shape,
    if (size case final Vector3 s) 'size': vectorJson(s),
    if (radius case final double r) 'radius': roundNumber(r),
    if (height case final double h) 'height': roundNumber(h),
  };
}

/// An instance of another prefab placed inside this one.
final class NestedInstance {
  const NestedInstance(this.prefab, {this.overrides = const {}});

  /// The prefab's id in the document's `prefabs`.
  final String prefab;

  /// What this instance changes in it, by entity path — see
  /// `PrefabInstance` in `flutter3d_sim`.
  final PrefabOverrides overrides;
}

/// One node of a converted scene.
final class SceneItem {
  SceneItem({
    required this.name,
    Matrix4? local,
    this.asset,
    this.materials = const <String?>[],
    this.shape,
    this.instance,
    List<SceneItem>? children,
    Map<String, Object?>? properties,
  }) : local = local ?? Matrix4.identity(),
       children = children ?? <SceneItem>[],
       properties = properties ?? <String, Object?>{};

  /// The source's name for it.
  final String name;

  /// Placement relative to its parent, in the engine's frame.
  final Matrix4 local;

  /// The converted model it draws, relative to the output directory.
  final String? asset;

  /// The level material each of the model's slots wears instead of its own,
  /// by id in the document's `materials`; null keeps the model's.
  final List<String?> materials;

  /// The primitive it draws instead of a model.
  final PrimitiveShape? shape;

  /// The prefab it places instead of drawing anything itself.
  final NestedInstance? instance;

  final List<SceneItem> children;

  /// Anything else the row should carry.
  final Map<String, Object?> properties;
}

/// A template: what one source file — a `.prefab`, a `.tscn`, a USD layer,
/// a glTF scene — places.
final class ScenePrefab {
  const ScenePrefab(this.id, this.roots);

  final String id;
  final List<SceneItem> roots;
}

/// A material a level names: its id, the `.fmat` or `.f3dmat` it defers
/// to, and the surface the level's own fields are filled from.
final class SceneMaterial {
  const SceneMaterial(this.id, this.file, this.surface);

  final String id;

  /// Relative to the output directory.
  final String file;
  final SurfaceMaterial surface;
}

/// [value] to six decimals, without a negative zero: what every number a
/// converter writes into a document goes through, so a rotation that came
/// out as `1e-17` on one machine is the same `0.0` on another.
double roundNumber(double value) {
  final rounded = (value * 1e6).roundToDouble() / 1e6;
  return rounded == 0.0 ? 0.0 : rounded;
}

/// [v] as a JSON array, rounded.
List<double> vectorJson(Vector3 v) => <double>[
  roundNumber(v.x),
  roundNumber(v.y),
  roundNumber(v.z),
];

/// Hamilton product `a * b`: the rotation [b], then [a].
Quaternion quaternionProduct(Quaternion a, Quaternion b) => Quaternion(
  a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
  a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
  a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
  a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z,
);

/// A row's placement, the way a level document says it.
///
/// A level places a thing by `at` and `yaw`, and composes nothing else
/// through a prefab instance: `expandPrefabs` turns a template's rows by the
/// instance's yaw and adds the yaws. So the rotation is split into the turn
/// about Y the format already has, and the rest, `tilt`, applied first:
/// rotation = yaw · tilt. A parent's yaw then composes with a child's
/// exactly, and the tilt stays where it was.
typedef Placement = ({Vector3 at, double yaw, Quaternion tilt, Vector3 scale});

/// [matrix] split into a [Placement].
Placement placementOf(Matrix4 matrix) {
  final at = Vector3.zero();
  final rotation = Quaternion.identity();
  final scale = Vector3.zero();
  matrix.decompose(at, rotation, scale);
  final q = rotation.normalized();
  final twistLength = math.sqrt(q.y * q.y + q.w * q.w);
  if (twistLength < 1e-9) {
    // Upside down about a horizontal axis: no turn about Y to speak of.
    return (at: at, yaw: 0.0, tilt: q, scale: scale);
  }
  final twist = Quaternion(0.0, q.y / twistLength, 0.0, q.w / twistLength);
  final yaw = 2.0 * math.atan2(twist.y, twist.w);
  final tilt = quaternionProduct(twist.conjugated(), q).normalized();
  return (at: at, yaw: _wrapAngle(yaw), tilt: tilt, scale: scale);
}

double _wrapAngle(double radians) {
  var a = radians;
  while (a > math.pi) {
    a -= 2.0 * math.pi;
  }
  while (a <= -math.pi) {
    a += 2.0 * math.pi;
  }
  return a;
}

bool _isIdentityTilt(Quaternion q) =>
    (q.w.abs() - 1.0).abs() < 1e-6 &&
    q.x.abs() < 1e-6 &&
    q.y.abs() < 1e-6 &&
    q.z.abs() < 1e-6;

bool _isUnitScale(Vector3 s) =>
    (s.x - 1.0).abs() < 1e-6 &&
    (s.y - 1.0).abs() < 1e-6 &&
    (s.z - 1.0).abs() < 1e-6;

/// The keys a [Placement] adds to a row.
Map<String, Object?> placementJson(Placement p) => <String, Object?>{
  'at': vectorJson(p.at),
  if (roundNumber(p.yaw) != 0.0) 'yaw': roundNumber(p.yaw),
  if (!_isIdentityTilt(p.tilt))
    'tilt': <double>[
      roundNumber(p.tilt.x),
      roundNumber(p.tilt.y),
      roundNumber(p.tilt.z),
      roundNumber(p.tilt.w),
    ],
  if (!_isUnitScale(p.scale)) 'scale': vectorJson(p.scale),
};

/// The paths a level names are asset paths: the output directory's own
/// prefix, then the path inside it.
String assetPath(String prefix, String relative) =>
    prefix.isEmpty ? relative : '$prefix/$relative';

/// Builds the level document for [prefabs], the first of which is the
/// input itself: every prefab under `prefabs`, and one instance of the first
/// at the origin, so the document opens as the thing it was converted from.
///
/// [prefix] is put in front of every path the document names. [report]
/// hears what was folded away.
String levelDocument({
  required String name,
  required List<ScenePrefab> prefabs,
  required List<SceneMaterial> materials,
  required String prefix,
  required ConvertReport report,
}) {
  final byId = <String, ScenePrefab>{for (final p in prefabs) p.id: p};
  final templates = <String, Prefab>{
    for (final prefab in prefabs)
      prefab.id: Prefab(
        entities: _rows(
          prefab,
          byId,
          prefix,
          report,
        ).map(EntityDef.fromJson).toList(),
      ),
  };
  final level = Level(
    name: name,
    prefabs: templates,
    materials: <String, LevelMaterial>{
      for (final m in materials)
        m.id: LevelMaterial(
          baseColor: LinearColor.fromSrgb(
            roundNumber(m.surface.baseColor.toSrgb().r),
            roundNumber(m.surface.baseColor.toSrgb().g),
            roundNumber(m.surface.baseColor.toSrgb().b),
            roundNumber(m.surface.baseColor.a),
          ),
          roughness: roundNumber(m.surface.roughness),
          metallic: roundNumber(m.surface.metallic),
          fmat: assetPath(prefix, m.file),
        ),
    },
    entities: <EntityDef>[
      EntityDef(
        type: EntityTypes.prefab,
        name: prefabs.first.id,
        properties: <String, Object?>{'prefab': prefabs.first.id},
      ),
    ],
  );
  final json = level.toJson();
  // A converted document is not a hand-made one: an editor asked to save
  // over it says so and offers a copy, which is what `generatedBy` is for.
  json['generatedBy'] = 'flutter3d convert';
  return '${const JsonEncoder.withIndent('  ').convert(_rounded(json))}\n';
}

/// [value] with every number rounded by [roundNumber]: the level's own
/// vectors are single precision, and `0.9` read back from one is
/// `0.8999999761581421`.
Object? _rounded(Object? value) => switch (value) {
  /// A number, in whatever unit the level holds it in.
  final double d => roundNumber(d),
  final Map<String, Object?> map => <String, Object?>{
    for (final MapEntry(:key, :value) in map.entries) key: _rounded(value),
  },
  final List<Object?> list => <Object?>[for (final v in list) _rounded(v)],
  _ => value,
};

/// [prefab]'s entity rows, relative to its origin.
List<Map<String, Object?>> _rows(
  ScenePrefab prefab,
  Map<String, ScenePrefab> byId,
  String prefix,
  ConvertReport report,
) {
  final rows = <Map<String, Object?>>[];
  final names = <String, int>{};
  String unique(String name) {
    final seen = names[name] ?? 0;
    names[name] = seen + 1;
    return seen == 0 ? name : '$name.$seen';
  }

  void walk(SceneItem item, Matrix4 parent, Set<String> inlining) {
    final world = parent * item.local;
    if (item.instance case final NestedInstance nested) {
      final placement = placementOf(world);
      final keepsInstance =
          _isIdentityTilt(placement.tilt) && _isUnitScale(placement.scale);
      final target = byId[nested.prefab];
      if (keepsInstance || target == null) {
        if (target == null) {
          report.warn(
            '${item.name}: prefab "${nested.prefab}" was not converted; the '
            'row names it anyway',
          );
        }
        rows.add(<String, Object?>{
          'type': EntityTypes.prefab,
          'name': unique(item.name),
          ...placementJson(placement)
            ..remove('tilt')
            ..remove('scale'),
          'prefab': nested.prefab,
          if (nested.overrides.isNotEmpty) 'overrides': nested.overrides,
          ...item.properties,
        });
      } else if (inlining.contains(nested.prefab)) {
        report.drop(item.name, 'prefab "${nested.prefab}" contains itself');
      } else {
        // A level turns an instance by its yaw and nothing else, so one
        // that is tilted or scaled is written out row by row instead: the
        // picture is kept, the link to the template is not.
        report.warn(
          '${item.name}: an instance of "${nested.prefab}" that is tilted or '
          'scaled is written as its rows, since a level places an instance '
          'by position and yaw only',
        );
        if (nested.overrides.isNotEmpty) {
          report.drop(
            '${item.name}: overrides of the inlined instance',
            'they address rows of a template the document no longer names',
          );
        }
        for (final root in target.roots) {
          walk(root, world, <String>{...inlining, nested.prefab});
        }
      }
    } else if (item.asset != null) {
      rows.add(<String, Object?>{
        'type': kModelEntityType,
        'name': unique(item.name),
        ...placementJson(placementOf(world)),
        'asset': assetPath(prefix, item.asset!),
        if (item.materials.any((String? m) => m != null))
          'materials': item.materials,
        ...item.properties,
      });
    } else if (item.shape case final PrimitiveShape shape) {
      // A prop is drawn by its size, and turned by its yaw alone: the scale
      // goes into the size where the shape can take it.
      final placement = placementOf(world);
      final (sized, rest) = shape.scaled(placement.scale);
      if (!_isUnitScale(rest)) {
        report.warn(
          '${item.name}: a ${shape.shape} scaled unevenly keeps its scale as '
          'a key; PropVisuals draws it at its size',
        );
      }
      if (!_isIdentityTilt(placement.tilt)) {
        report.warn(
          '${item.name}: a prop is turned by its yaw alone; its tilt is kept '
          'as a key PropVisuals does not read',
        );
      }
      rows.add(<String, Object?>{
        'type': kPropEntityType,
        'name': unique(item.name),
        ...placementJson((
          at: placement.at,
          yaw: placement.yaw,
          tilt: placement.tilt,
          scale: rest,
        )),
        ...sized.toProperties(),
        if (item.materials.any((String? m) => m != null))
          'materials': item.materials,
        ...item.properties,
      });
    }
    for (final child in item.children) {
      walk(child, world, inlining);
    }
  }

  for (final root in prefab.roots) {
    walk(root, Matrix4.identity(), <String>{prefab.id});
  }
  return rows;
}
