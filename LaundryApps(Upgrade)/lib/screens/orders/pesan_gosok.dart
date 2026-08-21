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

class PesanGosokPage extends StatefulWidget {
  const PesanGosokPage({super.key});

  @override
  State<PesanGosokPage> createState() => _PesanGosokPageState();
}

class _PesanGosokPageState extends State<PesanGosokPage> {
  final TransactionRepository _repository = TransactionRepository();
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;

  // Catalog & Cart State
  List<TransactionModel> _allItems = [];
  List<TransactionModel> _filteredItems = [];
  Map<int, double> _weights = {};
  final Map<int, String> _notes = {};
  bool _isLoading = true;
  bool _isSubmitting = false;

  // Customer Management
  final TextEditingController _customerNameController = TextEditingController();
  final TextEditingController _customerPhoneController = TextEditingController();
  final TextEditingController _searchProductController = TextEditingController();
  List<Customer> _allCustomers = [];

  // Payment Studio State
  String _selectedPaymentTab = 'cash'; // 'cash', 'qris', 'tempo'
  String _tempoSubMode = 'piutang'; // 'piutang', 'dp'
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
      if (query.isEmpty) {
        _filteredItems = List.from(_allItems);
      } else {
        _filteredItems = _allItems.where((item) => item.nama.toLowerCase().contains(query)).toList();
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
      _cashController.clear();
      _dpController.clear();
      _qrisUrl = null;
      _qrisId = null;
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
    for (var w in _weights.values) {
      total += w;
    }
    return double.parse(total.toStringAsFixed(1));
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
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal', style: TextStyle(color: StyleConstants.textMuted)),
          ),
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

  // =========================================================
  // INTEGRATED DIRECT CHECKOUT & PAYMENT ENGINE
  // =========================================================
  Future<void> _processAllInOneCheckout() async {
    final total = _calculateTotal();
    final totalWeight = _calculateTotalWeight();

    if (totalWeight <= 0 || total <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih minimal 1 paket layanan setrika terlebih dahulu!'), backgroundColor: StyleConstants.warningColor),
      );
      return;
    }

    if (_customerNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Harap pilih atau isi nama pelanggan terlebih dahulu!'), backgroundColor: StyleConstants.warningColor),
      );
      return;
    }

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
          .where((it) => (_weights[it.id ?? 0] ?? 0.0) > 0)
          .map((it) {
            final w = _weights[it.id ?? 0] ?? 0.0;
            return OrderItem(
              itemName: it.nama,
              quantity: w.ceil(),
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
        const SnackBar(content: Text('Tambahkan item setrika terlebih dahulu!'), backgroundColor: StyleConstants.warningColor),
      );
      return;
    }

    setState(() {
      _isGeneratingQris = true;
      _qrisError = null;
    });

    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final orderId = 'QRIS-GOSOK-$timestamp';

      final response = await MidtransService.createQRISTransaction(
        orderId: orderId,
        amount: total.toDouble(),
        customerName: _customerNameController.text.isNotEmpty ? _customerNameController.text : 'Pelanggan Setrika',
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
    buffer.writeln("   *AZIMA GOSOK & SETRIKA*");
    buffer.writeln("=========================");
    buffer.writeln("Halo Kak *$name*, berikut adalah rincian nota setrika Kakak:\n");
    buffer.writeln("*Nota #$orderId* - _($dateStr)_");
    buffer.writeln("---------------------------------");
    buffer.writeln("*DETAIL LAYANAN:*");

    for (var item in finalOrder.items) {
      buffer.writeln("- *${item.itemName}* -> *${formatRp(item.price)}*");
      if (item.note != null && item.note!.trim().isNotEmpty) {
        buffer.writeln("  _Catatan: ${item.note!.trim()}_");
      }
    }

    buffer.writeln("---------------------------------");
    buffer.writeln("*TOTAL TAGIHAN:* *${formatRp(finalOrder.totalAmount)}*");
    buffer.writeln("*STATUS PEMBAYARAN:* *$statusBayar*");
    buffer.writeln("---------------------------------");
    buffer.writeln("*INFORMASI:* Kakak akan menerima pesan WhatsApp otomatis setelah proses penyetrikaan selesai dilakukan dan pakaian siap diambil.");
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
  // MAIN VIEW: INTEGRATED SPLIT WORKSTATION (60% : 40%)
  // =========================================================
  @override
  Widget build(BuildContext context) {
    final total = _calculateTotal();
    final totalWeight = _calculateTotalWeight();

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.pop(context),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: const Color(0xFFF1F5F9), // Slate 100 Workbench Ground
          body: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Top Header Bar
                    _buildHeaderBar(),

                    // Main 2-Container Workspace (60% : 40%)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(14.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // =========================================================
                            // CONTAINER KIRI: KATALOG SETRIKA KOMPAK & PADAT (58%)
                            // =========================================================
                            Expanded(
                              flex: 58,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: StyleConstants.borderLight),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF0F172A).withValues(alpha: 0.03),
                                      blurRadius: 10,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    // Catalog Section Header
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                                      decoration: const BoxDecoration(
                                        color: Color(0xFFF8FAFC),
                                        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                                        border: Border(bottom: BorderSide(color: StyleConstants.borderLight)),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.iron_rounded, size: 18, color: Color(0xFFF97316)),
                                          const SizedBox(width: 8),
                                          const Text(
                                            'Katalog Tarif Gosok & Setrika Uap',
                                            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: StyleConstants.textHeading),
                                          ),
                                          const Spacer(),
                                          Text(
                                            '${_filteredItems.length} Paket Tarif Tersedia',
                                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: StyleConstants.textMuted),
                                          ),
                                        ],
                                      ),
                                    ),

                                    // Catalog Grid
                                    Expanded(
                                      child: _filteredItems.isEmpty
                                          ? Center(
                                              child: Column(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  Icon(Icons.inventory_2_outlined, size: 42, color: Colors.grey[300]),
                                                  const SizedBox(height: 10),
                                                  const Text(
                                                    'Belum ada paket tarif setrika.',
                                                    style: TextStyle(color: StyleConstants.textMuted, fontSize: 13, fontWeight: FontWeight.w600),
                                                  ),
                                                ],
                                              ),
                                            )
                                          : GridView.builder(
                                              padding: const EdgeInsets.all(14),
                                              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                                maxCrossAxisExtent: 220,
                                                crossAxisSpacing: 10,
                                                mainAxisSpacing: 10,
                                                childAspectRatio: 1.52,
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
                            ),

                            const SizedBox(width: 14),

                            // =========================================================
                            // CONTAINER KANAN: NOTA STRUK & PEMBAYARAN TERPADU (42%)
                            // =========================================================
                            Expanded(
                              flex: 42,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: StyleConstants.borderLight),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF0F172A).withValues(alpha: 0.04),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    // 1. Customer Header Badge
                                    _buildCustomerTicketSection(),

                                    const Divider(height: 1, color: StyleConstants.borderLight),

                                    // 2. Scrollable Cart Items Slip
                                    Expanded(
                                      child: _buildCartItemsList(),
                                    ),

                                    const Divider(height: 1, color: StyleConstants.borderLight),

                                    // 3. Integrated Payment & Total Section
                                    _buildIntegratedPaymentSection(total, totalWeight),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
        ),
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
            tooltip: 'Kembali ke Dashboard (Esc)',
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 8),
          const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'KASIR POS: PESAN SETRIKA & PEMBAYARAN',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w900,
                  color: StyleConstants.textHeading,
                  letterSpacing: -0.3,
                ),
              ),
              Text(
                'Workstation Kasir Terpadu: Pakaian Kiloan Gosok Saja / Uap Rapi',
                style: TextStyle(fontSize: 10.5, color: StyleConstants.textMuted),
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
                  hintText: 'Cari paket tarif setrika...',
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
    final isExpress = item.nama.toLowerCase().contains('exp') || item.nama.toLowerCase().contains('kilat');

    return Container(
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFFFFF7ED) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? const Color(0xFFF97316) : StyleConstants.borderLight,
          width: isSelected ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isSelected
                ? const Color(0xFFF97316).withValues(alpha: 0.12)
                : const Color(0xFF0F172A).withValues(alpha: 0.02),
            blurRadius: isSelected ? 8 : 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _updateWeight(item.id, 0.5),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Top Title & Icon
                Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFFF97316)
                            : const Color(0xFFF97316).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Icon(
                        isExpress ? Icons.bolt_rounded : Icons.iron_rounded,
                        color: isSelected ? Colors.white : const Color(0xFFF97316),
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item.nama,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: StyleConstants.textHeading,
                          letterSpacing: -0.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_notes[item.id]?.isNotEmpty == true)
                      InkWell(
                        onTap: () => _showNoteDialog(item.id ?? 0, item.nama),
                        child: const Icon(Icons.sticky_note_2_rounded, size: 14, color: Color(0xFFF97316)),
                      )
                    else
                      InkWell(
                        onTap: () => _showNoteDialog(item.id ?? 0, item.nama),
                        child: const Icon(Icons.note_add_outlined, size: 14, color: StyleConstants.textMuted),
                      ),
                  ],
                ),

                // Bottom Price & Stepper
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      formatRp(item.harga),
                      style: StyleConstants.tabularNumbers(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFFF97316),
                      ),
                    ),

                    // Counter Stepper (- Kg +)
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: StyleConstants.borderLight),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_rounded, size: 14),
                            padding: const EdgeInsets.all(2),
                            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                            color: weight > 0 ? StyleConstants.dangerColor : Colors.grey[400],
                            onPressed: weight > 0 ? () => _updateWeight(item.id, -0.5) : null,
                            tooltip: 'Kurangi 0.5 Kg',
                          ),
                          InkWell(
                            onTap: () => _setCustomWeight(item.id ?? 0, item.nama),
                            child: Container(
                              constraints: const BoxConstraints(minWidth: 24),
                              alignment: Alignment.center,
                              child: Text(
                                '$weight',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12.5,
                                  color: isSelected ? const Color(0xFFF97316) : StyleConstants.textHeading,
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_rounded, size: 14),
                            padding: const EdgeInsets.all(2),
                            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                            color: const Color(0xFFF97316),
                            onPressed: () => _updateWeight(item.id, 0.5),
                            tooltip: 'Tambah 0.5 Kg',
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

  Widget _buildCustomerTicketSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
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
                  _customerNameController.text.isEmpty
                      ? 'Pilih Pelanggan...'
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
          if (_customerNameController.text.isNotEmpty) ...[
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 16, color: StyleConstants.dangerColor),
              onPressed: _clearCustomer,
              tooltip: 'Hapus Pelanggan',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: 8),
          ],
          OutlinedButton(
            onPressed: _showCustomerPicker,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              side: const BorderSide(color: StyleConstants.borderLight),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            child: Text(
              _customerNameController.text.isEmpty ? 'Pilih (+)' : 'Ganti',
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFFF97316)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCartItemsList() {
    final cartItems = _allItems.where((it) => (_weights[it.id ?? 0] ?? 0.0) > 0).toList();

    if (cartItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shopping_bag_outlined, size: 36, color: Colors.grey[300]),
            const SizedBox(height: 8),
            const Text(
              'Nota Pesanan Masih Kosong',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: StyleConstants.textMuted),
            ),
            const Text(
              'Pilih tarif setrika di sebelah kiri.',
              style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      itemCount: cartItems.length,
      separatorBuilder: (_, __) => const Divider(height: 12, color: StyleConstants.borderLight),
      itemBuilder: (context, index) {
        final item = cartItems[index];
        final w = _weights[item.id ?? 0] ?? 0.0;
        final subtotal = (item.harga * w).round();
        final note = _notes[item.id];

        return Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFF97316).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '$w kg',
                style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFFF97316), fontSize: 12),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.nama,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: StyleConstants.textHeading),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (note != null && note.trim().isNotEmpty)
                    Text(
                      'Catatan: $note',
                      style: const TextStyle(fontSize: 10.5, fontStyle: FontStyle.italic, color: Color(0xFFF97316)),
                    ),
                ],
              ),
            ),
            Text(
              formatRp(subtotal),
              style: StyleConstants.tabularNumbers(fontSize: 12.5, fontWeight: FontWeight.w800),
            ),
            const SizedBox(width: 6),
            InkWell(
              onTap: () => setState(() => _weights[item.id ?? 0] = 0.0),
              child: const Icon(Icons.close_rounded, size: 16, color: StyleConstants.textMuted),
            ),
          ],
        );
      },
    );
  }

  // --- INTEGRATED PAYMENT & TOTAL SECTION (PANE KANAN BAWAH) ---
  Widget _buildIntegratedPaymentSection(int total, double totalWeight) {
    final change = _cashReceived - total;
    final isCashValid = total > 0 && _cashReceived >= total;
    final isDpValid = total > 0 && _dpAmount > 0 && _dpAmount < total;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Total Amount Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('TOTAL TAGIHAN:', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: StyleConstants.textMuted, letterSpacing: 0.5)),
                  Text('$totalWeight Kg Dipilih', style: const TextStyle(fontSize: 11, color: StyleConstants.textMuted)),
                ],
              ),
              Text(
                formatRp(total),
                style: StyleConstants.tabularNumbers(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFFF97316),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Payment Method Selector (3-Pills)
          Row(
            children: [
              Expanded(
                child: _methodTab(key: 'cash', label: 'Tunai', icon: Icons.payments_rounded, color: StyleConstants.successColor),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _methodTab(key: 'qris', label: 'QRIS', icon: Icons.qr_code_scanner_rounded, color: StyleConstants.primaryColor),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _methodTab(key: 'tempo', label: 'Tempo/DP', icon: Icons.schedule_rounded, color: const Color(0xFFF97316)),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // --- 1. CASH WORKBENCH ---
          if (_selectedPaymentTab == 'cash') ...[
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: isCashValid ? StyleConstants.successColor : StyleConstants.borderFocus, width: 1.5),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              child: Row(
                children: [
                  const Text('Rp', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: StyleConstants.textMuted)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _cashController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [ThousandsSeparatorInputFormatter()],
                      style: StyleConstants.tabularNumbers(fontSize: 19, fontWeight: FontWeight.w900),
                      decoration: const InputDecoration(hintText: '0', border: InputBorder.none),
                      onSubmitted: (_) {
                        if (isCashValid && !_isSubmitting) _processAllInOneCheckout();
                      },
                    ),
                  ),
                  if (_cashReceived > 0)
                    InkWell(
                      onTap: () => _cashController.clear(),
                      child: const Icon(Icons.clear_rounded, size: 16, color: StyleConstants.textMuted),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // Quick Cash Denomination Chips
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                _quickCashChip(total, 'Uang Pas', isExact: true),
                _quickCashChip(10000, '10k'),
                _quickCashChip(20000, '20k'),
                _quickCashChip(50000, '50k'),
                _quickCashChip(100000, '100k'),
                _quickCashChip(200000, '200k'),
              ],
            ),
            const SizedBox(height: 10),

            // Kembalian Banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: (change >= 0) ? const Color(0xFFECFDF5) : const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: (change >= 0) ? const Color(0xFFA7F3D0) : const Color(0xFFFDE68A)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    (change >= 0) ? 'KEMBALIAN TUNAI:' : 'UANG KURANG:',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                      color: (change >= 0) ? const Color(0xFF047857) : const Color(0xFFB45309),
                    ),
                  ),
                  Text(
                    formatRp((change >= 0) ? change : change.abs()),
                    style: StyleConstants.tabularNumbers(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: (change >= 0) ? const Color(0xFF047857) : const Color(0xFFB45309),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            ElevatedButton(
              onPressed: (isCashValid && !_isSubmitting) ? _processAllInOneCheckout : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: StyleConstants.successColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              child: _isSubmitting
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('BAYAR LUNAS & CETAK STRUK (ENTER)', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
            ),
          ],

          // --- 2. QRIS WORKBENCH ---
          if (_selectedPaymentTab == 'qris') ...[
            if (_qrisUrl == null) ...[
              if (_qrisError != null) ...[
                Text('Error: $_qrisError', style: const TextStyle(color: Colors.red, fontSize: 11, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
              ],
              ElevatedButton.icon(
                onPressed: _isGeneratingQris ? null : _generateQrisBarcode,
                icon: _isGeneratingQris
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.qr_code_scanner_rounded, size: 16),
                label: const Text('BUAT QRIS MIDTRANS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: StyleConstants.primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ] else ...[
              Row(
                children: [
                  QrImageView(data: _qrisUrl!, version: QrVersions.auto, size: 90),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Scan QRIS Pelanggan', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        Text('Status: ${_lastQrisStatus ?? "Menunggu"}', style: const TextStyle(fontSize: 11, color: StyleConstants.warningColor, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        OutlinedButton(
                          onPressed: () {
                            _qrisTimer?.cancel();
                            setState(() {
                              _qrisUrl = null;
                              _qrisId = null;
                            });
                          },
                          child: const Text('Batal QRIS', style: TextStyle(fontSize: 11, color: StyleConstants.dangerColor)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ],

          // --- 3. TEMPO / DP WORKBENCH ---
          if (_selectedPaymentTab == 'tempo') ...[
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _tempoSubMode = 'piutang'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: _tempoSubMode == 'piutang' ? const Color(0xFFFEF2F2) : Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: _tempoSubMode == 'piutang' ? StyleConstants.dangerColor : StyleConstants.borderLight),
                      ),
                      child: Center(
                        child: Text(
                          '100% Piutang (Tempo)',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _tempoSubMode == 'piutang' ? StyleConstants.dangerColor : StyleConstants.textMuted),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _tempoSubMode = 'dp'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: _tempoSubMode == 'dp' ? const Color(0xFFFFFBEB) : Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: _tempoSubMode == 'dp' ? StyleConstants.warningColor : StyleConstants.borderLight),
                      ),
                      child: Center(
                        child: Text(
                          'Bayar DP Sebagian',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _tempoSubMode == 'dp' ? StyleConstants.warningColor : StyleConstants.textMuted),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            if (_tempoSubMode == 'dp') ...[
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: StyleConstants.warningColor),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                child: TextField(
                  controller: _dpController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [ThousandsSeparatorInputFormatter()],
                  style: StyleConstants.tabularNumbers(fontSize: 16, fontWeight: FontWeight.bold),
                  decoration: const InputDecoration(hintText: 'Nominal DP...', border: InputBorder.none),
                ),
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: (isDpValid && !_isSubmitting) ? _processAllInOneCheckout : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: StyleConstants.warningColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('KONFIRMASI BAYAR DP', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
              ),
            ] else ...[
              ElevatedButton(
                onPressed: (total > 0 && !_isSubmitting) ? _processAllInOneCheckout : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: StyleConstants.dangerColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('SIMPAN NOTA PIUTANG (TEMPO)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _methodTab({required String key, required String label, required IconData icon, required Color color}) {
    final isSelected = _selectedPaymentTab == key;
    return InkWell(
      onTap: () => setState(() => _selectedPaymentTab = key),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? color : StyleConstants.borderLight),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: isSelected ? Colors.white : color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: isSelected ? Colors.white : StyleConstants.textHeading,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickCashChip(int amount, String label, {bool isExact = false}) {
    final isSelected = _cashReceived == amount;
    return InkWell(
      onTap: () => _setQuickCash(amount),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: isExact
              ? (isSelected ? const Color(0xFFF97316) : const Color(0xFFF97316).withValues(alpha: 0.1))
              : (isSelected ? StyleConstants.textHeading : Colors.white),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isExact
                ? const Color(0xFFF97316)
                : (isSelected ? StyleConstants.textHeading : StyleConstants.borderLight),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: isExact
                ? (isSelected ? Colors.white : const Color(0xFFF97316))
                : (isSelected ? Colors.white : StyleConstants.textHeading),
          ),
        ),
      ),
    );
  }
}
