/// A device has one id that compilers and manifests match exactly.
///
/// `backendName` is for people, and the engine joined it to the compilers'
/// lower-case names by a prefix. `backendId` is the one name both sides
/// give: the name in lower case unless a backend says otherwise, and the
/// recorder answers with the device's own.
///
/// Mutation: make the default `backendName` as written.
library;

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
}
