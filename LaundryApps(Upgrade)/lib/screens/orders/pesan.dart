import 'package:flutter/material.dart';
import '../../database/models/transaction_model.dart';
import '../../transactions/transaction_repository.dart';
import '../../transactions/order_repository.dart';
import '../../database/models/order_model.dart';
import '../../database/models/customer_model.dart';
import 'payment_screen.dart';
import 'receipt_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../database/models/database_helper.dart';
import '../../utils/currency_format.dart';
import '../../utils/style_constants.dart';
import '../../services/machine_status_service.dart';

class PesanPage extends StatefulWidget {
  const PesanPage({Key? key}) : super(key: key);

  @override
  _PesanPageState createState() => _PesanPageState();
}

class _PesanPageState extends State<PesanPage> {
  final TransactionRepository _repository = TransactionRepository();
  final OrderRepository _orderRepository = OrderRepository();
  late DatabaseHelper _databaseHelper;

  List<TransactionModel> _allItems = [];
  List<TransactionModel> _filteredItems = [];
  Map<int, int> _quantities = {};
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
    _databaseHelper = DatabaseHelper.instance;
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
      // Filter for wash/cuci services
      final washItems = items.where((it) {
        final name = it.nama.toLowerCase();
        return it.machineType == 'cuci' || name.contains('cuci') || name.contains('wash');
      }).toList();

      if (mounted) {
        setState(() {
          _allItems = washItems;
          _filteredItems = washItems;
          _quantities = {for (var item in _allItems) item.id ?? 0: 0};
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
      if (query.isEmpty) {
        _filteredItems = List.from(_allItems);
      } else {
        _filteredItems = _allItems.where((item) {
          return item.nama.toLowerCase().contains(query);
        }).toList();
      }
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

  void _updateQuantity(int? id, bool increment) {
    if (id == null) return;
    setState(() {
      int current = _quantities[id] ?? 0;
      if (increment) {
        _quantities[id] = current + 1;
      } else {
        if (current > 0) _quantities[id] = current - 1;
      }
    });
  }

  void _clearCart() {
    setState(() {
      _quantities = {for (var item in _allItems) item.id ?? 0: 0};
      _notes.clear();
    });
  }

  int _calculateTotal() {
    int total = 0;
    for (var item in _allItems) {
      int qty = _quantities[item.id ?? 0] ?? 0;
      total += qty * item.harga;
    }
    return total;
  }

  int _calculateTotalItems() {
    int total = 0;
    _quantities.values.forEach((qty) => total += qty);
    return total;
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
                  Icon(Icons.people_alt_rounded, color: StyleConstants.primaryColor, size: 22),
                  SizedBox(width: 10),
                  Text('Pilih Pelanggan Laundry', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
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
                  backgroundColor: StyleConstants.primaryColor,
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
                      ? const Center(
                          child: Text(
                            'Pelanggan tidak ditemukan.',
                            style: TextStyle(color: StyleConstants.textMuted),
                          ),
                        )
                      : ListView.separated(
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const Divider(height: 1, color: StyleConstants.borderLight),
                          itemBuilder: (context, index) {
                            final customer = filtered[index];
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: StyleConstants.primaryColor.withValues(alpha: 0.1),
                                child: Text(
                                  customer.name.isNotEmpty ? customer.name[0].toUpperCase() : '?',
                                  style: const TextStyle(color: StyleConstants.primaryColor, fontWeight: FontWeight.bold),
                                ),
                              ),
                              title: Text(customer.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                              subtitle: Text(customer.phone, style: const TextStyle(fontSize: 12, color: StyleConstants.textMuted)),
                              trailing: const Icon(Icons.check_circle_outline_rounded, color: StyleConstants.primaryColor, size: 20),
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
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal', style: TextStyle(color: StyleConstants.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: StyleConstants.primaryColor,
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
            decoration: StyleConstants.inputDecoration(
              'Instruksi Khusus',
              Icons.note_alt_outlined,
              hintText: 'Misal: Pisahkan pakaian putih, parfum ekstra...',
            ),
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
              backgroundColor: StyleConstants.primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              setState(() {
                _notes[itemId] = controller.text.trim();
              });
              Navigator.pop(ctx);
            },
            child: const Text('Simpan Catatan', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // --- SUBMIT ORDER LOGIC ---
  Future<void> _submitOrder(String mode) async {
    if (_customerNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih atau isi nama pelanggan terlebih dahulu')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final total = _calculateTotal();
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('user_id');

      final orderItems = _allItems
          .where((it) => (_quantities[it.id ?? 0] ?? 0) > 0)
          .map((it) => OrderItem(
                itemName: it.nama,
                quantity: _quantities[it.id ?? 0] ?? 0,
                price: it.harga,
                note: _notes[it.id ?? 0] ?? '',
                machineType: it.machineType ?? 'cuci',
                itemId: it.id ?? 1,
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
        if (!await _updateStocks(orderId)) return;

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
      if (!await _updateStocks(orderId)) return;

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

  Future<bool> _updateStocks(int orderId) async {
    bool allOk = true;
    for (var entry in _quantities.entries.where((e) => e.value > 0)) {
      final success = await _repository.decreaseStock(entry.key, entry.value);
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
                      const Text('Total Tagihan Order:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
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

  // --- MAIN VIEW BUILDER (3-PANE POS WORKSTATION) ---
  @override
  Widget build(BuildContext context) {
    final total = _calculateTotal();
    final totalItems = _calculateTotalItems();

    return Scaffold(
      backgroundColor: StyleConstants.backgroundColor,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Top POS Header Bar
                _buildPosHeader(),

                // 2. Main POS 3-Pane Body
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // SISI KIRI (65%): Catalog Grid & Quick Search
                      Expanded(
                        flex: 65,
                        child: _filteredItems.isEmpty
                            ? const Center(
                                child: Text(
                                  'Tidak ada paket layanan yang sesuai.',
                                  style: TextStyle(color: StyleConstants.textMuted),
                                ),
                              )
                            : GridView.builder(
                                padding: const EdgeInsets.all(18),
                                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 270,
                                  crossAxisSpacing: 14,
                                  mainAxisSpacing: 14,
                                  childAspectRatio: 1.32,
                                ),
                                itemCount: _filteredItems.length,
                                itemBuilder: (context, index) {
                                  final item = _filteredItems[index];
                                  final quantity = _quantities[item.id ?? 0] ?? 0;
                                  return _buildProductCard(item, quantity);
                                },
                              ),
                      ),

                      // VERTICAL SPLIT DIVIDER
                      Container(width: 1, color: StyleConstants.borderLight),

                      // SISI KANAN (35%): Sticky Ticket & Checkout Ledger
                      Container(
                        width: StyleConstants.posReceiptWidth,
                        color: Colors.white,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Customer Card Header
                            _buildCustomerTicketSection(),

                            const Divider(height: 1, color: StyleConstants.borderLight),

                            // Items in Cart List
                            Expanded(
                              child: _buildCartItemsList(),
                            ),

                            const Divider(height: 1, color: StyleConstants.borderLight),

                            // Financial Summary & Actions
                            _buildCheckoutSummarySection(total, totalItems),
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

  // --- SUB-WIDGET: POS TOP HEADER ---
  Widget _buildPosHeader() {
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
                'KASIR POS: PESAN LAUNDRY',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: StyleConstants.textHeading,
                  letterSpacing: -0.3,
                ),
              ),
              Text(
                'Layanan Cuci Kiloan, Bedcover, Sepatu & Satuan',
                style: TextStyle(fontSize: 11, color: StyleConstants.textMuted),
              ),
            ],
          ),
          const SizedBox(width: 24),

          // Fast Search Field
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
                  hintText: 'Cari nama layanan / paket laundry (F2)...',
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

          // Clear cart button
          if (_calculateTotalItems() > 0)
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

  // --- SUB-WIDGET: PRODUCT CARD GRID ITEM ---
  Widget _buildProductCard(TransactionModel item, int quantity) {
    final isSelected = quantity > 0;
    final isKiloan = item.nama.toLowerCase().contains('kg') || item.nama.toLowerCase().contains('kilo');
    final isExpress = item.nama.toLowerCase().contains('exp') || item.nama.toLowerCase().contains('kilat');

    return Container(
      decoration: BoxDecoration(
        color: isSelected ? StyleConstants.statusInfoBg : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSelected ? StyleConstants.primaryColor : StyleConstants.borderLight,
          width: isSelected ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isSelected
                ? StyleConstants.primaryColor.withValues(alpha: 0.12)
                : const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: isSelected ? 12 : 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _updateQuantity(item.id, true),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Top Row: Icon Avatar + Service Title & Badge
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? StyleConstants.primaryColor
                            : StyleConstants.primaryColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        isExpress
                            ? Icons.bolt_rounded
                            : (isKiloan ? Icons.scale_rounded : Icons.local_laundry_service_rounded),
                        color: isSelected ? Colors.white : StyleConstants.primaryColor,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isExpress
                                  ? const Color(0xFFFEF3C7)
                                  : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              isExpress ? 'EXPRESS' : (isKiloan ? 'KILOAN' : 'REGULER'),
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                color: isExpress ? const Color(0xFFD97706) : StyleConstants.textMuted,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            item.nama,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              color: StyleConstants.textHeading,
                              letterSpacing: -0.3,
                              height: 1.15,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    if (_notes[item.id]?.isNotEmpty == true)
                      Tooltip(
                        message: 'Catatan: ${_notes[item.id]}',
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: StyleConstants.warningColor.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.sticky_note_2_rounded, size: 14, color: StyleConstants.warningColor),
                        ),
                      ),
                  ],
                ),

                // Middle: Big Bold Price
                Text(
                  formatRp(item.harga),
                  style: StyleConstants.tabularNumbers(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w900,
                    color: StyleConstants.primaryColor,
                  ),
                ),

                // Bottom Controls: Note Pill & Quantity Stepper
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Note Button
                    InkWell(
                      onTap: () => _showNoteDialog(item.id ?? 0, item.nama),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _notes[item.id]?.isNotEmpty == true
                              ? StyleConstants.warningColor.withValues(alpha: 0.12)
                              : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: _notes[item.id]?.isNotEmpty == true
                                ? StyleConstants.warningColor.withValues(alpha: 0.4)
                                : StyleConstants.borderLight,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.edit_note_rounded,
                              size: 14,
                              color: _notes[item.id]?.isNotEmpty == true
                                  ? StyleConstants.warningColor
                                  : StyleConstants.textMuted,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Catatan',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: _notes[item.id]?.isNotEmpty == true
                                    ? StyleConstants.warningColor
                                    : StyleConstants.textHeading,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Counter Stepper (- Qty +)
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: StyleConstants.borderLight),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_rounded, size: 16),
                            padding: const EdgeInsets.all(4),
                            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                            color: quantity > 0 ? StyleConstants.dangerColor : Colors.grey[400],
                            onPressed: quantity > 0 ? () => _updateQuantity(item.id, false) : null,
                            tooltip: 'Kurangi',
                          ),
                          Container(
                            constraints: const BoxConstraints(minWidth: 26),
                            alignment: Alignment.center,
                            child: Text(
                              '$quantity',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 14,
                                color: isSelected ? StyleConstants.primaryColor : StyleConstants.textHeading,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_rounded, size: 16),
                            padding: const EdgeInsets.all(4),
                            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                            color: StyleConstants.primaryColor,
                            onPressed: () => _updateQuantity(item.id, true),
                            tooltip: 'Tambah',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- SUB-WIDGET: CUSTOMER TICKET SECTION ---
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
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: StyleConstants.textMuted,
                  letterSpacing: 0.5,
                ),
              ),
              if (_customerNameController.text.isNotEmpty)
                InkWell(
                  onTap: _clearCustomer,
                  child: const Text(
                    'Ganti',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: StyleConstants.primaryColor),
                  ),
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
                  color: _customerNameController.text.isNotEmpty ? StyleConstants.primaryColor.withValues(alpha: 0.4) : StyleConstants.borderLight,
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: StyleConstants.primaryColor.withValues(alpha: 0.1),
                    child: const Icon(Icons.person_rounded, size: 16, color: StyleConstants.primaryColor),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _customerNameController.text.isEmpty
                              ? 'Pilih Pelanggan (Klik di sini)...'
                              : _customerNameController.text,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: _customerNameController.text.isEmpty ? StyleConstants.textMuted : StyleConstants.textHeading,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (_customerPhoneController.text.isNotEmpty)
                          Text(
                            _customerPhoneController.text,
                            style: const TextStyle(fontSize: 11, color: StyleConstants.textMuted),
                          ),
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

  // --- SUB-WIDGET: CART ITEMS LIST ---
  Widget _buildCartItemsList() {
    final cartItems = _allItems.where((it) => (_quantities[it.id ?? 0] ?? 0) > 0).toList();

    if (cartItems.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shopping_cart_outlined, size: 36, color: Color(0xFFCBD5E1)),
            SizedBox(height: 8),
            Text(
              'Nota masih kosong.',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: StyleConstants.textMuted),
            ),
            Text(
              'Klik paket di kiri untuk menambahkan.',
              style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
            ),
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
        final qty = _quantities[item.id ?? 0] ?? 0;
        final subtotal = item.harga * qty;
        final note = _notes[item.id];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '$qty x ',
                  style: const TextStyle(fontWeight: FontWeight.w900, color: StyleConstants.primaryColor, fontSize: 13),
                ),
                Expanded(
                  child: Text(
                    item.nama,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: StyleConstants.textHeading),
                  ),
                ),
                Text(
                  formatRp(subtotal),
                  style: StyleConstants.tabularNumbers(fontSize: 13, fontWeight: FontWeight.w800),
                ),
                const SizedBox(width: 6),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 16, color: StyleConstants.textMuted),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => setState(() => _quantities[item.id ?? 0] = 0),
                ),
              ],
            ),
            if (note != null && note.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 24),
                child: Text(
                  'Catatan: $note',
                  style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: StyleConstants.primaryColor),
                ),
              ),
          ],
        );
      },
    );
  }

  // --- SUB-WIDGET: FINANCIAL TOTALS & ACTION BUTTONS ---
  Widget _buildCheckoutSummarySection(int total, int totalItems) {
    return Container(
      padding: const EdgeInsets.all(18),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total Kuantitas:', style: TextStyle(fontSize: 12.5, color: StyleConstants.textMuted)),
              Text('$totalItems Item', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
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

          // Primary Checkout Button
          ElevatedButton(
            onPressed: totalItems > 0 && !_isSubmitting ? () => _submitOrder('lunas') : null,
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

          // Secondary Split & Credit Buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: totalItems > 0 && !_isSubmitting ? () => _submitOrder('bayar_setengah') : null,
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
                  onPressed: totalItems > 0 && !_isSubmitting ? () => _submitOrder('belum_bayar') : null,
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

  // --- WHATSAPP RECEIPT DISPATCH ENGINE ---
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
    buffer.writeln("   *SMART LAUNDRY PRO*");
    buffer.writeln("=========================");
    buffer.writeln("Halo Kak *${name}*, berikut adalah rincian pesanan cuci Kakak:\n");
    buffer.writeln("*Nota #${orderId}* - _(${dateStr})_");
    buffer.writeln("---------------------------------");
    buffer.writeln("*DETAIL LAYANAN:*");

    for (var item in finalOrder.items) {
      if (item.quantity == 1) {
        buffer.writeln("- *${item.itemName}* -> *${formatRp(item.price)}*");
      } else {
        buffer.writeln("- *${item.itemName}* -> *${item.quantity} x ${formatRp(item.price)}* = *${formatRp(item.price * item.quantity)}*");
      }
      if (item.note != null && item.note!.trim().isNotEmpty) {
        buffer.writeln("  _Catatan: ${item.note!.trim()}_");
      }
    }

    buffer.writeln("---------------------------------");
    buffer.writeln("*TOTAL TAGIHAN:* *${formatRp(finalOrder.totalAmount)}*");
    buffer.writeln("*STATUS PEMBAYARAN:* *${statusBayar}*");
    buffer.writeln("---------------------------------");
    buffer.writeln("*INFORMASI:* Kakak akan menerima pesan WhatsApp otomatis ketika proses pencucian dimulai dan setelah selesai/siap diambil.");
    buffer.writeln("=========================");
    buffer.writeln("Terima kasih telah mempercayakan pakaian Kakak kepada kami.");

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
