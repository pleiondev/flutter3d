/// Shaders a plugin brings as source: built where the backend compiles at
/// run time, refused with a sentence where it does not, and switched off
/// rather than failing the plugin.
///
///     dart test test/data_plugin/runtime_shaders_test.dart
///
/// The WebGL2 bundle is translated against the engine's real GLSL headers,
/// read off disk the way the build reads them; the device is a stand-in that
/// hands back a library, since nothing here draws. Each test names the
/// mutation that would defeat it.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/data_plugins.dart';
import 'package:flutter3d_core/flutter3d_core.dart' show Renderer;
import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show UnsupportedCapabilityException;
import 'package:flutter3d_hardware/backend.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart' show FakeBackend;
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_shaders/compile.dart' show loadShaders;
import 'package:flutter3d_shaders/flutter3d_shaders.dart'
    show MissingShaderStageException;
import 'package:test/test.dart';

const String _glow = '''
material Glow {
  param vec3 tint = vec3(1.0, 0.6, 0.2);
  fragment {
    return vec4(albedo * tint, alpha);
  }
}
''';

/// A library the stand-in device hands back for a bundle.
final class _Library with ShaderLibrary, LoadedShaderLibrary {
  _Library(this.bundle);

  final ShaderBundle bundle;

  @override
  String get name => bundle.name;

  @override
  ShaderHandle? operator [](String name) => bundle.names.contains(name)
      ? wrapShader(backend: Object(), name: name)
      : null;

  @override
  void refresh(ByteData bytes) {}
}

/// A [RuntimeShaders] over a stand-in device, recording what reaches the
/// renderer.
({
  RuntimeShaders shaders,
  List<ShaderLibrary> added,
  List<ShaderLibrary> removed,
})
_shaders(
  String backend, {
  Map<String, String>? engine,
  Future<ByteData?> Function(String material)? prebuilt,
}) {
  final added = <ShaderLibrary>[];
  final removed = <ShaderLibrary>[];
  return (
    shaders: RuntimeShaders(
      backend: backend,
      loadShaders: (bytes) async => _Library(ShaderBundle.decode(bytes)),
      addMaterials: (library) {
        added.add(library);
        return Registration(() => removed.add(library));
      },
      engineSources: engine,
      prebuilt: prebuilt,
    ),
    added: added,
    removed: removed,
  );
}

void main() {
  group('a material as a bundle', () {
    test('the software backend gets the source, and nothing compiled', () {
      // Mutation: emit GLSL for every backend. The software rasteriser has
      // no GLSL to run and evaluates the material section; a bundle without
      // it is refused there.
      final bundle = runtimeMaterialBundle(
        _glow,
        backend: 'cpu',
        from: 'glow.f3dmat',
      );
      expect(bundle.names, <String>['Glow']);
      expect(bundle.sections.keys, <String>[ShaderBundle.materialSection]);
      expect(decodeMaterialSection(bundle), <String, String>{'Glow': _glow});
    });

    test('WebGL2 gets GLSL ES translated against the engine\'s headers', () {
      // Mutation: hand the browser the emitter's desktop GLSL. It names
      // `#version 460` and the engine's headers by include, and WebGL2
      // links neither.
      final bundle = runtimeMaterialBundle(
        _glow,
        backend: 'WebGL2',
        from: 'glow.f3dmat',
        engineSources: loadShaders().sources,
      );
      expect(
        bundle.sections.keys,
        containsAll(<String>[
          ShaderBundle.webglSection,
          ShaderBundle.materialSection,
        ]),
      );
      final glsl = String.fromCharCodes(
        bundle.sections[ShaderBundle.webglSection]!.buffer.asUint8List(),
      );
      expect(glsl, contains('300 es'));
      expect(glsl, isNot(contains('#include')));
      expect(
        () =>
            runtimeMaterialBundle(_glow, backend: 'webgl', from: 'glow.f3dmat'),
        throwsA(
          isA<RuntimeShadersException>().having(
            (e) => e.message,
            'message',
            contains('engineSources'),
          ),
        ),
        reason: 'without the headers there is nothing to translate against',
      );
    });

    test('Impeller is refused, and WebGPU with no host, each saying why', () {
      // Mutation: hand Impeller the GLSL. It loads compiled stages only,
      // and the bundle would be refused by the device with a sentence about
      // a missing section rather than about compiling ahead of time.
      expect(
        () => runtimeMaterialBundle(_glow, backend: 'Impeller', from: 'g'),
        throwsA(
          isA<RuntimeShadersException>().having(
            (e) => e.message,
            'message',
            contains('impellerc'),
          ),
        ),
      );
      // `material_wgsl_test.dart` builds it with one.
      expect(
        () => runtimeMaterialBundle(_glow, backend: 'webgpu', from: 'g'),
        throwsA(
          isA<RuntimeShadersException>().having(
            (e) => e.message,
            'message',
            contains('webGpuHost'),
          ),
        ),
      );
    });

    test('a material that does not parse is refused with its line', () {
      // Mutation: refuse it without the place. An author editing a mod's
      // material needs the line, as the build gives it.
      expect(
        () => runtimeMaterialBundle(
          'material Broken {\n  fragment {\n    return wobble;\n  }\n}\n',
          backend: 'cpu',
          from: 'broken.f3dmat',
        ),
        throwsA(
          isA<RuntimeShadersException>().having(
            (e) => e.message,
            'message',
            startsWith('broken.f3dmat:3:'),
          ),
        ),
      );
    });
  });

  group('the registry', () {
    test(
      'a material arrives in the renderer, and leaves with its plugin',
      () async {
        // Mutation: drop the cancel's removeMaterials. Switching the plugin
        // off would leave its material layered over the engine's.
        final cpu = _shaders('cpu');
        final registration = cpu.shaders.addMaterial(
          _glow,
          from: 'glow.f3dmat',
        );
        await cpu.shaders.settled;
        expect(cpu.added, hasLength(1));
        expect(cpu.added.single['Glow'], isNotNull);
        expect(cpu.shaders.lighting('Glow')?.shaderName, 'Glow');
        expect(cpu.shaders.statuses, <String, String?>{'Glow': null});
        registration.cancel();
        expect(cpu.removed, <ShaderLibrary>[cpu.added.single]);
        expect(cpu.shaders.lighting('Glow'), isNull);
        expect(cpu.shaders.statuses, isEmpty);
      },
    );

    test('on Impeller the material is off, with the reason, and the rest '
        'installs', () async {
      // Mutation: throw the refusal. One material a backend cannot compile
      // would take the whole plugin down, which decision 15 says it may not.
      final impeller = _shaders('impeller');
      impeller.shaders.addMaterial(_glow, from: 'glow.f3dmat');
      await impeller.shaders.settled;
      expect(impeller.added, isEmpty);
      expect(impeller.shaders.statuses['Glow'], contains('impellerc'));
      expect(
        () => impeller.shaders.addMaterial('material {', from: 'bad.f3dmat'),
        throwsA(isA<PluginException>()),
        reason: 'a source that does not parse is wrong on every backend',
      );
      // D19: the refusal is typed, and names the stage.
      expect(
        impeller.shaders.refusals['Glow'],
        isA<MissingShaderStageException>().having(
          (e) => e.stage,
          'stage',
          'Glow',
        ),
      );
    });

    test('on Impeller the build\'s compiled bundle is found by name', () async {
      // Mutation: refuse on Impeller whatever the build wrote. Every plugin
      // material is compiled into the project for this SDK (D19).
      final asked = <String>[];
      final impeller = _shaders(
        'impeller',
        prebuilt: (material) async {
          asked.add(material);
          return ShaderBundle(
            name: material,
            sdk: '3.13.0',
            stages: <ShaderBundleStage>[
              ShaderBundleStage(material, fragment: true),
            ],
          ).encode();
        },
      );
      impeller.shaders.addMaterial(_glow, from: 'glow.f3dmat');
      await impeller.shaders.settled;
      expect(asked, <String>['Glow']);
      expect(impeller.added, hasLength(1));
      expect(impeller.shaders.statuses['Glow'], isNull);
      expect(impeller.shaders.lighting('Glow'), isNotNull);
    });

    test('on Impeller a material the build did not write is refused by '
        'name', () async {
      final impeller = _shaders('impeller', prebuilt: (_) async => null);
      impeller.shaders.addMaterial(_glow, from: 'glow.f3dmat');
      await impeller.shaders.settled;
      expect(impeller.added, isEmpty);
      final refusal = impeller.shaders.refusals['Glow']!;
      expect(refusal, isA<MissingShaderStageException>());
      expect(refusal.message, contains('the build did not write it'));
      expect(impeller.shaders.statuses['Glow'], refusal.message);
    });

    test('a render step from data that samples a texture of its own is '
        'refused, saying so', () {
      // Mutation: drop the refusal and the step draws with `lut_texture`
      // unbound: WebGPU throws at the next frame, Impeller crashes.
      final steps = Renderer.create(device: FakeBackend()).renderSteps;
      final cpu = _shaders('cpu');
      cpu.shaders.addRenderStep(
        RuntimeRenderStep(
          name: 'glow.grade',
          anchor: RenderAnchor.afterTonemap,
          present: true,
          shaders: const <String, String>{
            RuntimeRenderStep.materialStage: '''
f3dmat 3
fullscreen Grade {
  texture lut = lut_texture;
  fragment { return vec4(sample(scene, uv).rgb * sample(lut, uv).r, 1.0); }
}
''',
          },
        ),
        steps,
      );
      expect(
        cpu.shaders.statuses['glow.grade'],
        allOf(contains('lut'), contains('FullscreenEffect.material')),
      );
    });

    test('a render step is the renderer\'s, and off where it has no stage', () {
      // Mutation: skip the step when the backend has no stage. A plugin
      // list could not say why the haze is not drawn, and the frame would
      // not report it switched off.
      final steps = Renderer.create(device: FakeBackend()).renderSteps;
      final cpu = _shaders('cpu');
      final registration = cpu.shaders.addRenderStep(
        RuntimeRenderStep(
          name: 'glow.haze',
          anchor: RenderAnchor.afterTonemap,
          present: true,
          shaders: const <String, String>{'webgl': 'void main() {}'},
        ),
        steps,
      );
      expect(steps.named('glow.haze'), isNotNull);
      expect(steps.nodesAt(RenderAnchor.afterTonemap), <String>['glow.haze']);
      expect(cpu.shaders.statuses['glow.haze'], contains('cpu'));
      registration.cancel();
      expect(steps.named('glow.haze'), isNull);
      expect(steps.nodesAt(RenderAnchor.afterTonemap), isEmpty);
      expect(
        () => cpu.shaders.addRenderStep(
          RuntimeRenderStep(
            name: 'glow.haze',
            anchor: RenderAnchor.afterTonemap,
            shaders: const <String, String>{'webgl': ''},
            needs: const <String>['sparkle'],
          ),
          steps,
        ),
        throwsA(isA<PluginException>()),
        reason: 'a need that is not one of the renderer\'s steps is refused',
      );
    });

    test('backend names are one name each', () {
      // Mutation: compare names as written. `WebGL2` from a device and
      // `webgl` in a manifest would be two backends.
      expect(RuntimeBackends.normalize('WebGL2'), RuntimeBackends.webgl);
      expect(RuntimeBackends.normalize('Impeller'), RuntimeBackends.impeller);
      expect(RuntimeBackends.normalize('WebGPU'), RuntimeBackends.webgpu);
      expect(RuntimeBackends.normalize('cpu'), RuntimeBackends.cpu);
      expect(
        RuntimeBackends.normalize('the software rasteriser'),
        RuntimeBackends.cpu,
      );
      expect(RuntimeBackends.normalize(null), isNull);
    });

    test('a backend from outside is its own id, matched exactly', () {
      // Mutation: match by prefix again, and a Dawn backend from outside is
      // taken for the engine's WebGPU, and a Vulkan one is lower-cased past
      // the compiler registered under its id.
      expect(RuntimeBackends.normalize('webgpu-dawn'), 'webgpu-dawn');
      expect(RuntimeBackends.normalize('Vulkan'), 'Vulkan');
      expect(RuntimeBackends.normalize('software-gl'), 'software-gl');
    });
  });

  group('a compute stage', () {
    const ripples = '''
f3dmat 2
compute Ripples {
  kernel { return vec4(uv, 0.0, 1.0); }
}
''';

    test('is its lowered kernel where the backend computes', () {
      // Mutation: refuse it as before, and a plugin's computed texture
      // never runs on WebGPU or the software backend.
      for (final backend in <String>['webgpu', 'cpu']) {
        final bundle = runtimeMaterialBundle(
          ripples,
          backend: backend,
          from: 'ripples.f3dmat',
        );
        expect(bundle.stages.single.kind, ShaderStageKind.compute);
        expect(
          decodeKernelSection(bundle)['Ripples'],
          startsWith('kernel 1\n'),
        );
      }
    });

    test('is refused by naming compute where the backend has none', () {
      for (final backend in <String>['impeller', 'WebGL2']) {
        expect(
          () => runtimeMaterialBundle(
            ripples,
            backend: backend,
            from: 'ripples.f3dmat',
          ),
          throwsA(
            isA<UnsupportedCapabilityException>().having(
              (e) => e.feature,
              'feature',
              DeviceFeature.compute,
            ),
          ),
        );
      }
    });
  });
}
