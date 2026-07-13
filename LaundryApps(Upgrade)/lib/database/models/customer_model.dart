import 'db_encryption_helper.dart';

class Customer {
  final int? id;
  final String name;
  final String phone;
  final String? address;
  final DateTime createdAt;

  Customer({
    this.id,
    required this.name,
    required this.phone,
    this.address,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': DbEncryptionHelper.encrypt(name),
      'phone': DbEncryptionHelper.encrypt(phone),
      'address': address != null ? DbEncryptionHelper.encrypt(address!) : null,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Customer.fromMap(Map<String, dynamic> map) {
    return Customer(
      id: map['id'],
      name: DbEncryptionHelper.decrypt(map['name'] ?? ''),
      phone: DbEncryptionHelper.decrypt(map['phone'] ?? ''),
      address: map['address'] != null ? DbEncryptionHelper.decrypt(map['address']) : null,
      createdAt: map['created_at'] != null 
          ? DateTime.parse(map['created_at']) 
          : DateTime.now(),
    );
  }

  Customer copyWith({
    int? id,
    String? name,
    String? phone,
    String? address,
    DateTime? createdAt,
  }) {
    return Customer(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
