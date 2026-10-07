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
/// the core says. A dry cell at the shore is drawn level with the water
/// beside it, so the water runs flat into the bank and ends where it meets
/// the ground, not in a wedge slanting down to the cell's ground; a dry
/// cell away from water sinks under the ground and is not seen. Each vertex
/// tells the material what the material cannot see: the flow, x and z, as
/// 0.5 + velocity / 8 in its colour's red and green; the froth in its blue
/// — the share of the column that is air over three hundredths, water being
/// white where it is a few parts in a hundred air, however fast it runs;
/// and in its texture coordinates the depth, and where the water ends.
///
/// **A sheet off a lip is one sheet.** What the lip's faces threw in one
/// step is a row across it, and each row is sewn to the one thrown before
/// it, face to face, and to its neighbours along the lip; the sheet's edges
/// stand half a face out. It is drawn with the surface's look, which its vertices
/// tell what it is: clear at the lip, streaked and whitening as it falls,
/// fraying apart at its foot. Where the drops come down on the water they
/// raise a mist, drawn with that look as well.
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
    // The sheet and the mist are drawn with the surface's own look, which
    // tells them apart by what their vertices and instances carry.
    sheetNode = MeshNode(_sheet, look, name: 'falling water')
      ..castsShadow = false;
    _mist = InstancedMeshNode(
      DeviceMesh.upload(
        device,
        const SphereShape(radius: 1.0, segments: 10, rings: 6).build(),
      ),
      look,
      capacity: math.max(detail.drops ~/ 3, 1),
      name: 'mist',
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
      ..add(_mist)
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
  late final InstancedMeshNode _drops, _mist, _bubbles;
  final List<_Puff> _puffs = <_Puff>[];
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

  /// Everything brought up to date with the world as it stands, [dt]
  /// seconds after the last time: how far the mist off a falls has drifted
  /// and thinned, which a step at sixty a second assumes when not told.
  void update([double dt = 1.0 / 60.0]) {
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
    _drawDrops(spray, dt);
    _drawSheet(spray);
    _drawBubbles(bubbles);
  }

  /// How much of each column is air, of the bubbles in it, spread over the
  /// column's neighbours as a cloud spreads: two cells out, thinning with
  /// distance by the binomial 1 4 6 4 1, so a falls' froth is a round
  /// plume that fades into the pool, not a square of cells.
  Float64List _airIn(Float32List bubbles, Float32List depth) {
    final nx = liquid.nx, nz = liquid.nz, cell = liquid.cell;
    final air = Float64List(liquid.cells);
    const spread = <double>[1.0, 4.0, 6.0, 4.0, 1.0];
    for (var o = 0; o < bubbles.length; o += nativeBubbleFloats) {
      final i = ((bubbles[o] - liquid.origin.x) / cell).floor();
      final j = ((bubbles[o + 2] - liquid.origin.z) / cell).floor();
      for (var dj = -2; dj <= 2; dj++) {
        for (var di = -2; di <= 2; di++) {
          final (x, z) = (i + di, j + dj);
          if (x < 0 || z < 0 || x >= nx || z >= nz) continue;
          air[x + z * nx] +=
              bubbles[o + 4] * spread[di + 2] * spread[dj + 2] / 256.0;
        }
      }
    }
    // A cloud spread onto a film at the shore is not a white column: the
    // share is of a column at least five centimetres deep.
    for (var c = 0; c < air.length; c++) {
      air[c] = depth[c] > _wet
          ? air[c] / (math.max(depth[c], 0.05) * cell * cell)
          : 0.0;
    }
    return air;
  }

  /// Shallower than this, m, a cell is drawn dry.
  static const double _wet = 0.004;

  /// Two neighbouring surfaces further apart than this, in cells, are not
  /// one surface but water falling from one to the other, which the
  /// falling sheet draws.
  static const double _fall = 0.4;

  /// A wet cell whose ground stands over the surface of water beside it by
  /// more than this, in cells, is perched on a step over that water.
  static const double _perch = 0.15;

  /// The height each vertex is drawn at over the origin, NaN where it is
  /// sunk under its ground: rewritten with the surface.
  late final Float64List _drawn = Float64List(liquid.cells);

  /// Whether each vertex is drawn as the water of its own cell, not as the
  /// edge of its neighbours': rewritten with the surface.
  late final Uint8List _standing = Uint8List(liquid.cells);

  /// How far under nought the material is told the depth is at a bank
  /// vertex the water stands over: as deep as the water it is drawn level
  /// with stands in the wet cells round it, at least two centimetres, and
  /// less the more of the cells round it are wet, so the water reaches
  /// further into a bay of wet cells than past a lone corner of one and
  /// its edge is rounded, not stepped cell by cell. Rewritten with the
  /// surface.
  late final Float64List _beside = Float64List(liquid.cells);

  /// Where each vertex is drawn: a wet cell at its own surface; a dry one
  /// beside water at the mean surface of the wet cells round it, so the
  /// triangles between them lie level, as the water does, and run into the
  /// bank or out over the drop instead of slanting down to the ground in a
  /// wedge; a dry one with no water near sunk under its ground.
  ///
  /// A wet cell beside water lower than itself by more than [_fall] of a
  /// cell — a film on a step over a pond, the lip of a falls — is drawn as
  /// the lower water's bank, as a dry cell would be: a triangle from it down
  /// to the water below would be a wall of water standing across the step.
  /// The water above then ends where its surface meets its ground, short of
  /// the lip, and the lower water runs into the step. Of the wet cells round
  /// a vertex, only those level with the lowest of them are averaged, for
  /// the same reason.
  ///
  /// So is a wet cell whose ground stands over the surface of water beside
  /// it by [_perch] of a cell: on ground in steps — voxels a cell high — a
  /// film on a step over a pond three quarters of a cell deep is only a
  /// quarter of a cell above the pond, but it stands on ground over the
  /// pond's surface, and a triangle between them is a slanting sheet across
  /// the step's face. Down a slope, or across a river from its shallow side
  /// to its deep middle, the ground runs under the water beside it, and
  /// nothing is cut.
  void _drawHeights(Float32List surface, Float32List depth) {
    final nx = liquid.nx, nz = liquid.nz;
    final fall = _fall * liquid.cell, perch = _perch * liquid.cell;
    for (var j = 0; j < nz; j++) {
      for (var i = 0; i < nx; i++) {
        final c = i + j * nx;
        final (z0, z1) = (math.max(j - 1, 0), math.min(j + 1, nz - 1));
        final (x0, x1) = (math.max(i - 1, 0), math.min(i + 1, nx - 1));
        final wetHere = depth[c] > _wet;
        var lowest = double.infinity;
        var perched = false;
        for (var z = z0; z <= z1; z++) {
          for (var x = x0; x <= x1; x++) {
            final n = x + z * nx;
            if (depth[n] <= _wet) continue;
            lowest = math.min(lowest, surface[n]);
            perched = perched || (wetHere && _ground[c] - surface[n] > perch);
          }
        }
        final standing = wetHere && !perched && surface[c] <= lowest + fall;
        _standing[c] = standing ? 1 : 0;
        if (standing) {
          _drawn[c] = surface[c];
          continue;
        }
        // The water this vertex is the bank of: below the cell's own when
        // it is perched over it, else level with the lowest round it.
        final top = perched ? _ground[c] - perch : lowest + fall;
        var sum = 0.0, deep = 0.0, wet = 0;
        for (var z = z0; z <= z1; z++) {
          for (var x = x0; x <= x1; x++) {
            final n = x + z * nx;
            if (depth[n] <= _wet || surface[n] > top) continue;
            sum += surface[n];
            deep += depth[n];
            wet++;
          }
        }
        _drawn[c] = wet == 0 ? double.nan : sum / wet;
        // Three wet cells along one side of it — a straight shore — end the
        // water about halfway; five, a bay, a little past; one, a corner,
        // a little short.
        _beside[c] = wet == 0
            ? 0.0
            : math.max(deep / wet, 0.02) * (1.5 - wet / 8.0);
      }
    }
  }

  /// What the material is told of where the water ends, at cell [c] of
  /// [depth], as a depth the material fades the water out by. A wet cell is
  /// told how deep it is. A cell drawn as a bank above the water is told how
  /// far over its ground the water is drawn there, under nought, so across
  /// the triangle from the last wet cell the depth passes nought where the
  /// water meets the ground, and the water ends at that line, not where its
  /// cells stop. A dry cell the water stands over — a drop, or a flat shore
  /// the flow has not wetted — is told [_beside]: deep water then ends
  /// about halfway there, at the edge of the cell it stands in, and a film
  /// short of it, as the thin edge of a puddle does. A sunk cell is told
  /// nought: nothing of it is drawn.
  double _edge(int c, double depth) {
    if (_standing[c] == 1) return depth;
    final drawn = _drawn[c];
    if (drawn.isNaN) return 0.0;
    final over = drawn - _ground[c];
    return over > 0.0 ? -_beside[c] : over;
  }

  Float32List _writeSurface(Float32List bubbles) {
    final read = _world.readShallowSurface(liquid);
    final flow = _world.readShallowFlow(liquid);
    final nx = liquid.nx, nz = liquid.nz, cell = liquid.cell;
    final o = liquid.origin;
    final depth = read.depth;
    final air = _airIn(bubbles, depth);
    _drawHeights(read.surface, depth);
    // The slope is the drawn surface's: a neighbour sunk under its ground,
    // off the grid or across a fall counts as level with the cell, so the
    // water's edge is not tipped towards the bank it meets.
    final fall = _fall * cell;
    double height(int c, int i, int j) {
      if (i < 0 || j < 0 || i >= nx || j >= nz) return _drawn[c];
      final h = _drawn[i + j * nx];
      return h.isNaN || (h - _drawn[c]).abs() > fall ? _drawn[c] : h;
    }

    for (var j = 0; j < nz; j++) {
      for (var i = 0; i < nx; i++) {
        final c = i + j * nx;
        final sunk = _drawn[c].isNaN;
        final normal = sunk
            ? Vector3(0.0, 1.0, 0.0)
            : (Vector3(
                -(height(c, i + 1, j) - height(c, i - 1, j)) / (2 * cell),
                1.0,
                -(height(c, i, j + 1) - height(c, i, j - 1)) / (2 * cell),
              )..normalize());
        writeVertex(
          _vertices,
          c,
          Vector3(
            o.x + (i + 0.5) * cell,
            o.y + (sunk ? _ground[c] - 0.2 * cell : _drawn[c]),
            o.z + (j + 0.5) * cell,
          ),
          normal,
          Vector4(
            (0.5 + flow[2 * c] / 8.0).clamp(0.0, 1.0),
            (0.5 + flow[2 * c + 1] / 8.0).clamp(0.0, 1.0),
            (air[c] / 0.03).clamp(0.0, 1.0),
            1.0,
          ),
          uv: (_edge(c, depth[c]), 0.0),
        );
      }
    }
    return _vertices;
  }

  void _drawDrops(Float32List spray, double dt) {
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
      // Where it comes down on the water fast, every third drop throws up
      // a puff of mist as well: a plume over the foot of a falls, thick
      // where most comes down, faint over a lone splash.
      if (k % 3 == 0 && _puffs.length < _mist.capacity) {
        final i = ((spray[o] - liquid.origin.x) / liquid.cell).floor();
        final j = ((spray[o + 2] - liquid.origin.z) / liquid.cell).floor();
        if (i < 0 || j < 0 || i >= liquid.nx || j >= liquid.nz) continue;
        final water = _drawn[i + j * liquid.nx];
        final over = spray[o + 1] - liquid.origin.y - water;
        // Slower than a fall of a few tens of centimetres, it is a trickle
        // just leaving a lip over other water, not a landing.
        final speed2 =
            spray[o + 3] * spray[o + 3] +
            spray[o + 4] * spray[o + 4] +
            spray[o + 5] * spray[o + 5];
        // And it must be coming down: a drop thrown off a lip flies fast
        // over the water it left, but it has not landed on it.
        if (water.isNaN ||
            over > 0.6 * liquid.cell ||
            // Below the surface of the cell it is over, it is falling past
            // a cliff whose top is wet, not landing on water.
            over < -0.3 * liquid.cell ||
            speed2 < 6.0 ||
            spray[o + 4] > -2.0) {
          continue;
        }
        _puffs.add(
          _Puff(
            Vector3(spray[o], spray[o + 1], spray[o + 2]),
            // Thrown out the way the drop was going, slowed by the air.
            Vector3(spray[o + 3] * 0.15, 0.0, spray[o + 5] * 0.15),
            0.25 + 0.35 * _hash(k),
          ),
        );
      }
    }
    _drops.count = drops;
    _drawMist(dt);
  }

  /// The mist's puffs, each risen, grown, thinned and carried on by how
  /// long it has hung in the air: a churning haze that drifts off the foot
  /// of a falls and fades, rather than one cloud sitting on it.
  void _drawMist(double dt) {
    var mist = 0;
    _puffs.removeWhere((p) {
      p.age += dt;
      if (p.age >= _Puff.life) return true;
      p.at
        ..add(p.drift * dt)
        ..y += 0.45 * dt;
      p.drift.scale(1.0 - 0.8 * dt);
      final t = p.age / _Puff.life;
      final r = p.size * (1.0 + 2.2 * t);
      _m
        ..setIdentity()
        ..setTranslationRaw(p.at.x, p.at.y, p.at.z)
        ..scaleByDouble(r, r * 0.8, r, 1.0);
      // Thickest just after the landing, thinning as it spreads.
      final thick = 0.07 * (1.0 - t) * (1.0 - t) * _smooth(0.0, 0.15, t);
      _mist
        ..setTransform(mist, _m)
        ..setInstanceData(mist, Vector4(thick, 0.0, 0.0, 1.0));
      mist++;
      return false;
    });
    _mist.count = mist;
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
    // Across the fall, level: the way along the lip a piece's faces lie.
    Vector3 acrossOf(int o) {
      final across = Vector3(
        spray[o + 3],
        spray[o + 4],
        spray[o + 5],
      ).cross(up);
      if (across.length2 < 1e-9) across.setValues(1.0, 0.0, 0.0);
      return across..normalize();
    }

    Vector3 point(int o, double side) =>
        Vector3(spray[o], spray[o + 1], spray[o + 2]) +
        acrossOf(o) * (side * spray[o + 7]);

    double apart(int a, int b) {
      final dx = spray[b] - spray[a], dy = spray[b + 1] - spray[a + 1];
      final dz = spray[b + 2] - spray[a + 2];
      return dx * dx + dy * dy + dz * dz;
    }

    // How high each face's lip is, the height of the newest piece it
    // threw, and how far down its sheet is drawn, to the last piece still
    // sewn to the one above it: each face's own, so a strand of the sheet
    // that tears off short fades out at its own foot and does not end in a
    // cut edge. Two rows a step apart are a step's fall apart: a metre
    // between them is a tear, not a sheet.
    const torn = 1.0;
    // The foot is the lowest piece of the run sewn unbroken to the lip:
    // past the first tear the rest of the strand is drops, and a stretch
    // sewn together again lower down is not where this one ends.
    final lip = <int, double>{}, foot = <int, double>{};
    final broken = <int>{};
    for (var r = 0; r < rows.length; r++) {
      for (final MapEntry(key: face, value: o) in rows[r].entries) {
        lip.putIfAbsent(face, () => spray[o + 1]);
        if (broken.contains(face)) continue;
        final above = r == 0 ? null : rows[r - 1][face];
        if (above == null) continue;
        if (apart(above, o) <= torn) {
          foot[face] = math.min(foot[face] ?? spray[o + 1], spray[o + 1]);
        } else {
          broken.add(face);
        }
      }
    }

    // Faces side by side on a lip: faces across x are numbered one apart,
    // faces across z a row of nx + 1 apart.
    bool beside(int a, int b) => b - a == 1 || b - a == liquid.nx + 1;
    void quad(_SheetCorner a, _SheetCorner b, _SheetCorner c, _SheetCorner d) {
      if (quads >= detail.sheet) return;
      final normal = (b.at - a.at).cross(c.at - a.at);
      if (normal.length2 < 1e-12) return;
      normal.normalize();
      for (final (k, corner) in <_SheetCorner>[a, b, c, d].indexed) {
        writeVertex(
          v,
          quads * 4 + k,
          corner.at,
          normal,
          corner.colour,
          uv: corner.uv,
        );
      }
      quads++;
    }

    // What the look is told of a corner of the sheet, which it draws as
    // falling water by its second texture coordinate being one or more:
    // that coordinate is one plus how far under its lip the corner is, m,
    // and the first how far along the lip, m, so the look's streaks run
    // down the fall and stay with the water; the colour's red is how far
    // down its face's strand of the sheet it is, nought at the lip and one
    // at the strand's foot, and its green how thick the water is, three
    // centimetres and more counting as one. Its alpha is what the sheet's
    // outline leaves:
    // its edges thin to nothing over half a face, not a cut ribbon, and
    // its last stretch, where the core breaks it into drops, thins out.
    _SheetCorner piece(int o, int face, double side) {
      final at = point(o, side);
      final top = lip[face] ?? at.y;
      final fallen = ((top - at.y) / math.max(top - (foot[face] ?? at.y), 1e-3))
          .clamp(0.0, 1.0);
      final thick = (spray[o + 8] / 0.03).clamp(0.0, 1.0);
      final last = 1.0 - _smooth(0.5, 1.0, fallen);
      final edge = 1.0 - _smooth(0.2, 0.5, side.abs());
      return (
        at: at,
        colour: Vector4(fallen, thick, 0.0, last * edge),
        uv: (at.dot(acrossOf(o)), 1.0 + math.max(top - at.y, 0.0)),
      );
    }

    // Two faces of a row a metre apart are torn apart too.
    for (var r = 0; r + 1 < rows.length; r++) {
      final now = rows[r], next = rows[r + 1];
      final faces = now.keys.where(next.containsKey).toList()..sort();
      for (var i = 0; i < faces.length; i++) {
        final f = faces[i];
        final a = now[f]!, b = next[f]!;
        if (apart(a, b) > torn) continue;
        final left = i == 0 || !beside(faces[i - 1], f);
        final right = i == faces.length - 1 || !beside(f, faces[i + 1]);
        if (left) {
          quad(
            piece(a, f, -0.5),
            piece(a, f, 0.0),
            piece(b, f, -0.5),
            piece(b, f, 0.0),
          );
        }
        if (right) {
          quad(
            piece(a, f, 0.0),
            piece(a, f, 0.5),
            piece(b, f, 0.0),
            piece(b, f, 0.5),
          );
        } else {
          final g = faces[i + 1];
          if (apart(a, now[g]!) > torn) continue;
          quad(
            piece(a, f, 0.0),
            piece(now[g]!, g, 0.0),
            piece(b, f, 0.0),
            piece(next[g]!, g, 0.0),
          );
        }
      }
    }
    sheetQuads = quads;
    _sheet.overwriteVertices(_device, 0, v.buffer.asByteData());
    sheetNode.markBoundsDirty();
  }

  /// A number in [0, 1) that says nothing about its neighbours': the
  /// same for the same [n] every frame.
  static double _hash(int n) {
    // Integer mixing, so no platform's libm has a say in it.
    final a = (n * 0x9E3779B1) & 0xFFFFFFFF;
    final b = ((a ^ (a >> 15)) * 0x85EBCA77) & 0xFFFFFFFF;
    return (b ^ (b >> 13)) / 4294967296.0;
  }

  /// Nought below [a], one above [b], and smoothly between.
  static double _smooth(double a, double b, double x) {
    final t = ((x - a) / (b - a)).clamp(0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
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

/// A corner of the falling sheet: where it is, and what the look is told
/// of it.
typedef _SheetCorner = ({Vector3 at, Vector4 colour, (double, double) uv});

/// A puff of mist off falling water landing: where it is, how it drifts,
/// how big it began and how long it has hung in the air.
final class _Puff {
  _Puff(this.at, this.drift, this.size);

  /// Seconds a puff hangs before it has thinned away.
  static const double life = 1.6;

  final Vector3 at, drift;
  final double size;
  double age = 0.0;
}
