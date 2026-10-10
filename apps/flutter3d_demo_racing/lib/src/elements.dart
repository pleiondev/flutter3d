/// Water standing on the circuit, wrecks burning where cars hit hard, and the
/// dust and smoke a car throws up: the physics core's water and fire, in the
/// effects' own world beside the race.
///
/// **Nothing here reaches the race.** The cars, the laps, the ghosts and the
/// recorded demos are `flutter3d_game_racing`'s and are stepped exactly as
/// they were; this layer reads where the cars are, how fast they go and how
/// hard they were struck, and draws and sounds what follows from that. A car
/// ploughing through a ford is not slowed by it, and a car that set a wreck
/// alight is not hurt by the fire: both are things seen and heard, and a lap
/// time is the same with this layer as without it.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_audio/flutter3d_audio.dart';
import 'package:flutter3d_effects/flutter3d_effects.dart';
import 'package:flutter3d_elements/flutter3d_elements.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart' show Portable;
import 'package:flutter3d_game_racing/flutter3d_game_racing.dart';
import 'package:flutter3d_particles/flutter3d_particles.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';

import 'looks.dart';

/// What the water, the fires and the wash of a car through water sound like:
/// the effects package's own recordings, played through this game's mixer.
abstract final class ElementSounds {
  static const String _from = 'packages/flutter3d_effects/assets';

  /// A wreck burning: one loop a fire, as loud as its heat.
  static const SoundDef fire = SoundDef(
    name: 'fire',
    asset: '$_from/fire_loop.wav',
    loop: true,
    attenuation: InverseRolloff(reference: 6.0, maximum: 120.0),
    maxInstances: 6,
  );

  /// A car's wheels throwing water: the roar of falling water, held for as
  /// long as a car is ploughing through a ford and as loud as it is fast.
  static const SoundDef wash = SoundDef(
    name: 'wash',
    asset: '$_from/falls_loop.wav',
    loop: true,
    attenuation: InverseRolloff(reference: 8.0, maximum: 140.0),
    maxInstances: 4,
  );

  /// A car hitting the water, and a piece of a wreck landing in it.
  static const SoundDef splash = SoundDef(
    name: 'splash',
    asset: '$_from/splash.wav',
    priority: 3,
    rateVariance: 0.12,
    attenuation: InverseRolloff(reference: 8.0, maximum: 160.0),
  );

  /// Added to the game's own bank when the speakers open, in `main.dart`.
  static const List<SoundDef> all = <SoundDef>[fire, wash, splash];
}

/// A stretch of water on the circuit, and the square of ground it covers.
final class _Pool {
  _Pool(this.water, this.along, this.x0, this.z0, this.x1, this.z1);

  final WaterBody water;

  /// How far round the circuit it lies, m.
  final double along;
  final double x0, z0, x1, z1;

  /// Whether ([x], [z]) is within [margin] metres of the pool's grid.
  bool near(double x, double z, double margin) =>
      x > x0 - margin && x < x1 + margin && z > z0 - margin && z < z1 + margin;
}

/// Whether a car was in water last frame, and how long until its wheels are
/// heard hitting it again.
final class _Wader {
  bool wet = false;
  double hush = 0.0;
}

/// A piece of a wrecked car.
final class _Debris {
  _Debris(this.body, this.node);

  final TrackedBody body;
  final MeshNode node;
}

/// What a hard crash left on the circuit: a floor for its pieces to land on,
/// the pieces, and the fuel that spilled from the tank burning on what is
/// left of the car.
final class _Wreck {
  _Wreck(
    this.floor,
    this.pieces,
    this.heap,
    this.floorNode,
    this.ground,
    this.along,
  );

  /// The slabs of road laid under the wreck, by which four metres of the
  /// circuit each is: more are laid as a piece rolls on down the road, so a
  /// tyre running away downhill rolls on the road rather than through it.
  final Map<int, TrackedBody> floor;
  final MeshNode floorNode;

  /// Where the car crashed, on the road, and how far round the circuit.
  final Vector3 ground;
  final double along;
  final List<_Debris> pieces;

  /// What is left of the car, where the spilt fuel burns.
  final _Debris heap;
  double age = 0.0;

  /// Whether the marshals have put it out.
  bool doused = false;
}

/// The water, the fires and the dust of one circuit.
///
/// Made by `main.dart` once a circuit is loaded and a renderer exists, and
/// let go with [dispose] when the circuit is left. Fed twice: [stepped] after
/// every fixed step of the race, for the crashes, which are edges a frame
/// would miss; and [frame] once a frame, for everything that is drawn and
/// heard.
final class TrackElements {
  TrackElements._({
    required this._elements,
    required GraphicsDevice device,
    required this._scene,
    required Renderer renderer,
    required this._track,
    required List<SphereVehicle> cars,
    required SkyPreset sky,
    required List<PassContributor> before,
    required this._light,
  }) : _device = device,
       _renderer = renderer,
       _cars = cars {
    final sheet = _smokeSheet;
    TextureHandle upload(Uint8List bytes) => device.createTextureFromPixels(
      width: sheet.width,
      height: sheet.height,
      format: TextureFormat.r8g8b8a8UNormInt,
      pixels: ByteData.sublistView(bytes),
    );
    // Dust and smoke lit by the sun, so a cloud is bright on the side
    // facing it and grey in its own shade, and hides what is behind it; the
    // spray after it, added on top, because water in the sun glitters.
    renderer
      ..renderSteps.addContributor(
        ParticleContributor(
          _haze,
          sixWay: SixWayMaterial(
            positive: upload(sheet.positive),
            negative: upload(sheet.negative),
            ambient: Vector3.all(0.45 * sky.ambientIntensity + 0.2),
          ),
          flipbook: Flipbook(columns: 4, rows: 4),
          softness: 0.5,
        ),
      )
      ..renderSteps.addContributor(ParticleContributor(_spray));
    _contributors.addAll(
      renderer.renderSteps.contributors.where((c) => !before.contains(c)),
    );
    // Every water mirrors this circuit's sky and glints in its sun.
    _elements
      ..sun(along: -sky.directionToSun, light: sky.sunColor * sky.sunIntensity)
      ..sky(zenith: sky.zenith, horizon: sky.horizon);
    // The race's world — its gravity, air and wind — so the spray, the fires
    // and the water fall and drift as the cars do: one gravity in a race.
    if (cars.isNotEmpty) {
      _elements.world.applyProperties(cars.first.world.properties);
    }
    _floodLowSpots();
    for (var i = 0; i < cars.length; i++) {
      _lastVelocity.add(cars[i].velocity.clone());
      _lastPosition.add(cars[i].position.clone());
      _cooldown.add(0.0);
      _waders.add(_Wader());
      _wet.add(false);
      _follow(i);
    }
  }

  /// The circuit's elements, their water's look loaded through [load]: null
  /// when it cannot be, and the circuit is raced dry and unburnt.
  static Future<TrackElements?> open({
    required GraphicsDevice device,
    required Scene scene,
    required Renderer renderer,
    required TrackSpline track,
    required List<SphereVehicle> cars,
    required SkyPreset sky,
    required Future<ByteData> Function(String asset) load,
    bool light = false,
  }) async {
    final before = renderer.renderSteps.contributors.toList();
    final Elements elements;
    try {
      elements = await Elements.open(
        device: device,
        renderer: renderer,
        scene: scene,
        load: load,
        quality: ElementsQuality.of(phone: light),
        hearing: (world) => PhysicsHearing(
          world,
          fireScale: _fireHeard,
          fallScale: _fallHeard,
          splashScale: _splashHeard,
        ),
      );
    } on Object {
      return null;
    }
    return TrackElements._(
      elements: elements,
      device: device,
      scene: scene,
      renderer: renderer,
      track: track,
      cars: cars,
      sky: sky,
      before: before,
      light: light,
    );
  }

  /// How loud this game plays what the physics does: a fire from half a
  /// kilowatt, a candle, to half a megawatt, a car alight from end to end;
  /// water falling from fifty watts to a hundred kilowatts; a splash from
  /// twenty joules, a stone dropped from a hand, to twenty kilojoules.
  static const HearingScale _fireHeard = HearingScale(
    quiet: 500.0,
    loud: 5e5,
    reference: 2e4,
  );
  static const HearingScale _fallHeard = HearingScale(
    quiet: 50.0,
    loud: 1e5,
    reference: 5e3,
  );
  static const HearingScale _splashHeard = HearingScale(
    quiet: 20.0,
    loud: 2e4,
    reference: 2e3,
  );

  final Elements _elements;
  final GraphicsDevice _device;
  final Scene _scene;
  final Renderer _renderer;
  final TrackSpline _track;
  final List<SphereVehicle> _cars;

  /// Whether to draw less of everything, for a phone.
  final bool _light;

  final List<PassContributor> _contributors = <PassContributor>[];
  final List<_Pool> _pools = <_Pool>[];
  final List<_Wader> _waders = <_Wader>[];

  /// Each car's four tyres in the world.
  final List<List<Follower>> _tireSet = <List<Follower>>[];
  final List<_Wreck> _wrecks = <_Wreck>[];
  final List<Vector3> _lastVelocity = <Vector3>[];
  final List<Vector3> _lastPosition = <Vector3>[];
  final List<double> _cooldown = <double>[];
  final math.Random _random = math.Random(29);

  late final ParticleSystem _haze = ParticleSystem(
    capacity: _light ? 500 : 1400,
    seed: 41,
  );
  late final ParticleSystem _spray = ParticleSystem(
    capacity: _light ? 400 : 1200,
    seed: 43,
  );

  /// One sheet of six-way smoke for every circuit: a bake is a few hundred
  /// milliseconds, and the puff is the same puff each time.
  static final SixWaySheet _smokeSheet = bakeSixWay(
    density: smokePuff(seed: 9),
    frames: 16,
    columns: 4,
    cell: 48,
  );

  // ------------------------------------------------------------- the water

  /// The size of a cell of water, m: fine enough that a car parts it,
  /// coarse enough that a ford is a few thousand cells.
  double get _cell => _light ? 0.7 : 0.5;

  /// How deep a ford may be on its low side, m. A road banked across, or
  /// running downhill, can only be under water from side to side if it is
  /// deeper on one side than the other, and past about this a car would be
  /// seen wading in to its axles.
  static const double _deepestFord = 0.3;

  /// Half the length of road a ford covers, m.
  static const double _fordHalf = 6.0;

  /// Lays water in the low spots of the circuit: a ford across the road
  /// wherever the road is level enough to be under water from side to side,
  /// and a puddle along the low edge of the road at the bottom of a dip.
  void _floodLowSpots() {
    final length = _track.length;
    final frame = TrackFrame();
    final spots = <({double s, double y, double need})>[];
    for (var s = 0.0; s < length; s += 4.0) {
      _track.frameAt(s, frame);
      final width = _track.widthAt(s);
      final across = frame.right.y.abs() * width;
      final along = frame.forward.y.abs() * 2.0 * _fordHalf;
      spots.add((s: s, y: frame.position.y, need: across + along));
    }
    bool apart(double s, List<double> taken) => taken.every((t) {
      final d = (s - t).abs() % length;
      return math.min(d, length - d) > 140.0;
    });

    // Away from the grid: a ford on the start line is a field of cars
    // standing in water before the lights go out.
    final grid = _track.grid.s;
    final taken = <double>[grid];
    final most = _light ? 2 : 3;
    // Water runs down to the low half of a circuit and stands there; a
    // level stretch over a crest stays dry.
    final heights = spots.map((p) => p.y).toList()..sort();
    final low = heights[heights.length ~/ 2];
    final fords =
        spots.where((p) => p.need <= _deepestFord - 0.05 && p.y <= low).toList()
          ..sort((a, b) => a.y.compareTo(b.y));
    for (final f in fords) {
      if (_pools.length >= math.min(2, most)) break;
      if (!apart(f.s, taken)) continue;
      taken.add(f.s);
      _ford(f.s);
    }
    final dips = <({double s, double y, double need})>[
      for (var i = 0; i < spots.length; i++)
        if (spots[i].y <= spots[(i - 1) % spots.length].y &&
            spots[i].y <= spots[(i + 1) % spots.length].y)
          spots[i],
    ]..sort((a, b) => a.y.compareTo(b.y));
    for (final d in dips) {
      if (_pools.length >= most) break;
      if (!apart(d.s, taken)) continue;
      taken.add(d.s);
      _puddle(d.s);
    }
  }

  /// Where on the road ([x], [z]) is, as the road near [s0] has it: how far
  /// along from [s0], how far across from the centre line, and the height
  /// of the road or its verge there.
  ({double along, double across, double height, double halfWidth}) _onRoad(
    double x,
    double z,
    double s0,
    double y0,
  ) {
    final s = _track.center.closestS(Vector3(x, y0, z), nearS: s0, window: 30);
    _track.frameAt(s, _frame);
    final r = _frame.right;
    final flat = r.x * r.x + r.z * r.z;
    final across =
        ((x - _frame.position.x) * r.x + (z - _frame.position.z) * r.z) / flat;
    var along = s - s0;
    final length = _track.length;
    if (along > length / 2) along -= length;
    if (along < -length / 2) along += length;
    return (
      along: along,
      across: across,
      height: _frame.position.y + r.y * across,
      halfWidth: _track.widthAt(s) / 2.0,
    );
  }

  final TrackFrame _frame = TrackFrame();

  /// A ford at [s0]: water across the whole road and a little onto either
  /// verge, its surface a few centimetres over the road's highest point.
  void _ford(double s0) {
    _track.frameAt(s0, _frame);
    final halfWidth = _track.widthAt(s0) / 2.0;
    final reachAcross = halfWidth + 1.2;
    _pool(
      s0,
      reach: math.sqrt(_fordHalf * _fordHalf + reachAcross * reachAcross),
      // Its two shores wander across the road, as a ford's do where the
      // water has found the low ruts, rather than running straight from
      // kerb to kerb.
      inside: (along, across, _) {
        final reachAlong =
            _fordHalf *
            (0.78 +
                0.14 * Portable.sin(across * 0.55 + s0) +
                0.08 * Portable.sin(across * 1.7 - 2.0 * s0) * along.sign);
        final a = along / reachAlong, b = across / reachAcross;
        return a * a + b * b * b * b * b * b <= 1.0;
      },
      level: (cells) =>
          cells
              .where((c) => c.across.abs() <= c.halfWidth)
              .map((c) => c.height)
              .fold(-1e9, math.max) +
          0.05,
    );
  }

  /// A puddle at [s0], along the low edge of the road: wider onto the verge
  /// than into the road, and reaching a couple of metres in from the kerb.
  void _puddle(double s0) {
    _track.frameAt(s0, _frame);
    final halfWidth = _track.widthAt(s0) / 2.0;
    // The low side is the one the road's right falls towards.
    final side = _frame.right.y > 0.0 ? -1.0 : 1.0;
    final middle = side * (halfWidth - 0.4);
    const longHalf = 11.0, wideHalf = 3.4;
    _pool(
      s0,
      reach: longHalf + halfWidth,
      inside: (along, across, _) {
        final a = along / longHalf, b = (across - middle) / wideHalf;
        return a * a + b * b <= 1.0;
      },
      level: (cells) {
        final lowest = cells.map((c) => c.height).fold(1e9, math.min);
        // Two metres into the road at the bottom of the dip, and never so
        // deep that the verge is a pond.
        final inRoad =
            _frame.position.y + _frame.right.y * side * (halfWidth - 2.0);
        return math.min(inRoad + 0.03, lowest + 0.35);
      },
    );
  }

  /// A pool of water laid over the road about [s0], everywhere within
  /// [reach] metres of it that [inside] says is water, filled to the height
  /// [level] works out from the ground under it. Round it the grid's cells
  /// are walls, so the water ends where [inside] does and not at the square
  /// edge of its grid, and the road under the walls is drawn as the road.
  void _pool(
    double s0, {
    required double reach,
    required bool Function(double along, double across, double halfWidth)
    inside,
    required double Function(
      List<({double across, double height, double halfWidth})> cells,
    )
    level,
  }) {
    _track.frameAt(s0, _frame);
    final center = _frame.position.clone();
    // On the road or its verge only: past the verge is the level's own
    // ground, which this water does not know the shape of.
    bool wetHere(
      ({double along, double across, double height, double halfWidth}) at,
    ) =>
        at.across.abs() <= at.halfWidth + _track.shoulder - 0.5 &&
        inside(at.along, at.across, at.halfWidth);
    // Where the water is, roughly, a metre at a time: the grid is laid over
    // that and a margin, not over the whole square round the spot.
    var lowX = double.infinity, lowZ = double.infinity;
    var highX = -double.infinity, highZ = -double.infinity;
    for (var z = center.z - reach; z <= center.z + reach; z += 1.0) {
      for (var x = center.x - reach; x <= center.x + reach; x += 1.0) {
        if (!wetHere(_onRoad(x, z, s0, center.y))) continue;
        lowX = math.min(lowX, x);
        lowZ = math.min(lowZ, z);
        highX = math.max(highX, x);
        highZ = math.max(highZ, z);
      }
    }
    if (lowX > highX) return;
    final cell = _cell;
    final nx = math.min(((highX - lowX + 3.0) / cell).ceil(), 96);
    final nz = math.min(((highZ - lowZ + 3.0) / cell).ceil(), 96);
    final x0 = (lowX + highX) / 2.0 - nx * cell / 2.0;
    final z0 = (lowZ + highZ) / 2.0 - nz * cell / 2.0;
    final wet = <({double across, double height, double halfWidth})>[];
    final road = List<double>.filled(nx * nz, 0.0);
    final walls = List<bool>.filled(nx * nz, true);
    for (var j = 0; j < nz; j++) {
      for (var i = 0; i < nx; i++) {
        final x = x0 + (i + 0.5) * cell, z = z0 + (j + 0.5) * cell;
        final at = _onRoad(x, z, s0, center.y);
        final k = i + j * nx;
        road[k] = at.height;
        if (wetHere(at)) {
          walls[k] = false;
          wet.add((
            across: at.across,
            height: at.height,
            halfWidth: at.halfWidth,
          ));
        }
      }
    }
    if (wet.length < 8) return;
    final surface = level(wet);
    final water = _elements.addWater(
      ground: ElementHeightfield.list(
        origin: Vector3(x0, 0.0, z0),
        cell: cell,
        nx: nx,
        nz: nz,
        heights: road,
      ),
      // As warm as the circuit's air: the world's, read as it is poured.
      liquid: Liquid.water(),
      // Asphalt: smooth asphalt's normal Manning n is troweled concrete's,
      // 0.013 (Chow, Open-Channel Hydraulics, table 5-6).
      bed: const Bed(roughness: Bed.concrete),
      mist: const MistSettings(),
    )..setWalls(walls);
    water.fill(
      from: Vector3(x0, 0.0, z0),
      to: Vector3(x0 + nx * cell, 0.0, z0 + nz * cell),
      level: surface,
    );
    _pools.add(_Pool(water, s0, x0, z0, x0 + nx * cell, z0 + nz * cell));
  }

  // ------------------------------------------------------------ the wheels

  /// A car's tyre: its radius and half its width, m.
  static const double _tyreRadius = 0.33, _tyreHalfWidth = 0.17;

  /// Where a car's wheels are from the middle of it, m: half its track
  /// across, and its axles fore and aft.
  static const double _halfTrack = 0.8, _frontAxle = 1.6, _rearAxle = -1.4;

  /// Car [index]'s four wheels followed into the world as tyres: carried
  /// each frame to where the car's wheels are, they part the water and
  /// knock the pieces of a wreck aside, and nothing they meet ever reaches
  /// the car — the race is stepped as it was.
  void _follow(int index) {
    final car = _cars[index];
    // A cylinder stands along its own y; a tyre's axle is the car's right.
    final axle = Quaternion.axisAngle(Vector3(0.0, 0.0, 1.0), math.pi / 2);
    final wheels = <Follower>[];
    for (var k = 0; k < 4; k++) {
      final across = k.isEven ? -_halfTrack : _halfTrack;
      final along = k < 2 ? _frontAxle : _rearAxle;
      wheels.add(
        _elements.follow(() {
          final right = car.visualBasis.getColumn(0);
          final up = car.visualBasis.getColumn(1);
          final forward = car.visualBasis.getColumn(2);
          final road = car.position - up * car.tuning.rideHeight;
          return (
            position:
                road + right * across + forward * along + up * _tyreRadius,
            orientation: Quaternion.fromRotation(car.visualBasis) * axle,
          );
        }, shape: const NativeShape.cylinder(_tyreRadius, _tyreHalfWidth)),
      );
    }
    _tireSet.add(wheels);
  }

  // ------------------------------------------------------------- the fires

  /// How hard, m/s taken out of a car in one step, a crash has to be to
  /// leave a wreck burning. A wall leant on at a corner throws sparks; this
  /// is a car arriving at one.
  static const double _wrecking = 14.0;

  /// How fast, m/s, a car has to have been going for a crash to wreck it:
  /// a little over seventy kilometres an hour.
  static const double _wreckingFrom = 20.0;

  /// A car that has just left a wreck does not leave another for this long,
  /// s: a car bouncing along a wall is one crash.
  static const double _between = 6.0;

  /// How far round the circuit each stretch of water lies, m, fords first.
  List<double> get waterAlong => <double>[for (final p in _pools) p.along];

  /// Car [index]'s wreck left where it stands now, as a hard crash there
  /// would leave it.
  void wreckNow(int index) =>
      _wreck(index, _cars[index].velocity.clone(), _cars[index].trackDistance);

  /// After every step of the race: a car struck hard enough leaves a wreck
  /// where it was struck. Read from how hard the race says it was pushed
  /// back and from how much speed it lost, never written to.
  void stepped(double seconds) {
    for (var i = 0; i < _cars.length; i++) {
      final car = _cars[i];
      _cooldown[i] = math.max(0.0, _cooldown[i] - seconds);
      final jump = car.position.distanceTo(_lastPosition[i]);
      // A car put back on the road: its tyres put there too, not swept
      // through everything between.
      if (jump >= 4.0) {
        for (final tyre in _tireSet[i]) {
          tyre.jump();
        }
      }
      // Along the road only: a car landing from a crest, or dropped back on
      // the road after a fall, loses its speed downwards, and that is the
      // springs' business, not a crash.
      final up = car.visualBasis.getColumn(1);
      final was = _lastVelocity[i] - up * _lastVelocity[i].dot(up);
      final now = car.velocity - up * car.velocity.dot(up);
      final before = was.length;
      // The speed taken out of the car along the way it was going, and no
      // more than it had: a car that bumps another and bounces back has its
      // velocity changed by more than its speed, and a nudge on the grid at
      // ten metres a second is not a crash that sets anything alight.
      final lost = before > 0.0
          ? math.min(before, before - now.dot(was) / before)
          : 0.0;
      // A car put back on the road moves metres in a step and changes its
      // speed to nothing; that is a respawn, not a crash. And a car has to
      // have been going fast to be wrecked by stopping.
      final hit = jump < 4.0 && before >= _wreckingFrom
          ? math.max(car.impactThisStep, lost)
          : 0.0;
      if (hit >= _wrecking && _cooldown[i] <= 0.0) {
        _cooldown[i] = _between;
        _wreck(i, _lastVelocity[i], car.trackDistance);
      }
      _lastVelocity[i].setFrom(car.velocity);
      _lastPosition[i].setFrom(car.position);
    }
  }

  late final DeviceMesh _tyreMesh = DeviceMesh.upload(
    _device,
    const CylinderShape(
      radiusTop: _tyreRadius,
      radiusBottom: _tyreRadius,
      height: 2.0 * _tyreHalfWidth,
      segments: 14,
    ).build(),
  );
  late final DeviceMesh _panelMesh = DeviceMesh.upload(
    _device,
    CuboidShape(size: Vector3(1.0, 0.06, 0.7)).build(),
  );

  /// The burnt-out car, as a tub with its parts lying broken about it: the
  /// tub is what the fire is on, the rest is drawn with it.
  late final DeviceMesh _tubMesh = _box(0.75, 0.3, 1.7);
  late final DeviceMesh _engineMesh = _box(0.6, 0.38, 0.6);
  late final DeviceMesh _noseMesh = _box(0.35, 0.16, 0.9);
  late final DeviceMesh _wingMesh = _box(0.9, 0.4, 0.06);
  DeviceMesh _box(double x, double y, double z) =>
      DeviceMesh.upload(_device, CuboidShape(size: Vector3(x, y, z)).build());
  late final DeviceMesh _scorchMesh = DeviceMesh.upload(
    _device,
    const CylinderShape(
      radiusTop: 2.2,
      radiusBottom: 2.2,
      height: 0.02,
      segments: 20,
    ).build(),
  );

  /// Petrol: its heat of combustion, 43.7 MJ/kg, and the absorption of its
  /// flame, 2.1 per metre (Babrauskas, "Heat release rates", SFPE Handbook,
  /// table of large pool burning); its specific heat as a liquid, about
  /// 2.2 kJ/(kg K); and a sooty flame, as rubber's is.
  static final NativeMaterial _petrol = NativeMaterial.rubber().copyWith(
    specificHeat: 2220.0,
    heatOfCombustion: 43.7e6,
    flameAbsorption: 2.1,
  );

  /// How fast spilt petrol burns off a large pool, kg/(m² s) (Babrauskas,
  /// SFPE Handbook), and the pool a racing car's ruptured tank leaves under
  /// it, m²: a car's floor.
  static const double _petrolBurns = 0.055, _spill = 1.5;

  /// Car [index]'s wreck, thrown along [velocity] — the car's speed before
  /// it struck: a floor where it crashed, the car's tub with the fuel from
  /// its split tank burning on it, a tyre and panels of its paint thrown
  /// off. What else catches catches from that fire.
  void _wreck(int index, Vector3 velocity, double along) {
    final car = _cars[index];
    final up = car.visualBasis.getColumn(1);
    final ground = car.position - up * car.tuning.rideHeight;
    // The road under it, from a little behind to well past where it
    // stopped, as slabs the pieces land and roll on: the road and its
    // verges, banked as they are.
    final first = (along / _slabLength).round();
    final floor = <int, TrackedBody>{
      for (var k = first - 3; k <= first + 8; k++) k: _slab(k),
    };
    // Laid along the road, banked as it is, and the hulk turned a little
    // across it, as a car that spun to a stop lies.
    _track.frameAt(along, _frame);
    final road = Quaternion.fromRotation(
      Matrix3.columns(_frame.right, _frame.up, _frame.forward),
    );
    final lying =
        road *
        Quaternion.axisAngle(
          Vector3(0.0, 1.0, 0.0),
          (_random.nextDouble() * 2.0 - 1.0) * 0.6,
        );
    // Burnt road: longer than it is wide, where the car slid as it burned,
    // and black at the heart of it, browner out to where the heat ended.
    RenderMaterial burnt(double r, double g, double b) => RenderMaterial(
      name: 'scorch',
      baseColor: LinearColor.fromSrgb(r, g, b, 1.0),
      roughness: 1.0,
    );
    final scorch =
        MeshNode(_scorchMesh, burnt(0.13, 0.12, 0.11), name: 'scorch')
          ..setPositionFrom(ground + up * 0.012)
          ..setRotation(road)
          ..setScale(0.75, 1.0, 1.3)
          ..castsShadow = false
          ..add(
            MeshNode(_scorchMesh, burnt(0.035, 0.032, 0.03), name: 'scorch')
              ..setPosition(0.0, 0.008, 0.25)
              ..setScale(0.55, 1.0, 0.6)
              ..castsShadow = false,
          );
    _scene.add(scorch);

    final pieces = <_Debris>[];
    final paint = index == 0
        ? Vector4(0.82, 0.82, 0.84, 1.0)
        : Looks.carPaint(index);
    _Debris piece(
      DeviceMesh mesh,
      Solid solid, {
      required Vector4 color,
      required double throwAt,
      bool stays = false,
    }) {
      final out = Vector3(
        _random.nextDouble() * 2.0 - 1.0,
        0.0,
        _random.nextDouble() * 2.0 - 1.0,
      );
      final node = MeshNode(
        mesh,
        RenderMaterial(
          name: 'wreck',
          baseColor: _fromSrgb(color),
          roughness: 0.6,
        ),
        name: 'wreck',
      );
      _scene.add(node);
      final thrown = stays
          ? null
          : velocity * throwAt +
                out * (2.0 + 3.0 * _random.nextDouble()) +
                up * (2.5 + 2.5 * _random.nextDouble());
      final tumbling = stays
          ? null
          : Vector3(
              _random.nextDouble() * 8.0 - 4.0,
              _random.nextDouble() * 8.0 - 4.0,
              _random.nextDouble() * 8.0 - 4.0,
            );
      final body = _elements.addBody(
        solid,
        at: stays ? ground + up * 0.16 : ground + up * 0.6 + out * 0.6,
        turn: stays ? lying : null,
        velocity: thrown,
        spin: tumbling,
        look: node,
        type: stays ? NativeBodyType.fixed : NativeBodyType.dynamic,
      );
      final debris = _Debris(body, node);
      pieces.add(debris);
      return debris;
    }

    // What is left of the car stays where it stopped: seventy kilograms of
    // carbon tub, rubber-like as fire sees it, the core of the fire.
    final tub = Vector3(0.375, 0.15, 0.85);
    final heap = piece(
      _tubMesh,
      Solid.box(
        tub,
        material: NativeMaterial.rubber(),
        density: 70.0 / (8.0 * tub.x * tub.y * tub.z),
      ),
      color: Vector4(0.12, 0.11, 0.1, 1.0),
      throwAt: 0.0,
      stays: true,
    );
    // The fuel from its split tank burns on it, as a pool of petrol does.
    _elements.fires.setBurner(
      heap.body,
      NativeBurner(fuel: _petrol, rate: _petrolBurns * _spill),
    );
    // What is left round the tub, in the tub's own colour, so it chars and
    // glows with it: the engine, the nose bent aside, the rear wing torn
    // half off, and a wheel still on its upright.
    final hulk = heap.node.material;
    MeshNode part(
      DeviceMesh mesh,
      Vector3 at, {
      double pitch = 0.0,
      double yaw = 0.0,
      double roll = 0.0,
    }) => MeshNode(mesh, hulk, name: 'wreck')
      ..setPositionFrom(at)
      ..setRotationYawPitchRoll(yaw, pitch, roll);
    heap.node
      ..add(part(_engineMesh, Vector3(0.0, 0.3, -0.45), pitch: 0.17, yaw: 0.14))
      ..add(part(_noseMesh, Vector3(0.14, -0.05, 1.2), yaw: 0.32, roll: -0.1))
      ..add(part(_wingMesh, Vector3(-0.2, 0.3, -1.0), pitch: -0.26, roll: 0.45))
      ..add(
        part(_tyreMesh, Vector3(0.58, 0.03, 0.55), roll: math.pi / 2)
          ..setUniformScale(0.9),
      );
    // A tyre torn off: eleven kilograms of rubber.
    final tyreVolume =
        math.pi * _tyreRadius * _tyreRadius * 2.0 * _tyreHalfWidth;
    piece(
      _tyreMesh,
      Solid.cylinder(
        _tyreRadius,
        _tyreHalfWidth,
        material: NativeMaterial.rubber(),
        density: 11.0 / tyreVolume,
      ),
      color: Vector4(0.05, 0.05, 0.05, 1.0),
      throwAt: 0.3,
    );
    // Bodywork: steel panels, six kilograms each, which do not burn.
    final panel = Vector3(0.5, 0.03, 0.35);
    for (var k = 0; k < (_light ? 1 : 2); k++) {
      piece(
        _panelMesh,
        Solid.box(
          panel,
          material: NativeMaterial.steel(),
          density: 6.0 / (8.0 * panel.x * panel.y * panel.z),
        ),
        color: paint,
        throwAt: 0.25,
      );
    }
    _wrecks.add(_Wreck(floor, pieces, heap, scorch, ground, along));
    // A circuit keeps a few; the oldest is cleared away.
    while (_wrecks.length > (_light ? 2 : 3)) {
      _clear(_wrecks.removeAt(0));
    }
  }

  /// How much of the circuit a slab of a wreck's floor stands for, m.
  static const double _slabLength = 4.0;

  /// Granite's density, kg/m³: what a slab of road is made of as heat
  /// sees it.
  static const double _stone = 2700.0;

  /// Slab [k] of road, the [_slabLength] metres of it [k] slabs round the
  /// circuit from the line, as wide as the road and both verges, its top the
  /// road's surface. A little longer than it stands for, so the slabs
  /// either side of a bend still meet.
  TrackedBody _slab(int k) {
    final s = (k * _slabLength) % _track.length;
    _track.frameAt(s, _frame);
    return _elements.addBody(
      Solid.box(
        Vector3(_track.widthAt(s) / 2.0 + _track.shoulder, 0.25, 2.3),
        material: NativeMaterial.stone(),
        density: _stone,
      ),
      at: _frame.position - _frame.up * 0.25,
      turn: Quaternion.fromRotation(
        Matrix3.columns(_frame.right, _frame.up, _frame.forward),
      ),
      type: NativeBodyType.fixed,
    );
  }

  /// Road laid under a piece of [wreck] at [at] and either side of it, if
  /// it is not there yet: counted from where the wreck is, so a piece that
  /// rolls on over the line is still on the same floor.
  void _floorUnder(_Wreck wreck, Vector3 at) {
    final length = _track.length;
    final s = _track.center.closestS(at, nearS: wreck.along, window: 80.0);
    final d = (s - wreck.along + length * 1.5) % length - length / 2;
    final k = ((wreck.along + d) / _slabLength).round();
    for (var n = k - 1; n <= k + 1; n++) {
      wreck.floor.putIfAbsent(n, () => _slab(n));
    }
  }

  /// How long a wreck is left on the circuit at most, s, burning or not.
  static const double _wreckLasts = 70.0;

  /// How long a wreck burns before the marshals reach it and put it out, s.
  static const double _burnsFor = 25.0;

  /// How much water a marshal's extinguisher puts on each piece, kg.
  static const double _extinguisher = 6.0;

  /// [wreck]'s fires put out, as the marshals do: the fuel's flame smothered
  /// and water onto every piece, which holds it at boiling until it has
  /// gone.
  void _douse(_Wreck wreck) {
    if (wreck.doused) return;
    wreck.doused = true;
    _elements.fires.setBurner(wreck.heap.body, null);
    for (final d in wreck.pieces) {
      _elements.fires.douse(d.body, _extinguisher);
    }
  }

  void _clear(_Wreck wreck) {
    wreck.pieces.forEach(_forgetPiece);
    wreck.floor.values.forEach(_elements.remove);
    _scene.remove(wreck.floorNode);
  }

  void _forgetPiece(_Debris d) {
    _elements.remove(d.body);
    _scene.remove(d.node);
  }

  // ------------------------------------------------------------ the dust

  /// Earth thrown up by a car off the road, hanging in the air behind it:
  /// lit and solid, so a car running wide leaves a cloud a pursuer drives
  /// into rather than a few specks.
  ///
  /// Thrown forward with a share of the car's own speed, [speed] m/s, and
  /// slowed by the air: so a car at speed draws one long cloud along its
  /// line, not a row of puffs left where it was each frame. One effect for
  /// every four metres a second, made the first time it is asked for.
  ParticleEffect _dustAt(double speed) => _thrown.putIfAbsent(
    ('dust', (speed / 4.0).round()),
    () => ParticleEffect(
      count: 1,
      emitter: ConeEmitter(
        speed: Range(0.6 + 0.2 * speed, 1.6 + 0.45 * speed),
        halfAngle: 30.0 * math.pi / 180.0,
      ),
      lifetime: const Range(1.8, 3.0),
      size: const Range(1.1, 1.8),
      color: Vector4(0.62, 0.53, 0.40, 0.45),
      affectors: <ParticleAffector>[
        const ParticleDrag(1.6),
        const ParticleGravity(0.25),
        const ParticleTurbulence(strength: 0.6, scale: 2.0),
        ParticleSizeCurve(ParticleCurve.linear(1.0, 3.4)),
        const ParticleFade(startsAt: 0.3),
      ],
    ),
  );

  /// The mist off a wet wheel, carried the same way.
  ParticleEffect _mistAt(double speed) => _thrown.putIfAbsent(
    ('mist', (speed / 4.0).round()),
    () => ParticleEffect(
      count: 1,
      emitter: ConeEmitter(
        speed: Range(2.0 + 0.2 * speed, 4.0 + 0.5 * speed),
        halfAngle: 35.0 * math.pi / 180.0,
      ),
      lifetime: const Range(0.5, 0.9),
      size: const Range(1.0, 1.7),
      color: Vector4(0.92, 0.95, 1.0, 0.18),
      affectors: <ParticleAffector>[
        const ParticleDrag(2.5),
        const ParticleGravity(-2.0),
        ParticleSizeCurve(ParticleCurve.linear(1.0, 2.6)),
        const ParticleFade(startsAt: 0.2),
      ],
    ),
  );

  final Map<(String, int), ParticleEffect> _thrown =
      <(String, int), ParticleEffect>{};

  /// Rubber smoke off a sliding or spinning wheel: pale and slow, and
  /// lingering on the line long after the car has gone.
  static final ParticleEffect _rubber = ParticleEffect(
    count: 1,
    emitter: const ConeEmitter(
      speed: Range(0.3, 1.2),
      halfAngle: 60.0 * math.pi / 180.0,
    ),
    lifetime: const Range(1.4, 2.4),
    size: const Range(0.6, 1.0),
    color: Vector4(0.88, 0.88, 0.9, 0.42),
    affectors: <ParticleAffector>[
      const ParticleDrag(1.8),
      const ParticleGravity(0.5),
      const ParticleTurbulence(strength: 0.5, scale: 1.5),
      ParticleSizeCurve(ParticleCurve.linear(1.0, 3.8)),
      const ParticleFade(startsAt: 0.25),
    ],
  );

  /// A broken car's engine smoking: dark, and the more broken the more of it.
  static final ParticleEffect _broken = ParticleEffect(
    count: 1,
    emitter: const ConeEmitter(
      speed: Range(0.8, 1.8),
      halfAngle: 20.0 * math.pi / 180.0,
    ),
    lifetime: const Range(1.0, 1.8),
    size: const Range(0.35, 0.6),
    color: Vector4(0.16, 0.15, 0.15, 0.55),
    affectors: <ParticleAffector>[
      const ParticleDrag(1.2),
      const ParticleTurbulence(strength: 0.4, scale: 1.0),
      ParticleSizeCurve(ParticleCurve.linear(1.0, 3.0)),
      const ParticleFade(startsAt: 0.3),
    ],
  );

  /// The drops in that mist: flung up and out off each tyre in a fan, and
  /// falling. Bright, because water in the sun is.
  static final ParticleEffect _drops = ParticleEffect(
    count: 1,
    emitter: const ConeEmitter(
      speed: Range(4.0, 11.0),
      halfAngle: 22.0 * math.pi / 180.0,
    ),
    lifetime: const Range(0.4, 0.8),
    size: const Range(0.05, 0.11),
    color: Vector4(0.9, 0.95, 1.0, 0.9),
    affectors: <ParticleAffector>[
      const ParticleGravity(),
      const ParticleDrag(0.6),
      const ParticleFade(startsAt: 0.5),
    ],
  );

  /// The sheet a front tyre throws aside as it cuts into the water: fast,
  /// low and spreading, falling back within a few metres of the car.
  static final ParticleEffect _bow = ParticleEffect(
    count: 1,
    emitter: const ConeEmitter(
      speed: Range(3.0, 8.0),
      halfAngle: 28.0 * math.pi / 180.0,
    ),
    lifetime: const Range(0.35, 0.7),
    size: const Range(0.04, 0.09),
    color: Vector4(0.88, 0.93, 1.0, 0.8),
    affectors: <ParticleAffector>[
      const ParticleGravity(),
      const ParticleDrag(1.2),
      const ParticleFade(startsAt: 0.4),
    ],
  );

  /// How far the wheels must slip, as `Reactions` reads it, before rubber
  /// smoke hangs behind them; and how fast a car must go before it throws
  /// up anything at all, m/s.
  static const double _slipping = 0.3, _sliding = 0.2, _moving = 3.0;

  /// Each car's dust, smoke and spray for this frame.
  void _throwUp(List<RacerProgress> progress) {
    for (var i = 0; i < _cars.length; i++) {
      final car = _cars[i];
      final up = car.visualBasis.getColumn(1);
      final p = car.position;
      final patch = p - up * car.tuning.rideHeight;
      final speed = car.speed;
      final going = (speed / 25.0).clamp(0.0, 1.0);
      final back = speed > 0.5
          ? -car.velocity.normalized()
          : -car.visualBasis.getColumn(2);
      final behind = patch + back * 1.6 + up * 0.2;
      final offRoad = i < progress.length && progress[i].offRoad;
      final moving = car.isGrounded && speed > _moving;

      final wet = _wading(car, patch);
      _wet[i] = wet;
      final sliding =
          car.slipRatio.abs() > _slipping || car.slipAngle.abs() > _sliding;
      final dust = moving && offRoad && !wet;
      final rubber = moving && !offRoad && !wet && sliding;
      _haze
        ..emit(
          ('dust', i),
          _dustAt(speed),
          behind,
          perSecond: dust ? 16.0 + 50.0 * going : 0.0,
          direction: up * 0.35 - back,
        )
        ..emit(
          ('rubber', i),
          _rubber,
          behind,
          perSecond: rubber
              ? 6.0 +
                    24.0 *
                        math
                            .max(car.slipRatio.abs(), car.slipAngle.abs() * 1.5)
                            .clamp(0.0, 1.0)
              : 0.0,
          direction: up,
        );
      // Dark from a car the race says is broken: its own number, read.
      final damage = car.damage;
      _haze.emit(
        ('broken', i),
        _broken,
        p + up * 0.5 + back * 1.4,
        perSecond: damage > 0.3 ? 4.0 + 18.0 * damage : 0.0,
        direction: up + back * 0.4,
      );
      final throwing = wet && moving;
      _haze.emit(
        ('mist', i),
        _mistAt(speed),
        behind,
        perSecond: throwing ? 30.0 + 90.0 * going : 0.0,
        direction: up * 0.6 - back * 0.6,
      );
      // A fan off each rear wheel, out to its own side; and the bow wave
      // of each front wheel, thrown out low and flat on either side. The
      // water's own surface stays low, and the height of a car going
      // through a ford is all in these.
      final right = car.visualBasis.getColumn(0);
      final ahead = car.visualBasis.getColumn(2);
      for (final side in <double>[-1.0, 1.0]) {
        _spray.emit(
          ('drops', i, side),
          _drops,
          behind + right * (0.8 * side),
          perSecond: throwing ? 80.0 + 220.0 * going : 0.0,
          direction: up + right * (0.9 * side) + back * 0.3,
        );
        _spray.emit(
          ('bow', i, side),
          _bow,
          patch + ahead * (_frontAxle + 0.3) + right * (1.0 * side) + up * 0.1,
          perSecond: throwing ? 60.0 + 260.0 * going : 0.0,
          direction: up * 0.45 + right * side + ahead * 0.15,
        );
      }
    }
  }

  /// Whether [car], its tyres on the road at [patch], is driving through
  /// water. Asked just outside its wheels rather than under them: the tyres
  /// followed into the water push it out of the furrows they run in, and
  /// leave it shallow there.
  bool _wading(SphereVehicle car, Vector3 patch) {
    final right = car.visualBasis.getColumn(0);
    for (final side in <double>[-1.3, 1.3]) {
      final x = patch.x + right.x * side, z = patch.z + right.z * side;
      for (final pool in _pools) {
        if (!pool.near(x, z, 0.0)) continue;
        final here = pool.water.sample(Vector3(x, patch.y, z));
        if (here != null &&
            here.depth > 0.015 &&
            here.surface > patch.y - 0.1) {
          return true;
        }
      }
    }
    return false;
  }

  /// Whether each car was driving through water this frame.
  final List<bool> _wet = <bool>[];

  // ------------------------------------------------------------ the frame

  /// The frame: the water and the fires on by [dt], every car's spray, dust
  /// and smoke thrown, everything drawn from [eye].
  void frame(
    double dt, {
    required Vector3 eye,
    required List<RacerProgress> progress,
  }) {
    if (dt <= 0.0) return;
    final step = math.min(dt, 1.0 / 30.0);
    _elements.update(step, eye: eye);
    for (final wreck in _wrecks) {
      wreck.age += step;
      if (wreck.age > _burnsFor) _douse(wreck);
      wreck.pieces.removeWhere((d) {
        final at = _elements.world.localPositionOf(d.body.native);
        // Over the edge of the embankment and out of the world this layer
        // knows: let go rather than fall for ever.
        final lost = at.y < wreck.ground.y - 8.0;
        if (lost) {
          _forgetPiece(d);
        } else {
          _floorUnder(wreck, at);
        }
        return lost;
      });
    }
    _wrecks.removeWhere((w) {
      final out =
          w.age > _wreckLasts ||
          (w.age > 30.0 &&
              !w.pieces.any((d) => _elements.world.isBurning(d.body.native)));
      if (out) _clear(w);
      return out;
    });
    _throwUp(progress);
    // The drops fall as the circuit's world does.
    _spray.gravity = _elements.world.gravityMagnitude;
    _haze.advance(step);
    _spray.advance(step);
  }

  // ------------------------------------------------------------- the sound

  /// A crackle held to every fire, as loud as its heat.
  final HeldVoices _fires = HeldVoices(ElementSounds.fire);

  /// The wash of each car's wheels, held while it ploughs through water.
  final HeldVoices _washes = HeldVoices(ElementSounds.wash);

  /// What this frame sounds like, played on [scene]: a crackle held to every
  /// fire, a splash where a car or a piece of a wreck hits the water, and
  /// the wash of a car's wheels for as long as it ploughs through it.
  /// Called before the scene is updated for the frame.
  void hear(AudioScene scene, double dt) {
    final hearing = _elements.hearing!;
    _fires.hold(scene, <Held>[
      for (final f in hearing.fires)
        (key: f.key, at: f.at, gain: f.loudness, rate: f.rate),
    ]);
    for (final s in hearing.splashes) {
      scene.play(ElementSounds.splash, s.at)
        ..gain = s.loudness
        ..rate = s.rate;
    }
    final washing = <Held>[];
    for (var i = 0; i < _cars.length; i++) {
      final car = _cars[i];
      final wader = _waders[i];
      final p = car.position;
      final wet = _wet[i];
      final speed = car.speed;
      wader.hush = math.max(0.0, wader.hush - dt);
      // Into the water at speed: a splash as loud as the car is fast.
      if (wet && !wader.wet && speed > 4.0 && wader.hush <= 0.0) {
        wader.hush = 0.4;
        scene.play(ElementSounds.splash, p)
          ..gain = (speed / 40.0).clamp(0.3, 1.0)
          ..rate = 0.8 + 0.2 * _random.nextDouble();
      }
      wader.wet = wet;
      if (wet && speed > 3.0) {
        washing.add((
          key: i,
          at: p,
          gain: (speed / 35.0).clamp(0.2, 1.0),
          rate: 0.9 + 0.3 * (speed / 60.0).clamp(0.0, 1.0),
        ));
      }
    }
    _washes.hold(scene, washing);
  }

  /// Everything let go: the sounds stopped, the particles no longer drawn,
  /// the world freed. The scene goes with the circuit.
  void dispose() {
    _fires.silence();
    _washes.silence();
    _contributors.forEach(_renderer.renderSteps.removeContributor);
    _elements.dispose();
  }
}

/// A `Vector4` holding a colour sRGB-encoded, as the linear colour it names.
LinearColor _fromSrgb(Vector4 c) => LinearColor.fromSrgb(c.x, c.y, c.z, c.w);
