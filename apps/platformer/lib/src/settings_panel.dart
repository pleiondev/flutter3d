import 'package:flutter/material.dart';
import 'package:flutter3d_audio/flutter3d_audio.dart';
import 'package:flutter3d_game/flutter3d_game.dart';

import 'credits.dart';

/// Volume sliders and the keys, over the top of the paused game.
///
/// Flutter widgets, which is the one thing this stack gets for nothing: a
/// settings screen in a C++ engine is a small project of its own, and here it
/// is a `Slider` and a `Column`.
class SettingsPanel extends StatelessWidget {
  const SettingsPanel({
    super.key,
    required this.mixer,
    required this.bindings,
    required this.onVolume,
    required this.onClose,
  });

  final Mixer mixer;
  final Bindings bindings;
  final void Function(AudioBus bus, double volume) onVolume;
  final VoidCallback onClose;

  static const List<AudioBus> _buses = <AudioBus>[
    AudioBus.master,
    AudioBus.sfx,
  ];

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.72),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Settings',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 18),
                for (final bus in _buses) ...<Widget>[
                  Text(
                    bus.name,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      letterSpacing: 2,
                      fontSize: 12,
                    ),
                  ),
                  Slider(
                    value: mixer.volumeOf(bus),
                    onChanged: (double value) => onVolume(bus, value),
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  'Controls',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    letterSpacing: 2,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
                // Read from the same table the keyboard reads, so a rebinding
                // that never reached the game cannot look as though it did.
                for (final action in GameAction.common)
                  _Binding(
                    action: action.name,
                    sources: bindings.sourcesFor(action).length,
                  ),
                const SizedBox(height: 18),
                const CreditsSection(),
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: onClose,
                    child: const Text('Back to the game'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Binding extends StatelessWidget {
  const _Binding({required this.action, required this.sources});

  final String action;
  final int sources;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(action, style: const TextStyle(color: Colors.white)),
          Text(
            sources == 1 ? '1 key' : '$sources keys',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
          ),
        ],
      ),
    );
  }
}
