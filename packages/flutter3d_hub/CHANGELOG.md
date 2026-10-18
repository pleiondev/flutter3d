## 1.0.0-rc.1

- **New: the model hub's client contract, as a package of its own.**
  `HubReference` reads the reference format `<uuid>@<n>` with an optional
  `#sha256=` checksum, fixed for good, through one function, `parse`, that
  refuses anything else with a `HubReferenceFormatException` saying what is
  wrong. `HubRefusedException` carries a `HubRefusal` (`notFound`, `withdrawn`,
  `hashMismatch`, `offline`, `tooLarge`, `protocol`), an open set.
  `HubCachePolicy` says where a model may come from and whether it is kept.
- **New: the server protocol as an interface.** `HubProtocol.version` is
  `1.0`; every request carries it, every answer carries the server's own,
  and `HubProtocol.greet` and `HubProtocol.resolve` refuse a server of
  another major with a sentence. `HubServer` is the side a client calls, one
  request object per exchange. The exchanges' schemas are
  `HubProtocol.endpoints`, snapshotted in `api/flutter3d_hub.hub`. No
  network code yet: the client is an addition on these types.
