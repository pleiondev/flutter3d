/// A row of trees whose far ones are drawn as octahedral impostors: one card
/// each, turned to the eye and painted from views baked in advance.
///
/// Quoted by `impostors.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

/// A ball of the tree: where it is, how big, and its colour as a paint
/// program shows it.
typedef _Ball = ({Vector3 centre, double radius, Vector3 colour});

/// What a ray met first: how far along it, the surface normal there and the
/// colour of the part it hit.
typedef _Hit = ({double t, Vector3 normal, Vector3 colour});

final class ImpostorsDemo extends ShowcaseDemo {
  bool markCards = false;
  double sunYaw = 0.6;

  late final Scene _scene;
  late final LightNode _sun;

  /// Texels along each side of one baked view.
  static const int _cell = 32;

  /// How many trees stand in the row.
  static const int _count = 5;

  static Vector3 get _bark => Vector3(0.45, 0.3, 0.18);
  static Vector3 get _leaves => Vector3(0.25, 0.6, 0.2);
  static Vector3 get _fruit => Vector3(0.85, 0.15, 0.1);

  // #region tree
  static Aabb3 get _trunk =>
      Aabb3.minMax(Vector3(-0.12, 0.0, -0.12), Vector3(0.12, 1.2, 0.12));
  static List<_Ball> get _balls => <_Ball>[
    (centre: Vector3(0.0, 1.75, 0.0), radius: 0.75, colour: _leaves),
    (centre: Vector3(0.0, 2.4, 0.0), radius: 0.45, colour: _leaves),
    // One fruit on the +X side, so the tree looks different from each side.
    (centre: Vector3(0.8, 1.45, 0.0), radius: 0.25, colour: _fruit),
  ];
  // #endregion tree

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..target.setValues(0.0, 1.3, -10.0)
      ..distance = 11.0
      ..pitch = 0.12
      ..yaw = 0.25;
  }

  @override
  Scene build(DemoContext context) {
    final GraphicsDevice device = context.device;

    // #region mesh
    final MeshData tree = MeshData.merge(<MeshData>[
      _painted(
        CuboidShape(
          size: _trunk.max - _trunk.min,
        ).build().transformed(Matrix4.translation(_trunk.center)),
        _bark,
      ),
      for (final _Ball ball in _balls)
        _painted(
          SphereShape(
            radius: ball.radius,
            segments: 24,
            rings: 12,
          ).build().transformed(Matrix4.translation(ball.centre)),
          ball.colour,
        ),
    ]);
    final Vector3 centre = tree.computeBounds().center;
    // A little over the furthest vertex: a ball's true edge can lie between
    // the vertices of its mesh.
    final double radius = _radiusAround(tree, centre) * 1.02;
    // #endregion mesh

    // #region upload
    final ({Uint8List albedo, Uint8List normalDepth}) atlas = _bake(
      centre,
      radius,
    );
    const int side = _cell * kImpostorGrid;
    TextureHandle upload(Uint8List rgba) => device.createTextureFromPixels(
      width: side,
      height: side,
      format: TextureFormat.r8g8b8a8UNormInt,
      pixels: ByteData.sublistView(rgba),
    )!;
    final TextureHandle albedo = upload(atlas.albedo);
    final TextureHandle normalDepth = upload(atlas.normalDepth);
    // #endregion upload

    // #region asset
    final ModelImpostor impostor = ModelImpostor(
      // Indices into a file's images. Nothing is read through them here: the
      // textures are handed over below.
      albedoImage: 0,
      normalDepthImage: 1,
      grid: kImpostorGrid,
      centre: centre,
      radius: radius,
    );
    final ModelAsset asset = ModelAsset(
      name: 'tree',
      parts: <ModelPart>[
        ModelPart(
          mesh: DeviceMesh.upload(device, tree),
          material: Material(name: 'tree', roughness: 0.8),
          name: 'tree',
        ),
      ],
      nodes: <ModelNode>[
        ModelNode(
          name: 'tree',
          surfaces: const <int>[0],
          lods: <ModelLod>[
            ModelLod.impostor(impostor: impostor, maxScreenFraction: 0.25),
          ],
        ),
      ],
      roots: const <int>[0],
      localBounds: tree.computeBounds(),
      impostors: <ModelImpostor, ImpostorPart>{
        impostor: (
          card: DeviceMesh.upload(
            device,
            impostorCard(centre: centre, radius: radius),
          ),
          albedo: albedo,
          normalDepth: normalDepth,
        ),
      },
    );
    // #endregion asset

    _scene = Scene()
      ..ambientColor = Vector3(0.5, 0.6, 0.75)
      ..ambientIntensity = 0.25
      ..add(
        MeshNode(
          DeviceMesh.upload(
            device,
            const PlaneShape(width: 24, depth: 40).build(),
          ),
          Material(
            name: 'grass',
            baseColor: Vector4(0.42, 0.5, 0.32, 1.0),
            roughness: 0.95,
          ),
          name: 'ground',
        )..setPosition(0.0, 0.0, -12.0),
      );

    // #region row
    for (var i = 0; i < _count; i++) {
      asset
          .instantiate(_scene, name: 'tree $i')
          .root
          .setPosition(i.isEven ? -1.5 : 1.5, 0.0, -2.0 - 6.0 * i);
    }
    // #endregion row

    // #region sun
    _sun = LightNode(name: 'sun', intensity: 3.0)..castsShadow = true;
    // #endregion sun
    return _scene..add(_sun);
  }

  @override
  void update(DemoContext context, double dt) {
    // #region light
    _sun.setLocalForward(
      Vector3(math.sin(sunYaw), -0.9, math.cos(sunYaw))..normalize(),
    );
    // #endregion light

    // #region mark
    for (final LodGroup group in _scene.lodGroups) {
      for (final LodLevel level in group.levels) {
        if (level.node is ImpostorNode) {
          level.node.material.baseColor.setValues(
            markCards ? 0.55 : 1.0,
            markCards ? 0.75 : 1.0,
            1.0,
            1.0,
          );
        }
      }
    }
    // #endregion mark
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ToggleControl(
      'Tint the cards blue',
      value: () => markCards,
      onChanged: (bool v) => markCards = v,
    ),
    SliderControl(
      'Sun direction',
      min: -math.pi,
      max: math.pi,
      value: () => sunYaw,
      onChanged: (double v) => sunYaw = v,
      format: (double v) => '${(v * 180 / math.pi).round()} deg',
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    final List<LodGroup> groups = scene.lodGroups;
    bool showsCard(LodGroup g) =>
        g.levels[g.activeLevel].node is ImpostorNode &&
        g.levels[g.activeLevel].node.visible;
    if (groups.length != _count ||
        !groups.any(showsCard) ||
        !groups.any((LodGroup g) => g.activeLevel == 0) ||
        frame.drawCalls < 1) {
      throw StateError('the row should end in cards and start in meshes');
    }
    // #endregion check
  }
}

// #region bake
/// Both atlases, [kImpostorGrid] by [kImpostorGrid] views of [ImpostorsDemo._cell]
/// texels, found by casting one ray a texel at the tree's own shapes.
///
/// Each view looks back along [impostorViewDirection] at the sphere of
/// [radius] around [centre], with [impostorRight] to its right, and the top
/// row of a view is the side its up axis points to: the layout the impostor
/// shader reads.
({Uint8List albedo, Uint8List normalDepth}) _bake(
  Vector3 centre,
  double radius,
) {
  const int cell = ImpostorsDemo._cell;
  const int side = cell * kImpostorGrid;
  final Uint8List albedo = Uint8List(side * side * 4);
  final Uint8List normalDepth = Uint8List(side * side * 4);
  int byte(double v) => (v.clamp(0.0, 1.0) * 255.0).round();
  final List<_Ball> balls = ImpostorsDemo._balls;
  final Aabb3 trunk = ImpostorsDemo._trunk;
  final Vector3 bark = ImpostorsDemo._bark;
  final Vector3 empty = ImpostorsDemo._leaves;

  for (var row = 0; row < kImpostorGrid; row++) {
    for (var column = 0; column < kImpostorGrid; column++) {
      final Vector3 d = impostorViewDirection(column, row);
      final Vector3 right = impostorRight(d);
      final Vector3 up = d.cross(right);
      for (var y = 0; y < cell; y++) {
        for (var x = 0; x < cell; x++) {
          final Vector3 origin =
              centre +
              right.scaled(((x + 0.5) / cell * 2.0 - 1.0) * radius) +
              up.scaled((1.0 - (y + 0.5) / cell * 2.0) * radius) +
              d.scaled(2.0 * radius);
          final _Hit? hit = _cast(origin, -d, balls, trunk, bark);
          final int to = ((row * cell + y) * side + column * cell + x) * 4;
          // An empty texel still gets a leaf colour, with no coverage, so a
          // filtered read at the edge of the tree does not mix in black.
          final Vector3 colour = hit?.colour ?? empty;
          albedo
            ..[to] = byte(colour.x)
            ..[to + 1] = byte(colour.y)
            ..[to + 2] = byte(colour.z)
            ..[to + 3] = hit == null ? 0 : 255;
          if (hit == null) continue;
          final Vector3 point = origin + (-d).scaled(hit.t);
          // How far along the view the surface is: 0 at the near side of the
          // sphere, 1 at the far side.
          final double depth = 0.5 - (point - centre).dot(d) / (2.0 * radius);
          normalDepth
            ..[to] = byte(hit.normal.x * 0.5 + 0.5)
            ..[to + 1] = byte(hit.normal.y * 0.5 + 0.5)
            ..[to + 2] = byte(hit.normal.z * 0.5 + 0.5)
            ..[to + 3] = byte(depth);
        }
      }
    }
  }
  return (albedo: albedo, normalDepth: normalDepth);
}
// #endregion bake

/// The nearest of the trunk and the balls along the ray from [origin] in
/// [direction], or null when it misses them all.
_Hit? _cast(
  Vector3 origin,
  Vector3 direction,
  List<_Ball> balls,
  Aabb3 box,
  Vector3 bark,
) {
  _Hit? nearest;
  for (final _Ball ball in balls) {
    final Vector3 oc = origin - ball.centre;
    final double b = oc.dot(direction);
    final double disc = b * b - (oc.dot(oc) - ball.radius * ball.radius);
    if (disc < 0.0) continue;
    final double t = -b - math.sqrt(disc);
    if (t < 0.0 || (nearest != null && t >= nearest.t)) continue;
    final Vector3 at = origin + direction.scaled(t);
    nearest = (
      t: t,
      normal: (at - ball.centre)..scale(1.0 / ball.radius),
      colour: ball.colour,
    );
  }

  // The trunk, by the slab test: the ray enters the box where it has
  // crossed the near face of all three pairs of faces.
  var enter = double.negativeInfinity;
  var leave = double.infinity;
  var axis = -1;
  for (var i = 0; i < 3; i++) {
    if (direction[i].abs() < 1e-9) {
      if (origin[i] < box.min[i] || origin[i] > box.max[i]) return nearest;
      continue;
    }
    final double a = (box.min[i] - origin[i]) / direction[i];
    final double b = (box.max[i] - origin[i]) / direction[i];
    final double near = math.min(a, b);
    if (near > enter) {
      enter = near;
      axis = i;
    }
    leave = math.min(leave, math.max(a, b));
  }
  if (axis < 0 || enter > leave || enter < 0.0) return nearest;
  if (nearest != null && enter >= nearest.t) return nearest;
  final Vector3 normal = Vector3.zero()
    ..[axis] = direction[axis] > 0.0 ? -1.0 : 1.0;
  return (t: enter, normal: normal, colour: bark);
}

/// [mesh] with every vertex colour set to [srgb], converted to the linear
/// value a vertex colour is authored in.
MeshData _painted(MeshData mesh, Vector3 srgb) {
  double linear(double c) =>
      c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  final int stride = mesh.layout.floatsPerVertex;
  final int at = mesh.layout.floatOffsetOf(VertexLayout.color.name);
  final Float32List vertices = Float32List.fromList(mesh.vertices);
  for (var v = 0; v < mesh.vertexCount; v++) {
    vertices[v * stride + at] = linear(srgb.x);
    vertices[v * stride + at + 1] = linear(srgb.y);
    vertices[v * stride + at + 2] = linear(srgb.z);
  }
  return MeshData(
    layout: mesh.layout,
    vertices: vertices,
    indices: mesh.indices,
  );
}

/// The furthest any vertex of [mesh] is from [centre].
double _radiusAround(MeshData mesh, Vector3 centre) {
  final int stride = mesh.layout.floatsPerVertex;
  final int at = mesh.layout.floatOffsetOf(VertexLayout.position.name);
  return Iterable<int>.generate(mesh.vertexCount).fold(0.0, (
    double furthest,
    int v,
  ) {
    final int o = v * stride + at;
    return math.max(
      furthest,
      Vector3(
        mesh.vertices[o] - centre.x,
        mesh.vertices[o + 1] - centre.y,
        mesh.vertices[o + 2] - centre.z,
      ).length,
    );
  });
}
