import 'package:flutter/material.dart';

/// Sharing, where a run can be shared or raced: a button that files the run
/// just played and says its code, and a field that takes somebody else's
/// code and races their run as a ghost.
///
/// Both answer in a sentence — the code, or why there is none — because a
/// share that failed silently is a code the player reads out to a friend
/// and nobody can open.
class ShareStrip extends StatefulWidget {
  const ShareStrip({super.key, this.onShare, required this.onRace});

  /// Files the run just played and answers what to say: its code, or why
  /// not. Null when there is no finished run to share.
  final Future<String> Function()? onShare;

  /// Opens [code] and races it; answers what to say.
  final Future<String> Function(String code) onRace;

  @override
  State<ShareStrip> createState() => _ShareStripState();
}

class _ShareStripState extends State<ShareStrip> {
  final TextEditingController _code = TextEditingController();
  String? _said;
  bool _busy = false;

  Future<void> _do(Future<String> Function() action) async {
    setState(() => _busy = true);
    final said = await action();
    if (mounted) {
      setState(() {
        _said = said;
        _busy = false;
      });
    }
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final share = widget.onShare;
    return Material(
      color: const Color(0xCC101418),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: SizedBox(
          width: 260,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (share != null)
                FilledButton(
                  key: const ValueKey<String>('share:run'),
                  onPressed: _busy ? null : () => _do(share),
                  child: const Text('Share this run'),
                ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      key: const ValueKey<String>('share:code'),
                      controller: _code,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'A friend\'s code',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    key: const ValueKey<String>('share:race'),
                    onPressed: _busy
                        ? null
                        : () => _do(() => widget.onRace(_code.text.trim())),
                    child: const Text('Race it'),
                  ),
                ],
              ),
              if (_said case final String said) ...<Widget>[
                const SizedBox(height: 8),
                SelectableText(
                  said,
                  key: const ValueKey<String>('share:said'),
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
