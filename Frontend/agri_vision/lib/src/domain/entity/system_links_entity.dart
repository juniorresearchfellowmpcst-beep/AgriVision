import 'package:equatable/equatable.dart';

/// Where the backend is reachable, from `GET /api/system/links`.
///
/// Two different people need this screen. An operator setting up a second
/// handset needs the API base URL. Someone running Mission Planner or
/// QGroundControl needs a host and port to *send* telemetry to — and the usual
/// mistake is getting the direction backwards, so the backend reports whether
/// it is currently listening at all rather than leaving that to be guessed.
class SystemLinksEntity extends Equatable {
  const SystemLinksEntity({
    required this.hostname,
    required this.addresses,
    required this.apiBaseUrl,
    required this.apiUrls,
    required this.apiPort,
    required this.mavlink,
    required this.hints,
  });

  final String hostname;

  /// Every LAN IPv4 address this machine has, best guess first. More than one
  /// means the operator has to pick the network the other program is on.
  final List<String> addresses;

  /// Paste-ready value for the app's `BASE_URL`.
  final String apiBaseUrl;
  final List<String> apiUrls;
  final int apiPort;

  final MavlinkLinkInfo mavlink;

  /// Plain instructions for the situation the operator is actually in.
  final List<String> hints;

  bool get hasAddresses => addresses.isNotEmpty;

  factory SystemLinksEntity.fromJson(Map<String, dynamic> json) {
    final api = (json['api'] as Map?)?.cast<String, dynamic>() ?? const {};
    return SystemLinksEntity(
      hostname: json['hostname']?.toString() ?? '',
      addresses: _strings(json['addresses']),
      apiBaseUrl: api['base_url']?.toString() ?? '',
      apiUrls: _strings(api['urls']),
      apiPort: api['port'] is num ? (api['port'] as num).toInt() : 0,
      mavlink: MavlinkLinkInfo.fromJson(
        (json['mavlink'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      hints: _strings(json['hints']),
    );
  }

  static const empty = SystemLinksEntity(
    hostname: '',
    addresses: [],
    apiBaseUrl: '',
    apiUrls: [],
    apiPort: 0,
    mavlink: MavlinkLinkInfo.empty,
    hints: [],
  );

  @override
  List<Object?> get props => [hostname, addresses, apiBaseUrl, mavlink];
}

/// The telemetry link's configuration and what a ground station should target.
class MavlinkLinkInfo extends Equatable {
  const MavlinkLinkInfo({
    required this.configuredUrl,
    required this.activeUrl,
    required this.scheme,
    required this.port,
    required this.listening,
    required this.available,
    required this.connected,
    required this.alive,
    required this.sourceSystem,
    required this.gcsTargets,
    required this.listenTargets,
    required this.listenUrl,
  });

  /// The endpoint from configuration, e.g. `udpin:0.0.0.0:14550`.
  final String configuredUrl;

  /// The endpoint of the link that is actually open, when one is. Differs from
  /// [configuredUrl] the moment an operator connects to something else.
  final String activeUrl;

  /// `udpin` | `udpout` | `tcp` | `serial` | `unknown`.
  final String scheme;
  final int? port;

  /// True when this backend waits to be sent telemetry. When false there is no
  /// inbound port and no ground station can connect to it.
  final bool listening;

  /// False when pymavlink is not installed on the server.
  final bool available;
  final bool connected;
  final bool alive;
  final int sourceSystem;

  /// Addresses a ground station can send to right now. Empty when [listening]
  /// is false — deliberately, because offering an address that nothing is
  /// bound to is the most confusing failure this screen can produce.
  final List<GcsTarget> gcsTargets;

  /// Addresses that *would* work if the link were switched to listening mode.
  /// Shown so the operator can see the address, not just be told to change a
  /// setting.
  final List<GcsTarget> listenTargets;

  /// The connection string to set to accept an incoming stream.
  final String listenUrl;

  bool get isSerial => scheme == 'serial';

  factory MavlinkLinkInfo.fromJson(Map<String, dynamic> json) {
    return MavlinkLinkInfo(
      configuredUrl: json['configured_url']?.toString() ?? '',
      activeUrl: json['active_url']?.toString() ?? '',
      scheme: json['scheme']?.toString() ?? 'unknown',
      port: json['port'] is num ? (json['port'] as num).toInt() : null,
      listening: json['listening'] == true,
      available: json['available'] == true,
      connected: json['connected'] == true,
      alive: json['alive'] == true,
      sourceSystem: json['source_system'] is num
          ? (json['source_system'] as num).toInt()
          : 255,
      gcsTargets: GcsTarget.listFrom(json['gcs_targets']),
      listenTargets: GcsTarget.listFrom(json['listen_targets']),
      listenUrl: json['listen_url']?.toString() ?? '',
    );
  }

  static const empty = MavlinkLinkInfo(
    configuredUrl: '',
    activeUrl: '',
    scheme: 'unknown',
    port: null,
    listening: false,
    available: false,
    connected: false,
    alive: false,
    sourceSystem: 255,
    gcsTargets: [],
    listenTargets: [],
    listenUrl: '',
  );

  @override
  List<Object?> get props => [configuredUrl, activeUrl, scheme, listening, connected];
}

/// One host:port a ground station can be pointed at.
class GcsTarget extends Equatable {
  const GcsTarget({
    required this.transport,
    required this.host,
    required this.port,
    required this.address,
    required this.mavproxy,
  });

  final String transport; // UDP | TCP
  final String host;
  final int port;

  /// `192.168.1.5:14550` — what goes in Mission Planner's connection box.
  final String address;

  /// The equivalent MAVProxy / mavlink-router argument.
  final String mavproxy;

  factory GcsTarget.fromJson(Map<String, dynamic> json) => GcsTarget(
    transport: json['transport']?.toString() ?? 'UDP',
    host: json['host']?.toString() ?? '',
    port: json['port'] is num ? (json['port'] as num).toInt() : 0,
    address: json['address']?.toString() ?? '',
    mavproxy: json['mavproxy']?.toString() ?? '',
  );

  static List<GcsTarget> listFrom(dynamic value) =>
      (value as List?)
          ?.map((e) => GcsTarget.fromJson((e as Map).cast<String, dynamic>()))
          .toList() ??
      const [];

  @override
  List<Object?> get props => [transport, host, port];
}

List<String> _strings(dynamic value) =>
    (value as List?)?.map((e) => e.toString()).toList() ?? const [];
