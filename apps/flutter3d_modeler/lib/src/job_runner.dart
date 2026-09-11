/// A cancellable computation reported in chunks — `ui-25`'s own runner for
/// the jobs `doc-24`'s `JobRequest` already describes as values.
///
/// **Progress and cancellation live here, not at the isolate boundary.**
/// `editInIsolate` in `flutter3d_mesh` already decides *whether* one unit of
/// work leaves this isolate; a [Job] decides how many units a `JobButton`
/// sees between armed and done, which is a different question with a
/// different answer even for work `editInIsolate` would run in a single hop.
/// So [Job] never spawns anything itself — [runChunk] is a caller's own
/// closure, built on `Isolate.run` on native or a plain `await` with a yield
/// between chunks on the web, `ui-25`'s own "`Isolate.run` на native, чанки с
/// уступкой на вебе" — and this file only counts what came back.
///
/// **Checked between chunks, not inside one.** A chunk already running
/// finishes before [cancel] takes effect, since a result built from a chunk
/// stopped halfway would be built from an inconsistent mix of finished and
/// unfinished work — the same reason a transaction is one step or none.
library;

/// What a [Job] answered: a value, or nothing because it was cancelled first.
///
/// Two cases rather than a nullable value, because a `T` that is itself
/// nullable would make a cancelled job indistinguishable from a finished one
/// that legitimately answered null.
sealed class JobOutcome<T> {
  const JobOutcome();
}

/// Every chunk ran, and here is what they built together.
final class JobFinished<T> extends JobOutcome<T> {
  const JobFinished(this.value);

  final T value;
}

/// [Job.cancel] was called before some chunk started running.
final class JobCancelled<T> extends JobOutcome<T> {
  const JobCancelled();
}

/// [chunkCount] calls to [runChunk], each one [progress] step further along.
///
/// A `JobButton` reads [progress] to draw its own indicator and calls
/// [cancel] for its own button press; nothing else about the shape of the
/// work — what a chunk is, how many there are, what they add up to — is this
/// class's business, which is why [runChunk] and the value [run] eventually
/// returns are both generic.
final class Job<T> {
  Job({required this.chunkCount, required this.runChunk, this.onProgress})
    : assert(chunkCount > 0, 'a job of zero chunks has nothing to report');

  /// How many calls to [runChunk] make up the whole job — `ui-25`'s own
  /// worked example uses ten.
  final int chunkCount;

  /// Does chunk [index]'s own share of the work. Whatever it returns is
  /// discarded; [run]'s own `combine` argument is what turns finished chunks
  /// into a result, since some jobs have nothing to combine — only a side
  /// effect chunk after chunk.
  final Future<void> Function(int index) runChunk;

  /// Told [progress] every time it moves, so a `JobButton` does not have to
  /// poll a field between frames to know when to repaint.
  final void Function(double progress)? onProgress;

  double _progress = 0.0;

  /// How far through [chunkCount] the last completed chunk left this job, from
  /// 0 (nothing run yet) to 1 (every chunk ran).
  double get progress => _progress;

  bool _cancelRequested = false;

  /// Asks this job to stop before its next chunk starts.
  ///
  /// Idempotent, and safe to call whether or not the job is still running: a
  /// button pressed twice, or pressed after the job already finished, asks
  /// for the same thing it would have the first time and changes nothing a
  /// second time.
  void cancel() => _cancelRequested = true;

  /// Runs every chunk in order, reporting [progress] after each, until either
  /// they are all done or [cancel] was called first.
  ///
  /// [combine] builds the result from whatever state [runChunk] accumulated
  /// on the side — called only if every chunk ran, since a job cancelled
  /// partway has nothing complete enough to combine.
  Future<JobOutcome<T>> run(T Function() combine) async {
    for (var index = 0; index < chunkCount; index++) {
      if (_cancelRequested) return const JobCancelled();
      await runChunk(index);
      _progress = (index + 1) / chunkCount;
      onProgress?.call(_progress);
    }
    return JobFinished<T>(combine());
  }
}
