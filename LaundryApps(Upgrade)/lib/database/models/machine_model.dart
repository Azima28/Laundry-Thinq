class MachineModel {
  final int? id;
  final String name;
  final String url;
  final String machineType;
  final String key;
  final DateTime createdAt;

  MachineModel({
    this.id,
    required this.name,
    this.machineType = 'cuci',
    required this.url,
    required this.key,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'machine_type': machineType,
      'name': name,
      'url': url,
      'key': key,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory MachineModel.fromMap(Map<String, dynamic> map) {
    return MachineModel(
      id: map['id'],
      machineType: map['machine_type'] ?? 'cuci',
      name: map['name'] ?? '',
      url: map['url'] ?? '',
      key: map['key'] ?? '',
      createdAt: map['created_at'] != null ? DateTime.parse(map['created_at']) : DateTime.now(),
    );
  }
}
