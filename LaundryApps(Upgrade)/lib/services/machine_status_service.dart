import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class MachineStatusService {
  MachineStatusService._init();
  static final MachineStatusService instance = MachineStatusService._init();

  Timer? _timer;
  String _baseUrl = 'http://127.0.0.1:5001/';
  String _dashboardUrl = 'http://127.0.0.1:5000/';
  final Map<String, dynamic> _states = {};
  final ValueNotifier<int> _notifier = ValueNotifier<int>(0);
  bool _hasFetchedOnce = false;
  bool _lastFetchFailed = false;
  final Set<int> _activatingIds = {};
  final Set<String> _processingOrderKeys = {};
  final Set<String> _failedOrderKeys = {};

  // v2: Connectivity status
  bool _internetOk = false;
  bool _thinqOk = false;
  bool _bardiOk = false;
  bool _waOk = false;
  int _thinqDeviceCount = 0;
  int _bardiDeviceCount = 0;

  ValueListenable<int> get updates => _notifier;

  Map<String, dynamic> get states => _states;
  bool get hasFetchedOnce => _hasFetchedOnce;
  bool get lastFetchFailed => _lastFetchFailed;
  Set<int> get activatingIds => _activatingIds;
  Set<String> get processingOrderKeys => _processingOrderKeys;
  Set<String> get failedOrderKeys => _failedOrderKeys;

  // v2: Connectivity getters
  bool get internetOk => _internetOk;
  bool get thinqOk => _thinqOk;
  bool get bardiOk => _bardiOk;
  bool get waOk => _waOk;
  int get thinqDeviceCount => _thinqDeviceCount;
  int get bardiDeviceCount => _bardiDeviceCount;
  String get dashboardUrl => _dashboardUrl;

  bool isActivating(int machineId) => _activatingIds.contains(machineId);
  bool isOrderProcessing(String orderKey) =>
      _processingOrderKeys.contains(orderKey);
  bool isOrderFailed(String orderKey) => _failedOrderKeys.contains(orderKey);

  void setActivating(int machineId, bool activating) {
    if (activating) {
      _activatingIds.add(machineId);
    } else {
      _activatingIds.remove(machineId);
    }
    _notifier.value++; // Trigger UI update
  }

  void setOrderProcessing(String orderKey, bool processing) {
    if (processing) {
      _processingOrderKeys.add(orderKey);
      _failedOrderKeys.remove(orderKey); // Clear failure if re-trying
    } else {
      _processingOrderKeys.remove(orderKey);
    }
    _notifier.value++;
  }

  void setOrderFailed(String orderKey, bool failed) {
    if (failed) {
      _failedOrderKeys.add(orderKey);
      _processingOrderKeys.remove(orderKey);
    } else {
      _failedOrderKeys.remove(orderKey);
    }
    _notifier.value++;
  }

  void updateMachineStatus(String machineName, String status) {
    final entry = _states[machineName] ?? {};
    final newEntry = Map<String, dynamic>.from(entry is Map ? entry : {});
    newEntry['status'] = status;
    // Optimistically set state to 'on' if we are making it unready
    if (status.toLowerCase() == 'unready') {
      newEntry['state'] = 'on';
    }
    _states[machineName] = newEntry;
    _states['sensor.' + machineName] = newEntry;
    _notifier.value++;
  }

  void updateMachineStatusOptimistic(String machineName, {
    required String status,
    String? customerName,
    String? customerPhone,
    String? state,
    String? runState,
  }) {
    final entry = _states[machineName] ?? {};
    final newEntry = Map<String, dynamic>.from(entry is Map ? entry : {});
    newEntry['status'] = status;
    if (customerName != null) newEntry['customer_name'] = customerName;
    if (customerPhone != null) newEntry['customer_phone'] = customerPhone;
    if (state != null) newEntry['state'] = state;
    if (runState != null) newEntry['run_state'] = runState;
    _states[machineName] = newEntry;
    _states['sensor.' + machineName] = newEntry;
    _notifier.value++;
  }

  Future<void> pollNow() async {
    await _fetch();
    await _fetchConnectivity();
  }

  Future<void> start() async {
    if (_timer != null) return;
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString('machines_base_url') ?? _baseUrl;
    if (_baseUrl.contains('azima.local')) {
      _baseUrl = _baseUrl.replaceAll('azima.local', '127.0.0.1');
      await prefs.setString('machines_base_url', _baseUrl);
    }

    // Derive dashboard URL from API URL
    // API is on port 5001, dashboard on port 5000
    try {
      final apiUri = Uri.parse(_baseUrl);
      _dashboardUrl = '${apiUri.scheme}://${apiUri.host}:5000';
    } catch (_) {}

    await _fetch();
    _fetchConnectivity(); // Initial connectivity check
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      _fetch();
      _fetchConnectivity();
    });
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> setBaseUrl(String url) async {
    _baseUrl = url;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('machines_base_url', url);

    // Derive dashboard URL
    try {
      final apiUri = Uri.parse(url);
      _dashboardUrl = '${apiUri.scheme}://${apiUri.host}:5000';
    } catch (_) {}

    await _fetch();
    _fetchConnectivity();
  }

  Future<void> _fetch() async {
    try {
      final uri = Uri.parse(_baseUrl);
      final resp = await http.get(uri).timeout(const Duration(seconds: 6));
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final Map<String, dynamic> data =
            json.decode(resp.body) as Map<String, dynamic>;
        _states.clear();
        data.forEach((k, v) {
          _states[k] = v;
          if (k.startsWith('sensor.'))
            _states[k.replaceFirst('sensor.', '')] = v;
        });
        _lastFetchFailed = false;
        _hasFetchedOnce = true;
      } else {
        _lastFetchFailed = true;
      }
    } catch (e, stack) {
      _lastFetchFailed = true;
      debugPrint('[MachineStatusService] _fetch error: $e\n$stack');
    } finally {
      _notifier.value++;
    }
  }

  /// v2: Open/Focus the live WhatsApp Web GUI window on desktop
  Future<Map<String, dynamic>> openWhatsAppWebGUI() async {
    try {
      final cleanBase = _dashboardUrl.endsWith('/') ? _dashboardUrl.substring(0, _dashboardUrl.length - 1) : _dashboardUrl;
      final uri = Uri.parse('$cleanBase/api/wa/open-gui');
      final resp = await http.get(uri).timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final data = json.decode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
        return {'success': true, 'message': data['message'] ?? 'Jendela WhatsApp Web telah dibuka.'};
      } else {
        return {'success': false, 'message': 'Gagal membuka WA: HTTP ${resp.statusCode}'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Gagal menghubungi WhatsApp service: $e'};
    }
  }

  /// v2: Fetch connectivity status from Python server
  Future<void> _fetchConnectivity() async {
    try {
      final uri = Uri.parse('$_dashboardUrl/api/connectivity');
      final resp = await http.get(uri).timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        _internetOk = data['internet'] == true;
        _thinqOk = data['thinq'] == true;
        _bardiOk = data['bardi'] == true;
        _waOk = data['whatsapp'] == true;
        _thinqDeviceCount = data['thinq_devices'] ?? 0;
        _bardiDeviceCount = data['bardi_devices'] ?? 0;
      }
    } catch (e, stack) {
      debugPrint('[MachineStatusService] _fetchConnectivity error: $e\n$stack');
      // If we can't reach the server, everything is down
      _internetOk = false;
      _thinqOk = false;
      _bardiOk = false;
      _waOk = false;
    }
    _notifier.value++;
  }

  /// v2: Start machine monitoring (no relay, monitoring-only)
  /// Returns a map with 'success' bool and optional 'error' string
  Future<Map<String, dynamic>> startMachineMonitoring({
    required String entityId,
    String? customerName,
    String? customerPhone,
    int durationMinutes = 5,
    String source = 'customer',
    bool bypassCooldown = false,
  }) async {
    // Optimistic Update!
    updateMachineStatusOptimistic(
      entityId,
      status: 'unready',
      customerName: customerName ?? 'Pelanggan',
      customerPhone: customerPhone,
      state: 'Ready',
      runState: 'Idle',
    );
    try {
      final uri = Uri.parse('$_dashboardUrl/api/machine/start');
      final resp = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'entity_id': entityId,
              'customer_name': customerName,
              'customer_phone': customerPhone,
              'duration': durationMinutes,
              'source': source,
              'bypass_cooldown': bypassCooldown,
            }),
          )
          .timeout(const Duration(seconds: 10));

      final data = json.decode(resp.body) as Map<String, dynamic>;

      if (resp.statusCode == 200) {
        return {'success': true, 'message': data['message']};
      } else if (resp.statusCode == 423) {
        // Revert status on cooldown
        updateMachineStatusOptimistic(
          entityId,
          status: 'ready',
          customerName: '',
          customerPhone: '',
          state: 'Ready',
          runState: 'Idle',
        );
        return {
          'success': false,
          'error': 'Machine in cooldown',
          'bypass_available': true,
        };
      } else {
        return {'success': false, 'error': data['error'] ?? 'Unknown error'};
      }
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// v2: Stop machine monitoring
  Future<Map<String, dynamic>> stopMachineMonitoring({
    required String entityId,
    String source = 'admin',
  }) async {
    // Optimistic Update!
    updateMachineStatusOptimistic(
      entityId,
      status: 'ready',
      customerName: '',
      customerPhone: '',
      state: 'Ready',
      runState: 'Idle',
    );
    try {
      final uri = Uri.parse('$_dashboardUrl/api/machine/stop');
      final resp = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'entity_id': entityId, 'source': source}),
          )
          .timeout(const Duration(seconds: 10));

      final data = json.decode(resp.body) as Map<String, dynamic>;

      if (resp.statusCode == 200) {
        return {'success': true, 'message': data['message']};
      } else {
        return {'success': false, 'error': data['error'] ?? 'Unknown error'};
      }
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// v2: Get WhatsApp service status
  Future<Map<String, dynamic>> getWaStatus() async {
    try {
      final uri = Uri.parse('$_dashboardUrl/api/wa/status');
      final resp = await http.get(uri).timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        return json.decode(resp.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return {'connected': false, 'error': 'Cannot reach WA service'};
  }

  /// v2: Send manual WhatsApp message
  Future<Map<String, dynamic>> sendWaMessage({
    required String phone,
    required String message,
  }) async {
    try {
      final uri = Uri.parse('$_dashboardUrl/api/wa/send');
      final resp = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'phone': phone, 'message': message}),
          )
          .timeout(const Duration(seconds: 15));

      return json.decode(resp.body) as Map<String, dynamic>;
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Manually finish monitoring (Selesaikan)
  Future<Map<String, dynamic>> finishAndNotify({
    required String entityId,
    required bool sendWa,
    String? waMessage,
    String? customerPhone,
  }) async {
    // Optimistic Update!
    updateMachineStatusOptimistic(
      entityId,
      status: 'ready',
      customerName: '',
      customerPhone: '',
      state: 'Ready',
      runState: 'Idle',
    );
    try {
      final uri = Uri.parse('$_dashboardUrl/api/machine/finish');
      final resp = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'entity_id': entityId,
              'send_wa': sendWa,
              'wa_message': waMessage,
              'customer_phone': customerPhone,
            }),
          )
          .timeout(const Duration(seconds: 10));

      final data = json.decode(resp.body) as Map<String, dynamic>;
      if (resp.statusCode == 200) {
        return {'success': true, 'message': data['message']};
      } else {
        return {'success': false, 'error': data['error'] ?? 'Unknown error'};
      }
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Replace customer on occupied machine
  Future<Map<String, dynamic>> replaceCustomer({
    required String entityId,
    required String newCustomerName,
    String? newCustomerPhone,
    required bool sendWaToPrevious,
    String? waMessage,
    String? previousCustomerPhone,
  }) async {
    // Optimistic Update!
    updateMachineStatusOptimistic(
      entityId,
      status: 'unready',
      customerName: newCustomerName,
      customerPhone: newCustomerPhone,
      state: 'Ready',
      runState: 'Idle',
    );
    try {
      final uri = Uri.parse('$_dashboardUrl/api/machine/replace');
      final resp = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'entity_id': entityId,
              'new_customer_name': newCustomerName,
              'new_customer_phone': newCustomerPhone,
              'previous_customer_phone': previousCustomerPhone,
              'send_wa_to_previous': sendWaToPrevious,
              'wa_message': waMessage,
            }),
          )
          .timeout(const Duration(seconds: 10));

      final data = json.decode(resp.body) as Map<String, dynamic>;
      if (resp.statusCode == 200) {
        return {'success': true, 'message': data['message']};
      } else {
        return {'success': false, 'error': data['error'] ?? 'Unknown error'};
      }
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Send a custom WhatsApp message via /api/wa/send-custom
  Future<Map<String, dynamic>> sendCustomWa({
    required String phone,
    required String message,
  }) async {
    try {
      final uri = Uri.parse('$_dashboardUrl/api/wa/send-custom');
      final resp = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'phone': phone, 'message': message}),
          )
          .timeout(const Duration(seconds: 15));

      return json.decode(resp.body) as Map<String, dynamic>;
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Fetch all machines from DB
  Future<List<Map<String, dynamic>>> fetchMachines() async {
    try {
      final uri = Uri.parse('$_dashboardUrl/api/machines');
      final resp = await http.get(uri).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final List<dynamic> data = json.decode(resp.body);
        return List<Map<String, dynamic>>.from(data);
      }
      return [];
    } catch (e) {
      print('Error fetching machines list: $e');
      return [];
    }
  }

  /// Save or update a machine in DB
  Future<bool> saveMachine(String name, String url, String key) async {
    try {
      final uri = Uri.parse('$_dashboardUrl/api/machines');
      final resp = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'name': name,
              'url': url,
              'key': key,
            }),
          )
          .timeout(const Duration(seconds: 10));
      return resp.statusCode == 200;
    } catch (e) {
      print('Error saving machine: $e');
      return false;
    }
  }

  /// Delete a machine from DB
  Future<bool> deleteMachine(int id) async {
    try {
      final uri = Uri.parse('$_dashboardUrl/api/machines/$id');
      final resp = await http.delete(uri).timeout(const Duration(seconds: 10));
      return resp.statusCode == 200;
    } catch (e) {
      print('Error deleting machine: $e');
      return false;
    }
  }

  /// Discover ThinQ devices on-demand
  Future<List<Map<String, dynamic>>> discoverThinqDevices() async {
    try {
      final uri = Uri.parse('$_dashboardUrl/api/thinq/discover');
      final resp = await http.get(uri).timeout(const Duration(seconds: 25));
      if (resp.statusCode == 200) {
        final List<dynamic> data = json.decode(resp.body);
        return List<Map<String, dynamic>>.from(data);
      }
      return [];
    } catch (e) {
      print('Error scanning ThinQ devices: $e');
      return [];
    }
  }

  // ==========================================
  // BACKEND-CENTRIC AUTH & SECURITY SERVICES
  // ==========================================

  /// Login via backend API with PBKDF2 verification
  Future<Map<String, dynamic>> loginBackend({
    required String username,
    required String password,
  }) async {
    try {
      final uri = Uri.parse('$_dashboardUrl/api/auth/login');
      final resp = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'username': username, 'password': password}),
          )
          .timeout(const Duration(seconds: 8));

      final data = json.decode(resp.body) as Map<String, dynamic>;
      return data;
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Check if admin exists in database via backend
  Future<bool> checkAdminExistsBackend() async {
    try {
      final uri = Uri.parse('$_dashboardUrl/api/auth/check-admin-exists');
      final resp = await http.get(uri).timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        return data['admin_exists'] == true;
      }
    } catch (e) {
      print('Error checking admin exists backend: $e');
    }
    return false;
  }

  /// Create initial admin via backend
  Future<Map<String, dynamic>> createInitialAdminBackend({
    required String username,
    required String password,
  }) async {
    try {
      final uri = Uri.parse('$_dashboardUrl/api/auth/create-initial-admin');
      final resp = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'username': username, 'password': password}),
          )
          .timeout(const Duration(seconds: 8));

      return json.decode(resp.body) as Map<String, dynamic>;
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Verify admin password via backend
  Future<bool> verifyAdminPasswordBackend(String password) async {
    try {
      final uri = Uri.parse('$_dashboardUrl/api/auth/verify-admin');
      final resp = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'password': password}),
          )
          .timeout(const Duration(seconds: 6));

      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        return data['valid'] == true;
      }
    } catch (e) {
      print('Error verifying admin password backend: $e');
    }
    return false;
  }

  /// Change user password via backend
  Future<Map<String, dynamic>> changePasswordBackend({
    required int userId,
    required String oldPassword,
    required String newPassword,
    bool isAdminOverride = false,
  }) async {
    try {
      final uri = Uri.parse('$_dashboardUrl/api/auth/change-password');
      final resp = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'user_id': userId,
              'old_password': oldPassword,
              'new_password': newPassword,
              'is_admin_override': isAdminOverride,
            }),
          )
          .timeout(const Duration(seconds: 8));

      return json.decode(resp.body) as Map<String, dynamic>;
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // ==========================================
  // BACKEND-CENTRIC ORDERS & PRICING SERVICES
  // ==========================================

  /// Calculate verified order totals on backend
  Future<Map<String, dynamic>?> calculateOrderTotalsBackend({
    required List<Map<String, dynamic>> items,
  }) async {
    try {
      final uri = Uri.parse('$_dashboardUrl/api/orders/calculate');
      final resp = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'items': items}),
          )
          .timeout(const Duration(seconds: 6));

      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        return data['calculation'] as Map<String, dynamic>?;
      }
    } catch (e) {
      print('Error calculating order totals on backend: $e');
    }
    return null;
  }

  /// Atomically create order on backend
  Future<Map<String, dynamic>> createOrderBackend({
    required String customerName,
    String? customerPhone,
    required List<Map<String, dynamic>> items,
    required int userId,
    required String paymentMethod,
    int? paidAmount,
    bool? isPaid,
    int? assignedMachineId,
  }) async {
    try {
      final uri = Uri.parse('$_dashboardUrl/api/orders/create');
      final resp = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'customer_name': customerName,
              'customer_phone': customerPhone ?? '',
              'items': items,
              'user_id': userId,
              'payment_method': paymentMethod,
              'paid_amount': paidAmount,
              'is_paid': isPaid,
              'assigned_machine_id': assignedMachineId,
            }),
          )
          .timeout(const Duration(seconds: 10));

      return json.decode(resp.body) as Map<String, dynamic>;
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Update order payment on backend
  Future<Map<String, dynamic>> updateOrderPaymentBackend({
    required int orderId,
    required int paidAmount,
    required String paymentMethod,
    bool? isPaid,
  }) async {
    try {
      final uri = Uri.parse('$_dashboardUrl/api/orders/$orderId/payment');
      final resp = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'paid_amount': paidAmount,
              'payment_method': paymentMethod,
              'is_paid': isPaid,
            }),
          )
          .timeout(const Duration(seconds: 8));

      return json.decode(resp.body) as Map<String, dynamic>;
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // ==========================================
  // BACKEND-CENTRIC FINANCE & LEDGER SERVICES
  // ==========================================

  /// Record expense via backend
  Future<Map<String, dynamic>> createExpenseBackend({
    required String name,
    required int amount,
    String? date,
  }) async {
    try {
      final uri = Uri.parse('$_dashboardUrl/api/expenses/create');
      final resp = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'name': name,
              'amount': amount,
              'date': date,
            }),
          )
          .timeout(const Duration(seconds: 8));

      return json.decode(resp.body) as Map<String, dynamic>;
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Get verified financial ledger summary from backend
  Future<Map<String, dynamic>?> getLedgerSummaryBackend({
    String? startDate,
    String? endDate,
    String? date,
  }) async {
    try {
      String query = '';
      if (startDate != null && endDate != null) {
        query = '?start_date=$startDate&end_date=$endDate';
      } else if (date != null) {
        query = '?date=$date';
      }
      final uri = Uri.parse('$_dashboardUrl/api/ledger/summary$query');
      final resp = await http.get(uri).timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        return data['summary'] as Map<String, dynamic>?;
      }
    } catch (e) {
      print('Error getting ledger summary from backend: $e');
    }
    return null;
  }
}
