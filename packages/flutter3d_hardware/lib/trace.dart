/// Recording what a device was asked, keeping it as a `.f3dtrace` file, and
/// asking it again of any backend — `H3`.
///
/// ```dart
/// final recording = RecordingDevice(device);
/// final renderer = Renderer.create(device: recording);
/// final frame = renderer.render(...);
/// await recording.readPixels(frame.frame);
/// final bytes = Trace(recording.events).encode();
///
/// final replay = await replayTrace(Trace.decode(bytes), otherDevice);
/// replay.pixels.single; // the same frame, drawn by the other backend
/// ```
///
/// A library of its own rather than part of `flutter3d_hardware.dart`: an
/// application draws without it, and a tool or a test that wants it asks.
library;

export 'src/trace/recording_device.dart' show RecordingDevice;
export 'src/trace/trace.dart' show Trace, TraceReplay, replayTrace;
export 'src/trace/trace_event.dart';
export 'src/trace/trace_values.dart' show TraceBlobReader, TraceBlobWriter;
