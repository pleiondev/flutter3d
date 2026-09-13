/// Screen 17: three thirds of the same object, each at a different level of
/// detail, and the zone bar underneath that sets where each one takes over.
/// `pro-lod-04`'s own row — it absorbs `view-20`, which asked for the same
/// mesh-simplification picture on its own before this screen existed to
/// hold it.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_geometry/flutter3d_geometry.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';

import 'lod_zone_bar.dart';

/// Draws one third of [LodScreen] — the real `ModelerViewport` wired to a
/// stage built from [mesh] in the application, a recording stand-in in a
/// test that has no renderer to give it.
///
/// **A builder rather than a `Widget` field, unlike `Shell.viewport`.**
/// `Shell` draws one picture of one document, built once by whatever called
/// it; this draws the same object three times over, and the thing that
/// differs between the three calls — which mesh a third is handed — is
/// exactly what the plan's own acceptance ("the three thirds look visibly
/// different") has to be checkable without a GPU. A `Widget` handed in whole
/// would already have that choice baked in where nothing could see it happen.
typedef LodViewportBuilder =
    Widget Function(BuildContext context, int lodIndex, MeshData? mesh);

/// Three thirds of [object], each fed [LodMeshCache.meshFor] at a different
/// level, and a [LodZoneBar] underneath.
class LodScreen extends StatelessWidget {
  const LodScreen({
    super.key,
    required this.object,
    required this.cache,
    required this.viewportBuilder,
    required this.onThresholdChanged,
    this.levelCount = 3,
  });

  /// The object every third shows, at [levelCount] different levels.
  final ModelObject object;

  /// What turns a level into an actual mesh. See [LodMeshCache.meshFor].
  final LodMeshCache cache;

  /// Draws one third. See [LodViewportBuilder].
  final LodViewportBuilder viewportBuilder;

  /// A marker on the zone bar moved to a new threshold — see
  /// [LodZoneBar.onThresholdChanged].
  final void Function(int lodIndex, double maxScreenFraction)
  onThresholdChanged;

  /// How many thirds. Three is the plan's own number and the default; a
  /// fourth level an object grows later should not need a second screen.
  final int levelCount;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: Row(
            children: <Widget>[
              for (int lodIndex = 0; lodIndex < levelCount; lodIndex++)
                Expanded(
                  child: _LodPane(
                    lodIndex: lodIndex,
                    label: _labelFor(lodIndex),
                    mesh: cache.meshFor(object, lodIndex),
                    builder: viewportBuilder,
                  ),
                ),
            ],
          ),
        ),
        LodZoneBar(lods: object.lods, onThresholdChanged: onThresholdChanged),
      ],
    );
  }

  /// "LOD 0 · 100%" when [object] actually has a spec for [lodIndex] —
  /// [LodSpec.ratio] is what a person set out to simplify to, which is a
  /// caption they chose rather than a triangle count the mesh happened to
  /// land on. "LOD n" alone for a level nothing has been asked for yet, the
  /// ordinary case for an object [AddLod] has not reached.
  String _labelFor(int lodIndex) {
    if (lodIndex >= object.lods.length) return 'LOD $lodIndex';
    final LodSpec spec = object.lods[lodIndex];
    return 'LOD $lodIndex · ${(spec.ratio * 100).round()}%';
  }
}

class _LodPane extends StatelessWidget {
  const _LodPane({
    required this.lodIndex,
    required this.label,
    required this.mesh,
    required this.builder,
  });

  final int lodIndex;
  final String label;
  final MeshData? mesh;
  final LodViewportBuilder builder;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          child: Text(
            label,
            key: ValueKey<String>('lod-label-$lodIndex'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
        Expanded(
          child: KeyedSubtree(
            key: ValueKey<String>('lod-viewport-$lodIndex'),
            child: builder(context, lodIndex, mesh),
          ),
        ),
      ],
    );
  }
}
