/// The map's world drawn and heard: the pond and the stream, the flames and
/// the smoke, the stones and the brands, the castles and the woods sooted.
///
/// **It reads the world and never writes to it.** The world is the match's
/// — the simulation steps it with every one of its own steps, and a replay
/// steps it again — so what is here only looks: it is handed the
/// world's events once a frame, puts a mesh on each thing thrown, darkens
/// what has burnt, and plays what the fires and the water sound like. A run
/// drawn and a run not drawn are the same run.
library;

import 'dart:math' as math;
import 'dart:typed_data' show ByteData;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_effects/flutter3d_effects.dart';
import 'package:flutter3d_elements/flutter3d_elements.dart';
import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:vector_math/vector_math.dart';

import 'kit.dart' show pondLevel;
import 'map_world.dart';
import 'staging.dart';
import 'woods.dart' show plantWoods, woodScales;

/// The world over one map, drawn into a scene through a renderer.
final class MapEffects {
  MapEffects._({
    required GraphicsDevice device,
    required this._scene,
    required this._elements,
    required this._world,
    required this._staged,
    required ByteData liquid,
    required Vector3 sunAlong,
    required Vector3 sunLight,
  }) {
    _look = LiquidLook.of(liquid)
      ..optics = _optics
      ..wind = _world.wind.length
      ..sun(along: sunAlong, light: sunLight);
    _river = LiquidView(
      world: _world.world,
      liquid: _world.river,
      ground: _world.bed,
      device: device,
      scene: _scene,
      look: _look.material,
      detail: _elements.quality.liquid,
    );
    _elements.hearing?.listen(
      _world.river,
      density: NativeLiquidProperties.water.density,
    );
    _stoneMesh = DeviceMesh.upload(
      device,
      const SphereShape(radius: 1.0, segments: 10, rings: 7).build(),
    );
    _blockMesh = DeviceMesh.upload(
      device,
      CuboidShape(size: Vector3.all(2.0)).build(),
    );
    _drawBoulders();
    // The painted sheet gives way to the water that moves.
    _staged.visuals.water?.isVisible = false;
    _river.update();
  }

  /// Draws [world], the world of [staged]'s match, into [scene] through
  /// [renderer], lit by the sun along [sunAlong] with [sunLight].
  static Future<MapEffects> open({
    required GraphicsDevice device,
    required Scene scene,
    required Renderer renderer,
    required MapWorld world,
    required Staged staged,
    required Vector3 sunAlong,
    required Vector3 sunLight,
  }) async {
    final phone =
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    final elements = await Elements.adopt(
      world.world,
      device: device,
      renderer: renderer,
      scene: scene,
      load: rootBundle.load,
      quality: ElementsQuality.of(phone: phone),
      // Heard from where the camera hangs, forty metres and more up: a
      // crown alight is the quietest fire worth hearing, a burning hall
      // the loudest.
      hearing: (NativeWorld native) => PhysicsHearing(
        native,
        fireScale: const HearingScale(quiet: 500.0, loud: 5e5, reference: 2e4),
        fallScale: const HearingScale(quiet: 50.0, loud: 1e5, reference: 5e3),
        splashScale: const HearingScale(quiet: 20.0, loud: 2e4, reference: 2e3),
      ),
    );
    return MapEffects._(
      device: device,
      scene: scene,
      elements: elements,
      world: world,
      staged: staged,
      liquid: await rootBundle.load(LiquidLook.asset),
      sunAlong: sunAlong,
      sunLight: sunLight,
    );
  }

  /// A hill pond over earth, and a river stirring it up: green and cloudy,
  /// letting through two parts in a thousand a metre.
  static final LiquidOptics _optics = LiquidOptics(
    absorb: Vector3.all(6.215),
    backscatter: Vector3(0.1268, 0.4678, 0.6905),
  );

  final Elements _elements;
  final MapWorld _world;
  final Staged _staged;
  final Scene _scene;
  late final LiquidLook _look;
  late final LiquidView _river;
  late final DeviceMesh _stoneMesh, _blockMesh;
  final List<MeshNode> _boulders = <MeshNode>[];

  /// What draws each piece of the world, and its body as the elements keep
  /// it.
  final Map<MapPiece, (TrackedBody, MeshNode)> _drawn =
      <MapPiece, (TrackedBody, MeshNode)>{};

  /// Where each tree is drawn, batch by batch: the woods the kit planted,
  /// planted again here for the snag a burnt-out tree is drawn as.
  late final List<List<Matrix4>> _planted = plantWoods(
    simulation: _staged.simulation,
    kinds: woodScales,
    waterLevel: pondLevel,
  );

  /// How black each tree has been drawn, nought to one, and two once it has
  /// been drawn a snag.
  final Expando<double> _charred = Expando<double>('charred');

  /// The castles' colours before any soot, by hall.
  final Map<int, LinearColor> _fresh = <int, LinearColor>{};

  double _seconds = 0.0;

  /// What the fires, the stream and the splashes sound like this frame.
  PhysicsHearing get hearing => _elements.hearing!;

  /// The stones laid in the river drawn: rounded boulders, a little sunk
  /// into the bed, standing out of the water.
  void _drawBoulders() {
    for (final (n, (:at, down: _, :size, level: _))
        in _world.boulders.indexed) {
      final node =
          MeshNode(
              _stoneMesh,
              RenderMaterial(
                name: 'boulder',
                baseColor: LinearColor.fromSrgb(0.42, 0.40, 0.37, 1.0),
                roughness: 0.9,
              ),
              name: 'boulder',
            )
            ..setPosition(at.x, at.y + 0.25, at.z)
            ..setRotation(Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), n * 1.7))
            ..setScale(size, 0.6 * size, 0.8 * size);
      _scene.add(node);
      _boulders.add(node);
    }
  }

  /// The world drawn as it stands, [dt] seconds of picture after the last
  /// frame, from [eye].
  void update(double dt, {required Vector3 eye}) {
    if (dt <= 0.0) return;
    _seconds += dt;
    _pieces();
    _look.wind = _world.wind.length;
    _elements.update(dt, eye: eye, events: _world.takeEvents());
    _look.update(seconds: _seconds, eye: eye, pixel: 0.001);
    _river.update(dt);
    _glow();
    _char();
  }

  /// A mesh put on every piece the world has thrown since the last frame,
  /// and taken off every piece it has let go.
  void _pieces() {
    final Set<MapPiece> live = _world.pieces.toSet();
    _drawn.removeWhere((MapPiece piece, (TrackedBody, MeshNode) drawn) {
      if (live.contains(piece)) return false;
      _elements.remove(drawn.$1);
      _scene.remove(drawn.$2);
      return true;
    });
    for (final MapPiece piece in _world.pieces) {
      if (_drawn.containsKey(piece)) continue;
      final Vector3 s = piece.size;
      final MeshNode node = switch (piece.kind) {
        PieceKind.stone => MeshNode(
          _stoneMesh,
          RenderMaterial(
            name: 'stone',
            baseColor: LinearColor.fromSrgb(0.42, 0.40, 0.37, 1.0),
            roughness: 0.9,
          ),
          name: 'stone',
        )..setScale(s.x, s.x, s.x),
        PieceKind.rubble => MeshNode(
          _blockMesh,
          RenderMaterial(
            name: 'rubble',
            // The castle's sandstone, a little dirtier for having come off.
            baseColor: LinearColor.fromSrgb(0.80, 0.68, 0.52, 1.0),
            roughness: 0.95,
          ),
          name: 'rubble',
        )..setScale(s.x, s.y, s.z),
        // A brand, and anything else the world one day throws: a ball.
        _ => MeshNode(
          _stoneMesh,
          RenderMaterial(
            name: 'brand',
            baseColor: LinearColor.fromSrgb(0.1, 0.05, 0.02, 1.0),
          ),
          name: 'brand',
        )..setScale(s.x, s.x, s.x),
      };
      _scene.add(node);
      _drawn[piece] = (_elements.track(piece.body, look: node), node);
    }
  }

  /// Every brand glowing as hot as its surface is.
  void _glow() {
    for (final MapEntry<MapPiece, (TrackedBody, MeshNode)> drawn
        in _drawn.entries) {
      if (drawn.key.kind != PieceKind.brand) continue;
      drawn.value.$2.material.emissive = _light(
        _world.world.surfaceTemperatureOf(drawn.key.body),
      ).toLinearColor();
    }
  }

  /// The light a surface at [kelvin] gives off, as the engine's emissive: its
  /// luminance, the exitance εσT⁴ over π as a Lambertian surface's is, as the
  /// lumens a blackbody that hot gives, in its colour.
  static Vector3 _light(double kelvin) {
    final double nits =
        MapWorld.dry.emissivity *
        stefanBoltzmann *
        kelvin *
        kelvin *
        kelvin *
        kelvin *
        Blackbody.efficacy(kelvin) /
        math.pi;
    return Blackbody.color(kelvin)..scale(nits / Photometric.bulbAtOneMeter);
  }

  /// Every tree with a body drawn as burnt as it is: blackening by the share
  /// of it char covers, and once burnt out, a bare black snag. A castle
  /// whose timber has caught goes towards char's colour by the share of its
  /// timbers' surface char covers.
  ///
  /// **Not [FireView.watch]**, which chars a body's own look and makes it
  /// glow while it burns: the castle is one model, stone walls and timber
  /// roofs together, and a whole castle glowing like an ember because one
  /// tower's roof is alight read as a castle lit pink. Here the stone only
  /// darkens, by how much of its timber has gone.
  void _char() {
    final NativeWorld world = _world.world;
    for (final MapHall hall in _world.halls) {
      if (hall.timbers.isEmpty) continue;
      final double soot =
          hall.timbers
              .map((NativeBody timber) => world.charOf(timber).share)
              .reduce((a, b) => a + b) /
          hall.timbers.length;
      if (soot <= 0.0 && !_fresh.containsKey(hall.index)) continue;
      final MeshNode? look = _staged.visuals.buildingAt(hall.index);
      if (look == null) continue;
      final LinearColor fresh = _fresh[hall.index] ??= look.material.baseColor;
      // Towards char in the encoded colour, as the look was tuned.
      final was = fresh.toSrgb();
      look.material.baseColor = LinearColor.fromSrgb(
        was.r + (_charColour.x - was.r) * soot,
        was.g + (_charColour.y - was.g) * soot,
        was.b + (_charColour.z - was.b) * soot,
        fresh.a,
      );
    }
    // The world plants its woods from the map, whether or not the kit that
    // draws them loaded: a tree in no batch drawn is a tree with no look.
    final int batches = _staged.visuals.propBatchCount;
    for (final MapTree tree in _world.burnable) {
      if (tree.batch >= batches) continue;
      final double drawn = _charred[tree] ?? 0.0;
      if (drawn >= 2.0) continue;
      final double black = world.charOf(tree.body!).share;
      if (!tree.dead && black - drawn < 0.02) continue;
      final double g = tree.dead ? 0.1 : 1.0 - 0.9 * black;
      final bool dressed = _staged.visuals.dressProp(
        tree.batch,
        tree.placement,
        color: Vector4(g, g * 0.97, g * 0.93, 1.0),
        transform: tree.dead
            ? (_planted[tree.batch][tree.placement].clone()
                ..scaleByDouble(0.45, 0.85, 0.45, 1.0))
            : null,
      );
      if (!dressed) continue;
      // Two marks a snag already drawn as one, so it is not drawn again.
      _charred[tree] = tree.dead ? 2.0 : black;
    }
  }

  /// Char's colour, as `FireView` draws it.
  static Vector4 get _charColour => Vector4(0.06, 0.05, 0.045, 1.0);

  /// Everything drawn taken out of the scene; the world is the match's, and
  /// is let go with it.
  void dispose() {
    for (final (TrackedBody body, MeshNode node) in _drawn.values) {
      _elements.remove(body);
      _scene.remove(node);
    }
    _drawn.clear();
    _boulders.forEach(_scene.remove);
    _elements.hearing?.unlisten(_world.river);
    _river.dispose();
    _elements.dispose();
  }
}
