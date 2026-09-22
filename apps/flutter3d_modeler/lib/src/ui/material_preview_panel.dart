/// `ux-40`'s own preview: the material the panel is editing, on a sphere or
/// a cube, inside the panel rather than behind a dialog.
///
/// **A dialog was the wrong shape for this and `mat-15` already said so in
/// passing.** Material Studio shows a material on four bodies under three
/// skies, which is what somebody opens deliberately to judge one; what a
/// person editing a roughness slider needs is the sphere moving while the
/// slider does, and a dialog that covers the slider cannot give them that.
/// So this is the same stage, the same environment and the same two of the
/// four bodies, sized to a panel — and Material Studio stays where it is,
/// for the judging.
///
/// **It draws whatever material it is handed, and does not own one.** The
/// live `Material` comes off `MaterialPool` the same way the viewport's own
/// does, so a field committed through `SetMaterialField` reaches the sphere
/// on the frame the document emits — there is no second copy here to keep
/// in step and nothing to invalidate.
library;

import 'package:flutter/material.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' as engine show Material;
import 'package:flutter3d_mesh/flutter3d_mesh.dart';

import '../modeler_viewport.dart';
import '../staging.dart';
import 'material_studio_dialog.dart'
    show
        MaterialStudioEnvironment,
        MaterialStudioSkyPreset,
        materialStudioSkyPresets;

/// Which of the two bodies the panel's preview stands the material on.
///
/// **Two, where the studio has four.** The teapot is a shape to judge a
/// material's silhouette against and "this object" is a shape to judge it in
/// place; both are worth a screen of their own and neither is worth a
/// hundred and eighty pixels of a panel that also has to hold the slider
/// being dragged.
enum MaterialPreviewBody {
  sphere('Sphere'),
  cube('Cube');

  const MaterialPreviewBody(this.label);

  final String label;
}

/// How tall the preview draws — `ModelerMetrics` has no entry for it because
/// nothing else is this shape: wide enough to read a highlight across, short
/// enough that the fields under it stay on screen beside it.
const double kMaterialPreviewHeight = 180;

/// The material being edited, drawn live.
class MaterialPreviewPanel extends StatefulWidget {
  const MaterialPreviewPanel({
    super.key,
    required this.renderer,
    required this.material,
    this.height = kMaterialPreviewHeight,
  });

  final Renderer renderer;

  /// The live material — `MaterialPool`'s own instance for the object being
  /// painted, or clay where the pool has not built one yet.
  final engine.Material material;

  final double height;

  @override
  State<MaterialPreviewPanel> createState() => _MaterialPreviewPanelState();
}

class _MaterialPreviewPanelState extends State<MaterialPreviewPanel> {
  late final ModelerStage _stage;
  late final MaterialStudioEnvironment _environment;
  late final List<MaterialStudioSkyPreset> _presets;

  MaterialPreviewBody _body = MaterialPreviewBody.sphere;
  int _presetIndex = 0;

  @override
  void initState() {
    super.initState();
    _presets = materialStudioSkyPresets();
    _stage = ModelerStage.build(device: widget.renderer.device);
    _environment = MaterialStudioEnvironment(
      device: widget.renderer.device,
      scene: _stage.scene,
    )..apply(_presets[_presetIndex].sky);
    _showBody(MaterialPreviewBody.sphere);
    (_stage.subject as MeshNode).material = widget.material;
    _stage.frameSubject();
  }

  @override
  void didUpdateWidget(covariant MaterialPreviewPanel old) {
    super.didUpdateWidget(old);
    // Identity, not equality: `MaterialPool` hands back the same instance
    // until the material's own version moves, so a changed field is a
    // changed object and an untouched one costs nothing here.
    if (!identical(old.material, widget.material)) {
      (_stage.subject as MeshNode).material = widget.material;
    }
  }

  @override
  void dispose() {
    _environment.dispose();
    super.dispose();
  }

  void _showBody(MaterialPreviewBody body) {
    (_stage.subject as MeshNode).mesh = DeviceMesh.upload(
      widget.renderer.device,
      switch (body) {
        MaterialPreviewBody.sphere =>
          const ParametricSphere().toEditMesh().toMeshData(),
        MaterialPreviewBody.cube =>
          ParametricCuboid().toEditMesh().toMeshData(),
      },
    );
    _stage.frameSubject();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      SizedBox(
        height: widget.height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: ModelerViewport(
            key: const ValueKey<String>('materialPreview'),
            renderer: widget.renderer,
            stage: _stage,
            onFrame: () {},
            grid: null,
          ),
        ),
      ),
      const SizedBox(height: 6),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: <Widget>[
          for (final MaterialPreviewBody body in MaterialPreviewBody.values)
            ChoiceChip(
              label: Text(body.label),
              selected: _body == body,
              onSelected: (bool _) => setState(() {
                _body = body;
                _showBody(body);
              }),
            ),
          for (var i = 0; i < _presets.length; i++)
            ChoiceChip(
              label: Text(_presets[i].name),
              selected: _presetIndex == i,
              onSelected: (bool _) => setState(() {
                _presetIndex = i;
                _environment.apply(_presets[i].sky);
              }),
            ),
        ],
      ),
    ],
  );
}
