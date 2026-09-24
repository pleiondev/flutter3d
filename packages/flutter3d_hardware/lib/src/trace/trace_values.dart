/// The value types a trace carries, to JSON and back, and the blob the bytes
/// live in.
///
/// Enums go by name rather than by index: a trace written before a value was
/// added to an enum still reads, and one that names a value this build does
/// not have fails by name instead of meaning something else.
library;

import 'dart:typed_data';

import 'package:vector_math/vector_math.dart' show Vector4;

import '../formats.dart';
import '../geometry_buffer.dart';
import '../render_pass_descriptor.dart';
import '../render_target_pool.dart';
import '../sampler.dart';
import '../vertex_layout_spec.dart';

/// Collects the byte payloads of a trace into one buffer, handing back where
/// each landed.
final class TraceBlobWriter {
  final BytesBuilder _bytes = BytesBuilder(copy: false);

  /// Appends a copy of [data] and returns `[offset, length]` for the header.
  List<int> add(ByteData data) {
    final offset = _bytes.length;
    _bytes.add(
      Uint8List.fromList(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      ),
    );
    return <int>[offset, data.lengthInBytes];
  }

  Uint8List take() => _bytes.takeBytes();
}

/// Reads payloads back out of a trace's blob.
final class TraceBlobReader {
  TraceBlobReader(this._blob);

  final Uint8List _blob;

  /// A fresh copy of the payload at `[offset, length]`, so a replay that
  /// hands it to a backend cannot alias the file.
  ByteData read(Object? where) {
    final pair = (where! as List<Object?>).cast<int>();
    return ByteData.sublistView(
      Uint8List.fromList(_blob.sublist(pair[0], pair[0] + pair[1])),
    );
  }
}

T byName<T extends Enum>(List<T> values, Object? name) =>
    values.byName(name! as String);

Map<String, Object?> asMap(Object? value) =>
    (value! as Map<Object?, Object?>).cast<String, Object?>();

int asInt(Object? value) => (value! as num).toInt();

double asDouble(Object? value) => (value! as num).toDouble();

List<Object?> screenRectToJson(ScreenRect r) => <Object?>[
  r.x,
  r.y,
  r.width,
  r.height,
];

ScreenRect screenRectFromJson(Object? json) {
  final v = (json! as List<Object?>).cast<num>();
  return ScreenRect(
    x: v[0].toInt(),
    y: v[1].toInt(),
    width: v[2].toInt(),
    height: v[3].toInt(),
  );
}

List<Object?> vector4ToJson(Vector4 v) => <Object?>[v.x, v.y, v.z, v.w];

Vector4 vector4FromJson(Object? json) {
  final v = (json! as List<Object?>).cast<num>();
  return Vector4(
    v[0].toDouble(),
    v[1].toDouble(),
    v[2].toDouble(),
    v[3].toDouble(),
  );
}

Map<String, Object?> blendToJson(BlendState b) => <String, Object?>{
  'colorOperation': b.colorOperation.name,
  'sourceColorFactor': b.sourceColorFactor.name,
  'destinationColorFactor': b.destinationColorFactor.name,
  'alphaOperation': b.alphaOperation.name,
  'sourceAlphaFactor': b.sourceAlphaFactor.name,
  'destinationAlphaFactor': b.destinationAlphaFactor.name,
};

BlendState blendFromJson(Object? json) {
  final m = asMap(json);
  return BlendState(
    colorOperation: byName(BlendOperation.values, m['colorOperation']),
    sourceColorFactor: byName(BlendFactor.values, m['sourceColorFactor']),
    destinationColorFactor: byName(
      BlendFactor.values,
      m['destinationColorFactor'],
    ),
    alphaOperation: byName(BlendOperation.values, m['alphaOperation']),
    sourceAlphaFactor: byName(BlendFactor.values, m['sourceAlphaFactor']),
    destinationAlphaFactor: byName(
      BlendFactor.values,
      m['destinationAlphaFactor'],
    ),
  );
}

Map<String, Object?> stencilToJson(StencilState s) => <String, Object?>{
  'compare': s.compare.name,
  'failOp': s.failOp.name,
  'depthFailOp': s.depthFailOp.name,
  'passOp': s.passOp.name,
  'readMask': s.readMask,
  'writeMask': s.writeMask,
};

StencilState stencilFromJson(Object? json) {
  final m = asMap(json);
  return StencilState(
    compare: byName(CompareFunction.values, m['compare']),
    failOp: byName(StencilOperation.values, m['failOp']),
    depthFailOp: byName(StencilOperation.values, m['depthFailOp']),
    passOp: byName(StencilOperation.values, m['passOp']),
    readMask: asInt(m['readMask']),
    writeMask: asInt(m['writeMask']),
  );
}

Map<String, Object?> samplerToJson(SamplerOptions s) => <String, Object?>{
  'minFilter': s.minFilter.name,
  'magFilter': s.magFilter.name,
  'mipFilter': s.mipFilter.name,
  'widthAddressMode': s.widthAddressMode.name,
  'heightAddressMode': s.heightAddressMode.name,
  'anisotropy': s.anisotropy,
};

SamplerOptions samplerFromJson(Object? json) {
  final m = asMap(json);
  return SamplerOptions(
    minFilter: byName(MinMagFilter.values, m['minFilter']),
    magFilter: byName(MinMagFilter.values, m['magFilter']),
    mipFilter: byName(MipFilter.values, m['mipFilter']),
    widthAddressMode: byName(SamplerAddressMode.values, m['widthAddressMode']),
    heightAddressMode: byName(
      SamplerAddressMode.values,
      m['heightAddressMode'],
    ),
    anisotropy: asInt(m['anisotropy']),
  );
}

Map<String, Object?> specToJson(RenderTargetSpec s) => <String, Object?>{
  'width': s.width,
  'height': s.height,
  'format': s.format.name,
  'sampleCount': s.sampleCount,
  'storageMode': s.storageMode.name,
};

RenderTargetSpec specFromJson(Object? json) {
  final m = asMap(json);
  return RenderTargetSpec(
    width: asInt(m['width']),
    height: asInt(m['height']),
    format: byName(TextureFormat.values, m['format']),
    sampleCount: asInt(m['sampleCount']),
    storageMode: byName(StorageMode.values, m['storageMode']),
  );
}

List<Object?> layoutToJson(VertexLayoutSpec layout) => <Object?>[
  for (final buffer in layout.buffers)
    <String, Object?>{
      'stride': buffer.strideInBytes,
      'stepMode': buffer.stepMode.name,
      'attributes': <Object?>[
        for (final a in buffer.attributes)
          <String, Object?>{
            'name': a.name,
            'format': a.format.name,
            'offset': a.offsetInBytes,
          },
      ],
    },
];

VertexLayoutSpec layoutFromJson(Object? json) =>
    VertexLayoutSpec(<BufferLayout>[
      for (final b in (json! as List<Object?>).map(asMap))
        BufferLayout(
          strideInBytes: asInt(b['stride']),
          stepMode: byName(VertexStepMode.values, b['stepMode']),
          attributes: <InputAttribute>[
            for (final a in (b['attributes']! as List<Object?>).map(asMap))
              InputAttribute(
                name: a['name']! as String,
                format: byName(VertexFormat.values, a['format']),
                offsetInBytes: asInt(a['offset']),
              ),
          ],
        ),
    ]);

GeometryUsage usageFromJson(Object? json) => byName(GeometryUsage.values, json);
