import 'package:dart_mcp/server.dart';
import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_mcp_kit/flutter3d_mcp_kit.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
// `EnumHint` is hidden here because `flutter3d_formats`'s own — used below to
// build `setMaterialField`'s schema from `MaterialHint` — collides with this
// package's unrelated modifier-parameter `EnumHint`, which nothing here reads.
import 'package:flutter3d_model_core/flutter3d_model_core.dart' hide EnumHint;

import 'model_session.dart';

/// One tool: what an agent is offered, and what calling it does — see
/// `flutter3d_mcp_kit`'s [OfferedTool] for why a pair rather than a table and
/// a switch.
typedef ModelTool = OfferedTool<ModelSession, Answer>;

Future<Answer> Function(ModelSession, Map<String, Object?>) _sync(
  Answer Function(ModelSession, Map<String, Object?>) body,
) =>
    (ModelSession session, Map<String, Object?> arguments) async =>
        body(session, arguments);

// --------------------------------------------------------------- schemas

/// Three numbers, which is how the project spells every position, axis and
/// size.
///
/// [unit] is appended to [about] rather than left to each call site —
/// `ux-43`'s own acceptance is that every numeric field says what its number
/// is a number *of*, and forty call sites each remembering to say "in metres"
/// is forty chances to forget. A direction says so instead: a normalised axis
/// is a ratio of three numbers and has no unit at all.
ListSchema _vector(String about, {String unit = 'in metres'}) => ListSchema(
  description: '$about — three numbers, x y z, $unit',
  items: NumberSchema(),
  minItems: 3,
  maxItems: 3,
);

/// Sixteen numbers, column-major — `Matrix4.storage` — for the two commands
/// that take a whole transform rather than a friendlier vector or angle.
ListSchema _matrix16(String about) => ListSchema(
  description:
      '$about — sixteen numbers, column-major (Matrix4.storage order); the '
      'translation in the last column is in metres, Y-up',
  items: NumberSchema(),
  minItems: 16,
  maxItems: 16,
);

UntitledSingleSelectEnumSchema _pivot(String about) =>
    UntitledSingleSelectEnumSchema(
      description: about,
      values: <String>[for (final p in TransformPivot.values) p.name],
    );

UntitledSingleSelectEnumSchema _space(String about) =>
    UntitledSingleSelectEnumSchema(
      description: about,
      values: <String>[for (final s in TransformSpace.values) s.name],
    );

UntitledSingleSelectEnumSchema _interpolation(String about) =>
    UntitledSingleSelectEnumSchema(
      description: about,
      values: <String>[for (final i in AnimationInterpolation.values) i.name],
    );

/// `import`'s own "unit" — `apps/flutter3d_modeler`'s `import_plan.dart`
/// `ImportUnit` restated as a string enum, since the app that owns that
/// type is not something this package depends on. Keys into
/// [_importUnitScale] for the multiplier `ImportOptions.scale` actually
/// takes.
UntitledSingleSelectEnumSchema _importUnit(String about) =>
    UntitledSingleSelectEnumSchema(
      description: about,
      values: const <String>['mm', 'cm', 'm'],
    );

/// [_importUnit]'s own values, mapped to [ImportOptions.scale] the way
/// `import_plan.dart`'s `ImportUnit` already does — `mm` and `cm` read as
/// this project's own metres, `m` (the default) leaves a file untouched.
const Map<String, double> _importUnitScale = <String, double>{
  'mm': 0.001,
  'cm': 0.01,
  'm': 1.0,
};

UntitledSingleSelectEnumSchema _upAxis(String about) =>
    UntitledSingleSelectEnumSchema(
      description: about,
      values: <String>[for (final a in UpAxis.values) a.name],
    );

/// The three components [PoseJoint] can key — never `weights`, which the
/// command itself refuses, so the schema does not offer a value guaranteed
/// to fail.
UntitledSingleSelectEnumSchema _posablePath(String about) =>
    UntitledSingleSelectEnumSchema(
      description: about,
      values: <String>[
        for (final p in AnimationPath.values)
          if (p != AnimationPath.weights) p.name,
      ],
    );

/// A list of numbers whose own length is a track's `componentCount` — not
/// known ahead of time the way [_vector]'s always-three or [_matrix16]'s
/// always-sixteen are, so no `minItems`/`maxItems` here; the command itself
/// is what checks the count matches the track it targets.
ListSchema _numbers(String about) =>
    ListSchema(description: about, items: NumberSchema());

ListSchema _ints(String about) =>
    ListSchema(description: about, items: IntegerSchema());

/// The material fields `setMaterialField` accepts — `_fieldSet`'s own switch
/// in `material_commands.dart`, named again here because that switch is
/// private. Kept in the order `SurfaceMaterial`'s own constructor declares
/// them, so the schema reads the way the class does.
const List<String> _materialFields = <String>[
  'name',
  'baseColor',
  'metallic',
  'roughness',
  'normalScale',
  'occlusionStrength',
  'emissive',
  'emissiveStrength',
  'alphaMode',
  'alphaCutoff',
  'doubleSided',
  'unlit',
];

/// What `setMaterialField`'s schema says about one field — derived from
/// [builtInMaterialHints] when a hint exists for it, so the shape and the
/// help text an agent reads come from the same table an inspector's slider
/// does, rather than a second, hand-written description that can drift from
/// it.
String _materialFieldHelp(String field) {
  final MaterialHint? hint = builtInMaterialHints[field];
  final String shape = switch (hint?.kind) {
    RangeHint(:final min, :final max) => 'a number, $min..$max',
    ColorHint(:final channels) => '$channels numbers',
    EnumHint(:final values) =>
      'one of ${values.map((EnumHintValue v) => v.value).join('/')}',
    TextureHint() || null => switch (field) {
      'name' => 'a string, or omit to clear it',
      'doubleSided' || 'unlit' => 'a bool',
      _ => 'a number',
    },
  };
  final String? help = hint?.help;
  return help == null ? shape : '$shape — $help';
}

/// `setMaterialField`'s own "field" enum, its description built one line a
/// field from [_materialFieldHelp] — see that function's own doc comment.
UntitledSingleSelectEnumSchema _materialField() =>
    UntitledSingleSelectEnumSchema(
      description: <String>[
        for (final String field in _materialFields)
          '$field: ${_materialFieldHelp(field)}',
      ].join('; '),
      values: _materialFields,
    );

/// Runs the command [name] stands for, built out of the call's own arguments
/// through [modelCommandFromJson] — the same reader the project file and
/// `CommandJournal` use, so a tool call is that map with the tool's own name
/// written into it and nothing here re-decides what a vector is.
Future<Answer> Function(ModelSession, Map<String, Object?>) _command(
  String name,
) => (ModelSession session, Map<String, Object?> arguments) async {
  final ModelCommand? command = modelCommandFromJson(<String, Object?>{
    'name': name,
    ...arguments,
  });
  if (command == null) {
    return (
      did: false,
      says:
          '$name cannot be read from those arguments — check the schema '
          'that tools/list gave for it',
    );
  }
  // `mcp-14n`'s own lock: a modal transform — a drag, mid-gesture — holds
  // one open, and this command waits its turn rather than landing inside a
  // step it had no part in, at whatever intermediate position the drag has
  // reached the instant this call arrived.
  await session.history.whenNotInTransaction;
  return session.runTargeted(command, ModelSession.targetIn(arguments));
};

/// Every command tool, with the target arguments added to the ones that act
/// on a selection — and that is exactly the ones whose schema does not
/// already name what they act on.
///
/// **The rule is computed rather than written down as a list.** A list of
/// "commands that read the selection" is a second place to remember something,
/// and the first command added without an entry in it would advertise no way
/// to be aimed. A tool that already takes an `id` or an `index` is aimed;
/// every other one reads `history.selection`, which is what [_targetSchema]
/// is for.
List<ModelTool> get _aimableCommandTools => <ModelTool>[
  for (final ModelTool tool in _commandTools) _aimable(tool),
];

ModelTool _aimable(ModelTool tool) {
  final Map<String, Schema> properties =
      tool.tool.inputSchema.properties ?? const <String, Schema>{};
  if (properties.containsKey('id') || properties.containsKey('index')) {
    return tool;
  }
  return ModelTool(
    Tool(
      name: tool.name,
      description:
          '${tool.tool.description} Acts on what is selected, or on the '
          'object and elements you name — "object" with "faces", "edges" or '
          '"vertices", or "ids" for whole objects. Naming a target leaves the '
          'selection exactly as it was; what the command selected while it '
          'ran is in the answer.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{...properties, ..._targetSchema},
        required: tool.tool.inputSchema.required,
      ),
    ),
    tool.run,
  );
}

/// The target arguments, as schema, added to every command tool that acts on
/// a selection. `ModelSession.targetIn` is what reads them back, and its own
/// doc comment is why they live there rather than here.
Map<String, Schema> get _targetSchema => <String, Schema>{
  'object': IntegerSchema(
    description:
        'act on this object\'s mesh rather than on what is selected; the '
        'selection is left exactly as it was',
  ),
  'vertices': _ints('vertex ids of "object" to act on'),
  'edges': _ints('edge ids of "object" to act on'),
  'faces': _ints('face ids of "object" to act on'),
  'ids': _ints('object ids to act on, instead of what is selected'),
};

// ------------------------------------------------------------ command tools

/// Every command `modelCommandNames` names, one tool each. `test/tools_test.dart`
/// holds this list to that name list, both ways round — a command added there
/// without a tool here is a failing test, not a silent gap.
List<ModelTool> get _commandTools => <ModelTool>[
  ModelTool(
    Tool(
      name: 'rename',
      description:
          'Give an object a new name. The name shown everywhere else '
          '— the listing, an issue, an undo label.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'id': IntegerSchema(description: 'the object, from list'),
          'to': StringSchema(description: 'the new name; may not be blank'),
        },
        required: <String>['id', 'to'],
      ),
    ),
    _command('rename'),
  ),
  ModelTool(
    Tool(
      name: 'setTransform',
      description:
          'Replace an object\'s whole local transform at once, as a '
          '16-number column-major matrix. moveBy/rotateBy/scaleBy are the '
          'friendlier way to move something that is already placed; this is '
          'for setting it outright.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'id': IntegerSchema(description: 'the object, from list'),
          'to': _matrix16('the new transform, Matrix4.storage order'),
        },
        required: <String>['id', 'to'],
      ),
    ),
    _command('setTransform'),
  ),
  ModelTool(
    Tool(
      name: 'moveBy',
      description:
          'Move everything selected by a vector, in the model\'s own '
          'units. Select objects first — this reads the current selection '
          'rather than taking an id.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{'by': _vector('how far to move')},
        required: <String>['by'],
      ),
    ),
    _command('moveBy'),
  ),
  ModelTool(
    Tool(
      name: 'rotateBy',
      description:
          'Turn everything selected about an axis, in radians. '
          'pivot chooses whether the selection swings around its shared '
          'middle or each object turns about its own; space chooses the '
          'world\'s axes or each object\'s own.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'axis': _vector('the axis to turn about', unit: 'a direction, no unit'),
          'radians': NumberSchema(description: 'how far, in radians'),
          'pivot': _pivot('median (default) or individual'),
          'space': _space('global (default) or local'),
        },
        required: <String>['axis', 'radians'],
      ),
    ),
    _command('rotateBy'),
  ),
  ModelTool(
    Tool(
      name: 'scaleBy',
      description:
          'Scale everything selected by a uniform factor about a '
          'pivot. 2 doubles the size; 0.5 halves it.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'by': NumberSchema(
            description:
                'how much bigger, as a multiplier: 2 is twice the size, '
                '0.5 is half. Above 0',
          ),
          'pivot': _pivot('median (default) or individual'),
        },
        required: <String>['by'],
      ),
    ),
    _command('scaleBy'),
  ),
  ModelTool(
    Tool(
      name: 'setParent',
      description:
          'Hang one object under another, or leave "to" out to put '
          'it back at the top level. The child keeps its local transform, not '
          'its world position — move it back afterwards if that matters.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'id': IntegerSchema(description: 'the object to reparent'),
          'to': IntegerSchema(
            description: 'the new parent, by object id; omit for none',
          ),
        },
        required: <String>['id'],
      ),
    ),
    _command('setParent'),
  ),
  ModelTool(
    Tool(
      name: 'setOrigin',
      description:
          'Move an object\'s own origin without moving the object '
          'on screen — the geometry shifts one way, the node the other, so '
          'the next rotation turns about the point named here rather than '
          'wherever the model happened to be authored around.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'id': IntegerSchema(description: 'the object'),
          'to': UntitledSingleSelectEnumSchema(
            description: 'boundsCentre (default), boundsBottom or worldOrigin',
            values: <String>[for (final p in OriginPlacement.values) p.name],
          ),
        },
        required: <String>['id'],
      ),
    ),
    _command('setOrigin'),
  ),
  ModelTool(
    Tool(
      name: 'applyTransform',
      description:
          'Bake an object\'s node transform into its geometry, '
          'leaving an identity transform behind — a step before exporting to '
          'an engine that expects a model at the origin.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'id': IntegerSchema(description: 'the object'),
        },
        required: <String>['id'],
      ),
    ),
    _command('applyTransform'),
  ),
  ModelTool(
    Tool(
      name: 'addPrimitive',
      description:
          'Add a basic shape — ${AddPrimitive.primitiveKinds.join(', ')} '
          '— and select it. It stays parametric: setParametric can still '
          'change its size and segment count afterwards.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'kind': UntitledSingleSelectEnumSchema(
            // `ux-43`: `cuboid` is offered beside `box` and means the same
            // shape. The project format spells it `cuboid` and the menu says
            // `box`; a caller that read one and asked the other used to be
            // refused for spelling it the way the file did.
            description: 'which shape. "cuboid" is another name for "box"',
            values: <String>[...AddPrimitive.primitiveKinds, 'cuboid'],
          ),
          'size': NumberSchema(
            description: 'how big across, in metres; default 1',
          ),
          'segments': IntegerSchema(
            description: 'how many segments around, default 32',
          ),
          'at': _vector('where it goes, default the origin'),
        },
        required: <String>['kind'],
      ),
    ),
    _command('addPrimitive'),
  ),
  ModelTool(
    Tool(
      name: 'addLathe',
      description:
          'Turn a profile on the (radius, height) half-plane into a '
          'shape — a glass, a bottle, a chair leg — and select it. At least '
          'two points, none at a negative radius.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'profile': ListSchema(
            description: 'points bottom to top, each [radius, height]',
            items: ListSchema(items: NumberSchema(), minItems: 2, maxItems: 2),
            minItems: 2,
          ),
          'segments': IntegerSchema(
            description: 'how many segments around, default 32',
          ),
          'closedProfile': BooleanSchema(
            description:
                'join the last point back to the first, for a torus '
                'shape; default false',
          ),
          'label': StringSchema(
            description: 'what to call it, default "lathe"',
          ),
          'at': _vector('where it goes, default the origin'),
        },
        required: <String>['profile'],
      ),
    ),
    _command('addLathe'),
  ),
  ModelTool(
    Tool(
      name: 'addSocket',
      description:
          'Add a named point with no geometry of its own — a place for an '
          'accessory or an attachment — and select it. Exports as a node '
          'with no surface, the same way an empty group already does, and '
          'reads back as a socket.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'label': StringSchema(
            description: 'what to call it, default "socket"',
          ),
          'at': _vector('where it goes, default the origin'),
        },
      ),
    ),
    _command('addSocket'),
  ),
  ModelTool(
    Tool(
      name: 'setParametric',
      description:
          'Replace the parameters of a shape that still has them — '
          'a cylinder of 32 segments becomes one of 48 without rebuilding it '
          'from scratch. Refused on a mesh or an imported object: only a '
          'still-parametric shape has parameters to set. "to" is an object '
          'with a "shape" field naming which kind ("cuboid", "plane", '
          '"lathe", "sphere", "cylinder" or "torus") and every field that '
          'shape needs — call list to see what the target already is before '
          'changing it, or read `flutter3d_model_core`\'s ParametricShape '
          'subtypes for the exact field names each kind takes.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'id': IntegerSchema(description: 'the object'),
          'to': ObjectSchema(
            description:
                'the new parameters, shaped like the shape named in '
                '"shape"',
            properties: <String, Schema>{
              'shape': UntitledSingleSelectEnumSchema(
                values: <String>[
                  'cuboid',
                  'plane',
                  'lathe',
                  'sphere',
                  'cylinder',
                  'torus',
                ],
              ),
            },
            required: <String>['shape'],
          ),
        },
        required: <String>['id', 'to'],
      ),
    ),
    _command('setParametric'),
  ),
  ModelTool(
    Tool(
      name: 'bakeToMesh',
      description:
          'Turn a shape that still knows its parameters into an '
          'editable mesh. One-way — there is no command back — but undo puts '
          'the parametric shape back whole.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'id': IntegerSchema(description: 'the object'),
        },
        required: <String>['id'],
      ),
    ),
    _command('bakeToMesh'),
  ),
  ModelTool(
    Tool(
      name: 'deleteObjects',
      description:
          'Delete everything selected, and everything parented '
          'under it. Select objects first.',
      inputSchema: ObjectSchema(),
    ),
    _command('deleteObjects'),
  ),
  ModelTool(
    Tool(
      name: 'duplicateObjects',
      description:
          'Copy everything selected, in place, and select the '
          'copies. Select objects first.',
      inputSchema: ObjectSchema(),
    ),
    _command('duplicateObjects'),
  ),
  ModelTool(
    Tool(
      name: 'extrude',
      description:
          'Pull the selected faces out along their normal, by a '
          'distance. Mesh mode: select an object, then faces at the face '
          'level.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'distance': NumberSchema(
            description: 'how far along the face normal, in metres',
          ),
        },
        required: <String>['distance'],
      ),
    ),
    _command('extrude'),
  ),
  ModelTool(
    Tool(
      name: 'loopCut',
      description:
          'Cut one or more loops across the selected faces, evenly '
          'spaced by factor.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'cuts': IntegerSchema(description: 'how many loops, default 1'),
          'factor': NumberSchema(
            description:
                'where along the edge, as a fraction 0..1; default 0.5 '
                '(centred)',
          ),
        },
      ),
    ),
    _command('loopCut'),
  ),
  ModelTool(
    Tool(
      name: 'bevelEdges',
      description:
          'Cut a corner off every selected edge or vertex, by width, '
          'walling the gap with a new face. Mesh mode: select edges, or '
          'vertices for every edge each one touches. The selection has to '
          'be a closed region — every face touching a beveled edge needs '
          'all of its own edges beveled too.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'width': NumberSchema(
            description:
                'how far the new wall sits from the original corner, '
                'in metres',
          ),
        },
        required: <String>['width'],
      ),
    ),
    _command('bevelEdges'),
  ),
  ModelTool(
    Tool(
      name: 'deleteElements',
      description:
          'Delete the selected vertices, edges or faces, at '
          'whichever level is selected.',
      inputSchema: ObjectSchema(),
    ),
    _command('deleteElements'),
  ),
  ModelTool(
    Tool(
      name: 'transformElements',
      description:
          'Move, turn or scale the selected mesh elements by a '
          '16-number matrix — the element-level twin of setTransform. '
          'moveBy/rotateBy/scaleBy move whole objects; this moves vertices, '
          'edges or faces within one.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'by': _matrix16('the transform to apply, Matrix4.storage order'),
          'what': StringSchema(
            description: 'a word for undo — "move", "turn" or "scale"',
          ),
          'pivot': _pivot('median (default); individual is refused here'),
          'space': _space('global (default) or local'),
        },
        required: <String>['by'],
      ),
    ),
    _command('transformElements'),
  ),
  ModelTool(
    Tool(
      name: 'mergeByDistance',
      description:
          'Weld vertices in the selection closer together than '
          'distance into one.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'distance': NumberSchema(
            description:
                'how close two vertices must be to become one, in '
                'metres; default a small epsilon',
          ),
        },
      ),
    ),
    _command('mergeByDistance'),
  ),
  ModelTool(
    Tool(
      name: 'dissolveEdges',
      description:
          'Remove the selected edges, merging the faces on either '
          'side of each into one.',
      inputSchema: ObjectSchema(),
    ),
    _command('dissolveEdges'),
  ),
  ModelTool(
    Tool(
      name: 'triangulate',
      description:
          'Cut every face with more than three corners into '
          'triangles.',
      inputSchema: ObjectSchema(),
    ),
    _command('triangulate'),
  ),
  ModelTool(
    Tool(
      name: 'recalculateNormals',
      description:
          'Recompute vertex normals from the mesh\'s own faces, '
          'optionally flipping them to point the other way.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'flip': BooleanSchema(
            description:
                'invert every normal, default '
                'false',
          ),
        },
      ),
    ),
    _command('recalculateNormals'),
  ),
  ModelTool(
    Tool(
      name: 'markSeam',
      description:
          'Mark the selected edges as a UV seam, or clear that mark. '
          'unwrap only cuts an island apart at a seam.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'on': BooleanSchema(
            description: 'true to mark (default), false to clear',
          ),
        },
      ),
    ),
    _command('markSeam'),
  ),
  ModelTool(
    Tool(
      name: 'unwrap',
      description:
          'Lay out a UV for the selected faces, or the whole mesh '
          'when nothing is selected, cutting islands apart at seams '
          'markSeam left. autoPack lays every island into one shared '
          '[0, 1] square afterward.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'margin': NumberSchema(
            description:
                'gap autoPack leaves between islands, as a fraction of '
                'the UV square; default 0.01',
          ),
          'autoPack': BooleanSchema(
            description:
                'pack every island into one shared square, default true',
          ),
        },
      ),
    ),
    _command('unwrap'),
  ),
  ModelTool(
    Tool(
      name: 'separate',
      description:
          'Pull the selected faces out of their object into a new '
          'object of their own, standing where they stood.',
      inputSchema: ObjectSchema(),
    ),
    _command('separate'),
  ),
  ModelTool(
    Tool(
      name: 'selectAll',
      description: 'Select everything there is, at the current level.',
      inputSchema: ObjectSchema(),
    ),
    _command('selectAll'),
  ),
  ModelTool(
    Tool(
      name: 'selectNone',
      description: 'Clear the selection at the current level.',
      inputSchema: ObjectSchema(),
    ),
    _command('selectNone'),
  ),
  ModelTool(
    Tool(
      name: 'invertSelection',
      description:
          'Select what was not selected, and deselect what was, at '
          'the current level.',
      inputSchema: ObjectSchema(),
    ),
    _command('invertSelection'),
  ),
  ModelTool(
    Tool(
      name: 'growSelection',
      description: 'Extend the mesh selection to everything touching it.',
      inputSchema: ObjectSchema(),
    ),
    _command('growSelection'),
  ),
  ModelTool(
    Tool(
      name: 'shrinkSelection',
      description: 'Pull the mesh selection in from its own boundary.',
      inputSchema: ObjectSchema(),
    ),
    _command('shrinkSelection'),
  ),
  ModelTool(
    Tool(
      name: 'selectLinked',
      description:
          'Extend the mesh selection to everything connected to it '
          'by shared geometry.',
      inputSchema: ObjectSchema(),
    ),
    _command('selectLinked'),
  ),
  ModelTool(
    Tool(
      name: 'selectEdgeLoop',
      description: 'Select the loop of edges that runs through one edge.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'edge': IntegerSchema(description: 'one edge id already in the mesh'),
        },
        required: <String>['edge'],
      ),
    ),
    _command('selectEdgeLoop'),
  ),
  ModelTool(
    Tool(
      name: 'selectEdgeRing',
      description:
          'Select the ring of edges parallel to one edge, across '
          'the faces on either side of it.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'edge': IntegerSchema(description: 'one edge id already in the mesh'),
        },
        required: <String>['edge'],
      ),
    ),
    _command('selectEdgeRing'),
  ),
  ModelTool(
    Tool(
      name: 'selectByMaterial',
      description:
          'Select the faces on one material slot of the active '
          'object\'s mesh. Mesh mode only.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'slot': IntegerSchema(
            description:
                'the slot, as the mesh numbers '
                'them',
          ),
        },
        required: <String>['slot'],
      ),
    ),
    _command('selectByMaterial'),
  ),
  ModelTool(
    Tool(
      name: 'selectFacing',
      description:
          'Select the faces pointing a given way — "the top", "the '
          'front", said in a way a program can say it. Takes a direction in '
          'the object\'s own space ([0,1,0] is up) and an angle to allow '
          'either side of it. Answers with the faces, at face level, '
          'whatever level was live. Mesh mode only. This is how you find the '
          'face to extrude without rendering a picture and guessing.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'axis': _vector('the direction to face, e.g. [0,1,0] for up', unit: 'a direction, no unit'),
          'within': NumberSchema(
            description:
                'how far off that direction a face may point and still '
                'count, in degrees; 45 by default, which is "the top" on a '
                'box',
          ),
        },
        required: <String>['axis'],
      ),
    ),
    _command('selectFacing'),
  ),
  // `ux-14`, `ux-13` and `ux-16` added four commands and no tools for them,
  // which `tools_test.dart`'s own "a command exists that this server cannot
  // call" caught — closed here, since `ux-19` is the row about an agent being
  // able to reach the state it edits.
  ModelTool(
    Tool(
      name: 'setObjectVisible',
      description:
          'Show or hide an object. A hidden object is not drawn and is '
          'not written to an export — it is a fact about the document, not '
          'about this session — and hiding a parent hides its children.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'id': IntegerSchema(description: 'the object, from list'),
          'to': BooleanSchema(description: 'true to show, false to hide'),
        },
        required: <String>['id', 'to'],
      ),
    ),
    _command('setObjectVisible'),
  ),
  ModelTool(
    Tool(
      name: 'setObjectLocked',
      description:
          'Lock or unlock an object. A locked object stays on screen '
          'and refuses to be picked or transformed — the floor somebody '
          'keeps catching by accident.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'id': IntegerSchema(description: 'the object, from list'),
          'to': BooleanSchema(description: 'true to lock, false to unlock'),
        },
        required: <String>['id', 'to'],
      ),
    ),
    _command('setObjectLocked'),
  ),
  ModelTool(
    Tool(
      name: 'buildTopology',
      description:
          'Turn an object that came from a file into a real editable '
          'mesh, welding vertices that sit on top of each other. This is '
          'what gives an imported object elements with ids — an STL arrives '
          'with every triangle carrying its own three corners, and nothing '
          'can be extruded or bevelled until they are shared. Refused on '
          'something that already has topology, since rebuilding it would '
          'throw away every edit that made it what it is.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'id': IntegerSchema(description: 'the imported object, from list'),
          'weld': NumberSchema(
            description:
                'how close two corners must be to become one; left out, '
                'the import\'s own scale-aware default',
          ),
        },
        required: <String>['id'],
      ),
    ),
    _command('buildTopology'),
  ),
  ModelTool(
    Tool(
      name: 'selectNear',
      description:
          'Select everything at the live level within a distance of a '
          'point — a box-select for something with no screen. Measured in '
          'the object\'s own space, the same space describe answers in and '
          'transformElements moves in. Mesh mode only.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'point': _vector('the centre, in the object\'s own space'),
          'radius': NumberSchema(
            description: 'how far from it to reach, in metres',
          ),
        },
        required: <String>['point', 'radius'],
      ),
    ),
    _command('selectNear'),
  ),
  ModelTool(
    Tool(
      name: 'setLightTransform',
      description:
          'Place one of the project\'s own lights: replace its whole '
          'local transform at once, as a 16-number column-major matrix — '
          'the same shape setTransform gives an object. This is what moves '
          'a light off the origin every light starts at.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'index': IntegerSchema(description: 'the light, from list'),
          'to': _matrix16('the new transform, Matrix4.storage order'),
        },
        required: <String>['index', 'to'],
      ),
    ),
    _command('setLightTransform'),
  ),
  ModelTool(
    Tool(
      name: 'addMaterial',
      description:
          'Add a new row to the material table, painted with '
          'nothing in particular. Its index is the table\'s length before '
          'this runs — call list to see where it landed.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'materialName': StringSchema(
            description:
                'what the table shows '
                'for it; omit to leave it unnamed',
          ),
        },
      ),
    ),
    _command('addMaterial'),
  ),
  ModelTool(
    Tool(
      name: 'removeMaterial',
      description:
          'Drop a row out of the material table. Everything beyond '
          'it moves down one; an object painted with the row removed comes '
          'back unpainted.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'index': IntegerSchema(description: 'the row, from list'),
        },
        required: <String>['index'],
      ),
    ),
    _command('removeMaterial'),
  ),
  ModelTool(
    Tool(
      name: 'duplicateMaterial',
      description:
          'Copy a material to a new row, named after its source, '
          'for a variant that starts from it.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'index': IntegerSchema(description: 'the row to copy'),
        },
        required: <String>['index'],
      ),
    ),
    _command('duplicateMaterial'),
  ),
  ModelTool(
    Tool(
      name: 'setMaterialField',
      description:
          'Set one field of a material by the name `.fmat` writes it '
          'under. See the "field" enum for what each one takes — the same '
          'range, colour and enum shapes an inspector\'s own slider reads '
          'from MaterialHint. Texture slots go through setTexture instead.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'index': IntegerSchema(description: 'the material row'),
          'field': _materialField(),
          'value': Schema.combined(
            description:
                'a number, a string, a bool, or a list of 3 or 4 '
                'numbers, matching the field',
            anyOf: <Schema>[
              StringSchema(),
              NumberSchema(),
              BooleanSchema(),
              ListSchema(items: NumberSchema()),
            ],
          ),
        },
        required: <String>['index', 'field', 'value'],
      ),
    ),
    _command('setMaterialField'),
  ),
  ModelTool(
    Tool(
      name: 'setTexture',
      description:
          'Point a material\'s texture slot at an image, or leave '
          'imageIndex out to clear it. Slots: albedo, normal, '
          'metallicRoughness, occlusion, emissive.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'materialIndex': IntegerSchema(description: 'the material row'),
          'slot': UntitledSingleSelectEnumSchema(
            values: <String>[
              'albedo',
              'normal',
              'metallicRoughness',
              'occlusion',
              'emissive',
            ],
          ),
          'imageIndex': IntegerSchema(
            description:
                'the image, from addImage; '
                'omit to clear the slot',
          ),
          'wrapS': UntitledSingleSelectEnumSchema(
            description: 'repeat (default), clampToEdge or mirroredRepeat',
            values: <String>['repeat', 'clampToEdge', 'mirroredRepeat'],
          ),
          'wrapT': UntitledSingleSelectEnumSchema(
            description: 'repeat (default), clampToEdge or mirroredRepeat',
            values: <String>['repeat', 'clampToEdge', 'mirroredRepeat'],
          ),
        },
        required: <String>['materialIndex', 'slot'],
      ),
    ),
    _command('setTexture'),
  ),
  ModelTool(
    Tool(
      name: 'addImage',
      description:
          'Add an image a material can sample, from base64-encoded '
          'bytes. Interned by content — the same bytes twice come back as '
          'the same row rather than uploading twice.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'bytes': StringSchema(description: 'the file, base64-encoded'),
          'imageName': StringSchema(description: 'a name for it, optional'),
          'mimeType': StringSchema(description: 'e.g. "image/png", optional'),
        },
        required: <String>['bytes'],
      ),
    ),
    _command('addImage'),
  ),
  ModelTool(
    Tool(
      name: 'assignMaterial',
      description:
          'Paint an object with a material row, or leave "to" out '
          'to take the paint off.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'id': IntegerSchema(description: 'the object'),
          'to': IntegerSchema(
            description:
                'the material row; omit to '
                'unpaint it',
          ),
        },
        required: <String>['id'],
      ),
    ),
    _command('assignMaterial'),
  ),
  ModelTool(
    Tool(
      name: 'setMaterialGraph',
      description:
          'Replace (or, with "graph" left out, clear) the whole '
          'texture graph a material\'s slots can be baked from. "graph" is '
          'an object with a "nodes" list, each an object naming its own '
          '"id" (an int, unique in the graph), "kind" (one of image, '
          'color, blend, channels, levels, invert, uvTransform, checker, '
          'noise, normalFromHeight, output) and that kind\'s own fields — '
          'read `flutter3d_model_core`\'s TextureNode subtypes for the '
          'exact field names each kind takes. An "output" node also names '
          '"slot" (albedo, normal, metallicRoughness, occlusion or '
          'emissive) to say which material slot bakeTextureGraph writes it '
          'to; an output with no slot is a preview nothing paints with.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'materialIndex': IntegerSchema(description: 'the material row'),
          'graph': ObjectSchema(
            description: 'the new graph, or omit to clear it',
            properties: <String, Schema>{
              'nodes': ListSchema(items: ObjectSchema()),
            },
            required: <String>['nodes'],
          ),
        },
        required: <String>['materialIndex'],
      ),
    ),
    _command('setMaterialGraph'),
  ),
  ModelTool(
    Tool(
      name: 'bakeTextureGraph',
      description:
          'Bake a material\'s own texture graph (set by '
          'setMaterialGraph) to pixels and wire the result into every slot '
          'an "output" node in it names — one image per slot, one undo '
          'step for the whole graph. Refused when the material has no '
          'graph, the graph does not validate, or no output in it names a '
          'slot.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'materialIndex': IntegerSchema(description: 'the material row'),
          'size': IntegerSchema(
            description: 'the square a slot bakes to; 1024 if omitted',
          ),
        },
        required: <String>['materialIndex'],
      ),
    ),
    _command('bakeTextureGraph'),
  ),
  ModelTool(
    Tool(
      name: 'linkMaterialFile',
      description:
          'Point a material row at a standalone .fmat on disk. With '
          '"bytes" given (the file already read, base64-encoded), the '
          'material adopts that file\'s whole look — colour, the scalar '
          'factors, alpha, whether it is double-sided or unlit — except its '
          'texture slots, which are left exactly as they were; import '
          'textures separately. With "bytes" left out, only the path is '
          'remembered, for a file that does not exist yet.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'index': IntegerSchema(description: 'the material row'),
          'path': StringSchema(
            description: 'the .fmat path, relative to the project',
          ),
          'bytes': StringSchema(
            description:
                'the .fmat file already read from disk, '
                'base64-encoded; omit to link without adopting a look yet',
          ),
        },
        required: <String>['index', 'path'],
      ),
    ),
    _command('linkMaterialFile'),
  ),
  ModelTool(
    Tool(
      name: 'embedMaterial',
      description:
          'Take a material off the .fmat it was linked to (by '
          'linkMaterialFile), so its look is owned by the project alone '
          'from here on. Its look does not change — only the link is '
          'cleared.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'index': IntegerSchema(description: 'the material row'),
        },
        required: <String>['index'],
      ),
    ),
    _command('embedMaterial'),
  ),
  ModelTool(
    Tool(
      name: 'addModifier',
      description:
          'Append a modifier to an object\'s own stack, enabled. '
          '"modifier" is an object naming which kind and its own fields: '
          'kind "array" takes count (an int, total instances including the '
          'original) and offset (3 numbers, added per copy); kind "mirror" '
          'takes normal (3 numbers, the plane through the object\'s own '
          'origin) — both also take an optional mergeDistance (a number) to '
          'weld seams, and mirror also takes bisect (refused — not built '
          'yet) and flipUv (stored, no effect yet); kind "smooth" takes '
          'iterations (an int, at least 1), an optional lambda (a number, '
          '0-1, how far each pass moves toward its neighbours\' average) '
          'and an optional preserveVolume (a bool — without it, enough '
          'iterations visibly shrink the mesh); kind "subdivision" takes '
          'levels (an int, at least 1, how many Catmull-Clark passes are '
          'actually baked into the mesh) and an optional viewLevels (an '
          'int — defaults to levels; nothing here reads it, it is carried '
          'for a viewport that might); kind "boolean" takes operation '
          '(one of union/subtract/intersect), operandId (the id of the '
          'other object to combine with) and operandTransform (16 numbers, '
          'column-major, mapping the operand\'s own local positions into '
          'this object\'s own local space) — the operand object itself is '
          'not read here, only named; combining it happens once the stack '
          'is evaluated.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'id': IntegerSchema(description: 'the object'),
          'modifier': ObjectSchema(
            properties: <String, Schema>{
              'kind': UntitledSingleSelectEnumSchema(
                values: <String>[
                  'array',
                  'mirror',
                  'smooth',
                  'subdivision',
                  'boolean',
                ],
              ),
              'count': IntegerSchema(description: 'array only'),
              'offset': ListSchema(
                items: NumberSchema(),
                description: 'array only, 3 numbers',
              ),
              'normal': ListSchema(
                items: NumberSchema(),
                description: 'mirror only, 3 numbers',
              ),
              'mergeDistance': NumberSchema(description: 'array or mirror'),
              'bisect': BooleanSchema(description: 'mirror only'),
              'flipUv': BooleanSchema(description: 'mirror only'),
              'iterations': IntegerSchema(description: 'smooth only'),
              'lambda': NumberSchema(description: 'smooth only, 0-1'),
              'preserveVolume': BooleanSchema(description: 'smooth only'),
              'levels': IntegerSchema(description: 'subdivision only'),
              'viewLevels': IntegerSchema(description: 'subdivision only'),
              'operation': UntitledSingleSelectEnumSchema(
                description: 'boolean only',
                values: <String>['union', 'subtract', 'intersect'],
              ),
              'operandId': IntegerSchema(description: 'boolean only'),
              'operandTransform': ListSchema(
                items: NumberSchema(),
                description: 'boolean only, 16 numbers',
              ),
            },
            required: <String>['kind'],
          ),
        },
        required: <String>['id', 'modifier'],
      ),
    ),
    _command('addModifier'),
  ),
  ModelTool(
    Tool(
      name: 'setModifierField',
      description:
          'Set one field of a modifier already on an object\'s '
          'stack, by the same field names addModifier\'s own "modifier" '
          'object takes.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'id': IntegerSchema(description: 'the object'),
          'index': IntegerSchema(description: 'the modifier, from list'),
          'field': StringSchema(description: 'the field name'),
          'value': Schema.combined(
            description:
                'a number, a bool, or a list of 3 numbers, '
                'matching the field',
            anyOf: <Schema>[
              NumberSchema(),
              BooleanSchema(),
              ListSchema(items: NumberSchema()),
            ],
          ),
        },
        required: <String>['id', 'index', 'field', 'value'],
      ),
    ),
    _command('setModifierField'),
  ),
  ModelTool(
    Tool(
      name: 'toggleModifier',
      description: 'Flip whether a modifier on an object\'s stack runs.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'id': IntegerSchema(description: 'the object'),
          'index': IntegerSchema(description: 'the modifier, from list'),
        },
        required: <String>['id', 'index'],
      ),
    ),
    _command('toggleModifier'),
  ),
  ModelTool(
    Tool(
      name: 'toggleModifierExport',
      description:
          'Flip whether a modifier runs for the file as well as for '
          'the picture. A modifier switched off here still shapes what you '
          'see and is left out of an export — a mirror you are working '
          'against but do not want baked into the GLB.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'id': IntegerSchema(description: 'the object'),
          'index': IntegerSchema(description: 'the modifier, from list'),
        },
        required: <String>['id', 'index'],
      ),
    ),
    _command('toggleModifierExport'),
  ),
  ModelTool(
    Tool(
      name: 'reorderModifier',
      description: 'Move a modifier to a different position in the stack.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'id': IntegerSchema(description: 'the object'),
          'from': IntegerSchema(
            description: 'the modifier\'s current index in the stack',
          ),
          'to': IntegerSchema(
            description: 'the index in the stack it should end up at',
          ),
        },
        required: <String>['id', 'from', 'to'],
      ),
    ),
    _command('reorderModifier'),
  ),
  ModelTool(
    Tool(
      name: 'removeModifier',
      description: 'Drop a modifier from an object\'s own modifier stack.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'id': IntegerSchema(description: 'the object'),
          'index': IntegerSchema(description: 'the modifier, from list'),
        },
        required: <String>['id', 'index'],
      ),
    ),
    _command('removeModifier'),
  ),
  ModelTool(
    Tool(
      name: 'applyModifier',
      description:
          'Bake a modifier and everything below it on the stack '
          'into the object\'s own mesh, and drop those entries — what is '
          'left above keeps running, now over the newly baked base. Bakes '
          'in the named modifier even if it is currently switched off: this '
          'is what exporting with it enabled would give.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'id': IntegerSchema(description: 'the object'),
          'index': IntegerSchema(description: 'the modifier, from list'),
        },
        required: <String>['id', 'index'],
      ),
    ),
    _command('applyModifier'),
  ),
  ModelTool(
    Tool(
      name: 'applyJobResult',
      description:
          'Write the mesh a background job finished into the object '
          'it answers for. Refused when baseVersion no longer matches the '
          'object\'s own current version — something else changed it while '
          'the job ran, and its answer no longer applies. Nothing here '
          'starts a job or waits for one; an agent that wants a modifier '
          'baked synchronously should call applyModifier instead.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'objectId': IntegerSchema(description: 'the object'),
          'baseVersion': IntegerSchema(
            description: 'the object\'s version when the job started',
          ),
          'meshBytes': StringSchema(
            description: 'the baked mesh, base64-encoded EditMesh.toBytes',
          ),
        },
        required: <String>['objectId', 'baseVersion', 'meshBytes'],
      ),
    ),
    _command('applyJobResult'),
  ),
  ModelTool(
    Tool(
      name: 'applyClipResult',
      description:
          'Write a baked clip — retargetClip/bakeIk/bakeDrivers\'s own '
          'result, or one computed some other way — into the project. '
          'clipIndex null (or left out) appends it as a new clip; given, '
          'replaces the clip already at that index. Nothing here computes '
          'anything: retargetClip/bakeIk/bakeDrivers already compute and '
          'land their own result in one call, so this tool exists for '
          'a clip an agent is landing separately from computing it — the '
          'same reason applyJobResult exists beside applyModifier.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'clipIndex': IntegerSchema(
            description: 'the clip to replace; omit to append instead',
          ),
          'clip': ObjectSchema(
            description: 'the clip, ApplyClipResult\'s own toJson shape',
            properties: <String, Schema>{
              'name': StringSchema(description: 'optional'),
              'tracks': ListSchema(
                description: 'one entry per animated object/property',
                items: ObjectSchema(
                  properties: <String, Schema>{
                    'objectId': IntegerSchema(
                      description: 'the object this track drives',
                    ),
                    'track': ObjectSchema(
                      properties: <String, Schema>{
                        'nodeIndex': IntegerSchema(
                          description:
                              'unused on read; carried through for '
                              'round-trip with a source document only',
                        ),
                        'path': UntitledSingleSelectEnumSchema(
                          description: 'what this track animates',
                          values: <String>[
                            for (final p in AnimationPath.values) p.name,
                          ],
                        ),
                        'interpolation': _interpolation(
                          'how keys blend between times',
                        ),
                        'times': _numbers(
                          'keyframe times in seconds, ascending',
                        ),
                        'values': _numbers(
                          'keyframe values, componentCount per key '
                          '(times valuesPerKey for cubicSpline)',
                        ),
                        'componentCount': IntegerSchema(
                          description: 'values per keyframe',
                        ),
                      },
                      required: <String>[
                        'nodeIndex',
                        'path',
                        'interpolation',
                        'times',
                        'values',
                        'componentCount',
                      ],
                    ),
                  },
                  required: <String>['objectId', 'track'],
                ),
              ),
              'extras': ObjectSchema(
                description: 'optional, carried through opaquely',
              ),
            },
            required: <String>['tracks'],
          ),
        },
        required: <String>['clip'],
      ),
    ),
    _command('applyClipResult'),
  ),
  ModelTool(
    Tool(
      name: 'applySimulationCache',
      description:
          'Write a baked simulation cache into the object it answers '
          'for. Refused when baseVersion no longer matches the object\'s own '
          'current version — something else changed it while the bake ran, '
          'and its answer no longer applies. Nothing here runs a bake; that '
          'is BakeClothJobRequest, off this tool table entirely since it '
          'has no synchronous, single-call shape a tool call could wait on.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'objectId': IntegerSchema(description: 'the object'),
          'baseVersion': IntegerSchema(
            description: 'the object\'s version when the bake started',
          ),
          'cache': ObjectSchema(
            description: 'the baked SimulationCache, as its own toJson',
            properties: <String, Schema>{
              'vertexCount': IntegerSchema(description: 'vertices per frame'),
              'frames': ListSchema(
                description:
                    'one base64-encoded Float32List per frame, each '
                    'vertexCount × 3 values long',
                items: StringSchema(),
              ),
            },
            required: <String>['vertexCount', 'frames'],
          ),
        },
        required: <String>['objectId', 'baseVersion', 'cache'],
      ),
    ),
    _command('applySimulationCache'),
  ),
  ModelTool(
    Tool(
      name: 'bakeSimulationToShapes',
      description:
          'Turn an object\'s own baked simulation cache into up to '
          'maxKeys shape keys, appended to whatever shape set it already '
          'has, each named for the cache frame it came from. Refused when '
          'there is no baked cache, no mesh to hold a shape key, or the '
          'cache\'s own vertex count does not match the mesh\'s.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'id': IntegerSchema(description: 'the object'),
          'maxKeys': IntegerSchema(
            description: 'how many shape keys at most; defaults to 8',
          ),
        },
        required: <String>['id'],
      ),
    ),
    _command('bakeSimulationToShapes'),
  ),
  ModelTool(
    Tool(
      name: 'setProfileLimits',
      description:
          'Change the project\'s own rig limits — maxJoints and/or '
          'maxInfluences. Refused when a value is out of range: maxJoints '
          'past 64 (the skinning shader\'s own ceiling) or maxInfluences '
          'past 4 (a vertex stores four joint/weight pairs). Either field '
          'left out keeps the project\'s current value for it.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'maxJoints': IntegerSchema(
            description: 'how many joints a skeleton may have, 1 to 64',
          ),
          'maxInfluences': IntegerSchema(
            description:
                'how many joints may pull on one vertex, 1 to 4',
          ),
        },
      ),
    ),
    _command('setProfileLimits'),
  ),
  ModelTool(
    Tool(
      name: 'setShapeWeight',
      description:
          'Set one of an object\'s shape keys to a live preview weight — '
          'not a keyframe. keyShape is what records the current weights as '
          'one.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'id': IntegerSchema(description: 'the object'),
          'shapeIndex': IntegerSchema(description: 'the shape key, from list'),
          'weight': NumberSchema(description: 'the new weight'),
        },
        required: <String>['id', 'shapeIndex', 'weight'],
      ),
    ),
    _command('setShapeWeight'),
  ),
  ModelTool(
    Tool(
      name: 'addShapeFromMesh',
      description:
          'Add a new shape key to an object, captured from the mesh\'s '
          'own current vertex positions — sculpt the mesh first, then call '
          'this to save it as a shape. Starts at weight 0.0.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'id': IntegerSchema(description: 'the object; needs an edited mesh'),
          'shapeName': StringSchema(description: 'the new shape key\'s name'),
        },
        required: <String>['id', 'shapeName'],
      ),
    ),
    _command('addShapeFromMesh'),
  ),
  ModelTool(
    Tool(
      name: 'renameShape',
      description: 'Rename one of an object\'s own shape keys.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'id': IntegerSchema(description: 'the object'),
          'shapeIndex': IntegerSchema(description: 'the shape key, from list'),
          'to': StringSchema(description: 'the new name; may not be blank'),
        },
        required: <String>['id', 'shapeIndex', 'to'],
      ),
    ),
    _command('renameShape'),
  ),
  ModelTool(
    Tool(
      name: 'deleteShape',
      description:
          'Remove one of an object\'s own shape keys, shifting the ones '
          'after it down one index. Also drops that shape\'s own component '
          'from any weights animation track driving this object, so the '
          'track keeps driving the survivors rather than reading a dead '
          'shape\'s old slot.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'id': IntegerSchema(description: 'the object'),
          'shapeIndex': IntegerSchema(description: 'the shape key, from list'),
        },
        required: <String>['id', 'shapeIndex'],
      ),
    ),
    _command('deleteShape'),
  ),
  ModelTool(
    Tool(
      name: 'keyShape',
      description:
          'Record an object\'s own current shape weights (whatever '
          'setShapeWeight last set) as a keyframe, at a given time, in a '
          'clip. Creates the object\'s weights track in that clip if it '
          'does not have one yet.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'id': IntegerSchema(description: 'the object; needs shape keys'),
          'clipIndex': IntegerSchema(description: 'which clip, from list'),
          'time': NumberSchema(description: 'when, in seconds'),
        },
        required: <String>['id', 'clipIndex', 'time'],
      ),
    ),
    _command('keyShape'),
  ),
  ModelTool(
    Tool(
      name: 'addShapeDriver',
      description:
          'Add a shape driver to an object: one of its own shape keys, '
          'wired to track how far a joint has turned about one axis '
          'between two angles, rather than a person\'s own slider. '
          'bakeDrivers freezes these into an animation track.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'id': IntegerSchema(description: 'the object; needs shape keys'),
          'driver': ObjectSchema(
            properties: <String, Schema>{
              'shapeIndex': IntegerSchema(
                description: 'the shape key, from list',
              ),
              'jointId': IntegerSchema(description: 'the joint to read'),
              'axis': UntitledSingleSelectEnumSchema(
                description: 'x (default), y or z',
                values: <String>['x', 'y', 'z'],
              ),
              'from': NumberSchema(
                description: 'the angle, in radians, that reads as 0',
              ),
              'to': NumberSchema(
                description: 'the angle, in radians, that reads as 1',
              ),
            },
            required: <String>['shapeIndex', 'jointId', 'from', 'to'],
          ),
        },
        required: <String>['id', 'driver'],
      ),
    ),
    _command('addShapeDriver'),
  ),
  ModelTool(
    Tool(
      name: 'removeShapeDriver',
      description: 'Remove one of an object\'s own shape drivers.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'id': IntegerSchema(description: 'the object'),
          'index': IntegerSchema(description: 'the shape driver, from list'),
        },
        required: <String>['id', 'index'],
      ),
    ),
    _command('removeShapeDriver'),
  ),
  ModelTool(
    Tool(
      name: 'setShapeDriverField',
      description:
          'Change one field of one of an object\'s own shape drivers, by '
          'the same field names addShapeDriver\'s own "driver" object '
          'takes.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'id': IntegerSchema(description: 'the object'),
          'index': IntegerSchema(description: 'the shape driver, from list'),
          'field': UntitledSingleSelectEnumSchema(
            description: 'shapeIndex, jointId, axis, from or to',
            values: <String>['shapeIndex', 'jointId', 'axis', 'from', 'to'],
          ),
          'value': Schema.combined(
            description:
                'a number for shapeIndex/jointId/from/to (from and to in '
                'radians), or "x"/"y"/"z" for axis',
            anyOf: <Schema>[NumberSchema(), StringSchema()],
          ),
        },
        required: <String>['id', 'index', 'field', 'value'],
      ),
    ),
    _command('setShapeDriverField'),
  ),
  ModelTool(
    Tool(
      name: 'addSkeleton',
      description:
          'Add a new, empty skeleton — no joints yet — appended at the '
          'end of the skeleton list. addJoint refuses a skeletonIndex '
          'naming nothing, so this is what makes one to add the first '
          'joint to.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'skeletonName': StringSchema(description: 'optional'),
        },
      ),
    ),
    _command('addSkeleton'),
  ),
  ModelTool(
    Tool(
      name: 'bindSkin',
      description:
          'Set which skeleton an object\'s own mesh is skinned to. A '
          'mesh with no skin reads null; this is the only tool that '
          'ever sets it to something else.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'objectId': IntegerSchema(description: 'the object to bind'),
          'skeletonIndex': IntegerSchema(
            description: 'which skeleton, from list',
          ),
        },
        required: <String>['objectId', 'skeletonIndex'],
      ),
    ),
    _command('bindSkin'),
  ),
  ModelTool(
    Tool(
      name: 'addJoint',
      description:
          'Add an existing object to a skeleton as a new joint, appended '
          'at the end of the joint list. Refused if the object is already '
          'a joint in that skeleton.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'skeletonIndex': IntegerSchema(
            description: 'which skeleton, from list',
          ),
          'objectId': IntegerSchema(description: 'the object to make a joint'),
          'inverseBindMatrix': _matrix16(
            'optional; identity\'s own inverse (identity) when left out',
          ),
        },
        required: <String>['skeletonIndex', 'objectId'],
      ),
    ),
    _command('addJoint'),
  ),
  ModelTool(
    Tool(
      name: 'removeJoint',
      description:
          'Remove a joint from a skeleton. Every vertex weight on it moves '
          'to the joint\'s own parent (or is dropped, renormalized, if it '
          'has none), and every later joint\'s index shifts down by one.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'skeletonIndex': IntegerSchema(
            description: 'which skeleton, from list',
          ),
          'jointIndex': IntegerSchema(description: 'the joint, from list'),
        },
        required: <String>['skeletonIndex', 'jointIndex'],
      ),
    ),
    _command('removeJoint'),
  ),
  ModelTool(
    Tool(
      name: 'renameJoint',
      description:
          'Rename a joint — really just its own underlying object, so '
          'the new name shows up everywhere else that object does too.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'skeletonIndex': IntegerSchema(
            description: 'which skeleton, from list',
          ),
          'jointIndex': IntegerSchema(description: 'the joint, from list'),
          'to': StringSchema(description: 'the new name; may not be blank'),
        },
        required: <String>['skeletonIndex', 'jointIndex', 'to'],
      ),
    ),
    _command('renameJoint'),
  ),
  ModelTool(
    Tool(
      name: 'reparentJoint',
      description:
          'Reparent a joint to a different object — delegates to setParent, '
          'reached through the skeleton\'s own joint index. Refused on a cycle, '
          'the same way setParent refuses one.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'skeletonIndex': IntegerSchema(
            description: 'which skeleton, from list',
          ),
          'jointIndex': IntegerSchema(description: 'the joint, from list'),
          'to': IntegerSchema(description: 'the new parent object\'s id'),
        },
        required: <String>['skeletonIndex', 'jointIndex', 'to'],
      ),
    ),
    _command('reparentJoint'),
  ),
  ModelTool(
    Tool(
      name: 'setRestPose',
      description:
          'Move a joint to a new rest-pose world transform, recomputing '
          'both its own local transform (against its actual current parent) '
          'and its skeleton\'s own inverse bind matrix, so the mesh does not '
          'jump when this is applied.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'skeletonIndex': IntegerSchema(
            description: 'which skeleton, from list',
          ),
          'jointIndex': IntegerSchema(description: 'the joint, from list'),
          'worldTransform': _matrix16('the joint\'s own new world transform'),
        },
        required: <String>['skeletonIndex', 'jointIndex', 'worldTransform'],
      ),
    ),
    _command('setRestPose'),
  ),
  ModelTool(
    Tool(
      name: 'mirrorJoints',
      description:
          'Mirror one or more joints across an axis-aligned plane, by '
          'reflecting each named source joint\'s own current world transform '
          'onto its named target. Name a pair both ways (left to right and '
          'right to left) to mirror a symmetric rig in one call; name a joint '
          'to itself to mirror it in place, for one that straddles the plane.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'skeletonIndex': IntegerSchema(
            description: 'which skeleton, from list',
          ),
          'axis': IntegerSchema(
            description:
                'which axis to mirror across, as an index: 0 for x, 1 '
                'for y, 2 for z',
          ),
          'jointMirror': ObjectSchema(
            description:
                'source joint index (as a string key) to target joint index',
            additionalProperties: IntegerSchema(),
          ),
        },
        required: <String>['skeletonIndex', 'axis', 'jointMirror'],
      ),
    ),
    _command('mirrorJoints'),
  ),
  ModelTool(
    Tool(
      name: 'setRig',
      description:
          'One undo step for a whole auto-rig result: appends jointObjects '
          '(each one\'s own id already chosen, e.g. from buildSkeleton\'s '
          'own preview) to the project, appends skeleton as a new skeleton, '
          'and — when skinObjectId is given — binds it to that new '
          'skeleton, writing weights onto its mesh too when weights is '
          'also given. Refused: an id in jointObjects already taken, '
          'skinObjectId with no mesh to skin, or weights.baseVersion '
          'behind skinObjectId\'s own current version.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'jointObjects': ListSchema(
            description:
                'the new joint (and, for a rig controller, socket) '
                'objects, in order — each one\'s own parent may name an '
                'earlier entry in this same list',
            items: ObjectSchema(
              properties: <String, Schema>{
                'id': IntegerSchema(description: 'not already in the project'),
                'name': StringSchema(),
                'transform': _matrix16('this joint\'s own local transform'),
                'parent': IntegerSchema(
                  description:
                      'an earlier id in jointObjects, or omit for the root',
                ),
              },
              required: <String>['id', 'name', 'transform'],
            ),
          ),
          'skeleton': ObjectSchema(
            description: 'the new skeleton, addressing jointObjects by id',
            properties: <String, Schema>{
              'name': StringSchema(description: 'optional'),
              'joints': _ints('jointObjects ids, in vertex-attribute order'),
              'inverseBindMatrices': ListSchema(
                description: 'one per joint, same order',
                items: _matrix16('an inverse bind matrix'),
              ),
              'skeletonRoot': IntegerSchema(description: 'optional'),
              'constraints': ListSchema(
                description: 'optional two-bone IK chains',
                items: ObjectSchema(
                  properties: <String, Schema>{
                    'rootJointId': IntegerSchema(),
                    'midJointId': IntegerSchema(),
                    'effectorJointId': IntegerSchema(),
                    'target': _vector('the effector\'s own target position'),
                    'pole': _vector('where the mid joint bends toward', unit: 'a direction, no unit'),
                  },
                  required: <String>[
                    'rootJointId',
                    'midJointId',
                    'effectorJointId',
                    'target',
                    'pole',
                  ],
                ),
              ),
            },
            required: <String>['joints', 'inverseBindMatrices'],
          ),
          'skinObjectId': IntegerSchema(
            description: 'optional; bind this object to the new skeleton',
          ),
          'weights': ObjectSchema(
            description:
                'optional; a bind-weights job\'s own result for '
                'skinObjectId\'s mesh — refused unless baseVersion still '
                'matches skinObjectId\'s own current version',
            properties: <String, Schema>{
              'baseVersion': IntegerSchema(
                description: 'skinObjectId\'s own version when this was read',
              ),
              'data': StringSchema(
                description:
                    'base64 Float32, 8 numbers per vertex slot (4 joint '
                    'indices into skeleton.joints, then 4 weights)',
              ),
            },
            required: <String>['baseVersion', 'data'],
          ),
          'label': StringSchema(
            description:
                'what the history offers to undo, e.g. "auto-rig '
                'humanoid (17 joints)"',
          ),
        },
        required: <String>['jointObjects', 'skeleton', 'label'],
      ),
    ),
    _command('setRig'),
  ),
  ModelTool(
    Tool(
      name: 'setKey',
      description:
          'Write (or replace) a keyframe at a given time, on a named '
          'track in a named clip. values needs one number per the track\'s '
          'own component count; inTangent/outTangent are read only while the '
          'track is in cubic interpolation.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'clipIndex': IntegerSchema(description: 'which clip, from list'),
          'trackIndex': IntegerSchema(description: 'which track in that clip'),
          'time': NumberSchema(description: 'when, in seconds'),
          'values': _numbers(
            'the keyed value, one number a component, in the track\'s '
            'own units — metres for translation, a unit quaternion for '
            'rotation, a multiplier for scale',
          ),
          'inTangent': _numbers('optional; one number a component, in the track\'s own units'),
          'outTangent': _numbers('optional; one number a component, in the track\'s own units'),
        },
        required: <String>['clipIndex', 'trackIndex', 'time', 'values'],
      ),
    ),
    _command('setKey'),
  ),
  ModelTool(
    Tool(
      name: 'moveKeys',
      description:
          'Shift the named keyframes on a track by a fixed amount of '
          'time, re-sorting afterward if any crossed another key on the way.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'clipIndex': IntegerSchema(description: 'which clip, from list'),
          'trackIndex': IntegerSchema(description: 'which track in that clip'),
          'indices': _ints('which keys, by their current index'),
          'deltaTime': NumberSchema(
            description: 'how far to shift, in seconds',
          ),
        },
        required: <String>['clipIndex', 'trackIndex', 'indices', 'deltaTime'],
      ),
    ),
    _command('moveKeys'),
  ),
  ModelTool(
    Tool(
      name: 'deleteKeys',
      description:
          'Remove the named keyframes from a track. Refused, rather than '
          'applied, if doing so would leave the track with no keys at all — '
          'a track needs at least one.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'clipIndex': IntegerSchema(description: 'which clip, from list'),
          'trackIndex': IntegerSchema(description: 'which track in that clip'),
          'indices': _ints('which keys, by their current index'),
        },
        required: <String>['clipIndex', 'trackIndex', 'indices'],
      ),
    ),
    _command('deleteKeys'),
  ),
  ModelTool(
    Tool(
      name: 'setInterpolation',
      description:
          'Switch how a track blends between its own keys — linear, '
          'step, or cubicSpline. Every key\'s own tangents survive the '
          'switch even while it is not the mode currently showing.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'clipIndex': IntegerSchema(description: 'which clip, from list'),
          'trackIndex': IntegerSchema(description: 'which track in that clip'),
          'interpolation': _interpolation('the new interpolation mode'),
        },
        required: <String>['clipIndex', 'trackIndex', 'interpolation'],
      ),
    ),
    _command('setInterpolation'),
  ),
  ModelTool(
    Tool(
      name: 'setTangent',
      description:
          'Set one keyframe\'s own in/out tangents, leaving its time and '
          'value untouched. Either tangent left out keeps whatever that key '
          'already had.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'clipIndex': IntegerSchema(description: 'which clip, from list'),
          'trackIndex': IntegerSchema(description: 'which track in that clip'),
          'index': IntegerSchema(description: 'the key, from its own track'),
          'inTangent': _numbers('optional; one number a component, in the track\'s own units'),
          'outTangent': _numbers('optional; one number a component, in the track\'s own units'),
        },
        required: <String>['clipIndex', 'trackIndex', 'index'],
      ),
    ),
    _command('setTangent'),
  ),
  ModelTool(
    Tool(
      name: 'fillHoles',
      description:
          'Close every open boundary loop in the object\'s own mesh '
          'with one new face — the fix for "won\'t load: an open edge" '
          'a readiness check names. Refused when nothing is open.',
      inputSchema: ObjectSchema(),
    ),
    _command('fillHoles'),
  ),
  ModelTool(
    Tool(
      name: 'poseJoint',
      description:
          'Key an object\'s own current translation, rotation or scale '
          '— read off its live transform, not taken as an argument — onto a '
          'clip at a given frame. Creates the track if none exists yet for '
          'that object and path; calling it again at the same frame '
          'replaces the key rather than adding a second one, so posing a '
          'joint and then keying it repeatedly at the same frame is safe.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'joint': IntegerSchema(description: 'the object id to key'),
          'path': _posablePath('translation, rotation or scale'),
          'clipIndex': IntegerSchema(description: 'which clip, from list'),
          'frame': IntegerSchema(
            description: 'which frame, at the project\'s own fps',
          ),
        },
        required: <String>['joint', 'path', 'clipIndex', 'frame'],
      ),
    ),
    _command('poseJoint'),
  ),
  ModelTool(
    Tool(
      name: 'extractRootMotion',
      description:
          'Flatten a clip\'s own translation track for a root object to '
          'its first key\'s value — the root stands still — after saving '
          'every key\'s real value on the clip itself, so '
          'bakeRootMotionIntoClip can restore them exactly. Refused if '
          'this clip already has extracted root motion.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'clipIndex': IntegerSchema(description: 'which clip, from list'),
          'rootJoint': IntegerSchema(description: 'the root object id'),
        },
        required: <String>['clipIndex', 'rootJoint'],
      ),
    ),
    _command('extractRootMotion'),
  ),
  ModelTool(
    Tool(
      name: 'bakeRootMotionIntoClip',
      description:
          'Restore a clip\'s own translation track for a root object '
          'from whatever extractRootMotion last saved — the exact '
          'inverse, key for key. Refused if this clip has no extracted '
          'root motion, or if the track was edited since extraction and '
          'no longer has the same number of keys.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'clipIndex': IntegerSchema(description: 'which clip, from list'),
          'rootJoint': IntegerSchema(description: 'the root object id'),
        },
        required: <String>['clipIndex', 'rootJoint'],
      ),
    ),
    _command('bakeRootMotionIntoClip'),
  ),
  ModelTool(
    Tool(
      name: 'addClip',
      description:
          'Add a new, empty animation clip — no tracks yet — appended '
          'at the end of the clip list. setKey and poseJoint both refuse '
          'a clipIndex naming nothing, so this is what makes one to key '
          'the first track in.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'clipName': StringSchema(description: 'optional'),
        },
      ),
    ),
    _command('addClip'),
  ),
  ModelTool(
    Tool(
      name: 'addLight',
      description:
          'Add a light to the project\'s own lighting, appended at the '
          'end of the light list — its index is the list\'s length before '
          'this runs. Lit with nothing in particular; setLightField sets '
          'its colour, intensity and the rest afterward.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'type': UntitledSingleSelectEnumSchema(
            description: 'directional (default), point or spot',
            values: <String>[for (final t in ProjectLightType.values) t.name],
          ),
        },
      ),
    ),
    _command('addLight'),
  ),
  ModelTool(
    Tool(
      name: 'removeLight',
      description:
          'Drop a light out of the project\'s own lighting. A document '
          'edit only — the LightNode a synced viewport built for it comes '
          'down the next time LightingSync runs, not here.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'index': IntegerSchema(description: 'the light, from list'),
        },
        required: <String>['index'],
      ),
    ),
    _command('removeLight'),
  ),
  ModelTool(
    Tool(
      name: 'setLightField',
      description:
          'Set one field of a light by name: type ("directional", '
          '"point" or "spot"), color (3 numbers, linear RGB), intensity, '
          'range (0 is unbounded), castsShadow (a bool, a request rather '
          'than a promise), innerConeAngle and outerConeAngle (spot only, '
          'radians).',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'index': IntegerSchema(description: 'the light, from list'),
          'field': StringSchema(description: 'the field name'),
          'value': Schema.combined(
            description:
                'a number, a string, a bool, or a list of 3 numbers, '
                'matching the field',
            anyOf: <Schema>[
              StringSchema(),
              NumberSchema(),
              BooleanSchema(),
              ListSchema(items: NumberSchema()),
            ],
          ),
        },
        required: <String>['index', 'field', 'value'],
      ),
    ),
    _command('setLightField'),
  ),
  ModelTool(
    Tool(
      name: 'setEnvironment',
      description:
          'Set the project\'s own built-in sky — one of a fixed handful '
          'of presets, not an imported panorama.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'preset': UntitledSingleSelectEnumSchema(
            values: <String>[
              for (final p in SceneEnvironmentPreset.values) p.name,
            ],
          ),
        },
        required: <String>['preset'],
      ),
    ),
    _command('setEnvironment'),
  ),
  ModelTool(
    Tool(
      name: 'setSceneLightingField',
      description:
          'Set one scene-wide lighting field that is not a light or the '
          'environment: ambientIntensity (a number, the flat ambient '
          'term), shadows (a bool — whether this project\'s lights ask the '
          'viewport for a shadow map at all), or exposure (a number).',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'field': UntitledSingleSelectEnumSchema(
            values: <String>['ambientIntensity', 'shadows', 'exposure'],
          ),
          'value': Schema.combined(
            description:
                'a number for ambientIntensity/exposure, a bool for '
                'shadows',
            anyOf: <Schema>[NumberSchema(), BooleanSchema()],
          ),
        },
        required: <String>['field', 'value'],
      ),
    ),
    _command('setSceneLightingField'),
  ),
  ModelTool(
    Tool(
      name: 'addNode',
      description:
          'Add a node to a material\'s texture graph: image, color, '
          'blend, channels, levels, invert, uvTransform, checker, noise, '
          'normalFromHeight or output. "fields" carries whatever that kind '
          'needs beyond id and kind — image\'s own imageId, blend\'s own '
          'mode, and so on.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'materialIndex': IntegerSchema(description: 'the material row'),
          'kind': StringSchema(description: 'the node kind'),
          'fields': ObjectSchema(
            description: 'the kind\'s own fields beyond id and kind',
            additionalProperties: true,
          ),
          'x': NumberSchema(
            description: 'where on the graph canvas, in pixels; '
                'default 0',
          ),
          'y': NumberSchema(
            description: 'where on the graph canvas, in pixels; '
                'default 0',
          ),
        },
        required: <String>['materialIndex', 'kind'],
      ),
    ),
    _command('addNode'),
  ),
  ModelTool(
    Tool(
      name: 'link',
      description:
          'Wire a node\'s output into another node\'s input socket. '
          'Refused before anything changes if the link would not type-check '
          '— a colour output into a scalar input, for one.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'materialIndex': IntegerSchema(description: 'the material row'),
          'nodeId': IntegerSchema(description: 'the node being wired into'),
          'input': StringSchema(description: 'which of its inputs'),
          'from': IntegerSchema(
            description: 'the node whose output feeds it, by node id',
          ),
        },
        required: <String>['materialIndex', 'nodeId', 'input', 'from'],
      ),
    ),
    _command('link'),
  ),
  ModelTool(
    Tool(
      name: 'unlink',
      description: 'Take whatever is wired into a node\'s input back off it.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'materialIndex': IntegerSchema(description: 'the material row'),
          'nodeId': IntegerSchema(description: 'the node'),
          'input': StringSchema(description: 'which of its inputs'),
        },
        required: <String>['materialIndex', 'nodeId', 'input'],
      ),
    ),
    _command('unlink'),
  ),
  ModelTool(
    Tool(
      name: 'setNodeField',
      description:
          'Set one non-link field of a texture-graph node. A field '
          'that is actually a link (an input socket name) is refused — use '
          'link or unlink for those.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'materialIndex': IntegerSchema(description: 'the material row'),
          'nodeId': IntegerSchema(description: 'the node'),
          'field': StringSchema(description: 'the field name'),
          'value': Schema.combined(
            description:
                'a number, a string, a bool, or a list of 2, 3 or 4 '
                'numbers, matching the field',
            anyOf: <Schema>[
              StringSchema(),
              NumberSchema(),
              BooleanSchema(),
              ListSchema(items: NumberSchema()),
            ],
          ),
        },
        required: <String>['materialIndex', 'nodeId', 'field', 'value'],
      ),
    ),
    _command('setNodeField'),
  ),
  ModelTool(
    Tool(
      name: 'moveNode',
      description:
          'Move a texture-graph node to a new canvas position. Purely '
          'presentational — it never marks the graph\'s bake stale.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'materialIndex': IntegerSchema(description: 'the material row'),
          'nodeId': IntegerSchema(description: 'the node'),
          'x': NumberSchema(
            description: 'the new canvas position, in pixels',
          ),
          'y': NumberSchema(
            description: 'the new canvas position, in pixels',
          ),
        },
        required: <String>['materialIndex', 'nodeId', 'x', 'y'],
      ),
    ),
    _command('moveNode'),
  ),
  ModelTool(
    Tool(
      name: 'removeNode',
      description:
          'Delete a node from a material\'s texture graph. Every other '
          'node\'s own link that pointed at it is cleared in the same step, '
          'so the graph never comes back with a dangling reference. Nothing '
          'is protected from this, including an output node — bakeTextureGraph '
          'is what refuses when a graph is left feeding no material slot.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'materialIndex': IntegerSchema(description: 'the material row'),
          'nodeId': IntegerSchema(description: 'the node to delete'),
        },
        required: <String>['materialIndex', 'nodeId'],
      ),
    ),
    _command('removeNode'),
  ),
  ModelTool(
    Tool(
      name: 'addLod',
      description:
          'Add a level of detail to an object: a target triangle '
          'ratio in (0, 1] and the screen-height fraction below which it '
          'takes over.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'id': IntegerSchema(description: 'the object'),
          'ratio': NumberSchema(
            description:
                'how many triangles to keep, as a fraction of the '
                'original: (0, 1]',
          ),
          'maxScreenFraction': NumberSchema(
            description: 'screen-height fraction this level takes over below',
          ),
        },
        required: <String>['id', 'ratio', 'maxScreenFraction'],
      ),
    ),
    _command('addLod'),
  ),
  ModelTool(
    Tool(
      name: 'setLodRatio',
      description:
          'Change one of an object\'s levels of detail\' own target '
          'ratio, leaving its screen threshold alone.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'id': IntegerSchema(description: 'the object'),
          'lodIndex': IntegerSchema(description: 'which level, from addLod'),
          'ratio': NumberSchema(
            description:
                'how many triangles to keep, as a fraction of the '
                'original: (0, 1]',
          ),
        },
        required: <String>['id', 'lodIndex', 'ratio'],
      ),
    ),
    _command('setLodRatio'),
  ),
  ModelTool(
    Tool(
      name: 'regenerateLods',
      description:
          'Force every one of an object\'s cached level-of-detail '
          'meshes to regenerate on the next ask — for after the '
          'simplification algorithm itself changed, not for an ordinary '
          'edit to the base mesh (a version bump already covers that).',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'id': IntegerSchema(description: 'the object'),
        },
        required: <String>['id'],
      ),
    ),
    _command('regenerateLods'),
  ),
];

// ------------------------------------------------------------ session tools

/// Everything this server offers: every command as a tool, and the verbs
/// that are about the session rather than about one edit — `list` and
/// `select`, because a program with no screen cannot point at anything;
/// `undo`/`redo`; `check`, `save`, `export` and `import`, because a project
/// has a life outside the commands that shape it; `journal`, because
/// `CommandJournal` is worth writing from the one place that runs every
/// command already.
List<ModelTool> get modelTools => <ModelTool>[
  ModelTool(
    Tool(
      name: 'list',
      description:
          'Everything in the project, one line each — id, name, '
          'kind — plus the material table and the current selection. Call '
          'this first, and again after a delete: ids stay stable, but a '
          'freshly duplicated or imported object has one you have not seen '
          'yet.',
      inputSchema: ObjectSchema(),
    ),
    _sync(
      (ModelSession session, Map<String, Object?> arguments) =>
          (did: true, says: session.listing()),
    ),
  ),
  ModelTool(
    Tool(
      name: 'describe',
      description:
          'One object in numbers: its box, and where each of its '
          'elements is, which way it faces and how big it is. This is how '
          'you find the element to edit — the face that points up, the '
          'vertex at a corner, the longest edge — without rendering a '
          'picture and guessing from it. Element ids from here go straight '
          'into select. Describes the first 50 elements unless you name '
          'some in "elements" or raise "limit".',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'id': IntegerSchema(description: 'the object, from list'),
          'level': UntitledSingleSelectEnumSchema(
            description:
                'vertex, edge or face; defaults to whatever the selection '
                'is at, or faces',
            values: <String>[for (final l in ElementLevel.values) l.name],
          ),
          'elements': _ints('specific element ids, instead of the first few'),
          'limit': IntegerSchema(
            description: 'how many to describe when "elements" is not given',
          ),
        },
        required: <String>['id'],
      ),
    ),
    _sync((ModelSession session, Map<String, Object?> arguments) {
      final Object? id = arguments['id'];
      if (id is! int) return (did: false, says: 'describe needs an "id"');
      final Object? elements = arguments['elements'];
      return (
        did: true,
        says: session.describe(
          id,
          level: arguments['level'] as String?,
          limit: arguments['limit'] as int?,
          elements: elements is List
              ? elements.whereType<int>().toList()
              : null,
        ),
      );
    }),
  ),
  ModelTool(
    Tool(
      name: 'listMaterials',
      description:
          'The material table, one line a row — every field '
          'setMaterialField can set, which texture slots are painted and '
          'with which image, whether the material is linked to a .fmat, '
          'and whether it carries a texture graph still waiting for '
          'bakeTextureGraph. Call this before setMaterialField or '
          'assignMaterial to see what a row already looks like.',
      inputSchema: ObjectSchema(),
    ),
    _sync(
      (ModelSession session, Map<String, Object?> arguments) =>
          (did: true, says: session.listMaterials()),
    ),
  ),
  ModelTool(
    Tool(
      name: 'select',
      description:
          'Choose what the object-level commands act on (by id), or '
          'switch to mesh mode on one object and pick vertices, edges or '
          'faces of it by id. Call it with nothing to select nothing.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'objects': ListSchema(
            description: 'object ids to select, in object mode',
            items: IntegerSchema(),
          ),
          'object': IntegerSchema(
            description: 'the one object to select elements of, in mesh mode',
          ),
          'level': UntitledSingleSelectEnumSchema(
            description: 'vertex, edge or face — required with "object"',
            values: <String>[for (final l in ElementLevel.values) l.name],
          ),
          'elements': ListSchema(
            description: 'element ids at that level, in mesh mode',
            items: IntegerSchema(),
          ),
        },
      ),
    ),
    _sync((ModelSession session, Map<String, Object?> arguments) {
      final objects = arguments['objects'];
      final elements = arguments['elements'];
      return session.select(
        objects: objects is List ? objects.whereType<int>().toList() : null,
        object: arguments['object'] as int?,
        level: arguments['level'] as String?,
        elements: elements is List ? elements.whereType<int>().toList() : null,
      );
    }),
  ),
  ..._aimableCommandTools,
  ModelTool(
    Tool(
      name: 'batch',
      description:
          'Run several commands as one undo step, all or nothing. Each '
          'entry is a command object — "name" plus that command\'s own '
          'arguments, the same shape amend and the journal use — and may '
          'carry its own "object"/"faces"/"edges"/"vertices"/"ids" target. '
          'If any entry refuses, the whole batch is taken back and the '
          'project is exactly as it was; the answer names the entry that '
          'refused and why. Use it for a run of edits that only makes sense '
          'together, so a person\'s undo takes back the change rather than '
          'the last third of it.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'commands': ListSchema(
            description: 'the commands to run, in order',
            items: ObjectSchema(),
            minItems: 1,
          ),
        },
        required: <String>['commands'],
      ),
    ),
    (ModelSession session, Map<String, Object?> arguments) async {
      final Object? commands = arguments['commands'];
      if (commands is! List) {
        return (did: false, says: 'batch needs a list of "commands"');
      }
      // `mcp-14n`'s own lock — see `_command`'s own copy of this line. A
      // batch opens a transaction of its own, and two open at once is a
      // `StateError` rather than a refusal.
      await session.history.whenNotInTransaction;
      return session.batch(<Map<String, Object?>>[
        for (final Object? entry in commands)
          if (entry is Map<String, Object?>) entry,
      ]);
    },
  ),
  ModelTool(
    Tool(
      name: 'amend',
      description:
          'Adjust the last operation instead of pushing a second one '
          'on top of it — the operation card\'s own slider. Takes a whole '
          'command object, the same shape run/the journal use ("name" '
          'plus that command\'s own arguments, e.g. {"name": "extrude", '
          '"distance": 0.09}) and re-runs it against the document as it '
          'was before the step being adjusted, replacing that step rather '
          'than adding a new one. Refused when there is nothing to adjust, '
          'or when the new arguments themselves are refused — the old step '
          'is left in place either way.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'name': StringSchema(
            description: 'the command to re-run, e.g. "extrude"',
          ),
        },
        required: <String>['name'],
      ),
    ),
    (ModelSession session, Map<String, Object?> arguments) async {
      final ModelCommand? command = modelCommandFromJson(arguments);
      if (command == null) {
        final Object? name = arguments['name'];
        return (
          did: false,
          says:
              '${name ?? 'that'} cannot be read from those arguments — '
              'check the schema tools/list gave for the command amend is '
              'adjusting to',
        );
      }
      // `mcp-14n`'s own lock — see `_command`'s own copy of this line.
      await session.history.whenNotInTransaction;
      return session.amend(command);
    },
  ),
  ModelTool(
    Tool(
      name: 'undo',
      description:
          'Put the project back the way it was before the last '
          'change, and say which change that was.',
      inputSchema: ObjectSchema(),
    ),
    _sync(
      (ModelSession session, Map<String, Object?> arguments) => session.undo(),
    ),
  ),
  ModelTool(
    Tool(
      name: 'redo',
      description: 'Put back the change that undo just took away.',
      inputSchema: ObjectSchema(),
    ),
    _sync(
      (ModelSession session, Map<String, Object?> arguments) => session.redo(),
    ),
  ),
  ModelTool(
    Tool(
      name: 'check',
      description:
          'What is wrong with the project, as an export would see '
          'it — budgets, n-gons, manifoldness. Worth calling before export.',
      inputSchema: ObjectSchema(),
    ),
    _sync(
      (ModelSession session, Map<String, Object?> arguments) =>
          (did: true, says: session.check()),
    ),
  ),
  ModelTool(
    Tool(
      name: 'save',
      description:
          'Write the project out in its own format, keeping the '
          'parameters, the history and everything else an export would lose. '
          'With no path it writes back where it was opened from.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'path': StringSchema(
            description:
                'where to write it, or leave it '
                'out to write back',
          ),
        },
      ),
    ),
    _sync((ModelSession session, Map<String, Object?> arguments) {
      final path = arguments['path'];
      return session.save(path is String ? path : null);
    }),
  ),
  ModelTool(
    Tool(
      name: 'export',
      description:
          'Take the project out to a format a game or another tool reads: '
          '${builtInModelWriters.map((ModelWriter w) => '"${w.name}" (${w.says})').join(', ')}. '
          'The format is the extension of "to" unless named; a JSON ".gltf" '
          'with a separate ".bin" is not built and this says so. Refused when '
          'the project has an error-level issue unless force is set.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'to': StringSchema(description: 'the path to write'),
          'format': StringSchema(
            description:
                'defaults to the extension of '
                '"to"',
          ),
          'force': BooleanSchema(
            description:
                'write anyway despite an error, '
                'default false',
          ),
        },
        required: <String>['to'],
      ),
    ),
    _sync((ModelSession session, Map<String, Object?> arguments) {
      final to = arguments['to'];
      if (to is! String) {
        return (did: false, says: 'export needs a "to" path');
      }
      return session.export(
        to,
        format: arguments['format'] as String?,
        force: arguments['force'] == true,
      );
    }),
  ),
  ModelTool(
    Tool(
      name: 'import',
      description:
          'Bring a glTF, GLB, OBJ, `.f3d` or STL file in as new '
          'objects, added beside what is already here. Every object it '
          'brings arrives as one undo step. An FBX file is recognised and '
          'refused with the reason. Defaults to no scaling, up axis "y" and '
          'every object left exactly as the file read — pass unit/upAxis '
          'for a file with a different convention of its own (an `.stl` in '
          'particular carries no unit at all) and weld/fixNormals/'
          'triangulate to build real mesh topology on the way in, the same '
          'choices the app\'s own import screen offers a person.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'from': StringSchema(description: 'the path to read'),
          'unit': _importUnit(
            'the file\'s own unit: "mm" (an `.stl`\'s usual '
            'convention), "cm" or "m" (default, no scaling)',
          ),
          'upAxis': _upAxis('the file\'s own up axis, default "y"'),
          'weld': BooleanSchema(
            description:
                'weld coincident vertices into real mesh '
                'topology on the objects this import adds, default false '
                '(left byte-for-byte as the file read)',
          ),
          'fixNormals': BooleanSchema(
            description:
                'recalculate normals on the objects this '
                'import adds, default false',
          ),
          'triangulate': BooleanSchema(
            description:
                'triangulate every n-gon on the objects this '
                'import adds, default false',
          ),
        },
        required: <String>['from'],
      ),
    ),
    (ModelSession session, Map<String, Object?> arguments) {
      final from = arguments['from'];
      if (from is! String) {
        return Future<Answer>.value((
          did: false,
          says: 'import needs a "from" path',
        ));
      }
      final unit = arguments['unit'];
      final scale = unit is String ? (_importUnitScale[unit] ?? 1.0) : 1.0;
      final upAxis = arguments['upAxis'] == 'z' ? UpAxis.z : UpAxis.y;
      return session.import(
        from,
        options: ImportOptions(scale: scale, upAxis: upAxis),
        weld: arguments['weld'] == true,
        fixNormals: arguments['fixNormals'] == true,
        triangulate: arguments['triangulate'] == true,
      );
    },
  ),
  ModelTool(
    Tool(
      name: 'journal',
      description:
          'Write every command this session has run, successfully, '
          'to a JSON Lines file — `doc-16`\'s `CommandJournal` format, for '
          'recovery or an audit trail. Not the project itself; save is that.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'to': StringSchema(description: 'the path to write'),
        },
        required: <String>['to'],
      ),
    ),
    _sync((ModelSession session, Map<String, Object?> arguments) {
      final to = arguments['to'];
      if (to is! String) {
        return (did: false, says: 'journal needs a "to" path');
      }
      return session.journal(to);
    }),
  ),
  ModelTool(
    Tool(
      name: 'cleanup',
      description:
          'Weld every mesh\'s own duplicate vertices, drop faces '
          'with no area, and wind every closed shell outward — the whole '
          'project, one undo step. Worth calling right after import.',
      inputSchema: ObjectSchema(),
    ),
    _sync(
      (ModelSession session, Map<String, Object?> arguments) =>
          session.cleanup(),
    ),
  ),
  ModelTool(
    Tool(
      name: 'makeGameReady',
      description:
          'Triangulate every mesh, recalculate normals, and fit '
          'every image to a texture budget — "desktop", "mobile" or "web" '
          '— all in one undo step. The project\'s own profile is not '
          'changed; this only fits images to the named budget for this '
          'call.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'profile': UntitledSingleSelectEnumSchema(
            values: <String>['desktop', 'mobile', 'web'],
          ),
        },
        required: <String>['profile'],
      ),
    ),
    _sync((ModelSession session, Map<String, Object?> arguments) {
      final profile = arguments['profile'];
      if (profile is! String) {
        return (did: false, says: 'makeGameReady needs a "profile"');
      }
      return session.makeGameReady(profile);
    }),
  ),
  ModelTool(
    Tool(
      name: 'buildFrom',
      description:
          'Add a batch of primitives in one undo step. Each entry '
          'takes addPrimitive\'s own arguments (kind, size, segments, at) '
          'plus an optional name and an optional parent — the index of an '
          'earlier entry in this same list, not an object id, since '
          'nothing in the batch has one until this runs.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'spec': ListSchema(
            description: 'the batch, built in order',
            items: ObjectSchema(
              properties: <String, Schema>{
                'kind': UntitledSingleSelectEnumSchema(
                  values: AddPrimitive.primitiveKinds,
                ),
                'size': NumberSchema(
            description: 'how big across, in metres; default 1',
          ),
                'segments': IntegerSchema(
            description: 'how many segments around, default 32',
          ),
                'at': _vector('where it goes, default the origin'),
                'name': StringSchema(description: 'what to call it'),
                'parent': IntegerSchema(
                  description:
                      'an earlier index in this same list, for '
                      'a child of it',
                ),
              },
              required: <String>['kind'],
            ),
          ),
        },
        required: <String>['spec'],
      ),
    ),
    _sync((ModelSession session, Map<String, Object?> arguments) {
      final spec = arguments['spec'];
      if (spec is! List) {
        return (did: false, says: 'buildFrom needs a "spec" list');
      }
      return session.buildFrom(
        spec.map((Object? e) => Map<String, Object?>.from(e! as Map)).toList(),
      );
    }),
  ),
  ModelTool(
    Tool(
      name: 'inspect',
      description:
          'Metrics (object, vertex and face counts) and issues in '
          'one call — list and check together, for a quick read on what '
          'was just built. No picture yet.',
      inputSchema: ObjectSchema(),
    ),
    _sync(
      (ModelSession session, Map<String, Object?> arguments) =>
          (did: true, says: session.inspect()),
    ),
  ),
  ..._rigPipelineTools,
];

// ------------------------------------------------------------- anim-30
//
// MCP tools over `anim-21`'s `buildSkeleton`, `anim-15`'s `bakeIk`,
// `anim-20`'s `bakeShapeDrivers`, `anim-13`'s `rigIssues` and `anim-17`'s
// `retargetClip`, plus `addShape` — a second, plan-facing name for the
// already-offered `addShapeFromMesh` tool.
// Kept as one block, appended after every other tool, rather than woven in
// beside the rig/keyframe tools above: `setKey`, `extractRootMotion` and
// `addShapeFromMesh` already existed on this branch before this row and
// are untouched; everything here is new, and a merge that finds this file
// changed elsewhere too only has to reconcile one seam, not several.
//
// **`paintWeights` itself sits here too, but runs through `_command`, not
// a session recipe.** `anim-10`'s own `PaintWeights` is a real
// `ModelCommand` (`flutter3d_model_core`'s own `paint_weights.dart`) —
// unlike every other tool in this block, which wraps a real function that
// cannot be one. It stays in this block anyway rather than moving up
// beside the other command tools: it is still part of the same rig
// pipeline scenario `rig_pipeline_mcp_test.dart` drives end to end, and
// splitting it out would cost that continuity for no reader's benefit.
List<ModelTool> get _rigPipelineTools => <ModelTool>[
  ModelTool(
    Tool(
      name: 'autoRig',
      description:
          'Build a humanoid or quadruped skeleton from a handful of '
          'world-space marker positions (one per joint the template asks '
          'for — call this with a wrong or missing marker to see which) '
          'and add it to the project as one undo step. Every right-side '
          'joint is the mirror of its left-side marker; only the left half '
          'and the centerline need naming. skinObjectId, when given, binds '
          'that object\'s own mesh to the new skeleton in the same step — '
          'paintWeights is what then puts real weights on its vertices. '
          'spineCount, fingers, toes, faceBones, ikChains and controllers '
          'compose extra joints (humanoid only, past the base template) — '
          'see the refusal this gives if a combination would deform more '
          'than the skinning shader\'s own 64 joints.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'template': UntitledSingleSelectEnumSchema(
            description: 'humanoid or quadruped',
            values: <String>['humanoid', 'quadruped'],
          ),
          'markers': ObjectSchema(
            description:
                'marker name to a 3-number world position; see the '
                'refusal this gives for which names a template needs',
            additionalProperties: _vector('a marker\'s world position'),
          ),
          'skinObjectId': IntegerSchema(
            description: 'an object to bind to the new skeleton; optional',
          ),
          'skeletonName': StringSchema(description: 'optional'),
          'mirrorAxis': UntitledSingleSelectEnumSchema(
            description: 'x (default), y or z',
            values: <String>['x', 'y', 'z'],
          ),
          'bounds': ListSchema(
            description:
                'optional sanity box, 6 numbers in metres: minX minY minZ '
                'maxX maxY maxZ; computed from the markers themselves '
                'when left out',
            items: NumberSchema(),
            minItems: 6,
            maxItems: 6,
          ),
          'spineCount': IntegerSchema(
            description:
                '1 (default) through 3 spine segments between hips and '
                'chest; humanoid only',
          ),
          'fingers': BooleanSchema(
            description:
                'five three-phalanx fingers per hand, off the wrists; '
                'humanoid only, default false',
          ),
          'toes': BooleanSchema(
            description:
                'one toes joint per foot, off the ankles; humanoid only, '
                'default false',
          ),
          'faceBones': BooleanSchema(
            description:
                'a jaw and two eyes, derived from head/neck; humanoid '
                'only, default false',
          ),
          'ikChains': BooleanSchema(
            description:
                'two-bone IK on both arms and both legs; humanoid only, '
                'default false',
          ),
          'controllers': BooleanSchema(
            description:
                'a socket-parent controller above the root joint, not '
                'itself a deforming joint; default false',
          ),
        },
        required: <String>['template', 'markers'],
      ),
    ),
    (ModelSession session, Map<String, Object?> arguments) async {
      final template = arguments['template'];
      final markersJson = arguments['markers'];
      if (template is! String || markersJson is! Map) {
        return (did: false, says: 'autoRig needs a "template" and "markers"');
      }
      final markers = <String, List<double>>{};
      for (final entry in markersJson.entries) {
        final value = entry.value;
        if (value is! List || value.length != 3) {
          return (
            did: false,
            says: 'marker "${entry.key}" needs a 3-number position',
          );
        }
        markers[entry.key as String] = <double>[
          for (final n in value) (n as num).toDouble(),
        ];
      }
      final bounds = arguments['bounds'];
      return session.autoRig(
        template: template,
        markers: markers,
        skinObjectId: arguments['skinObjectId'] as int?,
        skeletonName: arguments['skeletonName'] as String?,
        mirrorAxis: arguments['mirrorAxis'] as String? ?? 'x',
        bounds: bounds is List
            ? <double>[for (final n in bounds) (n as num).toDouble()]
            : null,
        spineCount: (arguments['spineCount'] as num?)?.toInt() ?? 1,
        fingers: arguments['fingers'] as bool? ?? false,
        toes: arguments['toes'] as bool? ?? false,
        faceBones: arguments['faceBones'] as bool? ?? false,
        ikChains: arguments['ikChains'] as bool? ?? false,
        controllers: arguments['controllers'] as bool? ?? false,
      );
    },
  ),
  ModelTool(
    Tool(
      name: 'paintWeights',
      description:
          'Paint one joint\'s skin weight influence over one or more brush '
          'samples on an object\'s own mesh, hit-tested against the '
          'mesh\'s current posed shape, as one undo step. mode "paint" '
          'blends onto whatever a vertex already has; "assign" replaces '
          'its whole influence list with this one joint. normalize '
          '(default true) prunes every touched vertex to maxInfluences — '
          'the project\'s own profile limit by default — and renormalizes '
          'it, once the stroke (and the mirror, when one is given) is '
          'done.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'objectId': IntegerSchema(description: 'the object, with a mesh'),
          'skeletonIndex': IntegerSchema(
            description: 'which skeleton, from list',
          ),
          'joint': IntegerSchema(
            description: 'the joint\'s own object id, from that skeleton',
          ),
          'samples': ListSchema(
            description: 'one or more brush hits making up this stroke',
            items: ObjectSchema(
              properties: <String, Schema>{
                'center': _vector('where the brush hit, in world space'),
                'radius': NumberSchema(description: 'how far the hit reaches'),
              },
              required: <String>['center', 'radius'],
            ),
          ),
          'strength': NumberSchema(description: 'how much weight to add'),
          'mode': UntitledSingleSelectEnumSchema(
            description: 'paint (default) or assign',
            values: <String>['paint', 'assign'],
          ),
          'mirror': ObjectSchema(
            description: 'optional; mirror the stroke across a plane',
            properties: <String, Schema>{
              'axis': IntegerSchema(
            description:
                'which axis to mirror across, as an index: 0 for x, 1 '
                'for y, 2 for z',
          ),
              'jointMirror': ObjectSchema(
                description: 'source joint index (string key) to target',
                additionalProperties: IntegerSchema(),
              ),
              'plane': NumberSchema(description: 'default 0'),
              'tolerance': NumberSchema(description: 'default 1e-4'),
            },
            required: <String>['axis', 'jointMirror'],
          ),
          'normalize': BooleanSchema(
            description:
                'prune every touched vertex to maxInfluences and '
                'renormalize it after the stroke; default true',
          ),
          'maxInfluences': IntegerSchema(
            description:
                'how many joints may pull on one vertex once normalize '
                'has pruned; default the project\'s own profile limit',
          ),
        },
        required: <String>[
          'objectId',
          'skeletonIndex',
          'joint',
          'samples',
          'strength',
        ],
      ),
    ),
    _command('paintWeights'),
  ),
  ModelTool(
    Tool(
      name: 'retargetClip',
      description:
          'Retarget a clip authored for one skeleton onto another '
          'skeleton\'s own joints — rest-relative rotation, height-scaled '
          'translation, with a two-bone IK foot lock by default — and '
          'append the result as a new clip. boneMap left out guesses one '
          'from matching joint names.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'sourceClipIndex': IntegerSchema(description: 'the clip to read'),
          'sourceSkeletonIndex': IntegerSchema(
            description: 'the skeleton that clip\'s tracks address',
          ),
          'targetSkeletonIndex': IntegerSchema(
            description: 'the skeleton to retarget onto',
          ),
          'boneMap': ObjectSchema(
            description:
                'optional; source joint name to target joint name. Left '
                'out, matching names are mapped automatically',
            additionalProperties: StringSchema(),
          ),
          'lockFeet': BooleanSchema(description: 'default true'),
          'groundY': NumberSchema(
            description: 'where the floor is, in metres; default 0',
          ),
          'footTolerance': NumberSchema(
            description:
                'how far a foot may drift from the floor before it is '
                'locked to it, in metres; default 1e-3',
          ),
          'clipName': StringSchema(description: 'optional'),
        },
        required: <String>[
          'sourceClipIndex',
          'sourceSkeletonIndex',
          'targetSkeletonIndex',
        ],
      ),
    ),
    _sync((ModelSession session, Map<String, Object?> arguments) {
      final sourceClipIndex = arguments['sourceClipIndex'];
      final sourceSkeletonIndex = arguments['sourceSkeletonIndex'];
      final targetSkeletonIndex = arguments['targetSkeletonIndex'];
      if (sourceClipIndex is! int ||
          sourceSkeletonIndex is! int ||
          targetSkeletonIndex is! int) {
        return (
          did: false,
          says:
              'retargetClip needs "sourceClipIndex", "sourceSkeletonIndex" '
              'and "targetSkeletonIndex"',
        );
      }
      final boneMapJson = arguments['boneMap'];
      return session.retargetClip(
        sourceClipIndex: sourceClipIndex,
        sourceSkeletonIndex: sourceSkeletonIndex,
        targetSkeletonIndex: targetSkeletonIndex,
        boneMap: boneMapJson is Map
            ? <String, String>{
                for (final e in boneMapJson.entries)
                  e.key as String: e.value as String,
              }
            : null,
        lockFeet: arguments['lockFeet'] as bool? ?? true,
        groundY: (arguments['groundY'] as num?)?.toDouble() ?? 0.0,
        footTolerance: (arguments['footTolerance'] as num?)?.toDouble() ?? 1e-3,
        clipName: arguments['clipName'] as String?,
      );
    }),
  ),
  ModelTool(
    Tool(
      name: 'bakeIk',
      description:
          'Solve a two-bone IK chain (root, mid, effector reaching for '
          'target, bending toward pole) at every 1/fps second of a clip, '
          'and write the result as the root and mid joints\' own baked '
          'rotation keyframes — export always plays the baked clip, never '
          'a live IK constraint.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'clipIndex': IntegerSchema(description: 'which clip, from list'),
          'rootJointId': IntegerSchema(description: 'the chain\'s own root'),
          'midJointId': IntegerSchema(description: 'the chain\'s own middle'),
          'effectorJointId': IntegerSchema(description: 'the chain\'s own tip'),
          'target': _vector('where the effector should reach'),
          'pole': _vector('which side the middle joint bends toward', unit: 'a direction, no unit'),
          'fps': NumberSchema(
            description: 'how many samples a second, in fps; default 30',
          ),
        },
        required: <String>[
          'clipIndex',
          'rootJointId',
          'midJointId',
          'effectorJointId',
          'target',
          'pole',
        ],
      ),
    ),
    _sync((ModelSession session, Map<String, Object?> arguments) {
      final clipIndex = arguments['clipIndex'];
      final rootJointId = arguments['rootJointId'];
      final midJointId = arguments['midJointId'];
      final effectorJointId = arguments['effectorJointId'];
      final target = arguments['target'];
      final pole = arguments['pole'];
      if (clipIndex is! int ||
          rootJointId is! int ||
          midJointId is! int ||
          effectorJointId is! int ||
          target is! List ||
          pole is! List) {
        return (
          did: false,
          says:
              'bakeIk needs "clipIndex", "rootJointId", "midJointId", '
              '"effectorJointId", "target" and "pole"',
        );
      }
      return session.bakeIkOnClip(
        clipIndex: clipIndex,
        rootJointId: rootJointId,
        midJointId: midJointId,
        effectorJointId: effectorJointId,
        target: <double>[for (final n in target) (n as num).toDouble()],
        pole: <double>[for (final n in pole) (n as num).toDouble()],
        fps: (arguments['fps'] as num?)?.toDouble() ?? 30,
      );
    }),
  ),
  ModelTool(
    Tool(
      name: 'bakeDrivers',
      description:
          'Bake one or more shape-key drivers (each reading how far a '
          'joint has turned about one axis) into one more weights track on '
          'a clip, naming the shape-owning object — additive, so drivers '
          'naming the same shape add rather than the second overwriting '
          'the first. "drivers" is optional: when it is left out, this '
          'bakes the shape-owning object\'s own drivers, whatever '
          'addShapeDriver has built up on it.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'clipIndex': IntegerSchema(description: 'which clip, from list'),
          'shapeTargetObjectId': IntegerSchema(
            description: 'the object whose shape keys are driven',
          ),
          'drivers': ListSchema(
            description:
                'one or more drivers, combined additively; omit to bake '
                'the object\'s own persisted shape drivers instead',
            items: ObjectSchema(
              properties: <String, Schema>{
                'shapeIndex': IntegerSchema(
                  description: 'the shape key, from list',
                ),
                'jointId': IntegerSchema(description: 'the joint to read'),
                'axis': UntitledSingleSelectEnumSchema(
                  description: 'x (default), y or z',
                  values: <String>['x', 'y', 'z'],
                ),
                'from': NumberSchema(
                  description: 'the angle, in radians, that reads as 0',
                ),
                'to': NumberSchema(
                  description: 'the angle, in radians, that reads as 1',
                ),
              },
              required: <String>['shapeIndex', 'jointId', 'from', 'to'],
            ),
          ),
        },
        required: <String>['clipIndex', 'shapeTargetObjectId'],
      ),
    ),
    _sync((ModelSession session, Map<String, Object?> arguments) {
      final clipIndex = arguments['clipIndex'];
      final shapeTargetObjectId = arguments['shapeTargetObjectId'];
      if (clipIndex is! int || shapeTargetObjectId is! int) {
        return (
          did: false,
          says: 'bakeDrivers needs "clipIndex" and "shapeTargetObjectId"',
        );
      }
      final driversJson = arguments['drivers'];
      List<Map<String, Object?>>? drivers;
      if (driversJson != null) {
        if (driversJson is! List) {
          return (
            did: false,
            says: '"drivers", when given, needs to be a list',
          );
        }
        drivers = <Map<String, Object?>>[
          for (final d in driversJson) Map<String, Object?>.from(d! as Map),
        ];
      }
      return session.bakeDrivers(
        clipIndex: clipIndex,
        shapeTargetObjectId: shapeTargetObjectId,
        drivers: drivers,
      );
    }),
  ),
  ModelTool(
    Tool(
      name: 'addShape',
      description:
          'Add a new shape key to an object, captured from the mesh\'s own '
          'current vertex positions — the same command addShapeFromMesh '
          'already offers, under the name the rig-pipeline scenario '
          'knows it by. Sculpt the mesh first, then call this to save it '
          'as a shape; it starts at weight 0.0.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'id': IntegerSchema(description: 'the object; needs an edited mesh'),
          'shapeName': StringSchema(description: 'the new shape key\'s name'),
        },
        required: <String>['id', 'shapeName'],
      ),
    ),
    _command('addShapeFromMesh'),
  ),
  ModelTool(
    Tool(
      name: 'validateRig',
      description:
          'Everything wrong with this project\'s skeletons and clips — '
          'bone counts over budget, weights that do not sum to one, a '
          'weight naming a joint that is not there, a joint no vertex '
          'weighs to. Read-only, the rig-shaped half of what check already '
          'covers for geometry and materials.',
      inputSchema: ObjectSchema(),
    ),
    _sync(
      (ModelSession session, Map<String, Object?> arguments) =>
          (did: true, says: session.validateRig()),
    ),
  ),
];
