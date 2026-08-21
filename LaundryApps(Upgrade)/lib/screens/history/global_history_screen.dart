import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../database/models/database_helper.dart';
import '../../database/models/transaction_model.dart';
import '../../transactions/transaction_repository.dart';
import '../../utils/currency_format.dart';
import '../../utils/pdf_export_helper.dart';
import '../../utils/style_constants.dart';

class GlobalHistoryScreen extends StatefulWidget {
  const GlobalHistoryScreen({super.key});

  @override
  State<GlobalHistoryScreen> createState() => _GlobalHistoryScreenState();
}

class _GlobalHistoryScreenState extends State<GlobalHistoryScreen> {
  final DatabaseHelper _db = DatabaseHelper.instance;

  bool _isLoading = true;
  DateTime _selectedDate = DateTime.now();
  String _activeTab = 'semua'; // 'semua', 'cuci', 'gosok', 'pengeluaran'

  // Global totals
  int _totalPengeluaran = 0;

  // Per-category data class
  _CategoryData _laundry = _CategoryData();
  _CategoryData _gosok = _CategoryData();

  List<Map<String, dynamic>> _laundryList = [];
  List<Map<String, dynamic>> _gosokList = [];
  List<Map<String, dynamic>> _pengeluaranList = [];
  List<Map<String, dynamic>> _combinedEntries = [];

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
        'id': order.id,
        'title': order.customerName,
        'category': isGosok ? 'Setrika / Gosok' : 'Cuci & Kering',
        'status': paymentStatus,
        'payment_method': order.paymentMethod.toUpperCase(),
        'income_amount': order.paidAmount,
        'total_order': order.totalAmount,
        'type': 'income',
        'time': DateFormat('HH:mm').format(order.orderDate),
        'timestamp': order.orderDate,
        'items_count': order.items.fold<int>(0, (s, it) => s + it.quantity),
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
        if (order.paymentMethod.toLowerCase() == 'cash' || order.paymentMethod.toLowerCase().contains('tunai')) {
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

    // Combine and sort by timestamp descending
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
        _gosok = gosok;
        _pengeluaranList = pengeluaranList;
        _laundryList = laundryList;
        _gosokList = gosokList;
        _combinedEntries = combined;
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

  void _changeDateBy(int days) {
    setState(() {
      _selectedDate = _selectedDate.add(Duration(days: days));
    });
    _loadData();
  }

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
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: StyleConstants.primaryColor.withValues(alpha: 0.1),
                    child: const Icon(Icons.today_rounded, color: StyleConstants.primaryColor),
                  ),
                  title: const Text('Laporan Harian (Hari Terpilih)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  subtitle: Text(DateFormat('EEEE, dd MMMM yyyy').format(_selectedDate), style: const TextStyle(fontSize: 11.5)),
                  onTap: () {
                    Navigator.pop(context);
                    PdfExportHelper.exportLedgerToPdf(
                      context: context,
                      startDate: _selectedDate,
                      endDate: _selectedDate,
                    );
                  },
                ),
                const Divider(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: StyleConstants.secondaryColor.withValues(alpha: 0.1),
                    child: const Icon(Icons.date_range_rounded, color: StyleConstants.secondaryColor),
                  ),
                  title: const Text('Kustom Rentang Tanggal (Mingguan/Bulanan)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  subtitle: const Text('Pilih periode tanggal mulai s.d. selesai', style: TextStyle(fontSize: 11.5)),
                  onTap: () async {
                    final navigator = Navigator.of(context);
                    final currentContext = this.context;
                    navigator.pop();
                    final pickedRange = await showDateRangePicker(
                      context: currentContext,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                      saveText: 'EKSPOR PDF',
                    );
                    if (pickedRange != null && currentContext.mounted) {
                      PdfExportHelper.exportLedgerToPdf(
                        context: currentContext,
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

  List<Map<String, dynamic>> _getFilteredList() {
    switch (_activeTab) {
      case 'cuci':
        return _laundryList;
      case 'gosok':
        return _gosokList;
      case 'pengeluaran':
        return _pengeluaranList;
      case 'semua':
      default:
        return _combinedEntries;
    }
  }

  @override
  Widget build(BuildContext context) {
    final int totalOmzet = _laundry.totalPendapatan + _gosok.totalPendapatan;
    final int totalKasMasuk = _laundry.totalDiterima + _gosok.totalDiterima;
    final int totalPiutang = _laundry.totalPiutang + _gosok.totalPiutang;
    final int netProfit = totalKasMasuk - _totalPengeluaran;

    final filteredList = _getFilteredList();

    final Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Top Control Bar (Date Range & PDF Actions)
        _buildControlHeader(),
        const SizedBox(height: 14),

        // 2. 4-in-1 Financial KPI Ribbon
        _buildFinancialKpiRibbon(
          totalOmzet: totalOmzet,
          totalKasMasuk: totalKasMasuk,
          totalPiutang: totalPiutang,
          totalPengeluaran: _totalPengeluaran,
          netProfit: netProfit,
        ),
        const SizedBox(height: 14),

        // 3. Filter Tabs Bar
        _buildFilterTabsBar(),
        const SizedBox(height: 10),

        // 4. Data Grid Table (General Ledger)
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : filteredList.isEmpty
                  ? _buildEmptyState()
                  : _buildLedgerTable(filteredList, totalKasMasuk, _totalPengeluaran),
        ),
      ],
    );

    if (Navigator.canPop(context)) {
      return Scaffold(
        backgroundColor: StyleConstants.backgroundColor,
        appBar: AppBar(
          title: const Text('Buku Besar, Kas & Riwayat Global', style: TextStyle(fontWeight: FontWeight.bold)),
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

  Widget _buildControlHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: StyleConstants.cardDecoration(),
      child: Row(
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
          const Spacer(),

          // Export PDF Button
          ElevatedButton.icon(
            onPressed: _showExportPdfDialog,
            icon: const Icon(Icons.picture_as_pdf_rounded, size: 16),
            label: const Text('Ekspor Laporan PDF', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
            style: ElevatedButton.styleFrom(
              backgroundColor: StyleConstants.primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
          ),
        ],
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
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isHighlight ? color.withValues(alpha: 0.4) : StyleConstants.borderLight, width: isHighlight ? 1.5 : 1),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: isHighlight ? 0.12 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: color, width: 3),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        color: isHighlight ? color : StyleConstants.textMuted,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      value,
                      style: StyleConstants.tabularNumbers(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: isHighlight ? color : StyleConstants.textHeading,
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

  Widget _buildFilterTabsBar() {
    return Row(
      children: [
        _tabButton('semua', 'Semua Transaksi (${_combinedEntries.length})'),
        const SizedBox(width: 8),
        _tabButton('cuci', 'Cuci & Kering (${_laundryList.length})'),
        const SizedBox(width: 8),
        _tabButton('gosok', 'Setrika (${_gosokList.length})'),
        const SizedBox(width: 8),
        _tabButton('pengeluaran', 'Pengeluaran Kas (${_pengeluaranList.length})'),
      ],
    );
  }

  Widget _tabButton(String key, String label) {
    final isSelected = _activeTab == key;
    return InkWell(
      onTap: () => setState(() => _activeTab = key),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? StyleConstants.sidebarBackground : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? StyleConstants.sidebarBackground : StyleConstants.borderLight),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: isSelected ? Colors.white : StyleConstants.textBody,
          ),
        ),
      ),
    );
  }

  Widget _buildLedgerTable(List<Map<String, dynamic>> items, int totalIn, int totalOut) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: StyleConstants.borderLight),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Table Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              border: Border(bottom: BorderSide(color: StyleConstants.borderLight)),
            ),
            child: const Row(
              children: [
                SizedBox(width: 75, child: Text('WAKTU', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: StyleConstants.textMuted, letterSpacing: 0.5))),
                Expanded(flex: 3, child: Text('DESKRIPSI / PELANGGAN', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: StyleConstants.textMuted, letterSpacing: 0.5))),
                Expanded(flex: 2, child: Text('KATEGORI', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: StyleConstants.textMuted, letterSpacing: 0.5))),
                Expanded(flex: 2, child: Text('STATUS BAYAR', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: StyleConstants.textMuted, letterSpacing: 0.5))),
                SizedBox(width: 130, child: Text('KAS MASUK', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: StyleConstants.successColor, letterSpacing: 0.5))),
                SizedBox(width: 130, child: Text('PENGELUARAN', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: StyleConstants.dangerColor, letterSpacing: 0.5))),
              ],
            ),
          ),

          // Table Rows List
          Expanded(
            child: ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1, color: StyleConstants.borderLight),
              itemBuilder: (context, index) {
                final entry = items[index];
                final isExpense = entry['type'] == 'expense';

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 70,
                        child: Text(
                          entry['time'] ?? '-',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: StyleConstants.textMuted),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 12,
                              backgroundColor: isExpense ? StyleConstants.statusDangerBg : StyleConstants.statusSuccessBg,
                              child: Icon(
                                isExpense ? Icons.arrow_upward_rounded : Icons.person_rounded,
                                size: 12,
                                color: isExpense ? StyleConstants.dangerColor : StyleConstants.successColor,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                entry['title'] ?? '-',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: StyleConstants.textHeading),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          entry['category'] ?? '-',
                          style: const TextStyle(fontSize: 12, color: StyleConstants.textBody),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: isExpense
                                    ? StyleConstants.statusDangerBg
                                    : (entry['status'].toString().contains('Lunas')
                                        ? StyleConstants.statusSuccessBg
                                        : StyleConstants.statusWarningBg),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                entry['status'] ?? '-',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  color: isExpense
                                      ? StyleConstants.statusDangerText
                                      : (entry['status'].toString().contains('Lunas')
                                          ? StyleConstants.statusSuccessText
                                          : StyleConstants.statusWarningText),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 120,
                        child: Text(
                          !isExpense ? formatRp(entry['income_amount'] ?? 0) : '-',
                          textAlign: TextAlign.right,
                          style: StyleConstants.tabularNumbers(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: !isExpense ? StyleConstants.successColor : StyleConstants.textMuted,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 120,
                        child: Text(
                          isExpense ? formatRp(entry['amount'] ?? 0) : '-',
                          textAlign: TextAlign.right,
                          style: StyleConstants.tabularNumbers(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: isExpense ? StyleConstants.dangerColor : StyleConstants.textMuted,
                          ),
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

  Widget _buildEmptyState() {
    return Container(
      decoration: StyleConstants.cardDecoration(),
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long_outlined, size: 48, color: Color(0xFFCBD5E1)),
            SizedBox(height: 12),
            Text(
              'Belum ada transaksi tercatat pada tanggal ini.',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: StyleConstants.textHeading),
            ),
            SizedBox(height: 4),
            Text(
              'Pilih tanggal lain atau buat transaksi baru dari menu kasir.',
              style: TextStyle(fontSize: 12, color: StyleConstants.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

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
