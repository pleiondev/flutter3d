/// What a fixture looks like, and the four questions the bridge asks the game.
///
///     flutter test test/fixture_visuals_test.dart
///
/// **Four hundred and twenty-six lines with no test at all.** This package is
/// the only one allowed to see both halves of the engine, which makes it the
/// most expensive place in the repository for something to be quietly wrong —
/// and `fixture_visuals.dart` and `actor_visuals.dart` were reached by nothing
/// but the level loader's own file.
///
/// What is checked here is the seam rather than the picture: `sync` reads the
/// simulation and writes to scene nodes, and every branch of it is a question
/// put to [FixtureAppearance]. A game answers those four questions; getting one
/// of them wrong is a coin that is never visible, a checkpoint that never turns
/// green, or a torch whose flame burns while its light is out. All four have
/// happened in this repository, and §7.1 of `docs/SPEC.md` names three of them.
///
/// Nothing here renders. The picture is `apps/*/test/frame_test.dart`'s job;
/// this is about what those files would be drawing.
library;

import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' as engine show Material;
import 'package:flutter3d_bridge/flutter3d_bridge.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// An appearance whose every answer is a field, so a test can say what the game
/// says without inventing a game.
final class _Answers implements FixtureAppearance {
  bool spent = false;
  double scale = 1.0;
  bool spinning = false;

  /// Every fixture `refresh` was offered, in order. Empty is the interesting
  /// value: a fixture drawn from a loaded model is deliberately not offered.
  final List<Fixture> refreshed = <Fixture>[];

  /// The holders `buildLightFixture` was handed.
  final List<SceneNode> lit = <SceneNode>[];

  /// What to return from `buildLightFixture`, so both branches can be taken.
  TorchFire? fire;

  @override
  TorchFire? buildLightFixture(LightFixtureBuild build) {
    lit.add(build.holder);
    return fire;
  }

  @override
  LevelMaterial fallbackFor(Fixture fixture) =>
      LevelMaterial(baseColor: Vector4(0.5, 0.5, 0.5, 1.0));

  @override
  bool isSpent(Fixture fixture) => spent;

  @override
  double scaleOf(Fixture fixture) => scale;

  @override
  bool spins(Fixture fixture) => spinning;

  @override
  void refresh(Fixture fixture, engine.Material material) =>
      refreshed.add(fixture);
}

/// A level with one wall and one named light, which is what `bindLights` looks
/// for.
Level _level() => Level.fromJson(<String, Object?>{
      'version': 1,
      'materials': <String, Object?>{
        'wall': <String, Object?>{
          'color': <double>[0.8, 0.8, 0.8],
        },
      },
      'brushes': <Object?>[
        <String, Object?>{
          'material': 'wall',
          'at': <double>[0.0, 1.5, -1.5],
          'size': <double>[4.0, 3.0, 1.0],
        },
      ],
      'lights': <Object?>[
        <String, Object?>{
          'name': 'brazier',
          'type': 'point',
          'at': <double>[0.0, 2.0, 0.0],
          'color': <double>[1.0, 0.7, 0.3],
          'range': 8.0,
          'intensity': 4.0,
        },
      ],
    });

Fixture _fixture({
  String type = 'crate',
  Vector3? at,
  Mechanism? mechanism,
  Map<String, Object?> properties = const <String, Object?>{},
}) =>
    Fixture(
      entity: EntityDef(
        type: type,
        position: at ?? Vector3(1.0, 0.5, 0.0),
        properties: properties,
      ),
      size: Vector3(1.0, 1.0, 1.0),
      material: 'wall',
      at: at ?? Vector3(1.0, 0.5, 0.0),
      mechanism: mechanism,
    );

void main() {
  late CpuDevice device;
  late LoadedLevel loaded;

  setUp(() async {
    device = CpuDevice(
      width: 16,
      height: 16,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    );
    loaded = await const LevelLoader().build(
      _level(),
      device: device,
      registry: EntityRegistry(<EntityKind>[]),
    );
  });

  FixtureVisuals visuals(_Answers answers) => FixtureVisuals(
        loaded.scene,
        loaded,
        appearance: answers,
        device: device,
      );

  group('sync', () {
    test('hides a fixture the game calls spent', () {
      // The coin that was taken. `isSpent` is the game's word for "gone", and
      // the bridge must not learn what a pickup is to ask it.
      //
      // Mutation: return early from `sync` before the `isSpent` branch.
      final answers = _Answers();
      final it = visuals(answers)..add(_fixture());

      it.sync(0.0);
      expect(_only(loaded.scene, 'crate').visible, isTrue);

      answers.spent = true;
      it.sync(0.0);
      expect(_only(loaded.scene, 'crate').visible, isFalse);
    });

    test('and hides one whose scale has shrunk to nothing', () {
      // **Separate from spent, and the doc says why**: a fixture can be
      // invisible without being over. A coin shrinks on the way out, and the
      // shrink is what connects the sound to the thing that made it.
      //
      // Mutation: fold `scaleOf` into `isSpent`. A fixture mid-shrink then
      // vanishes on the frame it is taken.
      final answers = _Answers()..scale = 0.0;
      final it = visuals(answers)..add(_fixture());

      it.sync(0.0);
      expect(_only(loaded.scene, 'crate').visible, isFalse);

      answers.scale = 0.5;
      it.sync(0.0);
      final node = _only(loaded.scene, 'crate');
      expect(node.visible, isTrue);
      expect(_scaleOf(node), closeTo(0.5, 1e-9),
          reason: 'the node was shown at full size while the game shrank it');
    });

    test('and offers a fixture built from a shape its own material each frame',
        () {
      // **The checkpoint that stayed blue.** `fallbackFor` is asked once, when
      // the node is built, which is right for "what colour is a key" and wrong
      // for anything whose look depends on what has happened. Without this
      // call, the one thing a checkpoint exists to say it never says.
      //
      // Mutation: call `refresh` only when the node is created.
      final answers = _Answers();
      final it = visuals(answers)..add(_fixture());

      it.sync(0.0);
      it.sync(1.0);

      expect(answers.refreshed, hasLength(2),
          reason: 'the material was offered ${answers.refreshed.length} times '
              'across two frames');
    });

    test('and turns one the game says spins, and not one it does not', () {
      // Mutation: spin everything. A door rotating on the spot is a door
      // nobody can walk through.
      final answers = _Answers()..spinning = false;
      final it = visuals(answers)..add(_fixture());

      it.sync(1.0);
      final still = _forwardOf(_only(loaded.scene, 'crate'));

      answers.spinning = true;
      it.sync(1.0);
      expect(_forwardOf(_only(loaded.scene, 'crate')).x, isNot(closeTo(still.x, 1e-6)));
    });

    test('and follows the collider rather than a second copy of the travel',
        () {
      // A door stopped by somebody standing in it is drawn where it actually
      // stopped. The fixture's position is the simulation's; nothing here
      // recomputes it.
      //
      // Mutation: set the node from `fixture.entity.position`, which is where
      // the document said it started.
      final at = Vector3(1.0, 0.5, 0.0);
      final fixture = _fixture(at: at);
      final it = visuals(_Answers())..add(fixture);

      it.sync(0.0);
      expect(_positionOf(_only(loaded.scene, 'crate')).x, closeTo(1.0, 1e-9));

      fixture.position.setValues(4.0, 0.5, 0.0);
      it.sync(0.0);
      expect(_positionOf(_only(loaded.scene, 'crate')).x, closeTo(4.0, 1e-9),
          reason: 'the node stayed where the document put it');
    });
  });

  group('a light fixture', () {
    test('dims the level light it names, from the mechanism\'s brightness', () {
      // **The flame and the light move together, off one number.** Two
      // generators of the same value disagree eventually, and the disagreement
      // looks like a torch burning while its light is out.
      //
      // Mutation: leave `node.intensity` alone in `sync`. The brazier then
      // burns at full strength however far the fixture has guttered.
      final mechanism = LightFixture(light: 'brazier');
      final it = visuals(_Answers())
        ..bindLights()
        ..add(_fixture(type: 'torch', mechanism: mechanism));

      final brazier = _light(loaded.scene, 'brazier');
      final full = brazier.intensity;
      expect(full, greaterThan(0.0), reason: 'the level light has no strength');

      mechanism.measure(0.25);
      it.sync(0.0);
      expect(brazier.intensity, closeTo(full * 0.25, 1e-6));

      mechanism.measure(1.0);
      it.sync(0.0);
      expect(brazier.intensity, closeTo(full, 1e-6));
    });

    test('and puts the light where the fire actually is, once measured', () {
      // A flame is not a point and does not sit still. Null until something has
      // measured it, which is every fixture that is not a fire — so a lamp must
      // not be dragged to the origin by this.
      //
      // Mutation: call `setPositionFrom` unconditionally with `measuredAt ??
      // Vector3.zero()`.
      final mechanism = LightFixture(light: 'brazier');
      final it = visuals(_Answers())
        ..bindLights()
        ..add(_fixture(type: 'torch', mechanism: mechanism));

      final brazier = _light(loaded.scene, 'brazier');
      final authored = _positionOf(brazier);

      it.sync(0.0);
      expect(_positionOf(brazier), authored,
          reason: 'an unmeasured fixture moved the light it drives');

      mechanism.measure(1.0, at: Vector3(3.0, 2.0, 1.0));
      it.sync(0.0);
      expect(_positionOf(brazier).x, closeTo(3.0, 1e-9));
    });

    test('and a fixture naming no light dims nothing', () {
      // A purely decorative sconce. Mutation: drop the `name == null` guard and
      // this throws, or worse, dims a light chosen by whatever `_lights[null]`
      // returns.
      final mechanism = LightFixture(light: null);
      final it = visuals(_Answers())
        ..bindLights()
        ..add(_fixture(type: 'sconce', mechanism: mechanism));

      final brazier = _light(loaded.scene, 'brazier');
      final full = brazier.intensity;

      mechanism.measure(0.1);
      it.sync(0.0);

      expect(brazier.intensity, closeTo(full, 1e-9));
    });

    test('and the fire the game built is offered back for its particles', () {
      // The bridge does not make flames — it hands the game a holder and keeps
      // whatever comes back, so the particle system has somewhere to emit from.
      // Returning null is the other half: a window glows and does not burn.
      final answers = _Answers()..fire = TorchFire(SceneNode(), rise: 0.4);
      final lit = LightFixture(light: 'brazier');
      final unlit = LightFixture(light: null);

      final it = visuals(answers)
        ..bindLights()
        ..add(_fixture(type: 'torch', mechanism: lit));
      expect(it.flames.keys, <LightFixture>[lit]);

      answers.fire = null;
      it.add(_fixture(type: 'window', mechanism: unlit));
      expect(it.flames.keys, <LightFixture>[lit],
          reason: 'a fixture that glows without burning was given a flame');
    });
  });

  test('bindLights finds only the lights the level named', () {
    // Mutation: index by node rather than by name. A fixture then dims a light
    // chosen by scene order, which is stable within a run and meaningless.
    final it = visuals(_Answers())..bindLights();
    final mechanism = LightFixture(light: 'no such light');
    it.add(_fixture(type: 'torch', mechanism: mechanism));

    final brazier = _light(loaded.scene, 'brazier');
    final full = brazier.intensity;

    mechanism.measure(0.0);
    it.sync(0.0);

    expect(brazier.intensity, closeTo(full, 1e-9),
        reason: 'a fixture naming a light that does not exist dimmed one that '
            'does');
  });
}

/// The one node in [scene] with this name, and a failure if there is not
/// exactly one.
///
/// Walks the graph by hand because `Scene` offers `meshes` and `lights` and
/// nothing that covers a bare `SceneNode` — which is what a light fixture's
/// holder is.
SceneNode _only(Scene scene, String name) {
  final found = <SceneNode>[];
  void walk(SceneNode node) {
    if (node.name == name) found.add(node);
    for (final child in node.childrenView) {
      walk(child);
    }
  }

  walk(scene.root);
  expect(found, hasLength(1), reason: 'expected one node named "$name"');
  return found.single;
}

/// A node's world position, read off the matrix.
///
/// `SceneNode` keeps its transform private and exposes `worldMatrix`, which is
/// the honest thing to read: it is what the renderer uses.
Vector3 _positionOf(SceneNode node) {
  final m = node.worldMatrix;
  return Vector3(m.storage[12], m.storage[13], m.storage[14]);
}

/// A node's uniform scale, as the length of its first basis vector.
double _scaleOf(SceneNode node) {
  final m = node.worldMatrix.storage;
  return Vector3(m[0], m[1], m[2]).length;
}

/// Where a node's local −Z points, which is what turning on the spot changes.
Vector3 _forwardOf(SceneNode node) {
  final m = node.worldMatrix.storage;
  return Vector3(-m[8], -m[9], -m[10]).normalized();
}

LightNode _light(Scene scene, String name) {
  final found = <LightNode>[
    for (final node in scene.lights)
      if (node.name == name) node,
  ];
  expect(found, hasLength(1), reason: 'expected one light named "$name"');
  return found.single;
}
