/// The value types a trace carries, to JSON and back, and the blob the bytes
/// live in.
///
/// Enums go by a word rather than by index: a trace written before a value
/// was added to an enum still reads, and one that names a value this build
/// does not have fails by name instead of meaning something else. The words
/// are the tables in `trace_wire_names.dart`, not the Dart names, so a
/// rename in the API does not change a file.
library;

import 'dart:typed_data';

import 'package:vector_math/vector_math.dart' show Vector4;

import '../formats.dart';
import '../geometry_buffer.dart';
import '../render_pass_descriptor.dart';
import '../render_target_pool.dart';
import '../sampler.dart';
import '../vertex_layout_spec.dart';
import 'trace_wire_names.dart';

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

  Uint8List drain() => _bytes.takeBytes();
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
  'colorOperation': blendOperationWire.write(b.colorOperation),
  'sourceColorFactor': blendFactorWire.write(b.sourceColorFactor),
  'destinationColorFactor': blendFactorWire.write(b.destinationColorFactor),
  'alphaOperation': blendOperationWire.write(b.alphaOperation),
  'sourceAlphaFactor': blendFactorWire.write(b.sourceAlphaFactor),
  'destinationAlphaFactor': blendFactorWire.write(b.destinationAlphaFactor),
};

BlendState blendFromJson(Object? json) {
  final m = asMap(json);
  return BlendState(
    colorOperation: blendOperationWire.read(m['colorOperation']),
    sourceColorFactor: blendFactorWire.read(m['sourceColorFactor']),
    destinationColorFactor: blendFactorWire.read(m['destinationColorFactor']),
    alphaOperation: blendOperationWire.read(m['alphaOperation']),
    sourceAlphaFactor: blendFactorWire.read(m['sourceAlphaFactor']),
    destinationAlphaFactor: blendFactorWire.read(m['destinationAlphaFactor']),
  );
}

Map<String, Object?> stencilToJson(StencilState s) => <String, Object?>{
  'compare': compareFunctionWire.write(s.compare),
  'failOp': stencilOperationWire.write(s.failOp),
  'depthFailOp': stencilOperationWire.write(s.depthFailOp),
  'passOp': stencilOperationWire.write(s.passOp),
  'readMask': s.readMask,
  'writeMask': s.writeMask,
};

StencilState stencilFromJson(Object? json) {
  final m = asMap(json);
  return StencilState(
    compare: compareFunctionWire.read(m['compare']),
    failOp: stencilOperationWire.read(m['failOp']),
    depthFailOp: stencilOperationWire.read(m['depthFailOp']),
    passOp: stencilOperationWire.read(m['passOp']),
    readMask: asInt(m['readMask']),
    writeMask: asInt(m['writeMask']),
  );
}

Map<String, Object?> samplerToJson(SamplerDescriptor s) => <String, Object?>{
  'minFilter': minMagFilterWire.write(s.minFilter),
  'magFilter': minMagFilterWire.write(s.magFilter),
  'mipFilter': mipFilterWire.write(s.mipFilter),
  'widthAddressMode': samplerAddressModeWire.write(s.widthAddressMode),
  'heightAddressMode': samplerAddressModeWire.write(s.heightAddressMode),
  'anisotropy': s.anisotropy,
  // Since 1.0, written only when set, so a trace of a pre-1.0 sampler is
  // byte-for-byte what it was and an old reader still reads it.
  if (s.depthAddressMode != SamplerAddressMode.clampToEdge)
    'depthAddressMode': samplerAddressModeWire.write(s.depthAddressMode),
  if (s.compare case final compare?)
    'compare': compareFunctionWire.write(compare),
  if (s.lodMinClamp != 0) 'lodMinClamp': s.lodMinClamp,
  if (s.lodMaxClamp != 32) 'lodMaxClamp': s.lodMaxClamp,
  if (s.borderColor case final border?)
    'borderColor': samplerBorderColorWire.write(border),
};

SamplerDescriptor samplerFromJson(Object? json) {
  final m = asMap(json);
  return SamplerDescriptor(
    minFilter: minMagFilterWire.read(m['minFilter']),
    magFilter: minMagFilterWire.read(m['magFilter']),
    mipFilter: mipFilterWire.read(m['mipFilter']),
    widthAddressMode: samplerAddressModeWire.read(m['widthAddressMode']),
    heightAddressMode: samplerAddressModeWire.read(m['heightAddressMode']),
    anisotropy: asInt(m['anisotropy']),
    depthAddressMode: m['depthAddressMode'] == null
        ? SamplerAddressMode.clampToEdge
        : samplerAddressModeWire.read(m['depthAddressMode']),
    compare: m['compare'] == null
        ? null
        : compareFunctionWire.read(m['compare']),
    lodMinClamp: (m['lodMinClamp'] as num?)?.toDouble() ?? 0,
    lodMaxClamp: (m['lodMaxClamp'] as num?)?.toDouble() ?? 32,
    borderColor: m['borderColor'] == null
        ? null
        : samplerBorderColorWire.read(m['borderColor']),
  );
}

Map<String, Object?> specToJson(RenderTargetDescriptor s) => <String, Object?>{
  'width': s.width,
  'height': s.height,
  'format': textureFormatWire.write(s.format),
  'sampleCount': s.sampleCount,
  'storageMode': storageModeWire.write(s.storageMode),
};

RenderTargetDescriptor specFromJson(Object? json) {
  final m = asMap(json);
  return RenderTargetDescriptor(
    width: asInt(m['width']),
    height: asInt(m['height']),
    format: textureFormatWire.read(m['format']),
    sampleCount: asInt(m['sampleCount']),
    storageMode: storageModeWire.read(m['storageMode']),
  );
}

List<Object?> layoutToJson(VertexLayoutDescriptor layout) => <Object?>[
  for (final buffer in layout.buffers)
    <String, Object?>{
      'stride': buffer.strideInBytes,
      'stepMode': vertexStepModeWire.write(buffer.stepMode),
      'attributes': <Object?>[
        for (final a in buffer.attributes)
          <String, Object?>{
            'name': a.name,
            'format': vertexFormatWire.write(a.format),
            'offset': a.offsetInBytes,
          },
      ],
    },
];

VertexLayoutDescriptor layoutFromJson(Object? json) =>
    VertexLayoutDescriptor(<BufferLayout>[
      for (final b in (json! as List<Object?>).map(asMap))
        BufferLayout(
          strideInBytes: asInt(b['stride']),
          stepMode: vertexStepModeWire.read(b['stepMode']),
          attributes: <InputAttribute>[
            for (final a in (b['attributes']! as List<Object?>).map(asMap))
              InputAttribute(
                name: a['name']! as String,
                format: vertexFormatWire.read(a['format']),
                offsetInBytes: asInt(a['offset']),
              ),
          ],
        ),
    ]);

GeometryUsage usageFromJson(Object? json) => geometryUsageWire.read(json);
