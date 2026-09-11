import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';

/// What a tool call actually did, and the sentence to say about it.
///
/// **A refusal is an answer here, not an exception**, for the reason
/// `flutter3d_editor_mcp`'s own `Answer` gives: the protocol layer turns a
/// [did] of false into a tool result marked as an error, which is how an
/// agent is told to try something else rather than told nothing.
typedef Answer = ({bool did, String says});

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
  ModelSession(this.history, {this.path});

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

  /// Every command this session has run, for [journal] to write out.
  final CommandJournal _journal = CommandJournal();

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
  String listing() {
    final objects = contentsOf(project);
    final materials = materialsOf(project);
    return <String>[
      if (objects.isEmpty) 'the project is empty' else ...objects.map(_line),
      if (materials.isNotEmpty) ...<String>[
        'materials:',
        for (final Listed material in materials)
          '  ${material.id} ${material.name}',
      ],
      '',
      'selection: $selection',
    ].join('\n');
  }

  String _line(Listed row) => '${row.id} ${row.name} (${row.kind})';

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
  /// Object-level picking is a click, the way it is in the application — not
  /// a [ModelCommand], and so not something [CommandJournal] can replay. See
  /// that package's own doc comment for what that costs a recovery journal.
  Answer select({
    List<int>? objects,
    int? object,
    String? level,
    List<int>? elements,
  }) {
    if (object != null) {
      final ElementLevel? at = _levelNamed(level);
      if (at == null) {
        return (
          did: false,
          says: '"$level" is not a level; it is vertex, edge or face',
        );
      }
      history.selection = ProjectSelection(
        mode: SelectionMode.mesh,
        objects: <int>[object],
        level: at,
        elements: elements ?? const <int>[],
      );
      return (did: true, says: selection);
    }
    history.selection = ProjectSelection(
      mode: SelectionMode.object,
      objects: objects ?? const <int>[],
    );
    return (did: true, says: selection);
  }

  /// Runs [command] through the history, and records it if it succeeded —
  /// always as `StepAuthor.agent`: every command an MCP tool call reaches
  /// this method with is one by definition, `mcp-10n`'s own row.
  Answer run(ModelCommand command) {
    final String? refused = history.run(command, author: StepAuthor.agent);
    if (refused != null) {
      return (did: false, says: 'nothing did ${command.says}: $refused');
    }
    _journal.record(command);
    return (did: true, says: '${command.says} — $selection');
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
  /// **`.f3d`, `.obj` and GLB today; a `.gltf` + `.bin` + loose images is not
  /// built.** `GltfWriter.writeGlb` (`fmt-06`) embeds vertex data and images in
  /// one binary chunk, which is what a GLB is; splitting that into a JSON
  /// `.gltf` beside a `.bin` and per-image files is a second entry point onto
  /// the same writer that nothing has asked for yet. Skins, animations and
  /// morph targets do not travel through GLB either — `fmt-07`'s part of
  /// `GltfWriter`, not written — so a rigged project exports its geometry and
  /// materials only, with no warning of its own beyond what `ExportReadiness`
  /// already checks.
  Answer export(String to, {String? format, bool force = false}) {
    final String kind = format ?? _formatFromSuffix(to);
    if (kind != 'f3d' && kind != 'obj' && kind != 'glb') {
      return (
        did: false,
        says: kind == 'gltf'
            ? '".gltf" (JSON plus a separate .bin) is not built; export ".glb" '
                  'instead — same writer, one self-contained file'
            : '"$kind" is not a format this can export; it is "f3d", "obj" or '
                  '"glb"',
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

    final document = _document.of(project);
    if (kind == 'f3d') {
      File(to).writeAsBytesSync(F3dWriter(document).write());
    } else if (kind == 'glb') {
      File(to).writeAsBytesSync(GltfWriter(document).writeGlb());
    } else {
      final name = to
          .split(RegExp(r'[\\/]'))
          .last
          .replaceAll(RegExp(r'\.obj$'), '');
      final writer = ObjWriter(document, name: name);
      File(to).writeAsBytesSync(writer.write());
      if (writer.writeMaterialLibrary() case final Uint8List mtl) {
        final dir = to.contains('/')
            ? to.substring(0, to.lastIndexOf('/'))
            : '.';
        File('$dir/${writer.materialLibraryName}').writeAsBytesSync(mtl);
      }
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
  Future<Answer> import(String from) async {
    final file = File(from);
    if (!file.existsSync()) {
      return (did: false, says: 'there is no file at $from');
    }
    final ModelDocument document;
    try {
      document = await decodeModel(ModelLoadRequest(source: _FileSource(file)));
    } catch (error) {
      return (did: false, says: 'could not read $from: $error');
    }
    final report = importInto(project, document);
    if (report.counts.objects == 0) {
      return (did: false, says: '$from has nothing this reader could place');
    }
    // `ReplaceDocument` rather than a run of `AddPrimitive`-style commands,
    // because the import brought whole meshes across, not parameters a
    // command could describe from scratch. Run directly against `history`
    // rather than through this session's own `run` — `ReplaceDocument` is
    // deliberately not recorded to `_journal`, since it carries a whole
    // `ModelProject` a JSON Lines file has no way to hold; an import does not
    // appear in the recovery journal, only in the undo stack.
    history.run(ReplaceDocument(report.project, 'import $from'));
    return (
      did: true,
      says:
          'imported ${report.counts.objects} '
          '${report.counts.objects == 1 ? 'object' : 'objects'} from $from',
    );
  }

  /// Writes the commands run so far to [to], as `doc-16`'s `CommandJournal`
  /// format — a recovery log, not the project itself.
  Answer journal(String to) {
    File(to).writeAsBytesSync(_journal.toBytes());
    return (did: true, says: 'wrote ${_journal.length} journal lines to $to');
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
    history.transaction(() {
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
        says: '"$profile" is not a profile this knows; it is desktop, '
            'mobile or web',
      );
    }
    final ids = <int>[
      for (final ModelObject object in project.objects)
        if (object.geometry is EditedGeometry) object.id,
    ];
    var didAnything = false;
    history.transaction(() {
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
      final ModelProject fitted = FitTexturesToProfile(
        project,
        budget: budget,
      );
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
    history.transaction(() {
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
}

ElementLevel? _levelNamed(String? word) {
  for (final ElementLevel level in ElementLevel.values) {
    if (level.name == word) return level;
  }
  return null;
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
