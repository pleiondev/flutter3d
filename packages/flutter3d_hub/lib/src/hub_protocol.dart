import 'hub_reference.dart';
import 'hub_refused.dart';

/// A version of the hub's protocol: `<major>.<minor>`.
///
/// **A major only grows.** Within one major the protocol takes additions
/// only: a new optional request field, a new response field, a new endpoint,
/// a new refusal reason. A client ignores what it does not know, so a 1.0
/// client works against every 1.x server. Anything else (a field gone,
/// retyped or newly required, an endpoint gone) is a new major, and a client
/// refuses a server that announces a major other than its own with a
/// sentence rather than misreading it. The response schema is snapshotted in
/// `api/flutter3d_hub.hub`, and the structure rules hold a change there to
/// the version it needs.
final class HubProtocolVersion {
  /// The version [major].[minor].
  const HubProtocolVersion(this.major, this.minor)
    : assert(major >= 1),
      assert(minor >= 0);

  /// The version [text] spells (`1.0`), or null when it spells none.
  static HubProtocolVersion? tryParse(String text) {
    final match = RegExp(
      r'^([1-9][0-9]{0,8})\.(0|[1-9][0-9]{0,8})$',
    ).firstMatch(text);
    if (match == null) return null;
    return HubProtocolVersion(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
    );
  }

  /// The major: a change in it is a change a client cannot read past.
  final int major;

  /// The minor: what a major has grown by.
  final int minor;

  /// Whether a client speaking this version reads a server announcing
  /// [server]: the same major, whatever the minor.
  bool reads(HubProtocolVersion server) => server.major == major;

  @override
  bool operator ==(Object other) =>
      other is HubProtocolVersion &&
      other.major == major &&
      other.minor == minor;

  @override
  int get hashCode => Object.hash(major, minor);

  /// The version as the wire spells it: `1.0`.
  @override
  String toString() => '$major.$minor';
}

/// One exchange of the protocol: what a client sends and what a server
/// answers, each as a JSON Schema.
///
/// The schemas are the contract a server is held to and the source of the
/// snapshot; the message classes below are tested against them.
final class HubEndpoint {
  /// An endpoint called [name].
  const HubEndpoint({
    required this.name,
    required this.description,
    required this.request,
    required this.response,
  });

  /// The endpoint's name, as the snapshot lists it.
  final String name;

  /// What it does, in sentences; the first is the one the snapshot keeps.
  final String description;

  /// The JSON Schema of the request's fields.
  final Map<String, Object?> request;

  /// The JSON Schema of the answer.
  final Map<String, Object?> response;
}

/// The hub's server protocol: its version, its endpoints and their schemas,
/// and the checks a client makes of what a server answers.
///
/// **An interface, like MCP and the network hello.** Every request carries
/// the [version] the client speaks, the server announces its own in every
/// answer, and a client refuses a server of another major with
/// `HubRefusal.protocol` and a sentence naming both. How the exchanges
/// travel (HTTP paths, headers, a mirror's layout) belongs to the client and
/// the server; what they carry is fixed here.
///
/// **No network code in this release.** The types are the contract the
/// engine freezes; a client that implements [HubServer] over HTTP arrives
/// as an addition.
abstract final class HubProtocol {
  /// The version this client speaks.
  static const HubProtocolVersion version = HubProtocolVersion(1, 0);

  /// The JSON Schema of a protocol version as the wire spells it.
  static const Map<String, Object?> _versionSchema = <String, Object?>{
    'type': 'string',
    'pattern': r'^[1-9][0-9]*\.(0|[1-9][0-9]*)$',
  };

  /// The JSON Schema of a reference, [HubReference]'s format as a pattern.
  static const Map<String, Object?> _referenceSchema = <String, Object?>{
    'type': 'string',
    'pattern':
        r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
        r'@[1-9][0-9]*(#sha256=[0-9a-f]{64})?$',
  };

  /// The exchanges of [version], in the order the snapshot lists them.
  static const List<HubEndpoint> endpoints = <HubEndpoint>[
    HubEndpoint(
      name: 'hello',
      description:
          'The server says which protocol it speaks and where its mirrors '
          'are. A client asks before anything else and refuses a server of '
          'another major.',
      request: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{'protocol': _versionSchema},
        'required': <Object?>['protocol'],
      },
      response: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'protocol': _versionSchema,
          'server': <String, Object?>{'type': 'string'},
          'mirrors': <String, Object?>{
            'type': 'array',
            'items': <String, Object?>{'type': 'string', 'format': 'uri'},
          },
        },
        'required': <Object?>['protocol', 'server'],
      },
    ),
    HubEndpoint(
      name: 'resolve',
      description:
          'What one version of one model is: its hash, its size, its format, '
          'where its bytes are, and its licence and author. A version that '
          'is not there, or was withdrawn, is answered with a refusal.',
      request: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'protocol': _versionSchema,
          'reference': _referenceSchema,
        },
        'required': <Object?>['protocol', 'reference'],
      },
      response: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'protocol': _versionSchema,
          'uuid': <String, Object?>{
            'type': 'string',
            'pattern':
                r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-'
                r'[0-9a-f]{12}$',
          },
          'version': <String, Object?>{
            'type': 'integer',
            'minimum': 1,
            'maximum': HubReference.maxVersion,
          },
          'sha256': <String, Object?>{
            'type': 'string',
            'pattern': r'^[0-9a-f]{64}$',
          },
          'bytes': <String, Object?>{'type': 'integer', 'minimum': 0},
          'format': <String, Object?>{'type': 'string'},
          'url': <String, Object?>{'type': 'string', 'format': 'uri'},
          'license': <String, Object?>{'type': 'string'},
          'author': <String, Object?>{'type': 'string'},
          'name': <String, Object?>{'type': 'string'},
        },
        'required': <Object?>[
          'protocol',
          'uuid',
          'version',
          'sha256',
          'bytes',
          'format',
          'url',
          'license',
        ],
      },
    ),
    HubEndpoint(
      name: 'refusal',
      description:
          'The answer to any request the server refuses, in place of the '
          'answer it asked for. `reason` is a wire name of `HubRefusal`, an '
          'open set: a client reads one it does not know as a refusal all '
          'the same.',
      request: <String, Object?>{'type': 'object'},
      response: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'protocol': _versionSchema,
          'reason': <String, Object?>{'type': 'string'},
          'message': <String, Object?>{'type': 'string'},
        },
        'required': <Object?>['protocol', 'reason', 'message'],
      },
    ),
  ];

  /// Asks [server] which protocol it speaks, and refuses one of another
  /// major with `HubRefusal.protocol`.
  static Future<HubHello> greet(HubServer server) async {
    final hello = await server.hello(const HubHelloRequest());
    check(hello.protocol);
    return hello;
  }

  /// Asks [server] what [reference] is, and holds the answer to it: the
  /// protocol's major, the model and version asked for, and the checksum
  /// when [reference] carries one (`HubRefusal.hashMismatch` when the
  /// server announces another hash).
  static Future<HubModel> resolve(
    HubServer server,
    HubReference reference,
  ) async {
    final model = await server.resolve(HubResolveRequest(reference));
    check(model.protocol);
    if (model.reference != reference.withoutChecksum) {
      throw HubRefusedException(
        HubRefusal.protocol,
        reference: reference,
        detail:
            'the server answered for ${model.reference}, not for the model '
            'and version asked for.',
      );
    }
    if (reference.sha256 case final String expected
        when expected != model.sha256) {
      throw HubRefusedException(
        HubRefusal.hashMismatch,
        reference: reference,
        detail:
            'the server announces sha256 ${model.sha256}, and the reference '
            'says $expected.',
      );
    }
    return model;
  }

  /// Refuses a server announcing [server] when its major is not
  /// [version]'s.
  static void check(HubProtocolVersion server) {
    if (version.reads(server)) return;
    throw HubRefusedException(
      HubRefusal.protocol,
      detail:
          'it speaks protocol $server and this client speaks $version. A '
          'client reads every minor of its own major and no other major; '
          '${server.major > version.major ? 'a newer flutter3d_hub speaks ${server.major}.x' : 'the server is older than any client this release can talk to'}.',
    );
  }
}

/// The server side of the protocol, as a client calls it.
///
/// **One request object per call**, so a field a later minor adds to a
/// request reaches an implementation without changing a signature. A
/// refusal is thrown as [HubRefusedException], whatever carried it.
///
/// Implemented by a client over a transport (HTTP in a later release) and by
/// a test's fake. `base`: extend it, so a call a later minor adds arrives
/// with a default body.
abstract base class HubServer {
  /// A server.
  const HubServer();

  /// The `hello` exchange.
  Future<HubHello> hello(HubHelloRequest request);

  /// The `resolve` exchange.
  Future<HubModel> resolve(HubResolveRequest request);
}

/// Reads [json]'s field [key] as a [T], or refuses the answer.
T _field<T>(Map<String, Object?> json, String key, String message) {
  final value = json[key];
  if (value is T) return value;
  throw HubRefusedException(
    HubRefusal.protocol,
    detail:
        'a $message answer has ${value == null ? 'no "$key"' : '"$key" as ${value.runtimeType}, not $T'}.',
  );
}

HubProtocolVersion _protocolOf(Map<String, Object?> json, String message) {
  final text = _field<String>(json, 'protocol', message);
  return HubProtocolVersion.tryParse(text) ??
      (throw HubRefusedException(
        HubRefusal.protocol,
        detail:
            'a $message answer names protocol "$text", which is no version.',
      ));
}

/// The `hello` request.
final class HubHelloRequest {
  /// A request from a client speaking [protocol].
  const HubHelloRequest({this.protocol = HubProtocol.version});

  /// The protocol the client speaks.
  final HubProtocolVersion protocol;

  /// The request as the wire carries it.
  Map<String, Object?> toJson() => <String, Object?>{
    'protocol': protocol.toString(),
  };
}

/// The `hello` answer: the protocol the server speaks, and where its mirrors
/// are.
final class HubHello {
  /// An answer from [server], speaking [protocol].
  const HubHello({
    required this.protocol,
    required this.server,
    this.mirrors = const <Uri>[],
  });

  /// Reads an answer, ignoring fields this version does not know; refuses
  /// one that lacks a field it requires with `HubRefusal.protocol`.
  factory HubHello.fromJson(Map<String, Object?> json) {
    const message = 'hello';
    final mirrors = json['mirrors'];
    return HubHello(
      protocol: _protocolOf(json, message),
      server: _field<String>(json, 'server', message),
      mirrors: <Uri>[
        if (mirrors is List)
          for (final mirror in mirrors)
            if (mirror is String) ?Uri.tryParse(mirror),
      ],
    );
  }

  /// The protocol the server speaks.
  final HubProtocolVersion protocol;

  /// The server's name for itself, for a message.
  final String server;

  /// Where the same immutable files are served when this server does not
  /// answer, in the order to try them.
  final List<Uri> mirrors;

  /// The answer as the wire carries it.
  Map<String, Object?> toJson() => <String, Object?>{
    'protocol': protocol.toString(),
    'server': server,
    if (mirrors.isNotEmpty)
      'mirrors': <String>[for (final m in mirrors) m.toString()],
  };
}

/// The `resolve` request: what is [reference]?
final class HubResolveRequest {
  /// A request for [reference] from a client speaking [protocol].
  const HubResolveRequest(
    this.reference, {
    this.protocol = HubProtocol.version,
  });

  /// The model and version asked for, with its checksum if it has one.
  final HubReference reference;

  /// The protocol the client speaks.
  final HubProtocolVersion protocol;

  /// The request as the wire carries it.
  Map<String, Object?> toJson() => <String, Object?>{
    'protocol': protocol.toString(),
    'reference': reference.toString(),
  };
}

/// The `resolve` answer: one version of one model, as the hub describes it.
final class HubModel {
  /// A description of [reference]'s file.
  const HubModel({
    required this.protocol,
    required this.reference,
    required this.sha256,
    required this.bytes,
    required this.format,
    required this.url,
    required this.license,
    this.author,
    this.name,
  });

  /// Reads an answer, ignoring fields this version does not know; refuses
  /// one that lacks a field it requires, or holds one of the wrong shape,
  /// with `HubRefusal.protocol`.
  factory HubModel.fromJson(Map<String, Object?> json) {
    const message = 'resolve';
    final uuid = _field<String>(json, 'uuid', message);
    final version = _field<int>(json, 'version', message);
    final sha256 = _field<String>(json, 'sha256', message);
    final HubReference reference;
    try {
      reference = HubReference(uuid: uuid, version: version, sha256: sha256);
    } on HubReferenceFormatException catch (e) {
      throw HubRefusedException(
        HubRefusal.protocol,
        detail: 'a resolve answer names no model: ${e.reason}.',
        cause: e,
      );
    }
    final url = _field<String>(json, 'url', message);
    final bytes = _field<int>(json, 'bytes', message);
    if (bytes < 0) {
      throw HubRefusedException(
        HubRefusal.protocol,
        reference: reference,
        detail: 'a resolve answer says the file has $bytes bytes.',
      );
    }
    return HubModel(
      protocol: _protocolOf(json, message),
      reference: reference.withoutChecksum,
      sha256: sha256,
      bytes: bytes,
      format: _field<String>(json, 'format', message),
      url:
          Uri.tryParse(url) ??
          (throw HubRefusedException(
            HubRefusal.protocol,
            reference: reference,
            detail: 'a resolve answer gives "$url" as the address.',
          )),
      license: _field<String>(json, 'license', message),
      author: json['author'] is String ? json['author']! as String : null,
      name: json['name'] is String ? json['name']! as String : null,
    );
  }

  /// The protocol the server speaks.
  final HubProtocolVersion protocol;

  /// The model and version this describes, without a checksum: [sha256] is
  /// the checksum.
  final HubReference reference;

  /// The SHA-256 of the file as served, as 64 lowercase hexadecimal digits.
  final String sha256;

  /// The file's size, in bytes.
  final int bytes;

  /// The file's format, as the hub names it (`glb`, `f3d`, …): an open set.
  final String format;

  /// Where the file's bytes are. Immutable, like the version.
  final Uri url;

  /// The licence the author published it under: an SPDX identifier
  /// (`CC-BY-4.0`) where there is one, its text otherwise. Required: the hub
  /// does not publish a model without one.
  final String license;

  /// Who made it, as the author wrote it; null when the hub does not say.
  final String? author;

  /// The model's name on the hub, for a message; null when it has none.
  final String? name;

  /// The reference with this file's checksum on it: what to write into code
  /// so the bytes are checked on every load.
  HubReference get pinned => HubReference(
    uuid: reference.uuid,
    version: reference.version,
    sha256: sha256,
  );

  /// The answer as the wire carries it.
  Map<String, Object?> toJson() => <String, Object?>{
    'protocol': protocol.toString(),
    'uuid': reference.uuid,
    'version': reference.version,
    'sha256': sha256,
    'bytes': bytes,
    'format': format,
    'url': url.toString(),
    'license': license,
    'author': ?author,
    'name': ?name,
  };
}

/// Reads a `refusal` answer as the [HubRefusedException] it stands for.
///
/// A reason this version does not name is read as `HubRefusal.protocol`
/// with the server's word and sentence kept in the detail: the server did
/// refuse, and the caller learns why in words.
HubRefusedException hubRefusalFromJson(
  Map<String, Object?> json, {
  HubReference? reference,
}) {
  const message = 'refusal';
  final protocol = _protocolOf(json, message);
  HubProtocol.check(protocol);
  final reason = _field<String>(json, 'reason', message);
  final said = _field<String>(json, 'message', message);
  final known = HubRefusal.byName(reason);
  return HubRefusedException(
    known ?? HubRefusal.protocol,
    reference: reference,
    detail: known == null ? 'the hub refused with "$reason": $said' : said,
  );
}

/// [refused] as the `refusal` answer a server sends.
Map<String, Object?> hubRefusalToJson(
  HubRefusedException refused, {
  HubProtocolVersion protocol = HubProtocol.version,
}) => <String, Object?>{
  'protocol': protocol.toString(),
  'reason': refused.reason.name,
  'message': refused.message,
};
