# flutter3d_hub

The client contract of the flutter3d model hub, models.pleion.dev: what a
reference to a model is, why the hub refuses one, how a fetched model may be
cached, and what a client and a server say to each other.

```dart
import 'package:flutter3d_hub/flutter3d_hub.dart';

final chair = HubReference.parse('0f8b5c2e-7a41-4d3b-9c6e-2a1f8e4d7b90@3');
final pinned = HubReference.parse(
  '0f8b5c2e-7a41-4d3b-9c6e-2a1f8e4d7b90@3'
  '#sha256=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
);
```

## The reference format

`<uuid>@<n>`, optionally followed by `#sha256=<64 lowercase hex digits>`.
The UUID names the model, the number its version on the hub, and the
checksum, when present, is checked against the bytes. A version on the hub
is immutable, so a reference names one file for good.

The format is fixed for good: references are written into code and levels
and stay there for years. `HubReference.parse` is the one function that
reads it, and it refuses anything else with a sentence that says what is
wrong. `test/fixtures/references.json` lists the texts it accepts and the
texts it refuses.

## Refusals

`HubRefusedException` carries a `HubRefusal`: `notFound`, `withdrawn`,
`hashMismatch`, `offline`, `tooLarge` or `protocol`. The set is open, so a
`switch` over it ends with a wildcard.

## The protocol

Every request carries the protocol version the client speaks
(`HubProtocol.version`, `1.0`), and every answer the version the server
speaks. A client reads every minor of its own major and refuses another
major with `HubRefusal.protocol`. Within a major the protocol only grows.
The exchanges and their JSON Schemas are `HubProtocol.endpoints`, and
`api/flutter3d_hub.hub` snapshots them, so a change to what a server
answers is a version decision the structure rules check.

## What this release does not do

There is no network code here yet. The client that downloads a model,
checks its hash and keeps an on-device cache keyed by it arrives as an
addition on these types. In the engine, `HubAssetSource` (in
`flutter3d_core`) names a hub model as an asset source today and refuses
to read it with `HubRefusal.offline` until then.

Hub references are for examples and prototypes. An app in production
vendors its models.
