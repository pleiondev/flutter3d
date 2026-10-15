// The shared scene natively — P9, phase 12: its snapshot hashes to the
// number `test/web_core_test.dart` holds the browser to.
@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:test/test.dart';

import 'scenes/shared_scene.dart';

void main() {
  test('the shared scene hashes to the number the browser must match', () {
    expect(
      hashOf(sharedSceneSnapshot()),
      sharedSceneHash,
      reason:
          'the core no longer steps the shared scene to the bits it did: do '
          'not update sharedSceneHash, find what changed the stepping',
    );
  });

  test('the hash does not move with the ABI stamp', () {
    // The scene's bytes as a build with another F3D_ABI_VERSION writes them:
    // the stamp at byte 8 is the only difference, and the world is the same.
    //
    // Mutation: hash bytes 8 to 11 as they lie and the two differ.
    final snapshot = sharedSceneSnapshot();
    final restamped = Uint8List.fromList(snapshot);
    ByteData.sublistView(restamped).setUint32(8, 1, Endian.little);
    expect(hashOf(restamped), hashOf(snapshot));
  });
}
