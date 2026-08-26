import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../utils/globals.dart';
import '../../database/models/order_model.dart';
import '../../database/models/database_helper.dart';
import 'package:intl/intl.dart'; // Tambahkan untuk format mata uang
import '../../services/machine_status_service.dart';

class HistoryMesinCuciPage extends StatefulWidget {
  const HistoryMesinCuciPage({Key? key}) : super(key: key);

  @override
  _HistoryMesinCuciPageState createState() => _HistoryMesinCuciPageState();
}

class _HistoryMesinCuciPageState extends State<HistoryMesinCuciPage>
    with WidgetsBindingObserver {
  // Palet Warna dan Konstanta
  final Color _primaryColor = const Color(0xFF4E80EE);
  final Color _backgroundColor = const Color(0xFFF5F7FA);

  final DatabaseHelper _db = DatabaseHelper.instance;
  List<Map<String, dynamic>> _usageHistory = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadData();
    _searchController.addListener(_applySearch);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
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
      // Fetch machine usage history for washers only
      final usageRecords = await _db.getMachineUsageHistory(type: 'cuci');

      // Apply date range filter
      List<Map<String, dynamic>> dateFiltered = usageRecords;
      dateFiltered = usageRecords.where((record) {
        final startedAt = DateTime.parse(
          record['started_at'] as String,
        ).toLocal();
        return startedAt.year == _selectedDate.year &&
               startedAt.month == _selectedDate.month &&
               startedAt.day == _selectedDate.day;
      }).toList();

      setState(() {
        _usageHistory = dateFiltered;
        _filtered = dateFiltered;
        _isLoading = false;
      });
    } catch (e, st) {
      debugPrint('ERROR in _loadData: $e\n$st');
      setState(() {
        _usageHistory = [];
        _isLoading = false;
      });
    }
  }

  void _applySearch() {
    final q = _searchController.text.toLowerCase();
    setState(() {
      if (q.isEmpty) {
        _filtered = _usageHistory;
      } else {
        _filtered = _usageHistory.where((record) {
          final customerName = (record['customer_name'] as String? ?? '')
              .toLowerCase();
          final machineName = (record['machine_name'] as String? ?? '')
              .toLowerCase();
          return customerName.contains(q) || machineName.contains(q);
        }).toList();
      }
    });
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
      _loadData();
    }
  }

  void _showStatistics() {
    int totalUsage = _filtered.length;
    int countSuccess = 0;
    int countFailed = 0;
    int countSended = 0;
    Map<String, int> machineCount = {};
    Map<String, int> machineSuccess = {};
    Map<String, int> machineFailed = {};

    for (var record in _filtered) {
      final status = record['status'] as String? ?? 'Success';
      if (status == 'Success') countSuccess++;
      else if (status == 'Failed') countFailed++;
      else countSended++;

      final name = record['machine_name'] as String? ?? 'Mesin Tak Dikenal';
      machineCount[name] = (machineCount[name] ?? 0) + 1;
      if (status == 'Success') machineSuccess[name] = (machineSuccess[name] ?? 0) + 1;
      if (status == 'Failed') machineFailed[name] = (machineFailed[name] ?? 0) + 1;
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
          decoration: const BoxDecoration(color: Color(0xFFF5F7FA), borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          child: Column(children: [
            Container(margin: const EdgeInsets.only(top: 12, bottom: 8), width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(children: [
                Icon(Icons.local_laundry_service_rounded, color: _primaryColor, size: 24),
                const SizedBox(width: 10),
                Text('Statistik Mesin Cuci', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
              ]),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(controller: scrollController, padding: const EdgeInsets.all(20), children: [
                // Summary cards
                Row(children: [
                  Expanded(child: _mStatCard('Total\nPenggunaan', '$totalUsage kali', _primaryColor, Icons.repeat_rounded)),
                  const SizedBox(width: 10),
                  Expanded(child: _mStatCard('Tingkat\nSukses', '$successRate%', Colors.green, Icons.check_circle_rounded)),
                  const SizedBox(width: 10),
                  Expanded(child: _mStatCard('Total\nMesin', '${machineCount.length}', Colors.purple, Icons.precision_manufacturing_rounded)),
                ]),
                const SizedBox(height: 24),

                // Activation Status
                _mSectionTitle('STATUS AKTIVASI'),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
                  child: Column(children: [
                    _mStatusBar(Icons.check_circle, 'Berhasil', countSuccess, Colors.green, totalUsage),
                    const SizedBox(height: 12),
                    _mStatusBar(Icons.send, 'Terkirim', countSended, Colors.blue, totalUsage),
                    const SizedBox(height: 12),
                    _mStatusBar(Icons.cancel, 'Gagal', countFailed, Colors.red, totalUsage),
                  ]),
                ),
                const SizedBox(height: 24),

                // Per machine breakdown
                _mSectionTitle('Detail per Mesin'),
                const SizedBox(height: 12),
                if (machineCount.isEmpty)
                  Center(child: Padding(padding: const EdgeInsets.all(20), child: Text('Belum ada data', style: TextStyle(color: Colors.grey[500]))))
                else
                  ...(machineCount.keys.toList()..sort()).map((name) {
                    final total = machineCount[name] ?? 0;
                    final success = machineSuccess[name] ?? 0;
                    final failed = machineFailed[name] ?? 0;
                    final pct = totalUsage > 0 ? (total / totalUsage) : 0.0;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8)]),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          Row(children: [
                            Icon(Icons.local_laundry_service_rounded, size: 16, color: _primaryColor),
                            const SizedBox(width: 8),
                            Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                          ]),
                          Text('$total kali', style: TextStyle(fontWeight: FontWeight.bold, color: _primaryColor, fontSize: 14)),
                        ]),
                        const SizedBox(height: 8),
                        ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: pct, backgroundColor: Colors.grey[200], valueColor: AlwaysStoppedAnimation(_primaryColor), minHeight: 6)),
                        const SizedBox(height: 6),
                        Row(children: [
                          Icon(Icons.check_circle, size: 14, color: Colors.green),
                          Text(' $success berhasil', style: TextStyle(fontSize: 12, color: Colors.green[700])),
                          if (failed > 0) ...[
                            const SizedBox(width: 12),
                            Icon(Icons.error, size: 14, color: Colors.red),
                            Text(' $failed gagal', style: TextStyle(fontSize: 12, color: Colors.red[700])),
                          ],
                          const Spacer(),
                          Text('${(pct * 100).toStringAsFixed(1)}% dari total', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                        ]),
                      ]),
                    );
                  }),
                const SizedBox(height: 40),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _mStatCard(String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: color.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, 4))]),
      child: Column(children: [
        Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle), child: Icon(icon, color: color, size: 20)),
        const SizedBox(height: 8),
        Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: color), textAlign: TextAlign.center),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600]), textAlign: TextAlign.center),
      ]),
    );
  }

  Widget _mSectionTitle(String t) => Container(
    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
    decoration: BoxDecoration(color: _primaryColor.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
    child: Text(t, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _primaryColor, letterSpacing: 1.2)),
  );

  Widget _mStatusBar(IconData icon, String label, int count, Color color, int total) {
    final pct = total > 0 ? (count / total) : 0.0;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
        Text('$count kali', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
      ]),
      const SizedBox(height: 6),
      Row(children: [
        Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: pct, backgroundColor: Colors.grey[200], valueColor: AlwaysStoppedAnimation(color), minHeight: 6))),
        const SizedBox(width: 12),
        Text('${(pct * 100).toStringAsFixed(0)}%', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: color)),
      ]),
    ]);
  }

  String _formatDate(DateTime dt) {
    return DateFormat('dd MMM yyyy, HH:mm').format(dt);
  }

  void _showDetails(Map<String, dynamic> record) async {
    final orderId = record['order_id'] as int?;
    if (orderId == null) return;

    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    final Order? order = await _db.getOrder(orderId);
    Navigator.pop(context); // Close loading

    if (order == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Detail pesanan tidak ditemukan')),
      );
      return;
    }

    final startedAt = DateTime.parse(record['started_at'] as String);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Detail Log Mesin Cuci',
          style: TextStyle(fontWeight: FontWeight.bold, color: _primaryColor),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow(
                label: 'Nama Pelanggan',
                value: order.customerName,
                isBold: true,
              ),
              _buildDetailRow(
                label: 'Tanggal Pesanan',
                value: _formatDate(order.orderDate),
              ),
              const Divider(height: 20),
              _buildDetailRow(
                label: 'Mesin Digunakan',
                value: record['machine_name'] ?? '-',
              ),
              _buildDetailRow(
                label: 'Waktu Mulai Cuci',
                value: _formatDate(startedAt),
              ),
              _buildDetailRow(
                label: 'Status Pesanan',
                value: order.status,
                color: order.status == 'Selesai' ? Colors.green : Colors.orange,
              ),
              _buildDetailRow(
                label: 'Total Biaya',
                value: _formatCurrency(order.totalAmount.toDouble()),
                color: Colors.green,
                isBold: true,
              ),
              const Divider(height: 20),
              _buildDetailRow(
                label: 'Status Aktivasi',
                value: record['status'] ?? 'Success',
                color: _getStatusColor(record['status']),
                isBold: true,
              ),
              if (record['error_message'] != null)
                _buildDetailRow(
                  label: 'Detail Error',
                  value: record['error_message'],
                  color: Colors.red,
                ),

              const Divider(height: 20),
              Text(
                'Item Laundry:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              ...order.items
                  .map(
                    (it) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text('${it.quantity}x ${it.itemName}'),
                          ),
                          Text(
                            _formatCurrency(it.price * it.quantity.toDouble()),
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Tutup', style: TextStyle(color: _primaryColor)),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow({
    required String label,
    required String value,
    Color color = Colors.black87,
    bool isBold = false,
  }) {
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

  String _formatCurrency(double amount) {
    final format = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp',
      decimalDigits: 0,
    );
    return format.format(amount).replaceAll(',', '.');
  }

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'Success':
        return Colors.green;
      case 'Failed':
        return Colors.red;
      case 'Sended':
        return Colors.blue;
      default:
        return Colors.green;
    }
  }

  Future<void> _retryActivation(Map<String, dynamic> record) async {
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
        title: const Text('Konfirmasi'),
        content: Text('Coba nyalakan kembali ${machine.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Coba Lagi'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      String endpoint = '';

      // Try to get dynamic URL from service first
      final states = MachineStatusService.instance.states;
      final entry = states[machine.name] ?? states[machine.key];
      if (entry != null &&
          entry['url'] != null &&
          entry['url'].toString().isNotEmpty) {
        endpoint = entry['url'].toString();
      } else {
        endpoint = machine.url;
      }

      final String sanitizedName = order.customerName
          .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')
          .toLowerCase();

      String fullUrl = endpoint;
      if (fullUrl.endsWith('/on')) {
        fullUrl = '$fullUrl/$sanitizedName';
      } else if (!fullUrl.contains('/on')) {
        fullUrl = fullUrl.endsWith('/')
            ? '${fullUrl}on/$sanitizedName'
            : '$fullUrl/on/$sanitizedName';
      }

      final resp = await http
          .get(Uri.parse(fullUrl))
          .timeout(const Duration(seconds: 15));

      Navigator.pop(context); // Close loading dialog

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        await _db.updateMachineUsageStatus(
          historyId: record['id'] as int,
          status: 'Success',
          errorMessage: null,
        );
        Globals.showSuccessSnackBar(
          'Mesin ${machine.name} berhasil dinyalakan (Retry)!',
        );
        _loadData(); // Refresh history
      } else {
        await _db.updateMachineUsageStatus(
          historyId: record['id'] as int,
          status: 'Failed',
          errorMessage: 'Retry Failed: HTTP ${resp.statusCode}',
        );
        Globals.showErrorSnackBar('Gagal (Retry): Respon ${resp.statusCode}');
      }
    } catch (e) {
      Navigator.pop(context); // Close loading dialog
      await _db.updateMachineUsageStatus(
        historyId: record['id'] as int,
        status: 'Failed',
        errorMessage: 'Retry Error: $e',
      );
      Globals.showErrorSnackBar('Error koneksi mesin (Retry)');
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}';
    final isToday = _selectedDate.year == DateTime.now().year &&
        _selectedDate.month == DateTime.now().month &&
        _selectedDate.day == DateTime.now().day;

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
            onPressed: _selectDate,
            icon: Icon(Icons.calendar_today, size: 18, color: _primaryColor),
            label: Text(
              isToday ? 'Hari Ini' : dateStr,
              style: TextStyle(color: _primaryColor, fontWeight: FontWeight.bold),
            ),
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
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 15,
                  horizontal: 20,
                ),
                fillColor: Colors.white,
                filled: true,
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(_primaryColor),
                    ),
                  )
                : _filtered.isEmpty
                ? Center(
                    child: Text(
                      'Belum ada riwayat penggunaan mesin cuci.',
                      style: TextStyle(color: Colors.grey[600], fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.only(
                      left: 16,
                      right: 16,
                      bottom: 20,
                    ),
                    itemCount: _filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (ctx, idx) {
                      final record = _filtered[idx];
                      return _buildMachineUsageCard(record);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMachineUsageCard(Map<String, dynamic> record) {
    final startedAt = DateTime.parse(record['started_at'] as String);
    final machineNameDisplay =
        record['machine_name'] as String? ?? 'Mesin Tidak Diketahui';
    final customerName =
        record['customer_name'] as String? ?? 'Pelanggan Tidak Diketahui';

    return InkWell(
      onTap: () => _showDetails(record),
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
                  Row(
                    children: [
                      Icon(
                        Icons.local_laundry_service_rounded,
                        size: 20,
                        color: _primaryColor,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        machineNameDisplay,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: _primaryColor,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    _formatDate(startedAt),
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
              const Divider(height: 15),
              Text(
                customerName,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'ID Pesanan: #${record['order_id']}',
                    style: TextStyle(color: Colors.grey[500], fontSize: 13),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _getStatusColor(record['status']).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      record['status'] ?? 'Success',
                      style: TextStyle(
                        color: _getStatusColor(record['status']),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              if (record['status'] == 'Failed')
                Padding(
                  padding: const EdgeInsets.only(top: 12.0),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _retryActivation(record),
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Coba Nyalakan Lagi'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
