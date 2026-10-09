# flame_multiplayer

Two players on two machines, for a game that steps in fixed steps. No
dependencies: not Flame, not Flutter, not a socket library. A game calls it
from its own fixed step, and the wire to a real network is an adapter.

```dart
final room = PeerRoom(wire, slot: joined ? 1 : 0, about: {'class': 'elf'});

// Once a fixed step:
room.step(dt);
if (room.met) startWith(room.peer!['class']);
```

## Four ways to share a game

**`PeerRoom`** is who is who. Whoever made the room is slot nought on both
machines. It says hello, with whatever the machine tells about itself, until
the other answers; a relay passes on nothing sent before both were there, so
one greeting is not enough. `channel('level:2')` is a conversation of its
own on the same wire, and frames of the last level still in flight never
land in the next.

**`RollbackPlay`** is both machines playing one simulation in step, each
driving its own player: the input delay, the guess of the other's hands, the
rollback when the guess was wrong. The game hands it four functions —
capture this machine's hands, apply both and step, save, restore — and the
state can be any type. `endsAt` says what an ending looks like, and
`agreedEnd` is the first settled step that shows one, the same on both
machines, so a game goes on to its next level from the same state.

**`BatonStream`** is taking turns. The machine whose turn it is plays as a
game on its own would, and tells the other each step what to draw and
whatever it decided; the other replays that at the pace it was played, and
catches up if it falls behind. Nothing needs to be deterministic. The turn
goes across with the state it starts from.

**`PeerFeed`** is two games side by side, a race over the same course: each
tells the other where it is, and the latest word is all that counts.

## Wires

`PeerWire` is two methods: send a JSON-shaped map, reliably or not, and
listen. `LoopbackWire.pair(delaySteps: 6, lossRate: 0.1)` is two ends in one
process, as late and as lossy as a test asks; it loses only unreliable
messages, because that is the promise the other kind makes.

- `flutter3d_net`'s `NetTransportWire` carries it over that package's relay
  WebSocket and WebRTC transports.
- `flame_multiplayer_dashwire`'s `DashwireWire` carries it over a
  [dashwire](https://pub.dev/packages/dashwire) connection, with reliable and
  unreliable messages on dashwire's two channels.

A turn's messages are numbered and put back in order on arrival. I found
out why while writing the dashwire adapter: its network simulator keeps
every reliable message but not always their order, and a replay of a turn
with frame 22 after frame 23 is not the turn that was played.
