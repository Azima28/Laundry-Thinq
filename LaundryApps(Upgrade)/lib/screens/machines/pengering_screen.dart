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

class PengeringScreen extends StatelessWidget {
  final int items;
  final String title;

  const PengeringScreen({
    Key? key,
    this.items = 5,
    this.title = 'Status Mesin Pengering',
  }) : super(key: key);

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
      body: PengeringContent(items: items, title: title),
    );
  }
}

class PengeringContent extends StatefulWidget {
  final int items;
  final String title;

  const PengeringContent({
    Key? key,
    this.items = 5,
    this.title = 'Status Mesin Pengering',
  }) : super(key: key);

  @override
  State<PengeringContent> createState() => _PengeringContentState();
}

class _PengeringContentState extends State<PengeringContent> {
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
      final items = await _db.getAllMachines(type: 'pengering');
      setState(() => _machines = items);
    } catch (e) {
      setState(() => _machines = []);
    }
  }

  Future<void> _loadActiveOrders() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('user_id');
      final orders = await _orderRepo.getAllOrders(userId: userId);

      final List<Order> dryingOrders = orders.where((order) {
        final items = order.items;
        return items.any((item) {
              final name = item.itemName.toLowerCase();
              return item.machineType == 'pengering' ||
                  name.contains('kering') ||
                  name.contains('pengering') ||
                  name.contains('dry');
            }) &&
            order.status.toLowerCase() != 'completed';
      }).toList();

      dryingOrders.sort((a, b) {
        DateTime da = _parseOrderDate(a.orderDate);
        DateTime db = _parseOrderDate(b.orderDate);
        return da.compareTo(db);
      });

      final List<Map<String, dynamic>> expanded = [];
      final db = await _db.database;

      for (final order in dryingOrders) {
        final dryItems = order.items.where((it) {
          final name = it.itemName.toLowerCase();
          return it.machineType == 'pengering' ||
              name.contains('kering') ||
              name.contains('pengering') ||
              name.contains('dry');
        }).toList();

        if (dryItems.isEmpty) {
          expanded.add({'order': order, 'key': 'dry_order_${order.id}_0'});
        } else {
          final totalQty = dryItems.fold<int>(0, (s, it) => s + it.quantity);
          final usageResult = await db.rawQuery(
            '''
            SELECT COUNT(*) as cnt 
            FROM machine_usage_history muh 
            LEFT JOIN machines m ON muh.machine_id = m.id
            WHERE muh.order_id = ? AND muh.status = 'Success' AND (m.machine_type = 'pengering' OR m.machine_type = 'kering' OR muh.machine_name LIKE '%kering%' OR muh.machine_name LIKE '%pengering%' OR muh.machine_name LIKE '%dry%')
            ''',
            [order.id],
          );
          final usedQty = usageResult.isNotEmpty
              ? (usageResult[0]['cnt'] as int)
              : 0;
          final remainingQty = (totalQty - usedQty).clamp(0, 999999);

          for (int i = 0; i < remainingQty; i++) {
            expanded.add({'order': order, 'key': 'dry_order_${order.id}_$i'});
          }
        }
      }

      if (mounted) {
        setState(() {
          _activeOrders = expanded;
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
                      'Antrian Kering (${_activeOrders.length})',
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
                      'Daftar Mesin Pengering',
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
                          color: primaryColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: primaryColor.withOpacity(0.2),
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
            'Tidak ada cucian yang menunggu dikeringkan.',
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
              name: 'Kering 0${index + 1}',
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

    final int minutes = _parseRemainMinutes(remain);
    final bool waSent = entry != null && entry['wa_sent'] == true;
    final bool isError = state == 'ERROR' || state == 'OFFLINE';

    final bool isRunning = state == 'RUNNING' ||
                           state == 'RUN' ||
                           (runState.isNotEmpty &&
                            runState != 'Idle' &&
                            runState != 'Completed' &&
                            runState != 'Ready' &&
                            runState != '-' &&
                            runState != 'unknown');

    final bool isOfflineRunning = isRunning && (
      runState.toLowerCase().contains('offline') ||
      (entry != null && entry['is_offline'] == true) ||
      (remain.contains(':') && remain.length >= 4 && !remain.startsWith('0:'))
    );

    Color iconColor;
    Color iconBg;
    IconData machineIcon = Icons.wb_sunny_rounded;
    Color border;
    Gradient cardGradient;
    String badgeText;
    Color badgeBg;
    Color badgeTextColor;
    Color titleColor;
    Color subColor;
    bool canClick = false;

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
      // OFFLINE RUNNING (Amber / Warm Orange Gradient)
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
    } else if (isRunning) {
      // RUNNING (Blue/Amber Electric Full Gradient)
      cardGradient = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFEFF6FF), Color(0xFFDBEAFE)],
      );
      border = const Color(0xFF93C5FD);
      iconBg = const Color(0xFF2563EB);
      iconColor = Colors.white;
      machineIcon = Icons.wb_sunny_rounded;
      badgeBg = const Color(0xFF1D4ED8);
      badgeTextColor = Colors.white;
      titleColor = const Color(0xFF1E3A8A);
      subColor = const Color(0xFF1D4ED8);
      final String timeText = (remain.isNotEmpty && remain != '--:--') ? ' $remain' : '';
      badgeText = "RUNNING$timeText";
      canClick = true;
    } else if (customerName.isEmpty) {
      // READY (Green Emerald Full Gradient)
      cardGradient = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFF0FDF4), Color(0xFFDCFCE7)],
      );
      border = const Color(0xFF86EFAC);
      iconBg = const Color(0xFF10B981);
      iconColor = Colors.white;
      badgeBg = const Color(0xFF059669);
      badgeTextColor = Colors.white;
      titleColor = const Color(0xFF065F46);
      subColor = const Color(0xFF047857);
      badgeText = "READY";
      canClick = true;
    } else {
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
        badgeBg = const Color(0xFFD97706);
        badgeTextColor = Colors.white;
        titleColor = const Color(0xFF78350F);
        subColor = const Color(0xFFB45309);
        final String timeText = (remain.isNotEmpty && remain != '--:--') ? ' $remain' : '';
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
                        child: Text(
                          badgeText,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w900,
                            color: badgeTextColor,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    displayName,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      color: titleColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    minutes > 0 ? '$remain ($runState)' : (runState == 'Idle' ? 'Siap Digunakan (Idle)' : runState),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: subColor,
                    ),
                  ),
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

    // If machine is ready and empty (Green)
    if (machineStatus == 'ready' && customerName.isEmpty) {
      if (_selectedOrderItem != null) {
        _confirmAndAssign(_selectedOrderItem!, machine.id ?? 0, displayName);
      }
      return;
    }

    // Otherwise, trigger the new 2-button action dialog
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
    final String customerPhone = (entry?['customer_phone'] ?? '').toString();
    final bool waSent = entry?['wa_sent'] == true;
    final bool isLastMachine = entry?['is_last_machine'] != false;
    final List<dynamic> otherMachines = entry?['other_machines'] != null
        ? List<dynamic>.from(entry['other_machines'])
        : [];

    final Order? newOrder = _selectedOrderItem != null
        ? _selectedOrderItem!['order'] as Order
        : null;
    final bool isReplacing = newOrder != null;

    // Check if new customer needs phone number input
    final bool needsPhoneInput =
        isReplacing &&
        (newOrder.customerPhone == null ||
            newOrder.customerPhone!.trim().isEmpty);

    // WA options
    bool sendWa = !waSent; // default checked if not sent yet
    bool isCustomMessage = false;

    final TextEditingController phoneCtrl = TextEditingController(text: '8');
    final TextEditingController msgCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Row(
                children: [
                  Icon(
                    isReplacing
                        ? Icons.swap_horiz_rounded
                        : Icons.info_outline_rounded,
                    color: primaryColor,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isReplacing ? 'Ganti Pelanggan' : 'Detail Pemantauan',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Machine info
                    Text(
                      'Mesin: $displayName',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Pelanggan Aktif: $customerName',
                      style: TextStyle(color: Colors.grey[600], fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Text(
                          'Status WA: ',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Color(0xFF475569),
                          ),
                        ),
                        Text(
                          waSent ? 'Sudah di-WA' : 'Belum di-WA',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: waSent ? const Color(0xFF8B5CF6) : const Color(0xFFF59E0B),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Section 1: Other active machines warning (only if NOT last machine)
                    if (!isLastMachine && otherMachines.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.amber.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.warning_rounded,
                                  color: Colors.amber.shade700,
                                  size: 18,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '$customerName masih memiliki cucian aktif di:',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: Colors.amber.shade900,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            ...otherMachines.map(
                              (m) => Padding(
                                padding: const EdgeInsets.only(
                                  left: 24,
                                  bottom: 2,
                                ),
                                child: Text(
                                  '• $m',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.amber.shade900,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'WA "cucian selesai" akan dikirim otomatis saat cucian terakhir $customerName selesai.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                          fontStyle: FontStyle.italic,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Section 2: WA check (only if last machine)
                    if (isLastMachine) ...[
                      Text(
                        'Ini adalah cucian terakhir $customerName.',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (customerPhone.isNotEmpty) ...[
                        CheckboxListTile(
                          title: Text('Kirim WA selesai ke $customerName'),
                          value: sendWa,
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          activeColor: primaryColor,
                          onChanged: (val) {
                            setModalState(() {
                              sendWa = val ?? false;
                            });
                          },
                        ),
                        if (sendWa) ...[
                          RadioListTile<bool>(
                            title: const Text(
                              'Gunakan template standar',
                              style: TextStyle(fontSize: 13),
                            ),
                            value: false,
                            groupValue: isCustomMessage,
                            contentPadding: EdgeInsets.zero,
                            activeColor: primaryColor,
                            onChanged: (val) {
                              setModalState(() {
                                isCustomMessage = val ?? false;
                              });
                            },
                          ),
                          RadioListTile<bool>(
                            title: const Text(
                              'Ketik pesan sendiri',
                              style: TextStyle(fontSize: 13),
                            ),
                            value: true,
                            groupValue: isCustomMessage,
                            contentPadding: EdgeInsets.zero,
                            activeColor: primaryColor,
                            onChanged: (val) {
                              setModalState(() {
                                isCustomMessage = val ?? true;
                              });
                            },
                          ),
                          if (isCustomMessage) ...[
                            const SizedBox(height: 4),
                            TextField(
                              controller: msgCtrl,
                              maxLines: 2,
                              decoration: InputDecoration(
                                hintText: 'Tulis pesan WhatsApp custom di sini...',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                contentPadding: const EdgeInsets.all(12),
                              ),
                            ),
                          ],
                        ],
                      ] else ...[
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8.0),
                          child: Row(
                            children: [
                              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 16),
                              SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Nomor WA pelanggan tidak terdaftar di sistem.',
                                  style: TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                    ],

                    // Section 3: New Customer info (only if isReplacing)
                    if (isReplacing) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: primaryColor.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: primaryColor.withOpacity(0.2),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Ganti ke Pelanggan Baru:',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: primaryColor,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              newOrder.customerName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (needsPhoneInput) ...[
                        const Text(
                          'Pelanggan baru belum memiliki nomor WA. Masukkan nomor:',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: phoneCtrl,
                          keyboardType: TextInputType.phone,
                          decoration: InputDecoration(
                            labelText: 'Nomor WA',
                            prefixText: '+62 ',
                            prefixStyle: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text(
                    'Batal',
                    style: TextStyle(color: Color(0xFF64748B)),
                  ),
                ),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(ctx); // Close dialog

                    final service = MachineStatusService.instance;
                    final int machineId = machine.id ?? 0;
                    service.setActivating(machineId, true);

                    try {
                      String? customMsg =
                          isCustomMessage && msgCtrl.text.isNotEmpty
                          ? msgCtrl.text
                          : null;

                      if (isReplacing) {
                        String finalPhone = newOrder.customerPhone ?? '';
                        if (needsPhoneInput) {
                          finalPhone = '+62${phoneCtrl.text.trim()}';
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
                          'Mesin pengering ${machine.name} berhasil diganti ke ${newOrder.customerName}!',
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
                          'Mesin pengering ${machine.name} berhasil diselesaikan!',
                        );

                        service.finishAndNotify(
                          entityId: machine.name,
                          sendWa: sendWa,
                          waMessage: customMsg,
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
                        ? StyleConstants.primaryColor
                        : (isLastMachine && sendWa ? StyleConstants.successColor : StyleConstants.primaryColor),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isReplacing
                            ? Icons.swap_horiz_rounded
                            : (sendWa ? Icons.send_rounded : Icons.check_circle_rounded),
                        size: 16,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isReplacing
                            ? 'Ganti Pelanggan'
                            : (isLastMachine
                                ? (sendWa ? 'Selesaikan & Kirim WA' : 'Selesaikan Mesin')
                                : 'Selesaikan Mesin Ini'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
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

    // 2. Fire-and-forget the API call in the background
    service.startMachineMonitoring(
      entityId: machine.name,
      customerName: name.isNotEmpty ? name : 'Pelanggan',
      customerPhone: phone.isNotEmpty ? phone : null,
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
              return it.machineType == 'pengering' ||
                  name.contains('kering') ||
                  name.contains('pengering') ||
                  name.contains('dry');
            })
            .fold<int>(0, (s, it) => s + it.quantity);

        final db = await _db.database;
        final usageCount = await db.rawQuery(
          '''
          SELECT COUNT(*) as cnt 
          FROM machine_usage_history muh 
          LEFT JOIN machines m ON muh.machine_id = m.id
          WHERE muh.order_id = ? AND muh.status = 'Success' AND (m.machine_type = 'pengering' OR muh.machine_name LIKE '%pengering%' OR muh.machine_name LIKE '%dry%')
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
          (await _db.getMachine(machineId))?.name ?? 'Kering $machineId';

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
