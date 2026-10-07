/// What a block's faces are drawn with: a material for every surface in the
/// palette, and the one way a face of a block is laid down as a mesh, which
/// the chunks and the falling blocks both use so a block looks the same
/// lying in the world and tumbling through the air.
library;

import 'dart:typed_data';

import 'package:flutter/services.dart' show AssetBundle;
import 'package:flutter3d/flutter3d.dart';
import 'package:vector_math/vector_math.dart';

import 'palette.dart';

/// A material a surface of [surfaces], shared by every chunk and every
/// falling block that shows it.
final class BlockSurfaces {
  BlockSurfaces._(this._materials);

  /// Every surface in its flat colour: what a run with no pictures to hand
  /// — a test on the software device — draws.
  factory BlockSurfaces.flat() => BlockSurfaces._(<String, Material>{
    for (final MapEntry(key: name, value: surface) in surfaces.entries)
      name: Material(
        name: name,
        baseColor: surface.colour,
        roughness: surface.roughness,
        metallic: surface.metallic,
      ),
  });

  /// Every surface with its pictures from `assets/blocks/`, read from
  /// [bundle] and uploaded through [device]: `<name>.jpg` for its colour and
  /// `<name>_normal.jpg` for the bumps in it.
  ///
  /// **Clamped, not repeated.** Each face is one block's picture from edge
  /// to edge, so its texture coordinates never leave the square, and a
  /// repeating sampler would only blur the far edge into the near one: the
  /// fringe of turf along the bottom of a grass side. A surface whose colour
  /// will not load keeps its flat colour rather than going black; one whose
  /// normal map will not load is drawn flat.
  static Future<BlockSurfaces> load(
    GraphicsDevice device,
    AssetBundle bundle,
  ) async {
    const sampling = TextureSampling(
      wrapS: TextureWrap.clampToEdge,
      wrapT: TextureWrap.clampToEdge,
    );
    final sampler = samplerOptionsFor(sampling);
    final flat = BlockSurfaces.flat();
    Future<TextureHandle?> picture(String file) async {
      final bytes = await bundle.load('assets/blocks/$file.jpg');
      return uploadEncodedImage(
        device,
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        decodeImage: defaultImageDecoder,
        sampling: sampling,
      );
    }

    final materials = <String, Material>{};
    for (final MapEntry(key: name, value: surface) in surfaces.entries) {
      final colour = await picture(name);
      materials[name] = colour == null
          ? flat.of(name)
          : Material(
              name: name,
              albedo: colour,
              albedoSampler: sampler,
              normal: await picture('${name}_normal'),
              normalSampler: sampler,
              normalScale: surface.bumps,
              roughness: surface.roughness,
              metallic: surface.metallic,
            );
    }
    return BlockSurfaces._(materials);
  }

  final Map<String, Material> _materials;

  /// The material [surface] is drawn with: stone's, for a name the palette
  /// does not have.
  Material of(String surface) => _materials[surface] ?? _materials['stone']!;
}

/// Which way a face looks: one of the six, as a unit step between blocks.
typedef Facing = ({int x, int y, int z});

/// The six ways a block's faces look.
const List<Facing> facings = <Facing>[
  (x: 1, y: 0, z: 0),
  (x: -1, y: 0, z: 0),
  (x: 0, y: 1, z: 0),
  (x: 0, y: -1, z: 0),
  (x: 0, y: 0, z: 1),
  (x: 0, y: 0, z: -1),
];

/// The surface of [kind] a face looking along [facing] shows.
String surfaceOf(BlockKind kind, Facing facing) => switch (facing.y) {
  1 => kind.top,
  -1 => kind.bottom,
  _ => kind.side,
};

/// Block faces laid down as one mesh, in `VertexLayout.standard`.
///
/// **A face is a picture hung the right way up.** Its texture runs from
/// the top-left corner as seen from outside, with "down" the world's down
/// on a side, so the turf of a grass side is at the top of every side
/// whichever way it faces; a top is seen with north up and a bottom with
/// south up, so neither is a mirror image. A face may be given quarter
/// turns on top of that, which is how a field of sand or stone stops
/// showing the same metre over and over.
///
/// **The corners carry their own shade** in the vertex colour, which the
/// engine multiplies into the albedo: that is how a chunk darkens the
/// corner a block meets its neighbours in. The quad is split along the
/// diagonal between its two lighter or two darker corners, whichever pair
/// is the more alike, so the shade runs smoothly across the face rather
/// than creasing along the wrong diagonal.
final class FaceMesh {
  final List<double> _vertices = <double>[];
  final List<int> _indices = <int>[];

  /// Whether nothing has been laid down.
  bool get isEmpty => _indices.isEmpty;

  /// The face of the block centred at ([x], [y], [z]) that looks along
  /// [facing], its picture given [turns] quarter turns and its corners
  /// shaded by [shade] — top-left, bottom-left, bottom-right and top-right
  /// of the turned picture as seen from outside, one for each — and tinted
  /// by what [tint] gives for where each corner is in the world.
  void face(
    double x,
    double y,
    double z,
    Facing facing, {
    int turns = 0,
    List<double> shade = const <double>[1.0, 1.0, 1.0, 1.0],
    Vector3 Function(Vector3 corner)? tint,
  }) {
    final n = Vector3(
      facing.x.toDouble(),
      facing.y.toDouble(),
      facing.z.toDouble(),
    );
    final (right, down) = pictureAxes(facing, turns: turns);
    final centre = Vector3(x, y, z) + n * 0.5;
    final base = _vertices.length ~/ VertexLayout.standard.floatsPerVertex;
    // glTF's bitangent, `cross(normal, tangent) * w`, runs *up* the picture,
    // the way a normal map's green does; the sign makes it so.
    final handedness = n.cross(right).dot(down) < 0.0 ? 1.0 : -1.0;
    for (final (i, (u, v)) in _corners.indexed) {
      final p = centre + right * (u - 0.5) + down * (v - 0.5);
      final c = (tint?.call(p) ?? Vector3.all(1.0))..scale(shade[i]);
      _vertices.addAll(<double>[
        p.x, p.y, p.z, //
        n.x, n.y, n.z,
        u, v,
        right.x, right.y, right.z, handedness,
        c.x, c.y, c.z, 1.0,
      ]);
    }
    // Counter-clockwise seen from outside either way round; the second turns
    // the diagonal to run between the corners that are the more alike.
    final turn = shade[0] + shade[2] < shade[1] + shade[3];
    _indices.addAll(<int>[
      for (final i in const <int>[0, 1, 2, 0, 2, 3])
        base + (turn ? (i + 1) % 4 : i),
    ]);
  }

  /// What was laid down, as mesh data.
  MeshData build() => MeshData(
    layout: VertexLayout.standard,
    vertices: Float32List.fromList(_vertices),
    indices: Uint32List.fromList(_indices),
  );

  /// The corners in picture coordinates, in the order [face] takes them:
  /// top-left, bottom-left, bottom-right, top-right — counter-clockwise
  /// seen from outside, since the picture's down is the screen's down.
  static const List<(double, double)> _corners = <(double, double)>[
    (0.0, 0.0),
    (0.0, 1.0),
    (1.0, 1.0),
    (1.0, 0.0),
  ];
}

/// Which way the picture on a face looking along [facing] runs, given
/// [turns] quarter turns: its right and its down, in the world.
(Vector3, Vector3) pictureAxes(Facing facing, {int turns = 0}) {
  final upright = switch (facing.y) {
    1 => (Vector3(1.0, 0.0, 0.0), Vector3(0.0, 0.0, 1.0)),
    -1 => (Vector3(1.0, 0.0, 0.0), Vector3(0.0, 0.0, -1.0)),
    // Seen from outside, looking back along the normal with the sky up.
    _ => (
      Vector3(
        0.0,
        1.0,
        0.0,
      ).cross(Vector3(facing.x.toDouble(), 0.0, facing.z.toDouble())),
      Vector3(0.0, -1.0, 0.0),
    ),
  };
  // A quarter turn takes down to right and right to up, which keeps the
  // picture unmirrored and its corners counter-clockwise.
  return Iterable<int>.generate(
    turns % 4,
  ).fold(upright, (axes, _) => (axes.$2, -axes.$1));
}

/// How many quarter turns the picture on the face of block ([x], [y], [z])
/// looking along [facing] gets, if its surface may be turned: the same
/// every time the chunk is drawn, and no pattern to it a walker would see.
int turnsAt(int x, int y, int z, Facing facing) {
  final h =
      (x * 73856093) ^
      (y * 19349663) ^
      (z * 83492791) ^
      ((facing.x + 2 * facing.y + 3 * facing.z) * 2654435761);
  return (h ^ (h >> 11) ^ (h >> 23)) & 3;
}

/// A whole block of [kind] centred on the origin, a mesh a surface it shows:
/// what a falling block is drawn with.
Map<String, MeshData> blockMeshes(BlockKind kind) {
  final faces = <String, FaceMesh>{};
  for (final facing in facings) {
    faces
        .putIfAbsent(surfaceOf(kind, facing), FaceMesh.new)
        .face(0.0, 0.0, 0.0, facing);
  }
  return <String, MeshData>{
    for (final MapEntry(key: name, value: mesh) in faces.entries)
      name: mesh.build(),
  };
}
