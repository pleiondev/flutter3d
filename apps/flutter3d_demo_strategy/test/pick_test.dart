/// Pointing at things by pixel, which this genre is the first here to do.
///
///     flutter test test/pick_test.dart
///
/// **Why this is a test of the game rather than of the engine.** The picking
/// pass has its own tests in `flutter3d` and `flutter3d_cpu`, and a conformance
/// check that all three backends answer alike. What none of them says is that
/// a *game* can use it: that the scene a game assembles has meshes with names
/// worth reading, that the answer comes back as the node the game is holding
/// rather than a copy of it, and that the thing under the cursor is the thing
/// the cursor is over rather than the box around it.
///
/// The demo asks this on hover to light the hall under the pointer. Everything
/// here goes through `stage`, so it is the game's own scene being pointed at.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_demo_strategy/src/staging.dart';
import 'package:flutter3d_game_strategy/flutter3d_game_strategy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

const int _width = 120;
const int _height = 90;

void main() {
  test('the pass answers with the hall the cursor is over', () async {
    final it = cpuTestDevice(width: _width, height: _height);
    final renderer = Renderer.create(device: it.device);
    final staged = stage(device: it.device, workers: 8);

    final scene = Scene(name: 'map');
    staged.visuals
      ..addTo(scene)
      // Before anything is drawn: a building becomes a node on the first sync
      // that finds its ground uncovered, and a pass over a scene without it
      // would be a pass that could only ever answer "ground".
      ..sync();
    scene.add(
      LightNode(
        type: LightType.directional,
        color: vm.Vector3(1.0, 0.96, 0.88),
        intensity: 3.2,
        name: 'sun',
      )..lookAt(vm.Vector3(0.35, -1.0, 0.5)),
    );

    // Straight down the middle at this side's own hall, rather than through the
    // map camera: what is being tested is the answer, not the aim, and a view
    // that has the target in the middle of it makes the question "what is at
    // the middle" a question with a known answer.
    final Building hall = staged.simulation.buildings.first;
    final camera = scene.add(CameraNode(name: 'camera'));
    camera
      ..setPosition(hall.centre.x, hall.centre.y + 30.0, hall.centre.z + 22.0)
      ..lookAt(vm.Vector3(hall.centre.x, hall.centre.y + 1.5, hall.centre.z));
    final views = <RenderView>[RenderView(camera: camera)];

    // Two questions of one frame, which is what the pass is built to take: the
    // middle, where the hall is, and a corner, where it is not. One alone would
    // not say much — a pass that answered "hall" everywhere would pass the
    // first and fail the second.
    final Future<MeshNode?> middle = renderer.pickPixel(0.5, 0.5);
    final Future<MeshNode?> corner = renderer.pickPixel(0.02, 0.02);
    renderer.render(
      width: _width,
      height: _height,
      scene: scene,
      views: views,
      settings: const RenderSettings(),
    );

    final MeshNode? hit = await middle;
    expect(hit, isNotNull, reason: 'the middle of the view was empty');
    expect(hit!.name, 'hall');
    expect(
      identical(hit, staged.visuals.buildings.first),
      isTrue,
      reason: 'the answer is not the node the game is holding',
    );

    final MeshNode? edge = await corner;
    expect(
      edge?.name,
      isNot('hall'),
      reason: 'a hall that fills the frame is not a silhouette',
    );
  });
}
