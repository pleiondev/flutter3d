# Rollback between eight phones

The report P4 asks for, before the run: the protocol, the line each phone
writes, and the table it fills. Not measured yet.

## The run

- Eight phones on one Wi-Fi network, the Galaxy A55 among them, each
  running the racing demo's party race in a release build.
- Ten minutes at 60 Hz, `inputDelay 2`, `maxRollbackFrames 8`.
- Each phone measures its round trip to every other (the median and the
  99th percentile over the run, in milliseconds) and writes it; nobody
  assumes one.
- At the end each phone writes one line of the shape
  `packages/flutter3d_net/tool/rollback_report.dart` documents:
  `RollbackSession.stats.toJson()` with the machine, the device, the round
  trip, the settled digests every 100 steps and how the session ended.
- The lines are put together into this page:

      cd packages/flutter3d_net
      dart run tool/rollback_report.dart a55-*.json \
        --out ../../doc/pacing/rollback-party.md \
        --title 'Rollback between eight phones' --fail-on dropped=0.5,p99=8

## Thresholds

- `droppedCorrections` at most 0.5 % of the steps, on every phone. A
  correction counts once, when the frame that came after its step settled
  contradicts the guess it settled on.
- The 99th percentile of the time of a step run again at most 8 ms on the
  A55, the restore counted against the first step of each rollback.
- One world digest on all eight phones at the last step they all settled.
- No session dropped: every phone's line ends by `time`.

## The rehearsal on loopback

The same report, from eight sessions in one process over a loopback party
with a round trip and loss, to exercise the timer and the report before
the phones are there. Its times are the harness's small world on a desktop
CPU, so it proves the tools and not P4:

    cd packages/flutter3d_net
    dart run tool/rollback_party.dart --players 8 --rtt-ms 120 --loss 0.05 \
      --seconds 600 --out <dir> --fail-on dropped=0.5,p99=8

## Results

| Machine | Device | RTT p50 / p99 (ms) | Steps | Rollbacks | Steps run again | Settled on a guess | Dropped corrections | Resim p50 (ms) | Resim p99 (ms) | Resim max (ms) | Ended by |
|---|---|---|---|---|---|---|---|---|---|---|---|
| to measure | Galaxy A55 | | | | | | | | | | |
| to measure | | | | | | | | | | | |
| to measure | | | | | | | | | | | |
| to measure | | | | | | | | | | | |
| to measure | | | | | | | | | | | |
| to measure | | | | | | | | | | | |
| to measure | | | | | | | | | | | |
| to measure | | | | | | | | | | | |
