/// A trace, its file, and drawing it again — `H3`.
///
/// **`.f3dtrace`.** Eight bytes of magic, a little-endian version and header
/// length, a JSON header holding every event, then one blob holding every
/// payload the events point into by offset and length. JSON because a trace
/// is read by people as often as by code — the question is usually "what did
/// the renderer ask for here" — and a blob because a frame's vertex data in
/// base64 would be a third larger and unreadable anyway.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../command_encoder.dart';
import '../compute.dart';
import '../geometry_buffer.dart';
import '../graphics_device.dart';
import '../shader.dart';
import '../texture.dart';
import 'trace_event.dart';
import 'trace_values.dart';

/// Calls made of a device, in order, with every resource named by an id.
final class Trace {
  const Trace(this.events, {this.metadata = const <String, Object?>{}});

  /// Reads a trace written by [encode].
  factory Trace.decode(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    for (var i = 0; i < _magic.length; i++) {
      if (bytes.length <= i || bytes[i] != _magic[i]) {
        throw const FormatException('not a flutter3d trace: no F3DTRACE magic');
      }
    }
    final version = data.getUint32(8, Endian.little);
    if (version != formatVersion) {
      throw FormatException(
        'a trace of format $version; this build reads $formatVersion',
      );
    }
    final headerLength = data.getUint32(12, Endian.little);
    final header = asMap(
      jsonDecode(utf8.decode(bytes.sublist(16, 16 + headerLength))),
    );
    final blob = TraceBlobReader(bytes.sublist(16 + headerLength));
    return Trace(<TraceEvent>[
      for (final e in (header['events']! as List<Object?>).map(asMap))
        TraceEvent.fromJson(e, blob),
    ], metadata: asMap(header['metadata'] ?? <String, Object?>{}));
  }

  final List<TraceEvent> events;

  /// Whatever the recorder wants to say about where this came from — the
  /// backend, the scene, the engine's version. Carried, never interpreted.
  final Map<String, Object?> metadata;

  static const List<int> _magic = <int>[
    0x46, 0x33, 0x44, 0x54, 0x52, 0x41, 0x43, 0x45, // F3DTRACE
  ];

  /// Bumped when an event's fields change meaning, not when one is added.
  static const int formatVersion = 1;

  /// The `.f3dtrace` bytes.
  Uint8List encode() {
    final blob = TraceBlobWriter();
    final header = utf8.encode(
      jsonEncode(<String, Object?>{
        'metadata': metadata,
        'events': <Object?>[
          for (final e in events)
            <String, Object?>{'kind': e.kind, ...e.toJson(blob)},
        ],
      }),
    );
    final payload = blob.take();
    final prefix = ByteData(16);
    for (var i = 0; i < _magic.length; i++) {
      prefix.setUint8(i, _magic[i]);
    }
    prefix
      ..setUint32(8, formatVersion, Endian.little)
      ..setUint32(12, header.length, Endian.little);
    return (BytesBuilder(copy: false)
          ..add(prefix.buffer.asUint8List())
          ..add(header)
          ..add(payload))
        .takeBytes();
  }
}

/// What a replay read back, in the order the trace asked.
final class TraceReplay {
  TraceReplay._(this.pixels, this.readbacks, this.buffers);

  /// One per `readPixels`, null where the device could not read it.
  final List<ByteData?> pixels;

  /// One per `readback`.
  final List<ByteData> readbacks;

  /// One per `readBuffer`.
  final List<ByteData> buffers;
}

/// Issues every call of [trace] against [device] and collects what it reads.
///
/// Stages are found by name: in the libraries the trace itself loaded, newest
/// first, and then in the device's own. A trace recorded against a shader the
/// replaying device does not have fails with that stage's name.
Future<TraceReplay> replayTrace(Trace trace, GraphicsDevice device) async {
  final libraries = <LoadedShaderLibrary>[];
  final geometry = <int, GeometryBuffer>{};
  final textures = <int, TextureHandle>{};
  final pipelines = <int, PipelineHandle>{};
  final passes = <int, CommandEncoder>{};
  final storage = <int, StorageBuffer>{};
  final computePipelines = <int, ComputePipelineHandle>{};
  final computePasses = <int, ComputeEncoder>{};
  final pixels = <Future<ByteData?>>[];
  final readbacks = <Future<ByteData>>[];
  final buffers = <Future<ByteData>>[];

  ShaderHandle stage(String name) {
    for (final library in libraries.reversed) {
      final found = library[name];
      if (found != null) return found;
    }
    return device.shaders[name] ??
        (throw StateError('the trace names a stage "$name" this device lacks'));
  }

  GeometryBuffer range(TraceGeometryRange r) =>
      geometry[r.buffer]!.slice(offset: r.offset, length: r.length);

  TextureHandle texture(int id) =>
      textures[id] ??
      (throw StateError('the trace names texture $id before creating it'));

  for (final event in trace.events) {
    switch (event) {
      case TraceBeginFrame():
        device.beginFrame();
      case TraceUploadGeometry(:final id, :final usage, :final bytes):
        geometry[id] = device.uploadGeometry(bytes, usage);
      case TraceOverwriteGeometry(:final target, :final offset, :final bytes):
        device.overwriteGeometry(range(target), offset, bytes);
      case TraceReleaseGeometry(:final buffer):
        device.releaseGeometry(geometry.remove(buffer)!);
      case TraceCreateTexture(:final id, :final spec):
        textures[id] = device.createTexture(spec);
      case TraceCreateTextureFromPixels():
        final made = device.createTextureFromPixels(
          width: event.width,
          height: event.height,
          format: event.format,
          pixels: event.pixels,
          mipLevels: event.mipLevels,
        );
        if (made != null) textures[event.id] = made;
      case TraceCreateCubeTextureFromPixels():
        final made = device.createCubeTextureFromPixels(
          size: event.size,
          format: event.format,
          faces: event.faces,
          mipLevels: event.mipLevels,
        );
        if (made != null) textures[event.id] = made;
      case TraceCreateCubeRenderTarget():
        final made = device.createCubeRenderTarget(
          size: event.size,
          format: event.format,
          mipLevels: event.mipLevels,
        );
        if (made != null) textures[event.id] = made;
      case TraceOverwriteTexture():
        await device.overwriteTexture(
          texture(event.texture),
          event.rgba,
          region: event.region,
          mipLevel: event.mipLevel,
        );
      case TraceReleaseTexture(:final texture):
        device.releaseTexture(textures.remove(texture)!);
      case TraceLoadShaders(:final bytes):
        libraries.add(await device.loadShaders(bytes));
      case TraceCreatePipeline():
        pipelines[event.id] = device.createPipeline(
          stage(event.vertex),
          stage(event.fragment),
          layout: event.layout,
        );
      case TraceBeginRenderPass():
        passes[event.pass] = device.beginRenderPass(
          RenderPassDescriptor(
            label: event.label,
            colors: <ColorTarget>[
              for (final c in event.colors)
                ColorTarget(
                  texture: texture(c.texture),
                  resolveTexture: c.resolveTexture == null
                      ? null
                      : texture(c.resolveTexture!),
                  loadAction: c.loadAction,
                  storeAction: c.storeAction,
                  clearValue: c.clearValue,
                  face: c.face,
                  mipLevel: c.mipLevel,
                ),
            ],
            depth: switch (event.depth) {
              null => null,
              final d => DepthTarget(
                texture: texture(d.texture),
                clearValue: d.clearValue,
                loadAction: d.loadAction,
                storeAction: d.storeAction,
                stencilLoadAction: d.stencilLoadAction,
                stencilStoreAction: d.stencilStoreAction,
                stencilClearValue: d.stencilClearValue,
              ),
            },
          ),
        );
      case TraceReadPixels(:final texture):
        pixels.add(device.readPixels(textures[texture]!));
      case TraceReadback(:final texture, :final region):
        readbacks.add(device.readback(textures[texture]!, region: region));
      case TracePassEvent(:final pass):
        _replayPassEvent(
          event,
          passes[pass] ??
              (throw StateError(
                'the trace names pass $pass before opening it',
              )),
          pipelines: pipelines,
          range: range,
          texture: texture,
          stage: stage,
        );
        if (event is TraceSubmit) passes.remove(pass);
      case TraceCreateStorageBuffer():
        storage[event.id] = device.createStorageBuffer(
          event.bytes,
          hostReadable: event.hostReadable,
        );
      case TraceReleaseStorageBuffer(:final buffer):
        device.releaseStorageBuffer(storage.remove(buffer)!);
      case TraceCreateComputePipeline(:final id, :final shader):
        computePipelines[id] = device.createComputePipeline(stage(shader));
      case TraceBeginComputePass(:final pass, :final label):
        computePasses[pass] = device.beginComputePass(label: label);
      case TraceComputeBindPipeline(:final pass, :final pipeline):
        computePasses[pass]!.bindPipeline(computePipelines[pipeline]!);
      case TraceComputeBindStorageBuffer():
        computePasses[event.pass]!.bindStorageBuffer(
          stage(event.shader),
          event.name,
          storage[event.buffer]!,
        );
      case TraceComputeBindUniformBlock():
        computePasses[event.pass]!.bindUniformBlock(
          stage(event.shader),
          event.block,
          event.members,
        );
      case TraceDispatch(:final pass, :final x, :final y, :final z):
        computePasses[pass]!.dispatch(x, y, z);
      case TraceComputeSubmit(:final pass):
        computePasses.remove(pass)!.submit();
      case TraceReadBuffer(:final buffer):
        buffers.add(device.readBuffer(storage[buffer]!));
    }
  }

  return TraceReplay._(
    await Future.wait(pixels),
    await Future.wait(readbacks),
    await Future.wait(buffers),
  );
}

void _replayPassEvent(
  TracePassEvent event,
  CommandEncoder pass, {
  required Map<int, PipelineHandle> pipelines,
  required GeometryBuffer Function(TraceGeometryRange) range,
  required TextureHandle Function(int) texture,
  required ShaderHandle Function(String) stage,
}) {
  switch (event) {
    case TraceSetViewport(:final rect):
      pass.setViewport(rect);
    case TraceSetScissor(:final rect):
      pass.setScissor(rect);
    case TraceSetPrimitiveType(:final value):
      pass.setPrimitiveType(value);
    case TraceSetPolygonMode(:final value):
      pass.setPolygonMode(value);
    case TraceSetCullMode(:final value):
      pass.setCullMode(value);
    case TraceSetWindingOrder(:final value):
      pass.setWindingOrder(value);
    case TraceSetDepthWrite(:final value):
      pass.setDepthWrite(value);
    case TraceSetDepthCompare(:final value):
      pass.setDepthCompare(value);
    case TraceSetStencil(:final front, :final back):
      pass.setStencil(front, back: back);
    case TraceSetStencilReference(:final value):
      pass.setStencilReference(value);
    case TraceSetBlend(:final state, :final attachment):
      pass.setBlend(state, attachment: attachment);
    case TraceSetBlendColor(:final color):
      pass.setBlendColor(color);
    case TraceBindPipeline(:final pipeline):
      pass.bindPipeline(pipelines[pipeline]!);
    case TraceBindVertexBuffer(:final buffer, :final vertexCount, :final slot):
      pass.bindVertexBuffer(range(buffer), vertexCount, slot: slot);
    case TraceBindVertexData(:final bytes, :final vertexCount, :final slot):
      pass.bindVertexData(bytes, vertexCount, slot: slot);
    case TraceBindIndexBuffer(:final buffer, :final type, :final indexCount):
      pass.bindIndexBuffer(range(buffer), type, indexCount);
    case TraceBindIndexData(:final bytes, :final type, :final indexCount):
      pass.bindIndexData(bytes, type, indexCount);
    case TraceBindUniformBlock(:final shader, :final block, :final members):
      pass.bindUniformBlock(stage(shader), block, members);
    case TraceBindTexture():
      pass.bindTexture(
        stage(event.shader),
        event.slot,
        texture(event.texture),
        sampler: event.sampler,
      );
    case TraceClearBindings():
      pass.clearBindings();
    case TraceDraw(:final instanceCount):
      pass.draw(instanceCount: instanceCount);
    case TraceSubmit():
      pass.submit();
  }
}
