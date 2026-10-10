/// Debug groups, markers and labels in a trace.
///
/// A backend without a debug API (WebGL2 has no `KHR_debug`) shows a group
/// to no browser tool, so the trace is where a group is kept for every
/// backend: `RecordingDevice` writes each one, and a replay hands it to the
/// replaying device, which passes it on where its API can.
library;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter3d_hardware/trace.dart';
import 'package:test/test.dart';

const RenderTargetDescriptor _target = RenderTargetDescriptor(
  width: 4,
  height: 4,
  format: TextureFormat.r8g8b8a8UNormInt,
);

void main() {
  test('a pass writes its groups and markers into the trace', () {
    // Mutation: forward `pushDebugGroup` without recording it. The kinds
    // below lose 'pushDebugGroup'.
    final device = RecordingDevice(FakeBackend());
    final target = device.createTexture(_target);
    device.beginRenderPass(
        RenderPassDescriptor(
          colors: <ColorTarget>[ColorTarget(texture: target)],
        ),
      )
      ..pushDebugGroup('opaque')
      ..insertDebugMarker('floor')
      ..popDebugGroup()
      ..submit();
    final kinds = device.events.map((e) => e.kind).toList();
    expect(
      kinds.where(
        (k) => <String>{
          'pushDebugGroup',
          'insertDebugMarker',
          'popDebugGroup',
        }.contains(k),
      ),
      <String>['pushDebugGroup', 'insertDebugMarker', 'popDebugGroup'],
    );
    final push = device.events.whereType<TracePushDebugGroup>().single;
    expect(push.label, 'opaque');
  });

  test('a label survives the trace and the replay', () async {
    // Mutation: drop the `TraceSetLabel` arm from the replay. The replayed
    // texture has no label.
    final device = RecordingDevice(FakeBackend());
    final target = device.createTexture(_target);
    device.setLabel(target, 'scene colour');
    expect(device.labelOf(target), 'scene colour');
    final label = device.events.whereType<TraceSetLabel>().single;
    expect(label.resource, TraceLabeled.texture);
    expect(label.label, 'scene colour');

    final read = Trace.decode(Trace(device.events).encode());
    final again = RecordingDevice(FakeBackend());
    await replayTrace(read, again);
    final replayed = again.events.whereType<TraceSetLabel>().single;
    expect(replayed.label, 'scene colour');
    expect(replayed.id, label.id);
  });

  test('a label on something the trace did not make is listed, not lost', () {
    final device = RecordingDevice(FakeBackend());
    device.setLabel(Object(), 'stray');
    expect(device.unrecorded, contains('setLabel'));
    expect(device.events.whereType<TraceSetLabel>(), isEmpty);
  });
}
