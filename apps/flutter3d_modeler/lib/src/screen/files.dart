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
part of 'modeler_screen.dart';

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
  /// way regardless: `setState` forgetting the element-picker cache and
  /// `TransformSession`'s own other-object picker cache, because ids start
  /// again in the new project and a picker held against the old one could
  /// match a version and answer about a mesh that is gone (`tut-18`).
  void _installOpened(
    ModelHistory history,
    ModelerStage stage, {
    required String documentName,
    String? said,
    required bool forgetSurfaces,
  }) {
    stage.frameSubject();
    if (forgetSurfaces) {
      _surfaces.forget();
      _weightGradientShading.forget();
    }
    _cubit.opened(
      history,
      renderer: (_state as ModelerReady).renderer,
      stage: stage,
      documentName: documentName,
      said: said,
    );
    setState(() {
      _elementPickerCache.forget();
      _transformSession.forget();
    });
    // `ux-47`: watch whatever this project links to, and stop watching what
    // the last one did. Here rather than in `build`, because a project only
    // changes on an open and this is the one place every open goes through.
    _linkedMaterials.follow(history.project);
    _capturePreviewIfDue();
  }

  /// `tut-19`'s own trigger for the preview capture: the same "subject
  /// framed" moment every [_installOpened] call already reaches for the
  /// ordinary camera-fit behaviour, reused rather than a second signal
  /// invented for this.
  ///
  /// **Scheduled for the frame after this one, not run here.** The camera
  /// [_installOpened] just framed only reaches the viewport's own canvas
  /// once `SceneSurface` has actually rendered and presented it, and that
  /// happens during the paint the `setState` above causes — after this
  /// method returns, not before. `WidgetsBinding.instance.
  /// addPostFrameCallback` is what runs after that paint, the ordinary
  /// Flutter answer to "once this frame is actually on screen".
  ///
  /// **At most once per [ModelerScreen].** [_cabinetPreviewCaptured] latches
  /// the moment a [CabinetLink.shouldCapturePreview] worth acting on is
  /// seen, so a document opened locally afterward — a drag-drop, a recovered
  /// autosave — over a build that was opened from a cabinet entry never
  /// captures a picture of something that is not what that entry's id
  /// names. [_cabinetLink] itself never changes after `_open()` sets it, so
  /// nothing here re-reads it expecting a different answer later.
  void _capturePreviewIfDue() {
    if (_cabinetPreviewCaptured) return;
    final CabinetLink link = _cabinetLink;
    if (!link.shouldCapturePreview) return;
    _cabinetPreviewCaptured = true;
    final int modelId = link.id!;
    final String sourceSha = link.sourceSha!;
    final String csrf = link.csrf;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        _sendPreviewCapture(modelId: modelId, sourceSha: sourceSha, csrf: csrf),
      );
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
      // `ux-37`: whichever workspace the settings store holds — Essential
      // for an empty one, which is a first launch and the case the row is
      // for. Applied here rather than carried into `opened`, because
      // `opened` is also the door a *re*-open comes through and the
      // workspace is a property of the session rather than of the document.
      _cubit.workspace(_settings.workspace);
      // `ux-42`: Quick Setup once, Home after that. Scheduled rather than
      // awaited here, because everything below this line — the agent port,
      // the recovery offer — belongs to opening the document and none of it
      // should wait on somebody reading five questions.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_showLaunchScreen());
      });
      final int mcpPort = widget.mcpPort ?? kMcpPort;
      if (mcpPort >= 0) {
        unawaited(
          startMcpServer(
            history: opening3,
            port: mcpPort,
            sessionPath: widget.mcpSessionPath,
            uiActions: ModelerUiActions(
              cubit: _cubit,
              openExportDialog: _showExportDialog,
              openLatheDialog: _openLatheDialog,
              // `ux-36`: both of these are built, and `ui.openDialog` said
              // otherwise until somebody re-read the sentence.
              openAutorigDialog: _openAutorigDialog,
              openGamePreview: _openGamePreview,
              // `ux-50`: the document walked in, on one of three templates.
              openPlay: _openPlay,
              play: _play,
              // `ux-25`: the same door the rail and the palette press.
              runTool: _ranTool,
              // `ux-44`: the window itself, for an agent that needs to see
              // what the person sees rather than what the model looks like.
              captureWindow: _captureWindow,
            ),
            // `ux-45`: the person's own brake. Asked before every call, so a
            // paused agent is told why rather than left waiting — and being
            // told is what lets it say so instead of retrying.
            pausedBecause: () => _agentPaused
                ? 'the person has paused agent calls in this editor; '
                      'they will resume when the pause is lifted'
                : null,
            // `tut-16`'s own feed: screen 26's own tool-call panel reads
            // `ModelerReady.agentCalls`, appended to here as each call
            // answers — the one place a headless caller has nobody to
            // hand this to, which is why `onToolCall` is optional.
            onToolCall:
                (
                  String tool,
                  Map<String, Object?> arguments,
                  ({bool did, String says, Uint8List? png}) answer,
                  Duration elapsed,
                ) => _cubit.agentToolCalled(
                  AgentToolCall(
                    tool: tool,
                    arguments: arguments,
                    did: answer.did,
                    says: answer.says,
                    elapsed: elapsed,
                    at: DateTime.now(),
                    png: answer.png,
                  ),
                ),
            // `ux-05`: an open port is not an agent. Nothing agent-shaped is
            // on screen until this fires.
            onInitialize: _cubit.agentConnected,
          ),
        );
      }
      setState(() {
        // With no run to wait for, the opening cost is the whole report —
        // and `ux-30`'s own two seconds, because this one is a greeting
        // rather than something somebody asked to be told.
        if (kOrbit <= 0) {
          _showReport(
            'opened in ${_measurementRuns.openedInMs} ms',
            forAWhile: kOpeningReportFor,
          );
        }
      });
      final query = Uri.base.queryParameters;
      // `tut-19`/`tut-20`'s own `id`/`mode`/`csrf` — read from the same
      // query string `model`/`name` come from below, since a real launch
      // only ever sends any of them together (`cloud/server`'s own
      // `viewer.js` names all four at once). `widget.cabinetLink` lets a
      // test hand one in directly instead, since nothing in a `flutter
      // test` process can put a query string on `Uri.base`.
      _cabinetLink = widget.cabinetLink ?? CabinetLink.fromQuery(query);
      // Opened from a link: the models service loads this build in a frame
      // with the file's address in the query, so the document becomes that
      // model rather than staying a cube.
      final linked = query['model'];
      if (linked != null && linked.isNotEmpty) {
        unawaited(
          _openLinked(
            Uri.base.resolve(linked),
            query['name'] ?? 'model',
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
      // `ux-06`: the defaults read the format off the name.
      fileName: name,
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
  ///
  /// [only], when given, restricts the sweep to those object ids —
  /// `tut-08`'s own "Import" action passes the ids `importInto` just added,
  /// so a cleanup choice made for a second file does not reach back and
  /// rebuild an object that was already open and left untouched on purpose.
  ModelProject _applyImportCleanup(
    ModelProject project,
    ImportChoice choice, {
    Set<int>? only,
  }) {
    if (!choice.weld && !choice.fixNormals && !choice.triangulate) {
      return project;
    }
    var result = project;
    for (final object in project.objects) {
      if (only != null && !only.contains(object.id)) continue;
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

  /// `tut-08`'s own "Import" action: a second file's own objects merged into
  /// the document already open, rather than replacing it.
  ///
  /// **The same tested seam `flutter3d_model_mcp`'s own `ModelSession.
  /// import` already runs, reachable by a person now instead of only by an
  /// agent over MCP.** `import_into_test.dart` is what proves `importInto`
  /// itself; this is the picker, the import screen and the undo step around
  /// it, the same three `_openBytesWithImportScreen` already has — reused
  /// rather than duplicated, since the only real difference is what happens
  /// to the result: [ReplaceDocument] over the *merged* project here,
  /// [_installOpened]'s wholesale replacement there.
  ///
  /// **A project file is refused rather than guessed at.** `ModelSession.
  /// import` never special-cases one either — `importInto` takes a
  /// [ModelDocument], and a `.f3dproj` is a [ModelProject] already, nothing
  /// this call knows how to fold two of into one.
  Future<void> _importFile() async {
    if (_state is! ModelerReady) return;
    _cubit.say('choosing…');
    try {
      final picked = await openModel();
      if (picked == null) {
        if (mounted) _cubit.say('nothing chosen');
        return;
      }
      if (isProjectFile(picked.bytes)) {
        _cubit.say('${picked.name} is a project file; use Open instead');
        return;
      }
      final limitRefusal = refuseBeforeDecoding(
        fileSizeBytes: picked.bytes.length,
        onWeb: kIsWeb,
      );
      if (limitRefusal != null) {
        _cubit.say(limitRefusal);
        return;
      }
      final ModelDocument document;
      try {
        document = await decodeBytes(picked.bytes, picked.name);
      } catch (error) {
        _cubit.say('${picked.name} could not be read: $error');
        return;
      }
      final empty = emptyDecodeRefusal(document, picked.name);
      if (empty != null) {
        _cubit.say(empty);
        return;
      }
      if (!mounted) return;
      final choice = await showImportScreen(
        context,
        document: document,
        profile: _history.project.profile,
        fileName: picked.name,
      );
      if (choice == null) {
        _cubit.say('import cancelled');
        return;
      }
      final ModelProject before = _history.project;
      final report = importInto(
        before,
        document,
        options: ImportOptions(scale: choice.unit.scale, upAxis: choice.upAxis),
      );
      if (report.counts.objects == 0) {
        _cubit.say('${picked.name} has nothing this reader could place');
        return;
      }
      // `importInto` always appends the incoming objects after whatever was
      // already in the project (`ModelProject.added`'s own doc comment), so
      // everything past `before`'s own length is exactly what this import
      // brought in — `_applyImportCleanup`'s own `only` restricts the
      // cleanup choice to that set.
      final newIds = <int>{
        for (final ModelObject object in report.project.objects.skip(
          before.objects.length,
        ))
          object.id,
      };
      var merged = _applyImportCleanup(report.project, choice, only: newIds);
      // `ux-48`: everything this import brought in remembers the file it came
      // from, and what that file said. One project rather than a command per
      // object, since the import itself is already one step and a link is
      // part of the same act.
      if (choice.linkToSource && picked.path != null) {
        final String path = picked.path!;
        final String sha = shaOfBytes(picked.bytes);
        for (final int id in newIds) {
          final ModelObject? object = merged[id];
          if (object == null) continue;
          merged = merged.withObject(
            object.copyWith(source: (path: path, sha: sha)),
          );
        }
      }
      _cubit.ran(
        ReplaceDocument(merged, 'import ${picked.name}'),
        said:
            'imported ${report.counts.objects} '
            '${report.counts.objects == 1 ? 'object' : 'objects'} from '
            '${picked.name}',
      );
    } catch (error) {
      if (mounted) _cubit.say('could not import it: $error');
    }
  }

  /// `ux-49`: picks a Radiance `.hdr` and lights the scene with it.
  ///
  /// **The image goes into the project's own table**, like every texture,
  /// so a panorama travels with the file rather than being a path that may
  /// not exist on the next machine — and so `SetPanorama` can check its size
  /// by index rather than being handed a number to trust.
  ///
  /// Two commands rather than one: the image is added, and then pointed at.
  /// `SetPanorama` is what refuses an image that is not twice as wide as it
  /// is tall, and the refusal reaches the strip with the size in it.
  Future<void> _choosePanorama() async {
    final PickedFile? picked = await openPanorama();
    if (picked == null || !mounted) return;
    final int at = _history.project.images.length;
    _cubit.ran(
      AddImage(
        bytes: picked.bytes,
        imageName: picked.name,
        mimeType: 'image/vnd.radiance',
      ),
      said: 'added ${picked.name}',
    );
    if (!mounted) return;
    _cubit.ran(SetPanorama(index: at), said: 'lit by ${picked.name}');
  }

  /// `ux-48`: reads [id]'s own source file again and replaces its geometry.
  ///
  /// **Everything else about the object stays**, which is the whole reason
  /// this exists rather than "import it again": the transform, the materials,
  /// the modifier stack and the shape keys are work done in this project
  /// about a mesh, and a file moving is not a reason to do that twice.
  ///
  /// The read goes through `readRecentModel`, which swallows a refusal into
  /// null for the reason its own doc comment gives — under the macOS sandbox
  /// a path written down earlier is not a licence to read it later, and the
  /// honest answer to that is a sentence rather than an exception.
  Future<void> _reimport(int id) async {
    final ModelObject? object = _history.project[id];
    final SourceLink? link = object?.source;
    if (link == null) return;
    final Uint8List? bytes = await readRecentModel(link.path);
    if (!mounted) return;
    if (bytes == null) {
      _cubit.say(
        '${link.path} could not be read \u2014 open it once from the file '
        'picker and link it again',
        important: true,
      );
      return;
    }
    final String sha = shaOfBytes(bytes);
    if (sha == link.sha) {
      _cubit.say('${link.path} has not changed since it was last read');
      return;
    }
    final ModelDocument document;
    try {
      document = await decodeBytes(bytes, link.path);
    } on Object catch (error) {
      if (!mounted) return;
      _cubit.say('${link.path} did not read: $error', important: true);
      return;
    }
    if (!mounted) return;
    final MeshData? read = document.surfaces.firstOrNull?.mesh;
    if (read == null) {
      _cubit.say(
        '${link.path} has no mesh this reader could place',
        important: true,
      );
      return;
    }
    // Welded into real topology, for the same reason the import screen's own
    // "weld" does: a re-imported mesh a person cannot then edit is a mesh
    // that has to be re-imported again the moment they want to. The first
    // surface, because a link is to one object and a file that grew a second
    // mesh is a file to import rather than to re-read.
    final (EditMesh mesh, _, _) = importMeshData(
      read,
      weldEpsilon: weldEpsilonFor(weld: true),
    );
    _cubit.ran(
      Reimport(id: id, sha: sha, meshBytes: mesh.toBytes()),
      said: 'read ${link.path} again',
    );
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

  /// `tut-20`'s own write-back: exports the open document as `.f3dproj`
  /// bytes — `writeProject`, the same lossless writer [_saveFile] already
  /// calls, never a second exporter — and POSTs them to the cabinet entry
  /// this build was opened from.
  ///
  /// **Always `.f3dproj`, whatever format the cabinet entry originally
  /// held.** A model opened from a `.glb` upload becomes a `.f3dproj`
  /// cabinet entry the moment it is saved back here, since that is the one
  /// format nothing this application can hold — materials, modifiers,
  /// animation, everything `mat-*`/`S2`/`S5`/`S6` built — is lost into. The
  /// status line says so explicitly, so nobody who opened a `.glb` is
  /// surprised their cabinet entry is now something else.
  ///
  /// **UX-only gating, not the security boundary.** [_cabinetLink]'s own
  /// `canSaveBack` is what decides whether the button that calls this even
  /// exists — see `ready_parts.dart`'s own `TopBarActions.onSaveToCabinet`.
  /// The server's own `canEdit` check on `/api/v1/models/<id>/source` is
  /// what actually decides whether the save is allowed, the same as every
  /// other mutating endpoint in `cloud/server`; this method still checks
  /// [CabinetLink.canSaveBack] itself rather than trusting the caller,
  /// because a stray call site should refuse the same way a hidden button
  /// would have.
  Future<void> _saveToCabinet() async {
    if (_state is! ModelerReady) return;
    final int? id = _cabinetLink.id;
    if (id == null || !_cabinetLink.canSaveBack) return;

    _cubit.say('saving to the cabinet…');
    final Uint8List bytes;
    try {
      // No history section: a cabinet entry is a document other people may
      // open too, and `_saveFile`'s own "Save without history" choice is
      // exactly the default worth making here without asking, rather than a
      // dialog in front of a one-click action.
      bytes = writeProject(_history.project);
    } on ArgumentError catch (error) {
      if (mounted) _cubit.say('not saved: ${error.message}', important: true);
      return;
    }

    final outcome = await _sendCabinetSource(
      modelId: id,
      csrf: _cabinetLink.csrf,
      bytes: bytes,
    );
    if (!mounted) return;
    switch (outcome) {
      case CabinetSaveWritten():
        _history.markSaved();
        _cubit.say(
          'saved ${bytes.length} bytes to the cabinet as .f3dproj — always '
          'this format, regardless of what the cabinet entry held before',
          important: true,
        );
      case CabinetSaveFailed(:final String said):
        _cubit.say('not saved to the cabinet: $said', important: true);
    }
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
    bool selectionOnly = false,
    bool applyModifiers = true,
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
      // `ux-18`: what the screen asked for. An empty set writes everything,
      // which is what Export has always meant.
      only: selectionOnly ? _history.selection.objects.toSet() : const <int>{},
      applyModifiers: applyModifiers,
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
          // **The status line is one line, and an export can have six
          // things to say** — `ux-18`. Joining them with newlines put
          // everything after the first into a strip that shows one, so a
          // person was told the file was written and never told what had
          // been left out of it. The first line goes to the strip, which is
          // where the eye already is; the whole of it goes to the console,
          // which `ux-26` built for exactly this.
          final List<String> everything = <String>[...said, ...warnings];
          _cubit.say(everything.first, important: true);
          for (final String line in everything.skip(1)) {
            _cubit.note(line);
          }
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
  Future<void> _showExportDialog({ExportFormat? format}) async {
    if (_state is! ModelerReady) return;
    final choice = await showExportScreen(
      context,
      project: _history.project,
      format: format ?? ExportFormat.glb,
      hasSelection: _history.selection.objects.isNotEmpty,
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
    unawaited(
      showShortcutHelp(
        context,
        // `ux-10`: the screen lists the preset that is actually live, and
        // the camera section follows the navigation scheme beside it.
        keymap: keymapFor(
          _settings.keymap,
          apple:
              Theme.of(context).platform == TargetPlatform.macOS ||
              Theme.of(context).platform == TargetPlatform.iOS,
        ),
        navigation: _settings.navigation,
      ),
    );
  }

  /// `ux-25`'s own command palette: every tool in the application by name,
  /// with the key the live preset gives it and a reason beside the ones
  /// another mode owns.
  ///
  /// **It runs what the rail runs**, through `_ranTool`, so a tool reached
  /// this way arms, opens a dialog or lands a command exactly as it would
  /// from the button — one door, and the palette is a second way through it
  /// rather than a second implementation of it.
  Future<void> _showCommandPalette() async {
    final ModelerState state = _state;
    if (state is! ModelerReady) return;
    final Keymap keymap = keymapFor(
      _settings.keymap,
      apple:
          Theme.of(context).platform == TargetPlatform.macOS ||
          Theme.of(context).platform == TargetPlatform.iOS,
    );
    final String? chosen = await showCommandPalette(
      context,
      entries: paletteEntries(
        l10n: AppLocalizations.of(context),
        mode: state.mode,
        animation: state.animationSubmode,
        keymap: keymap,
        unavailable: unavailableTools(
          mode: state.mode,
          selection: state.history.selection,
        ),
        extra: <PaletteEntry>[
          ...foldEntries(
            keymap,
            mode: state.mode,
            l10n: AppLocalizations.of(context),
          ),
          ...helpEntries(mode: state.mode, l10n: AppLocalizations.of(context)),
        ],
      ),
    );
    if (chosen == null || !mounted) return;
    switch (chosen) {
      // `ux-27`'s own two, which are about the window rather than the model
      // and so are not rail tools.
      case kFoldPanelCommand:
        setState(() => _foldedPanel = !_foldedPanel);
      case kFoldRailCommand:
        setState(() => _foldedRail = !_foldedRail);
      // `rel-21d`: the same screen Settings opens, reached by name.
      case kLegalCommand:
        unawaited(showLegalScreen(context));
      default:
        _ranTool(chosen);
    }
  }

  /// `ux-25`'s own right-click menu: the tools of the mode somebody is in,
  /// where the pointer already is.
  ///
  /// The palette's own list, shortened to what can be run from here — a menu
  /// is read at a glance and a greyed row from another mode would be noise
  /// at that size, where in the palette it is an answer to a search.
  Future<void> _showViewportMenu(Offset at) async {
    final ModelerState state = _state;
    if (state is! ModelerReady) return;
    final RenderBox? overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final List<PaletteEntry> entries = <PaletteEntry>[
      for (final PaletteEntry entry in paletteEntries(
        l10n: AppLocalizations.of(context),
        mode: state.mode,
        animation: state.animationSubmode,
        keymap: keymapFor(
          _settings.keymap,
          apple:
              Theme.of(context).platform == TargetPlatform.macOS ||
              Theme.of(context).platform == TargetPlatform.iOS,
        ),
        unavailable: unavailableTools(
          mode: state.mode,
          selection: state.history.selection,
        ),
      ))
        if (entry.mode == state.mode && entry.enabled) entry,
    ];
    if (entries.isEmpty) return;
    final String? chosen = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        at & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: <PopupMenuEntry<String>>[
        for (final PaletteEntry entry in entries)
          PopupMenuItem<String>(
            value: entry.id,
            child: Row(
              children: <Widget>[
                Icon(entry.icon, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(entry.label)),
                if (entry.keys case final String keys)
                  Text(keys, style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
          ),
      ],
    );
    if (chosen == null || !mounted) return;
    _ranTool(chosen);
  }

  /// `ux-09`'s own settings screen.
  ///
  /// The dialog answers with the settings to keep, or null when the person
  /// backed out; a write that fails says so on the status line rather than
  /// being swallowed — see [SettingsStore.write] for why this one is worth
  /// reporting where the recent list's own is not.
  Future<void> _showSettings() async {
    final ModelerSettings? chosen = await showSettingsScreen(
      context,
      _settings,
      // `rel-21d`: the documents, and the one button the privacy policy
      // promises. Passed in rather than reached for inside the dialog, so
      // the settings screen stays a dialog over a value and keeps its own
      // tests free of a storage.
      onShowLegal: () => unawaited(showLegalScreen(context)),
      onClearLocalData: _clearLocalData,
    );
    if (chosen == null || !mounted) return;
    // `ux-11`: the steps a held snap rounds to are the person's own, and a
    // transform started after this reads the new ones. `ux-37`: the switcher
    // grows or shrinks with no restart, and a person standing in a mode the
    // new workspace does not have is moved off it. Both live in
    // `_keepSettings` now, which `ux-42`'s own Quick Setup shares.
    _keepSettings(chosen);
  }

  /// `ux-44`'s own `ui.screenshot`: the window as PNG bytes, or null when
  /// there is nothing laid out to capture yet.
  ///
  /// **A `RepaintBoundary` round the whole screen, not round the viewport.**
  /// The point of this picture is everything the viewport is not — the
  /// panels, the rail, the dialog that is open, the status line somebody
  /// just captioned with `ui.say`. `render` already draws the model on its
  /// own and does it better, with a camera an agent can aim.
  Future<List<int>?> _captureWindow() async {
    final RenderObject? found = _windowKey.currentContext?.findRenderObject();
    if (found is! RenderRepaintBoundary) return null;
    final ui.Image image = await found.toImage();
    try {
      final ByteData? png = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      return png?.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  /// `rel-21d`: removes what this application has written on this device —
  /// the settings, the recent-files list and the one autosave slot — and
  /// answers with the sentence to show.
  ///
  /// The settings this session is holding go back to their defaults in the
  /// same breath, because leaving them in memory would write them straight
  /// back out the next time anything changed one, and a person who has just
  /// cleared their data would find it there again.
  Future<String> _clearLocalData() async {
    // `_autosave` is built in `initState` and is null only before it, which
    // is before there is a settings dialog to press this from. Saying so
    // here rather than asserting it, because a refusal is a better answer
    // than a crash for a button about somebody's data.
    final AutosaveController? autosave = _autosave;
    if (autosave == null) return 'The editor is still starting up.';
    final ClearedLocalData cleared = await clearLocalData(
      storage: _settingsStore.storage,
      documents: autosave.storage,
      autosaveSessionId: _kAutosaveSessionId,
    );
    if (cleared.settings && mounted) {
      setState(() {
        _settings = const ModelerSettings();
        _transformSession.snapSteps = _snapStepsOf(_settings);
      });
    }
    return cleared.says;
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
  Future<void> _showStartScreen({bool atLaunch = false}) async {
    final device = _device;
    if (device == null || _state is! ModelerReady) return;
    final recent = RecentModels().read(exists: pathExists);
    if (!mounted) return;
    final choice = await showStartScreen(
      context,
      recentPaths: recent,
      showAtLaunch: _settings.showHomeAtLaunch,
      // `ux-42`: only the launch showing offers the setting. Asking "show
      // this at launch?" on a screen somebody opened by pressing Home is
      // asking about a moment that has already passed.
      offerLaunchChoice: atLaunch,
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case OpenFileChoice():
        await _openFileAndRemember(device);
      case OpenRecentChoice(:final String path):
        await _openRecent(path, device);
      case NewProjectChoice(:final ProjectProfile profile):
        _newProjectWith(profile);
      case ScenarioChoice(:final StartScenario scenario):
        await _startScenario(scenario, device);
      case ShowAtLaunchChoice(:final bool show):
        _keepSettings(_settings.copyWith(showHomeAtLaunch: show));
        // The checkbox closed the screen to answer; put it back, because
        // ticking a box is not choosing what to do next.
        await _showStartScreen(atLaunch: atLaunch);
    }
  }

  /// `ux-42`: what the first launch shows — Quick Setup on an empty settings
  /// store, Home on a filled one, and nothing at all when a person has turned
  /// Home off.
  ///
  /// **Quick Setup is not optional and Home is.** The five questions are ones
  /// somebody knows the answer to before they have used the editor, and
  /// asking them later means asking after the defaults have already annoyed
  /// somebody; Home is a convenience, and a person who wants to land straight
  /// in the document should get to say so.
  Future<void> _showLaunchScreen() async {
    if (!_settings.quickSetupDone) {
      final ModelerSettings chosen = await showQuickSetup(context, _settings);
      if (!mounted) return;
      _keepSettings(chosen);
      return;
    }
    if (_settings.showHomeAtLaunch) await _showStartScreen(atLaunch: true);
  }

  /// Keeps [chosen] — in this session, in the store, and wherever the rest of
  /// the screen reads a setting from.
  ///
  /// The same three things `_showSettings` does with what its dialog answers,
  /// named once so `ux-42`'s own two callers do not each re-derive them.
  void _keepSettings(ModelerSettings chosen) {
    setState(() {
      _settings = chosen;
      _transformSession.snapSteps = _snapStepsOf(chosen);
    });
    _cubit.workspace(chosen.workspace);
    if (!_settingsStore.write(chosen)) {
      _cubit.say('Settings could not be saved', important: true);
    }
  }

  /// `ux-42`: each card lands in the state its tutorial case starts from.
  ///
  /// **Landing somewhere, rather than explaining where to go.** A person
  /// following the tutorial's own "a character" case needs the Full
  /// workspace, Animation mode and a document; telling them that in three
  /// sentences and leaving them in Object mode is how a tutorial loses
  /// somebody in its first paragraph.
  Future<void> _startScenario(
    StartScenario scenario,
    GraphicsDevice device,
  ) async {
    switch (scenario) {
      // A scan arrives through the same door every file does — the import
      // screen, where the unit and the welding are chosen (`ux-06`).
      case StartScenario.scan:
        await _openFileAndRemember(device);
      case StartScenario.primitives:
        _newProjectWith(const ProjectProfile());
        _cubit.mode(ModelerMode.object);
      case StartScenario.character:
        _newProjectWith(const ProjectProfile());
        // Animation mode is in the Full workspace only, so asking for it
        // without this would be refused by `ux-37`'s own gate — correctly,
        // and uselessly for somebody who just asked for a character.
        _keepSettings(_settings.copyWith(workspace: Workspace.full));
        _cubit.mode(ModelerMode.animation);
      case StartScenario.scene:
        _newProjectWith(const ProjectProfile());
        _cubit.mode(ModelerMode.scene);
    }
  }

  /// "Open file" from the start screen — the same picker and the same import
  /// screen the toolbar's own Open button uses, with the chosen path written
  /// into `RecentModels` on success.
  ///
  /// **`ux-06`: through [_openBytes], like every other door.** This used to
  /// call `openBytes` directly and skip the import screen entirely, behind a
  /// comment about `_openFile` being mid-rewrite in a concurrent session —
  /// work that is not in the tree and was not when the comment was written.
  /// What it cost is the review's own worst first-hour finding: the start
  /// screen is the shortest path to a file and the only one that silently
  /// applied metres and no welding, so a scan opened there arrived a
  /// thousand times too large and without topology, with nothing said about
  /// either.
  Future<void> _openFileAndRemember(GraphicsDevice device) async {
    _cubit.say('choosing…');
    try {
      final picked = await openModel();
      if (picked == null) {
        if (mounted) _cubit.say('nothing chosen');
        return;
      }
      await _openBytes(picked.name, picked.bytes, device);
      if (!mounted) return;
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
    final name = path.split(RegExp(r'[\\/]')).lastOrNull ?? path;
    // Through [_openBytes] for `ux-06`'s own reason, the same as the door
    // above: a file reopened from the recent list is a file being opened,
    // and the unit and the cleanup are questions about it either way.
    await _openBytes(name, bytes, device);
    if (!mounted) return;
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
  ///
  /// **The rest is `_openBytes`, the same shared helper `_openFile` already
  /// calls a few lines above** — not a second copy of its switch on
  /// `_openBytesWithImportScreen`'s result. A drop used to await that result
  /// and throw it away, which decoded the file, ran the import screen, and
  /// then put nothing on screen at all (`tut-17`).
  Future<void> _handleDroppedFile(String name, Uint8List bytes) async {
    final device = _device;
    if (device == null || _state is! ModelerReady) return;
    if (unopenableDropRefusal(name, bytes) case final String because) {
      _cubit.say(because);
      return;
    }
    await _openBytes(name, bytes, device);
  }
}
