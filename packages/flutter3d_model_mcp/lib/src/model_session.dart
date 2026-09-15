import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_fbx/flutter3d_fbx.dart';
import 'package:flutter3d_formats/flutter3d_formats.dart';
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
  /// always as `StepAuthor.agent`, both to [history] and to [_journal]: every
  /// command an MCP tool call reaches this method with is one by definition,
  /// `mcp-10n`'s own row, and `mcp-12n`'s own recovered journal has to agree
  /// with the live session about whose step each one was, not fall back to
  /// `record`'s own `person` default because nobody here named one.
  Answer run(ModelCommand command) {
    final String? refused = history.run(command, author: StepAuthor.agent);
    if (refused != null) {
      return (did: false, says: 'nothing did ${command.says}: $refused');
    }
    _journal.record(command, author: StepAuthor.agent);
    return (did: true, says: '${command.says} — $selection');
  }

  /// Runs [body] as one [history] step, its own journal lines bracketed the
  /// same way — a recipe (`mcp-09n`) calling [run] several times inside
  /// [body] is one undo step in the live session and, thanks to this, one
  /// step again when `mcp-12n`'s own [CommandJournal.replay] rebuilds a
  /// crashed session's journal from disk: [history]'s own transaction
  /// grouping and [_journal]'s are two different objects that would
  /// otherwise have to be kept in step by every caller separately, and a
  /// caller that wrapped only [history] — every recipe here did, once —
  /// left [_journal] recording the same body as several ungrouped lines,
  /// correct for the live session and wrong for anything recovered from
  /// disk.
  T _recipe<T>(T Function() body) =>
      history.transaction(() => _journal.transaction(body));

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
  Future<Answer> import(String from) async {
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
    //
    // `mcp-14n`'s own lock, the same reason `model_tools.dart`'s generic
    // command tool waits for it: an import landing mid-drag would replace
    // the whole document out from under a transform the picture is still
    // mid-way through showing.
    await history.whenNotInTransaction;
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
  // MCP tools over `anim-21`'s `buildSkeleton`, `anim-10`'s `paintWeights`,
  // `anim-15`'s `bakeIk`, `anim-20`'s `bakeShapeDrivers`, `anim-13`'s
  // `rigIssues` and `anim-17`'s `retargetClip` — none of them a
  // `ModelCommand` (`command.dart`'s own sealed hierarchy cannot be
  // extended from outside `flutter3d_model_core`), so each is a session
  // recipe the same shape `cleanup`/`makeGameReady`/`buildFrom` above
  // already are: read the project, call the real function, and hand the
  // result to `ReplaceDocument` for one undo step through `run` —
  // `paintSkinWeights` alone does not, for the reason its own doc comment
  // gives.

  /// Builds a [template]-shaped skeleton from [markers] (a world-space
  /// position per name `requiredMarkers(template)` asks for) and adds it —
  /// every new joint object, then the skeleton itself — to this project as
  /// one undo step. [skinObjectId], when given, is bound to the new
  /// skeleton in that same step: the "`SetSkeleton` + `SetWeights`
  /// transaction" `anim-23`'s own row describes, minus the weights half,
  /// which is [paintSkinWeights]'s own job.
  ///
  /// [bounds] is 6 numbers, `[minX, minY, minZ, maxX, maxY, maxZ]`; left
  /// out, this computes a box around every marker [template] actually
  /// reads, padded by one unit each way — [buildSkeleton]'s own `bounds` is
  /// a sanity check, not a shape a caller normally has reason to hand-pick.
  Answer autoRig({
    required String template,
    required Map<String, List<double>> markers,
    int? skinObjectId,
    String? skeletonName,
    String mirrorAxis = 'x',
    List<double>? bounds,
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
        options: RigBuildOptions(mirrorAxis: axis),
        firstObjectId: project.nextId,
        skeletonName: skeletonName,
      );
    } on ArgumentError catch (error) {
      return (did: false, says: 'autoRig refused: ${error.message}');
    }

    var next = project;
    for (final object in built.objects) {
      next = next.added(
        (int id) => ModelObject(
          id: id,
          name: object.name,
          geometry: object.geometry,
          transform: object.transform,
          parent: object.parent,
        ),
      );
    }
    final skeletonIndex = next.skeletons.length;
    next = next.copyWith(
      skeletons: <ProjectSkeleton>[...next.skeletons, built.skeleton],
    );
    if (skinObjectId != null) {
      next = next.withObject(
        next[skinObjectId]!.copyWith(skeletonIndex: skeletonIndex),
      );
    }

    return run(
      ReplaceDocument(
        next,
        'auto-rig ${chosen.name} (${built.skeleton.jointCount} joints)',
      ),
    );
  }

  /// Paints `anim-10`'s own brush (`paintWeights`, `paint_weights.dart`)
  /// over one or more samples on [objectId]'s own mesh, at [joint] — a
  /// joint of skeleton [skeletonIndex].
  ///
  /// **Not an undo step.** `paint_weights.dart`'s own doc comment calls
  /// itself "not a `ModelCommand`" on purpose — `command.dart`'s own sealed
  /// hierarchy cannot be extended from `flutter3d_model_mcp` — so this
  /// mutates the live `EditMesh` already inside this session's own project
  /// directly, the same limit `select`'s own doc comment already accepts
  /// for the same reason. The paint itself is real, and is what an export
  /// afterward reads; only the ability to undo it specifically is missing.
  Answer paintSkinWeights({
    required int objectId,
    required int skeletonIndex,
    required int joint,
    required List<Map<String, Object?>> samples,
    required double strength,
    String mode = 'paint',
    Map<String, Object?>? mirror,
    bool normalize = false,
  }) {
    final object = project[objectId];
    if (object == null) {
      return (did: false, says: 'there is no object $objectId');
    }
    if (object.geometry is! EditedGeometry) {
      return (
        did: false,
        says:
            'object $objectId has no mesh to paint weights on — bakeToMesh '
            'it first',
      );
    }
    if (skeletonIndex < 0 || skeletonIndex >= project.skeletons.length) {
      return (did: false, says: 'there is no skeleton $skeletonIndex');
    }
    final skeleton = project.skeletons[skeletonIndex];
    if (!skeleton.joints.contains(joint)) {
      return (
        did: false,
        says: 'object $joint is not a joint of skeleton $skeletonIndex',
      );
    }
    if (samples.isEmpty) {
      return (did: false, says: 'paintWeights needs at least one sample');
    }

    final brushSamples = <BrushSample>[];
    for (final sample in samples) {
      final center = sample['center'];
      final radius = sample['radius'];
      if (center is! List || center.length != 3 || radius is! num) {
        return (
          did: false,
          says: 'each sample needs a 3-number "center" and a "radius"',
        );
      }
      brushSamples.add(
        BrushSample(
          center: Vector3(
            (center[0] as num).toDouble(),
            (center[1] as num).toDouble(),
            (center[2] as num).toDouble(),
          ),
          radius: radius.toDouble(),
        ),
      );
    }

    PaintMirror? paintMirror;
    if (mirror != null) {
      final axis = mirror['axis'];
      final jointMirrorJson = mirror['jointMirror'];
      if (axis is! int || jointMirrorJson is! Map) {
        return (
          did: false,
          says: 'mirror needs an integer "axis" and a "jointMirror" map',
        );
      }
      paintMirror = PaintMirror(
        axis: axis,
        jointMirror: <int, int>{
          for (final entry in jointMirrorJson.entries)
            int.parse(entry.key as String): entry.value as int,
        },
        plane: (mirror['plane'] as num?)?.toDouble() ?? 0.0,
        tolerance: (mirror['tolerance'] as num?)?.toDouble() ?? 1e-4,
      );
    }

    final mesh = (object.geometry as EditedGeometry).mesh;
    paintWeights(
      project: project,
      mesh: mesh,
      skeleton: skeleton,
      joint: joint,
      samples: brushSamples,
      strength: strength,
      mode: mode == 'assign' ? PaintWeightsMode.assign : PaintWeightsMode.paint,
      mirror: paintMirror,
      normalize: normalize,
    );
    return (
      did: true,
      says:
          'painted weights for joint $joint on object $objectId over '
          '${brushSamples.length} '
          'sample${brushSamples.length == 1 ? '' : 's'} — not recorded as '
          'an undo step',
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
  Answer bakeDrivers({
    required int clipIndex,
    required int shapeTargetObjectId,
    required List<Map<String, Object?>> drivers,
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
    if (drivers.isEmpty) {
      return (did: false, says: 'bakeDrivers needs at least one driver');
    }
    final parsed = <ShapeDriver>[];
    for (final driver in drivers) {
      final shapeIndex = driver['shapeIndex'];
      final jointId = driver['jointId'];
      final from = driver['from'];
      final to = driver['to'];
      if (shapeIndex is! int || jointId is! int || from is! num || to is! num) {
        return (
          did: false,
          says:
              'each driver needs a "shapeIndex", a "jointId", a "from" and '
              'a "to"',
        );
      }
      final axis = switch (driver['axis']) {
        'y' => DriverAxis.y,
        'z' => DriverAxis.z,
        _ => DriverAxis.x,
      };
      parsed.add(
        ShapeDriver(
          shapeIndex: shapeIndex,
          jointId: jointId,
          axis: axis,
          from: from.toDouble(),
          to: to.toDouble(),
        ),
      );
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
