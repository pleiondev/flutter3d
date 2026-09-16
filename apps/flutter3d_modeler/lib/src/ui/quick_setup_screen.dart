/// The first launch, asked once — `ux-42`.
///
/// **Five questions on one page, before anything is on screen.** Every one of
/// them is already in Settings and every one of them is a thing a person knows
/// the answer to before they have used the editor at all: which buttons orbit,
/// which keys they are used to, whether a transform key acts or arms, how much
/// of the application they want to see, and what language to read it in.
/// Asking later means asking after somebody has already been annoyed by the
/// default.
///
/// **Once, and never again unless they ask.** `ModelerSettings.quickSetupDone`
/// is what remembers; Settings is where every one of these can be changed
/// afterwards, and a person who wants the page back gets it by clearing local
/// data.
///
/// **No theme question, unlike the row's own list.** This build has one
/// palette — the hand-off's own dark scheme, `theme.dart`'s `kModelerScheme`
/// — so a theme picker would be a control with one option and nothing to
/// decide. It belongs in the row that makes a second palette, not in the one
/// that asks which palette to use.
library;

import 'package:flutter/material.dart';

import '../settings.dart';

/// Opens Quick Setup over [context], starting from [current], and answers
/// with what to keep — never null, because there is no way to back out of a
/// first launch: the defaults are the answer if somebody presses Start
/// without touching anything, and that is a real answer rather than a
/// cancellation.
Future<ModelerSettings> showQuickSetup(
  BuildContext context,
  ModelerSettings current,
) async {
  final ModelerSettings? chosen = await showDialog<ModelerSettings>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) => QuickSetupScreen(settings: current),
  );
  return (chosen ?? current).copyWith(quickSetupDone: true);
}

class QuickSetupScreen extends StatefulWidget {
  const QuickSetupScreen({super.key, required this.settings});

  final ModelerSettings settings;

  @override
  State<QuickSetupScreen> createState() => _QuickSetupScreenState();
}

/// "System", as the language row's own first option — the same sentinel
/// `settings_screen.dart` uses, restated rather than shared because it is a
/// word on a menu and not a value either file stores.
const String _system = 'system';

class _QuickSetupScreenState extends State<QuickSetupScreen> {
  late ModelerSettings _draft = widget.settings;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Set up the editor'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Five answers, once. Every one of them is in Settings '
                  'afterwards.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              _Ask<NavigationScheme>(
                label: 'Camera',
                help: 'Which buttons and gestures orbit, pan and zoom.',
                value: _draft.navigation,
                values: NavigationScheme.values,
                labelOf: (NavigationScheme it) => it.label,
                onChanged: (NavigationScheme it) =>
                    setState(() => _draft = _draft.copyWith(navigation: it)),
              ),
              _Ask<KeymapPreset>(
                label: 'Keys',
                help: 'Which set of shortcuts you already know.',
                value: _draft.keymap,
                values: KeymapPreset.values,
                labelOf: (KeymapPreset it) => it.label,
                onChanged: (KeymapPreset it) =>
                    setState(() => _draft = _draft.copyWith(keymap: it)),
              ),
              _Ask<TransformStart>(
                label: 'Move, rotate and scale',
                help: 'Whether the key acts at once or arms the next drag.',
                value: _draft.transformStart,
                values: TransformStart.values,
                labelOf: (TransformStart it) => it.label,
                onChanged: (TransformStart it) => setState(
                  () => _draft = _draft.copyWith(transformStart: it),
                ),
              ),
              _Ask<Workspace>(
                label: 'How much of it',
                help:
                    'Essential is Object, Material and Scene. Full adds Mesh '
                    'and Animation.',
                value: _draft.workspace,
                values: Workspace.values,
                labelOf: (Workspace it) => it.label,
                onChanged: (Workspace it) =>
                    setState(() => _draft = _draft.copyWith(workspace: it)),
              ),
              _Ask<String>(
                label: 'Language',
                help: 'What the interface is written in.',
                value: _draft.language ?? _system,
                values: const <String>[_system, 'en', 'ru'],
                labelOf: (String it) => switch (it) {
                  'en' => 'English',
                  'ru' => 'Russian',
                  _ => 'System',
                },
                onChanged: (String it) => setState(() {
                  _draft = it == _system
                      ? _draft.copyWith(clearLanguage: true)
                      : _draft.copyWith(language: it);
                }),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_draft),
          child: const Text('Start'),
        ),
      ],
    );
  }
}

/// One question: a label, a sentence, and a dropdown.
///
/// The same shape `settings_screen.dart`'s own `_Choice` has, and deliberately
/// a separate class: this one is a first impression and carries its help text
/// under the control rather than as a subtitle inside it, which is what makes
/// a page of five of them readable in one pass.
class _Ask<T> extends StatelessWidget {
  const _Ask({
    required this.label,
    required this.help,
    required this.value,
    required this.values,
    required this.labelOf,
    required this.onChanged,
  });

  final String label;
  final String help;
  final T value;
  final List<T> values;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          DropdownButtonFormField<T>(
            initialValue: value,
            decoration: InputDecoration(
              labelText: label,
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            items: <DropdownMenuItem<T>>[
              for (final T it in values)
                DropdownMenuItem<T>(value: it, child: Text(labelOf(it))),
            ],
            onChanged: (T? it) {
              if (it != null) onChanged(it);
            },
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 12),
            child: Text(
              help,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
