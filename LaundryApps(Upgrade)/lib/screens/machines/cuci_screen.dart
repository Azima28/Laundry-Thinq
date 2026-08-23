import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import '../../services/machine_status_service.dart';
import '../../transactions/order_repository.dart';
import '../../utils/globals.dart';
import '../../database/models/order_model.dart';
import '../../database/models/database_helper.dart';
import '../../database/models/machine_model.dart';
import '../../services/notification_service.dart';
import '../../utils/style_constants.dart';

class CuciScreen extends StatelessWidget {
  final int items;
  final String title;

  const CuciScreen({Key? key, this.items = 5, this.title = 'Status Mesin Cuci'})
    : super(key: key);

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.canPop(context);
    return Scaffold(
      backgroundColor: StyleConstants.backgroundColor,
      appBar: canPop
          ? AppBar(
              title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              backgroundColor: Colors.white,
              foregroundColor: StyleConstants.textHeading,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: StyleConstants.textHeading),
                tooltip: 'Kembali',
                onPressed: () => Navigator.pop(context),
              ),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(1),
                child: Container(color: StyleConstants.borderLight, height: 1),
              ),
            )
          : null,
      body: CuciContent(items: items, title: title),
    );
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

class _CuciContentState extends State<CuciContent> {
  final OrderRepository _orderRepo = OrderRepository();
  final DatabaseHelper _db = DatabaseHelper.instance;
  List<Map<String, dynamic>> _activeOrders = [];
  List<MachineModel> _machines = [];
  bool _isLoading = true;

  // Selected order for assignment
  Map<String, dynamic>? _selectedOrderItem;

  final Color primaryColor = const Color(0xFF4E80EE);
  final Color secondaryColor = const Color(0xFF7CA0F3);
  final Color backgroundColor = const Color(0xFFF8FAFC);

  @override
  void initState() {
    super.initState();
    _loadActiveOrders();
    _loadMachines();
    MachineStatusService.instance.updates.addListener(_onServiceUpdate);
  }

  @override
  void dispose() {
    MachineStatusService.instance.updates.removeListener(_onServiceUpdate);
    super.dispose();
  }

  void _onServiceUpdate() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _loadMachines() async {
    try {
      final items = await _db.getAllMachines(type: 'cuci');
      final ordered = await _applySavedOrder(items);
      setState(() => _machines = ordered);
    } catch (e) {
      setState(() => _machines = []);
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
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('user_id');
      final orders = await _orderRepo.getAllOrders(userId: userId);

      final List<Order> washingOrders = orders.where((order) {
        final items = order.items;
        return items.any((item) {
              final name = item.itemName.toLowerCase();
              return item.machineType == 'cuci' ||
                  name.contains('cuci') ||
                  name.contains('wash');
            }) &&
            order.status.toLowerCase() != 'completed';
      }).toList();

      washingOrders.sort((a, b) {
        DateTime da = _parseOrderDate(a.orderDate);
        DateTime db = _parseOrderDate(b.orderDate);
        return da.compareTo(db);
      });

      final List<Map<String, dynamic>> expanded = [];
      final db = await _db.database;

      for (final order in washingOrders) {
        final washingItems = order.items.where((it) {
          final name = it.itemName.toLowerCase();
          return it.machineType == 'cuci' ||
              name.contains('cuci') ||
              name.contains('wash');
        }).toList();

        if (washingItems.isEmpty) {
          expanded.add({'order': order, 'key': 'order_${order.id}_0'});
        } else {
          final totalQty = washingItems.fold<int>(
            0,
            (s, it) => s + it.quantity,
          );
          final usageResult = await db.rawQuery(
            '''
            SELECT COUNT(*) as cnt 
            FROM machine_usage_history muh 
            LEFT JOIN machines m ON muh.machine_id = m.id
            WHERE muh.order_id = ? AND muh.status = 'Success' AND (m.machine_type = 'cuci' OR muh.machine_name LIKE '%cuci%' OR muh.machine_name LIKE '%wash%')
            ''',
            [order.id],
          );
          final usedQty = usageResult.isNotEmpty
              ? (usageResult[0]['cnt'] as int)
              : 0;
          final remainingQty = (totalQty - usedQty).clamp(0, 999999);

          for (int i = 0; i < remainingQty; i++) {
            expanded.add({'order': order, 'key': 'order_${order.id}_$i'});
          }
        }
      }

      if (mounted) {
        setState(() {
          _activeOrders = expanded;
          // Clear selected order if it is no longer active
          if (_selectedOrderItem != null &&
              !expanded.any(
                (item) => item['key'] == _selectedOrderItem!['key'],
              )) {
            _selectedOrderItem = null;
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _activeOrders = []);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Left Panel: Active Orders List (Master: 340px width)
        Container(
          width: 340,
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(right: BorderSide(color: Color(0xFFE2E8F0))),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Antrian Cuci (${_activeOrders.length})',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded, size: 20),
                      onPressed: _loadActiveOrders,
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _activeOrders.isEmpty
                    ? _buildEmptyOrdersState()
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _activeOrders.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, idx) {
                          final item = _activeOrders[idx];
                          final isSelected =
                              _selectedOrderItem?['key'] == item['key'];
                          return _buildOrderCard(item, isSelected);
                        },
                      ),
              ),
            ],
          ),
        ),

        // 2. Right Panel: Responsive Machine Grid (Detail: Expanded)
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(28.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.grid_view_rounded,
                      color: Color(0xFF0F172A),
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Daftar Mesin Cuci',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const Spacer(),
                    if (_selectedOrderItem != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: primaryColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: primaryColor.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          children: [
                            Text(
                              'Pilih mesin untuk: ${_selectedOrderItem!['order'].customerName}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: primaryColor,
                              ),
                            ),
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: () =>
                                  setState(() => _selectedOrderItem = null),
                              child: Icon(
                                Icons.close_rounded,
                                size: 14,
                                color: primaryColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: ValueListenableBuilder<int>(
                    valueListenable: MachineStatusService.instance.updates,
                    builder: (context, _, __) {
                      return _buildMachineGrid();
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyOrdersState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle_outline_rounded,
            size: 48,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 12),
          const Text(
            'Antrian Bersih!',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFF475569),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Tidak ada cucian yang menunggu.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> item, bool isSelected) {
    final Order order = item['order'];
    final String orderKey = item['key'];
    final date = _parseOrderDate(order.orderDate);

    final bool isProcessing = MachineStatusService.instance.isOrderProcessing(
      orderKey,
    );
    final bool isFailed = MachineStatusService.instance.isOrderFailed(orderKey);

    Color borderCol = isSelected ? primaryColor : const Color(0xFFCBD5E1);
    Color bgCol = isSelected ? const Color(0xFFEFF6FF) : Colors.white;

    if (isProcessing) {
      bgCol = const Color(0xFFFEFCE8);
      borderCol = const Color(0xFFFACC15);
    } else if (isFailed) {
      bgCol = const Color(0xFFFEF2F2);
      borderCol = const Color(0xFFF87171);
    }

    return Container(
      decoration: BoxDecoration(
        color: bgCol,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderCol, width: isSelected ? 2 : 1.5),
        boxShadow: [
          BoxShadow(
            color: isSelected
                ? primaryColor.withValues(alpha: 0.15)
                : const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: isSelected ? 10 : 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: isProcessing
              ? null
              : () {
                  setState(() {
                    _selectedOrderItem = isSelected ? null : item;
                  });
                },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: isSelected
                          ? primaryColor
                          : const Color(0xFFF1F5F9),
                      child: Text(
                        order.customerName.isNotEmpty
                            ? order.customerName[0].toUpperCase()
                            : '?',
                        style: TextStyle(
                          color: isSelected ? Colors.white : primaryColor,
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            order.customerName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14.5,
                              color: Color(0xFF0F172A),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Nota #${order.id}',
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF475569),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  order.items
                      .map((e) => "${e.itemName} x${e.quantity}")
                      .join(', '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF334155),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatDateTime(date),
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    if (isProcessing)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      Icon(
                        isSelected
                            ? Icons.check_circle_rounded
                            : Icons.arrow_forward_rounded,
                        size: 18,
                        color: isSelected ? primaryColor : const Color(0xFF94A3B8),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMachineGrid() {
    final List<MachineModel> displayMachines = _machines.isNotEmpty
        ? _machines
        : List.generate(
            widget.items,
            (index) => MachineModel(
              id: index + 1,
              name: 'Cuci 0${index + 1}',
              url: '',
              key: '',
              createdAt: DateTime.now(),
            ),
          );

    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 280,
        childAspectRatio: 1.1,
        crossAxisSpacing: 18,
        mainAxisSpacing: 18,
      ),
      itemCount: displayMachines.length,
      itemBuilder: (context, index) {
        final machine = displayMachines[index];
        String displayName = machine.name.isNotEmpty
            ? machine.name
            : machine.key;
        if (displayName.toLowerCase().startsWith('sensor.')) {
          displayName = displayName.substring(7);
        }
        return _buildMachineCard(machine, displayName);
      },
    );
  }

  Widget _buildMachineCard(MachineModel machine, String displayName) {
    final service = MachineStatusService.instance;
    final states = service.states;

    String normalize(String s) {
      String result = s.toLowerCase().replaceAll(' ', '_');
      if (result.startsWith('sensor.')) {
        result = result.substring(7);
      }
      return result;
    }

    dynamic entry = states[machine.name] ?? states[displayName];
    if (entry == null) {
      entry =
          states['sensor.' + machine.name] ?? states['sensor.' + displayName];
    }
    if (entry == null) {
      final normalizedName = normalize(machine.name);
      final normalizedDisplay = normalize(displayName);
      for (final key in states.keys) {
        final normalizedKey = normalize(key);
        if (normalizedKey == normalizedName ||
            normalizedKey == normalizedDisplay) {
          entry = states[key];
          break;
        }
      }
    }

    String state = 'READY';
    String runState = 'Idle';
    String machineStatus = 'ready';
    String remain = '';
    String customerName = '';

    if (entry != null) {
      state = (entry['state'] ?? 'Ready').toString().toUpperCase();
      runState = (entry['run_state'] ?? 'Idle').toString();
      machineStatus = (entry['status'] ?? 'ready').toString().toLowerCase();
      remain = (entry['remain_time'] ?? '').toString();
      customerName = (entry['customer_name'] ?? '').toString();
    }

    final bool waSent = entry != null && entry['wa_sent'] == true;
    final bool isError = state == 'ERROR' || state == 'OFFLINE';

    Color iconColor;
    Color iconBg;
    IconData machineIcon = Icons.local_laundry_service_rounded;
    Color border;
    Gradient cardGradient;
    String badgeText;
    Color badgeBg;
    Color badgeTextColor;
    Color titleColor;
    Color subColor;
    bool canClick = false;

    final bool isPause = runState.toLowerCase().contains('pause') ||
        state.toLowerCase().contains('pause');

    final bool isRunning = customerName.isNotEmpty &&
                           ((state == 'RUNNING' ||
                            state == 'RUN' ||
                            (runState.isNotEmpty &&
                             runState != 'Idle' &&
                             runState != 'Completed' &&
                             runState != 'Ready' &&
                             runState != 'Standby' &&
                             runState != 'Initial' &&
                             runState != '-' &&
                             runState != 'unknown')) && !isPause);

    final bool isDetecting = runState.toLowerCase() == 'detecting';

    final bool isOfflineRunning = !isDetecting && isRunning && (
      runState.toLowerCase().contains('offline') ||
      (entry != null && entry['is_offline'] == true)
    );

    final bool isBooking = !isRunning &&
        !isDetecting &&
        !isPause &&
        customerName.isNotEmpty &&
        (machineStatus == 'unready' ||
            state.toUpperCase().contains('BOOKING') ||
            runState.toLowerCase().contains('booking'));

    if (isError) {
      // ERROR (Red Full Gradient)
      cardGradient = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFEF2F2), Color(0xFFFEE2E2)],
      );
      border = const Color(0xFFFCA5A5);
      iconBg = const Color(0xFFEF4444);
      iconColor = Colors.white;
      machineIcon = Icons.error_outline_rounded;
      badgeBg = const Color(0xFFDC2626);
      badgeTextColor = Colors.white;
      titleColor = const Color(0xFF7F1D1D);
      subColor = const Color(0xFF991B1B);
      badgeText = "ERROR";
      canClick = true;
    } else if (isOfflineRunning) {
      // OFFLINE RUNNING (Amber / Warm Orange Gradient with Cloud Off Icon)
      cardGradient = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFFF7ED), Color(0xFFFFEDD5)],
      );
      border = const Color(0xFFFDBA74);
      iconBg = const Color(0xFFEA580C);
      iconColor = Colors.white;
      machineIcon = Icons.cloud_off_rounded;
      badgeBg = const Color(0xFFC2410C);
      badgeTextColor = Colors.white;
      titleColor = const Color(0xFF7C2D12);
      subColor = const Color(0xFF9A3412);
      final String timeText = (remain.isNotEmpty && remain != '--:--') ? ' $remain' : '';
      badgeText = "OFFLINE$timeText";
      canClick = true;
    } else if (isPause) {
      // PAUSED STATE (Amber / Warning Yellow/Orange Full Gradient with Warning/Pause Icon)
      cardGradient = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFFFBEB), Color(0xFFFEF3C7)],
      );
      border = const Color(0xFFF59E0B);
      iconBg = const Color(0xFFD97706);
      iconColor = Colors.white;
      machineIcon = Icons.pause_circle_filled_rounded;
      badgeBg = const Color(0xFFD97706);
      badgeTextColor = Colors.white;
      titleColor = const Color(0xFF78350F);
      subColor = const Color(0xFFB45309);
      final String timeText = (remain.isNotEmpty && remain != '--:--') ? ' $remain' : '';
      badgeText = "PAUSE$timeText";
      canClick = true;
    } else if (isRunning) {
      // RUNNING ONLINE (Blue Electric Full Gradient from Real LG Cloud Sensor)
      cardGradient = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFEFF6FF), Color(0xFFDBEAFE)],
      );
      border = const Color(0xFF93C5FD);
      iconBg = const Color(0xFF2563EB);
      iconColor = Colors.white;
      machineIcon = isDetecting ? Icons.scale_rounded : Icons.local_laundry_service_rounded;
      badgeBg = const Color(0xFF1D4ED8);
      badgeTextColor = Colors.white;
      titleColor = const Color(0xFF1E3A8A);
      subColor = const Color(0xFF1D4ED8);
      final String timeText = (remain.isNotEmpty && remain != '--:--') ? ' $remain' : '';
      badgeText = isDetecting ? "MENIMBANG" : "RUNNING$timeText";
      canClick = true;
    } else if (customerName.isEmpty) {
      final bool isStandby = runState.toLowerCase().contains('standby') ||
          runState.toLowerCase().contains('initial') ||
          state.contains('STANDBY');

      if (isStandby) {
        // STANDBY (Amber / Warm Orange Full Gradient)
        cardGradient = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFFBEB), Color(0xFFFEF3C7)],
        );
        border = const Color(0xFFF59E0B);
        iconBg = const Color(0xFFD97706);
        iconColor = Colors.white;
        machineIcon = Icons.power_rounded;
        badgeBg = const Color(0xFFD97706);
        badgeTextColor = Colors.white;
        titleColor = const Color(0xFF78350F);
        subColor = const Color(0xFFB45309);
        final String timeText = (remain.isNotEmpty && remain != '--:--') ? ' $remain' : '';
        badgeText = "STANDBY$timeText";
        canClick = true;
      } else {
        // READY (Green Emerald Full Gradient)
        cardGradient = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF0FDF4), Color(0xFFDCFCE7)],
        );
        border = const Color(0xFF86EFAC);
        iconBg = const Color(0xFF10B981);
        iconColor = Colors.white;
        machineIcon = Icons.local_laundry_service_rounded;
        badgeBg = const Color(0xFF059669);
        badgeTextColor = Colors.white;
        titleColor = const Color(0xFF065F46);
        subColor = const Color(0xFF047857);
        final String timeText = (remain.isNotEmpty && remain != '--:--') ? ' $remain' : '';
        badgeText = "READY$timeText";
        canClick = true;
      }
    } else {
      // We have a customer name but not running
      if (machineStatus == 'unready') {
        // BOOKING (Orange/Amber Full Gradient)
        cardGradient = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFFBEB), Color(0xFFFEF3C7)],
        );
        border = const Color(0xFFFDE68A);
        iconBg = const Color(0xFFF59E0B);
        iconColor = Colors.white;
        machineIcon = Icons.hourglass_top_rounded;
        badgeBg = const Color(0xFFD97706);
        badgeTextColor = Colors.white;
        titleColor = const Color(0xFF78350F);
        subColor = const Color(0xFFB45309);
        final String timeText = (remain.isNotEmpty && remain != '--:--') ? ' $remain' : ' 5:00';
        badgeText = "BOOKING$timeText";
        canClick = true;
      } else {
        if (waSent) {
          // WA TERKIRIM (Teal/Cyan Full Gradient)
          cardGradient = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF0FDFA), Color(0xFFCCFBF1)],
          );
          border = const Color(0xFF99F6E4);
          iconBg = const Color(0xFF0D9488);
          iconColor = Colors.white;
          machineIcon = Icons.mark_chat_read_rounded;
          badgeBg = const Color(0xFF0F766E);
          badgeTextColor = Colors.white;
          titleColor = const Color(0xFF134E4A);
          subColor = const Color(0xFF0F766E);
          badgeText = "WA TERKIRIM";
          canClick = true;
        } else {
          // SELESAI / MENUNGGU (Yellow/Amber Full Gradient)
          cardGradient = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFEFCE8), Color(0xFFFEF08A)],
          );
          border = const Color(0xFFFDE047);
          iconBg = const Color(0xFFEAB308);
          iconColor = Colors.white;
          machineIcon = Icons.check_circle_rounded;
          badgeBg = const Color(0xFFA16207);
          badgeTextColor = Colors.white;
          titleColor = const Color(0xFF713F12);
          subColor = const Color(0xFF854D0E);
          badgeText = "SELESAI";
          canClick = true;
        }
      }
    }

    if (customerName.isEmpty) {
      canClick = _selectedOrderItem != null;
    }

    final bool isActivating = service.isActivating(machine.id ?? 0);

    return Container(
      decoration: BoxDecoration(
        gradient: cardGradient,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: border,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: iconBg.withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: (isActivating || !canClick)
                ? null
                : () => _handleMachineTap(
                    machine,
                    displayName,
                    machineStatus,
                    state,
                    entry,
                  ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                // Top Row: Machine Icon + Status Chip
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: iconBg,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: iconBg.withValues(alpha: 0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: isActivating
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Icon(
                              machineIcon,
                              color: iconColor,
                              size: 22,
                            ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: badgeBg,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: badgeBg.withValues(alpha: 0.25),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isPause) ...[
                            const Icon(
                              Icons.warning_amber_rounded,
                              size: 13,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            badgeText,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w900,
                              color: badgeTextColor,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Spacer(),

                // Name
                Text(
                  displayName,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    color: titleColor,
                  ),
                ),
                const SizedBox(height: 4),

                // Subtitle/Remain
                Text(
                  isDetecting
                      ? 'Menimbang Beban (Detecting)...'
                      : (isPause
                          ? (remain.isNotEmpty && remain != '--:--'
                              ? '$remain (Dijeda / Pause)'
                              : 'Mesin Dijeda (Pause)')
                          : (isBooking
                              ? (remain.isNotEmpty && remain != '--:--'
                                  ? 'Booking ($remain tersisa)'
                                  : 'Booking (5:00)')
                              : (isRunning
                                  ? (remain.isNotEmpty && remain != '--:--'
                                      ? '$remain ($runState)'
                                      : runState)
                                  : (customerName.isEmpty && (runState.toLowerCase().contains('standby') || runState.toLowerCase().contains('initial') || state.contains('STANDBY'))
                                      ? (remain.isNotEmpty && remain != '--:--'
                                          ? 'Mesin Menyala ($remain tersisa)'
                                          : 'Mesin Menyala (Standby LG)')
                                      : ((runState == 'Idle' || runState == 'Standby' || runState == 'Initial')
                                          ? (customerName.isNotEmpty
                                              ? (waSent ? 'Selesai (Sudah di-WA)' : 'Selesai (Menunggu Tindakan)')
                                              : 'Siap Digunakan (Idle)')
                                          : runState))))),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: subColor,
                  ),
                ),

                // Customer details if active
                if (customerName.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.person_rounded,
                          size: 13,
                          color: iconBg,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            customerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: titleColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

  Future<void> _handleMachineTap(
    MachineModel machine,
    String displayName,
    String machineStatus,
    String state,
    dynamic entry,
  ) async {
    final String customerName = (entry?['customer_name'] ?? '').toString();
    final String runState = (entry?['run_state'] ?? 'Idle').toString();

    final bool isRunning = state == 'RUNNING' ||
        state == 'RUN' ||
        (runState.isNotEmpty &&
            runState != 'Idle' &&
            runState != 'Completed' &&
            runState != 'Ready' &&
            runState != 'Standby' &&
            runState != 'Initial' &&
            runState != '-' &&
            runState != 'unknown');

    final bool isDetecting = runState.toLowerCase() == 'detecting';

    final bool isBooking = !isRunning &&
        !isDetecting &&
        customerName.isNotEmpty &&
        (machineStatus == 'unready' ||
            state.toUpperCase().contains('BOOKING') ||
            runState.toLowerCase().contains('booking'));

    // 1. If machine is empty (no customer assigned)
    if (customerName.isEmpty) {
      if (_selectedOrderItem != null) {
        _confirmAndAssign(_selectedOrderItem!, machine.id ?? 0, displayName);
      }
      return;
    }

    // 2. If machine is in 5-minute BOOKING window (before physical start) -> LOCKED
    if (isBooking) {
      final remainStr = (entry?['remain_time'] ?? '').toString();
      final String timeInfo = remainStr.isNotEmpty && remainStr != '--:--' ? ' ($remainStr tersisa)' : '';
      Globals.showWarningSnackBar(
        'Mesin $displayName sedang dalam masa Booking$timeInfo untuk $customerName. Mesin terkunci selama periode 5 menit untuk dinyalakan di outlet.',
      );
      return;
    }

    // 3. Otherwise (Machine is RUNNING, DETECTING, COMPLETED, or OCCUPIED) -> trigger action dialog
    _showActionDialog(machine, displayName, machineStatus, state, entry);
  }

  Future<void> _showActionDialog(
    MachineModel machine,
    String displayName,
    String machineStatus,
    String state,
    dynamic entry,
  ) async {
    final String customerName = (entry?['customer_name'] ?? '').toString();
    String customerPhone = (entry?['customer_phone'] ?? '').toString();
    final bool waSent = entry?['wa_sent'] == true;

    final String currentCleanName = displayName.trim().toLowerCase();
    final String currentMachineName = machine.name.trim().toLowerCase();
    final Set<String> otherMachinesSet = {};

    // 1. Add other machines from entry['other_machines'] if any
    if (entry?['other_machines'] != null) {
      for (final m in entry['other_machines']) {
        final mStr = m.toString().trim();
        if (mStr.isNotEmpty &&
            mStr.toLowerCase() != currentCleanName &&
            mStr.toLowerCase() != currentMachineName) {
          otherMachinesSet.add(mStr);
        }
      }
    }

    // 2. Cross-check active machines across all live IoT statuses (washers & dryers)
    final allStatuses = MachineStatusService.instance.states;
    allStatuses.forEach((key, val) {
      if (val is Map<String, dynamic>) {
        final cName = (val['customer_name'] ?? '').toString().trim();
        final cPhone = (val['customer_phone'] ?? '').toString().trim();
        final isMatch = (customerName.isNotEmpty &&
                customerName != '-' &&
                customerName != 'null' &&
                cName.toLowerCase() == customerName.toLowerCase()) ||
            (customerPhone.isNotEmpty &&
                cPhone.isNotEmpty &&
                cPhone == customerPhone);

        if (isMatch) {
          final mDisp = (val['name'] ?? key).toString().replaceAll('_', ' ').trim();
          if (mDisp.toLowerCase() != currentCleanName &&
              mDisp.toLowerCase() != currentMachineName) {
            final st = (val['status'] ?? '').toString().toLowerCase();
            final runSt = (val['run_state'] ?? '').toString().toLowerCase();
            final stateVal = (val['state'] ?? '').toString().toUpperCase();
            final isBooking = st == 'unready';
            final isRunning = stateVal == 'RUNNING' ||
                stateVal == 'RUN' ||
                (runSt.isNotEmpty &&
                    runSt != 'idle' &&
                    runSt != 'ready' &&
                    runSt != 'completed' &&
                    runSt != 'standby' &&
                    runSt != '-' &&
                    runSt != 'unknown');

            if (isBooking || isRunning) {
              otherMachinesSet.add(mDisp);
            }
          }
        }
      }
    });

    // 3. Query active orders & pending cycles in SQLite database
    int pendingOrderCycles = 0;
    final List<String> pendingBreakdowns = [];

    if (customerName.isNotEmpty && customerName != '-' && customerName != 'null') {
      try {
        final db = await _db.database;
        final activeOrders = await db.rawQuery(
          'SELECT id FROM orders WHERE customer_name = ? AND LOWER(status) != "completed"',
          [customerName],
        );

        for (final o in activeOrders) {
          final orderId = o['id'] as int;
          final items = await db.rawQuery(
            '''
            SELECT oi.item_name, oi.quantity, t.machine_type
            FROM order_items oi
            LEFT JOIN transactions t ON oi.item_id = t.id
            WHERE oi.order_id = ?
            ''',
            [orderId],
          );

          int totalOrderCycles = 0;
          int orderWashCount = 0;
          int orderDryCount = 0;

          for (final it in items) {
            final qty = (it['quantity'] as num?)?.toInt() ?? 1;
            final mType = (it['machine_type'] as String?)?.toLowerCase();
            final iName = (it['item_name'] as String?)?.toLowerCase() ?? '';
            if (mType == 'cuci' || iName.contains('cuci') || iName.contains('wash')) {
              totalOrderCycles += qty;
              orderWashCount += qty;
            } else if (mType == 'pengering' || iName.contains('kering') || iName.contains('pengering') || iName.contains('dry')) {
              totalOrderCycles += qty;
              orderDryCount += qty;
            }
          }

          if (totalOrderCycles == 0) continue;

          final usedRows = await db.rawQuery(
            'SELECT COUNT(*) as cnt FROM machine_usage_history WHERE order_id = ? AND status = "Success"',
            [orderId],
          );
          final usedCycles = usedRows.isNotEmpty ? (usedRows.first['cnt'] as int? ?? 0) : 0;

          final int remaining = (totalOrderCycles - usedCycles).clamp(0, 999999);
          if (remaining > 0) {
            pendingOrderCycles += remaining;
            if (orderDryCount > 0) {
              pendingBreakdowns.add('$orderDryCount Pengeringan');
            }
            if (orderWashCount > usedCycles) {
              pendingBreakdowns.add('${orderWashCount - usedCycles} Cuci');
            }
          }
        }
      } catch (e) {
        debugPrint('Error checking pending cycles: $e');
      }
    }

    final List<String> otherMachines = otherMachinesSet.toList();
    final bool isFinalCycle = otherMachines.isEmpty && pendingOrderCycles == 0;

    // If phone is missing in IoT state, look up phone number from local SQLite DB
    if (customerPhone.isEmpty && customerName.isNotEmpty && customerName != '-' && customerName != 'null') {
      try {
        final db = await _db.database;
        final res = await db.rawQuery(
          'SELECT customer_phone FROM orders WHERE customer_name = ? AND customer_phone IS NOT NULL AND customer_phone != "" ORDER BY id DESC LIMIT 1',
          [customerName],
        );
        if (res.isNotEmpty && res.first['customer_phone'] != null) {
          customerPhone = res.first['customer_phone'].toString();
        } else {
          final custRes = await db.rawQuery(
            'SELECT phone FROM customers WHERE name = ? AND phone IS NOT NULL AND phone != "" LIMIT 1',
            [customerName],
          );
          if (custRes.isNotEmpty && custRes.first['phone'] != null) {
            customerPhone = custRes.first['phone'].toString();
          }
        }
      } catch (_) {}
    }

    final Order? newOrder = _selectedOrderItem != null
        ? _selectedOrderItem!['order'] as Order
        : null;
    final bool isReplacing = newOrder != null;

    // Check if new customer needs phone number input
    final bool needsPhoneInput =
        isReplacing &&
        (newOrder.customerPhone == null ||
            newOrder.customerPhone!.trim().isEmpty);

    // WA options: Only default to ON if this is the genuine final cycle to finish
    bool sendWa = isFinalCycle && !waSent;
    bool isCustomMessage = false;

    final String defaultTemplate =
        "Halo Kak $customerName, cucian Anda di Smart Laundry sudah selesai dan siap diambil! Silakan mampir untuk pengambilan ya. Terima kasih! 😊";

    final TextEditingController activePhoneCtrl = TextEditingController(
      text: customerPhone.startsWith('+62')
          ? customerPhone.substring(3)
          : (customerPhone.startsWith('0') ? customerPhone.substring(1) : customerPhone),
    );
    final TextEditingController newPhoneCtrl = TextEditingController(text: '8');
    final TextEditingController msgCtrl = TextEditingController(text: defaultTemplate);

    if (!mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
              elevation: 16,
              backgroundColor: Colors.white,
              child: Container(
                width: 580,
                constraints: const BoxConstraints(maxHeight: 700),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 1. Desktop Header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 20, 20, 16),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: isReplacing
                                  ? primaryColor.withValues(alpha: 0.1)
                                  : const Color(0xFF10B981).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              isReplacing
                                  ? Icons.swap_horiz_rounded
                                  : Icons.tune_rounded,
                              color: isReplacing ? primaryColor : const Color(0xFF059669),
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isReplacing
                                      ? 'Ganti Pelanggan ($displayName)'
                                      : 'Kelola Mesin: $displayName',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 17,
                                    color: Color(0xFF0F172A),
                                    letterSpacing: -0.2,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  isReplacing
                                      ? 'Selesaikan cucian aktif & alihkan ke pesanan antrian'
                                      : 'Selesaikan cucian & kirim notifikasi WhatsApp ke pelanggan',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF64748B),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 20, color: Color(0xFF94A3B8)),
                            splashRadius: 18,
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: Color(0xFFE2E8F0)),

                    // 2. Scrollable Body Content
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Machine & Active Customer Info Tile
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 18,
                                    backgroundColor: primaryColor.withValues(alpha: 0.12),
                                    child: Text(
                                      customerName.isNotEmpty ? customerName[0].toUpperCase() : '?',
                                      style: TextStyle(
                                        color: primaryColor,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              customerName.isNotEmpty ? customerName : 'Tanpa Pelanggan',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 14.5,
                                                color: Color(0xFF0F172A),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFE2E8F0),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: const Text(
                                                'Pelanggan Aktif',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w700,
                                                  color: Color(0xFF475569),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          customerPhone.isNotEmpty ? customerPhone : 'Nomor WA belum tercatat',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: customerPhone.isNotEmpty ? const Color(0xFF059669) : const Color(0xFF94A3B8),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: waSent ? const Color(0xFFEDE9FE) : const Color(0xFFFEF3C7),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: waSent ? const Color(0xFFDDD6FE) : const Color(0xFFFDE68A),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          waSent ? Icons.mark_chat_read_rounded : Icons.schedule_rounded,
                                          size: 13,
                                          color: waSent ? const Color(0xFF7C3AED) : const Color(0xFFD97706),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          waSent ? 'Sudah di-WA' : 'Belum di-WA',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            color: waSent ? const Color(0xFF6D28D9) : const Color(0xFFB45309),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Cycle Status Banner (Bukan Siklus Terakhir vs Siklus Terakhir)
                            if (customerName.isNotEmpty && customerName != '-' && customerName != 'null') ...[
                              if (!isFinalCycle) ...[
                                Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFFBEB),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: const Color(0xFFFDE68A)),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Icon(Icons.info_outline_rounded, color: Color(0xFFD97706), size: 20),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Bukan Siklus Terakhir untuk $customerName',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 13,
                                                color: Color(0xFF92400E),
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              otherMachines.isNotEmpty && pendingOrderCycles > 0
                                                  ? '$customerName masih aktif di ${otherMachines.join(", ")} dan masih ada $pendingOrderCycles siklus antrian.'
                                                  : (otherMachines.isNotEmpty
                                                      ? '$customerName masih memiliki mesin aktif di: ${otherMachines.join(", ")}.'
                                                      : '$customerName masih memiliki $pendingOrderCycles siklus lanjutan (${pendingBreakdowns.join(", ")}) dalam antrian pesanan.'),
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Color(0xFFB45309),
                                                height: 1.35,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            const SizedBox(height: 5),
                                            const Text(
                                              '💡 Notifikasi WhatsApp selesai otomatis diaktifkan saat siklus mesin terakhir diselesaikan.',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFF78350F),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ] else ...[
                                Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF0FDF4),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: const Color(0xFF86EFAC)),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Icon(Icons.check_circle_outline_rounded, color: Color(0xFF16A34A), size: 20),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Siklus Mesin Terakhir Selesai! 🎉',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 13,
                                                color: Color(0xFF166534),
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              'Semua proses cucian untuk $customerName telah tuntas. Notifikasi WhatsApp siap dikirimkan ke pelanggan.',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Color(0xFF15803D),
                                                height: 1.35,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ],
                            ],

                            // WhatsApp Studio Card (Compact & Modern)
                            if (customerName.isNotEmpty && customerName != '-' && customerName != 'null') ...[
                              Container(
                                decoration: BoxDecoration(
                                  color: sendWa ? const Color(0xFFF0FDF4) : const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: sendWa ? const Color(0xFF86EFAC) : const Color(0xFFE2E8F0),
                                    width: sendWa ? 1.5 : 1.0,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Header Toggle Row
                                    InkWell(
                                      borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
                                      onTap: () => setModalState(() => sendWa = !sendWa),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                        child: Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                color: sendWa ? const Color(0xFF22C55E) : const Color(0xFFCBD5E1),
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                              child: const Icon(Icons.chat_rounded, color: Colors.white, size: 16),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'Kirim WhatsApp Selesai ke $customerName',
                                                    style: const TextStyle(
                                                      fontWeight: FontWeight.w800,
                                                      fontSize: 13.5,
                                                      color: Color(0xFF0F172A),
                                                    ),
                                                  ),
                                                  Text(
                                                    sendWa
                                                        ? 'Otomatis kirim pesan konfirmasi cucian selesai'
                                                        : (isFinalCycle
                                                            ? 'Matikan jika tidak ingin mengirim notifikasi'
                                                            : 'Dinonaktifkan sementara (Menunggu siklus terakhir selesai)'),
                                                    style: TextStyle(
                                                      fontSize: 11.5,
                                                      color: sendWa ? const Color(0xFF15803D) : const Color(0xFF64748B),
                                                      fontWeight: FontWeight.w500,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Switch.adaptive(
                                              value: sendWa,
                                              activeThumbColor: const Color(0xFF16A34A),
                                              activeTrackColor: const Color(0xFF86EFAC),
                                              onChanged: (v) => setModalState(() => sendWa = v),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),

                                    if (sendWa) ...[
                                      const Divider(height: 1, color: Color(0xFFDCFCE7)),
                                      Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            // Manual Phone Input if missing
                                            if (customerPhone.isEmpty) ...[
                                              const Text(
                                                'Nomor WhatsApp belum tercatat. Masukkan nomor:',
                                                style: TextStyle(
                                                  fontSize: 11.5,
                                                  fontWeight: FontWeight.bold,
                                                  color: Color(0xFFD97706),
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              TextField(
                                                controller: activePhoneCtrl,
                                                keyboardType: TextInputType.phone,
                                                decoration: InputDecoration(
                                                  labelText: 'Nomor WhatsApp $customerName',
                                                  prefixText: '+62 ',
                                                  prefixStyle: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
                                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                                  filled: true,
                                                  fillColor: Colors.white,
                                                ),
                                              ),
                                              const SizedBox(height: 12),
                                            ],

                                            // Modern Segmented Option Buttons (Template vs Custom)
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: InkWell(
                                                    onTap: () => setModalState(() {
                                                      isCustomMessage = false;
                                                      msgCtrl.text = defaultTemplate;
                                                    }),
                                                    borderRadius: BorderRadius.circular(10),
                                                    child: Container(
                                                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                                                      decoration: BoxDecoration(
                                                        color: !isCustomMessage ? Colors.white : Colors.transparent,
                                                        borderRadius: BorderRadius.circular(10),
                                                        border: Border.all(
                                                          color: !isCustomMessage ? const Color(0xFF16A34A) : const Color(0xFFCBD5E1),
                                                          width: !isCustomMessage ? 1.5 : 1.0,
                                                        ),
                                                        boxShadow: !isCustomMessage ? [
                                                          BoxShadow(
                                                            color: const Color(0xFF16A34A).withValues(alpha: 0.1),
                                                            blurRadius: 4,
                                                            offset: const Offset(0, 2),
                                                          ),
                                                        ] : null,
                                                      ),
                                                      child: Row(
                                                        mainAxisAlignment: MainAxisAlignment.center,
                                                        children: [
                                                          Icon(
                                                            !isCustomMessage ? Icons.radio_button_checked : Icons.radio_button_off,
                                                            size: 15,
                                                            color: !isCustomMessage ? const Color(0xFF16A34A) : const Color(0xFF94A3B8),
                                                          ),
                                                          const SizedBox(width: 6),
                                                          const Text(
                                                            'Template Standar',
                                                            style: TextStyle(
                                                              fontSize: 12,
                                                              fontWeight: FontWeight.w700,
                                                              color: Color(0xFF0F172A),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                  child: InkWell(
                                                    onTap: () => setModalState(() {
                                                      isCustomMessage = true;
                                                      if (msgCtrl.text == defaultTemplate) {
                                                        msgCtrl.clear();
                                                      }
                                                    }),
                                                    borderRadius: BorderRadius.circular(10),
                                                    child: Container(
                                                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                                                      decoration: BoxDecoration(
                                                        color: isCustomMessage ? Colors.white : Colors.transparent,
                                                        borderRadius: BorderRadius.circular(10),
                                                        border: Border.all(
                                                          color: isCustomMessage ? const Color(0xFF16A34A) : const Color(0xFFCBD5E1),
                                                          width: isCustomMessage ? 1.5 : 1.0,
                                                        ),
                                                        boxShadow: isCustomMessage ? [
                                                          BoxShadow(
                                                            color: const Color(0xFF16A34A).withValues(alpha: 0.1),
                                                            blurRadius: 4,
                                                            offset: const Offset(0, 2),
                                                          ),
                                                        ] : null,
                                                      ),
                                                      child: Row(
                                                        mainAxisAlignment: MainAxisAlignment.center,
                                                        children: [
                                                          Icon(
                                                            isCustomMessage ? Icons.radio_button_checked : Icons.radio_button_off,
                                                            size: 15,
                                                            color: isCustomMessage ? const Color(0xFF16A34A) : const Color(0xFF94A3B8),
                                                          ),
                                                          const SizedBox(width: 6),
                                                          const Text(
                                                            'Pesan Sendiri',
                                                            style: TextStyle(
                                                              fontSize: 12,
                                                              fontWeight: FontWeight.w700,
                                                              color: Color(0xFF0F172A),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 12),

                                            // Always Visible & Directly Editable Message Textbox
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                const Row(
                                                  children: [
                                                    Icon(Icons.edit_note_rounded, size: 16, color: Color(0xFF475569)),
                                                    SizedBox(width: 4),
                                                    Text(
                                                      'Teks Pesan (Dapat Diedit Langsung):',
                                                      style: TextStyle(
                                                        fontSize: 11.5,
                                                        fontWeight: FontWeight.w800,
                                                        color: Color(0xFF334155),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                if (!isCustomMessage)
                                                  InkWell(
                                                    onTap: () {
                                                      setModalState(() {
                                                        msgCtrl.text = defaultTemplate;
                                                      });
                                                    },
                                                    child: const Padding(
                                                      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                                      child: Text(
                                                        'Reset Template',
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          fontWeight: FontWeight.bold,
                                                          color: Color(0xFF16A34A),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            const SizedBox(height: 6),
                                            TextField(
                                              controller: msgCtrl,
                                              maxLines: 3,
                                              style: const TextStyle(
                                                fontSize: 12.5,
                                                height: 1.4,
                                                color: Color(0xFF0F172A),
                                              ),
                                              decoration: InputDecoration(
                                                hintText: isCustomMessage ? 'Tulis pesan WhatsApp khusus di sini...' : defaultTemplate,
                                                border: OutlineInputBorder(
                                                  borderRadius: BorderRadius.circular(10),
                                                  borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                                                ),
                                                enabledBorder: OutlineInputBorder(
                                                  borderRadius: BorderRadius.circular(10),
                                                  borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                                                ),
                                                focusedBorder: OutlineInputBorder(
                                                  borderRadius: BorderRadius.circular(10),
                                                  borderSide: const BorderSide(color: Color(0xFF16A34A), width: 1.5),
                                                ),
                                                filled: true,
                                                fillColor: Colors.white,
                                                contentPadding: const EdgeInsets.all(12),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],

                            // If Replacing with New Customer
                            if (isReplacing) ...[
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: primaryColor.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: primaryColor.withValues(alpha: 0.25),
                                    width: 1.2,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(Icons.arrow_forward_rounded, size: 16, color: primaryColor),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Alihkan Mesin ke Pelanggan Baru:',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            color: primaryColor,
                                            fontSize: 12.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 16,
                                          backgroundColor: primaryColor,
                                          child: Text(
                                            newOrder.customerName.isNotEmpty ? newOrder.customerName[0].toUpperCase() : '?',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w900,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                newOrder.customerName,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w900,
                                                  fontSize: 14.5,
                                                  color: Color(0xFF0F172A),
                                                ),
                                              ),
                                              Text(
                                                'Nota #${newOrder.id} • ${newOrder.customerPhone ?? "Belum ada No. WA"}',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Color(0xFF64748B),
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (needsPhoneInput) ...[
                                      const SizedBox(height: 12),
                                      const Text(
                                        'Pelanggan baru belum memiliki nomor WA. Masukkan nomor:',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF64748B),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      TextField(
                                        controller: newPhoneCtrl,
                                        keyboardType: TextInputType.phone,
                                        decoration: InputDecoration(
                                          labelText: 'Nomor WhatsApp Baru',
                                          prefixText: '+62 ',
                                          prefixStyle: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                          filled: true,
                                          fillColor: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),

                    // 3. Desktop Footer Action Bar
                    const Divider(height: 1, color: Color(0xFFE2E8F0)),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
                      child: Row(
                        children: [
                          OutlinedButton(
                            onPressed: () => Navigator.pop(ctx),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF64748B),
                              side: const BorderSide(color: Color(0xFFCBD5E1)),
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'Batal',
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                            ),
                          ),
                          const Spacer(),
                          ElevatedButton(
                            onPressed: () async {
                              Navigator.pop(ctx); // Close dialog

                              final service = MachineStatusService.instance;
                              final int machineId = machine.id ?? 0;
                              service.setActivating(machineId, true);

                              try {
                                String activePhone = customerPhone;
                                if (activePhoneCtrl.text.trim().isNotEmpty) {
                                  final input = activePhoneCtrl.text.trim();
                                  activePhone = input.startsWith('+62')
                                      ? input
                                      : (input.startsWith('0') ? '+62${input.substring(1)}' : '+62$input');
                                }

                                final String messageToSend = msgCtrl.text.trim();
                                final String? customMsg = messageToSend.isNotEmpty ? messageToSend : null;

                                if (isReplacing) {
                                  String finalPhone = newOrder.customerPhone ?? '';
                                  if (needsPhoneInput) {
                                    finalPhone = '+62${newPhoneCtrl.text.trim()}';
                                    // Update order in SQLite database
                                    final db = await _db.database;
                                    await db.rawUpdate(
                                      'UPDATE orders SET customer_phone = ? WHERE id = ?',
                                      [finalPhone, newOrder.id],
                                    );
                                    // Update active order item in local memory state
                                    final updatedOrder = newOrder.copyWith(
                                      customerPhone: finalPhone,
                                    );
                                    _selectedOrderItem!['order'] = updatedOrder;
                                  }

                                  // Complete local SQLite state trigger immediately
                                  await _handleSuccessfulStart(
                                    _selectedOrderItem!['order'] as Order,
                                    machineId,
                                    machine,
                                  );
                                  Globals.showSuccessSnackBar(
                                    'Mesin cuci ${machine.name} berhasil diganti ke ${newOrder.customerName}!',
                                  );
                                  setState(() {
                                    _selectedOrderItem = null;
                                  });

                                  // Call replaceCustomer in background
                                  service.replaceCustomer(
                                    entityId: machine.name,
                                    newCustomerName: newOrder.customerName,
                                    newCustomerPhone: finalPhone,
                                    sendWaToPrevious: sendWa,
                                    waMessage: customMsg,
                                    previousCustomerPhone: activePhone,
                                  ).then((res) {
                                    if (res['success'] != true) {
                                      Globals.showErrorSnackBar('Info IoT: ${res['error']}');
                                    }
                                  }).catchError((e) {
                                    Globals.showErrorSnackBar('Koneksi IoT error: $e');
                                  }).whenComplete(() {
                                    service.setActivating(machineId, false);
                                    if (mounted) setState(() {});
                                  });
                                } else {
                                  // Just finish the monitoring (Selesaikan) immediately
                                  Globals.showSuccessSnackBar(
                                    'Mesin cuci ${machine.name} berhasil diselesaikan!',
                                  );

                                  service.finishAndNotify(
                                    entityId: machine.name,
                                    sendWa: sendWa,
                                    waMessage: customMsg,
                                    customerPhone: activePhone,
                                  ).then((res) {
                                    if (res['success'] != true) {
                                      Globals.showErrorSnackBar('Info IoT: ${res['error']}');
                                    }
                                  }).catchError((e) {
                                    Globals.showErrorSnackBar('Koneksi IoT error: $e');
                                  }).whenComplete(() {
                                    service.setActivating(machineId, false);
                                    if (mounted) setState(() {});
                                  });
                                }
                              } catch (e) {
                                Globals.showErrorSnackBar('Error: $e');
                                service.setActivating(machineId, false);
                                if (mounted) setState(() {});
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isReplacing
                                  ? primaryColor
                                  : (sendWa ? const Color(0xFF059669) : primaryColor),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 2,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isReplacing
                                      ? Icons.swap_horiz_rounded
                                      : (sendWa ? Icons.send_rounded : Icons.check_circle_rounded),
                                  size: 17,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  isReplacing
                                      ? (sendWa ? 'Ganti & Kirim WA' : 'Ganti Pelanggan')
                                      : (sendWa ? 'Selesaikan & Kirim WA' : 'Selesaikan Mesin'),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _startMonitoring({
    required MachineModel machine,
    required String name,
    required String phone,
    Order? order,
  }) async {
    final service = MachineStatusService.instance;
    final int machineId = machine.id ?? 0;

    service.setActivating(machineId, true);
    try {
      // 1. Immediately record in database and update active orders list (no await on network!)
      if (order != null) {
        await _handleSuccessfulStart(order, machineId, machine);
      } else {
        Globals.showSuccessSnackBar(
          'Monitoring mesin ${machine.name} berhasil dimulai!',
        );
      }
    } catch (e) {
      Globals.showErrorSnackBar('Gagal menyimpan ke database lokal: $e');
    }

    // 2. Fire-and-forget the API call in the background (5-minute booking window)
    service.startMachineMonitoring(
      entityId: machine.name,
      customerName: name.isNotEmpty ? name : 'Pelanggan',
      customerPhone: phone.isNotEmpty ? phone : null,
      durationMinutes: 5,
    ).then((res) {
      if (res['success'] != true) {
        Globals.showErrorSnackBar('Info IoT: ${res['error']}');
      }
    }).catchError((e) {
      Globals.showErrorSnackBar('Koneksi IoT error: $e');
    }).whenComplete(() {
      service.setActivating(machineId, false);
      if (mounted) setState(() {});
    });
  }

  Future<void> _stopMonitoring(MachineModel machine) async {
    final service = MachineStatusService.instance;
    final int machineId = machine.id ?? 0;

    service.setActivating(machineId, true);
    try {
      final res = await service.stopMachineMonitoring(entityId: machine.name);
      if (res['success'] == true) {
        Globals.showSuccessSnackBar(
          'Pemantauan mesin ${machine.name} berhasil dihentikan!',
        );
      } else {
        Globals.showErrorSnackBar(
          'Gagal menghentikan pemantauan: ${res['error']}',
        );
      }
    } catch (e) {
      Globals.showErrorSnackBar('Koneksi error: $e');
    } finally {
      service.setActivating(machineId, false);
      if (mounted) setState(() {});
    }
  }

  Future<void> _confirmAndAssign(
    Map<String, dynamic> item,
    int machineId,
    String machineName,
  ) async {
    final Order order = item['order'];
    final machine = _machines.firstWhere(
      (m) => (m.id ?? 0) == machineId,
      orElse: () => MachineModel(
        id: machineId,
        name: machineName,
        url: '',
        key: '',
        createdAt: DateTime.now(),
      ),
    );

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Konfirmasi Pemakaian Mesin',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Text(
            'Apakah Anda yakin memulai $machineName untuk "${order.customerName}"?',
            style: const TextStyle(fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('Ya, Mulai', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    // Clear selection immediately
    setState(() {
      _selectedOrderItem = null;
    });

    // Call start monitoring via Python API in the background
    _startMonitoring(
      machine: machine,
      name: order.customerName,
      phone: order.customerPhone ?? '',
      order: order,
    );
  }

  Future<void> _handleSuccessfulStart(
    Order order,
    int machineId,
    MachineModel machine,
  ) async {
    final now = DateTime.now();
    try {
      final dbOrder = order.id != null ? await _db.getOrder(order.id!) : null;

      int totalWashingQty = 0;
      int usedWashingQty = 0;
      if (dbOrder != null) {
        totalWashingQty = dbOrder.items
            .where((it) {
              final name = it.itemName.toLowerCase();
              return it.machineType == 'cuci' ||
                  name.contains('cuci') ||
                  name.contains('wash');
            })
            .fold<int>(0, (s, it) => s + it.quantity);

        final db = await _db.database;
        final usageCount = await db.rawQuery(
          '''
          SELECT COUNT(*) as cnt 
          FROM machine_usage_history muh 
          LEFT JOIN machines m ON muh.machine_id = m.id
          WHERE muh.order_id = ? AND muh.status = 'Success' AND (m.machine_type = 'cuci' OR muh.machine_name LIKE '%cuci%' OR muh.machine_name LIKE '%wash%')
          ''',
          [order.id],
        );
        usedWashingQty = usageCount.isNotEmpty
            ? (usageCount[0]['cnt'] as int)
            : 0;
      }
      int remainingWashingQty = (totalWashingQty - usedWashingQty - 1).clamp(
        0,
        999999,
      );

      final machineName =
          (await _db.getMachine(machineId))?.name ?? 'Cuci $machineId';

      await _db.recordMachineUsage(
        orderId: order.id!,
        machineId: machineId,
        machineName: machineName,
        customerName: order.customerName,
        startedAt: now,
        status: 'Success',
      );

      if (remainingWashingQty == 0) {
        await _db.updateOrderMachineAssignment(order.id!, machineId, now);
      }

      if (mounted) {
        await _loadActiveOrders();
      }

      Globals.showSuccessSnackBar(
        'Mesin ${machine.name} berhasil dinyalakan & dipantau!',
      );
      await NotificationService.instance.showNotification(
        title: 'Mesin ${machine.name}',
        body: 'Berhasil dinyalakan & dipantau',
      );
    } catch (e) {
      Globals.showErrorSnackBar('Gagal menyelesaikan proses mesin: $e');
    }
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
}
