/// Screen 11 — `pro-sim-06`: the simulation panel and the strip under it.
///
/// **A chip per kind rather than a dropdown**, because the parameters change
/// wholesale with the choice: cloth has stiffness and damping, a rigid body
/// has mass and friction, particles have a rate and a lifetime. A dropdown
/// would put the name of the thing being configured somewhere other than
/// above the things configuring it.
///
/// **Pinning is a selection, not a list of numbers.** A cloth is pinned by
/// picking the vertices that hold it up — which is phase one's own element
/// selection, already in the viewport — so this shows how many are pinned
/// and offers to take whatever is selected now. Typing vertex indices into a
/// panel is the alternative, and nobody knows a vertex by its number.
///
/// **The transport is under the viewport rather than in the panel**, the
/// same place the animation mode puts its own: a cache is scrubbed while
/// looking at the model, and a scrub bar beside a parameter list is a scrub
/// bar somebody has to look away to reach.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_editor_widgets/flutter3d_editor_widgets.dart';

import '../../l10n/app_localizations.dart';
import 'simulation_cache_strip.dart';

/// The transport strip's own height — `pro-sim-06`'s own 150.
const double kSimulationBarHeight = 150;

/// What a simulation is, as the panel offers it.
typedef SimulationKindRow = ({String name, IconData icon});

/// How much of the cache is baked.
typedef SimulationCacheState = ({int frames, int baked, bool running});

/// Screen 11's own panel: the kind, its parameters, what it collides with,
/// and what is pinned.
class SimulationPanel extends StatelessWidget {
  const SimulationPanel({
    super.key,
    required this.kind,
    required this.onKind,
    required this.parameters,
    required this.onParameter,
    required this.colliders,
    required this.onCollider,
    required this.pinnedCount,
    required this.selectedCount,
    required this.onPinSelection,
    required this.onClearPins,
  });

  /// Which kind is chosen, by [kinds]' own names.
  final String kind;
  final ValueChanged<String> onKind;

  /// The chosen kind's own numbers, in the order they are shown.
  final Map<String, double> parameters;
  final void Function(String name, double value) onParameter;

  /// Objects this simulation collides with, by name, and whether each is on.
  final Map<String, bool> colliders;
  final void Function(String name, bool on) onCollider;

  /// How many vertices hold the simulation up now.
  final int pinnedCount;

  /// How many are selected in the viewport — what "Pin the selection" would
  /// take.
  final int selectedCount;

  final VoidCallback onPinSelection;
  final VoidCallback onClearPins;

  /// The three kinds `pro-sim-02`/`pro-sim-03` between them can bake.
  static const List<SimulationKindRow> kinds = <SimulationKindRow>[
    (name: 'cloth', icon: Icons.waves_outlined),
    (name: 'rigid', icon: Icons.view_in_ar_outlined),
    (name: 'particles', icon: Icons.grain_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SectionLabel(l.simKind),
        Wrap(
          spacing: 6,
          children: <Widget>[
            for (final SimulationKindRow each in kinds)
              ChoiceChip(
                key: ValueKey<String>('simKind-${each.name}'),
                avatar: Icon(each.icon, size: 16),
                label: Text(each.name),
                selected: each.name == kind,
                onSelected: (bool on) {
                  if (on) onKind(each.name);
                },
              ),
          ],
        ),
        SectionLabel(l.simParameters),
        for (final MapEntry<String, double> each in parameters.entries)
          RangeSliderField(
            key: ValueKey<String>('simParameter-${each.key}'),
            label: each.key,
            value: each.value,
            min: 0,
            max: 1,
            step: 0.01,
            onChanged: (double to) => onParameter(each.key, to),
          ),
        SectionLabel(l.simCollidesWith),
        if (colliders.isEmpty)
          Text(l.simNothingElse, style: theme.textTheme.bodySmall)
        else
          for (final MapEntry<String, bool> each in colliders.entries)
            CheckboxListTile(
              key: ValueKey<String>('simCollider-${each.key}'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(each.key, style: theme.textTheme.bodySmall),
              value: each.value,
              onChanged: (bool? on) => onCollider(each.key, on ?? false),
            ),
        SectionLabel(l.simPinned),
        Text(
          pinnedCount == 0 ? 'Nothing pinned' : '$pinnedCount vertices',
          key: const ValueKey<String>('simPinnedCount'),
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        FilledButton.tonal(
          key: const ValueKey<String>('simPinSelection'),
          onPressed: selectedCount == 0 ? null : onPinSelection,
          child: Text(
            selectedCount == 0
                ? 'Select vertices to pin'
                : 'Pin $selectedCount selected',
          ),
        ),
        TextButton(
          key: const ValueKey<String>('simClearPins'),
          onPressed: pinnedCount == 0 ? null : onClearPins,
          child: Text(l.simClearPins),
        ),
      ],
    );
  }
}

/// The strip under the viewport: a transport over the baked cache, and what
/// there is of it.
class SimulationBar extends StatelessWidget {
  const SimulationBar({
    super.key,
    required this.cache,
    required this.frame,
    required this.onSeek,
    required this.playing,
    required this.onPlayPause,
    required this.onBake,
    required this.onClearCache,
  });

  final SimulationCacheState cache;

  /// Which frame is on screen.
  final int frame;
  final ValueChanged<int> onSeek;

  final bool playing;
  final VoidCallback onPlayPause;

  final VoidCallback onBake;
  final VoidCallback onClearCache;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool hasCache = cache.baked > 0;
    final AppLocalizations l = AppLocalizations.of(context);
    return SizedBox(
      height: kSimulationBarHeight,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                IconButton(
                  key: const ValueKey<String>('simPlayPause'),
                  onPressed: hasCache ? onPlayPause : null,
                  icon: Icon(
                    playing ? Icons.pause_outlined : Icons.play_arrow_outlined,
                  ),
                ),
                Expanded(
                  child: Slider(
                    key: const ValueKey<String>('simScrub'),
                    value: frame.toDouble().clamp(
                      0,
                      cache.frames == 0 ? 0 : (cache.frames - 1).toDouble(),
                    ),
                    max: cache.frames == 0 ? 0 : (cache.frames - 1).toDouble(),
                    onChanged: hasCache
                        ? (double to) => onSeek(to.round())
                        : null,
                  ),
                ),
                Text(
                  '$frame / ${cache.frames}',
                  key: const ValueKey<String>('simFrameCount'),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 4),
            // How much of the cache exists, drawn as the bar it is: a
            // simulation half baked is a scrub bar that runs out halfway,
            // and saying so before somebody drags into the empty half is
            // cheaper than explaining it afterwards.
            //
            // `pro-sim-03`'s own strip rather than the progress indicator
            // that stood in for it: the same fill, and the two things an
            // indicator has not got — a tooltip with the two counts in it,
            // and a sentence for a screen reader, which otherwise meets a
            // bar of unexplained progress in the middle of a transport.
            SimulationCacheStrip(
              key: const ValueKey<String>('simCacheBar'),
              bakedFrameCount: cache.baked,
              targetFrameCount: cache.frames,
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                FilledButton.tonal(
                  key: const ValueKey<String>('simBake'),
                  onPressed: cache.running ? null : onBake,
                  child: Text(cache.running ? 'Baking…' : 'Bake'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  key: const ValueKey<String>('simClearCache'),
                  onPressed: hasCache ? onClearCache : null,
                  child: Text(l.simClearCache),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
