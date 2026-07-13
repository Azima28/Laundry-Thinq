import 'package:flutter/material.dart';
import '../../transactions/transaction_repository.dart';
import '../../database/models/transaction_model.dart';
import '../../utils/currency_format.dart';

class TambahItemScreen extends StatefulWidget {
  const TambahItemScreen({Key? key}) : super(key: key);

  @override
  _TambahItemScreenState createState() => _TambahItemScreenState();
}

class _TambahItemScreenState extends State<TambahItemScreen> {
  final TextEditingController _namaController = TextEditingController();
  final TextEditingController _hargaController = TextEditingController();
  final TextEditingController _stockController = TextEditingController();
  final TransactionRepository _repository = TransactionRepository();
  List<TransactionModel> _items = [];
  bool _isUnlimitedStock = false;
  bool _isStaffRestockable = false;
  
  String? _machineType; // 'cuci' or 'pengering' or null
  int? _machineId; 

  final Color primaryColor = const Color(0xFF4E80EE);
  final Color backgroundColor = const Color(0xFFF8FAFC);

  @override
  void initState() {
    super.initState();
    _loadItems();
    _namaController.addListener(_autoDetectMachineType);
  }

  void _autoDetectMachineType() {
    final name = _namaController.text.toLowerCase();
    if (name.contains('kering') || name.contains('pengering') || name.contains('dryer') || name.contains('jemur')) {
      if (_machineType != 'pengering') {
        setState(() { _machineType = 'pengering'; _machineId = 2; });
      }
    } else if (name.contains('cuci') || name.contains('wash') || name.contains('basah')) {
      if (_machineType != 'cuci') {
        setState(() { _machineType = 'cuci'; _machineId = 1; });
      }
    }
  }

  @override
  void dispose() {
    _namaController.dispose();
    _hargaController.dispose();
    _stockController.dispose();
    super.dispose();
  }

  Future<void> _loadItems() async {
    final items = await _repository.getAllTransactions();
    setState(() {
      _items = items;
    });
  }

  Future<void> _tambahItem() async {
    final String nama = _namaController.text.trim();
    final String hargaText = _hargaController.text.trim();
    final String stockText = _stockController.text.trim();
    
    if (nama.isEmpty || hargaText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Nama dan harga harus diisi!')),
      );
      return;
    }

    final int? harga = int.tryParse(hargaText);
    if (harga == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Harga harus berupa angka!')),
      );
      return;
    }

    int? stock;
    if (!_isUnlimitedStock) {
      stock = int.tryParse(stockText);
      if (stock == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('⚠️ Stok harus berupa angka!')),
        );
        return;
      }
    }

    final item = TransactionModel(
      nama: nama,
      harga: harga,
      stock: stock,
      isUnlimitedStock: _isUnlimitedStock,
      isStaffRestockable: _isStaffRestockable,
      machineType: _machineType,
      machineId: _machineId,
      type: TransactionType.item,
      createdAt: DateTime.now(),
    );
    
    final success = await _repository.insertTransaction(item) > 0;
    if (success) {
      _namaController.clear();
      _hargaController.clear();
      _stockController.clear();
      setState(() {
        _isUnlimitedStock = false;
        _isStaffRestockable = false;
        _machineType = null;
        _machineId = null;
      });
      _loadItems();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Item berhasil ditambahkan!'), backgroundColor: Colors.green),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ Gagal menambahkan item')),
      );
    }
  }

  Future<void> _toggleStaffRestockable(TransactionModel item) async {
    final updated = TransactionModel(
      id: item.id,
      nama: item.nama,
      harga: item.harga,
      stock: item.stock,
      isUnlimitedStock: item.isUnlimitedStock,
      isStaffRestockable: !item.isStaffRestockable,
      machineType: item.machineType,
      machineId: item.machineId,
      type: item.type,
      createdAt: item.createdAt,
    );
    final success = await _repository.updateTransaction(updated);
    if (success) _loadItems();
  }

  Future<void> _updateStock(TransactionModel item) async {
    final controller = TextEditingController(text: item.stock?.toString() ?? '0');
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit Stok: ${item.nama}'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Jumlah Stok Baru', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () async {
              final newStock = int.tryParse(controller.text) ?? 0;
              final updated = TransactionModel(
                id: item.id,
                nama: item.nama,
                harga: item.harga,
                stock: newStock,
                isUnlimitedStock: item.isUnlimitedStock,
                isStaffRestockable: item.isStaffRestockable,
                machineType: item.machineType,
                machineId: item.machineId,
                type: item.type,
                createdAt: item.createdAt,
              );
              await _repository.updateTransaction(updated);
              Navigator.pop(ctx);
              _loadItems();
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
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
    final visibleItems = _items.where((item) => item.type == TransactionType.item).toList();

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text('Kelola Paket & Item Laundry', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
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
                    'Tambah Item Baru',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF475569), letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 16),
                  
                  TextField(
                    controller: _namaController,
                    decoration: _inputDecoration(
                      'Nama Item / Paket',
                      'Cth: Cuci Setrika Wangi',
                      Icons.label_rounded,
                    ),
                  ),
                  const SizedBox(height: 14),
                  
                  TextField(
                    controller: _hargaController,
                    keyboardType: TextInputType.number,
                    decoration: _inputDecoration(
                      'Harga (Rp)',
                      'Masukkan harga item',
                      Icons.payments_rounded,
                      prefixText: 'Rp ',
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Unlimited Switch
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Stok Unlimited', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF334155))),
                      Switch(
                        value: _isUnlimitedStock,
                        onChanged: (val) {
                          setState(() {
                            _isUnlimitedStock = val;
                            if (val) {
                              _stockController.clear();
                              _isStaffRestockable = false;
                            }
                          });
                        },
                        activeColor: primaryColor,
                        activeTrackColor: primaryColor.withOpacity(0.15),
                      ),
                    ],
                  ),
                  
                  if (!_isUnlimitedStock) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _stockController,
                      keyboardType: TextInputType.number,
                      decoration: _inputDecoration(
                        'Jumlah Stok Awal',
                        'Masukkan stok awal',
                        Icons.inventory_rounded,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Kasir Boleh Restock', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF475569))),
                        Checkbox(
                          value: _isStaffRestockable,
                          onChanged: (val) => setState(() => _isStaffRestockable = val ?? false),
                          activeColor: primaryColor,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 16),
                  const Divider(color: Color(0xFFF1F5F9)),
                  const SizedBox(height: 16),

                  // Machine mapping
                  const Text('Trigger Pemantauan Mesin', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF64748B), letterSpacing: 0.5)),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _machineType,
                    dropdownColor: Colors.white,
                    style: const TextStyle(color: Color(0xFF0F172A), fontSize: 14),
                    decoration: _inputDecoration(
                      'Tipe Mesin LG',
                      '',
                      Icons.local_laundry_service_rounded,
                    ),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('Bukan Mesin (Item Toko)')),
                      DropdownMenuItem(value: 'cuci', child: Text('Mesin Cuci (Washing)')),
                      DropdownMenuItem(value: 'pengering', child: Text('Mesin Pengering (Drying)')),
                    ],
                    onChanged: (val) {
                      setState(() {
                        _machineType = val;
                        if (val == 'cuci') _machineId = 1;
                        if (val == 'pengering') _machineId = 2;
                        if (val == null) _machineId = null;
                      });
                    },
                  ),
                  
                  const SizedBox(height: 28),
                  ElevatedButton.icon(
                    onPressed: _tambahItem,
                    icon: const Icon(Icons.add_rounded, color: Colors.white, size: 18),
                    label: const Text('Simpan Item', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
                              'Daftar Item & Paket Aktif',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Kelola katalog paket kiloan/satuan dan produk penunjang laundry',
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
                            '${visibleItems.length} Item',
                            style: const TextStyle(fontSize: 11.5, color: Color(0xFF475569), fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Divider(color: Color(0xFFF1F5F9)),
                    const SizedBox(height: 20),

                    Expanded(
                      child: visibleItems.isEmpty
                          ? const Center(child: Text('Belum ada item ditambahkan.', style: TextStyle(color: Color(0xFF64748B))))
                          : ListView.builder(
                              itemCount: visibleItems.length,
                              itemBuilder: (context, index) {
                                final item = visibleItems[index];

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
                                        backgroundColor: item.machineType != null ? primaryColor.withOpacity(0.08) : const Color(0xFFF1F5F9),
                                        child: Icon(
                                          item.machineType == 'cuci' 
                                              ? Icons.local_laundry_service_rounded 
                                              : (item.machineType == 'pengering' ? Icons.wb_sunny_rounded : Icons.shopping_bag_rounded),
                                          color: item.machineType != null ? primaryColor : const Color(0xFF64748B),
                                          size: 20,
                                        ),
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
                                              item.machineType != null 
                                                  ? 'Jenis: Otomatis ${item.machineType}' 
                                                  : 'Jenis: Layanan Toko',
                                              style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                                            ),
                                          ],
                                        ),
                                      ),

                                      Expanded(
                                        flex: 2,
                                        child: Text(
                                          formatRp(item.harga),
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Color(0xFF0F172A)),
                                        ),
                                      ),

                                      Expanded(
                                        flex: 2,
                                        child: Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: item.isUnlimitedStock || (item.stock ?? 0) > 0 ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
                                                borderRadius: BorderRadius.circular(20),
                                              ),
                                              child: Text(
                                                item.isUnlimitedStock ? 'Unlimited' : '${item.stock ?? 0} unit',
                                                style: TextStyle(
                                                  fontSize: 10.5,
                                                  fontWeight: FontWeight.bold,
                                                  color: item.isUnlimitedStock || (item.stock ?? 0) > 0 ? const Color(0xFF047857) : const Color(0xFFB91C1C),
                                                ),
                                              ),
                                            ),
                                            if (!item.isUnlimitedStock && item.isStaffRestockable) ...[
                                              const SizedBox(width: 6),
                                              const Icon(Icons.verified_user_rounded, color: Colors.orange, size: 14),
                                            ],
                                          ],
                                        ),
                                      ),

                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (!item.isUnlimitedStock) ...[
                                            IconButton(
                                              icon: Icon(
                                                item.isStaffRestockable ? Icons.verified_user_rounded : Icons.gpp_maybe_rounded,
                                                color: item.isStaffRestockable ? Colors.orange : const Color(0xFF94A3B8),
                                                size: 18,
                                              ),
                                              tooltip: item.isStaffRestockable ? 'Larang Restock Kasir' : 'Izinkan Restock Kasir',
                                              style: IconButton.styleFrom(hoverColor: const Color(0xFFF1F5F9)),
                                              onPressed: () => _toggleStaffRestockable(item),
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.inventory_rounded, color: Color(0xFF64748B), size: 18),
                                              tooltip: 'Ubah Stok',
                                              style: IconButton.styleFrom(hoverColor: const Color(0xFFF1F5F9)),
                                              onPressed: () => _updateStock(item),
                                            ),
                                          ],
                                          IconButton(
                                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                                            tooltip: 'Hapus Item',
                                            style: IconButton.styleFrom(hoverColor: Colors.red.withOpacity(0.05)),
                                            onPressed: () async {
                                              final confirm = await showDialog<bool>(
                                                context: context,
                                                builder: (context) => AlertDialog(
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                                  backgroundColor: Colors.white,
                                                  title: const Text('Hapus Item', style: TextStyle(fontWeight: FontWeight.bold)),
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
