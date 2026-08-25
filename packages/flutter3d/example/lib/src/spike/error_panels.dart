import 'package:flutter/material.dart';

/// Shown in place of the scene surface when the current model failed to load.
class LoadErrorPanel extends StatelessWidget {
  const LoadErrorPanel({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(Icons.error_outline, color: Colors.amberAccent),
            const SizedBox(height: 12),
            SelectableText(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown for the whole page when the renderer itself failed to start.
class ErrorPanel extends StatelessWidget {
  const ErrorPanel({super.key, required this.error, this.stack});

  final Object error;
  final StackTrace? stack;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Renderer failed to start',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          const Text(
            'Most likely the shader bundle is missing or stale. Rebuild it with '
            'tool/build_shaders.sh, then restart. The bundle format is tied to '
            'the Flutter version.',
          ),
          const SizedBox(height: 16),
          SelectableText(
            '$error\n\n${stack ?? ''}',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ],
      ),
    );
  }
}
