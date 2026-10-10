/// What `WebGpuDevice` does with what the browser says about it, frame by
/// frame.
///
///     flutter test test/webgpu_error_ledger_test.dart
///
/// **The browser's verdicts arrive late, and used to arrive nowhere.** Every
/// guarded call left a future in a list that only `debugDrainErrors` emptied,
/// which production never called: several entries a frame, kept for the life
/// of the tab, and every complaint in them unread. The ledger holds the two
/// halves apart: a verdict in flight leaves the set when it settles, and a
/// complaint that settled is handed over at the next frame as a typed refusal
/// — a `ShaderCompileException` for WGSL the browser would not compile, a
/// `DeviceResourceException` for anything else it refused. A device that is
/// lost reports on `GraphicsDevice.lost` instead, so the frame after a loss
/// does not also throw what the loss explains.
///
/// Pure Dart, so it runs on the VM: the device needs a browser with WebGPU to
/// open, and the ledger does not. On the VM only, because the device's wiring
/// is held by reading its source.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_webgpu/src/webgpu_error_ledger.dart';
import 'package:flutter_test/flutter_test.dart';

WebGpuErrorLedger _ledger() => WebGpuErrorLedger(backend: 'WebGPU');

void main() {
  test('a verdict leaves the set once it has settled', () async {
    // Mutation: add to the set without the `whenComplete` that takes it out,
    // and a thousand frames leave a thousand futures behind.
    final ledger = _ledger();
    for (var i = 0; i < 1000; i++) {
      ledger.track(Future<void>.value());
    }
    await pumpEventQueue();
    expect(ledger.inFlight, 0);
  });

  test(
    'a verdict that rejects is a complaint, not an unhandled error',
    () async {
      // Mutation: track the future as it is, and the rejection escapes the
      // zone and fails this test as an uncaught error.
      final ledger = _ledger()
        ..track(Future<void>.error(StateError('the promise rejected')));
      await pumpEventQueue();
      expect(ledger.inFlight, 0);
      expect(() => ledger.takeFrame(), throwsA(isA<DeviceResourceException>()));
    },
  );

  test('a frame with nothing said takes nothing and throws nothing', () {
    _ledger().takeFrame();
  });

  test('a refused call is thrown at the next frame, once', () {
    // Mutation: leave `takeFrame` empty, as production was, and nothing
    // is ever thrown.
    final ledger = _ledger()
      ..complain('a pipeline over "pbr"', 'the vertex layout is not legal');
    expect(
      ledger.takeFrame,
      throwsA(
        isA<DeviceResourceException>()
            .having((e) => e.operation, 'operation', 'a pipeline over "pbr"')
            .having((e) => e.backend, 'backend', 'WebGPU')
            .having(
              (e) => e.reason,
              'reason',
              contains('the vertex layout is not legal'),
            ),
      ),
    );
    // Taken, so the next frame is clean: a refusal is news once.
    ledger.takeFrame();
  });

  test('WGSL that did not compile is a ShaderCompileException', () {
    // Mutation: file the compiler's message as a plain complaint, and the
    // refusal is a DeviceResourceException that hides which stage it was.
    final ledger = _ledger()
      ..complain('a pipeline over "pbr"', 'Invalid ShaderModule "pbr.frag"')
      ..complainOfShader('pbr.frag', 'line 3, column 7: unknown type');
    expect(
      ledger.takeFrame,
      throwsA(
        isA<ShaderCompileException>()
            .having((e) => e.shader, 'shader', 'pbr.frag')
            .having((e) => e.backend, 'backend', 'WebGPU')
            .having((e) => e.log, 'log', contains('unknown type'))
            // The pipeline that failed because of it is said too.
            .having((e) => e.log, 'log', contains('pbr.frag')),
      ),
    );
  });

  test('a lost device does not throw what its loss explains', () {
    // Mutation: ignore `deviceLost`, and the frame after a loss throws a
    // refusal on top of the event on `lost`.
    final ledger = _ledger()..complain('a submit', 'the device is lost');
    ledger.takeFrame(deviceLost: true);
    ledger.takeFrame();
  });

  test('a frame of many complaints keeps a bounded number of them', () {
    // Mutation: drop the cap, and a frame that refuses every draw holds a
    // sentence per draw until somebody begins the next frame.
    final ledger = _ledger();
    for (var i = 0; i < 10000; i++) {
      ledger.complain('draw $i', 'refused');
    }
    expect(ledger.held, WebGpuErrorLedger.maxHeld);
    expect(
      ledger.takeFrame,
      throwsA(
        isA<DeviceResourceException>().having(
          (e) => e.reason,
          'reason',
          contains('and ${10000 - WebGpuErrorLedger.maxHeld} more'),
        ),
      ),
    );
  });

  test('the device files everything here and empties it every frame', () {
    // The device opens only in a browser with WebGPU, so the wiring is held
    // by reading its source: a ledger nobody empties is the leak this file
    // exists to close.
    //
    // Mutation: drop the `takeFrame` from `beginFrame`, or the
    // `uncapturederror` listener, or the call that starts watching in the
    // constructor, and this fails naming it.
    final source = File('lib/src/webgpu_device.dart').readAsStringSync();
    for (final wired in <String>[
      '_ledger.takeFrame(deviceLost: _isLost);',
      "'uncapturederror',",
      '_watchBrowser();',
      'Future<String?> debugDrainErrors([String where = \'\']) =>',
    ]) {
      expect(source, contains(wired), reason: wired);
    }
    // And nothing is kept outside it any more.
    expect(source, isNot(contains('_pending')));
    expect(source, isNot(contains('_errors')));
  });

  test('the debug drain waits for what is in flight and says it all', () async {
    // The test path the device kept: what `debugDrainErrors` answered before
    // the ledger, in the same words.
    final ledger = _ledger();
    final verdict = Completer<void>();
    ledger.track(
      verdict.future.then((_) => ledger.complain('the draw', 'refused')),
    );
    final said = ledger.debugDrain('a test');
    verdict.complete();
    expect(await said, 'a test: the draw: refused');
    expect(await ledger.debugDrain(), isNull);
    expect(ledger.inFlight, 0);
  });
}
