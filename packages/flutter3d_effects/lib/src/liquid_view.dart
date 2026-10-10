/// One shallow liquid of the physics core, drawn: its surface, the sheet it throws
/// off a lip, the drops that sheet breaks into and the splashes, and the
/// bubbles it drags down.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_elements/flutter3d_elements.dart' show LiquidSteps;
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart'
    show
        NativeLiquidProperties,
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

/// Mist where falling water lands — [LiquidView.mist].
///
/// [shareAt] the speed it lands at, of the mass that lands goes up as
/// droplets [droplet] m across; how much light a cloud of them stops
/// follows from that: over a length L of cloud holding w kg of water a
/// cubic metre it lets through e^(−βL), β = 3w / (2ρr) for drops much
/// larger than light's wavelength, whose extinction efficiency is two (van
/// de Hulst, Light Scattering by Small Particles, 1957).
///
/// The share is the airborne fraction measured off falling water: three
/// times DOE-HDBK-3010's 8.9·10⁻¹⁰·Ar^0.55, the handbook's own bound for
/// water-like spills, at the height a free fall lands at that speed from.
/// That is 3·10⁻⁴ at 10 m/s, what lands clear of a plunge pool measured
/// as (Sun and colleagues, 2023; Liu and colleagues, 2020), and rises as
/// the speed to the 3.3; no more than 1.5 %, the most of a jet the flood
/// spray models turn to spray (`doc/mist_share.md`).
final class MistSettings {
  const MistSettings({this.share, this.droplet = 14.8e-6});

  /// A copy with the given fields replaced. A `clear…` flag resets that
  /// nullable field to null, which passing null cannot say.
  MistSettings copyWith({
    double? share,
    double? droplet,
    bool clearShare = false,
  }) => MistSettings(
    share: clearShare ? null : (share ?? this.share),
    droplet: droplet ?? this.droplet,
  );

  /// The share of the mass of falling water landing on the liquid that goes
  /// up as mist, whatever its speed; null for [shareAt]'s law.
  final double? share;

  /// The mist's droplets' diameter, in metres: the Sauter mean of what a spill of
  /// water throws into the air, 27 µm by mass with a geometric spread of
  /// 3.0 (DOE-HDBK-3010-94, table 3-7), 27·e^(−½ ln²3) — what stops light
  /// for its mass (`doc/mist_share.md`).
  final double droplet;

  /// The share of water landing at [speed] m/s that goes up as mist:
  /// [share] when one is given, else the law above, under the world's
  /// gravity [g] and of a liquid of [viscosity] — see [mistShare].
  double shareAt(
    double speed, {

    /// The world's gravity, in metres per second squared.
    double g = standardGravity,
    double? viscosity,
  }) => share ?? mistShare(speed, g: g, viscosity: viscosity);
}

/// The airborne share of a liquid landing at [speed] m/s
/// (`doc/mist_share.md`): 3 × 8.9·10⁻¹⁰ Ar^0.55, Ar = ρ_a² g H³ / μ², H
/// = v² / 2g; at most 0.015.
///
/// **g is the world's and μ the liquid's** — [g] a [LiquidView] reads off
/// its world, [viscosity] off the liquid's preset, water's
/// ([NativeLiquidProperties.water], 1.0 mPa s) when none is given: on the
/// Moon a fall lands slower from the same height and throws up less. ρ_a is
/// not the world's: it is the 1.2 kg/m³ the handbook's correlation was
/// fitted in (DOE-HDBK-3010-94, eq. 3-13), part of the fit rather than of
/// any air the water falls through.
double mistShare(
  double speed, {

  /// The world's gravity, in metres per second squared.
  double g = standardGravity,
  double? viscosity,
}) {
  const air = 1.2;
  final mu = viscosity ?? NativeLiquidProperties.water.viscosity;
  final fall = speed * speed / (2.0 * g);
  final archimedes = air * air * g * fall * fall * fall / (mu * mu);
  return math.min(3.0 * 8.9e-10 * math.pow(archimedes, 0.55), 0.015);
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
/// plunging whole into water or fraying through where the core parts it.
///
/// **Spray is drawn as the light it stops.** The drops the sheet parts
/// into, the [mist] they raise where they come down on the water and the
/// bubbles a plunge drives down are each drawn with that look too, as
/// clouds as deep as their drops' extinction makes them ([dropShadow]),
/// so a broken strand falls on as a veil.
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
    required RenderMaterial look,
    this.detail = LiquidDetail.full,
    this.mist,
    NativeLiquidProperties? properties,
  }) : properties = properties ?? NativeLiquidProperties.water,
       _device = device,
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
    _mistNode = InstancedMeshNode(
      DeviceMesh.upload(
        device,
        const SphereShape(radius: 1.0, segments: 10, rings: 6).build(),
      ),
      look,
      capacity: math.max(detail.drops ~/ 3, 1),
      name: 'mist',
    )..castsShadow = false;
    // Drops are drawn as the mist is, a cloud as thick as they make it:
    // millimetre drops a few metres off are far under a pixel, and what an
    // eye sees of a falls' spray is the veil they make together.
    _drops = InstancedMeshNode(
      DeviceMesh.upload(
        device,
        const SphereShape(radius: 1.0, segments: 8, rings: 5).build(),
      ),
      look,
      capacity: detail.drops,
      name: 'drops',
    )..castsShadow = false;
    _bubbles = InstancedMeshNode(
      DeviceMesh.upload(
        device,
        const SphereShape(radius: 1.0, segments: 8, rings: 5).build(),
      ),
      look,
      capacity: detail.bubbles,
      name: 'bubbles',
    )..castsShadow = false;
    scene
      ..add(surfaceNode)
      ..add(sheetNode)
      ..add(_drops)
      ..add(_bubbles);
    if (mist != null) scene.add(_mistNode);
  }

  final NativeWorld _world;
  final GraphicsDevice _device;

  /// The liquid drawn.
  final NativeShallowLiquid liquid;

  /// How much of its falling water is drawn at most.
  final LiquidDetail detail;

  /// The mist where its falling water lands; none for null.
  final MistSettings? mist;

  /// What the liquid drawn is: the density that weighs a cubic metre of it
  /// thrown up as mist, the viscosity [MistSettings.shareAt] reads. The
  /// liquid's own preset, as it was given to the world;
  /// [NativeLiquidProperties.water] when none is said.
  final NativeLiquidProperties properties;

  final List<double> _ground;
  late final Float32List _vertices;
  late final DeviceMesh _surface;
  late final Float32List _sheetVertices;
  late final DeviceMesh _sheet;
  late final InstancedMeshNode _drops, _mistNode, _bubbles;
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

  /// The falling sheet's vertices as the last [update] wrote them, four a
  /// quad, [sheetQuads] of them.
  Float32List get sheetVertices => _sheetVertices;

  /// The ground under it changed — dug, built on — as the core's
  /// `setShallowGround` was told.
  set ground(List<double> heights) {
    _ground.setAll(0, heights);
    _stale = true;
  }

  /// Every node it draws with.
  List<SceneNode> get nodes => <SceneNode>[
    surfaceNode,
    sheetNode,
    _drops,
    _mistNode,
    _bubbles,
  ];

  /// Its nodes taken out of the scene they are in.
  void dispose() {
    for (final node in nodes) {
      node.removeFromParent();
    }
  }

  /// Which of its steps the view takes ([LiquidSteps]).
  LiquidSteps steps = LiquidSteps.all;

  /// What each step wanted to draw this frame and how much it holds: the
  /// pieces of drops in the air and the clouds of bubbles past what the
  /// detail draws.
  List<(String, int, int)> get wanted => <(String, int, int)>[
    ('drops', sprayInFlight, detail.drops),
    ('bubbles', bubbleClouds, detail.bubbles),
  ];

  /// Whether what was last drawn may no longer be what the core has.
  bool _stale = true;

  /// Everything brought up to date with the world as it stands, [dt]
  /// seconds after the last time: how far the mist off a falls has drifted
  /// and thinned, which a step at sixty a second assumes when not told.
  void update([double dt = 1.0 / 60.0]) {
    // Water the core lets rest, with nothing in the air over it, is as it
    // was last drawn.
    final resting = _world.shallowInfoOf(liquid).resting;
    if (resting &&
        !_stale &&
        sprayInFlight == 0 &&
        bubbleClouds == 0 &&
        _puffs.isEmpty) {
      return;
    }
    _stale = !resting;
    final bubbles = _world.readBubbles(of: liquid);
    surfaceNode.isVisible = steps.surface;
    if (steps.surface) {
      _surface.overwriteVertices(
        _device,
        0,
        _writeSurface(bubbles).buffer.asByteData(),
      );
      surfaceNode.markBoundsDirty();
    }
    final spray = _world.readSpray(
      capacity: detail.sheet + detail.drops,
      of: liquid,
    );
    // Drops and the mist where they land come of the same pieces.
    if (steps.drops || steps.mist) {
      _drawDrops(spray, dt);
    } else {
      _puffs.clear();
    }
    if (!steps.drops) _drops.count = 0;
    if (!steps.mist) {
      _puffs.clear();
      _mistNode.count = 0;
    }
    sheetNode.isVisible = steps.sheet;
    if (steps.sheet) _drawSheet(spray, dt);
    if (steps.bubbles) {
      _drawBubbles(bubbles);
    } else {
      _bubbles.count = 0;
    }
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

    // Written straight into the vertices, as `writeVertex` lays them out: a
    // river keeps tens of thousands of cells, and three small objects a
    // cell a frame were most of what drawing it cost.
    final v = _vertices;
    for (var j = 0; j < nz; j++) {
      for (var i = 0; i < nx; i++) {
        final c = i + j * nx;
        final sunk = _drawn[c].isNaN;
        var gx = 0.0, gz = 0.0;
        if (!sunk) {
          gx = -(height(c, i + 1, j) - height(c, i - 1, j)) / (2 * cell);
          gz = -(height(c, i, j + 1) - height(c, i, j - 1)) / (2 * cell);
        }
        final unit = 1.0 / math.sqrt(gx * gx + 1.0 + gz * gz);
        final k = c * vertexFloats;
        v[k] = o.x + (i + 0.5) * cell;
        v[k + 1] = o.y + (sunk ? _ground[c] - 0.2 * cell : _drawn[c]);
        v[k + 2] = o.z + (j + 0.5) * cell;
        v[k + 3] = gx * unit;
        v[k + 4] = unit;
        v[k + 5] = gz * unit;
        v[k + 6] = _edge(c, depth[c]);
        v[k + 7] = 0.0;
        v[k + 8] = 1.0;
        v[k + 9] = 0.0;
        v[k + 10] = 0.0;
        v[k + 11] = 1.0;
        v[k + 12] = 0.5 + flow[2 * c] / 8.0;
        v[k + 13] = 0.5 + flow[2 * c + 1] / 8.0;
        v[k + 14] = (air[c] / 0.03).clamp(0.0, 1.0);
        v[k + 15] = 1.0;
      }
    }
    return v;
  }

  /// The light [volume] m³ of water in drops [diameter] m across stops,
  /// m²: N drops of radius r each stop Q times their cross-section, N·πr²
  /// = 3V / (4r) in all, Q by van de Hulst's anomalous diffraction, 2 −
  /// (4/ρ)·sin ρ + (4/ρ²)(1 − cos ρ), ρ = 2πd(n − 1)/λ, at green light,
  /// 550 nm, and water's n = 1.333 (van de Hulst, Light Scattering by
  /// Small Particles, 1957): twice their cross-section for drops much
  /// larger than the light's wavelength, as rain and spray are, and next
  /// to nothing for drops much smaller. Over a cloud spread round its
  /// middle as a cloud of drops thrown with a scatter of speeds spreads,
  /// normally, σ either way, the optical depth through its middle is that
  /// over 2πσ² ([cloudDepth]).
  static double dropShadow({required double volume, required double diameter}) {
    if (!(diameter > 0.0) || !(volume > 0.0)) return 0.0;
    final rho = 2.0 * math.pi * diameter * 0.333 / 550e-9;
    // Below a hundredth, the series' first term, ρ²/2, as the closed form
    // loses its digits there.
    final q = rho < 1e-2
        ? 0.5 * rho * rho
        : 2.0 -
              4.0 / rho * math.sin(rho) +
              4.0 / (rho * rho) * (1.0 - math.cos(rho));
    return q * 3.0 * volume / (2.0 * diameter);
  }

  /// The optical depth through the middle of a cloud stopping [shadow] m²
  /// of light, spread normally [spread] m either way.
  static double cloudDepth(double shadow, double spread) =>
      spread <= 0.0 ? 0.0 : shadow / (2.0 * math.pi * spread * spread);

  /// [_m] set to a cloud at [x], [y], [z] spread [spread] m either way,
  /// [depth] through its middle, and what the look is told of it: a sphere
  /// out to as many spreads, three at the least, as it takes for the cloud
  /// to stop under a hundredth of the light there, e^(−R²/2)·τ = 0.01, so
  /// that even a thick cloud thins to nothing at the sphere's rim and is
  /// not cut off by it; the depth through the middle, and that many
  /// spreads.
  Vector4 _cloud(double x, double y, double z, double spread, double depth) {
    final reach = math.max(
      3.0,
      math.sqrt(2.0 * math.log(math.max(100.0 * depth, 1.0))),
    );
    final r = reach * spread;
    _m
      ..setIdentity()
      ..setTranslationRaw(x, y, z)
      ..scaleByDouble(r, r, r, 1.0);
    return Vector4(depth, reach, 0.0, 1.0);
  }

  void _drawDrops(Float32List spray, double dt) {
    sprayInFlight = spray.length ~/ nativeSprayFloats;
    var drops = 0;
    final cell = liquid.cell;
    final mist = this.mist;
    // The world's pull and the liquid's own make-up, read once a frame
    // rather than a drop at a time.
    final g = _world.gravityMagnitude;
    final density = properties.density, viscosity = properties.viscosity;
    for (var k = 0; k < sprayInFlight; k++) {
      final o = k * nativeSprayFloats;
      final sheet = spray[o + 9] == nativeSpraySheet;
      if (!sheet && drops < detail.drops) {
        // A piece of drops is what one face of a lip, or one cell's
        // splash, threw in a step: drawn as a cloud spread over a cell
        // across and as far as it flies in a step, so the clouds thrown
        // side by side and one after another add up to an even veil, as
        // thick as its drops make it. Where the sheet broke, its strand
        // goes on falling as a veil of its own drops, not as a few beads.
        final speed = math.sqrt(
          spray[o + 3] * spray[o + 3] +
              spray[o + 4] * spray[o + 4] +
              spray[o + 5] * spray[o + 5],
        );
        final spread = 0.5 * math.max(cell, speed * dt);
        final shadow = dropShadow(volume: spray[o + 6], diameter: spray[o + 7]);
        final cloud = _cloud(
          spray[o],
          spray[o + 1],
          spray[o + 2],
          spread,
          cloudDepth(shadow, spread),
        );
        _drops
          ..setTransform(drops, _m)
          ..setInstanceData(drops, cloud);
        drops++;
      }
      // Where drops come down on the water, a puff of mist goes up with
      // the mist's share of the water they bring at the speed they bring
      // it — more the farther they fell — as wide as the face they
      // fell from: a plume along the line they land on, thick where most
      // comes down, faint over a lone splash. A sheet plunging into water
      // deeper than it is thick goes in whole, the core says, and drives
      // air down instead of throwing spray up.
      if (sheet ||
          mist == null ||
          _puffs.length >= _mistNode.capacity ||
          !_landing(spray, o, dt, onWater: true)) {
        continue;
      }
      // The air the falling drops drag down with them turns where they
      // land and runs out over the water the way they were going over the
      // ground — a falls' drops forward off its foot, a splash's crown out
      // all round — so the mist is carried off in billows along the pool,
      // not heaped on it; straight down, it runs out any way. Slowed by
      // the air.
      final speed = math.sqrt(
        spray[o + 3] * spray[o + 3] +
            spray[o + 4] * spray[o + 4] +
            spray[o + 5] * spray[o + 5],
      );
      final level = math.sqrt(
        spray[o + 3] * spray[o + 3] + spray[o + 5] * spray[o + 5],
      );
      final heading = level > 1e-3
          ? math.atan2(spray[o + 5], spray[o + 3])
          : 2.0 * math.pi * _hash(k + 7);
      final out = 0.15 * speed;
      _puffs.add(
        _Puff(
          Vector3(spray[o], spray[o + 1], spray[o + 2]),
          Vector3(out * math.cos(heading), 0.0, out * math.sin(heading)),
          0.5 * cell * (1.0 + _hash(k)),
          mist.shareAt(speed, g: g, viscosity: viscosity) *
              density *
              spray[o + 6],
        ),
      );
    }
    _drops.count = drops;
    _drawMist(dt);
  }

  /// Whether piece [o] of [spray] comes down within the next [dt] seconds
  /// on the water drawn under it — or, unless [onWater], on the ground
  /// where there is none. It must be coming down onto it: a drop thrown
  /// off a lip flies over the water it left, but has not landed on it;
  /// below the surface of the cell it is over, it is falling past a cliff
  /// whose top is wet.
  bool _landing(Float32List spray, int o, double dt, {bool onWater = false}) {
    final i = ((spray[o] - liquid.origin.x) / liquid.cell).floor();
    final j = ((spray[o + 2] - liquid.origin.z) / liquid.cell).floor();
    if (i < 0 || j < 0 || i >= liquid.nx || j >= liquid.nz) return false;
    final c = i + j * liquid.nx;
    final water = _drawn[c];
    if (onWater && water.isNaN) return false;
    final over =
        spray[o + 1] - liquid.origin.y - (water.isNaN ? _ground[c] : water);
    final falling = -spray[o + 4];
    return falling > 0.0 && over <= falling * dt && over >= -0.3 * liquid.cell;
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
      // Spread as far either way as half its size, which grows as it
      // hangs; as much as its droplets stop through its middle, come in
      // over its first moments and gone over its last.
      final spread = 0.5 * p.size * (1.0 + 2.2 * t);
      final shadow = dropShadow(
        volume: p.kilograms / properties.density,
        diameter: this.mist!.droplet,
      );
      final cloud = _cloud(
        p.at.x,
        p.at.y,
        p.at.z,
        spread,
        cloudDepth(shadow, spread) *
            _smooth(0.0, 0.15, t) *
            (1.0 - _smooth(0.8, 1.0, t)),
      );
      _mistNode
        ..setTransform(mist, _m)
        ..setInstanceData(mist, cloud);
      mist++;
      return false;
    });
    _mistNode.count = mist;
  }

  void _drawSheet(Float32List spray, double dt) {
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
    // Rows are a step apart, so how many rows a piece is under its face's
    // lip is how many steps ago it left it.
    final lip = <int, double>{}, lipRow = <int, int>{}, footRow = <int, int>{};
    final footAt = <int, int>{};
    final broken = <int>{};
    for (var r = 0; r < rows.length; r++) {
      for (final MapEntry(key: face, value: o) in rows[r].entries) {
        lip.putIfAbsent(face, () => spray[o + 1]);
        lipRow.putIfAbsent(face, () => r);
        if (broken.contains(face)) continue;
        final above = r == 0 ? null : rows[r - 1][face];
        if (above == null) continue;
        if (apart(above, o) <= torn) {
          footRow[face] = r;
          footAt[face] = o;
        } else {
          broken.add(face);
        }
      }
    }
    // A strand whose foot is about to land — on the water, or the ground
    // where there is none — plunges whole, as a falls of a few metres
    // does. One whose foot is still in the air ends where the core broke
    // its next piece into drops: the ripples on it grow an e-fold each
    // Weber time, and twelve part it (Grant and Middleman), so it is
    // holed through, and frays, over the last of the twelve, the last
    // twelfth of the time its foot has fallen; then the veil of its drops
    // goes on below it.
    final plunges = <int>{
      for (final MapEntry(key: face, value: o) in footAt.entries)
        if (_landing(spray, o, dt)) face,
    };
    double fray(int face, int r) {
      final age = (footRow[face] ?? 0) - (lipRow[face] ?? 0);
      if (plunges.contains(face) || age <= 0) return 0.0;
      final s = r - lipRow[face]!;
      return ((s - age * 11.0 / 12.0) / (age / 12.0)).clamp(0.0, 1.0);
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
          corner.color,
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
    // through its fraying the strand is there, nought above its last
    // e-fold and one where it parts, and its green how thick the water
    // is, three centimetres and more counting as one. Its alpha is what
    // the sheet's outline leaves: its edges thin to nothing over half a
    // face, not a cut ribbon, and it is gone where the strand parts.
    _SheetCorner piece(int o, int face, int r, double side) {
      final at = point(o, side);
      final top = lip[face] ?? at.y;
      final frayed = fray(face, r);
      final thick = (spray[o + 8] / 0.03).clamp(0.0, 1.0);
      final edge = 1.0 - _smooth(0.2, 0.5, side.abs());
      return (
        at: at,
        color: Vector4(frayed, thick, 0.0, (1.0 - frayed) * edge),
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
            piece(a, f, r, -0.5),
            piece(a, f, r, 0.0),
            piece(b, f, r + 1, -0.5),
            piece(b, f, r + 1, 0.0),
          );
        }
        if (right) {
          quad(
            piece(a, f, r, 0.0),
            piece(a, f, r, 0.5),
            piece(b, f, r + 1, 0.0),
            piece(b, f, r + 1, 0.5),
          );
        } else {
          final g = faces[i + 1];
          if (apart(a, now[g]!) > torn) continue;
          quad(
            piece(a, f, r, 0.0),
            piece(now[g]!, g, r, 0.0),
            piece(b, f, r + 1, 0.0),
            piece(next[g]!, g, r + 1, 0.0),
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
    // A cloud of bubbles stops light as a cloud of drops does, each
    // bubble twice its cross-section: what a plunging sheet drags down in
    // a step under a cell, spread over that cell — but no further than
    // keeps it under the surface, which it is gone at — white under the
    // water where much air is driven in and gone where little is.
    final cell = liquid.cell;
    for (var k = 0; k < drawn; k++) {
      final o = k * nativeBubbleFloats;
      final i = ((bubbles[o] - liquid.origin.x) / cell).floor();
      final j = ((bubbles[o + 2] - liquid.origin.z) / cell).floor();
      final inside = i >= 0 && j >= 0 && i < liquid.nx && j < liquid.nz;
      final surface = inside ? _drawn[i + j * liquid.nx] : double.nan;
      final under = surface.isNaN
          ? 0.0
          : liquid.origin.y + surface - bubbles[o + 1];
      final shadow = under > 0.0
          ? dropShadow(volume: bubbles[o + 4], diameter: 2.0 * bubbles[o + 3])
          : 0.0;
      // Drawn as far round as it takes to thin out, that far under: a
      // narrower cloud is deeper and takes more spreads to thin out, so
      // the two are settled together.
      var spread = math.max(math.min(0.5 * cell, under / 3.0), 1e-6);
      for (var settle = 0; settle < 8; settle++) {
        final reach = _cloud(0, 0, 0, spread, cloudDepth(shadow, spread)).y;
        if (reach * spread <= under) break;
        spread = math.max(under / reach, 1e-6);
      }
      final cloud = _cloud(
        bubbles[o],
        bubbles[o + 1],
        bubbles[o + 2],
        spread,
        cloudDepth(shadow, spread),
      );
      _bubbles
        ..setTransform(k, _m)
        ..setInstanceData(k, cloud);
    }
    _bubbles.count = drawn;
  }
}

/// A corner of the falling sheet: where it is, and what the look is told
/// of it.
typedef _SheetCorner = ({Vector3 at, Vector4 color, (double, double) uv});

/// A puff of mist off falling water landing: where it is, how it drifts,
/// how big it began, the water it holds and how long it has hung in the
/// air.
final class _Puff {
  _Puff(this.at, this.drift, this.size, this.kilograms);

  /// Seconds a puff hangs before it has thinned away.
  static const double life = 1.6;

  final Vector3 at, drift;

  /// How big it began, in metres.
  final double size;

  /// The water it holds as droplets, kg.
  final double kilograms;

  /// How long it has hung in the air, in seconds.
  double age = 0.0;
}
