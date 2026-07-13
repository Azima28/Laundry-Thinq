import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../database/models/database_helper.dart';
import '../../database/models/transaction_model.dart';
import '../../transactions/transaction_repository.dart';
import '../../utils/currency_format.dart';

class GlobalHistoryScreen extends StatefulWidget {
  const GlobalHistoryScreen({Key? key}) : super(key: key);

  @override
  State<GlobalHistoryScreen> createState() => _GlobalHistoryScreenState();
}

class _GlobalHistoryScreenState extends State<GlobalHistoryScreen> {
  final DatabaseHelper _db = DatabaseHelper.instance;

  bool _isLoading = true;
  DateTime _selectedDate = DateTime.now();

  // Global totals
  int _totalPengeluaran = 0;

  // Per-category data class
  _CategoryData _laundry = _CategoryData();
  _CategoryData _gosok = _CategoryData();

  List<Map<String, dynamic>> _laundryList = [];
  List<Map<String, dynamic>> _gosokList = [];
  List<Map<String, dynamic>> _pengeluaranList = [];

  final Color primaryColor = const Color(0xFF4E80EE);

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);

    // 1. Load Pengeluaran
    final expenses = await _db.getExpensesByDate(dateStr);
    int totalPengeluaran = 0;
    List<Map<String, dynamic>> pengeluaranList = [];
    for (var exp in expenses) {
      totalPengeluaran += (exp['amount'] as int);
      pengeluaranList.add({
        'title': exp['name'],
        'amount': exp['amount'],
        'type': 'expense',
        'time': DateFormat('HH:mm').format(DateTime.parse(exp['created_at']))
      });
    }

    // 2. Load Orders
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

    for (var order in orders) {
      bool isGosok = order.items.isNotEmpty &&
          order.items.every((item) => ironItemIds.contains(item.itemId));

      int unpaid = (order.totalAmount - order.paidAmount).clamp(0, order.totalAmount);
      
      String paymentStatus = 'Lunas';
      if (order.paidAmount == 0) {
        paymentStatus = 'Belum Bayar';
      } else if (unpaid > 0) {
        paymentStatus = 'Cicilan (Sisa ${formatRp(unpaid)})';
      }

      Map<String, dynamic> itemData = {
        'title': order.customerName,
        'subtitle': '$paymentStatus • ${order.paymentMethod.toUpperCase()}',
        'amount': order.paidAmount,
        'total': order.totalAmount,
        'type': 'income',
        'time': DateFormat('HH:mm').format(order.orderDate),
      };

      _CategoryData target = isGosok ? gosok : laundry;
      target.totalPendapatan += order.totalAmount;
      target.totalDiterima += order.paidAmount;
      if (unpaid > 0) target.totalPiutang += unpaid;

      if (order.paidAmount == 0) {
        target.countBelum++;
      } else if (unpaid > 0) {
        target.countCicilan++;
      } else {
        target.countLunas++;
      }

      if (order.paidAmount > 0) {
        if (order.paymentMethod.toLowerCase() == 'cash') {
          target.totalCash += order.paidAmount;
        } else {
          target.totalQRIS += order.paidAmount;
        }
      }

      if (isGosok) {
        gosokList.add(itemData);
      } else {
        laundryList.add(itemData);
      }
    }

    if (mounted) {
      setState(() {
        _totalPengeluaran = totalPengeluaran;
        _laundry = laundry;
        _gosok = gosok;
        _pengeluaranList = pengeluaranList;
        _laundryList = laundryList;
        _gosokList = gosokList;
        _isLoading = false;
      });
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
      _loadData();
    }
  }

  // ──────────── UI WIDGETS ────────────

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey[500], letterSpacing: 1)),
    );
  }

  Widget _netProfitCard(int netProfit, String dateStr) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: netProfit >= 0
              ? [primaryColor, const Color(0xFF7CA0F3)]
              : [Colors.red.shade400, Colors.red.shade300],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: (netProfit >= 0 ? primaryColor : Colors.red).withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 6))
        ],
      ),
      child: Column(
        children: [
          const Text('KEUNTUNGAN BERSIH', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
          const SizedBox(height: 8),
          FittedBox(fit: BoxFit.scaleDown, child: Text(formatRp(netProfit), style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold))),
          const SizedBox(height: 4),
          Text(dateStr, style: const TextStyle(color: Colors.white70, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _quickSummaryRow() {
    int totalDiterima = _laundry.totalDiterima + _gosok.totalDiterima;
    int totalPiutang = _laundry.totalPiutang + _gosok.totalPiutang;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _quickCard('Uang Masuk', totalDiterima, Colors.green, Icons.arrow_downward),
            const SizedBox(width: 8),
            _quickCard('Pengeluaran', _totalPengeluaran, Colors.red, Icons.arrow_upward),
            const SizedBox(width: 8),
            _quickCard('Piutang', totalPiutang, Colors.orange, Icons.schedule),
          ],
        ),
      ),
    );
  }

  Widget _quickCard(String title, int amount, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 6),
            Text(title, style: TextStyle(fontSize: 10, color: Colors.grey[600], fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            FittedBox(fit: BoxFit.scaleDown, child: Text(formatRp(amount), style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color))),
          ],
        ),
      ),
    );
  }

  /// Category card — simple and friendly
  Widget _categoryCard(String title, IconData icon, Color color, _CategoryData data, int orderCount) {
    if (orderCount == 0) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.grey.shade200)),
        child: Row(children: [
          Icon(icon, color: Colors.grey[400], size: 22), const SizedBox(width: 10),
          Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[400], fontSize: 15)),
          const Spacer(),
          Text('Belum ada pesanan', style: TextStyle(color: Colors.grey[400], fontSize: 12, fontStyle: FontStyle.italic)),
        ]),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withValues(alpha: 0.2))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
              child: Text('$orderCount pesanan', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
            ),
          ]),

          const SizedBox(height: 16),

          // Total Penjualan
          _highlightRow(Icons.sell, 'Total Penjualan', formatRp(data.totalPendapatan), Colors.black87),
          const SizedBox(height: 6),

          // Uang yang sudah masuk
          _highlightRow(Icons.check_circle_outline, 'Sudah Diterima', formatRp(data.totalDiterima), Colors.green.shade700),
          const SizedBox(height: 6),

          // Belum masuk (piutang)
          _highlightRow(Icons.pending_actions, 'Belum Diterima (Piutang)', formatRp(data.totalPiutang), Colors.orange.shade700),
          
          const SizedBox(height: 12),
          Divider(height: 1, color: Colors.grey.shade200),
          const SizedBox(height: 12),

          // Cara bayar
          Text('Cara Bayar:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey[600])),
          const SizedBox(height: 8),
          Row(children: [
            _miniPill(Icons.payments_outlined, 'Tunai', formatRp(data.totalCash), Colors.teal),
            const SizedBox(width: 8),
            _miniPill(Icons.qr_code_2, 'QRIS', formatRp(data.totalQRIS), Colors.blue),
          ]),

          const SizedBox(height: 12),
          Divider(height: 1, color: Colors.grey.shade200),
          const SizedBox(height: 12),

          // Status pelanggan
          Text('Status Pelanggan:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey[600])),
          const SizedBox(height: 8),
          Row(children: [
            _statusBadge(Icons.check_circle, '${data.countLunas} Lunas', Colors.green),
            const SizedBox(width: 6),
            _statusBadge(Icons.timelapse, '${data.countCicilan} Cicilan', Colors.orange),
            const SizedBox(width: 6),
            _statusBadge(Icons.error_outline, '${data.countBelum} Belum', Colors.red),
          ]),
        ],
      ),
    );
  }

  /// Rincian Total — super simple, like reading a story
  Widget _rincianTotal() {
    int totalPenjualan = _laundry.totalPendapatan + _gosok.totalPendapatan;
    int totalDiterima = _laundry.totalDiterima + _gosok.totalDiterima;
    int totalPiutang = _laundry.totalPiutang + _gosok.totalPiutang;
    int totalCash = _laundry.totalCash + _gosok.totalCash;
    int totalQRIS = _laundry.totalQRIS + _gosok.totalQRIS;
    int countLunas = _laundry.countLunas + _gosok.countLunas;
    int countCicilan = _laundry.countCicilan + _gosok.countCicilan;
    int countBelum = _laundry.countBelum + _gosok.countBelum;
    int totalOrders = countLunas + countCicilan + countBelum;
    int labaBersih = totalDiterima - _totalPengeluaran;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: primaryColor.withValues(alpha: 0.3)),
        boxShadow: [BoxShadow(color: primaryColor.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(color: primaryColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
              child: Icon(Icons.calculate, color: primaryColor, size: 20),
            ),
            const SizedBox(width: 10),
            const Text('Rincian Total', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ]),
          const SizedBox(height: 4),
          Text('Gabungan semua layanan hari ini', style: TextStyle(fontSize: 11, color: Colors.grey[500])),

          const SizedBox(height: 16),

          // ═══ STEP 1: Total Penjualan ═══
          _stepHeader('1', 'Berapa yang terjual?', Colors.blue),
          const SizedBox(height: 8),
          _iconRow(Icons.local_laundry_service, 'Laundry (${_laundryList.length} pesanan)', formatRp(_laundry.totalPendapatan), Colors.blue),
          _iconRow(Icons.iron, 'Gosok (${_gosokList.length} pesanan)', formatRp(_gosok.totalPendapatan), Colors.deepOrange),
          _totalRow('Total Penjualan', formatRp(totalPenjualan)),

          _divider(),

          // ═══ STEP 2: Yang sudah masuk ═══
          _stepHeader('2', 'Yang sudah masuk ke kantong?', Colors.green),
          const SizedBox(height: 8),
          _iconRow(Icons.payments_outlined, 'Bayar Tunai / Cash', formatRp(totalCash), Colors.teal),
          _iconRow(Icons.qr_code_2, 'Bayar QRIS / Digital', formatRp(totalQRIS), Colors.blue),
          _totalRow('Total Uang Masuk', formatRp(totalDiterima)),

          _divider(),

          // ═══ STEP 3: Yang belum masuk ═══
          _stepHeader('3', 'Yang belum masuk? (Piutang)', Colors.orange),
          const SizedBox(height: 8),
          _iconRow(Icons.person_off_outlined, 'Belum bayar sama sekali', '$countBelum orang', Colors.red),
          _iconRow(Icons.hourglass_bottom, 'Bayar sebagian (cicilan)', '$countCicilan orang', Colors.orange),
          _totalRow('Total Piutang', formatRp(totalPiutang)),

          _divider(),

          // ═══ STEP 4: Pengeluaran ═══
          _stepHeader('4', 'Berapa yang keluar? (Pengeluaran)', Colors.red),
          const SizedBox(height: 8),
          if (_pengeluaranList.isEmpty)
            _iconRow(Icons.check, 'Tidak ada pengeluaran', formatRp(0), Colors.grey)
          else
            ..._pengeluaranList.map((e) => _iconRow(Icons.receipt_long, '${e['title']}', formatRp(e['amount'] as int), Colors.red)),
          _totalRow('Total Pengeluaran', '- ${formatRp(_totalPengeluaran)}'),

          const SizedBox(height: 16),

          // ═══ FINAL: Hasil Akhir ═══
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: labaBersih >= 0
                    ? [Colors.green.shade50, Colors.green.shade100]
                    : [Colors.red.shade50, Colors.red.shade100],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: labaBersih >= 0 ? Colors.green.shade200 : Colors.red.shade200),
            ),
            child: Column(
              children: [
                Text('HASIL AKHIR HARI INI', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey[600], letterSpacing: 1)),
                const SizedBox(height: 12),

                // Laba Bersih
                _resultRow(Icons.trending_up, 'Laba Bersih', formatRp(labaBersih),
                  labaBersih >= 0 ? Colors.green.shade800 : Colors.red,
                  '(Uang masuk ${formatRp(totalDiterima)} - Pengeluaran ${formatRp(_totalPengeluaran)})'),

                const SizedBox(height: 10),
                Divider(height: 1, color: Colors.grey.shade300),
                const SizedBox(height: 10),

                // Total Piutang
                _resultRow(Icons.pending_actions, 'Total Piutang', formatRp(totalPiutang),
                  totalPiutang > 0 ? Colors.orange.shade800 : Colors.green,
                  totalPiutang > 0 ? '(Uang yang belum dibayar pelanggan)' : null),

                const SizedBox(height: 10),
                Divider(height: 1, color: Colors.grey.shade300),
                const SizedBox(height: 10),

                // Total Semuanya
                _resultRow(Icons.account_balance_wallet, 'Total Semua', formatRp(totalPenjualan),
                  Colors.blue.shade800,
                  '(Total nilai seluruh pesanan hari ini)'),
              ],
            ),
          ),

          // Statistik kecil
          if (totalOrders > 0) ...[
            const SizedBox(height: 14),
            Row(children: [
              _statusBadge(Icons.receipt_long, '$totalOrders Pesanan', primaryColor),
              const SizedBox(width: 6),
              _statusBadge(Icons.check_circle, '$countLunas Lunas', Colors.green),
              const SizedBox(width: 6),
              _statusBadge(Icons.timelapse, '$countCicilan Cicilan', Colors.orange),
              const SizedBox(width: 6),
              _statusBadge(Icons.error_outline, '$countBelum Belum', Colors.red),
            ]),
          ],
        ],
      ),
    );
  }

  // ──────────── Helper widgets ────────────

  Widget _stepHeader(String number, String title, Color color) {
    return Row(
      children: [
        Container(
          width: 22, height: 22,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: Center(child: Text(number, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: color))),
      ],
    );
  }

  Widget _simpleRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(label, style: TextStyle(fontSize: 13, color: Colors.grey[700]))),
          Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey[800])),
        ],
      ),
    );
  }

  Widget _totalRow(String label, String value) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(6)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _divider() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Divider(height: 1, color: Colors.grey.shade200),
    );
  }

  Widget _highlightRow(IconData icon, String label, String value, Color color) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: TextStyle(fontSize: 13, color: Colors.grey[700]))),
        Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  Widget _iconRow(IconData icon, String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color.withValues(alpha: 0.7)),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: TextStyle(fontSize: 13, color: Colors.grey[700]))),
          Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey[800])),
        ],
      ),
    );
  }

  Widget _resultRow(IconData icon, String label, String value, Color color, String? subtitle) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            ]),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: color)),
            ),
          ],
        ),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(left: 30),
            child: Text(subtitle, style: TextStyle(fontSize: 10, color: Colors.grey[600])),
          ),
      ],
    );
  }

  Widget _miniPill(IconData icon, String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withValues(alpha: 0.15))),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                  FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusBadge(IconData icon, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
            Flexible(child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color), overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    );
  }

  Widget _transactionList(String title, List<Map<String, dynamic>> items, Color color, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(children: [
            Icon(icon, size: 18, color: color), const SizedBox(width: 8),
            Expanded(child: Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
              child: Text('${items.length}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
            ),
          ]),
        ),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Text('Tidak ada data', style: TextStyle(color: Colors.grey[400], fontStyle: FontStyle.italic)),
          )
        else
          ...items.map((item) {
            final isIncome = item['type'] == 'income';
            final subtitle = item['subtitle'] ?? item['time'];
            Color subColor = Colors.grey[600]!;
            if (subtitle.contains('Belum Bayar')) subColor = Colors.red;
            else if (subtitle.contains('Cicilan')) subColor = Colors.orange;
            return Container(
              margin: const EdgeInsets.only(bottom: 4, left: 16, right: 16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade100)),
              child: ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 15,
                  backgroundColor: color.withValues(alpha: 0.1),
                  child: Text((item['title'] as String).isNotEmpty ? (item['title'] as String)[0].toUpperCase() : '?', style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
                ),
                title: Text(item['title'], style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                subtitle: Text(subtitle, style: TextStyle(fontSize: 11, color: subColor, fontWeight: FontWeight.w500)),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${isIncome ? '+' : '-'} ${formatRp(item['amount'])}',
                      style: TextStyle(color: isIncome ? (item['amount'] == 0 ? Colors.grey : Colors.green.shade700) : Colors.red, fontWeight: FontWeight.bold, fontSize: 13)),
                    if (isIncome && item['amount'] != item['total'])
                      Text('dari ${formatRp(item['total'])}', style: TextStyle(fontSize: 10, color: Colors.grey[500])),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('dd MMM yyyy').format(_selectedDate);
    final isToday = DateFormat('yyyy-MM-dd').format(_selectedDate) == DateFormat('yyyy-MM-dd').format(DateTime.now());
    final int totalDiterima = _laundry.totalDiterima + _gosok.totalDiterima;
    final int netProfit = totalDiterima - _totalPengeluaran;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Buku Besar', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          TextButton.icon(
            onPressed: _selectDate,
            icon: const Icon(Icons.calendar_today, size: 18),
            label: Text(isToday ? 'Hari Ini' : dateStr),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    _netProfitCard(netProfit, dateStr),
                    const SizedBox(height: 16),
                    _quickSummaryRow(),

                    const SizedBox(height: 20),
                    _sectionLabel('RINCIAN PER KATEGORI'),
                    const SizedBox(height: 4),
                    _categoryCard('Laundry', Icons.local_laundry_service, Colors.blue, _laundry, _laundryList.length),
                    const SizedBox(height: 4),
                    _categoryCard('Gosok / Setrika', Icons.iron, Colors.deepOrange, _gosok, _gosokList.length),

                    const SizedBox(height: 20),
                    _sectionLabel('RINCIAN TOTAL'),
                    const SizedBox(height: 4),
                    _rincianTotal(),

                    const SizedBox(height: 24),
                    Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Divider(color: Colors.grey.shade300)),
                    const SizedBox(height: 8),

                    _transactionList('Pemasukan Laundry', _laundryList, Colors.blue, Icons.local_laundry_service),
                    const SizedBox(height: 12),
                    _transactionList('Pemasukan Gosok', _gosokList, Colors.deepOrange, Icons.iron),
                    const SizedBox(height: 12),
                    _transactionList('Pengeluaran', _pengeluaranList, Colors.red, Icons.receipt_long),
                  ],
                ),
              ),
            ),
    );
  }
}

/// Helper data class for per-category tracking
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
