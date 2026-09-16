/// Screen 16's own modal — `anim-23`'s app half: a second, throwaway
/// [ModelerStage.fromProject] with a frontal orthographic lens and a flat,
/// unlit silhouette, eight draggable markers over it, and the template/
/// composition/binding controls that turn them into a rig.
///
/// **A dialog, not a route or a sub-mode**, the same shape
/// `material_studio_dialog.dart`/`lathe_dialog.dart` already use for "the
/// application drawing a second [ModelerStage] on purpose" — see
/// `lathe_dialog.dart`'s own class comment for why sharing the document's
/// stage would be wrong here too: nothing a marker drag does should repaint
/// the model behind this dialog.
///
/// **No orbit, on purpose.** The frontal view is the one reference a rig
/// builder needs — see `autorig_markers.dart`'s own library comment for why
/// every marker's depth is fixed at the model's own centre — so this stacks
/// its own [GestureDetector] over a non-interactive [ModelerViewport]
/// (`overlay: false`, the same "read-only preview" shape
/// `retarget_viewports.dart` already uses) rather than letting a drag orbit
/// the camera out from under a marker.
library;

import 'dart:async';

import 'package:flutter/material.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' as engine show Material;
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:vector_math/vector_math.dart' show Aabb3, Vector3, Vector4;

import '../autorig_markers.dart';
import '../display_modes.dart';
import '../element_picking.dart';
import '../job_runner.dart';
import '../modeler_cubit.dart';
import '../modeler_viewport.dart';
import '../staging.dart';
import 'job_button.dart';
import 'roomy_dialog.dart';

/// Opens screen 16 for [skinObjectId] — the object every marker's own arm/
/// leg is scaled off of, and the one bound to the finished skeleton.
///
/// [project] is read once, at the moment this is called, for the preview
/// stage and the starting marker layout; the "Create" button reads
/// [cubit]'s own *current* project when it actually runs, so a background
/// job finishing while this dialog is open cannot make it act on a project
/// that has already moved on.
Future<void> showAutorigDialog(
  BuildContext context, {
  required ModelerCubit cubit,
  required Renderer renderer,
  required ModelProject project,
  required int skinObjectId,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (BuildContext context) => _AutorigDialog(
    cubit: cubit,
    renderer: renderer,
    project: project,
    skinObjectId: skinObjectId,
  ),
);

class _AutorigDialog extends StatefulWidget {
  const _AutorigDialog({
    required this.cubit,
    required this.renderer,
    required this.project,
    required this.skinObjectId,
  });

  final ModelerCubit cubit;
  final Renderer renderer;
  final ModelProject project;
  final int skinObjectId;

  @override
  State<_AutorigDialog> createState() => _AutorigDialogState();
}

class _AutorigDialogState extends State<_AutorigDialog> {
  late final ModelerStage _stage;
  late final Aabb3 _bounds;
  late final double _depthZ;

  RigTemplate _template = RigTemplate.humanoid;
  RigBuildOptions _options = const RigBuildOptions();
  bool _bindPrimaryWeights = true;
  bool _mirrorWeights = true;
  late Map<String, Vector3> _markers;
  String? _activeMarker;
  String? _error;

  /// The last size [ModelerViewport] laid out at — a `LayoutBuilder`'s own
  /// answer, kept so a gesture callback can build a [PickingView] without
  /// waiting for a rebuild to hand one in.
  Size _viewportSize = Size.zero;

  @override
  void initState() {
    super.initState();
    _stage = ModelerStage.fromProject(
      device: widget.renderer.device,
      project: widget.project,
    );
    _bounds =
        _stage.subjectBounds() ??
        Aabb3.minMax(Vector3.all(-1.0), Vector3.all(1.0));
    _depthZ = (_bounds.min.z + _bounds.max.z) / 2.0;
    _markers = startingMarkers(_template, _bounds);
    _stage.frameSubject();
    lookFrom(_stage.orbit, StandardView.front, seconds: 0.0);
    useLens(_stage.camera, ViewLens.orthographic, _stage.orbit);
    _paintDarkUnlit();
  }

  /// The design's own "dark unlit" silhouette: every mesh drawn flat, so a
  /// marker's own colour is the only thing on screen that reads as a
  /// highlight. A throwaway swap, unlike `SurfaceShading`'s own reversible
  /// one — this stage is discarded when the dialog closes, so there is
  /// nothing to put back.
  void _paintDarkUnlit() {
    final silhouette = engine.Material(
      name: 'autorigSilhouette',
      lighting: LightingModel.unlit,
      baseColor: Vector4(0.18, 0.20, 0.21, 1.0),
    );
    _stage.subject.traverse((SceneNode node) {
      if (node is MeshNode) node.material = silhouette;
    });
  }

  void _selectTemplate(RigTemplate template) {
    if (template == _template) return;
    setState(() {
      _template = template;
      _markers = startingMarkers(_template, _bounds);
      _activeMarker = null;
    });
  }

  PickingView? _pickingView() {
    if (_viewportSize.isEmpty) return null;
    return PickingView(camera: _stage.camera, size: _viewportSize);
  }

  /// The nearest on-screen marker to [at], within [_kMarkerHitRadius]
  /// logical pixels — null when nothing is close enough.
  String? _markerNear(Offset at, PickingView view) {
    String? nearest;
    double bestDistance = _kMarkerHitRadius;
    for (final String key in onScreenMarkerKeys(_template)) {
      final Vector3? world = _markers[key];
      if (world == null) continue;
      final Offset? screen = view.project(world);
      if (screen == null) continue;
      final double distance = (screen - at).distance;
      if (distance <= bestDistance) {
        bestDistance = distance;
        nearest = key;
      }
    }
    return nearest;
  }

  void _onPanStart(Offset at) {
    final PickingView? view = _pickingView();
    if (view == null) return;
    setState(() => _activeMarker = _markerNear(at, view));
  }

  void _onPanUpdate(Offset at) {
    final String? active = _activeMarker;
    final PickingView? view = _pickingView();
    if (active == null || view == null) return;
    setState(() => _markers[active] = markerFromScreen(view, at, _depthZ));
  }

  void _onPanEnd() => setState(() => _activeMarker = null);

  Future<void> _create(ModelerReady state) async {
    setState(() => _error = null);
    final Map<String, Vector3> markers = deriveMarkers(_template, _markers);
    final String? refused = await createRig(
      history: state.history,
      template: _template,
      markers: markers,
      options: _options,
      skinObjectId: widget.skinObjectId,
      bindPrimaryWeights: _bindPrimaryWeights,
      mirrorWeights: _mirrorWeights,
      bind: (BindWeightsJobRequest request) async {
        final outcome = await widget.cubit.runJob<JobResult>(
          JobKey.rig(widget.skinObjectId),
          request.run,
        );
        return outcome is JobFinished<JobResult> ? outcome.value : null;
      },
    );
    if (!mounted) return;
    if (refused != null) {
      setState(() => _error = refused);
      return;
    }
    widget.cubit.documentMoved(said: 'auto-rig built');
    Navigator.of(context).pop();
  }

  double? _progressOf(ModelerReady state) {
    final JobKey key = JobKey.rig(widget.skinObjectId);
    for (final ActiveJob job in state.jobs) {
      if (job.key == key) return job.progress;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final RigPreview preview = previewRig(_template, options: _options);
    return BlocBuilder<ModelerCubit, ModelerState>(
      bloc: widget.cubit,
      builder: (BuildContext context, ModelerState cubitState) {
        final ModelerReady? ready = cubitState is ModelerReady
            ? cubitState
            : null;
        return RoomyDialog(
          title: 'Auto-rig',
          width: 980,
          height: 720,
          onClose: () => Navigator.of(context).pop(),
          wide: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(child: _viewport(theme)),
              const VerticalDivider(width: 24),
              SizedBox(
                width: 300,
                child: SingleChildScrollView(
                  child: _rightPanel(theme, preview),
                ),
              ),
            ],
          ),
          // `ux-21`: the markers are dragged on the picture, so the picture
          // keeps the larger half of a narrow window and the options scroll
          // under it. The other way round would put the thing being dragged
          // in the smaller box.
          narrow: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(flex: 3, child: _viewport(theme)),
                const Divider(),
                Expanded(
                  flex: 2,
                  child: SingleChildScrollView(
                    child: _rightPanel(theme, preview),
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            JobButton(
              label: 'Create',
              progress: ready == null ? null : _progressOf(ready),
              onStart: ready == null ? () {} : () => unawaited(_create(ready)),
              onCancel: () =>
                  widget.cubit.cancelJob(JobKey.rig(widget.skinObjectId)),
            ),
          ],
        );
      },
    );
  }

  Widget _viewport(ThemeData theme) => ClipRect(
    child: LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        _viewportSize = constraints.biggest;
        final PickingView? view = _pickingView();
        final Map<String, Offset?> screenPositions = <String, Offset?>{
          for (final String key in onScreenMarkerKeys(_template))
            key: view == null || _markers[key] == null
                ? null
                : view.project(_markers[key]!),
        };
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            ModelerViewport(
              renderer: widget.renderer,
              stage: _stage,
              onFrame: () {},
              grid: null,
              overlay: false,
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _MarkerPainter(
                    positions: screenPositions,
                    connections: markerConnections(_template),
                    activeKey: _activeMarker,
                    ringColor: theme.colorScheme.primary,
                    activeColor: theme.colorScheme.secondary,
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (DragStartDetails details) =>
                    _onPanStart(details.localPosition),
                onPanUpdate: (DragUpdateDetails details) =>
                    _onPanUpdate(details.localPosition),
                onPanEnd: (_) => _onPanEnd(),
              ),
            ),
            Positioned(
              left: 12,
              top: 12,
              child: _badge(
                theme,
                'Markers ${onScreenMarkerKeys(_template).length} of '
                '${onScreenMarkerKeys(_template).length}',
              ),
            ),
            Positioned(
              left: 12,
              bottom: 12,
              child: _badge(theme, 'Drag a marker to refine the joint'),
            ),
          ],
        );
      },
    ),
  );

  Widget _badge(ThemeData theme, String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    ),
  );

  Widget _rightPanel(ThemeData theme, RigPreview preview) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text('Template', style: theme.textTheme.labelMedium),
      const SizedBox(height: 8),
      Wrap(
        spacing: 6,
        children: <Widget>[
          ChoiceChip(
            label: const Text('Humanoid'),
            selected: _template == RigTemplate.humanoid,
            onSelected: (_) => _selectTemplate(RigTemplate.humanoid),
          ),
          ChoiceChip(
            label: const Text('Quadruped'),
            selected: _template == RigTemplate.quadruped,
            onSelected: (_) => _selectTemplate(RigTemplate.quadruped),
          ),
          // Screen 16's own third chip — no `RigTemplate` behind it yet, the
          // same "shown, disabled, honest about not working" choice
          // `PivotChip.cursor` already makes in `display_modes.dart`.
          const ChoiceChip(label: Text('Custom'), selected: false),
        ],
      ),
      const SizedBox(height: 16),
      Text('Composition', style: theme.textTheme.labelMedium),
      const SizedBox(height: 8),
      if (_template == RigTemplate.humanoid) ...<Widget>[
        _twoWayRow(
          'Fingers',
          _options.fingers,
          (bool v) => setState(() => _options = _copyOptions(fingers: v)),
        ),
        _twoWayRow(
          'Toes',
          _options.toes,
          (bool v) => setState(() => _options = _copyOptions(toes: v)),
        ),
        Row(
          children: <Widget>[
            Text('Spine', style: theme.textTheme.bodySmall),
            const Spacer(),
            SegmentedButton<int>(
              showSelectedIcon: false,
              segments: const <ButtonSegment<int>>[
                ButtonSegment<int>(value: 1, label: Text('1')),
                ButtonSegment<int>(value: 2, label: Text('2')),
                ButtonSegment<int>(value: 3, label: Text('3')),
              ],
              selected: <int>{_options.spineCount},
              onSelectionChanged: (Set<int> picked) => setState(
                () => _options = _copyOptions(spineCount: picked.first),
              ),
            ),
          ],
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('Face bones'),
          value: _options.faceBones,
          onChanged: (bool? v) =>
              setState(() => _options = _copyOptions(faceBones: v ?? false)),
        ),
      ],
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        title: const Text('IK chains'),
        value: _options.ikChains,
        onChanged: (bool? v) =>
            setState(() => _options = _copyOptions(ikChains: v ?? false)),
      ),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        title: const Text('Rig controller'),
        value: _options.controllers,
        onChanged: (bool? v) =>
            setState(() => _options = _copyOptions(controllers: v ?? false)),
      ),
      const SizedBox(height: 16),
      Text('Binding', style: theme.textTheme.labelMedium),
      const SizedBox(height: 8),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        title: const Text('Assign primary weights'),
        value: _bindPrimaryWeights,
        onChanged: (bool? v) => setState(() => _bindPrimaryWeights = v ?? true),
      ),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        enabled: _bindPrimaryWeights,
        title: const Text('Symmetry'),
        value: _mirrorWeights,
        onChanged: !_bindPrimaryWeights
            ? null
            : (bool? v) => setState(() => _mirrorWeights = v ?? true),
      ),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _labelValue(theme, 'Bones', '${preview.jointCount}'),
            const SizedBox(height: 6),
            _labelValue(theme, 'Deforming', '${preview.deformingCount}'),
          ],
        ),
      ),
    ],
  );

  Widget _labelValue(ThemeData theme, String label, String value) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: <Widget>[
      Text(label, style: theme.textTheme.bodySmall),
      Text(value, style: theme.textTheme.bodyMedium),
    ],
  );

  Widget _twoWayRow(String label, bool value, ValueChanged<bool> onChanged) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: <Widget>[
            Expanded(child: Text(label)),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const <ButtonSegment<bool>>[
                ButtonSegment<bool>(value: false, label: Text('None')),
                ButtonSegment<bool>(value: true, label: Text('5')),
              ],
              selected: <bool>{value},
              onSelectionChanged: (Set<bool> picked) => onChanged(picked.first),
            ),
          ],
        ),
      );

  RigBuildOptions _copyOptions({
    int? spineCount,
    bool? fingers,
    bool? toes,
    bool? faceBones,
    bool? ikChains,
    bool? controllers,
  }) => RigBuildOptions(
    mirrorAxis: _options.mirrorAxis,
    spineCount: spineCount ?? _options.spineCount,
    fingers: fingers ?? _options.fingers,
    toes: toes ?? _options.toes,
    faceBones: faceBones ?? _options.faceBones,
    ikChains: ikChains ?? _options.ikChains,
    controllers: controllers ?? _options.controllers,
  );
}

/// A marker's own on-screen hit radius, in logical pixels — generous enough
/// for a mouse without a `pointer` kind to size it from the way
/// `pickSlackFor` does, since only a mouse or a trackpad ever drives this
/// dialog (macOS + web, per this track's own owner decision).
const double _kMarkerHitRadius = 18.0;

/// Draws every marker [positions] names — ⌀16, [ringColor] at 3px normally,
/// solid [activeColor] for [activeKey] — with a dotted line between every
/// pair [connections] names, the design hand-over's own screen 16.
class _MarkerPainter extends CustomPainter {
  const _MarkerPainter({
    required this.positions,
    required this.connections,
    required this.activeKey,
    required this.ringColor,
    required this.activeColor,
  });

  final Map<String, Offset?> positions;
  final List<(String, String)> connections;
  final String? activeKey;
  final Color ringColor;
  final Color activeColor;

  static const double _radius = 8.0;
  static const double _dash = 6.0;
  static const double _gap = 5.0;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint linePaint = Paint()
      ..color = ringColor
      ..strokeWidth = 2;
    for (final (String from, String to) in connections) {
      final Offset? a = positions[from];
      final Offset? b = positions[to];
      if (a == null || b == null) continue;
      _dashedLine(canvas, a, b, linePaint);
    }

    for (final MapEntry<String, Offset?> entry in positions.entries) {
      final Offset? at = entry.value;
      if (at == null) continue;
      final bool active = entry.key == activeKey;
      final Paint paint = Paint()..color = active ? activeColor : ringColor;
      if (active) {
        paint.style = PaintingStyle.fill;
        canvas.drawCircle(at, _radius, paint);
      } else {
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3;
        canvas.drawCircle(at, _radius, paint);
      }
    }
  }

  void _dashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    final double total = (b - a).distance;
    if (total <= 0) return;
    final Offset direction = (b - a) / total;
    var drawn = 0.0;
    while (drawn < total) {
      final double next = (drawn + _dash).clamp(0.0, total);
      canvas.drawLine(a + direction * drawn, a + direction * next, paint);
      drawn = next + _gap;
    }
  }

  @override
  bool shouldRepaint(covariant _MarkerPainter oldDelegate) =>
      oldDelegate.positions != positions ||
      oldDelegate.activeKey != activeKey ||
      oldDelegate.ringColor != ringColor ||
      oldDelegate.activeColor != activeColor;
}
