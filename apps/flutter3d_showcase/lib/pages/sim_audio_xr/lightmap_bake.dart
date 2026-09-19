/// Unwrapping a level's brush faces onto an atlas, and baking the light the
/// walls throw on each other into it.
///
/// Quoted by `lightmap_bake.md` and shown whole in the Source tab.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

final class LightmapBakeDemo extends ShowcaseDemo {
  late final String _report;

  @override
  Scene build(DemoContext context) {
    _report = _run();
    final material = Material(
      name: 'closet',
      baseColor: Vector4(0.8, 0.8, 0.7, 1.0),
    );
    final node = MeshNode(
      DeviceMesh.upload(context.device, SphereShape(segments: 16).build()),
      material,
    );
    return Scene()
      ..add(node)
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.4, -1.0, -0.3)),
      );
  }

  static String _run() {
    // #region level
    final level = Level(
      name: 'closet',
      brushes: <Brush>[
        Brush(centre: Vector3(2, 0, 2), size: Vector3(4, 0.2, 4)),
        Brush(centre: Vector3(2, 2, 0), size: Vector3(4, 4, 0.2)),
      ],
      lights: <LevelLight>[
        LevelLight(position: Vector3(2, 3, 2), intensity: 6.0),
      ],
    );
    // #endregion level

    // #region layout
    final layout = LightmapLayout.plan(level, texelsPerMetre: 2.0);
    // #endregion layout

    // #region bake
    const baker = LightmapBaker(bounces: 1, samples: 8);
    final lightmap = baker.bake(level, layout: layout);
    final anyLight = lightmap.pixels.any((int byte) => byte > 0);
    // #endregion bake

    return '${layout.faces.length} faces packed into a '
        '${layout.width}x${layout.height} atlas\n'
        'the baked map is ${lightmap.width}x${lightmap.height}, '
        'and holds some light: $anyLight';
  }

  @override
  Widget? customBody(BuildContext buildContext, DemoContext context) =>
      Container(
        color: const Color(0xFF14161A),
        padding: const EdgeInsets.all(24),
        alignment: Alignment.topLeft,
        child: DefaultTextStyle(
          style: const TextStyle(color: Color(0xFFE8E8EC), fontSize: 16),
          child: Text(_report),
        ),
      );

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('the closet marker was not drawn');
    }
    if (!_report.contains('holds some light: true')) {
      throw StateError(
        'a room with a light in it should bake a lightmap '
        'that is not entirely black',
      );
    }
  }
}
