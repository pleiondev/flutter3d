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
  Widget _screen(ModelerState state) => switch (state) {
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
    ModelerReady(:final renderer, :final stage) => Title(
      title: windowTitleFor(isDirty: state.history.isDirty),
      color: Colors.black,
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
                  onSave: _saveFile,
                  onExport: _exportFile,
                  onMaterialStudio: () => unawaited(_openMaterialStudio()),
                  onShortcutHelp: _showShortcutHelp,
                  onStartScreen: () => unawaited(_showStartScreen()),
                  onReportProblem: _reportProblem,
                ),
              ];
              final ModelObject? forStatus =
                  state.project[state.selection.activeObject ?? -1];
              final status = StatusLine(
                // One sentence, carried by the state. There used to be two — one for
                // files and one for operations — with the operation's winning by
                // sitting first in a `??` chain, which meant a file that failed to
                // open said nothing at all if an operation had run before it.
                said: state.said ?? _selectionSaid,
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
              );
              final properties = PropertiesPanel(
                mode: state.mode,
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
                // Phase one's own stack has exactly one buildable kind — the
                // mirror `mesh-41` already gives it. `ui-08`'s own "Add" link
                // reaches for it directly rather than opening a picker with one
                // entry in it.
                onAddModifier: (int id) => _cubit.ran(
                  AddModifier(
                    id: id,
                    modifier: MirrorModifier(normal: vm.Vector3(1, 0, 0)),
                  ),
                ),
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
              final viewport = Stack(
                children: <Widget>[
                  Positioned.fill(
                    child: ModelerViewport(
                      renderer: renderer,
                      stage: stage,
                      onFrame: () {},
                      onRendered: (int micros) => _lastRenderMicros = micros,
                      onViewportMetrics: (int width, int height, double dpr) =>
                          unawaited(_reopenDeviceIfStale(width, height, dpr)),
                      // One or the other, never both: a click in the mesh mode is a
                      // question about this mesh's elements and is answered on the
                      // CPU, and asking the renderer for a node as well would cost a
                      // whole frame to answer a question nobody asked.
                      onPick: _mode == ModelerMode.mesh ? null : _picked,
                      onElementPick:
                          _mode == ModelerMode.mesh && _editMesh != null
                          ? _pickedElement
                          : null,
                      // One or the other: with a transform tool armed a left drag is
                      // the transform, and with none it is a rectangle. A viewport
                      // that offered both would have to guess, and the guess would be
                      // wrong on the frame a person changed their mind.
                      onDragTool: kDragTools.contains(_tool)
                          ? _transformSession.dragged
                          : null,
                      onDragDone: _transformSession.endDrag,
                      onBox: _boxed,
                      // The gizmo stands on the selection and offers the transform
                      // the armed tool asks for. On a tablet it is the only way in:
                      // there is no `G` key on an iPad, so this is not a second path
                      // to the same place — on three of the five platforms phase 1
                      // ships to it is the path.
                      gizmoPivot: _transformSession.gizmoPivot,
                      gizmoKind: _transformSession.gizmoKind,
                      onGizmoDrag: _transformSession.grabbedGizmo,
                      snapHighlight: _transformSession.snapTarget?.position,
                      editMesh: _mode == ModelerMode.mesh ? _editMesh : null,
                      elements: _history.selection.asMeshSelection,
                      meshVersion:
                          _history
                              .project[_history.selection.activeObject ?? -1]
                              ?.version ??
                          0,
                      elementsVersion: _history.selection.elements.length,
                      settings: settingsFor(
                        _shading,
                        // The outline is the renderer's until the overlay draws the
                        // selection itself and can say which *part* of an object is
                        // selected. Until then this is what tells a person their click
                        // landed.
                        RenderSettings(
                          highlighted: <SceneNode>[
                            for (final int id in _history.selection.objects)
                              if (stage.sync?.nodeOf(id) case final SceneNode n)
                                n,
                          ],
                        ),
                      ),
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
                        stage.orbit.animateTo(yaw: view.yaw, pitch: view.pitch);
                      },
                    ),
                  ),
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
              // of `TimelinePanel`/`CurveEditor`. Every other mode, and the
              // animation mode's other three sub-modes, leave `bottom` null,
              // the same "nothing at all" `ModelerShell.bottom`'s own doc
              // comment already promises them.
              final bool showsTimeline =
                  state.mode == ModelerMode.animation &&
                  state.animationSubmode == AnimationSubmode.pose;
              final int? openClipIndex = _animationClip;
              final ProjectClip? openClip = openClipIndex == null
                  ? null
                  : state.project.clips[openClipIndex];

              return ShellForWidth(
                parts: ScreenParts(
                  actions: actions,
                  status: status,
                  properties: properties,
                  viewport: viewport,
                ),
                mode: state.mode,
                onMode: onMode,
                submode: state.submode,
                onSubmode: _cubit.submode,
                animationSubmode: state.animationSubmode,
                onAnimationSubmode: _cubit.animationSubmode,
                activeTool: state.tool,
                onTool: _ranTool,
                documentName: state.documentName,
                isDirty: state.history.isDirty,
                bottom: !showsTimeline
                    ? null
                    : AnimationBottom(
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
                      ),
                bottomHeight: showsTimeline ? ModelerMetrics.timeline : null,
              );
            },
          ),
        ),
      ),
    ),
  };
}
