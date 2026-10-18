/// The files of the plugin kinds 1.0 added to `flutter3d create plugin`:
/// a material injecting into the standard model, a compute step, an image
/// format, an editor plugin, and a data plugin with a Wasm module.
///
/// **Text a test reads exactly as a person gets it**, as the five first
/// kinds' are (`plugin_template.dart`), with the same placeholders, and
/// compiled in CI against the packages of this repository
/// (`tool/compile_templates.dart`): every kind is generated, resolved and
/// analysed on every change.
library;

// ---------------------------------------------------------------- material

/// The material's source, which both the library and `assets_src/` carry.
const String materialTemplateSource = '''
f3dmat 3
material {{pascal}} {
  lighting standard;
  uniform vec3 sheen = vec3(0.25, 0.2, 0.3);
  uniform float wear = 0.25;

  surface {
    out roughness = mix(roughness, 1.0, clamp(wear, 0.0, 1.0) * 0.5);
  }

  light {
    let rim = pow(1.0 - nDotV, 5.0);
    return standard + sheen * rim * nDotL;
  }
}
''';

/// A material plugin's `lib/<name>.dart`: the material's source as a
/// constant, and a view plugin that hands it to `RuntimeShaders` where the
/// engine compiles at run time.
const String materialLib = r'''
/// {{name}}: a material injecting into the engine's standard model.
///
/// The engine's metal-rough model, its environment, its maps and its
/// shadows, with two places of the material's own: its `surface` block
/// roughens the surface by wear before any light, and its `light` block adds
/// a sheen to the model's own answer to each light (`standard`). Written in
/// the material language, version 3.
///
/// **Two routes to the GPU, one source.** `flutter3d_build`'s hook compiles
/// `assets_src/{{name}}.f3dmat` for every backend of an application that
/// depends on this package; where the engine compiles while the game runs
/// (the software backend, WebGL2), [{{class}}] hands the same text to its
/// `RuntimeShaders`. Through the plugin's view the material is named in its
/// namespace: `{{name}}__{{pascal}}`.
library;

import 'package:flutter3d_core/data_plugins.dart' show RuntimeShaders;
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';

/// The material, as `assets_src/{{name}}.f3dmat` holds it.
const String {{camel}}Source = """
{{source}}""";

/// The name the material is compiled under through the plugin's view.
const String {{camel}}Stage = '{{name}}__{{pascal}}';

/// The plugin: a view plugin, since a material draws and steps nothing.
final class {{class}} extends Flutter3dPlugin {
  const {{class}}();

  @override
  PluginManifest get manifest => const PluginManifest(
    id: '{{name}}',
    apiVersion: PluginApiVersion(1, 0),
    touches: PluginTouches.view,
    description: 'A sheen and wear on the standard model.',
    extra: <String, Object?>{
      'budget': <String, Object?>{'stepMicroseconds': 250, 'eventsPerStep': 0},
    },
  );

  @override
  void install(PluginHost host) {
    // Where the engine compiles at run time; an application that builds
    // ahead of time loads the stage the hook compiled from assets_src/.
    host
        .maybeRegistry<RuntimeShaders>()
        ?.addMaterial({{camel}}Source, from: '{{name}}.f3dmat');
  }
}
''';

/// A material plugin's unit test: the source parses as the standard model,
/// matches `assets_src/`, and compiles on the fake device.
const String materialTest = r'''
/// {{name}}'s material reads as the standard model with its two injection
/// points, compiles where the engine compiles at run time, and is the file
/// the build compiles.
library;

import 'dart:io';

import 'package:flutter3d_core/data_plugins.dart';
import 'package:flutter3d_core/flutter3d_core.dart' show Renderer;
import 'package:flutter3d_core/formats.dart' show parseMaterial;
import 'package:flutter3d_hardware/testing.dart' show FakeBackend;
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart' show EngineLoop, InputState;
import 'package:{{name}}/{{name}}.dart';
import 'package:test/test.dart';

void main() {
  test('the source is the standard model with a surface and a light block',
      () {
    final program = parseMaterial({{camel}}Source);
    expect(program.isStandard, isTrue);
    expect(program.surface, isNotNull);
    expect(program.inputsUsed, contains('standard'));
  });

  test('the build compiles the same text', () {
    expect(
      File('assets_src/{{name}}.f3dmat').readAsStringSync(),
      {{camel}}Source,
    );
  });

  test('it compiles where the engine compiles at run time', () async {
    final device = FakeBackend();
    final renderer = Renderer.create(device: device);
    final shaders = RuntimeShaders(
      backend: RuntimeBackends.cpu,
      loadShaders: device.loadShaders,
      addMaterials: renderer.renderSteps.addMaterials,
    );
    EngineLoop(
      input: InputState(),
      backend: RuntimeBackends.cpu,
      registries: <PluginRegistry>[renderer.renderSteps, shaders],
      plugins: const <Flutter3dPlugin>[{{class}}()],
    );
    await shaders.settled;
    expect(shaders.statuses, containsPair({{camel}}Stage, isNull));
    expect(shaders.lighting({{camel}}Stage), isNotNull);
  });
}
''';

/// A material plugin's `test/conformance_test.dart`: the plugin suite over
/// a fake-device renderer and its run-time shaders.
const String materialConformance = r'''
/// flutter3d_conformance's plugin suite, over a renderer drawn with the
/// hardware layer's fake device and the run-time shaders the material
/// compiles into.
library;

import 'package:flutter3d_conformance/plugins.dart';
import 'package:flutter3d_core/data_plugins.dart';
import 'package:flutter3d_core/flutter3d_core.dart' show Renderer;
import 'package:flutter3d_hardware/testing.dart' show FakeBackend;
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show PluginRegistry;
import 'package:{{name}}/{{name}}.dart';

void main() {
  runPluginConformance(
    () => const {{class}}(),
    harness: PluginHarness(
      registries: (String? backend) {
        final device = FakeBackend();
        final renderer = Renderer.create(device: device);
        return <PluginRegistry>[
          renderer.renderSteps,
          RuntimeShaders(
            backend: RuntimeBackends.cpu,
            loadShaders: device.loadShaders,
            addMaterials: renderer.renderSteps.addMaterials,
          ),
        ];
      },
    ),
  );
}
''';

// ----------------------------------------------------------------- compute

/// A compute plugin's `lib/<name>.dart`: a compute step whose kernel moves
/// a 256-value buffer halfway to one each frame, the node that reads it,
/// and the view plugin that adds both.
const String computeLib = r'''
/// {{name}}: a compute step of its own, in the frame.
///
/// One kernel, written once in the kernel language, which the hardware
/// layer places where it chooses — the drawing device's compute, the wgpu
/// sidecar, or the CPU — and a frame skips with the typed refusal
/// (`PassSkip.unsupported`) where nothing computes it. It brightens a
/// buffer of [{{pascal}}Ramp.cells] values towards one, a frame at a time,
/// and [{{pascal}}Show] reads it after the scene.
///
/// **A step runs for a reader.** The frame graph culls a node whose output
/// nothing in the frame reads (`PassSkip.unconsumed`), a compute step as
/// any other; a particle draw, a post effect or a read back is what keeps
/// it, and [{{pascal}}Show] stands in for whichever yours is.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart'
    show
        ComputeContext,
        ComputeStep,
        FrameResourceIds,
        RenderFrame,
        RenderNode,
        RendererSteps,
        ResourceId;
import 'package:flutter3d_hardware/flutter3d_hardware.dart'
    show
        BufferDescriptor,
        BufferUsage,
        ComputePipelineHandle,
        GraphicsDevice,
        StorageBuffer;
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_shaders/kernel.dart' show ComputeKernel;

/// The step: every value of its buffer moves halfway to one each frame.
final class {{pascal}}Ramp extends ComputeStep {
  {{pascal}}Ramp();

  /// How many values the buffer holds.
  static const int cells = 256;

  /// What the frame graph orders it by.
  static const ResourceId rampResource = ResourceId('{{name}}.ramp');

  @override
  String get name => '{{name}}.ramp';

  @override
  List<ResourceId> get writes => const <ResourceId>[rampResource];

  @override
  late final List<ComputeKernel> kernels = ComputeKernel.parseAll("""
kernel 1
compute {{pascal}}Ramp {
  workgroup 64;
  buffer ramp: f32[] read_write;
  kernel {
    let i = id.x;
    if i >= len(ramp) { return; }
    ramp[i] = ramp[i] * 0.5 + 0.5;
  }
}
""");

  StorageBuffer? _ramp;
  ComputePipelineHandle? _pipeline;
  GraphicsDevice? _on;

  /// The buffer, on the device the step last ran on; null before its first
  /// frame.
  StorageBuffer? get ramp => _ramp;

  @override
  void record(ComputeContext context) {
    final device = context.device;
    if (!identical(_on, device)) {
      _release();
      _on = device;
      final ramp = device.createBuffer(
        const BufferDescriptor(
          lengthInBytes: cells * 4,
          usage: BufferUsage.standardStorage,
          label: '{{name}} ramp',
        ),
      );
      device.writeBuffer(
        ramp,
        0,
        ByteData.sublistView(Float32List(cells)),
      );
      _ramp = ramp;
    }
    final stage = context.stage('{{pascal}}Ramp');
    final pipeline = _pipeline ??= device.createComputePipeline(stage);
    context.beginPass()
      ..bindPipeline(pipeline)
      ..bindStorageBuffer(stage, 'ramp', _ramp!)
      ..dispatch((cells + 63) ~/ 64)
      ..submit();
  }

  void _release() {
    _ramp?.dispose();
    _pipeline?.dispose();
    _ramp = null;
    _pipeline = null;
    _on = null;
  }

  /// Gives its buffer back, when the step leaves the frame.
  @override
  void dispose() => _release();
}

/// Reads the ramp after the scene, where a draw that used it would, and
/// hands the scene's colour on unchanged: the reader that keeps the step in
/// the frame.
final class {{pascal}}Show extends RenderNode {
  const {{pascal}}Show();

  @override
  String get name => '{{name}}.show';

  @override
  List<ResourceId> get reads => const <ResourceId>[
    {{pascal}}Ramp.rampResource,
    FrameResourceIds.hdrColor,
  ];

  @override
  List<ResourceId> get writes => const <ResourceId>[FrameResourceIds.hdrColor];

  @override
  void execute(RenderFrame frame) => frame.resources.provide(
    FrameResourceIds.hdrColor,
    frame.resources.texture(FrameResourceIds.hdrColor),
  );
}

/// The plugin: a view plugin, since what it computes is drawn and never
/// stepped.
final class {{class}} extends Flutter3dPlugin {
  const {{class}}();

  @override
  PluginManifest get manifest => const PluginManifest(
    id: '{{name}}',
    apiVersion: PluginApiVersion(1, 0),
    touches: PluginTouches.view,
    description: 'A compute step in the frame.',
    extra: <String, Object?>{
      'budget': <String, Object?>{'stepMicroseconds': 250, 'eventsPerStep': 0},
    },
  );

  @override
  void install(PluginHost host) {
    host.registry<RendererSteps>()
      ..addComputeStep({{pascal}}Ramp())
      ..addNode(const {{pascal}}Show());
  }
}
''';

/// A compute plugin's unit test: the step is among the renderer's nodes
/// while the plugin is on and gone once it is disabled.
const String computeTest = r'''
/// {{name}}'s step is in the frame while the plugin is on, and gone after.
library;

import 'package:flutter3d_core/flutter3d_core.dart' show Renderer;
import 'package:flutter3d_hardware/testing.dart' show FakeBackend;
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart' show EngineLoop, InputState;
import 'package:{{name}}/{{name}}.dart';
import 'package:test/test.dart';

void main() {
  test('the step is the renderer\'s while the plugin is on', () {
    final renderer = Renderer.create(device: FakeBackend());
    final loop = EngineLoop(
      input: InputState(),
      registries: <PluginRegistry>[renderer.renderSteps],
      plugins: const <Flutter3dPlugin>[{{class}}()],
    );
    expect(renderer.renderSteps.nodeNames, contains('{{name}}.ramp'));

    loop.plugins.disable('{{name}}');
    loop.runSteps(1);
    expect(renderer.renderSteps.nodeNames, isNot(contains('{{name}}.ramp')));
  });
}
''';

/// A compute plugin's `test/conformance_test.dart`: the plugin suite, and
/// the render checks on a 32 by 32 software device.
const String computeConformance = r'''
/// flutter3d_conformance's plugin suite, and the render checks on the
/// software backend: the plugin places a node in the frame, so both are
/// part of its badge.
library;

import 'package:flutter3d_conformance/plugins.dart';
import 'package:flutter3d_conformance_render/flutter3d_conformance_render.dart';
import 'package:flutter3d_core/flutter3d_core.dart' show Renderer;
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_hardware/testing.dart' show FakeBackend;
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show PluginRegistry;
import 'package:{{name}}/{{name}}.dart';

void main() {
  runPluginConformance(
    () => const {{class}}(),
    harness: PluginHarness(
      registries: (String? backend) => <PluginRegistry>[
        Renderer.create(device: FakeBackend()).renderSteps,
      ],
    ),
  );
  runPluginRenderConformance(
    () => const {{class}}(),
    backend: 'cpu',
    device: () => CpuDevice(
      width: 32,
      height: 32,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    ),
    points: const PluginRenderPoints(
      nodes: <String>['{{name}}.ramp', '{{name}}.show'],
      computeStep: '{{name}}.ramp',
    ),
  );
}
''';

// ------------------------------------------------------------------- codec

/// A codec plugin's `lib/<name>.dart`: a texture codec for a toy format
/// (magic `F3DI`, a byte each of width and height, RGBA8 texels), its
/// encoder, and the plugin that registers it.
const String codecLib = r'''
/// {{name}}: an image format of its own, read wherever the engine loads a
/// texture.
///
/// A `.{{name}}` file is four bytes of magic, `F3DI`, a byte of width and a
/// byte of height, then the texels as RGBA8, row by row. Registered with
/// the engine's [TextureCodecs], it is asked before the engine's own
/// decoders for every texture a model, a material or a level loads.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart'
    show Rgba8Image, TextureCodec, TextureCodecs, TextureDecodeContext;
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';

/// The format: magic, size, texels.
final class {{pascal}}Codec extends TextureCodec {
  const {{pascal}}Codec();

  /// The four bytes a file of this format starts with.
  static const List<int> magic = <int>[0x46, 0x33, 0x44, 0x49];

  @override
  String get name => '{{name}}.image';

  @override
  bool sniff(Uint8List head) =>
      head.length >= 6 &&
      head[0] == magic[0] &&
      head[1] == magic[1] &&
      head[2] == magic[2] &&
      head[3] == magic[3];

  @override
  Future<Rgba8Image?> decode(TextureDecodeContext context) async {
    final bytes = context.bytes;
    final width = bytes[4];
    final height = bytes[5];
    final texels = width * height * 4;
    if (width == 0 || height == 0 || bytes.length < 6 + texels) {
      context.report?.call(
        'a {{name}} file of $width by $height ends early',
      );
      return null;
    }
    return Rgba8Image(
      width: width,
      height: height,
      pixels: Uint8List.fromList(bytes.sublist(6, 6 + texels)),
    );
  }
}

/// A file of [width] by [height] texels of [rgba], in the format.
Uint8List encode{{pascal}}(int width, int height, List<int> rgba) =>
    Uint8List.fromList(<int>[
      ...{{pascal}}Codec.magic,
      width,
      height,
      for (var i = 0; i < width * height; i++) ...rgba,
    ]);

/// The plugin: a view plugin, since an image is drawn and never stepped.
final class {{class}} extends Flutter3dPlugin {
  const {{class}}();

  @override
  PluginManifest get manifest => const PluginManifest(
    id: '{{name}}',
    apiVersion: PluginApiVersion(1, 0),
    touches: PluginTouches.view,
    description: 'An image format of its own.',
    extra: <String, Object?>{
      'budget': <String, Object?>{'stepMicroseconds': 250, 'eventsPerStep': 0},
    },
  );

  @override
  void install(PluginHost host) {
    host.maybeRegistry<TextureCodecs>()?.add(const {{pascal}}Codec());
  }
}
''';

/// A codec plugin's unit test: an encoded file uploads as a texture of its
/// size, and the codec is gone once the plugin is disabled.
const String codecTest = r'''
/// {{name}}'s format is read by the engine's texture loading while the
/// plugin is on.
library;

import 'package:flutter3d_core/flutter3d_core.dart'
    show ModelDecoders, uploadEncodedImage;
import 'package:flutter3d_hardware/testing.dart' show FakeBackend;
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart' show EngineLoop, InputState;
import 'package:{{name}}/{{name}}.dart';
import 'package:test/test.dart';

void main() {
  test('a file of its format loads as a texture of its size', () async {
    final decoders = ModelDecoders();
    final loop = EngineLoop(
      input: InputState(),
      registries: <PluginRegistry>[decoders],
      plugins: const <Flutter3dPlugin>[{{class}}()],
    );
    final texture = await uploadEncodedImage(
      FakeBackend(),
      encode{{pascal}}(4, 2, const <int>[255, 128, 0, 255]),
      decodeImage: (_) async => null,
      platformDecode: false,
      codecs: decoders.textureCodecs,
    );
    expect((texture.width, texture.height), (4, 2));

    loop.plugins.disable('{{name}}');
    loop.runSteps(1);
    expect(decoders.textureCodecs.codecs, isEmpty);
  });
}
''';

/// A codec plugin's `test/conformance_test.dart`: the plugin suite with
/// the engine's decoders, and `render.codec` on the software backend.
const String codecConformance = r'''
/// flutter3d_conformance's plugin suite with the engine's decoders, and
/// the render suite's `render.codec` on the software backend.
library;

import 'package:flutter3d_conformance/plugins.dart';
import 'package:flutter3d_conformance_render/flutter3d_conformance_render.dart';
import 'package:flutter3d_core/flutter3d_core.dart' show ModelDecoders;
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show PluginRegistry;
import 'package:{{name}}/{{name}}.dart';

void main() {
  runPluginConformance(
    () => const {{class}}(),
    harness: PluginHarness(
      registries: (String? backend) => <PluginRegistry>[ModelDecoders()],
    ),
  );
  runPluginRenderConformance(
    () => const {{class}}(),
    backend: 'cpu',
    device: () => CpuDevice(
      width: 32,
      height: 32,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    ),
    points: PluginRenderPoints(
      codec: PluginCodecPoint(
        name: '{{name}}.image',
        sample: encode{{pascal}}(4, 2, const <int>[255, 128, 0, 255]),
        width: 4,
        height: 2,
      ),
    ),
  );
}
''';

// ------------------------------------------------------------------ editor

/// An editor plugin's `lib/<name>.dart`: a command that raises the
/// selection, with a menu entry, a shortcut, a toolbar button and a tool
/// mode that run it.
const String editorLib = r'''
/// {{name}}: an editor plugin — a command, a menu entry with a key, a
/// toolbar button and a tool mode.
///
/// **A plugin of the editor's, not of the game's.** A game never depends on
/// this package; an editor that does adds its pieces, each filed under the
/// plugin's namespace (`{{name}}.raise`) and withdrawn when it is switched
/// off. The command is the one way it changes the level, as a key, a menu,
/// a button, the tool mode and an agent over MCP all run it: one step of
/// undo.
library;

import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_plugin_api/tools.dart' show ToolHints;
import 'package:vector_math/vector_math.dart' show Vector3;

/// Lifts the selection by [by] metres.
final class {{pascal}}Raise extends PluginCommand {
  const {{pascal}}Raise(this.by);

  /// Reads it back from a call's arguments.
  static {{pascal}}Raise? read(Map<String, Object?> arguments) =>
      switch (arguments['by']) {
        final num by => {{pascal}}Raise(by.toDouble()),
        _ => null,
      };

  /// How far, in metres.
  final double by;

  @override
  String get name => '{{name}}.raise';

  @override
  String get says => 'raise by $by';

  @override
  Map<String, Object?> get arguments => <String, Object?>{'by': by};

  @override
  bool apply(Editing editing) {
    if (editing.where == null) return false;
    editing.nudgeAll(Vector3(0.0, by, 0.0));
    return true;
  }
}

/// A tool mode that raises what is under the pointer as it is pressed.
final class {{pascal}}RaiseMode extends EditorToolMode {
  const {{pascal}}RaiseMode();

  @override
  String get label => 'Raise';

  @override
  DocumentCommand? pressed(ToolModeInput input) =>
      input.picked == null ? null : const {{pascal}}Raise(0.25);

  @override
  List<GizmoMark> preview(ToolModeInput input) => <GizmoMark>[
    GizmoMark.ball(input.point, radius: 0.25),
  ];
}

/// The plugin: a tooling plugin, since it edits documents and is in no
/// game.
final class {{class}} extends Flutter3dPlugin {
  const {{class}}();

  @override
  PluginManifest get manifest => const PluginManifest(
    id: '{{name}}',
    apiVersion: PluginApiVersion(1, 0),
    touches: PluginTouches.tooling,
    description: 'A command, a menu entry, a button and a tool mode.',
    extra: <String, Object?>{
      'budget': <String, Object?>{'stepMicroseconds': 250, 'eventsPerStep': 0},
    },
  );

  @override
  void install(PluginHost host) {
    host.registry<EditorPieces>()
      ..addCommand(
        'raise',
        {{pascal}}Raise.read,
        description: 'Lifts the selection.',
        hints: ToolHints.writes,
      )
      ..addMenuItem(
        EditorMenuItem(
          name: 'raise',
          label: 'Raise a little',
          command: 'raise',
          menu: 'Tools',
          arguments: const <String, Object?>{'by': 0.25},
          shortcut: EditorShortcut.parse('ctrl+shift+r'),
        ),
      )
      ..addToolMode('raiseMode', const {{pascal}}RaiseMode())
      ..addToolbarItem(
        const EditorToolbarItem.toolMode(
          name: 'raiseMode',
          label: 'Raise under the pointer',
          icon: 'arrow_upward',
          toolMode: 'raiseMode',
        ),
      );
  }
}
''';

/// An editor plugin's unit test: its pieces are filed under its namespace,
/// the menu entry runs the command, and all of it goes with the plugin.
const String editorTest = r'''
/// {{name}}'s pieces are the editor's while the plugin is on, under its
/// namespace, and its menu entry runs its command.
library;

import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart' show EngineLoop, InputState;
import 'package:{{name}}/{{name}}.dart';
import 'package:test/test.dart';

void main() {
  test('the menu entry runs the command, and everything goes with the '
      'plugin', () {
    final pieces = EditorPieces();
    final loop = EngineLoop(
      input: InputState(),
      registries: <PluginRegistry>[pieces],
      plugins: const <Flutter3dPlugin>[{{class}}()],
    );
    final item = pieces.menuItems.single;
    expect(item.name, '{{name}}.raise');
    expect(pieces.commandOf(item), isA<{{pascal}}Raise>());
    expect(pieces.toolModeNames, <String>['{{name}}.raiseMode']);
    expect(pieces.toolbarItems.single.toolMode, '{{name}}.raiseMode');

    loop.plugins.disable('{{name}}');
    loop.runSteps(1);
    expect(pieces.menuItems, isEmpty);
    expect(pieces.toolbarItems, isEmpty);
    expect(pieces.toolModeNames, isEmpty);
  });
}
''';

/// An editor plugin's `test/conformance_test.dart`: the plugin suite with
/// an editor's pieces to add to.
const String editorConformance = r'''
/// flutter3d_conformance's plugin suite, with an editor's pieces for the
/// plugin to add to.
library;

import 'package:flutter3d_conformance/plugins.dart';
import 'package:flutter3d_editor_core/flutter3d_editor_core.dart'
    show EditorPieces;
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show PluginRegistry;
import 'package:{{name}}/{{name}}.dart';

void main() {
  runPluginConformance(
    () => const {{class}}(),
    harness: PluginHarness(
      registries: (String? backend) => <PluginRegistry>[EditorPieces()],
    ),
  );
}
''';

// -------------------------------------------------------------------- data

/// The step module of a data plugin, in WebAssembly's text format: every
/// sixtieth step it publishes event 0 of its declaration, `tick`, with the
/// step's number.
const String dataWat = r'''
;; {{name}}'s step module, Wasm plugin ABI 2: 32-bit integers only, the
;; world reached through the f3d imports alone. Built with wabt into the
;; file plugin/{{name}}.f3dplugin names, which an application ships beside
;; it:
;;
;;     wat2wasm wasm/{{name}}.wat -o plugin/{{name}}.wasm
;;
;; lib/{{name}}.dart carries the same bytes, so the plugin installs from
;; Dart, and its tests run, without the file.
(module
  (import "f3d" "publish" (func $publish (param i32 i32 i32)))
  (func (export "f3d_abi") (result i32)
    i32.const 2)
  (func (export "f3d_step") (param $step i32) (param $dt i32)
    local.get $step
    i32.const 60
    i32.rem_u
    i32.eqz
    if
      i32.const 0
      local.get $step
      i32.const 0
      call $publish
    end))
''';

/// [dataWat], as `wat2wasm` assembles it.
const List<int> dataWasm = <int>[
  0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00, 0x01, 0x10, 0x03, 0x60, //
  0x03, 0x7f, 0x7f, 0x7f, 0x00, 0x60, 0x00, 0x01, 0x7f, 0x60, 0x02, 0x7f,
  0x7f, 0x00, 0x02, 0x0f, 0x01, 0x03, 0x66, 0x33, 0x64, 0x07, 0x70, 0x75,
  0x62, 0x6c, 0x69, 0x73, 0x68, 0x00, 0x00, 0x03, 0x03, 0x02, 0x01, 0x02,
  0x07, 0x16, 0x02, 0x07, 0x66, 0x33, 0x64, 0x5f, 0x61, 0x62, 0x69, 0x00,
  0x01, 0x08, 0x66, 0x33, 0x64, 0x5f, 0x73, 0x74, 0x65, 0x70, 0x00, 0x02,
  0x0a, 0x1a, 0x02, 0x04, 0x00, 0x41, 0x02, 0x0b, 0x13, 0x00, 0x20, 0x00,
  0x41, 0x3c, 0x70, 0x45, 0x04, 0x40, 0x41, 0x00, 0x20, 0x00, 0x41, 0x00,
  0x10, 0x00, 0x0b, 0x0b,
];

/// A data plugin's `plugin/<name>.f3dplugin`: the manifest, the `tick`
/// event, and the Wasm system in the `rules` phase with 10000 fuel a step.
const String dataPluginDocument = '''
{
  "format": "f3d.plugin",
  "version": 4,
  "requires": [],
  "generator": "flutter3d",
  "manifest": {
    "id": "{{name}}",
    "apiVersion": "1.0",
    "touches": "simulation",
    "description": "A Wasm step system that ticks.",
    "budget": {"stepMicroseconds": 500, "eventsPerStep": 1}
  },
  "events": [{"name": "tick", "description": "Every sixtieth step."}],
  "wasm": [
    {
      "module": "{{name}}.wasm",
      "system": "tick",
      "phase": "rules",
      "events": ["tick"],
      "limits": {"fuelPerStep": 10000}
    }
  ]
}
''';

/// A data plugin's `lib/<name>.dart`: the module's bytes, the system's
/// declaration, and a plugin that installs the same system from Dart.
const String dataLib = r'''
/// {{name}}: a data plugin — a `.f3dplugin` document and the Wasm module it
/// names — and the same system installed from Dart.
///
/// `plugin/{{name}}.f3dplugin` is what an application loads while the game
/// runs, with `DataPluginLoader` from `flutter3d_plugin_runtime`: its events
/// and its Wasm step system, stepped on the metered interpreter, the same
/// answer on every platform. [{{class}}] installs the same module from Dart,
/// for a game that ships it compiled in, and is what the conformance suite
/// holds.
library;

import 'dart:typed_data';

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_plugin_runtime/flutter3d_plugin_runtime.dart';

/// `plugin/{{name}}.wasm`'s bytes, as `wasm/{{name}}.wat` assembles.
final Uint8List {{camel}}Module = Uint8List.fromList(const <int>[
{{wasm}}]);

/// The system's declaration: in the loop's `rules` phase, publishing one
/// event, `tick`.
const WasmSystemSpec {{camel}}System = WasmSystemSpec(
  module: '{{name}}.wasm',
  system: 'tick',
  phase: 'rules',
  events: <String>['tick'],
  limits: WasmLimits(fuelPerStep: 10000),
);

/// The plugin: it touches the simulation, since its system publishes on the
/// step channel.
final class {{class}} extends Flutter3dPlugin {
  {{class}}() : _module = WasmModule.decode({{camel}}Module);

  final WasmModule _module;
  WasmSystem? _system;

  /// The installed system, or null while the plugin is off.
  WasmSystem? get system => _system;

  @override
  PluginManifest get manifest => const PluginManifest(
    id: '{{name}}',
    apiVersion: PluginApiVersion(1, 0),
    touches: PluginTouches.simulation,
    description: 'A Wasm step system that ticks.',
    extra: <String, Object?>{
      'budget': <String, Object?>{'stepMicroseconds': 500, 'eventsPerStep': 1},
    },
  );

  @override
  void install(PluginHost host) {
    host.events.declare<PluginDataEvent>(
      '{{name}}.tick',
      codec: PluginDataEvent.codecFor('{{name}}.tick'),
    );
    final system = _system = installWasmSystem(host, {{camel}}System, _module);
    // Its module's memory is the run's state: a rewind, a rollback and the
    // double-step check carry it.
    host.registry<SnapshotRegistry>().add(
      SnapshotPart.of(
        id: '{{name}}.module',
        capture: system.save,
        restore: (context) =>
            system.restore((context.data! as Map).cast<String, Object?>()),
      ),
    );
  }

  @override
  void uninstall(PluginHost host) => _system = null;
}
''';

/// A data plugin's unit test: the document loads with its module, and it
/// and the Dart install both tick three times in 121 steps.
const String dataTest = r'''
/// {{name}}'s document loads with the runtime and ticks every sixtieth
/// step, as the plugin installed from Dart does.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_plugin_runtime/flutter3d_plugin_runtime.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:{{name}}/{{name}}.dart';
import 'package:test/test.dart';

/// The ticks a loop running [plugin] hears in [steps] steps.
List<String> _ticks(Flutter3dPlugin plugin, int steps) {
  final loop = EngineLoop(
    input: InputState(),
    plugins: <Flutter3dPlugin>[plugin],
  );
  final heard = <String>[];
  loop.events.onStep<BusEvent>(
    'test.ticks',
    (Delivered<BusEvent> event) {
      if (event.event.name == '{{name}}.tick') heard.add(event.event.name);
    },
  );
  loop.runSteps(steps);
  return heard;
}

void main() {
  test('the document loads with its module, and ticks every sixtieth step',
      () async {
    // The bytes the library carries stand for `plugin/{{name}}.wasm`,
    // which `wat2wasm wasm/{{name}}.wat` writes for an application to ship.
    final plugin = await const DataPluginLoader().load(
      File('plugin/{{name}}.f3dplugin').readAsStringSync(),
      MemoryPluginSource(<String, Uint8List>{
        '{{name}}.wasm': {{camel}}Module,
      }),
    );
    expect(plugin.document.wasm.single.system, {{camel}}System.system);
    expect(_ticks(plugin, 121), hasLength(3));
  });

  test('installed from Dart, it ticks the same', () {
    expect(_ticks({{class}}(), 121), hasLength(3));
  });
}
''';

/// A data plugin's `test/conformance_test.dart`: the plugin suite alone,
/// the module's memory carried by the loop's snapshots.
const String dataConformance = r'''
/// flutter3d_conformance's plugin suite. The module's memory is in the
/// loop's snapshots from the plugin's install, so the determinism check
/// steps each step twice from it.
library;

import 'package:flutter3d_conformance/plugins.dart';
import 'package:{{name}}/{{name}}.dart';

void main() {
  runPluginConformance({{class}}.new);
}
''';
