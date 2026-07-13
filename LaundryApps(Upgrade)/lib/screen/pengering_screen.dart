import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
// Pastikan import di bawah ini sesuai dengan struktur folder Anda
import '../../transactions/order_repository.dart';
import '../../database/models/order_model.dart';
import '../database/models/database_helper.dart';
import '../../database/models/machine_model.dart';

class PengeringScreen extends StatelessWidget {
  final int items;
  final String title;

  const PengeringScreen({Key? key, this.items = 5, this.title = 'Status Mesin Pengering'}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Background sedikit off-white agar card lebih pop-up
      backgroundColor: const Color(0xFFF5F7FA),
      body: PengeringContent(items: items, title: title),
    );
  }
}

class PengeringContent extends StatefulWidget {
  final int items;
  final String title;

  const PengeringContent({Key? key, this.items = 5, this.title = 'Status Mesin Pengering'}) : super(key: key);

  @override
  State<PengeringContent> createState() => _PengeringContentState();
}

class _PengeringContentState extends State<PengeringContent> {
  final OrderRepository _orderRepo = OrderRepository();
  final DatabaseHelper _db = DatabaseHelper.instance;
  List<Order> _activeOrders = [];
  List<MachineModel> _machines = [];
  bool _isLoading = true;

  // Palet Warna Friendly
  final Color primaryColor = const Color(0xFF4E80EE); // Biru yang lebih cerah
  final Color secondaryColor = const Color(0xFF7CA0F3);
  final Color accentColor = const Color(0xFFFF9F43); // Oranye soft untuk highlight

  @override
  void initState() {
    super.initState();
    _loadActiveOrders();
    _loadMachines();
  }

  Future<void> _loadMachines() async {
    try {
      final items = await _db.getAllMachines(type: 'pengering');
      setState(() => _machines = items);
    } catch (e) {
      setState(() => _machines = []);
    }
  }

  Future<void> _loadActiveOrders() async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('user_id');
      final orders = await _orderRepo.getAllOrders(userId: userId);
      
      final List<Order> washingOrders = orders.where((order) {
        final items = order.items;
        final hasIroningOnly = items.every((item) => (item.note ?? '').toLowerCase().contains('kg'));
        if (hasIroningOnly) return false;
        // Check itemId == 2 (Dryer / Pengering Machine)
        // Exclude already completed orders from active list
        return items.any((item) => item.itemId == 2) && order.status.toLowerCase() != 'completed';
      }).toList();

      washingOrders.sort((a, b) {
        DateTime da = _parseOrderDate(a.orderDate);
        DateTime db = _parseOrderDate(b.orderDate);
        // Sort ascending so the oldest order is at the top
        return da.compareTo(db);
      });
      
      setState(() {
        _activeOrders = washingOrders;
      });
    } catch (e) {
      setState(() => _activeOrders = []);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _openMachinePicker(Order order) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.only(top: 12, bottom: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag Handle
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: primaryColor.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.local_laundry_service, color: primaryColor),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Pilih Mesin', style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                          Text(order.customerName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 30),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: _machines.isNotEmpty
                      ? _machines.map((m) => _buildMachineTile(m.name, () => _confirmAndAssign(order, m.id ?? 0, m.name))).toList()
                      : List.generate(widget.items, (index) {
                          return _buildMachineTile('Mesin 0${index + 1}', () => _confirmAndAssign(order, index + 1, 'Mesin 0${index + 1}'));
                        }),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMachineTile(String name, VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        leading: Icon(Icons.power_settings_new, color: Colors.grey[400]),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
        trailing: Icon(Icons.chevron_right, color: primaryColor),
        onTap: onTap,
      ),
    );
  }

  Future<void> _confirmAndAssign(Order order, int machineId, String machineName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Konfirmasi'),
         
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Batal', style: TextStyle(color: Colors.grey[600])),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Jalankan', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (!mounted) return; // Check mounted before using context
      Navigator.of(context).pop(); // Close bottom sheet
      _assignMachine(order, machineId);
    }
  }

  void _assignMachine(Order order, int machineNumber) {
    final machine = _machines.firstWhere(
      (m) => (m.id ?? 0) == machineNumber,
      orElse: () => MachineModel(id: null, name: '', url: '', key: '', createdAt: DateTime.now()),
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Menghubungkan ke Mesin $machineNumber...'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );

    if ((machine.id ?? 0) != 0 && (machine.url).isNotEmpty) {
      final endpoint = (machine.key).isNotEmpty ? '${machine.url}/${machine.key}' : machine.url;
      _callMachineEndpoint(endpoint, order, machineNumber, machine);
    }
  }

  Future<void> _callMachineEndpoint(String endpoint, Order order, int machineNumber, MachineModel machine) async {
    try {
      final uri = Uri.parse(endpoint);
      final resp = await http.get(uri).timeout(const Duration(seconds: 8));
      if (!mounted) return;
      
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        _showSuccessSnackBar('Mesin $machineNumber berhasil dinyalakan!');
        if (order.id != null && (machine.id ?? 0) != 0) {
          await _db.assignMachineToOrder(order.id!, machine.id!, DateTime.now());
          await _orderRepo.updateOrderStatus(order.id!, 'Completed');
          await _loadActiveOrders();
        }
      } else {
        _showErrorSnackBar('Gagal: Respon ${resp.statusCode}');
      }
    } catch (e) {
      if (!mounted) return;
      _showErrorSnackBar('Error koneksi mesin');
    }
  }

  void _showSuccessSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.green));
  }
  
  void _showErrorSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  DateTime _parseOrderDate(dynamic val) {
    if (val == null) return DateTime.fromMillisecondsSinceEpoch(0);
    if (val is DateTime) return val;
    if (val is String) {
      try { return DateTime.parse(val); } catch (_) { return DateTime.fromMillisecondsSinceEpoch(0); }
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month} • ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Modern Header with Bubbles
        _buildModernHeader(context),
        
        // List Content
        Expanded(
          child: _isLoading
              ? Center(child: CircularProgressIndicator(color: primaryColor))
              : _activeOrders.isEmpty
                  ? _buildEmptyState()
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 100),
                      itemCount: _activeOrders.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 16),
                      itemBuilder: (context, idx) {
                        return _buildOrderCard(_activeOrders[idx]);
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildModernHeader(BuildContext context) {
    return Stack(
      children: [
        Container(
          padding: const EdgeInsets.only(top: 60, left: 24, right: 24, bottom: 40),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [primaryColor, secondaryColor],
            ),
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(32),
              bottomRight: Radius.circular(32),
            ),
            boxShadow: [
              BoxShadow(color: primaryColor.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.title, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                        const SizedBox(height: 4),
                        Text('Pantau antrian & mesin', style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 14)),
                      ],
                    ),
                  ),
                  _buildHeaderIconButton(Icons.settings, () => Navigator.pushNamed(context, '/settings')),
                ],
              ),
            ],
          ),
        ),
        // Decorative Bubbles (Visual Interest)
        Positioned(top: -20, right: -20, child: _bubbleDecoration(100)),
        Positioned(top: 80, left: 20, child: _bubbleDecoration(40)),
        Positioned(top: 40, right: 80, child: _bubbleDecoration(20)),
      ],
    );
  }

  Widget _bubbleDecoration(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withOpacity(0.1),
      ),
    );
  }

  Widget _buildHeaderIconButton(IconData icon, VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.only(left: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: IconButton(
        icon: Icon(icon, color: Colors.white, size: 22),
        onPressed: onTap,
        splashRadius: 24,
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 20)],
            ),
            child: Icon(Icons.local_laundry_service_outlined, size: 60, color: Colors.grey[300]),
          ),
          const SizedBox(height: 20),
          Text('Mesin sedang istirahat', style: TextStyle(color: Colors.grey[800], fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('Belum ada antrian pengering saat ini.', style: TextStyle(color: Colors.grey[500], fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildOrderCard(Order order) {
    final date = _parseOrderDate(order.orderDate);
    final isNew = DateTime.now().difference(date).inHours < 2;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.08),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _openMachinePicker(order),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    // Avatar Initials
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: isNew ? primaryColor.withOpacity(0.1) : Colors.grey[100],
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Center(
                        child: Text(
                          order.customerName.isNotEmpty ? order.customerName[0].toUpperCase() : '?',
                          style: TextStyle(
                            color: isNew ? primaryColor : Colors.grey[600],
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            order.customerName,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.scale, size: 14, color: Colors.grey[500]),
                              const SizedBox(width: 4),
                              Text('${order.items.length} Item', style: TextStyle(color: Colors.grey[500], fontSize: 13)),
                              const SizedBox(width: 12),
                              Icon(Icons.access_time, size: 14, color: Colors.grey[500]),
                              const SizedBox(width: 4),
                              Text(_formatDateTime(date), style: TextStyle(color: Colors.grey[500], fontSize: 13)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Action Bar
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        order.status.toUpperCase(),
                        style: const TextStyle(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                    Row(
                      children: [
                        Text('Pilih Mesin', style: TextStyle(color: primaryColor, fontWeight: FontWeight.w600)),
                        const SizedBox(width: 4),
                        Icon(Icons.arrow_forward_rounded, size: 16, color: primaryColor),
                      ],
                    )
                  ],
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}