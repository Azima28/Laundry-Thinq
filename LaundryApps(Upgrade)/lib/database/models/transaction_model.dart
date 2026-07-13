enum TransactionType {
  item,
  coupon,
  iron
}

class TransactionModel {
  final int? id;
  final String nama;
  final int harga;
  final int? stock;
  final bool isUnlimitedStock;
  final bool isStaffRestockable;
  final TransactionType type;
  final String? machineType; // 'cuci' or 'pengering' or null
  final int? machineId;
  final int? parentId;
  final bool isUsed;
  final int? durationDays;
  final DateTime createdAt;

  TransactionModel({
    this.id,
    required this.nama,
    required this.harga,
    this.stock,
    this.isUnlimitedStock = false,
    this.isStaffRestockable = false,
    this.type = TransactionType.item,
    this.machineType,
    this.machineId,
    this.parentId,
    this.isUsed = false,
    this.durationDays,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nama': nama,
      'harga': harga,
      'stock': stock,
      'is_unlimited_stock': isUnlimitedStock ? 1 : 0,
      'is_staff_restockable': isStaffRestockable ? 1 : 0,
      'type': type.index,
      'machine_type': machineType,
      'machine_id': machineId,
      'parent_id': parentId,
      'is_used': isUsed ? 1 : 0,
      'duration_days': durationDays,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory TransactionModel.fromMap(Map<String, dynamic> map) {
    return TransactionModel(
      id: map['id'],
      nama: map['nama'],
      harga: map['harga'],
      stock: map['stock'],
      isUnlimitedStock: map['is_unlimited_stock'] == 1,
      isStaffRestockable: map['is_staff_restockable'] == 1,
      type: TransactionType.values[map['type'] ?? 0],
      machineType: map['machine_type'],
      machineId: map['machine_id'],
      parentId: map['parent_id'],
      isUsed: map['is_used'] == 1,
      durationDays: map['duration_days'],
      createdAt: DateTime.parse(map['created_at']),
    );
  }

  TransactionModel copyWith({
    int? id,
    String? nama,
    int? harga,
    int? stock,
    bool? isUnlimitedStock,
    bool? isStaffRestockable,
    TransactionType? type,
    String? machineType,
    int? machineId,
    int? parentId,
    bool? isUsed,
    int? durationDays,
    DateTime? createdAt,
  }) {
    return TransactionModel(
      id: id ?? this.id,
      nama: nama ?? this.nama,
      harga: harga ?? this.harga,
      stock: stock ?? this.stock,
      isUnlimitedStock: isUnlimitedStock ?? this.isUnlimitedStock,
      isStaffRestockable: isStaffRestockable ?? this.isStaffRestockable,
      type: type ?? this.type,
      machineType: machineType ?? this.machineType,
      machineId: machineId ?? this.machineId,
      parentId: parentId ?? this.parentId,
      isUsed: isUsed ?? this.isUsed,
      durationDays: durationDays ?? this.durationDays,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
