/// A device, a target and two stages small enough to reason about, for the
/// tests of the 1.0 surface.
library;

import 'dart:typed_data';

import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:vector_math/vector_math.dart';

/// Clip position straight from the vertex — `x, y, z` with `w` one — moved
/// right by [instanceShift] in clip space per instance.
final class PositionVertex extends CpuVertexShaderByIndex {
  const PositionVertex({this.instanceShift = 0.0});

  final double instanceShift;

  @override
  int get varyingCount => 0;

  @override
  Vector4 run(Float32List a, ShaderBindings b, Float32List v) =>
      runAt(0, 0, a, b, v);

  @override
  Vector4 runAt(
    int vertexIndex,
    int instanceIndex,
    Float32List a,
    ShaderBindings b,
    Float32List v,
  ) => Vector4(a[0] + instanceShift * instanceIndex, a[1], a[2], 1);
}

/// One colour everywhere, and [second] as the dual-source output when set.
final class SolidFragment extends CpuFragmentShader {
  SolidFragment(this.color, {this.second});

  final Vector4 color;
  final Vector4? second;

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    c.source1 = second;
    return color;
  }
}

/// A [width] × [height] float target, optionally a `d32FloatS8UInt` depth
/// beside it, and a device whose library holds [stages] beside the two
/// above.
final class Rig {
  Rig({
    this.width = 4,
    this.height = 1,
    Vector4? color,
    Vector4? second,
    double instanceShift = 0.5,
    bool withDepth = false,
    Iterable<DeviceFeature> withhold = const <DeviceFeature>[],
    Map<String, CpuStage> stages = const <String, CpuStage>{},
  }) : device = CpuDevice(
         width: width,
         height: height,
         withhold: withhold,
         shaders: CpuShaderLibrary(<String, CpuStage>{
           'Position': CpuStage.vertex(
             PositionVertex(instanceShift: instanceShift),
           ),
           'Solid': CpuStage.fragment(
             SolidFragment(color ?? Vector4(1, 1, 1, 1), second: second),
           ),
           ...stages,
         }),
       ) {
    target = device.createTexture(
      RenderTargetDescriptor(
        width: width,
        height: height,
        format: TextureFormat.r32g32b32a32Float,
      ),
    );
    depth = withDepth
        ? device.createTexture(
            RenderTargetDescriptor(
              width: width,
              height: height,
              format: TextureFormat.d32FloatS8UInt,
            ),
          )
        : null;
  }

  final int width;
  final int height;
  final CpuDevice device;
  late final TextureHandle target;
  late final TextureHandle? depth;

  /// A pass over [target] cleared to [clear], with the rig's pipeline bound
  /// — [fragment] chooses the fragment stage — and depth writes on when
  /// there is a depth target.
  CommandEncoder pass({
    Vector4? clear,
    String fragment = 'Solid',
    QuerySet? occlusion,
    PassTimestampWrites? timestamps,
  }) {
    final depthTexture = depth;
    final pass = device.beginRenderPass(
      RenderPassDescriptor(
        colors: <ColorTarget>[
          ColorTarget(texture: target, clearValue: clear ?? Vector4.zero()),
        ],
        depth: depthTexture == null ? null : DepthTarget(texture: depthTexture),
        occlusionQuerySet: occlusion,
        timestampWrites: timestamps,
      ),
    );
    pass.bindPipeline(
      device.createPipeline(
        device.shaders['Position']!,
        device.shaders[fragment]!,
      ),
    );
    if (depthTexture != null) {
      pass
        ..setDepthWrite(enabled: true)
        ..setDepthCompare(CompareFunction.always);
    }
    return pass;
  }

  /// The target's floats.
  Float32List get pixels => device.readHdrPixels(target);

  /// Red at pixel [x] of row [y].
  double redAt(int x, [int y = 0]) => pixels[(y * width + x) * 4];

  /// The depth plane the passes wrote.
  Float32List get depthPlane => (depth!.backend as CpuTexture).depth!;
}

/// A quad over column [column] of a four-wide target, at depth [z]: four
/// corners and the six indices of its two triangles.
({ByteData vertices, ByteData indices}) columnQuad(
  int column, {
  double z = 0.5,
}) {
  final left = -1.0 + column * 0.5;
  final right = left + 0.5;
  return (
    vertices: ByteData.sublistView(
      Float32List.fromList(<double>[
        left, -1, z, //
        right, -1, z,
        left, 1, z,
        right, 1, z,
      ]),
    ),
    indices: ByteData.sublistView(Uint16List.fromList(<int>[0, 1, 2, 2, 1, 3])),
  );
}

/// One triangle covering the whole target, at depth [z].
ByteData fullScreen({double z = 0.5}) => ByteData.sublistView(
  Float32List.fromList(<double>[
    -1, -1, z, //
    3, -1, z,
    -1, 3, z,
  ]),
);
