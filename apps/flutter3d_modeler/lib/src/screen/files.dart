/// `_ModelerScreenState`'s own file, device-open and export half — `ui-14`
/// through `ui-17`.
///
/// A `part of 'main.dart'` for the same reason `device.dart` beside it is:
/// every method here reaches `context`, `mounted`, `_device` or `_cubit`
/// directly, most of them behind an `await` a dialog or a picker returns.
///
/// `setState` is `@protected` on `State`, and the analyzer's check for that
/// annotation does not recognise an extension method on `_ModelerScreenState`
/// as code written inside the class — even though this file is, syntactically,
/// exactly that. The call itself is correct; only the check misfires.
// ignore_for_file: invalid_use_of_protected_member
part of '../../main.dart';

extension _FileHandling on _ModelerScreenState {
  /// Puts a freshly opened project on screen, and resets what belonged to
  /// the project that was open before it.
  ///
  /// **The five sites that used to each hand-roll "frame → forget → opened →
  /// setState" — `_openBytes`, `_openFileAndRemember`, `_openRecent`,
  /// `_newProjectWith` and `_offerRecovery` — now this one.** The scene the
  /// old materials belonged to is going, so an ordinary open forgets them
  /// too; [forgetSurfaces] is what lets `_offerRecovery` opt out, since there
  /// is no old scene there to have painted anything. Every path ends the same
  /// way regardless: `setState` forgetting the element-picker cache, because
  /// ids start again in the new project and a picker held against the old
  /// one could match a version and answer about a mesh that is gone.
  void _installOpened(
    ModelHistory history,
    ModelerStage stage, {
    required String documentName,
    String? said,
    required bool forgetSurfaces,
  }) {
    stage.frameSubject();
    if (forgetSurfaces) _surfaces.forget();
    _cubit.opened(
      history,
      renderer: (_state as ModelerReady).renderer,
      stage: stage,
      documentName: documentName,
      said: said,
    );
    setState(() {
      _elementPickerCache.forget();
    });
  }

  Future<void> _open() async {
    // What it costs to get to the first frame, which on the web is a different
    // number from what a frame costs afterwards — and the one a person waiting
    // at a white page is actually measuring.
    final opening = Stopwatch()..start();
    // The document a new session starts with: one cube, so the first thing on
    // screen is a thing rather than an empty grid.
    final opening3 = ModelHistory(_ModelerScreenState._newProject());
    try {
      // The size a web build's canvas is created at: `kFixedResolution` is
      // true there, so this is the resolution the browser scales from —
      // the screen's own logical size, so a canvas fits it from the first
      // frame rather than starting at a guess and reopening immediately
      // (`ui-20`). Impeller ignores it and sizes itself per frame.
      final view = ui.PlatformDispatcher.instance.views.firstOrNull;
      final devicePixelRatio = view?.devicePixelRatio ?? 1.0;
      final width = view == null
          ? 1600
          : (view.physicalSize.width / devicePixelRatio)
                .round()
                .clamp(1, 8192)
                .toInt();
      final height = view == null
          ? 1000
          : (view.physicalSize.height / devicePixelRatio)
                .round()
                .clamp(1, 8192)
                .toInt();
      final device = await openDevice(width: width, height: height);
      if (!mounted) return;
      _device = device;
      _deviceWidth = width;
      _deviceHeight = height;
      _deviceDevicePixelRatio = devicePixelRatio;
      final renderer = Renderer.create(device: device);

      final asset = kModel.isEmpty ? null : await _load(kModel, device);
      if (!mounted) return;

      // The measurement stands keep the old door: `p0-01` is about triangles on
      // a screen and putting a project behind a million-triangle lattice would
      // be measuring the document instead. Everything else comes through the
      // project, which is the one a person edits.
      final stage = kStress > 0 || asset != null
          ? ModelerStage.build(
              device: device,
              asset: asset,
              stressTriangles: kStress,
              stressObjects: kStressObjects,
            )
          : ModelerStage.fromProject(device: device, project: opening3.project);
      // Framed once, after the meshes are in: an object of any size arrives on
      // screen at a usable distance rather than as a dot or as the inside of
      // itself.
      stage.frameSubject();
      if (kChurn) {
        final subject = stage.subject;
        final node = subject is MeshNode
            ? subject
            : subject.children.whereType<MeshNode>().firstOrNull;
        final source = node?.mesh.source;
        if (node != null && source != null) {
          _measurementRuns.churn = ChurnRun(
            device: device,
            node: node,
            from: source,
          );
        }
      }
      opening.stop();
      _measurementRuns.openedInMs = opening.elapsedMilliseconds;
      if (kOrbit > 0) {
        _measurementRuns.orbit = OrbitRun(frames: kOrbit, stage: stage);
      }
      if (kSandboxProbe) {
        final said = describeProbe(await probeSandbox());
        debugPrint(said);
        if (mounted) _cubit.say(said);
        // The other half of the question needs the panel, and the panel needs
        // somebody to answer it: this opens it, and what comes back — the write
        // and whether a rename beside it would have worked — is printed the
        // same way. See `saveAs`.
        if (kSandboxPick) await _saveFile();
      }
      _cubit.opened(
        opening3,
        renderer: renderer,
        stage: stage,
        documentName: kModel.isEmpty ? 'cube' : kModel,
      );
      if (kMcpPort >= 0) {
        unawaited(startMcpServer(history: opening3, port: kMcpPort));
      }
      setState(() {
        // With no run to wait for, the opening cost is the whole report.
        if (kOrbit <= 0) {
          _report = 'opened in ${_measurementRuns.openedInMs} ms';
        }
      });
      // Opened from a link: the models service loads this build in a frame
      // with the file's address in the query, so the document becomes that
      // model rather than staying a cube.
      final linked = Uri.base.queryParameters['model'];
      if (linked != null && linked.isNotEmpty) {
        unawaited(
          _openLinked(
            Uri.base.resolve(linked),
            Uri.base.queryParameters['name'] ?? 'model',
            device,
          ),
        );
      } else if (kModel.isEmpty && kOrbit <= 0 && !kSandboxProbe) {
        // `ui-18`'s own "предложение восстановить" — checked once, on an
        // ordinary interactive launch only. A `--dart-define` measurement
        // run (`kModel`, `kOrbit`, `kSandboxProbe`) has nobody to answer a
        // dialog, and a link-open is about to replace the document anyway.
        unawaited(_offerRecovery(device));
      }
    } catch (error) {
      if (!mounted) return;
      _cubit.failed('$error');
    }
  }

  /// Opens a model the person chose, and puts it in the document.
  ///
  /// The whole of `p0-08` on the web and the ordinary path everywhere else:
  /// bytes from a picker, `decodeModel` over them, upload, frame. Nothing here
  /// branches on the platform — `ProjectFiles` already did.
  ///
  /// **The document is what is opened, and the picture follows from it.** This
  /// used to instantiate the decoded model straight into a scene and then start
  /// a fresh project holding a cube, which put the model on the screen and left
  /// every other half of the application describing something else: the
  /// outliner listed one cube, a click selected nothing that was drawn, undo had
  /// no edits to take back and `ExportReadiness` measured a shape nobody could
  /// see. `fromModelDocument` turns the file into objects, and `SceneSync`
  /// draws those — so what is picked, moved, undone and exported is the model
  /// that was opened.
  ///
  /// **The materials do not survive an import yet, and that is a known cost.**
  /// `mat-01` gives a project its material table, so a model imported from a
  /// glTF arrives painted; a project saved by this application carries its own
  /// and opens exactly as it was left.
  Future<void> _openFile() async {
    final device = _device;
    if (device == null) return;
    _cubit.say('choosing…');
    try {
      final picked = await openModel();
      if (picked == null) {
        if (mounted) _cubit.say('nothing chosen');
        return;
      }
      await _openBytes(picked.name, picked.bytes, device);
    } catch (error) {
      if (mounted) _cubit.say('could not open it: $error');
    }
  }

  /// Opens the model at [url], which the page this build was loaded into
  /// named.
  ///
  /// **Only an address on the origin this build was served from.** The query
  /// is something anybody can write into a link, and a frame that fetched
  /// whatever it was told would be a frame that sends this origin's cookies'
  /// worth of trust to another site's file.
  Future<void> _openLinked(Uri url, String name, GraphicsDevice device) async {
    if (url.origin != Uri.base.origin) {
      _cubit.say('not opening $name: it is not on ${Uri.base.origin}');
      return;
    }
    _cubit.say('fetching $name…');
    try {
      final fetched = await fetchModel(url, name: name);
      await _openBytes(fetched.name, fetched.bytes, device);
    } catch (error) {
      if (mounted) _cubit.say('could not open $name: $error');
    }
  }

  /// `ui-16`'s own import screen, threaded between a decoded [ModelDocument]
  /// and the [ImportOptions] `fromModelDocument` reads — a saved project
  /// skips straight past this, since it is not a model to be asked about.
  ///
  /// **Refused before decoding is a refusal, not a screen.** `ui-16`'s own
  /// worked example: a file over the web size limit never reaches
  /// [decodeBytes] at all, the same "cost nothing rather than something
  /// wrong" this file already keeps for a file that will not read.
  ///
  /// **Cancelling the screen is not an error.** [OpenRefused] is reused for
  /// it anyway, the same neutral tone `_openFile`'s own "nothing chosen"
  /// already reads in — the document on screen is untouched either way.
  Future<FileOpened> _openBytesWithImportScreen(
    String name,
    Uint8List bytes,
    GraphicsDevice device,
  ) async {
    if (isProjectFile(bytes)) {
      return openBytes(bytes, name: name, device: device);
    }

    final limitRefusal = refuseBeforeDecoding(
      fileSizeBytes: bytes.length,
      onWeb: kIsWeb,
    );
    if (limitRefusal != null) return OpenRefused(limitRefusal);

    final ModelDocument document;
    try {
      document = await decodeBytes(bytes, name);
    } catch (error) {
      return OpenRefused('$name could not be read: $error');
    }
    final empty = emptyDecodeRefusal(document, name);
    if (empty != null) return OpenRefused(empty);

    if (!mounted) return OpenRefused('import cancelled');
    final choice = await showImportScreen(
      context,
      document: document,
      profile: _history.project.profile,
    );
    if (choice == null) return OpenRefused('import cancelled');

    return openDocument(
      document,
      device: device,
      options: ImportOptions(scale: choice.unit.scale, upAxis: choice.upAxis),
    ).then(
      (OpenedModel opened) => OpenedModel(
        _applyImportCleanup(opened.project, choice),
        opened.stage,
      ),
    );
  }

  /// [project], with every `ImportedGeometry` object turned into real
  /// `EditMesh` topology via `importMeshData` when [choice] asks for any of
  /// weld/normals/triangulate — `BakeToMesh`'s own doc comment names this as
  /// where that conversion belongs. An object left untouched stays
  /// `ImportedGeometry`, byte for byte, which is this project's own default.
  ModelProject _applyImportCleanup(ModelProject project, ImportChoice choice) {
    if (!choice.weld && !choice.fixNormals && !choice.triangulate) {
      return project;
    }
    var result = project;
    for (final object in project.objects) {
      if (object.geometry case ImportedGeometry(:final data)) {
        final (mesh, _, _) = importMeshData(
          data,
          weldEpsilon: weldEpsilonFor(weld: choice.weld),
        );
        if (choice.fixNormals) mesh.makeConsistent();
        if (choice.triangulate) {
          triangulateFaces(mesh, Selection.all(mesh, ElementLevel.face));
        }
        result = result.withObject(
          object.copyWith(geometry: EditedGeometry(mesh)),
        );
      }
    }
    return result;
  }

  /// Puts the model in [bytes] in the document, whether it came from a picker
  /// or from a link.
  Future<void> _openBytes(
    String name,
    Uint8List bytes,
    GraphicsDevice device,
  ) async {
    try {
      final opening = Stopwatch()..start();
      final opened = await _openBytesWithImportScreen(name, bytes, device);
      opening.stop();
      if (!mounted) return;

      switch (opened) {
        // A file that will not read is a sentence on the status line and
        // nothing else: the document on screen is still the one the person was
        // working on, and throwing it away because they picked the wrong file
        // out of a folder would be the worst possible answer.
        case OpenRefused(:final String because):
          _cubit.say(because);
        case OpenedModel(
          :final ModelProject project,
          :final ModelerStage stage,
        ):
          final said = describeOpened(
            name: name,
            objectCount: project.objects.length,
            triangleCount: project.triangleCount,
            materialCount: project.materials.length,
            openedInMs: opening.elapsedMilliseconds,
          );
          _installOpened(
            ModelHistory(project),
            stage,
            documentName: name,
            said: <String>[said, ...opened.warnings].join('\n'),
            forgetSurfaces: true,
          );
      }
    } catch (error) {
      if (mounted) _cubit.say('could not open it: $error');
    }
  }

  /// Writes the document as the modeller's own file.
  ///
  /// **The project, not the picture.** This used to pull one `MeshData` off the
  /// scene's subject node and write it through `F3dWriter`, which meant a save
  /// that silently kept one mesh of however many the document held, threw away
  /// every name, transform and parent, and produced a file this application
  /// could not open back into the project it came from. `writeProject` writes
  /// the objects, their hierarchy, their material slots and the tables those
  /// index.
  ///
  /// `.f3d` is still a thing this can produce, and it is an *export* rather
  /// than a save — `ui-17`, and the difference is that an export is allowed to
  /// lose what the target format cannot hold, while a save is not.
  ///
  /// The spike part is what follows the write: `p0-13n` asks whether the same
  /// directory would have taken a temporary file and a rename, and the answer
  /// goes on the screen beside the result.
  /// `ui-33d`'s own "Save without history" checkbox is asked first, through
  /// [showSaveAsScreen] — a cancelled dialog is the same "nothing saved" a
  /// cancelled native panel already is, so it is reported the same way rather
  /// than treated as a silent no-op.
  /// Answers whether bytes actually landed on disk — `ui-24`'s own
  /// "неудачная запись не закрывает" needs to know, not just report.
  Future<bool> _saveFile() async {
    if (_state is! ModelerReady) return false;

    final choice = await showSaveAsScreen(context);
    if (choice == null) {
      if (mounted) _cubit.say('nothing saved', important: true);
      return false;
    }
    if (!mounted) return false;

    final Uint8List bytes;
    try {
      bytes = writeProject(
        _history.project,
        // `doc-31d`'s own `history` parameter: null is what leaves the
        // section out of the file entirely, the same way `ModelSession.save`
        // already does it in `flutter3d_model_mcp`.
        history: choice.includeHistory ? _history : null,
      );
    } on ArgumentError catch (error) {
      // What the format has no section for yet — a mesh carrying morph
      // targets. The message names the object, and it belongs in front of the
      // person rather than in a stack trace.
      _cubit.say('not saved: ${error.message}', important: true);
      return false;
    }
    final result = await saveAs(bytes, suggestedName: 'model.f3dproj');
    var said = switch (result.outcome) {
      SaveOutcome.written => 'wrote ${bytes.length} bytes to ${result.path}',
      SaveOutcome.cancelled => 'nothing saved',
      SaveOutcome.refused => result.said ?? 'refused',
    };
    final path = result.path;
    if (result.outcome == SaveOutcome.written && path != null) {
      final why = await whyAtomicWriteFails(path);
      said += why == null
          ? '\na temporary file and a rename would also have worked'
          : '\na temporary file and a rename would not: $why';
    }
    final written = result.outcome == SaveOutcome.written;
    // A cancelled picker or a refusal has not put the document in the state
    // a person who chose "save and close" asked to leave it in — only an
    // actual write clears dirty, the same way `ModelHistory.markSaved`'s
    // own doc comment already puts it.
    if (written) _history.markSaved();
    // Written or not, this is the direct outcome of a save a person just
    // asked for — worth reading, not something a stray selection click after
    // it should erase before they get the chance.
    if (mounted) _cubit.say(said, important: true);
    return written;
  }

  /// Takes the document out to a format somebody else reads.
  ///
  /// **An export may lose what the target cannot hold, and says what.** That is
  /// the whole difference from `_saveFile`: a `.f3dproj` keeps the parameters a
  /// cylinder knows itself by and the hierarchy, and an OBJ keeps triangles and
  /// a colour. So the person is told rather than protected — the errors stop
  /// the write until they answer, and the warnings ride along with it.
  Future<void> _exportFile(
    ExportFormat format, {
    bool bakeTransforms = false,
    TextureEncoding textureEncoding = TextureEncoding.png,
    // The export screen's own "Export anyway" label already showed every
    // issue this would otherwise ask about a second time — `ui-17`'s own
    // row, and the review's own finding that the two dialogs partly
    // duplicated each other. `_askAnyway` still exists for the top-bar's
    // own smaller entry points, which show no issue list of their own
    // first.
    bool skipConfirm = false,
  }) async {
    if (_state is! ModelerReady) return;

    var planned = planExport(
      _history.project,
      format: format,
      bakeTransforms: bakeTransforms,
      textureEncoding: textureEncoding,
      force: skipConfirm,
    );

    if (planned case final ExportBlocked blocked) {
      // Unreachable when skipConfirm is true: the first planExport call
      // above already passed force: skipConfirm, so a blocked plan only
      // ever reaches here when nobody has been asked yet.
      final go = await _askAnyway(blocked, blocked.issues);
      if (!go || !mounted) return;
      planned = planExport(
        _history.project,
        format: format,
        force: true,
        bakeTransforms: bakeTransforms,
        textureEncoding: textureEncoding,
      );
    }

    switch (planned) {
      case ExportRefused(:final String because):
        _cubit.say(because, important: true);
      case ExportBlocked():
        // Unreachable: the branch above either forced or returned. Named rather
        // than defaulted, so that adding a case to `ExportResult` is a compile
        // error here instead of a silent nothing.
        _cubit.say('not exported', important: true);
      case ExportWritten(
        :final List<ExportFile> files,
        :final List<String> warnings,
      ):
        final said = <String>[];
        for (final ExportFile file in files) {
          final result = await saveAs(file.bytes, suggestedName: file.name);
          said.add(switch (result.outcome) {
            SaveOutcome.written =>
              'wrote ${file.bytes.length} bytes to ${result.path}',
            SaveOutcome.cancelled => 'nothing saved',
            SaveOutcome.refused => result.said ?? 'refused',
          });
          // The `.mtl` is only worth asking for if the `.obj` was taken; a
          // person who cancelled the first panel has cancelled the export.
          if (result.outcome != SaveOutcome.written) break;
        }
        if (mounted) {
          _cubit.say(
            <String>[...said, ...warnings].join('\n'),
            important: true,
          );
        }
    }
  }

  /// `ui-17`'s own export screen — format, every readiness issue with a way
  /// to see what it is about, the triangle budget as a bar, and the "bake
  /// node transforms" flag. `ui-10`'s own row ("клик → диалог экспорта")
  /// wired the status line's readiness sentence and `⌘E` to a much smaller
  /// format-only dialog as a placeholder for this; both now open this
  /// screen instead, so there is one export entry point rather than two
  /// that could drift apart.
  Future<void> _showExportDialog() async {
    if (_state is! ModelerReady) return;
    final choice = await showExportScreen(
      context,
      project: _history.project,
      onShow: (int id) {
        _history.selection = _history.selection.copyWith(
          mode: SelectionMode.object,
          objects: <int>[id],
        );
        _cubit.documentMoved();
      },
    );
    if (choice != null) {
      unawaited(
        _exportFile(
          choice.format,
          bakeTransforms: choice.bakeTransforms,
          textureEncoding: choice.textureEncoding,
          skipConfirm: choice.acknowledgedWarnings,
        ),
      );
    }
  }

  /// `ui-13`'s own lathe dialog: `AddLathe` needs a profile, and this is the
  /// only place one gets drawn. Cancelling runs nothing at all — a person
  /// backing out of the dialog should not have to undo a box they never
  /// asked for.
  Future<void> _openLatheDialog() async {
    if (_state is! ModelerReady) return;
    final choice = await showLatheDialog(
      context,
      renderer: (_state as ModelerReady).renderer,
    );
    if (choice != null) {
      _cubit.ran(
        AddLathe(
          profile: choice.profile,
          segments: choice.segments,
          closedProfile: choice.closedProfile,
        ),
      );
    }
  }

  /// `mat-15`'s own studio: previews whatever material the active selection
  /// carries — or clay, when nothing is selected or the pool has not built
  /// one for it yet — on a body of its own, under a sky of its own. Nothing
  /// it does is undoable, because nothing it does changes the document: it
  /// hands back no result at all.
  Future<void> _openMaterialStudio() async {
    if (_state is! ModelerReady) return;
    final ready = _state as ModelerReady;
    final selectedId = ready.selection.activeObject;
    final selectedObject = selectedId == null
        ? null
        : ready.project[selectedId];
    final material = selectedObject == null
        ? null
        : ready.stage.materials?.forObject(selectedObject);
    await showMaterialStudioDialog(
      context,
      renderer: ready.renderer,
      material: material ?? clay(),
      selectedObjectMesh: selectedId == null
          ? null
          : ready.stage.sync?.nodeOf(selectedId)?.mesh,
    );
  }

  /// `ui-32n`'s own shortcut-help screen, opened by `?` or the Help button.
  void _showShortcutHelp() {
    if (_state is! ModelerReady) return;
    unawaited(showShortcutHelp(context));
  }

  /// `rel-15`'s own "Report a problem" button: opens a GitHub issue draft
  /// against `modeler_report.yml`, prefilled and sent nowhere on its own —
  /// [reportProblemUrl]'s own doc comment is the whole design here.
  /// [environmentSummary]'s own doc comment explains what "environment"
  /// actually holds and why.
  void _reportProblem() {
    unawaited(
      launchUrl(
        reportProblemUrl(environment: 'Flutter, ${environmentSummary()}'),
      ),
    );
  }

  /// `ui-15`'s own start screen: "Open file", "New project" with a profile,
  /// and the recent-models list `RecentModels` already keeps.
  Future<void> _showStartScreen() async {
    final device = _device;
    if (device == null || _state is! ModelerReady) return;
    final recent = RecentModels().read(exists: pathExists);
    if (!mounted) return;
    final choice = await showStartScreen(context, recentPaths: recent);
    if (!mounted || choice == null) return;
    switch (choice) {
      case OpenFileChoice():
        await _openFileAndRemember(device);
      case OpenRecentChoice(:final String path):
        await _openRecent(path, device);
      case NewProjectChoice(:final ProjectProfile profile):
        _newProjectWith(profile);
    }
  }

  /// "Open file" from the start screen — the same picker `_openFile` uses,
  /// with the chosen path written into `RecentModels` on success.
  ///
  /// **A sibling of `_openFile` rather than a change to it.** `_openFile`'s
  /// own body is mid-rewrite in a concurrent session's own uncommitted work
  /// (extracting the shared `_openBytes` this file already calls) — adding a
  /// line inside a function somebody else is simultaneously restructuring
  /// is not a safe edit to make no matter how small, so this repeats the
  /// picker call here instead of reaching into `_openFile`'s own body. The
  /// toolbar's own "Open" button keeps calling plain `_openFile` and does
  /// not record yet; folding the two into one recording path is a follow-up
  /// once that rewrite lands.
  Future<void> _openFileAndRemember(GraphicsDevice device) async {
    _cubit.say('choosing…');
    try {
      final picked = await openModel();
      if (picked == null) {
        if (mounted) _cubit.say('nothing chosen');
        return;
      }
      final opening = Stopwatch()..start();
      final opened = await openBytes(
        picked.bytes,
        name: picked.name,
        device: device,
      );
      opening.stop();
      if (!mounted) return;
      switch (opened) {
        case OpenRefused(:final String because):
          _cubit.say(because);
        case OpenedModel(
          :final ModelProject project,
          :final ModelerStage stage,
        ):
          final said = describeOpened(
            name: picked.name,
            objectCount: project.objects.length,
            triangleCount: project.triangleCount,
            materialCount: project.materials.length,
            openedInMs: opening.elapsedMilliseconds,
          );
          _installOpened(
            ModelHistory(project),
            stage,
            documentName: picked.name,
            said: <String>[said, ...opened.warnings].join('\n'),
            forgetSurfaces: true,
          );
      }
      // A browser's own PickedFile has no path — nothing to remember there,
      // and RecentModels reads that the same way a first launch does.
      if (picked.path case final String path) {
        RecentModels().remember(path, exists: pathExists);
      }
    } catch (error) {
      if (mounted) _cubit.say('could not open it: $error');
    }
  }

  /// A row from the start screen's own recent list, tapped. The sandbox's
  /// grant for a path it did not just hand out itself does not outlive the
  /// run that earned it — `readRecentModel`'s own doc comment — so a null
  /// here is the ordinary case to expect on a later launch, not a bug.
  Future<void> _openRecent(String path, GraphicsDevice device) async {
    final bytes = await readRecentModel(path);
    if (!mounted) return;
    if (bytes == null) {
      _cubit.say('could not reopen $path; use Open file instead');
      return;
    }
    final opening = Stopwatch()..start();
    final name = path.split(RegExp(r'[\\/]')).lastOrNull ?? path;
    final opened = await openBytes(bytes, name: name, device: device);
    opening.stop();
    if (!mounted) return;
    switch (opened) {
      case OpenRefused(:final String because):
        _cubit.say(because);
      case OpenedModel(:final ModelProject project, :final ModelerStage stage):
        final said = describeOpened(
          name: name,
          objectCount: project.objects.length,
          triangleCount: project.triangleCount,
          materialCount: project.materials.length,
          openedInMs: opening.elapsedMilliseconds,
        );
        _installOpened(
          ModelHistory(project),
          stage,
          documentName: name,
          said: <String>[said, ...opened.warnings].join('\n'),
          forgetSurfaces: true,
        );
    }
    RecentModels().remember(path, exists: pathExists);
  }

  /// "New project" from the start screen, with the profile picked there.
  void _newProjectWith(ProjectProfile profile) {
    final device = _device;
    if (device == null || _state is! ModelerReady) return;
    final project = _ModelerScreenState._newProject().copyWith(
      profile: profile,
    );
    final stage = ModelerStage.fromProject(device: device, project: project);
    _installOpened(
      ModelHistory(project),
      stage,
      documentName: 'untitled (${profile.name})',
      forgetSurfaces: true,
    );
  }

  /// Asks whether to export a model that will not load cleanly.
  ///
  /// A dialog rather than a refusal, because the alternative is this
  /// application deciding what somebody's model is for. It names what will be
  /// wrong rather than counting it: "3 problems" is a number nobody can act on.
  Future<bool> _askAnyway(ExportBlocked blocked, List<ExportIssue> issues) =>
      ExportAnywayDialog.show(context, blocked: blocked, issues: issues);

  /// A file dragged onto the window — `ui-31n`'s own door onto the same path
  /// `_openFile` already opens by hand.
  ///
  /// **Wrapped once, around the whole shell, rather than around the
  /// viewport.** A person drops a file wherever the pointer happens to be —
  /// over the outliner, the properties panel, the rail — and only one of
  /// those is the viewport; a window is either a place a file can land or it
  /// is not, and `ui-14`/`ui-16`'s own picker was never restricted to one
  /// widget either.
  ///
  /// **`unopenableDropRefusal` runs before any of the rest of this, and that
  /// is the one thing dropping cannot skip.** `openModel`'s own dialogue only
  /// ever offers this build's own extensions, so `_openFile` never has to ask
  /// — a drop can carry anything the desktop or the browser lets somebody
  /// drag onto the window, including a file this build has no reader for at
  /// all, and the answer for that is a sentence rather than a guess at what
  /// the bytes might be.
  Future<void> _handleDroppedFile(String name, Uint8List bytes) async {
    final device = _device;
    if (device == null || _state is! ModelerReady) return;
    if (unopenableDropRefusal(name, bytes) case final String because) {
      _cubit.say(because);
      return;
    }
    await _openBytesWithImportScreen(name, bytes, device);
  }
}
