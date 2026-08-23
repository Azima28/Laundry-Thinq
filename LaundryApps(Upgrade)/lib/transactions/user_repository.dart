import 'package:shared_preferences/shared_preferences.dart';
import '../database/models/database_helper.dart';
import '../database/models/user_model.dart';
import '../services/machine_status_service.dart';

class UserRepository {
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;
  final MachineStatusService _statusService = MachineStatusService.instance;

  Future<UserModel?> login(String username, String password) async {
    // 1. Try Backend Authentication First (PBKDF2 Password Hashing & Signed Token)
    try {
      final res = await _statusService.loginBackend(
        username: username,
        password: password,
      );
      if (res['success'] == true && res['user'] != null) {
        final userData = res['user'] as Map<String, dynamic>;
        final token = userData['token'] as String?;
        if (token != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('auth_token', token);
        }
        return UserModel(
          id: userData['id'] as int?,
          username: userData['username'] as String,
          password: '***', // Masked from memory
          role: userData['role'] as String,
          isActive: userData['is_active'] == true,
        );
      }
    } catch (e) {
      print('[UserRepository] Backend login fallback: $e');
    }

    // 2. Local SQLite Fallback
    try {
      final db = await _databaseHelper.database;
      final List<Map<String, dynamic>> maps = await db.query(
        'users',
        where: 'LOWER(username) = ? AND is_active = 1',
        whereArgs: [username.toLowerCase()],
      );

      if (maps.isEmpty) return null;
      for (final row in maps) {
        final storedPwd = row['password'] as String;
        // Verify exact plain-text password match if legacy unhashed
        if (!storedPwd.startsWith('pbkdf2:sha256:') && storedPwd == password) {
          return UserModel.fromMap(row);
        }
      }
      return null;
    } catch (e) {
      print('Error logging in: $e');
      return null;
    }
  }

  Future<bool> checkAdminExists() async {
    // Try backend check first
    try {
      final exists = await _statusService.checkAdminExistsBackend();
      if (exists) return true;
    } catch (_) {}

    try {
      final db = await _databaseHelper.database;
      final List<Map<String, dynamic>> maps = await db.query(
        'users',
        where: 'role = ?',
        whereArgs: ['admin'],
      );

      return maps.isNotEmpty;
    } catch (e) {
      print('Error checking admin: $e');
      return false;
    }
  }

  Future<bool> createAdmin(String username, String password) async {
    // Try backend creation first
    try {
      final res = await _statusService.createInitialAdminBackend(
        username: username,
        password: password,
      );
      if (res['success'] == true) return true;
    } catch (_) {}

    try {
      final adminExists = await checkAdminExists();
      if (adminExists) {
        print('Admin already exists');
        return false;
      }

      final db = await _databaseHelper.database;

      await db.transaction((txn) async {
        final user = UserModel(
          username: username,
          password: password,
          role: 'admin',
        );

        final id = await txn.insert('users', user.toMap());
        if (id <= 0) throw Exception('Failed to create admin user');
      });

      return true;
    } catch (e) {
      print('Error creating admin: $e');
      return false;
    }
  }

  Future<bool> createUser(String username, String password, {String role = 'user'}) async {
    try {
      final user = UserModel(
        username: username,
        password: password,
        role: role,
      );

      final db = await _databaseHelper.database;
      final id = await db.insert('users', user.toMap());
      return id > 0;
    } catch (e) {
      print('Error creating user: $e');
      return false;
    }
  }

  Future<List<UserModel>> getAllUsers() async {
    try {
      final db = await _databaseHelper.database;
      final List<Map<String, dynamic>> maps = await db.query('users');
      return List.generate(maps.length, (i) => UserModel.fromMap(maps[i]));
    } catch (e) {
      print('Error getting users: $e');
      return [];
    }
  }

  Future<bool> updateUser(UserModel user) async {
    try {
      final db = await _databaseHelper.database;
      final rowsAffected = await db.update(
        'users',
        user.toMap(),
        where: 'id = ?',
        whereArgs: [user.id],
      );
      return rowsAffected > 0;
    } catch (e) {
      print('Error updating user: $e');
      return false;
    }
  }

  Future<bool> changePassword(int userId, String newPassword, {String oldPassword = ''}) async {
    try {
      if (oldPassword.isNotEmpty) {
        final res = await _statusService.changePasswordBackend(
          userId: userId,
          oldPassword: oldPassword,
          newPassword: newPassword,
        );
        if (res['success'] == true) return true;
      }
    } catch (_) {}

    try {
      final db = await _databaseHelper.database;
      final rowsAffected = await db.update(
        'users',
        {'password': newPassword},
        where: 'id = ?',
        whereArgs: [userId],
      );
      return rowsAffected > 0;
    } catch (e) {
      print('Error changing password: $e');
      return false;
    }
  }

  Future<UserModel?> getUserById(int userId) async {
    try {
      final db = await _databaseHelper.database;
      final List<Map<String, dynamic>> maps = await db.query(
        'users',
        where: 'id = ?',
        whereArgs: [userId],
      );

      if (maps.isEmpty) return null;
      return UserModel.fromMap(maps.first);
    } catch (e) {
      print('Error getting user by ID: $e');
      return null;
    }
  }

  Future<bool> verifyAdminPassword(String password) async {
    // 1. Try Backend verification first (hashes & salt compare)
    try {
      final isValid = await _statusService.verifyAdminPasswordBackend(password);
      if (isValid) return true;
    } catch (_) {}

    // 2. Local fallback
    try {
      final db = await _databaseHelper.database;
      final List<Map<String, dynamic>> maps = await db.query(
        'users',
        where: 'role = ? AND is_active = 1',
        whereArgs: ['admin'],
      );
      for (final row in maps) {
        if (row['password'] == password) return true;
      }
      return false;
    } catch (e) {
      print('Error verifying admin password: $e');
      return false;
    }
  }
}
