import 'package:flutter/material.dart';
import '../../database/models/order_model.dart';
import '../../transactions/order_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../database/models/database_helper.dart';
import '../../utils/currency_format.dart';

class HistoryPage extends StatefulWidget {
  @override
  _HistoryPageState createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final OrderRepository _repository = OrderRepository();
  late DatabaseHelper _databaseHelper;
  List<Order> _orders = [];
  List<Order> _filteredOrders = [];
  bool _isLoading = true;
  DateTime _selectedDate = DateTime.now();
  final TextEditingController _searchController = TextEditingController();

  // Filters state
  String _statusFilter = 'Semua'; // Semua, Pending, Proses, Selesai
  String _paymentFilter = 'Semua'; // Semua, Lunas, Belum Lunas, Cicilan

  final Color primaryColor = const Color(0xFF4E80EE);
  final Color backgroundColor = const Color(0xFFF8FAFC);

  @override
  void initState() {
    super.initState();
    _databaseHelper = DatabaseHelper.instance;
    _loadOrders();
    _searchController.addListener(_filterOrders);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadOrders() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    
    // Retrieve all orders for user
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('user_id');
    final all = await _repository.getAllOrders(userId: userId);
    
    // Filter by selected date on date string (YYYY-MM-DD)
    final dateStr = _formatDateString(_selectedDate);
    final dayOrders = all.where((o) => o.orderDate.toIso8601String().startsWith(dateStr)).toList();

    if (mounted) {
      setState(() {
        _orders = dayOrders;
        _isLoading = false;
        _filterOrders();
      });
    }
  }

  String _formatDateString(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  void _filterOrders() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredOrders = _orders.where((order) {
        // Query text matches customer or items
        final matchesQuery = query.isEmpty ||
            order.customerName.toLowerCase().contains(query) ||
            order.items.any((item) => item.itemName.toLowerCase().contains(query));
        
        // Status filter match
        bool matchesStatus = true;
        if (_statusFilter != 'Semua') {
          final s = order.status.toLowerCase();
          if (_statusFilter == 'Pending') matchesStatus = (s == 'pending');
          if (_statusFilter == 'Proses') matchesStatus = (s == 'proses' || s == 'processing');
          if (_statusFilter == 'Selesai') matchesStatus = (s == 'completed' || s == 'selesai');
        }

        // Payment status filter match
        bool matchesPayment = true;
        if (_paymentFilter != 'Semua') {
          if (_paymentFilter == 'Lunas') matchesPayment = order.isPaid;
          if (_paymentFilter == 'Belum Lunas') matchesPayment = (!order.isPaid && order.paidAmount == 0);
          if (_paymentFilter == 'Cicilan') matchesPayment = (!order.isPaid && order.paidAmount > 0);
        }

        return matchesQuery && matchesStatus && matchesPayment;
      }).toList();
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
      _loadOrders();
    }
  }

  Future<void> _updateOrderStatus(Order order, String newStatus) async {
    final success = await _repository.updateOrderStatus(order.id!, newStatus);
    if (success) {
      _loadOrders();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Status pengerjaan berhasil diperbarui!'), backgroundColor: Colors.green),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('❌ Gagal memperbarui status pengerjaan'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showPaymentDialog(Order order) {
    final sisaTagihan = order.totalAmount - order.paidAmount;
    final controller = TextEditingController(text: sisaTagihan.toString());
    String selectedMethod = 'cash';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Pelunasan Pembayaran', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Pelanggan: ${order.customerName}', style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text('Total Nota: ${formatRp(order.totalAmount)}'),
              Text('Sudah Dibayar: ${formatRp(order.paidAmount)}'),
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
              const SizedBox(height: 16),
              const Text('Metode Pembayaran:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Radio<String>(
                    value: 'cash',
                    groupValue: selectedMethod,
                    onChanged: (val) => setStateDialog(() => selectedMethod = val!),
                  ),
                  const Text('Tunai'),
                  const SizedBox(width: 20),
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
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
            ElevatedButton(
              onPressed: () async {
                final inputAmount = int.tryParse(controller.text) ?? 0;
                if (inputAmount <= 0) {
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('⚠️ Nominal bayar tidak valid')));
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

                await _databaseHelper.updateOrder(updated);
                Navigator.pop(ctx);
                _loadOrders();

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(isFullyPaid ? '✅ Pembayaran Lunas berhasil!' : '✅ Cicilan masuk berhasil dicatat!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
  }

  void _showOrderDetails(Order order) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Rincian Nota #${order.id}', style: const TextStyle(fontWeight: FontWeight.bold)),
            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
          ],
        ),
        content: Container(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Pelanggan: ${order.customerName}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  Text(order.customerPhone ?? '', style: TextStyle(color: Colors.grey[500], fontSize: 13)),
                ],
              ),
              const SizedBox(height: 6),
              Text('Waktu Order: ${_formatDateTime(order.orderDate)}', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),

              const Text('Layanan/Item Belanja:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF475569))),
              const SizedBox(height: 10),
              ...order.items.map((it) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('${it.quantity}x ${it.itemName}', style: const TextStyle(fontSize: 13)),
                        Text(formatRp(it.price * it.quantity), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      ],
                    ),
                  )),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total Biaya:', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(formatRp(order.totalAmount), style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Jumlah Dibayar:', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                  Text(formatRp(order.paidAmount), style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                ],
              ),
              if (!order.isPaid) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Kekurangan Bayar:', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                    Text(formatRp(order.totalAmount - order.paidAmount), style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        actions: [
          if (!order.isPaid)
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _showPaymentDialog(order);
              },
              icon: const Icon(Icons.payment_rounded, size: 16),
              label: const Text('Lakukan Pelunasan'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.grey[200], foregroundColor: Colors.black),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day.toString().padLeft(2, '0')}/${dateTime.month.toString().padLeft(2, '0')}/${dateTime.year} '
        '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Colors.orange;
      case 'proses':
      case 'processing':
        return Colors.blue;
      case 'completed':
      case 'selesai':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}';
    final isToday = _selectedDate.year == DateTime.now().year &&
        _selectedDate.month == DateTime.now().month &&
        _selectedDate.day == DateTime.now().day;

    // Calculate dynamic stats for the active left bar
    int revenueTotal = 0;
    int receivedTotal = 0;
    int unpaidTotal = 0;

    for (var o in _filteredOrders) {
      revenueTotal += o.totalAmount;
      receivedTotal += o.paidAmount;
      unpaidTotal += (o.totalAmount - o.paidAmount);
    }

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text('Riwayat Transaksi Laundry', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Left Sidebar: Datepicker, bookkeeping statistics counters and quick filters (340px)
          Container(
            width: 340,
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(right: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Date picker
                  ElevatedButton.icon(
                    onPressed: _selectDate,
                    icon: Icon(Icons.calendar_month_rounded, size: 16, color: primaryColor),
                    label: Text(
                      isToday ? 'Hari Ini ($dateStr)' : dateStr,
                      style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor.withOpacity(0.06),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 24),

                  const Text('Rangkuman Pendapatan', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A))),
                  const SizedBox(height: 14),

                  // Total Revenue Card (Grand total)
                  _buildStatTile(
                    label: 'Total Nilai Nota',
                    value: formatRp(revenueTotal),
                    color: primaryColor,
                    icon: Icons.receipt_long_rounded,
                  ),
                  const SizedBox(height: 10),

                  // Received Cash
                  _buildStatTile(
                    label: 'Uang Masuk (Kas)',
                    value: formatRp(receivedTotal),
                    color: Colors.green,
                    icon: Icons.account_balance_wallet_rounded,
                  ),
                  const SizedBox(height: 10),

                  // Unpaid Piutang
                  _buildStatTile(
                    label: 'Total Piutang',
                    value: formatRp(unpaidTotal),
                    color: Colors.redAccent,
                    icon: Icons.pending_actions_rounded,
                  ),
                  const SizedBox(height: 28),
                  const Divider(height: 1),
                  const SizedBox(height: 24),

                  // Filter 1: Status Kerja
                  const Text('Filter Status Pengerjaan', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF334155))),
                  const SizedBox(height: 10),
                  _buildFilterChips(
                    options: ['Semua', 'Pending', 'Proses', 'Selesai'],
                    currentValue: _statusFilter,
                    onChanged: (val) {
                      setState(() {
                        _statusFilter = val;
                        _filterOrders();
                      });
                    },
                  ),
                  const SizedBox(height: 20),

                  // Filter 2: Status Pembayaran
                  const Text('Filter Status Bayar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF334155))),
                  const SizedBox(height: 10),
                  _buildFilterChips(
                    options: ['Semua', 'Lunas', 'Belum Lunas', 'Cicilan'],
                    currentValue: _paymentFilter,
                    onChanged: (val) {
                      setState(() {
                        _paymentFilter = val;
                        _filterOrders();
                      });
                    },
                  ),
                ],
              ),
            ),
          ),

          // 2. Right Expanded Area: Orders ledger table
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(28.0),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.grey[200]!),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.01), blurRadius: 10)],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Search & Reload row
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            decoration: InputDecoration(
                              hintText: 'Cari nama pelanggan atau item laundry...',
                              hintStyle: TextStyle(fontSize: 13, color: Colors.grey[400]),
                              prefixIcon: const Icon(Icons.search_rounded, size: 20),
                              filled: true,
                              fillColor: Colors.grey[50],
                              contentPadding: const EdgeInsets.all(12),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.grey[200]!),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        IconButton(
                          icon: const Icon(Icons.refresh_rounded, size: 20),
                          onPressed: _loadOrders,
                          tooltip: 'Muat ulang data',
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Divider(height: 1),

                    // Ledger Table
                    Expanded(
                      child: _isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : _filteredOrders.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.search_off_rounded, size: 48, color: Colors.grey[300]),
                                      const SizedBox(height: 12),
                                      const Text('Tidak ada riwayat transaksi cocok', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                                    ],
                                  ),
                                )
                              : ListView.separated(
                                  padding: const EdgeInsets.only(top: 16),
                                  itemCount: _filteredOrders.length,
                                  separatorBuilder: (_, __) => const Divider(height: 1),
                                  itemBuilder: (context, index) {
                                    final order = _filteredOrders[index];
                                    final isLunas = order.isPaid;
                                    final isCicilan = !order.isPaid && order.paidAmount > 0;
                                    final sisa = order.totalAmount - order.paidAmount;

                                    return Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                                      child: Row(
                                        children: [
                                          // Nota ID Badge
                                          Container(
                                            width: 60,
                                            padding: const EdgeInsets.symmetric(vertical: 6),
                                            decoration: BoxDecoration(
                                              color: primaryColor.withOpacity(0.06),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Center(
                                              child: Text(
                                                '#${order.id}',
                                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: primaryColor),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 16),

                                          // Time & Customer Name
                                          Expanded(
                                            flex: 3,
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  order.customerName,
                                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Color(0xFF0F172A)),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  _formatDateTime(order.orderDate),
                                                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                                                ),
                                              ],
                                            ),
                                          ),

                                          // Status Kerja
                                          Expanded(
                                            flex: 2,
                                            child: Align(
                                              alignment: Alignment.centerLeft,
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: _getStatusColor(order.status).withOpacity(0.08),
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  order.status,
                                                  style: TextStyle(
                                                    color: _getStatusColor(order.status),
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 11,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),

                                          // Status Bayar Tag
                                          Expanded(
                                            flex: 3,
                                            child: Align(
                                              alignment: Alignment.centerLeft,
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: isLunas 
                                                      ? Colors.green.withOpacity(0.08)
                                                      : (isCicilan 
                                                          ? Colors.orange.withOpacity(0.08) 
                                                          : Colors.red.withOpacity(0.08)),
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  isLunas 
                                                    ? 'Lunas' 
                                                    : (isCicilan ? 'Cicilan (Sisa ${formatRp(sisa)})' : 'Belum Bayar'),
                                                  style: TextStyle(
                                                    color: isLunas 
                                                        ? Colors.green 
                                                        : (isCicilan ? Colors.orange[800] : Colors.red),
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 11,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),

                                          // Total Price
                                          Expanded(
                                            flex: 2,
                                            child: Align(
                                              alignment: Alignment.centerRight,
                                              child: Text(
                                                formatRp(order.totalAmount),
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Color(0xFF1E293B)),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 24),

                                          // Action buttons (view/edit details)
                                          IconButton(
                                            icon: const Icon(Icons.visibility_rounded, size: 20, color: Color(0xFF64748B)),
                                            onPressed: () => _showOrderDetails(order),
                                            tooltip: 'Rincian detail',
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatTile({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withOpacity(0.1),
            radius: 18,
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                const SizedBox(height: 2),
                Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips({
    required List<String> options,
    required String currentValue,
    required ValueChanged<String> onChanged,
  }) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: options.map((opt) {
        final isSelected = opt == currentValue;
        return InkWell(
          onTap: () => onChanged(opt),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isSelected ? primaryColor : Colors.grey[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: isSelected ? primaryColor : Colors.grey[200]!),
            ),
            child: Text(
              opt,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.white : const Color(0xFF475569),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
