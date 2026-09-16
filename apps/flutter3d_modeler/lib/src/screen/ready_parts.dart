/// `_ModelerScreenState`'s own screen-assembly half — `ui-05`'s three
/// shells, built from the one state every one of them reads.
///
/// A `part of 'main.dart'` for the same reason `device.dart` beside it is:
/// [_screen] closes over `context`, `_cubit`, `_history`, `_transformSession`
/// and most of the rest of `_ModelerScreenState`'s own fields to build the
/// actions, status, properties and viewport every mode and every shell
/// share.
///
/// `setState` is `@protected` on `State`, and the analyzer's check for that
/// annotation does not recognise an extension method on `_ModelerScreenState`
/// as code written inside the class — even though this file is, syntactically,
/// exactly that. The call itself is correct; only the check misfires.
// ignore_for_file: invalid_use_of_protected_member
part of '../../main.dart';

extension _ReadyParts on _ModelerScreenState {
  /// The whole screen, inside `ux-44`'s own capture boundary.
  ///
  /// **A boundary round everything, and only one.** `ui.screenshot` is for
  /// what the person is looking at — the panels, the rail, the dialog that
  /// is open — and a boundary round the viewport alone would answer the
  /// question `render` already answers better. It costs a layer at the root,
  /// which is where Flutter puts one anyway.
  Widget _screen(ModelerState state) =>
      RepaintBoundary(key: _windowKey, child: _screenBody(state));

  Widget _screenBody(ModelerState state) => switch (state) {
    ModelerOpening() => const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    ),
    // `ui-15` is the start screen and this is the state it will show in. Until
    // it exists there is no way to reach this, and a wildcard here would be a
    // silent blank window on the day somebody adds the first path to it.
    ModelerChoosing(:final said) => Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(said, textAlign: TextAlign.center),
        ),
      ),
    ),
    ModelerFailed(:final said) => Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(said, textAlign: TextAlign.center),
        ),
      ),
    ),
    // `ux-30`: the title says which document this is, and on macOS the
    // window itself is told, since `Title` alone never reaches an `NSWindow`.
    ModelerReady(:final renderer, :final stage) => DocumentWindowTitle(
      name: state.documentName,
      isDirty: state.history.isDirty,
      // `ui-24`'s own "при isDirty — диалог" on the platforms that route an
      // exit attempt through a `Navigator` pop — Android's back gesture,
      // chiefly, since this single-screen app has nothing else to pop to.
      // `_onExitRequested` covers the desktop window-close case, which
      // never goes through here at all.
      child: PopScope(
        canPop: !state.history.isDirty,
        onPopInvokedWithResult: _onPopInvoked,
        child: ModelerKeys(
          onKey: _transformSession.modalKey,
          onUndo: _undo,
          onRedo: _redo,
          onExport: _showExportDialog,
          onTool: _ranTool,
          onSelectAll: () => _runSelection(const SelectAll()),
          onSelectNone: () => _runSelection(const SelectNone()),
          onInvertSelection: () => _runSelection(const InvertSelection()),
          onShortcutHelp: _showShortcutHelp,
          // `ux-25`: ⌘P, or F3 on a keyboard with no command key.
          onCommandPalette: () => unawaited(_showCommandPalette()),
          // `ux-27`: `N` and `T`, and the same two from the palette.
          onFoldPanel: () => setState(() => _foldedPanel = !_foldedPanel),
          onFoldRail: () => setState(() => _foldedRail = !_foldedRail),
          // `ux-28`: one ring of neighbours more, and one less.
          onGrowSelection: () => _runSelection(const GrowSelection()),
          onShrinkSelection: () => _runSelection(const ShrinkSelection()),
          // `ux-24`: the brush's own reach, a fifth at a time so that a
          // handful of presses crosses the whole range rather than fifty.
          onBrushNarrower: () => _setWeightBrushRadius(
            (_weightBrushRadius * 0.8).clamp(4.0, 256.0),
          ),
          onBrushWider: () => _setWeightBrushRadius(
            (_weightBrushRadius * 1.25).clamp(4.0, 256.0),
          ),
          // `ux-10`: whichever preset Settings holds, on this platform's own
          // command key.
          keymap: keymapFor(
            _settings.keymap,
            apple:
                Theme.of(context).platform == TargetPlatform.macOS ||
                Theme.of(context).platform == TargetPlatform.iOS,
          ),
          onSave: () => unawaited(_saveFile()),
          onDelete: () => _ranTool(
            state.mode == ModelerMode.mesh ? 'mesh.delete' : 'object.delete',
          ),
          // Object ⇄ Mesh, and nothing else: the other modes are a choice
          // somebody makes, and this is the switch a modeller makes most.
          onToggleObjectMesh: () => _cubit.mode(
            state.mode == ModelerMode.mesh
                ? ModelerMode.object
                : ModelerMode.mesh,
          ),
          onFrameSelection: () =>
              setState(() => stage.frameObjects(state.selection.objects)),
          onFrameAll: () => setState(stage.frameSubject),
          onPlayPause: _toggleAnimationPlayback,
          onStandardView: (ModelerAction view) => setState(
            () => lookFrom(stage.orbit, switch (view) {
              ModelerAction.viewSide => StandardView.right,
              ModelerAction.viewTop => StandardView.top,
              _ => StandardView.front,
            }),
          ),
          mode: state.mode,
          onLevel: _cubit.submode,
          onAnimationLevel: _cubit.animationSubmode,
          tools: toolsFor(state.mode, animation: state.animationSubmode),
          // **`ui-05`'s own three shells, built once and handed to
          // [ScreenParts].** The actions/status/properties/viewport widgets
          // below are the same objects whichever shell draws them —
          // `ui-05`'s own acceptance is that the same tools answer to the
          // same keys in all three, and building them once here rather than
          // once per shell branch is what makes that true by construction
          // rather than by three call sites staying in sync by hand.
          // [ShellForWidth] is what picks the shell now.
          child: Builder(
            builder: (BuildContext context) {
              final actions = <Widget>[
                TopBarActions(
                  canUndo: state.history.canUndo,
                  canRedo: state.history.canRedo,
                  undoSays: state.history.undoSays,
                  redoSays: state.history.redoSays,
                  onUndo: _undo,
                  onRedo: _redo,
                  onAddPrimitive: (String kind) =>
                      _cubit.ran(AddPrimitive(kind: kind)),
                  onOpen: _openFile,
                  onImport: () => unawaited(_importFile()),
                  onSave: _saveFile,
                  isDirty: state.history.isDirty,
                  onSaveToCabinet: _cabinetLink.canSaveBack
                      ? () => unawaited(_saveToCabinet())
                      : null,
                  // `ux-18`: the menu no longer exports on its own. It
                  // opens the one export screen with the format it names
                  // already chosen — two export paths that could disagree
                  // about "bake transforms", "selection only" and every
                  // readiness issue were two answers to one question.
                  onExport: (ExportFormat format) =>
                      unawaited(_showExportDialog(format: format)),
                  onMaterialStudio: () => unawaited(_openMaterialStudio()),
                  onPreview: () => unawaited(_openGamePreview()),
                  onShortcutHelp: _showShortcutHelp,
                  onSettings: () => unawaited(_showSettings()),
                  agentClient: state.agentClient,
                  agentCallCount: state.agentCalls.length,
                  onToggleAgentPanel: () =>
                      setState(() => _agentPanelOpen = !_agentPanelOpen),
                  onStartScreen: () => unawaited(_showStartScreen()),
                  onReportProblem: _reportProblem,
                ),
              ];
              final ModelObject? forStatus =
                  state.project[state.selection.activeObject ?? -1];
              // `S6`'s own row: whether the held object's own `weights`
              // track carries a key on the timeline's current frame — one
              // boolean `MorphsPanel` reads for every shape row alike, see
              // `shape_key_state.dart`'s own class comment for why one is
              // all there is to compute.
              final bool hasShapeKeyAtCurrentFrame = forStatus == null
                  ? false
                  : hasShapeKeyAtFrame(
                      clip: _animationClip == null
                          ? null
                          : state.project.clips[_animationClip!],
                      objectId: forStatus.id,
                      frame: _frame.value,
                      fps: state.project.profile.fps,
                    );
              final status = StatusLine(
                // One sentence, carried by the state. There used to be two — one for
                // files and one for operations — with the operation's winning by
                // sitting first in a `??` chain, which meant a file that failed to
                // open said nothing at all if an operation had run before it.
                said: state.said ?? _selectionSaid,
                // `ux-17`: only the state's own sentence can be a refusal —
                // what is selected never is.
                saidIsRefusal: state.said != null && state.saidIsRefusal,
                // A value on the state, refreshed when a command lands rather than
                // computed while a frame is drawn. It cannot go stale behind a check
                // that never runs, which is what a getter here could do.
                readiness: state.readiness,
                triangles: state.project.triangleCount,
                vertices: state.project.vertexCount,
                materialCount: state.project.materials.length,
                // The held object's own texel density — null with nothing selected,
                // or nothing on it for `texelDensityOf` to measure.
                texelDensity: forStatus == null
                    ? null
                    : texelDensityOf(state.project, forStatus),
                textureBudget: (
                  usedBytes: measure(
                    state.project,
                    state.project.profile.textures,
                  ).totalBytes,
                  budgetBytes: state.project.profile.textures.maxBytesOnDevice,
                ),
                // Screen 07's own row: "Bones N · actions N · influences M
                // per vertex", in the animation mode's pose sub-mode only —
                // every other mode keeps the ordinary vertex/material count.
                modeSummary:
                    state.mode == ModelerMode.animation &&
                        state.animationSubmode == AnimationSubmode.pose
                    ? animationModeSummary(
                        bones:
                            heldSkeletonOf(
                              state.project,
                              forStatus,
                            )?.joints.length ??
                            0,
                        actions: state.project.clips.length,
                        maxInfluences: state.project.profile.maxInfluences,
                      )
                    : null,
                micros: _lastRenderMicros,
                onExport: _showExportDialog,
                // `ux-01`: offered only while autosave is actually failing,
                // and only where the platform has a folder to open at all —
                // the web build's own `applicationFolder` answers null.
                onShowFolder: switch (state.autosaveTrouble?.folder) {
                  final String folder => () => _showAutosaveFolder(folder),
                  null => null,
                },
                // `ux-26`: what the three buttons do right now, under the
                // person's own scheme and whatever is armed. Only where
                // there are three buttons — a touch shell has none, and the
                // segment would be three lies.
                mouseHints:
                    LayoutClass.of(MediaQuery.sizeOf(context).width) ==
                        LayoutClass.desktop
                    ? mouseHintsFor(
                        scheme: _settings.navigation,
                        tool: state.tool,
                        lookingAround: _lookingAround,
                      )
                    : null,
                onConsole: () => setState(() => _consoleOpen = !_consoleOpen),
              );
              final properties = PropertiesPanel(
                mode: state.mode,
                animationSubmode: state.animationSubmode,
                stage: stage,
                project: state.project,
                selection: state.selection,
                onSelect: (int id) {
                  // Straight onto the history's selection rather than through a
                  // command: `doc-32n` gave the *set* operations commands — all,
                  // none, invert, grow — and picking one object out of the outliner
                  // is not one of them yet. When it is, this becomes `_cubit.ran`.
                  state.history.selection = state.selection.copyWith(
                    mode: SelectionMode.object,
                    objects: <int>[id],
                  );
                  _cubit.documentMoved();
                },
                onTransform: _setTransform,
                pivot: _pivot,
                onPivot: (PivotChip to) => setState(() => _pivot = to),
                space: _space,
                onSpace: (TransformSpace to) => setState(() => _space = to),
                onRename: (int id, String to) =>
                    _cubit.ran(Rename(id: id, to: to)),
                onToggleModifier: (int id, int index) =>
                    _cubit.ran(ToggleModifier(id: id, index: index)),
                onReorderModifier: (int id, int from, int to) =>
                    _cubit.ran(ReorderModifier(id: id, from: from, to: to)),
                // `ux-13`: whichever kind the menu offered. What was here
                // added a mirror on X without asking, which is one of five
                // and was never the one anybody meant more than a fifth of
                // the time.
                onAddModifier: (int id, Modifier modifier) =>
                    _cubit.ran(AddModifier(id: id, modifier: modifier)),
                onToggleModifierExport: (int id, int index) =>
                    _cubit.ran(ToggleModifierExport(id: id, index: index)),
                onRemoveModifier: (int id, int index) =>
                    _cubit.ran(RemoveModifier(id: id, index: index)),
                onSetModifierField: _setModifierField,
                onAssignMaterial: _assignMaterial,
                onAddMaterial: _addMaterial,
                onSetMaterialField: _setMaterialField,
                onChooseTexture: _chooseTexture,
                onClearTexture: _clearTexture,
                onAddTextureNode: _addTextureNode,
                onLinkTextureNode: _linkTextureNode,
                onUnlinkTextureNode: _unlinkTextureNode,
                onSetTextureNodeField: _setTextureNodeField,
                onMoveTextureNode: _moveTextureNode,
                onRemoveTextureNode: _removeTextureNode,
                onBakeTextureGraph: _bakeTextureGraph,
                onAddClip: _addClip,
                selectedAnimationClip: _animationClip,
                onSelectAnimationClip: _selectAnimationClip,
                selectedJoint: _selectedJoint,
                onSelectJoint: _selectAnimationJoint,
                selectedConstraint: _selectedConstraint,
                onSelectConstraint: _selectAnimationConstraint,
                weightBrushMode: paintWeightsModeOf(state.tool),
                onWeightBrushModeChanged: _setWeightBrushMode,
                weightBrushRadius: _weightBrushRadius,
                onWeightBrushRadiusChanged: _setWeightBrushRadius,
                weightBrushStrength: _weightBrushStrength,
                onWeightBrushStrengthChanged: _setWeightBrushStrength,
                weightMirror: _weightMirror,
                onWeightMirrorChanged: _setWeightMirror,
                weightNormalize: _weightNormalize,
                onWeightNormalizeChanged: _setWeightNormalize,
                selectedWeightVertex: _selectedWeightVertex,
                hasShapeKeyAtCurrentFrame: hasShapeKeyAtCurrentFrame,
                onSetShapeWeight: _setShapeWeight,
                onKeyShape: _keyShape,
                selectedShape: _selectedShape,
                onSelectShape: _selectShape,
                onAddShapeDriver: _addShapeDriver,
                onRemoveShapeDriver: _removeShapeDriver,
                onSetShapeDriverField: _setShapeDriverField,
                retargetSourceNames: _retargetSourceNames,
                retargetBoneMap: _retargetBoneMap,
                onRetargetAutoMap: _autoMapRetarget,
                retargetRootMotion: _retargetRootMotion,
                onRetargetRootMotionChanged: _setRetargetRootMotion,
                retargetLockFeet: _retargetLockFeet,
                onRetargetLockFeetChanged: _setRetargetLockFeet,
                retargetGroundY: _retargetGroundY,
                onRetargetGroundYChanged: _setRetargetGroundY,
                retargetFootTolerance: _retargetFootTolerance,
                onRetargetFootToleranceChanged: _setRetargetFootTolerance,
                canApplyRetarget: _retargetCanApply,
                onApplyRetarget: _retargetCanApply
                    ? () => unawaited(_applyRetarget())
                    : null,
                selectedLight: _selectedLight,
                onSelectLight: _selectLight,
                onAddLight: _addLight,
                onRemoveLight: _removeLight,
                onLightTypeChanged: _setLightType,
                onLightIntensityChanged: _setLightIntensity,
                onLightRangeChanged: _setLightRange,
                onLightShadowChanged: _setLightShadow,
                onLightConeChanged: _setLightCone,
                onSceneShadowsChanged: _setSceneShadows,
                onEnvironmentChanged: _setEnvironment,
                onAmbientChanged: _setAmbient,
                onBloomChanged: _setBloom,
                onExposureChanged: _setExposure,
                // `ux-16`'s own three.
                onSelectElements: (ElementLevel level, List<int> ids) =>
                    setState(() {
                      _history.selection = _history.selection.copyWith(
                        mode: SelectionMode.mesh,
                        level: level,
                        elements: ids,
                      );
                      _cubit.say(null);
                    }),
                onFixMesh: _ranTool,
                onBuildTopology: (int id) => _cubit.ran(BuildTopology(id: id)),
                // `ux-14`'s own four.
                onPickObject: _pickedInOutliner,
                onObjectVisible: (int id, bool to) =>
                    _cubit.ran(SetObjectVisible(id: id, to: to)),
                onObjectLocked: (int id, bool to) =>
                    _cubit.ran(SetObjectLocked(id: id, to: to)),
                onReparent: (int id, int? to) =>
                    _cubit.ran(SetParent(id: id, to: to)),
                lastCommand: state.history.journal.isEmpty
                    ? null
                    : state.history.journal.last,
                onAmend: _amend,
                shading: _shading,
                onShading: (ShadingMode mode) =>
                    setState(() => _shading = mode),
                lens: _lens,
                onLens: (ViewLens lens) => setState(() => _lens = lens),
                onView: (StandardView view) => lookFrom(stage.orbit, view),
              );
              // `S5`'s own row: the weights sub-mode's own view — the brush
              // routes to `InputPolicy` rather than the drag/box branches,
              // the picture draws unlit through the vertex-colour gradient
              // `weight_gradient.dart` overwrites after every stroke, and the
              // legend pins to the corner the same way `MeasurementReportOverlay`
              // already does.
              final bool weightsView =
                  state.mode == ModelerMode.animation &&
                  state.animationSubmode == AnimationSubmode.weights;
              // Narrower than [weightsView]: `weights.mirror`/`weights.
              // normalize` are one-shot actions, not a stroke tool
              // (`kStrokeTools`'s own doc comment) — armed, a drag in the
              // viewport is still the camera, the same as any other mode
              // with no stroke tool of its own.
              final bool weightsBrushArmed =
                  weightsView && kStrokeTools.contains(state.tool);
              // `S6`'s own row: the morphs sub-mode's own shape markers —
              // one per shape key, in world space, `secondary` for whichever
              // one `MorphsPanel` has selected. No live deformation: only
              // these markers move, never the mesh underneath them — see
              // `shape_points_overlay.dart`'s own class comment for why.
              final bool morphsView =
                  state.mode == ModelerMode.animation &&
                  state.animationSubmode == AnimationSubmode.morphs;
              // `S7`'s own row: screen 14 replaces the ordinary single
              // viewport wholesale with the library and the source/target
              // pair — `_retargetViewport`'s own doc comment says why a
              // second `Stack` branch is the shape of that rather than one
              // more overlay layered onto the viewport below.
              final bool retargetView =
                  state.mode == ModelerMode.animation &&
                  state.animationSubmode == AnimationSubmode.retarget;
              final List<ShapeMarker> shapeMarkers =
                  !morphsView || forStatus == null
                  ? const <ShapeMarker>[]
                  : <ShapeMarker>[
                      for (var i = 0; i < forStatus.shapeSet.keys.length; i++)
                        (
                          position:
                              worldTransformOf(
                                state.project,
                                forStatus.id,
                              ).transformed3(
                                shapePointOf(forStatus.shapeSet.keys[i]),
                              ),
                          active: i == _selectedShape,
                        ),
                    ];
              // The outline is the renderer's until the overlay draws the
              // selection itself and can say which *part* of an object is
              // selected. Until then this is what tells a person their click
              // landed.
              // `tut-07`'s own fix: exposure, the shadow request and the
              // bloom toggle now come from `project.lighting` the same way
              // `stage.lighting.sync` already folded the lights themselves
              // into the scene — see `LightingSync.apply`'s own doc comment
              // for what is (and, on purpose, is not yet) carried across.
              final RenderSettings viewportRenderSettings =
                  (stage.lighting ?? LightingSync()).apply(
                    RenderSettings(
                      highlighted: <SceneNode>[
                        for (final int id in _history.selection.objects)
                          if (stage.sync?.nodeOf(id) case final SceneNode n) n,
                      ],
                      // `view-27d`'s own row: the octahedra-and-crosses
                      // overlay `DebugDrawGizmos.addSkeletonOverlay` draws is
                      // what shows a rig is actually driving the mesh
                      // underneath it, so it is worth the extra lines
                      // exactly while animation mode is open and not
                      // otherwise.
                      debug: DebugDrawOptions(
                        skeletons: _mode == ModelerMode.animation,
                      ),
                    ),
                    state.project.lighting,
                  );
              final viewport = retargetView
                  ? _retargetViewport(state)
                  : Stack(
                      children: <Widget>[
                        Positioned.fill(
                          child: ModelerViewport(
                            renderer: renderer,
                            stage: stage,
                            onFrame: () {},
                            onRendered: (FrameResult result) =>
                                _lastRenderMicros = result.cpuMicros,
                            onViewportMetrics:
                                (int width, int height, double dpr) {
                                  // `ux-29`: a value drag started from the
                                  // keyboard needs the same pixel size a
                                  // pointer drag measures with, and this is
                                  // the one place the screen is told it.
                                  _viewportHeight = height / dpr;
                                  unawaited(
                                    _reopenDeviceIfStale(width, height, dpr),
                                  );
                                },
                            // One or the other, never both: a click in the mesh mode is a
                            // question about this mesh's elements and is answered on the
                            // CPU, and asking the renderer for a node as well would cost a
                            // whole frame to answer a question nobody asked.
                            onPick: _mode == ModelerMode.mesh ? null : _picked,
                            onElementPick:
                                _mode == ModelerMode.mesh && _editMesh != null
                                ? _pickedElement
                                : null,
                            // `ux-28`: the same question a click asks, asked
                            // while nothing is pressed, so the answer can be
                            // shown before the click rather than after it.
                            onElementHover:
                                _mode == ModelerMode.mesh && _editMesh != null
                                ? _hoveredElement
                                : null,
                            hovered: _mode == ModelerMode.mesh
                                ? _hoveredElements
                                : null,
                            // `ux-26`: while the right button is held the
                            // strip says the buttons mean something else.
                            onLookingChanged: (bool looking) =>
                                setState(() => _lookingAround = looking),
                            // One or the other: with a transform tool armed a left drag is
                            // the transform, and with none it is a rectangle. A viewport
                            // that offered both would have to guess, and the guess would be
                            // wrong on the frame a person changed their mind.
                            // `ux-29`: an extrusion or a bevel takes the drag
                            // ahead of a transform, because while one is open
                            // it is the thing the pointer is driving — and it
                            // wants only the delta, not the view a transform
                            // needs to cast a ray through.
                            onDragTool: _transformSession.valueDrag != null
                                ? (
                                    Offset delta,
                                    double _,
                                    PickingView _,
                                    Offset _,
                                  ) => setState(
                                    () => _transformSession.valueDragged(delta),
                                  )
                                : kDragTools.contains(_tool)
                                ? _transformSession.dragged
                                : null,
                            onDragDone: _transformSession.endDrag,
                            // `ux-11`: under the modal preset the transform is
                            // already running by the time the pointer moves,
                            // so the hover drives it and the buttons answer
                            // it. The readout goes beside the pointer either
                            // way — a drag started from a button wants it as
                            // much as one started from a key.
                            // `ux-29`: a value drag is always pointer-driven —
                            // it opens on a key press with nothing held, the
                            // same shape `ux-11`'s modal preset gives a
                            // transform, so the hover drives it and the
                            // buttons answer it.
                            toolFollowsPointer:
                                _transformSession.valueDrag != null ||
                                _transformSession.followsPointer,
                            onToolConfirm: () => setState(() {
                              _transformSession
                                ..commitValueDrag()
                                ..commit();
                            }),
                            onToolCancel: () => setState(() {
                              _transformSession
                                ..cancelValueDrag()
                                ..cancel();
                            }),
                            transformReadout:
                                _transformSession.valueDrag?.readout ??
                                _transformSession.modal?.readout,
                            transformHints:
                                _transformSession.valueDrag?.hints ??
                                _transformSession.modal?.hints,
                            transformAxis: _transformSession.modal?.axis,
                            // `ux-25`: the same tools, where the pointer is.
                            onContextMenu: (Offset at) =>
                                unawaited(_showViewportMenu(at)),
                            onBox: _boxed,
                            // `ux-28`: the same drag, catching what a loop
                            // encloses rather than what a rectangle does.
                            lassoSelect: _tool == 'mesh.lasso',
                            // Earlier and more specific than the box/drag branch
                            // above: only set while `weights.paint`/`weights.assign`
                            // is actually armed, so `InputPolicy` never even asks
                            // about a pointer anywhere else — including the
                            // weights sub-mode's own one-shot mirror/normalize
                            // tools, which take no drag at all.
                            // `ux-24`: how far the brush reaches, drawn where
                            // the pointer is. Only while one is actually
                            // armed — a circle following the pointer in
                            // object mode would be a control for nothing.
                            brushRadius: weightsBrushArmed
                                ? _weightBrushRadius
                                : null,
                            brushInverting:
                                HardwareKeyboard.instance.isControlPressed,
                            strokeTool: weightsBrushArmed
                                ? ToolCategory.weightPainting
                                : null,
                            onStroke: weightsBrushArmed
                                ? _onWeightStroke
                                : null,
                            // The gizmo stands on the selection and offers the transform
                            // the armed tool asks for. On a tablet it is the only way in:
                            // there is no `G` key on an iPad, so this is not a second path
                            // to the same place — on three of the five platforms phase 1
                            // ships to it is the path.
                            gizmoPivot: _transformSession.gizmoPivot,
                            gizmoKind: _transformSession.gizmoKind,
                            // `ux-04`: whichever scheme Settings holds.
                            navigation: _settings.navigation,
                            onGizmoDrag: _transformSession.grabbedGizmo,
                            snapHighlight:
                                _transformSession.snapTarget?.position,
                            editMesh: _mode == ModelerMode.mesh
                                ? _editMesh
                                : null,
                            elements: _history.selection.asMeshSelection,
                            meshVersion:
                                _history
                                    .project[_history.selection.activeObject ??
                                        -1]
                                    ?.version ??
                                0,
                            elementsVersion: _history.selection.elements.length,
                            shapeMarkers: shapeMarkers,
                            shapeMarkerColour: shapeMarkers.isEmpty
                                ? null
                                : colourAsVector4(kModelerScheme.primary),
                            shapeMarkerActiveColour: shapeMarkers.isEmpty
                                ? null
                                : colourAsVector4(kModelerScheme.secondary),
                            settings: weightsView
                                ? weightGradientSettings(
                                    settingsFor(
                                      _shading,
                                      viewportRenderSettings,
                                    ),
                                  )
                                : settingsFor(_shading, viewportRenderSettings),
                          ),
                        ),
                        // `ux-16`: mesh mode on something that has no mesh.
                        // **A banner over the picture rather than a refusal
                        // in the status line**: the viewport is otherwise
                        // empty of everything mesh mode draws — no
                        // wireframe, no handles — and the review found
                        // people taking that for a broken window rather
                        // than for a shape that has not been converted.
                        if (_mode == ModelerMode.mesh && _editMesh == null)
                          Positioned(
                            left: 12,
                            top: 12,
                            child: NoMeshBanner(
                              object: state
                                  .project[state.selection.activeObject ?? -1],
                              onConvert: _ranTool,
                              onBuildTopology: (int id) =>
                                  _cubit.ran(BuildTopology(id: id)),
                            ),
                          ),
                        Positioned(
                          right: 12,
                          bottom: 12,
                          child: OrientationDial(
                            yaw: stage.orbit.yaw,
                            pitch: stage.orbit.pitch,
                            onPressed: (ViewAxis axis) {
                              // The dial says where; the controller does the turning, and
                              // takes the short way round because `viewAlong` already chose
                              // the turn nearest the yaw the camera is at.
                              final view = const OrientationGizmo().viewAlong(
                                axis,
                                fromYaw: stage.orbit.yaw,
                              );
                              stage.orbit.animateTo(
                                yaw: view.yaw,
                                pitch: view.pitch,
                              );
                            },
                          ),
                        ),
                        if (weightsView) const WeightLegend(),
                        if (_report case final String said)
                          MeasurementReportOverlay(said: said),
                      ],
                    );

              void onMode(ModelerMode mode) {
                // `ui-40d`'s own row: the animation mode's own tools depend
                // on the remembered sub-mode, the same as the rail already
                // reads `state.animationSubmode` for it.
                final tools = toolsFor(mode, animation: state.animationSubmode);
                _cubit
                  ..mode(mode)
                  // The armed tool belongs to the mode it came from, so a mode change
                  // arms that mode's pointer rather than leaving a tool id from the
                  // old one that nothing here would recognise.
                  ..tool(tools.isEmpty ? null : tools.first.id);
              }

              // `S2`'s own row: the pose sub-mode's own bottom slot —
              // `ui-41d`'s 270-tall region under the viewport — is the
              // transport bar plus the `Keys`/`Curves` toggle's own choice
              // of `TimelinePanel`/`CurveEditor`. `S5`'s own row: the weights
              // sub-mode's own bottom slot is `BendSliderBar`, 74 tall —
              // `_weightBottom`'s own doc comment. Every other mode leaves
              // `bottom` null, the same "nothing at all" `ModelerShell.bottom`'s
              // own doc comment already promises them.
              final bool showsTimeline =
                  state.mode == ModelerMode.animation &&
                  state.animationSubmode == AnimationSubmode.pose;
              final int? openClipIndex = _animationClip;
              final ProjectClip? openClip = openClipIndex == null
                  ? null
                  : state.project.clips[openClipIndex];

              // `tut-16`'s own row: screen 26's own panel and contact
              // sheet, shown whenever this build was launched with
              // `--mcp-port` — the same flag `screen/files.dart`'s own
              // `startMcpServer` call already gates on, so the panel is on
              // screen exactly while a real session is reachable through
              // it. `bottom`'s own three other claimants below all win
              // over it: a person mid-pose/weights/retarget still gets
              // that mode's own lower area, agent session or not.
              // `ux-05`: an open port is not an agent, and an agent is not
              // a panel. Nothing agent-shaped is on screen until a client
              // has said hello, and the panel itself waits for the badge to
              // be tapped.
              final String? agentClient = state.agentClient;
              final bool agentPanelOpen =
                  agentClient != null && _agentPanelOpen;

              final Keymap keymap = keymapFor(
                _settings.keymap,
                apple:
                    Theme.of(context).platform == TargetPlatform.macOS ||
                    Theme.of(context).platform == TargetPlatform.iOS,
              );
              return ShellForWidth(
                parts: ScreenParts(
                  actions: actions,
                  status: status,
                  properties: properties,
                  viewport: viewport,
                ),
                mode: state.mode,
                onMode: onMode,
                // `ux-37`: Essential offers three modes, Full five. The
                // state carries it so the switcher, the keyboard and an
                // agent's own `ui.setMode` cannot disagree about which.
                workspace: state.workspace,
                submode: state.submode,
                onSubmode: _cubit.submode,
                animationSubmode: state.animationSubmode,
                onAnimationSubmode: _setAnimationSubmode,
                activeTool: state.tool,
                onTool: _ranTool,
                documentName: state.documentName,
                isDirty: state.history.isDirty,
                keymap: keymap,
                // `ux-27`: the width is the person's own and is remembered;
                // the two folds are this session's, since a window that
                // opened with its panels hidden would be a window somebody
                // has to find the keys to get back.
                propertiesWidth: _settings.propertiesWidth,
                onPropertiesWidth: (double to) => setState(() {
                  _settings = _settings.copyWith(propertiesWidth: to);
                  _settingsStore.write(_settings);
                }),
                foldedPanel: _foldedPanel,
                foldedRail: _foldedRail,
                // `ux-23`: the lights, in the mode that is about them. The
                // panel lists them too — it has room for their settings —
                // but a mode whose rail is empty reads as a mode with
                // nothing in it.
                railExtras: _mode == ModelerMode.scene
                    ? <RailEntry>[
                        for (
                          var at = 0;
                          at < state.project.lighting.lights.length;
                          at++
                        )
                          (
                            label:
                                'Light ${at + 1} · '
                                '${state.project.lighting.lights[at].type.name}',
                            // `ProjectLightType` is a class with three const
                            // members rather than an enum, so this reads the
                            // name it carries — the same string the label
                            // above already shows.
                            icon: switch (state
                                .project
                                .lighting
                                .lights[at]
                                .type
                                .name) {
                              'point' => Icons.lightbulb_outline,
                              'spot' => Icons.highlight_outlined,
                              _ => Icons.wb_sunny_outlined,
                            },
                            armed: _selectedLight == at,
                            onPressed: () =>
                                setState(() => _selectedLight = at),
                          ),
                      ]
                    : const <RailEntry>[],
                agentPanel: agentPanelOpen
                    ? AgentSessionPanel(
                        calls: state.agentCalls,
                        history: state.history,
                        onUndoAgentSteps: _undoAgentSteps,
                        // `ux-45`: the person's own brake, read by the
                        // server's `pausedBecause` gate.
                        paused: _agentPaused,
                        onPaused: (bool to) =>
                            setState(() => _agentPaused = to),
                        clientName: agentClient,
                        onClose: () => setState(() => _agentPanelOpen = false),
                      )
                    : null,
                // `ux-26`: the console takes the lower area when it is open,
                // over whatever the mode would otherwise put there. **Over
                // rather than beside**: the timeline, the bend bar and the
                // retarget tracks are each the thing that mode is for, and a
                // window that tried to show one of them and the console at
                // once would show too little of both. Opening the console is
                // a deliberate "what did it just say", and closing it puts
                // the mode's own area straight back.
                bottom: _consoleOpen
                    ? ConsolePanel(
                        log: _cubit.console,
                        onClose: () => setState(() => _consoleOpen = false),
                      )
                    : showsTimeline
                    ? AnimationBottom(
                        clipIndex: openClipIndex,
                        clip: openClip,
                        frame: _frame,
                        fps: state.project.profile.fps,
                        playback: state.playback,
                        editMode: _timelineEditMode,
                        onEditMode: _setTimelineEditMode,
                        onPlayPause: _toggleAnimationPlayback,
                        onLoopChanged: _setAnimationLoop,
                        onSpeedChanged: _setAnimationSpeed,
                        selectedTrack: _selectedAnimationTrack,
                        selectedKey: _selectedAnimationKey,
                        onMoveKeys: _moveKeys,
                        onSeek: _scrubAnimation,
                        onSelectKey: _selectAnimationTrackKey,
                        onSetKey: _setAnimationKey,
                        onSetKeyValue: _setAnimationKeyValue,
                        onSetTangent: _setAnimationTangent,
                      )
                    : weightsView
                    ? _weightBottom(state)
                    : retargetView
                    ? _retargetBottom()
                    : null,
                bottomHeight: _consoleOpen
                    ? kConsoleHeight
                    : showsTimeline
                    ? ModelerMetrics.timeline
                    : weightsView
                    ? ModelerMetrics.bendBar
                    : retargetView
                    ? ModelerMetrics.retargetTracksBar
                    : null,
              );
            },
          ),
        ),
      ),
    ),
  };

  /// Opens [folder] in whatever this desktop shows folders with — `ux-01`'s
  /// own "Show folder" beside the autosave warning.
  ///
  /// A `file:` URI through `url_launcher`, the same door the crash dialog's
  /// own "Report a problem" already uses, rather than a `Process.run('open')`
  /// that would be macOS's alone and would be refused by the sandbox besides.
  void _showAutosaveFolder(String folder) =>
      unawaited(launchUrl(Uri.directory(folder)));
}
