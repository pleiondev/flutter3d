/// What a stage takes in and hands on, and the check that the stages of a
/// pipeline agree before they reach a device.
library;

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show Flutter3dFormatException;

/// One variable a stage reads or writes across its boundary: a vertex
/// attribute, a varying, a fragment output.
final class StageVariable {
  const StageVariable(this.name, this.type, {this.location});

  /// The name the GLSL declares.
  final String name;

  /// The GLSL type: `vec3`, `float`, `mat4`.
  final String type;

  /// The location a `layout(location = N)` gives it, or null where the
  /// translator numbers it.
  final int? location;

  @override
  bool operator ==(Object other) =>
      other is StageVariable &&
      other.name == name &&
      other.type == type &&
      other.location == location;

  @override
  int get hashCode => Object.hash(name, type, location);

  @override
  String toString() =>
      '${location == null ? '' : 'layout(location = $location) '}$type $name';
}

/// One member of a uniform block, in the order the block declares it.
final class StageBlockMember {
  const StageBlockMember(this.name, this.type);

  final String name;
  final String type;

  @override
  bool operator ==(Object other) =>
      other is StageBlockMember && other.name == name && other.type == type;

  @override
  int get hashCode => Object.hash(name, type);

  @override
  String toString() => '$type $name';
}

/// What one stage of a pipeline declares at its edges: what comes in, what
/// goes out, and the uniform blocks it reads.
///
/// **What the stage agreement check reads** (amendment 5 of the field
/// review). The bundle writer makes one per stage, from the GLSL after its
/// includes are resolved ([StageInterface.fromGlsl]) or from a backend's
/// reflection, and holds the stages of every pipeline to each other with
/// [checkStageAgreement]; a mismatch is a build error naming both stages,
/// not a crash on one backend at the first draw.
final class StageInterface {
  const StageInterface({
    required this.name,
    required this.fragment,
    this.inputs = const <StageVariable>[],
    this.outputs = const <StageVariable>[],
    this.blocks = const <String, List<StageBlockMember>>{},
  });

  /// Reads the declarations of [glsl] — a stage's source with its
  /// `#include`s already resolved — as the engine's GLSL writes them: `in`
  /// and `out` at the top level, with or without a `layout(location = N)`,
  /// and `uniform Name { … }` blocks. Comments are skipped; anything else
  /// (a function's own locals, a `#define`) is not a declaration here.
  factory StageInterface.fromGlsl(
    String glsl, {
    required String name,
    required bool fragment,
  }) {
    final text = glsl
        .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), ' ')
        .replaceAll(RegExp(r'//[^\n]*'), '');
    final inputs = <StageVariable>[];
    final outputs = <StageVariable>[];
    for (final match in _variable.allMatches(text)) {
      final location = match.group(1);
      final variable = StageVariable(
        match.group(4)!,
        match.group(3)!,
        location: location == null ? null : int.parse(location),
      );
      (match.group(2) == 'in' ? inputs : outputs).add(variable);
    }
    final blocks = <String, List<StageBlockMember>>{
      for (final match in _block.allMatches(text))
        match.group(1)!: <StageBlockMember>[
          for (final member in _member.allMatches(match.group(2)!))
            StageBlockMember(member.group(2)!, member.group(1)!),
        ],
    };
    return StageInterface(
      name: name,
      fragment: fragment,
      inputs: inputs,
      outputs: outputs,
      blocks: blocks,
    );
  }

  /// The entry point's name.
  final String name;

  /// Whether this is a fragment stage.
  final bool fragment;

  /// For a vertex stage its attributes, for a fragment stage its varyings.
  final List<StageVariable> inputs;

  /// For a vertex stage its varyings, for a fragment stage its colour
  /// outputs.
  final List<StageVariable> outputs;

  /// Each uniform block it declares, by name, with its members in order.
  final Map<String, List<StageBlockMember>> blocks;

  static final RegExp _variable = RegExp(
    r'^\s*(?:layout\s*\(\s*location\s*=\s*(\d+)\s*\)\s*)?'
    r'(?:flat\s+|smooth\s+|noperspective\s+)?(in|out)\s+'
    r'(?:highp\s+|mediump\s+|lowp\s+)?(\w+)\s+(\w+)\s*;',
    multiLine: true,
  );

  static final RegExp _block = RegExp(
    r'^\s*(?:layout\s*\([^)]*\)\s*)?uniform\s+(\w+)\s*\{([^}]*)\}',
    multiLine: true,
  );

  static final RegExp _member = RegExp(
    r'(?:highp\s+|mediump\s+|lowp\s+)?(\w+)\s+(\w+(?:\s*\[\s*\w+\s*\])?)\s*;',
  );
}

/// What kind of disagreement a [StageMismatch] is.
///
/// An open set (S0): a later check — a sampler's type, a push constant —
/// adds a kind and breaks no `switch`.
final class StageMismatchKind {
  const StageMismatchKind._(this.name);

  /// A fragment stage reads a varying the vertex stage does not write, or
  /// both declare it with another type or location.
  static const StageMismatchKind varying = StageMismatchKind._('varying');

  /// A vertex stage reads an attribute the pipeline's vertex layout does
  /// not give it, or gives it as another type.
  static const StageMismatchKind attribute = StageMismatchKind._('attribute');

  /// Two stages declare one uniform block with different members.
  static const StageMismatchKind block = StageMismatchKind._('block');

  static const List<StageMismatchKind> values = <StageMismatchKind>[
    varying,
    attribute,
    block,
  ];

  /// The kind called [name], or null for one this version does not know.
  static StageMismatchKind? byName(String name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  /// The stable name, and the wire name.
  final String name;

  @override
  String toString() => 'StageMismatchKind.$name';
}

/// One way two stages of a pipeline disagree, with the names a person
/// fixes it by.
final class StageMismatch {
  const StageMismatch({
    required this.kind,
    required this.name,
    required this.says,
  });

  final StageMismatchKind kind;

  /// The varying, the attribute or the block they disagree about.
  final String name;

  /// The sentence that names both stages and what each declares.
  final String says;

  @override
  String toString() => 'StageMismatch(${kind.name} $name): $says';
}

/// Whether [vertex] and [fragment], the stages of one pipeline, agree —
/// and with [attributes], the vertex layout the pipeline is drawn with,
/// when it is known. Every mismatch, in the order found; empty when they
/// agree.
///
/// **The check the bundle writer runs over every pipeline it writes**
/// (amendment 5): before this, a fragment stage reading a varying its vertex
/// stage never wrote compiled on every backend and drew zeros on one,
/// garbage on another, and failed to link on a third.
///
/// What it holds:
///
/// - every input of [fragment] is an output of [vertex] with the same
///   type, and the same location where both state one ([StageMismatchKind.varying]);
///   an output nobody reads is not a mismatch;
/// - every input of [vertex] is in [attributes] with the same type, where
///   [attributes] is given ([StageMismatchKind.attribute]);
/// - a uniform block both stages declare has the same members, in the same
///   order, with the same types ([StageMismatchKind.block]).
List<StageMismatch> checkStageAgreement({
  required StageInterface vertex,
  required StageInterface fragment,
  List<StageVariable>? attributes,
}) {
  final found = <StageMismatch>[];
  final pair = '"${vertex.name}" and "${fragment.name}"';
  for (final input in fragment.inputs) {
    final output = vertex.outputs.where((o) => o.name == input.name);
    if (output.isEmpty) {
      found.add(
        StageMismatch(
          kind: StageMismatchKind.varying,
          name: input.name,
          says:
              '"${fragment.name}" reads the varying ${input.name}, which '
              '"${vertex.name}" does not write',
        ),
      );
      continue;
    }
    final written = output.first;
    if (written.type != input.type ||
        (written.location != null &&
            input.location != null &&
            written.location != input.location)) {
      found.add(
        StageMismatch(
          kind: StageMismatchKind.varying,
          name: input.name,
          says:
              '$pair disagree about the varying ${input.name}: '
              '"${vertex.name}" writes $written, "${fragment.name}" reads $input',
        ),
      );
    }
  }
  if (attributes != null) {
    for (final input in vertex.inputs) {
      final given = attributes.where((a) => a.name == input.name);
      if (given.isEmpty) {
        found.add(
          StageMismatch(
            kind: StageMismatchKind.attribute,
            name: input.name,
            says:
                '"${vertex.name}" reads the attribute ${input.name}, which the '
                'vertex layout does not give it',
          ),
        );
      } else if (given.first.type != input.type) {
        found.add(
          StageMismatch(
            kind: StageMismatchKind.attribute,
            name: input.name,
            says:
                '"${vertex.name}" reads ${input.name} as ${input.type}, and the '
                'vertex layout gives it as ${given.first.type}',
          ),
        );
      }
    }
  }
  for (final MapEntry(key: block, value: members) in vertex.blocks.entries) {
    final other = fragment.blocks[block];
    if (other == null || _sameMembers(members, other)) continue;
    found.add(
      StageMismatch(
        kind: StageMismatchKind.block,
        name: block,
        says:
            '$pair declare the block $block differently: '
            '{${members.join('; ')}} against {${other.join('; ')}}',
      ),
    );
  }
  return found;
}

bool _sameMembers(List<StageBlockMember> a, List<StageBlockMember> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// A bundle the writer refused because the stages of one of its pipelines
/// disagree: every [StageMismatch] found, each naming both stages.
///
/// **A build error with names, not a crash on one backend** (amendment 5).
/// The section writers throw it before a byte is written, so the stage that
/// would have drawn zeros on one device and failed to link on another
/// never reaches either.
final class StageAgreementException extends Flutter3dFormatException {
  StageAgreementException(Iterable<StageMismatch> mismatches)
    : mismatches = List<StageMismatch>.unmodifiable(mismatches);

  /// What disagrees, in the order found.
  final List<StageMismatch> mismatches;

  @override
  String get message =>
      'the stages of a pipeline disagree, so no bundle is written: '
      '${mismatches.map((m) => m.says).join('; ')}';

  @override
  String toString() => 'StageAgreementException: $message';
}

/// The fragment stage of [fragments] that the vertex stage [vertex] is drawn
/// with in a bundle, by the names the material language and the engine give
/// their stages, or null when its name pairs it with none.
///
/// A vertex stage `<F>Vertex` belongs to the fragment stage `<F>`, and so do
/// its halves — `<F>VertexSkinned`, `<F>VertexInstanced`,
/// `<F>VertexLightmapped` — which is how a material's `vertex` block names
/// the stages it becomes. A shared vertex stage (`MeshVertex`) pairs with no
/// fragment stage by name, and is held to the ones it is drawn with where a
/// pipeline names them.
String? pairedFragmentStage(String vertex, Set<String> fragments) {
  final half = _halves.where(vertex.endsWith).firstOrNull;
  final stem = half == null
      ? vertex
      : vertex.substring(0, vertex.length - half.length);
  if (!stem.endsWith('Vertex')) return null;
  final base = stem.substring(0, stem.length - 'Vertex'.length);
  return base.isNotEmpty && fragments.contains(base) ? base : null;
}

const List<String> _halves = <String>['Skinned', 'Instanced', 'Lightmapped'];

/// Every mismatch between the stages of a bundle that are drawn together:
/// [vertex] and [fragment] are the GLSL of each stage by name, includes
/// resolved, and each vertex stage is held to the fragment stage
/// [pairedFragmentStage] names. Empty when they agree.
List<StageMismatch> checkBundleAgreement({
  required Map<String, String> vertex,
  required Map<String, String> fragment,
}) {
  final fragments = fragment.keys.toSet();
  return <StageMismatch>[
    for (final MapEntry(key: name, value: glsl) in vertex.entries)
      if (pairedFragmentStage(name, fragments) case final paired?)
        ...checkStageAgreement(
          vertex: StageInterface.fromGlsl(glsl, name: name, fragment: false),
          fragment: StageInterface.fromGlsl(
            fragment[paired]!,
            name: paired,
            fragment: true,
          ),
        ),
  ];
}

/// Throws a [StageAgreementException] when [checkBundleAgreement] finds
/// anything: what a bundle's section writer calls before it writes.
void requireBundleAgreement({
  required Map<String, String> vertex,
  required Map<String, String> fragment,
}) {
  final found = checkBundleAgreement(vertex: vertex, fragment: fragment);
  if (found.isNotEmpty) throw StageAgreementException(found);
}
