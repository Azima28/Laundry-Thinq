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
import '../../utils/style_constants.dart';
import '../../services/machine_status_service.dart';

class PesanGosokPage extends StatefulWidget {
  const PesanGosokPage({super.key});

  @override
  _PesanGosokPageState createState() => _PesanGosokPageState();
}

class _PesanGosokPageState extends State<PesanGosokPage> {
  final TransactionRepository _repository = TransactionRepository();
  final OrderRepository _orderRepository = OrderRepository();
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;

  List<TransactionModel> _allItems = [];
  List<TransactionModel> _filteredItems = [];
  Map<int, double> _weights = {};
  Map<int, String> _notes = {};
  bool _isLoading = true;
  bool _isSubmitting = false;

  final TextEditingController _customerNameController = TextEditingController();
  final TextEditingController _customerPhoneController = TextEditingController();
  final TextEditingController _searchProductController = TextEditingController();

  List<Customer> _allCustomers = [];
  Customer? _selectedCustomer;

  @override
  void initState() {
    super.initState();
    _loadItems();
    _loadCustomers();
    _searchProductController.addListener(_filterProducts);
  }

  @override
  void dispose() {
    _searchProductController.dispose();
    _customerNameController.dispose();
    _customerPhoneController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomers() async {
    final data = await _databaseHelper.getAllCustomers();
    if (mounted) {
      setState(() {
        _allCustomers = data.map((e) => Customer.fromMap(e)).toList();
      });
    }
  }

  Future<void> _loadItems() async {
    try {
      final items = await _repository.getAllTransactions();
      // Filter for iron/gosok services
      final ironItems = items.where((it) {
        final name = it.nama.toLowerCase();
        return it.machineType == 'gosok' || it.machineType == 'iron' || name.contains('gosok') || name.contains('setrika') || name.contains('iron');
      }).toList();

      if (mounted) {
        setState(() {
          _allItems = ironItems;
          _filteredItems = ironItems;
          _weights = {for (var item in _allItems) item.id ?? 0: 0.0};
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _filterProducts() {
    final query = _searchProductController.text.toLowerCase().trim();
    setState(() {
      _filteredItems = _allItems.where((item) => item.nama.toLowerCase().contains(query)).toList();
    });
  }

  void _onCustomerSelected(Customer customer) {
    setState(() {
      _selectedCustomer = customer;
      _customerNameController.text = customer.name;
      _customerPhoneController.text = customer.phone;
    });
  }

  void _clearCustomer() {
    setState(() {
      _selectedCustomer = null;
      _customerNameController.clear();
      _customerPhoneController.clear();
    });
  }

  void _updateWeight(int? id, double delta) {
    if (id == null) return;
    setState(() {
      double current = _weights[id] ?? 0.0;
      double updated = current + delta;
      if (updated < 0) updated = 0;
      _weights[id] = double.parse(updated.toStringAsFixed(1));
    });
  }

  void _setCustomWeight(int itemId, String itemName) {
    final controller = TextEditingController(text: (_weights[itemId] ?? 0.0).toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: Colors.white,
        title: Text('Input Berat/Jumlah: $itemName', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        content: SizedBox(
          width: 340,
          child: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autofocus: true,
            decoration: StyleConstants.inputDecoration('Berat (Kg) / Jumlah Satuan', Icons.scale_rounded),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal', style: TextStyle(color: StyleConstants.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF97316),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              final parsed = double.tryParse(controller.text.replaceAll(',', '.')) ?? 0.0;
              setState(() {
                _weights[itemId] = parsed;
              });
              Navigator.pop(ctx);
            },
            child: const Text('Terapkan', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showNoteDialog(int itemId, String itemName) {
    final controller = TextEditingController(text: _notes[itemId] ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: Colors.white,
        title: Text('Catatan Khusus: $itemName', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        content: SizedBox(
          width: 380,
          child: TextField(
            controller: controller,
            decoration: StyleConstants.inputDecoration('Instruksi Gosok', Icons.note_alt_outlined, hintText: 'Misal: Setrika lipat rapi, hanger khusus...'),
            maxLines: 3,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal', style: TextStyle(color: StyleConstants.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF97316),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              setState(() {
                _notes[itemId] = controller.text.trim();
              });
              Navigator.pop(ctx);
            },
            child: const Text('Simpan', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _clearCart() {
    setState(() {
      _weights = {for (var item in _allItems) item.id ?? 0: 0.0};
      _notes.clear();
    });
  }

  int _calculateTotal() {
    double total = 0;
    for (var item in _allItems) {
      double w = _weights[item.id ?? 0] ?? 0.0;
      total += w * item.harga;
    }
    return total.round();
  }

  double _calculateTotalWeight() {
    double total = 0;
    _weights.values.forEach((w) => total += w);
    return double.parse(total.toStringAsFixed(1));
  }

  // --- CUSTOMER PICKER MODAL ---
  Future<void> _showCustomerPicker() async {
    final searchController = TextEditingController();
    List<Customer> filtered = _allCustomers;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: Colors.white,
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.people_alt_rounded, color: Color(0xFFF97316), size: 22),
                  SizedBox(width: 10),
                  Text('Pilih Pelanggan Setrika', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ],
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  final added = await _quickAddCustomer();
                  if (added != null) {
                    await _loadCustomers();
                    _onCustomerSelected(added);
                    if (ctx.mounted) Navigator.pop(ctx);
                  }
                },
                icon: const Icon(Icons.person_add_rounded, size: 16),
                label: const Text('Tambah Baru', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF97316),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 520,
            height: 420,
            child: Column(
              children: [
                TextField(
                  controller: searchController,
                  decoration: StyleConstants.inputDecoration('Cari Nama Pelanggan atau No. WA...', Icons.search_rounded),
                  onChanged: (val) {
                    setModalState(() {
                      filtered = _allCustomers.where((c) =>
                        c.name.toLowerCase().contains(val.toLowerCase()) ||
                        c.phone.contains(val)).toList();
                    });
                  },
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: filtered.isEmpty
                      ? const Center(child: Text('Pelanggan tidak ditemukan.', style: TextStyle(color: StyleConstants.textMuted)))
                      : ListView.separated(
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const Divider(height: 1, color: StyleConstants.borderLight),
                          itemBuilder: (context, index) {
                            final customer = filtered[index];
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: const Color(0xFFF97316).withValues(alpha: 0.1),
                                child: Text(
                                  customer.name.isNotEmpty ? customer.name[0].toUpperCase() : '?',
                                  style: const TextStyle(color: Color(0xFFF97316), fontWeight: FontWeight.bold),
                                ),
                              ),
                              title: Text(customer.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                              subtitle: Text(customer.phone, style: const TextStyle(fontSize: 12, color: StyleConstants.textMuted)),
                              trailing: const Icon(Icons.check_circle_outline_rounded, color: Color(0xFFF97316), size: 20),
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
              child: const Text('Batal', style: TextStyle(color: StyleConstants.textMuted, fontWeight: FontWeight.bold)),
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
        backgroundColor: Colors.white,
        title: const Text('Tambah Pelanggan Cepat', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: StyleConstants.inputDecoration('Nama Pelanggan *', Icons.person_outline_rounded),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: StyleConstants.inputDecoration('Nomor WhatsApp *', Icons.phone_rounded, prefixText: '+62 '),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal', style: TextStyle(color: StyleConstants.textMuted))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF97316),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            onPressed: () {
              if (nameCtrl.text.trim().isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Nama wajib diisi')));
                return;
              }
              Navigator.pop(ctx, true);
            },
            child: const Text('Simpan Data', style: TextStyle(fontWeight: FontWeight.bold)),
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

  // --- SUBMIT ORDER GOSOK ---
  Future<void> _submitOrder(String mode) async {
    if (_customerNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Pilih atau isi nama pelanggan terlebih dahulu')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final total = _calculateTotal();
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('user_id');

      final orderItems = _allItems
          .where((it) => (_weights[it.id ?? 0] ?? 0.0) > 0)
          .map((it) {
            final w = _weights[it.id ?? 0] ?? 0.0;
            return OrderItem(
              itemName: it.nama,
              quantity: w.ceil(), // Store as integer or ceil for item count
              price: (it.harga * w).round(),
              note: _notes[it.id ?? 0] ?? '',
              machineType: 'gosok',
              itemId: it.id ?? 1,
            );
          })
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
        _sendWaReceipt(partialOrder, 'belum_bayar', 0);

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

      // === BAYAR SETENGAH (DP) ===
      if (mode == 'bayar_setengah') {
        final result = await _showPartialPaymentDialog(total);
        if (result == null) {
          await _orderRepository.deleteOrder(orderId);
          return;
        }
        final paidAmount = result['amount'] as int;
        final paymentMethod = result['method'] as String;

        final updatedOrder = await _orderRepository.getOrder(orderId);
        final finalOrder = (updatedOrder ?? order.copyWith(id: orderId)).copyWith(
          isPaid: false,
          paidAmount: paidAmount,
          totalAmount: total,
          paymentMethod: paymentMethod == 'qris' ? 'QRIS (DP)' : 'Tunai (DP)',
        );
        await _databaseHelper.updateOrder(finalOrder);
        _sendWaReceipt(finalOrder, 'bayar_setengah', paidAmount);

        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => ReceiptScreen(
                order: finalOrder,
                isPaid: false,
                paymentMethod: paymentMethod == 'qris' ? 'QRIS (DP)' : 'Tunai (DP)',
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
      if (paidOrder == null) return;

      final fullPaidOrder = paidOrder.copyWith(isPaid: true, paidAmount: total);
      await _databaseHelper.updateOrder(fullPaidOrder);
      _sendWaReceipt(fullPaidOrder, 'bayar_lunas', total);

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

  Future<Map<String, dynamic>?> _showPartialPaymentDialog(int total) {
    final controller = TextEditingController();
    String selectedMethod = 'cash';

    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: Colors.white,
          title: const Text('Pembayaran Uang Muka (DP)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: StyleConstants.statusWarningBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: StyleConstants.warningColor.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total Tagihan Setrika:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      Text(
                        formatRp(total),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: StyleConstants.warningColor),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  decoration: StyleConstants.inputDecoration('Jumlah Bayar DP *', Icons.payments_rounded, prefixText: 'Rp '),
                ),
                const SizedBox(height: 16),
                const Text('Metode Pembayaran DP:', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => setStateDialog(() => selectedMethod = 'cash'),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                          decoration: BoxDecoration(
                            color: selectedMethod == 'cash' ? StyleConstants.statusSuccessBg : Colors.white,
                            border: Border.all(color: selectedMethod == 'cash' ? StyleConstants.successColor : StyleConstants.borderLight),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.payments_rounded, color: StyleConstants.successColor, size: 18),
                              SizedBox(width: 6),
                              Text('Tunai / Cash', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: InkWell(
                        onTap: () => setStateDialog(() => selectedMethod = 'qris'),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                          decoration: BoxDecoration(
                            color: selectedMethod == 'qris' ? StyleConstants.statusInfoBg : Colors.white,
                            border: Border.all(color: selectedMethod == 'qris' ? StyleConstants.primaryColor : StyleConstants.borderLight),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.qr_code_scanner_rounded, color: StyleConstants.primaryColor, size: 18),
                              SizedBox(width: 6),
                              Text('QRIS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Batal', style: TextStyle(color: StyleConstants.textMuted)),
            ),
            ElevatedButton(
              onPressed: () {
                final amount = int.tryParse(controller.text) ?? 0;
                if (amount <= 0) {
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Masukkan jumlah DP yang valid')));
                  return;
                }
                if (amount >= total) {
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Untuk bayar penuh, gunakan tombol "Bayar Lunas"')));
                  return;
                }
                Navigator.pop(ctx, {'amount': amount, 'method': selectedMethod});
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: StyleConstants.warningColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Konfirmasi DP', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  // --- 3-PANE DESKTOP POS BUILDER ---
  @override
  Widget build(BuildContext context) {
    final total = _calculateTotal();
    final totalWeight = _calculateTotalWeight();

    return Scaffold(
      backgroundColor: StyleConstants.backgroundColor,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Top Header Bar
                _buildHeaderBar(),

                // 2. Main POS Workspace (Split 65% / 35%)
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // SISI KIRI (65%): Catalog Grid
                      Expanded(
                        flex: 65,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              padding: const EdgeInsets.fromLTRB(18, 12, 18, 6),
                              child: const Text(
                                'Pilih Paket Tarif Gosok & Setrika Uap',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: StyleConstants.textHeading),
                              ),
                            ),
                            Expanded(
                              child: _filteredItems.isEmpty
                                  ? const Center(
                                      child: Text(
                                        'Belum ada paket tarif setrika.',
                                        style: TextStyle(color: StyleConstants.textMuted),
                                      ),
                                    )
                                  : GridView.builder(
                                      padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
                                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: 3,
                                        crossAxisSpacing: 12,
                                        mainAxisSpacing: 12,
                                        childAspectRatio: 2.0,
                                      ),
                                      itemCount: _filteredItems.length,
                                      itemBuilder: (context, index) {
                                        final item = _filteredItems[index];
                                        final weight = _weights[item.id ?? 0] ?? 0.0;
                                        return _buildIronProductCard(item, weight);
                                      },
                                    ),
                            ),
                          ],
                        ),
                      ),

                      // VERTICAL DIVIDER
                      Container(width: 1, color: StyleConstants.borderLight),

                      // SISI KANAN (35%): Ticket Ledger
                      Container(
                        width: StyleConstants.posReceiptWidth,
                        color: Colors.white,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Customer Card
                            _buildCustomerTicketSection(),

                            const Divider(height: 1, color: StyleConstants.borderLight),

                            // Items in Cart List
                            Expanded(
                              child: _buildCartItemsList(),
                            ),

                            const Divider(height: 1, color: StyleConstants.borderLight),

                            // Financial Summary & Actions
                            _buildCheckoutSummarySection(total, totalWeight),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildHeaderBar() {
    return Container(
      height: StyleConstants.topBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: StyleConstants.borderLight)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: StyleConstants.textHeading),
            tooltip: 'Kembali ke Dashboard',
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 8),
          const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'KASIR POS: PESAN SETRIKA / GOSOK',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: StyleConstants.textHeading,
                  letterSpacing: -0.3,
                ),
              ),
              Text(
                'Layanan Setrika Uap Rapi & Gosok Kiloan',
                style: TextStyle(fontSize: 11, color: StyleConstants.textMuted),
              ),
            ],
          ),
          const SizedBox(width: 24),

          Expanded(
            child: Container(
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: StyleConstants.borderLight),
              ),
              child: TextField(
                controller: _searchProductController,
                decoration: InputDecoration(
                  hintText: 'Cari paket tarif setrika (F2)...',
                  hintStyle: const TextStyle(fontSize: 12.5, color: StyleConstants.textMuted),
                  prefixIcon: const Icon(Icons.search_rounded, size: 18, color: StyleConstants.textMuted),
                  suffixIcon: _searchProductController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 16),
                          onPressed: () => _searchProductController.clear(),
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),

          if (_calculateTotalWeight() > 0)
            OutlinedButton.icon(
              onPressed: _clearCart,
              icon: const Icon(Icons.delete_sweep_rounded, size: 16, color: StyleConstants.dangerColor),
              label: const Text('Reset Nota', style: TextStyle(color: StyleConstants.dangerColor, fontSize: 12, fontWeight: FontWeight.bold)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: StyleConstants.dangerColor.withValues(alpha: 0.3)),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildIronProductCard(TransactionModel item, double weight) {
    final isSelected = weight > 0;

    return Container(
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFFFFF7ED) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? const Color(0xFFF97316) : StyleConstants.borderLight,
          width: isSelected ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    item.nama,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: StyleConstants.textHeading),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_notes[item.id]?.isNotEmpty == true)
                  InkWell(
                    onTap: () => _showNoteDialog(item.id ?? 0, item.nama),
                    child: const Icon(Icons.note_alt_rounded, size: 16, color: Color(0xFFF97316)),
                  ),
              ],
            ),

            Text(
              formatRp(item.harga),
              style: StyleConstants.tabularNumbers(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: const Color(0xFFF97316),
              ),
            ),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                InkWell(
                  onTap: () => _setCustomWeight(item.id ?? 0, item.nama),
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.edit_rounded, size: 11, color: StyleConstants.textMuted),
                        SizedBox(width: 2),
                        Text('Ketik Kg', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: StyleConstants.textMuted)),
                      ],
                    ),
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline_rounded, size: 20),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      color: weight > 0 ? StyleConstants.dangerColor : Colors.grey[300],
                      onPressed: () => _updateWeight(item.id, -0.5),
                    ),
                    Container(
                      constraints: const BoxConstraints(minWidth: 36),
                      alignment: Alignment.center,
                      child: Text(
                        '$weight',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 13.5,
                          color: isSelected ? const Color(0xFFF97316) : StyleConstants.textMuted,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_rounded, size: 20),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      color: const Color(0xFFF97316),
                      onPressed: () => _updateWeight(item.id, 0.5),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerTicketSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: const Color(0xFFF8FAFC),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'DATA PELANGGAN',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: StyleConstants.textMuted, letterSpacing: 0.5),
              ),
              if (_customerNameController.text.isNotEmpty)
                InkWell(
                  onTap: _clearCustomer,
                  child: const Text('Ganti', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFF97316))),
                ),
            ],
          ),
          const SizedBox(height: 8),

          InkWell(
            onTap: _showCustomerPicker,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _customerNameController.text.isNotEmpty ? const Color(0xFFF97316).withValues(alpha: 0.4) : StyleConstants.borderLight,
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: const Color(0xFFF97316).withValues(alpha: 0.1),
                    child: const Icon(Icons.person_rounded, size: 16, color: Color(0xFFF97316)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _customerNameController.text.isEmpty ? 'Pilih Pelanggan (Klik di sini)...' : _customerNameController.text,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: _customerNameController.text.isEmpty ? StyleConstants.textMuted : StyleConstants.textHeading,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (_customerPhoneController.text.isNotEmpty)
                          Text(_customerPhoneController.text, style: const TextStyle(fontSize: 11, color: StyleConstants.textMuted)),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down_rounded, color: StyleConstants.textMuted),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCartItemsList() {
    final cartItems = _allItems.where((it) => (_weights[it.id ?? 0] ?? 0.0) > 0).toList();

    if (cartItems.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.iron_outlined, size: 36, color: Color(0xFFCBD5E1)),
            SizedBox(height: 8),
            Text('Nota setrika masih kosong.', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: StyleConstants.textMuted)),
            Text('Pilih paket di kiri untuk menambahkan.', style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: cartItems.length,
      separatorBuilder: (_, __) => const Divider(height: 16, color: StyleConstants.borderLight),
      itemBuilder: (context, index) {
        final item = cartItems[index];
        final w = _weights[item.id ?? 0] ?? 0.0;
        final subtotal = (item.harga * w).round();
        final note = _notes[item.id];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('$w Kg x ', style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFFF97316), fontSize: 13)),
                Expanded(child: Text(item.nama, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: StyleConstants.textHeading))),
                Text(formatRp(subtotal), style: StyleConstants.tabularNumbers(fontSize: 13, fontWeight: FontWeight.w800)),
                const SizedBox(width: 6),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 16, color: StyleConstants.textMuted),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => setState(() => _weights[item.id ?? 0] = 0.0),
                ),
              ],
            ),
            if (note != null && note.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 24),
                child: Text('📝 $note', style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Color(0xFFF97316))),
              ),
          ],
        );
      },
    );
  }

  Widget _buildCheckoutSummarySection(int total, double totalWeight) {
    return Container(
      padding: const EdgeInsets.all(18),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total Berat / Satuan:', style: TextStyle(fontSize: 12.5, color: StyleConstants.textMuted)),
              Text('$totalWeight Kg', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Grand Total:', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: StyleConstants.textHeading)),
              Text(
                formatRp(total),
                style: StyleConstants.tabularNumbers(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: StyleConstants.successColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          ElevatedButton(
            onPressed: totalWeight > 0 && !_isSubmitting ? () => _submitOrder('lunas') : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: StyleConstants.successColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle_rounded, size: 18),
                SizedBox(width: 8),
                Text('BAYAR LUNAS (TUNAI / QRIS)', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5)),
              ],
            ),
          ),
          const SizedBox(height: 8),

          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: totalWeight > 0 && !_isSubmitting ? () => _submitOrder('bayar_setengah') : null,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: StyleConstants.warningColor, width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Bayar DP', style: TextStyle(color: StyleConstants.warningColor, fontWeight: FontWeight.w800, fontSize: 12)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: totalWeight > 0 && !_isSubmitting ? () => _submitOrder('belum_bayar') : null,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: StyleConstants.dangerColor, width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Belum Bayar', style: TextStyle(color: StyleConstants.dangerColor, fontWeight: FontWeight.w800, fontSize: 12)),
                ),
              ),
            ],
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

    String statusBayar = 'BELUM LUNAS';
    if (finalOrder.isPaid || paidAmount >= finalOrder.totalAmount) {
      statusBayar = 'LUNAS';
    } else if (paidAmount > 0) {
      statusBayar = 'BELUM LUNAS (Telah Dibayar: ${formatRp(paidAmount)})';
    }

    final buffer = StringBuffer();
    buffer.writeln("=========================");
    buffer.writeln("   🧺 *AZIMA GOSOK & SETRIKA* 🧺");
    buffer.writeln("=========================");
    buffer.writeln("Halo Kak *${name}*, berikut adalah rincian nota setrika Kakak:\n");
    buffer.writeln("📌 *Nota #${orderId}* - _(${dateStr})_");
    buffer.writeln("---------------------------------");
    buffer.writeln("🛒 *DETAIL LAYANAN:*");

    for (var item in finalOrder.items) {
      buffer.writeln("• *${item.itemName}* ➔ *${formatRp(item.price)}*");
      if (item.note != null && item.note!.trim().isNotEmpty) {
        buffer.writeln("  _Catatan: ${item.note!.trim()}_");
      }
    }

    buffer.writeln("---------------------------------");
    buffer.writeln("💰 *TOTAL TAGIHAN:* *${formatRp(finalOrder.totalAmount)}*");
    buffer.writeln("💳 *STATUS PEMBAYARAN:* *${statusBayar}*");
    buffer.writeln("---------------------------------");
    buffer.writeln("📢 *INFORMASI:* Kakak akan menerima pesan WhatsApp otomatis setelah proses penyetrikaan selesai dilakukan dan pakaian siap diambil.");
    buffer.writeln("=========================");
    buffer.writeln("🙏 Terima kasih telah mempercayakan pakaian Kakak kepada kami! 😊");

    try {
      await MachineStatusService.instance.sendCustomWa(
        phone: phone,
        message: buffer.toString(),
      );
    } catch (e) {
      debugPrint("Error sending checkout WA receipt: $e");
    }
  }
}
