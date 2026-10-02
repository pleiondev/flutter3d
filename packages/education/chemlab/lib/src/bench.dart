import 'dart:math' as math;

import 'package:flutter/painting.dart' show Color;
import 'package:flutter3d/flutter3d.dart';
import 'package:vector_math/vector_math.dart';

import 'glassware.dart';
import 'label.dart';
import 'optics.dart';
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

  final Color colour;

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
  late final List<Vector2> wall = () {
    final full = liquidAt(highest);
    // The cap is `meniscus`'s six points; its first is the top of the wall.
    return full.sublist(0, full.length - 5);
  }();

  /// Its liquid's surface and how it moves.
  late final Slosh slosh = Slosh(
    radius: radiusAt(wall, level) ?? wall.last.x,
    depth: level - wall.first.y,
  );

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
    vessel.level = level.clamp(vessel.lowest, vessel.highest);
    vessel.slosh
      ..radius = radiusAt(vessel.wall, vessel.level) ?? vessel.wall.last.x
      ..depth = vessel.level - vessel.wall.first.y;
    _reshape(vessel);
    if (!photons && vessel.tilt == 0.0) _repaint(vessel);
  }

  /// The liquid's mesh for where its surface is now.
  DeviceMesh _liquidMesh(Vessel vessel) => DeviceMesh.upload(
    device,
    liquidVolume(wall: vessel.wall, level: vessel.level, surface: vessel.slosh),
  );

  void _reshape(Vessel vessel) {
    final old = vessel.liquid.mesh;
    vessel.liquid.mesh = _liquidMesh(vessel);
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

  /// Moves every liquid on by [seconds], and says whether any is still
  /// moving, so the caller knows to ask for another frame.
  bool step(double seconds) {
    var moving = false;
    for (final vessel in vessels) {
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
    final card = !photons && vessel.tilt == 0.0;
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
