/// What the crypt's crates and barrels are drawn with: boards and battens,
/// staves and iron hoops, and the planks a broken one leaves.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter3d/flutter3d.dart';
import 'package:vector_math/vector_math.dart';

/// Floats a vertex of [VertexLayout.standard] takes: place, normal, picture
/// coordinates, tangent and colour.
const int _stride = 16;

/// How many metres of boards one repeat of the planks picture covers.
const double _boardsEvery = 0.8;

/// Vertices and indices being gathered into one mesh.
final class _Builder {
  final List<double> vertices = <double>[];
  final List<int> indices = <int>[];

  int get count => vertices.length ~/ _stride;

  void vertex(
    Vector3 at,
    Vector3 normal,
    double u,
    double v,
    Vector3 tangent,
    double shade,
  ) => vertices.addAll(<double>[
    at.x, at.y, at.z, //
    normal.x, normal.y, normal.z,
    u, v,
    tangent.x, tangent.y, tangent.z, -1.0,
    shade, shade, shade, 1.0,
  ]);

  /// A box about [centre] with half-sizes [half], each face's picture laid
  /// on from the side it faces, in metres, so boards run on across the
  /// parts of a crate rather than being squeezed onto each batten; one
  /// repeat of the picture every [every] metres.
  void box(
    Vector3 centre,
    Vector3 half, {
    double shade = 1.0,
    double every = _boardsEvery,
  }) {
    for (var axis = 0; axis < 3; axis++) {
      for (final sign in const <double>[1.0, -1.0]) {
        final n = Vector3.zero()..[axis] = sign;
        // Two directions across the face: u along the next axis round, v
        // along the one after, the tangent along u.
        final a = (axis + 1) % 3, b = (axis + 2) % 3;
        final du = Vector3.zero()..[a] = 1.0;
        final first = count;
        for (final (su, sv) in const <(double, double)>[
          (-1.0, -1.0),
          (1.0, -1.0),
          (1.0, 1.0),
          (-1.0, 1.0),
        ]) {
          final p = centre.clone()
            ..[axis] += sign * half[axis]
            ..[a] += su * half[a]
            ..[b] += sv * half[b];
          vertex(p, n, p[a] / every, p[b] / every, du, shade);
        }
        // Counter-clockwise seen from outside: u × v is the normal for one
        // sign of the axis and its opposite for the other.
        if (sign > 0) {
          indices.addAll(<int>[
            first, first + 1, first + 2, first, first + 2, first + 3, //
          ]);
        } else {
          indices.addAll(<int>[
            first, first + 2, first + 1, first, first + 3, first + 2, //
          ]);
        }
      }
    }
  }

  MeshData build() => MeshData(
    layout: VertexLayout.standard,
    vertices: Float32List.fromList(vertices),
    indices: Uint32List.fromList(indices),
  );
}

/// A block about [centre] with half-sizes [half], its picture laid on each
/// face from the side, repeating every [every] metres: the stone the
/// flooded vault's sill and culvert are built of.
MeshData blockMesh(Vector3 centre, Vector3 half, {double every = 1.0}) =>
    (_Builder()..box(centre, half, every: every)).build();

/// The meshes and pictures every crate and barrel of a run shares; each
/// prop has a material of its own, so a fire chars it alone.
final class WoodenProps {
  WoodenProps._(
    this._boards,
    this._relief,
    this._iron,
    this._ironRelief, {
    required this.crate,
    required this.barrel,
    required this.hoops,
    required this.plank,
    required this.stave,
  });

  /// A crate's side, m.
  static const double crateSize = 0.8;

  /// A barrel's radius at its ends and its height, m.
  static const double barrelRadius = 0.3, barrelHeight = 0.9;

  /// A broken crate's planks and a broken barrel's staves, as boxes: their
  /// half-sizes.
  static Vector3 get plankHalf => Vector3(0.38, 0.06, 0.016);
  static Vector3 get staveHalf => Vector3(0.05, 0.44, 0.016);

  final TextureHandle? _boards, _relief, _iron, _ironRelief;

  /// A crate: six boarded faces with a batten along every edge.
  final DeviceMesh crate;

  /// A barrel: bellied staves and its two heads; [hoops] are drawn apart, in
  /// iron.
  final DeviceMesh barrel, hoops;

  /// A board of a broken crate, and a stave of a broken barrel.
  final DeviceMesh plank, stave;

  /// Loads the pictures and builds the meshes onto [device].
  static Future<WoodenProps> load(GraphicsDevice device) async {
    Future<TextureHandle?> picture(String file) async {
      final data = await rootBundle.load('assets/textures/$file');
      return uploadEncodedImage(
        device,
        Uint8List.sublistView(data),
        decodeImage: defaultImageDecoder,
      );
    }

    return WoodenProps._(
      await picture('planks_albedo.jpg'),
      await picture('planks_normal.png'),
      await picture('metal_albedo.jpg'),
      await picture('metal_normal.png'),
      crate: DeviceMesh.upload(device, _crate()),
      barrel: DeviceMesh.upload(device, _barrel()),
      hoops: DeviceMesh.upload(device, _hoops()),
      plank: DeviceMesh.upload(
        device,
        (_Builder()..box(Vector3.zero(), plankHalf)).build(),
      ),
      stave: DeviceMesh.upload(
        device,
        (_Builder()..box(Vector3.zero(), staveHalf)).build(),
      ),
    );
  }

  /// A fresh material of boards, its own to char: grey weathered pine,
  /// warmed a little by [tint].
  ///
  /// Its glow, which stays off until a fire chars it, is the same picture:
  /// embers show along the grain and in the seams between boards, not as
  /// one lit face.
  Material wood({Vector4? tint}) => Material(
    name: 'boards',
    albedo: _boards,
    normal: _relief,
    normalScale: 0.9,
    emissiveTexture: _boards,
    baseColor: tint ?? Vector4(1.0, 0.86, 0.7, 1.0),
    roughness: 0.88,
  );

  /// The barrels' hoops, which a fire blackens no further than iron is.
  late final Material iron = Material(
    name: 'hoops',
    albedo: _iron,
    normal: _ironRelief,
    baseColor: Vector4(0.55, 0.5, 0.46, 1.0),
    metallic: 0.85,
    roughness: 0.55,
  );

  static MeshData _crate() {
    const h = crateSize / 2;
    const batten = 0.045;
    final b = _Builder()
      // The boards, set back a little behind the battens.
      ..box(Vector3.zero(), Vector3.all(h - 0.02));
    // A batten along each of the twelve edges, darker with handling.
    for (var axis = 0; axis < 3; axis++) {
      for (final s1 in const <double>[-1.0, 1.0]) {
        for (final s2 in const <double>[-1.0, 1.0]) {
          final at = Vector3.zero()
            ..[(axis + 1) % 3] = s1 * (h - batten)
            ..[(axis + 2) % 3] = s2 * (h - batten);
          final half = Vector3.all(batten)..[axis] = h;
          b.box(at, half, shade: 0.72);
        }
      }
    }
    // And a brace across each side face, corner to corner, drawn as a flat
    // board laid on it: across x on the faces looking along z, across z on
    // those looking along x.
    for (final sign in const <double>[-1.0, 1.0]) {
      b
        ..box(
          Vector3(0.0, 0.0, sign * (h - 0.005)),
          Vector3(h - 2 * batten, 0.05, 0.012),
          shade: 0.8,
        )
        ..box(
          Vector3(sign * (h - 0.005), 0.0, 0.0),
          Vector3(0.012, 0.05, h - 2 * batten),
          shade: 0.8,
        );
    }
    return b.build();
  }

  /// The radius a barrel's staves stand at, [y] up from its middle: wider
  /// at the belly than at the heads, as a cooper bends them.
  static double _girth(double y) {
    final t = y / (barrelHeight / 2);
    return barrelRadius + 0.05 * (1.0 - t * t);
  }

  static MeshData _barrel() {
    const sides = 18, rings = 8;
    final b = _Builder();
    const half = barrelHeight / 2;
    for (var j = 0; j <= rings; j++) {
      final y = -half + barrelHeight * j / rings;
      final r = _girth(y);
      // How the stave leans at this height, for its normal.
      final slope = -0.05 * 2 * y / (half * half);
      for (var i = 0; i <= sides; i++) {
        final a = 2 * math.pi * i / sides;
        final out = Vector3(math.cos(a), 0.0, math.sin(a));
        final normal = Vector3(out.x, -slope, out.z)..normalize();
        // Staves upright: the picture's boards, which run along u, run up
        // the barrel; one board of the picture a stave.
        final stave = (i % 2 == 0) ? 1.0 : 0.9;
        b.vertex(
          out * r + Vector3(0.0, y, 0.0),
          normal,
          (y + half) / _boardsEvery,
          i * 0.17,
          Vector3(0.0, 1.0, 0.0),
          stave,
        );
      }
    }
    for (var j = 0; j < rings; j++) {
      for (var i = 0; i < sides; i++) {
        final k = j * (sides + 1) + i;
        b.indices.addAll(<int>[
          k, k + sides + 1, k + 1, k + 1, k + sides + 1, k + sides + 2, //
        ]);
      }
    }
    // The two heads, a fan each.
    for (final sign in const <double>[1.0, -1.0]) {
      final centre = b.count;
      final y = sign * half;
      b.vertex(
        Vector3(0.0, y, 0.0),
        Vector3(0.0, sign, 0.0),
        0.5,
        0.5,
        Vector3(1.0, 0.0, 0.0),
        0.85,
      );
      for (var i = 0; i <= sides; i++) {
        final a = 2 * math.pi * i / sides;
        final p = Vector3(
          math.cos(a) * barrelRadius,
          y,
          math.sin(a) * barrelRadius,
        );
        b.vertex(
          p,
          Vector3(0.0, sign, 0.0),
          0.5 + p.x / _boardsEvery,
          0.5 + p.z / _boardsEvery,
          Vector3(1.0, 0.0, 0.0),
          0.85,
        );
      }
      for (var i = 0; i < sides; i++) {
        b.indices.addAll(
          sign > 0
              ? <int>[centre, centre + i + 2, centre + i + 1]
              : <int>[centre, centre + i + 1, centre + i + 2],
        );
      }
    }
    return b.build();
  }

  static MeshData _hoops() {
    const sides = 18;
    final b = _Builder();
    // Four hoops: by each head and either side of the belly.
    for (final y in const <double>[-0.4, -0.16, 0.16, 0.4]) {
      final r = _girth(y) + 0.008;
      final first = b.count;
      for (var i = 0; i <= sides; i++) {
        final a = 2 * math.pi * i / sides;
        final out = Vector3(math.cos(a), 0.0, math.sin(a));
        for (final dy in const <double>[-0.025, 0.025]) {
          b.vertex(
            out * r + Vector3(0.0, y + dy, 0.0),
            out,
            i * 0.2,
            dy * 4,
            Vector3(-out.z, 0.0, out.x),
            1.0,
          );
        }
      }
      for (var i = 0; i < sides; i++) {
        final k = first + 2 * i;
        b.indices.addAll(<int>[k, k + 1, k + 2, k + 2, k + 1, k + 3]);
      }
    }
    return b.build();
  }
}
