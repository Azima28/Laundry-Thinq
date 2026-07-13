import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../database/models/order_model.dart';
import '../../transactions/order_repository.dart';
import '../database/models/database_helper.dart';
import '../../database/models/machine_model.dart';
import 'package:intl/intl.dart'; // Tambahkan untuk format mata uang

class HistoryMesinCuciPage extends StatefulWidget {
  const HistoryMesinCuciPage({Key? key}) : super(key: key);

  @override
  _HistoryMesinCuciPageState createState() => _HistoryMesinCuciPageState();
}

class _HistoryMesinCuciPageState extends State<HistoryMesinCuciPage> with WidgetsBindingObserver {
  // Palet Warna dan Konstanta
  final Color _primaryColor = const Color(0xFF4E80EE);
  final Color _backgroundColor = const Color(0xFFF5F7FA);

  final OrderRepository _repository = OrderRepository();
  final DatabaseHelper _db = DatabaseHelper.instance;
  List<Order> _orders = [];
  List<Order> _filtered = [];
  List<MachineModel> _machines = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();
  // Date filter & statistics
  DateTime? _startDate;
  DateTime? _endDate;
  bool _showOnlyToday = true;

  int _totalRevenue = 0;
  Map<String, int> _itemQuantities = {};
  Map<String, int> _itemRevenues = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadData();
    _searchController.addListener(_applySearch);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Reload data when app comes back to foreground
    if (state == AppLifecycleState.resumed) {
      _loadData();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('user_id');
      print('=== DEBUG HISTORY LOAD START ===');
      print('User ID: $userId');
      
      // Query directly to check database content
      final db = await _db.database;
      final allOrdersFromDb = await db.query('orders');
      print('DEBUG: Total orders in DB: ${allOrdersFromDb.length}');
      for (var row in allOrdersFromDb) {
        print('  - Order ${row['id']}: status=${row['status']}, assigned_machine_id=${row['assigned_machine_id']}, machine_started_at=${row['machine_started_at']}, user_id=${row['user_id']}');
      }
      
      // Ambil ALL orders untuk user ini
      final allOrders = await _repository.getAllOrders(userId: userId);
      print('DEBUG: Orders from repo for userId=$userId (${allOrders.length}):');
      for (var o in allOrders) {
        print('  - Order ${o.id}: status=${o.status}, assigned=${o.assignedMachineId}, started=${o.machineStartedAt}, userId=${o.userId}');
      }

      // FILTER: Hanya ambil yang sudah ditugaskan ke mesin (assignedMachineId != null)
      final machineOrders = allOrders.where((o) => o.assignedMachineId != null).toList();
      print('DEBUG: After filter assignedMachineId != null (${machineOrders.length}):');
      for (var o in machineOrders) {
        print('  - Order ${o.id}: status=${o.status}');
      }

      // Apply date filter
      List<Order> dateFiltered = machineOrders;
      if (_showOnlyToday) {
        final now = DateTime.now();
        print('DEBUG: Filtering for today: ${now.year}-${now.month}-${now.day}');
        dateFiltered = machineOrders.where((order) {
          final checkDate = order.machineStartedAt ?? order.orderDate;
          final isSameDay = checkDate.year == now.year && checkDate.month == now.month && checkDate.day == now.day;
          print('  - Order ${order.id}: checkDate=${checkDate.toIso8601String()}, isSameDay=$isSameDay');
          return isSameDay;
        }).toList();
      } else if (_startDate != null && _endDate != null) {
        final start = DateTime(_startDate!.year, _startDate!.month, _startDate!.day);
        final end = DateTime(_endDate!.year, _endDate!.month, _endDate!.day, 23, 59, 59, 999);
        dateFiltered = machineOrders.where((order) {
          final checkDate = order.machineStartedAt ?? order.orderDate;
          return (checkDate.isAtSameMomentAs(start) || checkDate.isAfter(start)) &&
                 (checkDate.isAtSameMomentAs(end) || checkDate.isBefore(end));
        }).toList();
      }

      // Sort: terbaru pertama
      dateFiltered.sort((a, b) {
        final da = a.machineStartedAt ?? a.orderDate;
        final db = b.machineStartedAt ?? b.orderDate;
        return db.compareTo(da);
      });

      print('DEBUG: Final result (${dateFiltered.length}):');
      for (var o in dateFiltered) {
        print('  - Order ${o.id}: ${o.customerName}, status=${o.status}');
      }
      print('=== DEBUG HISTORY LOAD END ===');

      final machines = await _db.getAllMachines(type: 'cuci');

      setState(() {
        _machines = machines;
        _orders = dateFiltered;
        _filtered = dateFiltered;
        _isLoading = false;
      });
      _calculateStatistics();
    } catch (e, st) {
      print('ERROR in _loadData: $e\n$st');
      setState(() => _isLoading = false);
    }
  }

  void _applySearch() {
    final q = _searchController.text.toLowerCase();
    print('DEBUG SEARCH: Query="$q", _orders.length=${_orders.length}');
    setState(() {
      if (q.isEmpty) {
        _filtered = _orders;
      } else {
        _filtered = _orders.where((o) {
          return o.customerName.toLowerCase().contains(q) ||
              o.items.any((it) => it.itemName.toLowerCase().contains(q));
        }).toList();
      }
    });
    print('DEBUG SEARCH: _filtered.length=${_filtered.length}');
  }

  void _calculateStatistics() {
    _totalRevenue = 0;
    _itemQuantities.clear();
    _itemRevenues.clear();

    for (var order in _orders) {
      _totalRevenue += order.totalAmount;
      for (var item in order.items) {
        _itemQuantities[item.itemName] = (_itemQuantities[item.itemName] ?? 0) + item.quantity;
        _itemRevenues[item.itemName] = (_itemRevenues[item.itemName] ?? 0) + (item.price * item.quantity);
      }
    }
  }

  Future<void> _selectDateRange(BuildContext context) async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : DateTimeRange(start: DateTime.now(), end: DateTime.now()),
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
        _showOnlyToday = false;
      });
      await _loadData();
    }
  }

  void _toggleTodayFilter() {
    setState(() {
      _showOnlyToday = !_showOnlyToday;
      if (_showOnlyToday) {
        _startDate = null;
        _endDate = null;
      }
    });
    _loadData();
  }

  void _showStatistics() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Statistik Pesanan'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Total Pendapatan: Rp$_totalRevenue', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.green)),
              const SizedBox(height: 12),
              Text('Statistik per Item:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...(_itemQuantities.keys.toList()..sort()).map((itemName) {
                final quantity = _itemQuantities[itemName] ?? 0;
                final revenue = _itemRevenues[itemName] ?? 0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(itemName, style: TextStyle(fontWeight: FontWeight.w500)),
                      Padding(
                        padding: const EdgeInsets.only(left: 16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [Text('Jumlah: $quantity'), Text('Pendapatan: Rp$revenue')],
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: Text('Tutup'))],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return DateFormat('dd MMM yyyy, HH:mm').format(dt);
  }

  String _formatCurrency(double amount) {
    final format = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0);
    return format.format(amount).replaceAll(',', '.');
  }

  MachineModel? _findMachine(int? id) {
    if (id == null) return null;
    return _machines.firstWhere(
      (m) => m.id == id,
      orElse: () => MachineModel(id: null, name: 'Mesin Tak Dikenal', url: '', key: '', createdAt: DateTime.now()),
    );
  }

  void _showDetails(Order order) {
    final machine = _findMachine(order.assignedMachineId);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Detail Log Cuci', style: TextStyle(fontWeight: FontWeight.bold, color: _primaryColor)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow(label: 'Nama Pelanggan', value: order.customerName, isBold: true),
              _buildDetailRow(label: 'Tanggal Pesanan', value: _formatDate(order.orderDate)),
              const Divider(height: 20),
              _buildDetailRow(label: 'Mesin Digunakan', value: machine?.name ?? '-'),
              _buildDetailRow(
                  label: 'Waktu Mulai Cuci',
                  value: order.machineStartedAt != null ? _formatDate(order.machineStartedAt!) : '-'),
              _buildDetailRow(label: 'Status Pesanan', value: order.status, color: order.status == 'Selesai' ? Colors.green : Colors.orange),
              _buildDetailRow(label: 'Total Biaya', value: _formatCurrency(order.totalAmount.toDouble()), color: Colors.green, isBold: true),
              
              const Divider(height: 20),
              Text('Item Laundry:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
              const SizedBox(height: 8),
              ...order.items.map((it) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: Text('${it.quantity}x ${it.itemName}')),
                    Text(_formatCurrency(it.price * it.quantity.toDouble()), style: TextStyle(fontWeight: FontWeight.w500)),
                  ],
                ),
              )).toList()
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Tutup', style: TextStyle(color: _primaryColor)),
          )
        ],
      ),
    );
  }

  Widget _buildDetailRow({required String label, required String value, Color color = Colors.black87, bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label, style: TextStyle(color: Colors.grey[600])),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
        ),
        iconTheme: IconThemeData(color: _primaryColor),
        title: Text(
          'Log Mesin Cuci',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
        ),
        actions: [
            TextButton.icon(
            icon: Icon(Icons.today, color: _showOnlyToday ? Colors.white : Colors.grey),
            label: Text('Hari Ini', style: TextStyle(color: _showOnlyToday ? Colors.white : Colors.grey)),
            onPressed: _toggleTodayFilter,
            style: TextButton.styleFrom(backgroundColor: _showOnlyToday ? _primaryColor : Colors.black26, padding: EdgeInsets.symmetric(horizontal: 12)),
            ),
          
          IconButton(
            icon: Icon(Icons.date_range, color: _primaryColor),
            onPressed: () => _selectDateRange(context),
          ),
          IconButton(
            icon: Icon(Icons.analytics_outlined, color: _primaryColor),
            onPressed: _showStatistics,
          ),
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: _primaryColor),
            onPressed: _loadData,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                prefixIcon: Icon(Icons.search, color: _primaryColor),
                hintText: 'Cari nama pelanggan atau item laundry...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide(color: _primaryColor, width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
                fillColor: Colors.white,
                filled: true,
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(_primaryColor)))
                : _filtered.isEmpty
                    ? Center(
                        child: Text(
                          'Belum ada riwayat penggunaan mesin cuci.',
                          style: TextStyle(color: Colors.grey[600], fontSize: 16),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.only(left: 16, right: 16, bottom: 20),
                        itemCount: _filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (ctx, idx) {
                          final o = _filtered[idx];
                          final m = _findMachine(o.assignedMachineId);
                          final displayTime = o.machineStartedAt ?? o.orderDate;
                          return _buildHistoryCard(o, m, displayTime);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryCard(Order order, MachineModel? machine, DateTime displayTime) {
    final Color statusColor = order.status == 'Selesai' ? Colors.green : (order.status == 'Proses' ? Colors.orange : Colors.grey);
    
    return InkWell(
      onTap: () => _showDetails(order),
      borderRadius: BorderRadius.circular(15),
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        elevation: 3,
        shadowColor: _primaryColor.withOpacity(0.1),
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Mesin & Waktu
                  Row(
                    children: [
                      Icon(Icons.local_laundry_service_rounded, size: 20, color: _primaryColor),
                      const SizedBox(width: 8),
                      Text(
                        '${machine?.name ?? 'Mesin Tak Dikenal'}',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _primaryColor),
                      ),
                    ],
                  ),
                  
                  // Tanggal/Waktu Mulai
                  Text(
                    _formatDate(displayTime),
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
              
              const Divider(height: 15),
              
              // Detail Pesanan
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          order.customerName,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'ID: #${order.id}',
                          style: TextStyle(color: Colors.grey[500], fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(width: 10),

                  // Total & Status
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _formatCurrency(order.totalAmount.toDouble()),
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green.shade700),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          order.status,
                          style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}