/// Turning a joint's name into the set of joints under it.
///
/// **The walk lives on the document because the hierarchy does.**
/// `AnimationTarget` is three setters and no parents, so a player cannot work
/// out what hangs off a spine and is handed the answer instead — see
/// `AnimationMask`. `ModelDocument.nodes` is the tree, and the indices it walks
/// are the ones an animation channel addresses, so nothing is translated on the
/// way in and there is no second numbering to get wrong.
library;

import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:flutter_test/flutter_test.dart';

/// A skeleton, as a document and nothing else.
///
///     0 root
///     ├── 1 hips
///     │   ├── 2 legL
///     │   └── 3 legR
///     └── 4 spine
///         ├── 5 armL
///         └── 6 armR
final class _Rig extends ModelDocument {
  const _Rig({this.cyclic = false});

  /// Whether node 6 claims node 4 as a child, which is a document a decoder
  /// should never produce and one this must not hang on.
  final bool cyclic;

  @override
  List<ModelSurface> get surfaces => const <ModelSurface>[];

  @override
  List<SurfaceMaterial> get materials => const <SurfaceMaterial>[];

  @override
  List<EncodedImage> get images => const <EncodedImage>[];

  @override
  List<String> get warnings => const <String>[];

  @override
  List<ModelNode> get nodes => <ModelNode>[
    ModelNode(name: 'root', children: <int>[1, 4]),
    ModelNode(name: 'hips', children: <int>[2, 3]),
    ModelNode(name: 'legL'),
    ModelNode(name: 'legR'),
    ModelNode(name: 'spine', children: <int>[5, 6]),
    ModelNode(name: 'armL'),
    ModelNode(name: 'armR', children: cyclic ? <int>[4] : <int>[]),
  ];
}

void main() {
  group('a mask under a joint', () {
    test('holds that joint and everything hanging off it', () {
      const rig = _Rig();
      final upper = rig.maskUnder('spine');

      expect(upper.covers(4), isTrue, reason: 'the spine itself');
      expect(upper.covers(5), isTrue, reason: 'armL');
      expect(upper.covers(6), isTrue, reason: 'armR');
      expect(upper.length, 3);
    });

    test('and nothing on another branch', () {
      // The assertion the feature is for: an upper-body layer must not reach
      // the legs, or a soldier reloading stops walking.
      const rig = _Rig();
      final upper = rig.maskUnder('spine');

      expect(upper.covers(1), isFalse, reason: 'hips');
      expect(upper.covers(2), isFalse, reason: 'legL');
      expect(upper.covers(3), isFalse, reason: 'legR');
      expect(upper.covers(0), isFalse, reason: 'the root above it');
    });

    test('under the root is the whole skeleton', () {
      const rig = _Rig();
      expect(rig.maskUnder('root').length, 7);
    });

    test('under a leaf is the leaf alone', () {
      const rig = _Rig();
      final one = rig.maskUnder('armL');
      expect(one.length, 1);
      expect(one.covers(5), isTrue);
    });
  });

  group('a mask nobody can build', () {
    test('a name the rig does not carry is empty, not everything', () {
      // The safe direction, and it is a choice rather than an accident: a layer
      // over an empty mask writes nothing, so a misspelt joint is a layer that
      // does nothing rather than one that takes over the skeleton. Returning
      // `AnimationMask.everything` here would have been the same call spelt the
      // same way with the opposite meaning.
      const rig = _Rig();
      final missing = rig.maskUnder('tail');

      expect(missing.isEmpty, isTrue);
      expect(missing.covers(0), isFalse);
    });

    test('an index off the end is empty as well', () {
      const rig = _Rig();
      expect(rig.maskUnderIndex(99).isEmpty, isTrue);
      expect(rig.maskUnderIndex(-1).isEmpty, isTrue);
    });

    test('a rig whose children point back up does not hang', () {
      // A decoder is exactly where a cycle arrives from, and a recursive walk
      // would follow this one for ever. Mutation: drop the seen set from
      // `maskUnderIndex` and this test never returns.
      const rig = _Rig(cyclic: true);
      final upper = rig.maskUnder('spine');

      expect(upper.length, 3, reason: 'spine, armL, armR, each once');
    });
  });
}
