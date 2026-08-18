/// That a lighting model can come from outside this package.
///
/// It was an enum, so the answer was no: six models, and the two properties a
/// UI asks about were derived by comparing against particular constants —
/// `this != unlit && this != normals`, `this == pbr`. Both were true of the six
/// that existed and wrong for any seventh, silently.
///
/// These tests are about the shape rather than about rendering. What they
/// prevent is the derivation coming back: it reads as harmless and is only
/// wrong for a model nobody had written yet.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('a model defined outside the engine', () {
    // What an application shipping its own bundle entry would write.
    const custom = LightingModel(
      'Velvet',
      'Velvet',
      usesMetallicRoughnessMap: false,
      usesMetallic: false,
    );

    test('is not obliged to be one of the built-ins', () {
      expect(LightingModel.builtIn.contains(custom), isFalse);
      expect(custom.shaderName, 'Velvet');
    });

    test('answers about its own parameters, not about which constant it is', () {
      // The derived version said yes here because the model was neither unlit
      // nor normals — an answer about identity dressed as an answer about the
      // shader.
      expect(custom.usesMaterialParameters, isTrue);
      expect(custom.usesMetallic, isFalse,
          reason: 'the old rule read `this == pbr`, so every custom model '
              'answered no by accident and a metallic one would have been '
              'wrong with no way to say otherwise');
    });

    test('can declare it does interpret metallic', () {
      const metal = LightingModel('Brushed', 'Brushed', usesMetallic: true);
      expect(metal.usesMetallic, isTrue);
    });
  });

  group('the built-ins keep the answers they had', () {
    test('unlit and normals ignore the material parameters', () {
      expect(LightingModel.unlit.usesMaterialParameters, isFalse);
      expect(LightingModel.normals.usesMaterialParameters, isFalse);
    });

    test('the lit models use them', () {
      for (final model in <LightingModel>[
        LightingModel.lambert,
        LightingModel.blinnPhong,
        LightingModel.pbr,
        LightingModel.toon,
      ]) {
        expect(model.usesMaterialParameters, isTrue, reason: model.label);
      }
    });

    test('only the physical model interprets metallic', () {
      for (final model in LightingModel.builtIn) {
        expect(model.usesMetallic, model == LightingModel.pbr,
            reason: model.label);
      }
    });

    test('every built-in has a distinct shader name', () {
      // The renderer caches pipelines by this name and the draw sort groups by
      // its hash. Two models sharing a name would share a pipeline, which is a
      // wrong picture rather than a slow one.
      final names = LightingModel.builtIn.map((m) => m.shaderName).toSet();
      expect(names.length, LightingModel.builtIn.length);
    });

    test('the pipeline group is a fixed number, not a run-dependent hash', () {
      // The draw sort keys on this. Dart does not promise String.hashCode is
      // the same from one run to the next, so using it made the order two
      // lighting models drew in vary between runs — which two goldens found at
      // 25% and 0.6% of their pixels. Pinning the literal values is the only
      // way to notice a change back.
      expect(LightingModel.unlit.pipelineGroup,
          _fnv1a6('Unlit'));
      expect(LightingModel.pbr.pipelineGroup, _fnv1a6('Pbr'));

      // And it depends on the name alone, so two models with the same shader
      // group together whoever built them.
      const same = LightingModel('Another name', 'Pbr');
      expect(same.pipelineGroup, LightingModel.pbr.pipelineGroup);
    });

    test('the group fits the six bits the sort key has for it', () {
      for (final model in LightingModel.builtIn) {
        expect(model.pipelineGroup, inInclusiveRange(0, 63), reason: model.label);
      }
    });

    test('a model sampling no maps cannot sample the metal-rough one', () {
      // The assert exists because Unlit sat in exactly that state — binding a
      // texture the compiled shader has no slot for — until a golden caught it.
      expect(
        () => LightingModel('Bad', 'Bad',
            usesMaterialMaps: false, usesMetallicRoughnessMap: true),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}


/// FNV-1a folded to six bits, computed here independently of the engine's copy.
///
/// A second implementation rather than a call to the first: a test that asks
/// the code under test what the answer is agrees with it by construction, and
/// would have agreed just as readily with `hashCode`.
int _fnv1a6(String name) {
  var hash = 0x811c9dc5;
  for (var i = 0; i < name.length; i++) {
    hash = ((hash ^ name.codeUnitAt(i)) * 0x01000193) & 0xFFFFFFFF;
  }
  return hash & 0x3F;
}
