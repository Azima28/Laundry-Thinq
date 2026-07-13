import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:laundry_apps/database/models/order_model.dart';
import 'package:laundry_apps/database/models/machine_model.dart';
import 'package:laundry_apps/transactions/order_repository.dart';
import 'package:laundry_apps/database/models/database_helper.dart';
import 'package:laundry_apps/services/machine_status_service.dart';

class CuciScreen extends StatelessWidget {
  final int items;
  final String title;

  const CuciScreen({
    Key? key,
    this.items = 5,
    this.title = 'Status Mesin Cuci',
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: CuciContent(items: items, title: title),
    );
  }

  int _parseRemainMinutes(String remain) {
    if (remain.isEmpty) return 0;
    try {
      final parts = remain.split(':');
      if (parts.length >= 2) {
        final h = int.tryParse(parts[0]) ?? 0;
        final m = int.tryParse(parts[1]) ?? 0;
        return h * 60 + m;
      }
    } catch (_) {}
    return 0;
  }
}

class CuciContent extends StatefulWidget {
  final int items;
  final String title;

  const CuciContent({
    Key? key,
    this.items = 5,
    this.title = 'Status Mesin Cuci',
  }) : super(key: key);

  @override
  State<CuciContent> createState() => _CuciContentState();
}

class _CuciContentState extends State<CuciContent> with WidgetsBindingObserver {
  final OrderRepository _orderRepo = OrderRepository();
  final DatabaseHelper _db = DatabaseHelper.instance;
  List<Order> _activeOrders = [];
  List<MachineModel> _machines = [];
  bool _isLoading = true;

  // Palet Warna Friendly
  final Color primaryColor = const Color(0xFF4E80EE);
  final Color secondaryColor = const Color(0xFF7CA0F3);
  final Color accentColor = const Color(0xFFFF9F43);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadActiveOrders();
    _loadMachines();
    MachineStatusService.instance.updates.addListener(_onServiceUpdate);
  }

  @override
  void dispose() {
    MachineStatusService.instance.updates.removeListener(_onServiceUpdate);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onServiceUpdate() {
    if (!mounted) return;
    // Refresh active orders when machine status updates so UI reflects started machines
    if (!_isLoading) {
      _loadActiveOrders();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed && mounted) {
      // App returned to foreground; refresh orders to pick up any background DB changes
      _loadActiveOrders();
    }
  }

  Future<void> _loadMachines() async {
    try {
      final items = await _db.getAllMachines(type: 'cuci');
      final ordered = await _applySavedOrder(items);
      if (mounted) {
        setState(() => _machines = ordered);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _machines = []);
      }
    }
  }

  Future<List<MachineModel>> _applySavedOrder(List<MachineModel> items) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final order = prefs.getStringList('machines_order_cuci') ?? [];
      if (order.isEmpty) return items;
      final Map<String, MachineModel> map = {for (var m in items) m.name: m};
      final List<MachineModel> ordered = [];
      for (var name in order) {
        if (map.containsKey(name)) ordered.add(map[name]!);
      }
      for (var m in items) {
        if (!ordered.any((om) => om.name == m.name)) ordered.add(m);
      }
      return ordered;
    } catch (_) {
      return items;
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
        return items.any((item) => item.itemId == 1) &&
            order.status.toLowerCase() != 'completed';
      }).toList();

      washingOrders.sort((a, b) {
        DateTime da = _parseOrderDate(a.orderDate);
        DateTime db = _parseOrderDate(b.orderDate);
        return da.compareTo(db);
      });

      final List<Order> expanded = [];
      final db = await _db.database; // database instance for usage queries
      for (final order in washingOrders) {
        final washingItems = order.items.where((it) => it.itemId == 1).toList();

        if (washingItems.isEmpty) {
          expanded.add(order);
        } else {
          // total qty for washing items in the order
          final totalQty = washingItems.fold<int>(0, (s, it) => s + it.quantity);
          // count how many units have already been recorded in machine_usage_history
          final usageResult = await db.rawQuery(
            'SELECT COUNT(*) as cnt FROM machine_usage_history WHERE order_id = ?',
            [order.id],
          );
          final usedQty = usageResult.isNotEmpty ? (usageResult[0]['cnt'] as int) : 0;
          final remainingQty = (totalQty - usedQty).clamp(0, 999999);

          for (int i = 0; i < remainingQty; i++) {
            expanded.add(order);
          }
        }
      }

      if (mounted) {
        setState(() {
          _activeOrders = expanded;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _activeOrders = []);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
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
                          Text(
                            'Pilih Mesin',
                            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                          ),
                          Text(
                            order.customerName,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 30),
              Flexible(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _buildMachineGrid(order),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMachineGrid(Order order) {
    final List<MachineModel> displayMachines = _machines.isNotEmpty
        ? _machines
        : List.generate(
            widget.items,
            (index) => MachineModel(
              id: index + 1,
              name: 'Mesin 0${index + 1}',
              url: '',
              key: '',
              createdAt: DateTime.now(),
            ),
          );

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 1.0,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: displayMachines.length,
      itemBuilder: (context, index) {
        final machine = displayMachines[index];
        final displayName = machine.key.isNotEmpty ? machine.key : machine.name;
        return _buildMachineBoxFromModel(
          machine,
          displayName,
          () => _confirmAndAssign(order, machine.id ?? 0, displayName),
        );
      },
    );
  }

  Widget _buildMachineBoxFromModel(
    MachineModel machine,
    String displayName,
    VoidCallback onTap,
  ) {
    final service = MachineStatusService.instance;
    final states = service.states;
    final dynamic entry = states[machine.name] ??
        states['sensor.${machine.name}'] ??
        states[displayName] ??
        states['sensor.$displayName'];

    String state;
    if (entry != null && entry['state'] != null) {
      state = entry['state'].toString();
    } else {
      if (!service.hasFetchedOnce) {
        state = 'error';
      } else if (service.lastFetchFailed) {
        state = 'error';
      } else {
        state = 'off';
      }
    }

    final String remain = (entry != null && entry['remain_time'] != null)
        ? entry['remain_time'].toString()
        : '';
    final int minutes = _parseRemainMinutes(remain);
    final bool isOn = state.toLowerCase() == 'on';

    final Color bg = state == 'error'
        ? Colors.orange.withOpacity(0.12)
        : (isOn ? Colors.green.withOpacity(0.12) : Colors.red.withOpacity(0.10));
    final Color border = state == 'error'
        ? Colors.orange.withOpacity(0.4)
        : (isOn ? Colors.green.withOpacity(0.4) : Colors.red.withOpacity(0.4));
    final Color iconColor =
        state == 'error' ? Colors.orange : (isOn ? Colors.green : Colors.red);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border, width: 1.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.local_laundry_service, size: 36, color: iconColor),
            const SizedBox(height: 8),
            Text(
              displayName,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              state == 'error'
                  ? 'err'
                  : minutes > 0
                      ? '${minutes}m'
                      : (state.toLowerCase() == 'on' ? '-' : 'off'),
              style: const TextStyle(
                fontSize: 12,
                color: Colors.black54,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  int _parseRemainMinutes(String remain) {
    if (remain.isEmpty) return 0;
    try {
      final parts = remain.split(':');
      if (parts.length >= 2) {
        final h = int.tryParse(parts[0]) ?? 0;
        final m = int.tryParse(parts[1]) ?? 0;
        return h * 60 + m;
      }
    } catch (_) {}
    return 0;
  }

  Future<void> _confirmAndAssign(
    Order order,
    int machineId,
    String machineName,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Konfirmasi'),
        content: Text(
          'Jalankan $machineName untuk pesanan ${order.customerName}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Batal', style: TextStyle(color: Colors.grey[600])),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Jalankan',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (!mounted) return;
      Navigator.of(context).pop();
      _assignMachine(order, machineId);
    }
  }

  void _assignMachine(Order order, int machineNumber) {
    final machine = _machines.firstWhere(
      (m) => (m.id ?? 0) == machineNumber,
      orElse: () => MachineModel(
        id: machineNumber,
        name: 'Mesin $machineNumber',
        url: '',
        key: '',
        createdAt: DateTime.now(),
      ),
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Menghubungkan ke Mesin ${machine.name}...'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );

    if ((machine.id ?? 0) != 0 && machine.url.isNotEmpty) {
      final endpoint = machine.key.isNotEmpty
          ? '${machine.url}/${machine.key}'
          : machine.url;
      _callMachineEndpoint(endpoint, order, machine.id!, machine);
    } else {
      _showSuccessSnackBar(
        'Mesin ${machine.name} berhasil diasosiasikan (Simulasi)!',
      );
      _persistAssignment(order, machine.id!);
    }
  }

  Future<void> _persistAssignment(Order order, int machineId) async {
    try {
      if (order.id != null && machineId != 0) {
        final now = DateTime.now();

        // Determine total washing qty for this order
        final washingItems = order.items.where((it) => it.itemId == 1).toList();
        final totalQty = washingItems.fold<int>(0, (s, it) => s + it.quantity);

        // Count used qty from history
        final db = await _db.database;
        final usageResult = await db.rawQuery(
          'SELECT COUNT(*) as cnt FROM machine_usage_history WHERE order_id = ?',
          [order.id],
        );
        final usedQty = usageResult.isNotEmpty ? (usageResult[0]['cnt'] as int) : 0;

        // Record a machine usage entry (do not change original order_items)
        final machine = await _db.getMachine(machineId);
        final machineName = machine?.name ?? 'Mesin $machineId';
        await _db.recordMachineUsage(
          orderId: order.id!,
          machineId: machineId,
          machineName: machineName,
          customerName: order.customerName,
          startedAt: now,
        );

        // If this was the last unit, update order assignment/status
        final remainingAfter = (totalQty - usedQty - 1).clamp(0, 999999);
        if (remainingAfter == 0) {
          await _db.updateOrderMachineAssignment(order.id!, machineId, now);
        }

        await _loadActiveOrders();
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('Gagal menyimpan status ke database');
      }
    }
  }

  Future<void> _callMachineEndpoint(
    String endpoint,
    Order order,
    int machineId,
    MachineModel machine,
  ) async {
    try {
      final uri = Uri.parse(endpoint);
      final resp = await http.get(uri).timeout(const Duration(seconds: 8));
      if (!mounted) return;

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        _showSuccessSnackBar('Mesin ${machine.name} berhasil dinyalakan!');
        await _persistAssignment(order, machineId);
      } else {
        _showErrorSnackBar('Gagal menyalakan mesin: Respon ${resp.statusCode}');
      }
    } catch (e) {
      if (!mounted) return;
      _showErrorSnackBar('Error koneksi mesin. Cek URL/Jaringan.');
    }
  }

  void _showSuccessSnackBar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.green),
    );
  }

  void _showErrorSnackBar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  DateTime _parseOrderDate(dynamic val) {
    if (val == null) return DateTime.fromMillisecondsSinceEpoch(0);
    if (val is DateTime) return val;
    if (val is String) {
      try {
        return DateTime.parse(val);
      } catch (_) {
        return DateTime.fromMillisecondsSinceEpoch(0);
      }
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day.toString().padLeft(2, '0')}/${dateTime.month.toString().padLeft(2, '0')} • ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildModernHeader(context),
        Expanded(
          child: _isLoading
              ? Center(
                  child: CircularProgressIndicator(color: primaryColor),
                )
              : _activeOrders.isEmpty
                  ? _buildEmptyState()
                  : RefreshIndicator(
                      onRefresh: _loadActiveOrders,
                      color: primaryColor,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 100),
                        itemCount: _activeOrders.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 16),
                        itemBuilder: (context, idx) {
                          return _buildOrderCard(_activeOrders[idx]);
                        },
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildModernHeader(BuildContext context) {
    return Stack(
      children: [
        Container(
          padding: const EdgeInsets.only(
            top: 60,
            left: 24,
            right: 24,
            bottom: 40,
          ),
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
              BoxShadow(
                color: primaryColor.withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
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
                        Text(
                          widget.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Pantau antrian & mesin',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildHeaderIconButton(Icons.refresh, _loadActiveOrders),
                ],
              ),
            ],
          ),
        ),
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
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  blurRadius: 20,
                ),
              ],
            ),
            child: Icon(
              Icons.local_laundry_service_outlined,
              size: 60,
              color: Colors.grey[300],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Mesin sedang istirahat',
            style: TextStyle(
              color: Colors.grey[800],
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Belum ada antrian cuci saat ini.',
            style: TextStyle(color: Colors.grey[500], fontSize: 14),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _loadActiveOrders,
            icon: const Icon(Icons.refresh, color: Colors.white),
            label: const Text(
              'Refresh Data',
              style: TextStyle(color: Colors.white),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          )
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
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: isNew
                            ? primaryColor.withOpacity(0.1)
                            : Colors.grey[100],
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Center(
                        child: Text(
                          order.customerName.isNotEmpty
                              ? order.customerName[0].toUpperCase()
                              : '?',
                          style: TextStyle(
                            color: isNew ? primaryColor : Colors.grey[600],
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            order.customerName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.scale, size: 14, color: Colors.grey[500]),
                              const SizedBox(width: 4),
                              Text(
                                '${order.items.length} Item',
                                style: TextStyle(
                                  color: Colors.grey[500],
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Icon(
                                Icons.access_time,
                                size: 14,
                                color: Colors.grey[500],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _formatDateTime(date),
                                style: TextStyle(
                                  color: Colors.grey[500],
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        order.status.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.orange,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Text(
                          'Pilih Mesin',
                          style: TextStyle(
                            color: primaryColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.arrow_forward_rounded,
                          size: 16,
                          color: primaryColor,
                        ),
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