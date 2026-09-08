/// The WebGPU section of a `ShaderBundle`: WGSL sources and their reflection.
///
/// A JSON document, as UTF-8, shaped
/// `{"vertex": {name: stage}, "fragment": {name: stage}}` — where a stage is
/// the WGSL text beside the three things the browser cannot be asked about it.
///
/// **The reflection is here because WGSL has no equivalent of it.** Impeller
/// reads its block, sampler and attribute names out of `impellerc`'s
/// flatbuffer, and the WebGL2 backend asks the context: `getActiveUniformBlock`,
/// `getAttribLocation` and the rest are part of GL. `GPUShaderModule` answers
/// none of that. It cannot even be interrogated for the bindings it declares,
/// which a pipeline layout has to state up front — so a WebGPU pipeline built
/// from nothing but WGSL is a pipeline the engine has no way to bind anything
/// to.
///
/// The contract is the reason this is names and not indices.
/// `PassEncoder.bindUniformBlock` takes a block name, `bindTexture` takes a
/// sampler name and `InputAttribute.name` says outright that a name is what the
/// two hardware backends agree about. This section is what lets a third one
/// answer to the same names.
///
/// **No `package:web` here and no `dart:js_interop`, on purpose.** It is the
/// most valuable line copied from `webgl_bundle_section.dart`: the packer runs
/// on the Dart VM, where a browser binding does not load, and it has to write
/// exactly what the device reads. One file both import is how the two stay the
/// same document, and a codec that could only be compiled in a browser would
/// mean the writer and the reader were two hand-kept transcriptions of a format
/// nobody had written down.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';

/// One vertex input, by the name the engine binds it under.
///
/// [location] because that is all WGSL kept, and [format] because a WebGPU
/// vertex layout must state one per attribute — GL derived it from the shader
/// and the buffer between them, and WebGPU asks the caller.
final class WebGpuAttribute {
  const WebGpuAttribute({
    required this.name,
    required this.location,
    required this.format,
  });

  final String name;
  final int location;
  final VertexFormat format;
}

/// Where one member of a uniform block begins, and how many bytes it spans.
///
/// Both in the block's own bytes, and both std140 — see [WebGpuBlock].
final class WebGpuBlockMember {
  const WebGpuBlockMember({
    required this.name,
    required this.offsetInBytes,
    required this.sizeInBytes,
  });

  final String name;
  final int offsetInBytes;
  final int sizeInBytes;
}

/// One uniform block, by the type name the engine binds it under.
///
/// The offsets are std140's, computed by the packer from the GLSL rather than
/// read back out of the WGSL. That is not a shortcut: the GLSL is compiled with
/// an explicit `std140` on every block, so the packing is stated rather than
/// negotiated, and WGSL's uniform address space lays a struct of vectors and
/// matrices out the same way. `tool/generate_shaders.dart` checks the
/// arithmetic against glslang's own `Offset` decorations on every block it
/// writes, which is the only place the two could ever disagree.
final class WebGpuBlock {
  const WebGpuBlock({
    required this.name,
    required this.group,
    required this.binding,
    required this.sizeInBytes,
    required this.members,
  });

  final String name;
  final int group;
  final int binding;

  /// The whole block, rounded up the way std140 rounds a structure up.
  final int sizeInBytes;

  final List<WebGpuBlockMember> members;
}

/// Which shape of texture a sampler reads.
///
/// The spelling is WebGPU's own `GPUTextureViewDimension`, because that is
/// where the value ends up: a bind group layout entry has to declare it, and a
/// layout that says `2d` over a cube view is an error at pipeline creation
/// rather than a picture that is merely wrong.
enum WebGpuTextureDimension {
  twoDimensional('2d'),
  cube('cube');

  const WebGpuTextureDimension(this.gpuName);

  final String gpuName;
}

/// One texture-and-sampler pair, by the name the engine binds it under.
///
/// **Two bindings for one name**, which is the whole shape of the problem this
/// package's GLSL is edited to solve. GLSL's `sampler2D` is one object; WGSL,
/// like Vulkan and Metal, keeps the image and the filtering state apart. So the
/// engine's `bindTexture('base_color_texture', …)` becomes two bind group
/// entries, and this record is what says which two.
final class WebGpuSampler {
  const WebGpuSampler({
    required this.name,
    required this.group,
    required this.textureBinding,
    required this.samplerBinding,
    required this.dimension,
  });

  final String name;
  final int group;
  final int textureBinding;
  final int samplerBinding;
  final WebGpuTextureDimension dimension;
}

/// One shader stage: the WGSL, and what a pipeline needs to know about it.
///
/// [attributes] is empty for a fragment stage, which has no vertex inputs. It
/// is a list rather than a map because a vertex layout is built in location
/// order and the order is the reflection's to state.
final class WebGpuStage {
  const WebGpuStage({
    required this.wgsl,
    required this.attributes,
    required this.blocks,
    required this.samplers,
  });

  final String wgsl;
  final List<WebGpuAttribute> attributes;
  final List<WebGpuBlock> blocks;
  final List<WebGpuSampler> samplers;
}

/// What the section decodes to.
typedef WebGpuSectionStages = ({
  Map<String, WebGpuStage> vertex,
  Map<String, WebGpuStage> fragment,
});

/// The section bytes for [vertex] and [fragment] stages.
ByteData encodeWebGpuSection({
  required Map<String, WebGpuStage> vertex,
  required Map<String, WebGpuStage> fragment,
}) {
  final text = jsonEncode(<String, Object>{
    'vertex': <String, Object>{
      for (final entry in vertex.entries) entry.key: _stageToJson(entry.value),
    },
    'fragment': <String, Object>{
      for (final entry in fragment.entries)
        entry.key: _stageToJson(entry.value),
    },
  });
  return Uint8List.fromList(utf8.encode(text)).buffer.asByteData();
}

/// The stages in [bytes].
///
/// Throws [FormatException] when the bytes are not the document above — the
/// device turns that into a refusal naming the bundle, rather than a pipeline
/// built from half a reflection.
WebGpuSectionStages decodeWebGpuSection(ByteData bytes) {
  final text = utf8.decode(
    bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
  );
  final document = jsonDecode(text);
  if (document is! Map<String, dynamic>) {
    throw const FormatException('the section is not a JSON object');
  }

  Map<String, WebGpuStage> stages(String kind) {
    final entries = document[kind];
    if (entries is! Map<String, dynamic>) {
      throw FormatException('the section has no "$kind" object');
    }
    return <String, WebGpuStage>{
      for (final entry in entries.entries)
        entry.key: _stageFromJson('"${entry.key}" under "$kind"', entry.value),
    };
  }

  return (vertex: stages('vertex'), fragment: stages('fragment'));
}

Map<String, Object> _stageToJson(WebGpuStage stage) => <String, Object>{
  'wgsl': stage.wgsl,
  'attributes': <Object>[
    for (final attribute in stage.attributes)
      <String, Object>{
        'name': attribute.name,
        'location': attribute.location,
        'format': attribute.format.name,
      },
  ],
  'blocks': <Object>[
    for (final block in stage.blocks)
      <String, Object>{
        'name': block.name,
        'group': block.group,
        'binding': block.binding,
        'size': block.sizeInBytes,
        'members': <Object>[
          for (final member in block.members)
            <String, Object>{
              'name': member.name,
              'offset': member.offsetInBytes,
              'size': member.sizeInBytes,
            },
        ],
      },
  ],
  'samplers': <Object>[
    for (final sampler in stage.samplers)
      <String, Object>{
        'name': sampler.name,
        'group': sampler.group,
        'texture': sampler.textureBinding,
        'sampler': sampler.samplerBinding,
        'dimension': sampler.dimension.gpuName,
      },
  ],
};

WebGpuStage _stageFromJson(String where, Object? value) {
  final stage = _object(where, value);
  return WebGpuStage(
    wgsl: _string('$where has no "wgsl"', stage['wgsl']),
    attributes: <WebGpuAttribute>[
      for (final entry in _list(
        '$where has no "attributes"',
        stage['attributes'],
      ))
        _attributeFromJson(where, entry),
    ],
    blocks: <WebGpuBlock>[
      for (final entry in _list('$where has no "blocks"', stage['blocks']))
        _blockFromJson(where, entry),
    ],
    samplers: <WebGpuSampler>[
      for (final entry in _list('$where has no "samplers"', stage['samplers']))
        _samplerFromJson(where, entry),
    ],
  );
}

WebGpuAttribute _attributeFromJson(String where, Object? value) {
  final json = _object('$where has a malformed attribute', value);
  final format = _string(
    '$where has an attribute with no format',
    json['format'],
  );
  return WebGpuAttribute(
    name: _string('$where has an attribute with no name', json['name']),
    location: _integer(
      '$where has an attribute with no location',
      json['location'],
    ),
    format: VertexFormat.values.firstWhere(
      (candidate) => candidate.name == format,
      orElse: () =>
          throw FormatException('$where names the vertex format "$format"'),
    ),
  );
}

WebGpuBlock _blockFromJson(String where, Object? value) {
  final json = _object('$where has a malformed block', value);
  return WebGpuBlock(
    name: _string('$where has a block with no name', json['name']),
    group: _integer('$where has a block with no group', json['group']),
    binding: _integer('$where has a block with no binding', json['binding']),
    sizeInBytes: _integer('$where has a block with no size', json['size']),
    members: <WebGpuBlockMember>[
      for (final member in _list(
        '$where has a block with no members',
        json['members'],
      ))
        _memberFromJson(where, member),
    ],
  );
}

WebGpuBlockMember _memberFromJson(String where, Object? value) {
  final json = _object('$where has a malformed block member', value);
  return WebGpuBlockMember(
    name: _string('$where has a member with no name', json['name']),
    offsetInBytes: _integer(
      '$where has a member with no offset',
      json['offset'],
    ),
    sizeInBytes: _integer('$where has a member with no size', json['size']),
  );
}

WebGpuSampler _samplerFromJson(String where, Object? value) {
  final json = _object('$where has a malformed sampler', value);
  final dimension = _string(
    '$where has a sampler with no dimension',
    json['dimension'],
  );
  return WebGpuSampler(
    name: _string('$where has a sampler with no name', json['name']),
    group: _integer('$where has a sampler with no group', json['group']),
    textureBinding: _integer(
      '$where has a sampler with no texture binding',
      json['texture'],
    ),
    samplerBinding: _integer(
      '$where has a sampler with no sampler binding',
      json['sampler'],
    ),
    dimension: WebGpuTextureDimension.values.firstWhere(
      (candidate) => candidate.gpuName == dimension,
      orElse: () =>
          throw FormatException('$where names the dimension "$dimension"'),
    ),
  );
}

Map<String, dynamic> _object(String message, Object? value) =>
    value is Map<String, dynamic> ? value : throw FormatException(message);

List<dynamic> _list(String message, Object? value) =>
    value is List<dynamic> ? value : throw FormatException(message);

String _string(String message, Object? value) =>
    value is String ? value : throw FormatException(message);

int _integer(String message, Object? value) =>
    value is int ? value : throw FormatException(message);
