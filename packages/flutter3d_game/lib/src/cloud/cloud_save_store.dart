/// Somewhere other than this device that a save can be kept.
///
/// ## Answers, not exceptions
///
/// A network that is down, a player signed out of Play Games, an iCloud
/// account with no space: all ordinary, all reached on a launch the player
/// expects to work. So every call answers, and an answer that is not the
/// document says why in a sentence [SaveSync] can show. Nothing here throws
/// for a reason the network gave.
///
/// ## Versions
///
/// Every copy comes back with a version the store chose — an HTTP `ETag`,
/// Play Games' snapshot revision, an iCloud change token — and a write names
/// the version it means to replace. A store that has moved on since answers
/// [CloudMoved] rather than writing, so two devices syncing at once cannot
/// both win and silently lose one of the runs.
library;

/// **Implementable outside this package, as a base class**: a member added in
/// a minor release arrives with a default body, so a store written against
/// 1.0 keeps compiling — `extends CloudSaveStore`, not `implements`.
abstract base class CloudSaveStore {
  /// Lets a subclass be a `const` value; the base holds no state.
  const CloudSaveStore();

  /// The store's name as a player knows it — "Play Games", "iCloud" — for
  /// the sentences a sync answers with.
  String get name;

  /// The copy kept under [slot], if there is one.
  Future<CloudFetch> fetch(String slot);

  /// Keeps the request's document under its slot in place of the copy at
  /// [CloudPutRequest.replacing], or only if there is no copy at all when
  /// that is null.
  Future<CloudPut> put(CloudPutRequest request);
}

/// What [CloudSaveStore.put] is handed.
///
/// **One object, so a minor can hand a store more** — a description for
/// the platform's save list, a cover picture — without breaking a store
/// written against 1.0.
final class CloudPutRequest {
  /// A request to keep [document] under [slot], replacing the copy at
  /// [replacing] or, when that is null, only where there is none.
  const CloudPutRequest({
    required this.slot,
    required this.document,
    this.replacing,
  });

  /// The name the copy is kept under.
  final String slot;

  /// The save, as `SaveFile.encode` writes it.
  final String document;

  /// The version of the copy this replaces; null to write only where there
  /// is no copy yet.
  final String? replacing;
}

/// What [CloudSaveStore.fetch] found.
///
/// **Closed for good, and sealed on purpose.** A sync answers every case and nothing else can
/// happen to a fetch — there is a copy, there is none, or the store could not
/// say — so a `switch` over it is exhaustive and a case that went unhandled
/// would be a run silently lost. A fourth answer would be a new protocol, and
/// waits for a major.
sealed class CloudFetch {
  /// Lets the cases be `const` values.
  const CloudFetch();
}

/// What [CloudSaveStore.put] did.
///
/// **Closed for good, and sealed on purpose**, for the reason [CloudFetch] is: kept, overtaken by
/// another device, or not reachable are the whole of what a write can do.
sealed class CloudPut {
  /// Lets the cases be `const` values.
  const CloudPut();
}

/// A copy is kept there: its document and the version the store gave it.
final class CloudDocument extends CloudFetch {
  /// A fetched copy, [document] at [version].
  const CloudDocument(this.document, {required this.version});

  /// The save, as `SaveFile.encode` wrote it.
  final String document;

  /// The store's own version of the copy, to name in
  /// [CloudPutRequest.replacing] when writing over it.
  final String version;
}

/// Nothing is kept there yet.
final class CloudEmpty extends CloudFetch {
  /// The answer for a slot with no copy.
  const CloudEmpty();
}

/// The write was kept, and the version the store gave the new copy.
final class CloudStored extends CloudPut {
  /// A kept write, now at [version].
  const CloudStored({required this.version});

  /// The store's version of the copy just written, to name in the next
  /// [CloudPutRequest.replacing].
  final String version;
}

/// Another device wrote since the version a write meant to replace.
final class CloudMoved extends CloudPut {
  /// The answer for a write that was overtaken and not kept.
  const CloudMoved();
}

/// The store could not be reached, or would not do it, and why.
final class CloudUnavailable implements CloudFetch, CloudPut {
  /// An answer that is not the document, with [reason] for the player.
  const CloudUnavailable(this.reason);

  /// Why, in a sentence [SaveSync] can show the player.
  final String reason;
}
