/// What a material carries, and what carries it: the two places that lose it.
///
///     flutter test test/material_state_test.dart
///
/// Both halves of this file are about a field arriving somewhere it should and
/// nowhere else, and both were written after the fact. `Material` grew depth
/// state so that a backdrop could be drawn behind everything; the field was
/// dropped on the floor by the model loader's hand-written copy, and the sort
/// bucket that a backdrop needs turned out never to have worked in the
/// direction it was documented for.
library;

import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' as engine show Material;
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// A material with nothing left at its default, so that a copy which drops a
/// field drops something visible.
engine.Material _distinctive() => engine.Material(
  name: 'distinctive',
  lighting: LightingModel.blinnPhong,
  baseColor: Vector4(0.1, 0.2, 0.3, 0.4),
  metallic: 0.25,
  roughness: 0.75,
  normalScale: 2.0,
  occlusionStrength: 0.5,
  emissive: Vector3(0.6, 0.7, 0.8),
  emissiveStrength: 3.0,
  alphaMode: MaterialAlphaMode.mask,
  alphaCutoff: 0.25,
  doubleSided: true,
  drawBucket: -7,
  depthWrite: false,
  depthCompare: CompareFunction.always,
);

/// A scene of unlit boxes, one per bucket, all in front of the camera.
({Scene scene, CameraNode camera}) _buckets(List<int> buckets) {
  final scene = Scene();
  final geometry = CpuMesh(CuboidShape(size: Vector3(1.0, 1.0, 1.0)).build());
  for (var i = 0; i < buckets.length; i++) {
    scene.add(
      MeshNode(
          geometry,
          engine.Material(
            name: 'bucket-${buckets[i]}',
            lighting: LightingModel.unlit,
            drawBucket: buckets[i],
          ),
          name: 'bucket-${buckets[i]}',
        )
        // Spread along the view axis so that a depth term, if it ever
        // outranked the bucket, would order them differently from the bucket.
        ..setPosition(0.0, 0.0, 10.0 + i * 5.0),
    );
  }
  final camera = scene.add(CameraNode())..lookAt(Vector3(0.0, 0.0, 1.0));
  return (scene: scene, camera: camera);
}

List<String> _drawOrder(List<int> buckets) {
  final world = _buckets(buckets);
  final view = RenderView(camera: world.camera);
  // Two calls, as the renderer makes them: `build` gathers what is visible and
  // `sort` puts it in order. A test that only builds reads submission order and
  // proves nothing about the key.
  final list = RenderList()
    ..build(
      world.scene,
      view,
      viewMatrix: world.camera.viewMatrix,
      frustum: Frustum.matrix(world.camera.viewProjection(1.0)),
    )
    ..sort(view);
  return <String>[
    for (final index in list.opaque) list.itemAt(index).material.name ?? '?',
  ];
}

void main() {
  group('a copied material', () {
    test('keeps every field it was given', () {
      // Mutation: drop any line from `Material.copy`. The dropped field comes
      // back as its default, which for `depthCompare` means a backdrop starts
      // testing depth again — an instantiated model behaving differently from
      // the asset it was built from, in one game, on one asset.
      //
      // This list has to grow with the class. That is the reason `copy` was
      // moved out of `ModelAsset` and onto `Material`: a copy that lives beside
      // the fields is a copy the next field gets added next to.
      final source = _distinctive();
      final copy = source.copy();

      expect(copy.name, source.name);
      expect(copy.lighting, source.lighting);
      expect(copy.baseColor, source.baseColor);
      expect(copy.metallic, source.metallic);
      expect(copy.roughness, source.roughness);
      expect(copy.normalScale, source.normalScale);
      expect(copy.occlusionStrength, source.occlusionStrength);
      expect(copy.emissive, source.emissive);
      expect(copy.emissiveStrength, source.emissiveStrength);
      expect(copy.alphaMode, source.alphaMode);
      expect(copy.alphaCutoff, source.alphaCutoff);
      expect(copy.doubleSided, source.doubleSided);
      expect(copy.drawBucket, source.drawBucket);
      expect(copy.depthWrite, source.depthWrite);
      expect(copy.depthCompare, source.depthCompare);
    });

    test('is a different object, with its own vectors', () {
      // The point of copying at all: two instances of one model must not share
      // a tint. Mutation: return `source` itself.
      final source = _distinctive();
      final copy = source.copy();

      copy.baseColor.setValues(1.0, 1.0, 1.0, 1.0);
      copy.emissive.setValues(1.0, 1.0, 1.0);

      // Loose, because `Vector4` is single precision and 0.1 is not one of the
      // numbers it holds exactly.
      expect(source.baseColor.x, closeTo(0.1, 1e-6));
      expect(source.emissive.x, closeTo(0.6, 1e-6));
    });
  });

  group('the draw bucket', () {
    test('orders draws, low first', () {
      expect(_drawOrder(<int>[2, 0, 1]), <String>[
        'bucket-0',
        'bucket-1',
        'bucket-2',
      ]);
    });

    test('a negative bucket is drawn before everything', () {
      // Mutation: mask the bucket with `& 0xFF` instead of biasing it, which is
      // what this did until a sky asked to go first. −1 became 255 and the
      // thing meant to be behind the world was drawn in front of it, silently
      // and last. Ordinary materials sit at zero, so negative is the *only* way
      // to say "before the scene" — the direction the field is documented for
      // and the one it did not have.
      expect(_drawOrder(<int>[0, -1]), <String>['bucket--1', 'bucket-0']);
      expect(_drawOrder(<int>[5, -128, 0]), <String>[
        'bucket--128',
        'bucket-0',
        'bucket-5',
      ]);
    });

    test('a bucket beyond the range clamps rather than wrapping', () {
      // Mutation: keep the mask. 256 wraps to 0 and an overlay asked to be
      // drawn last lands in the middle of the scene.
      expect(_drawOrder(<int>[300, 0]), <String>['bucket-0', 'bucket-300']);
      expect(_drawOrder(<int>[-500, 0]), <String>['bucket--500', 'bucket-0']);
    });
  });
}
