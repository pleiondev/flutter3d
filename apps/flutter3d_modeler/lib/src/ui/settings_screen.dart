/// `ux-09`'s own screen: every setting in one dialog, each a row.
///
/// **A dialog, not a route** — the same call `shortcut_help_screen.dart` and
/// `export_screen.dart` already make, and for the same reason: this is a
/// single-screen application, and a modal keeps the document behind it rather
/// than pushing a route nothing else here uses.
///
/// **Nothing is applied until Save, and Cancel means cancel.** A settings
/// screen that writes on every tap is one nobody can back out of, and the
/// settings here change how the mouse and the keyboard behave — the two
/// things a person would want to undo fastest if they picked wrong.
///
/// **Every row is a real control rather than a segmented picture**, because
/// the acceptance asks for keyboard reach: a `DropdownButtonFormField` and a
/// `SwitchListTile` both take focus in the ordinary traversal order and both
/// answer a screen reader, which a row of tappable chips would not without a
/// wrapper each.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_editor_widgets/flutter3d_editor_widgets.dart'
    show NumberField;

import '../../l10n/app_localizations.dart';
import '../settings.dart';

/// Opens the settings dialog over [context], and answers with what to save —
/// null when the person backed out.
/// [onShowLegal] opens `rel-21d`'s own legal screen and [onClearLocalData]
/// removes what the application has written on this device, answering with a
/// sentence to show. Both optional, and a caller that passes neither gets the
/// settings dialog exactly as it was — which is what every test of the rows
/// above does.
Future<ModelerSettings?> showSettingsScreen(
  BuildContext context,
  ModelerSettings current, {
  VoidCallback? onShowLegal,
  Future<String> Function()? onClearLocalData,
}) => showDialog<ModelerSettings>(
  context: context,
  builder: (BuildContext context) => SettingsScreen(
    settings: current,
    onShowLegal: onShowLegal,
    onClearLocalData: onClearLocalData,
  ),
);

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.settings,
    this.onShowLegal,
    this.onClearLocalData,
  });

  final ModelerSettings settings;

  /// Opens the legal documents. Null hides the row.
  final VoidCallback? onShowLegal;

  /// Removes what this application has written on the device, and answers
  /// with what it removed, in a sentence. Null hides the row.
  final Future<String> Function()? onClearLocalData;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late ModelerSettings _draft = widget.settings;

  /// Asks first, then clears, then says what went.
  ///
  /// **Asked rather than undone**, because there is no undo for this: the
  /// autosave is the copy a crash would have been recovered from, and once it
  /// is gone the only thing between a person and a lost session is a file
  /// they saved themselves.
  Future<void> _clearLocalData() async {
    final Future<String> Function()? clear = widget.onClearLocalData;
    if (clear == null) return;
    final bool? sure = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(AppLocalizations.of(context).settingsClearDataTitle),
        content: Text(AppLocalizations.of(context).settingsClearDataBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(AppLocalizations.of(context).cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(AppLocalizations.of(context).settingsClear),
          ),
        ],
      ),
    );
    if (sure != true) return;
    final String said = await clear();
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(said)));
  }

  /// A step has to be a positive number: zero would divide by zero the moment
  /// the modifier was held, and a negative one would round the wrong way. A
  /// field that says otherwise keeps whatever it had.
  double _step(double said) => said.isFinite && said > 0 ? said : 0.1;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.settings),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _Choice<NavigationScheme>(
                label: l.settingsCameraNavigation,
                help: l.settingsCameraNavigationHelp,
                value: _draft.navigation,
                values: NavigationScheme.values,
                labelOf: (NavigationScheme it) => it.label,
                onChanged: (NavigationScheme it) =>
                    setState(() => _draft = _draft.copyWith(navigation: it)),
              ),
              _Choice<KeymapPreset>(
                label: l.settingsKeys,
                help: l.settingsKeysHelp,
                value: _draft.keymap,
                values: KeymapPreset.values,
                labelOf: (KeymapPreset it) => it.label,
                onChanged: (KeymapPreset it) =>
                    setState(() => _draft = _draft.copyWith(keymap: it)),
              ),
              _Choice<TransformStart>(
                label: l.settingsTransformTools,
                help: l.settingsTransformToolsHelp,
                value: _draft.transformStart,
                values: TransformStart.values,
                labelOf: (TransformStart it) => it.label,
                onChanged: (TransformStart it) => setState(
                  () => _draft = _draft.copyWith(transformStart: it),
                ),
              ),
              _Choice<Workspace>(
                label: l.settingsWorkspace,
                help: l.settingsWorkspaceHelp,
                value: _draft.workspace,
                values: Workspace.values,
                labelOf: (Workspace it) => it.label,
                onChanged: (Workspace it) =>
                    setState(() => _draft = _draft.copyWith(workspace: it)),
              ),
              _Choice<String>(
                label: l.settingsLanguage,
                help: l.settingsLanguageHelp,
                value: _draft.language ?? _system,
                values: const <String>[_system, 'en', 'ru'],
                // **Named in English rather than each in its own language.** A
                // picker usually shows endonyms — "Русский" beside "English" —
                // and a hardcoded one here would be the one Cyrillic string in
                // `lib/`, which `ui-22`'s own rule exists to keep out. `ux-22`
                // takes the whole interface through `AppLocalizations`, and the
                // endonyms belong in the same pass rather than as one exception
                // ahead of it.
                labelOf: (String it) => switch (it) {
                  'en' => l.settingsLanguageEnglish,
                  'ru' => l.settingsLanguageRussian,
                  _ => l.settingsLanguageSystem,
                },
                onChanged: (String it) => setState(() {
                  _draft = it == _system
                      ? _draft.copyWith(clearLanguage: true)
                      : _draft.copyWith(language: it);
                }),
              ),
              const SizedBox(height: 8),
              // `ux-11`: what holding the snap modifier rounds to. Three
              // numbers rather than one, because a tenth of a radian is not a
              // step anybody thinks in — and the label beside the pointer
              // during a transform says which of them is live.
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  l.settingsSnapSteps,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              Row(
                children: <Widget>[
                  Expanded(
                    child: NumberField(
                      label: l.settingsStepMove,
                      labelWidth: 44,
                      value: _draft.snapMove,
                      onChanged: (double it) => setState(
                        () => _draft = _draft.copyWith(snapMove: _step(it)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: NumberField(
                      label: l.settingsStepTurn,
                      labelWidth: 44,
                      value: _draft.snapTurnDegrees,
                      onChanged: (double it) => setState(
                        () => _draft = _draft.copyWith(
                          snapTurnDegrees: _step(it),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: NumberField(
                      label: l.settingsStepScale,
                      labelWidth: 44,
                      value: _draft.snapScale,
                      onChanged: (double it) => setState(
                        () => _draft = _draft.copyWith(snapScale: _step(it)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l.settingsShowHome),
                subtitle: Text(l.settingsShowHomeHelp),
                value: _draft.showHomeAtLaunch,
                onChanged: (bool it) => setState(
                  () => _draft = _draft.copyWith(showHomeAtLaunch: it),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l.settingsSaveHistory),
                subtitle: Text(l.settingsSaveHistoryHelp),
                value: _draft.saveWithHistory,
                onChanged: (bool it) => setState(
                  () => _draft = _draft.copyWith(saveWithHistory: it),
                ),
              ),
              // `rel-21d`: the two rows that are about the person's rights and
              // their data rather than about how the editor behaves. Here
              // rather than behind a seventh icon in the top bar, which is
              // where a person looking for either of them would not think to
              // look anyway — "where do I turn things off and get my data
              // back" is what a settings screen is.
              if (widget.onShowLegal != null ||
                  widget.onClearLocalData != null) ...<Widget>[
                const Divider(height: 32),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    l.settingsLegalSection,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                if (widget.onShowLegal case final VoidCallback open)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.gavel_outlined),
                    title: Text(l.settingsLegal),
                    subtitle: Text(l.settingsLegalHelp),
                    onTap: open,
                  ),
                if (widget.onClearLocalData != null)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.delete_sweep_outlined),
                    title: Text(l.settingsClearData),
                    subtitle: Text(l.settingsClearDataHelp),
                    onTap: _clearLocalData,
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_draft),
          child: Text(l.save),
        ),
      ],
    );
  }

  /// The value that means "no language of its own", which is null on
  /// [ModelerSettings] and needs something to stand for it in a dropdown.
  static const String _system = 'system';
}

/// One labelled dropdown with a sentence under it.
class _Choice<T> extends StatelessWidget {
  const _Choice({
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
  final void Function(T) onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        DropdownButtonFormField<T>(
          initialValue: value,
          decoration: InputDecoration(labelText: label, helperText: help),
          items: <DropdownMenuItem<T>>[
            for (final T it in values)
              DropdownMenuItem<T>(value: it, child: Text(labelOf(it))),
          ],
          onChanged: (T? it) {
            if (it != null) onChanged(it);
          },
        ),
      ],
    ),
  );
}
