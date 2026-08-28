/// Index and vertex formats: how a mesh's bytes are shaped, translated to and
/// from flutter_gpu's vocabulary.
library;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;

extension IndexTypeToGpu on IndexType {
  gpu.IndexType toGpu() => switch (this) {
    IndexType.int16 => gpu.IndexType.int16,
    IndexType.int32 => gpu.IndexType.int32,
  };
}

extension IndexTypeFromGpu on gpu.IndexType {
  IndexType toEngine() => switch (this) {
    gpu.IndexType.int16 => IndexType.int16,
    gpu.IndexType.int32 => IndexType.int32,
  };
}

extension VertexFormatToGpu on VertexFormat {
  gpu.VertexFormat toGpu() => switch (this) {
    VertexFormat.float32 => gpu.VertexFormat.float32,
    VertexFormat.float32x2 => gpu.VertexFormat.float32x2,
    VertexFormat.float32x3 => gpu.VertexFormat.float32x3,
    VertexFormat.float32x4 => gpu.VertexFormat.float32x4,
    VertexFormat.uint32 => gpu.VertexFormat.uint32,
    VertexFormat.uint32x2 => gpu.VertexFormat.uint32x2,
    VertexFormat.uint32x3 => gpu.VertexFormat.uint32x3,
    VertexFormat.uint32x4 => gpu.VertexFormat.uint32x4,
    VertexFormat.sint32 => gpu.VertexFormat.sint32,
    VertexFormat.sint32x2 => gpu.VertexFormat.sint32x2,
    VertexFormat.sint32x3 => gpu.VertexFormat.sint32x3,
    VertexFormat.sint32x4 => gpu.VertexFormat.sint32x4,
  };
}

extension VertexFormatFromGpu on gpu.VertexFormat {
  VertexFormat toEngine() => switch (this) {
    gpu.VertexFormat.float32 => VertexFormat.float32,
    gpu.VertexFormat.float32x2 => VertexFormat.float32x2,
    gpu.VertexFormat.float32x3 => VertexFormat.float32x3,
    gpu.VertexFormat.float32x4 => VertexFormat.float32x4,
    gpu.VertexFormat.uint32 => VertexFormat.uint32,
    gpu.VertexFormat.uint32x2 => VertexFormat.uint32x2,
    gpu.VertexFormat.uint32x3 => VertexFormat.uint32x3,
    gpu.VertexFormat.uint32x4 => VertexFormat.uint32x4,
    gpu.VertexFormat.sint32 => VertexFormat.sint32,
    gpu.VertexFormat.sint32x2 => VertexFormat.sint32x2,
    gpu.VertexFormat.sint32x3 => VertexFormat.sint32x3,
    gpu.VertexFormat.sint32x4 => VertexFormat.sint32x4,
  };
}

extension VertexStepModeToGpu on VertexStepMode {
  gpu.VertexStepMode toGpu() => switch (this) {
    VertexStepMode.vertex => gpu.VertexStepMode.vertex,
    VertexStepMode.instance => gpu.VertexStepMode.instance,
  };
}

extension VertexStepModeFromGpu on gpu.VertexStepMode {
  VertexStepMode toEngine() => switch (this) {
    gpu.VertexStepMode.vertex => VertexStepMode.vertex,
    gpu.VertexStepMode.instance => VertexStepMode.instance,
  };
}

/// The whole layout, which is a structure rather than an enum and so is
/// translated by construction rather than by a `switch`.
extension VertexLayoutSpecToGpu on VertexLayoutSpec {
  gpu.VertexLayout toGpu() => gpu.VertexLayout(
    buffers: <gpu.VertexBuffer>[
      for (final buffer in buffers)
        gpu.VertexBuffer(
          strideInBytes: buffer.strideInBytes,
          stepMode: buffer.stepMode.toGpu(),
          attributes: <gpu.VertexAttribute>[
            for (final attribute in buffer.attributes)
              gpu.VertexAttribute(
                name: attribute.name,
                format: attribute.format.toGpu(),
                offsetInBytes: attribute.offsetInBytes,
              ),
          ],
        ),
    ],
  );
}
