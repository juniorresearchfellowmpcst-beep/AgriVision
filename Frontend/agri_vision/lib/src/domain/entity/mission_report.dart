class MissionReportEntity {
  final int id;
  final String title;
  final String date;
  final String area;
  final String status;

  MissionReportEntity({
    required this.id,
    required this.title,
    required this.date,
    required this.area,
    required this.status,
  });

  factory MissionReportEntity.fromJson(Map<String, dynamic> json) {
    return MissionReportEntity(
      id: json['id'] ?? 0,
      title: json['title']?.toString() ?? '',
      date: json['date']?.toString() ?? '',
      area: json['area']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
    );
  }

  static List<MissionReportEntity> fromJsonList(List<dynamic> jsonList) {
    return jsonList
        .map(
          (json) => MissionReportEntity.fromJson(json as Map<String, dynamic>),
        )
        .toList();
  }

  /// Generate dummy/mock data for development and testing
  static List<MissionReportEntity> getDummyData() {
    return [
      MissionReportEntity(
        id: 1,
        title: 'Block A – North Section',
        date: 'Jun 21, 2026',
        area: '4.2 ha',
        status: 'done',
      ),
      MissionReportEntity(
        id: 2,
        title: 'Orchard Rows 7–12',
        date: 'Jun 19, 2026',
        area: '1.8 ha',
        status: 'done',
      ),
      MissionReportEntity(
        id: 3,
        title: 'Paddock 3 – South',
        date: 'Jun 17, 2026',
        area: '6.1 ha',
        status: 'partial',
      ),
      MissionReportEntity(
        id: 4,
        title: 'Field E – East Border',
        date: 'Jun 15, 2026',
        area: '3.5 ha',
        status: 'pending',
      ),
      MissionReportEntity(
        id: 5,
        title: 'Greenhouse Complex',
        date: 'Jun 13, 2026',
        area: '0.8 ha',
        status: 'done',
      ),
      MissionReportEntity(
        id: 4,
        title: 'Field E – East Border',
        date: 'Jun 15, 2026',
        area: '3.5 ha',
        status: 'pending',
      ),
      MissionReportEntity(
        id: 5,
        title: 'Greenhouse Complex',
        date: 'Jun 13, 2026',
        area: '0.8 ha',
        status: 'done',
      ),
      MissionReportEntity(
        id: 4,
        title: 'Field E – East Border',
        date: 'Jun 15, 2026',
        area: '3.5 ha',
        status: 'pending',
      ),
      MissionReportEntity(
        id: 5,
        title: 'Greenhouse Complex',
        date: 'Jun 13, 2026',
        area: '0.8 ha',
        status: 'done',
      ),
    ];
  }
}
