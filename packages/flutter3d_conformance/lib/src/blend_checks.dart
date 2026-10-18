/// The blend constant, on a backend that has one and on a backend that has not.
///
/// `PassEncoder.setBlendColor` is the only member of the HAL whose sole caller
/// is this file, and the reason is the failure it ends. Four [BlendFactor]
/// values read a blend constant; for as long as nothing could set one, the
/// software rasteriser threw, and the two hardware backends multiplied by their
/// own untouched default — transparent black — so the term evaluated to zero
/// and the frame came out a plausible picture with a term missing from it. No
/// error, no log line, nothing to notice.
///
/// So the check has two halves and no way to be silent about either. A backend
/// that lists `DeviceFeature.blendConstant` has to show the
/// constant arriving at the blend; one without it has to refuse, from
/// both the setter and from `setBlend` handed a state that names the factor.
library;

import 'dart:typed_data';

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show LinearColor, UnsupportedCapabilityException;
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:vector_math/vector_math.dart';

import '../flutter3d_conformance.dart';

const int _size = 8;

/// The blend constant reaches the blend, or the backend refuses it outright.
///
/// The equation is `source × CONSTANT_COLOR + destination × zero`, drawn in
/// white over a cleared target: what lands is the constant itself, one channel
/// at a time, so a backend that ignores the constant paints white and a backend
/// that never set one paints black. Both are a wrong picture with no error, and
/// both are what the two hardware backends drew before this existed.
///
/// Then a second pass with the same equation and **no** `setBlendColor` at all,
/// which must paint black: the constant is pass state and starts at transparent
/// black however the pass before it left the context.
///
/// Mutations watched go red:
///
///  * `CpuEncoder._factor`, `BlendFactor.blendColor => 1.0` instead of `bc` —
///    the centre comes back (255, 255, 255) and the constant is reported as
///    ignored;
///  * `WebGlEncoder.setBlendColor` made a no-op — the centre comes back
///    (0, 0, 0), which is the term lost rather than the factor mistaken, and
///    the message tells the two apart;
///  * `WebGlEncoder`'s constructor, the `_gl.blendColor(0, 0, 0, 0)` reset
///    deleted — the second pass inherits the first's (153, 51, 204) and the
///    "starts at transparent black" assertion names it.
Future<void> checkBlendColorReachesTheBlend(GraphicsDevice device) async {
  final vertex = device.shaders['DebugLineVertex'];
  final fragment = device.shaders['DebugLine'];
  require(
    vertex != null && fragment != null,
    'the debug-line stages are missing, so this cannot draw a flat colour',
  );

  // Two thirds and one third: values a byte carries exactly enough of to tell
  // them apart from each other, from zero and from one.
  // Its alpha is the alpha pair's constant, in every channel.
  const constant = LinearColor(0.6, 0.2, 0.8, 0.4);

  // Only the source term survives, and only through the constant.
  const equation = BlendState(
    sourceColorFactor: BlendFactor.blendColor,
    destinationColorFactor: BlendFactor.zero,
    sourceAlphaFactor: BlendFactor.one,
    destinationAlphaFactor: BlendFactor.zero,
  );

  if (!device.features.has(DeviceFeature.blendConstant)) {
    _refusesTheConstant(device, equation, constant);
    return;
  }

  final drawn = await _centerOf(
    device,
    vertex: vertex!,
    fragment: fragment!,
    equation: equation,
    constant: constant,
  );
  require(
    (drawn[0] - 153).abs() <= 4 &&
        (drawn[1] - 51).abs() <= 4 &&
        (drawn[2] - 204).abs() <= 4,
    'a white draw blended through BlendFactor.blendColor against a constant of '
    '(0.6, 0.2, 0.8) should have left (153, 51, 204); the centre came back '
    '$drawn. White means the constant was ignored and the factor treated as '
    'one; black means setBlendColor never reached the blend at all.',
  );

  final inherited = await _centerOf(
    device,
    vertex: vertex,
    fragment: fragment,
    equation: equation,
    // The pass says nothing about the constant, so the constant is zero and
    // the draw contributes nothing.
    constant: null,
  );
  require(
    inherited[0] < 8 && inherited[1] < 8 && inherited[2] < 8,
    'a pass that never called setBlendColor blended against a constant of '
    '$inherited rather than transparent black — it inherited the previous '
    'pass\'s. See PassEncoder.setBlendColor: the constant is pass state, and a '
    'backend whose setter is global context state has to put it back.',
  );

  // **The alpha pair, since 1.0.0-rc.1**: `CONSTANT_ALPHA` reads the
  // constant's alpha into every channel, behind a feature of its own,
  // because WebGPU has the colour pair and cannot form this one. Mutation:
  // map `BlendFactor.blendAlpha` to `CONSTANT_COLOR` on WebGL2, and the
  // centre comes back the constant's colour rather than (102, 102, 102).
  const alphaEquation = BlendState(
    sourceColorFactor: BlendFactor.blendAlpha,
    destinationColorFactor: BlendFactor.zero,
    sourceAlphaFactor: BlendFactor.one,
    destinationAlphaFactor: BlendFactor.zero,
  );
  if (!device.features.has(DeviceFeature.blendConstantAlpha)) {
    _refusesTheAlphaPair(device, alphaEquation);
    return;
  }
  final alpha = await _centerOf(
    device,
    vertex: vertex,
    fragment: fragment,
    equation: alphaEquation,
    constant: constant,
  );
  require(
    alpha.every((int channel) => (channel - 102).abs() <= 4),
    'a white draw blended through BlendFactor.blendAlpha against a constant '
    'whose alpha is 0.4 should have left (102, 102, 102); the centre came '
    'back $alpha. The constant\'s colour there means the alpha pair was '
    'read as the colour pair.',
  );
}

/// A backend with the colour pair and not the alpha pair refuses a state
/// naming the alpha pair by its own feature, `blendConstantAlpha`.
void _refusesTheAlphaPair(GraphicsDevice device, BlendState equation) {
  final pass = device.beginRenderPass(
    RenderPassDescriptor(
      colors: <ColorTarget>[
        ColorTarget(
          texture: device.createTexture(
            const RenderTargetDescriptor(
              width: _size,
              height: _size,
              format: TextureFormat.r8g8b8a8UNormInt,
            ),
          ),
        ),
      ],
    ),
  );
  try {
    DeviceFeature? refusedBy;
    try {
      pass.setBlend(equation);
    } on UnsupportedCapabilityException catch (refusal) {
      refusedBy = refusal.feature as DeviceFeature?;
    }
    require(
      refusedBy == DeviceFeature.blendConstantAlpha,
      'blend-constant-alpha is not listed and a BlendState naming '
      'BlendFactor.blendAlpha was ${refusedBy == null ? 'accepted' : 'refused as ${refusedBy.name}'}. '
      'A backend with the colour pair refuses the alpha pair by its own '
      'feature; see BlendState.checkFeatures.',
    );
  } finally {
    pass.submit();
  }
}

/// Draws one full-frame white triangle through [equation], having set
/// [constant] first when it is not null, and reads the centre pixel back.
Future<List<int>> _centerOf(
  GraphicsDevice device, {
  required ShaderHandle vertex,
  required ShaderHandle fragment,
  required BlendState equation,
  required LinearColor? constant,
}) async {
  final target = device.createTexture(
    const RenderTargetDescriptor(
      width: _size,
      height: _size,
      format: TextureFormat.r8g8b8a8UNormInt,
    ),
  );
  final pass = device.beginRenderPass(
    RenderPassDescriptor(
      colors: <ColorTarget>[
        ColorTarget(
          texture: target,
          loadAction: LoadAction.clear,
          // Opaque black, so the destination term is visible if it survives
          // the zero factor it was given.
          clearValue: ClearColor(0.0, 0.0, 0.0, 1.0),
        ),
      ],
    ),
  );
  pass
    ..setPrimitiveType(PrimitiveType.triangle)
    ..setCullMode(CullMode.none);
  if (constant != null) pass.setBlendColor(constant);
  pass
    ..setBlend(equation)
    ..bindPipeline(
      device.createPipelineFrom(
        PipelineDescriptor(vertex: vertex, fragment: fragment),
      ),
    )
    ..bindUniformBlock(vertex, 'LineInfo', <String, Float32List>{
      'view_projection': Float32List.fromList(Matrix4.identity().storage),
    })
    ..bindVertexData(
      ByteData.sublistView(
        Float32List.fromList(<double>[
          -1, -1, 0.5, 1, 1, 1, 1, //
          3, -1, 0.5, 1, 1, 1, 1,
          -1, 3, 0.5, 1, 1, 1, 1,
        ]),
      ),
      3,
    )
    ..bindIndexData(
      ByteData.sublistView(Uint16List.fromList(<int>[0, 1, 2])),
      IndexType.int16,
      3,
    )
    ..draw();
  pass.submit();

  final pixels = await device.readback(target);
  final at = ((_size ~/ 2) * _size + _size ~/ 2) * 4;
  return pixels.buffer.asUint8List().sublist(at, at + 3);
}

/// The other half of the rule: a backend with no constant refuses, from both
/// ends, rather than drawing the term as zero.
///
/// Asked without a draw, because there is nothing to look at — the point is
/// that neither call returns.
void _refusesTheConstant(
  GraphicsDevice device,
  BlendState equation,
  LinearColor constant,
) {
  final pass = device.beginRenderPass(
    RenderPassDescriptor(
      colors: <ColorTarget>[
        ColorTarget(
          texture: device.createTexture(
            const RenderTargetDescriptor(
              width: _size,
              height: _size,
              format: TextureFormat.r8g8b8a8UNormInt,
            ),
          ),
          loadAction: LoadAction.clear,
        ),
      ],
    ),
  );
  try {
    var refusedSetter = false;
    try {
      pass.setBlendColor(constant);
    } on UnsupportedCapabilityException {
      refusedSetter = true;
    } on UnsupportedError {
      refusedSetter = true;
    }
    require(
      refusedSetter,
      'blendConstant is not listed and setBlendColor was accepted anyway. A '
      'backend that cannot set the constant has to say so — accepting the call '
      'and dropping it leaves the caller believing a value it will never see, '
      'which is the silence DeviceFeature.blendConstant exists to break.',
    );

    var refusedState = false;
    try {
      pass.setBlend(equation);
    } on UnsupportedCapabilityException {
      refusedState = true;
    } on UnsupportedError {
      refusedState = true;
    }
    require(
      refusedState,
      'blendConstant is not listed and a BlendState naming '
      'BlendFactor.blendColor was accepted anyway. The term will be multiplied '
      'by a constant nothing can set — transparent black — so the draw loses '
      'it and paints a plausible picture with no error. See '
      'BlendState.usesBlendColor.',
    );
  } finally {
    // Submitted whatever happened: an unsubmitted pass is a native command
    // buffer nobody ends, and this one drew nothing worth keeping either way.
    pass.submit();
  }
}
