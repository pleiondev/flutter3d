/// One shallow liquid of the physics core, drawn: its surface, the sheet it throws
/// off a lip, the drops that sheet breaks into and the splashes, and the
/// bubbles it drags down.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart'
    show
        NativeShallowLiquid,
        NativeWorld,
        nativeBubbleFloats,
        nativeSprayFloats,
        nativeSpraySheet;
import 'package:vector_math/vector_math.dart';

import 'vertices.dart';

/// How much falling water is drawn at most: pieces of a falling sheet, drops
/// and clouds of bubbles. What is past it is still simulated.
final class LiquidDetail {
  const LiquidDetail({
    required this.sheet,
    required this.drops,
    required this.bubbles,
  });

  /// A desktop or a console.
  static const LiquidDetail full = LiquidDetail(
    sheet: 4000,
    drops: 3000,
    bubbles: 3000,
  );

  /// A phone, or a browser on one.
  static const LiquidDetail light = LiquidDetail(
    sheet: 1500,
    drops: 800,
    bubbles: 600,
  );

  final int sheet, drops, bubbles;
}

/// [liquid] of [world] drawn into [scene] with [look], over the ground it
/// was made with.
///
/// **Its surface is one vertex a cell,** rewritten every frame from what
/// the core says: where it is dry the vertex sinks under the ground and is
/// not seen. Each vertex tells the material what the material cannot see:
/// the flow, x and z, as 0.5 + velocity / 8 in its colour's red and green;
/// the froth in its blue — the share of the column that is air over three
/// hundredths, water being white where it is a few parts in a hundred air,
/// however fast it runs; and the depth as its first texture coordinate.
///
/// **A sheet off a lip is one sheet.** What the lip's faces threw in one
/// step is a row across it, and each row is sewn to the one thrown before
/// it, face to face, and to its neighbours along the lip; the sheet's edges
/// stand half a face out. It is white where it is thick and thins to clear
/// as continuity thins it.
///
/// **None of it casts a shadow:** water lets most of the sun through, and a
/// shadow map knows only through or not — a solid shadow of a waterfall on
/// the cliff behind it is a dark band.
final class LiquidView {
  LiquidView({
    required this._world,
    required this.liquid,
    required List<double> ground,
    required GraphicsDevice device,
    required Scene scene,
    required Material look,
    this.detail = LiquidDetail.full,
  }) : _device = device,
       _ground = List<double>.of(ground) {
    if (ground.length != liquid.cells) {
      throw ArgumentError.value(
        ground.length,
        'ground',
        'one height a cell, ${liquid.cells}',
      );
    }
    _vertices = Float32List(liquid.cells * vertexFloats);
    _surface = DeviceMesh.upload(
      device,
      MeshData(
        layout: VertexLayout.standard,
        vertices: _writeSurface(Float32List(0)),
        indices: gridTriangles(liquid.nx, liquid.nz),
      ),
    );
    surfaceNode = MeshNode(_surface, look, name: 'water')..castsShadow = false;
    _sheetVertices = Float32List(detail.sheet * 4 * vertexFloats);
    _sheet = DeviceMesh.upload(
      device,
      MeshData(
        layout: VertexLayout.standard,
        vertices: _sheetVertices,
        indices: quadTriangles(detail.sheet),
      ),
    );
    sheetNode = MeshNode(
      _sheet,
      Material(
        name: 'falling water',
        baseColor: Vector4(0.88, 0.93, 1.0, 1.0),
        emissive: Vector3(0.55, 0.60, 0.65),
        roughness: 0.3,
        alphaMode: MaterialAlphaMode.blend,
        doubleSided: true,
      ),
      name: 'falling water',
    )..castsShadow = false;
    _drops = InstancedMeshNode(
      DeviceMesh.upload(
        device,
        const SphereShape(radius: 1.0, segments: 6, rings: 4).build(),
      ),
      Material(
        name: 'drops',
        baseColor: Vector4(0.92, 0.96, 1.0, 0.6),
        emissive: Vector3(0.6, 0.65, 0.7),
        alphaMode: MaterialAlphaMode.blend,
      ),
      capacity: detail.drops,
      name: 'drops',
    )..castsShadow = false;
    // Each cloud of millimetre bubbles drawn as one bead an eye picks out.
    _bubbles = InstancedMeshNode(
      DeviceMesh.upload(
        device,
        const SphereShape(radius: 0.03, segments: 6, rings: 4).build(),
      ),
      Material(
        name: 'bubbles',
        baseColor: Vector4(0.95, 0.98, 1.0, 0.55),
        emissive: Vector3(0.5, 0.55, 0.6),
        alphaMode: MaterialAlphaMode.blend,
      ),
      capacity: detail.bubbles,
      name: 'bubbles',
    )..castsShadow = false;
    scene
      ..add(surfaceNode)
      ..add(sheetNode)
      ..add(_drops)
      ..add(_bubbles);
  }

  final NativeWorld _world;
  final GraphicsDevice _device;

  /// The liquid drawn.
  final NativeShallowLiquid liquid;

  /// How much of its falling water is drawn at most.
  final LiquidDetail detail;

  final List<double> _ground;
  late final Float32List _vertices;
  late final DeviceMesh _surface;
  late final Float32List _sheetVertices;
  late final DeviceMesh _sheet;
  late final InstancedMeshNode _drops, _bubbles;
  final Matrix4 _m = Matrix4.identity();

  /// The surface, and the falling sheet.
  late final MeshNode surfaceNode, sheetNode;

  /// How many pieces of falling water and clouds of bubbles the core has
  /// for this liquid, and how many quads of sheet were drawn, as of the last
  /// [update].
  int sprayInFlight = 0, bubbleClouds = 0, sheetQuads = 0;

  /// The surface's vertices as the last [update] wrote them.
  Float32List get surfaceVertices => _vertices;

  /// The ground under it changed — dug, built on — as the core's
  /// `setShallowGround` was told.
  set ground(List<double> heights) => _ground.setAll(0, heights);

  /// Everything brought up to date with the world as it stands.
  void update() {
    final bubbles = _world.readBubbles(of: liquid);
    _surface.overwriteVertices(
      _device,
      0,
      _writeSurface(bubbles).buffer.asByteData(),
    );
    surfaceNode.markBoundsDirty();
    final spray = _world.readSpray(
      capacity: detail.sheet + detail.drops,
      of: liquid,
    );
    _drawDrops(spray);
    _drawSheet(spray);
    _drawBubbles(bubbles);
  }

  /// How much of each column is air, of the bubbles in it, spread over the
  /// column's neighbours as a cloud spreads.
  Float64List _airIn(Float32List bubbles, Float32List depth) {
    final nx = liquid.nx, nz = liquid.nz, cell = liquid.cell;
    final air = Float64List(liquid.cells);
    for (var o = 0; o < bubbles.length; o += nativeBubbleFloats) {
      final i = ((bubbles[o] - liquid.origin.x) / cell).floor();
      final j = ((bubbles[o + 2] - liquid.origin.z) / cell).floor();
      for (var dj = -1; dj <= 1; dj++) {
        for (var di = -1; di <= 1; di++) {
          final (x, z) = (i + di, j + dj);
          if (x < 0 || z < 0 || x >= nx || z >= nz) continue;
          air[x + z * nx] += bubbles[o + 4] / 9.0;
        }
      }
    }
    for (var c = 0; c < air.length; c++) {
      air[c] = depth[c] > _wet ? air[c] / (depth[c] * cell * cell) : 0.0;
    }
    return air;
  }

  /// Shallower than this, m, a cell is drawn dry.
  static const double _wet = 0.004;

  Float32List _writeSurface(Float32List bubbles) {
    final read = _world.readShallowSurface(liquid);
    final flow = _world.readShallowFlow(liquid);
    final nx = liquid.nx, nz = liquid.nz, cell = liquid.cell;
    final o = liquid.origin;
    final surface = read.surface;
    final air = _airIn(bubbles, read.depth);
    double height(int i, int j) =>
        surface[i.clamp(0, nx - 1) + j.clamp(0, nz - 1) * nx];
    for (var j = 0; j < nz; j++) {
      for (var i = 0; i < nx; i++) {
        final c = i + j * nx;
        final wet = read.depth[c] > _wet;
        final normal = Vector3(
          -(height(i + 1, j) - height(i - 1, j)) / (2 * cell),
          1.0,
          -(height(i, j + 1) - height(i, j - 1)) / (2 * cell),
        )..normalize();
        writeVertex(
          _vertices,
          c,
          Vector3(
            o.x + (i + 0.5) * cell,
            o.y + (wet ? surface[c] : _ground[c] - 0.2 * cell),
            o.z + (j + 0.5) * cell,
          ),
          normal,
          Vector4(
            (0.5 + flow[2 * c] / 8.0).clamp(0.0, 1.0),
            (0.5 + flow[2 * c + 1] / 8.0).clamp(0.0, 1.0),
            (air[c] / 0.03).clamp(0.0, 1.0),
            1.0,
          ),
          uv: (read.depth[c], 0.0),
        );
      }
    }
    return _vertices;
  }

  void _drawDrops(Float32List spray) {
    sprayInFlight = spray.length ~/ nativeSprayFloats;
    var drops = 0;
    for (var k = 0; k < sprayInFlight && drops < detail.drops; k++) {
      final o = k * nativeSprayFloats;
      if (spray[o + 9] == nativeSpraySheet) continue;
      // Too small to see is drawn at a size an eye picks out.
      final d = math.max(spray[o + 7], 0.012);
      _m
        ..setIdentity()
        ..setTranslationRaw(spray[o], spray[o + 1], spray[o + 2])
        ..scaleByDouble(d, d, d, 1.0);
      _drops.setTransform(drops++, _m);
    }
    _drops.count = drops;
  }

  void _drawSheet(Float32List spray) {
    // A row starts again where a face's number does not rise, the order
    // the core throws a step's pieces in.
    final rows = <Map<int, int>>[];
    var last = -1;
    for (var k = 0; k < sprayInFlight; k++) {
      final o = k * nativeSprayFloats;
      if (spray[o + 9] != nativeSpraySheet) continue;
      final face = spray[o + 10].round();
      if (face <= last || rows.isEmpty) rows.add(<int, int>{});
      rows.last[face] = o;
      last = face;
    }
    // The core reuses the slots of what has landed, so the rows do not come
    // out oldest last. A sheet only falls, so how high a row is says how
    // long ago it left the lip: highest first is newest first.
    double height(Map<int, int> row) =>
        row.values.fold(0.0, (sum, o) => sum + spray[o + 1]) / row.length;
    rows.sort((a, b) => height(b).compareTo(height(a)));
    final v = _sheetVertices..fillRange(0, _sheetVertices.length, 0.0);
    var quads = 0;
    final up = Vector3(0.0, 1.0, 0.0);
    Vector3 point(int o, double side) {
      final across = Vector3(
        spray[o + 3],
        spray[o + 4],
        spray[o + 5],
      ).cross(up);
      if (across.length2 < 1e-9) across.setValues(1.0, 0.0, 0.0);
      across.normalize();
      return Vector3(spray[o], spray[o + 1], spray[o + 2]) +
          across * (side * spray[o + 7]);
    }

    double apart(int a, int b) {
      final dx = spray[b] - spray[a], dy = spray[b + 1] - spray[a + 1];
      final dz = spray[b + 2] - spray[a + 2];
      return dx * dx + dy * dy + dz * dz;
    }

    // Faces side by side on a lip: faces across x are numbered one apart,
    // faces across z a row of nx + 1 apart.
    bool beside(int a, int b) => b - a == 1 || b - a == liquid.nx + 1;
    void quad(Vector3 a, Vector3 b, Vector3 c, Vector3 d, double alpha) {
      if (quads >= detail.sheet) return;
      final normal = (b - a).cross(c - a);
      if (normal.length2 < 1e-12) return;
      normal.normalize();
      final colour = Vector4(1.0, 1.0, 1.0, alpha);
      writeVertex(v, quads * 4, a, normal, colour);
      writeVertex(v, quads * 4 + 1, b, normal, colour);
      writeVertex(v, quads * 4 + 2, c, normal, colour);
      writeVertex(v, quads * 4 + 3, d, normal, colour);
      quads++;
    }

    // Thick water is white; a few millimetres shows through.
    double alphaOf(int o) => (spray[o + 8] / 0.01).clamp(0.25, 0.9);
    // Two rows a step apart are a step's fall apart, and two faces of a row
    // a face apart: a metre between them is a tear, not a sheet.
    const torn = 1.0;
    for (var r = 0; r + 1 < rows.length; r++) {
      final now = rows[r], next = rows[r + 1];
      final faces = now.keys.where(next.containsKey).toList()..sort();
      for (var i = 0; i < faces.length; i++) {
        final f = faces[i];
        final a = now[f]!, b = next[f]!;
        if (apart(a, b) > torn) continue;
        final alpha = alphaOf(a);
        final left = i == 0 || !beside(faces[i - 1], f);
        final right = i == faces.length - 1 || !beside(f, faces[i + 1]);
        if (left) {
          quad(
            point(a, -0.5),
            point(a, 0.0),
            point(b, -0.5),
            point(b, 0.0),
            alpha,
          );
        }
        if (right) {
          quad(
            point(a, 0.0),
            point(a, 0.5),
            point(b, 0.0),
            point(b, 0.5),
            alpha,
          );
        } else {
          final g = faces[i + 1];
          if (apart(a, now[g]!) > torn) continue;
          quad(
            point(a, 0.0),
            point(now[g]!, 0.0),
            point(b, 0.0),
            point(next[g]!, 0.0),
            alpha,
          );
        }
      }
    }
    sheetQuads = quads;
    _sheet.overwriteVertices(_device, 0, v.buffer.asByteData());
    sheetNode.markBoundsDirty();
  }

  void _drawBubbles(Float32List bubbles) {
    bubbleClouds = bubbles.length ~/ nativeBubbleFloats;
    final drawn = math.min(bubbleClouds, detail.bubbles);
    for (var k = 0; k < drawn; k++) {
      final o = k * nativeBubbleFloats;
      _m
        ..setIdentity()
        ..setTranslationRaw(bubbles[o], bubbles[o + 1], bubbles[o + 2]);
      _bubbles.setTransform(k, _m);
    }
    _bubbles.count = drawn;
  }
}
