import 'dart:math' as math;

import 'package:flutter/painting.dart' show Color;
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart'
    show
        FluidMedium,
        FluidWorld,
        LiquidBody,
        LiquidLayer,
        PlaneObstacle,
        RevolvedVessel,
        VesselVolumes,
        fallTime,
        overCircularLip;
import 'package:vector_math/vector_math.dart';

import 'glassware.dart';
import 'label.dart';
import 'optics.dart';

/// One piece of glass on the bench and what is in it.
final class Vessel {
  Vessel({
    required this.name,
    required this.at,
    required this.glass,
    required this.inside,
    required this.dye,
    required this.startLevel,
    required this.lowest,
    required this.highest,
    this.solution,
    this.foot,
  });

  /// What the controls call it.
  final String name;

  /// Where its base stands.
  final Vector3 at;

  /// Its outline, swept into the glass, and the inside the liquid fills.
  final List<Vector2> glass;
  final List<Vector2> inside;

  /// A plastic foot it stands on, swept with six segments; null for none.
  final List<Vector2>? foot;

  /// The colour of the solution it starts with, which is also the dye that
  /// colours it: see [Bench.colourOf]. White for none.
  final Color dye;

  /// How full it starts, and how far it may be filled, in metres up from
  /// its base.
  final double startLevel;
  final double lowest;
  final double highest;

  /// What its label says; null for glass that wears none.
  final Solution? solution;

  /// How far it leans, in radians, and about which horizontal axis. State.
  double tilt = 0.0;
  Vector3 leanAxis = Vector3(1, 0, 0);

  /// How far it is lifted out of the row to lean, from nought, standing in
  /// its place, to one, clear of the other glass. State: [Bench.step] moves
  /// it.
  double lift = 0.0;

  /// The inside as the liquid sees it.
  late final RevolvedVessel shape = RevolvedVessel(inside);

  /// What is in it, as the physics has it.
  late final LiquidBody liquid;

  /// How full it is now, upright.
  double get level =>
      liquid.volume > 0.0 ? shape.levelFor(liquid.volume) : shape.floor;

  /// The lowest point of the mouth once the glass leans towards the front:
  /// the edge of the inside, on the side it leans to.
  Vector3 get lip => Vector3(0, inside.last.y, inside.last.x);

  /// The glass and all it carries, which tilts as one; and the same hung
  /// upside down under the tabletop, for the reflections.
  late final SceneNode body;
  late final SceneNode mirror;

  /// One node per layer of liquid, and its reflection.
  final List<({MeshNode node, MeshNode reflection, Color colour})> layers = [];

  MeshNode? label;
  MeshNode? labelReflection;

  /// The card on the bench that carries where its light went; see [Bench].
  late final MeshNode shadow;

  /// Its glass, as drawn.
  late final MeshNode glassNode;

  /// What the liquid was drawn as: redrawn when any of it moves.
  double _drawnVolume = -1.0;
  double _drawnTilt = double.nan;
  double _drawnLift = double.nan;
}

Vector3 _rgb(Color c) => Vector3(c.r, c.g, c.b);

/// The name of the empty tube at the front of the bench, which solutions
/// are poured into.
const String cleanTube = 'Clean tube';

/// Five labelled test tubes, a clean one, a graduated cylinder, a beaker and
/// an Erlenmeyer flask, each holding a solution of its own colour.
List<Vessel> standardVessels() {
  final solutions = <Solution>[
    (
      tex: r'\mathrm{HCl}',
      note: '0.1 mol/L',
      band: const Color(0xFFD9483B),
      colour: const Color(0xFFD1E6F2),
    ),
    (
      tex: r'\mathrm{CuSO_4}',
      note: '0.5 mol/L',
      band: const Color(0xFF2F6FD6),
      colour: const Color(0xFF1A6BF2),
    ),
    (
      tex: r'\mathrm{KMnO_4}',
      note: '0.02 mol/L',
      band: const Color(0xFF8E3FB5),
      colour: const Color(0xFF800A6B),
    ),
    (
      tex: r'\mathrm{K_2Cr_2O_7}',
      note: '0.1 mol/L',
      band: const Color(0xFFE38A1C),
      colour: const Color(0xFFFA730D),
    ),
    (
      tex: r'\mathrm{NiCl_2}',
      note: '0.2 mol/L',
      band: const Color(0xFF3C9A4B),
      colour: const Color(0xFF33BF4D),
    ),
  ];
  return <Vessel>[
    for (var i = 0; i < solutions.length; i++)
      Vessel(
        name: solutions[i].tex.replaceAll(RegExp(r'\\mathrm|[{}_]'), ''),
        at: Vector3(-0.044 + i * 0.022, 0, 0.015),
        glass: tubeProfile(),
        inside: tubeInside(),
        dye: solutions[i].colour,
        startLevel: 0.036 + 0.005 * (i % 3),
        lowest: 0.003,
        highest: 0.08,
        solution: solutions[i],
      ),
    Vessel(
      name: cleanTube,
      at: Vector3(0.011, 0, 0.062),
      glass: tubeProfile(),
      inside: tubeInside(),
      dye: const Color(0xFFFFFFFF),
      startLevel: 0.0,
      lowest: 0.0,
      highest: 0.08,
    ),
    Vessel(
      name: 'Cylinder',
      at: Vector3(-0.105, 0, -0.025),
      glass: cylinderProfile(),
      foot: cylinderFoot(),
      inside: cylinderInside(),
      dye: const Color(0xFFF2D91A),
      startLevel: 0.062,
      lowest: 0.005,
      highest: 0.084,
    ),
    Vessel(
      name: 'Beaker',
      at: Vector3(0.078, 0, -0.015),
      glass: beakerProfile(),
      inside: beakerInside(),
      dye: const Color(0xFFF24D8C),
      startLevel: 0.027,
      lowest: 0.002,
      highest: 0.04,
    ),
    Vessel(
      name: 'Flask',
      at: Vector3(0.132, 0, -0.045),
      glass: flaskProfile(),
      inside: flaskInside(),
      dye: const Color(0xFFB35214),
      startLevel: 0.022,
      lowest: 0.003,
      highest: 0.04,
    ),
  ];
}

/// The bench: a table, the glass, the liquids, the labels and the light.
///
/// **What is in the glass is physics** (`flutter3d_physics`): each vessel's
/// liquid is a `LiquidBody`, and the bench is one `FluidWorld` under Earth's
/// gravity, stepped at a fixed step — so a surface keeps level and rocks
/// when the glass is turned, a tap starts rings, liquid tipped far enough
/// runs over the lip as a stream that falls, thins, runs down the glass it
/// meets and lands, and what lands mixes. This class draws it
/// (`liquidMeshes`, `jetMesh`, `particleMesh`) and decides what the hand
/// does; the liquid decides the rest.
///
/// **A solution's colour is its dyes'.** Each starting solution is a dye at
/// unit concentration whose absorbance is what makes [Vessel.dye] its colour
/// over [fade] of it, by Beer and Lambert; poured together, concentrations
/// add by volume (the physics keeps them) and so do absorbances, so a
/// mixture is the colour light through both would be.
///
/// **The shadows are worked out, not guessed.** A vessel is a surface of
/// revolution, so the sunlight through it can be followed by geometric
/// optics in each horizontal cut (see `optics.dart`) and painted on a card
/// on the bench along its shadow; or, with [photons], the engine follows
/// photons through the liquid instead.
///
/// **The reflections in the tabletop are geometry too**: each liquid and
/// label again, scaled by −1 in height so it hangs under the top, laid over
/// it at a twelfth of its strength and only where it is behind it.

final class Bench {
  Bench(this.device, {List<Vessel>? vessels, bool photons = false})
    : vessels = vessels ?? standardVessels(),
      _photons = photons {
    for (final vessel in this.vessels) {
      vessel
        ..body = (SceneNode(name: vessel.name)..setPositionFrom(vessel.at))
        ..mirror = (SceneNode(name: '${vessel.name} reflection')
          ..setPositionFrom(vessel.at)
          ..setScale(1, -1, 1));
      scene
        ..add(vessel.body)
        ..add(vessel.mirror);
      final white = vessel.dye.toARGB32() == 0xFFFFFFFF;
      vessel.liquid = LiquidBody(
        shape: vessel.shape,
        medium: FluidMedium.water,
        volume: vessel.startLevel > vessel.shape.floor
            ? vessel.shape.volumeUpTo(vessel.startLevel)
            : 0.0,
        concentrations: white ? const {} : {vessel.name: 1.0},
        modes: 8,
        surfaceCells: 24,
        wallThickness: glassThickness,
      );
      if (!white) _dyes[vessel.name] = _absorbance(vessel.dye);
      world.bodies.add(vessel.liquid);
      vessel.shadow =
          MeshNode(
              _card(vessel),
              Material(
                name: 'shadow card',
                lighting: LightingModel.pbrLayered,
                baseColor: Vector4(_lightScale, _lightScale, _lightScale, 1.0),
                albedo: uploadRgba8(device, _picture(vessel)),
                extensions: MaterialExtensions(transmission: 1.0, ior: 1.0),
              ),
              name: '${vessel.name} shadow',
            )
            ..setPositionFrom(vessel.at)
            ..shadowCasting = ShadowCastingMode.shadowsOnly;
      if (!photons) scene.add(vessel.shadow);
      vessel.body.add(
        vessel.glassNode =
            MeshNode(
                _lathe(glassWall(vessel.glass)),
                glass(),
                name: '${vessel.name} glass',
              )
              ..castsShadow = photons
              ..receivesTranslucentShadows = false
              ..lightChannels = _vesselChannel,
      );
      final foot = vessel.foot;
      if (foot != null) {
        final hexagon = DeviceMesh.upload(
          device,
          LatheShape(profile: foot, segments: 6).build(),
        );
        vessel.body.add(
          MeshNode(hexagon, footPlastic(), name: '${vessel.name} foot')
            ..lightChannels = _vesselChannel,
        );
        vessel.mirror.add(
          _mirrored(
            hexagon,
            _reflection(albedo: null, colour: Vector3(0.2, 0.42, 0.8)),
            vessel,
          ),
        );
      }
      _place(vessel);
      vessel.liquid.place(_turnOf(vessel), vessel.body.readPosition());
      _redraw(vessel);
    }
    final environment = EnvironmentMap.fromSky(device, labSky);
    if (environment != null) {
      scene
        ..environment = environment.texture
        ..environmentLevels = environment.levels
        // The sun carries most of the light, as through a lab window: the
        // coloured shadows tint only the sun's share, and under a sky as
        // bright as the sun they were barely there.
        ..ambientIntensity = 0.55;
    }
    scene
      ..add(
        MeshNode(
            DeviceMesh.upload(
              device,
              CuboidShape(size: Vector3(0.6, 0.004, 0.44)).build(),
            ),
            Material(
              name: 'bench',
              baseColor: Vector4(0.46, 0.45, 0.43, 1.0),
              roughness: 0.25,
            ),
            name: 'bench',
          )
          ..setPosition(0, -0.002, 0.06)
          // A floor casts nothing.
          ..castsShadow = false
          // Its own channel: the sun reaches every channel, and the fill
          // only the glass.
          ..lightChannels = _benchChannel,
      )
      ..add(
        LightNode(name: 'sun', intensity: 2.6)
          ..setLocalForward(Vector3(-0.5, -1.0, -0.6)),
      )
      ..add(
        // The fill lights the glass from the front, not the bench: it
        // shines towards the camera, and on a glossy tabletop its highlight
        // was a white smear across the near corner.
        LightNode(name: 'fill', intensity: 0.9)
          ..setLocalForward(Vector3(0.6, -0.4, 0.8))
          ..channels = _vesselChannel,
      );
  }

  final GraphicsDevice device;
  final Scene scene = Scene();

  /// The liquids, under Earth's gravity, over the bench's top.
  final FluidWorld world = FluidWorld(
    gravity: Vector3(0, -9.81, 0),
    particleSpacing: 0.001,
    floor: [PlaneObstacle(normal: Vector3(0, 1, 0), offset: 0.0)],
  );

  /// Whether the shadows come from the engine's caustics
  /// (`ShadowSettings.caustics`, drawn with [settings]) rather than from the
  /// cards this bench works out itself.
  bool get photons => _photons;
  bool _photons;

  set photons(bool value) {
    if (value == _photons) return;
    _photons = value;
    for (final vessel in vessels) {
      _castBy(vessel);
    }
  }

  /// How this bench is drawn.
  RenderSettings get settings => photons ? photonSettings : benchSettings;
  final List<Vessel> vessels;

  /// How a replaced mesh is let go of: after the frames still drawing it
  /// when there is a renderer (`Renderer.releaseMeshAfterFrame`), at once
  /// when there is none.
  void Function(DeviceMesh mesh)? retire;

  /// How a replaced shadow picture is let go of: after the frames still
  /// sampling it when there is a renderer
  /// (`Renderer.releaseTextureAfterFrame`), and kept when there is none.
  void Function(TextureHandle texture)? retireTexture;

  void _releaseNow(DeviceMesh mesh) => device
    ..releaseGeometry(mesh.vertices)
    ..releaseGeometry(mesh.indices);

  void _swap(MeshNode node, MeshData data) {
    final old = node.mesh;
    node.mesh = DeviceMesh.upload(device, data);
    if (old is DeviceMesh) (retire ?? _releaseNow)(old);
  }

  DeviceMesh _lathe(List<Vector2> profile) => DeviceMesh.upload(
    device,
    LatheShape(profile: profile, segments: 64).build(),
  );

  // --------------------------------------------------------------- colour

  /// Each dye's absorbance per metre at unit concentration: what makes it
  /// its colour over [fade] of it.
  final Map<String, Vector3> _dyes = {};

  static Vector3 _absorbance(Color colour) {
    double mu(double c) => -math.log(c.clamp(1e-3, 1.0)) / fade;
    return Vector3(mu(colour.r), mu(colour.g), mu(colour.b));
  }

  /// The colour of [layer]: light through [fade] of it, every dye in it
  /// taking its share by Beer and Lambert.
  Color colourOf(LiquidLayer layer) {
    final absorb = Vector3.zero();
    layer.concentrations.forEach((dye, c) {
      final mu = _dyes[dye];
      if (mu != null) absorb.addScaled(mu, c);
    });
    double through(double mu) => math.exp(-mu * fade);
    return Color.from(
      alpha: 1.0,
      red: through(absorb.x),
      green: through(absorb.y),
      blue: through(absorb.z),
    );
  }

  /// The colour of what [vessel] holds at its surface.
  Color colour(Vessel vessel) {
    final layers = vessel.liquid.layers;
    return layers.isEmpty ? vessel.dye : colourOf(layers.last);
  }

  // ------------------------------------------------------------- the hand

  /// Fills [vessel] to [level]: liquid poured in or drawn off, the same
  /// solution it holds.
  void pour(Vessel vessel, double level) {
    if (busy) return;
    final target = vessel.shape.volumeUpTo(
      level.clamp(vessel.lowest, vessel.highest),
    );
    final now = vessel.liquid.volume;
    if (target > now) {
      final layers = vessel.liquid.layers;
      vessel.liquid.pour(
        target - now,
        concentrations: layers.isEmpty
            ? (vessel.dye.toARGB32() == 0xFFFFFFFF
                  ? const {}
                  : {vessel.name: 1.0})
            : layers.last.concentrations,
      );
    } else if (target < now) {
      vessel.liquid.drain(now - target);
    }
    _redraw(vessel);
    if (!photons && vessel.tilt == 0.0) _repaint(vessel);
  }

  /// The furthest [vessel] may lean either way: a little short of where what
  /// it holds reaches the lip and would run out on the bench.
  double maxLean(Vessel vessel) => math.max(
    0.05,
    math.min(1.45, _tiltHolding(vessel, vessel.liquid.volume) - 0.08),
  );

  /// How far [vessel] must be lifted to lean as it does without passing
  /// through the glass standing round it.
  ///
  /// Walked up its axis: wherever the tipped glass is over another vessel's
  /// footprint, its underside there has to clear that vessel's top by a
  /// millimetre. A vessel leaning away from its neighbours is hardly lifted;
  /// one leaning over a row of tubes goes over their mouths.
  double _clearance(Vessel vessel) {
    if (vessel.tilt == 0.0) return 0.0;
    final turn = Matrix3.zero()
      ..setFrom(
        Quaternion.axisAngle(vessel.leanAxis, vessel.tilt).asRotationMatrix(),
      );
    final top = vessel.glass.map((p) => p.y).reduce(math.max);
    final sideways = math.sin(vessel.tilt).abs();
    var lowest = double.infinity;
    for (final p in [...vessel.glass, ...?vessel.foot]) {
      for (var k = 0; k < 24; k++) {
        final a = 2.0 * math.pi * k / 24;
        lowest = math.min(
          lowest,
          turn
              .transformed(Vector3(p.x * math.cos(a), p.y, p.x * math.sin(a)))
              .y,
        );
      }
    }
    var need = 0.0;
    for (var i = 0; i <= 48; i++) {
      final h = top * i / 48;
      final r = radiusAt(vessel.glass, h) ?? 0.0;
      final axis = turn.transformed(Vector3(0, h, 0));
      // Its underside here, standing on the bench before any lift.
      final under = axis.y - lowest - r * sideways;
      for (final other in vessels) {
        if (identical(other, vessel) || other.tilt != 0.0) continue;
        // Its footprint: the glass, or the foot it stands on if wider.
        final reach = [
          ...other.glass,
          ...?other.foot,
        ].map((p) => p.x).reduce(math.max);
        final dx = vessel.at.x + axis.x - other.at.x;
        final dz = vessel.at.z + axis.z - other.at.z;
        if (math.sqrt(dx * dx + dz * dz) > reach + r + 0.001) continue;
        final otherTop = other.glass.map((p) => p.y).reduce(math.max);
        need = math.max(need, otherTop + 0.001 - under);
      }
    }
    return need;
  }

  /// Leans [vessel] by [angle] radians about [across], a horizontal axis —
  /// the way the camera looks, so it leans in the picture — after lifting
  /// it out of the row ([step] lifts and lowers it). The glass turns at
  /// once; the liquid keeps level and follows late, as liquid does.
  void lean(Vessel vessel, double angle, {Vector3? across}) {
    if (busy) return;
    final limit = maxLean(vessel);
    vessel.tilt = angle.clamp(-limit, limit);
    if (across != null) {
      final flat = Vector3(across.x, 0, across.z);
      if (flat.length2 > 1e-9) vessel.leanAxis = flat..normalize();
    }
    // One vessel in the hand: leaning this one puts the last one back.
    if (vessel.tilt != 0.0) {
      for (final other in vessels) {
        if (identical(other, vessel) || other.tilt == 0.0) continue;
        other.tilt = 0.0;
        _place(other);
        _castBy(other);
      }
    }
    _place(vessel);
    _castBy(vessel);
  }

  /// Puts [vessel]'s glass where its lean and lift say: turned about its
  /// lean axis, raised by its lift, its lowest point on the bench when the
  /// lift is nought.
  void _place(Vessel vessel) {
    final turn = Quaternion.axisAngle(vessel.leanAxis, vessel.tilt);
    // The lowest point of the glass, and of its foot, once turned.
    var lowest = double.infinity;
    for (final p in [...vessel.glass, ...?vessel.foot]) {
      for (var k = 0; k < 24; k++) {
        final a = 2.0 * math.pi * k / 24;
        final turned = turn.rotated(
          Vector3(p.x * math.cos(a), p.y, p.x * math.sin(a)),
        );
        lowest = math.min(lowest, turned.y);
      }
    }
    final lift = _ease(vessel.lift) * _clearance(vessel);
    final y = vessel.at.y - lowest + lift;
    vessel.body
      ..setRotation(turn)
      ..setPosition(vessel.at.x, y, vessel.at.z);
    // The mirror of a turn about a horizontal axis is the opposite turn.
    vessel.mirror
      ..setRotation(Quaternion.axisAngle(vessel.leanAxis, -vessel.tilt))
      ..setPosition(vessel.at.x, -y, vessel.at.z);
  }

  /// [vessel]'s turn as a matrix, for the physics.
  static Matrix3 _turnOf(Vessel vessel) {
    final m = vessel.body.localMatrix;
    return Matrix3(
      m.entry(0, 0),
      m.entry(1, 0),
      m.entry(2, 0), //
      m.entry(0, 1),
      m.entry(1, 1),
      m.entry(2, 1), //
      m.entry(0, 2),
      m.entry(1, 2),
      m.entry(2, 2),
    );
  }

  /// Knocks on [vessel]'s glass: half a millimetre of ripple where the
  /// knock lands on the surface.
  void tap(Vessel vessel) => vessel.liquid.surface.knock(
    vessel.liquid.up * vessel.liquid.height,
    0.0005,
  );

  // ------------------------------------------------------------ the pour

  /// Whether a pour is under way, during which the controls wait.
  bool get busy => _transfer != null;
  _Transfer? _transfer;

  /// The tube solutions are poured into.
  Vessel get clean => vessels.firstWhere((v) => v.name == cleanTube);

  /// Whether [from] can be poured into the [clean] tube until the two hold
  /// the same: it has more, and half of both fits.
  bool canShare(Vessel from) {
    // The clean tube stands upright to be poured into.
    if (busy || identical(from, clean) || clean.tilt != 0.0) return false;
    final mine = from.liquid.volume;
    final theirs = clean.liquid.volume;
    return mine > theirs + 1e-8 &&
        (mine + theirs) / 2.0 <= clean.shape.capacity;
  }

  /// Pours [from] into the [clean] tube until the two hold the same: lifts
  /// it over the bench, tips it over the tube's mouth as far as it takes to
  /// pour that much and no faster, and puts it back. [step] plays it; the
  /// liquid itself runs, falls and lands by the physics.
  void share(Vessel from) {
    if (!canShare(from)) return;
    final mine = from.liquid.volume;
    final theirs = clean.liquid.volume;
    from
      ..tilt = 0.0
      ..lift = 0.0
      ..leanAxis = Vector3(1, 0, 0);
    _transfer = _Transfer(
      from: from,
      to: clean,
      start: mine,
      goal: (mine + theirs) / 2.0,
    )..spill = _tiltHolding(from, mine);
    _castBy(from);
  }

  /// How long each part of a pour takes: up, over, and back; the pour
  /// itself is as long as the hand takes, about two seconds.
  static const double _rise = 0.45;
  static const double _over = 1.2;
  static const double _pourTime = 2.0;
  static const double _back = 1.4;

  /// The world's up seen from glass leaning [tilt] towards the front.
  static Vector3 _upAt(double tilt) =>
      Vector3(0, math.cos(tilt), -math.sin(tilt));

  /// The lean at which [vessel] holds just [volume]: past it, the rest runs
  /// out. Holding less the further it leans, so found by halving.
  static double _tiltHolding(Vessel vessel, double volume) {
    var lo = 0.0;
    var hi = 2.8;
    for (var i = 0; i < 36; i++) {
      final mid = 0.5 * (lo + hi);
      if (vessel.shape.holds(_upAt(mid)) > volume) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return 0.5 * (lo + hi);
  }

  static double _ease(double t) {
    final x = t.clamp(0.0, 1.0);
    return x * x * (3.0 - 2.0 * x);
  }

  /// Places [vessel]'s glass with its base at [base], leaning [tilt].
  void _pose(Vessel vessel, Vector3 base, double tilt) {
    vessel.body
      ..setRotation(Quaternion.axisAngle(Vector3(1, 0, 0), tilt))
      ..setPositionFrom(base);
    vessel.mirror
      ..setRotation(Quaternion.axisAngle(Vector3(1, 0, 0), -tilt))
      ..setPosition(base.x, -base.y, base.z);
  }

  /// One frame of the hand's part in a pour: where the glass is, and how
  /// far it leans. The hand tips further while less runs than it wants and
  /// back while more does, wanting the root of what is left, so the pour
  /// ends at the edge of pouring; the flow itself is the liquid's.
  void _handStep(_Transfer t, double seconds) {
    final from = t.from;
    final to = t.to;
    t.time += seconds;
    final raised = from.at + Vector3(0, 0.1, 0);
    // **Lip to lip, as a chemist pours.** The lip goes a millimetre over the
    // clean tube's rim, back from the middle by half of how far the stream
    // is carried forward while it falls to the surface, so it enters through
    // the mouth and lands near the middle; never further back than the
    // inside of the wall.
    //
    // **Planned once, and held.** Worked out from the flow the hand means
    // to pour, not the flow it sees: answering the flow as it came, the aim
    // jumped when the liquid first ran, the hand jerked the glass with it,
    // and the jerk threw the rest out.
    final aim = t.aim ??= () {
      final rim = to.glass.map((p) => p.y).reduce(math.max);
      final most = 1.5 * (t.start - t.goal) / _pourTime;
      final over = overCircularLip(
        flow: most,
        radius: from.lip.z,
        tilt: t.spill,
        g: 9.81,
      );
      final thrown =
          Vector3(0, math.cos(t.spill), math.sin(t.spill)) * over.speed;
      final drift =
          thrown.z *
          fallTime(thrown, to.at.y + rim + 0.001, to.at.y + to.level);
      final back = math.min(0.5 * drift, to.lip.z - 0.001);
      return to.at + Vector3(0, rim + 0.001, -back);
    }();
    Vector3 baseFor(double tilt) {
      final c = math.cos(tilt);
      final s = math.sin(tilt);
      final lip = from.lip;
      return aim - Vector3(0, lip.y * c - lip.z * s, lip.y * s + lip.z * c);
    }

    var base = from.at.clone();
    var tilt = 0.0;
    final time = t.time;
    if (time < _rise) {
      base = from.at + (raised - from.at) * _ease(time / _rise);
    } else if (time < _rise + _over) {
      final e = _ease((time - _rise) / _over);
      tilt = t.spill * e;
      base = raised + (baseFor(tilt) - raised) * e;
    } else if (t.poured == null) {
      final start = _rise + _over;
      if (t.hand == 0.0) t.hand = t.spill;
      final amount = t.start - t.goal;
      final most = 1.5 * amount / _pourTime;
      final remaining = math.max(from.liquid.volume - t.goal, 0.0);
      final wanted =
          most *
          _ease((time - start) / 0.6) *
          math.min(1.0, math.sqrt(remaining / (0.8 * most)));
      // Ahead of the liquid, not behind it: tipped to where what the glass
      // holds below its lip is what is in it less the next eighth of a
      // second's worth, so that much stands over the lip to run. A hand
      // that answered the flow it saw was always late, and a glass this
      // small, nearly on its side, empties in the time it takes to notice.
      final target = math.max(
        _tiltHolding(from, from.liquid.volume - wanted * 0.12),
        t.spill,
      );
      t.hand += (target - t.hand).clamp(-2.0 * seconds, 2.0 * seconds);
      tilt = t.hand;
      if (remaining <= 1e-10 || time - start > 3.0 * _pourTime) {
        t
          ..poured = time
          ..end = tilt;
      }
      base = baseFor(tilt);
    } else if (time < t.poured! + _back) {
      final s = (time - t.poured!) / _back;
      if (s < 0.6) {
        final e = _ease(s / 0.6);
        tilt = t.end * (1.0 - e);
        base = baseFor(tilt) + (raised - baseFor(tilt)) * e;
      } else {
        base = raised + (from.at - raised) * _ease((s - 0.6) / 0.4);
      }
    } else if (world.jets.isEmpty) {
      _finish(t);
      return;
    } else {
      // Put down; what was in the air is still landing.
      tilt = 0.0;
      base = from.at.clone();
    }
    _pose(from, base, tilt);
    from.tilt = tilt;
    t.tilt = tilt;
  }

  /// The pour is over: the glass back where it stood, upright.
  void _finish(_Transfer t) {
    final from = t.from;
    _transfer = null;
    _pose(from, from.at, 0.0);
    from.tilt = 0.0;
    for (final vessel in [from, t.to]) {
      _castBy(vessel);
      if (!photons) _repaint(vessel);
    }
  }

  // ---------------------------------------------------------------- step

  /// The streams drawn, one per pouring vessel, and the drops.
  final Map<LiquidBody, MeshNode> _streams = {};
  final Map<String, MeshNode> _drops = {};

  /// Moves everything on by [seconds], and says whether anything still
  /// moves, so the caller knows to ask for another frame.
  bool step(double seconds) {
    var moving = false;
    for (final vessel in vessels) {
      if (identical(vessel, _transfer?.from)) continue;
      // Lifted out of the row while it leans, put back when it does not.
      final wanted = vessel.tilt != 0.0 ? 1.0 : 0.0;
      if (vessel.lift != wanted) {
        final change = seconds / 0.6;
        vessel.lift = wanted > vessel.lift
            ? math.min(vessel.lift + change, wanted)
            : math.max(vessel.lift - change, wanted);
        _place(vessel);
        moving = true;
      }
    }
    final transfer = _transfer;
    final before = transfer?.from.liquid.volume;
    if (transfer != null) {
      _handStep(transfer, seconds);
      moving = true;
    }
    // Where the glass is at the end of this frame, stamped with that time:
    // the frame runs a whole number of the world's fixed steps, and a frame
    // of one step after one of three must not read as a jolt.
    final now = world.time + seconds;
    for (final vessel in vessels) {
      vessel.liquid.place(
        _turnOf(vessel),
        vessel.body.readPosition(),
        time: now,
      );
    }
    world.advance(seconds);
    if (transfer != null && before != null && seconds > 0.0) {
      transfer.flow =
          math.max(before - transfer.from.liquid.volume, 0.0) / seconds;
    }
    for (final vessel in vessels) {
      final liquid = vessel.liquid;
      final still = liquid.surface.settled;
      if (!still) moving = true;
      if (!still ||
          liquid.volume != vessel._drawnVolume ||
          vessel.tilt != vessel._drawnTilt ||
          vessel.lift != vessel._drawnLift) {
        _redraw(vessel);
      }
    }
    if (_drawStreams()) moving = true;
    return moving;
  }

  /// Draws [vessel]'s liquid as it is now, layer by layer.
  void _redraw(Vessel vessel) {
    vessel
      .._drawnVolume = vessel.liquid.volume
      .._drawnTilt = vessel.tilt
      .._drawnLift = vessel.lift;
    final meshes = vessel.liquid.volume > 0.0
        ? liquidMeshes(vessel.liquid)
        : const <LiquidLayerMesh>[];
    // As many nodes as layers.
    while (vessel.layers.length > meshes.length) {
      final gone = vessel.layers.removeLast();
      gone.node.removeFromParent();
      gone.reflection.removeFromParent();
    }
    for (var i = 0; i < meshes.length; i++) {
      final colour = colourOf(meshes[i].layer);
      final depth = 2.0 * vessel.shape.radiusAt(vessel.level);
      if (i == vessel.layers.length) {
        final node =
            MeshNode(
                DeviceMesh.upload(device, meshes[i].mesh),
                liquid(_rgb(colour), depth: depth),
                name: '${vessel.name} liquid',
              )
              ..lightChannels = _vesselChannel
              ..castsShadow = photons || vessel.tilt != 0.0
              ..receivesTranslucentShadows = false;
        final reflection = _mirrored(
          node.mesh,
          _reflection(albedo: null, colour: _rgb(colour)),
          vessel,
        );
        vessel.body.add(node);
        vessel.mirror.add(reflection);
        vessel.layers.add((node: node, reflection: reflection, colour: colour));
        continue;
      }
      final layer = vessel.layers[i];
      _swap(layer.node, meshes[i].mesh);
      layer.reflection.mesh = layer.node.mesh;
      if (layer.colour != colour) {
        layer.node.material = liquid(_rgb(colour), depth: depth);
        layer.reflection.material = _reflection(
          albedo: null,
          colour: _rgb(colour),
        );
        vessel.layers[i] = (
          node: layer.node,
          reflection: layer.reflection,
          colour: colour,
        );
      }
    }
  }

  /// Draws every stream in the air and every drop off the glass; says
  /// whether there are any.
  bool _drawStreams() {
    var any = false;
    final pouring = world.jets;
    for (final source in _streams.keys.toList()) {
      if (!pouring.containsKey(source)) {
        _streams.remove(source)!.removeFromParent();
      }
    }
    pouring.forEach((source, jet) {
      any = true;
      final mesh = jetMesh(jet);
      final from = vessels.firstWhere((v) => identical(v.liquid, source));
      final node = _streams.putIfAbsent(source, () {
        final made =
            MeshNode(
                DeviceMesh.upload(device, mesh),
                liquid(_rgb(colour(from)), depth: 0.002)..doubleSided = true,
                name: 'stream',
              )
              ..castsShadow = false
              ..lightChannels = _vesselChannel;
        scene.add(made);
        return made;
      });
      _swap(node, mesh);
      node.visible = mesh.triangleCount > 0;
    });
    world.particles.forEach((medium, fluid) {
      final node = _drops.putIfAbsent(medium, () {
        final made = MeshNode(
          DeviceMesh.upload(device, particleMesh(const [], 0.0005)),
          liquid(Vector3(0.9, 0.95, 1.0), depth: 0.001),
          name: 'drops',
        )..castsShadow = false;
        scene.add(made);
        return made;
      });
      if (fluid.count > 0) any = true;
      _swap(node, particleMesh(fluid.positions, 0.5 * fluid.spacing));
      node.visible = fluid.count > 0;
    });
    return any;
  }

  // -------------------------------------------------------------- shadows

  /// Who casts [vessel]'s shadow: the engine's photons, or this bench's card,
  /// which is worked out for glass standing upright and is put away while it
  /// leans — the glass and liquid then cast for themselves, as tinted
  /// translucent casters.
  void _castBy(Vessel vessel) {
    final card =
        !photons && vessel.tilt == 0.0 && !identical(vessel, _transfer?.from);
    for (final layer in vessel.layers) {
      layer.node.castsShadow = !card;
    }
    vessel.glassNode.castsShadow = !card;
    if (card) {
      if (vessel.shadow.parent == null) {
        _repaint(vessel);
        scene.add(vessel.shadow);
      }
    } else if (vessel.shadow.parent != null) {
      scene.remove(vessel.shadow);
    }
  }

  void _repaint(Vessel vessel) {
    final material = vessel.shadow.material;
    final picture = material.albedo;
    material.albedo = uploadRgba8(device, _picture(vessel));
    if (picture != null) retireTexture?.call(picture);
  }

  /// The most a card's picture can brighten the bench: light gathered past
  /// this, at a focus, is held to it.
  static const double _lightScale = 3.0;

  /// The sun's elevation above the bench, and the way its light crosses it.
  static final double _elevation = math.asin(-_sun.y);
  static final Vector3 _across = (Vector3(_sun.x, 0, _sun.z)..normalize());

  /// How far either side of its axis a vessel's card reaches: the light a
  /// liquid spreads past its focus lands well outside the glass.
  static double _halfWidth(Vessel vessel) =>
      3.0 * vessel.glass.map((p) => p.x).reduce(math.max);

  static double _height(Vessel vessel) =>
      vessel.glass.map((p) => p.y).reduce(math.max);

  /// [vessel]'s liquid as an outline for the optics: the inside up to its
  /// level, closed flat across.
  static List<Vector2> _liquidOutline(Vessel vessel) {
    final level = vessel.level;
    return <Vector2>[
      for (final p in vessel.inside)
        if (p.y < level) p,
      Vector2(vessel.shape.radiusAt(level), level),
      Vector2(0, level),
    ];
  }

  /// Where [vessel]'s light goes, as its card shows it.
  Rgba8Image _picture(Vessel vessel) => shadowPicture(
    glass: vessel.glass,
    liquid: vessel.liquid.volume > 0.0 ? _liquidOutline(vessel) : null,
    wall: glassThickness,
    height: _height(vessel),
    glassIndex: 1.5,
    liquidIndex: 1.33,
    liquidAbsorption: absorptionFor(_rgb(colour(vessel)), fade),
    elevation: _elevation,
    halfWidth: _halfWidth(vessel),
    scale: _lightScale,
  );

  /// The card [vessel]'s light is painted on: a strip lying a hair above the
  /// bench from under its axis out along the light's way, as long as its
  /// tallest point throws a shadow, and as wide as [_halfWidth] either side.
  /// Two coincident layers, because the stage counts a caster as crossed by
  /// two surfaces and takes a square root for each.
  DeviceMesh _card(Vessel vessel) {
    final half = _halfWidth(vessel);
    final length = _height(vessel) / math.tan(_elevation);
    final side = Vector3(-_across.z, 0, _across.x);
    final builder = MeshBuilder(VertexLayout.standard);
    final normal = Vector3(0, 1, 0);
    final tangent = Vector4(side.x, side.y, side.z, 1);
    for (var layer = 0; layer < 2; layer++) {
      final base = layer * 4;
      for (final (u, v) in const [
        (0.0, 0.0),
        (1.0, 0.0),
        (1.0, 1.0),
        (0.0, 1.0),
      ]) {
        final at = side * ((u * 2.0 - 1.0) * half) + _across * (v * length);
        builder.addVertex(
          position: Vector3(at.x, 0.00015, at.z),
          normal: normal,
          texcoord: Vector2(u, v),
          tangent: tangent,
        );
      }
      builder.addQuad(base, base + 1, base + 2, base + 3);
    }
    return DeviceMesh.upload(device, builder.build());
  }

  /// [mesh] for [vessel]'s mirror, which hangs it upside down under the
  /// tabletop.
  MeshNode _mirrored(MeshGeometry mesh, Material material, Vessel vessel) =>
      MeshNode(mesh, material, name: '${vessel.name} reflection')
        ..castsShadow = false
        ..lightChannels = LightChannels.none;

  /// What a reflection is drawn with: flat, a little darker than the
  /// thing, and from both sides, since the mirroring turns it inside out.
  /// Blended at a twelfth over the top, behind which it hangs, and drawn
  /// only there: nearer than the top is not in the mirror.
  static Material _reflection({
    required TextureHandle? albedo,
    required Vector3 colour,
  }) => Material(
    name: 'reflection',
    lighting: LightingModel.unlit,
    albedo: albedo,
    baseColor: Vector4(colour.x * 0.7, colour.y * 0.7, colour.z * 0.7, 0.08),
    alphaMode: MaterialAlphaMode.blend,
    doubleSided: true,
    depthWrite: false,
    depthCompare: CompareFunction.greater,
  );

  static const int _vesselChannel = 1 << 0;
  static const int _benchChannel = 1 << 1;

  /// Where sunlight goes: the sun node's forward.
  static final Vector3 _sun = Vector3(-0.5, -1.0, -0.6)..normalize();

  /// Wraps [image] round [vessel] as its label, and returns the texture it
  /// uploaded.
  ///
  /// The label joins the scene with its picture already on it, so the bench
  /// never shows blank paper; a label drawn again replaces the node. The
  /// scene is not drawn again by itself: `SceneSurface` paints when its
  /// widget changes, so whoever dresses a vessel asks for a frame afterwards,
  /// as `BenchScreen` does with `setState`.
  TextureHandle? dress(Vessel vessel, Rgba8Image image) {
    if (vessel.solution == null) return null;
    final texture = uploadRgba8(device, image);
    vessel.label?.removeFromParent();
    vessel.labelReflection?.removeFromParent();
    final band = DeviceMesh.upload(device, labelBand().build());
    vessel.labelReflection = _mirrored(
      band,
      _reflection(albedo: texture, colour: Vector3.all(1)),
      vessel,
    );
    vessel.mirror.add(vessel.labelReflection!);
    vessel.label = MeshNode(band, paper(texture), name: '${vessel.name} label')
      ..receivesTranslucentShadows = false
      ..lightChannels = _vesselChannel;
    vessel.body.add(vessel.label!);
    return texture;
  }
}

/// A pour from one vessel into another, under way: the hand's part. The
/// liquid's part — what runs, the stream, what lands — is the physics'.
final class _Transfer {
  _Transfer({
    required this.from,
    required this.to,
    required this.start,
    required this.goal,
  });

  final Vessel from;
  final Vessel to;

  /// What [from] held at the start, and what it is to hold at the end.
  final double start;
  final double goal;

  /// Seconds since the pour began.
  double time = 0.0;

  /// The lean at which it starts to run, the furthest it went, and the lean
  /// the hand holds; when the pour was done, null until it is.
  double spill = 0.0;
  double end = 0.0;
  double hand = 0.0;
  double? poured;

  /// How fast it ran on the last step, and how far it leaned.
  double flow = 0.0;
  double tilt = 0.0;

  /// Where the hand holds the lip: over the clean tube's mouth.
  Vector3? aim;
}
