/// A frame recorded as a trace, written to a file, read back and drawn again
/// on a fresh device, comes out the same to the byte — `H3`.
///
///     flutter test test/trace_replay_test.dart
///
/// The software rasteriser on both ends, because it is the backend whose
/// answer is exact: the same calls, the same bytes. That is what makes this a
/// test of the trace rather than of two backends' agreement. A trace that
/// dropped a uniform member, forgot a texture's sampler or recorded a scratch
/// array by reference instead of by value would draw a different frame, and
/// the comparison below would count it.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d/parity_scene.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_hardware/trace.dart';
import 'package:flutter_test/flutter_test.dart';

CpuDevice _cpu() => CpuDevice(
  width: kParityWidth,
  height: kParityHeight,
  shaders: CpuShaderLibrary(builtinCpuShaders()),
);

TextureHandle _texel(GraphicsDevice device, List<int> rgba) =>
    device.createTextureFromPixels(
      width: 1,
      height: 1,
      format: TextureFormat.r8g8b8a8UNormInt,
      pixels: ByteData.sublistView(Uint8List.fromList(rgba)),
    )!;

void main() {
  for (final which in ParityScene.values) {
    test('the ${which.name} fixture replays to the same bytes', () async {
      // Mutation: record `bindUniformBlock`'s members by reference rather
      // than copying them. Every draw of the replay reads the last draw's
      // uniforms, and the frame is a pile of objects at one place.
      final recording = RecordingDevice(_cpu());
      final renderer = Renderer.create(
        device: recording,
        fallbackAlbedo: _texel(recording, <int>[255, 255, 255, 255]),
        fallbackNormal: _texel(recording, <int>[128, 128, 255, 255]),
      );
      final built = buildParityScene(recording, which: which);
      final frame = renderer.render(
        width: kParityWidth,
        height: kParityHeight,
        scene: built.scene,
        views: <RenderView>[RenderView(camera: built.camera)],
        settings: paritySettingsFor(which),
      );
      final original = await recording.readPixels(frame.frame);

      final file = Trace(
        recording.events,
        metadata: <String, Object?>{'scene': which.name},
      ).encode();
      final read = Trace.decode(file);
      expect(read.metadata['scene'], which.name);
      expect(read.events.length, recording.events.length);

      final replay = await replayTrace(read, _cpu());
      final again = replay.pixels.single;
      expect(again, isNotNull);
      expect(
        again!.buffer.asUint8List(again.offsetInBytes, again.lengthInBytes),
        original!.buffer.asUint8List(
          original.offsetInBytes,
          original.lengthInBytes,
        ),
      );
    });
  }

  test('a trace that is not one says so', () {
    expect(
      () => Trace.decode(Uint8List.fromList(<int>[1, 2, 3])),
      throwsFormatException,
    );
  });
}
