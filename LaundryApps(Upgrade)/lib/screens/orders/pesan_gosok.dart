import 'package:flutter/material.dart';
import '../../database/models/transaction_model.dart';
import '../../transactions/transaction_repository.dart';
import '../../transactions/order_repository.dart';
import '../../database/models/order_model.dart';
import '../../database/models/customer_model.dart';
import '../../database/models/database_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'payment_screen.dart';
import 'receipt_screen.dart';
import '../../utils/currency_format.dart';
import '../../services/machine_status_service.dart';

class PesanGosokPage extends StatefulWidget {
  @override
  _PesanGosokPageState createState() => _PesanGosokPageState();
}

class _PesanGosokPageState extends State<PesanGosokPage> {
  final TransactionRepository _repository = TransactionRepository();
  final OrderRepository _orderRepository = OrderRepository();
  List<TransactionModel> _items = [];
  Map<int, double> _weights = {};
  Map<int, String> _notes = {};
  bool _isLoading = true;
  bool _isSubmitting = false;
  final TextEditingController _customerNameController = TextEditingController();
  final TextEditingController _customerPhoneController = TextEditingController();
  List<Customer> _allCustomers = [];
  Customer? _selectedCustomer;
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;

  final Color primaryColor = const Color(0xFF4E80EE);
  final Color backgroundColor = const Color(0xFFF8FAFC);

  @override
  void initState() {
    super.initState();
    _loadItems();
    _loadCustomers();
  }

  Future<void> _loadCustomers() async {
    final data = await _databaseHelper.getAllCustomers();
    setState(() {
      _allCustomers = data.map((e) => Customer.fromMap(e)).toList();
    });
  }

  void _onCustomerSelected(Customer customer) {
    setState(() {
      _selectedCustomer = customer;
      _customerNameController.text = customer.name;
      _customerPhoneController.text = customer.phone;
    });
  }

  Future<void> _showCustomerPicker() async {
    final searchController = TextEditingController();
    List<Customer> filtered = _allCustomers;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Pilih Pelanggan', style: TextStyle(fontWeight: FontWeight.bold)),
              IconButton(
                icon: const Icon(Icons.add_circle_rounded, color: Color(0xFF4E80EE)),
                onPressed: () async {
                  final added = await _quickAddCustomer();
                  if (added != null) {
                    await _loadCustomers();
                    _onCustomerSelected(added);
                    Navigator.pop(ctx);
                  }
                },
              ),
            ],
          ),
          content: Container(
            width: 500,
            height: 400,
            child: Column(
              children: [
                TextField(
                  controller: searchController,
                  decoration: InputDecoration(
                    hintText: 'Cari nama atau No. WA...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onChanged: (val) {
                    setModalState(() {
                      filtered = _allCustomers.where((c) => 
                        c.name.toLowerCase().contains(val.toLowerCase()) || 
                        c.phone.contains(val)).toList();
                    });
                  },
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: filtered.isEmpty
                      ? const Center(child: Text('Pelanggan tidak ditemukan'))
                      : ListView.separated(
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final customer = filtered[index];
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: primaryColor.withOpacity(0.1),
                                child: Text(customer.name[0].toUpperCase(), style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold)),
                              ),
                              title: Text(customer.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text(customer.phone),
                              onTap: () {
                                _onCustomerSelected(customer);
                                Navigator.pop(ctx);
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Batal'),
            ),
          ],
        ),
      ),
    );
  }

  Future<Customer?> _quickAddCustomer() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Tambah Pelanggan Cepat', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Nama Pelanggan', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'No. WhatsApp', prefixText: '+62 ', border: OutlineInputBorder(), hintText: '812...'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(ctx).primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () {
              if (nameCtrl.text.trim().isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Nama wajib diisi')));
                return;
              }
              Navigator.pop(ctx, true);
            },
            child: const Text('Simpan', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (result == true) {
      String phone = phoneCtrl.text.trim();
      if (phone.isNotEmpty) {
        if (phone.startsWith('0')) phone = phone.substring(1);
        phone = '+62$phone';
      }
      final newCust = Customer(
        name: nameCtrl.text.trim(),
        phone: phone,
        address: '',
        createdAt: DateTime.now(),
      );
      final id = await _databaseHelper.insertCustomer(newCust.toMap());
      return newCust.copyWith(id: id);
    }
    return null;
  }

  Future<void> _loadItems() async {
    try {
      final items = await _repository.getAllTransactions();
      final gosokItems = items.where((it) {
        final name = it.nama.toLowerCase();
        return it.type == TransactionType.iron || it.machineType == 'gosok' || name.contains('gosok') || name.contains('setrika') || name.contains('iron');
      }).toList();

      setState(() {
        _items = gosokItems;
        _isLoading = false;
      });
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  void _updateWeight(int itemId) async {
    final controller = TextEditingController(
      text: _weights[itemId] != null && _weights[itemId]! > 0 ? _weights[itemId].toString() : '',
    );

    final double? weight = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Set Berat (kg)'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Berat Pakaian (Kg)',
            suffixText: ' kg',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () {
              final val = double.tryParse(controller.text);
              if (val == null || val <= 0) {
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Masukkan berat yang valid')));
                return;
              }
              Navigator.pop(ctx, val);
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );

    if (weight != null) {
      setState(() {
        _weights[itemId] = weight;
      });
    }
  }

  void _showNoteDialog(int itemId) {
    final controller = TextEditingController(text: _notes[itemId] ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tambah Catatan Item'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Masukkan catatan seperti: setrika uap, kancing lepas...'),
          maxLines: 2,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _notes[itemId] = controller.text.trim();
              });
              Navigator.pop(ctx);
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  int _calculateTotal() {
    double total = 0;
    for (var item in _items) {
      double weight = _weights[item.id] ?? 0;
      total += weight * item.harga;
    }
    return total.round();
  }

  double _calculateTotalWeight() {
    double total = 0;
    _weights.values.forEach((w) => total += w);
    return total;
  }

  Future<void> _submitOrder(String mode) async {
    if (_customerNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pilih atau isi nama pelanggan terlebih dahulu')));
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final total = _calculateTotal();
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('user_id');

      final orderItems = _items
          .where((it) => (_weights[it.id ?? 0] ?? 0) > 0)
          .map((it) => OrderItem(
                itemName: it.nama,
                quantity: 1, // weight is multiplier, qty is 1 package
                price: (it.harga * (_weights[it.id ?? 0] ?? 0)).round(),
                note: '${_notes[it.id ?? 0] ?? ""} (${_weights[it.id ?? 0]} kg)',
                machineType: it.machineType ?? 'gosok',
                itemId: it.id ?? 2,
              ))
          .toList();

      final order = Order(
        customerName: _customerNameController.text.trim(),
        customerPhone: _customerPhoneController.text.trim(),
        orderDate: DateTime.now(),
        status: 'Proses',
        isPaid: false,
        totalAmount: total,
        paidAmount: 0,
        paymentMethod: '-',
        items: orderItems,
        userId: userId ?? 1,
      );

      final orderId = await _databaseHelper.insertOrder(order);

      // === BELUM BAYAR ===
      if (mode == 'belum_bayar') {
        final partialOrder = order.copyWith(id: orderId, isPaid: false, paymentMethod: 'Belum Lunas');
        await _databaseHelper.updateOrder(partialOrder);
        if (!await _updateStocks(orderId)) return;

        await _sendWaReceipt(partialOrder, 'belum_bayar', 0);

        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => ReceiptScreen(
                order: partialOrder,
                isPaid: false,
                paymentMethod: 'Belum Lunas',
                paidAmount: 0,
              ),
            ),
          );
        }
        return;
      }

      // === BAYAR SETENGAH ===
      if (mode == 'bayar_setengah') {
        final paidAmount = await _showPartialPaymentDialog(total);
        if (paidAmount == null) {
          await _orderRepository.deleteOrder(orderId);
          return;
        }

        final updatedOrder = await _orderRepository.getOrder(orderId);
        final finalOrder = (updatedOrder ?? order.copyWith(id: orderId)).copyWith(
          isPaid: false,
          paidAmount: paidAmount,
          totalAmount: total,
          paymentMethod: 'Bayar Setengah',
        );
        await _databaseHelper.updateOrder(finalOrder);
        if (!await _updateStocks(orderId)) return;

        await _sendWaReceipt(finalOrder, 'bayar_setengah', paidAmount);

        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => ReceiptScreen(
                order: finalOrder,
                isPaid: false,
                paymentMethod: 'Bayar Setengah',
                paidAmount: paidAmount,
              ),
            ),
          );
        }
        return;
      }

      // === BAYAR LUNAS ===
      final paymentSuccess = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (context) => PaymentScreen(order: order.copyWith(id: orderId)),
        ),
      );

      if (paymentSuccess != true) {
        await _orderRepository.deleteOrder(orderId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pembayaran dibatalkan')));
        }
        return;
      }

      final paidOrder = await _orderRepository.getOrder(orderId);
      if (paidOrder == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gagal mendapatkan data pesanan')));
        return;
      }

      final fullPaidOrder = paidOrder.copyWith(isPaid: true, paidAmount: total);
      await _databaseHelper.updateOrder(fullPaidOrder);
      if (!await _updateStocks(orderId)) return;

      await _sendWaReceipt(fullPaidOrder, 'bayar_lunas', total);

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => ReceiptScreen(
              order: fullPaidOrder,
              isPaid: true,
              paymentMethod: fullPaidOrder.paymentMethod,
              paidAmount: total,
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<bool> _updateStocks(int orderId) async {
    bool allOk = true;
    for (var entry in _weights.entries.where((e) => e.value > 0)) {
      final success = await _repository.decreaseStock(entry.key, entry.value.round());
      if (!success) {
        allOk = false;
        break;
      }
    }
    if (!allOk) {
      await _orderRepository.deleteOrder(orderId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal memperbarui stok. Pesanan dibatalkan.')),
        );
      }
    }
    return allOk;
  }

  Future<int?> _showPartialPaymentDialog(int total) {
    final controller = TextEditingController();
    return showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Bayar Setengah'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Total: ${formatRp(total)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Jumlah yang dibayar',
                prefixText: 'Rp ',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Batal', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              final amount = int.tryParse(controller.text) ?? 0;
              if (amount <= 0) {
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Masukkan jumlah yang valid')));
                return;
              }
              if (amount >= total) {
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Untuk bayar penuh, gunakan tombol "Bayar Lunas"')));
                return;
              }
              Navigator.pop(ctx, amount);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Lanjut Bayar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = _calculateTotal();
    final totalWeight = _calculateTotalWeight();

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text('Buat Order Gosok (Setrika)', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Left Side: Inputs & Items Picker (60% width)
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Customer Picker Row
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                        child: InkWell(
                          onTap: _showCustomerPicker,
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: primaryColor.withOpacity(0.3)),
                              boxShadow: [BoxShadow(color: primaryColor.withOpacity(0.02), blurRadius: 10)],
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: primaryColor.withOpacity(0.1),
                                  child: Icon(Icons.person_rounded, color: primaryColor),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _customerNameController.text.isEmpty
                                            ? 'Pilih Data Pelanggan'
                                            : _customerNameController.text,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                          color: _customerNameController.text.isEmpty
                                              ? Colors.grey
                                              : const Color(0xFF0F172A),
                                        ),
                                      ),
                                      if (_customerPhoneController.text.isNotEmpty)
                                        const SizedBox(height: 2),
                                      if (_customerPhoneController.text.isNotEmpty)
                                        Text(_customerPhoneController.text,
                                            style: TextStyle(color: Colors.grey[500], fontSize: 13)),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.grey),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // Items list header
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 24.0, vertical: 12),
                        child: Text(
                          'Pilih Layanan Gosok Setrika',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF475569)),
                        ),
                      ),

                      // Items picker list
                      Expanded(
                        child: ListView.separated(
                          padding: const EdgeInsets.only(left: 24, right: 24, bottom: 24),
                          itemCount: _items.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final item = _items[index];
                            final weight = _weights[item.id ?? 0] ?? 0.0;
                            final hasWeight = weight > 0;

                            return Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: hasWeight ? primaryColor.withOpacity(0.3) : Colors.grey[200]!),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                title: Text(item.nama, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 4),
                                    Text('Tarif: ${formatRp(item.harga)} / kg', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                                    if (hasWeight)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4.0),
                                        child: Text(
                                          'Subtotal: ${formatRp((item.harga * weight).round())} ($weight kg)',
                                          style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold, fontSize: 12),
                                        ),
                                      ),
                                    if (_notes[item.id]?.isNotEmpty == true)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 6),
                                        child: Text(
                                          'Catatan: ${_notes[item.id]}',
                                          style: TextStyle(
                                            fontStyle: FontStyle.italic,
                                            fontSize: 11,
                                            color: Colors.orange[700],
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: Icon(Icons.note_add_rounded, color: primaryColor, size: 20),
                                      onPressed: () => _showNoteDialog(item.id ?? 0),
                                      tooltip: 'Tambah Catatan',
                                    ),
                                    const SizedBox(width: 8),
                                    ElevatedButton(
                                      onPressed: () => _updateWeight(item.id ?? 0),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: hasWeight ? primaryColor : Colors.grey[100],
                                        foregroundColor: hasWeight ? Colors.white : Colors.grey[800],
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      child: Text(hasWeight ? '${weight} kg' : 'Set Berat'),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),

                // 2. Vertical Divider
                Container(width: 1, color: Colors.grey[200]),

                // 3. Right Side: Checkout Summary & Total (40% width)
                Container(
                  width: 380,
                  color: Colors.white,
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.shopping_cart_checkout_rounded, color: Color(0xFF0F172A)),
                          SizedBox(width: 10),
                          Text(
                            'Ringkasan Nota',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      const Divider(height: 1),
                      const SizedBox(height: 24),

                      // Order details list
                      Expanded(
                        child: totalWeight == 0
                            ? Center(
                                child: Text(
                                  'Pilih item di kiri untuk memulai nota.',
                                  style: TextStyle(color: Colors.grey[400], fontSize: 13),
                                ),
                              )
                            : ListView(
                                children: _items
                                    .where((it) => (_weights[it.id ?? 0] ?? 0) > 0)
                                    .map((it) {
                                      final w = _weights[it.id ?? 0] ?? 0.0;
                                      return Padding(
                                        padding: const EdgeInsets.only(bottom: 12.0),
                                        child: Row(
                                          children: [
                                            Text('$w kg x ', style: TextStyle(fontWeight: FontWeight.bold, color: primaryColor)),
                                            Expanded(
                                              child: Text(
                                                it.nama,
                                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                              ),
                                            ),
                                            Text(
                                              formatRp((it.harga * w).round()),
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                            ),
                                          ],
                                        ),
                                      );
                                    })
                                    .toList(),
                              ),
                      ),

                      const Divider(height: 1),
                      const SizedBox(height: 24),

                      // Price Row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Total Berat:', style: TextStyle(fontSize: 14, color: Colors.grey)),
                          Text('${totalWeight.toStringAsFixed(2)} kg', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Grand Total:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          Text(formatRp(total), style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green[600])),
                        ],
                      ),
                      const SizedBox(height: 32),

                      // Actions Block
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Bayar Lunas Button
                          ElevatedButton(
                            onPressed: totalWeight > 0 && !_isSubmitting ? () => _submitOrder('lunas') : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 0,
                            ),
                            child: const Text('Bayar Lunas (Tunai/QRIS)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                          ),
                          const SizedBox(height: 12),
                          
                          Row(
                            children: [
                              // Belum Bayar
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: totalWeight > 0 && !_isSubmitting ? () => _submitOrder('belum_bayar') : null,
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: Colors.redAccent, width: 1.5),
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  child: const Text('Belum Bayar', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                                ),
                              ),
                              const SizedBox(width: 12),
                              // Bayar Setengah
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: totalWeight > 0 && !_isSubmitting ? () => _submitOrder('bayar_setengah') : null,
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: Colors.orange, width: 1.5),
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  child: const Text('Bayar Setengah', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 13)),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _sendWaReceipt(Order finalOrder, String mode, int paidAmount) async {
    if (finalOrder.customerPhone == null || finalOrder.customerPhone!.trim().isEmpty) return;
    
    final phone = finalOrder.customerPhone!.trim();
    final name = finalOrder.customerName;
    final orderId = finalOrder.id;
    final d = finalOrder.orderDate;
    final dateStr = '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    
    // Construct payment status text
    String statusBayar = 'BELUM LUNAS';
    if (finalOrder.isPaid || paidAmount >= finalOrder.totalAmount) {
      statusBayar = 'LUNAS';
    } else if (paidAmount > 0) {
      statusBayar = 'BELUM LUNAS (Telah Dibayar: ${formatRp(paidAmount)})';
    }

    final buffer = StringBuffer();
    buffer.writeln("=========================");
    buffer.writeln("   🧾 *AZIMA LAUNDRY* 🧾");
    buffer.writeln("=========================");
    buffer.writeln("Halo Kak *${name}*, berikut adalah rincian pesanan Anda:\n");
    buffer.writeln("📌 *Nota #${orderId}* - _(${dateStr})_");
    buffer.writeln("---------------------------------");
    buffer.writeln("🛒 *DETAIL LAYANAN:*");
    
    for (var item in finalOrder.items) {
      if (item.quantity == 1) {
        buffer.writeln("• *${item.itemName}* ➔ *${formatRp(item.price)}*");
      } else {
        buffer.writeln("• *${item.itemName}* ➔ *${item.quantity} x ${formatRp(item.price)}* = *${formatRp(item.price * item.quantity)}*");
      }
      if (item.note != null && item.note!.trim().isNotEmpty) {
        buffer.writeln("  _Catatan: ${item.note!.trim()}_");
      }
    }
    
    buffer.writeln("---------------------------------");
    buffer.writeln("💰 *TOTAL TAGIHAN:* *${formatRp(finalOrder.totalAmount)}*");
    buffer.writeln("💳 *STATUS PEMBAYARAN:* *${statusBayar}*");
    buffer.writeln("---------------------------------");
    buffer.writeln("📢 *INFORMASI PENTING:*");
    
    // Check if there are any cuci/iron services to customize instruction info
    bool hasCuci = finalOrder.items.any((it) {
      final n = it.itemName.toLowerCase();
      final mt = it.machineType?.toLowerCase() ?? '';
      return n.contains('cuci') || n.contains('wash') || n.contains('kering') || n.contains('dry') || mt == 'cuci' || mt == 'pengering';
    });
    bool hasIron = finalOrder.items.any((it) {
      final n = it.itemName.toLowerCase();
      final mt = it.machineType?.toLowerCase() ?? '';
      return n.contains('gosok') || n.contains('setrika') || n.contains('iron') || mt == 'gosok' || mt == 'iron';
    });
    
    if (hasCuci && hasIron) {
      buffer.writeln("• Kakak akan menerima pesan WhatsApp otomatis ketika proses pencucian dimulai dan setelah proses penyetrikaan selesai/siap diambil.");
    } else if (hasIron) {
      buffer.writeln("• Kakak akan menerima pesan WhatsApp otomatis setelah proses penyetrikaan selesai dilakukan dan pakaian siap diambil.");
    } else {
      buffer.writeln("• Kakak akan menerima pesan WhatsApp otomatis ketika proses pencucian dimulai dan setelah cucian selesai/siap diambil.");
    }
    
    buffer.writeln("=========================");
    buffer.writeln("🙏 Terima kasih telah mempercayakan pakaian Kakak kepada kami! 😊");

    try {
      await MachineStatusService.instance.sendWaMessage(
        phone: phone,
        message: buffer.toString(),
      );
    } catch (e) {
      print("Error sending checkout WA receipt: $e");
    }
  }
}
