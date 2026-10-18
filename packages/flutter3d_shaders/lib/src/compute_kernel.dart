/// A compute kernel written in the kernel language, and its two
/// translations: WGSL for WebGPU and the wgpu sidecar, a Dart kernel for the
/// CPU — 1.0.
///
/// **The kernel language, and the material language's form of it.** This
/// is the language a `ComputeStep` hands its kernels in, with buffers,
/// textures, images, loops and branches. A `.f3dmat` file's `compute` block
/// is something else: the material language's form for a texture computed
/// texel by texel (`workgroup x y`, a `kernel` body that returns the
/// texel), which `lowerMaterialCompute` in `flutter3d_core` writes in this
/// language. This reader skips a `material` or `fullscreen` block beside
/// its kernels, refuses every other top-level word, and names the material
/// form when it meets one.
///
/// **Versioned** ([kernelLanguageVersion]): a source may open with
/// `kernel 1`, after the `f3dmat <N>` line of a `.f3dmat` file if it has
/// one, and a source of a newer version is refused with both numbers. Each
/// word of the language carries the version it arrived in: a later
/// version's word is a name like any other in an older source, so a
/// version that adds words reads every kernel written before it. Version
/// 2's `atomic…` words are the one exception, taken in version 1 sources
/// as they always were.
///
/// **One source, three placements.** A frame's compute step runs on the
/// device that draws, on a compute-only sidecar or on the CPU, decided per
/// frame. Writing the kernel twice — GLSL for one, Dart for another — is
/// how two placements come to disagree; so a kernel is written once, read
/// once into one tree by this package, and each placement gets a
/// translation of that tree. The four kernels conformance runs give the
/// same bytes on each.
///
/// ```text
/// compute Scale {
///   workgroup 64;
///   buffer values: f32[] read_write;
///   buffer factor: f32[] read;
///   kernel {
///     let i = id.x;
///     if i >= len(values) { return; }
///     values[i] = values[i] * factor[0];
///   }
/// }
/// ```
///
/// A kernel declares its workgroup size, then its bindings in order —
/// `buffer` (of `f32`, `i32` or `u32`, `read` by default or `read_write`),
/// `texture` (RGBA8, read with `load(t, x, y)`) and `image` (RGBA8, written
/// with `store(i, x, y, v)`) — then its `kernel` body, which runs once per
/// invocation with `id.x`, `id.y` and `id.z` its global invocation id. The
/// body has `let` and `var`, assignment and `+=` and its kin, `if`/`else`,
/// `for i in a .. b`, `break`, `continue` and `return`; the types `f32`,
/// `i32`, `u32`, `bool` and `vec2`–`vec4`; WGSL's operators; and `len`,
/// `width`, `height`, `f32`, `i32`, `u32`, `min`, `max`, `clamp`, `abs`,
/// `floor`, `ceil`, `round`, `trunc`, `sqrt`, `sin`, `cos`, `pow`,
/// `select(c, a, b)` and the vector constructors. There is no workgroup
/// memory and no barrier: invocations are independent, and a kernel writes
/// each element of a plain buffer from one invocation.
///
/// **Kernel language 2** adds `atomic` buffers of `i32` or `u32`, which any
/// number of invocations read and write at once through `atomicLoad(b, i)`,
/// `atomicStore(b, i, v)`, `atomicExchange(b, i, v)` and `atomicAdd(b, i,
/// v)` — the last two answer what was there, or stand as a statement —
/// and never by index: what a grid of lists many invocations build
/// together needs.
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import 'kernel/kernel_ast.dart';
import 'kernel/kernel_dart.dart';
import 'kernel/kernel_parser.dart';
import 'kernel/kernel_wgsl.dart';
import 'kernel_exception.dart';

export 'kernel/kernel_dart.dart'
    show
        KernelImage,
        KernelPixels,
        KernelTexture,
        roundHalfEven,
        unormLevel,
        unormValue;
export 'kernel/kernel_wgsl.dart' show kernelEntryPoint;
export 'kernel_exception.dart';
export 'kernel_version.dart';

/// How many invocations a workgroup runs along each of its three axes: a
/// kernel's `workgroup x, y, z`, and a material's `workgroup x y`.
///
/// **A class rather than a record**, so it can say what it is and gain a
/// member later; three numbers rather than two, because a kernel over a
/// volume needs the third.
final class WorkgroupSize {
  /// [x] × [y] × [z] invocations, each at least one.
  const WorkgroupSize(this.x, this.y, this.z)
    : assert(x >= 1 && y >= 1 && z >= 1);

  /// Along x.
  final int x;

  /// Along y; one for a kernel over a line.
  final int y;

  /// Along z; one for a kernel over a line or a plane.
  final int z;

  /// How many invocations one workgroup runs: [x] × [y] × [z].
  int get invocations => x * y * z;

  @override
  bool operator ==(Object other) =>
      other is WorkgroupSize && other.x == x && other.y == y && other.z == z;

  @override
  int get hashCode => Object.hash(x, y, z);

  @override
  String toString() => 'WorkgroupSize($x, $y, $z)';
}

/// What a [KernelBinding] is.
///
/// **An open set** (S0): a later version may add a kind (a uniform block,
/// a sampled texture with a sampler) without breaking a `switch`.
final class KernelBindingKind {
  const KernelBindingKind._(this.name);

  /// A storage buffer of scalars, bound with
  /// `ComputeEncoder.bindStorageBuffer`.
  static const KernelBindingKind buffer = KernelBindingKind._('buffer');

  /// A texture read with `load`, bound with `ComputeEncoder.bindTexture`.
  static const KernelBindingKind texture = KernelBindingKind._('texture');

  /// A storage texture written with `store`, bound with
  /// `ComputeEncoder.bindStorageTexture`.
  static const KernelBindingKind image = KernelBindingKind._('image');

  /// Every kind this version names. A later version appends.
  static const List<KernelBindingKind> values = <KernelBindingKind>[
    buffer,
    texture,
    image,
  ];

  /// The kind called [name], or null for one this version does not know.
  static KernelBindingKind? byName(String name) {
    for (final kind in values) {
      if (kind.name == name) return kind;
    }
    return null;
  }

  /// The stable name.
  final String name;

  @override
  String toString() => 'KernelBindingKind.$name';
}

/// One binding a kernel declares, in the order it declares them: its
/// [index] is its WGSL binding in group zero.
final class KernelBinding {
  const KernelBinding._({
    required this.name,
    required this.kind,
    required this.element,
    required this.writable,
    required this.index,
  });

  /// What a caller binds it by.
  final String name;

  /// What it is.
  final KernelBindingKind kind;

  /// What a buffer holds — `f32`, `i32` or `u32` — or `rgba8` for a texture
  /// or an image.
  final String element;

  /// Whether the kernel writes it: a `read_write` buffer, or an image.
  final bool writable;

  /// Its position among the kernel's bindings, from zero.
  final int index;

  /// The storage texture format an image binds as.
  TextureFormat get textureFormat => TextureFormat.r8g8b8a8UNormInt;

  @override
  String toString() =>
      'KernelBinding($index: ${kind.name} $name, $element'
      '${writable ? ', written' : ''})';
}

/// A kernel's WGSL, and what binds it.
final class WgslKernel {
  const WgslKernel._(this.code, this.bindings, this.workgroupSize);

  /// One WGSL module; its entry point is [entryPoint].
  final String code;

  /// The kernel's bindings, group zero, in binding order.
  final List<KernelBinding> bindings;

  /// `@workgroup_size`, as [ComputeKernel.workgroupSize].
  final WorkgroupSize workgroupSize;

  /// The compute entry point, `main` for every kernel.
  String get entryPoint => kernelEntryPoint;
}

/// What a [DartKernel] dispatch reads and writes, by binding name: buffers
/// as bytes (little-endian, as a GPU lays them), textures and images
/// through the backend's own [KernelTexture] and [KernelImage].
final class KernelInputs {
  /// The inputs of one dispatch; each map empty unless given.
  KernelInputs({
    this.buffers = const <String, ByteData>{},
    this.textures = const <String, KernelTexture>{},
    this.images = const <String, KernelImage>{},
  });

  /// The bytes themselves, not copies: the kernel writes into them.
  final Map<String, ByteData> buffers;

  /// The textures the kernel samples or loads, by binding name.
  final Map<String, KernelTexture> textures;

  /// The storage images the kernel reads or writes, by binding name.
  final Map<String, KernelImage> images;
}

/// A kernel as Dart: what the CPU placement runs.
final class DartKernel {
  DartKernel._(this.kernel, this._compiled);

  /// What it was translated from.
  final ComputeKernel kernel;

  final CompiledKernel _compiled;

  /// Runs every invocation of the workgroup at [group] over [inputs].
  ///
  /// A binding the kernel reads and [inputs] does not hold is a
  /// [StateError] naming it, as a GPU refuses a dispatch with a binding
  /// missing; one it holds and the kernel does not declare is ignored.
  void runWorkgroup((int, int, int) group, KernelInputs inputs) {
    final (gx, gy, gz) = group;
    _compiled.runWorkgroup(gx, gy, gz, _resources(inputs));
  }

  /// Runs a dispatch of [x] × [y] × [z] workgroups over [inputs].
  void dispatch(KernelInputs inputs, int x, [int y = 1, int z = 1]) {
    final resources = _resources(inputs);
    for (var gz = 0; gz < z; gz++) {
      for (var gy = 0; gy < y; gy++) {
        for (var gx = 0; gx < x; gx++) {
          _compiled.runWorkgroup(gx, gy, gz, resources);
        }
      }
    }
  }

  KernelResources _resources(KernelInputs inputs) {
    final bindings = _compiled.kernel.bindings;
    return KernelResources(
      <ByteData?>[for (final b in bindings) inputs.buffers[b.name]],
      <KernelTexture?>[for (final b in bindings) inputs.textures[b.name]],
      <KernelImage?>[for (final b in bindings) inputs.images[b.name]],
    );
  }
}

/// One compute kernel, read from kernel language source and checked.
///
/// Throws [ComputeKernelException], with the line and column, for source
/// that is not one.
final class ComputeKernel {
  ComputeKernel._(this._tree, this.source);

  /// Every `compute` block of [source], in order; a `material` or
  /// `fullscreen` block beside them is skipped, and any other top-level
  /// word refused.
  static List<ComputeKernel> parseAll(String source) => <ComputeKernel>[
    for (final tree in parseKernels(source)) ComputeKernel._(tree, source),
  ];

  /// The kernel called [name] in [source], or its only kernel when [name]
  /// is null. Throws [ComputeKernelException] when there is no such kernel,
  /// or more than one and no name.
  static ComputeKernel parse(String source, {String? name}) {
    final all = parseAll(source);
    if (name != null) {
      for (final kernel in all) {
        if (kernel.name == name) return kernel;
      }
      throw ComputeKernelException(
        'there is no kernel called "$name" here; there '
        '${all.length == 1 ? 'is' : 'are'} '
        '${all.map((k) => '"${k.name}"').join(', ')}',
        line: 1,
        column: 1,
      );
    }
    if (all.length != 1) {
      throw ComputeKernelException(
        'expected one kernel and found ${all.length}; name the one you mean',
        line: 1,
        column: 1,
      );
    }
    return all.single;
  }

  final KKernel _tree;

  /// The whole source it was read from: what a bundle's kernel section
  /// carries, so every device reads the kernel from the text itself.
  final String source;

  /// The name a bundle and a step know it by.
  String get name => _tree.name;

  /// The kernel language version the source is written in: its
  /// `kernel <N>` line, or [kernelLanguageFirstVersion] without one.
  int get languageVersion => _tree.languageVersion;

  /// `workgroup x, y, z`, one where the source gave fewer.
  WorkgroupSize get workgroupSize {
    final (x, y, z) = _tree.workgroup;
    return WorkgroupSize(x, y, z);
  }

  /// What it binds, in order.
  late final List<KernelBinding> bindings =
      List<KernelBinding>.unmodifiable(<KernelBinding>[
        for (final b in _tree.bindings)
          KernelBinding._(
            name: b.name,
            // The parser's kinds and the public ones are one set, by name.
            kind: KernelBindingKind.byName(b.kind.name)!,
            element: b.kind == KBindingKind.buffer ? b.element.name : 'rgba8',
            writable: b.writable,
            index: b.index,
          ),
      ]);

  /// The binding called [name], or null.
  KernelBinding? binding(String name) {
    for (final b in bindings) {
      if (b.name == name) return b;
    }
    return null;
  }

  /// How many workgroups along x cover [invocations] invocations.
  int groupsFor(int invocations) {
    final x = workgroupSize.x;
    return (invocations + x - 1) ~/ x;
  }

  /// This kernel as one WGSL module.
  WgslKernel toWgsl() => WgslKernel._(emitWgsl(_tree), bindings, workgroupSize);

  /// This kernel as Dart.
  DartKernel toDartKernel() => DartKernel._(this, CompiledKernel(_tree));

  @override
  String toString() => 'ComputeKernel($name)';
}

/// A bundle named [name] that carries [kernels] in its kernel section, each
/// claimed as a stage of its name: what `GraphicsDevice.loadShaders` takes
/// on any device with compute.
ShaderBundle kernelBundle(String name, Iterable<ComputeKernel> kernels) {
  final list = kernels.toList();
  return ShaderBundle(
    name: name,
    sdk: '',
    stages: <ShaderBundleStage>[
      for (final k in list)
        ShaderBundleStage(k.name, kind: ShaderStageKind.compute),
    ],
    sections: <String, ByteData>{
      ShaderBundle.kernelSection: encodeKernelSection(<String, String>{
        for (final k in list) k.name: k.source,
      }),
    },
  );
}

/// The kernels [bundle]'s kernel section carries, read and checked, by
/// stage name; empty when it has none. What a device's `loadShaders` calls.
///
/// Throws [ShaderBundleException] naming the bundle for a section that is
/// not the payload, and for a kernel whose source does not read, with the
/// reason.
Map<String, ComputeKernel> kernelsOf(ShaderBundle bundle) {
  final sources = decodeKernelSection(bundle);
  final kernels = <String, ComputeKernel>{};
  for (final MapEntry(key: name, value: source) in sources.entries) {
    try {
      kernels[name] = ComputeKernel.parse(source, name: name);
    } on ComputeKernelException catch (error, stack) {
      Error.throwWithStackTrace(
        ShaderBundleException(
          name: bundle.name,
          reason: 'its kernel "$name" does not read: ${error.message}',
        ),
        stack,
      );
    }
  }
  return kernels;
}
