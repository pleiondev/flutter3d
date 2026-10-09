/// Shaders a plugin brings as source: built where the backend compiles at
/// run time, refused with a sentence where it does not, and switched off
/// rather than failing the plugin.
///
///     dart test test/runtime_shaders_test.dart
///
/// The WebGL2 bundle is translated against the engine's real GLSL headers,
/// read off disk the way the build reads them; the device is a stand-in that
/// hands back a library, since nothing here draws. Each test names the
/// mutation that would defeat it.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart' show Renderer;
import 'package:flutter3d_hardware/backend.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart' show FakeBackend;
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_plugin_runtime/flutter3d_plugin_runtime.dart';
import 'package:flutter3d_shaders/compile.dart' show loadShaders;
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
_shaders(String backend, {Map<String, String>? engine}) {
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
      expect(RuntimeBackends.normalize(null), isNull);
    });
  });
}
