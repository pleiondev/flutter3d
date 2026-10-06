/// A level's decals, mirrors and camera screens, built into the scene the
/// game and the editor both draw.
library;

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

Level _pool() => Level.fromJson(<String, Object?>{
  'version': 1,
  'materials': <String, Object?>{
    'stone': <String, Object?>{
      'baseColor': <double>[0.6, 0.6, 0.6, 1.0],
    },
    'water': <String, Object?>{
      'baseColor': <double>[0.1, 0.2, 0.2, 1.0],
    },
    'glass': <String, Object?>{
      'baseColor': <double>[0.2, 0.2, 0.2, 1.0],
    },
  },
  'brushes': <Object?>[
    <String, Object?>{
      'material': 'stone',
      'at': <double>[0.0, -0.5, 0.0],
      'size': <double>[10.0, 1.0, 10.0],
    },
    <String, Object?>{
      'material': 'water',
      'at': <double>[0.0, 0.05, 0.0],
      'size': <double>[4.0, 0.1, 4.0],
      'solid': false,
    },
    <String, Object?>{
      'material': 'glass',
      'at': <double>[4.0, 1.0, 0.0],
      'size': <double>[0.1, 1.0, 1.6],
    },
  ],
  'entities': <Object?>[
    <String, Object?>{
      'type': 'decal',
      'name': 'stain',
      'at': <double>[-3.0, 0.0, 2.0],
      'yaw': 0.5,
      'material': 'water',
      'size': <double>[2.0, 0.5, 1.0],
      'pitch': 90.0,
      'order': 2,
    },
    <String, Object?>{
      'type': 'reflector',
      'at': <double>[0.0, 0.1, 0.0],
      'material': 'water',
      'reflectance': 0.4,
    },
    <String, Object?>{
      'type': 'camera_screen',
      'at': <double>[0.0, 3.0, 4.0],
      'look': <double>[0.0, 0.0, 0.0],
      'material': 'glass',
      'width': 64,
      'height': 32,
    },
  ],
});

void main() {
  final device = CpuDevice(
    width: 4,
    height: 4,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );

  test('each entity is its node, where and as the document says', () {
    final parts = const LevelScene().build(_pool(), device: device);

    final decal = parts.decals.single;
    expect(decal.name, 'stain');
    expect(decal.order, 2);
    // The material's colour, and the box the document gave it, stood on a
    // wall: tipped ninety degrees, so its stamp runs along the world's z.
    // Mutation: the pitch left as degrees, or not applied.
    expect(decal.color.xyz, _colour(0.1, 0.2, 0.2));
    final up =
        decal.worldMatrix.transform3(Vector3(0.0, 1.0, 0.0)) -
        decal.worldMatrix.getTranslation();
    expect(up.y.abs(), lessThan(1e-6));
    expect(up.length, closeTo(0.5, 1e-6));
    expect(decal.worldMatrix.getTranslation(), _near(Vector3(-3.0, 0.0, 2.0)));

    // The mirror: on the water's batch and only on it.
    final mirror = parts.reflectors.single;
    expect(mirror.surfaces.map((MeshNode n) => n.material.name), <String>[
      'water',
    ]);
    expect(mirror.reflectance, 0.4);
    expect(mirror.worldMatrix.getTranslation(), _near(Vector3(0.0, 0.1, 0.0)));

    // The screen: drawn into the glass, which gives it off as light and is
    // left out of its own picture.
    final screen = parts.screens.single;
    expect((screen.width, screen.height), (64, 32));
    final glass = parts.batches
        .map((LevelBatch b) => b.node)
        .where((MeshNode n) => n.material.name == 'glass');
    expect(glass, isNotEmpty);
    for (final node in glass) {
      // Mutation: a screen that takes its picture and shows it nowhere.
      expect(node.material.emissiveTexture, same(screen.texture));
      expect(node.material.emissiveStrength, greaterThanOrEqualTo(1.0));
      expect(screen.excluded, contains(node));
    }
    expect(parts.scene.renderTextures, contains(screen));
  });

  test('a level with none of them adds nothing', () {
    final level = Level.fromJson(<String, Object?>{
      'version': 1,
      'brushes': <Object?>[
        <String, Object?>{
          'at': <double>[0.0, -0.5, 0.0],
          'size': <double>[4.0, 1.0, 4.0],
        },
      ],
    });
    final parts = const LevelScene().build(level, device: device);
    expect(parts.decals, isEmpty);
    expect(parts.reflectors, isEmpty);
    expect(parts.screens, isEmpty);
  });
}

Matcher _near(Vector3 expected) => predicate<Vector3>(
  (Vector3 at) => (at - expected).length < 1e-6,
  'within a micrometre of $expected',
);

Matcher _colour(double r, double g, double b) => predicate<Vector3>(
  (Vector3 c) =>
      (c.x - r).abs() < 1e-6 &&
      (c.y - g).abs() < 1e-6 &&
      (c.z - b).abs() < 1e-6,
  'the colour ($r, $g, $b)',
);
