/// A pointer track plays onto a material or a light, and crossfades.
///
///     dart test test/animation_pointer_player_test.dart
///
/// Mutation: drop the `_applyPointer` branch in `AnimationPlayer.apply` and
/// the material keeps its authored roughness; leave `pointer.index` out of
/// `animationTrackKey` and the crossfade blends material 0's roughness from
/// material 1's.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

AnimationTrack _track(AnimationPointer pointer, List<double> values) =>
    AnimationTrack(
      nodeIndex: -1,
      path: AnimationPath.pointer,
      interpolation: AnimationInterpolation.linear,
      times: Float32List.fromList(<double>[0.0, 1.0]),
      values: Float32List.fromList(values),
      componentCount: pointer.property.componentCount,
      pointer: pointer,
    );

final class _Node implements AnimationTarget {
  final Vector3 position = Vector3.zero();

  @override
  void setPosition(double x, double y, double z) => position.setValues(x, y, z);

  @override
  void setRotation(Quaternion value) {}

  @override
  void setScale(double x, double y, double z) {}
}

void main() {
  final roughness = AnimationPointer.of(AnimationPointerProperty.roughness, 0);

  test('a roughness track moves the material, sampled where it is', () {
    final material = Material(roughness: 0.5);
    final player = AnimationPlayer(
      clips: <AnimationClip>[
        AnimationClip(
          tracks: <AnimationTrack>[
            _track(roughness, <double>[0.0, 1.0]),
          ],
        ),
      ],
      targets: const <AnimationTarget?>[],
      pointers: PointerTargets(materials: <int, Material>{0: material}),
    )..play(0);

    expect(material.roughness, 0.0);
    player.seek(0.25);
    expect(material.roughness, closeTo(0.25, 1e-6));
  });

  test('a crossfade blends a pointer track with its own and no other', () {
    final material = Material();
    final other = Material();
    final node = _Node();
    final player = AnimationPlayer(
      clips: <AnimationClip>[
        AnimationClip(
          tracks: <AnimationTrack>[
            // Node 0's translation shares an index with material 0, and
            // material 1's roughness shares a property: neither is the track
            // material 0's roughness fades from.
            AnimationTrack(
              nodeIndex: 0,
              path: AnimationPath.translation,
              interpolation: AnimationInterpolation.step,
              times: Float32List.fromList(<double>[0.0]),
              values: Float32List.fromList(<double>[9.0, 9.0, 9.0]),
              componentCount: 3,
            ),
            _track(roughness, <double>[0.2, 0.2]),
            _track(
              AnimationPointer.of(AnimationPointerProperty.roughness, 1),
              <double>[0.9, 0.9],
            ),
          ],
        ),
        AnimationClip(
          tracks: <AnimationTrack>[
            _track(roughness, <double>[0.8, 0.8]),
          ],
        ),
      ],
      targets: <AnimationTarget?>[node],
      pointers: PointerTargets(
        materials: <int, Material>{0: material, 1: other},
      ),
    )..play(0);
    expect(material.roughness, closeTo(0.2, 1e-6));
    expect(other.roughness, closeTo(0.9, 1e-6));
    expect(node.position.x, 9.0);

    player
      ..crossFadeTo(1, duration: 1.0)
      ..update(0.5);
    expect(material.roughness, closeTo(0.5, 1e-6));
  });

  test('base colour arrives linear and is kept as the authored tint', () {
    final material = Material();
    PointerTargets(materials: <int, Material>{2: material}).setPointer(
      AnimationPointer.of(AnimationPointerProperty.baseColor, 2),
      <double>[0.2140, 0.0, 1.0, 0.5],
    );
    expect(material.baseColor.x, closeTo(0.5, 1e-3));
    expect(material.baseColor.y, 0.0);
    expect(material.baseColor.z, closeTo(1.0, 1e-6));
    expect(material.baseColor.w, 0.5);
  });

  test('a light track reaches the light bound to its index', () {
    final light = LightNode(type: LightType.point);
    final targets = PointerTargets(lights: <int, LightNode>{1: light})
      ..setPointer(
        AnimationPointer.of(AnimationPointerProperty.lightIntensity, 1),
        <double>[Photometric.referenceIlluminance * 3.0],
      )
      ..setPointer(
        AnimationPointer.of(AnimationPointerProperty.lightColor, 1),
        <double>[1.0, 0.5, 0.25],
      )
      // No light 0: ignored rather than thrown.
      ..setPointer(
        AnimationPointer.of(AnimationPointerProperty.lightIntensity, 0),
        <double>[1.0],
      );
    expect(targets.lights, hasLength(1));
    expect(light.intensity, closeTo(3.0, 1e-9));
    expect(light.color, Vector3(1.0, 0.5, 0.25));
  });
}
