import 'db_encryption_helper.dart';

class OrderItem {
  final int? id;
  final int itemId;
  final String itemName;
  final int quantity;
  final int price;
  final String? note;
  final String? machineType;

  OrderItem({
    this.id,
    required this.itemId,
    required this.itemName,
    required this.quantity,
    required this.price,
    this.note,
    this.machineType,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'item_id': itemId,
      'item_name': itemName,
      'quantity': quantity,
      'price': price,
      'note': note != null ? DbEncryptionHelper.encrypt(note!) : null,
    };
  }

  factory OrderItem.fromMap(Map<String, dynamic> map) {
    return OrderItem(
      id: map['id'],
      itemId: map['item_id'],
      itemName: map['item_name'],
      quantity: map['quantity'],
      price: map['price'],
      note: map['note'] != null ? DbEncryptionHelper.decrypt(map['note']) : null,
      machineType: map['machine_type'],
    );
  }
}

class Order {
  final int? id;
  final String customerName;
  final String? customerPhone;
  final DateTime orderDate;
  final int totalAmount;
  final List<OrderItem> items;
  final String status;
  final int userId;
  final bool isPaid;
  final int paidAmount;
  final String paymentMethod;
  final String? qrisUrl;
  final String? qrisId;
  final DateTime? qrisCreatedAt;
  final String? qrisStatus;
  final DateTime? paymentTimestamp;
  final int? assignedMachineId;
  final DateTime? machineStartedAt;
  final bool loyaltyClaimed;
  final int washSequence;
  final int stampsUsed;

  Order({
    this.id,
    required this.customerName,
    this.customerPhone,
    required this.orderDate,
    required this.totalAmount,
    required this.items,
    required this.status,
    required this.userId,
    this.isPaid = false,
    this.paidAmount = 0,
    this.paymentMethod = 'cash',
    this.qrisUrl,
    this.qrisId,
    this.qrisCreatedAt,
    this.qrisStatus = 'pending',
    this.paymentTimestamp,
    this.assignedMachineId,
    this.machineStartedAt,
    this.loyaltyClaimed = false,
    this.washSequence = 0,
    this.stampsUsed = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'customer_name': DbEncryptionHelper.encrypt(customerName),
      'customer_phone': customerPhone != null ? DbEncryptionHelper.encrypt(customerPhone!) : null,
      'order_date': orderDate.toIso8601String(),
      'total_amount': totalAmount,
      'status': status,
      'user_id': userId,
      'is_paid': isPaid ? 1 : 0,
      'paid_amount': paidAmount,
      'payment_method': paymentMethod,
      'qris_url': qrisUrl,
      'qris_id': qrisId,
      'qris_created_at': qrisCreatedAt?.toIso8601String(),
      'qris_status': qrisStatus,
      'payment_timestamp': paymentTimestamp?.toIso8601String(),
      'assigned_machine_id': assignedMachineId,
      'machine_started_at': machineStartedAt?.toIso8601String(),
      'loyalty_claimed': loyaltyClaimed ? 1 : 0,
      'wash_sequence': washSequence,
      'stamps_used': stampsUsed,
    };
  }

  factory Order.fromMap(Map<String, dynamic> map, List<OrderItem> orderItems) {
    return Order(
      id: map['id'],
      customerName: DbEncryptionHelper.decrypt(map['customer_name'] ?? ''),
      customerPhone: map['customer_phone'] != null ? DbEncryptionHelper.decrypt(map['customer_phone']) : null,
      orderDate: DateTime.parse(map['order_date']),
      totalAmount: map['total_amount'],
      status: map['status'],
      items: orderItems,
      isPaid: map['is_paid'] == 1,
      paidAmount: map['paid_amount'] ?? 0,
      userId: map['user_id'],
      paymentMethod: map['payment_method'] ?? 'cash',
      qrisUrl: map['qris_url'],
      qrisId: map['qris_id'],
      qrisCreatedAt: map['qris_created_at'] != null ? DateTime.tryParse(map['qris_created_at']) : null,
      qrisStatus: map['qris_status'] ?? 'pending',
      paymentTimestamp: map['payment_timestamp'] != null
          ? DateTime.parse(map['payment_timestamp'])
          : null,
      assignedMachineId: map['assigned_machine_id'],
      machineStartedAt: map['machine_started_at'] != null ? DateTime.parse(map['machine_started_at']) : null,
      loyaltyClaimed: (map['loyalty_claimed'] == 1 || map['loyalty_claimed'] == true),
      washSequence: (map['wash_sequence'] as num?)?.toInt() ?? 0,
      stampsUsed: (map['stamps_used'] as num?)?.toInt() ?? 0,
    );
  }

  Order copyWith({
    int? id,
    String? customerName,
    String? customerPhone,
    DateTime? orderDate,
    int? totalAmount,
    List<OrderItem>? items,
    String? status,
    int? userId,
    bool? isPaid,
    int? paidAmount,
    String? paymentMethod,
    String? qrisUrl,
    String? qrisId,
    DateTime? qrisCreatedAt,
    String? qrisStatus,
    DateTime? paymentTimestamp,
    int? assignedMachineId,
    DateTime? machineStartedAt,
    bool? loyaltyClaimed,
    int? washSequence,
    int? stampsUsed,
  }) {
    return Order(
      id: id ?? this.id,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      orderDate: orderDate ?? this.orderDate,
      totalAmount: totalAmount ?? this.totalAmount,
      items: items ?? this.items,
      status: status ?? this.status,
      userId: userId ?? this.userId,
      isPaid: isPaid ?? this.isPaid,
      paidAmount: paidAmount ?? this.paidAmount,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      qrisUrl: qrisUrl ?? this.qrisUrl,
      qrisId: qrisId ?? this.qrisId,
      qrisCreatedAt: qrisCreatedAt ?? this.qrisCreatedAt,
      qrisStatus: qrisStatus ?? this.qrisStatus,
      paymentTimestamp: paymentTimestamp ?? this.paymentTimestamp,
      assignedMachineId: assignedMachineId ?? this.assignedMachineId,
      machineStartedAt: machineStartedAt ?? this.machineStartedAt,
      loyaltyClaimed: loyaltyClaimed ?? this.loyaltyClaimed,
      washSequence: washSequence ?? this.washSequence,
      stampsUsed: stampsUsed ?? this.stampsUsed,
    );
  }
}
