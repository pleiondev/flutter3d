/// The sample plugin's points in the frame, drawn: the render checks of
/// `flutter3d_conformance_render` on the backends a VM can draw on.
///
///     dart test test/render_conformance_test.dart
///
/// **Two of the four, and which.** The software rasteriser draws the
/// pictures here, and a recording fake holds every point to its structure.
/// WebGL2 and WebGPU are Flutter packages that draw in a browser, and
/// Impeller draws through a Flutter GPU context only an application has;
/// each of the three runs the same `runPluginRenderConformance` from a suite
/// of its own once the plugin ships its stages compiled for it.
///
/// **The plugin's stages on this backend.** A plugin ships its lit model as
/// a bundle; this one is drawn through a software stage written in Dart
/// against the same names the material's slot table gives every backend
/// (`MaterialParams.gloss`, `Strands.tint` and `Strands.shift`, and the
/// texture `material_fur`), so what the check sees is the renderer binding
/// the table and this backend handing it over by name. Its decal stage has
/// the engine's decal interface, so it is the engine's software decal stage
/// under the plugin's name.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_conformance_render/flutter3d_conformance_render.dart';
import 'package:flutter3d_core/data_plugins.dart';
import 'package:flutter3d_core/flutter3d_core.dart' show Renderer;
import 'package:flutter3d_cpu/builtin.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart' show GraphicsDevice;
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show PluginRegistry;
import 'package:flutter3d_plugin_runtime/flutter3d_plugin_runtime.dart';
import 'package:flutter3d_plugin_runtime_example/acme_sample.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// The hair model as the software rasteriser draws it: the base colour
/// times the block's tint, the texture and the parameters, under every
/// light in the draw, the plugin's own included: a model of the plugin's
/// own reads the rows the engine's stages skip.
final class _HairStage extends CpuFragmentShader {
  const _HairStage();

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    final s = readSurface(v, b, c);
    if (s == null) return null;
    final tint = b.read('Strands', 'tint') ?? Float32List(3);
    final shift = b.read('Strands', 'shift')?.first ?? 0.0;
    final gloss = b.read('MaterialParams', 'gloss')?.first ?? 0.0;
    final fur = b.textures['material_fur']?.pixels ?? Float32List(4);
    final light = Vector3.zero();
    for (var i = 0; i < lightCount(b, s.world); i++) {
      if (i >= CpuMeshLayout.maxLights) break;
      final color = b.vec4('FragInfo', 'light_color', Vector4.zero(), at: i);
      light.add(Vector3(color.x, color.y, color.z)..scale(color.w));
    }
    final k = gloss + shift;
    return writeLit(
      c,
      v,
      b,
      color: Vector3(
        s.albedo.x * tint[0] * fur[0] * k * light.x,
        s.albedo.y * tint[1] * fur[1] * k * light.y,
        s.albedo.z * tint[2] * fur[2] * k * light.z,
      ),
      alpha: s.alpha,
      normal: s.normal,
      roughness: 1,
    );
  }
}

final PluginRenderPoints _points = PluginRenderPoints(
  nodes: const <String>[
    'acme_sample.smear',
    'acme_sample.sparks',
    'acme_sample.sparks shown',
    'acme_sample.glow streak',
  ],
  computeStep: 'acme_sample.sparks',
  litModel: hairModel,
  lightType: tubeLight,
  decal: decalStage,
  velocityReader: 'acme_sample.smear',
  shadows: const SoftSun(),
  drawList: const HideHook(),
  lod: const CoarsePolicy(),
  // A `.pix` of four by two: the magic and the size, its texels nought.
  codec: PluginCodecPoint(
    name: 'acme_sample.pix',
    sample: Uint8List.fromList(<int>[...'PIX!'.codeUnits, 4, 2]),
    width: 4,
    height: 2,
  ),
);

void main() {
  group('the software rasteriser', () {
    runPluginRenderConformance(
      AcmeSamplePlugin.new,
      backend: 'cpu',
      points: _points,
      device: () => CpuDevice(
        width: 32,
        height: 32,
        shaders: CpuShaderLibrary(<String, CpuStage>{
          ...builtinCpuShaders(),
          'acme_sample__Hair': const CpuStage.fragment(_HairStage()),
          'acme_sample__Decal': builtinCpuShaders()['Decal']!,
        }),
      ),
    );
  });

  group('a device opened with an await, the stages handed beside it', () {
    // How the GPU backends run the same checks: a device is opened with an
    // await (WebGPU's adapter is a promise), and the plugin's stages arrive
    // as a library of their own, loaded from its bundle, rather than inside
    // the device's. Mutation: build the renderer without `materials`, and
    // the lit model and the decal are names the device does not answer.
    runPluginRenderConformance(
      AcmeSamplePlugin.new,
      backend: 'cpu, opened',
      points: _points,
      device: () async => CpuDevice(
        width: 32,
        height: 32,
        shaders: CpuShaderLibrary(builtinCpuShaders()),
      ),
      materials: (GraphicsDevice device) => CpuShaderLibrary(<String, CpuStage>{
        'acme_sample__Hair': const CpuStage.fragment(_HairStage()),
        'acme_sample__Decal': builtinCpuShaders()['Decal']!,
      }),
    );
  });

  group('the Wasm render sample, as data', () {
    // `plugin/acme_pulse.f3dplugin`: a render step whose material the run
    // time compiles and whose frame a Wasm render module drives, through the
    // same checks as the Dart plugin. Mutation: hand the engine's loop no
    // backend, and the data plugin's render steps are never installed.
    //
    // **On the recording fake, which takes any stage.** The software
    // rasteriser draws a run-time material only with the material-language
    // compiler `flutter3d_app` hands it (`materialLanguageCompiler`), a
    // Flutter package this example does not reach; an application's own
    // suite runs the same group on it.
    late DataPlugin pulse;
    setUpAll(() async {
      pulse = await DataPluginLoader(sections: DataSections(renderDataSections))
          .load(
            File('plugin/acme_pulse.f3dplugin').readAsStringSync(),
            MemoryPluginSource(<String, Uint8List>{
              for (final name in <String>['pulse.wasm', 'pulse.f3dmat'])
                name: File('plugin/$name').readAsBytesSync(),
            }),
          );
    });
    List<PluginRegistry> runtimeShaders(
      Renderer renderer,
      GraphicsDevice device,
    ) => <PluginRegistry>[
      RuntimeShaders(
        backend: RuntimeBackends.cpu,
        loadShaders: device.loadShaders,
        addMaterials: renderer.renderSteps.addMaterials,
      ),
    ];
    runPluginRenderConformance(
      () => pulse,
      backend: 'fake, data',
      points: const PluginRenderPoints(
        nodes: <String>['acme_sample.pulse.beat'],
      ),
      device: FakeBackend.new,
      registries: runtimeShaders,
      engineBackend: RuntimeBackends.cpu,
    );
  });

  group('a recording fake', () {
    runPluginRenderConformance(
      AcmeSamplePlugin.new,
      backend: 'fake',
      points: _points,
      // The decal pass reads the surface and albedo buffers beside the
      // colour, so it runs only where more than two targets attach.
      device: () => FakeBackend(maxColorAttachments: 4),
    );
  });
}
