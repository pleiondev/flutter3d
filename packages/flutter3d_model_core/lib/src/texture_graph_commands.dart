/// The six node-by-node verbs `TextureGraphPanel` (`mat-13`) edits a
/// material's own [TextureGraph] with.
///
/// **`SetMaterialGraph` swaps the whole graph; these swap one piece of it.**
/// The same split [AddMaterial] and [SetMaterialField] already draw for a
/// material's own fields — one command to hand a material something to edit,
/// several fine-grained ones to edit it — drawn here one level down, over
/// the nodes inside a graph rather than the graph itself.
///
/// **A node's own fields are read back through [TextureNode.fromJson], not a
/// `copyWith` this file invents.** [TextureNode.inputs]' own keys are, for
/// every one of the eleven kinds, exactly the field name [TextureNode.toJson]
/// writes for that socket (`BlendTextureNode`'s `base`/`overlay`,
/// `ChannelsTextureNode`'s `source`, `NormalFromHeightTextureNode`'s
/// `height`, `OutputTextureNode`'s `result`) — so [Link], [Unlink] and
/// [SetNodeField] all reduce to the same operation: take a node's own JSON,
/// change one key, read it back. A value [TextureNode.fromJson] would refuse
/// is a value these refuse too, for the same reason and with the same kind of
/// sentence.
///
/// **A position is not a node field.** [MoveNode] writes to
/// [TextureGraph.positions] instead, and — alone among this file's six —
/// does not bump [ProjectMaterial.version]: nothing a panel drags a node to
/// changes a pixel [BakeTextureGraph] would produce, so a drag leaving
/// [ProjectMaterial.isGraphStale] true would be asking for a rebake that
/// cannot change the result.
///
/// **No node is protected from [RemoveNode], `output` included.** Nothing
/// else in this file — or in [TextureGraph] itself — requires a graph to
/// keep even one: a fresh graph starts with none, [SetMaterialGraph] takes
/// whatever [TextureGraph.fromJson] reads back, and the one place an absent
/// output actually matters, [BakeTextureGraph], already refuses on its own
/// terms ("the texture graph feeds no material slot") rather than an
/// edit-time rule here duplicating that refusal ahead of time.
part of 'command.dart';

/// [node] with [field] set to [value], or null when [field] is not one of its
/// fields, or [value] is the wrong shape for it.
///
/// Shared by [Link] (setting an input to a source id), [Unlink] (setting one
/// to null) and [SetNodeField] (setting any other field) — see the library
/// comment for why one function answers all three.
TextureNode? _textureNodeWith(TextureNode node, String field, Object? value) {
  final json = <String, Object?>{
    'id': node.id,
    'kind': node.kind,
    ...node.toJson(),
    field: value,
  };
  try {
    return TextureNode.fromJson(json);
  } on FormatException {
    return null;
  }
}

/// The material at [materialIndex] in [project], or null with a refusal
/// already built — the bounds check every one of this file's five commands
/// starts with.
(ProjectMaterial?, Outcome?) _materialAt(
  ModelProject project,
  int materialIndex,
) {
  if (materialIndex < 0 || materialIndex >= project.materials.length) {
    return (null, Outcome.refused('there is no material $materialIndex'));
  }
  return (project.materials[materialIndex], null);
}

/// [project] with the material at [materialIndex] replaced by [next].
ModelProject _withMaterial(
  ModelProject project,
  int materialIndex,
  ProjectMaterial next,
) => project.copyWith(
  materials: <ProjectMaterial>[
    for (var i = 0; i < project.materials.length; i++)
      i == materialIndex ? next : project.materials[i],
  ],
);

/// Adds one node to a material's [TextureGraph], creating the graph itself
/// first if the material had none.
///
/// **[fields] is [TextureNode.fromJson]'s own shape, minus `id` and `kind`.**
/// This command hands out the id itself, from [ModelProject.nextId] — the
/// same allocator every other "add a thing" command already shares — so a
/// node's id is unique across the whole project, not merely within its own
/// graph. A kind with a required field (`image`'s own `imageId`, `blend`'s
/// own `mode`) refuses the command when [fields] leaves it out, the same way
/// leaving it out of a hand-written `.json` file would.
final class AddNode extends ModelCommand {
  const AddNode({
    required this.materialIndex,
    required this.kind,
    this.fields = const <String, Object?>{},
    this.position = (0.0, 0.0),
  });

  final int materialIndex;

  /// [TextureNode.kind]'s own word: `image`, `color`, `blend`, `channels`,
  /// `levels`, `invert`, `uvTransform`, `checker`, `noise`,
  /// `normalFromHeight` or `output`.
  final String kind;

  /// Every field [TextureNode.fromJson] reads beyond `id` and `kind`.
  final Map<String, Object?> fields;

  /// Where `TextureGraphPanel` draws the new node. See
  /// [TextureGraph.positions].
  final (double x, double y) position;

  @override
  String get name => 'addNode';

  @override
  String get says => 'add a $kind node';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'materialIndex': materialIndex,
    'kind': kind,
    'fields': fields,
    'x': position.$1,
    'y': position.$2,
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    final (material, refusal) = _materialAt(project, materialIndex);
    if (material == null) return refusal!;
    final int id = project.nextId;
    final TextureNode node;
    try {
      node = TextureNode.fromJson(<String, Object?>{
        'id': id,
        'kind': kind,
        ...fields,
      });
    } on FormatException catch (error) {
      return Outcome.refused('"$kind" did not make a node: ${error.message}');
    }
    final TextureGraph graph = material.graph ?? const TextureGraph();
    final nextGraph = TextureGraph(
      nodes: <TextureNode>[...graph.nodes, node],
      positions: <int, (double, double)>{...graph.positions, id: position},
    );
    return Outcome.done(
      ModelProject(
        profile: project.profile,
        objects: project.objects,
        materials: <ProjectMaterial>[
          for (var i = 0; i < project.materials.length; i++)
            i == materialIndex
                ? material.withGraph(nextGraph)
                : project.materials[i],
        ],
        images: project.images,
        nextId: id + 1,
        skeletons: project.skeletons,
        clips: project.clips,
        lighting: project.lighting,
      ),
    );
  }
}

/// Wires [from]'s output into [nodeId]'s input socket named [input].
///
/// **Refused before it is applied, not applied and left broken.** Wiring a
/// `color`-typed output into a `scalar`-typed input — the plan's own "Цвет→
/// маска отвергнута" — is caught by running [TextureGraph.validate] against
/// the graph this link would produce, the same check [BakeTextureGraph] runs
/// before it bakes, so a panel never shows a link [TextureGraph.validate]
/// would have complained about.
final class Link extends ModelCommand {
  const Link({
    required this.materialIndex,
    required this.nodeId,
    required this.input,
    required this.from,
  });

  final int materialIndex;
  final int nodeId;

  /// One of the target node's own [TextureNode.inputs] keys.
  final String input;

  /// The node whose output feeds [input].
  final int from;

  @override
  String get name => 'link';

  @override
  String get says => 'connect a link';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'materialIndex': materialIndex,
    'nodeId': nodeId,
    'input': input,
    'from': from,
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    final (material, refusal) = _materialAt(project, materialIndex);
    if (material == null) return refusal!;
    final TextureGraph? graph = material.graph;
    if (graph == null) {
      return Outcome.refused('material $materialIndex has no texture graph');
    }
    final TextureNode? node = graph.nodeById(nodeId);
    if (node == null) return Outcome.refused('there is no node $nodeId');
    if (!node.inputs.containsKey(input)) {
      return Outcome.refused('node $nodeId has no input "$input"');
    }
    if (graph.nodeById(from) == null) {
      return Outcome.refused('there is no node $from to link from');
    }
    final TextureNode? replaced = _textureNodeWith(node, input, from);
    if (replaced == null) {
      return Outcome.refused('"$input" cannot take a link');
    }
    final nextGraph = TextureGraph(
      nodes: <TextureNode>[
        for (final n in graph.nodes) n.id == nodeId ? replaced : n,
      ],
      positions: graph.positions,
    );
    final issues = nextGraph.validate();
    if (issues.isNotEmpty) {
      return Outcome.refused('that link is not valid: ${issues.first.message}');
    }
    return Outcome.done(
      _withMaterial(project, materialIndex, material.withGraph(nextGraph)),
    );
  }
}

/// Takes whatever is wired into [nodeId]'s [input] socket back off it.
final class Unlink extends ModelCommand {
  const Unlink({
    required this.materialIndex,
    required this.nodeId,
    required this.input,
  });

  final int materialIndex;
  final int nodeId;
  final String input;

  @override
  String get name => 'unlink';

  @override
  String get says => 'remove a link';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'materialIndex': materialIndex,
    'nodeId': nodeId,
    'input': input,
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    final (material, refusal) = _materialAt(project, materialIndex);
    if (material == null) return refusal!;
    final TextureGraph? graph = material.graph;
    if (graph == null) {
      return Outcome.refused('material $materialIndex has no texture graph');
    }
    final TextureNode? node = graph.nodeById(nodeId);
    if (node == null) return Outcome.refused('there is no node $nodeId');
    if (!node.inputs.containsKey(input)) {
      return Outcome.refused('node $nodeId has no input "$input"');
    }
    final TextureNode replaced = _textureNodeWith(node, input, null)!;
    final nextGraph = TextureGraph(
      nodes: <TextureNode>[
        for (final n in graph.nodes) n.id == nodeId ? replaced : n,
      ],
      positions: graph.positions,
    );
    return Outcome.done(
      _withMaterial(project, materialIndex, material.withGraph(nextGraph)),
    );
  }
}

/// Sets one non-link field of a node — [SetMaterialField]'s own shape, one
/// node down.
///
/// **Refuses a link's own name.** `blend`'s `base` and `overlay`, `channels`'
/// `source` and the rest are [Link]'s and [Unlink]'s to change; a value here
/// naming one of them is refused rather than quietly rewiring the graph
/// through the wrong verb.
final class SetNodeField extends ModelCommand {
  const SetNodeField({
    required this.materialIndex,
    required this.nodeId,
    required this.field,
    required this.value,
  });

  final int materialIndex;
  final int nodeId;
  final String field;

  /// A number, a string, a bool, or a list of two, three or four numbers,
  /// depending on [field] — the same shapes [TextureNode.toJson] writes.
  final Object? value;

  @override
  String get name => 'setNodeField';

  @override
  String get says => 'set $field';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'materialIndex': materialIndex,
    'nodeId': nodeId,
    'field': field,
    'value': value,
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    final (material, refusal) = _materialAt(project, materialIndex);
    if (material == null) return refusal!;
    final TextureGraph? graph = material.graph;
    if (graph == null) {
      return Outcome.refused('material $materialIndex has no texture graph');
    }
    final TextureNode? node = graph.nodeById(nodeId);
    if (node == null) return Outcome.refused('there is no node $nodeId');
    if (node.inputs.containsKey(field)) {
      return Outcome.refused('"$field" is a link; use Link or Unlink for it');
    }
    final TextureNode? replaced = _textureNodeWith(node, field, value);
    if (replaced == null) {
      return Outcome.refused(
        '"$field" is not a field on a "${node.kind}" node, or its value is '
        'the wrong shape',
      );
    }
    final nextGraph = TextureGraph(
      nodes: <TextureNode>[
        for (final n in graph.nodes) n.id == nodeId ? replaced : n,
      ],
      positions: graph.positions,
    );
    return Outcome.done(
      _withMaterial(project, materialIndex, material.withGraph(nextGraph)),
    );
  }
}

/// Moves [nodeId] to a new spot in `TextureGraphPanel`'s own canvas.
///
/// **Does not bump [ProjectMaterial.version].** See the library comment: a
/// position is not part of what [BakeTextureGraph] reads, so a drag leaves
/// [ProjectMaterial.isGraphStale] exactly as it was.
final class MoveNode extends ModelCommand {
  const MoveNode({
    required this.materialIndex,
    required this.nodeId,
    required this.x,
    required this.y,
  });

  final int materialIndex;
  final int nodeId;
  final double x;
  final double y;

  @override
  String get name => 'moveNode';

  @override
  String get says => 'move a node';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'materialIndex': materialIndex,
    'nodeId': nodeId,
    'x': x,
    'y': y,
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    final (material, refusal) = _materialAt(project, materialIndex);
    if (material == null) return refusal!;
    final TextureGraph? graph = material.graph;
    if (graph == null) {
      return Outcome.refused('material $materialIndex has no texture graph');
    }
    if (graph.nodeById(nodeId) == null) {
      return Outcome.refused('there is no node $nodeId');
    }
    final nextGraph = TextureGraph(
      nodes: graph.nodes,
      positions: <int, (double, double)>{...graph.positions, nodeId: (x, y)},
    );
    return Outcome.done(
      _withMaterial(
        project,
        materialIndex,
        ProjectMaterial(
          surface: material.surface,
          version: material.version,
          fmat: material.fmat,
          graph: nextGraph,
          bakedAtVersion: material.bakedAtVersion,
        ),
      ),
    );
  }
}

/// [node] with every input that pointed at [removedId] cleared — the same
/// per-socket edit [Unlink] makes, run once for whichever of [node]'s own
/// sockets named it (a `Blend` node could, in principle, wire both `base`
/// and `overlay` to the same id).
TextureNode _withoutLinksTo(TextureNode node, int removedId) {
  var next = node;
  for (final entry in node.inputs.entries) {
    if (entry.value.from == removedId) {
      next = _textureNodeWith(next, entry.key, null)!;
    }
  }
  return next;
}

/// Deletes [nodeId] from a material's [TextureGraph] — see the library
/// comment for why nothing, `output` included, is protected from this.
///
/// **A dangling link is not left for [TextureGraph.validate] to find.**
/// Every other node's own input that named [nodeId] is cleared in the same
/// step, through [_withoutLinksTo], so the graph this leaves behind is never
/// one [TextureGraph.validate] would call out for reading a node that is no
/// longer there.
final class RemoveNode extends ModelCommand {
  const RemoveNode({required this.materialIndex, required this.nodeId});

  final int materialIndex;
  final int nodeId;

  @override
  String get name => 'removeNode';

  @override
  String get says => 'remove a node';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'materialIndex': materialIndex,
    'nodeId': nodeId,
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    final (material, refusal) = _materialAt(project, materialIndex);
    if (material == null) return refusal!;
    final TextureGraph? graph = material.graph;
    if (graph == null) {
      return Outcome.refused('material $materialIndex has no texture graph');
    }
    if (graph.nodeById(nodeId) == null) {
      return Outcome.refused('there is no node $nodeId');
    }
    final nextNodes = <TextureNode>[
      for (final n in graph.nodes)
        if (n.id != nodeId) _withoutLinksTo(n, nodeId),
    ];
    final nextPositions = <int, (double, double)>{...graph.positions}
      ..remove(nodeId);
    final nextGraph = TextureGraph(nodes: nextNodes, positions: nextPositions);
    return Outcome.done(
      _withMaterial(project, materialIndex, material.withGraph(nextGraph)),
    );
  }
}
