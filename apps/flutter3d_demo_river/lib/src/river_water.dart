/// The river's own water: shallow water of the physics core over the bed the
/// course lays out, running down the valley towards the jet's tail, parting
/// round the tankers and the fuel barges, and spilling over a stone weir
/// under every bridge into a pool of white water.
///
/// **Drawn only.** The game flies over a level plane at nought, and goes on
/// doing so: nothing here is read by the run, and what moves the water is
/// read off it. The water is in worlds of its own; the hulls in it are balls
/// put where the craft are every frame, and what falls in is a ball dropped
/// where the game shows something going down.
///
/// **Only the water in sight is there.** The river never ends, so it is cut
/// into reaches sixty metres long, a liquid and a world apiece; the reaches
/// from just behind the jet to as far as the camera sees are kept, and each
/// is let go once the jet has left it behind. A reach is fed by springs
/// across its upper part and drained as fast across its lower part, so the
/// current runs through it as it runs through the reach before; the seams
/// between two reaches lie across the stream in the slack water beyond both,
/// where the two have the same level and neither is moving.
///
/// **The weirs are where the level is put back.** The river is level from
/// end to end and a falls has to drop somewhere. Under each bridge the reach
/// below starts on a sill whose springs well up and pour over its lip into a
/// scoured pool; the reach above is drained against the back of the sill,
/// where the bridge's deck hides that the water there stands no higher than
/// the pool. That is the one thing here that is not what water would do.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flame/components.dart' show Component, HasGameReference;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_effects/flutter3d_effects.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:vector_math/vector_math.dart';

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
      final look = await LiquidLook.load(
        device: game.device,
        renderer: drawing,
        bundle: await rootBundle.load(LiquidLook.asset),
      );
      if (!game.has3d || isRemoved) return;
      water = RiverWater(game: game, look: look, light: light);
    } catch (error) {
      debugPrint('river: no water material, so the plane stays ($error)');
    }
  }

  /// Everything let go, before the device it is drawn on closes.
  void close() {
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
  RiverWater({
    required RiverGame game,
    required LiquidLook look,
    required this._light,
  }) : _game = game,
       _look = look,
       // A course of its own, laid out by the same seed: reading the game's
       // would lay out its stretches ahead of when the game does.
       _course = Course(seed: game.course.seed) {
    final sun = Vector3(-0.35, -1.0, -0.45)..normalize();
    look
      ..sun(along: sun, light: Vector3(2.4, 2.34, 2.2))
      // The sky the game clears to, a little deeper overhead.
      ..sky(
        zenith: Vector3(0.2, 0.38, 0.72),
        horizon: Vector3(0.27, 0.48, 0.78),
      )
      // A lowland river: green-brown where it is shallow, and cloudy, so
      // the plane under it reads as depth rather than as a floor.
      ..tint(
        shallow: Vector3(0.12, 0.27, 0.25),
        deep: Vector3(0.02, 0.08, 0.13),
        clearness: 0.04,
      );
  }

  final RiverGame _game;
  final LiquidLook _look;
  final bool _light;
  final Course _course;

  /// How long a reach is, m: a third of a stretch, so the seams fall where
  /// the bridges are and no more than three are in sight between them.
  static const double reachLength = sectionLength / 3.0;

  /// A cell, m: a tanker is between five and six long.
  static const double cell = 0.6;

  /// Where the reaches start counting: the bridge before the first stretch,
  /// had it one.
  static const double _first = -bridgeInset;

  /// How far behind the jet and ahead of it the water is kept, m: as far
  /// down as the camera's view reaches past the jet's tail, and as far up as
  /// the haze lets anything be seen.
  static const double _behind = 20.0, _ahead = 150.0;

  /// What runs down the river, m³/s: about a quarter of a metre a second
  /// where it is widest and close to a metre between the bridge's piers.
  static const double _flow = 3.0;

  /// How far inside its ends a reach's springs and drains are, m.
  static const double _slack = 7.0;

  /// The sill under a bridge: how high its top stands, how far down the
  /// river it reaches from the bridge's line, and how deep the pool scoured
  /// at its foot is and how long, m. High enough over the pool for the core
  /// to throw what goes over it as a falls, which takes a drop of more than
  /// a cell; low enough that the water held on it stays under the grass.
  static const double _sillTop = 0.52, _sillLength = 1.5;
  static const double _poolDepth = -0.7, _poolLength = 1.5;

  /// How much of a reach's falling water is drawn: a weir's on a desktop
  /// and on a phone, and a reach with no weir, where nothing falls but the
  /// splash of a hull going down.
  static const LiquidDetail _weirDetail = LiquidDetail(
    sheet: 1500,
    drops: 900,
    bubbles: 1500,
  );
  static const LiquidDetail _plainDetail = LiquidDetail(
    sheet: 8,
    drops: 150,
    bubbles: 150,
  );

  /// The stone the sills are built of.
  final Material _stone = Material(
    name: 'weir',
    baseColor: Vector4(0.33, 0.31, 0.27, 1.0),
    roughness: 0.95,
  );

  final Map<int, _Reach> _reaches = <int, _Reach>{};
  final Map<TargetComponent, _Hull> _hulls = <TargetComponent, _Hull>{};
  final List<_Plunge> _plunges = <_Plunge>[];

  /// Each helicopter going down, where it was last seen: it falls into the
  /// river the frame it is gone.
  final Map<TargetComponent, Vector3> _falling = <TargetComponent, Vector3>{};

  /// Each bridge broken, and how long ago: its halves reach the water a
  /// little after.
  final Map<BridgeComponent, double> _broken = <BridgeComponent, double>{};
  bool _jetDown = false;
  double _seconds = 0.0;
  int _frame = 0;

  /// The game's own water, a plane at nought under every stretch, which
  /// the reaches are drawn over: by name, as the game names it.
  static final RegExp _plane = RegExp(r'^water -?\d+$');

  /// How far under the water the plane is put, m: under every surface the
  /// reaches draw, so it shows through them as depth and is seen as water
  /// only past the last of them.
  static const double _planeUnder = -0.12;

  /// What the plane is drawn with while the reaches are over it: about the
  /// colour the water itself is drawn, mostly its own light so the sun does
  /// not take it darker or brighter. The game's navy showed through every
  /// gap the reaches left — along a shore where the water stops a hand short
  /// of the sand, beside a hull — as dark blue blotches on lighter water.
  final Material _under = Material(
    name: 'river under',
    baseColor: Vector4(0.01, 0.02, 0.03, 1.0),
    emissive: Vector3(0.05, 0.16, 0.27),
    roughness: 1.0,
  );

  int _reachAt(double distance) => ((distance - _first) / reachLength).floor();

  /// Everything brought up to date [dt] seconds on.
  void update(double dt) {
    final step = math.min(dt, 1.0 / 30.0);
    if (step <= 0.0) return;
    _seconds += step;
    _frame++;
    final distance = _game.distance;
    _cover(_reachAt(distance - _behind), _reachAt(distance + _ahead));
    _wade(step);
    _plunge(step);
    for (final MapEntry(key: index, value: reach) in _reaches.entries) {
      // The water near the jet is stepped and drawn every other frame, and
      // far up the river every fourth, the reaches taking turns, each step
      // as long as the frames it stands for. The ripples run in the look on
      // the frame's own clock, so what is saved is only how often the
      // surface under them is moved, which from the camera's height is a
      // fraction of a pixel a frame.
      final ahead = reach.near - distance;
      final turn = _frame + index;
      reach
        ..unstepped += step
        ..undrawn += step
        ..age += step;
      if (turn % (ahead < 60.0 ? 2 : 4) == 0) {
        reach.world.step(math.min(reach.unstepped, 1.0 / 15.0));
        reach.unstepped = 0.0;
        // A reach just made has still water in it and nothing on its sill:
        // a few steps more for its first seconds, while it is still far up
        // the river, so it is running by the time it is close.
        if (reach.age < 3.0) reach.world.step(1.0 / 15.0);
      }
      if (turn % (ahead < 40.0 ? 2 : 4) == 0) {
        reach.view.update(reach.undrawn);
        reach.undrawn = 0.0;
      }
    }
    _look.update(seconds: _seconds, eye: _game.chase.rig.eye);
    _lowerPlanes();
  }

  /// Keeps reaches [from] to [to] and lets go of the rest; makes at most
  /// two a frame, the nearest first, so starting again is not one long
  /// frame.
  void _cover(int from, int to) {
    for (final index in _reaches.keys.toList()) {
      if (index < from || index > to) _drop(_reaches.remove(index)!);
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
    // A row more than the reach at its upper end, under the lower end of
    // the reach above: two surfaces a centimetre apart in height, meeting
    // edge to edge, left a crack across the river between them.
    final nz = (reachLength / cell).round() + 2;
    double rowDistance(int j) => high + cell - j * cell;
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

    final drawn = List<double>.filled(nx * nz, 0.0);
    final ground = List<double>.filled(nx * nz, 0.0);
    for (var j = 0; j < nz; j++) {
      final distance = rowDistance(j);
      final row = _course.rowAt(distance);
      final below = high - distance;
      for (var i = 0; i < nx; i++) {
        final c = i + j * nx;
        var h = groundAt(row, x0 + (i + 0.5) * cell);
        var held = h;
        if (weir && below <= _sillLength) {
          h = math.max(h, _sillTop);
          // The water held on the sill stands a hand over its top; banks
          // nobody sees keep it off the grass either side.
          held = h >= landHeight - 0.05 ? landHeight + 0.4 : h;
        } else if (weir && below <= _sillLength + _poolLength && h < 0.0) {
          h = math.min(h, _poolDepth);
          held = h;
        }
        drawn[c] = h;
        ground[c] = held;
      }
    }

    final world = NativeWorld();
    final origin = Vector3(x0, 0.0, -high - cell * 1.5);
    final liquid = world.createShallowLiquid(
      nx: nx,
      nz: nz,
      cell: cell,
      origin: origin,
      ground: ground,
    );
    world
      ..setShallowBed(liquid, roughness: 0.03)
      ..fillShallowLiquid(
        liquid,
        x0: origin.x,
        z0: origin.z,
        x1: origin.x + nx * cell,
        z1: origin.z + nz * cell,
        level: 0.0,
      );
    var source = 0;
    // Over the deep middle of each channel, a metre and more off its banks:
    // a drain over the shallow foot of a bank drew it dry, and the plane
    // under the water showed through the hole.
    void across(double distance, double rate) {
      final channels = <(double, double)>[
        for (final (from, to) in _course.rowAt(distance).channels)
          if (to - from > 3.0) (from + 1.2, to - 1.2),
      ];
      final total = channels.fold(0.0, (sum, c) => sum + c.$2 - c.$1);
      for (final (from, to) in channels) {
        final width = to - from;
        final count = math.max(1, (6.0 * width / total).round());
        for (var k = 0; k < count; k++) {
          world.setShallowSource(
            liquid,
            source++,
            x: from + (k + 0.5) * width / count,
            z: -distance,
            // Each spread over its share of the channel, so the level dips
            // and swells evenly across it rather than in pits round each.
            radius: math.max(0.5 * width / count, cell),
            rate: rate * width / total / count,
          );
        }
      }
    }

    // In over the sill or well inside the top, out well inside the foot.
    // The water past them lies slack, and so does the water past the next
    // reach's springs, so the two meet at a seam where both are still: a
    // seam between a reach drawing into its drains and one spreading from
    // its springs was a line across the river where the ripples changed
    // course.
    across(weir ? high - _sillLength / 2.0 : high - _slack, _flow);
    across(low + _slack, -_flow);

    final before = _game.scene.meshes.toSet();
    final view = LiquidView(
      world: world,
      liquid: liquid,
      ground: drawn,
      device: _game.device,
      scene: _game.scene,
      look: _look.material,
      detail: weir ? (_light ? LiquidDetail.light : _weirDetail) : _plainDetail,
    );
    final nodes = <MeshNode>[
      ..._game.scene.meshes.where((node) => !before.contains(node)),
    ];
    if (weir) nodes.add(_sill(high));
    return _Reach(world, liquid, view, nodes, near: low);
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
    _hulls.removeWhere((_, hull) => identical(hull.reach, reach));
    _plunges.removeWhere((plunge) => identical(plunge.reach, reach));
    reach.world.dispose();
  }

  /// The reach the water at [distance] is in, if it is kept.
  _Reach? _reachFor(double distance) => _reaches[_reachAt(distance)];

  /// Every tanker and fuel barge on the water stood in for by balls under
  /// its hull, put where it is and moving as it moves, so the water parts
  /// round it, the current piles against it, and a tanker going under
  /// pushes the river aside as it goes. The craft are never touched.
  void _wade(double dt) {
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
      final reach = _reachFor(target.plan.distance);
      if (reach == null) continue;
      seen.add(target);
      // Kept inside the hull's own outline and mostly under the surface:
      // balls as wide as the hull pushed the water out from beside it, and
      // the hollow round a tanker showed as a dark pit at its side.
      final hull = _hulls[target] ??= _Hull(reach, <NativeBody>[
        for (final _
            in kind == TargetKind.tanker
                ? const <int>[-1, 0, 1]
                : const <int>[0])
          _ball(reach.world, kind == TargetKind.tanker ? 0.4 : 0.6),
      ], target.scenePosition);
      final at = target.scenePosition;
      final moved = (at - hull.last)..scale(1.0 / dt);
      hull.last.setFrom(at);
      for (var k = 0; k < hull.balls.length; k++) {
        final along = hull.balls.length == 1 ? 0.0 : (k - 1) * 1.0;
        reach.world
          ..setPosition(hull.balls[k], Vector3(at.x + along, at.y - 0.22, at.z))
          ..setVelocity(hull.balls[k], moved.clone())
          ..setAngularVelocity(hull.balls[k], Vector3.zero());
      }
    }
    _hulls.removeWhere((target, hull) {
      if (seen.contains(target)) return false;
      hull.balls.forEach(hull.reach.world.removeBody);
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
      plunge.reach.world.removeBody(plunge.ball);
      return true;
    });
  }

  /// A ball of [radius] dropped into the water at [at], going down at
  /// [speed]; gone again once its rings have spread.
  void _splash(Vector3 at, {required double radius, required double speed}) {
    final reach = _reachFor(-at.z);
    if (reach == null) return;
    final ball = _ball(reach.world, radius);
    reach.world
      ..setPosition(ball, at)
      ..setVelocity(ball, Vector3(0.0, -speed, 0.0));
    _plunges.add(_Plunge(reach, ball));
  }

  /// A ball of [radius], a little denser than water: what is dropped in
  /// goes under rather than bobbing.
  NativeBody _ball(NativeWorld world, double radius) {
    final body = world.addBody(
      position: Vector3(0.0, -50.0, 0.0),
      mass: 1400.0 * 4.0 / 3.0 * math.pi * radius * radius * radius,
    );
    world
      ..setShape(body, NativeShape.sphere(radius))
      ..setMaterial(body, NativeMaterial.wood());
    return body;
  }

  /// The game's plane under each stretch, put under the reaches.
  void _lowerPlanes() {
    final at = Vector3.zero();
    for (final node in _game.scene.meshes) {
      final name = node.name;
      if (name == null || !name.startsWith('water ')) continue;
      if (!_plane.hasMatch(name)) continue;
      node.readPosition(at);
      if (at.y != _planeUnder) node.setPosition(at.x, _planeUnder, at.z);
      node.material = _under;
    }
  }

  /// Every reach let go.
  void dispose() {
    for (final reach in _reaches.values) {
      _drop(reach);
    }
    _reaches.clear();
  }
}

/// One reach of the river: its world, its water and how that is drawn, and
/// what was put into the scene for it.
final class _Reach {
  _Reach(this.world, this.liquid, this.view, this.nodes, {required this.near});

  final NativeWorld world;
  final NativeShallowLiquid liquid;
  final LiquidView view;
  final List<MeshNode> nodes;

  /// How far up the river its lower end is, m.
  final double near;

  /// Seconds since it was made, and since it was last stepped and drawn.
  double age = 0.0, unstepped = 0.0, undrawn = 0.0;
}

/// The balls standing in for one hull, and where it was last frame.
final class _Hull {
  _Hull(this.reach, this.balls, this.last);

  final _Reach reach;
  final List<NativeBody> balls;
  final Vector3 last;
}

/// A ball dropped into a reach, and how long it has left.
final class _Plunge {
  _Plunge(this.reach, this.ball);

  final _Reach reach;
  final NativeBody ball;
  double life = 1.5;
}
