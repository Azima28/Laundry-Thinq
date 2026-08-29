import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import '../../services/machine_status_service.dart';
import '../../transactions/order_repository.dart';
import '../../transactions/user_repository.dart';
import '../../utils/globals.dart';
import '../../database/models/order_model.dart';
import '../../database/models/database_helper.dart';
import '../../database/models/machine_model.dart';
import '../../services/notification_service.dart';
import '../../utils/style_constants.dart';
import '../../utils/tub_note_helper.dart';
import '../../services/printer_service.dart';
import 'machine_label_dialog.dart';

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
  final UserRepository _userRepo = UserRepository();
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
        final st = order.status.toLowerCase();
        return items.any((item) {
              final name = item.itemName.toLowerCase();
              return item.machineType == 'pengering' ||
                  name.contains('kering') ||
                  name.contains('pengering') ||
                  name.contains('dry');
            }) &&
            st != 'completed' &&
            st != 'bypass clear' &&
            st != 'cancelled';
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
          expanded.add({
            'order': order,
            'key': 'dry_order_${order.id}_0',
            'cycle_index': 0,
            'total_cycles': 1,
            'tub_note': '',
          });
        } else {
          final totalQty = dryItems.fold<int>(0, (s, it) => s + it.quantity);
          final usageResult = await db.rawQuery(
            '''
            SELECT COUNT(*) as cnt
            FROM machine_usage_history muh
            LEFT JOIN machines m ON muh.machine_id = m.id
            WHERE muh.order_id = ?
              AND (muh.status = 'Success' OR muh.status = 'Bypass Clear')
              AND (
                (m.id IS NOT NULL AND (m.machine_type = 'pengering' OR m.machine_type = 'kering'))
                OR muh.machine_name LIKE '%kering%'
                OR muh.machine_name LIKE '%pengering%'
                OR muh.machine_name LIKE '%dry%'
                OR muh.machine_name LIKE '%Bypass Clear (Pengering)%'
              )
            ''',
            [order.id],
          );
          final usedQty = usageResult.isNotEmpty
              ? (usageResult[0]['cnt'] as int)
              : 0;
          final remainingQty = (totalQty - usedQty).clamp(0, 999999);

          // Extract per-tub notes using TubNoteHelper
          final allDryNotes = TubNoteHelper.getOrderTubNotes(order, machineType: 'pengering');

          for (int i = 0; i < remainingQty; i++) {
            final currentCycleIdx = usedQty + i;
            final tubNote = currentCycleIdx < allDryNotes.length ? allDryNotes[currentCycleIdx] : '';
            expanded.add({
              'order': order,
              'key': 'dry_order_${order.id}_$i',
              'cycle_index': currentCycleIdx,
              'total_cycles': totalQty,
              'tub_note': tubNote,
            });
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

  /// Modal Dialog: Clear Antrean Pengering (Bypass Clear) dengan proteksi Password Admin & Multi-Select
  Future<void> _showClearQueueDialog() async {
    if (_activeOrders.isEmpty) return;

    final Set<String> selectedKeys = _activeOrders.map((e) => e['key'] as String).toSet();
    final passwordCtrl = TextEditingController();
    bool isObscure = true;
    String? errorMessage;
    bool isProcessing = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final int totalItems = _activeOrders.length;
            final int selectedCount = selectedKeys.length;
            final bool isAllSelected = selectedCount == totalItems && totalItems > 0;

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              actionsPadding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.cleaning_services_rounded, color: Color(0xFFDC2626), size: 24),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Clear Antrean Pengering (Bypass Clear)',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16.5, color: Color(0xFF0F172A)),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Pilih antrean yang ingin dibersihkan & masukkan password admin',
                          style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: isProcessing ? null : () => Navigator.pop(dialogCtx),
                    icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B), size: 20),
                    tooltip: 'Tutup',
                  ),
                ],
              ),
              content: SizedBox(
                width: 540,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Divider(height: 1, color: Color(0xFFE2E8F0)),
                    const SizedBox(height: 14),

                    // Toolbar: Counter & Select All / Unselect All
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: selectedCount > 0 ? const Color(0xFFEFF6FF) : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: selectedCount > 0 ? const Color(0xFFBFDBFE) : const Color(0xFFCBD5E1)),
                          ),
                          child: Text(
                            'Terpilih: $selectedCount dari $totalItems antrean',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: selectedCount > 0 ? const Color(0xFF1D4ED8) : const Color(0xFF64748B),
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: isProcessing
                              ? null
                              : () {
                                  setModalState(() {
                                    if (isAllSelected) {
                                      selectedKeys.clear();
                                    } else {
                                      selectedKeys.addAll(_activeOrders.map((e) => e['key'] as String));
                                    }
                                  });
                                },
                          icon: Icon(
                            isAllSelected ? Icons.deselect_rounded : Icons.select_all_rounded,
                            size: 16,
                            color: const Color(0xFF4E80EE),
                          ),
                          label: Text(
                            isAllSelected ? 'Batal Pilih Semua' : 'Pilih Semua',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF4E80EE)),
                          ),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // List of Queue Items with Checkboxes
                    Container(
                      constraints: const BoxConstraints(maxHeight: 220),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.all(8),
                        itemCount: _activeOrders.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 6),
                        itemBuilder: (ctx, idx) {
                          final item = _activeOrders[idx];
                          final key = item['key'] as String;
                          final order = item['order'] as Order;
                          final cycleIdx = (item['cycle_index'] as int? ?? 0) + 1;
                          final totalCycles = item['total_cycles'] as int? ?? 1;
                          final isChecked = selectedKeys.contains(key);
                          final tubNote = item['tub_note'] as String? ?? '';

                          return InkWell(
                            onTap: isProcessing
                                ? null
                                : () {
                                    setModalState(() {
                                      if (isChecked) {
                                        selectedKeys.remove(key);
                                      } else {
                                        selectedKeys.add(key);
                                      }
                                    });
                                  },
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: isChecked ? Colors.white : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isChecked ? const Color(0xFF93C5FD) : const Color(0xFFE2E8F0),
                                  width: isChecked ? 1.5 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Checkbox(
                                    value: isChecked,
                                    onChanged: isProcessing
                                        ? null
                                        : (val) {
                                            setModalState(() {
                                              if (val == true) {
                                                selectedKeys.add(key);
                                              } else {
                                                selectedKeys.remove(key);
                                              }
                                            });
                                          },
                                    activeColor: const Color(0xFFDC2626),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              order.customerName,
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFEFF6FF),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                'Nota #${order.id}',
                                                style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF2563EB)),
                                              ),
                                            ),
                                            if (totalCycles > 1) ...[
                                              const SizedBox(width: 4),
                                              Text(
                                                '• Siklus $cycleIdx/$totalCycles',
                                                style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                                              ),
                                            ],
                                          ],
                                        ),
                                        if (tubNote.isNotEmpty) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            'Catatan: $tubNote',
                                            style: const TextStyle(fontSize: 11, color: Color(0xFFD97706), fontStyle: FontStyle.italic),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Admin Password Input
                    TextField(
                      controller: passwordCtrl,
                      obscureText: isObscure,
                      enabled: !isProcessing,
                      decoration: InputDecoration(
                        labelText: 'Password Admin untuk Konfirmasi',
                        hintText: 'Masukkan password admin...',
                        prefixIcon: const Icon(Icons.lock_outline_rounded, color: Color(0xFF64748B), size: 20),
                        suffixIcon: IconButton(
                          icon: Icon(
                            isObscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                            color: const Color(0xFF64748B),
                            size: 20,
                          ),
                          onPressed: () => setModalState(() => isObscure = !isObscure),
                        ),
                        errorText: errorMessage,
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFDC2626), width: 2)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline_rounded, size: 14, color: Color(0xFF64748B)),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Status antrean terpilih akan diubah menjadi Bypass Clear. Riwayat pesanan & data keuangan tetap aman.',
                            style: TextStyle(fontSize: 11, color: Color(0xFF64748B), height: 1.3),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                OutlinedButton(
                  onPressed: isProcessing ? null : () => Navigator.pop(dialogCtx),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Batal', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
                ),
                ElevatedButton.icon(
                  onPressed: isProcessing
                      ? null
                      : () async {
                          if (selectedKeys.isEmpty) {
                            setModalState(() {
                              errorMessage = 'Pilih minimal 1 antrean untuk dibersihkan';
                            });
                            return;
                          }

                          final pwd = passwordCtrl.text.trim();
                          if (pwd.isEmpty) {
                            setModalState(() {
                              errorMessage = 'Password admin tidak boleh kosong';
                            });
                            return;
                          }

                          setModalState(() {
                            isProcessing = true;
                            errorMessage = null;
                          });

                          final isVerified = await _userRepo.verifyAdminPassword(pwd);
                          if (!isVerified) {
                            setModalState(() {
                              isProcessing = false;
                              errorMessage = 'Password admin salah!';
                            });
                            return;
                          }

                          // Process Bypass Clear for all selected items
                          try {
                            final db = await _db.database;
                            final now = DateTime.now().toIso8601String();
                            final selectedItems = _activeOrders.where((it) => selectedKeys.contains(it['key'])).toList();
                            final Set<int> affectedOrderIds = {};

                            for (final item in selectedItems) {
                              final order = item['order'] as Order;
                              if (order.id != null) {
                                affectedOrderIds.add(order.id!);
                              }

                              await db.insert('machine_usage_history', {
                                'order_id': order.id ?? 0,
                                'machine_id': 0,
                                'machine_name': 'Bypass Clear (Pengering)',
                                'customer_name': order.customerName,
                                'status': 'Bypass Clear',
                                'error_message': 'Antrean dibersihkan secara manual oleh Admin (Bypass Clear)',
                                'started_at': now,
                                'created_at': now,
                              });
                            }

                            // Check all affected orders if all cycles are completed/bypassed
                            for (final orderId in affectedOrderIds) {
                              final orderRes = await db.query('orders', where: 'id = ?', whereArgs: [orderId]);
                              if (orderRes.isNotEmpty) {
                                final currentStatus = (orderRes.first['status'] as String? ?? '').toLowerCase();
                                if (currentStatus != 'completed') {
                                  // Check total items vs total history
                                  final orderItems = await db.query('order_items', where: 'order_id = ?', whereArgs: [orderId]);
                                  int totalCycles = 0;
                                  for (var oi in orderItems) {
                                    final name = (oi['item_name'] as String? ?? '').toLowerCase();
                                    final bool isWash = name.contains('cuci') || name.contains('wash');
                                    final bool isDry = name.contains('kering') || name.contains('pengering') || name.contains('dry');
                                    if (isWash && isDry) {
                                      totalCycles += ((oi['quantity'] as int? ?? 1) * 2);
                                    } else if (isWash || isDry) {
                                      totalCycles += (oi['quantity'] as int? ?? 1);
                                    }
                                  }

                                  final histRes = await db.rawQuery(
                                    "SELECT COUNT(*) as cnt FROM machine_usage_history WHERE order_id = ? AND (status = 'Success' OR status = 'Bypass Clear')",
                                    [orderId],
                                  );
                                  final totalResolved = histRes.isNotEmpty ? (histRes[0]['cnt'] as int) : 0;

                                  if (totalResolved >= totalCycles) {
                                    // Check if all were Bypass Clear
                                    final successRes = await db.rawQuery(
                                      "SELECT COUNT(*) as cnt FROM machine_usage_history WHERE order_id = ? AND status = 'Success'",
                                      [orderId],
                                    );
                                    final successCount = successRes.isNotEmpty ? (successRes[0]['cnt'] as int) : 0;
                                    final newStatus = successCount == 0 ? 'Bypass Clear' : 'Completed';

                                    await db.update(
                                      'orders',
                                      {'status': newStatus},
                                      where: 'id = ?',
                                      whereArgs: [orderId],
                                    );
                                  }
                                }
                              }
                            }

                            if (dialogCtx.mounted) {
                              Navigator.pop(dialogCtx);
                            }

                            await _loadActiveOrders();

                            if (mounted) {
                              Globals.showSuccessSnackBar('${selectedItems.length} antrean berhasil di-bypass clear!');
                            }
                          } catch (e) {
                            setModalState(() {
                              isProcessing = false;
                              errorMessage = 'Gagal memproses: $e';
                            });
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFDC2626),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                  icon: isProcessing
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.cleaning_services_rounded, color: Colors.white, size: 18),
                  label: Text(
                    isProcessing ? 'Memproses...' : 'Clear (${selectedKeys.length}) Antrean',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
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
                      'Antrian Pengering (${_activeOrders.length})',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_activeOrders.isNotEmpty)
                          Tooltip(
                            message: 'Clear Antrean (Butuh Password Admin)',
                            child: InkWell(
                              onTap: _showClearQueueDialog,
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEE2E2),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: const Color(0xFFFECACA)),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.cleaning_services_rounded, size: 14, color: Color(0xFFDC2626)),
                                    SizedBox(width: 4),
                                    Text(
                                      'Clear',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFFDC2626),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.refresh_rounded, size: 20),
                          tooltip: 'Muat Ulang Antrean',
                          onPressed: _loadActiveOrders,
                        ),
                      ],
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
                    const SizedBox(width: 16),
                    OutlinedButton.icon(
                      onPressed: () => MachineLabelDialog.show(
                        context,
                        machineName: 'Kering 01',
                        serviceType: 'Kering Saja',
                      ),
                      icon: const Icon(Icons.label_important_outline_rounded, size: 16),
                      label: const Text('Cetak Label Manual', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
                            Builder(
                              builder: (_) {
                                final int selCycleIdx = (_selectedOrderItem!['cycle_index'] as int?) ?? 0;
                                final int selTotalCycles = (_selectedOrderItem!['total_cycles'] as int?) ?? 1;
                                final String selTubNote = (_selectedOrderItem!['tub_note'] ?? '').toString();
                                final String cycleInfo = selTotalCycles > 1
                                    ? ' (Kering ${selCycleIdx + 1}/$selTotalCycles${selTubNote.isNotEmpty ? " • ⚖️ $selTubNote" : ""})'
                                    : (selTubNote.isNotEmpty ? ' (⚖️ $selTubNote)' : '');

                                return Text(
                                  'Pilih mesin untuk: ${_selectedOrderItem!['order'].customerName}$cycleInfo',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: primaryColor,
                                  ),
                                );
                              },
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
    final int cycleIdx = (item['cycle_index'] as int?) ?? 0;
    final int totalCycles = (item['total_cycles'] as int?) ?? 1;
    final String tubNote = (item['tub_note'] ?? '').toString();
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
                          Row(
                            children: [
                              Text(
                                totalCycles > 1
                                    ? 'Nota #${order.id} • Kering ${cycleIdx + 1}/$totalCycles'
                                    : 'Nota #${order.id}',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF475569),
                                ),
                              ),
                              if (tubNote.isNotEmpty) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFFBEB),
                                    borderRadius: BorderRadius.circular(5),
                                    border: Border.all(color: const Color(0xFFFDE68A)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.scale_rounded, size: 11, color: Color(0xFFD97706)),
                                      const SizedBox(width: 3),
                                      Text(
                                        tubNote,
                                        style: const TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w900,
                                          color: Color(0xFFB45309),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
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
    if (_isLoading && _machines.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Sedang memuat data status mesin...',
              style: TextStyle(fontSize: 13, color: Color(0xFF64748B), fontWeight: FontWeight.bold),
            ),
          ],
        ),
      );
    }

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

    final bool waSent = entry != null && entry['wa_sent'] == true;
    final bool isError = state == 'ERROR' || state == 'OFFLINE';

    final bool isPause = runState.toLowerCase().contains('pause') ||
        state.toLowerCase().contains('pause');

    final bool isRelayOn = runState.toLowerCase().contains('relay on') ||
        runState.toLowerCase().contains('on') ||
        runState.toLowerCase().contains('standby') ||
        state.contains('ON') ||
        (entry != null && entry['is_relay_on'] == true);

    final bool isRunning = ((state == 'RUNNING' ||
                            state == 'RUN' ||
                            (runState.isNotEmpty &&
                             runState != 'Idle' &&
                             runState != 'Completed' &&
                             runState != 'Ready' &&
                             runState != 'Relay ON' &&
                             runState != 'Standby' &&
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

    Color iconColor;
    Color iconBg;
    IconData machineIcon = isDetecting ? Icons.scale_rounded : Icons.wb_sunny_rounded;
    Color border;
    Gradient cardGradient;
    String badgeText;
    Color badgeBg;
    Color badgeTextColor;
    Color titleColor;
    Color subColor;
    bool canClick = false;

    if (isError) {
      // ERROR / OFFLINE (Red Full Gradient)
      cardGradient = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFEF2F2), Color(0xFFFEE2E2)],
      );
      border = const Color(0xFFFCA5A5);
      iconBg = const Color(0xFFEF4444);
      iconColor = Colors.white;
      machineIcon = (state == 'OFFLINE') ? Icons.cloud_off_rounded : Icons.error_outline_rounded;
      badgeBg = const Color(0xFFDC2626);
      badgeTextColor = Colors.white;
      titleColor = const Color(0xFF7F1D1D);
      subColor = const Color(0xFF991B1B);
      badgeText = (state == 'OFFLINE') ? "OFFLINE" : "ERROR";
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
      // RUNNING (Blue/Amber Electric Full Gradient)
      cardGradient = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFEFF6FF), Color(0xFFDBEAFE)],
      );
      border = const Color(0xFF93C5FD);
      iconBg = const Color(0xFF2563EB);
      iconColor = Colors.white;
      machineIcon = isDetecting ? Icons.scale_rounded : Icons.wb_sunny_rounded;
      badgeBg = const Color(0xFF1D4ED8);
      badgeTextColor = Colors.white;
      titleColor = const Color(0xFF1E3A8A);
      subColor = const Color(0xFF1D4ED8);
      final String timeText = (remain.isNotEmpty && remain != '--:--') ? ' $remain' : '';
      badgeText = isDetecting ? "MENIMBANG" : "RUNNING$timeText";
      canClick = true;
    } else if (customerName.isEmpty) {
      if (isRelayOn) {
        // RELAY ON STANDBY (Amber / Warm Orange Full Gradient)
        cardGradient = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFFBEB), Color(0xFFFEF3C7)],
        );
        border = const Color(0xFFF59E0B);
        iconBg = const Color(0xFFD97706);
        iconColor = Colors.white;
        machineIcon = Icons.bolt_rounded;
        badgeBg = const Color(0xFFD97706);
        badgeTextColor = Colors.white;
        titleColor = const Color(0xFF78350F);
        subColor = const Color(0xFFB45309);
        final String timeText = (remain.isNotEmpty && remain != '--:--') ? ' $remain' : '';
        badgeText = "RELAY ON$timeText";
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
        machineIcon = Icons.wb_sunny_rounded;
        badgeBg = const Color(0xFF059669);
        badgeTextColor = Colors.white;
        titleColor = const Color(0xFF065F46);
        subColor = const Color(0xFF047857);
        badgeText = "READY";
        canClick = true;
      }
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

    if (customerName.isEmpty && !isRunning && !isPause && !isError && !isOfflineRunning) {
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
            onTap: (isActivating || !canClick || _isLoading)
                ? null
                : () => _handleMachineTap(
                    machine,
                    displayName,
                    machineStatus,
                    state,
                    entry,
                  ),
            onDoubleTap: (isActivating || _isLoading)
                ? null
                : () => _confirmForceTurnOffMachine(
                    machine,
                    displayName,
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
                    isDetecting
                        ? 'Menimbang Beban (Detecting)...'
                        : (isError
                            ? (state == 'OFFLINE' ? 'Mesin Terputus (Offline)' : 'Gangguan Mesin (Error)')
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
                                        : (customerName.isEmpty && isRelayOn
                                            ? (remain.isNotEmpty && remain != '--:--'
                                                ? 'Stopkontak Menyala ($remain tersisa)'
                                                : 'Stopkontak Menyala (Standby)')
                                            : ((runState == 'Idle' || runState == 'Standby' || runState == 'Initial')
                                                ? (customerName.isNotEmpty
                                                    ? (waSent ? 'Selesai (Sudah di-WA)' : 'Selesai (Menunggu Tindakan)')
                                                    : 'Siap Digunakan (Idle)')
                                                : runState)))))),
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

  Future<void> _confirmForceTurnOffMachine(
    MachineModel machine,
    String displayName,
    dynamic entry,
  ) async {
    final String customerName = (entry?['customer_name'] ?? '').toString();
    final String state = (entry?['state'] ?? 'Ready').toString().toUpperCase();
    final String runState = (entry?['run_state'] ?? 'Idle').toString();
    final String remain = (entry?['remain_time'] ?? '').toString();
    final bool isRelayOn = (entry?['is_relay_on'] == true) || runState.toLowerCase().contains('relay on');

    String statusDescription = 'Siap Digunakan (Ready)';
    if (state == 'RUNNING' || state == 'RUN' || (runState != 'Idle' && runState != 'Ready' && runState != '-')) {
      statusDescription = 'Sedang Berjalan (${remain.isNotEmpty && remain != "--:--" ? remain : runState})';
    } else if (isRelayOn) {
      statusDescription = 'Stopkontak Menyala / Standby';
    } else if (customerName.isNotEmpty) {
      statusDescription = 'Booking / Terisi ($customerName)';
    }

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 16,
          backgroundColor: Colors.white,
          child: Container(
            width: 440,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEE2E2),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.power_settings_new_rounded,
                        color: Color(0xFFDC2626),
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Matikan Mesin Pengering',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            displayName,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFDC2626),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Status Saat Ini:',
                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                          ),
                          Flexible(
                            child: Text(
                              statusDescription,
                              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                              textAlign: TextAlign.end,
                            ),
                          ),
                        ],
                      ),
                      if (customerName.isNotEmpty && customerName != '-') ...[
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Pelanggan:',
                              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                            ),
                            Text(
                              customerName,
                              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Color(0xFF2563EB)),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Apakah Anda yakin ingin mematikan daya stopkontak dan menghentikan mesin ini secara paksa ke status OFF / Ready?',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF475569),
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          side: const BorderSide(color: Color(0xFFCBD5E1)),
                        ),
                        child: const Text(
                          'Batal',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.pop(ctx, true),
                        icon: const Icon(Icons.power_settings_new_rounded, size: 18),
                        label: const Text(
                          'Ya, Matikan (OFF)',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFDC2626),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (confirmed == true) {
      final service = MachineStatusService.instance;
      service.setActivating(machine.id ?? 0, true);

      // Optimistic status update to OFF / Ready
      service.updateMachineStatusOptimistic(
        machine.name,
        status: 'ready',
        customerName: '',
        customerPhone: '',
        state: 'Ready',
        runState: 'Idle',
      );

      final String targetEntity = machine.name.isNotEmpty ? machine.name : displayName;
      final res = await service.stopMachineMonitoring(entityId: targetEntity);

      service.setActivating(machine.id ?? 0, false);

      if (res['success'] == true) {
        Globals.showSuccessSnackBar('Mesin $displayName berhasil dimatikan ke status OFF (Ready).');
      } else {
        Globals.showWarningSnackBar('Mesin $displayName diubah ke status Ready (${res['error'] ?? 'Lokal'}).');
      }

      await _loadActiveOrders();
    }
  }

  Future<void> _handleMachineTap(
    MachineModel machine,
    String displayName,
    String machineStatus,
    String state,
    dynamic entry,
  ) async {
    if (_isLoading) {
      Globals.showWarningSnackBar('Sedang memuat data antrean dan status pengering, mohon tunggu sebentar...');
      return;
    }

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

    final service = MachineStatusService.instance;

    // 1. If machine is empty (no customer assigned)
    if (customerName.isEmpty) {
      if (_selectedOrderItem != null) {
        _confirmAndAssign(_selectedOrderItem!, machine.id ?? 0, displayName);
      }
      return;
    }

    // 2. If machine is in 5-minute BOOKING window / Priority Booking -> LOCKED
    final bool isPriorityBooking = service.isBookingPriorityActive(machine.name) ||
        service.isBookingPriorityActive(displayName);

    if (isBooking || (isPriorityBooking && customerName.isNotEmpty)) {
      final remainStr = (entry?['remain_time'] ?? '').toString();
      final String timeInfo = isPriorityBooking
          ? ' (${service.getBookingPriorityRemainingFormatted(machine.name)} tersisa)'
          : (remainStr.isNotEmpty && remainStr != '--:--' ? ' ($remainStr tersisa)' : '');
      Globals.showWarningSnackBar(
        'Mesin $displayName sedang dalam masa Prioritas Booking$timeInfo untuk $customerName. Mesin terkunci selama periode 5 menit untuk persiapan.',
      );
      return;
    }

    // 3. Otherwise (Machine is RUNNING, DETECTING, COMPLETED, or OCCUPIED after 5 min) -> trigger action dialog
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

    // 1. Cross-check active machines across all live in-memory IoT statuses (washers & dryers)
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
            if (cName.isNotEmpty && cName != '-' && cName != 'null') {
              otherMachinesSet.add(mDisp);
            }
          }
        }
      }
    });

    // 2. Query active orders & pending cycles in SQLite database
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

          int orderWashCount = 0;
          int orderDryCount = 0;

          for (final it in items) {
            final qty = (it['quantity'] as num?)?.toInt() ?? 1;
            final mType = (it['machine_type'] as String?)?.toLowerCase();
            final iName = (it['item_name'] as String?)?.toLowerCase() ?? '';
            if (mType == 'cuci' || iName.contains('cuci') || iName.contains('wash')) {
              orderWashCount += qty;
            } else if (mType == 'pengering' || iName.contains('kering') || iName.contains('pengering') || iName.contains('dry')) {
              orderDryCount += qty;
            }
          }

          if ((orderWashCount + orderDryCount) == 0) continue;

          final usedWashRows = await db.rawQuery(
            '''
            SELECT COUNT(*) as cnt
            FROM machine_usage_history muh
            LEFT JOIN machines m ON muh.machine_id = m.id
            WHERE muh.order_id = ? AND muh.status = 'Success' AND (m.machine_type = 'cuci' OR muh.machine_name LIKE '%cuci%' OR muh.machine_name LIKE '%wash%')
            ''',
            [orderId],
          );
          final usedWashCycles = usedWashRows.isNotEmpty ? (usedWashRows.first['cnt'] as int? ?? 0) : 0;

          final usedDryRows = await db.rawQuery(
            '''
            SELECT COUNT(*) as cnt
            FROM machine_usage_history muh
            LEFT JOIN machines m ON muh.machine_id = m.id
            WHERE muh.order_id = ? AND muh.status = 'Success' AND (m.machine_type = 'pengering' OR muh.machine_name LIKE '%kering%' OR muh.machine_name LIKE '%pengering%' OR muh.machine_name LIKE '%dry%')
            ''',
            [orderId],
          );
          final usedDryCycles = usedDryRows.isNotEmpty ? (usedDryRows.first['cnt'] as int? ?? 0) : 0;

          final remainingWash = (orderWashCount - usedWashCycles).clamp(0, 999999);
          final remainingDry = (orderDryCount - usedDryCycles).clamp(0, 999999);
          final totalRemaining = remainingWash + remainingDry;

          if (totalRemaining > 0) {
            pendingOrderCycles += totalRemaining;
            if (remainingDry > 0) {
              pendingBreakdowns.add('$remainingDry Pengeringan');
            }
            if (remainingWash > 0) {
              pendingBreakdowns.add('$remainingWash Cuci');
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

    final prefs = await SharedPreferences.getInstance();
    final bizName = prefs.getString('biz_name')?.trim();
    final displayBizName = (bizName != null && bizName.isNotEmpty) ? bizName : 'Smart Laundry';

    final String defaultTemplate =
        "Halo Kak $customerName, cucian Anda di $displayBizName sudah selesai dikeringkan dan siap diambil! Silakan mampir untuk pengambilan ya. Terima kasih! 😊";

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
                                      ? 'Selesaikan pengeringan aktif & alihkan ke pesanan antrian'
                                      : 'Selesaikan pengeringan & kirim notifikasi WhatsApp ke pelanggan',
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
                                              'Semua proses pengeringan untuk $customerName telah tuntas. Notifikasi WhatsApp siap dikirimkan ke pelanggan.',
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
                                    'Mesin pengering ${machine.name} berhasil diganti ke ${newOrder.customerName}!',
                                  );
                                  setState(() {
                                    _selectedOrderItem = null;
                                  });

                                  // Call replaceCustomer in background
                                  service.setBookingPriority(machine.name, durationSeconds: 300);
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
                                  service.clearBookingPriority(machine.name);
                                  Globals.showSuccessSnackBar(
                                    'Mesin pengering ${machine.name} berhasil diselesaikan!',
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

    // 2. Fire-and-forget the API call in the background (uses admin configured dryer duration or Always ON)
    service.setBookingPriority(machine.name, durationSeconds: 300);
    service.startMachineMonitoring(
      entityId: machine.name,
      customerName: name.isNotEmpty ? name : 'Pelanggan',
      customerPhone: phone.isNotEmpty ? phone : null,
      durationMinutes: 0, // 0 tells backend to use admin configured dryer duration (e.g. 45 min or Always ON)
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

  Future<void> _confirmAndAssign(
    Map<String, dynamic> item,
    int machineId,
    String machineName,
  ) async {
    if (_isLoading) {
      Globals.showWarningSnackBar('Sedang memuat data antrean dan status pengering, mohon tunggu sebentar...');
      return;
    }

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

    final int selCycleIdx = (item['cycle_index'] as int?) ?? 0;
    final int selTotalCycles = (item['total_cycles'] as int?) ?? 1;
    final String selTubNote = (item['tub_note'] ?? '').toString();
    final String cycleInfo = selTotalCycles > 1
        ? ' (Pengering ${selCycleIdx + 1}/$selTotalCycles${selTubNote.isNotEmpty ? " • ⚖️ $selTubNote" : ""})'
        : (selTubNote.isNotEmpty ? ' (⚖️ $selTubNote)' : '');

    // Auto-detect service type from order
    bool hasCuci = false;
    bool hasKering = false;
    bool hasGosok = false;
    for (var it in order.items) {
      final name = it.itemName.toLowerCase();
      final mType = (it.machineType ?? '').toLowerCase();
      if (mType == 'cuci' || name.contains('cuci') || name.contains('wash')) hasCuci = true;
      if (mType == 'pengering' || name.contains('kering') || name.contains('dry')) hasKering = true;
      if (mType == 'gosok' || mType == 'iron' || name.contains('gosok') || name.contains('setrika') || name.contains('lipat')) hasGosok = true;
    }

    String defaultService = 'Kering Saja';
    if (hasCuci && hasKering && hasGosok) {
      defaultService = 'Cuci Kering Lipat';
    } else if (hasCuci && hasKering) {
      defaultService = 'Cuci Kering';
    } else if (hasKering) {
      defaultService = 'Kering Saja';
    } else if (hasCuci) {
      defaultService = 'Cuci Saja';
    }

    bool printLabel = false;
    String selectedService = defaultService;
    final TextEditingController labelMachineCtrl = TextEditingController(text: machineName);
    final TextEditingController labelCustomerCtrl = TextEditingController(text: order.customerName);
    final TextEditingController labelNoteCtrl = TextEditingController(text: selTubNote);
    final TextEditingController customServiceCtrl = TextEditingController();

    final List<String> serviceOptions = [
      'Cuci Kering',
      'Cuci Saja',
      'Cuci Kering Lipat',
      'Kering Saja',
      'Setrika',
      'Lainnya (Ketik Custom)',
    ];
    if (!serviceOptions.contains(selectedService)) {
      selectedService = 'Lainnya (Ketik Custom)';
      customServiceCtrl.text = defaultService;
    }

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setModalState) {
            final now = DateTime.now();
            final dateStr = '${now.day} ${['Jan','Feb','Mar','Apr','Mei','Jun','Jul','Agu','Sep','Okt','Nov','Des'][now.month - 1]}';
            final String effectiveService = selectedService == 'Lainnya (Ketik Custom)'
                ? (customServiceCtrl.text.trim().isNotEmpty ? customServiceCtrl.text.trim() : 'Kering Saja')
                : selectedService;

            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
              elevation: 20,
              backgroundColor: Colors.white,
              child: Container(
                width: printLabel ? 540 : 460,
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFD97706).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.wb_sunny_rounded, color: Color(0xFFD97706), size: 24),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Konfirmasi Pemakaian Mesin',
                                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: Color(0xFF0F172A)),
                              ),
                              Text(
                                '$machineName • ${order.customerName}$cycleInfo',
                                style: const TextStyle(fontSize: 12.5, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(height: 1, color: Color(0xFFE2E8F0)),
                    const SizedBox(height: 14),

                    // Label Print Toggle Switch Card
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: printLabel ? const Color(0xFFEFF6FF) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: printLabel ? const Color(0xFF93C5FD) : const Color(0xFFE2E8F0),
                          width: printLabel ? 1.5 : 1.0,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: printLabel ? StyleConstants.primaryColor : const Color(0xFFCBD5E1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.label_important_rounded, size: 16, color: Colors.white),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Cetak Label Mesin',
                                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Color(0xFF0F172A)),
                                ),
                                Text(
                                  'Cetak tiket tempel pakaian saat mesin dinyalakan',
                                  style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                ),
                              ],
                            ),
                          ),
                          Switch.adaptive(
                            value: printLabel,
                            activeThumbColor: StyleConstants.primaryColor,
                            onChanged: (val) => setModalState(() => printLabel = val),
                          ),
                        ],
                      ),
                    ),

                    // Expanded Label Customizer & Visual Preview
                    if (printLabel) ...[
                      const SizedBox(height: 14),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Left Form Inputs
                          Expanded(
                            flex: 52,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('JENIS LAYANAN:', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: Color(0xFF475569))),
                                const SizedBox(height: 4),
                                Container(
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFFCBD5E1)),
                                  ),
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: selectedService,
                                      isExpanded: true,
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                                      items: serviceOptions.map((opt) => DropdownMenuItem(value: opt, child: Text(opt))).toList(),
                                      onChanged: (val) {
                                        if (val != null) setModalState(() => selectedService = val);
                                      },
                                    ),
                                  ),
                                ),
                                if (selectedService == 'Lainnya (Ketik Custom)') ...[
                                  const SizedBox(height: 6),
                                  Container(
                                    height: 34,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: StyleConstants.primaryColor),
                                    ),
                                    padding: const EdgeInsets.symmetric(horizontal: 8),
                                    child: TextField(
                                      controller: customServiceCtrl,
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                                      decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 8), hintText: 'Nama layanan custom...'),
                                      onChanged: (_) => setModalState(() {}),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 10),

                                const Text('NAMA MESIN:', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: Color(0xFF475569))),
                                const SizedBox(height: 4),
                                Container(
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFFCBD5E1)),
                                  ),
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  child: TextField(
                                    controller: labelMachineCtrl,
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                                    decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 8)),
                                    onChanged: (_) => setModalState(() {}),
                                  ),
                                ),
                                const SizedBox(height: 10),

                                const Text('NAMA PELANGGAN:', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: Color(0xFF475569))),
                                const SizedBox(height: 4),
                                Container(
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFFCBD5E1)),
                                  ),
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  child: TextField(
                                    controller: labelCustomerCtrl,
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                                    decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 8)),
                                    onChanged: (_) => setModalState(() {}),
                                  ),
                                ),
                                const SizedBox(height: 10),

                                const Text('CATATAN (OPSIONAL):', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: Color(0xFF475569))),
                                const SizedBox(height: 4),
                                Container(
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFFCBD5E1)),
                                  ),
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  child: TextField(
                                    controller: labelNoteCtrl,
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                                    decoration: const InputDecoration(
                                      border: InputBorder.none,
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(vertical: 8),
                                      hintText: 'Misal: Pisah luntur / Jangan dicampur...',
                                    ),
                                    onChanged: (_) => setModalState(() {}),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 14),

                          // Right Label Preview (Exact User Ticket Outline)
                          Expanded(
                            flex: 48,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('PREVIEW TIKET:', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: StyleConstants.textMuted)),
                                const SizedBox(height: 4),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.black, width: 2.5),
                                    boxShadow: [
                                      BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 6, offset: const Offset(0, 2)),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        labelMachineCtrl.text.isNotEmpty ? labelMachineCtrl.text : machineName,
                                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: Colors.black),
                                      ),
                                      const SizedBox(height: 12),
                                      Center(
                                        child: Text(
                                          labelCustomerCtrl.text.isNotEmpty ? labelCustomerCtrl.text.toUpperCase() : 'NAMA PELANGGAN',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 16,
                                            color: labelCustomerCtrl.text.isNotEmpty ? Colors.black : Colors.grey[400],
                                            letterSpacing: 0.5,
                                          ),
                                          textAlign: TextAlign.center,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Center(
                                        child: Container(width: 110, height: 2.5, color: Colors.black),
                                      ),
                                      const SizedBox(height: 6),
                                      Center(
                                        child: Text(
                                          effectiveService,
                                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Colors.black),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                      if (labelNoteCtrl.text.trim().isNotEmpty) ...[
                                        const SizedBox(height: 5),
                                        Center(
                                          child: Text(
                                            'Catatan: ${labelNoteCtrl.text.trim()}',
                                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 10.5, fontStyle: FontStyle.italic, color: Colors.black),
                                            textAlign: TextAlign.center,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 14),
                                      Align(
                                        alignment: Alignment.bottomRight,
                                        child: Text(
                                          dateStr,
                                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: Colors.black),
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
                    ],
                    const SizedBox(height: 20),

                    // Actions
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              side: const BorderSide(color: Color(0xFFCBD5E1)),
                            ),
                            child: const Text('Batal', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF64748B))),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton.icon(
                            onPressed: () => Navigator.pop(ctx, true),
                            icon: Icon(printLabel ? Icons.print_rounded : Icons.play_arrow_rounded, size: 18),
                            label: Text(
                              printLabel ? 'Mulai & Cetak Label' : 'Ya, Mulai Mesin',
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFD97706),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              elevation: 1,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (confirm != true) return;

    // Clear selection immediately
    setState(() {
      _selectedOrderItem = null;
    });

    // If print label was requested, execute print job directly
    if (printLabel) {
      final String effectiveService = selectedService == 'Lainnya (Ketik Custom)'
          ? (customServiceCtrl.text.trim().isNotEmpty ? customServiceCtrl.text.trim() : 'Kering Saja')
          : selectedService;
      PrinterService.printMachineLabel(
        machineName: labelMachineCtrl.text.trim().isNotEmpty ? labelMachineCtrl.text.trim() : machineName,
        customerName: labelCustomerCtrl.text.trim().isNotEmpty ? labelCustomerCtrl.text.trim() : order.customerName,
        serviceType: effectiveService,
        date: DateTime.now(),
        note: labelNoteCtrl.text.trim().isNotEmpty ? labelNoteCtrl.text.trim() : null,
      ).then((printed) {
        if (printed) {
          Globals.showSuccessSnackBar('Label mesin berhasil dicetak ke printer thermal.');
        }
      });
    }

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
