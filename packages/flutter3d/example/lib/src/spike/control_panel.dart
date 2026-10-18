import 'package:flutter/material.dart';
import 'package:flutter3d/flutter3d.dart';

import 'scene_source.dart';

/// The bottom control panel: every slider, chip and readout the demo exposes.
class ControlPanel extends StatelessWidget {
  /// A panel showing the demo's current settings; every control reports its
  /// change through the matching callback and the screen rebuilds the panel.
  const ControlPanel({
    super.key,
    required this.sources,
    required this.sourceIndex,
    required this.onSource,
    required this.lighting,
    required this.onLighting,
    required this.roughness,
    required this.onRoughness,
    required this.metallic,
    required this.onMetallic,
    required this.specular,
    required this.onSpecular,
    required this.exposure,
    required this.onExposure,
    required this.ambient,
    required this.onAmbient,
    required this.wireframe,
    required this.onWireframe,
    required this.spinning,
    required this.onSpinning,
    required this.culling,
    required this.onCulling,
    required this.debug,
    required this.onDebug,
    required this.lights,
    required this.onLightsChanged,
    required this.bloom,
    required this.onBloom,
    required this.shadows,
    required this.onShadows,
    required this.ground,
    required this.onGround,
    required this.uiMicros,
    required this.rasterMicros,
    required this.pick,
    required this.player,
    required this.onPlayerChanged,
    required this.onFrameAll,
    this.morphNodes = const <MeshNode>[],
    required this.renderer,
    required this.scene,
    required this.asset,
    required this.frame,
    required this.loadMillis,
  });

  /// The models the Model chips offer, in order.
  final List<SceneSource> sources;

  /// Which of [sources] is loaded, by index.
  final int sourceIndex;

  /// A Model chip was picked, by its index in [sources].
  final ValueChanged<int> onSource;

  /// The lighting model the scene's materials use.
  final LightingModel lighting;

  /// A lighting model chip was picked.
  final ValueChanged<LightingModel> onLighting;

  /// The materials' roughness, from 0 to 1.
  final double roughness;

  /// The roughness slider moved, from 0 to 1.
  final ValueChanged<double> onRoughness;

  /// The materials' metallic factor, from 0 to 1; the slider is disabled for a
  /// lighting model that has none.
  final double metallic;

  /// The metallic slider moved, from 0 to 1.
  final ValueChanged<double> onMetallic;

  /// The materials' specular strength, from 0 to 1; the slider is disabled
  /// under Lambert.
  final double specular;

  /// The specular slider moved, from 0 to 1.
  final ValueChanged<double> onSpecular;

  /// The camera's exposure multiplier, from 0 to 4.
  final double exposure;

  /// The exposure slider moved, from 0 to 4.
  final ValueChanged<double> onExposure;

  /// The scene's ambient level, from 0 to 0.4.
  final double ambient;

  /// The ambient slider moved, from 0 to 0.4.
  final ValueChanged<double> onAmbient;

  /// Whether the scene is drawn as wireframe.
  final bool wireframe;

  /// The Wireframe chip was toggled.
  final ValueChanged<bool> onWireframe;

  /// Whether the model turns on its own.
  final bool spinning;

  /// The Spin chip was toggled.
  final ValueChanged<bool> onSpinning;

  /// Whether back faces are culled.
  final bool culling;

  /// The Backface cull chip was toggled.
  final ValueChanged<bool> onCulling;

  /// Which debug overlays are drawn: bounds, normals, light gizmos, axes and
  /// camera frusta.
  final DebugDrawSettings debug;

  /// A debug chip was toggled: the settings with that overlay changed.
  final ValueChanged<DebugDrawSettings> onDebug;

  /// The scene's lights, so each can be switched on and off.
  final List<LightNode> lights;

  /// A light chip was toggled; the light's own `isVisible` is already set.
  final VoidCallback onLightsChanged;

  /// The bloom pass's settings, which the Bloom row edits.
  final BloomSettings bloom;

  /// A bloom control changed: the settings with that field replaced.
  final ValueChanged<BloomSettings> onBloom;

  /// The shadow pass's settings, which the Shadows row edits.
  final ShadowSettings shadows;

  /// A shadow control changed: the settings with that field replaced.
  final ValueChanged<ShadowSettings> onShadows;

  /// Whether the ground plane is in the scene.
  final bool ground;

  /// The Ground chip was toggled.
  final ValueChanged<bool> onGround;

  /// The last frame's build time on the UI thread, in microseconds.
  final int uiMicros;

  /// The last frame's raster time, in microseconds.
  final int rasterMicros;

  /// What the last tap selected, or null when nothing is selected.
  final String? pick;

  /// The current model's animation player, null when it carries no clips.
  final AnimationPlayer? player;

  /// Called after a transport control mutates the player, so the panel redraws.
  final VoidCallback onPlayerChanged;

  /// The Frame all chip was pressed: put the camera on the whole model.
  final VoidCallback onFrameAll;

  /// The loaded model's mesh nodes that carry morph state, or empty for the
  /// models that morph nothing — which is most of them.
  final List<MeshNode> morphNodes;

  /// The renderer the scene is drawn through; the readout says whether its
  /// MSAA is on.
  final Renderer renderer;

  /// The scene, for the node count in the readout.
  final Scene scene;

  /// The loaded model, for its vertex and triangle counts and its warnings;
  /// null before the first load.
  final ModelAsset? asset;

  /// What the last frame reported: timings, draws, culled meshes and lights.
  /// Null before the first frame.
  final FrameResult? frame;

  /// Wall-clock time of the last load, including the isolate round trip.
  final int loadMillis;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final sliders = lighting.usesMaterialParameters;
    final warnings = asset?.warnings ?? const <String>[];

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      color: const Color(0xFF16191F),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _PanelLabel('Lighting model', textTheme),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final m in LightingModel.builtIn)
                ChoiceChip(
                  label: Text(m.label),
                  selected: m == lighting,
                  onSelected: (_) => onLighting(m),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _PanelLabel('Model', textTheme),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (var i = 0; i < sources.length; i++)
                ChoiceChip(
                  label: Text(sources[i].label),
                  selected: i == sourceIndex,
                  onSelected: (_) => onSource(i),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: <Widget>[
              Expanded(
                child: _PanelSlider(
                  label: 'Roughness',
                  value: roughness,
                  enabled: sliders,
                  onChanged: onRoughness,
                ),
              ),
              Expanded(
                child: _PanelSlider(
                  label: 'Metallic',
                  value: metallic,
                  enabled: sliders && lighting.usesMetallic,
                  onChanged: onMetallic,
                ),
              ),
              Expanded(
                child: _PanelSlider(
                  label: 'Specular',
                  value: specular,
                  enabled: sliders && lighting != LightingModel.lambert,
                  onChanged: onSpecular,
                ),
              ),
              Expanded(
                child: _PanelSlider(
                  label: 'Ambient',
                  value: ambient,
                  max: 0.4,
                  enabled: sliders,
                  onChanged: onAmbient,
                ),
              ),
              Expanded(
                child: _PanelSlider(
                  label: 'Exposure',
                  value: exposure,
                  max: 4.0,
                  enabled: sliders,
                  onChanged: onExposure,
                ),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              FilterChip(
                label: const Text('Wireframe'),
                selected: wireframe,
                onSelected: onWireframe,
              ),
              FilterChip(
                label: const Text('Spin'),
                selected: spinning,
                onSelected: onSpinning,
              ),
              FilterChip(
                label: const Text('Backface cull'),
                selected: culling,
                onSelected: onCulling,
              ),
              ActionChip(label: const Text('Frame all'), onPressed: onFrameAll),
            ],
          ),
          if (player != null && player!.hasClips) ...<Widget>[
            const SizedBox(height: 6),
            _PanelLabel('Animation', textTheme),
            AnimationControls(player: player!, onChanged: onPlayerChanged),
          ],
          if (morphNodes.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            _PanelLabel('Morph', textTheme),
            MorphControls(
              nodes: morphNodes,
              player: player,
              onChanged: onPlayerChanged,
            ),
          ],
          const SizedBox(height: 6),
          _PanelLabel('Lights', textTheme),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final light in lights)
                FilterChip(
                  label: Text(
                    '${light.name ?? light.type.name} '
                    '(${light.type.name})',
                  ),
                  selected: light.isVisible,
                  // Switching a light off only shortens the shader's loop; the
                  // pipeline is untouched, which the "pipeline sw" counter below
                  // keeps honest.
                  onSelected: (v) {
                    light.isVisible = v;
                    onLightsChanged();
                  },
                ),
            ],
          ),
          const SizedBox(height: 6),
          _PanelLabel('Shadows', textTheme),
          Row(
            children: <Widget>[
              FilterChip(
                label: const Text('Shadows'),
                selected: shadows.enabled,
                onSelected: (v) => onShadows(shadows.copyWith(enabled: v)),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('Ground'),
                selected: ground,
                onSelected: onGround,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _PanelSlider(
                  label: 'Strength',
                  value: shadows.strength,
                  enabled: shadows.enabled,
                  onChanged: (v) => onShadows(shadows.copyWith(strength: v)),
                ),
              ),
              Expanded(
                child: _PanelSlider(
                  label: 'Bias',
                  value: shadows.bias,
                  max: 0.01,
                  enabled: shadows.enabled,
                  onChanged: (v) => onShadows(shadows.copyWith(bias: v)),
                ),
              ),
              Expanded(
                child: _PanelSlider(
                  label: 'Normal offset',
                  value: shadows.normalOffset,
                  max: 0.2,
                  enabled: shadows.enabled,
                  onChanged: (v) =>
                      onShadows(shadows.copyWith(normalOffset: v)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _PanelLabel('Bloom', textTheme),
          Row(
            children: <Widget>[
              FilterChip(
                label: const Text('Bloom'),
                selected: bloom.enabled,
                onSelected: (v) => onBloom(bloom.copyWith(enabled: v)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _PanelSlider(
                  label: 'Threshold',
                  value: bloom.threshold,
                  max: 4.0,
                  enabled: bloom.enabled,
                  onChanged: (v) => onBloom(bloom.copyWith(threshold: v)),
                ),
              ),
              Expanded(
                child: _PanelSlider(
                  label: 'Intensity',
                  value: bloom.intensity,
                  max: 0.5,
                  enabled: bloom.enabled,
                  onChanged: (v) => onBloom(bloom.copyWith(intensity: v)),
                ),
              ),
              Expanded(
                child: _PanelSlider(
                  label: 'Radius',
                  value: bloom.filterRadius,
                  max: 4.0,
                  enabled: bloom.enabled,
                  onChanged: (v) => onBloom(bloom.copyWith(filterRadius: v)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _PanelLabel('Debug draw', textTheme),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              FilterChip(
                label: const Text('Bounds'),
                selected: debug.bounds,
                onSelected: (v) => onDebug(debug.copyWith(bounds: v)),
              ),
              FilterChip(
                label: const Text('Normals'),
                selected: debug.normals,
                onSelected: (v) => onDebug(debug.copyWith(normals: v)),
              ),
              FilterChip(
                label: const Text('Lights'),
                selected: debug.lightGizmos,
                onSelected: (v) => onDebug(debug.copyWith(lightGizmos: v)),
              ),
              FilterChip(
                label: const Text('Axes'),
                selected: debug.axes,
                onSelected: (v) => onDebug(debug.copyWith(axes: v)),
              ),
              FilterChip(
                label: const Text('Frusta'),
                selected: debug.cameraFrustums,
                onSelected: (v) => onDebug(debug.copyWith(cameraFrustums: v)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            asset == null
                ? 'loading…'
                : '${asset!.vertexCount} vtx · ${asset!.triangleCount} tri · '
                      '${scene.meshes.length} nodes · '
                      'load $loadMillis ms · '
                      'MSAA ${renderer.msaaEnabled ? '4x' : 'off'}',
            style: textTheme.bodySmall,
          ),
          Text(
            'ui ${_ms(uiMicros)} · raster ${_ms(rasterMicros)} · '
            'render ${_ms(frame?.cpuMicros ?? 0)} · '
            'submit ${_ms(frame?.submitMicros ?? 0)} · '
            '${frame?.drawCalls ?? 0} draws · '
            '${frame?.pipelineSwitches ?? 0} pipeline sw · '
            '${frame?.culled ?? 0} culled · '
            '${frame?.lights ?? 0} lights'
            '${(frame?.lightsDropped ?? 0) > 0 ? ' (+${frame!.lightsDropped} dropped)' : ''}'
            '${(frame?.shadowsDenied ?? 0) > 0 ? ' · ${frame!.shadowsDenied} shadows denied' : ''}'
            // Beside the other two refusals, and for the same reason: the
            // wireframe chip in this panel does nothing on the web build and
            // on the software backend, and a solid model with the switch on
            // reads as a broken switch until the frame says otherwise.
            '${(frame?.wireframeDeclined ?? false) ? ' · wireframe declined' : ''}'
            '${(frame?.debugLines ?? 0) > 0 ? ' · ${frame!.debugLines} debug lines' : ''}',
            style: textTheme.bodySmall?.copyWith(color: Colors.white60),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              pick == null
                  ? 'Drag to orbit · scroll or pinch to zoom · two fingers to '
                        'pan · tap to pick'
                  : 'picked: $pick',
              style: textTheme.bodySmall?.copyWith(
                color: pick == null ? Colors.white38 : Colors.lightGreenAccent,
              ),
            ),
          ),
          if (warnings.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '⚠ ${warnings.first}'
                '${warnings.length > 1 ? ' (+${warnings.length - 1} more)' : ''}',
                style: textTheme.bodySmall?.copyWith(color: Colors.amberAccent),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }
}

/// Transport controls for the current model's clips.
///
/// Scrubbing pauses first: dragging a slider while the clip is running fights
/// the ticker, and every frame would snap the playhead back.
class AnimationControls extends StatelessWidget {
  /// Transport controls over [player].
  const AnimationControls({
    super.key,
    required this.player,
    required this.onChanged,
  });

  /// The model's animation player, which the controls mutate directly.
  final AnimationPlayer player;

  /// Called after a control mutates [player], so the panel redraws.
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final names = player.clipNames;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            FilterChip(
              label: Text(player.isPlaying ? 'Pause' : 'Play'),
              selected: player.isPlaying,
              onSelected: (_) {
                player.isPlaying ? player.pause() : player.play();
                onChanged();
              },
            ),
            ActionChip(
              label: const Text('Rewind'),
              onPressed: () {
                player.stop();
                onChanged();
              },
            ),
            for (final wrap in AnimationWrap.values)
              ChoiceChip(
                label: Text(wrap.name),
                selected: player.wrap == wrap,
                onSelected: (_) {
                  player.wrap = wrap;
                  onChanged();
                },
              ),
            if (names.length > 1)
              for (var i = 0; i < names.length; i++)
                ChoiceChip(
                  label: Text(names[i]),
                  selected: player.clipIndex == i,
                  onSelected: (_) {
                    player.play(index: i);
                    onChanged();
                  },
                ),
          ],
        ),
        Row(
          children: <Widget>[
            Expanded(
              flex: 3,
              child: _PanelSlider(
                label:
                    'Time '
                    '${player.timeSeconds.toStringAsFixed(2)}/'
                    '${player.durationSeconds.toStringAsFixed(2)}s',
                value: player.durationSeconds <= 0.0
                    ? 0.0
                    : player.timeSeconds / player.durationSeconds,
                enabled: player.durationSeconds > 0.0,
                onChanged: (v) {
                  player.pause();
                  player.seek(v * player.durationSeconds);
                  onChanged();
                },
              ),
            ),
            Expanded(
              child: _PanelSlider(
                label: 'Speed ${player.speed.toStringAsFixed(2)}x',
                value: player.speed,
                max: 3.0,
                enabled: true,
                onChanged: (v) {
                  player.speed = v;
                  onChanged();
                },
              ),
            ),
          ],
        ),
        Text(
          '${player.clips.length} clip'
          '${player.clips.length == 1 ? '' : 's'} · '
          '${player.clip?.tracks.length ?? 0} tracks',
          style: textTheme.bodySmall?.copyWith(color: Colors.white60),
        ),
      ],
    );
  }
}

/// A slider per morph target of the loaded model.
///
/// **The reason to have this at all**: a face is the one thing in a renderer
/// whose parameters mean nothing written down and everything moved by hand.
/// Reading "target 2 at 0.4" tells you nothing; dragging target 2 from nought
/// to one and watching a jaw open tells you what the file contains.
///
/// The first drag pauses the clip, and that is not a nicety. A weights track
/// rewrites these every frame, so a slider moved under a running clip snaps
/// back on the next tick and reads as a broken control rather than as a clip
/// winning an argument.
class MorphControls extends StatelessWidget {
  /// A slider per morph target of every node in [nodes].
  const MorphControls({
    super.key,
    required this.nodes,
    required this.player,
    required this.onChanged,
  });

  /// The mesh nodes of the loaded model that carry morph state.
  final List<MeshNode> nodes;

  /// Paused on the first drag, or null when the model has no clips.
  final AnimationPlayer? player;

  /// Called after a slider moves a weight, so the panel redraws.
  final VoidCallback onChanged;

  /// What the file called target [index] of [node], or its number.
  ///
  /// glTF puts target names in `mesh.extras.targetNames`, which is a convention
  /// rather than part of the format, so most models answer with the number —
  /// and a number is still the thing to drag.
  String _label(MeshNode node, int index) {
    final source = node.mesh is DeviceMesh
        ? (node.mesh as DeviceMesh).source
        : null;
    final targets = source?.morphTargets ?? const <MorphTarget>[];
    final name = index < targets.length ? targets[index].name : null;
    return name ?? 'Target $index';
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final node in nodes) ...<Widget>[
          if (nodes.length > 1)
            Text(
              node.name ?? 'mesh',
              style: textTheme.bodySmall?.copyWith(color: Colors.white60),
            ),
          for (var i = 0; i < node.morphWeights.length; i++)
            _PanelSlider(
              label: _label(node, i),
              value: node.morphWeights[i],
              enabled: true,
              onChanged: (v) {
                // Every node of the model, not just this one: a glTF mesh split
                // across materials arrives as several nodes sharing one set of
                // shapes, and moving one of them alone tears the model apart
                // along the seam between its primitives.
                player?.pause();
                for (final other in nodes) {
                  if (i < other.morphWeights.length) {
                    other.morphWeights[i] = v;
                  }
                }
                onChanged();
              },
            ),
        ],
      ],
    );
  }
}

/// Microseconds as milliseconds with two decimals, so a sub-millisecond phase is
/// still readable instead of collapsing to "0 ms".
String _ms(int micros) => '${(micros / 1000.0).toStringAsFixed(2)} ms';

/// A section heading in capitals.
class _PanelLabel extends StatelessWidget {
  const _PanelLabel(this.text, this.theme);

  final String text;
  final TextTheme theme;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text.toUpperCase(),
      style: theme.labelSmall?.copyWith(letterSpacing: 1.1),
    ),
  );
}

/// A labelled slider from nought to [max], showing its value to two places.
class _PanelSlider extends StatelessWidget {
  const _PanelSlider({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.enabled,
    this.max = 1.0,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final bool enabled;
  final double max;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '$label ${value.toStringAsFixed(2)}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: enabled ? null : Theme.of(context).disabledColor,
          ),
        ),
        Slider(
          value: value.clamp(0.0, max),
          max: max,
          onChanged: enabled ? onChanged : null,
        ),
      ],
    );
  }
}
