/// `_ModelerScreenState`'s own view-only screen: what a build compiled with
/// `--dart-define=FLUTTER3D_MODELER_MODE=viewer` shows instead of the
/// editor's three shells — see `app_config.dart`'s own [kViewerOnly].
///
/// **The same document, stage and renderer, with nothing that changes
/// them.** The model opens through the ordinary path, is drawn by the same
/// viewport, turned by the same orbit and lit by its own lighting; what is
/// left out is every tool, panel, key and menu that edits it, the autosave
/// and the save-back. A preview picture is still captured once the subject
/// is framed: that is `screen/files.dart`'s own `_capturePreviewIfAsked`,
/// which runs whichever screen is drawn.
// ignore_for_file: invalid_use_of_protected_member
part of 'modeler_screen.dart';

extension _ViewerParts on _ModelerScreenState {
  Widget _viewerScreen(ModelerReady state) {
    final ModelerStage stage = state.stage;
    final AppLocalizations l = AppLocalizations.of(context);
    final RenderSettings lit = (stage.lighting ?? LightingSync()).apply(
      const RenderSettings(),
      state.project.lighting,
    );
    return DocumentWindowTitle(
      name: state.documentName,
      isDirty: false,
      child: Scaffold(
        body: Column(
          children: <Widget>[
            ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainer,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    Text(
                      state.documentName,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    SegmentedButton<ShadingMode>(
                      showSelectedIcon: false,
                      segments: <ButtonSegment<ShadingMode>>[
                        ButtonSegment<ShadingMode>(
                          value: ShadingMode.material,
                          label: Text(l.propMaterial),
                        ),
                        ButtonSegment<ShadingMode>(
                          value: ShadingMode.normals,
                          label: Text(l.propNormals),
                        ),
                        ButtonSegment<ShadingMode>(
                          value: ShadingMode.wireframe,
                          label: Text(l.propWire),
                        ),
                      ],
                      selected: <ShadingMode>{_shading},
                      onSelectionChanged: (Set<ShadingMode> picked) =>
                          setState(() => _shading = picked.first),
                    ),
                    SegmentedButton<ViewLens>(
                      showSelectedIcon: false,
                      segments: <ButtonSegment<ViewLens>>[
                        ButtonSegment<ViewLens>(
                          value: ViewLens.perspective,
                          label: Text(l.propPerspective),
                        ),
                        ButtonSegment<ViewLens>(
                          value: ViewLens.orthographic,
                          label: Text(l.propOrthographic),
                        ),
                      ],
                      selected: <ViewLens>{_lens},
                      onSelectionChanged: (Set<ViewLens> picked) =>
                          setState(() => _lens = picked.first),
                    ),
                    IconButton(
                      tooltip: 'Frame the model',
                      icon: const Icon(Icons.center_focus_strong_outlined),
                      onPressed: () => setState(stage.frameSubject),
                    ),
                    Text(
                      '${state.project.triangleCount} triangles · '
                      '${state.project.materials.length} materials',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Stack(
                children: <Widget>[
                  Positioned.fill(
                    child: ListenableBuilder(
                      listenable: _viewportFrames,
                      builder: (BuildContext context, Widget? _) =>
                          ModelerViewport(
                            renderer: state.renderer,
                            stage: stage,
                            announcements: <SceneAnnouncement>[
                              SceneAnnouncement(
                                id: 'subject',
                                label: state.documentName,
                                node: stage.subject,
                              ),
                            ],
                            onFrame: () {},
                            onRendered: (FrameResult result) =>
                                _lastRenderMicros = result.cpuMicros,
                            onViewportMetrics:
                                (int width, int height, double dpr) {
                                  _viewportHeight = height / dpr;
                                  unawaited(
                                    _reopenDeviceIfStale(width, height, dpr),
                                  );
                                },
                            navigation: _settings.navigation,
                            settings: settingsFor(
                              _shading,
                              lit,
                              edgesDrawn: false,
                            ),
                          ),
                    ),
                  ),
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: ListenableBuilder(
                      listenable: _viewportFrames,
                      builder: (BuildContext context, Widget? _) =>
                          OrientationDial(
                            yaw: stage.orbit.yaw,
                            pitch: stage.orbit.pitch,
                            onPressed: (ViewAxis axis) {
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
                  ),
                  if (_report case final String said)
                    MeasurementReportOverlay(said: said),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
