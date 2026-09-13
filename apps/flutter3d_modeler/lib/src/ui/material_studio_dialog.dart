/// `mat-15`'s own preview screen, absorbing `view-16-material-preview`'s
/// row (its own acceptance is a pointer here): a material seen on four
/// bodies, under three skies, lit and grounded the same way every other
/// stage in this app is.
///
/// **A stage of its own, the same shape `lathe_dialog.dart` already
/// committed to for exactly this reason.** `ModelerStage.build`'s own doc
/// comment names "a material preview beside it later" as the very next
/// thing a single `RenderView` was not enough for — this is that preview,
/// built the same way: `ModelerStage.build` gives a fresh `Scene`, two
/// `LightNode`s and an `OrbitController` for free, and this dialog mutates
/// the one thing it does not give — the subject's own mesh and material,
/// and the sky the scene reflects.
library;

import 'dart:async';

import 'package:flutter/material.dart' hide Material;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' as engine show Material;
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_samples/flutter3d_samples.dart';
import 'package:vector_math/vector_math.dart' show Vector3, Vector4;

import '../modeler_viewport.dart';
import '../staging.dart';

/// Which body the material is shown on.
enum MaterialStudioBody {
  sphere('Sphere'),
  cube('Cube'),
  teapot('Teapot'),
  thisObject('This object');

  const MaterialStudioBody(this.label);

  final String label;
}

/// One of the row's own "три пресета" — a name for the chip, and the sky it
/// draws.
final class MaterialStudioSkyPreset {
  const MaterialStudioSkyPreset({required this.name, required this.sky});

  final String name;
  final SkySettings sky;
}

/// A getter rather than a stored list: [SkySettings] holds `Vector3`s, which
/// have no const constructor (see that class's own docstring), so a shared
/// top-level list would be three mutable vectors every caller of this dialog
/// reached into the same instance of.
List<MaterialStudioSkyPreset> materialStudioSkyPresets() =>
    <MaterialStudioSkyPreset>[
      MaterialStudioSkyPreset(
        name: 'Studio',
        sky: SkySettings(
          enabled: true,
          zenith: Vector3(0.20, 0.20, 0.22),
          horizon: Vector3(0.55, 0.55, 0.56),
          nadir: Vector3(0.08, 0.08, 0.08),
          sunIntensity: 0.0,
          glowStrength: 0.0,
        ),
      ),
      MaterialStudioSkyPreset(
        name: 'Daylight',
        sky: SkySettings(
          enabled: true,
          zenith: Vector3(0.10, 0.28, 0.62),
          horizon: Vector3(0.68, 0.78, 0.92),
          nadir: Vector3(0.05, 0.06, 0.08),
          directionToSun: Vector3(0.35, 0.75, 0.4),
          sunColor: Vector3(1.0, 0.97, 0.9),
          sunIntensity: 6.0,
          glowStrength: 0.4,
        ),
      ),
      MaterialStudioSkyPreset(
        name: 'Sunset',
        sky: SkySettings(
          enabled: true,
          zenith: Vector3(0.06, 0.08, 0.20),
          horizon: Vector3(0.85, 0.45, 0.22),
          nadir: Vector3(0.05, 0.04, 0.06),
          directionToSun: Vector3(0.8, 0.1, 0.2),
          sunColor: Vector3(1.0, 0.6, 0.3),
          sunIntensity: 3.0,
          glowStrength: 0.9,
          glowExponent: 3.0,
        ),
      ),
    ];

/// Owns the studio's environment texture and the one rule the row's own
/// acceptance names: switching presets gives the old handle back rather than
/// leaking it.
///
/// Not private to this library, so a test can exercise the disposal rule
/// directly against a fake device — a [MaterialStudioEnvironment] with no
/// widget behind it at all — instead of driving a whole dialog to prove one
/// line of cleanup runs.
final class MaterialStudioEnvironment {
  MaterialStudioEnvironment({required this.device, required this.scene});

  final GraphicsDevice device;
  final Scene scene;

  TextureHandle? _handle;

  /// The handle currently bound to [scene], for a test to compare against.
  TextureHandle? get current => _handle;

  /// Builds the environment [sky] makes, binds it to [scene], and releases
  /// whatever was bound before — in that order, so the scene is never
  /// without one between two calls.
  void apply(SkySettings sky, {int size = 32}) {
    final built = EnvironmentMap.fromSky(device, sky, size: size);
    final old = _handle;
    scene.environment = built?.texture;
    scene.environmentLevels = built?.levels ?? 0;
    scene.ambientIntensity = built == null ? 0.06 : 1.0;
    _handle = built?.texture;
    if (old != null) device.releaseTexture(old);
  }

  /// Gives back whatever is currently bound. Called when the dialog closes —
  /// a [Scene] this studio built is going with it, and a released texture
  /// held by nobody is a leak the way [MaterialPool.dispose] already
  /// documents for the project's own textures.
  void dispose() {
    final handle = _handle;
    if (handle == null) return;
    device.releaseTexture(handle);
    _handle = null;
  }
}

/// The floor every preset stands the body on — flat, wide enough that the
/// horizon reads as a horizon rather than a tabletop's own edge.
MeshNode _buildGround(GraphicsDevice device) => MeshNode(
  DeviceMesh.upload(
    device,
    const ParametricPlane(width: 8, depth: 8).toEditMesh().toMeshData(),
  ),
  engine.Material(
    name: 'studio-floor',
    lighting: LightingModel.pbr,
    baseColor: Vector4(0.5, 0.5, 0.52, 1.0),
    roughness: 0.85,
  ),
  name: 'floor',
)..setPosition(0, -0.5, 0);

/// The bytes of `flutter3d_samples`' own teapot, decoded once and cached —
/// nothing about the file changes between one studio and the next.
MeshData? _cachedTeapot;
Future<MeshData?> _teapotMeshData() async {
  final cached = _cachedTeapot;
  if (cached != null) return cached;
  try {
    final data = await rootBundle.load('$kSamplesAsset/teapot.obj');
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final document = await ObjLoader().load(bytes);
    if (document.surfaces.isEmpty) return null;
    final mesh = document.surfaces.first.mesh;
    _cachedTeapot = mesh;
    return mesh;
  } catch (_) {
    // A bundle that cannot read the asset (a packaging slip, a corrupt
    // file) is not a reason to crash a preview dialog — the sphere it opened
    // on stays on screen and the teapot chip simply does nothing that frame.
    return null;
  }
}

/// Opens `mat-15`'s own studio: [material] shown on a chosen body, under a
/// chosen sky, drawn through [renderer] — the same device the document's own
/// viewport already uses.
///
/// [selectedObjectMesh] is the currently selected object's own uploaded
/// geometry, when there is one to show — the row's own "этот объект" body.
/// Null hides that chip rather than falling back to a shape it does not
/// name.
Future<void> showMaterialStudioDialog(
  BuildContext context, {
  required Renderer renderer,
  required engine.Material material,
  MeshGeometry? selectedObjectMesh,
}) => showDialog<void>(
  context: context,
  builder: (BuildContext context) => _MaterialStudioDialog(
    renderer: renderer,
    material: material,
    selectedObjectMesh: selectedObjectMesh,
  ),
);

class _MaterialStudioDialog extends StatefulWidget {
  const _MaterialStudioDialog({
    required this.renderer,
    required this.material,
    this.selectedObjectMesh,
  });

  final Renderer renderer;
  final engine.Material material;
  final MeshGeometry? selectedObjectMesh;

  @override
  State<_MaterialStudioDialog> createState() => _MaterialStudioDialogState();
}

class _MaterialStudioDialogState extends State<_MaterialStudioDialog> {
  late final ModelerStage _stage;
  late final MaterialStudioEnvironment _environment;
  late final List<MaterialStudioSkyPreset> _presets;

  MaterialStudioBody _body = MaterialStudioBody.sphere;
  int _presetIndex = 0;
  bool _loadingTeapot = false;

  @override
  void initState() {
    super.initState();
    _presets = materialStudioSkyPresets();
    _stage = ModelerStage.build(device: widget.renderer.device);
    (_stage.subject as MeshNode).material = widget.material;
    _stage.scene.add(_buildGround(widget.renderer.device));
    _environment = MaterialStudioEnvironment(
      device: widget.renderer.device,
      scene: _stage.scene,
    );
    _environment.apply(_presets[_presetIndex].sky);
    _stage.frameSubject();
  }

  @override
  void dispose() {
    _environment.dispose();
    super.dispose();
  }

  void _selectPreset(int index) {
    setState(() {
      _presetIndex = index;
      _environment.apply(_presets[index].sky);
    });
  }

  Future<void> _selectBody(MaterialStudioBody body) async {
    MeshGeometry? mesh;
    switch (body) {
      case MaterialStudioBody.sphere:
        mesh = DeviceMesh.upload(
          widget.renderer.device,
          const ParametricSphere().toEditMesh().toMeshData(),
        );
      case MaterialStudioBody.cube:
        mesh = DeviceMesh.upload(
          widget.renderer.device,
          ParametricCuboid().toEditMesh().toMeshData(),
        );
      case MaterialStudioBody.teapot:
        setState(() => _loadingTeapot = true);
        final data = await _teapotMeshData();
        if (!mounted) return;
        setState(() => _loadingTeapot = false);
        mesh = data == null
            ? null
            : DeviceMesh.upload(widget.renderer.device, data);
      case MaterialStudioBody.thisObject:
        mesh = widget.selectedObjectMesh;
    }
    if (mesh == null || !mounted) return;
    setState(() {
      _body = body;
      (_stage.subject as MeshNode).mesh = mesh!;
      _stage.frameSubject();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Material Studio'),
      content: SizedBox(
        width: 720,
        height: 520,
        child: Column(
          children: <Widget>[
            Expanded(
              child: Stack(
                children: <Widget>[
                  ModelerViewport(
                    renderer: widget.renderer,
                    stage: _stage,
                    onFrame: () {},
                    grid: null,
                  ),
                  if (_loadingTeapot)
                    const Positioned(
                      right: 12,
                      top: 12,
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: <Widget>[
                for (final MaterialStudioBody body in MaterialStudioBody.values)
                  if (body != MaterialStudioBody.thisObject ||
                      widget.selectedObjectMesh != null)
                    ChoiceChip(
                      label: Text(body.label),
                      selected: _body == body,
                      onSelected: (bool _) => unawaited(_selectBody(body)),
                    ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: <Widget>[
                for (var i = 0; i < _presets.length; i++)
                  ChoiceChip(
                    label: Text(_presets[i].name),
                    selected: _presetIndex == i,
                    onSelected: (bool _) => _selectPreset(i),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
