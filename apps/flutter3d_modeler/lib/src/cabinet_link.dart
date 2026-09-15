/// What the page that embedded this build in an iframe said about the
/// cabinet entry it was opened from — `tut-19`/`tut-20`.
///
/// **Parsed once, from the same query string `model`/`name` already come
/// from.** `cloud/server`'s own `web/assets/viewer.js` builds
/// `/app/?model=...&name=...&id=...&mode=...` when a person opens a model
/// from their cabinet — see `screen/files.dart`'s own `_open` for where
/// `CabinetLink.fromQuery` reads it, right beside the existing `model`/`name`
/// read.
library;

/// UX-only: which entry points this build offers, never a security boundary.
///
/// **The server decides what a save is allowed to do, every time,
/// independently.** `cloud/server`'s own `canEdit` check on
/// `/api/v1/models/<id>/source` is the real rule — a person could edit this
/// query string by hand, or a page could get it wrong, and the worst that
/// happens is a POST the server answers 404 or 403 to. What [CabinetLink]
/// decides is only whether this build *offers* the "Save to cabinet" button
/// in the first place, so it does not dangle an action in front of somebody
/// that cannot possibly succeed.
final class CabinetLink {
  const CabinetLink({
    required this.id,
    required this.mode,
    required this.csrf,
    this.isOwner = false,
    this.sourceSha,
  });

  /// No `id` at all — every launch that is not the cabinet's own iframe: a
  /// bare `flutter run`, a `--dart-define=model=` measurement run, a desktop
  /// build. [isFromCabinet] is false and nothing this stage added changes
  /// what a launch like that already did.
  static const CabinetLink none = CabinetLink(id: null, mode: null, csrf: '');

  /// The cabinet model's own numeric id, or null when this build was not
  /// opened from one.
  final int? id;

  /// `view` or `edit` — whatever the page that opened this build sent, or
  /// null when it sent nothing (today, every non-cabinet launch, and also
  /// `tut-20`'s own "a future default once the cabinet offers a real 'Edit'
  /// link" — a launch that names an [id] but no explicit `mode` is treated as
  /// editable, the same as an explicit `mode=edit` would be).
  final String? mode;

  /// The token a same-origin POST back to the cabinet needs in its own
  /// `X-CSRF` header — `cloud/server`'s own `scriptIsOurs`. Threaded through
  /// by `viewer.js`, the same way as `id`/`mode`/`editable`/`sourceSha` — see
  /// `model_page.dart`'s own `data-csrf` for where it starts. Empty only when
  /// the page that opened this build sent nothing at all, which is every
  /// non-cabinet launch.
  ///
  /// **Not the secret half of the pair `scriptIsOurs` checks.** That is the
  /// CSRF cookie itself, which is `HttpOnly` and never reaches this build —
  /// or anywhere a cross-origin page could read it — by any route, this one
  /// included; see `cabinet_save_web.dart`'s own doc comment for why the
  /// query string is the only way this value gets here at all. This token is
  /// no more sensitive sitting in that URL than it already is sitting in
  /// `model_page.dart`'s own `data-csrf` attribute, or in the hidden `csrf`
  /// field every ordinary form on that page already carries.
  final String csrf;

  /// Whether *this viewer* — the account signed in in the tab that opened
  /// this build — could edit the cabinet entry [id] names: `model_page.dart`'s
  /// own `canEdit(model, viewer)`, carried through `viewer.js`'s own
  /// `data-editable` the same way `id` already is.
  ///
  /// **UX-only, the same as every other field here.** `tut-19`'s own preview
  /// capture reads this to decide whether trying is worth it at all — a
  /// stray or hand-edited query string that claims `true` for a model this
  /// account cannot edit costs nothing beyond the one POST
  /// `/api/v1/models/<id>/preview`'s own `canEdit` check answers 404 to; see
  /// this file's own top-of-class doc comment.
  final bool isOwner;

  /// The cabinet entry's source file hash at the moment the page was
  /// rendered — `model_page.dart`'s own `data-source-sha`, threaded through
  /// `viewer.js` the same way. Null when the page sent nothing, which is
  /// every non-cabinet launch and any cabinet launch old enough to predate
  /// `tut-19`.
  ///
  /// This is what `/api/v1/models/<id>/preview`'s own `x-source-sha256`
  /// staleness check is answered with: a picture captured against a source
  /// this build opened is only accepted while the model's current source is
  /// still that exact file.
  final String? sourceSha;

  /// Whether this build was opened from a cabinet entry at all.
  bool get isFromCabinet => id != null;

  /// Whether the page that opened this build said it is here only to be
  /// looked at.
  bool get isViewOnly => mode == 'view';

  /// Whether "Save to cabinet" is worth offering: a cabinet entry to save
  /// back to, and nothing saying this build is here only to be looked at.
  bool get canSaveBack => isFromCabinet && !isViewOnly;

  /// Whether `tut-19`'s own preview capture is worth attempting once the
  /// viewport has framed the subject: a cabinet entry, opened to be looked
  /// at rather than edited, by an account that could edit it, with a source
  /// hash to tag the picture with. Every one of the four is UX-only — the
  /// server's own `canEdit` and staleness checks are what actually decide,
  /// independently, the moment the POST arrives.
  bool get shouldCapturePreview =>
      isFromCabinet &&
      isViewOnly &&
      isOwner &&
      sourceSha != null &&
      sourceSha!.isNotEmpty;

  /// Reads `id`, `mode`, `csrf`, `editable` and `sourceSha` out of a query
  /// string's own parameters — [Uri.queryParameters] shape, the same map
  /// `screen/files.dart`'s own `_open` already reads `model`/`name` out of.
  ///
  /// An `id` that is present but does not parse as an integer is treated the
  /// same as no `id` at all — [CabinetLink.none] in every field but `mode`
  /// and `csrf`, which still come along in case something downstream wants
  /// to know what the link claimed even though it could not be trusted.
  factory CabinetLink.fromQuery(Map<String, String> query) => CabinetLink(
    id: switch (query['id']) {
      final String raw? => int.tryParse(raw),
      null => null,
    },
    mode: query['mode'],
    csrf: query['csrf'] ?? '',
    isOwner: query['editable'] == 'true',
    sourceSha: query['sourceSha'],
  );
}
