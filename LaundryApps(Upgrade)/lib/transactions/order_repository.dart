import '../database/models/database_helper.dart';
import '../database/models/order_model.dart';
import '../services/machine_status_service.dart';

class OrderRepository {
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;
  final MachineStatusService _statusService = MachineStatusService.instance;

  Future<int?> getLatestOrderId() async {
    try {
      final orders = await _databaseHelper.getAllOrders();
      if (orders.isEmpty) return null;
      return orders.first.id;
    } catch (e) {
      print('Error getting latest order id: $e');
      return null;
    }
  }

  Future<int?> createOrder(
    String customerName,
    List<OrderItem> items,
    int totalAmount,
    int userId, {
    String? customerPhone,
    String paymentMethod = 'Tunai / Cash',
    int? paidAmount,
    bool? isPaid,
    int? assignedMachineId,
  }) async {
    // 1. Try Backend Atomic Creation & Price Verification
    try {
      final itemsPayload = items.map((it) => {
        'item_id': it.itemId,
        'quantity': it.quantity,
        'note': it.note ?? '',
      }).toList();

      final res = await _statusService.createOrderBackend(
        customerName: customerName,
        customerPhone: customerPhone,
        items: itemsPayload,
        userId: userId,
        paymentMethod: paymentMethod,
        paidAmount: paidAmount,
        isPaid: isPaid,
        assignedMachineId: assignedMachineId,
      );

      if (res['success'] == true && res['order'] != null) {
        final orderData = res['order'] as Map<String, dynamic>;
        final orderId = orderData['id'] as int?;
        if (orderId != null && orderId > 0) {
          return orderId;
        }
      }
    } catch (e) {
      print('[OrderRepository] Backend createOrder fallback: $e');
    }

    // 2. Local SQLite Fallback
    try {
      final order = Order(
        customerName: customerName,
        customerPhone: customerPhone,
        orderDate: DateTime.now(),
        totalAmount: totalAmount,
        items: items,
        status: 'Pending',
        userId: userId,
        isPaid: isPaid ?? (paidAmount != null && paidAmount >= totalAmount),
        paidAmount: paidAmount ?? (paymentMethod == 'Tunai / Cash' ? totalAmount : 0),
        paymentMethod: paymentMethod,
        assignedMachineId: assignedMachineId,
      );

      final id = await _databaseHelper.insertOrder(order);
      return id > 0 ? id : null;
    } catch (e) {
      print('Error creating order: $e');
      return null;
    }
  }

  Future<List<Order>> getAllOrders({int? userId}) async {
    try {
      return await _databaseHelper.getAllOrders(userId: userId);
    } catch (e) {
      print('Error getting orders: $e');
      return [];
    }
  }

  Future<Order?> getOrder(int id) async {
    try {
      return await _databaseHelper.getOrder(id);
    } catch (e) {
      print('Error getting order: $e');
      return null;
    }
  }

  Future<bool> updateOrderStatus(int id, String status) async {
    try {
      final rowsAffected = await _databaseHelper.updateOrderStatus(id, status);
      return rowsAffected > 0;
    } catch (e) {
      print('Error updating order status: $e');
      return false;
    }
  }

  Future<bool> updateOrder(Order order) async {
    try {
      final rowsAffected = await _databaseHelper.updateOrder(order);
      return rowsAffected > 0;
    } catch (e) {
      print('Error updating order: $e');
      return false;
    }
  }

  Future<bool> updateOrderPaymentStatus(int id, bool isPaid) async {
    try {
      final rowsAffected = await _databaseHelper.updateOrderPaymentStatus(id, isPaid);
      return rowsAffected > 0;
    } catch (e) {
      print('Error updating payment status: $e');
      return false;
    }
  }
}
