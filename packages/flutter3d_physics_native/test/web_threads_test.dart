// The core's threads in the browser — P9, phase 12: the threads build on a
// shared memory, three Web Workers beside the page, and a world stepping on
// four threads to the same bytes as the native library on one.
//
// Needs SharedArrayBuffer, which a page has when served cross-origin
// isolated; skipped where there is none. Chrome is asked for it:
//
//     <dart test> -p chrome_sab test/web_threads_test.dart
@TestOn('browser')
library;

import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:test/test.dart';

import 'scenes/shared_scene.dart';

void main() {
  setUpAll(
    () => loadPhysicsCore(
      url: '../web/f3d_physics.wasm',
      threads: 4,
      threadsUrl: '../web/f3d_physics_threads.wasm',
      workerUrl: '../web/f3d_worker.js',
    ),
  );

  test('the shared scene steps on four threads to the native bytes', () {
    if (physicsCoreThreads == 1) {
      markTestSkipped('no SharedArrayBuffer: the page is not isolated');
      return;
    }
    expect(physicsCoreThreads, 4);
    expect(hashOf(sharedSceneSnapshot(threads: 4)), sharedSceneHash);
    final world = NativeWorld();
    addTearDown(world.dispose);
    world.threads = 4;
    expect(world.threads, 4);
    expect(() => world.threads = 5, throwsArgumentError);
  });
}
