import 'dart:async';
import 'dart:typed_data';

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show ResourceException;

import 'asset_resolver.dart';

/// Where a model and its sibling files live.
///
/// A sendable *description* rather than a resolver closure, because that is what
/// crosses an isolate boundary: the background isolate reconstructs the resolver
/// from this instead of receiving a callback that closes over the asset bundle.
///
/// **Open, and without a registry.** A game whose assets live somewhere this
/// package has never heard of — inside an archive, behind a network cache, in a
/// database — writes its own source and passes it. Sealing said the engine has
/// the full list of places an asset can be, which was never true.
///
/// A registry was the obvious way to open it and is the wrong one here, for the
/// reason [ModelLoadRequest.decoders] is written down at length: decoding runs
/// on a background isolate, statics are not shared across isolates in Dart, and
/// a registry filled at startup in the main isolate is empty in the one that
/// does the reading. It would work in a test and fail in the application. So a
/// source travels with the request exactly as a decoder does — which means it
/// must be **sendable**: a plain object holding plain data. A source that
/// closes over a texture, a device or a port cannot cross and will say so at
/// run time.
///
/// **The two sources this repository ships are not here**, and the split is the
/// same one that made this a package: `BundleAssetSource` reads Flutter's asset
/// bundle and `FileAssetSource` reads `dart:io`, so both live in `flutter3d`,
/// which may name either. What is left is what a decoder actually needs — a
/// key, some bytes and a resolver — and it compiles wherever Dart does.
///
/// `base`: extend it, do not implement it, so a member added here later is
/// inherited rather than missing.
///
/// A subclass owes [key], [read] and [resolveUri]. [key] is the cache key, so
/// two sources naming the same file must agree on it and two naming different
/// files must not collide — prefix it the way the engine's two do.
abstract base class AssetSource {
  const AssetSource();

  /// Stable identity, used as the cache key.
  ///
  /// **A source with a [version] puts it in the key**, so two versions of
  /// one asset never share a cache entry: a level that moves a model from
  /// version 3 to 4 gets the new file, not the one already decoded. Two
  /// sources that differ only in [contentHash] name the same file and may
  /// share a key.
  String get key;

  /// The SHA-256 of the file [read] returns, as 64 lowercase hexadecimal
  /// digits, when the source knows it ahead of reading; null when it does
  /// not, which is every source that reads a file it did not publish.
  ///
  /// A promise about the bytes: a reader that checks it refuses bytes that
  /// do not match rather than decoding them. Null by default, so a source
  /// written against 1.0 says nothing and is read as before.
  String? get contentHash => null;

  /// The asset's version in the place it comes from (a model's version on
  /// the hub, a store's revision), from 1; null for a source with no
  /// versions, which is a file on disk or in a bundle.
  ///
  /// Part of [key] when it is not null. Null by default.
  int? get version => null;

  /// The file itself, read as [request] asks.
  ///
  /// **One request, so a minor can ask for more.** [AssetRead] carries
  /// what a reader wants of this read: a progress listener a source with
  /// something to report calls as bytes arrive, a cancel signal a source
  /// that can stop early checks, and the byte range a pager wants. A source
  /// that cannot do one of them ignores it and reads the whole file, which
  /// is always correct; the loaders check the signal around the call
  /// themselves. A caller with nothing to ask hands [AssetRead.whole].
  Future<Uint8List> read(AssetRead request);

  /// Resolves files referenced from inside the model, relative to its directory.
  AssetUriResolver get resolveUri;

  /// Everything after the last path separator.
  String get fileName {
    final path = key;
    final slash = path.lastIndexOf('/');
    return slash < 0 ? path : path.substring(slash + 1);
  }
}

/// What a reader asks of one [AssetSource.read]: progress, a way to stop,
/// and the bytes it wants.
///
/// **Final and growing**: a later minor adds a member here, with a default,
/// and every source written against 1.0 still compiles and reads the whole
/// file. Built on the reader's side and never sent to an isolate: the
/// loaders read a model's file where they were called and send only its
/// bytes, so [onProgress] may close over anything.
final class AssetRead {
  const AssetRead({this.onProgress, this.cancel, this.range});

  /// Nothing asked: the whole file, nobody listening, never canceled.
  static const AssetRead whole = AssetRead();

  /// Told as the bytes arrive, by a source that can tell: a network source
  /// per chunk, a file source once. A source that cannot tell says nothing,
  /// and a loader reports the whole file once it has it.
  final void Function(AssetProgress progress)? onProgress;

  /// Called off by the reader. A source that can stop early checks it
  /// ([throwIfCanceled]) or listens ([AssetCancel.whenCanceled]); one that
  /// cannot finishes its read, and the loader drops the bytes.
  final AssetCancel? cancel;

  /// The bytes wanted, for a reader that pages through a big file (splats,
  /// a point cloud's octree); null is the whole file. A source that cannot
  /// read a range reads the whole file, and the reader takes the range
  /// from it, so a range is a saving, never a different answer.
  final AssetByteRange? range;

  /// Whether [cancel] has been called.
  bool get isCanceled => cancel?.isCanceled ?? false;

  /// Throws [ResourceLoadCanceledException] naming [key] when [cancel] has
  /// been called: what a source checks between chunks.
  void throwIfCanceled(Object? key) => cancel?.throwIfCanceled(key);

  /// Tells [onProgress] that [received] bytes of [total] have arrived.
  void progress(int received, {int? total}) =>
      onProgress?.call(AssetProgress(received: received, total: total));

  /// [source] read as this asks, the way every loader reads one: refused
  /// before the call and after it once [cancel] has been called, so a
  /// source that never looks at the signal still stops the load, and the
  /// whole file reported to [onProgress] once it has arrived, so a source
  /// that never reports still ends at one.
  Future<Uint8List> readFrom(AssetSource source) async {
    throwIfCanceled(source.key);
    final bytes = await source.read(this);
    throwIfCanceled(source.key);
    progress(bytes.length, total: bytes.length);
    return bytes;
  }
}

/// How far a read has come: [received] bytes of [total].
final class AssetProgress {
  const AssetProgress({required this.received, this.total});

  /// Bytes arrived so far.
  final int received;

  /// The file's length in bytes, or the range's; null when the source does
  /// not know it ahead (a stream with no length).
  final int? total;

  /// [received] over [total], nought to one; null when [total] is unknown.
  double? get fraction => switch (total) {
    final t? when t > 0 => (received / t).clamp(0.0, 1.0),
    0 => 1.0,
    _ => null,
  };

  @override
  String toString() => 'AssetProgress($received of ${total ?? '?'})';
}

/// A read called off: the signal a reader keeps and a source watches.
///
/// **The engine's own**, since Dart has no standard cancellation token:
/// one [cancel] by whoever started the read (a widget gone, a level left),
/// seen by every source and loader it was handed to. Canceling twice is
/// canceling once.
final class AssetCancel {
  AssetCancel();

  final Completer<void> _canceled = Completer<void>();

  /// Whether [cancel] has been called.
  bool get isCanceled => _canceled.isCompleted;

  /// Completes when [cancel] is called: what a source with a request in
  /// flight listens to, to abort it.
  Future<void> get whenCanceled => _canceled.future;

  /// Calls the read off. Every read handed this signal stops at its next
  /// check, and the load it belongs to fails with
  /// [ResourceLoadCanceledException].
  void cancel() {
    if (!_canceled.isCompleted) _canceled.complete();
  }

  /// Throws [ResourceLoadCanceledException] naming [key] once [cancel] has
  /// been called.
  void throwIfCanceled(Object? key) {
    if (isCanceled) throw ResourceLoadCanceledException(key);
  }
}

/// The bytes from [start] up to [end] of a file, [end] not included; to
/// the end of the file when [end] is null.
final class AssetByteRange {
  const AssetByteRange(this.start, {this.end})
    : assert(start >= 0, 'a range starts at byte 0 or after');

  /// The first byte wanted.
  final int start;

  /// The byte after the last one wanted; null reads to the end.
  final int? end;

  /// How many bytes, when [end] is known.
  int? get length {
    final last = end;
    if (last == null) return null;
    if (last < start) {
      throw ArgumentError.value(last, 'end', 'is before start $start');
    }
    return last - start;
  }

  /// [bytes], a whole file, cut to this range: what a reader does with a
  /// source that could not read a range itself.
  Uint8List of(Uint8List bytes) => Uint8List.sublistView(
    bytes,
    start.clamp(0, bytes.length),
    (end ?? bytes.length).clamp(start.clamp(0, bytes.length), bytes.length),
  );

  @override
  bool operator ==(Object other) =>
      other is AssetByteRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'AssetByteRange($start, ${end ?? 'end'})';
}

/// A read or a request for a cached resource that was called off before it
/// was handed over: what [AssetCancel] throws and what
/// `ResourceRequest.handle` completes with after `ResourceRequest.cancel`.
final class ResourceLoadCanceledException extends ResourceException {
  const ResourceLoadCanceledException(this.key);

  /// The key that was asked for.
  final Object? key;

  @override
  String get message => 'the request for $key was canceled';

  @override
  String toString() => 'ResourceLoadCanceledException: $message';
}

/// A reference inside a model is always relative to the model. An absolute path
/// or a `..` segment means the file is reaching outside its directory, which is
/// worth refusing rather than resolving.
///
/// Public because the sources that need it are in another package now, and a
/// second copy of this check is a second chance to get it wrong.
String safeRelativeAssetPath(String uri) {
  final relative = Uri.decodeComponent(uri);
  if (relative.startsWith('/') ||
      relative.startsWith(r'\') ||
      relative.contains('://') ||
      relative.split(RegExp(r'[/\\]')).contains('..')) {
    throw ArgumentError(
      'Refusing to load "$uri": it escapes the asset directory.',
    );
  }
  return relative;
}
