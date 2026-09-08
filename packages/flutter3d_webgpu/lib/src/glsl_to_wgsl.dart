/// The half of the road to WGSL that is ours.
///
///     GLSL (flutter3d_shaders)
///       -> prepareStage        (this file)
///       -> glslangValidator -V --auto-map-locations
///       -> naga --keep-coordinate-space
///       -> WGSL
///
/// Two external programs do the compiling and this file does everything that
/// decides what they compile — which is where every decision that can be got
/// wrong lives. Pure text in, text and reflection out, so all of it is testable
/// without either compiler present and without a browser; `wgsl_compiler.dart`
/// is the only part that needs a process, and by then the shape of the answer
/// is already settled.
///
/// Under `lib/src/` and not under `tool/`, the way
/// `flutter3d_webgl/lib/src/glsl_translate.dart` is: nothing a consumer builds
/// reaches it, since `lib/engine_shaders.dart` is a table and not a
/// translation, and a test can import it. The browser test runner serves a
/// package from `test/` and cannot read a sibling directory, so a translator in
/// `tool/` is a translator no test in this package could name.
///
/// **The `#include`s are already resolved by the time anything here runs, and
/// the caller resolves them.** `resolveIncludes` belongs to
/// `flutter3d_webgl/lib/src/glsl_translate.dart` and is reused rather than
/// rewritten — a second answer to "which headers does this shader really pull
/// in" is how two backends drift apart in the one place neither can see. It is
/// called from `tool/generate_shaders.dart` and from the tests rather than from
/// here because that package is a *dev* dependency: a backend that depended on
/// another backend at run time would not be two backends, and a file under
/// `lib/` may only import what ships.
///
/// ## Why the source has to be edited at all
///
/// The engine's GLSL targets `impellerc`, and glslang in Vulkan mode is
/// stricter about three things impellerc infers:
///
///   * a uniform block has no `set`, `binding` or packing on it — there is not
///     one `layout(set =` anywhere in `flutter3d_shaders` today;
///   * a varying has no location, and the eight vertex–fragment pairs line up
///     only because both sides take their varyings from one header in one
///     order;
///   * a sampler is one object, and everything below WGSL keeps the image and
///     the filtering state apart.
///
/// ## The sampler split, and the error that names nothing
///
/// **naga does not accept a combined sampler.** `glslangValidator` on
/// `uniform sampler2D tex; texture(tex, uv)` emits SPIR-V that `spirv-val`
/// accepts and that naga 30.0.1 refuses with `invalid id %14` — no file, no
/// line, no construct. The measurement is in `test/wgsl_pipeline_test.dart`,
/// where both spellings are compiled so the refusal is a fact this repository
/// holds rather than a thing somebody remembers.
///
/// The way out is to edit **declarations only**. Each `uniform sampler2D NAME`
/// becomes a `texture2D NAME_tex`, a `sampler NAME_smp` and a
/// `#define NAME sampler2D(NAME_tex, NAME_smp)`, after which every call site
/// passes through the macro untouched — 59 `texture()` calls and 5
/// `textureLod()` calls across the manifest, none of them rewritten, none of
/// them at risk of being rewritten wrongly. Rewriting call sites instead would
/// mean parsing GLSL expressions well enough to tell a sampler argument from
/// anything else, and getting that wrong silently is far easier than getting
/// it right.
///
/// ## What is deliberately not fixed here
///
/// `gl_FragCoord.xy` feeds a hash in exactly two places — the dither in
/// `lib/surface.glsl` and the film grain in `post/composite.frag`. Vulkan's
/// fragment coordinate has y running down and GLSL ES 3.00's has it running up,
/// so the noise pattern those two produce will not be the same picture on this
/// backend as on WebGL2. That is a golden-set question and not a translation
/// one: the shading is identical, the sample positions are not, and deciding
/// what the reference should be needs a reference set to compare against.
library;

/// Raised when a stage cannot be prepared.
///
/// Carries the file, because a message naming only a construct is a message
/// about one of nineteen hundred lines of identical-looking GLSL.
final class WgslPrepareError implements Exception {
  const WgslPrepareError(this.message);

  final String message;

  @override
  String toString() => 'WgslPrepareError: $message';
}

/// One vertex input the scan found.
///
/// [format] is a `VertexFormat`'s name and not a `VertexFormat`, and that is
/// the one shape here worth explaining. **Nothing on this path may reach
/// `package:flutter`.** `tool/ci.sh` calls every backend's generator with
/// `dart run`, on the plain Dart VM, where `package:flutter` does not compile;
/// `flutter3d_hardware` reaches it for the widget `present` returns, so
/// importing the contract here would mean a build script the CI script has no
/// way to call — which is why `webgpu_bundle_section.dart`, where the shipped
/// types with real `VertexFormat`s live, is not imported here either. The
/// generated table names `VertexFormat.<format>`, and the analyser checks the
/// spelling at the only place it can be wrong.
typedef PreparedAttribute = ({String name, int location, String format});

/// One member of a uniform block, laid out by std140.
typedef PreparedMember = ({String name, int offsetInBytes, int sizeInBytes});

/// One uniform block and where it is bound.
typedef PreparedBlock = ({
  String name,
  int group,
  int binding,
  int sizeInBytes,
  List<PreparedMember> members,
});

/// One texture-and-sampler pair and the two bindings it takes.
///
/// [dimension] is a `WebGpuTextureDimension`'s name, for the reason
/// [PreparedAttribute] gives about `format`.
typedef PreparedSampler = ({
  String name,
  int group,
  int textureBinding,
  int samplerBinding,
  String dimension,
});

/// One stage, ready for glslang, beside the reflection nothing downstream can
/// recover.
///
/// The WGSL is what the two compilers make of [glsl]; the three lists here are
/// already final, because the packer hands out the bindings rather than reading
/// them back.
final class PreparedStage {
  const PreparedStage({
    required this.glsl,
    required this.attributes,
    required this.blocks,
    required this.samplers,
  });

  /// Vulkan-flavoured GLSL 4.60: one `#version`, explicit locations, explicit
  /// `set`/`binding`/`std140`, and split samplers.
  final String glsl;

  final List<PreparedAttribute> attributes;
  final List<PreparedBlock> blocks;
  final List<PreparedSampler> samplers;
}

/// Which bind group a stage's resources live in.
///
/// **One group per stage, and that is the whole reason there are two.** The
/// engine pairs stages freely — every lighting fragment shader runs against
/// four different vertex stages — so a numbering shared across a pair would
/// have to be a numbering shared across the entire manifest, and `FrameInfo`
/// binding 0 in a vertex stage would collide with `FragInfo` binding 0 in a
/// fragment stage the moment the two met in one pipeline layout. Giving each
/// stage a group of its own makes a stage's reflection complete on its own,
/// which is what lets the packer emit it without knowing who it will be paired
/// with.
const int kVertexGroup = 0;

/// See [kVertexGroup].
const int kFragmentGroup = 1;

/// `WebGpuTextureDimension.twoDimensional`, by name.
const String kTwoDimensional = 'twoDimensional';

/// `WebGpuTextureDimension.cube`, by name.
const String kCubeDimension = 'cube';

/// Every varying [resolved] declares, for [assignVaryingLocations] to number.
///
/// A stage has to be scanned before it can be prepared, because a varying's
/// location is decided across the manifest rather than inside one file. The
/// scan is the same one the preparation runs; this is the cheap half of it.
Set<String> scanVaryings(
  String resolved, {
  required String from,
  required bool fragment,
}) {
  final scan = _Scan(from: from, fragment: fragment)..run(resolved.split('\n'));
  return <String>{for (final varying in scan.varyings) varying.name};
}

/// A location per varying name, over every stage in the manifest.
///
/// ## Why this cannot be decided one stage at a time
///
/// **WebGPU does not link.** The two modules of a pipeline are compiled apart
/// and joined by location alone, so a varying's number has to be the same on
/// both sides of every pair the engine might build. Numbering each stage's own
/// declarations — in any order, including alphabetical — makes the number a
/// function of *which* varyings that stage has, and the first shader to declare
/// one of its own shifts one side of a pair and not the other. GL would refuse
/// to link that. WebGPU accepts it and draws the wrong picture.
///
/// So the number is a function of the name, and of nothing else.
///
/// ## Why not simply sort every name in the manifest
///
/// Because there are seventeen of them and a location must be below
/// `maxInterStageShaderVariables`, which is sixteen. One flat numbering runs
/// out by one name.
///
/// Two names only ever have to agree when some stage declares both — that is
/// what makes them share a pipeline. So the names are grouped into families by
/// exactly that relation and each family is numbered from zero: the mesh
/// varyings and the sky varyings never meet in one stage, and there is no
/// pipeline in which their numbers could collide. Four families come out of the
/// manifest today, the largest with eight names in it.
///
/// Deterministic throughout — every list is sorted before it is numbered —
/// because `tool/ci.sh` regenerates the shader table and diffs it, and a
/// numbering that depended on map iteration would fail that step on a day
/// nothing had changed.
Map<String, int> assignVaryingLocations(Iterable<Set<String>> stages) {
  final family = <String, String>{};
  String rootOf(String name) {
    var root = name;
    while (family[root] != root) {
      root = family[root]!;
    }
    return root;
  }

  for (final stage in stages) {
    final names = stage.toList()..sort();
    for (final name in names) {
      family.putIfAbsent(name, () => name);
    }
    for (final name in names.skip(1)) {
      final first = rootOf(names.first);
      final other = rootOf(name);
      if (first != other) family[other] = first;
    }
  }

  final members = <String, List<String>>{};
  for (final name in family.keys.toList()..sort()) {
    (members[rootOf(name)] ??= <String>[]).add(name);
  }

  final locations = <String, int>{};
  for (final group in members.values) {
    if (group.length > kMaxInterStageVariables) {
      throw WgslPrepareError(
        'the varyings ${group.join(', ')} have to share a numbering and there '
        'are ${group.length} of them, which is more than the '
        '$kMaxInterStageVariables locations WebGPU has',
      );
    }
    for (final (index, name) in group.indexed) {
      locations[name] = index;
    }
  }
  return locations;
}

/// How many inter-stage locations WebGPU guarantees.
///
/// `maxInterStageShaderVariables`, whose floor in the specification is sixteen,
/// and a `@location` must be below it. Named here because it is the reason
/// [assignVaryingLocations] groups rather than sorts.
const int kMaxInterStageVariables = 16;

/// Prepares one stage of the manifest.
///
/// [varyingLocations] comes from [assignVaryingLocations] over every stage —
/// required rather than defaulted, because a stage numbered on its own would
/// look right and pair wrongly, and a fallback is how that would happen without
/// anybody choosing it.
///
/// ## The order bindings and locations are handed out
///
/// Written down because two runs over one source must produce the same bytes:
/// `tool/ci.sh` regenerates `lib/engine_shaders.dart` and diffs it, and a
/// numbering that depended on a hash seed or a map iteration would fail that
/// step on a day nothing had changed.
///
///   1. **Uniform blocks** take bindings `0, 1, 2, …`, sorted by block type
///      name.
///   2. **Samplers** follow, sorted by sampler name, each taking two: the
///      texture first, then the sampler.
///   3. **Varyings** — a vertex stage's `out`, a fragment stage's `in` — take
///      the location [varyingLocations] gives their name, which is the point of
///      [fragment] being told rather than guessed.
///   4. **Vertex attributes** and **fragment outputs** keep any location they
///      already declare, and anything unqualified takes the lowest free one in
///      declaration order.
///
/// Blocks and samplers are sorted by name rather than taken in declaration
/// order for a smaller version of the varyings' reason: a stage's own bindings
/// cannot collide with another stage's, since each stage has a group to itself,
/// but a numbering that moves when a header is included in a different place
/// makes a diff of this table unreadable. Sorting is the order that does not
/// depend on where a declaration was written.
///
/// Attributes and fragment outputs are numbered by declaration order instead,
/// because both are already positional by nature: the vertex layout mirrors the
/// `in` declarations byte for byte, and a fragment output's slot is the colour
/// attachment it writes.
PreparedStage prepareStage(
  String resolved, {
  required String from,
  required bool fragment,
  required Map<String, int> varyingLocations,
}) {
  final lines = resolved.split('\n');
  final scan = _Scan(from: from, fragment: fragment);
  scan.run(lines);

  final group = fragment ? kFragmentGroup : kVertexGroup;
  var binding = 0;

  final blocks = <PreparedBlock>[];
  for (final found in scan.blocks.toList()..sort(_byName)) {
    blocks.add(
      _layOutBlock(found, group: group, binding: binding++, from: from),
    );
  }

  final samplers = <PreparedSampler>[];
  for (final found in scan.samplers.toList()..sort(_byName)) {
    samplers.add((
      name: found.name,
      group: group,
      textureBinding: binding++,
      samplerBinding: binding++,
      dimension: found.dimension,
    ));
  }

  for (final found in scan.varyings) {
    if (!varyingLocations.containsKey(found.name)) {
      throw WgslPrepareError(
        '$from declares the varying "${found.name}", which was not in the '
        'manifest-wide numbering',
      );
    }
  }

  final attributes = <PreparedAttribute>[
    for (final (name, location) in _numberInOrder(scan.attributes, from: from))
      (
        name: name,
        location: location,
        format: _vertexFormat(scan.attributeType(name), name: name, from: from),
      ),
  ];
  final attributeLocation = <String, int>{
    for (final attribute in attributes) attribute.name: attribute.location,
  };
  final outputLocation = <String, int>{
    for (final (name, location) in _numberInOrder(scan.outputs, from: from))
      name: location,
  };

  // The rewrite, by line index, so nothing but the declarations moves and a
  // diff against the original source stays a diff about declarations.
  final edited = List<String>.of(lines);
  final needsSamplerless = scan.samplerlessUses.isNotEmpty;
  final byName = <String, PreparedSampler>{
    for (final sampler in samplers) sampler.name: sampler,
  };

  for (final found in scan.blocks) {
    final block = blocks.firstWhere(
      (candidate) => candidate.name == found.name,
    );
    edited[found.line] =
        'layout(set = ${block.group}, binding = ${block.binding}, std140) '
        'uniform ${found.name} {';
  }
  for (final found in scan.samplers) {
    final sampler = byName[found.name]!;
    final cube = found.dimension == kCubeDimension;
    final texture = cube ? 'textureCube' : 'texture2D';
    final combined = cube ? 'samplerCube' : 'sampler2D';
    edited[found.line] =
        'layout(set = ${sampler.group}, binding = ${sampler.textureBinding}) '
        'uniform $texture ${found.name}_tex;\n'
        'layout(set = ${sampler.group}, binding = ${sampler.samplerBinding}) '
        'uniform sampler ${found.name}_smp;\n'
        '#define ${found.name} '
        '$combined(${found.name}_tex, ${found.name}_smp)';
  }
  for (final found in scan.varyings) {
    edited[found.line] = _qualified(found, varyingLocations[found.name]!);
  }
  for (final found in scan.attributes) {
    edited[found.line] = _qualified(found, attributeLocation[found.name]!);
  }
  for (final found in scan.outputs) {
    edited[found.line] = _qualified(found, outputLocation[found.name]!);
  }

  final header = StringBuffer('#version 460 core\n');
  if (needsSamplerless) {
    // A texture read with no sampler in it — `texelFetch`, `textureSize` — is
    // legal GLSL on a combined sampler and needs stating once the two are
    // apart. Nothing in the manifest reaches for one today; the extension is
    // emitted from a measurement of the source rather than from a habit, so the
    // day one appears it arrives already declared instead of failing to
    // compile.
    header.writeln('#extension GL_EXT_samplerless_texture_functions : require');
  }
  header.write(edited.where((line) => !_version.hasMatch(line)).join('\n'));

  return PreparedStage(
    glsl: header.toString(),
    attributes: attributes,
    blocks: blocks,
    samplers: samplers,
  );
}

int _byName(_Named a, _Named b) => a.name.compareTo(b.name);

String _qualified(_Variable found, int location) =>
    'layout(location = $location) '
    '${found.direction} ${found.qualifiers}${found.type} ${found.name};';

/// Locations for declarations that are positional: the ones that already state
/// a location keep it, and the rest take the lowest number nobody has claimed,
/// in the order they were written.
Iterable<(String, int)> _numberInOrder(
  List<_Variable> found, {
  required String from,
}) sync* {
  final taken = <int>{
    for (final variable in found)
      if (variable.location != null) variable.location!,
  };
  var next = 0;
  for (final variable in found) {
    final declared = variable.location;
    if (declared != null) {
      yield (variable.name, declared);
      continue;
    }
    while (taken.contains(next)) {
      next++;
    }
    taken.add(next);
    yield (variable.name, next);
  }
  if (taken.length != found.length) {
    throw WgslPrepareError('$from declares two of something at one location');
  }
}

/// A `VertexFormat`'s name for a GLSL attribute type.
///
/// The contract's spelling and WebGPU's spelling are the same word —
/// `float32x3` either way — which is why `gpuVertexFormat` in
/// `lib/src/webgpu_formats.dart` is an identity mapping and why this can return
/// a name without choosing between the two.
String _vertexFormat(
  String type, {
  required String name,
  required String from,
}) => switch (type) {
  'float' => 'float32',
  'vec2' => 'float32x2',
  'vec3' => 'float32x3',
  'vec4' => 'float32x4',
  'int' => 'sint32',
  'ivec2' => 'sint32x2',
  'ivec3' => 'sint32x3',
  'ivec4' => 'sint32x4',
  'uint' => 'uint32',
  'uvec2' => 'uint32x2',
  'uvec3' => 'uint32x3',
  'uvec4' => 'uint32x4',
  _ => throw WgslPrepareError(
    '$from declares the attribute "$name" as "$type", which is not a vertex '
    'format the contract has',
  ),
};

PreparedBlock _layOutBlock(
  _Block found, {
  required int group,
  required int binding,
  required String from,
}) {
  var offset = 0;
  final members = <PreparedMember>[];
  for (final member in found.members) {
    final (:align, :size) = _std140(
      member.type,
      member.count,
      name: member.name,
      from: from,
    );
    offset = _roundUp(offset, align);
    members.add((name: member.name, offsetInBytes: offset, sizeInBytes: size));
    offset += size;
  }
  return (
    name: found.name,
    group: group,
    binding: binding,
    // std140 rounds a structure up to the alignment of its widest member, which
    // for anything in this engine is a vec4. Stated rather than left to the
    // last member's size, because a block ending in a `vec2` would otherwise be
    // written eight bytes short of what the GPU reads.
    sizeInBytes: _roundUp(offset, 16),
    members: members,
  );
}

/// std140 alignment and size for a member.
///
/// The rules are the specification's, narrowed to what this engine writes and
/// refusing everything else. `flutter3d_shaders` uses exactly two types in a
/// uniform block today — `vec4` and `mat4`, each on its own or as an array —
/// and a member that is neither should stop the build rather than be laid out
/// by a guess.
({int align, int size}) _std140(
  String type,
  int? count, {
  required String name,
  required String from,
}) {
  final (align: elementAlign, size: elementSize) = switch (type) {
    'float' || 'int' || 'uint' || 'bool' => (align: 4, size: 4),
    'vec2' || 'ivec2' || 'uvec2' => (align: 8, size: 8),
    'vec3' || 'ivec3' || 'uvec3' => (align: 16, size: 12),
    'vec4' || 'ivec4' || 'uvec4' => (align: 16, size: 16),
    // A matrix is an array of its columns, and each column is padded to a vec4.
    'mat2' => (align: 16, size: 32),
    'mat3' => (align: 16, size: 48),
    'mat4' => (align: 16, size: 64),
    _ => throw WgslPrepareError(
      '$from declares the uniform "$name" as "$type", which this packer has no '
      'std140 rule for',
    ),
  };
  if (count == null) return (align: elementAlign, size: elementSize);
  // An array's stride is its element rounded up to a vec4, whatever the element
  // was. That is the rule that makes `vec4 x[8]` a hundred and twenty-eight
  // bytes and `float x[8]` a hundred and twenty-eight bytes as well.
  final stride = elementSize <= 16 ? 16 : _roundUp(elementSize, 16);
  return (align: 16, size: stride * count);
}

int _roundUp(int value, int alignment) =>
    (value + alignment - 1) ~/ alignment * alignment;

/// A declaration the scan found, by the name the rest of the pipeline knows it
/// by.
abstract interface class _Named {
  String get name;
}

final class _Variable implements _Named {
  const _Variable({
    required this.line,
    required this.name,
    required this.direction,
    required this.qualifiers,
    required this.type,
    required this.location,
  });

  final int line;
  @override
  final String name;
  final String direction;
  final String qualifiers;
  final String type;
  final int? location;
}

final class _Block implements _Named {
  const _Block({required this.line, required this.name, required this.members});

  final int line;
  @override
  final String name;
  final List<_Member> members;
}

final class _Member {
  const _Member({required this.name, required this.type, required this.count});

  final String name;
  final String type;

  /// Null when the member is not an array.
  final int? count;
}

final class _Sampler implements _Named {
  const _Sampler({
    required this.line,
    required this.name,
    required this.dimension,
  });

  final int line;
  @override
  final String name;

  /// A `WebGpuTextureDimension`'s name — see [PreparedAttribute] on why this
  /// side of the pipeline speaks in names.
  final String dimension;
}

/// One pass over the resolved text, collecting declarations that are live.
///
/// **Live is the word that matters.** `lib/surface.glsl` puts its point-shadow
/// sampler and its `PointShadow` block behind `#ifndef F3D_NO_POINT_SHADOW`,
/// and `lighting/unlit.frag` defines that symbol before including it. A scan
/// that ignored the guard would put a block into the reflection that the
/// compiled shader does not contain, and the engine would bind a buffer to a
/// slot that is not there — which is a native crash on one backend and a draw
/// discarded with nothing logged on another. Both are written up in that
/// header, which is how we know what it costs.
final class _Scan {
  _Scan({required this.from, required this.fragment});

  final String from;
  final bool fragment;

  final defined = <String>{};
  final constants = <String, int>{};
  final conditions = <bool>[];

  final attributes = <_Variable>[];
  final varyings = <_Variable>[];
  final outputs = <_Variable>[];
  final blocks = <_Block>[];
  final samplers = <_Sampler>[];
  final samplerlessUses = <String>{};

  bool get live => !conditions.contains(false);

  String attributeType(String name) =>
      attributes.firstWhere((candidate) => candidate.name == name).type;

  void run(List<String> lines) {
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (_handleDirective(line)) continue;
      if (!live) continue;

      for (final match in _samplerless.allMatches(line)) {
        samplerlessUses.add(match.group(1)!);
      }

      final constant = _constant.firstMatch(line);
      if (constant != null) {
        constants[constant.group(1)!] = int.parse(constant.group(2)!);
        continue;
      }

      final sampler = _sampler.firstMatch(line);
      if (sampler != null) {
        samplers.add(
          _Sampler(
            line: i,
            name: sampler.group(2)!,
            dimension: sampler.group(1) == 'samplerCube'
                ? kCubeDimension
                : kTwoDimensional,
          ),
        );
        continue;
      }

      final block = _blockStart.firstMatch(line);
      if (block != null) {
        final (:members, :end) = _members(lines, i);
        blocks.add(_Block(line: i, name: block.group(1)!, members: members));
        // Past the closing brace, so the body is read exactly once. It matters
        // for the conditionals: `_members` evaluates directives too, and a
        // second pass over the same `#ifndef` would push a branch onto the
        // stack that nothing ever pops.
        i = end;
        continue;
      }

      final variable = _variable.firstMatch(line);
      if (variable != null) _collect(i, variable);
    }
    if (conditions.isNotEmpty) {
      throw WgslPrepareError('$from has a conditional nobody closed');
    }
  }

  void _collect(int line, RegExpMatch match) {
    final declared = match.group(1);
    final direction = match.group(2)!;
    final variable = _Variable(
      line: line,
      name: match.group(5)!,
      direction: direction,
      qualifiers: match.group(3)!,
      type: match.group(4)!,
      location: declared == null ? null : int.parse(declared),
    );
    // A vertex stage's inputs are the vertex layout and its outputs are
    // varyings; a fragment stage's inputs are varyings and its outputs are
    // colour attachments. Told by [fragment] rather than inferred from a naming
    // convention, because a convention is a thing a new shader can be written
    // without knowing about.
    if (direction == 'in') {
      (fragment ? varyings : attributes).add(variable);
    } else {
      (fragment ? outputs : varyings).add(variable);
    }
  }

  ({List<_Member> members, int end}) _members(List<String> lines, int start) {
    final members = <_Member>[];
    for (var i = start + 1; i < lines.length; i++) {
      final line = lines[i];
      if (_handleDirective(line)) continue;
      if (line.trimLeft().startsWith('}')) {
        return (members: members, end: i);
      }
      if (!live) continue;
      final member = _member.firstMatch(line);
      if (member == null) continue;
      final size = member.group(3);
      members.add(
        _Member(
          name: member.group(2)!,
          type: member.group(1)!,
          count: size == null ? null : _evaluate(size),
        ),
      );
    }
    throw WgslPrepareError('$from opens a uniform block and never closes it');
  }

  /// True when [line] was a preprocessor directive and has been accounted for.
  bool _handleDirective(String line) {
    final directive = _directive.firstMatch(line);
    if (directive == null) return false;
    final keyword = directive.group(1)!;
    final rest = directive.group(2)!.trim();
    switch (keyword) {
      case 'ifndef':
        conditions.add(!defined.contains(rest));
      case 'ifdef':
        conditions.add(defined.contains(rest));
      case 'else':
        if (conditions.isEmpty) {
          throw WgslPrepareError('$from has an #else outside a conditional');
        }
        conditions[conditions.length - 1] = !conditions.last;
      case 'endif':
        if (conditions.isEmpty) {
          throw WgslPrepareError('$from has an #endif outside a conditional');
        }
        conditions.removeLast();
      case 'define':
        if (live) {
          final define = _define.firstMatch(rest);
          if (define != null) {
            defined.add(define.group(1)!);
            final value = define.group(2)?.trim();
            final number = value == null ? null : int.tryParse(value);
            if (number != null) constants[define.group(1)!] = number;
          }
        }
      case 'version' || 'extension' || 'line' || 'pragma':
        break;
      default:
        // `#if` and `#elif` take expressions, and an evaluator for them would
        // be a second GLSL preprocessor written on the assumption that nobody
        // will use it in anger. Refusing is the honest answer: the day a shader
        // needs one, this stops rather than quietly deciding which branch was
        // meant.
        throw WgslPrepareError(
          '$from uses "#$keyword", which this scan does not evaluate',
        );
    }
    return true;
  }

  /// An array size, as the source writes it.
  ///
  /// `vec4 light_position[kMaxLights]` and `mat4 faces[6 * kShadowSlots]` are
  /// both in the manifest, so the sizes are constants and small arithmetic on
  /// them rather than literals. Sums of products and nothing more — a shader
  /// that needs more than that should say so by failing here.
  int _evaluate(String expression) {
    var total = 0;
    for (final term in expression.split('+')) {
      var product = 1;
      for (final factor in term.split('*')) {
        final text = factor.trim();
        final literal = int.tryParse(text);
        final value = literal ?? constants[text];
        if (value == null) {
          throw WgslPrepareError(
            '$from sizes an array by "$expression", and "$text" is not a '
            'constant this scan saw',
          );
        }
        product *= value;
      }
      total += product;
    }
    return total;
  }
}

final RegExp _version = RegExp(r'^\s*#version\b');
final RegExp _directive = RegExp(r'^\s*#\s*(\w+)\b(.*)$');
final RegExp _define = RegExp(r'^(\w+)(?:\s+(.*))?$');
final RegExp _constant = RegExp(
  r'^\s*const\s+(?:int|uint)\s+(\w+)\s*=\s*(\d+)\s*;',
);
final RegExp _sampler = RegExp(
  r'^\s*uniform\s+(sampler2D|samplerCube)\s+(\w+)\s*;',
);
final RegExp _blockStart = RegExp(r'^\s*uniform\s+([A-Z]\w*)\s*\{\s*$');
final RegExp _member = RegExp(r'^\s*(\w+)\s+(\w+)\s*(?:\[([^\]]+)\])?\s*;');
final RegExp _variable = RegExp(
  r'^\s*(?:layout\s*\(\s*location\s*=\s*(\d+)\s*\)\s*)?'
  r'(in|out)\s+'
  r'((?:(?:flat|smooth|noperspective|centroid)\s+)*)'
  r'(\w+)\s+(\w+)\s*;\s*$',
);
final RegExp _samplerless = RegExp(
  r'\b(?:texelFetch|textureSize)\s*\(\s*(\w+)',
);
