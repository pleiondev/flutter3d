/// Eleven primitives, four skins, one armature: what `instantiate` binds.
///
/// `apps/flutter3d_demo_platformer/assets/models/hero.glb` draws as a loose fan of triangles
/// in the game, and the accusation this file was written to test was that
/// [ModelAsset.instantiate] builds a *separate* [Skeleton] for every skinned
/// mesh node — eleven of them for four skins whose joint arrays are
/// byte-identical in the file — and that the joint list one of them binds is
/// not the joint list it should have. The counts are real: this file's four
/// skins name the same twenty-nine nodes, and eleven primitives across four
/// meshes reference them.
///
/// **The verdict is that the binding is right**, and the tests below are what
/// says so rather than a reading of the code. They are kept because the
/// accusation was reasonable, because nothing else in the suite loads a model
/// with more than one skin, and because the obvious "optimisation" — one
/// skeleton per skin instead of one per mesh, cached on the asset — would break
/// two copies of a character posing independently, which is the whole reason
/// the asset/instance split exists. `two copies pose independently` below is
/// what refuses it.
///
/// **Where the bug is not.** The last test here skins every vertex with the
/// matrices the engine produces and finds them on the model, and the software
/// backend in `flutter3d_cpu` — a third implementation of `GraphicsDevice`
/// sharing no code with Impeller — draws this file as a legible character,
/// posed clip and all. So the decode, the hierarchy, the skin binding and the
/// skinning arithmetic are all right, and whatever draws a fan lives below the
/// device seam or in the shader bundle, not here.
///
/// The file is reached across the repository rather than copied into
/// `assets/samples`, because the point of these tests is *this* asset, the one
/// the game ships and the one that draws wrong. A copy would drift.
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter3d/src/engine/assets/gltf/gltf.dart';
import 'package:flutter3d/src/engine/assets/model_asset.dart';
import 'package:flutter3d/src/engine/geometry/geometry.dart';
import 'package:flutter3d/src/engine/render/lighting_model.dart';
import 'package:flutter3d/src/engine/scene/scene_graph.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' hide Ray;


// A fixture rather than a game's asset. It used to live in the platformer's
// `assets/models/`, which is declared whole, so a rig the game stopped drawing
// went into every download — see `test/fixtures/README.md`.
const String kHero = 'test/fixtures/hero.glb';

/// The decoded file and one uploaded copy of it, on a device that draws
/// nothing.
///
/// Nothing here needs a GPU: the question is which nodes a skeleton names and
/// where the matrices it produces put a vertex, and both are arithmetic.
Future<({ModelDocument document, ModelAsset asset})> loadHero() async {
  final document = await GltfLoader().load(File(kHero).readAsBytesSync());
  final device = FakeBackend();
  final asset = await ModelAsset.fromDocument(
    document,
    device: device,
    lighting: LightingModel.unlit,
  );
  return (document: document, asset: asset);
}

/// The [MeshData] each instantiated mesh node was built from.
///
/// Rebuilt from the hierarchy rather than assumed from list order: the mesh
/// nodes come out of `instantiate` in whatever order its walk reached them, and
/// a test that quietly relies on that order is testing the walk instead of the
/// skinning.
Map<MeshNode, MeshData> sourcesOf(
  ModelDocument document,
  ModelAsset asset,
  ModelInstance instance,
) {
  final sources = <MeshNode, MeshData>{};
  for (var n = 0; n < asset.nodes.length; n++) {
    final surfaces = asset.nodes[n].surfaces;
    if (surfaces.isEmpty) continue;
    final drawn = instance.nodes[n].children.whereType<MeshNode>().toList();
    expect(drawn, hasLength(surfaces.length));
    for (var k = 0; k < surfaces.length; k++) {
      sources[drawn[k]] = document.surfaces[surfaces[k]].mesh;
    }
  }
  return sources;
}

void main() {
  group('hero.glb: four skins over one armature', () {
    test('every primitive that names a skin gets a skeleton', () async {
      final (:document, :asset) = await loadHero();

      // The premise, asserted rather than assumed. If a re-export changes any
      // of these three numbers, the tests below are about a different file and
      // should be read again rather than trusted.
      expect(document.skins, hasLength(4));
      final skinned =
          document.surfaces.where((s) => s.skinIndex != null).toList();
      expect(skinned, hasLength(11));
      final joints = document.skins.first.joints;
      expect(joints, hasLength(29));
      for (final skin in document.skins) {
        expect(skin.joints, orderedEquals(joints),
            reason: 'the four skins are the same armature');
      }

      final instance = asset.instantiate(Scene());

      // Eleven, one per drawn primitive — not four, one per skin. That is the
      // shape the accusation called wasteful, and it is: eleven skeletons hold
      // eleven 4 KB matrix blocks for one pose. It is also correct, and the
      // cheaper shape is what `two copies pose independently` refuses.
      expect(instance.skeletons, hasLength(11));
      expect(instance.meshes, hasLength(11));
      for (final mesh in instance.meshes) {
        expect(mesh.skeleton, isNotNull, reason: '${mesh.name} lost its rig');
      }
      // Mutation: in `instantiate`, add to `pendingSkins` only for a node's
      // first surface (`if (surfaceIndex == model.surfaces.first)`). Eleven
      // becomes four and seven mesh nodes come back with a null skeleton.
    });

    test('each skeleton names this instance\'s own nodes, in file order',
        () async {
      final (:document, :asset) = await loadHero();
      final instance = asset.instantiate(Scene());
      final joints = document.skins.first.joints;

      for (var s = 0; s < instance.skeletons.length; s++) {
        final skeleton = instance.skeletons[s];
        expect(skeleton.joints, hasLength(joints.length));
        for (var k = 0; k < joints.length; k++) {
          expect(
            identical(skeleton.joints[k], instance.nodes[joints[k]]),
            isTrue,
            reason: 'skeleton $s joint $k should be node ${joints[k]}, '
                'which this instance created as '
                '"${instance.nodes[joints[k]].name}", and instead holds '
                '"${skeleton.joints[k].name}"',
          );
        }
        expect(identical(skeleton.skeletonRoot, instance.nodes[2]), isTrue);
      }
      // Mutation: in `_buildSkeleton`, resolve every joint to the skin's first
      // one (`joints.add(created[skin.joints.first]!)`). Every skeleton then
      // holds twenty-nine copies of "Root" and joint 1 onwards fails.
    });

    test('every skinned mesh hangs from the node that names it', () async {
      // The parent is not decoration: `Skeleton.update` divides the mesh
      // node's world transform back out, and this file's armature nodes carry
      // a 48x scale. A mesh reparented to the instance root would be skinned
      // as if that scale were not there, which is the shape a "fan of
      // triangles" would take.
      final (:document, :asset) = await loadHero();
      final instance = asset.instantiate(Scene());

      expect(
        instance.meshes.map((m) => m.parent?.name).toSet(),
        <String>{'Body', 'Ears', 'Head', 'Arms'},
      );
      for (final mesh in instance.meshes) {
        expect(mesh.worldMatrix.storage,
            orderedEquals(mesh.parent!.worldMatrix.storage),
            reason: 'a skinned mesh sits at identity under its node');
      }
      // Mutation: in `instantiate`, `root.add(mesh)` in place of
      // `node.add(mesh)`. Every parent becomes the instance root and the set
      // collapses to one name.
    });

    test('two copies pose independently', () async {
      // The regression the eleven-skeletons shape pays for. Caching a skeleton
      // per skin on the asset would halve nothing worth halving and would make
      // every copy of the character strike the same pose.
      final (:document, :asset) = await loadHero();
      final scene = Scene();
      final first = asset.instantiate(scene, name: 'first');
      final second = asset.instantiate(scene, name: 'second');

      final theirs = <SceneNode>{
        for (final skeleton in second.skeletons) ...skeleton.joints,
      };
      for (final skeleton in first.skeletons) {
        for (final joint in skeleton.joints) {
          expect(theirs.contains(joint), isFalse,
              reason: 'the two copies share joint "${joint.name}"');
        }
      }

      // And the consequence, which is what anybody actually cares about:
      // turning one copy's hips leaves the other where it was.
      void pose(ModelInstance instance) {
        for (final mesh in instance.meshes) {
          mesh.skeleton!.update(mesh.worldMatrix);
        }
      }

      pose(first);
      pose(second);
      final rest = List<double>.of(second.skeletons.first.matrices);
      expect(first.skeletons.first.matrices, orderedEquals(rest),
          reason: 'two copies at rest hold the same pose');

      first.nodes[6].setRotationYawPitchRoll(math.pi / 3.0, 0.0, 0.0);
      pose(first);
      pose(second);
      expect(second.skeletons.first.matrices, orderedEquals(rest));
      expect(first.skeletons.first.matrices, isNot(orderedEquals(rest)));
      // Mutation: memoise in `instantiate` — hold the skeletons in a
      // `<int, Skeleton>{}` on the asset and return the cached one for a skin
      // index already seen. Both copies then move together and the second
      // expectation on `before` fails.
    });

    test('the posed model stays on the model', () async {
      // The fan detector, and the only test here that would notice if the
      // matrices were wrong rather than merely bound to the wrong list. It
      // does on the CPU what mesh_skinned.vert does on the GPU — normalize the
      // weights, blend the four named joint matrices, transform the position —
      // and then asks how far the result is from the origin the vertices were
      // authored around.
      //
      // A skinned vertex may move a long way relative to its own primitive; an
      // arm swings. What it may not do is leave the character. So the bound is
      // the model's own bind-pose radius with half again for slack: the rest
      // pose in this file is not the bind pose, and the arms and ears do move.
      // Measured at 0.95 of the bind radius today.
      //
      // Nothing softer would be worth writing. The failures this is for are
      // not near misses — dropping the `inverse(meshWorld)` term multiplies
      // every position by this file's 48x armature scale, and a scrambled
      // joint order throws limbs clear of the body.
      final (:document, :asset) = await loadHero();
      final instance = asset.instantiate(Scene());
      final sources = sourcesOf(document, asset, instance);

      var bindRadius = 0.0;
      var posedRadius = 0.0;
      final position = Vector3.zero();
      final blended = Matrix4.zero();

      for (final mesh in instance.meshes) {
        final skeleton = mesh.skeleton!..update(mesh.worldMatrix);
        final source = sources[mesh]!;
        final layout = source.layout;
        final stride = layout.floatsPerVertex;
        final p = layout.floatOffsetOf(VertexLayout.position.name);
        final j = layout.floatOffsetOf(VertexLayout.joints.name);
        final w = layout.floatOffsetOf(VertexLayout.weights.name);

        for (var v = 0; v < source.vertexCount; v++) {
          final base = v * stride;
          position.setValues(
            source.vertices[base + p],
            source.vertices[base + p + 1],
            source.vertices[base + p + 2],
          );
          bindRadius = math.max(bindRadius, position.length);

          var total = 0.0;
          for (var c = 0; c < 4; c++) {
            total += source.vertices[base + w + c];
          }
          blended.setZero();
          for (var c = 0; c < 4; c++) {
            final weight =
                total > 1e-5 ? source.vertices[base + w + c] / total : 0.0;
            final slot = source.vertices[base + j + c].toInt() * 16;
            for (var e = 0; e < 16; e++) {
              blended.storage[e] += skeleton.matrices[slot + e] * weight;
            }
          }
          posedRadius =
              math.max(posedRadius, blended.transformed3(position).length);
        }
      }

      expect(bindRadius, greaterThan(0.0));
      expect(posedRadius, lessThan(bindRadius * 1.5),
          reason: 'posed to $posedRadius from a bind radius of $bindRadius');
      // Mutation: drop `_scratch.invert()` from `Skeleton.update`. The posed
      // radius goes from 0.95 of the bind radius to 2184 times it — this
      // file's 48x armature scale, applied twice — which is exactly the shape
      // the bug on screen looks like.
      //
      // Reparenting a mesh to the instance root does make this file red, but
      // **not here and not for this reason**: the run dies earlier, inside
      // `sourcesOf`, which finds no drawn surfaces under the node at all. Said
      // plainly because a comment naming the wrong detector sends the next
      // reader to the wrong place.
    });
  });
}
