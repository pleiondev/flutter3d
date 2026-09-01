import 'package:flutter/material.dart';
import 'package:flutter3d/flutter3d.dart';

import 'scene_source.dart';

/// The bottom control panel: every slider, chip and readout the demo exposes.
class ControlPanel extends StatelessWidget {
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
    required this.renderer,
    required this.scene,
    required this.asset,
    required this.frame,
    required this.loadMillis,
  });

  final List<SceneSource> sources;
  final int sourceIndex;
  final ValueChanged<int> onSource;
  final LightingModel lighting;
  final ValueChanged<LightingModel> onLighting;
  final double roughness;
  final ValueChanged<double> onRoughness;
  final double metallic;
  final ValueChanged<double> onMetallic;
  final double specular;
  final ValueChanged<double> onSpecular;
  final double exposure;
  final ValueChanged<double> onExposure;
  final double ambient;
  final ValueChanged<double> onAmbient;
  final bool wireframe;
  final ValueChanged<bool> onWireframe;
  final bool spinning;
  final ValueChanged<bool> onSpinning;
  final bool culling;
  final ValueChanged<bool> onCulling;
  final DebugDrawOptions debug;
  final ValueChanged<DebugDrawOptions> onDebug;

  /// The scene's lights, so each can be switched on and off.
  final List<LightNode> lights;

  final VoidCallback onLightsChanged;

  final BloomSettings bloom;
  final ValueChanged<BloomSettings> onBloom;

  final ShadowSettings shadows;
  final ValueChanged<ShadowSettings> onShadows;

  final bool ground;
  final ValueChanged<bool> onGround;
  final int uiMicros;
  final int rasterMicros;

  /// What the last tap selected, or null when nothing is selected.
  final String? pick;

  /// The current model's animation player, null when it carries no clips.
  final AnimationPlayer? player;

  /// Called after a transport control mutates the player, so the panel redraws.
  final VoidCallback onPlayerChanged;

  final VoidCallback onFrameAll;
  final Renderer renderer;
  final Scene scene;
  final ModelAsset? asset;
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
          PanelLabel('Lighting model', textTheme),
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
          PanelLabel('Model', textTheme),
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
                child: PanelSlider(
                  label: 'Roughness',
                  value: roughness,
                  enabled: sliders,
                  onChanged: onRoughness,
                ),
              ),
              Expanded(
                child: PanelSlider(
                  label: 'Metallic',
                  value: metallic,
                  enabled: sliders && lighting.usesMetallic,
                  onChanged: onMetallic,
                ),
              ),
              Expanded(
                child: PanelSlider(
                  label: 'Specular',
                  value: specular,
                  enabled: sliders && lighting != LightingModel.lambert,
                  onChanged: onSpecular,
                ),
              ),
              Expanded(
                child: PanelSlider(
                  label: 'Ambient',
                  value: ambient,
                  max: 0.4,
                  enabled: sliders,
                  onChanged: onAmbient,
                ),
              ),
              Expanded(
                child: PanelSlider(
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
            PanelLabel('Animation', textTheme),
            AnimationControls(player: player!, onChanged: onPlayerChanged),
          ],
          const SizedBox(height: 6),
          PanelLabel('Lights', textTheme),
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
                  selected: light.visible,
                  // Switching a light off only shortens the shader's loop; the
                  // pipeline is untouched, which the "pipeline sw" counter below
                  // keeps honest.
                  onSelected: (v) {
                    light.visible = v;
                    onLightsChanged();
                  },
                ),
            ],
          ),
          const SizedBox(height: 6),
          PanelLabel('Shadows', textTheme),
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
                child: PanelSlider(
                  label: 'Strength',
                  value: shadows.strength,
                  enabled: shadows.enabled,
                  onChanged: (v) => onShadows(shadows.copyWith(strength: v)),
                ),
              ),
              Expanded(
                child: PanelSlider(
                  label: 'Bias',
                  value: shadows.bias,
                  max: 0.01,
                  enabled: shadows.enabled,
                  onChanged: (v) => onShadows(shadows.copyWith(bias: v)),
                ),
              ),
              Expanded(
                child: PanelSlider(
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
          PanelLabel('Bloom', textTheme),
          Row(
            children: <Widget>[
              FilterChip(
                label: const Text('Bloom'),
                selected: bloom.enabled,
                onSelected: (v) => onBloom(bloom.copyWith(enabled: v)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: PanelSlider(
                  label: 'Threshold',
                  value: bloom.threshold,
                  max: 4.0,
                  enabled: bloom.enabled,
                  onChanged: (v) => onBloom(bloom.copyWith(threshold: v)),
                ),
              ),
              Expanded(
                child: PanelSlider(
                  label: 'Intensity',
                  value: bloom.intensity,
                  max: 0.5,
                  enabled: bloom.enabled,
                  onChanged: (v) => onBloom(bloom.copyWith(intensity: v)),
                ),
              ),
              Expanded(
                child: PanelSlider(
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
          PanelLabel('Debug draw', textTheme),
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
  const AnimationControls({
    super.key,
    required this.player,
    required this.onChanged,
  });

  final AnimationPlayer player;
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
                    player.play(i);
                    onChanged();
                  },
                ),
          ],
        ),
        Row(
          children: <Widget>[
            Expanded(
              flex: 3,
              child: PanelSlider(
                label:
                    'Time '
                    '${player.time.toStringAsFixed(2)}/'
                    '${player.duration.toStringAsFixed(2)}s',
                value: player.duration <= 0.0
                    ? 0.0
                    : player.time / player.duration,
                enabled: player.duration > 0.0,
                onChanged: (v) {
                  player.pause();
                  player.seek(v * player.duration);
                  onChanged();
                },
              ),
            ),
            Expanded(
              child: PanelSlider(
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

/// Microseconds as milliseconds with two decimals, so a sub-millisecond phase is
/// still readable instead of collapsing to "0 ms".
String _ms(int micros) => '${(micros / 1000.0).toStringAsFixed(2)} ms';

class PanelLabel extends StatelessWidget {
  const PanelLabel(this.text, this.theme, {super.key});

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

class PanelSlider extends StatelessWidget {
  const PanelSlider({
    super.key,
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
