import 'package:flutter/material.dart';
import '../../transactions/transaction_repository.dart';
import '../../database/models/transaction_model.dart';
import '../../utils/currency_format.dart';

class RestockScreen extends StatefulWidget {
  const RestockScreen({Key? key}) : super(key: key);

  @override
  State<RestockScreen> createState() => _RestockScreenState();
}

class _RestockScreenState extends State<RestockScreen> {
  final TransactionRepository _repository = TransactionRepository();
  List<TransactionModel> _items = [];
  bool _isLoading = true;

  final Color primaryColor = const Color(0xFF4E80EE);
  final Color backgroundColor = const Color(0xFFF8FAFC);

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    setState(() => _isLoading = true);
    try {
      final items = await _repository.getAllTransactions();
      setState(() {
        _items = items
            .where((item) =>
                item.type == TransactionType.item &&
                !item.isUnlimitedStock &&
                item.isStaffRestockable)
            .toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memuat barang: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _showRestockDialog(TransactionModel item) async {
    final TextEditingController quantityController = TextEditingController(text: '10');
    int addedAmount = 10;

    return showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Restock Barang',
                  style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  item.nama,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Stok Saat Ini:', style: TextStyle(color: Colors.grey, fontSize: 13)),
                        Text(
                          '${item.stock ?? 0} pcs',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: (item.stock ?? 0) <= 0
                                ? Colors.red
                                : ((item.stock ?? 0) <= 5 ? Colors.orange : Colors.green),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: quantityController,
                    keyboardType: TextInputType.number,
                    autofocus: true,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: primaryColor),
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      labelText: 'Jumlah Tambahan Stok',
                      labelStyle: const TextStyle(fontSize: 13),
                      suffixText: 'pcs',
                      prefixIcon: Icon(Icons.add_box_rounded, color: primaryColor),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onChanged: (val) {
                      setDialogState(() {
                        addedAmount = int.tryParse(val) ?? 0;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [5, 10, 20, 50, 100].map((amount) {
                      final isSelected = addedAmount == amount;
                      return ActionChip(
                        backgroundColor: isSelected ? primaryColor : Colors.grey[50],
                        side: BorderSide(color: isSelected ? primaryColor : Colors.grey[200]!),
                        label: Text(
                          '+$amount',
                          style: TextStyle(
                            color: isSelected ? Colors.white : const Color(0xFF334155),
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        onPressed: () {
                          setDialogState(() {
                            addedAmount = amount;
                            quantityController.text = amount.toString();
                            quantityController.selection = TextSelection.fromPosition(
                              TextPosition(offset: quantityController.text.length),
                            );
                          });
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
              ElevatedButton(
                onPressed: addedAmount <= 0
                    ? null
                    : () async {
                        final success = await _repository.increaseStock(item.id!, addedAmount);
                        if (context.mounted) {
                          Navigator.pop(context);
                          if (success) {
                            _loadItems();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: Colors.green,
                                content: Text('Stok "${item.nama}" berhasil ditambah +$addedAmount pcs.'),
                              ),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(backgroundColor: Colors.red, content: Text('Gagal memperbarui stok.')),
                            );
                          }
                        }
                      },
                child: const Text('Simpan', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Calculate stats
    final totalProducts = _items.length;
    final outOfStockCount = _items.where((it) => (it.stock ?? 0) <= 0).length;
    final criticalStockCount = _items.where((it) => (it.stock ?? 0) > 0 && (it.stock ?? 0) <= 5).length;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text('Restock Inventaris', style: TextStyle(fontWeight: FontWeight.bold)),
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
          // 1. Left Panel: Quick stats & overview (340px)
          Container(
            width: 340,
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
                    'Informasi Inventaris',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                  ),
                  const SizedBox(height: 16),
                  
                  // Total Card
                  _buildStatTile(
                    label: 'Total Produk Fisik',
                    value: '$totalProducts item',
                    color: primaryColor,
                    icon: Icons.inventory_rounded,
                  ),
                  const SizedBox(height: 12),

                  // Critical Stock Card
                  _buildStatTile(
                    label: 'Stok Kritis (<= 5)',
                    value: '$criticalStockCount item',
                    color: Colors.orange,
                    icon: Icons.warning_amber_rounded,
                  ),
                  const SizedBox(height: 12),

                  // Out of Stock Card
                  _buildStatTile(
                    label: 'Stok Habis',
                    value: '$outOfStockCount item',
                    color: Colors.red,
                    icon: Icons.error_outline_rounded,
                  ),

                  const SizedBox(height: 28),
                  const Divider(height: 1),
                  const SizedBox(height: 24),

                  // Rules card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.info_outline_rounded, size: 16, color: Colors.grey),
                            SizedBox(width: 8),
                            Text('Panduan Restock', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF334155))),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Kasir atau staff hanya diperbolehkan menambah jumlah stok barang fisik yang mendapat izin restock oleh pemilik laundry.',
                          style: TextStyle(fontSize: 11, color: Colors.grey, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 2. Right Panel: Product Grid List (Expanded)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(28.0),
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _items.isEmpty
                      ? _buildEmptyPlaceholder()
                      : Container(
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
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Pilih Barang Untuk Ditambah',
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.refresh_rounded, size: 20),
                                    onPressed: _loadItems,
                                    tooltip: 'Refresh barang',
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              const Divider(height: 1),
                              const SizedBox(height: 16),
                              Expanded(
                                child: GridView.builder(
                                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                    maxCrossAxisExtent: 280,
                                    mainAxisSpacing: 16,
                                    crossAxisSpacing: 16,
                                    childAspectRatio: 1.4,
                                  ),
                                  itemCount: _items.length,
                                  itemBuilder: (context, index) {
                                    final item = _items[index];
                                    final currentStock = item.stock ?? 0;

                                    Color stockColor = Colors.green;
                                    String statusText = 'Aman';
                                    if (currentStock <= 0) {
                                      stockColor = Colors.red;
                                      statusText = 'Habis';
                                    } else if (currentStock <= 5) {
                                      stockColor = Colors.orange;
                                      statusText = 'Kritis';
                                    }

                                    return Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(color: Colors.grey[200]!),
                                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.01), blurRadius: 5)],
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item.nama,
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A)),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(formatRp(item.harga), style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                                          const Spacer(),
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: stockColor.withOpacity(0.08),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  '$statusText: $currentStock pcs',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    color: stockColor,
                                                  ),
                                                ),
                                              ),
                                              ElevatedButton(
                                                onPressed: () => _showRestockDialog(item),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: primaryColor.withOpacity(0.1),
                                                  foregroundColor: primaryColor,
                                                  elevation: 0,
                                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                                ),
                                                child: const Text('Restock', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
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

  Widget _buildEmptyPlaceholder() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_rounded, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          const Text('Tidak ada barang restockable', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF475569))),
        ],
      ),
    );
  }
}
