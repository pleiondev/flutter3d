import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart'
    show
        LoadedShaderLibrary,
        ShaderBundle,
        ShaderBundleStage,
        ShaderLibrary,
        encodeMaterialSection;
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_shaders/translate.dart'
    show
        GlslTranslateException,
        PackedStage,
        WgslSectionException,
        encodeWebGlSection,
        translateGlsl,
        wgslSectionDocument;

import 'material_wgsl.dart';

/// A shader a plugin brought at run time that this engine cannot compile,
/// with the sentence that says why and what to do instead.
///
/// **The refusal decision 15 asks for, not a failure.** A material in a data
/// plugin is source; whether it can become a shader while the game runs is a
/// property of the backend. Impeller runs what `impellerc` compiled ahead of
/// time, and `impellerc` ships with the Flutter SDK rather than with a game,
/// so it never can. The registry that meets this records it as the reason
/// the material or the step is off, and the rest of the plugin installs.
final class RuntimeShadersException extends CapabilityException {
  const RuntimeShadersException(this.message);

  @override
  final String message;

  @override
  String toString() => 'RuntimeShadersException: $message';
}

/// The backends a shader can be built for at run time, by the names a
/// plugin manifest and [RuntimeShaders] use for them.
abstract final class RuntimeBackends {
  /// The software rasteriser: a material runs as its own source, evaluated
  /// in Dart, so it needs nothing compiled.
  static const String cpu = 'cpu';

  /// WebGL2: the browser compiles GLSL ES 3.00 when the program links, and
  /// the translation to it is text in, text out.
  static const String webgl = 'webgl';

  /// WebGPU: reads WGSL. The build makes it with glslang and naga; at run
  /// time a material is spliced into the engine's own compiled stage — see
  /// [spliceMaterialWgsl].
  static const String webgpu = 'webgpu';

  /// Impeller: runs what `impellerc` compiled ahead of time.
  static const String impeller = 'impeller';

  /// [backend] as one of the four names above: lower case, so `WebGL2`,
  /// `webgl2` and `webgl` are one backend. Null stays null.
  static String? normalize(String? backend) {
    if (backend == null) return null;
    final lower = backend.toLowerCase();
    if (lower.startsWith('webgl')) return webgl;
    if (lower.startsWith('webgpu')) return webgpu;
    if (lower.startsWith('impeller')) return impeller;
    if (lower.startsWith('cpu') || lower.startsWith('software')) return cpu;
    return lower;
  }
}

/// The text a [ShaderBundle] built at run time carries in its `sdk` field.
///
/// No backend that loads a run-time bundle compares it — the software
/// rasteriser and WebGL2 compile nothing ahead of time — and the one that
/// does, Impeller, never gets one: [runtimeMaterialBundle] refuses it first.
const String runtimeShaderSdk = 'flutter3d run time';

/// One material written in the material language, as a bundle [backend] can
/// load with `GraphicsDevice.loadShaders` — decision 4: shaders compiled at
/// run time work where the backend compiles at run time.
///
/// * **cpu**: the bundle carries the source alone, in its material section,
///   which the software device evaluates through its `materialCompiler`.
/// * **webgl**: the source is emitted as GLSL, translated to GLSL ES 3.00
///   against [engineSources] — the engine's own GLSL headers, which a
///   browser has no disk to read them from — and carried beside the source.
/// * **webgpu**: the material's body is written as WGSL and spliced into
///   [webGpuHost] — the engine's own compiled `Unlit` stage, which
///   `flutter3d_webgpu`'s `webGpuMaterialHost()` hands over — and carried
///   with its reflection in a `webgpu` section ([spliceMaterialWgsl]). No
///   compiler runs: glslang and naga, which make the engine's WGSL in the
///   build, do not ship with a game. A material with a `light` block, one
///   reading `instance`, or one sampling a map other than the base colour is
///   refused, with the reason, and is built from `assets_src/` instead.
/// * **impeller**: refused, for good: its shaders are compiled ahead of time.
///
/// Throws a [RuntimeShadersException] for a backend that cannot, for a WebGL2
/// build with no [engineSources], a WebGPU build with no [webGpuHost], and
/// for a source that does not parse — with its line and column. [from]
/// names the source in every message.
///
/// **Version 2 of the language.** A material's `vertex` block becomes its two
/// vertex stages beside the fragment stage on the software backend and
/// WebGL2, and is refused on WebGPU at run time (the build compiles it). A
/// `fullscreen` stage is built for all three: as its source, as GLSL ES, and
/// on WebGPU as WGSL written whole ([fullscreenMaterialWgsl]) at
/// [webGpuFullscreenUvLocation]. A `compute` kernel is refused everywhere: a
/// bundle carries no compute stage, and the software backend runs one handed
/// to it as `materialComputeStage(...)`.
ShaderBundle runtimeMaterialBundle(
  String source, {
  required String? backend,
  required String from,
  Map<String, String>? engineSources,
  PackedStage? webGpuHost,
  int? webGpuFullscreenUvLocation,
}) {
  final MaterialProgram program;
  try {
    program = parseMaterial(source);
  } on MaterialSyntaxException catch (error) {
    throw RuntimeShadersException(
      '$from:${error.line}:${error.column}: ${error.message}',
    );
  }
  final name = program.name;
  final kind = RuntimeBackends.normalize(backend);
  if (program.kind == MaterialStageKind.compute) {
    throw RuntimeShadersException(
      '$from: "$name" is a compute kernel, and a bundle carries no compute '
      'stage: Impeller and WebGL2 have no compute pipelines, WebGPU runs the '
      'engine\'s own alone, and the software backend runs a kernel handed to '
      'it as materialComputeStage(...)',
    );
  }
  final fullscreen = program.kind == MaterialStageKind.fullscreen;
  final vertexName = program.vertexStageName;
  final vertexNames = <String>[
    if (vertexName != null) ...<String>[vertexName, '${vertexName}Skinned'],
  ];
  final material = encodeMaterialSection(<String, String>{
    name: source,
    for (final vertex in vertexNames) vertex: source,
  });
  ShaderBundle bundle(Map<String, ByteData> sections) => ShaderBundle(
    name: name,
    sdk: runtimeShaderSdk,
    stages: <ShaderBundleStage>[
      ShaderBundleStage(name, fragment: true),
      for (final vertex in vertexNames)
        ShaderBundleStage(vertex, fragment: false),
    ],
    sections: sections,
  );
  switch (kind) {
    case RuntimeBackends.cpu:
      return bundle(<String, ByteData>{ShaderBundle.materialSection: material});
    case RuntimeBackends.webgl:
      if (engineSources == null) {
        throw RuntimeShadersException(
          '$from: a material is translated to GLSL ES against the engine\'s '
          'own GLSL headers, and this engine was given none. Hand '
          'RuntimeShaders the headers (flutter3d_shaders\' sources, shipped '
          'as assets) as engineSources',
        );
      }
      final specialised = specializeMaterial(program, MaterialVariant(name));
      final glsl = emitMaterialFragment(specialised);
      final String webgl;
      final Map<String, String> vertex;
      try {
        webgl = translateGlsl(glsl, engineSources, from: from, fragment: true);
        vertex = <String, String>{
          for (final stage in vertexNames)
            stage: translateGlsl(
              emitMaterialVertex(
                specialised,
                skinned: stage.endsWith('Skinned'),
              ),
              engineSources,
              from: from,
              fragment: false,
            ),
        };
      } on GlslTranslateException catch (error) {
        throw RuntimeShadersException('$from: ${error.message}');
      }
      return bundle(<String, ByteData>{
        ShaderBundle.webglSection: encodeWebGlSection(
          vertex: vertex,
          fragment: <String, String>{name: webgl},
        ),
        ShaderBundle.materialSection: material,
      });
    case RuntimeBackends.webgpu when fullscreen:
      if (webGpuFullscreenUvLocation == null) {
        throw RuntimeShadersException(
          '$from: a full-screen stage is written as WGSL at run time to meet '
          'the engine\'s full-screen vertex stage, and this engine was not '
          'told where it hands over the coordinates. Hand RuntimeShaders '
          'flutter3d_webgpu\'s webGpuFullscreenUvLocation() as '
          'webGpuFullscreenUvLocation',
        );
      }
      final String document;
      try {
        document = wgslSectionDocument(
          vertex: const <String, PackedStage>{},
          fragment: <String, PackedStage>{
            name: fullscreenMaterialWgsl(
              specializeMaterial(program, MaterialVariant(name)),
              uvLocation: webGpuFullscreenUvLocation,
              from: from,
            ),
          },
        );
      } on WgslSectionException catch (error) {
        throw RuntimeShadersException('$from: ${error.message}');
      }
      return bundle(<String, ByteData>{
        ShaderBundle.webgpuSection: Uint8List.fromList(
          utf8.encode(document),
        ).buffer.asByteData(),
        ShaderBundle.materialSection: material,
      });
    case RuntimeBackends.webgpu:
      if (webGpuHost == null) {
        throw RuntimeShadersException(
          '$from: a material is built for WebGPU at run time inside the '
          'engine\'s own compiled stage, and this engine was given none. Hand '
          'RuntimeShaders flutter3d_webgpu\'s webGpuMaterialHost() as '
          'webGpuHost',
        );
      }
      final spliced = spliceMaterialWgsl(
        specializeMaterial(program, MaterialVariant(name)),
        webGpuHost,
        from: from,
      );
      final String document;
      try {
        document = wgslSectionDocument(
          vertex: const <String, PackedStage>{},
          fragment: <String, PackedStage>{name: spliced},
        );
      } on WgslSectionException catch (error) {
        throw RuntimeShadersException('$from: ${error.message}');
      }
      return bundle(<String, ByteData>{
        ShaderBundle.webgpuSection: Uint8List.fromList(
          utf8.encode(document),
        ).buffer.asByteData(),
        ShaderBundle.materialSection: material,
      });
    case RuntimeBackends.impeller:
      throw RuntimeShadersException(
        '$from: Impeller runs shaders compiled ahead of time by impellerc, '
        'which ships with the Flutter SDK and not with a game, so no shader '
        'is compiled on it while the game runs. Put the material in '
        'assets_src/ and let flutter3d_build compile it into the bundle',
      );
    case null:
      throw RuntimeShadersException(
        '$from: this engine draws nothing, so there is no backend to compile '
        'the material for',
      );
    default:
      throw RuntimeShadersException(
        '$from: "$backend" is not a backend this engine can compile a shader '
        'for at run time; ${RuntimeBackends.webgl}, ${RuntimeBackends.webgpu} '
        'and ${RuntimeBackends.cpu} can',
      );
  }
}

/// A render step a plugin brought as data: a full-screen fragment stage at
/// an anchor, switched like the engine's own steps.
final class RuntimeRenderStep {
  const RuntimeRenderStep({
    required this.name,
    required this.anchor,
    required this.shaders,
    this.present = false,
    this.needs = const <String>[],
    this.after = const <String>[],
    this.before = const <String>[],
  });

  /// The step's name and its pass's name: `<plugin id>.<step>`.
  final String name;

  /// Where the pass goes.
  final RenderAnchor anchor;

  /// The fragment stage, by backend, as source that backend compiles at run
  /// time — GLSL ES 3.00 for [RuntimeBackends.webgl]. Decision 15 allows a
  /// raw stage per backend; a backend missing here switches the step off
  /// and says so.
  ///
  /// **Or one stage for all of them** (1.0): under [materialStage], a
  /// `fullscreen` source in the material language, built for whichever
  /// backend the engine draws with — the software rasteriser, WebGL2 and
  /// WebGPU while the game runs; Impeller from the build.
  final Map<String, String> shaders;

  /// The key of [shaders] a stage written in the material language goes
  /// under, in place of a backend's name — `"shaders": {"material":
  /// "vignette.f3dmat"}` in a `.f3dplugin`.
  static const String materialStage = 'material';

  /// Whether it draws over the finished picture (`frame`, after tone
  /// mapping) rather than over the scene's light (`hdr_colour`).
  final bool present;

  /// Built-in steps it cannot run without, by name: `bloom`.
  final List<String> needs;

  /// Other nodes at [anchor] it goes after and before.
  final List<String> after;
  final List<String> before;
}

/// Materials and render steps compiled while the game runs.
///
/// **A registry the application hands the engine beside the renderer's**:
/// it holds the doors a run-time shader needs — the device's `loadShaders`,
/// the renderer's `renderSteps.addMaterials`, for WebGL2 the
/// engine's GLSL headers, and for WebGPU the engine's compiled stage a
/// material is spliced into (`webGpuMaterialHost()` from
/// `flutter3d_webgpu`) — so a plugin brings source and nothing else.
///
/// A raw render step is compiled on WebGL2 alone: its stage is a whole
/// fragment shader in one backend's language, and on WebGPU it would come
/// with no reflection to bind it by.
///
/// ```dart
/// final shaders = RuntimeShaders(
///   backend: RuntimeBackends.cpu,
///   loadShaders: device.loadShaders,
///   addMaterials: renderer.renderSteps.addMaterials,
/// );
/// EngineLoop(
///   input: input,
///   backend: RuntimeBackends.cpu,
///   registries: [renderer.renderSteps, shaders],
///   plugins: [glow],
/// );
/// ```
///
/// **A material or a step the backend cannot compile is off, not an
/// error.** Decision 15: a missing backend switches the step off and reports
/// why. [statuses] holds the reason for each, by name, and the rest of the
/// plugin installs. Compiling and loading are asynchronous; a material is
/// in the renderer, and a step draws, from the frame after its library
/// arrives. [settled] completes when nothing is pending.
final class RuntimeShaders extends PluginRegistry {
  RuntimeShaders({
    required String? backend,
    required Future<LoadedShaderLibrary> Function(ByteData bundle) loadShaders,
    required Registration Function(ShaderLibrary library) addMaterials,
    Map<String, String>? engineSources,
    PackedStage? webGpuHost,
    int? webGpuFullscreenUvLocation,
  }) : _store = _ShaderStore(
         RuntimeBackends.normalize(backend),
         loadShaders,
         addMaterials,
         engineSources,
         webGpuHost,
         webGpuFullscreenUvLocation,
       ),
       _scope = null;

  RuntimeShaders._scoped(this._store, this._scope);

  final _ShaderStore _store;
  final PluginScope? _scope;

  /// The backend shaders are built for, normalised — see
  /// [RuntimeBackends.normalize].
  String? get backend => _store.backend;

  /// Every material and step added, by name, and why each is off — null for
  /// one that is on or still loading.
  Map<String, String?> get statuses =>
      Map<String, String?>.unmodifiable(_store.statuses);

  /// The lighting model a material added here is drawn with, once it is
  /// loaded: `RenderMaterial(lighting: shaders.lighting('RimGlow'))`. Null before
  /// then, and for a material that is off.
  LightingModel? lighting(String material) => _store.lighting[material];

  /// Completes once every load asked for so far has arrived or failed.
  Future<void> get settled => Future.wait(_store.pending.toList());

  /// Compiles [source] for this engine's backend and adds it to the
  /// renderer's materials once loaded. [from] names it in every message.
  ///
  /// The registration takes it out of the renderer again.
  Registration addMaterial(String source, {required String from}) {
    final String name;
    final ShaderBundle bundle;
    try {
      final program = parseMaterial(source);
      name = program.name;
      if (program.kind != MaterialStageKind.surface) {
        throw PluginException(
          '${_owner()} brought "$name", a ${program.kind} stage, as a '
          'material: a full-screen stage is a render step\'s, under its '
          '"shaders" as "material"',
        );
      }
    } on MaterialSyntaxException catch (error) {
      // A source that does not parse is the author's mistake on every
      // backend, so it fails the install rather than switching anything off.
      throw PluginException(
        '${_owner()} brought a material that does not parse: '
        '$from:${error.line}:${error.column}: ${error.message}',
      );
    }
    try {
      bundle = runtimeMaterialBundle(
        source,
        backend: _store.backend,
        from: from,
        engineSources: _store.engineSources,
        webGpuHost: _store.webGpuHost,
        webGpuFullscreenUvLocation: _store.webGpuFullscreenUvLocation,
      );
    } on RuntimeShadersException catch (refused) {
      _store.statuses[name] = refused.message;
      return _tracked(Registration(() => _store.statuses.remove(name)));
    }
    _store.statuses[name] = null;
    Registration? added;
    var cancelled = false;
    _store.load(bundle, name, (library) {
      if (cancelled) return;
      added = _store.addMaterials(library);
      _store.lighting[name] = describeMaterial(
        parseMaterial(source),
      ).lightingModel(label: name, shaderName: name);
    });
    return _tracked(
      Registration(() {
        cancelled = true;
        added?.cancel();
        _store.lighting.remove(name);
        _store.statuses.remove(name);
      }),
    );
  }

  /// Adds [step] to [into] — the renderer's steps as the same plugin sees
  /// them — with a pass that draws once its stage for this backend is
  /// loaded.
  ///
  /// A backend [step] has no stage for adds the step anyway, switched off,
  /// with the reason in [statuses]: `FrameResult.skipped` names it, and a
  /// plugin list can say why.
  Registration addRenderStep(RuntimeRenderStep step, RendererSteps into) {
    final needs = <RenderStep>{
      for (final name in step.needs) _builtInStep(name, step.name),
    };
    final renderStep = RenderStep(step.name, needs: needs);
    final node = _RuntimeEffectNode(step.name, present: step.present);
    final registrations = <Registration>[
      into.addStep(renderStep),
      into.addNode(
        node,
        at: step.anchor,
        step: renderStep,
        after: step.after,
        before: step.before,
      ),
    ];
    final backend = _store.backend;
    final source = backend == null ? null : step.shaders[backend];
    final material = step.shaders[RuntimeRenderStep.materialStage];
    if (material != null && backend != null) {
      _materialStep(step, material, node);
    } else if (source == null) {
      _store.statuses[step.name] = backend == null
          ? 'this engine draws nothing'
          : 'it has a stage for ${step.shaders.keys.join(', ')} and this '
                'engine draws with $backend';
    } else if (backend != RuntimeBackends.webgl) {
      _store.statuses[step.name] =
          'a raw stage is compiled at run time on '
          '${RuntimeBackends.webgl} only; this engine draws with $backend';
    } else {
      _store.statuses[step.name] = null;
      final bundle = ShaderBundle(
        name: step.name,
        sdk: runtimeShaderSdk,
        stages: <ShaderBundleStage>[
          ShaderBundleStage(step.name, fragment: true),
        ],
        sections: <String, ByteData>{
          ShaderBundle.webglSection: encodeWebGlSection(
            vertex: const <String, String>{},
            fragment: <String, String>{step.name: source},
          ),
        },
      );
      _store.load(bundle, step.name, (library) {
        final shader = library[step.name];
        if (shader == null) {
          _store.statuses[step.name] =
              'the loaded library has no stage named '
              '"${step.name}"';
          return;
        }
        node.effect = step.present
            ? FullscreenEffect.present(name: step.name, shader: shader)
            : FullscreenEffect.overlay(name: step.name, shader: shader);
      });
    }
    return _tracked(
      Registration(() {
        node.effect = null;
        for (final registration in registrations.reversed) {
          registration.cancel();
        }
        _store.statuses.remove(step.name);
      }),
    );
  }

  /// A render step whose stage is written in the material language — a
  /// `fullscreen` source, version 2 — built for this engine's backend as a
  /// material is, and drawn with its uniforms at their defaults.
  void _materialStep(
    RuntimeRenderStep step,
    String source,
    _RuntimeEffectNode node,
  ) {
    final MaterialProgram program;
    try {
      program = parseMaterial(source);
    } on MaterialSyntaxException catch (error) {
      throw PluginException(
        'render step "${step.name}" is written in the material language and '
        'does not parse: ${error.line}:${error.column}: ${error.message}',
      );
    }
    if (program.kind != MaterialStageKind.fullscreen) {
      throw PluginException(
        'render step "${step.name}" is a ${program.kind} source; a render '
        'step\'s stage is a "fullscreen" one',
      );
    }
    final ShaderBundle bundle;
    try {
      bundle = runtimeMaterialBundle(
        source,
        backend: _store.backend,
        from: step.name,
        engineSources: _store.engineSources,
        webGpuHost: _store.webGpuHost,
        webGpuFullscreenUvLocation: _store.webGpuFullscreenUvLocation,
      );
    } on RuntimeShadersException catch (refused) {
      _store.statuses[step.name] = refused.message;
      return;
    }
    final bindings = describeMaterial(program);
    _store.statuses[step.name] = null;
    _store.load(bundle, step.name, (library) {
      final shader = library[program.name];
      if (shader == null) {
        _store.statuses[step.name] =
            'the loaded library has no stage named "${program.name}"';
        return;
      }
      final uniforms = <String, Map<String, Float32List>>{
        if (bindings.uniforms.isNotEmpty)
          'MaterialParams': <String, Float32List>{
            for (final MapEntry(:key, :value) in bindings.uniforms.entries)
              key: Float32List.fromList(value),
          },
      };
      node.effect = step.present
          ? FullscreenEffect.present(
              name: step.name,
              shader: shader,
              uniforms: uniforms,
              readsSurface: bindings.readsSurfaceBuffer,
            )
          : FullscreenEffect.overlay(
              name: step.name,
              shader: shader,
              uniforms: uniforms,
              readsSurface: bindings.readsSurfaceBuffer,
            );
    });
  }

  RenderStep _builtInStep(String name, String wanted) {
    for (final step in RenderStep.values) {
      if (step.name == name) return step;
    }
    throw PluginException(
      'render step "$wanted" needs "$name", which is not one of the '
      'renderer\'s own steps (${RenderStep.values.map((s) => s.name).join(', ')})',
    );
  }

  Registration _tracked(Registration registration) {
    _scope?.track(registration);
    return registration;
  }

  String _owner() =>
      _scope == null ? 'the application' : 'plugin "${_scope.manifest.id}"';

  @override
  RuntimeShaders forPlugin(PluginScope scope) =>
      RuntimeShaders._scoped(_store, scope);
}

final class _ShaderStore {
  _ShaderStore(
    this.backend,
    this.loadShaders,
    this.addMaterials,
    this.engineSources,
    this.webGpuHost,
    this.webGpuFullscreenUvLocation,
  );

  final String? backend;
  final Future<LoadedShaderLibrary> Function(ByteData bundle) loadShaders;
  final Registration Function(ShaderLibrary library) addMaterials;
  final Map<String, String>? engineSources;
  final PackedStage? webGpuHost;
  final int? webGpuFullscreenUvLocation;

  // Insertion order throughout: a list of statuses reads in the order the
  // plugins asked, never by hash.
  final Map<String, String?> statuses = <String, String?>{};
  final Map<String, LightingModel> lighting = <String, LightingModel>{};
  final Set<Future<void>> pending = <Future<void>>{};

  void load(
    ShaderBundle bundle,
    String name,
    void Function(LoadedShaderLibrary library) arrived,
  ) {
    late final Future<void> done;
    done = loadShaders(bundle.encode())
        .then(arrived)
        .catchError((Object error) {
          statuses[name] = 'the device refused it: $error';
        })
        .whenComplete(() => pending.remove(done));
    pending.add(done);
  }
}

/// The pass a [RuntimeRenderStep] draws: a full-screen effect that waits for
/// its stage.
///
/// Registered when the plugin installs, which is synchronous, and drawing
/// from the frame after the device hands its library back, which is not.
/// Until then it is inactive, which the frame reports the way it reports any
/// pass that is switched off.
final class _RuntimeEffectNode extends RenderNode {
  _RuntimeEffectNode(this.name, {required this.present});

  @override
  final String name;

  final bool present;

  /// The effect once its stage is loaded.
  FullscreenEffect? effect;

  ResourceId get _target =>
      present ? FrameResourceIds.frame : FrameResourceIds.hdrColor;

  @override
  List<ResourceId> get reads => <ResourceId>[_target];

  @override
  List<ResourceId> get writes => <ResourceId>[_target];

  @override
  bool get isActive => effect != null;

  @override
  RenderAnchor get defaultAnchor =>
      present ? RenderAnchor.beforePresent : RenderAnchor.afterScene;

  @override
  void execute(RenderFrame frame) => effect?.execute(frame);
}
