import 'db_encryption_helper.dart';

class Customer {
  final int? id;
  final String name;
  final String phone;
  final String? address;
  final DateTime createdAt;
  final int washCountLifetime;
  final int washCountActive;
  final int rewardsClaimedCount;
  final int dryCountLifetime;
  final int storeItemCountLifetime;
  final int ironCountLifetime;
  final int totalSpentLifetime;

  Customer({
    this.id,
    required this.name,
    required this.phone,
    this.address,
    required this.createdAt,
    this.washCountLifetime = 0,
    this.washCountActive = 0,
    this.rewardsClaimedCount = 0,
    this.dryCountLifetime = 0,
    this.storeItemCountLifetime = 0,
    this.ironCountLifetime = 0,
    this.totalSpentLifetime = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': DbEncryptionHelper.encrypt(name),
      'phone': DbEncryptionHelper.encrypt(phone),
      'address': address != null ? DbEncryptionHelper.encrypt(address!) : null,
      'created_at': createdAt.toIso8601String(),
      'wash_count_lifetime': washCountLifetime,
      'wash_count_active': washCountActive,
      'rewards_claimed_count': rewardsClaimedCount,
      'dry_count_lifetime': dryCountLifetime,
      'store_item_count_lifetime': storeItemCountLifetime,
      'iron_count_lifetime': ironCountLifetime,
      'total_spent_lifetime': totalSpentLifetime,
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
      washCountLifetime: (map['wash_count_lifetime'] as num?)?.toInt() ?? 0,
      washCountActive: (map['wash_count_active'] as num?)?.toInt() ?? 0,
      rewardsClaimedCount: (map['rewards_claimed_count'] as num?)?.toInt() ?? 0,
      dryCountLifetime: (map['dry_count_lifetime'] as num?)?.toInt() ?? 0,
      storeItemCountLifetime: (map['store_item_count_lifetime'] as num?)?.toInt() ?? 0,
      ironCountLifetime: (map['iron_count_lifetime'] as num?)?.toInt() ?? 0,
      totalSpentLifetime: (map['total_spent_lifetime'] as num?)?.toInt() ?? 0,
    );
  }

  Customer copyWith({
    int? id,
    String? name,
    String? phone,
    String? address,
    DateTime? createdAt,
    int? washCountLifetime,
    int? washCountActive,
    int? rewardsClaimedCount,
    int? dryCountLifetime,
    int? storeItemCountLifetime,
    int? ironCountLifetime,
    int? totalSpentLifetime,
  }) {
    return Customer(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      createdAt: createdAt ?? this.createdAt,
      washCountLifetime: washCountLifetime ?? this.washCountLifetime,
      washCountActive: washCountActive ?? this.washCountActive,
      rewardsClaimedCount: rewardsClaimedCount ?? this.rewardsClaimedCount,
      dryCountLifetime: dryCountLifetime ?? this.dryCountLifetime,
      storeItemCountLifetime: storeItemCountLifetime ?? this.storeItemCountLifetime,
      ironCountLifetime: ironCountLifetime ?? this.ironCountLifetime,
      totalSpentLifetime: totalSpentLifetime ?? this.totalSpentLifetime,
    );
  }
}
