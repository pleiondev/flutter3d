/// Help → Legal — `rel-21d`.
///
/// **The documents, in the application, offline.** An app store asks for a
/// privacy policy URL and is satisfied by a link; a person who wants to know
/// what happens to their models is not, particularly the person who wants to
/// know it before agreeing to anything. So these are bundled assets, shown
/// here, at the version this build actually shipped under.
///
/// **The third-party licences are not one of them.** That list is generated
/// from what is linked into the binary — Flutter's own `LicenseRegistry` —
/// and a copy of it written by hand would be wrong by the next `pub upgrade`.
/// The row opens `showLicensePage`, which is the real list.
library;

import 'package:flutter/material.dart';

import '../legal/legal_document.dart';
import '../legal/legal_library.dart';
import '../legal/legal_view.dart';
import 'roomy_dialog.dart';

/// What a row in the list is called. Shorter than the document's own title,
/// which is a legal heading and not a menu item.
const Map<String, String> kLegalTitles = <String, String>{
  'eula.md': 'Licence agreement',
  'privacy.md': 'Privacy',
  'cookies.md': 'Cookies & storage',
  'terms.md': 'Website terms',
  'content-policy.md': 'Content & copyright',
  'export-compliance.md': 'Export compliance',
};

/// A one-line answer to "what is in this one", so the list is navigable
/// without opening all six.
const Map<String, String> kLegalSummaries = <String, String>{
  'eula.md': 'MIT, and what MIT does not cover',
  'privacy.md': 'Nothing leaves your device unless you send it',
  'cookies.md': 'No cookies, and why there is no banner',
  'terms.md': 'Using the documentation and the demos',
  'content-policy.md': 'Copyright notices, and what we do not host',
  'export-compliance.md': 'Publicly available, no cryptography',
};

/// Opens the legal screen over [context].
///
/// [bundle] and [openedAt] are for tests: one hands in the documents, the
/// other names which one to open on. Every real caller passes neither and
/// gets the bundled six with the licence agreement showing.
Future<void> showLegalScreen(
  BuildContext context, {
  AssetBundle? bundle,
  String? openedAt,
}) => showDialog<void>(
  context: context,
  builder: (BuildContext context) =>
      LegalScreen(bundle: bundle, openedAt: openedAt),
);

class LegalScreen extends StatefulWidget {
  const LegalScreen({super.key, this.bundle, this.openedAt});

  final AssetBundle? bundle;
  final String? openedAt;

  @override
  State<LegalScreen> createState() => _LegalScreenState();
}

class _LegalScreenState extends State<LegalScreen> {
  late final Future<List<LegalDocument>> _documents = loadLegalDocuments(
    bundle: widget.bundle,
  );
  late String _showing = widget.openedAt ?? kLegalDocuments.first;

  @override
  Widget build(BuildContext context) => RoomyDialog(
    title: 'Legal',
    width: 900,
    height: 620,
    onClose: () => Navigator.of(context).pop(),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Close'),
      ),
    ],
    wide: _Body(
      showing: _showing,
      onShow: (String name) => setState(() => _showing = name),
      documents: _documents,
      stacked: false,
    ),
    narrow: _Body(
      showing: _showing,
      onShow: (String name) => setState(() => _showing = name),
      documents: _documents,
      stacked: true,
    ),
  );
}

class _Body extends StatelessWidget {
  const _Body({
    required this.showing,
    required this.onShow,
    required this.documents,
    required this.stacked,
  });

  final String showing;
  final ValueChanged<String> onShow;
  final Future<List<LegalDocument>> documents;

  /// Whether the list goes above the text rather than beside it — the
  /// full-screen shape `RoomyDialog` gives a window that cannot hold the
  /// desktop one.
  final bool stacked;

  @override
  Widget build(BuildContext context) => FutureBuilder<List<LegalDocument>>(
    future: documents,
    builder:
        (
          BuildContext context,
          AsyncSnapshot<List<LegalDocument>> snapshot,
        ) {
          if (snapshot.hasError) {
            // A bundle that will not give up its own assets is a broken
            // build, and saying so beats an empty pane that looks like a
            // document with nothing in it.
            return Center(
              child: Text('The documents did not load: ${snapshot.error}'),
            );
          }
          final List<LegalDocument>? loaded = snapshot.data;
          if (loaded == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final LegalDocument document = loaded.firstWhere(
            (LegalDocument it) => it.name == showing,
            orElse: () => loaded.first,
          );
          final Widget list = _Chooser(
            documents: loaded,
            showing: document.name,
            onShow: onShow,
            stacked: stacked,
          );
          final Widget text = LegalView(
            key: ValueKey<String>(document.name),
            document: document,
          );
          return stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    list,
                    const Divider(height: 1),
                    Expanded(child: text),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    SizedBox(width: 240, child: list),
                    const VerticalDivider(width: 1),
                    Expanded(child: text),
                  ],
                );
        },
  );
}

class _Chooser extends StatelessWidget {
  const _Chooser({
    required this.documents,
    required this.showing,
    required this.onShow,
    required this.stacked,
  });

  final List<LegalDocument> documents;
  final String showing;
  final ValueChanged<String> onShow;
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    if (stacked) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            DropdownButtonFormField<String>(
              initialValue: showing,
              decoration: const InputDecoration(
                labelText: 'Document',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: <DropdownMenuItem<String>>[
                for (final LegalDocument it in documents)
                  DropdownMenuItem<String>(
                    value: it.name,
                    child: Text(kLegalTitles[it.name] ?? it.title),
                  ),
              ],
              onChanged: (String? name) {
                if (name != null) onShow(name);
              },
            ),
            const SizedBox(height: 8),
            const _ThirdPartyButton(),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: <Widget>[
        for (final LegalDocument it in documents)
          ListTile(
            dense: true,
            selected: it.name == showing,
            title: Text(kLegalTitles[it.name] ?? it.title),
            subtitle: Text(
              kLegalSummaries[it.name] ?? '',
              style: theme.textTheme.bodySmall,
            ),
            onTap: () => onShow(it.name),
          ),
        const Divider(),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: _ThirdPartyButton(),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
          child: Text(
            'These documents are published in English only, whatever the '
            'interface language: one authentic version, so there is never a '
            'question of which one binds.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _ThirdPartyButton extends StatelessWidget {
  const _ThirdPartyButton();

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    icon: const Icon(Icons.inventory_2_outlined, size: 18),
    label: const Text('Third-party licences'),
    onPressed: () => showLicensePage(
      context: context,
      applicationName: 'flutter3d Modeler',
      applicationLegalese: '© 2026 Dmitrii Zolotov. MIT licence.',
    ),
  );
}
