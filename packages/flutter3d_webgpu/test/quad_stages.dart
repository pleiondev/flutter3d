/// A stage table a test can open a device with, and the quad it draws.
///
/// **Hand-written rather than taken from `engine_shaders.dart`**, and the
/// reason is what a device test is asking. The engine's stages are twenty-odd
/// modules whose uniform blocks run to hundreds of bytes and whose vertex
/// inputs number eight; opening a device with them costs a second of
/// compilation before the first assertion and makes every colour that comes
/// back a function of the lighting model. These three are the smallest thing
/// that exercises the whole path — a uniform block in the vertex stage, another
/// in the fragment stage, a texture-and-sampler pair, and a second colour
/// output — so a texel that comes back wrong names one mechanism rather than a
/// shading pipeline.
///
/// The reflection beside each is what a bundle would have carried. That is the
/// point of the split the section codec makes: a `GPUShaderModule` answers no
/// question about its own bindings, so the group and binding numbers arrive
/// beside the code, and a test can state them as easily as a packer can.
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_webgpu/src/webgpu_bundle_section.dart';

/// Where the quad goes and how big it is: `xy` is the offset in clip space and
/// `zw` the scale, so a test can put the same four vertices in the top half of
/// a target or across the whole of it.
///
/// The member is called `bounds` and was called `where`, which WGSL reserves.
/// A reserved word is not a compile error a backend meets anywhere else: the
/// module is created, the failure arrives at the first pipeline built from it
/// as "invalid due to a previous error", and the line number is only in
/// `getCompilationInfo`. `WebGpuDevice` asks for it on every stage it compiles
/// because of this, which is a good use for a mistake in a test.
const String _quadVertex = '''
struct Placement {
  bounds : vec4<f32>,
};

@group(0) @binding(0) var<uniform> placement : Placement;

struct Varyings {
  @builtin(position) position : vec4<f32>,
  @location(0) uv : vec2<f32>,
};

@vertex
fn main(
  @location(0) position : vec2<f32>,
  @location(1) uv : vec2<f32>,
) -> Varyings {
  var out : Varyings;
  out.position = vec4<f32>(
    position * placement.bounds.zw + placement.bounds.xy, 0.0, 1.0);
  out.uv = uv;
  return out;
}
''';

/// The palette, tinted. One colour attachment.
const String _quadFragment = '''
struct Tint {
  colour : vec4<f32>,
};

@group(0) @binding(1) var<uniform> tint : Tint;
@group(0) @binding(2) var paletteSampler : sampler;
@group(0) @binding(3) var palette : texture_2d<f32>;

@fragment
fn main(@location(0) uv : vec2<f32>) -> @location(0) vec4<f32> {
  return textureSample(palette, paletteSampler, uv) * tint.colour;
}
''';

/// The tint alone, written to two colour attachments — which is what a blend
/// equation per attachment needs something to blend.
const String _quadFragmentPair = '''
struct Tint {
  colour : vec4<f32>,
};

@group(0) @binding(1) var<uniform> tint : Tint;

struct Targets {
  @location(0) first : vec4<f32>,
  @location(1) second : vec4<f32>,
};

@fragment
fn main(@location(0) uv : vec2<f32>) -> Targets {
  var out : Targets;
  out.first = tint.colour;
  out.second = tint.colour;
  return out;
}
''';

/// A cube sampled by direction, which is what the sky pass does and what
/// `supportsCubeTextures` answering true has to mean.
///
/// The left half of the quad looks down +X and the right half down −X — the
/// first two faces in the order `createCubeTextureFromPixels` documents, so a
/// table with two entries transposed comes back the wrong way round rather than
/// merely different.
const String _quadFragmentCube = '''
struct Tint {
  colour : vec4<f32>,
};

@group(0) @binding(1) var<uniform> tint : Tint;
@group(0) @binding(2) var skySampler : sampler;
@group(0) @binding(3) var sky : texture_cube<f32>;

@fragment
fn main(@location(0) uv : vec2<f32>) -> @location(0) vec4<f32> {
  let towards = vec3<f32>(select(-1.0, 1.0, uv.x < 0.5), 0.0, 0.0);
  return textureSample(sky, skySampler, towards) * tint.colour;
}
''';

const WebGpuBlockMember _oneVector = WebGpuBlockMember(
  name: 'value',
  offsetInBytes: 0,
  sizeInBytes: 16,
);

/// The three stages, as a bundle's WebGPU section would have decoded.
final WebGpuSectionStages quadStages = (
  vertex: <String, WebGpuStage>{
    'QuadVertex': const WebGpuStage(
      wgsl: _quadVertex,
      attributes: <WebGpuAttribute>[
        WebGpuAttribute(
          name: 'position',
          location: 0,
          format: VertexFormat.float32x2,
        ),
        WebGpuAttribute(
          name: 'uv',
          location: 1,
          format: VertexFormat.float32x2,
        ),
      ],
      blocks: <WebGpuBlock>[
        WebGpuBlock(
          name: 'Placement',
          group: 0,
          binding: 0,
          sizeInBytes: 16,
          members: <WebGpuBlockMember>[_oneVector],
        ),
      ],
      samplers: <WebGpuSampler>[],
    ),
  },
  fragment: <String, WebGpuStage>{
    'QuadFragment': const WebGpuStage(
      wgsl: _quadFragment,
      attributes: <WebGpuAttribute>[],
      blocks: <WebGpuBlock>[
        WebGpuBlock(
          name: 'Tint',
          group: 0,
          binding: 1,
          sizeInBytes: 16,
          members: <WebGpuBlockMember>[_oneVector],
        ),
      ],
      samplers: <WebGpuSampler>[
        WebGpuSampler(
          name: 'palette',
          group: 0,
          textureBinding: 3,
          samplerBinding: 2,
          dimension: WebGpuTextureDimension.twoDimensional,
        ),
      ],
    ),
    'QuadFragmentCube': const WebGpuStage(
      wgsl: _quadFragmentCube,
      attributes: <WebGpuAttribute>[],
      blocks: <WebGpuBlock>[
        WebGpuBlock(
          name: 'Tint',
          group: 0,
          binding: 1,
          sizeInBytes: 16,
          members: <WebGpuBlockMember>[_oneVector],
        ),
      ],
      samplers: <WebGpuSampler>[
        WebGpuSampler(
          name: 'sky',
          group: 0,
          textureBinding: 3,
          samplerBinding: 2,
          dimension: WebGpuTextureDimension.cube,
        ),
      ],
    ),
    'QuadFragmentPair': const WebGpuStage(
      wgsl: _quadFragmentPair,
      attributes: <WebGpuAttribute>[],
      blocks: <WebGpuBlock>[
        WebGpuBlock(
          name: 'Tint',
          group: 0,
          binding: 1,
          sizeInBytes: 16,
          members: <WebGpuBlockMember>[_oneVector],
        ),
      ],
      samplers: <WebGpuSampler>[],
    ),
  },
);

/// Four vertices of a unit quad, wound counter-clockwise in clip space with y
/// up — the winding every mesh in this engine has.
///
/// [stride] is how many bytes apart the elements sit. Sixteen is the packed
/// layout the vertex stage's own reflection derives; anything larger is a
/// padded buffer, and the pair of them is what asks whether the pipeline cache
/// keys on the layout.
ByteData quadVertices({int stride = 16}) {
  final bytes = ByteData(stride * 4);
  const List<List<double>> corners = <List<double>>[
    <double>[-1, -1, 0, 1],
    <double>[1, -1, 1, 1],
    <double>[1, 1, 1, 0],
    <double>[-1, 1, 0, 0],
  ];
  for (var i = 0; i < 4; i++) {
    for (var f = 0; f < 4; f++) {
      bytes.setFloat32(i * stride + f * 4, corners[i][f], Endian.little);
    }
  }
  return bytes;
}

/// Two triangles over [quadVertices], as sixteen-bit indices.
///
/// Six of them is twelve bytes, which is not a multiple of four — the case
/// `gpuWritableBytes` and the frame arena both round up, and the smallest draw
/// there is.
ByteData quadIndices() {
  final bytes = ByteData(12);
  const List<int> indices = <int>[0, 1, 2, 0, 2, 3];
  for (var i = 0; i < 6; i++) {
    bytes.setUint16(i * 2, indices[i], Endian.little);
  }
  return bytes;
}

/// The whole target, at the offset and scale the vertex stage multiplies by.
Float32List placedAt({
  double x = 0,
  double y = 0,
  double width = 1,
  double height = 1,
}) => Float32List.fromList(<double>[x, y, width, height]);

/// A colour, as the fragment stage's tint block wants it.
Float32List tinted(double r, double g, double b, double a) =>
    Float32List.fromList(<double>[r, g, b, a]);
