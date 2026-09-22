/// Screen 10 — `pro-rt-07`: the retopology and bake panel.
///
/// **Two blocks, because they are two decisions.** The top one is about the
/// mesh being made — how many quads a retopology should come out at, and the
/// button that makes it; the bottom is about the maps baked onto it once it
/// exists. A person does the first once and the second many times, and a
/// panel that mixed them would put the expensive button beside the one
/// pressed every few minutes.
///
/// **The progress takes the button's own place rather than appearing beside
/// it.** A bake is a job: while it runs, the thing a person wants is to know
/// how far along it is and to be able to stop it, and the button that starts
/// it is exactly the wrong thing to leave pressable. So the button is
/// replaced by a bar and a Cancel, in the same 290 points, and nothing
/// below it moves.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_editor_widgets/flutter3d_editor_widgets.dart';

import '../../l10n/app_localizations.dart';

/// The panel's own width — `pro-rt-07`'s own 290.
const double kBakePanelWidth = 290;

/// What a long-running job on this panel looks like from outside.
typedef BakeProgress = ({String label, double? fraction});

/// Screen 10's own panel: retopology above, maps below.
class BakePanel extends StatelessWidget {
  const BakePanel({
    super.key,
    required this.targetQuads,
    required this.onTargetQuads,
    required this.onRetopologize,
    required this.maps,
    required this.onMap,
    required this.resolution,
    required this.onResolution,
    required this.onBake,
    this.running,
    this.onCancel,
    this.refusal,
  });

  /// How many quads a retopology should aim for.
  final int targetQuads;
  final ValueChanged<int> onTargetQuads;

  /// Start the retopology.
  final VoidCallback onRetopologize;

  /// Which maps are ticked, by the name `BakeMaps` takes.
  final Set<String> maps;

  /// A map was ticked or unticked.
  final void Function(String map, bool on) onMap;

  /// The side of the baked image, in texels.
  final int resolution;
  final ValueChanged<int> onResolution;

  /// Start the bake.
  final VoidCallback onBake;

  /// The job running right now, or null when none is — see the library
  /// comment for why this replaces a button rather than sitting beside one.
  final BakeProgress? running;

  /// Stop it. Null disables the Cancel, which is what a job too far along to
  /// stop looks like.
  final VoidCallback? onCancel;

  /// Why neither button can run — no object selected, no UVs, no material.
  /// Shown once, above both blocks, rather than as two identical tooltips.
  final String? refusal;

  /// The four maps `BakeMaps` knows, in the order the panel lists them.
  static const List<String> offered = <String>[
    'normal',
    'ao',
    'curvature',
    'thickness',
  ];

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool busy = running != null;
    final AppLocalizations l = AppLocalizations.of(context);
    return SizedBox(
      width: kBakePanelWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (refusal != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                refusal!,
                key: const ValueKey<String>('bakeRefusal'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          SectionLabel(l.bakeRetopology),
          RangeSliderField(
            label: l.bakeTargetQuads,
            value: targetQuads.toDouble(),
            min: 100,
            max: 20000,
            step: 100,
            onChanged: (double to) => onTargetQuads(to.round()),
          ),
          const SizedBox(height: 4),
          FilledButton.tonalIcon(
            key: const ValueKey<String>('retopologize'),
            onPressed: busy || refusal != null ? null : onRetopologize,
            icon: const Icon(Icons.grid_on_outlined),
            label: Text(l.bakeRetopologize),
          ),
          const SizedBox(height: 12),
          SectionLabel(l.bakeMaps),
          for (final String map in offered)
            CheckboxListTile(
              key: ValueKey<String>('bakeMap-$map'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(map, style: theme.textTheme.bodySmall),
              value: maps.contains(map),
              onChanged: busy ? null : (bool? on) => onMap(map, on ?? false),
            ),
          RangeSliderField(
            label: l.bakeResolution,
            value: resolution.toDouble(),
            min: 256,
            max: 4096,
            step: 256,
            onChanged: (double to) => onResolution(to.round()),
          ),
          const SizedBox(height: 4),
          // The job takes the button's own place: while a bake runs there is
          // nothing useful about a button that starts a second one.
          if (running case final BakeProgress job)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(job.label, style: theme.textTheme.bodySmall),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  key: const ValueKey<String>('bakeProgress'),
                  value: job.fraction,
                ),
                const SizedBox(height: 4),
                OutlinedButton(
                  key: const ValueKey<String>('bakeCancel'),
                  onPressed: onCancel,
                  child: Text(l.cancel),
                ),
              ],
            )
          else
            FilledButton.icon(
              key: const ValueKey<String>('bake'),
              onPressed: refusal != null || maps.isEmpty ? null : onBake,
              icon: const Icon(Icons.texture_outlined),
              label: Text(
                maps.length == 1 ? 'Bake 1 map' : 'Bake ${maps.length} maps',
              ),
            ),
        ],
      ),
    );
  }
}
