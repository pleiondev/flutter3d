/// Which legal documents there are, and how the application gets them —
/// `rel-21d`.
///
/// **Bundled, not fetched.** A link to a privacy policy is what an app store
/// requires and not what a person on a plane can read. These are assets, so
/// Help → Legal answers with no network at all — and answers with the exact
/// text this build shipped under, rather than with whatever the website says
/// today.
library;

import 'package:flutter/services.dart';

import 'legal_document.dart';

/// The six, in the order the screen lists them: the agreement first, because
/// it is the one that governs the rest; then what happens to your data, which
/// is the question people actually arrive with; then the two about the
/// website; then the two nobody reads until they need them.
const List<String> kLegalDocuments = <String>[
  'eula.md',
  'privacy.md',
  'cookies.md',
  'terms.md',
  'content-policy.md',
  'export-compliance.md',
];

/// Where a document is bundled. Also what `tool/sync_legal.dart` writes and
/// what the pubspec declares, said once here so the three cannot disagree.
String legalAssetPath(String name) => 'assets/legal/$name';

/// [name], read and parsed.
///
/// [bundle] is for a test that wants to hand in its own text; every real
/// caller leaves it, and gets `rootBundle`.
Future<LegalDocument> loadLegalDocument(
  String name, {
  AssetBundle? bundle,
}) async => parseLegalDocument(
  await (bundle ?? rootBundle).loadString(legalAssetPath(name)),
  name: name,
);

/// All of [kLegalDocuments], in that order.
///
/// **One await, not six sequential ones.** They are six small files off the
/// same bundle, and reading them in parallel means the screen's own spinner is
/// gone in one frame rather than six.
Future<List<LegalDocument>> loadLegalDocuments({AssetBundle? bundle}) =>
    Future.wait(<Future<LegalDocument>>[
      for (final String name in kLegalDocuments)
        loadLegalDocument(name, bundle: bundle),
    ]);
