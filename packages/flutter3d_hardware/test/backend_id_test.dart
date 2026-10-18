/// A device has one id that compilers and manifests match exactly.
///
/// `backendName` is for people, and the engine joined it to the compilers'
/// lower-case names by a prefix. `backendId` is the one name both sides
/// give: the name in lower case unless a backend says otherwise, and the
/// recorder answers with the device's own. It is a `BackendId`, a string
/// with the engine's five spellings written down.
///
/// Mutation: make the default `backendName` as written.
library;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter3d_hardware/trace.dart';
import 'package:test/test.dart';

void main() {
  test('the id is the name in lower case by default', () {
    final device = FakeBackend();
    expect(device.backendName, 'FakeBackend');
    expect(device.backendId, 'fakebackend');
    expect(RecordingDevice(device).backendId, 'fakebackend');
  });

  test('an id is the string it holds, wherever a string is taken', () {
    // Mutation: drop `implements String` and the comparison with a manifest's
    // string, and the call taking a `String`, stop compiling.
    const String fromManifest = 'webgpu';
    expect(BackendId.webgpu == fromManifest, isTrue);
    expect(BackendId.webgpu.name, 'webgpu');
    String takesString(String s) => s;
    expect(takesString(BackendId.cpu), 'cpu');
  });

  test('the five engine backends, each spelled once', () {
    // Mutation: spell `impeller` as its device does not and the set below
    // holds a name no device answers.
    expect(BackendId.values.toSet(), <String>{
      'cpu',
      'impeller',
      'webgl',
      'webgpu',
      'wgpu',
    });
  });

  test('an outside backend names its own', () {
    // Mutation: make the constructor private and an outside backend has no
    // id to answer with.
    const vulkan = BackendId('vulkan');
    expect(BackendId.values, isNot(contains(vulkan)));
    expect(vulkan, 'vulkan');
  });
}
