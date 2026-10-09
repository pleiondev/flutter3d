/// The river's own water: shallow water of the physics core over the bed the
/// course lays out, running down the valley towards the jet's tail, parting
/// round the tankers and the fuel barges, and spilling over a stone weir
/// under every bridge into a pool of white water.
///
/// **Drawn only.** The game flies over a level plane at nought, and goes on
/// doing so: nothing here is read by the run, and what moves the water is
/// read off it. The hulls in it are followed — bodies the water's world is
/// told where to be, which push the water and are never moved back — and
/// what falls in is a ball dropped where the game shows something going
/// down. Once the water is drawn the game is told so and stops drawing its
/// plane.
///
/// **Only the water in sight is there.** The river never ends, so it is cut
/// into reaches sixty metres long, a liquid apiece in one world; the reaches
/// from the bottom of the camera's picture to one past the top of it are
/// kept, and each is let go once the picture has left it behind. A reach
/// takes the river in over its upper edge and stands at the river's level at
/// its lower one, so the current runs through it as it runs through the
/// reach before. Two reaches share the row of cells where they meet, so the
/// surfaces each draws through its cells' middles meet along one line.
///
/// **The weirs are where the level is put back.** The river is level from
/// end to end and a falls has to drop somewhere. Under each bridge the reach
/// below starts on a sill, the river let in over it and pouring over its lip
/// into a scoured pool; the reach above stands at the river's level against
/// the back of the sill, where the bridge's deck hides that the water there
/// stands no higher than the pool. That is the one thing here that is not
/// what water would do: a river that falls at each weir would have to fall
/// in the game too, whose plane is level.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flame/components.dart' show Component, HasGameReference;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_effects/flutter3d_effects.dart';
import 'package:flutter3d_elements/flutter3d_elements.dart';
import 'package:flutter3d_game_physics/wrecks.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';

import 'course.dart';
import 'river_game.dart';

/// Puts [RiverWater] on the river once there is a renderer to load its look
/// with, keeps it up to date every frame, and lets it go with the game.
///
/// Added by the application, not the game: a test that mounts the game
/// alone flies over the plane it always did.
final class RiverWaterLayer extends Component with HasGameReference<RiverGame> {
  /// [light] draws less of what falls, for a phone.
  RiverWaterLayer({required this.light})
    // After everything that moves this frame — the jet, the craft, the
    // camera — so the water is put where they are now.
    : super(priority: 1000);

  final bool light;

  /// The water, once its look has loaded; null before, and where the look
  /// would not load, which leaves the river the plane it was.
  RiverWater? water;

  bool _opening = false;

  @override
  void update(double dt) {
    super.update(dt);
    final drawing = game.renderer;
    if (!game.built || drawing == null) return;
    if (water == null && !_opening) {
      _opening = true;
      unawaited(_open(drawing));
    }
    water?.update(dt);
  }

  Future<void> _open(Renderer drawing) async {
    try {
      final elements = await Elements.open(
        device: game.device,
        renderer: drawing,
        scene: game.scene,
        load: rootBundle.load,
        quality: ElementsQuality(
          liquid: light ? LiquidDetail.light : RiverWater.detail,
          fire: light ? FireDetail.light : FireDetail.full,
        ),
      );
      if (!game.has3d || isRemoved) {
        elements.dispose();
        return;
      }
      water = RiverWater(game: game, elements: elements);
      // The run's wrecks burn on the water, in its elements.
      game
        ..wrecks = BurningWrecks(elements, game.device)
        ..waterDrawnElsewhere();
    } catch (error) {
      debugPrint('river: no water material, so the plane stays ($error)');
    }
  }

  /// Everything let go, before the device it is drawn on closes.
  void close() {
    game.wrecks = null;
    water?.dispose();
    water = null;
  }

  @override
  void onRemove() {
    close();
    super.onRemove();
  }
}

/// The reaches of shallow water along the stretch of river in sight.
final class RiverWater {
  RiverWater({required RiverGame game, required this.elements})
    : _game = game,
      // A course of its own, laid out by the same seed: reading the game's
      // would lay out its stretches ahead of when the game does.
      _course = Course(seed: game.course.seed) {
    elements
      ..sun(along: -_toSun, light: _sunLight)
      ..sky(zenith: _zenith, horizon: _horizon);
  }

  final RiverGame _game;

  /// The river's world, its waters and what is followed into it.
  final Elements elements;
  final Course _course;

  /// How long a reach is, m: a third of a stretch, so the seams fall where
  /// the bridges are and no more than three are in sight between them.
  static const double reachLength = sectionLength / 3.0;

  /// A cell, m: a tanker is between five and six long.
  static const double cell = 0.6;

  /// Where the reaches start counting: the bridge before the first stretch,
  /// had it one.
  static const double _first = -bridgeInset;

  /// What runs down the river, m³/s: about a quarter of a metre a second
  /// where it is widest and close to a metre between the bridge's piers.
  static const double _flow = 3.0;

  /// The sill under a bridge: how high its top stands, how far down the
  /// river it reaches from the bridge's line, and how deep the pool scoured
  /// at its foot is and how long, m. High enough over the pool for the core
  /// to throw what goes over it as a falls, which takes a drop of more than
  /// a cell; low enough that the water on it stays under the grass.
  static const double _sillTop = 0.52, _sillLength = 1.5;
  static const double _poolDepth = -0.7, _poolLength = 1.5;

  /// How much of a reach's falling water is drawn on a desktop: a weir's,
  /// and a reach with no weir, where nothing falls but the splash of a hull
  /// going down.
  static const LiquidDetail detail = LiquidDetail(
    sheet: 1500,
    drops: 900,
    bubbles: 1500,
  );
  static const LiquidDetail _plainDetail = LiquidDetail(
    sheet: 8,
    drops: 150,
    bubbles: 150,
  );

  /// A lowland river: green-brown and cloudy, so the bed under it reads as
  /// depth rather than as a floor — about a twenty-fifth of the light left
  /// through a metre of it.
  static final Liquid _river = Liquid.water().copyWith(
    optics: LiquidOptics(
      absorb: Vector3.all(3.219),
      backscatter: Vector3(0.06569, 0.2799, 0.481),
    ),
  );

  /// Towards the sun and its light, and the sky the game clears to, a little
  /// deeper overhead, for the water to mirror.
  static Vector3 get _toSun => Vector3(0.35, 1.0, 0.45)..normalize();
  static Vector3 get _sunLight => Vector3(2.4, 2.34, 2.2);
  static Vector3 get _zenith => Vector3(0.2, 0.38, 0.72);
  static Vector3 get _horizon => Vector3(0.27, 0.48, 0.78);

  /// The stone the sills are built of.
  final RenderMaterial _stone = RenderMaterial(
    name: 'weir',
    baseColor: LinearColor.fromSrgb(0.33, 0.31, 0.27, 1.0),
    roughness: 0.95,
  );

  final Map<int, _Reach> _reaches = <int, _Reach>{};
  final Map<TargetComponent, Follower> _hulls = <TargetComponent, Follower>{};
  final List<_Plunge> _plunges = <_Plunge>[];

  /// Each helicopter going down, where it was last seen: it falls into the
  /// river the frame it is gone.
  final Map<TargetComponent, Vector3> _falling = <TargetComponent, Vector3>{};

  /// Each bridge broken, and how long ago: its halves reach the water a
  /// little after.
  final Map<BridgeComponent, double> _broken = <BridgeComponent, double>{};
  bool _jetDown = false;

  int _reachAt(double distance) => ((distance - _first) / reachLength).floor();

  /// Everything brought up to date [dt] seconds on.
  void update(double dt) {
    final step = math.min(dt, 1.0 / 30.0);
    if (step <= 0.0) return;
    final (:near, :far) = seen(_game.camera3d);
    // And the reach past the top of the picture: each has run for as long
    // as the jet takes to fly a reach, at least two seconds at full speed,
    // before it comes into sight.
    _cover(_reachAt(near), _reachAt(far) + 1);
    _wade();
    _plunge(step);
    elements.update(step, eye: _game.chase.rig.eye);
  }

  /// How far down and up the river [camera] sees the water: where the
  /// bottom and the top of its picture meet the water's level, nought, as
  /// distances along the river. Where the top of the picture is over the
  /// horizon, as far as the haze or the camera's far plane lets it see.
  static ({double near, double far}) seen(CameraNode camera) {
    final eye = camera.readViewOrigin();
    final forward = camera.readForward();
    final m = camera.worldMatrix.storage;
    final up = Vector3(m[4], m[5], m[6])..normalize();
    final projection = camera.projection;
    final half = (projection.verticalFieldOfView ?? math.pi / 2.0) / 2.0;
    final reach = math.min(RiverGame.seenThroughHaze, projection.far);
    double along(double side) {
      final ray = forward + up.scaled(side * math.tan(half));
      final level = ray.y < -1e-6
          ? math.min(-eye.y / ray.y, reach / ray.length)
          : reach / ray.length;
      return -(eye.z + ray.z * level);
    }

    final (a, b) = (along(-1.0), along(1.0));
    return (near: math.min(a, b), far: math.max(a, b));
  }

  /// Whether reach [index] is kept while the picture shows reaches [from]
  /// to [to]: those, and one either side of them.
  static bool keeps(int index, int from, int to) =>
      index >= from - 1 && index <= to + 1;

  /// Keeps reaches [from] to [to] and lets go of the rest; makes at most
  /// two a frame, the nearest first, so starting again is not one long
  /// frame.
  ///
  /// **A reach is let go only once it is a whole reach out of the
  /// picture.** The edges of the picture move with the camera, and the
  /// camera shakes when something is hit: let go as soon as its edge left
  /// the picture, the reach under the bottom of it went and came back as
  /// the shake carried the edge across the seam, and the bare bed blinked
  /// through where its water had been.
  void _cover(int from, int to) {
    for (final index in _reaches.keys.toList()) {
      if (!keeps(index, from, to)) _drop(_reaches.remove(index)!);
    }
    var made = 0;
    for (var index = from; index <= to && made < 2; index++) {
      if (_reaches.containsKey(index)) continue;
      _reaches[index] = _make(index);
      made++;
    }
  }

  /// The ground under ([x], the row [row]) as the valley's mesh has it: its
  /// banks' slopes, its islands, its bed.
  static double groundAt(RiverRow row, double x) {
    final grown = row.islandGrown;
    final crest = bedDepth + (landHeight - bedDepth) * grown;
    final xs = <double>[
      row.left - bankTop,
      row.left + bankUnder,
      row.islandLeft - bankUnder * grown,
      row.islandLeft + bankTop * grown,
      row.islandRight - bankTop * grown,
      row.islandRight + bankUnder * grown,
      row.right - bankUnder,
      row.right + bankTop,
    ];
    const ys = <double>[
      landHeight,
      bedDepth,
      bedDepth,
      0.0,
      0.0,
      bedDepth,
      bedDepth,
      landHeight,
    ];
    if (x <= xs.first || x >= xs.last) return landHeight;
    for (var k = 0; k + 1 < xs.length; k++) {
      if (x > xs[k + 1]) continue;
      final width = xs[k + 1] - xs[k];
      // The island's top is its crest, which grows with it.
      final a = k == 3 || k == 4 ? crest : ys[k];
      final b = k == 2 || k == 3 ? crest : ys[k + 1];
      if (width <= 1e-6) return b;
      return a + (b - a) * (x - xs[k]) / width;
    }
    return landHeight;
  }

  _Reach _make(int index) {
    final low = _first + index * reachLength;
    final high = low + reachLength;
    // A row a reach shares with the reach above, its cells' middles on the
    // line where they meet, so the two surfaces, each drawn through its
    // cells' middles, meet along it. Two rows more, one cell's strip of
    // river was drawn twice, a pale band across it and out over both banks
    // sixty and a hundred and twenty metres short of every bridge; one row
    // less, the two stopped a cell apart and the bed showed between them.
    final nz = (reachLength / cell).round() + 1;
    double rowDistance(int j) => high - j * cell;
    var lo = double.infinity, hi = double.negativeInfinity;
    for (var j = 0; j < nz; j++) {
      final row = _course.rowAt(rowDistance(j));
      lo = math.min(lo, row.left);
      hi = math.max(hi, row.right);
    }
    final x0 = ((lo - bankTop) / cell).floor() * cell - cell;
    final nx = ((hi + bankTop - x0) / cell).ceil() + 1;
    // A sill under the bridge at the reach's upper end, when there is one.
    final section = _course.section(_course.sectionIndexAt(high - 1.0));
    final weir = section.hasBridge && (section.bridgeAt - high).abs() < 1e-6;

    final ground = List<double>.filled(nx * nz, 0.0);
    final walls = List<bool>.filled(nx * nz, false);
    for (var j = 0; j < nz; j++) {
      final distance = rowDistance(j);
      final row = _course.rowAt(distance);
      final below = high - distance;
      for (var i = 0; i < nx; i++) {
        final c = i + j * nx;
        var h = groundAt(row, x0 + (i + 0.5) * cell);
        if (weir && below <= _sillLength) {
          // The sill runs from bank to bank; where it meets the grass the
          // bank is a wall, so what stands on the sill stays in the river.
          if (h >= landHeight - 0.05) walls[c] = true;
          h = math.max(h, _sillTop);
        } else if (weir && below <= _sillLength + _poolLength && h < 0.0) {
          h = math.min(h, _poolDepth);
        }
        ground[c] = h;
      }
    }

    final origin = Vector3(x0, 0.0, -high - cell / 2.0);
    final water = elements.addWater(
      ground: ElementHeightfield.list(
        origin: origin,
        cell: cell,
        nx: nx,
        nz: nz,
        heights: ground,
      ),
      liquid: _river,
      bed: const Bed(roughness: Bed.naturalStream),
      mist: weir ? const MistSettings() : null,
      detail: weir ? null : _plainDetail,
    );
    if (weir) water.setWalls(walls);
    // Its rows run down the river along +z: the river comes in over its
    // upper edge and stands at its level, nought, past its lower one.
    water
      ..setEdge(GridSide.south, const NativeEdgeFlow.inflow(discharge: _flow))
      ..setEdge(GridSide.north, const NativeEdgeFlow.level(0.0));
    water.fill(
      from: origin,
      to: Vector3(origin.x + nx * cell, 0.0, origin.z + nz * cell),
      level: 0.0,
    );
    final nodes = <MeshNode>[if (weir) _sill(high)];
    return _Reach(water, nodes, near: low);
  }

  /// The sill under the bridge at [bridge], from bank to bank: stone from
  /// the bed to its top, its face to the pool under the bridge's near edge.
  MeshNode _sill(double bridge) {
    final row = _course.rowAt(bridge);
    final width = row.half * 2.0 + 1.2;
    final tall = _sillTop - bedDepth;
    final node =
        MeshNode(
          DeviceMesh.upload(
            _game.device,
            CuboidShape(size: Vector3(width, tall, _sillLength)).build(),
          ),
          _stone,
          name: 'weir',
        )..setPosition(
          row.center,
          bedDepth + tall / 2.0,
          -(bridge - _sillLength / 2.0),
        );
    _game.scene.add(node);
    return node;
  }

  void _drop(_Reach reach) {
    final drawing = _game.renderer;
    for (final node in reach.nodes) {
      node.removeFromParent();
      final mesh = node.mesh;
      if (mesh is! DeviceMesh) continue;
      if (drawing != null) {
        drawing.releaseMeshAfterFrame(mesh);
      } else {
        _game.device
          ..releaseGeometry(mesh.vertices)
          ..releaseGeometry(mesh.indices);
      }
    }
    elements.remove(reach.water);
  }

  /// How far under the water the hulls reach, m: the bottom of a tanker's
  /// hull and of a depot's pontoon as `models.dart` draws them, 0.12 − 0.45/2
  /// and 0.1 − 0.3/2 under the waterline.
  static const double _tankerDraft = 0.105, _depotDraft = 0.05;

  /// Every tanker and fuel barge on the water followed into it as its hull
  /// is under the waterline — the craft's outline as the game has it, as
  /// deep as it is drawn — so the water parts round it, the current piles
  /// against it and it leaves a wake. The craft are never touched.
  ///
  /// **Its draft, not more.** Three balls stood in for a tanker, reaching
  /// 0.62 m down into a river 0.4 m deep: they pushed every column they
  /// passed through out of its way down to the bed, and a tanker turning at
  /// a bank left a cell or two dry behind it, the sand of the bed showing
  /// yellow-brown for a frame or two before the river closed over it again.
  void _wade() {
    final seen = <TargetComponent>{};
    for (final target in _game.targets) {
      final kind = target.plan.kind;
      if (!target.isMounted) continue;
      if (kind == TargetKind.helicopter) {
        if (target.down) _falling[target] = target.scenePosition;
        continue;
      }
      if (kind != TargetKind.tanker && kind != TargetKind.depot) continue;
      // A tanker going under is let go: balls dragged down with it pushed
      // the water out of a block of cells, which showed as a pale square
      // of river bed under its burning oil long after it had sunk.
      if (target.down) continue;
      if (!_reaches.containsKey(_reachAt(target.plan.distance))) continue;
      seen.add(target);
      // A box from the hull's bottom to the waterline, its length across
      // the river as the craft lies and its beam along it.
      final draft = kind == TargetKind.tanker ? _tankerDraft : _depotDraft;
      _hulls[target] ??= elements.follow(
        () {
          final at = target.scenePosition;
          return (
            position: Vector3(at.x, at.y - draft / 2.0, at.z),
            orientation: Quaternion.identity(),
          );
        },
        shape: NativeShape.box(
          Vector3(target.size.x / 2.0, draft / 2.0, target.size.y / 2.0),
        ),
      );
    }
    _hulls.removeWhere((target, hull) {
      if (seen.contains(target)) return false;
      elements.remove(hull);
      return true;
    });
    // A helicopter the river has taken: gone from the game this frame.
    _falling.removeWhere((target, at) {
      if (target.isMounted) return false;
      _splash(at..y = 0.4, radius: 0.5, speed: 7.0);
      return true;
    });
  }

  /// What goes into the river from above: the jet brought down over it, a
  /// broken bridge's two halves.
  void _plunge(double dt) {
    final down = _game.phase == Phase.crashed || _game.phase == Phase.over;
    if (down && !_jetDown) {
      final at = _game.jet.scenePosition;
      if (_course.rowAt(-at.z).isWater(at.x)) {
        _splash(at..y = 0.6, radius: 0.7, speed: 11.0);
      }
    }
    _jetDown = down;
    for (final bridge in _game.bridges) {
      if (!bridge.down) continue;
      final was = _broken[bridge] ?? 0.0;
      final since = _broken[bridge] = was + dt;
      // The halves swing down and reach the water a little under a second
      // after the shot.
      if (was < 0.75 && since >= 0.75) {
        final at = bridge.scenePosition;
        for (final side in const <double>[-1.0, 1.0]) {
          _splash(
            Vector3(at.x + side * bridge.span / 4.0, 0.5, at.z),
            radius: 0.8,
            speed: 4.0,
          );
        }
      }
    }
    _broken.removeWhere((bridge, _) => !bridge.isMounted);
    _plunges.removeWhere((plunge) {
      plunge.life -= dt;
      if (plunge.life > 0.0) return false;
      elements.remove(plunge.ball);
      return true;
    });
  }

  /// A ball of [radius], a little denser than water, dropped into the water
  /// at [at] going down at [speed] — what is dropped in goes under rather
  /// than bobbing; gone again once its rings have spread.
  void _splash(Vector3 at, {required double radius, required double speed}) {
    if (!_reaches.containsKey(_reachAt(-at.z))) return;
    final ball = elements.addBody(
      Solid.sphere(radius, material: NativeMaterial.stone(), density: 1400.0),
      at: at,
      velocity: Vector3(0.0, -speed, 0.0),
    );
    _plunges.add(_Plunge(ball));
  }

  /// Every reach let go, and the world with them.
  void dispose() {
    for (final reach in _reaches.values) {
      _drop(reach);
    }
    _reaches.clear();
    elements.dispose();
  }
}

/// One reach of the river: its water, what was put into the scene for it,
/// and how far up the river its lower end is, m.
final class _Reach {
  _Reach(this.water, this.nodes, {required this.near});

  final WaterBody water;
  final List<MeshNode> nodes;
  final double near;
}

/// A ball dropped into the river, and how long it has left.
final class _Plunge {
  _Plunge(this.ball);

  final TrackedBody ball;
  double life = 1.5;
}
