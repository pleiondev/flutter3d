/// The material language's `compute` form written in the kernel language —
/// 1.0.
///
/// **One compute language, and a form of it.** A `compute` block of a
/// `.f3dmat` file is the short way to write the common kernel: one
/// invocation per texel of a texture, reading `cell`, `size` and `uv`, and
/// returning the texel. [lowerMaterialCompute] writes it as the kernel
/// language that `ComputeKernel` reads, so it runs wherever a kernel runs
/// (WebGPU, the wgpu sidecar, the CPU) through the same two translations,
/// and nothing about it is computed a second way. Its version is the kernel
/// language's: the lowered source opens with `kernel 1`.
///
/// What the lowering decides, once:
///
/// * The kernel writes the image `target`, and returns early for an
///   invocation past its edge, so a texture whose side is not a multiple of
///   the workgroup is written exactly.
/// * A `uniform` is read from the `f32` buffer `params`, every uniform's
///   components one after the other in the order the source declares them
///   ([MaterialComputeKernel.parameterBytes] packs it); a `param` is folded
///   at its default, as the build does for a surface.
/// * `sample(t, uv)` is bilinear between the four texels around `uv` of the
///   texture's base level, clamped to its edge, the texture bound by its
///   binding name.
/// * `mix`, `smoothstep`, `step`, `fract`, `dot`, `length` and `normalize`
///   are written out in `+`, `-`, `*`, `/` and `sqrt`; `sin`, `cos` and
///   `pow` are the kernel language's own.
library;

import 'dart:typed_data';

import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart'
    show
        ComputeRequirement,
        ComputeSite,
        DeviceFeature,
        FrameCompute,
        GraphicsDevice,
        ShaderHandle;
import 'package:flutter3d_shaders/kernel.dart';

import '../../engine/render/compute_step.dart' show kernelNeeds;

import 'material_ast.dart';
import 'material_parser.dart' show MaterialSyntaxException;

/// The binding a lowered kernel writes its texels to.
const String materialComputeTarget = 'target';

/// The `f32` buffer a lowered kernel reads its uniforms from.
const String materialComputeParameters = 'params';

/// Where [MaterialComputeKernel.place] put a material's kernel: the site
/// the hardware layer chose and the kernel's stage there — since
/// 1.0.0-rc.1.
final class MaterialComputePlacement {
  const MaterialComputePlacement._(this.site, this.stage);

  /// Where it runs; `site.beginPass()` opens its pass.
  final ComputeSite site;

  /// The kernel's stage on the site's device.
  final ShaderHandle stage;

  @override
  bool operator ==(Object other) =>
      other is MaterialComputePlacement &&
      other.site == site &&
      identical(other.stage, stage);

  @override
  int get hashCode => Object.hash(site, identityHashCode(stage));

  @override
  String toString() => 'MaterialComputePlacement($site, ${stage.name})';
}

/// A material `compute` stage, lowered: the kernel and what binds it.
final class MaterialComputeKernel {
  MaterialComputeKernel._(this.program, this.kernel);

  /// What it was lowered from.
  final MaterialProgram program;

  /// The kernel, in the kernel language: what a device loads through
  /// `kernelBundle`, and a `ComputeStep` dispatches.
  final ComputeKernel kernel;

  /// The kernel language source [kernel] was read from.
  String get source => kernel.source;

  /// How many invocations a workgroup runs: the material's `workgroup`.
  WorkgroupSize get workgroupSize => kernel.workgroupSize;

  /// The uniforms read from [materialComputeParameters], in order.
  List<MaterialParameter> get uniforms => <MaterialParameter>[
    for (final parameter in program.parameters)
      if (parameter.uniform) parameter,
  ];

  /// Whether the kernel reads [materialComputeParameters] at all: false
  /// for a kernel with no `uniform`, which then has no such binding.
  bool get readsParameters => kernel.binding(materialComputeParameters) != null;

  /// The textures the kernel samples, by the name each is bound under.
  List<String> get textures => <String>[
    for (final slot in program.textures) slot.bindingName,
  ];

  /// The bytes of [materialComputeParameters]: each uniform's value from
  /// [values], or its default, little-endian `f32`s in declaration order.
  ///
  /// Throws an [ArgumentError] for a value of the wrong width; a name that
  /// is not a uniform is ignored, as a draw ignores one.
  ByteData parameterBytes({
    Map<String, List<double>> values = const <String, List<double>>{},
  }) {
    final all = <double>[
      for (final parameter in uniforms)
        ...switch (values[parameter.name]) {
          final value? when value.length != parameter.type.components =>
            throw ArgumentError.value(
              value,
              parameter.name,
              'is ${parameter.type.name}, of ${parameter.type.components} '
              'components',
            ),
          final value? => value,
          null => parameter.defaultValue,
        },
    ];
    final bytes = ByteData(all.isEmpty ? 4 : all.length * 4);
    for (final (i, v) in all.indexed) {
      bytes.setFloat32(i * 4, v, Endian.little);
    }
    return bytes;
  }

  /// How many workgroups along x cover a target [width] texels wide.
  int groupsX(int width) => (width + workgroupSize.x - 1) ~/ workgroupSize.x;

  /// How many workgroups along y cover a target [height] texels high.
  int groupsY(int height) => (height + workgroupSize.y - 1) ~/ workgroupSize.y;

  /// Where the kernel runs for frames drawn on [device], as the hardware
  /// layer places it: the stage on the site it chose — the drawing device's
  /// compute, or a GPU beside it — or null, and the texture is [bake]d on
  /// the CPU at load, the bake being this kernel's own host code — since
  /// 1.0.0-rc.1. [requirements] as a compute step states them.
  ///
  /// A site that is not the frame's own ([ComputeSite.isOnFrameDevice]
  /// false) hands its texture to the drawing device through
  /// `SharedTexture`.
  Future<MaterialComputePlacement?> place(
    GraphicsDevice device, {
    Set<ComputeRequirement> requirements = const <ComputeRequirement>{},
  }) async {
    final placed = await FrameCompute.of(device).placeHosted(
      program.name,
      load,
      hasHost: true,
      needs: kernelNeeds(<ComputeKernel>[kernel], requirements),
    );
    return placed == null
        ? null
        : MaterialComputePlacement._(placed.site, placed.loaded);
  }

  /// The kernel loaded on [device]: the stage a compute pass binds
  /// ([materialComputeTarget], [materialComputeParameters] and [textures]
  /// by name) and dispatches [groupsX] × [groupsY] times. What [place]
  /// loads on each device it tries; a caller that has a device of its own
  /// to load on asks [place] instead, so the hardware layer chooses.
  ///
  /// **Where the device computes**: WebGPU, the wgpu sidecar and the
  /// software backend. Impeller and WebGL2 have no compute pipelines, and a
  /// device without [DeviceFeature.compute] is refused with an
  /// [UnsupportedCapabilityException] naming it, before anything is
  /// loaded. [place] then finds a GPU beside it, or bakes on the CPU.
  Future<ShaderHandle> load(GraphicsDevice device) async {
    if (!device.features.has(DeviceFeature.compute)) {
      throw UnsupportedCapabilityException(
        DeviceFeature.compute,
        backend: device.backendName,
        reason:
            'compute stage "${program.name}" runs only where a device '
            'computes; MaterialComputeKernel.place finds one beside it, or '
            'bakes the texture on the CPU at load',
      );
    }
    final library = await device.loadShaders(
      kernelBundle(program.name, <ComputeKernel>[kernel]).encode(),
    );
    return library[program.name] ??
        (throw StateError(
          '${device.backendName} loaded the kernel of "${program.name}" and '
          'has no stage of that name',
        ));
  }

  /// The texture, [width] × [height] RGBA8 texels with rows from the top,
  /// computed on the CPU now by the same kernel a device runs.
  ///
  /// The fallback where a device has no compute ([load] refuses there):
  /// computed once at load, with [parameters] for the uniforms and
  /// [textures] for what it samples, by binding name, and then uploaded.
  /// A uniform that changes every frame has no such fallback; the stage
  /// then needs a device with compute.
  KernelPixels bake(
    int width,
    int height, {
    Map<String, List<double>> parameters = const <String, List<double>>{},
    Map<String, KernelTexture> textures = const <String, KernelTexture>{},
  }) {
    final target = KernelPixels(width, height);
    kernel.toDartKernel().dispatch(
      KernelInputs(
        buffers: <String, ByteData>{
          if (readsParameters)
            materialComputeParameters: parameterBytes(values: parameters),
        },
        textures: textures,
        images: <String, KernelImage>{materialComputeTarget: target},
      ),
      groupsX(width),
      groupsY(height),
    );
    return target;
  }

  @override
  String toString() => 'MaterialComputeKernel(${program.name})';
}

/// [program], a [MaterialStageKind.compute] stage, written in the kernel
/// language: see the library's documentation for what that decides.
///
/// Throws an [ArgumentError] for a program of another kind, and a
/// [MaterialSyntaxException] for a binding name the kernel language keeps
/// for itself.
MaterialComputeKernel lowerMaterialCompute(MaterialProgram program) {
  if (program.kind != MaterialStageKind.compute) {
    throw ArgumentError.value(
      program.name,
      'program',
      'is a ${program.kind} stage, not a compute stage',
    );
  }
  final source = _Lowering(program).source();
  try {
    return MaterialComputeKernel._(program, ComputeKernel.parse(source));
  } on ComputeKernelException catch (error, stack) {
    // The one thing a valid material can do that its lowering cannot say: a
    // texture bound under a word of the kernel language.
    Error.throwWithStackTrace(
      MaterialSyntaxException(
        'compute stage "${program.name}" does not lower to the kernel '
        'language: ${error.reason}',
        1,
        1,
      ),
      stack,
    );
  }
}

/// Writes one program as kernel language text, a `let` for every value a
/// builtin's expansion reads more than once.
final class _Lowering extends MaterialExpressionVisitor<String> {
  _Lowering(this.program);

  final MaterialProgram program;
  final StringBuffer _body = StringBuffer();
  int _temporaries = 0;

  /// Each uniform's first element in `params`.
  late final Map<String, int> _offsets = () {
    final offsets = <String, int>{};
    var at = 0;
    for (final parameter in program.parameters) {
      if (!parameter.uniform) continue;
      offsets[parameter.name] = at;
      at += parameter.type.components;
    }
    return offsets;
  }();

  String source() {
    final folded = specializeMaterial(program, MaterialVariant(program.name));
    final statements = _Statements(this);
    for (final statement in folded.body) {
      statement.accept(statements);
    }
    final size = program.workgroupSize;
    const target = materialComputeTarget;
    const width = 'width($target)';
    const height = 'height($target)';
    return <String>[
      // Version 1: a material's form uses nothing a later version added, so
      // a bundle built now is read by a build that reads only version 1.
      'kernel $kernelLanguageFirstVersion',
      'compute ${program.name} {',
      '  workgroup ${size.x}, ${size.y}, ${size.z};',
      '  image $target: rgba8;',
      if (_offsets.isNotEmpty) '  buffer $materialComputeParameters: f32[];',
      for (final slot in program.textures)
        '  texture ${slot.bindingName}: rgba8;',
      '  kernel {',
      '    let f3d_x = id.x;',
      '    let f3d_y = id.y;',
      '    if f3d_x >= $width || f3d_y >= $height { return; }',
      '    let f3d_size = vec2(f32($width), f32($height));',
      '    let f3d_cell = vec2(f32(f3d_x), f32(f3d_y));',
      '    let f3d_uv = (f3d_cell + vec2(0.5, 0.5)) / f3d_size;',
      '$_body  }',
      '}',
      '',
    ].join('\n');
  }

  /// A fresh name for a value read more than once.
  String _let(String value) {
    final name = 'f3d_t${_temporaries++}';
    _body.writeln('    let $name = $value;');
    return name;
  }

  /// [e] as a vector of [n] components: a scalar spread across it.
  String _widen(Expression e, String text, int n) =>
      n > 1 && e.type.components == 1 ? 'vec$n($text)' : text;

  static String _float(double v) {
    final text = v == v.truncateToDouble() && v.abs() < 1e15
        ? v.toStringAsFixed(1)
        : '$v';
    return v < 0 ? '($text)' : text;
  }

  // -------------------------------------------------------------- statements

  void visitLet(MaterialLet statement) {
    _body.writeln(
      '    let m_${statement.name} = ${statement.value.accept(this)};',
    );
  }

  void visitReturn(MaterialReturn statement) {
    _body.writeln(
      '    store($materialComputeTarget, f3d_x, f3d_y, '
      '${statement.value.accept(this)});',
    );
  }

  @override
  Never visitUnknown(Object node) => throw UnsupportedError(
    'a compute stage does not lower ${node.runtimeType}',
  );

  // ------------------------------------------------------------- expressions

  @override
  String visitConstant(ExpressionConstant expression) {
    final value = expression.value;
    if (expression.type.isBoolean) {
      return value.isNotEmpty && value.first != 0 ? 'true' : 'false';
    }
    if (value.length == 1) return _float(value.single);
    return 'vec${value.length}(${value.map(_float).join(', ')})';
  }

  @override
  String visitInputRef(MaterialInputRef expression) =>
      switch (expression.input.name) {
        'cell' => 'f3d_cell',
        'size' => 'f3d_size',
        'uv' => 'f3d_uv',
        final other => visitUnknown(other),
      };

  @override
  String visitParamRef(MaterialParamRef expression) {
    final at = _offsets[expression.parameter.name];
    if (at == null) return visitUnknown(expression);
    final n = expression.parameter.type.components;
    if (n == 1) return '$materialComputeParameters[$at]';
    return 'vec$n(${<String>[for (var i = 0; i < n; i++) '$materialComputeParameters[${at + i}]'].join(', ')})';
  }

  @override
  String visitLocalRef(MaterialLocalRef expression) => 'm_${expression.name}';

  @override
  String visitConstruct(ExpressionConstruct expression) =>
      'vec${expression.type.components}('
      '${expression.arguments.map((a) => a.accept(this)).join(', ')})';

  @override
  String visitSwizzle(ExpressionSwizzle expression) {
    final target = expression.target.accept(this);
    final components = expression.components;
    if (expression.target.type.components == 1) {
      // A float's `.x`, or its `.xxx`.
      return components.length == 1
          ? target
          : 'vec${components.length}($target)';
    }
    return '($target).${components.map((c) => 'xyzw'[c]).join()}';
  }

  @override
  String visitNegate(ExpressionNegate expression) =>
      '(-${expression.operand.accept(this)})';

  @override
  String visitBinary(ExpressionBinary expression) {
    final left = expression.left.accept(this);
    final right = expression.right.accept(this);
    return '($left ${expression.op} $right)';
  }

  @override
  String visitCall(ExpressionCall expression) {
    final arguments = expression.arguments;
    final width = arguments.fold<int>(
      1,
      (n, a) => a.type.components > n ? a.type.components : n,
    );
    final texts = <String>[for (final a in arguments) a.accept(this)];
    // Every argument at the call's width, so the kernel language's rule
    // that a builtin's arguments share one type holds.
    List<String> wide() => <String>[
      for (final (i, a) in arguments.indexed) _widen(a, texts[i], width),
    ];
    String one(String t, int c) => width == 1 ? t : '$t.${'xyzw'[c]}';
    String each(String Function(int c) component) => width == 1
        ? component(0)
        : 'vec$width(${<String>[for (var c = 0; c < width; c++) component(c)].join(', ')})';
    String dot(String a, String b, int n) => n == 1
        ? '($a * $b)'
        : '(${<String>[for (var c = 0; c < n; c++) '$a.${'xyzw'[c]} * $b.${'xyzw'[c]}'].join(' + ')})';

    switch (expression.builtin.name) {
      case 'min' || 'max' || 'clamp' || 'pow':
        return '${expression.builtin.name}(${wide().join(', ')})';
      case 'abs' || 'floor' || 'sqrt' || 'sin' || 'cos':
        return '${expression.builtin.name}(${texts.single})';
      case 'fract':
        final x = _let(texts.single);
        return '($x - floor($x))';
      case 'mix':
        final [a, b, t] = wide();
        final la = _let(a);
        return '($la + ($b - $la) * ${_let(t)})';
      case 'step':
        final [edge, x] = wide().map(_let).toList();
        return each((c) => 'select(${one(x, c)} < ${one(edge, c)}, 0.0, 1.0)');
      case 'smoothstep':
        final [e0, e1, x] = wide().map(_let).toList();
        final zero = width == 1 ? '0.0' : 'vec$width(0.0)';
        final unit = width == 1 ? '1.0' : 'vec$width(1.0)';
        final t = _let('clamp(($x - $e0) / ($e1 - $e0), $zero, $unit)');
        return '($t * $t * (3.0 - 2.0 * $t))';
      case 'dot':
        final n = arguments.first.type.components;
        final [a, b] = texts.map(_let).toList();
        return dot(a, b, n);
      case 'length':
        final n = arguments.single.type.components;
        if (n == 1) return 'abs(${texts.single})';
        final v = _let(texts.single);
        return 'sqrt(${dot(v, v, n)})';
      case 'normalize':
        final n = arguments.single.type.components;
        final v = _let(texts.single);
        if (n == 1) return '($v / abs($v))';
        return '($v / sqrt(${dot(v, v, n)}))';
    }
    return visitUnknown(expression);
  }

  @override
  String visitSample(MaterialSample expression) {
    final texture = expression.slot.bindingName;
    final uv = _let(expression.uv.accept(this));
    final w = _let('i32(width($texture))');
    final h = _let('i32(height($texture))');
    // Texel centres sit at half a texel, so the four around uv start half a
    // texel back.
    final p = _let('$uv * vec2(f32($w), f32($h)) - vec2(0.5, 0.5)');
    final base = _let('floor($p)');
    final f = _let('$p - $base');
    final x0 = _let('i32($base.x)');
    final y0 = _let('i32($base.y)');
    String clampX(String x) => 'clamp($x, 0, $w - 1)';
    String clampY(String y) => 'clamp($y, 0, $h - 1)';
    final a = _let('load($texture, ${clampX(x0)}, ${clampY(y0)})');
    final b = _let('load($texture, ${clampX('$x0 + 1')}, ${clampY(y0)})');
    final c = _let('load($texture, ${clampX(x0)}, ${clampY('$y0 + 1')})');
    final d = _let(
      'load($texture, ${clampX('$x0 + 1')}, ${clampY('$y0 + 1')})',
    );
    final top = _let('$a + ($b - $a) * $f.x');
    final bottom = _let('$c + ($d - $c) * $f.x');
    return '($top + ($bottom - $top) * $f.y)';
  }
}

/// A compute stage's statements, handed to [_Lowering]: a `let` and its
/// `return`, which is all a `kernel` body holds.
final class _Statements extends MaterialStatementVisitor<void> {
  const _Statements(this.lowering);

  final _Lowering lowering;

  @override
  void visitLet(MaterialLet statement) => lowering.visitLet(statement);

  @override
  void visitReturn(MaterialReturn statement) => lowering.visitReturn(statement);

  @override
  void visitOutput(MaterialOutput statement) =>
      lowering.visitUnknown(statement);

  @override
  void visitUnknown(MaterialStatement statement) =>
      lowering.visitUnknown(statement);
}
