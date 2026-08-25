import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'transaction_model.dart';
import 'order_model.dart';
import 'machine_model.dart';
import 'db_encryption_helper.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;
  static const int _databaseVersion =
      18; // bumped: added duration_days to transactions

  DatabaseHelper._init();

  Future<void> deleteDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'laundry.db');
    await databaseFactory.deleteDatabase(path);
  }

  Future<String> getDatabasePath() async {
    if (Platform.isWindows) {
      try {
        final appData = Platform.environment['APPDATA'];
        if (appData != null && appData.isNotEmpty) {
          final dbDir = Directory(join(appData, 'SmartLaundry'));
          if (!await dbDir.exists()) {
            await dbDir.create(recursive: true);
          }
          return join(dbDir.path, 'laundry.db');
        }
        final docDir = await getApplicationDocumentsDirectory();
        final dbDir = Directory(join(docDir.path, 'SmartLaundry'));
        if (!await dbDir.exists()) {
          await dbDir.create(recursive: true);
        }
        return join(dbDir.path, 'laundry.db');
      } catch (_) {
        final docDir = await getApplicationDocumentsDirectory();
        return join(docDir.path, 'laundry.db');
      }
    }
    final dbPath = await getDatabasesPath();
    return join(dbPath, 'laundry.db');
  }

  Future<String> getBackupDirectoryPath() async {
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final backupDir = Directory(join(docDir.path, 'SmartLaundry_Backups'));
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }
      return backupDir.path;
    } catch (_) {
      final currentDir = Directory.current;
      final backupDir = Directory(join(currentDir.path, 'backups'));
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }
      return backupDir.path;
    }
  }

  Future<Map<String, dynamic>> getDatabaseStatistics() async {
    final db = await database;
    final path = await getDatabasePath();
    final file = File(path);

    int fileSizeBytes = 0;
    DateTime lastModified = DateTime.now();
    if (await file.exists()) {
      fileSizeBytes = await file.length();
      lastModified = await file.lastModified();
    }

    final orderCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM orders')) ?? 0;
    final customerCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM customers')) ?? 0;
    final expenseCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM expenses')) ?? 0;
    final serviceCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM transactions')) ?? 0;
    final userCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM users')) ?? 0;

    String formatSize(int bytes) {
      if (bytes <= 0) return '0 B';
      if (bytes < 1024) return '$bytes B';
      if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }

    return {
      'path': path,
      'fileSize': formatSize(fileSizeBytes),
      'fileSizeBytes': fileSizeBytes,
      'lastModified': lastModified,
      'orderCount': orderCount,
      'customerCount': customerCount,
      'expenseCount': expenseCount,
      'serviceCount': serviceCount,
      'userCount': userCount,
    };
  }

  Future<String> createBackup({String label = 'manual'}) async {
    final db = await database;
    // Checkpoint SQLite WAL to make sure all data is flushed to main disk file
    try {
      await db.rawQuery('PRAGMA wal_checkpoint(FULL);');
    } catch (_) {}

    final dbPath = await getDatabasePath();
    final sourceFile = File(dbPath);
    if (!await sourceFile.exists()) {
      throw Exception('File database tidak ditemukan di: $dbPath');
    }

    final backupDirPath = await getBackupDirectoryPath();
    final timestamp = DateFormat('yyyy-MM-dd_HHmmss').format(DateTime.now());

    String prefix = 'laundry_backup';
    if (label == 'pre_restore') {
      prefix = 'laundry_snapshot_sebelum_restore';
    } else if (label.isNotEmpty && label != 'manual') {
      final sanitizedLabel = label.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
      prefix = 'laundry_backup_$sanitizedLabel';
    }

    final backupFileName = '${prefix}_$timestamp.db';
    final targetPath = join(backupDirPath, backupFileName);

    await sourceFile.copy(targetPath);

    // Also sync copy to root laundry.db if running in project root
    try {
      final rootDbFile = File(join(Directory.current.path, 'laundry.db'));
      await sourceFile.copy(rootDbFile.path);
    } catch (_) {}

    return targetPath;
  }

  Future<List<File>> getAvailableBackups() async {
    final backupDirPath = await getBackupDirectoryPath();
    final dir = Directory(backupDirPath);
    if (!await dir.exists()) return [];

    final list = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.db')).toList();
    list.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return list;
  }

  Future<Map<String, String>> restoreDatabaseWithSnapshot(String backupFilePath) async {
    final backupFile = File(backupFilePath);
    if (!await backupFile.exists()) {
      throw Exception('File backup tidak ditemukan: $backupFilePath');
    }

    // 1. Auto-Snapshot: Create safety backup of current data before replacing
    final snapshotPath = await createBackup(label: 'pre_restore');

    // 2. Close current database
    if (_database != null && _database!.isOpen) {
      await _database!.close();
      _database = null;
    }

    // 3. Overwrite current database file
    final dbPath = await getDatabasePath();
    await backupFile.copy(dbPath);

    // 4. Overwrite root database if present
    try {
      final rootDbFile = File(join(Directory.current.path, 'laundry.db'));
      await backupFile.copy(rootDbFile.path);
    } catch (_) {}

    // 5. Reopen database and verify
    _database = await _initDB('laundry.db');

    return {
      'restoredFile': backupFilePath,
      'snapshotFile': snapshotPath,
    };
  }

  Future<bool> restoreDatabase(String backupFilePath) async {
    await restoreDatabaseWithSnapshot(backupFilePath);
    return true;
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('laundry.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final path = await getDatabasePath();

    int retries = 5;
    while (retries > 0) {
      try {
        return await openDatabase(
          path,
          version: _databaseVersion,
          onConfigure: (db) async {
            try {
              await db.execute('PRAGMA busy_timeout = 30000;');
              await db.execute('PRAGMA journal_mode = WAL;');
              await db.execute('PRAGMA synchronous = NORMAL;');
            } catch (_) {}
          },
          onCreate: _createDB,
          onUpgrade: _onUpgrade,
          onOpen: (db) async {
            await _ensureMachineColumns(db);
            await _ensureMachinesColumns(db);
            await _ensureOrderAssignmentColumns(db);
            await _ensureOrderLoyaltyColumns(db);
            await _ensureMachineUsageHistoryTable(db);
            await _ensurePendingNotificationsTable(db);
            await _ensurePaidAmountColumn(db);
            await _ensureCustomerPhoneColumn(db);
            await _ensureCustomersTable(db);
            await _ensureCustomerLoyaltyColumns(db);
            await _ensureExpensesTable(db);
            await _ensureDurationDaysColumn(db);
            await _ensureStaffRestockableColumn(db);
            await _migrateExistingItems(db);
            await _ensureIndexes(db);
          },
        );
      } catch (e) {
        retries--;
        if (retries <= 0) rethrow;
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }
    throw Exception('Failed to open database after retries');
  }

  Future<void> _migrateExistingItems(Database db) async {
    try {
      // Set 'cuci' for items with 'cuci' or 'wash' in their name
      await db.execute('''
        UPDATE transactions 
        SET machine_type = 'cuci', machine_id = 1 
        WHERE (nama LIKE '%cuci%' OR nama LIKE '%wash%') AND machine_type IS NULL
      ''');
      // Set 'pengering' for items with 'kering', 'pengering', or 'dry' in their name
      await db.execute('''
        UPDATE transactions 
        SET machine_type = 'pengering', machine_id = 2 
        WHERE (nama LIKE '%kering%' OR nama LIKE '%pengering%' OR nama LIKE '%dry%') AND machine_type IS NULL
      ''');
      // Fix machine_type for pengering machines that got 'cuci' by default
      await db.execute('''
        UPDATE machines 
        SET machine_type = 'pengering' 
        WHERE (name LIKE '%kering%' OR name LIKE '%pengering%' OR name LIKE '%dry%') AND machine_type = 'cuci'
      ''');

      // Clean up incorrect machine_type values from older migrations
      await db.execute('''
        UPDATE transactions 
        SET machine_type = NULL, machine_id = NULL 
        WHERE machine_type = 'cuci' 
          AND nama NOT LIKE '%cuci%' 
          AND nama NOT LIKE '%wash%' 
          AND nama NOT LIKE '%basah%'
      ''');
      await db.execute('''
        UPDATE transactions 
        SET machine_type = NULL, machine_id = NULL 
        WHERE machine_type = 'pengering' 
          AND nama NOT LIKE '%kering%' 
          AND nama NOT LIKE '%pengering%' 
          AND nama NOT LIKE '%dry%'
          AND nama NOT LIKE '%jemur%'
      ''');
    } catch (e) {
      print('Error migrating items: $e');
    }
  }

  Future<void> _ensureIndexes(Database db) async {
    try {
      await db.execute('CREATE INDEX IF NOT EXISTS idx_orders_date ON orders(order_date);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_orders_user ON orders(user_id);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_order_items_order ON order_items(order_id);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_transactions_type ON transactions(type);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_transactions_mtype ON transactions(machine_type);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_usage_order ON machine_usage_history(order_id);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_usage_started ON machine_usage_history(started_at);');
    } catch (e) {
      print('Error ensuring indexes: $e');
    }
  }

  Future<void> _ensurePendingNotificationsTable(Database db) async {
    try {
      final List<Map<String, dynamic>> info = await db.rawQuery(
        "PRAGMA table_info(pending_notifications)",
      );
      final existing = info.map((r) => r['name'] as String).toSet();

      if (existing.isEmpty) {
        await db.execute('''
          CREATE TABLE pending_notifications (
            id INTEGER PRIMARY KEY,
            title TEXT NOT NULL,
            body TEXT NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');
      }
    } catch (e) {
      print('Error ensuring pending_notifications table: $e');
    }
  }

  Future<void> _ensureMachineColumns(Database db) async {
    try {
      final List<Map<String, dynamic>> info = await db.rawQuery(
        "PRAGMA table_info(transactions)",
      );
      final existing = info.map((r) => r['name'] as String).toSet();

      if (!existing.contains('machine_type')) {
        await db.execute(
          "ALTER TABLE transactions ADD COLUMN machine_type TEXT",
        );
      }

      if (!existing.contains('machine_id')) {
        await db.execute(
          "ALTER TABLE transactions ADD COLUMN machine_id INTEGER",
        );
      }
    } catch (e) {
      print('Error ensuring machine columns: $e');
    }
  }

  Future<void> _ensurePaidAmountColumn(Database db) async {
    try {
      final List<Map<String, dynamic>> info = await db.rawQuery(
        "PRAGMA table_info(orders)",
      );
      final existing = info.map((r) => r['name'] as String).toSet();

      if (!existing.contains('paid_amount')) {
        await db.execute(
          "ALTER TABLE orders ADD COLUMN paid_amount INTEGER NOT NULL DEFAULT 0",
        );
      }
    } catch (e) {
      print('Error ensuring paid_amount column: $e');
    }
  }

  Future<void> _ensureCustomerPhoneColumn(Database db) async {
    try {
      final List<Map<String, dynamic>> info = await db.rawQuery(
        "PRAGMA table_info(orders)",
      );
      final existing = info.map((r) => r['name'] as String).toSet();

      if (!existing.contains('customer_phone')) {
        await db.execute(
          "ALTER TABLE orders ADD COLUMN customer_phone TEXT",
        );
      }
    } catch (e) {
      print('Error ensuring customer_phone column: $e');
    }
  }

  Future<void> _ensureCustomersTable(Database db) async {
    try {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS customers (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          phone TEXT NOT NULL,
          address TEXT,
          created_at TEXT NOT NULL,
          wash_count_lifetime INTEGER DEFAULT 0,
          wash_count_active INTEGER DEFAULT 0,
          rewards_claimed_count INTEGER DEFAULT 0,
          dry_count_lifetime INTEGER DEFAULT 0,
          store_item_count_lifetime INTEGER DEFAULT 0,
          iron_count_lifetime INTEGER DEFAULT 0,
          total_spent_lifetime INTEGER DEFAULT 0
        )
      ''');
    } catch (e) {
      print('Error ensuring customers table: $e');
    }
  }

  Future<void> _ensureCustomerLoyaltyColumns(Database db) async {
    try {
      final List<Map<String, dynamic>> info = await db.rawQuery(
        "PRAGMA table_info(customers)",
      );
      final existing = info.map((r) => r['name'] as String).toSet();

      final columns = {
        'wash_count_lifetime': 'INTEGER DEFAULT 0',
        'wash_count_active': 'INTEGER DEFAULT 0',
        'rewards_claimed_count': 'INTEGER DEFAULT 0',
        'dry_count_lifetime': 'INTEGER DEFAULT 0',
        'store_item_count_lifetime': 'INTEGER DEFAULT 0',
        'iron_count_lifetime': 'INTEGER DEFAULT 0',
        'total_spent_lifetime': 'INTEGER DEFAULT 0',
      };

      for (var entry in columns.entries) {
        if (!existing.contains(entry.key)) {
          await db.execute("ALTER TABLE customers ADD COLUMN ${entry.key} ${entry.value}");
        }
      }
    } catch (e) {
      print('Error ensuring customer loyalty columns: $e');
    }
  }

  Future<void> _ensureOrderLoyaltyColumns(Database db) async {
    try {
      final List<Map<String, dynamic>> info = await db.rawQuery(
        "PRAGMA table_info(orders)",
      );
      final existing = info.map((r) => r['name'] as String).toSet();

      final columns = {
        'loyalty_claimed': 'INTEGER DEFAULT 0',
        'wash_sequence': 'INTEGER DEFAULT 0',
        'stamps_used': 'INTEGER DEFAULT 0',
      };

      for (var entry in columns.entries) {
        if (!existing.contains(entry.key)) {
          await db.execute("ALTER TABLE orders ADD COLUMN ${entry.key} ${entry.value}");
        }
      }
    } catch (e) {
      print('Error ensuring order loyalty columns: $e');
    }
  }

  Future<void> _ensureExpensesTable(Database db) async {
    try {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS expenses (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          amount INTEGER NOT NULL,
          date TEXT NOT NULL,
          created_at TEXT NOT NULL
        )
      ''');
    } catch (e) {
      print('Error ensuring expenses table: $e');
    }
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nama TEXT NOT NULL,
        harga INTEGER NOT NULL,
        stock INTEGER,
        is_unlimited_stock INTEGER NOT NULL DEFAULT 0,
        is_staff_restockable INTEGER NOT NULL DEFAULT 0,
        type INTEGER NOT NULL DEFAULT 0,
        machine_type TEXT,
        machine_id INTEGER,
        parent_id INTEGER,
        is_used INTEGER NOT NULL DEFAULT 0,
        duration_days INTEGER,
        created_at TEXT NOT NULL,
        FOREIGN KEY (parent_id) REFERENCES transactions (id)
      )
    ''');

    await db.execute('''
      CREATE TABLE orders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_name TEXT NOT NULL,
        customer_phone TEXT,
        order_date TEXT NOT NULL,
        total_amount INTEGER NOT NULL,
        status TEXT NOT NULL,
        user_id INTEGER NOT NULL,
        is_paid INTEGER NOT NULL DEFAULT 0,
        paid_amount INTEGER NOT NULL DEFAULT 0,
        payment_method TEXT NOT NULL DEFAULT 'cash',
        qris_url TEXT,
        qris_id TEXT,
        payment_timestamp TEXT,
        assigned_machine_id INTEGER,
        machine_started_at TEXT,
        loyalty_claimed INTEGER DEFAULT 0,
        wash_sequence INTEGER DEFAULT 0,
        stamps_used INTEGER DEFAULT 0,
        FOREIGN KEY (user_id) REFERENCES users (id)
      )
    ''');

    await db.execute('''
      CREATE TABLE order_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        order_id INTEGER NOT NULL,
        item_id INTEGER NOT NULL,
        item_name TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        price INTEGER NOT NULL,
        note TEXT,
        FOREIGN KEY (order_id) REFERENCES orders (id),
        FOREIGN KEY (item_id) REFERENCES transactions (id)
      )
    ''');

    await db.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT NOT NULL UNIQUE,
        password TEXT NOT NULL,
        role TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    // Machines table: stores machine definitions for cuci/pengering etc.
    await db.execute('''
      CREATE TABLE machines (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        machine_type TEXT NOT NULL DEFAULT 'cuci',
        name TEXT NOT NULL,
        url TEXT NOT NULL,
        key TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    // Machine usage history: tracks each individual machine run
    await db.execute('''
      CREATE TABLE machine_usage_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        order_id INTEGER NOT NULL,
        machine_id INTEGER NOT NULL,
        machine_name TEXT NOT NULL,
        customer_name TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'Success',
        error_message TEXT,
        started_at TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (order_id) REFERENCES orders (id),
        FOREIGN KEY (machine_id) REFERENCES machines (id)
      )
    ''');

    // Pending notifications: stores notifications to display when app is foreground
    await db.execute('''
      CREATE TABLE pending_notifications (
        id INTEGER PRIMARY KEY,
        title TEXT NOT NULL,
        body TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE customers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT NOT NULL,
        address TEXT,
        created_at TEXT NOT NULL,
        wash_count_lifetime INTEGER DEFAULT 0,
        wash_count_active INTEGER DEFAULT 0,
        rewards_claimed_count INTEGER DEFAULT 0,
        dry_count_lifetime INTEGER DEFAULT 0,
        store_item_count_lifetime INTEGER DEFAULT 0,
        iron_count_lifetime INTEGER DEFAULT 0,
        total_spent_lifetime INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE expenses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        amount INTEGER NOT NULL,
        date TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _ensureMachinesColumns(Database db) async {
    try {
      final List<Map<String, dynamic>> info = await db.rawQuery(
        "PRAGMA table_info(machines)",
      );
      final existing = info.map((r) => r['name'] as String).toSet();

      if (!existing.contains('machine_type')) {
        await db.execute(
          "ALTER TABLE machines ADD COLUMN machine_type TEXT DEFAULT 'cuci'",
        );
      }
    } catch (e) {
      print('Error ensuring machines columns: $e');
    }
  }

  Future<void> _ensureOrderAssignmentColumns(Database db) async {
    try {
      final List<Map<String, dynamic>> info = await db.rawQuery(
        "PRAGMA table_info(orders)",
      );
      final existing = info.map((r) => r['name'] as String).toSet();

      if (!existing.contains('assigned_machine_id')) {
        await db.execute(
          "ALTER TABLE orders ADD COLUMN assigned_machine_id INTEGER",
        );
      }
      if (!existing.contains('machine_started_at')) {
        await db.execute(
          "ALTER TABLE orders ADD COLUMN machine_started_at TEXT",
        );
      }
    } catch (e) {
      print('Error ensuring order assignment columns: $e');
    }
  }

  Future<void> _ensureMachineUsageHistoryTable(Database db) async {
    try {
      final List<Map<String, dynamic>> tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='machine_usage_history'",
      );
      if (tables.isEmpty) {
        await db.execute('''
          CREATE TABLE machine_usage_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            order_id INTEGER NOT NULL,
            machine_id INTEGER NOT NULL,
            machine_name TEXT NOT NULL,
            customer_name TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'Success',
            error_message TEXT,
            started_at TEXT NOT NULL,
            created_at TEXT NOT NULL,
            FOREIGN KEY (order_id) REFERENCES orders (id),
            FOREIGN KEY (machine_id) REFERENCES machines (id)
          )
        ''');
      } else {
        final List<Map<String, dynamic>> info = await db.rawQuery(
          "PRAGMA table_info(machine_usage_history)",
        );
        final existing = info.map((r) => r['name'] as String).toSet();
        if (!existing.contains('status')) {
          await db.execute(
            "ALTER TABLE machine_usage_history ADD COLUMN status TEXT NOT NULL DEFAULT 'Success'",
          );
        }
        if (!existing.contains('error_message')) {
          await db.execute(
            "ALTER TABLE machine_usage_history ADD COLUMN error_message TEXT",
          );
        }
      }
    } catch (e) {
      print('Error ensuring machine_usage_history table: $e');
    }
  }

  // Order-related methods
  Future<int> insertOrder(Order order) async {
    final db = await database;
    int orderId = 0;

    await db.transaction((txn) async {
      // 1. Insert the order
      orderId = await txn.insert('orders', {
        'customer_name': DbEncryptionHelper.encrypt(order.customerName),
        'customer_phone': order.customerPhone != null ? DbEncryptionHelper.encrypt(order.customerPhone!) : null,
        'order_date': order.orderDate.toIso8601String(),
        'total_amount': order.totalAmount,
        'status': order.status,
        'user_id': order.userId,
        'is_paid': order.isPaid ? 1 : 0,
        'paid_amount': order.paidAmount,
        'payment_method': order.paymentMethod,
        'qris_url': order.qrisUrl,
        'qris_id': order.qrisId,
        'payment_timestamp': order.paymentTimestamp?.toIso8601String(),
        'assigned_machine_id': order.assignedMachineId,
        'machine_started_at': order.machineStartedAt?.toIso8601String(),
        'loyalty_claimed': order.loyaltyClaimed ? 1 : 0,
        'wash_sequence': order.washSequence,
        'stamps_used': order.stampsUsed,
      });

      // 2. Insert all order items
      int washQty = 0;
      int dryQty = 0;
      int ironQty = 0;
      int storeQty = 0;

      for (var item in order.items) {
        await txn.insert('order_items', {
          'order_id': orderId,
          'item_id': item.itemId,
          'item_name': item.itemName,
          'quantity': item.quantity,
          'price': item.price,
          'note': item.note != null ? DbEncryptionHelper.encrypt(item.note!) : null,
        });

        final nameLower = item.itemName.toLowerCase();
        final mType = (item.machineType ?? '').toLowerCase();
        if (mType == 'cuci' || nameLower.contains('cuci') || nameLower.contains('wash') || nameLower.contains('basah')) {
          washQty += item.quantity;
        } else if (mType == 'pengering' || nameLower.contains('kering') || nameLower.contains('pengering') || nameLower.contains('dry')) {
          dryQty += item.quantity;
        } else if (mType == 'gosok' || mType == 'iron' || nameLower.contains('gosok') || nameLower.contains('setrika')) {
          ironQty += item.quantity;
        } else {
          storeQty += item.quantity;
        }
      }

      // 3. Atomically update or insert customer loyalty statistics
      final customerNameClean = order.customerName.trim();
      final customerPhoneClean = order.customerPhone?.trim();

      if (customerNameClean.isNotEmpty) {
        List<Map<String, dynamic>> existingCust = [];
        if (customerPhoneClean != null && customerPhoneClean.isNotEmpty) {
          existingCust = await txn.query(
            'customers',
            where: 'phone = ?',
            whereArgs: [DbEncryptionHelper.encrypt(customerPhoneClean)],
          );
        }

        if (existingCust.isEmpty) {
          existingCust = await txn.query(
            'customers',
            where: 'name = ?',
            whereArgs: [DbEncryptionHelper.encrypt(customerNameClean)],
          );
        }

        if (existingCust.isNotEmpty) {
          final custMap = existingCust.first;
          final custId = custMap['id'] as int;

          int activeStamps = (custMap['wash_count_active'] as num?)?.toInt() ?? 0;
          int lifetimeWash = (custMap['wash_count_lifetime'] as num?)?.toInt() ?? 0;
          int rewardsClaimed = (custMap['rewards_claimed_count'] as num?)?.toInt() ?? 0;
          int lifetimeDry = (custMap['dry_count_lifetime'] as num?)?.toInt() ?? 0;
          int lifetimeStore = (custMap['store_item_count_lifetime'] as num?)?.toInt() ?? 0;
          int lifetimeIron = (custMap['iron_count_lifetime'] as num?)?.toInt() ?? 0;
          int lifetimeSpent = (custMap['total_spent_lifetime'] as num?)?.toInt() ?? 0;

          if (order.loyaltyClaimed) {
            activeStamps = (activeStamps - order.stampsUsed).clamp(0, 999999);
            rewardsClaimed += 1;
          }

          activeStamps += washQty;
          lifetimeWash += washQty;
          lifetimeDry += dryQty;
          lifetimeStore += storeQty;
          lifetimeIron += ironQty;
          lifetimeSpent += order.totalAmount;

          await txn.update(
            'customers',
            {
              'wash_count_active': activeStamps,
              'wash_count_lifetime': lifetimeWash,
              'rewards_claimed_count': rewardsClaimed,
              'dry_count_lifetime': lifetimeDry,
              'store_item_count_lifetime': lifetimeStore,
              'iron_count_lifetime': lifetimeIron,
              'total_spent_lifetime': lifetimeSpent,
            },
            where: 'id = ?',
            whereArgs: [custId],
          );
        } else {
          int activeStamps = washQty;
          int rewardsClaimed = 0;
          if (order.loyaltyClaimed) {
            activeStamps = (activeStamps - order.stampsUsed).clamp(0, 999999);
            rewardsClaimed = 1;
          }

          await txn.insert('customers', {
            'name': DbEncryptionHelper.encrypt(customerNameClean),
            'phone': customerPhoneClean != null ? DbEncryptionHelper.encrypt(customerPhoneClean) : '',
            'address': null,
            'created_at': DateTime.now().toIso8601String(),
            'wash_count_active': activeStamps,
            'wash_count_lifetime': washQty,
            'rewards_claimed_count': rewardsClaimed,
            'dry_count_lifetime': dryQty,
            'store_item_count_lifetime': storeQty,
            'iron_count_lifetime': ironQty,
            'total_spent_lifetime': order.totalAmount,
          });
        }
      }
    });

    return orderId;
  }

  Future<List<Order>> getAllOrders({int? userId}) async {
    final db = await database;
    final List<Map<String, dynamic>> orderMaps = await db.query(
      'orders',
      where: userId != null ? 'user_id = ?' : null,
      whereArgs: userId != null ? [userId] : null,
      orderBy: 'order_date DESC',
    );

    return Future.wait(
      orderMaps.map((orderMap) async {
        final List<Map<String, dynamic>> itemMaps = await db.rawQuery('''
          SELECT oi.*, t.machine_type 
          FROM order_items oi 
          LEFT JOIN transactions t ON oi.item_id = t.id 
          WHERE oi.order_id = ?
        ''', [orderMap['id']]);

        final items = itemMaps.map((item) => OrderItem.fromMap(item)).toList();
        return Order.fromMap(orderMap, items);
      }),
    );
  }

  Future<List<Order>> getOrdersByDate(String date) async {
    final db = await database;
    final List<Map<String, dynamic>> orderMaps = await db.query(
      'orders',
      where: "order_date LIKE ?",
      whereArgs: ['$date%'],
      orderBy: 'order_date DESC',
    );

    return Future.wait(
      orderMaps.map((orderMap) async {
        final List<Map<String, dynamic>> itemMaps = await db.rawQuery('''
          SELECT oi.*, t.machine_type 
          FROM order_items oi 
          LEFT JOIN transactions t ON oi.item_id = t.id 
          WHERE oi.order_id = ?
        ''', [orderMap['id']]);

        final items = itemMaps.map((item) => OrderItem.fromMap(item)).toList();
        return Order.fromMap(orderMap, items);
      }),
    );
  }

  Future<Order?> getOrder(int id) async {
    final db = await database;
    final List<Map<String, dynamic>> orderMaps = await db.query(
      'orders',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (orderMaps.isEmpty) return null;

    final List<Map<String, dynamic>> itemMaps = await db.rawQuery('''
      SELECT oi.*, t.machine_type 
      FROM order_items oi 
      LEFT JOIN transactions t ON oi.item_id = t.id 
      WHERE oi.order_id = ?
    ''', [id]);

    final items = itemMaps.map((item) => OrderItem.fromMap(item)).toList();
    return Order.fromMap(orderMaps.first, items);
  }

  Future<int> updateOrderStatus(int id, String status) async {
    final db = await database;
    return await db.update(
      'orders',
      {'status': status},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> updateOrder(Order order) async {
    if (order.id == null) return 0;

    final db = await database;
    int result = 0;

    await db.transaction((txn) async {
      // Update the order
      result = await txn.update(
        'orders',
        {
          'customer_name': DbEncryptionHelper.encrypt(order.customerName),
          'customer_phone': order.customerPhone != null ? DbEncryptionHelper.encrypt(order.customerPhone!) : null,
          'order_date': order.orderDate.toIso8601String(),
          'total_amount': order.totalAmount,
          'status': order.status,
          'user_id': order.userId,
          'is_paid': order.isPaid ? 1 : 0,
          'paid_amount': order.paidAmount,
          'payment_method': order.paymentMethod,
          'qris_url': order.qrisUrl,
          'qris_id': order.qrisId,
          'payment_timestamp': order.paymentTimestamp?.toIso8601String(),
          'assigned_machine_id': order.assignedMachineId,
          'machine_started_at': order.machineStartedAt?.toIso8601String(),
          'loyalty_claimed': order.loyaltyClaimed ? 1 : 0,
          'wash_sequence': order.washSequence,
          'stamps_used': order.stampsUsed,
        },
        where: 'id = ?',
        whereArgs: [order.id],
      );

      // Delete all existing order items
      await txn.delete(
        'order_items',
        where: 'order_id = ?',
        whereArgs: [order.id],
      );

      // Insert new order items
      for (var item in order.items) {
        await txn.insert('order_items', {
          'order_id': order.id,
          'item_id': item.itemId,
          'item_name': item.itemName,
          'quantity': item.quantity,
          'price': item.price,
          'note': item.note,
        });
      }
    });

    return result;
  }

  Future<int> updateOrderPaymentStatus(int id, bool isPaid) async {
    final db = await database;
    return await db.update(
      'orders',
      {'is_paid': isPaid ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> insertTransaction(TransactionModel transaction) async {
    final db = await database;
    return await db.insert('transactions', transaction.toMap());
  }

  Future<List<TransactionModel>> getAllTransactions() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'transactions',
      orderBy: 'created_at DESC',
    );

    return List.generate(maps.length, (i) {
      return TransactionModel.fromMap(maps[i]);
    });
  }

  Future<TransactionModel?> getTransaction(int id) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'transactions',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (maps.isEmpty) return null;
    return TransactionModel.fromMap(maps.first);
  }

  Future<int> updateTransaction(TransactionModel transaction) async {
    final db = await database;
    return await db.update(
      'transactions',
      transaction.toMap(),
      where: 'id = ?',
      whereArgs: [transaction.id],
    );
  }

  Future<int> deleteTransaction(int id) async {
    final db = await database;
    return await db.delete('transactions', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> assignMachineToOrder(
    int orderId,
    int machineId,
    DateTime startedAt,
  ) async {
    return await updateOrderMachineAssignment(orderId, machineId, startedAt);
  }

  // New simplified method: hanya update machine assignment dan status
  Future<int> updateOrderMachineAssignment(
    int orderId,
    int machineId,
    DateTime startedAt,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      // 1. Mark any previous order on this machine as 'Finished'
      // Only if it's not the same order and not already completed
      await txn.update(
        'orders',
        {'status': 'Finished'},
        where: 'assigned_machine_id = ? AND status != ? AND id != ?',
        whereArgs: [machineId, 'Completed', orderId],
      );

      // 2. Assign the new order to the machine
      await txn.update(
        'orders',
        {
          'assigned_machine_id': machineId,
          'machine_started_at': startedAt.toIso8601String(),
          'status': 'Proses',
        },
        where: 'id = ?',
        whereArgs: [orderId],
      );
    });
    return 1;
  }

  // Decrease quantity for an order_items row by `amount`.
  // If resulting quantity <= 0, the order_items row is deleted.
  Future<int> decreaseOrderItemQuantityById(int orderItemId, int amount) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'order_items',
      where: 'id = ?',
      whereArgs: [orderItemId],
    );

    if (maps.isEmpty) return 0;

    final currentQty = maps.first['quantity'] as int? ?? 0;
    final newQty = currentQty - amount;

    if (newQty > 0) {
      return await db.update(
        'order_items',
        {'quantity': newQty},
        where: 'id = ?',
        whereArgs: [orderItemId],
      );
    } else {
      return await db.delete(
        'order_items',
        where: 'id = ?',
        whereArgs: [orderItemId],
      );
    }
  }

  // Record machine usage in history (each individual machine run)
  Future<int> recordMachineUsage({
    required int orderId,
    required int machineId,
    required String machineName,
    required String customerName,
    required DateTime startedAt,
    String status = 'Success',
    String? errorMessage,
  }) async {
    final db = await database;
    return await db.insert('machine_usage_history', {
      'order_id': orderId,
      'machine_id': machineId,
      'machine_name': machineName,
      'customer_name': customerName,
      'status': status,
      'error_message': errorMessage,
      'started_at': startedAt.toIso8601String(),
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<int> updateMachineUsageStatus({
    required int historyId,
    required String status,
    String? errorMessage,
  }) async {
    final db = await database;
    return await db.update(
      'machine_usage_history',
      {
        'status': status,
        if (errorMessage != null) 'error_message': errorMessage,
      },
      where: 'id = ?',
      whereArgs: [historyId],
    );
  }

  /// Marks 'Sended' records older than 30 minutes as 'Failed'
  Future<int> cleanupStuckUsageRecords() async {
    final db = await database;
    final thirtyMinutesAgo = DateTime.now().subtract(
      const Duration(minutes: 30),
    );

    return await db.update(
      'machine_usage_history',
      {'status': 'Failed', 'error_message': 'Terhenti (App ditutup/Crash)'},
      where: "status = 'Sended' AND started_at < ?",
      whereArgs: [thirtyMinutesAgo.toIso8601String()],
    );
  }

  // Get machine usage history with optional type filter
  Future<List<Map<String, dynamic>>> getMachineUsageHistory({String? type}) async {
    final db = await database;
    if (type != null) {
      return await db.rawQuery('''
        SELECT h.*, m.machine_type 
        FROM machine_usage_history h
        JOIN machines m ON h.machine_id = m.id
        WHERE m.machine_type = ?
        ORDER BY h.started_at DESC
      ''', [type]);
    }
    return await db.query('machine_usage_history', orderBy: 'started_at DESC');
  }

  Future<void> close() async {
    final db = await database;
    db.close();
  }

  Future<void> _ensureDurationDaysColumn(Database db) async {
    try {
      final List<Map<String, dynamic>> columns =
          await db.rawQuery('PRAGMA table_info(transactions)');
      final bool hasDuration =
          columns.any((column) => column['name'] == 'duration_days');

      if (!hasDuration) {
        await db.execute('ALTER TABLE transactions ADD COLUMN duration_days INTEGER');
      }
    } catch (e) {
      print('Error ensuring duration_days column: $e');
    }
  }

  Future<void> _ensureStaffRestockableColumn(Database db) async {
    try {
      final List<Map<String, dynamic>> columns =
          await db.rawQuery('PRAGMA table_info(transactions)');
      final bool hasCol =
          columns.any((column) => column['name'] == 'is_staff_restockable');

      if (!hasCol) {
        await db.execute('ALTER TABLE transactions ADD COLUMN is_staff_restockable INTEGER NOT NULL DEFAULT 0');
      }
    } catch (e) {
      print('Error ensuring is_staff_restockable column: $e');
    }
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 9) {
      // Add payment-related columns to orders table if they don't exist
      try {
        await db.execute('''
          ALTER TABLE orders ADD COLUMN payment_method TEXT NOT NULL DEFAULT 'cash'
        ''');
        await db.execute('''
          ALTER TABLE orders ADD COLUMN qris_url TEXT
        ''');
        await db.execute('''
          ALTER TABLE orders ADD COLUMN qris_id TEXT
        ''');
        await db.execute('''
          ALTER TABLE orders ADD COLUMN payment_timestamp TEXT
        ''');
      } catch (e) {
        print('Error upgrading database: $e');
      }
    }

    if (oldVersion < 10) {
      // add machine_type and machine_id to transactions
      try {
        await db.execute(
          "ALTER TABLE transactions ADD COLUMN machine_type TEXT",
        );
        await db.execute(
          "ALTER TABLE transactions ADD COLUMN machine_id INTEGER",
        );
      } catch (e) {
        print('Error adding machine columns: $e');
      }
    }

    if (oldVersion < 13) {
      // add machine_type to machines table if missing
      try {
        await db.execute(
          "ALTER TABLE machines ADD COLUMN machine_type TEXT DEFAULT 'cuci'",
        );
      } catch (e) {
        print('Error adding machine_type to machines: $e');
      }
    }

    if (oldVersion < 14) {
      // add assigned_machine_id and machine_started_at to orders
      try {
        await db.execute(
          "ALTER TABLE orders ADD COLUMN assigned_machine_id INTEGER",
        );
        await db.execute(
          "ALTER TABLE orders ADD COLUMN machine_started_at TEXT",
        );
      } catch (e) {
        print('Error adding order assignment columns: $e');
      }
    }

    if (oldVersion < 12) {
      // create machines table if upgrading from older version
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS machines (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            url TEXT NOT NULL,
            key TEXT NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');
      } catch (e) {
        print('Error creating machines table: $e');
      }
    }

    if (oldVersion < 8) {
      // Previous upgrade logic for version 8
      await db.execute('DROP TABLE IF EXISTS transactions');
      await db.execute('''
        CREATE TABLE transactions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          nama TEXT NOT NULL,
          harga INTEGER NOT NULL,
          stock INTEGER,
          is_unlimited_stock INTEGER NOT NULL DEFAULT 0,
          type INTEGER NOT NULL DEFAULT 0,
          parent_id INTEGER,
          is_used INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL,
          FOREIGN KEY (parent_id) REFERENCES transactions (id)
        )
      ''');
    }
  }

  // Check if item has enough stock
  Future<bool> checkStock(int itemId, int quantity) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'transactions',
      where: 'id = ?',
      whereArgs: [itemId],
    );

    if (maps.isEmpty) return false;

    final item = TransactionModel.fromMap(maps.first);
    return item.isUnlimitedStock || (item.stock ?? 0) >= quantity;
  }

  // Update stock after order
  Future<bool> updateStockAfterOrder(int itemId, int quantity) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'transactions',
      where: 'id = ?',
      whereArgs: [itemId],
    );

    if (maps.isEmpty) return false;

    final item = TransactionModel.fromMap(maps.first);
    if (item.isUnlimitedStock) return true;

    final newStock = (item.stock ?? 0) - quantity;
    if (newStock < 0) return false;

    final rowsAffected = await db.update(
      'transactions',
      {'stock': newStock},
      where: 'id = ?',
      whereArgs: [itemId],
    );

    return rowsAffected > 0;
  }

  // --- Machines CRUD ---
  Future<int> insertMachine(MachineModel machine) async {
    final db = await database;
    return await db.insert('machines', machine.toMap());
  }

  Future<List<MachineModel>> getAllMachines({String? type}) async {
    final db = await database;
    List<Map<String, dynamic>> maps;
    if (type != null && type.isNotEmpty) {
      maps = await db.query(
        'machines',
        where: 'machine_type = ?',
        whereArgs: [type],
        orderBy: 'created_at DESC',
      );
    } else {
      maps = await db.query('machines', orderBy: 'created_at DESC');
    }
    return maps.map((m) => MachineModel.fromMap(m)).toList();
  }

  Future<MachineModel?> getMachine(int id) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'machines',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isEmpty) return null;
    return MachineModel.fromMap(maps.first);
  }

  Future<int> updateMachine(MachineModel machine) async {
    final db = await database;
    return await db.update(
      'machines',
      machine.toMap(),
      where: 'id = ?',
      whereArgs: [machine.id],
    );
  }

  Future<int> deleteMachine(int id) async {
    final db = await database;
    return await db.delete('machines', where: 'id = ?', whereArgs: [id]);
  }

  // --- Customer Methods ---
  Future<int> insertCustomer(Map<String, dynamic> customer) async {
    final db = await database;
    return await db.insert('customers', customer);
  }

  Future<List<Map<String, dynamic>>> getAllCustomers() async {
    final db = await database;
    return await db.query('customers', orderBy: 'name ASC');
  }

  Future<int> updateCustomer(Map<String, dynamic> customer) async {
    final db = await database;
    return await db.update(
      'customers',
      customer,
      where: 'id = ?',
      whereArgs: [customer['id']],
    );
  }

  Future<int> deleteCustomer(int id) async {
    final db = await database;
    return await db.delete('customers', where: 'id = ?', whereArgs: [id]);
  }

  Future<Map<String, dynamic>?> getCustomer(int id) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'customers',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isEmpty) return null;
    return maps.first;
  }

  Future<bool> checkIfCustomerPhoneExists(String phone) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'customers',
      where: 'phone = ?',
      whereArgs: [DbEncryptionHelper.encrypt(phone)],
    );
    return maps.isNotEmpty;
  }

  // --- Expenses Methods ---
  Future<int> insertExpense(Map<String, dynamic> expense) async {
    final db = await database;
    return await db.insert('expenses', expense);
  }

  Future<List<Map<String, dynamic>>> getExpensesByDate(String date) async {
    final db = await database;
    return await db.query(
      'expenses',
      where: 'date = ?',
      whereArgs: [date],
      orderBy: 'id DESC'
    );
  }

  Future<int> deleteExpense(int id) async {
    final db = await database;
    return await db.delete('expenses', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> getExpensesByDateRange(String start, String end) async {
    final db = await database;
    return await db.query(
      'expenses',
      where: 'date >= ? AND date <= ?',
      whereArgs: [start, end],
      orderBy: 'date DESC, id DESC'
    );
  }

  Future<List<Order>> getOrdersByDateRange(String start, String end) async {
    final db = await database;
    final List<Map<String, dynamic>> orderMaps = await db.query(
      'orders',
      where: "date(order_date) >= ? AND date(order_date) <= ?",
      whereArgs: [start, end],
      orderBy: 'order_date DESC',
    );

    return Future.wait(
      orderMaps.map((orderMap) async {
        final List<Map<String, dynamic>> itemMaps = await db.rawQuery('''
          SELECT oi.*, t.machine_type 
          FROM order_items oi 
          LEFT JOIN transactions t ON oi.item_id = t.id 
          WHERE oi.order_id = ?
        ''', [orderMap['id']]);

        final items = itemMaps.map((item) => OrderItem.fromMap(item)).toList();
        return Order.fromMap(orderMap, items);
      }),
    );
  }

  /// Get comprehensive customer statistics & loyalty points
  Future<Map<String, dynamic>> getCustomerFullStats({
    int? customerId,
    String? name,
    String? phone,
  }) async {
    final db = await database;
    Map<String, dynamic>? cust;

    if (customerId != null) {
      final res = await db.query('customers', where: 'id = ?', whereArgs: [customerId]);
      if (res.isNotEmpty) cust = res.first;
    }
    if (cust == null && phone != null && phone.trim().isNotEmpty) {
      final res = await db.query('customers', where: 'phone = ?', whereArgs: [DbEncryptionHelper.encrypt(phone.trim())]);
      if (res.isNotEmpty) cust = res.first;
    }
    if (cust == null && name != null && name.trim().isNotEmpty) {
      final res = await db.query('customers', where: 'name = ?', whereArgs: [DbEncryptionHelper.encrypt(name.trim())]);
      if (res.isNotEmpty) cust = res.first;
    }

    int activeStamps = (cust?['wash_count_active'] as num?)?.toInt() ?? 0;
    int lifetimeWash = (cust?['wash_count_lifetime'] as num?)?.toInt() ?? 0;
    int rewardsClaimed = (cust?['rewards_claimed_count'] as num?)?.toInt() ?? 0;
    int lifetimeDry = (cust?['dry_count_lifetime'] as num?)?.toInt() ?? 0;
    int lifetimeStore = (cust?['store_item_count_lifetime'] as num?)?.toInt() ?? 0;
    int lifetimeIron = (cust?['iron_count_lifetime'] as num?)?.toInt() ?? 0;
    int lifetimeSpent = (cust?['total_spent_lifetime'] as num?)?.toInt() ?? 0;

    // Also calculate from actual historical orders for backfilling accuracy
    final customerCleanName = name?.trim() ?? (cust != null ? DbEncryptionHelper.decrypt(cust['name']) : '');
    final customerCleanPhone = phone?.trim() ?? (cust != null ? DbEncryptionHelper.decrypt(cust['phone']) : '');

    if (customerCleanName.isNotEmpty || customerCleanPhone.isNotEmpty) {
      try {
        final allOrders = await getAllOrders();
        final matchedOrders = allOrders.where((o) {
          final isNameMatch = customerCleanName.isNotEmpty && o.customerName.trim().toLowerCase() == customerCleanName.toLowerCase();
          final isPhoneMatch = customerCleanPhone.isNotEmpty && o.customerPhone != null && o.customerPhone!.trim() == customerCleanPhone;
          return isNameMatch || isPhoneMatch;
        }).toList();

        int orderWash = 0;
        int orderDry = 0;
        int orderIron = 0;
        int orderStore = 0;
        int orderSpent = 0;
        int orderClaimed = 0;

        for (var o in matchedOrders) {
          orderSpent += o.totalAmount;
          if (o.loyaltyClaimed) {
            orderClaimed += 1;
          }
          for (var it in o.items) {
            final n = it.itemName.toLowerCase();
            final m = (it.machineType ?? '').toLowerCase();
            if (m == 'cuci' || n.contains('cuci') || n.contains('wash') || n.contains('basah')) {
              orderWash += it.quantity;
            } else if (m == 'pengering' || n.contains('kering') || n.contains('pengering') || n.contains('dry')) {
              orderDry += it.quantity;
            } else if (m == 'gosok' || m == 'iron' || n.contains('gosok') || n.contains('setrika')) {
              orderIron += it.quantity;
            } else {
              orderStore += it.quantity;
            }
          }
        }

        if (orderWash > lifetimeWash) lifetimeWash = orderWash;
        if (orderDry > lifetimeDry) lifetimeDry = orderDry;
        if (orderIron > lifetimeIron) lifetimeIron = orderIron;
        if (orderStore > lifetimeStore) lifetimeStore = orderStore;
        if (orderSpent > lifetimeSpent) lifetimeSpent = orderSpent;
        if (orderClaimed > rewardsClaimed) rewardsClaimed = orderClaimed;

        // If customer record active stamps is 0 but had past washes without claiming
        if (activeStamps == 0 && lifetimeWash > 0 && rewardsClaimed == 0) {
          activeStamps = lifetimeWash;
        }
      } catch (_) {}
    }

    // Load SharedPreferences for loyalty settings
    final prefs = await SharedPreferences.getInstance();
    final bool loyaltyEnabled = prefs.getBool('loyalty_program_enabled') ?? true;
    final int loyaltyThreshold = prefs.getInt('loyalty_wash_threshold') ?? 5;

    return {
      'customer_id': cust?['id'],
      'name': customerCleanName,
      'phone': customerCleanPhone,
      'wash_count_lifetime': lifetimeWash,
      'wash_count_active': activeStamps,
      'rewards_claimed_count': rewardsClaimed,
      'dry_count_lifetime': lifetimeDry,
      'store_item_count_lifetime': lifetimeStore,
      'iron_count_lifetime': lifetimeIron,
      'total_spent_lifetime': lifetimeSpent,
      'loyalty_enabled': loyaltyEnabled,
      'loyalty_threshold': loyaltyThreshold,
      'can_claim_reward': loyaltyEnabled && activeStamps >= loyaltyThreshold && loyaltyThreshold > 0,
      'available_rewards': loyaltyThreshold > 0 ? (activeStamps ~/ loyaltyThreshold) : 0,
    };
  }
}
