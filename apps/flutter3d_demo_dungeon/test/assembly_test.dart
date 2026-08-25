/// What `DungeonRun.open` draws that the simulation does not know about: the
/// torches bound to their lights, and the way out drawn rather than left an
/// invisible trigger.
///
///     flutter test test/assembly_test.dart
///
/// **Split out of `run_cubit_test.dart`.** That file is about the session —
/// starting, dying, moving on, quitting and coming back — and these three
/// tests are about none of that; they happen to use the same harness because
/// both need a level assembled the way the game assembles one. Grouped here
/// so the two concerns can be told apart at a glance.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart'; // RunSession, SettingsOverlay
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_demo_dungeon/src/run_cubit.dart';
import 'package:flutter3d_demo_dungeon/src/staging.dart';
import 'package:flutter3d_demo_dungeon/src/way_out_glow.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_shooter/sample.dart';
import 'package:flutter_test/flutter_test.dart';

const String _crypt = 'assets/levels/crypt.json';

/// Sixteen by nine, because nothing here looks at the picture.
///
/// The device exists so that `LevelLoader` has somewhere to upload the level's
/// textures to. What is being tested is the chain, and the chain runs at any
/// size — the platformer learned this the expensive way, with a frame test that
/// had produced no output after ten minutes at 320 by 180.
GraphicsDevice _device() => CpuDevice(
      width: 16,
      height: 9,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    );

/// A storage that keeps everything in a map.
final class _Storage implements Storage {
  final Map<String, String> documents = <String, String>{};

  @override
  String? read(String name) => documents[name];

  @override
  bool write(String name, String contents) {
    documents[name] = contents;
    return true;
  }

  @override
  void remove(String name) => documents.remove(name);
}

/// A cubit over the shipped documents, with a real device and no window.
({RunCubit run, _Storage storage}) _game({String first = _crypt}) {
  final device = _device();
  final storage = _Storage();
  return (
    storage: storage,
    run: RunCubit(DungeonRun(
      firstLevel: first,
      registry: sampleRegistry(),
      input: InputState(),
      inventory: startingInventory(),
      saves: SaveFile(appName: 'dungeon', storage: storage),
      // **The device, and nothing else.** Forty lines of the game's own
      // assembly used to sit here — the loader and both sets of visuals,
      // copied — and the copy had lost `bindLights()`, so every torch in this
      // harness lit nothing while the game's lit the room. That is what
      // `one_assembly_test` is named after, and this file was outside the two
      // calls it watched.
      device: device,
    )),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the assembly binds the level lights to the torches that drive them',
      () async {
    // **The line this file used to be missing.** Forty lines of the game's
    // assembly were copied here and the copy had lost `..bindLights()`, so
    // every torch in this harness lit nothing while the game's lit the room —
    // and nothing said so, because a crypt where the lights never move looks
    // exactly the same either way.
    //
    // That is also why this is not a picture. The crypt's torches are
    // `SteadyLight`: their brightness is one until something measures the fire,
    // which is the particle system in the running game and nothing at all in a
    // test. A frame drawn here is byte-identical with and without the binding
    // — measured — so a frame test cannot hold this and this test can.
    //
    // Mutation: drop `..bindLights()` from `DungeonRun.open`. The named light
    // stays at its authored intensity however far the torch has guttered.
    final it = _game();
    await it.run.begin();
    final level = (it.run.state as RunPlaying<LevelReady>).level;

    final torch = level.staged.mechanisms.all
        .whereType<LightFixture>()
        .firstWhere((LightFixture f) => f.light != null);
    final lamp = level.loaded.scene.lights
        .firstWhere((LightNode l) => l.name == torch.light);

    final authored = lamp.intensity;
    expect(authored, greaterThan(0.0), reason: 'the level light has no strength');

    torch.measure(0.25);
    level.fixtureVisuals.sync(0.0);

    expect(lamp.intensity, closeTo(authored * 0.25, 1e-4),
        reason: 'the torch guttered to a quarter and the light it names did '
            'not move — the assembly never bound them');
  });

  test('the way out is something you can see', () async {
    // **An exit was a trigger and nothing else**: `ExitKind` places a collider
    // and no geometry, so the end of every level was an invisible box in a
    // wall. The editor drew the arch and the game did not.
    //
    // Mutation: drop the `addExitsTo` call in `DungeonRun.open` — fails here,
    // and nowhere else: no frame test frames the doorway and no rule counts
    // nodes.
    final it = _game();
    await it.run.begin();

    final state = it.run.state as RunPlaying<LevelReady>;
    final exits = state.level.loaded.level.ofType(EntityTypes.exit).toList();
    expect(exits, hasLength(1), reason: 'the crypt has one way down');

    SceneNode? found;
    void look(SceneNode node) {
      if (node.name != null && node.name!.startsWith('exit-')) found = node;
      for (final child in node.children) {
        look(child);
      }
    }

    look(state.level.loaded.scene.root);
    expect(found, isNotNull, reason: 'nothing is drawn at the way out');
    // Where the entity says, unshifted: an exit is authored at the middle of
    // its opening rather than at the threshold, unlike a monster's feet.
    final where = found!.worldMatrix.getTranslation();
    expect(where.z, closeTo(exits.single.position.z, 1e-6));
    expect(where.y, closeTo(exits.single.position.y, 1e-6));
  });

  test('and it is bright enough to be found in the dark', () async {
    // **The arch was there and invisible.** Rendered in the crypt, and again
    // with the doorway hidden, the two frames differed in fifty-four pixels out
    // of a hundred and twenty thousand: iron at 0.17 in a corner no torch
    // reaches is the same black as the wall behind it.
    //
    // Mutation: drop the `_lightTheWayOut` call, or set `kWayOutGlow` back to
    // the 0.05 the generator writes — fails.
    final it = _game();
    await it.run.begin();

    final state = it.run.state as RunPlaying<LevelReady>;
    final glows = <double>[];
    void look(SceneNode node) {
      if (node is MeshNode) {
        final glow = node.material.emissive;
        final brightest = <double>[glow.x, glow.y, glow.z]
            .reduce((double a, double b) => a > b ? a : b);
        if (brightest > 0.0) glows.add(brightest);
      }
      for (final child in node.children) {
        look(child);
      }
    }

    SceneNode? door;
    void find(SceneNode node) {
      if (node.name != null && node.name!.startsWith('exit-')) door = node;
      for (final child in node.children) {
        find(child);
      }
    }

    find(state.level.loaded.scene.root);
    look(door!);
    expect(glows, isNotEmpty, reason: 'nothing in the doorway emits');
    expect(glows.reduce((double a, double b) => a > b ? a : b),
        closeTo(kWayOutGlow, 1e-6));
  });
}
