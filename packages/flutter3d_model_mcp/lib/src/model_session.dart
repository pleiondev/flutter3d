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
      ProjectOpened(:final project) => ModelSession(
        ModelHistory(project),
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

  /// Runs one command through the history, and records it if it succeeded.
  Answer run(ModelCommand command) {
    final String? refused = history.run(command);
    if (refused != null) {
      return (did: false, says: 'nothing did ${command.says}: $refused');
    }
    _journal.record(command);
    return (did: true, says: '${command.says} — $selection');
  }

  Answer undo() {
    final says = history.undoSays;
    if (says == null) return (did: false, says: 'nothing to undo');
    history.undo();
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
  Answer save(String? to) {
    final target = to ?? path;
    if (target == null) {
      return (
        did: false,
        says: 'this session has no path of its own — give one',
      );
    }
    File(target).writeAsBytesSync(writeProject(project));
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

    final document = toModelDocument(project);
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
  /// project — merged in, not replacing it, the way `ImportInto` (`doc-11a-n`)
  /// will once it exists; today this is [fromModelDocument] on a project of
  /// one and its objects copied across.
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
    final imported = fromModelDocument(document);
    var next = project;
    final made = <int>[];
    for (final ModelObject object in imported.objects) {
      next = next.added(
        (int id) => ModelObject(
          id: id,
          name: object.name,
          geometry: object.geometry,
          transform: object.transform,
          materialSlots: object.materialSlots,
        ),
      );
      made.add(next.objects.last.id);
    }
    if (made.isEmpty) {
      return (did: false, says: '$from has nothing this reader could place');
    }
    // `ReplaceDocument` rather than a run of `AddPrimitive`-style commands,
    // because the import brought whole meshes across, not parameters a
    // command could describe from scratch. Run directly against `history`
    // rather than through this session's own `run` — `ReplaceDocument` is
    // deliberately not recorded to `_journal`, since it carries a whole
    // `ModelProject` a JSON Lines file has no way to hold; an import does not
    // appear in the recovery journal, only in the undo stack.
    history.run(ReplaceDocument(next, 'import $from'));
    return (
      did: true,
      says:
          'imported ${made.length} '
          '${made.length == 1 ? 'object' : 'objects'} from $from',
    );
  }

  /// Writes the commands run so far to [to], as `doc-16`'s `CommandJournal`
  /// format — a recovery log, not the project itself.
  Answer journal(String to) {
    File(to).writeAsBytesSync(_journal.toBytes());
    return (did: true, says: 'wrote ${_journal.length} journal lines to $to');
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
