/// The crypt's fire, water and loose wood, drawn and heard: the crates and
/// barrels and their pieces where the run's world has them, charring and
/// glowing as they burn, the fires' flames, smoke and light, the vault's
/// water, the splinters a round knocks off and the splashes of a stride.
///
/// **It reads the run and writes nothing to it.** The world is the run's —
/// see [CryptWorld], which the simulation steps and saves — and this is
/// adopted onto it: it is never stepped from here, no body is made or
/// moved in it from here, and its events are the ones the step already
/// read. A run drawn and the same run not drawn are the same run, which is
/// what keeps a replay and a test of it honest.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_demo_content/crypt.dart';
import 'package:flutter3d_effects/flutter3d_effects.dart';
import 'package:flutter3d_particles/flutter3d_particles.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart'
    show NativeBody;
import 'package:flutter3d_sim/flutter3d_sim.dart' show Actor;

import 'flooded_vault.dart';
import 'wooden_props.dart';

/// What draws one piece of wood: its look, its fire's char on the first of
/// its meshes, and the handle it was drawn for.
final class _Drawn {
  _Drawn(this.body, this.look);

  final int body;
  final SceneNode look;
}

/// How far a walker has waded since its last splash, and where it was.
final class _Wading {
  _Wading(this.at);

  final Vector3 at;
  bool wet = false;
  double stride = 0.0;
}

/// The crypt's elements, drawn into each level's scene.
final class CryptElements {
  CryptElements({
    required this.elements,
    required this._device,
    required this._liquidBundle,
    required this.props,
    required this.particles,
    this.light = false,
  });

  /// What draws and hears the run's world: adopted onto it, so it steps
  /// nothing.
  final Elements elements;

  final GraphicsDevice _device;
  final ByteData _liquidBundle;

  /// The crates' and barrels' meshes and pictures.
  final WoodenProps props;

  /// The game's own particles, which the splashes and the splinters join.
  final ParticleSystem particles;

  /// Whether to draw less of the water, for a phone.
  final bool light;

  /// What the fires and the water sound like this frame.
  PhysicsHearing get hearing => elements.hearing!;

  /// The strides through the water since the last frame, each a splash.
  final List<Audible> wading = <Audible>[];

  /// The torches' heads, whose fires the fixtures' own sounds already
  /// carry: by raw handle.
  Set<int> get torchHeads => <int>{
    for (final t in _crypt?.torches ?? const <CryptTorch>[]) t.head.raw,
  };

  CryptWorld? _crypt;
  Scene? _scene;
  FloodedVault? _vault;
  RenderMaterial? _stoneLook;
  final Map<int, _Drawn> _drawn = <int, _Drawn>{};
  final Map<int, _Wading> _walkers = <int, _Wading>{};
  double _seconds = 0.0;

  // ---------------------------------------------------------------- level

  /// The last level's let go, and [crypt] drawn into [scene].
  void enter({
    required CryptWorld crypt,
    required Scene scene,
    required Map<String, TextureHandle?> textures,
  }) {
    _clear();
    _crypt = crypt;
    // The splinters and the splashes fall as the crypt's world does.
    particles.gravity = crypt.world.gravityMagnitude;
    _scene = scene;
    elements.scene = scene;
    _stoneLook = RenderMaterial(
      name: 'vault stone',
      albedo: textures['assets/textures/stone_albedo.jpg'],
      normal: textures['assets/textures/stone_normal.png'],
      baseColor: LinearColor.fromSrgb(0.7, 0.66, 0.6, 1.0),
      roughness: 0.9,
    );
    final vault = crypt.vault;
    if (vault != null) {
      _vault = FloodedVault(
        world: crypt.world,
        vault: vault,
        liquidBundle: _liquidBundle,
        device: _device,
        scene: scene,
        stone: _stoneLook!,
        light: light,
      );
      elements.hearing?.listen(vault.liquid);
    }
  }

  void _clear() {
    for (final drawn in _drawn.values) {
      _forget(drawn);
    }
    _drawn.clear();
    _walkers.clear();
    final vault = _vault;
    if (vault != null) {
      elements.hearing?.unlisten(vault.vault.liquid);
      vault.dispose();
    }
    _vault = null;
    _crypt = null;
    wading.clear();
  }

  void _forget(_Drawn drawn) {
    elements.fireView.forget(NativeBody(drawn.body));
    drawn.look.removeFromParent();
  }

  // ----------------------------------------------------------------- wood

  /// A look for [w], in the scene and charred with its fire.
  _Drawn _look(CryptWood w) {
    final nodes = switch (w.kind) {
      WoodKind.crate => <MeshNode>[
        MeshNode(props.crate, props.wood(tint: _tint(w.serial)), name: 'crate')
          ..setScale(w.size, w.size, w.size),
      ],
      WoodKind.barrel => <MeshNode>[
        MeshNode(props.barrel, props.wood(), name: 'barrel'),
        MeshNode(props.hoops, props.iron, name: 'hoops'),
      ],
      WoodKind.plank => <MeshNode>[
        MeshNode(props.plank, props.wood(), name: 'piece'),
      ],
      // A stave, and whatever else the package one day breaks wood into:
      // drawn as a piece rather than not at all.
      _ => <MeshNode>[MeshNode(props.stave, props.wood(), name: 'piece')],
    };
    final look = SceneNode(name: w.barrel ? 'barrel' : 'crate');
    for (final node in nodes) {
      look.add(node);
    }
    _scene?.add(look);
    elements.fireView.watch(w.body, nodes.first);
    return _Drawn(w.body.raw, look);
  }

  /// A crate's boards a little lighter or darker than the next one's: by
  /// its number, so the same crate is the same colour after a rewind.
  static Vector4 _tint(int serial) {
    double share(int k) => ((serial * 2654435761 + k * 40503) % 1000) / 1000.0;
    return Vector4(1.0, 0.84 + 0.06 * share(1), 0.66 + 0.08 * share(2), 1.0);
  }

  /// The looks made to agree with what the run has: one for each piece of
  /// wood, by its number, put where the world has it; one gone for each
  /// that is gone — burnt up, broken, or undone by a rewind.
  void _drawWood(CryptWorld crypt) {
    final now = <int, CryptWood>{
      for (final w in crypt.wood) w.serial: w,
      for (final w in crypt.pieces) w.serial: w,
    };
    _drawn.removeWhere((serial, drawn) {
      final w = now[serial];
      if (w != null && w.body.raw == drawn.body) return false;
      _forget(drawn);
      return true;
    });
    for (final MapEntry(key: serial, value: w) in now.entries) {
      final drawn = _drawn[serial] ??= _look(w);
      if (!crypt.world.contains(w.body)) continue;
      drawn.look
        ..setPositionFrom(crypt.world.localPositionOf(w.body))
        ..setRotation(crypt.world.orientationOf(w.body));
    }
  }

  /// Wood splinters off where a round strikes it.
  ///
  /// Public, as [splash] is, so `test/effect_documents_test.dart` holds
  /// `effects/crypt.f3dfx` to them particle for particle.
  static final ParticleEffect splinters = ParticleEffect(
    count: 8,
    emitter: const ConeEmitter(
      speed: Range(1.5, 4.5),
      halfAngle: 35.0 * math.pi / 180.0,
    ),
    lifetime: const Range(0.25, 0.6),
    size: const Range(0.03, 0.07),
    color: Vector4(0.42, 0.33, 0.22, 1.0),
    affectors: <ParticleAffector>[
      const ParticleGravity(),
      const ParticleFade(startsAt: 0.5),
    ],
  );

  /// Water thrown up by a stride or a body falling in.
  static final ParticleEffect splash = ParticleEffect(
    count: 16,
    emitter: const ConeEmitter(
      speed: Range(1.2, 2.8),
      halfAngle: 40.0 * math.pi / 180.0,
    ),
    lifetime: const Range(0.3, 0.6),
    size: const Range(0.025, 0.055),
    color: Vector4(0.32, 0.34, 0.33, 1.0),
    affectors: <ParticleAffector>[
      const ParticleGravity(),
      const ParticleFade(startsAt: 0.4),
    ],
  );

  final math.Random _pitch = math.Random(17);

  // ----------------------------------------------------------------- frame

  /// One frame, [dt] seconds on, seen from [eye]: the wood where the run's
  /// world has it, the splinters of the rounds that struck it, the
  /// splashes of the [player] (the middle of their body) and the living
  /// [monsters] wading, and the fires and the water drawn and heard as the
  /// steps since the last frame left them.
  void update(
    double dt, {
    required Vector3 eye,
    required Vector3 player,
    required Iterable<Actor> monsters,
  }) {
    final crypt = _crypt;
    if (crypt == null) return;
    _seconds += dt;
    _drawWood(crypt);
    for (final (point, normal) in crypt.takeStruck()) {
      particles.burst(splinters, point, direction: normal);
    }
    wading.clear();
    _splashes(crypt, 1, player, dt);
    for (final actor in monsters) {
      final at = actor.position;
      if (at == null || !actor.isAlive) continue;
      _splashes(crypt, 2 + actor.ordinal, at, dt);
    }
    elements.update(dt, eye: eye, events: crypt.takeHeard());
    _vault?.update(
      dt,
      seconds: _seconds,
      eye: eye,
      flames: <Vector3>[
        for (final t in crypt.torches)
          if (t.fixture.enabled) t.at,
      ],
    );
  }

  /// A splash for each stride a walker known by [key] takes through water,
  /// and one for stepping in.
  void _splashes(CryptWorld crypt, int key, Vector3 at, double dt) {
    final w = _walkers[key] ??= _Wading(at.clone());
    final moved = math.sqrt(
      (at.x - w.at.x) * (at.x - w.at.x) + (at.z - w.at.z) * (at.z - w.at.z),
    );
    w.at.setFrom(at);
    final here = crypt.waterAt(at.x, at.z);
    final wet = here != null && here.depth > 0.05;
    if (!wet) {
      w.wet = false;
      return;
    }
    final speed = moved / math.max(dt, 1e-3);
    w.stride += moved;
    final entering = !w.wet && speed > 0.4;
    w.wet = true;
    if (!entering && w.stride <= 0.8) return;
    w.stride = 0.0;
    final feet = Vector3(at.x, here.surface, at.z);
    final loudness = (entering ? 0.9 : speed / 5.0).clamp(0.25, 0.9);
    wading.add(
      Audible(
        key,
        feet,
        loudness * math.min(1.0, here.depth / 0.2),
        0.88 + 0.24 * _pitch.nextDouble(),
      ),
    );
    particles.burst(splash, feet, direction: Vector3(0.0, 1.0, 0.0));
  }

  void dispose() {
    _clear();
    elements.dispose();
  }
}
