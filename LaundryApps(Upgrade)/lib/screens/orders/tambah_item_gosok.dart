import 'package:flutter/material.dart';
import '../../transactions/transaction_repository.dart';
import '../../database/models/transaction_model.dart';
import '../../utils/currency_format.dart';

class TambahItemGosokScreen extends StatefulWidget {
  const TambahItemGosokScreen({Key? key}) : super(key: key);

  @override
  _TambahItemGosokScreenState createState() => _TambahItemGosokScreenState();
}

class _TambahItemGosokScreenState extends State<TambahItemGosokScreen> {
  final TextEditingController _namaController = TextEditingController();
  final TextEditingController _hargaPerKiloController = TextEditingController();
  final TextEditingController _durasiController = TextEditingController();
  final TransactionRepository _repository = TransactionRepository();
  List<TransactionModel> _items = [];

  final Color primaryColor = const Color(0xFF4E80EE);
  final Color backgroundColor = const Color(0xFFF8FAFC);

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  @override
  void dispose() {
    _namaController.dispose();
    _hargaPerKiloController.dispose();
    _durasiController.dispose();
    super.dispose();
  }

  Future<void> _loadItems() async {
    final items = await _repository.getAllTransactions();
    setState(() {
      _items = items.where((item) => item.type == TransactionType.iron).toList();
    });
  }

  Future<void> _tambahItem() async {
    final String nama = _namaController.text.trim();
    final String hargaText = _hargaPerKiloController.text.trim();
    
    if (nama.isEmpty || hargaText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nama dan harga harus diisi.')),
      );
      return;
    }

    final int? harga = int.tryParse(hargaText);
    if (harga == null || harga <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Harga tidak valid.')),
      );
      return;
    }

    final String durasiText = _durasiController.text.trim();
    final int? durasi = int.tryParse(durasiText);
    if (durasiText.isNotEmpty && (durasi == null || durasi < 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Durasi pengerjaan tidak valid.')),
      );
      return;
    }

    final transaction = TransactionModel(
      nama: nama,
      harga: harga,
      isUnlimitedStock: true,
      type: TransactionType.iron,
      durationDays: durasi ?? 0,
      createdAt: DateTime.now(),
    );

    try {
      final success = await _repository.insertTransaction(transaction);
      if (success > 0) {
        _namaController.clear();
        _hargaPerKiloController.clear();
        _durasiController.clear();
        _loadItems();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Layanan setrika berhasil ditambahkan.'), backgroundColor: Colors.green),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal menambahkan item.')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Terjadi kesalahan: $e')),
      );
    }
  }

  InputDecoration _inputDecoration(String label, String hint, IconData icon, {String? prefixText, String? suffixText}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixText: prefixText,
      suffixText: suffixText,
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
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text('Kelola Paket Setrika (Gosok)', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: const Color(0xFFE2E8F0), height: 1),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Left Panel: Add Item Form (360px)
          Container(
            width: 360,
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(right: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Tambah Layanan Gosok Baru',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF475569), letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 16),
                  
                  TextField(
                    controller: _namaController,
                    decoration: _inputDecoration(
                      'Nama Paket Gosok',
                      'Cth: Gosok Express 1 Hari',
                      Icons.label_rounded,
                    ),
                  ),
                  const SizedBox(height: 14),
                  
                  TextField(
                    controller: _hargaPerKiloController,
                    keyboardType: TextInputType.number,
                    decoration: _inputDecoration(
                      'Harga per Kilo (Rp)',
                      'Masukkan harga per kilo',
                      Icons.payments_rounded,
                      prefixText: 'Rp ',
                    ),
                  ),
                  const SizedBox(height: 14),

                  TextField(
                    controller: _durasiController,
                    keyboardType: TextInputType.number,
                    decoration: _inputDecoration(
                      'Durasi Pengerjaan (Hari)',
                      'Cth: 2 (isi 0 jika hari ini)',
                      Icons.schedule_rounded,
                      suffixText: ' Hari',
                    ),
                  ),
                  
                  const SizedBox(height: 28),
                  ElevatedButton.icon(
                    onPressed: _tambahItem,
                    icon: const Icon(Icons.add_rounded, color: Colors.white, size: 18),
                    label: const Text('Simpan Paket', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shadowColor: Colors.transparent,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 2. Right Panel: Items List (Expanded)
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
                              'Daftar Tarif Layanan Gosok',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Kelola katalog tarif layanan setrika pakaian saja',
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
                            '${_items.length} Paket',
                            style: const TextStyle(fontSize: 11.5, color: Color(0xFF475569), fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Divider(color: Color(0xFFF1F5F9)),
                    const SizedBox(height: 20),

                    Expanded(
                      child: _items.isEmpty
                          ? const Center(child: Text('Belum ada paket setrika ditambahkan.', style: TextStyle(color: Color(0xFF64748B))))
                          : ListView.builder(
                              itemCount: _items.length,
                              itemBuilder: (context, index) {
                                final item = _items[index];

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: const Color(0xFFE2E8F0)),
                                  ),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 20,
                                        backgroundColor: primaryColor.withOpacity(0.08),
                                        child: Icon(Icons.iron_rounded, color: primaryColor, size: 20),
                                      ),
                                      const SizedBox(width: 16),

                                      Expanded(
                                        flex: 4,
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(item.nama, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A))),
                                            const SizedBox(height: 4),
                                            Text(
                                              'Estimasi Kerja: ${item.durationDays ?? 0} hari',
                                              style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                                            ),
                                          ],
                                        ),
                                      ),

                                      Expanded(
                                        flex: 3,
                                        child: Text(
                                          '${formatRp(item.harga)} / kg',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Color(0xFF0F172A)),
                                        ),
                                      ),

                                      IconButton(
                                        icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                                        tooltip: 'Hapus Paket',
                                        style: IconButton.styleFrom(hoverColor: Colors.red.withOpacity(0.05)),
                                        onPressed: () async {
                                          final confirm = await showDialog<bool>(
                                            context: context,
                                            builder: (context) => AlertDialog(
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                              backgroundColor: Colors.white,
                                              title: const Text('Hapus Paket Gosok', style: TextStyle(fontWeight: FontWeight.bold)),
                                              content: Text('Apakah Anda yakin ingin menghapus "${item.nama}"?'),
                                              actions: [
                                                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal', style: TextStyle(color: Color(0xFF64748B)))),
                                                ElevatedButton(
                                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                                                  onPressed: () => Navigator.pop(context, true),
                                                  child: const Text('Hapus'),
                                                ),
                                              ],
                                            ),
                                          );
                                          if (confirm == true) {
                                            await _repository.deleteTransaction(item.id!);
                                            _loadItems();
                                          }
                                        },
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
}
