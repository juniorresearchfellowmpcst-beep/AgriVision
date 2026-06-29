class EnvSettings {
  final String appUrl;
  final String broadcastPort;
  final String ticketIntegrationUrl;
  final String surboBaseUrl;
  final String surboSocketUrl;

  EnvSettings({
    required this.appUrl,
    required this.broadcastPort,
    required this.ticketIntegrationUrl,
    required this.surboBaseUrl,
    required this.surboSocketUrl,
  });

  factory EnvSettings.fromJson(Map<String, dynamic> json) {
    return EnvSettings(
      appUrl: json['APP_URL'].toString(),
      broadcastPort: json['BROADCAST_PORT'].toString(),
      ticketIntegrationUrl: json['TICKET_INTEGRATION_URL'].toString(),
      surboBaseUrl: json['SURBO_BASE_URL'].toString(),
      surboSocketUrl: json['SURBO_SOCKET_URL'].toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'APP_URL': appUrl,
      'BROADCAST_PORT': broadcastPort,
      'TICKET_INTEGRATION_URL': ticketIntegrationUrl,
      'SURBO_BASE_URL': surboBaseUrl,
      'SURBO_SOCKET_URL': surboSocketUrl,
    };
  }
}
