import 'package:flutter/material.dart';
import '../database/models/database_helper.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();

  factory NotificationService() {
    return _instance;
  }

  NotificationService._internal();

  static NotificationService get instance => _instance;

  Future<void> init() async {
    // Initialize notification service
    // No platform-specific initialization needed anymore
  }

  /// Save notification to database for display when app is foreground
  Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
    int id = 0,
  }) async {
    try {
      final dbHelper = DatabaseHelper.instance;
      final db = await dbHelper.database;

      // Save to pending_notifications table
      await db.rawInsert(
        '''
        INSERT OR IGNORE INTO pending_notifications 
        (id, title, body, created_at) 
        VALUES (?, ?, ?, ?)
        ''',
        [
          id,
          title,
          body,
          DateTime.now().toIso8601String(),
        ],
      );

      debugPrint('[NotificationService] Saved notification: $title - $body');
    } catch (e) {
      debugPrint('[NotificationService] Error saving notification: $e');
    }
  }

  /// Retrieve pending notifications
  Future<List<Map<String, dynamic>>> getPendingNotifications() async {
    try {
      final dbHelper = DatabaseHelper.instance;
      final db = await dbHelper.database;
      final result = await db.rawQuery(
        'SELECT * FROM pending_notifications ORDER BY created_at DESC LIMIT 10',
      );
      return result;
    } catch (e) {
      debugPrint('[NotificationService] Error fetching notifications: $e');
      return [];
    }
  }

  /// Mark notification as read
  Future<void> clearNotification(int id) async {
    try {
      final dbHelper = DatabaseHelper.instance;
      final db = await dbHelper.database;
      await db.rawDelete(
        'DELETE FROM pending_notifications WHERE id = ?',
        [id],
      );
    } catch (e) {
      debugPrint('[NotificationService] Error clearing notification: $e');
    }
  }

  /// Clear all notifications
  Future<void> clearAllNotifications() async {
    try {
      final dbHelper = DatabaseHelper.instance;
      final db = await dbHelper.database;
      await db.rawDelete('DELETE FROM pending_notifications');
    } catch (e) {
      debugPrint('[NotificationService] Error clearing all notifications: $e');
    }
  }
}