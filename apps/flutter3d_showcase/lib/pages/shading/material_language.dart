/// The material expression language: a small GLSL-flavoured source parsed
/// into a tree that either emits a `.frag` or is evaluated directly.
///
/// Quoted by `material_language.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class MaterialLanguageDemo extends ShowcaseDemo {
  late final MaterialProgram _specialised;
  late final String _glsl;
  late final List<double> _shaded;

  static const double _albedo0 = 0.2;
  static const double _albedo1 = 0.2;
  static const double _albedo2 = 0.25;
  static const double _alpha = 1.0;
  static const double _nDotV = 0.2;
  static const double _rimPower = 4.0;

  @override
  Scene build(DemoContext context) {
    // #region source
    const String source = '''
material RimLight {
  param float rimPower = 2.0;
  param vec3 rimColor = vec3(0.2, 0.6, 1.0);

  fragment {
    let facing = clamp(nDotV, 0.0, 1.0);
    let rim = pow(1.0 - facing, rimPower);
    return vec4(albedo + rimColor * rim, alpha);
  }
}
''';
    final MaterialProgram program = parseMaterial(source);
    // #endregion source

    // #region specialise
    _specialised = specialiseMaterial(
      program,
      const MaterialVariant('RimLight_sharp', {
        'rimPower': <double>[_rimPower],
      }),
    );
    _glsl = emitMaterialFragment(_specialised);
    // #endregion specialise

    // #region evaluate
    _shaded = evaluateMaterial(
      _specialised,
      MaterialSurfaceValues(
        inputs: <String, List<double>>{
          'albedo': <double>[_albedo0, _albedo1, _albedo2],
          'alpha': <double>[_alpha],
          'nDotV': <double>[_nDotV],
        },
        sample: (MaterialTextureSlot slot, double u, double v) =>
            throw StateError('this material declares no texture'),
      ),
    );
    // #endregion evaluate

    return Scene()
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            SphereShape(segments: 40, rings: 20).build(),
          ),
          Material(baseColor: Vector4(0.8, 0.65, 0.35, 1.0), roughness: 0.5),
          name: 'ball',
        ),
      )
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.4, -0.7, -0.6)),
      );
  }

  // #region report
  String _report() =>
      'inputs this body reads: ${_specialised.inputsUsed.toList()..sort()}\n\n'
      'evaluated at nDotV=$_nDotV: $_shaded\n\n'
      '$_glsl';
  // #endregion report

  @override
  Widget? customBody(BuildContext buildContext, DemoContext context) =>
      Container(
        color: const Color(0xFF14161A),
        padding: const EdgeInsets.all(24),
        alignment: Alignment.topLeft,
        child: SingleChildScrollView(
          child: DefaultTextStyle(
            style: const TextStyle(
              color: Color(0xFFE8E8EC),
              fontSize: 13,
              fontFamily: 'monospace',
            ),
            child: Text(_report()),
          ),
        ),
      );

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    if (!_specialised.inputsUsed.containsAll(<String>[
      'albedo',
      'alpha',
      'nDotV',
    ])) {
      throw StateError('the body should read albedo, alpha and nDotV');
    }
    final double facing = _nDotV.clamp(0.0, 1.0);
    final double rim = math.pow(1.0 - facing, _rimPower).toDouble();
    final List<double> expected = <double>[
      _albedo0 + 0.2 * rim,
      _albedo1 + 0.6 * rim,
      _albedo2 + 1.0 * rim,
      _alpha,
    ];
    for (var i = 0; i < expected.length; i++) {
      if ((_shaded[i] - expected[i]).abs() > 1e-9) {
        throw StateError('evaluateMaterial disagrees with the hand-worked sum');
      }
    }
    if (!_glsl.contains('void main()')) {
      throw StateError('the emitted fragment has no entry point');
    }
    if (frame.drawCalls < 1) {
      throw StateError('the ball was not drawn');
    }
    // #endregion check
  }
}
