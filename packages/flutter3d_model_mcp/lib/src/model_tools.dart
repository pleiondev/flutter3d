import 'package:dart_mcp/server.dart';
import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';

import 'model_session.dart';

/// One tool: what an agent is offered, and what calling it does.
///
/// **A pair rather than a table and a switch**, for the reason
/// `flutter3d_editor_mcp`'s `EditorTool` gives: a tool that is offered is a
/// tool that has a body, because they are the same object, so the two halves
/// cannot drift the way a `tools/list` array and a `tools/call` switch can.
final class ModelTool {
  const ModelTool(this.tool, this.run);

  /// What `tools/list` hands the agent: a name, a sentence and a schema.
  final Tool tool;

  /// What calling it does to the session. Async because [ModelSession.import]
  /// decodes a file, which every decoder in this repository does off the
  /// synchronous path.
  final Future<Answer> Function(
    ModelSession session,
    Map<String, Object?> arguments,
  )
  run;

  String get name => tool.name;
}

Future<Answer> Function(ModelSession, Map<String, Object?>) _sync(
  Answer Function(ModelSession, Map<String, Object?>) body,
) =>
    (ModelSession session, Map<String, Object?> arguments) async =>
        body(session, arguments);

// --------------------------------------------------------------- schemas

/// Three numbers, which is how the project spells every position, axis and
/// size.
ListSchema _vector(String about) => ListSchema(
  description: about,
  items: NumberSchema(),
  minItems: 3,
  maxItems: 3,
);

/// Sixteen numbers, column-major — `Matrix4.storage` — for the two commands
/// that take a whole transform rather than a friendlier vector or angle.
ListSchema _matrix16(String about) => ListSchema(
  description: about,
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
  return session.run(command);
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
        properties: <String, Schema>{'by': _vector('how far, as x, y, z')},
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
          'axis': _vector('the axis to turn about'),
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
          'by': NumberSchema(description: 'the factor, above 0'),
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
          'to': IntegerSchema(description: 'the new parent; omit for none'),
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
            description: 'which shape',
            values: AddPrimitive.primitiveKinds,
          ),
          'size': NumberSchema(description: 'how big, default 1'),
          'segments': IntegerSchema(description: 'how round, default 32'),
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
          'segments': IntegerSchema(description: 'how round, default 32'),
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
          'distance': NumberSchema(description: 'how far, along the normal'),
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
            description: '0 to 1 along the edge, default 0.5 (centred)',
          ),
        },
      ),
    ),
    _command('loopCut'),
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
                'the threshold, default a '
                'small epsilon',
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
          'Set one field of a material by the name `.fmat` writes '
          'it under: name, baseColor (4 numbers), metallic, roughness, '
          'normalScale, occlusionStrength, emissive (3 numbers), '
          'emissiveStrength, alphaMode ("opaque"/"mask"/"blend"), '
          'alphaCutoff, doubleSided, unlit (the last two, booleans). Texture '
          'slots go through setTexture instead.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'index': IntegerSchema(description: 'the material row'),
          'field': StringSchema(description: 'the field name'),
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
      name: 'reorderModifier',
      description: 'Move a modifier to a different position in the stack.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'id': IntegerSchema(description: 'the object'),
          'from': IntegerSchema(description: 'the modifier\'s current index'),
          'to': IntegerSchema(description: 'where it should end up'),
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
      name: 'setProfileLimits',
      description:
          'Change the project\'s own rig limits — maxJoints and/or '
          'maxInfluences. Refused when a value is out of range: maxJoints '
          'past 64 (the skinning shader\'s own ceiling) or maxInfluences '
          'past 4 (a vertex stores four joint/weight pairs). Either field '
          'left out keeps the project\'s current value for it.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'maxJoints': IntegerSchema(description: 'new ceiling, 1 through 64'),
          'maxInfluences': IntegerSchema(
            description: 'new ceiling, 1 through 4',
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
      name: 'addJoint',
      description:
          'Add an existing object to a skeleton as a new joint, appended '
          'at the end of the joint list. Refused if the object is already '
          'a joint in that skeleton.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'skeletonIndex': IntegerSchema(description: 'which skeleton, from list'),
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
          'skeletonIndex': IntegerSchema(description: 'which skeleton, from list'),
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
          'skeletonIndex': IntegerSchema(description: 'which skeleton, from list'),
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
          'skeletonIndex': IntegerSchema(description: 'which skeleton, from list'),
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
          'skeletonIndex': IntegerSchema(description: 'which skeleton, from list'),
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
          'skeletonIndex': IntegerSchema(description: 'which skeleton, from list'),
          'axis': IntegerSchema(description: '0 for x, 1 for y, 2 for z'),
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
          'values': _numbers('one number a component'),
          'inTangent': _numbers('optional; one number a component'),
          'outTangent': _numbers('optional; one number a component'),
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
          'deltaTime': NumberSchema(description: 'how far to shift, in seconds'),
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
          'inTangent': _numbers('optional; one number a component'),
          'outTangent': _numbers('optional; one number a component'),
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
          'frame': IntegerSchema(description: 'which frame, at the project\'s own fps'),
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
  ..._commandTools,
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
          'Take the project out to a format a game or another tool '
          'reads: "f3d" or "obj" today. glTF/GLB is not built yet and this '
          'says so if asked for it. Refused when the project has an error-level '
          'issue unless force is set.',
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
          'brings arrives as one undo step.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'from': StringSchema(description: 'the path to read'),
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
      return session.import(from);
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
                'size': NumberSchema(description: 'how big, default 1'),
                'segments': IntegerSchema(description: 'how round, default 32'),
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
];
