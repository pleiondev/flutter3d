import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_mcp_kit/flutter3d_mcp_kit.dart' show Answer;
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
// `retargetClip` again, prefixed: this class has a method of that name, and a
// bare call inside it would be the method calling itself.
import 'package:flutter3d_model_core/flutter3d_model_core.dart'
    as core
    show retargetClip;
// The rig algorithms again, prefixed: `rig.autoMap` reads at every call site
// as what it is — a guess from bone names, not one of this session's verbs.
import 'package:flutter3d_model_core/flutter3d_model_core.dart'
    as rig
    show BoneMap, autoMap;
import 'package:vector_math/vector_math.dart';

// What a tool call did, and the sentence to say about it — the one `Answer`
// every server here shares, so a host importing two of them has one name.
export 'package:flutter3d_mcp_kit/flutter3d_mcp_kit.dart' show Answer;

/// What a call says it acts on, instead of leaving it to the selection —
/// `ux-20`. See [ModelSession.targetIn] for how it is read out of a call's
/// own arguments, and [ModelSession.runOn] for what it does.
typedef CommandTarget = ({
  int? object,
  String? level,
  List<int>? elements,
  List<int>? objects,
});

/// One model project, open, with the editor's own verbs on it.
///
/// **One per process, because the project is the state.** There is no `open`
/// tool and no second project — an agent that could swap the document
/// underneath itself would be left holding an undo stack describing a file it
/// is no longer editing. A host that wants two projects starts two processes.
///
/// **Runs every command through [ModelHistory], never through a command's own
/// `apply`.** That is where a step gets undone and where a slider's `amend`
/// lives; going around it would give an agent an edit nothing can take back.
final class ModelSession {
  /// Attaches a fresh [CommandJournal] to [history] when it does not already
  /// carry one (`??=`, not `=`) — `tut-15`'s own fix: `--mcp-port` binds a
  /// session over a [ModelHistory] the app already built and may already be
  /// editing, and this is what makes every command *this* session ever runs
  /// — and, since [ModelHistory.run]/[ModelHistory.amend] now record to
  /// whichever journal is attached regardless of caller, every command a
  /// person runs directly against the same shared [history] too — land on
  /// one recovery journal rather than each caller needing one of its own.
  ModelSession(this.history, {this.path, this.client}) {
    history.recoveryJournal ??= CommandJournal();
  }

  /// Which client this session is talking to, by the name it said hello with
  /// — `ux-45`. Every step this session makes is stamped with it, so an undo
  /// stack shared with a person, and possibly with a second agent, says which
  /// of them did what. Null until `initialize` arrives, and for a session a
  /// test built directly.
  String? client;

  /// Opens the project at [path], or a fresh one when there is nothing there
  /// yet — the shape `dart_mcp`'s own examples and `Г8` (the plan's decision
  /// on this) both ask for: a host naming a project that does not exist yet is
  /// asking to start one, not making a mistake.
  factory ModelSession.open(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      return ModelSession(ModelHistory(const ModelProject()), path: path);
    }
    final ProjectRead read = readProject(file.readAsBytesSync());
    return switch (read) {
      // `doc-31d`: a file with its own `history` section reopens with real
      // undo already on the stack, not just the project it last saved as.
      // `ModelHistory.withSteps` on an empty list (an older file, or one
      // saved with `save(includeHistory: false)`) is exactly
      // `ModelHistory(project)` — no branch needed for "this file has no
      // history."
      ProjectOpened(:final project, :final history) => ModelSession(
        ModelHistory.withSteps(project, history),
        path: path,
      ),
      ProjectRefused(:final because) => throw FormatException(because),
    };
  }

  final ModelHistory history;

  /// Where this was opened from, or last saved to. Null only for a session
  /// built directly in a test.
  String? path;

  /// Kept across calls to [export] rather than built fresh each time, so an
  /// object nobody has touched since the last export keeps the same
  /// [MeshData] — see `ProjectModelDocument`'s own doc comment for why that
  /// is worth doing at all.
  final ProjectModelDocument _document = ProjectModelDocument();

  ModelProject get project => history.project;

  /// Everything in the project, one line each, and what is selected.
  ///
  /// **The tool an agent has to call first.** Every command that names an
  /// object or a material takes an id, and a program with no screen has no
  /// way to guess one — without this, driving the editor means moving the
  /// third object without ever finding out there is a third object.
  /// **Every row carries what a command is going to ask for next** (`ux-19`).
  /// It used to be `id name (kind)` and nothing else, and the review watched
  /// an agent guess the rest: where an object it had just made had landed,
  /// whether the mesh it read a minute ago had moved under it, which of the
  /// two skeletons in the file `retargetClip` meant. All of it was in the
  /// project already; none of it was in the one call that exists to say what
  /// is there.
  String listing() {
    final objects = contentsOf(project);
    final materials = materialsOf(project);
    final skeletons = skeletonsOf(project);
    final clips = clipsOf(project);
    final lights = lightsOf(project);
    return <String>[
      if (objects.isEmpty) 'the project is empty' else ...objects.map(_line),
      if (materials.isNotEmpty) ...<String>[
        'materials:',
        for (final Listed material in materials)
          '  ${material.id} ${material.name}',
      ],
      if (skeletons.isNotEmpty) ...<String>[
        'skeletons:',
        for (final Listed row in skeletons)
          '  ${row.id} ${row.name}, ${row.about['joints']} joints',
      ],
      if (clips.isNotEmpty) ...<String>[
        'clips:',
        for (final Listed row in clips)
          '  ${row.id} ${row.name}, ${row.about['tracks']} tracks',
      ],
      if (lights.isNotEmpty) ...<String>[
        'lights:',
        for (final Listed row in lights)
          '  ${row.id} ${row.kind}, intensity ${row.about['intensity']}',
      ],
      '',
      'selection: $selection',
    ].join('\n');
  }

  String _line(Listed row) {
    final Object? vertices = row.about['vertices'];
    final shapes = shapesOf(project, row.id);
    final modifiers = modifiersOf(project, row.id);
    return <String>[
      '${row.id} ${row.name} (${row.kind}, v${row.version})',
      if (row.parent case final int parent) ' under $parent',
      ' at ${_place(row.transform)}',
      if (vertices != null)
        ', ${vertices}v ${row.about['edges']}e ${row.about['faces']}f',
      if (row.materials.isNotEmpty) ', materials ${row.materials.join('/')}',
      if (row.about['skeleton'] case final int skeleton) ', skeleton $skeleton',
      if (row.about['hidden'] == true) ', hidden',
      if (row.about['locked'] == true) ', locked',
      // Indented under the object rather than in a section of their own: a
      // shape key's index and a modifier's index are only meaningful beside
      // the object that owns them, and `setShapeWeight` names both.
      if (shapes.isNotEmpty)
        '\n  shapes: ${shapes.map((Listed it) => '${it.id} ${it.name} '
            '${it.about['weight']}').join(', ')}',
      if (modifiers.isNotEmpty)
        '\n  modifiers: ${modifiers.map((Listed it) => '${it.id} ${it.name}'
            '${it.about['enabled'] == false ? ' (off)' : ''}'
            '${it.about['inExport'] == false ? ' (not exported)' : ''}').join(', ')}',
    ].join();
  }

  /// A transform's own translation, which is what a person or an agent means
  /// by "where is it". The other twelve numbers are in `structuredContent`'s
  /// own `transform` for a caller that needs the rotation too — printing
  /// sixteen numbers a row would bury the listing.
  String _place(List<double>? transform) {
    if (transform == null || transform.length != 16) return '?';
    return '${_short(transform[12])} ${_short(transform[13])} '
        '${_short(transform[14])}';
  }

  static String _short(double value) => value.toStringAsFixed(3);

  /// One object in numbers: its box, and where each of its elements is, which
  /// way it faces and how big it is — `ux-19`.
  ///
  /// **The call that turns an agent's first edit from a guess into a pick.**
  /// `list` names objects and `select` takes element ids, and between the two
  /// there was nothing at all: an agent asked to extrude the top face of a
  /// cube could select face 0 through 5 and had no way to find out which of
  /// them pointed up. The review (§5.1) watched it choose one, render, look at
  /// the picture and try again — three calls and a rasterised image to answer
  /// a question the mesh knows the answer to.
  ///
  /// [level] is `vertex`, `edge` or `face`, defaulting to whichever the
  /// selection is at, or faces in object mode. [elements] names specific ones;
  /// without it this describes the first [limit] live ones, because a
  /// 200 000-face import would otherwise cost more context than the rest of
  /// the session put together.
  String describe(int id, {String? level, int? limit, List<int>? elements}) {
    final ModelObject? object = project[id];
    if (object == null) return 'there is no object $id';
    final Listed row = contentsOf(
      project,
    ).firstWhere((Listed it) => it.id == id);

    final String flags = <String>[
      if (object.parent case final int parent) ', under $parent',
      if (!object.visible) ', hidden',
      if (object.locked) ', locked',
    ].join();
    final head = <String>[
      '$id "${object.name}" — ${row.kind}, v${object.version}$flags',
      'at ${_place(row.transform)}',
      if (object.materialSlots.isNotEmpty)
        'materials ${object.materialSlots.join('/')}',
      for (final Listed shape in shapesOf(project, id))
        'shape ${shape.id} "${shape.name}" at ${shape.about['weight']}',
      for (final Listed modifier in modifiersOf(project, id))
        'modifier ${modifier.id} ${modifier.name} ${modifier.about['fields']}',
    ];

    if (object.geometry case EditedGeometry(:final mesh)) {
      final ElementLevel at =
          _levelNamed(level) ??
          (history.selection.mode == SelectionMode.mesh
              ? history.selection.level
              : ElementLevel.face);
      final Aabb3? box = boundsOfMesh(mesh);
      final int total = liveElements(mesh, at).length;
      final List<DescribedElement> described = describeElements(
        mesh,
        at,
        ids: elements,
        limit: limit ?? 50,
      );
      final String counts =
          '${mesh.vertexCount} vertices, ${mesh.edgeCount} edges, '
          '${mesh.faceCount} faces';
      final String more =
          '  … ${total - described.length} more; name them in "elements" or '
          'raise "limit"';
      return <String>[
        ...head,
        counts,
        if (box != null) 'bounds ${_vector(box.min)} to ${_vector(box.max)}',
        '${at.name}s (${described.length} of $total):',
        for (final DescribedElement each in described) '  ${_element(each)}',
        if (elements == null && described.length < total) more,
      ].join('\n');
    }
    final String unbaked =
        'no topology to describe — this is still a ${row.kind}. Run '
        '"bakeToMesh" or "buildTopology" to get elements with ids';
    return <String>[...head, unbaked].join('\n');
  }

  String _element(DescribedElement it) => <String>[
    '${it.id} at ${_vector(it.at)}',
    if (it.normal case final Vector3 normal) ' normal ${_vector(normal)}',
    if (it.area case final double area) ' area ${_short(area)}',
    if (it.length case final double length) ' length ${_short(length)}',
  ].join();

  String _vector(Vector3 it) =>
      '${_short(it.x)} ${_short(it.y)} ${_short(it.z)}';

  static ElementLevel? _levelNamed(String? word) {
    if (word == null) return null;
    for (final ElementLevel level in ElementLevel.values) {
      if (level.name == word) return level;
    }
    return null;
  }

  /// What a tool call answers in `structuredContent` — `ux-19`.
  ///
  /// **The sentence is for the model to read; this is for it to act on.**
  /// Every answer here has always carried what happened as prose, and an agent
  /// that wanted the id of the object it had just duplicated had to find it by
  /// calling `list` again and diffing against what it remembered. `ids` is
  /// what the newest step actually made, worked out from the step's own
  /// "before" rather than from a guess: `duplicate`, `import`, `separate`,
  /// `buildFrom` and every `add*` all answer it without any of them being
  /// special-cased.
  ///
  /// [made] is the object ids the call that is answering created, which the
  /// caller works out by bracketing the call — see `model_server.dart`. Kept a
  /// parameter rather than read from [history] here, because "the newest step"
  /// and "the step this call made" are different things the moment a call
  /// makes no step at all, and reporting the previous call's new objects again
  /// is worse than reporting none.
  Map<String, Object?> structured(
    Answer answer, {
    List<int> made = const <int>[],
  }) {
    // `ux-20`: a call that named its own target put the document's selection
    // back where it found it, and reporting *that* would tell an agent its
    // extrude selected nothing. What it selected while it ran is the answer.
    final ProjectSelection sel = reportedSelection ?? history.selection;
    return <String, Object?>{
      'did': answer.did,
      'says': answer.says,
      'ids': made,
      'selection': <String, Object?>{
        'mode': sel.mode.name,
        'objects': sel.objects,
        if (sel.mode == SelectionMode.mesh) ...<String, Object?>{
          'level': sel.level.name,
          'elements': sel.elements,
          if (sel.activeObject case final int active) 'object': active,
        },
      },
    };
  }

  /// The object ids in the project right now — what a caller takes before a
  /// tool call and hands back afterwards to find out what the call made.
  List<int> get objectIds => <int>[
    for (final ModelObject object in project.objects) object.id,
  ];

  /// The ids in [objectIds] that were not in [before], in project order.
  List<int> madeSince(List<int> before) {
    final was = before.toSet();
    return <int>[
      for (final ModelObject object in project.objects)
        if (!was.contains(object.id)) object.id,
    ];
  }

  /// The material table, one line a row — every field `setMaterialField`
  /// can set, which texture slots are painted and with which image, and
  /// whether a row is linked to a `.fmat` or carries a texture graph still
  /// waiting to be baked.
  ///
  /// **More than [listing] says about them.** `listing`'s own materials
  /// section exists so an id or a selection reads on one screen with
  /// everything else; an agent about to paint a table wants a row's real
  /// numbers first, and this is that agent's alternative to walking
  /// `SurfaceMaterial`'s fields itself.
  String listMaterials() {
    final materials = project.materials;
    if (materials.isEmpty) return 'no materials — call addMaterial';
    return <String>[
      for (var i = 0; i < materials.length; i++) _materialLine(i, materials[i]),
    ].join('\n');
  }

  String _materialLine(int index, ProjectMaterial material) {
    final SurfaceMaterial s = material.surface;
    final textures = <String>[
      if (s.baseColorTexture != null)
        'albedo=${s.baseColorTexture!.imageIndex}',
      if (s.normalTexture != null) 'normal=${s.normalTexture!.imageIndex}',
      if (s.metallicRoughnessTexture != null)
        'metallicRoughness=${s.metallicRoughnessTexture!.imageIndex}',
      if (s.occlusionTexture != null)
        'occlusion=${s.occlusionTexture!.imageIndex}',
      if (s.emissiveTexture != null)
        'emissive=${s.emissiveTexture!.imageIndex}',
    ];
    return '$index ${s.name ?? 'material $index'}: '
        'baseColor ${s.baseColor.storage.toList()}, '
        'metallic ${s.metallic}, roughness ${s.roughness}, '
        'alphaMode ${s.alphaMode.name}, doubleSided ${s.doubleSided}, '
        'unlit ${s.unlit}'
        '${textures.isEmpty ? '' : ', textures: ${textures.join(', ')}'}'
        '${material.fmat == null ? '' : ', linked to ${material.fmat}'}'
        '${material.graph == null
            ? ''
            : material.isGraphStale
            ? ', graph not yet baked'
            : ', graph baked'}';
  }

  /// What is selected, said to something that has no mouse.
  String get selection {
    final sel = history.selection;
    if (sel.isEmpty) return 'nothing selected — call select';
    return sel.mode == SelectionMode.object
        ? 'object${sel.objects.length == 1 ? '' : 's'} ${sel.objects.join(', ')}'
        : 'object ${sel.activeObject}, ${sel.level.name}s '
              '${sel.elements.join(', ')}';
  }

  /// Selects whole objects by id, or elements of one object at one level.
  ///
  /// **`SelectElements`, run through [history] like any other command
  /// (`tut-05`, closed).** This used to assign `history.selection =`
  /// directly — a click, named, the way the application makes one, but not a
  /// [ModelCommand] and so not something [CommandJournal] could replay. Now
  /// it runs a real, if non-mutating, command through [ModelHistory.run],
  /// which records it to whichever journal is attached the same as any other
  /// edit — a cold [journal] replay can rebuild a pick again, not only the
  /// edit that came after it.
  Answer select({
    List<int>? objects,
    int? object,
    String? level,
    List<int>? elements,
  }) {
    final String? refused = history.run(
      SelectElements(
        objects: objects,
        object: object,
        level: level,
        elements: elements,
      ),
      author: StepAuthor.agent,
    );
    if (refused != null) return (did: false, says: refused);
    return (did: true, says: selection);
  }

  /// Runs [command] through the history, always as `StepAuthor.agent` — every
  /// command an MCP tool call reaches this method with is one by definition,
  /// `mcp-10n`'s own row. [ModelHistory.run] itself records it, under that
  /// same author, to whichever journal is attached (`tut-15`): the session's
  /// own recovery file agrees with the live one about whose step each was
  /// without this method having to record to a journal of its own.
  Answer run(ModelCommand command) {
    final String? refused = history.run(
      command,
      author: StepAuthor.agent,
      client: client,
    );
    if (refused != null) {
      return (did: false, says: 'nothing did ${command.says}: $refused');
    }
    return (did: true, says: '${command.says} — $selection');
  }

  /// Runs [command] against something named rather than against whatever
  /// happens to be selected — `ux-20`.
  ///
  /// **The selection is a mouse's memory, and an agent has no mouse.** Every
  /// mesh command read `history.selection`, so driving the editor meant
  /// `select` then the edit, twice per operation, with the selection as a
  /// hidden argument between them — and the review found the failure that
  /// shape produces: a recipe changed the selection halfway through, the next
  /// call acted on what the recipe had left, and nothing in either answer said
  /// so. Naming the target makes the call say what it acts on.
  ///
  /// **The selection is put back afterwards, exactly as it was.** A call that
  /// names its own target is not asking to move the person's cursor, and
  /// `ux-20`'s own acceptance says so: `extrude` with an explicit face leaves
  /// an empty selection empty. What the command *did* select while it ran —
  /// the new faces an extrude makes — is not lost with it: it is kept in
  /// [reportedSelection], which is what the answer's own `structuredContent`
  /// reports, so the ids are in the reply even though the document's selection
  /// never moved.
  ///
  /// [object] with [level] and [elements] targets elements of one object;
  /// [objects] targets whole objects. Neither given, this is exactly [run].
  Answer runOn(
    ModelCommand command, {
    int? object,
    String? level,
    List<int>? elements,
    List<int>? objects,
  }) {
    if (object == null && objects == null) return run(command);

    final ProjectSelection was = history.selection;
    if (object != null) {
      final ElementLevel? at = _levelNamed(level) ?? _levelOf(was, object);
      if (at == null) {
        return (
          did: false,
          says:
              'naming elements of object $object needs a "level" — vertex, '
              'edge or face — unless something of that object is already '
              'selected',
        );
      }
      if (project[object] == null) {
        return (did: false, says: 'there is no object $object');
      }
      history.selection = ProjectSelection(
        mode: SelectionMode.mesh,
        objects: <int>[object],
        level: at,
        elements: elements ?? const <int>[],
      );
    } else {
      history.selection = ProjectSelection(
        mode: SelectionMode.object,
        objects: objects!,
      );
    }

    final Answer answer = run(command);
    reportedSelection = history.selection;
    history.selection = was;
    return answer;
  }

  /// Which level to read [object]'s own elements at when a call did not say:
  /// the one that is already live on that same object, or none.
  ElementLevel? _levelOf(ProjectSelection was, int object) =>
      was.mode == SelectionMode.mesh && was.activeObject == object
      ? was.level
      : null;

  /// What the last call left selected, when that is not what the document is
  /// left holding — `ux-20`'s own targeted calls, which put the selection
  /// back. Null the rest of the time, and cleared at the start of every call
  /// by whoever brackets one (`model_server.dart`).
  ProjectSelection? reportedSelection;

  /// Several commands as one undo step, all or nothing — `ux-20`.
  ///
  /// **All or nothing is the point, not the transaction.** [_recipe] already
  /// made a run of commands one step; what it did not do was put things back
  /// when one of them refused, so a batch that failed on its fourth command
  /// left three applied and an agent holding a sentence about the fourth. Here
  /// a refusal takes the whole batch back — the project, the meshes and the
  /// undo stack — and the answer names the entry that refused and why.
  ///
  /// Each entry is a command in the shape `modelCommandFromJson` reads, plus
  /// the optional `object`/`level`/`elements`/`objects` [runOn] takes, so a
  /// batch can name a different target per entry without a `select` between
  /// them.
  Answer batch(List<Map<String, Object?>> commands) {
    if (commands.isEmpty) return (did: false, says: 'a batch of nothing');

    // Read every entry before running any of them: an entry this build cannot
    // even name is not a reason to open a transaction and then unwind it.
    final read = <(ModelCommand, Map<String, Object?>)>[];
    for (var i = 0; i < commands.length; i++) {
      final ModelCommand? command = modelCommandFromJson(commands[i]);
      if (command == null) {
        return (
          did: false,
          says:
              'entry $i (${commands[i]['name'] ?? 'unnamed'}) is not a '
              'command this reads — check tools/list for its arguments',
        );
      }
      read.add((command, commands[i]));
    }

    final ProjectSelection was = history.selection;
    final int steps = history.steps.length;
    String? refused;
    var ran = 0;
    history.beginTransaction();
    try {
      for (final (ModelCommand command, Map<String, Object?> entry) in read) {
        final Answer answer = runTargeted(command, targetIn(entry));
        if (!answer.did) {
          refused = 'entry $ran (${command.name}) refused: ${answer.says}';
          break;
        }
        ran++;
      }
    } finally {
      history.endTransaction();
    }

    if (refused != null) {
      // Closed, then taken straight back — see `CommandJournal
      // .rollbackTransaction` for the same move on the journal, and for why
      // the step has to be checked for rather than assumed: a batch whose
      // very first command refused left no step, and an unguarded undo would
      // reach past it into whatever came before the batch.
      if (history.steps.length > steps) {
        history
          ..undo(onlyIfAuthoredBy: StepAuthor.agent)
          ..dropRedo();
      }
      history.recoveryJournal?.rollbackTransaction();
      history.selection = was;
      reportedSelection = null;
      return (did: false, says: 'nothing was changed — $refused');
    }
    return (
      did: true,
      says:
          'ran ${read.length} ${read.length == 1 ? 'command' : 'commands'} '
          'as one step — $selection',
    );
  }

  static List<int>? _intsIn(Object? value) =>
      value is List ? value.whereType<int>().toList() : null;

  /// `ux-20`'s own target arguments, read out of a call's own map: `object`
  /// with `faces`/`edges`/`vertices`, or `ids` for whole objects.
  ///
  /// **One way to name elements, not two** (`ux-43`). An earlier draft also
  /// took `level` with `elements`, for a caller holding a level in a
  /// variable; that is a second vocabulary for one idea, and two fields that
  /// can contradict each other. `faces: [4]` says which and what in one
  /// field, and cannot be said inconsistently.
  ///
  /// **Read here rather than in the tool table, because a batch entry is a
  /// call too.** The shorthand lived beside the schema at first and
  /// [batch]'s own entries went straight past it, so `{"name": "extrude",
  /// "object": 1, "faces": [0]}` worked as a tool call and was refused as a
  /// batch entry — the same JSON meaning two things depending on how it
  /// arrived.
  static CommandTarget targetIn(Map<String, Object?> arguments) {
    for (final MapEntry<String, String> named in _targetLevels.entries) {
      final List<int>? found = _intsIn(arguments[named.key]);
      if (found != null) {
        return (
          object: arguments['object'] as int?,
          level: named.value,
          elements: found,
          objects: _intsIn(arguments['ids']),
        );
      }
    }
    return (
      object: arguments['object'] as int?,
      level: null,
      elements: null,
      objects: _intsIn(arguments['ids']),
    );
  }

  /// The argument names that carry both the elements and what they are —
  /// `faces: [4]` rather than `level: "face", elements: [4]`, which is how a
  /// person says it and which cannot be said inconsistently.
  static const Map<String, String> _targetLevels = <String, String>{
    'vertices': 'vertex',
    'edges': 'edge',
    'faces': 'face',
  };

  /// [runOn]'s own arguments, gathered — see [targetIn].
  Answer runTargeted(ModelCommand command, CommandTarget target) => runOn(
    command,
    object: target.object,
    level: target.level,
    elements: target.elements,
    objects: target.objects,
  );

  /// Adjusts the top of the undo stack to [to] instead of pushing a second
  /// step — the operation card's own slider, reachable from outside the
  /// application for the first time (`tut-03`).
  ///
  /// **Calls through to the same [ModelHistory.amend] the app's own card
  /// calls directly** (`apps/flutter3d_modeler/lib/src/screen/
  /// interactions.dart`'s own `_amend`), so an agent adjusting the last
  /// operation reaches the identical re-run-against-the-document-before-it
  /// behaviour a person dragging the slider gets — not a second `run` that
  /// would leave two steps on the stack instead of one adjusted.
  ///
  /// **[ModelHistory.amend] itself records [to] to whichever journal is
  /// attached, not the step it replaces** (`tut-03`, `tut-15`) — under the
  /// step's own original author, the same one the adjusted [HistoryStep]
  /// keeps, so a cold [journal] replay lands on the adjusted state rather
  /// than the original one followed by an adjustment nothing on disk
  /// remembers, whoever made the step being adjusted.
  Answer amend(ModelCommand to) {
    final String? refused = history.amend(
      to,
      by: StepAuthor.agent,
      client: client,
    );
    if (refused != null) {
      return (did: false, says: 'nothing did ${to.says}: $refused');
    }
    return (did: true, says: '${to.says} — $selection');
  }

  /// Runs [body] as one [history] step — a recipe (`mcp-09n`) calling [run]
  /// several times inside [body] is one undo step in the live session and,
  /// thanks to [ModelHistory.beginTransaction]/[ModelHistory.endTransaction]
  /// bracketing whichever journal is attached the same way, one step again
  /// when `mcp-12n`'s own [CommandJournal.replay] rebuilds a crashed
  /// session's journal from disk (`tut-15`: [history]'s own transaction
  /// bracketing and its attached journal's are kept in step by [history]
  /// itself now, not by every caller separately).
  /// **And puts the selection back** — `ux-20`. A recipe walks the project
  /// object by object, assigning `history.selection` as it goes because the
  /// commands it runs read it; what it left behind was the last object it
  /// happened to touch. The review found the cost: an agent ran `cleanup` and
  /// then `extrude`, and the extrude landed on whatever mesh the cleanup had
  /// finished on. A recipe is one operation from outside, and one operation
  /// that was not about the selection should not move it.
  T _recipe<T>(T Function() body) {
    final ProjectSelection was = history.selection;
    try {
      return history.transaction(body);
    } finally {
      history.selection = was;
    }
  }

  /// Takes back the top step — refusing, by name, when it is not this
  /// session's own to take back. `mcp-10n`'s own acceptance: an agent's
  /// undo does not reach past a person's own step; a person's own ⌘Z (the
  /// app, not this session) is not gated the same way, since [undo] here is
  /// always asked for as [StepAuthor.agent].
  Answer undo() {
    final says = history.undoSays;
    if (says == null) return (did: false, says: 'nothing to undo');
    final StepAuthor? topAuthor = history.topStepAuthor;
    if (topAuthor != StepAuthor.agent) {
      return (
        did: false,
        says:
            'the top step ("$says") is a person\'s own, not this session\'s '
            '— an agent does not undo someone else\'s work',
      );
    }
    history.undo(onlyIfAuthoredBy: StepAuthor.agent);
    return (did: true, says: 'undid $says — $selection');
  }

  Answer redo() {
    final says = history.redoSays;
    if (says == null) return (did: false, says: 'nothing to redo');
    history.redo();
    return (did: true, says: 'redid $says — $selection');
  }

  /// What is wrong with the project, as an export would see it.
  String check() {
    final readiness = ExportReadiness.check(project);
    if (readiness.issues.isEmpty) return 'no issues';
    final errors = readiness.issues
        .where((ExportIssue i) => i.severity == ExportSeverity.error)
        .length;
    final headline =
        '${readiness.issues.length} '
        '${readiness.issues.length == 1 ? 'issue' : 'issues'}, $errors of '
        'them fatal';
    return <String>[
      headline,
      for (final ExportIssue issue in readiness.issues) '  $issue',
    ].join('\n');
  }

  /// Writes the project, to [to] or over the path it was opened from.
  ///
  /// [includeHistory] writes the undo stack in beside it (`doc-31d`) so the
  /// next `ModelSession.open` reopens with real undo already on the stack,
  /// not just the project as it last stood. Off by default: a project of a
  /// few objects, saved after the sort of session `agent_builds_a_table_
  /// test.dart` runs, grows roughly ninefold with every step's own object
  /// list written in beside it — a real cost worth asking for, not one an
  /// ordinary save should pay without being asked. The toggle to ask for
  /// it from outside this session is `ui-33d`'s own row, not built here.
  Answer save(String? to, {bool includeHistory = false}) {
    final target = to ?? path;
    if (target == null) {
      return (
        did: false,
        says: 'this session has no path of its own — give one',
      );
    }
    File(target).writeAsBytesSync(
      writeProject(project, history: includeHistory ? history : null),
    );
    path = target;
    return (did: true, says: 'written to $target');
  }

  /// Takes the project out to a format a game or another tool reads.
  ///
  /// **Any writer in `flutter3d_formats`' own [builtInModelWriters]**, named
  /// by [format] or by the suffix of [to] — the same list the engine's
  /// `encodeModel` and the modeller's export menu choose from, so an agent can
  /// write exactly what a person can. The first file lands at [to] and any
  /// others (an OBJ's `.mtl`) beside it, under the names the writer gave them.
  ///
  /// **A `.gltf` + `.bin` + loose images is not built.** `GltfWriter.writeGlb`
  /// (`fmt-06`) embeds vertex data and images in one binary chunk, which is
  /// what a GLB is; splitting that into a JSON `.gltf` beside a `.bin` and
  /// per-image files is a second entry point onto the same writer that nothing
  /// has asked for yet, so asking for one says so and names the GLB instead.
  Answer export(String to, {String? format, bool force = false}) {
    final String kind = format ?? _formatFromSuffix(to);
    final ModelWriter? writer = modelWriterNamed(kind);
    if (writer == null) {
      return (
        did: false,
        says: kind == 'gltf'
            ? '".gltf" (JSON plus a separate .bin) is not built; export ".glb" '
                  'instead — same writer, one self-contained file'
            : '"$kind" is not a format this can export; it is one of '
                  '${builtInModelWriters.map((ModelWriter w) => '"${w.name}"').join(', ')}',
      );
    }
    if (project.objects.isEmpty) {
      return (did: false, says: 'there is nothing in this project to export');
    }
    final readiness = ExportReadiness.check(project);
    final errors = <ExportIssue>[
      for (final ExportIssue issue in readiness.issues)
        if (issue.severity == ExportSeverity.error) issue,
    ];
    if (!force && errors.isNotEmpty) {
      return (
        did: false,
        says:
            '${errors.length} ${errors.length == 1 ? 'thing' : 'things'} in '
            'this project will not load where it is going: '
            '${errors.map((ExportIssue e) => e.message).join('; ')} — call '
            'export again with force to write it anyway',
      );
    }

    final String file = to.split(RegExp(r'[\\/]')).last;
    final String baseName = file.toLowerCase().endsWith(writer.suffix)
        ? file.substring(0, file.length - writer.suffix.length)
        : file;
    final String directory = to.contains('/')
        ? to.substring(0, to.lastIndexOf('/'))
        : '.';
    final ModelWrite written = writer.write(
      _document.of(project),
      baseName: baseName,
    );
    for (var i = 0; i < written.files.length; i++) {
      final WrittenFile each = written.files[i];
      File(
        i == 0 ? to : '$directory/${each.name}',
      ).writeAsBytesSync(each.bytes);
    }
    final warnings = <String>[
      for (final ExportIssue issue in readiness.issues)
        if (issue.severity == ExportSeverity.warning) issue.message,
    ];
    return (
      did: true,
      says: warnings.isEmpty
          ? 'written to $to'
          : 'written to $to, with ${warnings.length} '
                '${warnings.length == 1 ? 'warning' : 'warnings'}: '
                '${warnings.join('; ')}',
    );
  }

  /// Brings in a glTF, OBJ, `.f3d` or STL file as new objects in this
  /// project — merged in, not replacing it, through `doc-11a-n`'s own
  /// `importInto`: materials and images the file shares with this project
  /// (down to matching every field a `.f3dproj` manifest would write) come
  /// in once rather than doubling the tables, and the file's own hierarchy —
  /// parent and child alike — is preserved rather than flattened to the top
  /// level.
  ///
  /// **[options] and the three cleanup flags are the identical choice
  /// `apps/flutter3d_modeler`'s own import screen offers a person**
  /// (`import_plan.dart`'s `ImportUnit`/`ImportChoice`, `screen/files.dart`'s
  /// `_applyImportCleanup`) — an agent gets a unit and up axis to read a file
  /// with no convention of its own (an `.stl` in particular) correctly, and
  /// [weld]/[fixNormals]/[triangulate] to turn the objects this import just
  /// added into real `EditMesh` topology rather than leaving them raw
  /// `ImportedGeometry`, the same "сварить"/"нормали"/"триангулировать"
  /// checkboxes. All four default to today's own no-options behaviour: scale
  /// `1.0`, up axis `y`, every object left byte-for-byte as the file read
  /// (`tut-01`).
  Future<Answer> import(
    String from, {
    ImportOptions options = const ImportOptions(),
    bool weld = false,
    bool fixNormals = false,
    bool triangulate = false,
  }) async {
    final file = File(from);
    if (!file.existsSync()) {
      return (did: false, says: 'there is no file at $from');
    }
    final ModelDocument document;
    try {
      document = await decodeModel(
        ModelLoadRequest(
          source: _FileSource(file),
          // FBX is recognised and refused with its own reason rather than
          // sniffed into an empty OBJ — the plugin boundary, used.
          decoders: const <ModelDecoder>[FbxDecoder()],
        ),
      );
    } catch (error) {
      return (did: false, says: 'could not read $from: $error');
    }
    final beforeCount = project.objects.length;
    final report = importInto(project, document, options: options);
    if (report.counts.objects == 0) {
      return (did: false, says: '$from has nothing this reader could place');
    }
    var merged = report.project;
    if (weld || fixNormals || triangulate) {
      // Only the objects this import just added — `importInto`'s own doc
      // comment guarantees they land after everything already in the
      // project, so a cleanup choice made here cannot reach back and rebuild
      // an object that was already open and left untouched on purpose.
      final newIds = <int>{
        for (final ModelObject object in report.project.objects.skip(
          beforeCount,
        ))
          object.id,
      };
      merged = _cleanedUpImport(
        merged,
        newIds,
        weld: weld,
        fixNormals: fixNormals,
        triangulate: triangulate,
      );
    }
    // `ReplaceDocument` rather than a run of `AddPrimitive`-style commands,
    // because the import brought whole meshes across, not parameters a
    // command could describe from scratch. Run directly against `history`
    // rather than through this session's own `run` since there is no
    // sentence to build from a command's own `says` here worth adding to —
    // `ReplaceDocument.isJournaled` is false regardless of which door runs
    // it, since it carries a whole `ModelProject` a JSON Lines file has no
    // way to hold; an import does not appear in the recovery journal, only
    // in the undo stack.
    //
    // `mcp-14n`'s own lock, the same reason `model_tools.dart`'s generic
    // command tool waits for it: an import landing mid-drag would replace
    // the whole document out from under a transform the picture is still
    // mid-way through showing.
    await history.whenNotInTransaction;
    history.run(ReplaceDocument(merged, 'import $from'));
    return (
      did: true,
      says:
          'imported ${report.counts.objects} '
          '${report.counts.objects == 1 ? 'object' : 'objects'} from $from',
    );
  }

  /// [project], with every newly imported `ImportedGeometry` object among
  /// [onlyIds] turned into real `EditMesh` topology via `importMeshData` —
  /// the same conversion `apps/flutter3d_modeler`'s own
  /// `_applyImportCleanup` runs when its weld/normals/triangulate checkboxes
  /// are on. An object left out of [onlyIds], or that already holds
  /// `EditedGeometry`, is untouched.
  ModelProject _cleanedUpImport(
    ModelProject project,
    Set<int> onlyIds, {
    required bool weld,
    required bool fixNormals,
    required bool triangulate,
  }) {
    var result = project;
    for (final ModelObject object in project.objects) {
      if (!onlyIds.contains(object.id)) continue;
      if (object.geometry case ImportedGeometry(:final data)) {
        // `weld`'s own epsilon: `importMeshData`'s own default (a millionth
        // of the mesh's diagonal) when on, `0` (exact duplicates only) when
        // off — `import_plan.dart`'s own `weldEpsilonFor`, restated here
        // rather than reached for across the app/package boundary.
        final (EditMesh mesh, _, _) = importMeshData(
          data,
          weldEpsilon: weld ? null : 0.0,
        );
        if (fixNormals) mesh.makeConsistent();
        if (triangulate) {
          triangulateFaces(mesh, Selection.all(mesh, ElementLevel.face));
        }
        result = result.withObject(
          object.copyWith(geometry: EditedGeometry(mesh)),
        );
      }
    }
    return result;
  }

  /// Writes the commands run so far to [to], as `doc-16`'s `CommandJournal`
  /// format — a recovery log, not the project itself. Reads [history]'s own
  /// attached journal — the constructor always gives it one — rather than
  /// keeping a second copy here, so this names every step [history] recorded
  /// regardless of which caller ran it (`tut-15`).
  Answer journal(String to) {
    final CommandJournal j = history.recoveryJournal!;
    File(to).writeAsBytesSync(j.toBytes());
    return (did: true, says: 'wrote ${j.length} journal lines to $to');
  }

  // ------------------------------------------------------------- mcp-09n

  /// Welds every mesh's own duplicate vertices, drops faces with no area,
  /// and winds every closed shell outward — the whole project, one undo
  /// step regardless of how many objects it touched.
  ///
  /// **Twenty-eight commands are how a person cleans up one object at a
  /// time; this is what an agent that just imported a GLB full of them
  /// runs once.** Wrapped in [ModelHistory.transaction] — the mechanism
  /// `mcp-11n` is about, which existed in `flutter3d_model_core` before
  /// anything here called it — so a ⌘Z after this takes the whole batch
  /// back, not one weld at a time.
  Answer cleanup() {
    final ids = <int>[
      for (final ModelObject object in project.objects)
        if (object.geometry is EditedGeometry) object.id,
    ];
    if (ids.isEmpty) {
      return (did: false, says: 'nothing here has a mesh to clean up');
    }
    var didAnything = false;
    _recipe(() {
      for (final int id in ids) {
        history.selection = ProjectSelection(objects: <int>[id]);
        if (run(const MergeByDistance()).did) didAnything = true;

        if (project[id]?.geometry case EditedGeometry(:final mesh)) {
          final MeshIssue? degenerate = MeshChecks(mesh).degenerateFaces();
          if (degenerate != null) {
            history.selection = ProjectSelection(
              mode: SelectionMode.mesh,
              objects: <int>[id],
              level: ElementLevel.face,
              elements: degenerate.ids.toList(),
            );
            if (run(const DeleteElements()).did) didAnything = true;
            history.selection = ProjectSelection(objects: <int>[id]);
          }
        }

        // `makeConsistent` winds every *closed* island outward on its own,
        // never guessing at an open one — see its own doc comment — which
        // is exactly "вывернуть должной стороной" without this recipe
        // having to detect a shell's own winding itself.
        if (run(const RecalculateNormals()).did) didAnything = true;
      }
    });
    return (
      did: didAnything,
      says: didAnything
          ? 'cleaned up ${ids.length} ${ids.length == 1 ? 'mesh' : 'meshes'}'
          : 'nothing needed cleaning',
    );
  }

  /// Triangulates every mesh, recalculates its normals, and fits every
  /// image in the project to [profile]'s own texture budget — one of
  /// "desktop", "mobile" or "web" — all as one undo step.
  ///
  /// **[profile] picks a [TextureBudget], not the project's own
  /// [ProjectProfile]** — nothing in this plan lets an agent change a
  /// project's profile yet, and this recipe does not need to: an agent
  /// asking for mobile-sized textures on a project whose own profile is
  /// still "desktop" is asking to fit its images to that budget for this
  /// one call, which is exactly what `FitTexturesToProfile`'s own
  /// `budget` override is for. The project's [ModelProject.profile] comes
  /// back untouched.
  Answer makeGameReady(String profile) {
    final TextureBudget? budget = switch (profile) {
      'desktop' => TextureBudget.desktop,
      'mobile' => TextureBudget.mobile,
      'web' => TextureBudget.web,
      _ => null,
    };
    if (budget == null) {
      return (
        did: false,
        says:
            '"$profile" is not a profile this knows; it is desktop, '
            'mobile or web',
      );
    }
    final ids = <int>[
      for (final ModelObject object in project.objects)
        if (object.geometry is EditedGeometry) object.id,
    ];
    var didAnything = false;
    _recipe(() {
      for (final int id in ids) {
        // `Triangulate` refuses on an empty selection rather than
        // defaulting to "every face" the way `MergeByDistance` does, so
        // every live face is named first — `SelectAll` already does that
        // correctly in mesh mode (live faces, not dead slots), which is
        // worth reusing rather than re-deriving here.
        history.selection = ProjectSelection(
          mode: SelectionMode.mesh,
          objects: <int>[id],
          level: ElementLevel.face,
        );
        run(const SelectAll());
        if (run(const Triangulate()).did) didAnything = true;

        history.selection = ProjectSelection(objects: <int>[id]);
        if (run(const RecalculateNormals()).did) didAnything = true;
      }
      final ModelProject fitted = FitTexturesToProfile(project, budget: budget);
      if (!identical(fitted, project)) {
        run(ReplaceDocument(fitted, 'fit textures to $profile'));
        didAnything = true;
      }
    });
    return (
      did: didAnything,
      says: didAnything
          ? 'made game ready for $profile'
          : 'already game ready for $profile',
    );
  }

  /// A batch of primitives, each optionally naming an earlier entry in
  /// [spec] as its parent, built as one undo step.
  ///
  /// Each entry takes `addPrimitive`'s own arguments (`kind`, `size`,
  /// `segments`, `at`) plus an optional `name` and an optional `parent` —
  /// an index into [spec] itself, not an object id, since nothing in the
  /// batch has one until this runs.
  ///
  /// **Validated whole before anything is built.** A batch that fails
  /// partway through would leave some of a hierarchy built and some not,
  /// on a stack an agent's own `undo` — `mcp-10n`'s — would have to take
  /// back one piece at a time to get out of; checking every entry first
  /// means the transaction below never has a reason to fail midway.
  Answer buildFrom(List<Map<String, Object?>> spec) {
    if (spec.isEmpty) return (did: false, says: 'nothing to build');
    for (var i = 0; i < spec.length; i++) {
      final Object? kind = spec[i]['kind'];
      if (kind is! String || !AddPrimitive.primitiveKinds.contains(kind)) {
        return (
          did: false,
          says:
              'entry $i: "$kind" is not a shape this builds. It knows '
              '${AddPrimitive.primitiveKinds.join(', ')}',
        );
      }
      final Object? size = spec[i]['size'];
      if (size != null && (size is! num || size <= 0)) {
        return (did: false, says: 'entry $i needs a positive size');
      }
      final Object? parent = spec[i]['parent'];
      if (parent != null && (parent is! int || parent < 0 || parent >= i)) {
        return (
          did: false,
          says: 'entry $i names a parent this batch has not built yet',
        );
      }
    }

    final ids = <int>[];
    _recipe(() {
      for (var i = 0; i < spec.length; i++) {
        final entry = spec[i];
        final ModelCommand command = modelCommandFromJson(<String, Object?>{
          'name': 'addPrimitive',
          'kind': entry['kind'],
          if (entry['size'] != null) 'size': entry['size'],
          if (entry['segments'] != null) 'segments': entry['segments'],
          if (entry['at'] != null) 'at': entry['at'],
        })!;
        run(command);
        final int newId = history.selection.activeObject!;
        ids.add(newId);
        if (entry['name'] case final String label
            when label.trim().isNotEmpty) {
          run(Rename(id: newId, to: label));
        }
        if (entry['parent'] case final int parentIndex) {
          run(SetParent(id: newId, to: ids[parentIndex]));
        }
      }
    });
    // `ux-20` made `_recipe` put the selection back, which is right for
    // `cleanup` and `makeGameReady` — they walk every mesh and should not
    // leave the cursor on the last one they happened to reach. Building is
    // the other kind of recipe: everything that adds something selects what
    // it added, the instructions say so, and an agent that has just built a
    // hierarchy means to carry on with it.
    if (ids.isNotEmpty) {
      history.selection = ProjectSelection(objects: <int>[ids.last]);
    }
    return (
      did: true,
      says: 'built ${ids.length} ${ids.length == 1 ? 'object' : 'objects'}',
    );
  }

  /// Metrics and issues in one call, so checking on a project just built
  /// does not need [listing] and [check] both.
  ///
  /// **No picture.** The row this answers also asks for one; that needs
  /// `renderProject` (`mcp-05n`), itself waiting on the `DevicePresenter`
  /// split `mcp-01n` names — real, larger, unbuilt scope this recipe does
  /// not pretend to have by leaving the word out of its own name.
  String inspect() {
    var meshObjects = 0;
    var vertices = 0;
    var faces = 0;
    for (final ModelObject object in project.objects) {
      if (object.geometry case EditedGeometry(:final mesh)) {
        meshObjects++;
        vertices += mesh.vertexCount;
        faces += mesh.faceCount;
      }
    }
    return '${project.objects.length} '
        '${project.objects.length == 1 ? 'object' : 'objects'}'
        '${meshObjects == 0 ? '' : ', $meshObjects with topology: $vertices '
                  '${vertices == 1 ? 'vertex' : 'vertices'}, $faces '
                  '${faces == 1 ? 'face' : 'faces'}'}'
        '\n${check()}';
  }

  // --------------------------------------------------------------- anim-30
  //
  // MCP tools over `anim-21`'s `buildSkeleton`, `anim-15`'s `bakeIk`,
  // `anim-20`'s `bakeShapeDrivers`, `anim-13`'s `rigIssues` and `anim-17`'s
  // `retargetClip` — most of them not a `ModelCommand` (`command.dart`'s own
  // sealed hierarchy cannot be extended from outside `flutter3d_model_core`),
  // so each is a session recipe the same shape
  // `cleanup`/`makeGameReady`/`buildFrom` above already are: read the
  // project, call the real function, and hand the result to
  // `ReplaceDocument` for one undo step through `run`.
  //
  // **`anim-10`'s own `paintWeights` used to live here too, as
  // `paintSkinWeights`, and does not any more.** It closes as a real
  // `ModelCommand` now (`flutter3d_model_core`'s own `PaintWeights`,
  // `paint_weights.dart`) — the sealed hierarchy it once could not join —
  // so the `paintWeights` MCP tool runs it through the ordinary
  // `_command('paintWeights')` path (`model_tools.dart`) like every other
  // command tool, and there is nothing left for a session recipe to do.
  // `autoRig` is `doc-36d`'s own second such row: its own result is
  // `SetRig` now, not `ReplaceDocument`, though `autoRig` itself stays a
  // session recipe — `buildSkeleton` still is not a `ModelCommand`, only
  // the document edit its own result produces is one.

  /// Builds a [template]-shaped skeleton from [markers] (a world-space
  /// position per name `requiredMarkers(template)` asks for) and adds it —
  /// every new joint object, then the skeleton itself — to this project as
  /// one undo step, through `SetRig` (`flutter3d_model_core`'s own
  /// `set_rig.dart`, `doc-36d`) rather than `ReplaceDocument`, so an
  /// auto-rig now actually reaches the undo journal as itself. [skinObjectId],
  /// when given, is bound to the new skeleton in that same step: the
  /// "`SetSkeleton` + `SetWeights` transaction" `anim-23`'s own row
  /// describes, minus the weights half, which is the `paintWeights` tool's
  /// own job — `PaintWeights`, `flutter3d_model_core`'s own
  /// `paint_weights.dart`.
  ///
  /// [bounds] is 6 numbers, `[minX, minY, minZ, maxX, maxY, maxZ]`; left
  /// out, this computes a box around every marker [template] actually
  /// reads, padded by one unit each way — [buildSkeleton]'s own `bounds` is
  /// a sanity check, not a shape a caller normally has reason to hand-pick.
  ///
  /// [spineCount], [fingers], [toes], [faceBones], [ikChains] and
  /// [controllers] pass straight through to [RigBuildOptions] — screen 16's
  /// own rig-composition switches (`anim-33d`), given a backend here rather
  /// than in a new tool of their own, since composing a rig is still just
  /// [buildSkeleton] with different options.
  Answer autoRig({
    required String template,
    required Map<String, List<double>> markers,
    int? skinObjectId,
    String? skeletonName,
    String mirrorAxis = 'x',
    List<double>? bounds,
    int spineCount = 1,
    bool fingers = false,
    bool toes = false,
    bool faceBones = false,
    bool ikChains = false,
    bool controllers = false,
  }) {
    final RigTemplate? chosen = switch (template) {
      'humanoid' => RigTemplate.humanoid,
      'quadruped' => RigTemplate.quadruped,
      _ => null,
    };
    if (chosen == null) {
      return (
        did: false,
        says: '"$template" is not a rig template; it is humanoid or quadruped',
      );
    }
    final RigMirrorAxis axis = switch (mirrorAxis) {
      'y' => RigMirrorAxis.y,
      'z' => RigMirrorAxis.z,
      _ => RigMirrorAxis.x,
    };

    final required = requiredMarkers(chosen);
    final missing = <String>[
      for (final key in required)
        if (!markers.containsKey(key)) key,
    ];
    if (missing.isNotEmpty) {
      return (
        did: false,
        says:
            'autoRig(${chosen.name}) is missing markers: '
            '${missing.join(', ')}',
      );
    }
    final markerVectors = <String, Vector3>{
      for (final entry in markers.entries)
        entry.key: Vector3(entry.value[0], entry.value[1], entry.value[2]),
    };

    Aabb3 box;
    if (bounds != null) {
      if (bounds.length != 6) {
        return (
          did: false,
          says: 'bounds needs 6 numbers: minX minY minZ maxX maxY maxZ',
        );
      }
      box = Aabb3.minMax(
        Vector3(bounds[0], bounds[1], bounds[2]),
        Vector3(bounds[3], bounds[4], bounds[5]),
      );
    } else {
      var min = Vector3(double.infinity, double.infinity, double.infinity);
      var max = Vector3(
        double.negativeInfinity,
        double.negativeInfinity,
        double.negativeInfinity,
      );
      for (final key in required) {
        final v = markerVectors[key]!;
        min = Vector3(
          math.min(min.x, v.x),
          math.min(min.y, v.y),
          math.min(min.z, v.z),
        );
        max = Vector3(
          math.max(max.x, v.x),
          math.max(max.y, v.y),
          math.max(max.z, v.z),
        );
      }
      box = Aabb3.minMax(min - Vector3.all(1.0), max + Vector3.all(1.0));
    }

    if (skinObjectId != null && project[skinObjectId] == null) {
      return (did: false, says: 'there is no object $skinObjectId to skin');
    }

    final BuiltRig built;
    try {
      built = buildSkeleton(
        chosen,
        markerVectors,
        bounds: box,
        options: RigBuildOptions(
          mirrorAxis: axis,
          spineCount: spineCount,
          fingers: fingers,
          toes: toes,
          faceBones: faceBones,
          ikChains: ikChains,
          controllers: controllers,
        ),
        firstObjectId: project.nextId,
        skeletonName: skeletonName,
        // `tut-21`: markers are world-space picks, so the object actually
        // being skinned has to fold its own world transform back into the
        // inverse bind matrices — see `buildSkeleton`'s own `meshWorld` doc.
        meshWorld: skinObjectId == null
            ? null
            : worldTransformOf(project, skinObjectId),
      );
    } on ArgumentError catch (error) {
      return (did: false, says: 'autoRig refused: ${error.message}');
    }

    return run(
      SetRig(
        jointObjects: built.objects,
        skeleton: built.skeleton,
        skinObjectId: skinObjectId,
        label: 'auto-rig ${chosen.name} (${built.skeleton.jointCount} joints)',
      ),
    );
  }

  /// Retargets [sourceClipIndex] — a clip whose tracks address
  /// [sourceSkeletonIndex]'s own joints — onto [targetSkeletonIndex]'s
  /// joints, both in this same project, through [boneMap] (source name to
  /// target name) or, left out, the rig algorithms' own `autoMap` guess from
  /// the two skeletons' own joint names. Appends the retargeted clip to
  /// this project's own clip list as one undo step.
  Answer retargetClip({
    required int sourceClipIndex,
    required int sourceSkeletonIndex,
    required int targetSkeletonIndex,
    Map<String, String>? boneMap,
    bool lockFeet = true,
    double groundY = 0.0,
    double footTolerance = 1e-3,
    String? clipName,
  }) {
    if (sourceClipIndex < 0 || sourceClipIndex >= project.clips.length) {
      return (did: false, says: 'there is no clip $sourceClipIndex');
    }
    if (sourceSkeletonIndex < 0 ||
        sourceSkeletonIndex >= project.skeletons.length) {
      return (did: false, says: 'there is no skeleton $sourceSkeletonIndex');
    }
    if (targetSkeletonIndex < 0 ||
        targetSkeletonIndex >= project.skeletons.length) {
      return (did: false, says: 'there is no skeleton $targetSkeletonIndex');
    }
    final sourceSkeleton = project.skeletons[sourceSkeletonIndex];
    final targetSkeleton = project.skeletons[targetSkeletonIndex];
    final sourceNames = <String>[
      for (final id in sourceSkeleton.joints) project[id]?.name ?? '',
    ];
    final targetNames = <String>[
      for (final id in targetSkeleton.joints) project[id]?.name ?? '',
    ];
    final map = boneMap != null
        ? rig.BoneMap(boneMap)
        : rig.autoMap(sourceNames, targetNames);
    if (map.isEmpty) {
      return (
        did: false,
        says:
            'no bone of skeleton $sourceSkeletonIndex maps onto skeleton '
            '$targetSkeletonIndex — name them the same or give a "boneMap"',
      );
    }

    final retargeted = core.retargetClip(
      sourceClip: project.clips[sourceClipIndex],
      sourceProject: project,
      sourceSkeleton: sourceSkeleton,
      targetProject: project,
      targetSkeleton: targetSkeleton,
      boneMap: map,
      lockFeet: lockFeet,
      groundY: groundY,
      footTolerance: footTolerance,
    );
    final named = clipName == null
        ? retargeted
        : ProjectClip(
            name: clipName,
            tracks: retargeted.tracks,
            extras: retargeted.extras,
          );

    return run(
      ReplaceDocument(
        project.copyWith(clips: <ProjectClip>[...project.clips, named]),
        'retarget clip $sourceClipIndex onto skeleton $targetSkeletonIndex',
      ),
    );
  }

  /// Bakes `anim-15`'s `IkConstraint` — root/mid/effector joints reaching
  /// for [target], bending toward [pole] — into ordinary rotation
  /// keyframes on [clipIndex]'s own root and middle tracks, sampled every
  /// `1/[fps]` seconds, and replaces that clip with the baked result as one
  /// undo step.
  Answer bakeIkOnClip({
    required int clipIndex,
    required int rootJointId,
    required int midJointId,
    required int effectorJointId,
    required List<double> target,
    required List<double> pole,
    double fps = 30,
  }) {
    if (clipIndex < 0 || clipIndex >= project.clips.length) {
      return (did: false, says: 'there is no clip $clipIndex');
    }
    for (final id in <int>[rootJointId, midJointId, effectorJointId]) {
      if (project[id] == null) {
        return (did: false, says: 'there is no object $id');
      }
    }
    if (target.length != 3 || pole.length != 3) {
      return (did: false, says: '"target" and "pole" each need 3 numbers');
    }
    final constraint = IkConstraint(
      rootJointId: rootJointId,
      midJointId: midJointId,
      effectorJointId: effectorJointId,
      target: Vector3(target[0], target[1], target[2]),
      pole: Vector3(pole[0], pole[1], pole[2]),
    );
    final ProjectClip baked;
    try {
      baked = bakeIk(
        project: project,
        clip: project.clips[clipIndex],
        constraint: constraint,
        fps: fps,
      );
    } on ArgumentError catch (error) {
      return (did: false, says: 'bakeIk refused: ${error.message}');
    }
    final clips = List<ProjectClip>.of(project.clips)..[clipIndex] = baked;
    return run(
      ReplaceDocument(
        project.copyWith(clips: clips),
        'bake IK into clip $clipIndex',
      ),
    );
  }

  /// Bakes `anim-20`'s `ShapeDriver`s — each a shape key driven by how far
  /// one joint has turned — into one more weights track on [clipIndex],
  /// naming [shapeTargetObjectId]'s own shape keys, and replaces that clip
  /// with the baked result as one undo step.
  ///
  /// [drivers] is optional: when it is not given, this bakes
  /// [shapeTargetObjectId]'s own persisted `ModelObject.shapeDrivers` —
  /// `anim-34d`'s own row, whatever `addShapeDriver` has built up on that
  /// object — rather than asking a caller to look them up and pass them
  /// back in.
  Answer bakeDrivers({
    required int clipIndex,
    required int shapeTargetObjectId,
    List<Map<String, Object?>>? drivers,
  }) {
    if (clipIndex < 0 || clipIndex >= project.clips.length) {
      return (did: false, says: 'there is no clip $clipIndex');
    }
    final target = project[shapeTargetObjectId];
    if (target == null) {
      return (did: false, says: 'there is no object $shapeTargetObjectId');
    }
    final shapeCount = target.shapeSet.keys.length;
    if (shapeCount == 0) {
      return (
        did: false,
        says: 'object $shapeTargetObjectId has no shape keys to drive',
      );
    }

    final List<ShapeDriver> parsed;
    if (drivers == null) {
      parsed = target.shapeDrivers;
      if (parsed.isEmpty) {
        return (
          did: false,
          says:
              'bakeDrivers needs at least one driver, and object '
              '$shapeTargetObjectId has none of its own to fall back on',
        );
      }
    } else {
      if (drivers.isEmpty) {
        return (did: false, says: 'bakeDrivers needs at least one driver');
      }
      final out = <ShapeDriver>[];
      for (final driver in drivers) {
        final shapeIndex = driver['shapeIndex'];
        final jointId = driver['jointId'];
        final from = driver['from'];
        final to = driver['to'];
        if (shapeIndex is! int ||
            jointId is! int ||
            from is! num ||
            to is! num) {
          return (
            did: false,
            says:
                'each driver needs a "shapeIndex", a "jointId", a "from" '
                'and a "to"',
          );
        }
        final axis = switch (driver['axis']) {
          'y' => DriverAxis.y,
          'z' => DriverAxis.z,
          _ => DriverAxis.x,
        };
        out.add(
          ShapeDriver(
            shapeIndex: shapeIndex,
            jointId: jointId,
            axis: axis,
            from: from.toDouble(),
            to: to.toDouble(),
          ),
        );
      }
      parsed = out;
    }
    final baked = bakeShapeDrivers(
      clip: project.clips[clipIndex],
      drivers: parsed,
      shapeTargetObjectId: shapeTargetObjectId,
      shapeCount: shapeCount,
    );
    final clips = List<ProjectClip>.of(project.clips)..[clipIndex] = baked;
    return run(
      ReplaceDocument(
        project.copyWith(clips: clips),
        'bake ${parsed.length} shape '
        'driver${parsed.length == 1 ? '' : 's'} into clip $clipIndex',
      ),
    );
  }

  /// Everything `anim-13`'s `rigIssues` finds wrong with this project's
  /// skeletons and clips, against its own profile — `check`'s own shape,
  /// for the half of export readiness `check` itself does not cover.
  String validateRig() {
    final issues = rigIssues(project, project.profile);
    if (issues.isEmpty) return 'no rig issues';
    final errors = issues
        .where((ExportIssue i) => i.severity == ExportSeverity.error)
        .length;
    final headline =
        '${issues.length} ${issues.length == 1 ? 'issue' : 'issues'}, '
        '$errors of them fatal';
    return <String>[
      headline,
      for (final ExportIssue issue in issues) '  $issue',
    ].join('\n');
  }
}

String _formatFromSuffix(String path) {
  final dot = path.lastIndexOf('.');
  return dot < 0 ? '' : path.substring(dot + 1).toLowerCase();
}

/// Reads a model file from disk, for [ModelSession.import]. Not the
/// `FileAssetSource` `flutter3d` ships — that package depends on Flutter, and
/// this one may not — so this is the same idea, reimplemented on `dart:io`
/// alone.
final class _FileSource extends AssetSource {
  const _FileSource(this.file);

  final File file;

  @override
  String get key => file.path;

  @override
  Future<Uint8List> read() => file.readAsBytes();

  @override
  AssetUriResolver get resolveUri => (AssetRequest request) async {
    final relative = safeRelativeAssetPath(request.uri);
    final dir = file.path.contains('/')
        ? file.path.substring(0, file.path.lastIndexOf('/'))
        : '.';
    return File('$dir/$relative').readAsBytes();
  };
}
