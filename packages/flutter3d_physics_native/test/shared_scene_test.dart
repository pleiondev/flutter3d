// The shared scene natively — P9, phase 12: its snapshot hashes to the
// number `test/web_core_test.dart` holds the browser to.
@TestOn('vm')
library;

import 'package:test/test.dart';

import 'scenes/shared_scene.dart';

void main() {
  test('the shared scene hashes to the number the browser must match', () {
    expect(
      hashOf(sharedSceneSnapshot()),
      sharedSceneHash,
      reason: 'changed on purpose? set sharedSceneHash in test/scenes',
    );
  });
}
