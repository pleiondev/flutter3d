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
  });

  /// What the controls call it.
  final String name;

  /// Where its base stands.
  final Vector3 at;

  /// Its outline, swept into the glass.
  final List<Vector2> glass;

  /// The liquid's outline when it is filled to a level.
  final List<Vector2> Function(double level) liquidAt;

  final Color colour;

  /// How far it may be filled, in metres up from its base.
  final double lowest;
  final double highest;

  /// What its label says; null for glass that wears none.
  final Solution? solution;

  /// How full it is now. State: pouring changes it.
  double level;

  late final MeshNode liquid;
  MeshNode? label;
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
      at: Vector3(-1.05, 0, -0.25),
      glass: cylinderProfile(),
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
final class Bench {
  Bench(this.device, {List<Vessel>? vessels})
    : vessels = vessels ?? standardVessels() {
    for (final vessel in this.vessels) {
      vessel.liquid = MeshNode(
        _lathe(vessel.liquidAt(vessel.level)),
        liquid(_rgb(vessel.colour)),
        name: '${vessel.name} liquid',
      )..setPositionFrom(vessel.at);
      scene.add(vessel.liquid);
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
          ..setPositionFrom(vessel.at),
      );
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
            baseColor: Vector4(0.36, 0.38, 0.42, 1),
            roughness: 0.6,
          ),
          name: 'bench',
        )..setPosition(0, -0.02, 0.6),
      )
      ..add(
        LightNode(name: 'sun', intensity: 2.4)
          ..setLocalForward(Vector3(-0.5, -1.0, -0.6)),
      )
      ..add(
        LightNode(name: 'fill', intensity: 0.9)
          ..setLocalForward(Vector3(0.6, -0.4, 0.8)),
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
    if (old is DeviceMesh) (retire ?? _releaseNow)(old);
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
    vessel.label = MeshNode(
      DeviceMesh.upload(device, labelBand().build()),
      paper(texture),
      name: '${vessel.name} label',
    )..setPositionFrom(vessel.at);
    scene.add(vessel.label!);
    return texture;
  }
}
