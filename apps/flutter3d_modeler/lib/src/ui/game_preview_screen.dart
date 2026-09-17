/// Screen 19 — `S9`'s own full-screen "preview like in the game," closing
/// the app halves of `view-17` and `anim-24`.
///
/// **A route, not a mode.** Every other screen this app draws is a facet of
/// `ModelerMode` — Object, Mesh, Material, Animation, Scene — reached through
/// the same switcher and sharing the same properties rail. This is not one
/// of those: it replaces the whole window with a single picture, the
/// transport, a metrics card and the budget bars, and "leaving" it is a
/// `Navigator` pop rather than picking a different mode. `showGamePreview
/// Screen` pushes it as a full-screen `MaterialPageRoute`, opened from the
/// "Preview" entry `top_bar_actions.dart` puts beside Export rather than
/// from the mode switcher — the same distinction that entry's own doc
/// comment states.
///
/// **The same `Renderer`/`ModelerStage` as the editor, never a copy.** A
/// second `ModelerStage.fromProject` (the way `S7`'s retarget screen builds
/// its own source-and-target pair) would draw a snapshot rather than "the
/// model as it stands," and this screen exists to answer "what does the
/// document look like right now" — so it draws the live stage through a
/// second `ModelerViewport`, the same device the editor's own viewport
/// already uses, with different `RenderSettings` for the frames *this*
/// viewport asks for. Nothing about the document, the project or the stage
/// is written to here; only `GamePreviewSettings.applyTo` changes what one
/// more frame is drawn with. See that file's own class comment for why nothing
/// needs restoring once the route pops.
///
/// **This screen keeps its own [Ticker].** Orbiting the camera, and
/// `Playback.isPlaying` actually advancing a clip, both depend on *something*
/// calling `setState` every frame to make the freshly-moved camera or the
/// freshly-posed skeleton visible — `_ModelerScreenState`'s own `_onTick`
/// is exactly that for the editor, and it stops firing the moment this route
/// sits on top of it: `SingleTickerProviderStateMixin` mutes a widget's own
/// ticker for a route `Navigator` is not currently showing, which is exactly
/// what a screen full of nothing to look at should do to save the battery it
/// is not spending on a picture nobody sees. [onTick] is this screen's own
/// door for whatever the caller wants ticked alongside it — orbit damping,
/// `TimelinePreviewWiring.tick` — reusing the very same per-frame call the
/// editor's own ticker already makes rather than a second copy of it.
library;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart' hide Material;
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_model_core/flutter3d_model_core.dart'
    hide Key, Outcome;

import '../../../l10n/app_localizations.dart';
import '../game_preview_settings.dart';
import '../modeler_viewport.dart';
import '../scene_mode.dart';
import '../staging.dart';
import '../timeline_playback.dart';
import 'budget_bars.dart';
import 'metrics_overlay.dart';
import 'theme.dart';
import 'transport_bar.dart';

/// Opens screen 19 as a full-screen route over [context]'s own `Navigator`.
///
/// [baseSettings] is whatever `RenderSettings` the caller's own viewport
/// draws with — `LightingSync.apply`'s own output, the same way the main
/// viewport folds it in (`tut-07`'s own fix), so this preview's own
/// tonemap/shadows/sky sit on top of the document's real lighting rather
/// than a second default this screen invents.
Future<void> showGamePreviewScreen(
  BuildContext context, {
  required Renderer renderer,
  required ModelerStage stage,
  required ModelProject project,
  required ExportReadiness readiness,
  required RenderSettings baseSettings,
  required Playback playback,
  required ValueListenable<int> frame,
  required VoidCallback onPlayPause,
  ValueChanged<double>? onTick,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (BuildContext context) => GamePreviewScreen(
      renderer: renderer,
      stage: stage,
      project: project,
      readiness: readiness,
      baseSettings: baseSettings,
      playback: playback,
      frame: frame,
      onPlayPause: onPlayPause,
      onTick: onTick,
    ),
  ),
);

/// Screen 19 itself.
class GamePreviewScreen extends StatefulWidget {
  const GamePreviewScreen({
    super.key,
    required this.renderer,
    required this.stage,
    required this.project,
    required this.readiness,
    required this.baseSettings,
    required this.playback,
    required this.frame,
    required this.onPlayPause,
    this.onTick,
  });

  final Renderer renderer;
  final ModelerStage stage;
  final ModelProject project;
  final ExportReadiness readiness;
  final RenderSettings baseSettings;
  final Playback playback;
  final ValueListenable<int> frame;
  final VoidCallback onPlayPause;
  final ValueChanged<double>? onTick;

  @override
  State<GamePreviewScreen> createState() => _GamePreviewScreenState();
}

class _GamePreviewScreenState extends State<GamePreviewScreen>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  double _fps = 0;

  /// The last frame this screen's own viewport drew — read by [build] on the
  /// *next* tick, never written to during a build the way
  /// `_ModelerScreenState._lastRenderMicros` already is not: `onRendered`
  /// fires from inside `ModelerViewport`'s own `LayoutBuilder`, which is to
  /// say from inside this widget's own build, and `setState` is not legal
  /// there.
  FrameResult? _lastFrame;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
  }

  void _tick(Duration elapsed) {
    // The same clamp `_ModelerScreenState._onTick` applies, and for the same
    // reason: the first tick is measured from zero, and a route that sat
    // muted for a while before this screen closed comes back with a gap
    // `orbit.advance`/`TimelinePreviewWiring.tick` would otherwise read as a
    // multi-second leap.
    final double seconds = ((elapsed - _lastTick).inMicroseconds / 1e6).clamp(
      0.0,
      0.1,
    );
    _lastTick = elapsed;
    widget.onTick?.call(seconds);
    if (seconds > 0) _fps = 1 / seconds;
    setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ProfileBudgetReport report = ProfileBudgetReport.of(widget.project);
    final AppLocalizations l = AppLocalizations.of(context);
    final GamePreviewSettings preview = GamePreviewSettings.forProfile(
      widget.project.profile,
    );
    final List<ExportIssue> rig = rigIssues(
      widget.project,
      widget.project.profile,
    );
    // `lightOverflowOf`, the same pure count `properties_panel.dart` already
    // reads for `SceneShadowsPanel`'s own status — not this screen's own
    // `_lastFrame.lightsDropped`, which would always read zero: nothing in
    // this application yet threads `project.lighting.lights` into the
    // scene's own `LightNode`s (`LightingSync.sync`'s own doc comment), so a
    // real frame drops none of them for the plain reason that none of them
    // were ever there to drop.
    final SceneStatus scene = computeSceneStatus(
      lights: widget.project.lighting.lights,
      lightsDropped: lightOverflowOf(widget.project.lighting),
    );

    return Scaffold(
      backgroundColor: ModelerColors.dark.viewport,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _TopBar(onClose: () => Navigator.of(context).pop()),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(
                    child: Stack(
                      children: <Widget>[
                        Positioned.fill(
                          child: ModelerViewport(
                            renderer: widget.renderer,
                            stage: widget.stage,
                            overlay: false,
                            onFrame: () {},
                            onRendered: (FrameResult result) =>
                                _lastFrame = result,
                            settings: preview.applyTo(widget.baseSettings),
                          ),
                        ),
                        Positioned(
                          left: 12,
                          top: 12,
                          child: _WarningCard(
                            readiness: widget.readiness,
                            rigIssues: rig,
                            scene: scene,
                          ),
                        ),
                        Positioned(
                          right: 12,
                          top: 12,
                          child: MetricsOverlay(
                            fps: _fps,
                            drawCalls: _lastFrame?.drawCalls ?? 0,
                            triangles: _lastFrame?.triangles ?? 0,
                            bones: report.joints.used,
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: ColoredBox(
                            color: theme.colorScheme.surfaceContainerLowest
                                .withValues(alpha: 0.85),
                            child: SizedBox(
                              height: ModelerMetrics.transport,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: ValueListenableBuilder<int>(
                                    valueListenable: widget.frame,
                                    builder:
                                        (
                                          BuildContext context,
                                          int frameValue,
                                          Widget? _,
                                        ) => TransportBar.compact(
                                          playback: widget.playback,
                                          frame: frameValue,
                                          onPlayPause: widget.onPlayPause,
                                        ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: ModelerMetrics.propertiesMin,
                    color: theme.colorScheme.surfaceContainerLow,
                    padding: const EdgeInsets.all(16),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            l.previewBudgets,
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: 12),
                          BudgetBars(report: report),
                          const SizedBox(height: 20),
                          const _WireframeToggle(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final AppLocalizations l = AppLocalizations.of(context);
    return SizedBox(
      height: ModelerMetrics.topBar,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: <Widget>[
            Text(
              l.previewTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
            const Spacer(),
            MergeSemantics(
              child: Semantics(
                label: l.previewClose,
                button: true,
                child: IconButton(
                  tooltip: l.previewClose,
                  onPressed: onClose,
                  icon: const Icon(Icons.close),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `S9`'s own row: `rigIssues` plus [ExportReadiness] plus the same
/// `SceneStatus` `mat-24`'s status line already reads, in one card over the
/// viewport's own top-left corner — `measurement_report_overlay.dart`'s own
/// corner, kept apart from it since the two are never open at once (that
/// overlay is a mesh-mode measurement tool; this is screen 19).
class _WarningCard extends StatelessWidget {
  const _WarningCard({
    required this.readiness,
    required this.rigIssues,
    required this.scene,
  });

  final ExportReadiness readiness;
  final List<ExportIssue> rigIssues;
  final SceneStatus scene;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final AppLocalizations l = AppLocalizations.of(context);
    final bool warns =
        readiness.issues.isNotEmpty || rigIssues.isNotEmpty || scene.warning;
    final Color background = warns
        ? theme.colorScheme.tertiaryContainer
        : theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.9);
    final Color foreground = warns
        ? theme.colorScheme.onTertiaryContainer
        : theme.colorScheme.onSurfaceVariant;
    final TextStyle? style = theme.textTheme.bodySmall?.copyWith(
      color: foreground,
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(readiness.says, style: style),
              for (final ExportIssue issue in rigIssues.take(3))
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('· ${issue.message}', style: style),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  l.previewLights(
                    scene.lightCount,
                    scene.shadowedCount,
                    scene.shadowCap,
                  ),
                  style: style,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Показать каркас" — always off, always disabled: `S9`'s own honest gap.
/// `ProfileBudgetReport.wireframeDeclined`'s own doc comment says why —
/// `RenderShading` offers `material`/`normals` only, and no display mode in
/// this application ever asked the renderer for a wireframe pass. A control
/// that looked interactive and did nothing when pressed would be worse than
/// none at all, which is why this is a disabled [SwitchListTile] with a
/// reason attached rather than an enabled one wired to nothing.
class _WireframeToggle extends StatelessWidget {
  const _WireframeToggle();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: false,
      onChanged: null,
      title: Text(l.previewWireframe),
      subtitle: Text(l.previewNotBuilt),
    );
  }
}
