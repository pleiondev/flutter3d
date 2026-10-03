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
        overCircularLip,
        circularWeir;
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

  /// How far it is asked to lean, and how fast it is turning towards that:
  /// [Bench.step] brings [tilt] round to it as a hand would.
  double leanTo = 0.0;
  double _turning = 0.0;
  double _aim = 0.0;

  /// How high the hand holds it out of the row, and how fast that is
  /// changing.
  double _raised = 0.0;
  double _rising = 0.0;
  double _raiseAim = 0.0;
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
      if (!white) {
        _dyes[vessel.name] = _measured(vessel) ?? _absorbance(vessel.dye);
      }
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
      // The glass in the tabletop too: it was left out while it was nearly
      // invisible, and once it was not, the liquids stood in the mirror
      // with nothing round them.
      vessel.mirror.add(
        _mirrored(
          vessel.glassNode.mesh,
          _reflection(albedo: null, colour: Vector3(0.995, 0.999, 0.997)),
          vessel,
        ),
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
          // **In the shadow map, though it shades nothing below it.** The
          // engine's photons, bent through a liquid, land on whatever the
          // map holds under them; with the tabletop left out they found
          // nothing, were lost, and every solution threw the same grey
          // shadow, clear acid as dark as permanganate.
          ..castsShadow = true
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
    node.mesh = _upload(data);
    if (old is DeviceMesh) (retire ?? _releaseNow)(old);
  }

  /// [data] on the device, or, when it has nothing in it, one triangle too
  /// small to see: Metal makes no buffer of no bytes, and a stream with no
  /// parcels yet, or drops before the first, threw on every frame of a pour
  /// and stopped it there. The software device takes an empty buffer, so the
  /// tests never saw it.
  DeviceMesh _upload(MeshData data) {
    if (data.vertexCount > 0 && data.indexCount > 0) {
      return DeviceMesh.upload(device, data);
    }
    final tiny = MeshBuilder(VertexLayout.standard);
    final up = Vector3(0, 1, 0);
    for (final p in [
      Vector3.zero(),
      Vector3(1e-6, 0, 0),
      Vector3(0, 0, 1e-6),
    ]) {
      tiny.addVertex(position: p, normal: up);
    }
    tiny.addTriangle(0, 1, 2);
    return DeviceMesh.upload(device, tiny.build());
  }

  DeviceMesh _lathe(List<Vector2> profile) => DeviceMesh.upload(
    device,
    LatheShape(profile: profile, segments: 64).build(),
  );

  // --------------------------------------------------------------- colour

  /// Each dye's absorbance per metre at unit concentration — the strength
  /// on its label.
  final Map<String, Vector3> _dyes = {};

  /// Molar absorption coefficients, L·mol⁻¹·cm⁻¹, of what the labelled
  /// tubes hold, at about 610, 550 and 465 nm, where the eye's red, green
  /// and blue lie: read off published spectra of the aqueous ions, good to
  /// a few tens of percent, and enough to tell which solutions light goes
  /// through and which it does not. Copper(II) absorbs the red end weakly
  /// (its band peaks near 810 nm), permanganate the green very strongly
  /// (peaks at 525 and 545 nm), dichromate the blue (450 nm), nickel(II)
  /// little anywhere (395 and 720 nm), and hydrochloric acid nothing.
  static const Map<String, (double, double, double)> molarAbsorption = {
    'HCl': (0.0, 0.0, 0.0),
    'CuSO4': (4.5, 1.2, 0.2),
    'KMnO4': (150.0, 2300.0, 450.0),
    'K2Cr2O7': (0.2, 2.0, 250.0),
    'NiCl2': (1.1, 0.6, 0.8),
  };

  /// [vessel]'s absorbance per metre from [molarAbsorption] and the
  /// strength on its label, A = εcl in base ten: null for glass with no
  /// label or a solution not in the table.
  static Vector3? _measured(Vessel vessel) {
    final solution = vessel.solution;
    final eps = molarAbsorption[vessel.name];
    if (solution == null || eps == null) return null;
    final molar = double.tryParse(solution.note.split(' ').first);
    if (molar == null) return null;
    // ln 10 for base e, a hundred centimetres to the metre.
    final k = math.ln10 * molar * 100.0;
    return Vector3(eps.$1 * k, eps.$2 * k, eps.$3 * k);
  }

  /// What makes [colour] the colour of [fade] of a liquid: for the glass
  /// with no label, whose solution is only a colour.
  static Vector3 _absorbance(Color colour) {
    double mu(double c) => -math.log(c.clamp(1e-3, 1.0)) / fade;
    return Vector3(mu(colour.r), mu(colour.g), mu(colour.b));
  }

  /// The colour of [layer]: light through [fade] of it, every dye in it
  /// taking its share by Beer and Lambert.
  Color colourOf(LiquidLayer layer) => _colourOf(layer.concentrations);

  Color _colourOf(Map<String, double> concentrations) {
    final absorb = Vector3.zero();
    concentrations.forEach((dye, c) {
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

  /// The furthest [vessel] may lean either way: a half turn, mouth down.
  /// Past the lean it holds its liquid at, what it holds runs out over the
  /// lip, onto the bench or into whatever is under it, as it would from a
  /// glass in a hand; stopped short of that, nothing could be spilled.
  double maxLean(Vessel vessel) => math.pi;

  /// How far [vessel] must be lifted to lean as it does without passing
  /// through the glass standing round it.
  ///
  /// Walked up its axis: wherever the tipped glass is over another vessel's
  /// footprint, its underside there has to clear that vessel's top by a
  /// millimetre. A vessel leaning away from its neighbours is hardly lifted;
  /// one leaning over a row of tubes goes over their mouths.
  double _clearance(Vessel vessel, [double? at]) {
    final tilt = at ?? vessel.tilt;
    if (tilt == 0.0) return 0.0;
    final turn = Matrix3.zero()
      ..setFrom(Quaternion.axisAngle(vessel.leanAxis, tilt).asRotationMatrix());
    final top = vessel.glass.map((p) => p.y).reduce(math.max);
    final sideways = math.sin(tilt).abs();
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
  ///
  /// **Asked, not set.** [step] turns the glass to [angle] as a hand would,
  /// smoothly. Set at once, the glass jumped a frame's worth of lean and
  /// lift, the liquid felt a jolt of several g, its surface turned over, and
  /// a tube tipped by ten degrees emptied itself in one step.
  void lean(Vessel vessel, double angle, {Vector3? across}) {
    if (busy) return;
    final limit = maxLean(vessel);
    vessel.leanTo = angle.clamp(-limit, limit);
    if (across != null && vessel.tilt == 0.0) {
      final flat = Vector3(across.x, 0, across.z);
      if (flat.length2 > 1e-9) vessel.leanAxis = flat..normalize();
    }
    // One vessel in the hand: leaning this one puts the last one back.
    if (vessel.leanTo != 0.0) {
      for (final other in vessels) {
        if (!identical(other, vessel)) other.leanTo = 0.0;
      }
    }
  }

  /// How quickly a hand brings a glass round to the lean asked of it: the
  /// lean asked is first eased ([_aimRate]), and the glass turns towards
  /// the eased aim critically damped ([_handRate]), so it gathers speed
  /// from nothing and sheds it to nothing, a third of a second or so.
  /// Turning straight at the lean asked, critically damped alone, it took
  /// all its angular acceleration in the first instant; a tube asked for
  /// 0.8 rad felt three metres a second squared at once and threw a third
  /// of what it held over its lip.
  static const double _aimRate = 6.0;
  static const double _handRate = 8.0;

  /// Raises or lowers [vessel] towards [height] for [seconds], eased as a
  /// turn is; says whether it moved.
  bool _ease2(Vessel vessel, double height, double seconds) {
    if (vessel._raised == height &&
        vessel._raiseAim == height &&
        vessel._rising == 0.0) {
      return false;
    }
    final pieces = (seconds * 240).ceil().clamp(1, 32);
    final dt = seconds / pieces;
    for (var k = 0; k < pieces; k++) {
      vessel._raiseAim += _aimRate * (height - vessel._raiseAim) * dt;
      final pull =
          _handRate * _handRate * (vessel._raiseAim - vessel._raised) -
          2.0 * _handRate * vessel._rising;
      vessel._rising += pull * dt;
      vessel._raised += vessel._rising * dt;
    }
    if ((height - vessel._raised).abs() < 1e-6 && vessel._rising.abs() < 1e-5) {
      vessel
        .._raised = height
        .._raiseAim = height
        .._rising = 0.0;
    }
    return true;
  }

  /// Turns [vessel] towards [Vessel.leanTo] for [seconds]; says whether it
  /// moved.
  bool _turn(Vessel vessel, double seconds) {
    if (vessel.tilt == vessel.leanTo &&
        vessel._aim == vessel.leanTo &&
        vessel._turning == 0.0) {
      return false;
    }
    final wasUpright = vessel.tilt == 0.0;
    final pieces = (seconds * 240).ceil().clamp(1, 32);
    final dt = seconds / pieces;
    for (var k = 0; k < pieces; k++) {
      vessel._aim += _aimRate * (vessel.leanTo - vessel._aim) * dt;
      final pull =
          _handRate * _handRate * (vessel._aim - vessel.tilt) -
          2.0 * _handRate * vessel._turning;
      vessel._turning += pull * dt;
      vessel.tilt += vessel._turning * dt;
    }
    if ((vessel.leanTo - vessel.tilt).abs() < 1e-5 &&
        vessel._turning.abs() < 1e-4) {
      vessel
        ..tilt = vessel.leanTo
        .._aim = vessel.leanTo
        .._turning = 0.0;
    }
    _place(vessel);
    if (wasUpright != (vessel.tilt == 0.0)) _castBy(vessel);
    return true;
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
    final lift = vessel._raised;
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
  ///
  /// It tips about [across], a horizontal axis — the way the camera looks,
  /// so that the pour leans in the picture: tipped towards the eye, a tube
  /// seen from the front only seemed to rise and shorten.
  void share(Vessel from, {Vector3? across}) {
    if (!canShare(from)) return;
    final mine = from.liquid.volume;
    final theirs = clean.liquid.volume;
    final flat = across == null ? null : Vector3(across.x, 0, across.z);
    final axis = flat != null && flat.length2 > 1e-9
        ? (flat..normalize())
        : Vector3(1, 0, 0);
    from
      ..tilt = 0.0
      ..leanTo = 0.0
      .._aim = 0.0
      .._turning = 0.0
      ..lift = 0.0
      ..leanAxis = axis;
    _transfer = _Transfer(
      from: from,
      to: clean,
      start: mine,
      goal: (mine + theirs) / 2.0,
      axis: axis,
    )..spill = _tiltHolding(from, mine);
    _castBy(from);
  }

  /// How long each part of a pour takes: up, over, and back; the pour
  /// itself is as long as the hand takes, about a second.
  ///
  /// **Briskly, as a chemist pours half a tube.** Over two seconds the
  /// stream ran a millimetre across, and a thread that thin parts into
  /// drops some forty widths down, about five centimetres: the clean tube
  /// filled by dripping. At four times the flow the stream is twice as
  /// wide, and since how far a stream falls before it parts grows as its
  /// width to the power one and a half, it reaches the surface whole.
  static const double _rise = 0.45;
  static const double _over = 1.2;
  static const double _pourTime = 0.8;
  static const double _back = 1.4;

  /// The world's up seen from glass leaning [tilt] towards its local +z:
  /// what it holds is the same whichever way a round glass leans.
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

  /// The lean at which [vessel], holding [volume], runs [flow] over its lip:
  /// where the surface stands over the lip by the head a circular weir
  /// needs for it. Found by halving, from the lean where it starts to run.
  static double _tiltPouring(Vessel vessel, double volume, double flow) {
    final lowest = _tiltHolding(vessel, volume);
    if (flow <= 0.0) return lowest;
    final radius = vessel.lip.z;
    double short(double tilt) {
      final up = _upAt(tilt);
      final lip = vessel.shape.lip(up);
      if (lip == null) return 0.0;
      // By secants from the lip, which the surface is a little over.
      final head =
          vessel.shape.surfaceNear(up, volume, lip.height + 1e-4) - lip.height;
      // The flow that head passes, straight from the weir, rather than the
      // head that flow needs, which is a search of its own inside this one.
      final passes = circularWeir(
        head: head,
        radius: radius,
        tilt: tilt,
        g: 9.81,
        steps: 90,
      ).flow;
      return flow - passes;
    }

    var lo = lowest;
    var hi = math.min(lowest + 0.8, 2.6);
    if (short(hi) > 0.0) return hi;
    for (var i = 0; i < 14; i++) {
      final mid = 0.5 * (lo + hi);
      if (short(mid) > 0.0) {
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
      ..setRotation(Quaternion.axisAngle(vessel.leanAxis, tilt))
      ..setPositionFrom(base);
    vessel.mirror
      ..setRotation(Quaternion.axisAngle(vessel.leanAxis, -tilt))
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
      return to.at + Vector3(0, rim + 0.001, 0) - t.towards * back;
    }();
    // The lip is the side of the mouth that goes down: towards the pour.
    final lip = t.towards * from.lip.z + Vector3(0, from.lip.y, 0);
    // Turned by the matrix the scene node will be: `Quaternion.rotated`
    // turns the other way round, and the lip came down a hand's width past
    // the clean tube.
    Vector3 baseFor(double tilt) =>
        aim -
        Quaternion.axisAngle(t.axis, tilt).asRotationMatrix().transformed(lip);

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
      // Ahead of the liquid, not behind it: tipped to where the lip runs
      // what the hand wants, by the same weir the liquid runs by. A hand
      // that answered the flow it saw was always late; one that tipped to
      // hold the next eighth of a second's worth less stood the surface a
      // fraction of a millimetre over the lip of a tube on its side, where
      // its whole length spreads it, and the clean tube filled drop by drop.
      final target = math.max(
        _tiltPouring(from, from.liquid.volume, wanted),
        t.spill,
      );
      t.hand += (target - t.hand).clamp(-2.0 * seconds, 2.0 * seconds);
      tilt = t.hand;
      if (remaining <= 1e-10 || time - start > 3.0 * _pourTime + 2.0) {
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
  final Map<String, Color> _dropColours = {};

  /// What is out of the glasses (streams, drops, puddles) hung upside down
  /// under the tabletop, as each vessel's liquid is in its own mirror: one
  /// reflection per node, sharing its mesh.
  late final SceneNode _spiltMirror = () {
    final made = SceneNode(name: 'spilt reflection')..setScale(1, -1, 1);
    scene.add(made);
    return made;
  }();
  final Map<MeshNode, MeshNode> _spiltReflections = {};

  /// The puddles on the bench drawn, one node each, reused in order.
  final List<MeshNode> _puddles = [];
  final List<Color?> _puddleColours = [];

  /// Moves everything on by [seconds], and says whether anything still
  /// moves, so the caller knows to ask for another frame.
  bool step(double seconds) {
    var moving = false;
    for (final vessel in vessels) {
      if (identical(vessel, _transfer?.from)) continue;
      // **Lifted out of the row before it leans, and put back after.** The
      // height it must clear its neighbours by is taken for the lean it is
      // going to as well as the one it has, so the hand rises first; and
      // the rise is eased as the turn is. Taken for the lean it had, the
      // height jumped by centimetres the frame the tipping glass first came
      // over a neighbour, and the jolt threw nearly all it held out.
      //
      // **Either way, the same height.** A hand takes a glass up out of the
      // row whichever way it then tips it: lifted only as far as the side it
      // leaned to needed, a tube at the end of the row leaning off it was
      // not lifted at all and lay down on the bench, and leaning one way
      // and the other looked like two different hands.
      final need = [
        vessel.tilt,
        -vessel.tilt,
        vessel.leanTo,
        -vessel.leanTo,
      ].map((at) => _clearance(vessel, at)).reduce(math.max);
      final rose = _ease2(vessel, need, seconds);
      vessel.lift = need > 0.0 ? 1.0 : 0.0;
      if (_turn(vessel, seconds) | rose) {
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
        ? (() {
            final m = liquidMeshes(
              vessel.liquid,
              segments: 32,
              rows: 24,
              rings: 8,
            );
            return m;
          })()
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
                _upload(meshes[i].mesh),
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
                _upload(mesh),
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
      // The colour of what is in them, as a solution's is: the drops off
      // a pour of copper sulphate are blue, not the near white they were.
      final colour = _colourOf(fluid.concentrations);
      final node = _drops.putIfAbsent(medium, () {
        final made = MeshNode(
          _upload(particleMesh(const [], 0.0005)),
          liquid(_rgb(colour), depth: 2.0 * fluid.spacing),
          name: 'drops',
        )..castsShadow = false;
        scene.add(made);
        return made;
      });
      if (_dropColours[medium] != colour) {
        _dropColours[medium] = colour;
        node.material = liquid(_rgb(colour), depth: 2.0 * fluid.spacing);
      }
      if (fluid.count > 0) any = true;
      final drops = _clusters(fluid.positions, fluid.volumes, fluid.spacing);
      _swap(
        node,
        particleMesh(
          [for (final d in drops) d.centre],
          0.0,
          radii: [
            for (final d in drops)
              math
                  .pow(
                    3.0 * d.volume / (4.0 * math.pi),
                    1.0 / 3.0,
                  )
                  .toDouble(),
          ],
        ),
      );
      node.visible = fluid.count > 0;
    });
    // What lies on the bench: a cap of each drop or puddle's own radius and
    // height, the colour of what is in it.
    final g = world.gravity.length;
    final lying = [for (final s in world.spills) ...s.puddles];
    for (var i = 0; i < math.max(lying.length, _puddles.length); i++) {
      if (i >= lying.length) {
        _puddles[i].visible = false;
        continue;
      }
      final puddle = lying[i];
      final colour = _colourOf(puddle.concentrations);
      if (i >= _puddles.length) {
        final made = MeshNode(
          _upload(capMesh(const [], const [], const [])),
          liquid(_rgb(colour), depth: 0.001),
          name: 'puddle',
        )..castsShadow = false;
        scene.add(made);
        _puddles.add(made);
        _puddleColours.add(colour);
      }
      final node = _puddles[i];
      if (_puddleColours[i] != colour) {
        _puddleColours[i] = colour;
        node.material = liquid(_rgb(colour), depth: 0.001);
      }
      final r = puddle.radius(g);
      if (r < puddle.restRadius(g)) any = true;
      _swap(
        node,
        capMesh([puddle.centre], [r], [puddle.capHeight(r)]),
      );
      node.visible = true;
    }
    _reflectSpilt();
    return any;
  }

  /// Every stream, drop and puddle node given its reflection, or brought
  /// up to date with it: the same mesh, shown when it is, the colour of
  /// its liquid. Left out, a stream poured over the bench stood in the
  /// mirror nowhere, under glasses whose liquids all did.
  void _reflectSpilt() {
    final nodes = [..._streams.values, ..._drops.values, ..._puddles];
    for (final gone in _spiltReflections.keys
        .where((n) => !nodes.contains(n))
        .toList()) {
      _spiltReflections.remove(gone)!.removeFromParent();
    }
    for (final node in nodes) {
      final c = node.material.baseColor;
      final colour = Vector3(c.x, c.y, c.z);
      final reflection = _spiltReflections.putIfAbsent(node, () {
        final made =
            MeshNode(
                node.mesh,
                _reflection(albedo: null, colour: colour),
                name: '${node.name} reflection',
              )
              ..castsShadow = false
              ..lightChannels = LightChannels.none;
        _spiltMirror.add(made);
        return made;
      });
      reflection
        ..mesh = node.mesh
        ..visible = node.visible;
      final was = reflection.material.baseColor;
      if ((was.x - colour.x * 0.7).abs() > 1e-6 ||
          (was.y - colour.y * 0.7).abs() > 1e-6 ||
          (was.z - colour.z * 0.7).abs() > 1e-6) {
        reflection.material = _reflection(albedo: null, colour: colour);
      }
    }
  }

  /// [positions] gathered into drops: particles nearer each other than
  /// one and a half spacings are one drop, drawn as one sphere of all their
  /// liquid. A stream that breaks into drops two and a third of its width
  /// across was drawn as a scatter of millimetre dots, each a particle.
  static List<({Vector3 centre, double volume})> _clusters(
    List<Vector3> positions,
    List<double> volumes,
    double spacing,
  ) {
    final n = positions.length;
    final parent = List<int>.generate(n, (i) => i);
    int root(int i) {
      var r = i;
      while (parent[r] != r) {
        r = parent[r];
      }
      return parent[i] = r;
    }

    final reach2 = 2.25 * spacing * spacing;
    for (var i = 0; i < n; i++) {
      for (var j = i + 1; j < n; j++) {
        if (positions[i].distanceToSquared(positions[j]) < reach2) {
          parent[root(i)] = root(j);
        }
      }
    }
    // Each drop's middle is the middle of its liquid, weighed by volume.
    final sums = <int, ({Vector3 sum, double volume})>{};
    for (var i = 0; i < n; i++) {
      final r = root(i);
      final s = sums[r];
      final v = volumes[i];
      sums[r] = s == null
          ? (sum: positions[i] * v, volume: v)
          : (sum: s.sum..addScaled(positions[i], v), volume: s.volume + v);
    }
    return [
      for (final s in sums.values)
        (centre: s.sum / s.volume, volume: s.volume),
    ];
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
    required this.axis,
  }) : towards = axis.cross(Vector3(0, 1, 0))..normalize();

  final Vessel from;
  final Vessel to;

  /// The horizontal axis the glass tips about, and the way it pours: a turn
  /// about [axis] brings up round to [towards].
  final Vector3 axis;
  final Vector3 towards;

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
