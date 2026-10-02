import 'dart:math' as math;

import 'package:flutter/painting.dart' show Color;
import 'package:flutter3d/flutter3d.dart';
import 'package:vector_math/vector_math.dart';

import 'glassware.dart';
import 'label.dart';
import 'optics.dart';
import 'pouring.dart';
import 'slosh.dart';

/// One piece of glass on the bench and what is in it.
final class Vessel {
  Vessel({
    required this.name,
    required this.at,
    required this.glass,
    required this.liquidAt,
    required this.colour,
    required this.level,
    required this.lowest,
    required this.highest,
    this.solution,
    this.foot,
  });

  /// What the controls call it.
  final String name;

  /// Where its base stands.
  final Vector3 at;

  /// Its outline, swept into the glass.
  final List<Vector2> glass;

  /// A plastic foot it stands on, swept with six segments; null for none.
  final List<Vector2>? foot;

  /// The liquid's outline when it is filled to a level.
  final List<Vector2> Function(double level) liquidAt;

  /// The colour of what it holds. State: pouring one solution into another
  /// mixes them.
  Color colour;

  /// How far it may be filled, in metres up from its base.
  final double lowest;
  final double highest;

  /// What its label says; null for glass that wears none.
  final Solution? solution;

  /// How full it is now. State: pouring changes it.
  double level;

  /// How far it leans towards the front of the bench, in radians. State.
  double tilt = 0.0;

  /// The inside of the glass, as far up as it may be filled: [liquidAt]'s
  /// outline without its cap, which is where the liquid meets the glass
  /// whatever its surface does.
  ///
  /// Carried on straight up to the mouth, a little under the glass's top,
  /// which is where liquid tipped far enough runs out.
  late final List<Vector2> wall = () {
    final full = liquidAt(highest);
    // The cap is `meniscus`'s six points; its first is the top of the wall.
    final side = full.sublist(0, full.length - 5);
    final mouth = glass.map((p) => p.y).reduce(math.max) - 0.012;
    return <Vector2>[
      ...side,
      if (mouth > side.last.y) Vector2(side.last.x, mouth),
    ];
  }();

  /// The lowest point of the mouth once the glass leans towards the front:
  /// the edge of the inside, on the side it leans to.
  Vector3 get lip => Vector3(0, wall.last.y, wall.last.x);

  /// How much it holds at [level], and the most it can.
  double volumeAt(double level) => volumeUpTo(wall, level);
  double get capacity => volumeAt(highest);

  /// Whether there is nothing in it to draw.
  bool get empty => level - wall.first.y < 0.003;

  /// Its liquid's surface and how it moves.
  late final Slosh slosh = Slosh(radius: 0.05, depth: 0.1);

  /// Matches [slosh] to the surface [level] gives: its radius and depth.
  void _fitSlosh() => slosh
    ..radius = math.max(radiusAt(wall, level) ?? wall.last.x, 0.02)
    ..depth = math.max(level - wall.first.y, 0.005);

  /// The glass and all it carries, which tilts as one; and the same hung
  /// upside down under the tabletop, for the reflections.
  late final SceneNode body;
  late final SceneNode mirror;

  late final MeshNode liquid;
  MeshNode? label;

  /// Its liquid and its label mirrored under the tabletop; see [Bench].
  late final MeshNode liquidReflection;
  MeshNode? labelReflection;

  /// The card on the bench that carries where its light went; see [Bench].
  late final MeshNode shadow;

  /// Its glass, as drawn.
  late final MeshNode glassNode;
}

Vector3 _rgb(Color c) => Vector3(c.r, c.g, c.b);

/// The name of the empty tube at the front of the bench, which solutions
/// are poured into.
const String cleanTube = 'Clean tube';

/// Five labelled test tubes, a graduated cylinder, a beaker and an
/// Erlenmeyer flask, each holding a solution of its own colour.
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
        at: Vector3(-0.44 + i * 0.22, 0, 0.15),
        glass: tubeProfile(),
        liquidAt: tubeLiquidProfile,
        colour: solutions[i].colour,
        level: 0.36 + 0.05 * (i % 3),
        lowest: 0.03,
        highest: 0.8,
        solution: solutions[i],
      ),
    Vessel(
      name: cleanTube,
      at: Vector3(0.11, 0, 0.62),
      glass: tubeProfile(),
      liquidAt: tubeLiquidProfile,
      colour: const Color(0xFFFFFFFF),
      level: 0.0,
      lowest: 0.0,
      highest: 0.8,
    ),
    Vessel(
      name: 'Cylinder',
      at: Vector3(-1.05, 0, -0.25),
      glass: cylinderProfile(),
      foot: cylinderFoot(),
      liquidAt: (level) => flatLiquidProfile(0.051, 0.034, level),
      colour: const Color(0xFFF2D91A),
      level: 0.62,
      lowest: 0.05,
      highest: 0.84,
    ),
    Vessel(
      name: 'Beaker',
      at: Vector3(0.78, 0, -0.15),
      glass: beakerProfile(),
      liquidAt: (level) => flatLiquidProfile(0.192, 0.004, level),
      colour: const Color(0xFFF24D8C),
      level: 0.27,
      lowest: 0.02,
      highest: 0.4,
    ),
    Vessel(
      name: 'Flask',
      at: Vector3(1.32, 0, -0.45),
      glass: flaskProfile(),
      liquidAt: flaskLiquidProfile,
      colour: const Color(0xFFB35214),
      level: 0.22,
      lowest: 0.03,
      highest: 0.4,
    ),
  ];
}

/// The bench: a table, the glass, the liquids, the labels and the light.
///
/// Each vessel is two lathes, its liquid drawn first and its glass after it
/// so the blended glass lies over what it holds. A tube also gets a label, a
/// third lathe just outside the glass, once [dress] has its picture.
///
/// **The shadows are worked out, not guessed.** A vessel is a surface of
/// revolution, so the sunlight through it can be followed by geometric
/// optics in each horizontal cut (see `optics.dart`): bent at every surface,
/// reflected and dimmed on the way, and gathered where it lands. What lands
/// is painted on a card lying on the bench along the vessel's shadow, which
/// casts into the sun's atlas and nothing else
/// (`ShadowCastingMode.shadowsOnly`, `ShadowSettings.translucentCasters`):
/// dark where the light was turned away, coloured where it went through the
/// solution, and brighter than the bench around it where the liquid focused
/// it. The glass and the liquid cast nothing of their own, and neither they
/// nor the labels are shaded by the card, which stands for the light under
/// them, not over them. Pouring paints the card again.
///
/// **The reflections in the tabletop are geometry too.** Screen-space
/// reflections read only what the opaque pass drew, and the glass and the
/// liquids are drawn after it, so the tabletop reflected the labels and
/// nothing else. The table is flat, though, and a flat mirror has an exact
/// answer: each liquid and label again, scaled by -1 in height so it hangs
/// under the top, laid over the top at a twelfth of its strength and only
/// where it is behind it (`CompareFunction.greater`), which is where a
/// mirror shows it.
///
/// **The top itself is opaque**, so it is in the copy of the scene the
/// liquids read what is behind them from. It used to be the reflections that
/// showed through a top a twelfth transparent; then the top was drawn after
/// the liquids, not before, and a column of water showed the sky behind the
/// bench instead of the bench, bent — a white rod rather than a lens.
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
      vessel._fitSlosh();
      vessel.liquid = MeshNode(
        _liquidMesh(vessel),
        liquid(_rgb(vessel.colour), depth: 2.0 * _liquidRadius(vessel)),
        name: '${vessel.name} liquid',
      )..lightChannels = _vesselChannel;
      vessel.liquid
        ..castsShadow = photons
        ..receivesTranslucentShadows = false;
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
      vessel.liquidReflection = _mirrored(
        vessel.liquid.mesh,
        _reflection(albedo: null, colour: _rgb(vessel.colour)),
        vessel,
      );
      vessel.body.add(vessel.liquid);
      vessel.mirror.add(vessel.liquidReflection);
      vessel.liquid.visible = !vessel.empty;
      vessel.liquidReflection.visible = !vessel.empty;
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
              CuboidShape(size: Vector3(6, 0.04, 4.4)).build(),
            ),
            Material(
              name: 'bench',
              baseColor: Vector4(0.46, 0.45, 0.43, 1.0),
              roughness: 0.25,
            ),
            name: 'bench',
          )
          ..setPosition(0, -0.02, 0.6)
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

  /// Whether the shadows come from the engine's caustics
  /// (`ShadowSettings.caustics`, drawn with [settings]) rather than from the
  /// cards this bench works out itself. The liquids then cast, as refracting
  /// volumes, and the thin glass casts by its Fresnel loss; the cards are
  /// not drawn.
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

  DeviceMesh _lathe(List<Vector2> profile) => DeviceMesh.upload(
    device,
    LatheShape(profile: profile, segments: 64).build(),
  );

  /// Fills [vessel] to [level]: a new profile, cut higher or lower, and
  /// nothing else.
  void pour(Vessel vessel, double level) {
    if (_transfer != null) return;
    vessel.level = level.clamp(vessel.lowest, vessel.highest);
    vessel._fitSlosh();
    _reshape(vessel);
    if (!photons && vessel.tilt == 0.0) _repaint(vessel);
  }

  /// The liquid's mesh for where its surface is now.
  DeviceMesh _liquidMesh(Vessel vessel) => DeviceMesh.upload(
    device,
    liquidVolume(wall: vessel.wall, level: vessel.level, surface: vessel.slosh),
  );

  void _reshape(Vessel vessel, [MeshData? shape]) {
    vessel.liquid.visible = !vessel.empty;
    vessel.liquidReflection.visible = !vessel.empty;
    if (vessel.empty) return;
    final old = vessel.liquid.mesh;
    vessel.liquid.mesh = shape == null
        ? _liquidMesh(vessel)
        : DeviceMesh.upload(device, shape);
    vessel.liquidReflection.mesh = vessel.liquid.mesh;
    if (old is DeviceMesh) (retire ?? _releaseNow)(old);
  }

  /// The most a vessel leans either way: further, and the tall tubes reach
  /// over their neighbours' place in the row.
  static const double maxTilt = 0.5;

  /// Leans [vessel] by [angle] radians towards the front of the bench, about
  /// where it stands, lifted so its lowest point still rests on the bench.
  /// The glass goes at once; the liquid follows by [step], late.
  void lean(Vessel vessel, double angle) {
    if (_transfer != null) return;
    vessel.tilt = angle.clamp(-maxTilt, maxTilt);
    final turn = Quaternion.axisAngle(Vector3(1, 0, 0), vessel.tilt);
    final c = math.cos(vessel.tilt);
    final s = math.sin(vessel.tilt).abs();
    // The lowest point of the glass, and of its foot, once turned.
    final lowest = [
      ...vessel.glass,
      ...?vessel.foot,
    ].map((p) => p.y * c - p.x * s).reduce(math.min);
    vessel.body
      ..setRotation(turn)
      ..setPosition(vessel.at.x, vessel.at.y - lowest, vessel.at.z);
    // The mirror of a turn about x is the opposite turn.
    vessel.mirror
      ..setRotation(Quaternion.axisAngle(Vector3(1, 0, 0), -vessel.tilt))
      ..setPosition(vessel.at.x, -(vessel.at.y - lowest), vessel.at.z);
    // Level in the world: the world's up seen from the glass, which is the
    // turn's second row.
    final m = vessel.body.localMatrix;
    final up = Vector3(m.entry(1, 0), m.entry(1, 1), m.entry(1, 2));
    vessel.slosh
      ..targetX = -up.x / up.y
      ..targetZ = -up.z / up.y;
    _castBy(vessel);
  }

  /// Knocks on [vessel]'s glass.
  void tap(Vessel vessel) => vessel.slosh.tap(0.01);

  /// Whether a pour is under way, during which the controls wait.
  bool get busy => _transfer != null;
  _Transfer? _transfer;

  /// The tube solutions are poured into.
  Vessel get clean => vessels.firstWhere((v) => v.name == cleanTube);

  /// Whether [from] can be poured into the [clean] tube until the two hold
  /// the same: it has more, and half of both fits.
  bool canShare(Vessel from) {
    // The clean tube stands upright to be poured into: the stream is held
    // inside it as a vertical cylinder.
    if (busy || identical(from, clean) || clean.tilt != 0.0) return false;
    final mine = from.volumeAt(from.level);
    final theirs = clean.volumeAt(clean.level);
    return mine > theirs + 1e-4 && (mine + theirs) / 2.0 <= clean.capacity;
  }

  /// Pours [from] into the [clean] tube until the two hold the same: lifts
  /// it over the bench, tips it over the tube's mouth as far as it takes to
  /// pour that much and no faster, and puts it back. [step] plays it.
  void share(Vessel from) {
    if (!canShare(from)) return;
    final to = clean;
    final mine = from.volumeAt(from.level);
    final theirs = to.volumeAt(to.level);
    from
      ..tilt = 0.0
      ..slosh.settle();
    final transfer = _Transfer(
      from: from,
      to: to,
      start: mine,
      goal: (mine + theirs) / 2.0,
      received: theirs,
    )..spill = _tiltHolding(from, mine);
    final material = liquid(_rgb(from.colour), depth: 0.04)..doubleSided = true;
    // A real stream, hidden, until there is one to see: Metal makes no buffer
    // of no bytes, so an empty mesh is no placeholder there.
    transfer.stream =
        MeshNode(
            DeviceMesh.upload(
              device,
              stream(
                lip: from.at + Vector3(0, 0.1, 0),
                velocity: Vector3(0, -1, 0),
                across: Vector3(1, 0, 0),
                width: 0.01,
                floor: from.at.y,
                flow: 1e-6,
              ).mesh,
            ),
            material,
            name: 'stream',
          )
          ..visible = false
          ..castsShadow = false
          ..lightChannels = _vesselChannel;
    scene.add(transfer.stream);
    _transfer = transfer;
    _castBy(from);
  }

  /// How long each part of a pour takes: up, over, the pour, and back.
  static const double _rise = 0.45;
  static const double _over = 0.75;

  /// A steady pour from a real test tube takes about two seconds; on a
  /// bench [lifeScale] times the size, that is two seconds times its root.
  static final double _pourTime = 2.0 * math.sqrt(lifeScale);
  static const double _back = 1.4;

  /// The world's up seen from glass leaning [tilt] towards the front.
  static Vector3 _upAt(double tilt) =>
      Vector3(0, math.cos(tilt), -math.sin(tilt));

  /// How much [vessel] holds leaning [tilt] before it runs over its lip.
  static double _holds(Vessel vessel, double tilt) {
    final up = _upAt(tilt);
    return volumeBelow(vessel.wall, up, up.dot(vessel.lip));
  }

  /// The lean at which [vessel] holds just [volume]: past it, the rest runs
  /// out. Holding less the further it leans, so found by halving.
  static double _tiltHolding(Vessel vessel, double volume) {
    var lo = 0.0;
    var hi = 2.8;
    for (var i = 0; i < 36; i++) {
      final mid = 0.5 * (lo + hi);
      if (_holds(vessel, mid) > volume) {
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

  /// How the liquid leaves [vessel]'s lip leaning [tilt] at [flow]: along the
  /// glass, outwards, at the speed the weir over its lip gives (see
  /// [overLip]), as a sheet as wide as the wetted lip.
  ({Vector3 velocity, double width}) _thrown(
    Vessel vessel,
    double tilt,
    double flow,
  ) {
    final over = overLip(
      flow: math.max(flow, 1e-7),
      radius: vessel.lip.z,
      tilt: tilt,
    );
    final along = Vector3(0, math.cos(tilt), math.sin(tilt));
    return (velocity: along * over.speed, width: over.width);
  }

  /// One frame of the pour under way.
  void _pourStep(_Transfer t, double seconds) {
    final from = t.from;
    final to = t.to;
    t.time += seconds;
    final raised = from.at + Vector3(0, 1.0, 0);
    // Over the clean tube's mouth, a little towards the back, so the stream
    // thrown forward lands in the middle.
    // **Lip to lip, as a chemist pours.** The lip goes a centimetre over the
    // clean tube's rim, back from the middle by half of how far the stream
    // is carried forward while it falls to the surface, so it enters through
    // the mouth and lands near the middle; never further back than the
    // inside of the wall. The stream is thrown along the glass at the speed
    // the flow leaves the lip with (see [overLip]).
    final rim = to.glass.map((p) => p.y).reduce(math.max);
    final inside = to.lip.z;
    final surfaceY = to.at.y + (to.empty ? to.wall.first.y : to.level);
    final thrown = _thrown(from, t.tilt, t.flow);
    final drift =
        thrown.velocity.z *
        fallTime(thrown.velocity, to.at.y + rim + 0.01, surfaceY);
    final back = math.min(0.5 * drift, inside - 0.01);
    final aim = to.at + Vector3(0, rim + 0.01, -back);
    Vector3 baseFor(double tilt) {
      final c = math.cos(tilt);
      final s = math.sin(tilt);
      final lip = from.lip;
      return aim - Vector3(0, lip.y * c - lip.z * s, lip.y * s + lip.z * c);
    }

    final before = t.volume;
    var base = from.at.clone();
    var tilt = 0.0;
    final time = t.time;
    if (time < _rise) {
      base = from.at + (raised - from.at) * _ease(time / _rise);
    } else if (time < _rise + _over) {
      final e = _ease((time - _rise) / _over);
      tilt = t.spill * e;
      base = raised + (baseFor(tilt) - raised) * e;
    } else if (time < _rise + _over + _pourTime) {
      final e = _ease((time - _rise - _over) / _pourTime);
      t.volume = t.start + (t.goal - t.start) * e;
      tilt = math.max(_tiltHolding(from, t.volume), t.spill);
      t.end = tilt;
      base = baseFor(tilt);
    } else if (time < _rise + _over + _pourTime + _back) {
      final s = (time - _rise - _over - _pourTime) / _back;
      if (s < 0.6) {
        final e = _ease(s / 0.6);
        tilt = t.end * (1.0 - e);
        base = baseFor(tilt) + (raised - baseFor(tilt)) * e;
      } else {
        base = raised + (from.at - raised) * _ease((s - 0.6) / 0.4);
      }
    } else {
      _finish(t);
      return;
    }
    _pose(from, base, tilt);
    from.tilt = tilt;
    t.tilt = tilt;

    // What left the lip this frame, and what reaches the clean tube: what
    // left it a fall ago. Between the two is the liquid in the air.
    final poured = before - t.volume;
    final rate = seconds > 0.0 ? poured / seconds : 0.0;
    t.emitted.add((time: t.time, rate: rate));
    t.flow = rate;
    final arriving = t.rateAt(t.time - t.fall) * seconds;
    if (arriving > 0.0) {
      final held = t.received + t.arrived;
      t.arrived = math.min(t.arrived + arriving, t.start - t.goal);
      _mix(to, from.colour, t.received + t.arrived - held, held);
      to
        ..level = levelFor(to.wall, t.received + t.arrived)
        .._fitSlosh()
        ..slosh.tap(0.0015 * (_random.nextDouble() - 0.3));
      _reshape(to);
    }

    // The liquid in the tipped glass: the plane level in the world that
    // leaves its volume under it.
    final up = _upAt(tilt);
    from.level = levelFor(from.wall, t.volume);
    _reshape(
      from,
      cutLiquid(
        wall: from.wall,
        up: up,
        height: surfaceFor(from.wall, up, t.volume),
      ),
    );

    // The stream, while any of it is in the air. While liquid leaves the
    // lip the path is the one it leaves on; once it stops, the last of it
    // keeps the path it was on and falls away from the lip.
    double inAir(double age) => t.rateAt(t.time - age);
    var peak = 0.0;
    for (var k = 0; k <= 20; k++) {
      peak = math.max(peak, inAir(t.fall * k / 20));
    }
    final streaming = peak > 1e-7;
    t.stream.visible = streaming;
    if (streaming) {
      if (rate > 1e-7) {
        final leaving = _thrown(from, tilt, rate);
        t.launch = (
          lip: from.body.worldMatrix.transformed3(from.lip),
          velocity: leaving.velocity,
          width: leaving.width,
          flow: rate,
        );
      }
      final launch = t.launch;
      if (launch != null) {
        final surface = to.at.y + (to.empty ? to.wall.first.y : to.level);
        final old = t.stream.mesh;
        final built = stream(
          lip: launch.lip,
          velocity: launch.velocity,
          across: Vector3(1, 0, 0),
          width: launch.width,
          floor: surface,
          flow: launch.flow,
          flowAt: inAir,
          scale: lifeScale,
          wall: (
            x: to.at.x,
            z: to.at.z,
            radius: to.lip.z,
            rim: to.at.y + to.glass.map((p) => p.y).reduce(math.max),
          ),
        );
        t
          ..stream.mesh = DeviceMesh.upload(device, built.mesh)
          ..fall = built.duration;
        if (old is DeviceMesh) (retire ?? _releaseNow)(old);
      }
    }
  }

  /// The pour is over: both vessels stand where they did, upright, the one
  /// that was poured from rocking from being put down.
  void _finish(_Transfer t) {
    final from = t.from;
    _transfer = null;
    scene.remove(t.stream);
    final old = t.stream.mesh;
    if (old is DeviceMesh) (retire ?? _releaseNow)(old);
    _pose(from, from.at, 0.0);
    from
      ..tilt = 0.0
      ..level = levelFor(from.wall, t.goal)
      .._fitSlosh();
    // Whatever was still in the air has landed by now.
    final to = t.to;
    if (t.arrived < t.start - t.goal) {
      final held = t.received + t.arrived;
      _mix(to, from.colour, t.start - t.goal - t.arrived, held);
      to
        ..level = levelFor(to.wall, t.received + t.start - t.goal)
        .._fitSlosh();
      _reshape(to);
    }
    from.slosh
      ..settle()
      ..jolt(0.35);
    _reshape(from);
    for (final vessel in [from, t.to]) {
      _castBy(vessel);
      if (!photons) _repaint(vessel);
    }
  }

  /// Mixes [added] of a solution of [colour] into [vessel], which holds
  /// [held]. Each solution takes light away by Beer and Lambert, so what
  /// the mixture takes per metre is the two absorptions weighed by how much
  /// of each there is; the colour is what is left over the distance the
  /// colours are given at.
  void _mix(Vessel vessel, Color colour, double added, double held) {
    final total = added + held;
    if (total <= 0.0) return;
    double absorb(double c) => -math.log(c.clamp(1e-3, 1.0));
    double blend(double a, double b) =>
        math.exp(-(absorb(a) * held + absorb(b) * added) / total);
    final mixed = held <= 0.0
        ? colour
        : Color.from(
            alpha: 1.0,
            red: blend(vessel.colour.r, colour.r),
            green: blend(vessel.colour.g, colour.g),
            blue: blend(vessel.colour.b, colour.b),
          );
    final was = vessel.colour;
    vessel.colour = mixed;
    if ((was.r - mixed.r).abs() +
            (was.g - mixed.g).abs() +
            (was.b - mixed.b).abs() <
        1e-3) {
      return;
    }
    vessel.liquid.material = liquid(
      _rgb(mixed),
      depth: 2.0 * _liquidRadius(vessel),
    );
    vessel.liquidReflection.material = _reflection(
      albedo: null,
      colour: _rgb(mixed),
    );
  }

  final math.Random _random = math.Random(7);

  /// Moves every liquid on by [seconds], and says whether any is still
  /// moving, so the caller knows to ask for another frame.
  bool step(double seconds) {
    var moving = false;
    final transfer = _transfer;
    if (transfer != null) {
      _pourStep(transfer, seconds);
      moving = true;
    }
    for (final vessel in vessels) {
      if (identical(vessel, _transfer?.from)) continue;
      if (vessel.slosh.settled) continue;
      vessel.slosh.step(seconds);
      if (vessel.slosh.settled) vessel.slosh.settle();
      _reshape(vessel);
      moving = true;
    }
    return moving;
  }

  /// Who casts [vessel]'s shadow: the engine's photons, or this bench's card,
  /// which is worked out for glass standing upright and is put away while it
  /// leans — the glass and liquid then cast for themselves, as tinted
  /// translucent casters.
  void _castBy(Vessel vessel) {
    final card =
        !photons && vessel.tilt == 0.0 && !identical(vessel, _transfer?.from);
    vessel.liquid.castsShadow = !card;
    vessel.glassNode.castsShadow = !card;
    if (card) {
      if (vessel.shadow.parent == null) {
        // Painted for the level it has now: pouring leaves the card alone
        // while the engine is casting.
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
  /// this, at a focus, is held to it. Three is well past what the liquids
  /// here gather at the distances their shadows fall.
  static const double _lightScale = 3.0;

  /// The glass's thickness, as `glassWall` gives it.
  static const double _wall = 0.004;

  /// The sun's elevation above the bench, and the way its light crosses it.
  static final double _elevation = math.asin(-_sun.y);
  static final Vector3 _across = (Vector3(_sun.x, 0, _sun.z)..normalize());

  /// How far either side of its axis a vessel's card reaches: the light a
  /// liquid spreads past its focus lands well outside the glass.
  static double _halfWidth(Vessel vessel) =>
      3.0 * vessel.glass.map((p) => p.x).reduce(math.max);

  /// How wide [vessel]'s liquid is across its middle: the widest the
  /// profile reaches at its usual level.
  static double _liquidRadius(Vessel vessel) =>
      vessel.liquidAt(vessel.level).map((p) => p.x).reduce(math.max);

  static double _height(Vessel vessel) =>
      vessel.glass.map((p) => p.y).reduce(math.max);

  /// Where [vessel]'s light goes, as its card shows it.
  Rgba8Image _picture(Vessel vessel) => shadowPicture(
    glass: vessel.glass,
    liquid: vessel.liquidAt(vessel.level),
    wall: _wall,
    height: _height(vessel),
    glassIndex: 1.5,
    liquidIndex: 1.33,
    liquidAbsorption: absorptionFor(_rgb(vessel.colour), 0.3),
    elevation: _elevation,
    halfWidth: _halfWidth(vessel),
    scale: _lightScale,
  );

  /// The card [vessel]'s light is painted on: a strip lying a hair above the
  /// bench from under its axis out along the light's way, as long as its
  /// tallest point throws a shadow, and as wide as [_halfWidth] either side.
  /// U runs across it and V away from the vessel, so the picture's rows are
  /// the cuts from the base up. Two coincident layers, because the stage
  /// counts a caster as crossed by two surfaces and takes a square root for
  /// each: two layers give back the picture as it was painted.
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
          position: Vector3(at.x, 0.0015, at.z),
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

/// A pour from one vessel into another, under way; see [Bench.share].
final class _Transfer {
  _Transfer({
    required this.from,
    required this.to,
    required this.start,
    required this.goal,
    required this.received,
  }) : volume = start;

  final Vessel from;
  final Vessel to;

  /// What [from] held at the start and will hold at the end, and what [to]
  /// held at the start.
  final double start;
  final double goal;
  final double received;

  /// What [from] holds now.
  double volume;

  /// Seconds since the pour began.
  double time = 0.0;

  /// The lean at which it starts to run, and the furthest it went.
  double spill = 0.0;
  double end = 0.0;

  /// How fast it is running now, smoothed over a few frames.
  double flow = 0.0;

  /// How far it leaned last frame, which is what the stream left with.
  double tilt = 0.0;

  /// How fast liquid left the lip, frame by frame: the stream's history.
  final List<({double time, double rate})> emitted = [];

  /// How much of what left has reached the clean tube.
  double arrived = 0.0;

  /// How long a drop takes from the lip to the surface, as the last stream
  /// found it.
  double fall = 0.35;

  /// Where and how the stream last left the lip: the path its tail keeps
  /// once nothing more leaves.
  ({Vector3 lip, Vector3 velocity, double width, double flow})? launch;

  /// How fast liquid left the lip at [time]: the rate of the frame that
  /// time falls in, nought before the first.
  double rateAt(double time) {
    if (emitted.isEmpty || time <= emitted.first.time - 1e-9) return 0.0;
    for (var i = 1; i < emitted.length; i++) {
      // A frame's rate held over the span that ends at its time.
      if (time <= emitted[i].time) return emitted[i].rate;
    }
    return emitted.last.rate;
  }

  late final MeshNode stream;
}
