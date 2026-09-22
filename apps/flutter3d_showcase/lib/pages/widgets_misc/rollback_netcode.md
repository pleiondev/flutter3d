# Rollback netcode over a loopback

`NetSession` keeps two players' worth of a fixed-step simulation in step
across a connection that delays messages and drops some of them: input
frames, a fixed delay, prediction for a step whose remote input has not
arrived, and rollback once a late confirmation disagrees with the guess.
`LoopbackTransport` is the harness it is tested against: two transports
joined by a real delay and a real loss rate, not a mock that only records
what was asked of it.

> **Note.** `flutter3d_net` is not a dependency of this app. Both classes
> need only `flutter3d_sim`'s `Snapshot` and `GameRandom` underneath, so
> this page reimplements the transport half against those same real types.
> `flutter3d_net_webrtc`, the transport for an actual connection between two
> browsers, is a native plugin with no page of its own.

## Step 1: A lossy, delayed pair

{{code transport}}

## Step 2: Two sides listening to each other

{{code session}}

## Step 3: Send with redundancy

Every message a real `NetSession` sends repeats the last few steps as well
as the current one, so one dropped packet costs nothing as long as a later
message carrying the same step's data gets through. This page repeats the
current step three times running, the same idea in miniature.

{{code redundant}}

At a 30% loss rate, both sides still end up within a step or two of the
truth, and agreeing with each other about where that is — which is the
whole point of resending rather than trusting one packet each.
