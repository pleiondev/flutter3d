/// The model hub's client contract: what a reference to a model on the hub
/// is, why the hub refuses one, how a fetched model may be cached, and what
/// a client and a server say to each other.
///
/// ```dart
/// final chair = HubReference.parse(
///   '0f8b5c2e-7a41-4d3b-9c6e-2a1f8e4d7b90@3',
/// );
/// ```
///
/// **Types and the protocol, no network code.** These are frozen with 1.0
/// because references live in other people's code for years; the client that
/// downloads, checks the hash and keeps an on-device cache is an addition on
/// top of them. Plain Dart with no engine package beneath it, so a server, a
/// tool and the renderer's core can all name a reference.
library;

export 'src/hub_cache_policy.dart' show HubCachePolicy;
export 'src/hub_protocol.dart'
    show
        HubEndpoint,
        HubHello,
        HubHelloRequest,
        HubModel,
        HubProtocol,
        HubProtocolVersion,
        HubResolveRequest,
        HubServer,
        hubRefusalFromJson,
        hubRefusalToJson;
export 'src/hub_reference.dart' show HubReference, HubReferenceFormatException;
export 'src/hub_refused.dart' show HubRefusal, HubRefusedException;
