import 'package:flutter/painting.dart' show Color;
import 'package:flutter3d/flutter3d.dart';
import 'package:vector_math/vector_math.dart';

import 'glassware.dart';
import 'label.dart';

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
    this.focuses = true,
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

  final Color colour;

  /// How far it may be filled, in metres up from its base.
  final double lowest;
  final double highest;

  /// What its label says; null for glass that wears none.
  final Solution? solution;

  /// Whether its liquid throws a caustic on the bench. **The engine packs at
  /// most eight lights per object**, and the bench already has the sun and
  /// a fill: a ninth light pushes one out, and the sun's shadow went with
  /// it. Six caustics fit; the cylinder's narrow column and the flask go
  /// without.
  final bool focuses;

  /// How full it is now. State: pouring changes it.
  double level;

  late final MeshNode liquid;
  MeshNode? label;

  /// Its liquid and its label mirrored under the tabletop; see [Bench].
  late final MeshNode liquidReflection;
  MeshNode? labelReflection;

  /// The bright patch its liquid focuses onto the bench, if it [focuses];
  /// see [Bench].
  LightNode? caustic;
}

Vector3 _rgb(Color c) => Vector3(c.r, c.g, c.b);

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
      name: 'Cylinder',
      focuses: false,
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
      focuses: false,
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
/// **The caustics are a light, not a calculation.** A column of liquid is a
/// lens, and sunlight through it lands as a bright, tinted patch inside its
/// own shadow. The engine traces no photons, so each vessel carries a small
/// spot light of its solution's colour, aimed at where its liquid's shadow
/// falls and shining on the bench alone (light channel 1): the glass and the
/// liquids stay on channel 0 and are not lit by it. Pouring moves the patch
/// and makes it stronger or weaker with the height of the column.
///
/// **The reflections in the tabletop are geometry too.** Screen-space
/// reflections read only what the opaque pass drew, and the glass and the
/// liquids are drawn after it, so the tabletop reflected the labels and
/// nothing else. The table is flat, though, and a flat mirror has an exact
/// answer: each liquid and label again, scaled by -1 in height so it hangs
/// under the top, and a top that lets a twelfth of what is under it through.
/// The copies are opaque and unlit, so they are drawn before the top and
/// never sorted against it.
final class Bench {
  Bench(this.device, {List<Vessel>? vessels})
    : vessels = vessels ?? standardVessels() {
    for (final vessel in this.vessels) {
      vessel.liquid =
          MeshNode(
              _lathe(vessel.liquidAt(vessel.level)),
              liquid(_rgb(vessel.colour)),
              name: '${vessel.name} liquid',
            )
            ..setPositionFrom(vessel.at)
            ..lightChannels = _vesselChannel;
      if (vessel.focuses) {
        final caustic = vessel.caustic = LightNode(
          type: LightType.spot,
          name: '${vessel.name} caustic',
          color: _rgb(vessel.colour) * 0.8 + Vector3.all(0.2),
          outerConeAngle: 0.12,
          innerConeAngle: 0.02,
        )..channels = _benchChannel;
        scene.add(caustic);
        _focus(vessel);
      }
      vessel.liquidReflection = _mirrored(
        vessel.liquid.mesh,
        _reflection(albedo: null, colour: _rgb(vessel.colour)),
        vessel,
      );
      scene
        ..add(vessel.liquid)
        ..add(vessel.liquidReflection);
      scene.add(
        MeshNode(
            _lathe(glassWall(vessel.glass)),
            glass(),
            name: '${vessel.name} glass',
          )
          // Clear glass barely darkens what is behind it, and the engine's
          // shadows are all or nothing, so the glass casts none and the
          // coloured liquid inside it casts the shadow.
          ..castsShadow = false
          ..lightChannels = _vesselChannel
          ..setPositionFrom(vessel.at),
      );
      final foot = vessel.foot;
      if (foot != null) {
        final hexagon = DeviceMesh.upload(
          device,
          LatheShape(profile: foot, segments: 6).build(),
        );
        scene
          ..add(
            MeshNode(hexagon, footPlastic(), name: '${vessel.name} foot')
              ..lightChannels = _vesselChannel
              ..setPositionFrom(vessel.at),
          )
          ..add(
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
        ..ambientIntensity = 1.0;
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
              baseColor: Vector4(0.2, 0.22, 0.25, 0.92),
              alphaMode: MaterialAlphaMode.blend,
              // Glossy enough for the screen-space reflections, which fade
              // out by 0.25: the liquids show in the tabletop.
              roughness: 0.25,
            ),
            name: 'bench',
          )
          ..setPosition(0, -0.02, 0.6)
          // Its own channel: the sun reaches every channel, the caustics
          // only this one, and the fill only the glass.
          ..lightChannels = _benchChannel,
      )
      ..add(
        LightNode(name: 'sun', intensity: 2.4)
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
  final List<Vessel> vessels;

  /// How a replaced mesh is let go of: after the frames still drawing it
  /// when there is a renderer (`Renderer.releaseMeshAfterFrame`), at once
  /// when there is none.
  void Function(DeviceMesh mesh)? retire;

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
    vessel.level = level.clamp(vessel.lowest, vessel.highest);
    final old = vessel.liquid.mesh;
    vessel.liquid.mesh = _lathe(vessel.liquidAt(vessel.level));
    vessel.liquidReflection.mesh = vessel.liquid.mesh;
    if (old is DeviceMesh) (retire ?? _releaseNow)(old);
    _focus(vessel);
  }

  /// [mesh] hung upside down under the tabletop at [vessel]'s place.
  MeshNode _mirrored(MeshGeometry mesh, Material material, Vessel vessel) =>
      MeshNode(mesh, material, name: '${vessel.name} reflection')
        ..setPositionFrom(vessel.at)
        ..setScale(1, -1, 1)
        ..castsShadow = false
        ..lightChannels = LightChannels.none;

  /// What a reflection is drawn with: flat, a little darker than the
  /// thing, and from both sides, since the mirroring turns it inside out.
  static Material _reflection({
    required TextureHandle? albedo,
    required Vector3 colour,
  }) => Material(
    name: 'reflection',
    lighting: LightingModel.unlit,
    albedo: albedo,
    baseColor: Vector4(colour.x * 0.7, colour.y * 0.7, colour.z * 0.7, 1),
    doubleSided: true,
  );

  static const int _vesselChannel = 1 << 0;
  static const int _benchChannel = 1 << 1;

  /// Where sunlight goes: the sun node's forward.
  static final Vector3 _sun = Vector3(-0.5, -1.0, -0.6)..normalize();

  /// Aims [vessel]'s caustic at the middle of its liquid's shadow, along
  /// the sunlight from half a metre back, as strong as the column is tall.
  void _focus(Vessel vessel) {
    final caustic = vessel.caustic;
    if (caustic == null) return;
    final middle = (vessel.lowest + vessel.level) * 0.5;
    final lit = vessel.at + Vector3(0, middle, 0) + _sun * (middle / -_sun.y);
    final from = lit - _sun * 0.5;
    caustic
      ..intensity = 4.0 * (vessel.level - vessel.lowest).clamp(0.0, 1.0)
      ..setPosition(from.x, from.y, from.z)
      ..lookAt(lit);
  }

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
    final old = vessel.label;
    if (old != null) scene.remove(old);
    final oldReflection = vessel.labelReflection;
    if (oldReflection != null) scene.remove(oldReflection);
    final band = DeviceMesh.upload(device, labelBand().build());
    vessel.labelReflection = _mirrored(
      band,
      _reflection(albedo: texture, colour: Vector3.all(1)),
      vessel,
    );
    scene.add(vessel.labelReflection!);
    vessel.label = MeshNode(band, paper(texture), name: '${vessel.name} label')
      ..setPositionFrom(vessel.at)
      ..lightChannels = _vesselChannel;
    scene.add(vessel.label!);
    return texture;
  }
}
