/// What one stage may bind: the budget a material's stages are held to.
library;

/// The textures, samplers and uniform blocks one stage of a pipeline may
/// bind, the engine's own bindings and a material's together (M3).
///
/// **WebGPU's guaranteed minimums, the tightest of the four backends.** A
/// WebGPU device may report more, and the engine asks the adapter for what
/// it has, but a bundle built for any browser can count only on what every
/// device gives: 16 sampled textures, 16 samplers and 12 uniform buffers in
/// a stage. A texture the material language binds is a texture and a
/// sampler on WebGPU, so a stage's textures count against both.
///
/// The build refuses a stage over the budget, naming it and the count
/// (`wgslSectionDocument`, which every writer of a WebGPU section calls), so
/// a material that would fail to make its pipeline on somebody's device
/// fails on the author's machine instead. The engine's stages leave a lit
/// model's own bindings what `docs/CONTRACTS.md` ("A material's own blocks
/// and textures") says.
abstract final class MaterialStageBudget {
  /// Sampled textures in one stage.
  static const int textures = 16;

  /// Samplers in one stage.
  static const int samplers = 16;

  /// Uniform blocks in one stage.
  static const int uniformBlocks = 12;

  /// Textures a lighting model of a plugin's own may bind of its own,
  /// through all of 1.x: what the engine's bindings in a material-language
  /// lit stage leave it with every feature on (`binding_budget_test.dart`
  /// holds the engine to it). A minor that wants one more texture in the lit
  /// headers packs it into one the stage already reads instead, so a
  /// material at this edge builds in every 1.x.
  static const int materialTextures = 3;

  /// Uniform blocks a lighting model of a plugin's own may declare of its
  /// own through all of 1.x, `MaterialParams` included; see
  /// [materialTextures].
  static const int materialUniformBlocks = 4;

  /// Why a stage named [stage] that binds [textures] textures, [samplers]
  /// samplers and [uniformBlocks] uniform blocks is over the budget, or null
  /// when it is within it.
  static String? problem(
    String stage, {
    required int textures,
    required int samplers,
    required int uniformBlocks,
  }) {
    String over(int count, int budget, String what) =>
        'the stage "$stage" binds $count $what, and a stage may bind at most '
        '$budget on WebGPU, the engine\'s own bindings included: that is '
        'what every WebGPU device guarantees. Bind fewer in the material, '
        'or pack two maps into the channels of one';
    if (textures > MaterialStageBudget.textures) {
      return over(textures, MaterialStageBudget.textures, 'textures');
    }
    if (samplers > MaterialStageBudget.samplers) {
      return over(samplers, MaterialStageBudget.samplers, 'samplers');
    }
    if (uniformBlocks > MaterialStageBudget.uniformBlocks) {
      return over(
        uniformBlocks,
        MaterialStageBudget.uniformBlocks,
        'uniform blocks',
      );
    }
    return null;
  }

  /// Why [stage], whose GLSL with its includes resolved is [glsl], is over
  /// the budget, or null when it is within it: the same answer [problem]
  /// gives, counted from the source every backend's path has, so the build
  /// and `RuntimeShaders` refuse it on every backend and not only where a
  /// WGSL compiler is installed. Counted as declared, after `#ifdef`, which
  /// the engine's headers keep in step with what the compiler keeps.
  static String? problemOfGlsl(String stage, String glsl) {
    final GlslBindingCount(:textures, :uniformBlocks) = countGlslBindings(glsl);
    return problem(
      stage,
      textures: textures,
      samplers: textures,
      uniformBlocks: uniformBlocks,
    );
  }
}

/// What [countGlslBindings] counts in one stage's GLSL: a class rather than
/// a record, so a later minor can count one more kind of binding.
final class GlslBindingCount {
  /// A count of [textures] textures and [uniformBlocks] uniform blocks.
  const GlslBindingCount({required this.textures, required this.uniformBlocks});

  /// The distinct sampled textures the stage declares.
  final int textures;

  /// The distinct uniform blocks the stage declares.
  final int uniformBlocks;

  @override
  bool operator ==(Object other) =>
      other is GlslBindingCount &&
      other.textures == textures &&
      other.uniformBlocks == uniformBlocks;

  @override
  int get hashCode => Object.hash(textures, uniformBlocks);

  @override
  String toString() =>
      'GlslBindingCount(textures: $textures, uniformBlocks: $uniformBlocks)';
}

/// The distinct textures and uniform blocks [glsl] declares (its includes
/// already resolved), after `#define`, `#undef`, `#ifdef`, `#ifndef`,
/// `#else` and `#endif` are applied with [defines] set to begin with. A
/// directive it does not read (`#if <expression>`) is taken as true, which
/// counts more rather than fewer.
GlslBindingCount countGlslBindings(
  String glsl, {
  Set<String> defines = const <String>{},
}) {
  final defined = <String>{...defines};
  // One entry per open conditional: whether its branch is live, and
  // whether the enclosing one was.
  final open = <({bool live, bool outer})>[];
  var live = true;
  final kept = StringBuffer();
  final directive = RegExp(r'^\s*#\s*(\w+)\s*(\w*)');
  for (final line in glsl.split('\n')) {
    final match = directive.firstMatch(line);
    if (match == null) {
      if (live) kept.writeln(line);
      continue;
    }
    final word = match.group(2)!;
    switch (match.group(1)) {
      case 'ifdef' || 'ifndef':
        final holds = defined.contains(word) == (match.group(1) == 'ifdef');
        open.add((live: holds, outer: live));
        live = live && holds;
      case 'if':
        open.add((live: true, outer: live));
      case 'else':
        if (open.isNotEmpty) {
          final top = open.removeLast();
          open.add((live: !top.live, outer: top.outer));
          live = top.outer && !top.live;
        }
      case 'endif':
        if (open.isNotEmpty) live = open.removeLast().outer;
      case 'define' when live:
        defined.add(word);
      case 'undef' when live:
        defined.remove(word);
      default:
        break;
    }
  }
  final text = kept
      .toString()
      .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
      .replaceAll(RegExp(r'//[^\n]*'), '');
  final textures = <String>{
    for (final m in RegExp(
      r'\buniform\s+(?:(?:highp|mediump|lowp)\s+)?(?:sampler|texture)\w*\s+(\w+)',
    ).allMatches(text))
      m.group(1)!,
  };
  final blocks = <String>{
    for (final m in RegExp(r'\buniform\s+(\w+)\s*\{').allMatches(text))
      m.group(1)!,
  };
  return GlslBindingCount(
    textures: textures.length,
    uniformBlocks: blocks.length,
  );
}
