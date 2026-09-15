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
  const CabinetLink({required this.id, required this.mode, required this.csrf});

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
  /// `X-CSRF` header — `cloud/server`'s own `scriptIsOurs`. Empty when the
  /// page that opened this build did not send one, which is always true
  /// today: `viewer.js` names `id`, but threading a real token through the
  /// iframe URL is left for whichever stage builds the cabinet's own "Edit"
  /// link, since nothing reachable today ever sends `mode=edit` for this to
  /// matter yet.
  final String csrf;

  /// Whether this build was opened from a cabinet entry at all.
  bool get isFromCabinet => id != null;

  /// Whether the page that opened this build said it is here only to be
  /// looked at.
  bool get isViewOnly => mode == 'view';

  /// Whether "Save to cabinet" is worth offering: a cabinet entry to save
  /// back to, and nothing saying this build is here only to be looked at.
  bool get canSaveBack => isFromCabinet && !isViewOnly;

  /// Reads `id`, `mode` and `csrf` out of a query string's own parameters —
  /// [Uri.queryParameters] shape, the same map `screen/files.dart`'s own
  /// `_open` already reads `model`/`name` out of.
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
  );
}
