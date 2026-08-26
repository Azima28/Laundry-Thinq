import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/models/database_helper.dart';
import '../database/models/order_model.dart';
import 'midtrans_service.dart';
import '../utils/globals.dart';

class QrisPollingService {
  QrisPollingService._internal();
  static final QrisPollingService instance = QrisPollingService._internal();

  Timer? _pollingTimer;
  bool _isChecking = false;
  final ValueNotifier<int> _notifier = ValueNotifier<int>(0);

  ValueListenable<int> get updates => _notifier;

  void start() {
    if (_pollingTimer != null) return;
    debugPrint('[QrisPolling] Starting 30s background auto-checker for deferred QRIS...');

    // Initial check after 2 seconds
    Future.delayed(const Duration(seconds: 2), () => checkPendingQrisOrders());

    // Periodic check every 30 seconds
    _pollingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      checkPendingQrisOrders();
    });
  }

  void stop() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  /// Check all pending QRIS orders created within the last 24 hours
  Future<void> checkPendingQrisOrders() async {
    if (_isChecking) return;
    _isChecking = true;

    try {
      final db = DatabaseHelper.instance;
      final pendingOrders = await db.getPendingQrisOrders();

      if (pendingOrders.isEmpty) {
        // Zero pending orders -> No network calls made (0 overhead)
        _isChecking = false;
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final serverKey = prefs.getString('midtrans_server_key') ?? '';
      final now = DateTime.now();

      for (final order in pendingOrders) {
        if (order.id == null || order.qrisId == null || order.qrisId!.trim().isEmpty) continue;

        // Calculate exact 24-hour expiration window
        final qrisCreatedAt = order.qrisCreatedAt ?? order.orderDate;
        final elapsedDuration = now.difference(qrisCreatedAt);

        if (elapsedDuration.inHours >= 24) {
          // QRIS has expired (24h passed)
          if (order.qrisStatus != 'expire') {
            await db.updateOrderQrisStatus(order.id!, 'expire');
            debugPrint('[QrisPolling] Order #${order.id} QRIS expired (> 24 hours)');
          }
          continue;
        }

        // Check live transaction status from Midtrans Gateway
        try {
          final res = await MidtransService.checkTransactionStatus(
            order.qrisId!,
            overrideServerKey: serverKey,
          );

          if (res['success'] == true) {
            final String transactionStatus = (res['transaction_status'] ?? '').toString().toLowerCase();

            if (transactionStatus == 'settlement' || transactionStatus == 'capture') {
              // Successfully paid! Update database to PAID (LUNAS)
              await db.updateOrderQrisPaymentSuccess(
                order.id!,
                paymentTimestamp: res['transaction_time']?.toString() ?? DateTime.now().toIso8601String(),
                qrisStatus: 'settlement',
              );

              Globals.showSuccessSnackBar(
                '✅ Pembayaran QRIS Nota #${order.id} (${order.customerName}) LUNAS terverifikasi otomatis!',
              );
              _notifier.value++;
              debugPrint('[QrisPolling] Order #${order.id} successfully paid via QRIS!');
            } else if (transactionStatus == 'expire' || transactionStatus == 'cancel' || transactionStatus == 'deny') {
              await db.updateOrderQrisStatus(order.id!, transactionStatus);
              _notifier.value++;
            }
          }
        } catch (e) {
          debugPrint('[QrisPolling] Error verifying order #${order.id}: $e');
        }
      }
    } catch (e) {
      debugPrint('[QrisPolling] Background check error: $e');
    } finally {
      _isChecking = false;
    }
  }

  /// Manually check a specific order by ID immediately
  Future<Map<String, dynamic>> checkSpecificOrder(int orderId) async {
    try {
      final db = DatabaseHelper.instance;
      final order = await db.getOrder(orderId);
      if (order == null || order.qrisId == null || order.qrisId!.isEmpty) {
        return {'success': false, 'message': 'Data QRIS tidak ditemukan pada nota ini.'};
      }

      final prefs = await SharedPreferences.getInstance();
      final serverKey = prefs.getString('midtrans_server_key') ?? '';

      final res = await MidtransService.checkTransactionStatus(
        order.qrisId!,
        overrideServerKey: serverKey,
      );

      if (res['success'] == true) {
        final String transactionStatus = (res['transaction_status'] ?? '').toString().toLowerCase();

        if (transactionStatus == 'settlement' || transactionStatus == 'capture') {
          await db.updateOrderQrisPaymentSuccess(
            order.id!,
            paymentTimestamp: res['transaction_time']?.toString() ?? DateTime.now().toIso8601String(),
            qrisStatus: 'settlement',
          );
          _notifier.value++;
          return {'success': true, 'is_paid': true, 'status': 'settlement', 'message': 'Pembayaran Berhasil / LUNAS'};
        } else {
          await db.updateOrderQrisStatus(order.id!, transactionStatus);
          _notifier.value++;
          return {
            'success': true,
            'is_paid': false,
            'status': transactionStatus,
            'message': 'Status QRIS: $transactionStatus (Belum Dibayar)',
          };
        }
      } else {
        return {'success': false, 'message': res['message'] ?? 'Gagal memeriksa status ke Midtrans.'};
      }
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }
}
