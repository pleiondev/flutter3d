/// `gfx-65n`: reading a world transform does not walk to the root.
///
///     flutter test test/world_transform_cache_test.dart
///
/// **What it cost.** `SceneNode.worldMatrix` walked its ancestors on every
/// read with no early-out, and the inverse world matrix, the world bounds and
/// the normal matrix all route through it, so every drawable paid a full walk
/// per pass — and `visibleInHierarchy`, read from seventeen call sites, walked
/// again. A comparison that priced the write side called this a win; a frame is
/// made of reads.
///
/// **The mechanism, and its limit.** `SceneNode.changeEpoch` advances when
/// something is touched and never when a matrix is merely recomputed, so a node
/// that verified itself at the current epoch has an ancestor chain nobody has
/// touched since. What it cannot do is tell one subtree's change from
/// another's: move one node and every node in the scene walks once more. That
/// is the right way round, because the walk is per read and the change is per
/// move — which is what the last test here holds to.
library;

import 'package:flutter3d_core/src/engine/scene/scene_graph.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// A chain of [depth] nodes, each a child of the last, each offset by one.
({Scene scene, SceneNode leaf, List<SceneNode> chain}) _chain(int depth) {
  final scene = Scene();
  final chain = <SceneNode>[];
  SceneNode? previous;
  for (var i = 0; i < depth; i++) {
    final node = SceneNode(name: 'link $i')..setPosition(1.0, 0.0, 0.0);
    if (previous == null) {
      scene.add(node);
    } else {
      previous.add(node);
    }
    chain.add(node);
    previous = node;
  }
  return (scene: scene, leaf: chain.last, chain: chain);
}

/// How many ancestor walks [body] costs.
int walksIn(void Function() body) {
  final before = SceneNode.ancestorWalks;
  body();
  return SceneNode.ancestorWalks - before;
}

void main() {
  test('a second read of an unmoved node touches no ancestor', () async {
    // **The row's own acceptance.** The first read resolves the chain; the
    // second is one integer comparison.
    final built = _chain(8);

    walksIn(() => built.leaf.worldMatrix);
    expect(walksIn(() => built.leaf.worldMatrix), 0);
    expect(walksIn(() => built.leaf.worldMatrix), 0);
  });

  test('and the matrix it hands back is still the right one', () async {
    // The claim that makes the early-out safe, and the one a cache keyed on
    // nothing would fail: eight links of one unit each put the leaf at eight.
    final built = _chain(8);

    final position = built.leaf.readWorldPosition();
    expect(position.x, closeTo(8.0, 1e-6));

    built.chain.first.setPosition(0.0, 5.0, 0.0);
    final moved = built.leaf.readWorldPosition();
    expect(moved.x, closeTo(7.0, 1e-6));
    expect(moved.y, closeTo(5.0, 1e-6));
  });

  test('a node whose ancestor moved reads the move', () async {
    // Moving anything advances the epoch, so the next read walks and finds it.
    // A cache that held past this is the one bug this file exists to catch, and
    // it would be invisible in every picture except the one with the moved node
    // in it.
    final built = _chain(8);

    built.leaf.worldMatrix;
    expect(walksIn(() => built.leaf.worldMatrix), 0);

    built.chain[3].translate(0.0, 2.0, 0.0);
    expect(
      walksIn(() => built.leaf.worldMatrix),
      greaterThan(0),
      reason: 'the read after a move did not look',
    );
    expect(built.leaf.readWorldPosition().y, closeTo(2.0, 1e-6));
  });

  test('visibility in the hierarchy is cached the same way', () async {
    // The second walk, and the one read from seventeen places. Hiding a branch
    // has to reach everything under it, which is what the epoch does without
    // anybody walking down.
    final built = _chain(8);

    expect(built.leaf.visibleInHierarchy, isTrue);
    built.chain[2].visible = false;
    expect(built.leaf.visibleInHierarchy, isFalse);
    built.chain[2].visible = true;
    expect(built.leaf.visibleInHierarchy, isTrue);
  });

  test('setting a flag to what it already was changes nothing', () async {
    // `LodGroup` writes every level's visibility every frame to pick one, so
    // the write that changes nothing is the common one. Guarded because on a
    // bool the comparison is free; the transform setters are not guarded, and
    // their own doc says why.
    final built = _chain(8);

    built.leaf.worldMatrix;
    // ignore: no_self_assignments — the point of the test is the self-write.
    built.chain[2].visible = built.chain[2].visible;
    expect(walksIn(() => built.leaf.worldMatrix), 0);
  });

  test('one move costs every node one walk, and only one', () async {
    // **The limit, stated as a measurement rather than as a caveat.** The epoch
    // is global, so a move anywhere makes every node walk once more — and then
    // stop. A frame that reads a hundred nodes twice pays a hundred walks, not
    // two hundred, and not one per read for ever.
    final wide = Scene();
    final root = wide.add(SceneNode(name: 'root'));
    final nodes = <SceneNode>[
      for (var i = 0; i < 100; i++)
        SceneNode(name: 'leaf $i')..setPosition(i.toDouble(), 0.0, 0.0),
    ];
    for (final node in nodes) {
      root.add(node);
    }

    void readAll() {
      for (final node in nodes) {
        node.worldMatrix;
      }
    }

    readAll();
    expect(walksIn(readAll), 0);

    root.translate(0.0, 1.0, 0.0);
    // A hundred leaves, the node they hang from, and the scene's own root above
    // that — a `Scene` is a node too, and the first read of a leaf resolves the
    // whole chain above it.
    expect(walksIn(readAll), 102);
    expect(walksIn(readAll), 0);
  });

  test('a scene that nobody touched draws the same picture twice', () async {
    // The parity half of the acceptance, in the cheapest form that means
    // anything here: the world matrices a second pass reads are the ones the
    // first pass computed, to the bit.
    final built = _chain(6);
    final first = Matrix4.copy(built.leaf.worldMatrix);
    for (final node in built.chain) {
      node.worldMatrix;
    }
    expect(built.leaf.worldMatrix, first);
  });
}
