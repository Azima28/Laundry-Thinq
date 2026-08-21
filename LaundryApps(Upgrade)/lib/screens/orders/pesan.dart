import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../database/models/transaction_model.dart';
import '../../transactions/transaction_repository.dart';
import '../../database/models/order_model.dart';
import '../../database/models/customer_model.dart';
import '../../database/models/database_helper.dart';
import '../../services/midtrans_service.dart';
import '../../services/machine_status_service.dart';
import '../../utils/currency_format.dart';
import '../../utils/style_constants.dart';
import 'receipt_screen.dart';

class PesanPage extends StatefulWidget {
  const PesanPage({super.key});

  @override
  State<PesanPage> createState() => _PesanPageState();
}

class _PesanPageState extends State<PesanPage> {
  final TransactionRepository _repository = TransactionRepository();
  late DatabaseHelper _databaseHelper;

  // Catalog & Cart State
  List<TransactionModel> _allItems = [];
  List<TransactionModel> _filteredItems = [];
  Map<int, int> _quantities = {};
  final Map<int, String> _notes = {};
  bool _isLoading = true;
  bool _isSubmitting = false;

  // Customer Management
  final TextEditingController _customerNameController = TextEditingController();
  final TextEditingController _customerPhoneController = TextEditingController();
  final TextEditingController _searchProductController = TextEditingController();
  List<Customer> _allCustomers = [];

  // ==========================================
  // REAL-TIME INTEGRATED PAYMENT STUDIO STATE
  // ==========================================
  String _selectedPaymentTab = 'cash'; // 'cash', 'qris', 'tempo'
  String _tempoSubMode = 'piutang'; // 'piutang' (100% tempo), 'dp' (bayar sebagian)
  final TextEditingController _cashController = TextEditingController();
  final TextEditingController _dpController = TextEditingController();
  int _cashReceived = 0;
  int _dpAmount = 0;

  // Midtrans QRIS Live State
  String? _qrisUrl;
  String? _qrisId;
  String? _lastQrisStatus;
  String? _qrisError;
  bool _isGeneratingQris = false;
  Timer? _qrisTimer;
  String _midtransServerKey = '';

  @override
  void initState() {
    super.initState();
    _databaseHelper = DatabaseHelper.instance;
    _loadItems();
    _loadCustomers();
    _loadPaymentCredentials();

    _searchProductController.addListener(_filterProducts);

    _cashController.addListener(() {
      final text = _cashController.text.replaceAll('.', '').replaceAll(',', '');
      final parsed = int.tryParse(text) ?? 0;
      setState(() => _cashReceived = parsed);
    });

    _dpController.addListener(() {
      final text = _dpController.text.replaceAll('.', '').replaceAll(',', '');
      final parsed = int.tryParse(text) ?? 0;
      setState(() => _dpAmount = parsed);
    });
  }

  @override
  void dispose() {
    _qrisTimer?.cancel();
    _searchProductController.dispose();
    _customerNameController.dispose();
    _customerPhoneController.dispose();
    _cashController.dispose();
    _dpController.dispose();
    super.dispose();
  }

  Future<void> _loadPaymentCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _midtransServerKey = prefs.getString('midtrans_server_key') ?? '';
        });
      }
    } catch (_) {}
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
      _customerNameController.text = customer.name;
      _customerPhoneController.text = customer.phone;
    });
  }

  void _clearCustomer() {
    setState(() {
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
      _cashController.clear();
      _dpController.clear();
      _qrisUrl = null;
      _qrisId = null;
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
    for (var qty in _quantities.values) {
      total += qty;
    }
    return total;
  }

  void _setQuickCash(int amount) {
    if (amount <= 0) {
      _cashController.clear();
    } else {
      final formatted = ThousandsSeparatorInputFormatter.format(amount.toString());
      _cashController.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }
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

  // =========================================================
  // INTEGRATED ALL-IN-ONE DIRECT CHECKOUT & PAYMENT ENGINE
  // =========================================================
  Future<void> _processAllInOneCheckout() async {
    final total = _calculateTotal();
    final totalItems = _calculateTotalItems();

    if (totalItems <= 0 || total <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih minimal 1 paket layanan cucian terlebih dahulu!'), backgroundColor: StyleConstants.warningColor),
      );
      return;
    }

    if (_customerNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Harap pilih atau isi nama pelanggan terlebih dahulu!'), backgroundColor: StyleConstants.warningColor),
      );
      return;
    }

    // Validation per payment mode
    bool isPaidFlag = false;
    int paidAmount = 0;
    String paymentMethodName = 'Tunai';

    if (_selectedPaymentTab == 'cash') {
      if (_cashReceived < total) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Uang tunai yang diterima kurang dari total tagihan!'), backgroundColor: StyleConstants.warningColor),
        );
        return;
      }
      isPaidFlag = true;
      paidAmount = total;
      paymentMethodName = 'Tunai / Cash';
    } else if (_selectedPaymentTab == 'tempo') {
      if (_tempoSubMode == 'dp') {
        if (_dpAmount <= 0 || _dpAmount >= total) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Jumlah DP harus lebih dari Rp 0 dan kurang dari total tagihan!'), backgroundColor: StyleConstants.warningColor),
          );
          return;
        }
        isPaidFlag = false;
        paidAmount = _dpAmount;
        paymentMethodName = 'Tunai (DP)';
      } else {
        isPaidFlag = false;
        paidAmount = 0;
        paymentMethodName = 'Belum Lunas';
      }
    } else if (_selectedPaymentTab == 'qris') {
      isPaidFlag = true;
      paidAmount = total;
      paymentMethodName = 'QRIS Dinamis';
    }

    setState(() => _isSubmitting = true);

    try {
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
        isPaid: isPaidFlag,
        totalAmount: total,
        paidAmount: paidAmount,
        paymentMethod: paymentMethodName,
        items: orderItems,
        userId: userId ?? 1,
        qrisUrl: _qrisUrl,
        qrisId: _qrisId,
        paymentTimestamp: DateTime.now(),
      );

      final orderId = await _databaseHelper.insertOrder(order);
      final finalOrder = order.copyWith(id: orderId);

      // Decrease stocks
      for (var entry in _quantities.entries.where((e) => e.value > 0)) {
        await _repository.decreaseStock(entry.key, entry.value);
      }

      // Send WhatsApp Receipt
      _sendWaReceipt(finalOrder, paymentMethodName, paidAmount);

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => ReceiptScreen(
              order: finalOrder,
              isPaid: isPaidFlag,
              paymentMethod: paymentMethodName,
              paidAmount: paidAmount,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memproses transaksi: $e'), backgroundColor: StyleConstants.dangerColor),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // --- QRIS LIVE GENERATOR ---
  Future<void> _generateQrisBarcode() async {
    final total = _calculateTotal();
    if (total <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tambahkan item cucian terlebih dahulu!'), backgroundColor: StyleConstants.warningColor),
      );
      return;
    }

    setState(() {
      _isGeneratingQris = true;
      _qrisError = null;
    });

    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final orderId = 'QRIS-POS-$timestamp';

      final response = await MidtransService.createQRISTransaction(
        orderId: orderId,
        amount: total.toDouble(),
        customerName: _customerNameController.text.isNotEmpty ? _customerNameController.text : 'Pelanggan Laundry',
        overrideServerKey: _midtransServerKey,
      );

      if (response['success'] != true) {
        setState(() {
          _qrisError = response['message']?.toString() ?? 'Gagal membuat QRIS';
          _isGeneratingQris = false;
        });
        return;
      }

      final qrisData = response['qris_url'] ?? response['qr_code_url'];
      if (qrisData == null || qrisData.toString().isEmpty) {
        setState(() {
          _qrisError = 'QR Code tidak ditemukan dalam respon';
          _isGeneratingQris = false;
        });
        return;
      }

      setState(() {
        _qrisUrl = qrisData.toString();
        _qrisId = orderId;
        _lastQrisStatus = response['transaction_status'];
        _isGeneratingQris = false;
      });

      _startQrisPolling(orderId);
    } catch (e) {
      setState(() {
        _qrisError = e.toString();
        _isGeneratingQris = false;
      });
    }
  }

  void _startQrisPolling(String orderId) {
    _qrisTimer?.cancel();
    _qrisTimer = Timer.periodic(const Duration(seconds: 4), (timer) async {
      try {
        final status = await MidtransService.checkTransactionStatus(
          orderId,
          overrideServerKey: _midtransServerKey,
        );

        final st = status['transaction_status']?.toString();
        if (mounted) setState(() => _lastQrisStatus = st);

        if (st == 'settlement' || st == 'capture') {
          _qrisTimer?.cancel();
          _processAllInOneCheckout();
        }
      } catch (_) {}
    });
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
      statusBayar = 'BELUM LUNAS (Telah Dibayar DP: ${formatRp(paidAmount)})';
    }

    final buffer = StringBuffer();
    buffer.writeln("=========================");
    buffer.writeln("   *SMART LAUNDRY PRO*");
    buffer.writeln("=========================");
    buffer.writeln("Halo Kak *$name*, berikut adalah rincian pesanan cuci Kakak:\n");
    buffer.writeln("*Nota #$orderId* - _($dateStr)_");
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
    buffer.writeln("*STATUS PEMBAYARAN:* *$statusBayar*");
    buffer.writeln("---------------------------------");
    buffer.writeln("*INFORMASI:* Kakak akan menerima pesan WhatsApp otomatis ketika proses pencucian dimulai dan setelah selesai/siap diambil.");
    buffer.writeln("=========================");
    buffer.writeln("Terima kasih telah mempercayakan pakaian Kakak kepada kami.");

    try {
      await MachineStatusService.instance.sendCustomWa(
        phone: phone,
        message: buffer.toString(),
      );
    } catch (_) {}
  }

  // =========================================================
  // MAIN VIEW: ALL-IN-ONE 3-PANE POS WORKSTATION
  // =========================================================
  @override
  Widget build(BuildContext context) {
    final total = _calculateTotal();
    final totalItems = _calculateTotalItems();

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.pop(context),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: StyleConstants.backgroundColor,
          body: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 1. Top Universal Header Bar
                    _buildPosHeader(),

                    // 2. All-in-One 3-Pane Workstation Split
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // ==========================================
                          // PANE 1: KATALOG LAYANAN (Flex 44)
                          // ==========================================
                          Expanded(
                            flex: 44,
                            child: Container(
                              color: StyleConstants.backgroundColor,
                              child: _filteredItems.isEmpty
                                  ? const Center(
                                      child: Text(
                                        'Tidak ada paket layanan yang sesuai.',
                                        style: TextStyle(color: StyleConstants.textMuted),
                                      ),
                                    )
                                  : GridView.builder(
                                      padding: const EdgeInsets.all(16),
                                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                        maxCrossAxisExtent: 260,
                                        crossAxisSpacing: 12,
                                        mainAxisSpacing: 12,
                                        childAspectRatio: 1.30,
                                      ),
                                      itemCount: _filteredItems.length,
                                      itemBuilder: (context, index) {
                                        final item = _filteredItems[index];
                                        final quantity = _quantities[item.id ?? 0] ?? 0;
                                        return _buildProductCard(item, quantity);
                                      },
                                    ),
                            ),
                          ),

                          // VERTICAL DIVIDER 1
                          Container(width: 1, color: StyleConstants.borderLight),

                          // ==========================================
                          // PANE 2: NOTA TIKET TRANSAKSI (330px)
                          // ==========================================
                          SizedBox(
                            width: 330,
                            child: Container(
                              color: Colors.white,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // Customer Selector Card
                                  _buildCustomerTicketSection(),

                                  const Divider(height: 1, color: StyleConstants.borderLight),

                                  // Cart Items Scrollable List
                                  Expanded(
                                    child: _buildCartItemsList(),
                                  ),

                                  const Divider(height: 1, color: StyleConstants.borderLight),

                                  // Ledger Quick Recap Bar
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                    color: const Color(0xFFF8FAFC),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text('TOTAL TAGIHAN:', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: StyleConstants.textMuted, letterSpacing: 0.5)),
                                            Text('$totalItems Layanan Dipilih', style: const TextStyle(fontSize: 11, color: StyleConstants.textMuted)),
                                          ],
                                        ),
                                        Text(
                                          formatRp(total),
                                          style: StyleConstants.tabularNumbers(
                                            fontSize: 20,
                                            fontWeight: FontWeight.w900,
                                            color: StyleConstants.primaryColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // VERTICAL DIVIDER 2
                          Container(width: 1, color: StyleConstants.borderLight),

                          // ==========================================
                          // PANE 3: STUDIO PEMBAYARAN LANGSUNG (Flex 32)
                          // ==========================================
                          Expanded(
                            flex: 32,
                            child: Container(
                              color: Colors.white,
                              padding: const EdgeInsets.all(22),
                              child: _buildDirectPaymentPane(total),
                            ),
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

  // --- SUB-WIDGET: TOP HEADER BAR ---
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
            tooltip: 'Kembali ke Dashboard (Esc)',
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 8),
          const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'KASIR POS: PESAN LAUNDRY & BAYAR LANGSUNG',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w900,
                  color: StyleConstants.textHeading,
                  letterSpacing: -0.3,
                ),
              ),
              Text(
                'All-in-One POS Studio: Input Cuci, Nota Tiket & Pelunasan Kasir',
                style: TextStyle(fontSize: 10.5, color: StyleConstants.textMuted),
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
                  hintText: 'Cari nama layanan / paket laundry...',
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
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Top Row: Icon Avatar + Service Title & Badge
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
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
                        size: 19,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: isExpress
                                  ? const Color(0xFFFEF3C7)
                                  : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              isExpress ? 'EXPRESS' : (isKiloan ? 'KILOAN' : 'REGULER'),
                              style: TextStyle(
                                fontSize: 9,
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
                              fontSize: 14,
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
                    fontSize: 15.5,
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
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
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
                              size: 13,
                              color: _notes[item.id]?.isNotEmpty == true
                                  ? StyleConstants.warningColor
                                  : StyleConstants.textMuted,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              'Nota',
                              style: TextStyle(
                                fontSize: 10.5,
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
                            icon: const Icon(Icons.remove_rounded, size: 15),
                            padding: const EdgeInsets.all(3),
                            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                            color: quantity > 0 ? StyleConstants.dangerColor : Colors.grey[400],
                            onPressed: quantity > 0 ? () => _updateQuantity(item.id, false) : null,
                            tooltip: 'Kurangi',
                          ),
                          Container(
                            constraints: const BoxConstraints(minWidth: 24),
                            alignment: Alignment.center,
                            child: Text(
                              '$quantity',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 13.5,
                                color: isSelected ? StyleConstants.primaryColor : StyleConstants.textHeading,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_rounded, size: 15),
                            padding: const EdgeInsets.all(3),
                            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
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
      padding: const EdgeInsets.all(14),
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
                  fontSize: 10.5,
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
          const SizedBox(height: 6),

          InkWell(
            onTap: _showCustomerPicker,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                    radius: 13,
                    backgroundColor: StyleConstants.primaryColor.withValues(alpha: 0.1),
                    child: const Icon(Icons.person_rounded, size: 15, color: StyleConstants.primaryColor),
                  ),
                  const SizedBox(width: 8),
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
                            fontSize: 12.5,
                            color: _customerNameController.text.isEmpty ? StyleConstants.textMuted : StyleConstants.textHeading,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (_customerPhoneController.text.isNotEmpty)
                          Text(
                            _customerPhoneController.text,
                            style: const TextStyle(fontSize: 10.5, color: StyleConstants.textMuted),
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
            Icon(Icons.shopping_cart_outlined, size: 34, color: Color(0xFFCBD5E1)),
            SizedBox(height: 8),
            Text(
              'Nota masih kosong.',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: StyleConstants.textMuted),
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
      padding: const EdgeInsets.all(14),
      itemCount: cartItems.length,
      separatorBuilder: (_, __) => const Divider(height: 14, color: StyleConstants.borderLight),
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
                  style: const TextStyle(fontWeight: FontWeight.w900, color: StyleConstants.primaryColor, fontSize: 12.5),
                ),
                Expanded(
                  child: Text(
                    item.nama,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: StyleConstants.textHeading),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  formatRp(subtotal),
                  style: StyleConstants.tabularNumbers(fontSize: 12.5, fontWeight: FontWeight.w800),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 15, color: StyleConstants.textMuted),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => setState(() => _quantities[item.id ?? 0] = 0),
                  tooltip: 'Hapus Item',
                ),
              ],
            ),
            if (note != null && note.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 3, left: 20),
                child: Text(
                  'Catatan: $note',
                  style: const TextStyle(fontSize: 10.5, fontStyle: FontStyle.italic, color: StyleConstants.primaryColor),
                ),
              ),
          ],
        );
      },
    );
  }

  // =========================================================
  // SUB-WIDGET: DIRECT PAYMENT STUDIO (PANE 3)
  // =========================================================
  Widget _buildDirectPaymentPane(int total) {
    final change = _cashReceived - total;
    final isCashValid = total > 0 && _cashReceived >= total;
    final isDpValid = total > 0 && _dpAmount > 0 && _dpAmount < total;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Studio
          const Row(
            children: [
              Icon(Icons.point_of_sale_rounded, color: StyleConstants.primaryColor, size: 20),
              SizedBox(width: 8),
              Text(
                'STUDIO PEMBAYARAN LANGSUNG',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, color: StyleConstants.textHeading, letterSpacing: -0.2),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Payment Method Tabs (3-Pills)
          Row(
            children: [
              Expanded(
                child: _paymentMethodTabBtn(
                  key: 'cash',
                  label: 'Tunai (Cash)',
                  icon: Icons.payments_rounded,
                  color: StyleConstants.successColor,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _paymentMethodTabBtn(
                  key: 'qris',
                  label: 'QRIS',
                  icon: Icons.qr_code_scanner_rounded,
                  color: StyleConstants.primaryColor,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _paymentMethodTabBtn(
                  key: 'tempo',
                  label: 'Tempo/DP',
                  icon: Icons.schedule_rounded,
                  color: const Color(0xFFF97316),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // --- MODE 1: TUNAI / CASH ---
          if (_selectedPaymentTab == 'cash') ...[
            const Text(
              'Input Nominal Uang Tunai Diterima:',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: StyleConstants.textHeading),
            ),
            const SizedBox(height: 8),

            // Cash Input Field
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isCashValid ? StyleConstants.successColor : StyleConstants.borderFocus,
                  width: 2,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Row(
                children: [
                  const Text('Rp', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: StyleConstants.textMuted)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _cashController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [ThousandsSeparatorInputFormatter()],
                      style: StyleConstants.tabularNumbers(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: StyleConstants.textHeading,
                      ),
                      decoration: const InputDecoration(
                        hintText: '0',
                        hintStyle: TextStyle(color: Color(0xFFCBD5E1), fontSize: 24, fontWeight: FontWeight.w900),
                        border: InputBorder.none,
                      ),
                      onSubmitted: (_) {
                        if (isCashValid && !_isSubmitting) _processAllInOneCheckout();
                      },
                    ),
                  ),
                  if (_cashReceived > 0)
                    IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 18, color: StyleConstants.textMuted),
                      onPressed: () => _cashController.clear(),
                      tooltip: 'Reset Input',
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Quick Cash Chips
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _quickCashPill(total, 'Uang Pas', isExact: true),
                _quickCashPill(10000, '10k'),
                _quickCashPill(20000, '20k'),
                _quickCashPill(50000, '50k'),
                _quickCashPill(100000, '100k'),
                _quickCashPill(200000, '200k'),
                _quickCashPill(500000, '500k'),
              ],
            ),
            const SizedBox(height: 16),

            // Live Kembalian / Uang Kurang Box
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: (change >= 0) ? const Color(0xFFECFDF5) : const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: (change >= 0) ? const Color(0xFFA7F3D0) : const Color(0xFFFDE68A),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        (change >= 0) ? Icons.price_check_rounded : Icons.warning_amber_rounded,
                        size: 22,
                        color: (change >= 0) ? StyleConstants.successColor : StyleConstants.warningColor,
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (change >= 0) ? 'KEMBALIAN TUNAI' : 'UANG KURANG',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                              color: (change >= 0) ? const Color(0xFF047857) : const Color(0xFFB45309),
                              letterSpacing: 0.5,
                            ),
                          ),
                          Text(
                            (change >= 0) ? 'Harus diserahkan ke pelanggan' : 'Belum cukup untuk lunas',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: (change >= 0) ? const Color(0xFF065F46) : const Color(0xFF92400E),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Text(
                    formatRp((change >= 0) ? change : change.abs()),
                    style: StyleConstants.tabularNumbers(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: (change >= 0) ? const Color(0xFF047857) : const Color(0xFFB45309),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Submit Button
            ElevatedButton(
              onPressed: (isCashValid && !_isSubmitting) ? _processAllInOneCheckout : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: StyleConstants.successColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              child: _isSubmitting
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle_rounded, size: 18),
                        SizedBox(width: 8),
                        Text('BAYAR LUNAS & CETAK STRUK', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.4)),
                      ],
                    ),
            ),
          ],

          // --- MODE 2: QRIS DINAMIS MIDTRANS ---
          if (_selectedPaymentTab == 'qris') ...[
            if (_qrisUrl == null) ...[
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: StyleConstants.borderLight),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.qr_code_2_rounded, size: 54, color: StyleConstants.primaryColor),
                    const SizedBox(height: 10),
                    const Text('QRIS Dinamis Midtrans', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                    const SizedBox(height: 4),
                    Text(
                      'Buat barcode QRIS instan sebesar ${formatRp(total)}.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 11.5, color: StyleConstants.textMuted),
                    ),
                    if (_qrisError != null) ...[
                      const SizedBox(height: 8),
                      Text('Error: $_qrisError', style: const TextStyle(color: Colors.red, fontSize: 11, fontWeight: FontWeight.bold)),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _isGeneratingQris ? null : _generateQrisBarcode,
                icon: _isGeneratingQris
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.qr_code_scanner_rounded, size: 18),
                label: const Text('GENERATE BARCODE QRIS', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: StyleConstants.primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
              ),
            ] else ...[
              Center(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: StyleConstants.borderLight),
                  ),
                  child: QrImageView(
                    data: _qrisUrl!,
                    version: QrVersions.auto,
                    size: 170.0,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 8),
                  Text('Menunggu scan pelanggan (${_lastQrisStatus ?? "pending"})...', style: const TextStyle(fontSize: 11.5, color: StyleConstants.warningColor, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        _qrisTimer?.cancel();
                        setState(() {
                          _qrisUrl = null;
                          _qrisId = null;
                        });
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('Batal QRIS', style: TextStyle(color: StyleConstants.dangerColor, fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _processAllInOneCheckout,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: StyleConstants.successColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('Manual Selesai', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                  ),
                ],
              ),
            ],
          ],

          // --- MODE 3: TEMPO (PIUTANG) & DP ---
          if (_selectedPaymentTab == 'tempo') ...[
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _tempoSubMode = 'piutang'),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _tempoSubMode == 'piutang' ? const Color(0xFFFEF2F2) : Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _tempoSubMode == 'piutang' ? StyleConstants.dangerColor : StyleConstants.borderLight),
                      ),
                      child: Center(
                        child: Text(
                          '100% Piutang (Tempo)',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: _tempoSubMode == 'piutang' ? StyleConstants.dangerColor : StyleConstants.textMuted,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _tempoSubMode = 'dp'),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _tempoSubMode == 'dp' ? const Color(0xFFFFFBEB) : Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _tempoSubMode == 'dp' ? StyleConstants.warningColor : StyleConstants.borderLight),
                      ),
                      child: Center(
                        child: Text(
                          'Bayar Uang Muka (DP)',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: _tempoSubMode == 'dp' ? StyleConstants.warningColor : StyleConstants.textMuted,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (_tempoSubMode == 'dp') ...[
              const Text('Input Jumlah Uang Muka (DP):', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: StyleConstants.warningColor, width: 1.5),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                child: Row(
                  children: [
                    const Text('Rp', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: StyleConstants.warningColor)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _dpController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [ThousandsSeparatorInputFormatter()],
                        style: StyleConstants.tabularNumbers(fontSize: 20, fontWeight: FontWeight.w900),
                        decoration: const InputDecoration(hintText: '0', border: InputBorder.none),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: StyleConstants.borderLight),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Sisa Jadi Piutang:', style: TextStyle(fontSize: 12, color: StyleConstants.textMuted)),
                    Text(
                      formatRp((total - _dpAmount).clamp(0, total)),
                      style: StyleConstants.tabularNumbers(fontSize: 15, fontWeight: FontWeight.w900, color: StyleConstants.warningColor),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: (isDpValid && !_isSubmitting) ? _processAllInOneCheckout : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: StyleConstants.warningColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                child: _isSubmitting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('KONFIRMASI BAYAR DP (CICILAN)', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFECACA)),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.access_time_filled_rounded, color: StyleConstants.dangerColor, size: 36),
                    const SizedBox(height: 8),
                    const Text('Bayar Nanti Saat Ambil Cucian', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: StyleConstants.dangerColor)),
                    const SizedBox(height: 4),
                    Text(
                      'Total tagihan ${formatRp(total)} akan dicatat sebagai piutang penuh atas nama "${_customerNameController.text.isNotEmpty ? _customerNameController.text : "Pelanggan"}".',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 11, color: StyleConstants.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: (total > 0 && !_isSubmitting) ? _processAllInOneCheckout : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: StyleConstants.dangerColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                child: _isSubmitting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('SIMPAN SEBAGAI PIUTANG', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _paymentMethodTabBtn({
    required String key,
    required String label,
    required IconData icon,
    required Color color,
  }) {
    final isSelected = _selectedPaymentTab == key;
    return InkWell(
      onTap: () => setState(() => _selectedPaymentTab = key),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? color : StyleConstants.borderLight),
          boxShadow: isSelected
              ? [BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 6, offset: const Offset(0, 2))]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: isSelected ? Colors.white : color),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: isSelected ? Colors.white : StyleConstants.textHeading,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickCashPill(int amount, String label, {bool isExact = false}) {
    final isSelected = _cashReceived == amount;
    return InkWell(
      onTap: () => _setQuickCash(amount),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: isExact
              ? (isSelected ? StyleConstants.primaryColor : StyleConstants.primaryColor.withValues(alpha: 0.08))
              : (isSelected ? StyleConstants.textHeading : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isExact
                ? StyleConstants.primaryColor
                : (isSelected ? StyleConstants.textHeading : StyleConstants.borderLight),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            color: isExact
                ? (isSelected ? Colors.white : StyleConstants.primaryColor)
                : (isSelected ? Colors.white : StyleConstants.textHeading),
          ),
        ),
      ),
    );
  }
}
