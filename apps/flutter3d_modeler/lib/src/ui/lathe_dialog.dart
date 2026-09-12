/// `ui-13`'s own modal — the design hand-over's screen 09, "Тело вращения":
/// `profile_editor.dart` on the left, a second live `RenderView` on the
/// right updated on every edit, and the segment count and summary between
/// them.
///
/// **A dialog, not a route**, the same shape `export_screen.dart`'s own doc
/// comment already commits to for exactly this row.
///
/// **The stage is this dialog's own, not the document's.** `ModelerStage`'s
/// own doc comment says `no test builds its own world`, which is about a
/// *test* standing up a scene the application never draws — this is the
/// application drawing a second one on purpose, the way its own doc comment
/// names as the very next thing `SceneSurface` cannot do ("a material
/// preview beside it later"). Sharing the document's [ModelerStage] would
/// mean every edit to a draft profile repainted the model behind this
/// dialog too.
library;

import 'package:flutter/material.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:vector_math/vector_math.dart' show Vector2;

import '../modeler_viewport.dart';
import '../profile_editing.dart';
import '../staging.dart';
import 'profile_editor.dart';

/// What the dialog hands back when confirmed — [AddLathe]'s own two
/// user-facing fields, read off the profile authored inside.
final class LatheChoice {
  const LatheChoice({required this.profile, required this.segments, required this.closedProfile});

  final List<Vector2> profile;
  final int segments;
  final bool closedProfile;
}

/// The profile a new lathe opens with — a plain cylinder wall, the shape
/// nearest to [AddPrimitive]'s own default box: recognisable before a
/// single point has been touched, and every one of its four points and
/// three segments is already something `Point`, `Curve` and `Axis` can act
/// on immediately.
ProfileCurve _startingProfile() => ProfileCurve(
  points: <ProfilePoint>[
    ProfilePoint(Vector2(0, -60)),
    ProfilePoint(Vector2(40, -60)),
    ProfilePoint(Vector2(40, 60)),
    ProfilePoint(Vector2(0, 60)),
  ],
  segments: const <ProfileSegment>[
    LineSegment(),
    LineSegment(),
    LineSegment(),
  ],
);

/// Opens `ui-13`'s own lathe dialog, drawing its live preview through
/// [renderer] — the same one the viewport behind it already uses, so the
/// preview costs a second scene and camera, not a second device.
Future<LatheChoice?> showLatheDialog(
  BuildContext context, {
  required Renderer renderer,
}) => showDialog<LatheChoice>(
  context: context,
  builder: (BuildContext context) => _LatheDialog(renderer: renderer),
);

class _LatheDialog extends StatefulWidget {
  const _LatheDialog({required this.renderer});

  final Renderer renderer;

  @override
  State<_LatheDialog> createState() => _LatheDialogState();
}

class _LatheDialogState extends State<_LatheDialog> {
  ProfileCurve _curve = _startingProfile();
  ProfileEditTool _tool = ProfileEditTool.point;
  int _segments = 24;
  bool _closedProfile = false;

  late final ModelerStage _stage;
  MeshData? _lastMesh;

  @override
  void initState() {
    super.initState();
    _stage = ModelerStage.build(device: widget.renderer.device);
    _rebuildPreview();
  }

  /// Turns the authored [_curve] into the polyline `AddLathe`/[LatheShape]
  /// take, and redraws the preview stage's own subject with it — screen
  /// 09's own "вьюпорт с результатом, обновляемым немедленно."
  void _rebuildPreview() {
    final polyline = _curve.toPolyline();
    if (polyline.length < 2) {
      _lastMesh = null;
      return;
    }
    final mesh = ParametricLathe(
      profile: polyline,
      segments: _segments,
      closedProfile: _closedProfile,
    ).toEditMesh().toMeshData();
    _lastMesh = mesh;
    (_stage.subject as MeshNode).mesh = DeviceMesh.upload(
      widget.renderer.device,
      mesh,
    );
    _stage.frameSubject();
  }

  void _onCurveChanged(ProfileCurve next) {
    setState(() {
      _curve = next;
      _rebuildPreview();
    });
  }

  void _onSegmentsChanged(double value) {
    setState(() {
      _segments = value.round();
      _rebuildPreview();
    });
  }

  void _onClosedProfileChanged(bool? value) {
    setState(() {
      _closedProfile = value ?? false;
      _rebuildPreview();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mesh = _lastMesh;
    var minHeight = 0.0;
    var maxHeight = 0.0;
    for (final point in _curve.points) {
      if (point.position.y < minHeight) minHeight = point.position.y;
      if (point.position.y > maxHeight) maxHeight = point.position.y;
    }

    return AlertDialog(
      title: const Text('Lathe'),
      content: SizedBox(
        width: 900,
        height: 720,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SizedBox(
              width: 520,
              child: Column(
                children: <Widget>[
                  Expanded(
                    child: ClipRect(
                      child: ProfileEditor(
                        curve: _curve,
                        tool: _tool,
                        onChanged: _onCurveChanged,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<ProfileEditTool>(
                    showSelectedIcon: false,
                    segments: <ButtonSegment<ProfileEditTool>>[
                      for (final ProfileEditTool tool in ProfileEditTool.values)
                        ButtonSegment<ProfileEditTool>(
                          value: tool,
                          label: Text(tool.label),
                        ),
                    ],
                    selected: <ProfileEditTool>{_tool},
                    onSelectionChanged: (Set<ProfileEditTool> picked) =>
                        setState(() => _tool = picked.first),
                  ),
                ],
              ),
            ),
            const VerticalDivider(width: 24),
            Expanded(
              child: ModelerViewport(
                renderer: widget.renderer,
                stage: _stage,
                onFrame: () {},
                grid: null,
              ),
            ),
            const VerticalDivider(width: 24),
            SizedBox(
              width: 220,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('Segments', style: theme.textTheme.labelMedium),
                  Slider(
                    value: _segments.toDouble(),
                    min: 3,
                    max: 256,
                    divisions: 253,
                    label: '$_segments',
                    onChanged: _onSegmentsChanged,
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('Closed profile'),
                    value: _closedProfile,
                    onChanged: _onClosedProfileChanged,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    mesh == null
                        ? 'Add at least two points'
                        : 'Vertices ${mesh.vertexCount}\n'
                              'Triangles ${mesh.triangleCount}\n'
                              'Height ${(maxHeight - minHeight).toStringAsFixed(0)}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _curve.toPolyline().length < 2
              ? null
              : () => Navigator.of(context).pop(
                  LatheChoice(
                    profile: _curve.toPolyline(),
                    segments: _segments,
                    closedProfile: _closedProfile,
                  ),
                ),
          child: const Text('Add'),
        ),
      ],
    );
  }
}
