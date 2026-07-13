import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../database/models/database_helper.dart';

class PengeluaranScreen extends StatefulWidget {
  const PengeluaranScreen({Key? key}) : super(key: key);

  @override
  State<PengeluaranScreen> createState() => _PengeluaranScreenState();
}

class _PengeluaranScreenState extends State<PengeluaranScreen> {
  final DatabaseHelper _db = DatabaseHelper.instance;
  List<Map<String, dynamic>> _expenses = [];
  bool _isLoading = true;
  DateTime _selectedDate = DateTime.now();
  int _totalExpense = 0;

  // Form Fields Controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();

  final Color primaryColor = const Color(0xFF4E80EE);
  final Color backgroundColor = const Color(0xFFF8FAFC);

  @override
  void initState() {
    super.initState();
    _loadExpenses();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _loadExpenses() async {
    setState(() => _isLoading = true);
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final data = await _db.getExpensesByDate(dateStr);
    
    int total = 0;
    for (var item in data) {
      total += (item['amount'] as int);
    }

    if (mounted) {
      setState(() {
        _expenses = data;
        _totalExpense = total;
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
      setState(() {
        _selectedDate = picked;
      });
      _loadExpenses();
    }
  }

  Future<void> _saveExpense() async {
    final name = _nameController.text.trim();
    final amountStr = _amountController.text.trim();
    if (name.isEmpty || amountStr.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Harap isi nama dan jumlah uang pengeluaran'), backgroundColor: Colors.orange),
      );
      return;
    }
    final amount = int.tryParse(amountStr);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Jumlah uang pengeluaran tidak valid'), backgroundColor: Colors.orange),
      );
      return;
    }

    await _db.insertExpense({
      'name': name,
      'amount': amount,
      'date': DateFormat('yyyy-MM-dd').format(_selectedDate),
      'created_at': DateTime.now().toIso8601String(),
    });

    _nameController.clear();
    _amountController.clear();
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✅ Pengeluaran berhasil disimpan'), backgroundColor: Colors.green),
    );

    _loadExpenses();
  }

  Future<void> _deleteExpense(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Hapus Pengeluaran?', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('Apakah Anda yakin ingin menghapus data pengeluaran ini?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _db.deleteExpense(id);
      _loadExpenses();
    }
  }

  String _formatRp(int amount) {
    String s = amount.toString();
    String result = '';
    int count = 0;
    for (int i = s.length - 1; i >= 0; i--) {
      result = s[i] + result;
      count++;
      if (count == 3 && i > 0) {
        result = '.' + result;
        count = 0;
      }
    }
    return 'Rp $result';
  }

  InputDecoration _inputDecoration(String label, String hint, IconData icon, {String? prefixText}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixText: prefixText,
      labelStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
      hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
      floatingLabelStyle: const TextStyle(color: Color(0xFF4E80EE), fontWeight: FontWeight.bold),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF4E80EE), width: 2),
      ),
      prefixIcon: Icon(icon, color: const Color(0xFF64748B), size: 20),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('dd MMM yyyy').format(_selectedDate);
    final isToday = DateFormat('yyyy-MM-dd').format(_selectedDate) == DateFormat('yyyy-MM-dd').format(DateTime.now());

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Left Sidebar: Date picker, summary, and direct input form (340px)
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
                // Date picker trigger button
                ElevatedButton.icon(
                  onPressed: _selectDate,
                  icon: Icon(Icons.calendar_today_rounded, size: 16, color: primaryColor),
                  label: Text(
                    isToday ? 'Hari Ini ($dateStr)' : dateStr,
                    style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor.withOpacity(0.06),
                    foregroundColor: primaryColor,
                    elevation: 0,
                    shadowColor: Colors.transparent,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 20),

                // Total Expense Card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFEF4444), Color(0xFFF87171)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFEF4444).withOpacity(0.2),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      )
                    ],
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Total Pengeluaran',
                        style: TextStyle(color: Color(0xCCFFFFFF), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _formatRp(_totalExpense),
                        style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        dateStr,
                        style: const TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                const Divider(color: Color(0xFFF1F5F9)),
                const SizedBox(height: 24),

                // Add Expense Form Heading
                const Text(
                  'Tambah Pengeluaran Baru',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF475569), letterSpacing: 0.5),
                ),
                const SizedBox(height: 16),

                // Name Input
                TextField(
                  controller: _nameController,
                  decoration: _inputDecoration(
                    'Nama Item Pengeluaran',
                    'Contoh: Sabun, Token Listrik',
                    Icons.receipt_long_rounded,
                  ),
                ),
                const SizedBox(height: 14),

                // Amount Input
                TextField(
                  controller: _amountController,
                  keyboardType: TextInputType.number,
                  decoration: _inputDecoration(
                    'Jumlah Uang (Rp)',
                    'Contoh: 50000',
                    Icons.payments_rounded,
                    prefixText: 'Rp ',
                  ),
                ),
                const SizedBox(height: 20),

                // Save button
                ElevatedButton(
                  onPressed: _saveExpense,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shadowColor: Colors.transparent,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text(
                    'Simpan Pengeluaran',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ),

        // 2. Right Expanded Area: List of expenses (Table Layout)
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.02),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  )
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Daftar Rincian Pengeluaran',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Catatan pengeluaran operasional laundry',
                            style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${_expenses.length} Transaksi',
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Divider(color: Color(0xFFF1F5F9)),

                  // Table Body
                  Expanded(
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : _expenses.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(20),
                                      decoration: const BoxDecoration(
                                        color: Color(0xFFF8FAFC),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(Icons.receipt_long_rounded, size: 48, color: Colors.grey[300]),
                                    ),
                                    const SizedBox(height: 16),
                                    const Text(
                                      'Tidak ada pengeluaran',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF475569)),
                                    ),
                                    const SizedBox(height: 6),
                                    const Text(
                                      'Gunakan panel kiri untuk menambahkan pengeluaran baru.',
                                      style: TextStyle(fontSize: 12, color: Colors.grey),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.only(top: 16),
                                itemCount: _expenses.length,
                                itemBuilder: (context, index) {
                                  final exp = _expenses[index];
                                  final createdAt = exp['created_at'] != null 
                                      ? DateTime.parse(exp['created_at']) 
                                      : DateTime.now();
                                  final timeStr = DateFormat('HH:mm').format(createdAt);

                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(color: const Color(0xFFE2E8F0)),
                                    ),
                                    child: Row(
                                      children: [
                                        // Time badge
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF1F5F9),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            timeStr,
                                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                                          ),
                                        ),
                                        const SizedBox(width: 20),

                                        // Item Name
                                        Expanded(
                                          child: Text(
                                            exp['name'] ?? '',
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E293B)),
                                          ),
                                        ),

                                        // Amount Red
                                        Text(
                                          '- ${_formatRp(exp['amount'])}',
                                          style: const TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold, fontSize: 14),
                                        ),
                                        const SizedBox(width: 16),

                                        // Action delete
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Color(0xFF94A3B8)),
                                          onPressed: () => _deleteExpense(exp['id']),
                                          tooltip: 'Hapus pengeluaran',
                                          style: IconButton.styleFrom(
                                            hoverColor: Colors.red.withOpacity(0.05),
                                            foregroundColor: Colors.red,
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
            ),
          ),
        ),
      ],
    );
  }
}
