/// The scene, as something a screen reader can walk: one accessibility node
/// per object, positioned where the camera actually projects it.
///
/// Quoted by `scene_semantics.md` and shown whole in the Source tab.
library;

import 'package:flutter/widgets.dart' show Size, SizedBox;
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class SceneSemanticsDemo extends ShowcaseDemo {
  late final MeshNode _leftWheel;
  late final MeshNode _rightWheel;

  @override
  Scene build(DemoContext context) {
    final material = Material(
      name: 'wheel',
      baseColor: Vector4(0.3, 0.3, 0.3, 1.0),
    );
    _leftWheel = MeshNode(
      DeviceMesh.upload(context.device, SphereShape(segments: 16).build()),
      material,
      name: 'left-wheel',
    )..setPosition(-0.6, 0, 0);
    _rightWheel = MeshNode(
      DeviceMesh.upload(context.device, SphereShape(segments: 16).build()),
      material,
      name: 'right-wheel',
    )..setPosition(0.6, 0, 0);
    return Scene()
      ..add(_leftWheel)
      ..add(_rightWheel)
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.4, -1.0, -0.3)),
      );
  }

  // #region announce
  List<SceneAnnouncement> _announcements() => <SceneAnnouncement>[
    SceneAnnouncement(id: 'left', label: 'left wheel', node: _leftWheel),
    SceneAnnouncement(id: 'right', label: 'right wheel', node: _rightWheel),
  ];
  // #endregion announce

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('the wheels were not drawn');
    }
    // #region project
    final camera = CameraNode()..setPosition(0, 0, 4);
    final objects = semanticObjectsFor(
      _announcements(),
      camera: camera,
      size: const Size(320, 180),
    );
    // #endregion project
    if (objects.length != 2) {
      throw StateError('both wheels should project to a semantic object');
    }
    final left = objects.firstWhere((SemanticObject o) => o.id == 'left');
    final right = objects.firstWhere((SemanticObject o) => o.id == 'right');
    if (!(left.bounds.center.dx < right.bounds.center.dx)) {
      throw StateError(
        'the left wheel should project to the left of the '
        'right one',
      );
    }

    // #region overlay
    // The widget that publishes the objects to the platform. It is not
    // pumped here, only built, since the claim above is about the numbers
    // it would be given.
    final overlay = SceneSemantics(
      objects: objects,
      child: const SizedBox.shrink(),
    );
    // #endregion overlay
    if (overlay.objects.length != 2 || !overlay.enabled) {
      throw StateError(
        'the overlay should carry both objects, enabled by '
        'default',
      );
    }
  }
}
