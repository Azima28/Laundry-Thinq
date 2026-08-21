import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import '../../database/models/database_helper.dart';
import '../../database/models/order_model.dart';
import '../../database/models/transaction_model.dart';
import '../../transactions/transaction_repository.dart';
import '../../transactions/order_repository.dart';
import '../../services/machine_status_service.dart';
import '../../utils/currency_format.dart';
import '../../utils/pdf_export_helper.dart';
import '../../utils/style_constants.dart';
import '../../utils/globals.dart';

class GlobalHistoryScreen extends StatefulWidget {
  final String initialCategoryTab; // 'buku_besar', 'order', 'cuci', 'pengering', 'gosok'
  final bool showAppBar;
  const GlobalHistoryScreen({
    super.key,
    this.initialCategoryTab = 'buku_besar',
    this.showAppBar = false,
  });

  @override
  State<GlobalHistoryScreen> createState() => _GlobalHistoryScreenState();
}

class _GlobalHistoryScreenState extends State<GlobalHistoryScreen> {
  final DatabaseHelper _db = DatabaseHelper.instance;
  final OrderRepository _orderRepo = OrderRepository();

  bool _isLoading = true;
  DateTime _selectedDate = DateTime.now();
  late String _mainCategory; // 'buku_besar', 'order', 'cuci', 'pengering', 'gosok'

  // --- Sub-filters for Buku Besar ---
  String _bukuBesarSubTab = 'semua'; // 'semua', 'cuci', 'gosok', 'pengeluaran'

  // --- Search & Status Filters ---
  String _statusFilter = 'Semua'; // 'Semua', 'Pending', 'Proses', 'Selesai'
  String _paymentFilter = 'Semua'; // 'Semua', 'Lunas', 'Belum Lunas', 'Cicilan'
  final TextEditingController _searchCtrl = TextEditingController();

  // --- Data Containers ---
  int _totalPengeluaran = 0;
  _CategoryData _laundry = _CategoryData();
  _CategoryData _gosokData = _CategoryData();

  List<Map<String, dynamic>> _laundryList = [];
  List<Map<String, dynamic>> _gosokList = [];
  List<Map<String, dynamic>> _pengeluaranList = [];
  List<Map<String, dynamic>> _combinedLedgerEntries = [];

  List<Order> _allOrders = [];
  List<Order> _cuciOrders = [];
  List<Order> _pengeringOrders = [];
  List<Order> _ironOrders = [];

  Map<int, String> _machineNameMap = {};
  Map<int, Map<String, dynamic>> _latestUsageByOrderId = {};
  List<Map<String, dynamic>> _washerUsageHistory = [];
  List<Map<String, dynamic>> _dryerUsageHistory = [];

  @override
  void initState() {
    super.initState();
    _mainCategory = widget.initialCategoryTab;
    _searchCtrl.addListener(() => setState(() {}));
    _loadAllData();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _isCuciItem(OrderItem it) {
    final name = it.itemName.toLowerCase();
    return name.contains('cuci') ||
        name.contains('wash') ||
        name.contains('kiloan') ||
        name.contains('bedcover') ||
        name.contains('selimut') ||
        name.contains('sprei') ||
        name.contains('karpet') ||
        name.contains('boneka') ||
        name.contains('sepatu') ||
        name.contains('tas') ||
        name.contains('jas');
  }

  bool _isPengeringItem(OrderItem it) {
    final name = it.itemName.toLowerCase();
    return name.contains('kering') ||
        name.contains('pengering') ||
        name.contains('dry') ||
        name.contains('jemur');
  }

  bool _isGosokItem(OrderItem it, Set<int?> ironItemIds) {
    final name = it.itemName.toLowerCase();
    return ironItemIds.contains(it.itemId) ||
        name.contains('gosok') ||
        name.contains('setrika') ||
        name.contains('iron') ||
        name.contains('uap') ||
        name.contains('rapi');
  }

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);

    try {
      // 1. Load All Machines
      final machines = await _db.getAllMachines();
      final Map<int, String> machineNameMap = {
        for (var m in machines)
          if (m.id != null) m.id!: m.name
      };

      // 2. Load Pengeluaran
      final expenses = await _db.getExpensesByDate(dateStr);
      int totalPengeluaran = 0;
      List<Map<String, dynamic>> pengeluaranList = [];
      for (var exp in expenses) {
        totalPengeluaran += (exp['amount'] as int);
        pengeluaranList.add({
          'id': exp['id'],
          'title': exp['name'],
          'category': 'Pengeluaran Kas',
          'amount': exp['amount'],
          'type': 'expense',
          'status': 'PENGELUARAN',
          'payment_method': 'Tunai',
          'time': DateFormat('HH:mm').format(DateTime.parse(exp['created_at'])),
          'timestamp': DateTime.parse(exp['created_at']),
        });
      }

      // 3. Load Machine Usage History (for mapping assigned machine logs)
      final allWasherUsages = await _db.getMachineUsageHistory(type: 'cuci');
      final dayWasherUsages = allWasherUsages.where((record) {
        final startedAt = DateTime.parse(record['started_at'] as String).toLocal();
        return startedAt.year == _selectedDate.year &&
            startedAt.month == _selectedDate.month &&
            startedAt.day == _selectedDate.day;
      }).toList();

      final allDryerUsages = await _db.getMachineUsageHistory(type: 'pengering');
      final dayDryerUsages = allDryerUsages.where((record) {
        final startedAt = DateTime.parse(record['started_at'] as String).toLocal();
        return startedAt.year == _selectedDate.year &&
            startedAt.month == _selectedDate.month &&
            startedAt.day == _selectedDate.day;
      }).toList();

      final allUsages = await _db.getMachineUsageHistory();
      final Map<int, Map<String, dynamic>> latestUsageByOrderId = {};
      for (var u in allUsages) {
        final orderId = u['order_id'] as int?;
        if (orderId != null && !latestUsageByOrderId.containsKey(orderId)) {
          latestUsageByOrderId[orderId] = u;
        }
      }

      // 4. Load Orders for the day
      final orders = await _db.getOrdersByDate(dateStr);
      final allTransactions = await TransactionRepository().getAllTransactions();
      final ironItemIds = allTransactions
          .where((t) => t.type == TransactionType.iron)
          .map((t) => t.id)
          .toSet();

      _CategoryData laundry = _CategoryData();
      _CategoryData gosok = _CategoryData();
      List<Map<String, dynamic>> laundryList = [];
      List<Map<String, dynamic>> gosokList = [];

      List<Order> cuciOrders = [];
      List<Order> pengeringOrders = [];
      List<Order> ironOrders = [];

      for (var order in orders) {
        final bool hasCuci = order.items.any((it) => _isCuciItem(it)) ||
            (!order.items.any((it) => _isGosokItem(it, ironItemIds)) &&
                !order.items.any((it) => _isPengeringItem(it)));
        final bool hasPengering = order.items.any((it) => _isPengeringItem(it));
        final bool hasGosok = order.items.any((it) => _isGosokItem(it, ironItemIds));

        if (hasCuci) cuciOrders.add(order);
        if (hasPengering) pengeringOrders.add(order);
        if (hasGosok) ironOrders.add(order);

        bool isPureGosok = order.items.isNotEmpty &&
            order.items.every((item) => ironItemIds.contains(item.itemId));

        int unpaid = (order.totalAmount - order.paidAmount).clamp(0, order.totalAmount);

        String paymentStatus = 'Lunas';
        if (order.paidAmount == 0) {
          paymentStatus = 'Belum Bayar';
        } else if (unpaid > 0) {
          paymentStatus = 'Cicilan (Sisa ${formatRp(unpaid)})';
        }

        Map<String, dynamic> itemData = {
          'id': order.id,
          'title': order.customerName,
          'category': isPureGosok ? 'Setrika / Gosok' : 'Cuci & Kering',
          'status': paymentStatus,
          'payment_method': order.paymentMethod.toUpperCase(),
          'income_amount': order.paidAmount,
          'total_order': order.totalAmount,
          'type': 'income',
          'time': DateFormat('HH:mm').format(order.orderDate),
          'timestamp': order.orderDate,
          'items_count': order.items.fold<int>(0, (s, it) => s + it.quantity),
        };

        _CategoryData target = isPureGosok ? gosok : laundry;
        target.totalPendapatan += order.totalAmount;
        target.totalDiterima += order.paidAmount;
        if (unpaid > 0) {
          target.totalPiutang += unpaid;
        }

        if (order.paidAmount == 0) {
          target.countBelum++;
        } else if (unpaid > 0) {
          target.countCicilan++;
        } else {
          target.countLunas++;
        }

        if (order.paidAmount > 0) {
          if (order.paymentMethod.toLowerCase() == 'cash' ||
              order.paymentMethod.toLowerCase().contains('tunai')) {
            target.totalCash += order.paidAmount;
          } else {
            target.totalQRIS += order.paidAmount;
          }
        }

        if (isPureGosok) {
          gosokList.add(itemData);
        } else {
          laundryList.add(itemData);
        }
      }

      // Combine and sort ledger entries by timestamp descending
      final combined = <Map<String, dynamic>>[
        ...laundryList,
        ...gosokList,
        ...pengeluaranList,
      ];
      combined.sort((a, b) => (b['timestamp'] as DateTime).compareTo(a['timestamp'] as DateTime));

      if (mounted) {
        setState(() {
          _totalPengeluaran = totalPengeluaran;
          _laundry = laundry;
          _gosokData = gosok;
          _pengeluaranList = pengeluaranList;
          _laundryList = laundryList;
          _gosokList = gosokList;
          _combinedLedgerEntries = combined;

          _allOrders = orders;
          _cuciOrders = cuciOrders;
          _pengeringOrders = pengeringOrders;
          _ironOrders = ironOrders;

          _machineNameMap = machineNameMap;
          _latestUsageByOrderId = latestUsageByOrderId;

          _washerUsageHistory = dayWasherUsages;
          _dryerUsageHistory = dayDryerUsages;

          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _getMachineInfoForOrder(Order order, {String defaultCategory = 'cuci'}) {
    // 1. Check matching machine_usage_history record
    final usage = _latestUsageByOrderId[order.id];
    if (usage != null && usage['machine_name'] != null && usage['machine_name'].toString().isNotEmpty) {
      final status = usage['status']?.toString() ?? 'Success';
      return '${usage['machine_name']} ($status)';
    }

    // 2. Check assignedMachineId in order
    if (order.assignedMachineId != null && _machineNameMap.containsKey(order.assignedMachineId)) {
      return _machineNameMap[order.assignedMachineId]!;
    }

    // 3. Fallback queue status
    final s = order.status.toLowerCase();
    if (s == 'completed' || s == 'selesai') {
      return 'Selesai / Sukses';
    } else if (s == 'proses' || s == 'processing') {
      return 'Sedang Dikerjakan';
    } else {
      return defaultCategory == 'pengering' ? 'Antrian Pengering' : 'Antrian Cuci';
    }
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
      _loadAllData();
    }
  }

  void _changeDateBy(int days) {
    setState(() {
      _selectedDate = _selectedDate.add(Duration(days: days));
    });
    _loadAllData();
  }

  // ==========================================
  // EXPORT PDF MODAL DIALOG
  // ==========================================
  Future<void> _showExportPdfDialog() async {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: Colors.white,
          title: const Row(
            children: [
              Icon(Icons.picture_as_pdf_rounded, color: StyleConstants.dangerColor, size: 22),
              SizedBox(width: 10),
              Text('Ekspor Buku Besar (PDF)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Pilih format rentang waktu pembukuan yang ingin diekspor:',
                  style: TextStyle(fontSize: 13, color: StyleConstants.textBody),
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  tileColor: const Color(0xFFF8FAFC),
                  leading: const Icon(Icons.today_rounded, color: StyleConstants.primaryColor),
                  title: const Text('Laporan Harian (Hari Ini)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                  subtitle: Text(DateFormat('dd MMMM yyyy').format(_selectedDate), style: const TextStyle(fontSize: 12)),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                  onTap: () {
                    Navigator.pop(context);
                    PdfExportHelper.exportLedgerToPdf(
                      context: context,
                      startDate: _selectedDate,
                      endDate: _selectedDate,
                    );
                  },
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  tileColor: const Color(0xFFF8FAFC),
                  leading: const Icon(Icons.date_range_rounded, color: StyleConstants.secondaryColor),
                  title: const Text('Laporan Mingguan (7 Hari Terakhir)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                  subtitle: Text(
                    '${DateFormat('dd MMM').format(_selectedDate.subtract(const Duration(days: 6)))} - ${DateFormat('dd MMM yyyy').format(_selectedDate)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                  onTap: () {
                    Navigator.pop(context);
                    PdfExportHelper.exportLedgerToPdf(
                      context: context,
                      startDate: _selectedDate.subtract(const Duration(days: 6)),
                      endDate: _selectedDate,
                    );
                  },
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  tileColor: const Color(0xFFF8FAFC),
                  leading: const Icon(Icons.calendar_month_rounded, color: StyleConstants.successColor),
                  title: const Text('Laporan Bulanan Penuh', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                  subtitle: Text(DateFormat('MMMM yyyy').format(_selectedDate), style: const TextStyle(fontSize: 12)),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                  onTap: () {
                    Navigator.pop(context);
                    final firstDay = DateTime(_selectedDate.year, _selectedDate.month, 1);
                    final lastDay = DateTime(_selectedDate.year, _selectedDate.month + 1, 0);
                    PdfExportHelper.exportLedgerToPdf(
                      context: context,
                      startDate: firstDay,
                      endDate: lastDay,
                    );
                  },
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  tileColor: const Color(0xFFF8FAFC),
                  leading: const Icon(Icons.tune_rounded, color: Color(0xFFE11D48)),
                  title: const Text('Pilih Rentang Tanggal Bebas...', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                  onTap: () async {
                    Navigator.pop(context);
                    final pickedRange = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                      initialDateRange: DateTimeRange(
                        start: _selectedDate.subtract(const Duration(days: 7)),
                        end: _selectedDate,
                      ),
                    );
                    if (pickedRange != null && context.mounted) {
                      PdfExportHelper.exportLedgerToPdf(
                        context: context,
                        startDate: pickedRange.start,
                        endDate: pickedRange.end,
                      );
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal', style: TextStyle(color: StyleConstants.textMuted)),
            ),
          ],
        );
      },
    );
  }

  // ==========================================
  // IOT ACTIVATION LOGS & STATISTICS MODAL
  // ==========================================
  void _showMachineIoTAndStatsModal(String machineType) {
    final isWasher = machineType == 'cuci';
    final usageList = isWasher ? _washerUsageHistory : _dryerUsageHistory;
    final title = isWasher ? 'Log Aktivasi & Statistik Mesin Cuci' : 'Log Aktivasi & Statistik Mesin Pengering';
    final icon = isWasher ? Icons.local_laundry_service_rounded : Icons.wb_sunny_rounded;
    final color = isWasher ? StyleConstants.primaryColor : const Color(0xFFF59E0B);

    int totalUsage = usageList.length;
    int countSuccess = 0;
    int countFailed = 0;
    int countSended = 0;
    Map<String, int> machineCount = {};

    for (var record in usageList) {
      final status = record['status'] as String? ?? 'Success';
      if (status == 'Success') {
        countSuccess++;
      } else if (status == 'Failed') {
        countFailed++;
      } else {
        countSended++;
      }

      final name = record['machine_name'] as String? ?? 'Mesin Tak Dikenal';
      machineCount[name] = (machineCount[name] ?? 0) + 1;
    }

    final successRate = totalUsage > 0 ? ((countSuccess / totalUsage) * 100).toStringAsFixed(1) : '0';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF8FAFC),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  children: [
                    Icon(icon, color: color, size: 24),
                    const SizedBox(width: 10),
                    Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: StyleConstants.textHeading)),
                    const Spacer(),
                    IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx)),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  children: [
                    // Summary KPI Cards
                    Row(
                      children: [
                        Expanded(child: _mStatCard('Total\nAktivasi IoT', '$totalUsage kali', color, Icons.repeat_rounded)),
                        const SizedBox(width: 10),
                        Expanded(child: _mStatCard('Tingkat\nSukses Sinyal', '$successRate%', StyleConstants.successColor, Icons.check_circle_rounded)),
                        const SizedBox(width: 10),
                        Expanded(child: _mStatCard('Unit\nAktif', '${machineCount.length} Mesin', StyleConstants.secondaryColor, Icons.precision_manufacturing_rounded)),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Activation Breakdown
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: StyleConstants.borderLight),
                      ),
                      child: Column(
                        children: [
                          _mStatusBar(Icons.check_circle_rounded, 'Aktivasi Berhasil', countSuccess, StyleConstants.successColor, totalUsage),
                          const SizedBox(height: 8),
                          _mStatusBar(Icons.send_rounded, 'Sinyal Terkirim', countSended, StyleConstants.infoColor, totalUsage),
                          const SizedBox(height: 8),
                          _mStatusBar(Icons.cancel_rounded, 'Aktivasi Gagal', countFailed, StyleConstants.dangerColor, totalUsage),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Log Details List
                    _mSectionTitle('RIWAYAT EKSEKUSI TELEMETRI IOT HARI INI', color),
                    const SizedBox(height: 10),
                    if (usageList.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: StyleConstants.borderLight),
                        ),
                        child: const Center(
                          child: Text('Belum ada sinyal aktivasi mesin fisik yang dikirim pada tanggal ini.', style: TextStyle(color: StyleConstants.textMuted)),
                        ),
                      )
                    else
                      ...usageList.map((record) {
                        final status = record['status'] as String? ?? 'Success';
                        final isSuccess = status == 'Success';
                        final isFailed = status == 'Failed';
                        final startedAt = DateTime.parse(record['started_at'] as String).toLocal();

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: StyleConstants.borderLight),
                          ),
                          child: Row(
                            children: [
                              Text(
                                DateFormat('HH:mm:ss').format(startedAt),
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: StyleConstants.textMuted),
                              ),
                              const SizedBox(width: 12),
                              Icon(icon, size: 16, color: color),
                              const SizedBox(width: 6),
                              Expanded(
                                flex: 3,
                                child: Text(
                                  record['machine_name'] ?? '-',
                                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: StyleConstants.textHeading),
                                ),
                              ),
                              Expanded(
                                flex: 3,
                                child: Text(
                                  '${record['customer_name'] ?? 'Pelanggan'} • #${record['order_id'] ?? ''}',
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: isSuccess ? StyleConstants.statusSuccessBg : (isFailed ? StyleConstants.statusDangerBg : StyleConstants.statusInfoBg),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  status.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    color: isSuccess ? StyleConstants.statusSuccessText : (isFailed ? StyleConstants.statusDangerText : StyleConstants.statusInfoText),
                                  ),
                                ),
                              ),
                              if (isFailed) ...[
                                const SizedBox(width: 8),
                                ElevatedButton(
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    _retryMachineActivation(record);
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: StyleConstants.dangerColor,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    minimumSize: Size.zero,
                                  ),
                                  child: const Text('Retry', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ],
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mStatCard(String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: StyleConstants.borderLight),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: color), textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 11, color: StyleConstants.textMuted, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _mSectionTitle(String t, Color color) => Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
        child: Text(t, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: color, letterSpacing: 0.5)),
      );

  Widget _mStatusBar(IconData icon, String label, int count, Color color, int total) {
    final pct = total > 0 ? (count / total) : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: StyleConstants.textHeading))),
            Text('$count kali', style: const TextStyle(color: StyleConstants.textBody, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 5),
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: pct,
                  backgroundColor: const Color(0xFFE2E8F0),
                  valueColor: AlwaysStoppedAnimation(color),
                  minHeight: 5,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text('${(pct * 100).toStringAsFixed(0)}%', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11, color: color)),
          ],
        ),
      ],
    );
  }

  // ==========================================
  // RETRY ACTIVATION ACTION
  // ==========================================
  Future<void> _retryMachineActivation(Map<String, dynamic> record) async {
    final int? machineId = record['machine_id'] as int?;
    final int? orderId = record['order_id'] as int?;
    if (machineId == null || orderId == null) return;

    final machine = await _db.getMachine(machineId);
    final order = await _db.getOrder(orderId);
    if (machine == null || order == null) {
      Globals.showErrorSnackBar('Data mesin atau pesanan tidak ditemukan');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Konfirmasi Nyalakan Ulang', style: TextStyle(fontWeight: FontWeight.w800)),
        content: Text('Coba kirim sinyal aktivasi kembali ke ${machine.name} untuk pelanggan ${order.customerName}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal', style: TextStyle(color: StyleConstants.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: StyleConstants.primaryColor, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Coba Nyalakan'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      String endpoint = '';
      final states = MachineStatusService.instance.states;
      final entry = states[machine.name] ?? states[machine.key];
      if (entry != null && entry['url'] != null && entry['url'].toString().isNotEmpty) {
        endpoint = entry['url'].toString();
      } else {
        endpoint = machine.url;
      }

      final String sanitizedName = order.customerName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_').toLowerCase();
      String fullUrl = endpoint;
      if (fullUrl.endsWith('/on')) {
        fullUrl = '$fullUrl/$sanitizedName';
      } else if (!fullUrl.contains('/on')) {
        fullUrl = fullUrl.endsWith('/') ? '${fullUrl}on/$sanitizedName' : '$fullUrl/on/$sanitizedName';
      }

      final resp = await http.get(Uri.parse(fullUrl)).timeout(const Duration(seconds: 15));
      if (mounted) Navigator.pop(context);

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        await _db.updateMachineUsageStatus(
          historyId: record['id'] as int,
          status: 'Success',
          errorMessage: null,
        );
        Globals.showSuccessSnackBar('Mesin ${machine.name} berhasil dinyalakan ulang!');
        _loadAllData();
      } else {
        await _db.updateMachineUsageStatus(
          historyId: record['id'] as int,
          status: 'Failed',
          errorMessage: 'Retry Failed: HTTP ${resp.statusCode}',
        );
        Globals.showErrorSnackBar('Aktivasi gagal: HTTP ${resp.statusCode}');
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      await _db.updateMachineUsageStatus(
        historyId: record['id'] as int,
        status: 'Failed',
        errorMessage: 'Retry Error: $e',
      );
      Globals.showErrorSnackBar('Gagal menghubungi mesin: $e');
    }
  }

  // ==========================================
  // ORDER PAYMENT SETTLEMENT DIALOG
  // ==========================================
  void _showOrderPaymentDialog(Order order) {
    final sisaTagihan = order.totalAmount - order.paidAmount;
    final controller = TextEditingController(text: sisaTagihan.toString());
    String selectedMethod = 'cash';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Pelunasan Pembayaran', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Pelanggan: ${order.customerName}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 6),
              Text('Total Nota: ${formatRp(order.totalAmount)}'),
              Text('Sudah Dibayar: ${formatRp(order.paidAmount)}'),
              Text('Sisa Tagihan: ${formatRp(sisaTagihan)}', style: const TextStyle(fontWeight: FontWeight.bold, color: StyleConstants.dangerColor)),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Nominal Bayar Pelunasan (Rp)',
                  border: OutlineInputBorder(),
                  prefixText: 'Rp ',
                ),
              ),
              const SizedBox(height: 12),
              const Text('Metode Pembayaran:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              Row(
                children: [
                  Radio<String>(
                    value: 'cash',
                    groupValue: selectedMethod,
                    onChanged: (val) => setStateDialog(() => selectedMethod = val!),
                  ),
                  const Text('Tunai'),
                  const SizedBox(width: 16),
                  Radio<String>(
                    value: 'qris',
                    groupValue: selectedMethod,
                    onChanged: (val) => setStateDialog(() => selectedMethod = val!),
                  ),
                  const Text('QRIS'),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Batal', style: TextStyle(color: StyleConstants.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: StyleConstants.primaryColor, foregroundColor: Colors.white),
              onPressed: () async {
                final inputAmount = int.tryParse(controller.text) ?? 0;
                if (inputAmount <= 0) {
                  Globals.showErrorSnackBar('Nominal bayar tidak valid.');
                  return;
                }

                final totalNewPaid = order.paidAmount + inputAmount;
                final isFullyPaid = totalNewPaid >= order.totalAmount;

                final updated = order.copyWith(
                  isPaid: isFullyPaid,
                  paidAmount: isFullyPaid ? order.totalAmount : totalNewPaid,
                  paymentMethod: selectedMethod,
                  paymentTimestamp: DateTime.now(),
                );

                await _db.updateOrder(updated);
                if (mounted) Navigator.pop(ctx);
                _loadAllData();
                Globals.showSuccessSnackBar(isFullyPaid ? 'Pembayaran Lunas berhasil dicatat!' : 'Cicilan masuk berhasil dicatat!');
              },
              child: const Text('Simpan Pembayaran'),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // ORDER DETAILS DIALOG
  // ==========================================
  Future<void> _showOrderDetailsDialog(Order order) async {
    final db = await _db.database;
    final List<Map<String, dynamic>> usages = await db.query(
      'machine_usage_history',
      where: 'order_id = ?',
      whereArgs: [order.id],
      orderBy: 'started_at ASC',
    );

    final isDone = order.status.toLowerCase() == 'completed' ||
        order.status.toLowerCase() == 'selesai' ||
        order.status.toLowerCase() == 'siap diambil';
    final isProcessing =
        order.status.toLowerCase() == 'proses' || order.status.toLowerCase() == 'processing';

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: StyleConstants.primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.receipt_long_rounded, color: StyleConstants.primaryColor, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Rincian Lengkap Nota #${order.id}',
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              ),
            ),
            IconButton(icon: const Icon(Icons.close_rounded, size: 20), onPressed: () => Navigator.pop(ctx)),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Customer & Order Identity Card
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: StyleConstants.borderLight),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: StyleConstants.primaryColor.withValues(alpha: 0.12),
                        child: Text(
                          order.customerName.isNotEmpty ? order.customerName[0].toUpperCase() : '?',
                          style: const TextStyle(fontWeight: FontWeight.w900, color: StyleConstants.primaryColor, fontSize: 15),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              order.customerName,
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5, color: StyleConstants.textHeading),
                            ),
                            Text(
                              order.customerPhone?.isNotEmpty == true ? order.customerPhone! : 'Belum Ada No. WA',
                              style: const TextStyle(fontSize: 12, color: StyleConstants.textMuted, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: isDone ? StyleConstants.statusSuccessBg : (isProcessing ? StyleConstants.statusInfoBg : StyleConstants.statusWarningBg),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              isDone ? 'SELESAI' : (isProcessing ? 'SEDANG PROSES' : 'PENDING'),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                color: isDone ? StyleConstants.statusSuccessText : (isProcessing ? StyleConstants.statusInfoText : StyleConstants.statusWarningText),
                              ),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            order.isPaid ? 'LUNAS' : (order.paidAmount > 0 ? 'CICILAN' : 'BELUM BAYAR'),
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w900,
                              color: order.isPaid ? StyleConstants.statusSuccessText : StyleConstants.statusDangerText,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // 2. Comprehensive Timestamps & Machine Tracking Card
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: StyleConstants.borderLight),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.schedule_rounded, size: 16, color: StyleConstants.primaryColor),
                          SizedBox(width: 6),
                          Text(
                            'PELACAKAN WAKTU & SIKLUS MESIN',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: StyleConstants.textMuted, letterSpacing: 0.5),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _detailTimelineRow(
                        icon: Icons.add_shopping_cart_rounded,
                        label: 'Waktu Order Dibuat',
                        value: DateFormat('dd MMM yyyy, HH:mm:ss').format(order.orderDate),
                        color: StyleConstants.primaryColor,
                      ),
                      const SizedBox(height: 6),
                      _detailTimelineRow(
                        icon: Icons.hourglass_top_rounded,
                        label: 'Waktu Masuk Antrian',
                        value: DateFormat('dd MMM yyyy, HH:mm:ss').format(order.orderDate),
                        color: StyleConstants.warningColor,
                      ),
                      const SizedBox(height: 6),

                      // Machine Execution Time & Cycle Allocation
                      if (usages.isNotEmpty) ...[
                        if (usages.length == 1) ...[
                          _detailTimelineRow(
                            icon: Icons.power_rounded,
                            label: 'Waktu Mesin Dihidupkan',
                            value: DateFormat('dd MMM yyyy, HH:mm:ss').format(
                              DateTime.parse(usages.first['started_at'] as String).toLocal(),
                            ),
                            color: StyleConstants.successColor,
                          ),
                          const SizedBox(height: 6),
                          _detailTimelineRow(
                            icon: Icons.local_laundry_service_rounded,
                            label: 'Mesin Fisik Digunakan',
                            value: '${usages.first['machine_name']} (${usages.first['status']})',
                            color: StyleConstants.secondaryColor,
                            isBold: true,
                          ),
                        ] else ...[
                          _detailTimelineRow(
                            icon: Icons.repeat_rounded,
                            label: 'Total Siklus Mesin',
                            value: '${usages.length} Siklus / Unit Mesin',
                            color: StyleConstants.secondaryColor,
                            isBold: true,
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (int i = 0; i < usages.length; i++)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 3),
                                    child: Row(
                                      children: [
                                        Text(
                                          '• Siklus #${i + 1}: ',
                                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: StyleConstants.primaryColor),
                                        ),
                                        Text(
                                          '${usages[i]['machine_name']} ',
                                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                                        ),
                                        Text(
                                          '(Dihidupkan: ${DateFormat('HH:mm:ss').format(DateTime.parse(usages[i]['started_at'] as String).toLocal())})',
                                          style: const TextStyle(fontSize: 11.5, color: StyleConstants.textMuted),
                                        ),
                                        const Spacer(),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: usages[i]['status'] == 'Success' ? StyleConstants.statusSuccessBg : StyleConstants.statusDangerBg,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            usages[i]['status'] ?? 'Success',
                                            style: TextStyle(
                                              fontSize: 9.5,
                                              fontWeight: FontWeight.w800,
                                              color: usages[i]['status'] == 'Success' ? StyleConstants.statusSuccessText : StyleConstants.statusDangerText,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ] else if (order.assignedMachineId != null && _machineNameMap.containsKey(order.assignedMachineId)) ...[
                        _detailTimelineRow(
                          icon: Icons.power_rounded,
                          label: 'Waktu Mesin Dihidupkan',
                          value: order.machineStartedAt != null
                              ? DateFormat('dd MMM yyyy, HH:mm:ss').format(order.machineStartedAt!)
                              : '-',
                          color: StyleConstants.successColor,
                        ),
                        const SizedBox(height: 6),
                        _detailTimelineRow(
                          icon: Icons.local_laundry_service_rounded,
                          label: 'Mesin Fisik Digunakan',
                          value: _machineNameMap[order.assignedMachineId]!,
                          color: StyleConstants.secondaryColor,
                          isBold: true,
                        ),
                      ] else ...[
                        _detailTimelineRow(
                          icon: Icons.power_off_rounded,
                          label: 'Status Mesin Fisik',
                          value: 'Belum Dinyalakan (Menunggu di Antrian)',
                          color: StyleConstants.warningColor,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // 3. Itemized Order Details Card
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: StyleConstants.borderLight),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'RINCIAN LAYANAN & ITEM:',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: StyleConstants.textMuted, letterSpacing: 0.5),
                      ),
                      const SizedBox(height: 8),
                      ...order.items.map((item) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: StyleConstants.primaryColor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '${item.quantity}x',
                                    style: const TextStyle(fontWeight: FontWeight.w900, color: StyleConstants.primaryColor, fontSize: 12),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.itemName,
                                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: StyleConstants.textHeading),
                                      ),
                                      Text(
                                        '@ ${formatRp(item.price)}',
                                        style: const TextStyle(fontSize: 11, color: StyleConstants.textMuted),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  formatRp(item.price * item.quantity),
                                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5, color: StyleConstants.textHeading),
                                ),
                              ],
                            ),
                          )),
                      const SizedBox(height: 10),
                      const Divider(height: 1, color: StyleConstants.borderLight),
                      const SizedBox(height: 10),

                      // 4. Financial Summary Rows
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Total Tagihan:', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                          Text(formatRp(order.totalAmount), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: StyleConstants.primaryColor)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Telah Dibayar (Kasir):', style: TextStyle(fontSize: 12.5, color: StyleConstants.textMuted)),
                          Text(formatRp(order.paidAmount), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: StyleConstants.successColor)),
                        ],
                      ),
                      if (order.totalAmount > order.paidAmount) ...[
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Sisa Tagihan (Piutang):', style: TextStyle(fontSize: 12.5, color: StyleConstants.dangerColor, fontWeight: FontWeight.bold)),
                            Text(formatRp(order.totalAmount - order.paidAmount), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5, color: StyleConstants.dangerColor)),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Tutup', style: TextStyle(color: StyleConstants.textMuted, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _detailTimelineRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    bool isBold = false,
  }) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 8),
        SizedBox(
          width: 160,
          child: Text(label, style: const TextStyle(fontSize: 12, color: StyleConstants.textMuted, fontWeight: FontWeight.w500)),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: isBold ? FontWeight.w900 : FontWeight.w700,
              color: isBold ? color : StyleConstants.textHeading,
            ),
          ),
        ),
      ],
    );
  }

  // ==========================================
  // MAIN BUILD METHOD
  // ==========================================
  @override
  Widget build(BuildContext context) {
    final Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Universal Top Control Bar (Date Selector + Master Tabs + Action Buttons)
        _buildMasterHeaderBar(),
        const SizedBox(height: 12),

        // 2. Active View Body
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _buildActiveCategoryView(),
        ),
      ],
    );

    if (widget.showAppBar) {
      return Scaffold(
        backgroundColor: StyleConstants.backgroundColor,
        appBar: AppBar(
          title: const Text('Pusat Riwayat & Buku Besar', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
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
        ),
        body: Padding(
          padding: const EdgeInsets.all(StyleConstants.densePadding),
          child: content,
        ),
      );
    }

    return content;
  }

  // ==========================================
  // 1. MASTER TOP CONTROL BAR
  // ==========================================
  Widget _buildMasterHeaderBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: StyleConstants.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // Date Selector Pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: StyleConstants.borderLight),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left_rounded, size: 18),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: 'Hari Sebelumnya',
                      onPressed: () => _changeDateBy(-1),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: _selectDate,
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today_rounded, size: 14, color: StyleConstants.primaryColor),
                          const SizedBox(width: 8),
                          Text(
                            DateFormat('EEEE, dd MMMM yyyy').format(_selectedDate),
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: StyleConstants.textHeading),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.chevron_right_rounded, size: 18),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: 'Hari Berikutnya',
                      onPressed: () => _changeDateBy(1),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 12),

              // Master Category Selector Ribbon
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _categoryTabButton('buku_besar', 'Buku Besar', Icons.account_balance_wallet_rounded, null),
                      const SizedBox(width: 6),
                      _categoryTabButton('order', 'Semua Order', Icons.receipt_long_rounded, '${_allOrders.length}'),
                      const SizedBox(width: 6),
                      _categoryTabButton('cuci', 'Mesin Cuci', Icons.local_laundry_service_rounded, '${_cuciOrders.length}'),
                      const SizedBox(width: 6),
                      _categoryTabButton('pengering', 'Mesin Pengering', Icons.wb_sunny_rounded, '${_pengeringOrders.length}'),
                      const SizedBox(width: 6),
                      _categoryTabButton('gosok', 'Riwayat Gosok', Icons.iron_rounded, '${_ironOrders.length}'),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 12),

              // Action Buttons Based on Active Tab
              if (_mainCategory == 'buku_besar')
                ElevatedButton.icon(
                  onPressed: _showExportPdfDialog,
                  icon: const Icon(Icons.picture_as_pdf_rounded, size: 15),
                  label: const Text('Ekspor PDF', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: StyleConstants.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                )
              else if (_mainCategory == 'cuci' || _mainCategory == 'pengering')
                ElevatedButton.icon(
                  onPressed: () => _showMachineIoTAndStatsModal(_mainCategory),
                  icon: const Icon(Icons.analytics_rounded, size: 15),
                  label: const Text('Log Sinyal & Statistik', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _mainCategory == 'cuci' ? StyleConstants.primaryColor : const Color(0xFFF59E0B),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                ),

              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 19, color: StyleConstants.textMuted),
                tooltip: 'Perbarui Data',
                onPressed: _loadAllData,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _categoryTabButton(String key, String label, IconData icon, String? badge) {
    final isSelected = _mainCategory == key;
    return InkWell(
      onTap: () => setState(() => _mainCategory = key),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? StyleConstants.sidebarBackground : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? StyleConstants.sidebarBackground : StyleConstants.borderLight,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: isSelected ? StyleConstants.accentCyan : StyleConstants.textMuted,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? Colors.white : StyleConstants.textBody,
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: isSelected ? StyleConstants.accentCyan.withValues(alpha: 0.25) : const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  badge,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: isSelected ? StyleConstants.accentCyan : StyleConstants.textMuted,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ==========================================
  // 2. DISPATCH ACTIVE CATEGORY VIEW
  // ==========================================
  Widget _buildActiveCategoryView() {
    switch (_mainCategory) {
      case 'buku_besar':
        return _buildBukuBesarView();
      case 'order':
        return _buildCategoryOrdersWorkstation(
          categoryKey: 'order',
          title: 'Semua Transaksi & Pesanan',
          ordersList: _allOrders,
          accentColor: StyleConstants.primaryColor,
          icon: Icons.receipt_long_rounded,
        );
      case 'cuci':
        return _buildCategoryOrdersWorkstation(
          categoryKey: 'cuci',
          title: 'Riwayat Layanan Mesin Cuci',
          ordersList: _cuciOrders,
          accentColor: StyleConstants.primaryColor,
          icon: Icons.local_laundry_service_rounded,
        );
      case 'pengering':
        return _buildCategoryOrdersWorkstation(
          categoryKey: 'pengering',
          title: 'Riwayat Layanan Mesin Pengering',
          ordersList: _pengeringOrders,
          accentColor: const Color(0xFFF59E0B),
          icon: Icons.wb_sunny_rounded,
        );
      case 'gosok':
        return _buildCategoryOrdersWorkstation(
          categoryKey: 'gosok',
          title: 'Riwayat Pesanan Gosok / Setrika',
          ordersList: _ironOrders,
          accentColor: const Color(0xFFF97316),
          icon: Icons.iron_rounded,
        );
      default:
        return _buildBukuBesarView();
    }
  }

  // ==========================================
  // VIEW 1: BUKU BESAR & KAS GLOBAL
  // ==========================================
  Widget _buildBukuBesarView() {
    final int totalOmzet = _laundry.totalPendapatan + _gosokData.totalPendapatan;
    final int totalKasMasuk = _laundry.totalDiterima + _gosokData.totalDiterima;
    final int totalPiutang = _laundry.totalPiutang + _gosokData.totalPiutang;
    final int netProfit = totalKasMasuk - _totalPengeluaran;

    List<Map<String, dynamic>> filteredList = [];
    switch (_bukuBesarSubTab) {
      case 'cuci':
        filteredList = _laundryList;
        break;
      case 'gosok':
        filteredList = _gosokList;
        break;
      case 'pengeluaran':
        filteredList = _pengeluaranList;
        break;
      case 'semua':
      default:
        filteredList = _combinedLedgerEntries;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 4-in-1 Financial KPI Ribbon
        _buildFinancialKpiRibbon(
          totalOmzet: totalOmzet,
          totalKasMasuk: totalKasMasuk,
          totalPiutang: totalPiutang,
          totalPengeluaran: _totalPengeluaran,
          netProfit: netProfit,
        ),
        const SizedBox(height: 12),

        // Sub-filter Tabs for Buku Besar
        Row(
          children: [
            _ledgerSubTab('semua', 'Semua Mutasi (${_combinedLedgerEntries.length})'),
            const SizedBox(width: 8),
            _ledgerSubTab('cuci', 'Cuci & Kering (${_laundryList.length})'),
            const SizedBox(width: 8),
            _ledgerSubTab('gosok', 'Setrika (${_gosokList.length})'),
            const SizedBox(width: 8),
            _ledgerSubTab('pengeluaran', 'Pengeluaran Kas (${_pengeluaranList.length})'),
          ],
        ),
        const SizedBox(height: 10),

        // Data Table
        Expanded(
          child: filteredList.isEmpty
              ? _buildEmptyState('Belum ada transaksi atau pengeluaran pada tanggal ini.')
              : _buildLedgerTable(filteredList, totalKasMasuk, _totalPengeluaran),
        ),
      ],
    );
  }

  Widget _ledgerSubTab(String key, String label) {
    final isSelected = _bukuBesarSubTab == key;
    return InkWell(
      onTap: () => setState(() => _bukuBesarSubTab = key),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? StyleConstants.sidebarBackground : Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: isSelected ? StyleConstants.sidebarBackground : StyleConstants.borderLight),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: isSelected ? Colors.white : StyleConstants.textBody,
          ),
        ),
      ),
    );
  }

  Widget _buildFinancialKpiRibbon({
    required int totalOmzet,
    required int totalKasMasuk,
    required int totalPiutang,
    required int totalPengeluaran,
    required int netProfit,
  }) {
    return Row(
      children: [
        Expanded(
          child: _buildFinancialKpiCard(
            title: 'TOTAL OMZET KOTOR',
            value: formatRp(totalOmzet),
            icon: Icons.storefront_rounded,
            color: StyleConstants.primaryColor,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildFinancialKpiCard(
            title: 'KAS MASUK (TUNAI/QRIS)',
            value: formatRp(totalKasMasuk),
            icon: Icons.arrow_downward_rounded,
            color: StyleConstants.successColor,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildFinancialKpiCard(
            title: 'PENGELUARAN KAS',
            value: formatRp(totalPengeluaran),
            icon: Icons.arrow_upward_rounded,
            color: StyleConstants.dangerColor,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildFinancialKpiCard(
            title: 'LABA BERSIH HARIAN',
            value: formatRp(netProfit),
            icon: Icons.account_balance_rounded,
            color: netProfit >= 0 ? StyleConstants.successColor : StyleConstants.dangerColor,
            isHighlight: true,
          ),
        ),
      ],
    );
  }

  Widget _buildFinancialKpiCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    bool isHighlight = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isHighlight ? color.withValues(alpha: 0.4) : StyleConstants.borderLight, width: isHighlight ? 1.5 : 1),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: isHighlight ? 0.12 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: color, width: 3)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: StyleConstants.textMuted,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: isHighlight ? color : StyleConstants.textHeading,
                        letterSpacing: -0.3,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLedgerTable(List<Map<String, dynamic>> items, int totalIn, int totalOut) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: StyleConstants.borderLight),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Table Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
              border: Border(bottom: BorderSide(color: StyleConstants.borderLight)),
            ),
            child: const Row(
              children: [
                SizedBox(width: 70, child: Text('WAKTU', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: StyleConstants.textMuted))),
                Expanded(flex: 3, child: Text('DESKRIPSI / PELANGGAN', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: StyleConstants.textMuted))),
                Expanded(flex: 2, child: Text('KATEGORI', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: StyleConstants.textMuted))),
                SizedBox(width: 90, child: Text('METODE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: StyleConstants.textMuted))),
                SizedBox(width: 110, child: Text('STATUS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: StyleConstants.textMuted))),
                SizedBox(width: 120, child: Text('KAS MASUK', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: StyleConstants.successColor))),
                SizedBox(width: 120, child: Text('KAS KELUAR', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: StyleConstants.dangerColor))),
              ],
            ),
          ),

          // Scrollable Rows
          Expanded(
            child: ListView.separated(
              itemCount: items.length,
              separatorBuilder: (ctx, i) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
              itemBuilder: (ctx, i) {
                final item = items[i];
                final bool isExpense = item['type'] == 'expense';

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 70,
                        child: Text(
                          item['time'] ?? '--:--',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: StyleConstants.textMuted),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          item['title'] ?? '-',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: StyleConstants.textHeading),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          item['category'] ?? '-',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isExpense ? StyleConstants.dangerColor : StyleConstants.primaryColor,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 90,
                        child: Text(
                          item['payment_method'] ?? 'TUNAI',
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: StyleConstants.textBody),
                        ),
                      ),
                      SizedBox(
                        width: 110,
                        child: Text(
                          item['status'] ?? '-',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: isExpense ? StyleConstants.dangerColor : StyleConstants.successColor,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 120,
                        child: Text(
                          isExpense ? '-' : formatRp(item['income_amount'] ?? 0),
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: StyleConstants.successColor),
                        ),
                      ),
                      SizedBox(
                        width: 120,
                        child: Text(
                          isExpense ? formatRp(item['amount'] ?? 0) : '-',
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: StyleConstants.dangerColor),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          // Table Footer Summary
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(14)),
              border: Border(top: BorderSide(color: StyleConstants.borderLight)),
            ),
            child: Row(
              children: [
                Text(
                  'Total ${items.length} Baris Pembukuan',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: StyleConstants.textMuted),
                ),
                const Spacer(),
                Text(
                  'Kas Masuk: ${formatRp(totalIn)}',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5, color: StyleConstants.successColor),
                ),
                const SizedBox(width: 20),
                Text(
                  'Kas Keluar: ${formatRp(totalOut)}',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5, color: StyleConstants.dangerColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // VIEW 2: UNIFIED CATEGORY ORDERS WORKSTATION
  // ==========================================
  Widget _buildCategoryOrdersWorkstation({
    required String categoryKey,
    required String title,
    required List<Order> ordersList,
    required Color accentColor,
    required IconData icon,
  }) {
    final query = _searchCtrl.text.toLowerCase().trim();

    final filtered = ordersList.where((order) {
      final matchesQuery = query.isEmpty ||
          order.customerName.toLowerCase().contains(query) ||
          (order.customerPhone ?? '').contains(query) ||
          '${order.id}'.contains(query) ||
          order.items.any((it) => it.itemName.toLowerCase().contains(query));

      bool matchesStatus = true;
      if (_statusFilter != 'Semua') {
        final s = order.status.toLowerCase();
        if (_statusFilter == 'Pending') matchesStatus = (s == 'pending');
        if (_statusFilter == 'Proses') matchesStatus = (s == 'proses' || s == 'processing');
        if (_statusFilter == 'Selesai') matchesStatus = (s == 'completed' || s == 'selesai' || s == 'siap diambil');
      }

      bool matchesPayment = true;
      if (_paymentFilter != 'Semua') {
        if (_paymentFilter == 'Lunas') matchesPayment = order.isPaid;
        if (_paymentFilter == 'Belum Lunas') matchesPayment = (!order.isPaid && order.paidAmount == 0);
        if (_paymentFilter == 'Cicilan') matchesPayment = (!order.isPaid && order.paidAmount > 0);
      }

      return matchesQuery && matchesStatus && matchesPayment;
    }).toList();

    int countSelesai = 0;
    int countProses = 0;
    int countPending = 0;
    int totalNilai = 0;

    for (var o in filtered) {
      totalNilai += o.totalAmount;
      final s = o.status.toLowerCase();
      if (s == 'completed' || s == 'selesai' || s == 'siap diambil') {
        countSelesai++;
      } else if (s == 'proses' || s == 'processing') {
        countProses++;
      } else {
        countPending++;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 4-in-1 KPI Ribbon (Lifecycle Status)
        Row(
          children: [
            Expanded(
              child: _buildFinancialKpiCard(
                title: 'TOTAL PESANAN',
                value: '${filtered.length} Nota (${formatRp(totalNilai)})',
                icon: icon,
                color: accentColor,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildFinancialKpiCard(
                title: 'SUKSES / SELESAI',
                value: '$countSelesai Nota',
                icon: Icons.check_circle_rounded,
                color: StyleConstants.successColor,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildFinancialKpiCard(
                title: 'SEDANG PROSES / MESIN',
                value: '$countProses Nota',
                icon: Icons.sync_rounded,
                color: StyleConstants.infoColor,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildFinancialKpiCard(
                title: 'ANTRIAN / PENDING',
                value: '$countPending Nota',
                icon: Icons.hourglass_top_rounded,
                color: StyleConstants.warningColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Search Bar & Filter Chips
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 38,
                child: TextField(
                  controller: _searchCtrl,
                  style: const TextStyle(fontSize: 12.5),
                  decoration: InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded, size: 18, color: accentColor),
                    hintText: 'Cari nama pelanggan, nomor WhatsApp, nomor nota, atau item...',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: StyleConstants.borderLight)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: StyleConstants.borderLight)),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Status Filter Chips
            _filterChipGroup(
              label: 'Status:',
              currentVal: _statusFilter,
              options: ['Semua', 'Pending', 'Proses', 'Selesai'],
              onSelected: (val) => setState(() => _statusFilter = val),
            ),
            const SizedBox(width: 8),

            // Payment Filter Chips
            _filterChipGroup(
              label: 'Bayar:',
              currentVal: _paymentFilter,
              options: ['Semua', 'Lunas', 'Belum Lunas', 'Cicilan'],
              onSelected: (val) => setState(() => _paymentFilter = val),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Data Table
        Expanded(
          child: filtered.isEmpty
              ? _buildEmptyState('Tidak ada pesanan $title yang sesuai dengan filter tanggal atau pencarian.')
              : _buildCategoryOrdersTable(filtered, categoryKey, accentColor),
        ),
      ],
    );
  }

  Widget _filterChipGroup({
    required String label,
    required String currentVal,
    required List<String> options,
    required ValueChanged<String> onSelected,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: StyleConstants.borderLight),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: StyleConstants.textMuted)),
          const SizedBox(width: 4),
          ...options.map((opt) {
            final isSel = currentVal == opt;
            return InkWell(
              onTap: () => onSelected(opt),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isSel ? StyleConstants.sidebarBackground : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  opt,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isSel ? FontWeight.w800 : FontWeight.w600,
                    color: isSel ? Colors.white : StyleConstants.textBody,
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildCategoryOrdersTable(List<Order> orders, String categoryKey, Color accentColor) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: StyleConstants.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Table Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
              border: Border(bottom: BorderSide(color: StyleConstants.borderLight)),
            ),
            child: Row(
              children: [
                const SizedBox(width: 70, child: Text('NOTA', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: StyleConstants.textMuted))),
                const SizedBox(width: 65, child: Text('WAKTU', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: StyleConstants.textMuted))),
                if (categoryKey == 'cuci' || categoryKey == 'pengering')
                  const Expanded(flex: 3, child: Text('MESIN DIGUNAKAN', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: StyleConstants.textMuted))),
                const Expanded(flex: 3, child: Text('PELANGGAN', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: StyleConstants.textMuted))),
                const Expanded(flex: 3, child: Text('RINCIAN ITEM', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: StyleConstants.textMuted))),
                const SizedBox(width: 110, child: Text('STATUS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: StyleConstants.textMuted))),
                const SizedBox(width: 100, child: Text('PEMBAYARAN', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: StyleConstants.textMuted))),
                const SizedBox(width: 110, child: Text('TOTAL', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: StyleConstants.textMuted))),
                const SizedBox(width: 120, child: Text('AKSI', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: StyleConstants.textMuted))),
              ],
            ),
          ),

          // Scrollable Orders List
          Expanded(
            child: ListView.separated(
              itemCount: orders.length,
              separatorBuilder: (ctx, i) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
              itemBuilder: (ctx, i) {
                final order = orders[i];
                final isDone = order.status.toLowerCase() == 'completed' || order.status.toLowerCase() == 'selesai' || order.status.toLowerCase() == 'siap diambil';
                final isProcessing = order.status.toLowerCase() == 'proses' || order.status.toLowerCase() == 'processing';
                final machineInfo = _getMachineInfoForOrder(order, defaultCategory: categoryKey);

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 70,
                        child: Text(
                          '#${order.id}',
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5, color: StyleConstants.primaryColor),
                        ),
                      ),
                      SizedBox(
                        width: 65,
                        child: Text(
                          DateFormat('HH:mm').format(order.orderDate),
                          style: const TextStyle(fontSize: 12, color: StyleConstants.textMuted, fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (categoryKey == 'cuci' || categoryKey == 'pengering')
                        Expanded(
                          flex: 3,
                          child: Row(
                            children: [
                              Icon(
                                categoryKey == 'cuci' ? Icons.local_laundry_service_rounded : Icons.wb_sunny_rounded,
                                size: 15,
                                color: accentColor,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  machineInfo,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12.5,
                                    color: machineInfo.contains('Antrian') ? StyleConstants.warningColor : StyleConstants.textHeading,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(order.customerName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: StyleConstants.textHeading)),
                            if (order.customerPhone != null && order.customerPhone!.isNotEmpty)
                              Text(order.customerPhone!, style: const TextStyle(fontSize: 11, color: StyleConstants.textMuted)),
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          order.items.map((it) => '${it.quantity}x ${it.itemName}').join(', '),
                          style: const TextStyle(fontSize: 12, color: StyleConstants.textBody),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(
                        width: 110,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                          decoration: BoxDecoration(
                            color: isDone ? StyleConstants.statusSuccessBg : (isProcessing ? StyleConstants.statusInfoBg : StyleConstants.statusWarningBg),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            isDone ? 'SELESAI / SUKSES' : (isProcessing ? 'SEDANG PROSES' : 'PENDING'),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: isDone ? StyleConstants.statusSuccessText : (isProcessing ? StyleConstants.statusInfoText : StyleConstants.statusWarningText),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 100,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                          decoration: BoxDecoration(
                            color: order.isPaid ? StyleConstants.statusSuccessBg : StyleConstants.statusDangerBg,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            order.isPaid ? 'LUNAS' : (order.paidAmount > 0 ? 'CICILAN' : 'BELUM BAYAR'),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: order.isPaid ? StyleConstants.statusSuccessText : StyleConstants.statusDangerText,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 110,
                        child: Text(
                          formatRp(order.totalAmount),
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: StyleConstants.textHeading),
                        ),
                      ),
                      SizedBox(
                        width: 120,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.receipt_rounded, size: 17, color: StyleConstants.primaryColor),
                              tooltip: 'Rincian Nota',
                              constraints: const BoxConstraints(),
                              padding: const EdgeInsets.all(6),
                              onPressed: () => _showOrderDetailsDialog(order),
                            ),
                            if (!order.isPaid) ...[
                              const SizedBox(width: 4),
                              IconButton(
                                icon: const Icon(Icons.payments_rounded, size: 17, color: StyleConstants.successColor),
                                tooltip: 'Pelunasan',
                                constraints: const BoxConstraints(),
                                padding: const EdgeInsets.all(6),
                                onPressed: () => _showOrderPaymentDialog(order),
                              ),
                            ],
                            const SizedBox(width: 4),
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert_rounded, size: 16, color: StyleConstants.textMuted),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              tooltip: 'Ubah Status',
                              onSelected: (newStatus) async {
                                await _orderRepo.updateOrderStatus(order.id!, newStatus);
                                _loadAllData();
                                Globals.showSuccessSnackBar('Status pengerjaan diperbarui menjadi $newStatus');
                              },
                              itemBuilder: (ctx) => [
                                const PopupMenuItem(value: 'Pending', child: Text('Set: Pending')),
                                const PopupMenuItem(value: 'Proses', child: Text('Set: Proses')),
                                const PopupMenuItem(value: 'Selesai', child: Text('Set: Selesai')),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // EMPTY STATE HELPER
  // ==========================================
  Widget _buildEmptyState(String message) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: StyleConstants.borderLight),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Color(0xFFF1F5F9),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.inbox_rounded, size: 36, color: StyleConstants.textMuted),
            ),
            const SizedBox(height: 14),
            Text(
              message,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: StyleConstants.textMuted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------
// HELPER DATA CLASS FOR REVENUE ACCUMULATION
// ----------------------------------------------------
class _CategoryData {
  int totalPendapatan = 0;
  int totalDiterima = 0;
  int totalPiutang = 0;
  int totalCash = 0;
  int totalQRIS = 0;
  int countLunas = 0;
  int countCicilan = 0;
  int countBelum = 0;
}
