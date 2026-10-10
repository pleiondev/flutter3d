import 'package:flutter/material.dart';

import '../l10n/game_localizations.dart';

/// Sharing, where a run can be shared or opened: a button that files the
/// run just played and says its code, and a field that takes somebody
/// else's code and opens their run — raced as a ghost, watched, replayed,
/// whatever the game does with one.
///
/// Both answer in a sentence — the code, or why there is none — because a
/// share that failed silently is a code the player reads out to a friend
/// and nobody can open.
///
/// The keys a test finds it by are `share:run`, `share:code`, `share:open`
/// and `share:said`.
class ShareStrip extends StatefulWidget {
  const ShareStrip({
    super.key,
    this.onShare,
    required this.onOpen,
    this.shareLabel,
    this.codeHint,
    this.openLabel,
  });

  /// Files the run just played and answers what to say: its code, or why
  /// not. Null when there is no finished run to share, and then there is no
  /// button that cannot work.
  final Future<String> Function()? onShare;

  /// Opens [code], trimmed, and answers what to say.
  final Future<String> Function(String code) onOpen;

  /// The share button's words; null for
  /// [Flutter3dGameLocalizations.shareThisRun].
  final String? shareLabel;

  /// What the empty code field says; null for
  /// [Flutter3dGameLocalizations.aFriendsCode].
  final String? codeHint;

  /// The words on the button that opens a code — what the game does with
  /// somebody else's run; null for [Flutter3dGameLocalizations.openTheirRun].
  final String? openLabel;

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
    final words = Flutter3dGameLocalizations.of(context);
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
                  child: Text(widget.shareLabel ?? words.shareThisRun),
                ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      key: const ValueKey<String>('share:code'),
                      controller: _code,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: widget.codeHint ?? words.aFriendsCode,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    key: const ValueKey<String>('share:open'),
                    onPressed: _busy
                        ? null
                        : () => _do(() => widget.onOpen(_code.text.trim())),
                    child: Text(widget.openLabel ?? words.openTheirRun),
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
