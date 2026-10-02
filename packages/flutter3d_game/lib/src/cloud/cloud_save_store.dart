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

abstract interface class CloudSaveStore {
  /// The store's name as a player knows it — "Play Games", "iCloud" — for
  /// the sentences a sync answers with.
  String get name;

  /// The copy kept under [slot], if there is one.
  Future<CloudFetch> fetch(String slot);

  /// Keeps [document] under [slot] in place of the copy at [replacing], or
  /// only if there is no copy at all when [replacing] is null.
  Future<CloudPut> put(String slot, String document, {String? replacing});
}

/// What [CloudSaveStore.fetch] found.
sealed class CloudFetch {
  const CloudFetch();
}

/// What [CloudSaveStore.put] did.
sealed class CloudPut {
  const CloudPut();
}

final class CloudDocument extends CloudFetch {
  const CloudDocument(this.document, {required this.version});

  final String document;
  final String version;
}

/// Nothing is kept there yet.
final class CloudEmpty extends CloudFetch {
  const CloudEmpty();
}

final class CloudStored extends CloudPut {
  const CloudStored({required this.version});

  final String version;
}

/// Another device wrote since the version a write meant to replace.
final class CloudMoved extends CloudPut {
  const CloudMoved();
}

/// The store could not be reached, or would not do it, and why.
final class CloudUnavailable implements CloudFetch, CloudPut {
  const CloudUnavailable(this.reason);

  final String reason;
}
