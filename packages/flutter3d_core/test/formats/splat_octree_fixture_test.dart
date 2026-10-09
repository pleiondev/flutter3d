/// A `.f3dsplat` tree written at version 1, read by this build.
///
///     dart test test/formats/splat_octree_fixture_test.dart
///
/// One node holding one splat, minted once under `test/fixtures/v1/` and never
/// re-minted (decision 8 of `tasks/1.0-stability.md`). A version that changes
/// a node or page record moves `splatOctreeVersion`, reads the older record
/// the older way, and mints its own fixture beside this one.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:test/test.dart';

Uint8List _fixture(int version) =>
    File('test/fixtures/v$version/one.f3dsplat').readAsBytesSync();

void main() {
  test('the version 1 tree reads its node and its page', () {
    final bytes = _fixture(1);
    final tree = parseSplatOctreeIndex(bytes);

    // Mutation: put back the exact-version gate, then bump the constant.
    expect(tree.nodes, hasLength(1));
    final node = tree.nodes.single;
    expect(node.isLeaf, isTrue);
    expect(node.splatCount, 1);
    final page = decodeSplatPage(
      Uint8List.sublistView(bytes, node.pageOffset),
      node.splatCount,
    );
    expect(page.centers, <double>[0.5, 1.0, 2.0]);
  });

  test('every version up to this build has a fixture', () {
    // Mutation: bump `splatOctreeVersion` with no new fixture minted.
    for (var v = 1; v <= splatOctreeVersion; v++) {
      expect(parseSplatOctreeIndex(_fixture(v)).nodes, isNotEmpty);
    }
  });

  test('a tree from a newer build is refused, saying to update', () {
    final bytes = Uint8List.fromList(_fixture(1));
    ByteData.sublistView(
      bytes,
    ).setUint32(4, splatOctreeVersion + 1, Endian.little);

    // Mutation: drop the upper bound and a newer node record is misread.
    expect(
      () => parseSplatOctreeIndex(bytes),
      throwsA(
        isA<SplatOctreeException>().having(
          (SplatOctreeException e) => e.message,
          'message',
          contains('Update flutter3d'),
        ),
      ),
    );
  });
}
