import 'dart:async';
import 'dart:math';
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
  String _selectedCategory = 'semua'; // 'semua', 'cuci', 'pengering', 'toko', 'gosok'
  bool _isLoading = true;
  bool _isSubmitting = false;

  int get _cuciCount => _allItems.where((it) {
        final mType = (it.machineType ?? '').toLowerCase();
        final name = it.nama.toLowerCase();
        return mType == 'cuci' || name.contains('cuci') || name.contains('wash');
      }).length;

  int get _pengeringCount => _allItems.where((it) {
        final mType = (it.machineType ?? '').toLowerCase();
        final name = it.nama.toLowerCase();
        return mType == 'pengering' || name.contains('kering') || name.contains('dry');
      }).length;

  int get _gosokCount => _allItems.where((it) {
        final mType = (it.machineType ?? '').toLowerCase();
        final name = it.nama.toLowerCase();
        return mType == 'gosok' || mType == 'iron' || name.contains('gosok') || name.contains('setrika');
      }).length;

  int get _tokoCount => _allItems.where((it) {
        final mType = (it.machineType ?? '').toLowerCase();
        final name = it.nama.toLowerCase();
        final isCuci = mType == 'cuci' || name.contains('cuci') || name.contains('wash');
        final isKering = mType == 'pengering' || name.contains('kering') || name.contains('dry');
        final isGosok = mType == 'gosok' || mType == 'iron' || name.contains('gosok') || name.contains('setrika');
        return !isCuci && !isKering && !isGosok;
      }).length;

  // Customer Management
  final TextEditingController _customerNameController = TextEditingController();
  final TextEditingController _customerPhoneController = TextEditingController();
  final TextEditingController _searchProductController = TextEditingController();
  List<Customer> _allCustomers = [];

  // Loyalty Kupon State
  Map<String, dynamic>? _selectedCustomerLoyalty;
  bool _claimFreeWash = false;
  int _loyaltyThreshold = 5;
  bool _loyaltyEnabled = true;

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
    _databaseHelper = DatabaseHelper.instance;
    _loadItems();
    _loadCustomers();
    _loadPaymentCredentials();
    _loadLoyaltySettings();

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

  Future<void> _loadLoyaltySettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _loyaltyEnabled = prefs.getBool('loyalty_program_enabled') ?? true;
          _loyaltyThreshold = prefs.getInt('loyalty_wash_threshold') ?? 5;
        });
      }
    } catch (_) {}
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
      if (mounted) {
        setState(() {
          _allItems = items;
          _quantities = {for (var item in _allItems) item.id ?? 0: 0};
          _isLoading = false;
        });
        _filterProducts();
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _filterProducts() {
    final query = _searchProductController.text.toLowerCase().trim();
    setState(() {
      _filteredItems = _allItems.where((item) {
        final nameLower = item.nama.toLowerCase();
        final mType = (item.machineType ?? '').toLowerCase();

        // Category filter check
        bool matchesCategory = true;
        if (_selectedCategory == 'cuci') {
          matchesCategory = mType == 'cuci' || nameLower.contains('cuci') || nameLower.contains('wash');
        } else if (_selectedCategory == 'pengering') {
          matchesCategory = mType == 'pengering' || nameLower.contains('kering') || nameLower.contains('dry');
        } else if (_selectedCategory == 'gosok') {
          matchesCategory = mType == 'gosok' || mType == 'iron' || nameLower.contains('gosok') || nameLower.contains('setrika');
        } else if (_selectedCategory == 'toko') {
          final isCuci = mType == 'cuci' || nameLower.contains('cuci') || nameLower.contains('wash');
          final isKering = mType == 'pengering' || nameLower.contains('kering') || nameLower.contains('dry');
          final isGosok = mType == 'gosok' || mType == 'iron' || nameLower.contains('gosok') || nameLower.contains('setrika');
          matchesCategory = !isCuci && !isKering && !isGosok;
        }

        if (!matchesCategory) return false;

        if (query.isEmpty) return true;
        return nameLower.contains(query);
      }).toList();
    });
  }

  bool get _cartHasWashItem {
    for (var it in _allItems) {
      if ((_quantities[it.id ?? 0] ?? 0) > 0) {
        final m = (it.machineType ?? '').toLowerCase();
        final n = it.nama.toLowerCase();
        if (m == 'cuci' || n.contains('cuci') || n.contains('wash') || n.contains('basah')) {
          return true;
        }
      }
    }
    return false;
  }

  TransactionModel? get _firstWashItemInCart {
    for (var it in _allItems) {
      if ((_quantities[it.id ?? 0] ?? 0) > 0) {
        final m = (it.machineType ?? '').toLowerCase();
        final n = it.nama.toLowerCase();
        if (m == 'cuci' || n.contains('cuci') || n.contains('wash') || n.contains('basah')) {
          return it;
        }
      }
    }
    return null;
  }

  bool get _canClaimCuciGratis {
    if (!_loyaltyEnabled) return false;
    final activeStamps = (_selectedCustomerLoyalty?['wash_count_active'] as num?)?.toInt() ?? 0;
    return activeStamps >= _loyaltyThreshold && _loyaltyThreshold > 0;
  }

  Future<void> _onCustomerSelected(Customer customer) async {
    setState(() {
      _customerNameController.text = customer.name;
      _customerPhoneController.text = customer.phone;
      _claimFreeWash = false;
    });

    try {
      final stats = await _databaseHelper.getCustomerFullStats(
        customerId: customer.id,
        name: customer.name,
        phone: customer.phone,
      );
      if (mounted) {
        setState(() {
          _selectedCustomerLoyalty = stats;
          _loyaltyThreshold = stats['loyalty_threshold'] ?? 5;
          _loyaltyEnabled = stats['loyalty_enabled'] ?? true;
        });
      }
    } catch (_) {}
  }

  void _clearCustomer() {
    setState(() {
      _customerNameController.clear();
      _customerPhoneController.clear();
      _selectedCustomerLoyalty = null;
      _claimFreeWash = false;
    });
  }

  void _updateQuantity(int? id, bool increment) {
    if (id == null) return;
    final item = _allItems.firstWhere((it) => it.id == id, orElse: () => _allItems.first);
    setState(() {
      int current = _quantities[id] ?? 0;
      if (increment) {
        if (!item.isUnlimitedStock && item.stock != null && current >= item.stock!) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Stok ${item.nama} tidak mencukupi (sisa: ${item.stock})!'),
              backgroundColor: StyleConstants.warningColor,
              duration: const Duration(seconds: 2),
            ),
          );
          return;
        }
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
      _claimFreeWash = false;
    });
  }

  int _calculateTotal() {
    int total = 0;
    for (var item in _allItems) {
      int qty = _quantities[item.id ?? 0] ?? 0;
      total += qty * item.harga;
    }
    if (_claimFreeWash && _cartHasWashItem) {
      final firstWash = _firstWashItemInCart;
      if (firstWash != null) {
        total -= firstWash.harga;
      }
    }
    return max(0, total);
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
  // INTEGRATED DIRECT CHECKOUT & PAYMENT ENGINE
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

      bool freeApplied = false;
      final List<OrderItem> orderItems = [];

      for (var it in _allItems) {
        final qty = _quantities[it.id ?? 0] ?? 0;
        if (qty <= 0) continue;

        final m = (it.machineType ?? '').toLowerCase();
        final n = it.nama.toLowerCase();
        final isWash = m == 'cuci' || n.contains('cuci') || n.contains('wash') || n.contains('basah');

        if (_claimFreeWash && isWash && !freeApplied) {
          freeApplied = true;
          // Item pertama cuci digratiskan (Rp 0)
          orderItems.add(OrderItem(
            itemName: '${it.nama} (Gratis)',
            quantity: 1,
            price: 0,
            note: (_notes[it.id ?? 0]?.isNotEmpty == true) ? '${_notes[it.id ?? 0]} • Cuci Gratis (Kupon)' : 'Cuci Gratis (Kupon)',
            machineType: 'cuci',
            itemId: it.id ?? 1,
          ));

          if (qty > 1) {
            orderItems.add(OrderItem(
              itemName: it.nama,
              quantity: qty - 1,
              price: it.harga,
              note: _notes[it.id ?? 0] ?? '',
              machineType: it.machineType ?? 'cuci',
              itemId: it.id ?? 1,
            ));
          }
        } else {
          orderItems.add(OrderItem(
            itemName: it.nama,
            quantity: qty,
            price: it.harga,
            note: _notes[it.id ?? 0] ?? '',
            machineType: it.machineType ?? 'cuci',
            itemId: it.id ?? 1,
          ));
        }
      }

      final int lifetimeWashCount = (_selectedCustomerLoyalty?['wash_count_lifetime'] as num?)?.toInt() ?? 0;

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
        loyaltyClaimed: _claimFreeWash,
        stampsUsed: _claimFreeWash ? _loyaltyThreshold : 0,
        washSequence: lifetimeWashCount + 1,
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
      if (item.price == 0) {
        buffer.writeln("- *${item.itemName}* -> *Rp 0 (Gratis)*");
      } else if (item.quantity == 1) {
        buffer.writeln("- *${item.itemName}* -> *${formatRp(item.price)}*");
      } else {
        buffer.writeln("- *${item.itemName}* -> *${item.quantity} x ${formatRp(item.price)}* = *${formatRp(item.price * item.quantity)}*");
      }
      if (item.note != null && item.note!.trim().isNotEmpty) {
        buffer.writeln("  _Catatan: ${item.note!.trim()}_");
      }
    }

    int activeKuponCalc = (_selectedCustomerLoyalty?['wash_count_active'] as num?)?.toInt() ?? 0;
    if (finalOrder.loyaltyClaimed) {
      activeKuponCalc = (activeKuponCalc - finalOrder.stampsUsed).clamp(0, 999999);
    }
    for (var it in finalOrder.items) {
      final n = it.itemName.toLowerCase();
      final m = (it.machineType ?? '').toLowerCase();
      if (m == 'cuci' || n.contains('cuci') || n.contains('wash') || n.contains('basah')) {
        activeKuponCalc += it.quantity;
      }
    }

    buffer.writeln("---------------------------------");
    buffer.writeln("*TOTAL TAGIHAN:* *${formatRp(finalOrder.totalAmount)}*");
    buffer.writeln("*STATUS PEMBAYARAN:* *$statusBayar*");
    if (_loyaltyEnabled) {
      buffer.writeln("---------------------------------");
      buffer.writeln("*Kupon Cuci:* *$activeKuponCalc / $_loyaltyThreshold*");
    }
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
  // MAIN VIEW: INTEGRATED SPLIT WORKSTATION (58% : 42%)
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
          backgroundColor: const Color(0xFFF1F5F9), // Slate 100 Workbench Ground
          body: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Top Universal Header Bar
                    _buildPosHeader(),

                    // Main 2-Container Workspace (58% : 42%)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(14.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // =========================================================
                            // CONTAINER KIRI: KATALOG PRODUK BERAKSEN WARNA (58%)
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
                                      color: const Color(0xFF0F172A).withValues(alpha: 0.04),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    // Catalog Header Ribbon
                                    Container(
                                      padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
                                      decoration: const BoxDecoration(
                                        color: Color(0xFFF8FAFC),
                                        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                                        border: Border(bottom: BorderSide(color: StyleConstants.borderLight)),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: [
                                          Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(6),
                                                decoration: BoxDecoration(
                                                  color: StyleConstants.primaryColor.withValues(alpha: 0.1),
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: const Icon(Icons.grid_view_rounded, size: 16, color: StyleConstants.primaryColor),
                                              ),
                                              const SizedBox(width: 10),
                                              const Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'Katalog Layanan & Produk Laundry',
                                                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: StyleConstants.textHeading),
                                                  ),
                                                  Text(
                                                    'Pilih paket cuci, pengering, dan produk toko untuk nota transaksi',
                                                    style: TextStyle(fontSize: 10.5, color: StyleConstants.textMuted),
                                                  ),
                                                ],
                                              ),
                                              const Spacer(),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFE2E8F0),
                                                  borderRadius: BorderRadius.circular(20),
                                                ),
                                                child: Text(
                                                  '${_filteredItems.length} Item',
                                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: StyleConstants.textHeading),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 10),
                                          // Segment Filter Chips
                                          SingleChildScrollView(
                                            scrollDirection: Axis.horizontal,
                                            child: Row(
                                              children: [
                                                _buildCategoryChip('semua', 'Semua (${_allItems.length})', Icons.dashboard_outlined),
                                                const SizedBox(width: 6),
                                                _buildCategoryChip('cuci', 'Cuci ($_cuciCount)', Icons.local_laundry_service_outlined),
                                                const SizedBox(width: 6),
                                                _buildCategoryChip('pengering', 'Pengering ($_pengeringCount)', Icons.wb_sunny_outlined),
                                                const SizedBox(width: 6),
                                                _buildCategoryChip('toko', 'Produk Toko ($_tokoCount)', Icons.shopping_bag_outlined),
                                                if (_gosokCount > 0) ...[
                                                  const SizedBox(width: 6),
                                                  _buildCategoryChip('gosok', 'Setrika ($_gosokCount)', Icons.iron_outlined),
                                                ],
                                              ],
                                            ),
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
                                                  Container(
                                                    padding: const EdgeInsets.all(16),
                                                    decoration: const BoxDecoration(
                                                      color: Color(0xFFF8FAFC),
                                                      shape: BoxShape.circle,
                                                    ),
                                                    child: Icon(Icons.inventory_2_outlined, size: 40, color: Colors.grey[300]),
                                                  ),
                                                  const SizedBox(height: 12),
                                                  const Text(
                                                    'Tidak ada layanan yang sesuai pencarian.',
                                                    style: TextStyle(color: StyleConstants.textMuted, fontSize: 13, fontWeight: FontWeight.w700),
                                                  ),
                                                ],
                                              ),
                                            )
                                          : GridView.builder(
                                              padding: const EdgeInsets.all(14),
                                              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                                maxCrossAxisExtent: 220,
                                                crossAxisSpacing: 12,
                                                mainAxisSpacing: 12,
                                                childAspectRatio: 1.48,
                                              ),
                                              itemCount: _filteredItems.length,
                                              itemBuilder: (context, index) {
                                                final item = _filteredItems[index];
                                                final quantity = _quantities[item.id ?? 0] ?? 0;
                                                return _buildProductCard(item, quantity);
                                              },
                                            ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            const SizedBox(width: 14),

                            // =========================================================
                            // CONTAINER KANAN: NOTA STRUK & STUDIO BAYAR TERPADU (42%)
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
                                      color: const Color(0xFF0F172A).withValues(alpha: 0.05),
                                      blurRadius: 14,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    // 1. Digital Slip Receipt Header & Customer Card
                                    _buildCustomerTicketSection(),

                                    const Divider(height: 1, color: StyleConstants.borderLight),

                                    // 2. Scrollable Cart Items Slip
                                    Expanded(
                                      child: _buildCartItemsList(),
                                    ),

                                    // 3. Integrated Payment & High-Contrast Total Banner
                                    _buildIntegratedPaymentSection(total, totalItems),
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

  // --- TOP POS HEADER BAR ---
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
                'KASIR POS: PESAN LAUNDRY & PEMBAYARAN',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w900,
                  color: StyleConstants.textHeading,
                  letterSpacing: -0.3,
                ),
              ),
              Text(
                'Workstation Kasir Terpadu (Katalog, Nota Tiket & Pelunasan Kasir)',
                style: TextStyle(fontSize: 10.5, color: StyleConstants.textMuted),
              ),
            ],
          ),
          const SizedBox(width: 24),

          // Search Field
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
                  hintText: 'Cari nama paket cucian...',
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

  Widget _buildCategoryChip(String categoryKey, String label, IconData icon) {
    final bool isSelected = _selectedCategory == categoryKey;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedCategory = categoryKey;
        });
        _filterProducts();
      },
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? StyleConstants.primaryColor : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? StyleConstants.primaryColor : StyleConstants.borderLight,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: StyleConstants.primaryColor.withValues(alpha: 0.25),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: isSelected ? Colors.white : StyleConstants.textMuted,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? Colors.white : StyleConstants.textHeading,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- SUB-WIDGET: PRODUCT CARD RICH ACCENTS ---
  Widget _buildProductCard(TransactionModel item, int quantity) {
    final isSelected = quantity > 0;
    final nameLower = item.nama.toLowerCase();
    final mType = (item.machineType ?? '').toLowerCase();

    final bool isCuci = mType == 'cuci' || nameLower.contains('cuci') || nameLower.contains('wash');
    final bool isPengering = mType == 'pengering' || nameLower.contains('kering') || nameLower.contains('dry');
    final bool isGosok = mType == 'gosok' || mType == 'iron' || nameLower.contains('gosok') || nameLower.contains('setrika');
    final bool isKiloan = nameLower.contains('kg') || nameLower.contains('kilo');
    final bool isExpress = nameLower.contains('exp') || nameLower.contains('kilat');
    final bool isBedcover = nameLower.contains('bed') || nameLower.contains('selimut') || nameLower.contains('sepatu');

    // Distinct Theme Accent Color
    final Color accentColor = isExpress
        ? StyleConstants.warningColor
        : (isPengering
            ? const Color(0xFFD97706) // Amber for Dryer
            : (isCuci
                ? StyleConstants.primaryColor // Blue for Washer
                : (isGosok
                    ? const Color(0xFF7C3AED) // Purple for Ironing
                    : (isKiloan
                        ? StyleConstants.successColor
                        : (isBedcover ? StyleConstants.secondaryColor : const Color(0xFF059669)))))); // Emerald for Store Products/Sabun

    final IconData categoryIcon = isExpress
        ? Icons.bolt_rounded
        : (isPengering
            ? Icons.wb_sunny_rounded
            : (isCuci
                ? Icons.local_laundry_service_rounded
                : (isGosok
                    ? Icons.iron_rounded
                    : (isKiloan
                        ? Icons.scale_rounded
                        : (isBedcover ? Icons.inventory_2_rounded : Icons.shopping_bag_outlined)))));

    final String categoryBadge = isExpress
        ? 'EXPRESS'
        : (isPengering
            ? 'PENGERING'
            : (isCuci
                ? 'CUCI'
                : (isGosok
                    ? 'GOSOK'
                    : (isKiloan ? 'KILOAN' : (isBedcover ? 'SATUAN' : 'PRODUK')))));

    final bool hasStockLimit = !item.isUnlimitedStock && item.stock != null;
    final bool isOutOfStock = hasStockLimit && (item.stock ?? 0) <= 0;

    return Container(
      decoration: BoxDecoration(
        color: isOutOfStock
            ? Colors.grey[100]
            : (isSelected ? accentColor.withValues(alpha: 0.06) : Colors.white),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isOutOfStock
              ? Colors.grey[300]!
              : (isSelected ? accentColor : StyleConstants.borderLight),
          width: isSelected ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isSelected
                ? accentColor.withValues(alpha: 0.16)
                : const Color(0xFF0F172A).withValues(alpha: 0.03),
            blurRadius: isSelected ? 8 : 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isOutOfStock ? null : () => _updateQuantity(item.id, true),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Top Title, Accent Icon & Tag
                Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: isOutOfStock
                            ? Colors.grey[300]
                            : (isSelected
                                ? accentColor
                                : accentColor.withValues(alpha: 0.12)),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Icon(
                        categoryIcon,
                        color: isOutOfStock ? Colors.grey[600] : (isSelected ? Colors.white : accentColor),
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: accentColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  categoryBadge,
                                  style: TextStyle(
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w900,
                                    color: accentColor,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                              ),
                              if (hasStockLimit) ...[
                                const SizedBox(width: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: isOutOfStock
                                        ? StyleConstants.dangerColor.withValues(alpha: 0.1)
                                        : StyleConstants.successColor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    isOutOfStock ? 'Habis' : '${item.stock} unit',
                                    style: TextStyle(
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.w800,
                                      color: isOutOfStock ? StyleConstants.dangerColor : StyleConstants.successColor,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.nama,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 12.5,
                              color: isOutOfStock ? StyleConstants.textMuted : StyleConstants.textHeading,
                              letterSpacing: -0.2,
                              height: 1.1,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    InkWell(
                      onTap: () => _showNoteDialog(item.id ?? 0, item.nama),
                      child: Icon(
                        _notes[item.id]?.isNotEmpty == true ? Icons.sticky_note_2_rounded : Icons.note_add_outlined,
                        size: 15,
                        color: _notes[item.id]?.isNotEmpty == true ? StyleConstants.warningColor : StyleConstants.textMuted,
                      ),
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
                        fontSize: 14.5,
                        fontWeight: FontWeight.w900,
                        color: isOutOfStock
                            ? StyleConstants.textMuted
                            : (isSelected ? accentColor : StyleConstants.textHeading),
                      ),
                    ),

                    // Counter Stepper (- Qty +)
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
                            color: quantity > 0 ? StyleConstants.dangerColor : Colors.grey[400],
                            onPressed: quantity > 0 ? () => _updateQuantity(item.id, false) : null,
                            tooltip: 'Kurangi',
                          ),
                          Container(
                            constraints: const BoxConstraints(minWidth: 20),
                            alignment: Alignment.center,
                            child: Text(
                              '$quantity',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 12.5,
                                color: isSelected ? accentColor : StyleConstants.textHeading,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_rounded, size: 14),
                            padding: const EdgeInsets.all(2),
                            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                            color: (isOutOfStock || (hasStockLimit && quantity >= (item.stock ?? 0))) ? Colors.grey[400] : accentColor,
                            onPressed: (isOutOfStock || (hasStockLimit && quantity >= (item.stock ?? 0)))
                                ? null
                                : () => _updateQuantity(item.id, true),
                            tooltip: isOutOfStock ? 'Stok Habis' : 'Tambah',
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

  // --- CUSTOMER VIP HEADER SECTION ---
  Widget _buildCustomerTicketSection() {
    final int activeStamps = (_selectedCustomerLoyalty?['wash_count_active'] as num?)?.toInt() ?? 0;
    final bool hasLoyaltyBadge = _customerNameController.text.isNotEmpty && _loyaltyEnabled;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: StyleConstants.primaryGradient,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.person_rounded, size: 16, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'PELANGGAN: ',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: StyleConstants.textMuted, letterSpacing: 0.5),
                        ),
                        if (_customerNameController.text.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: StyleConstants.successColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'TERDAFTAR',
                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: StyleConstants.successColor),
                            ),
                          ),
                          if (hasLoyaltyBadge) ...[
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: _canClaimCuciGratis
                                    ? const Color(0xFFD97706).withValues(alpha: 0.15)
                                    : const Color(0xFF0284C7).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Kupon: $activeStamps/$_loyaltyThreshold',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                  color: _canClaimCuciGratis ? const Color(0xFFD97706) : const Color(0xFF0284C7),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _customerNameController.text.isEmpty
                          ? 'Pilih Data Pelanggan...'
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
              ElevatedButton(
                onPressed: _showCustomerPicker,
                style: ElevatedButton.styleFrom(
                  backgroundColor: StyleConstants.primaryColor,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                child: Text(
                  _customerNameController.text.isEmpty ? 'Pilih (+)' : 'Ganti',
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),

          // Loyalty Claim Option Card (Super clean & prominent when eligible)
          if (_customerNameController.text.isNotEmpty && _canClaimCuciGratis) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _claimFreeWash ? const Color(0xFFFFFBEB) : Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _claimFreeWash ? const Color(0xFFF59E0B) : const Color(0xFFCBD5E1),
                  width: _claimFreeWash ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.card_giftcard_rounded, size: 16, color: Color(0xFFD97706)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _cartHasWashItem
                          ? 'Pakai 1x Cuci Gratis (Tersedia Kupon $activeStamps/$_loyaltyThreshold)'
                          : 'Tersedia 1x Cuci Gratis ($activeStamps/$_loyaltyThreshold) — Tambah paket cuci untuk klaim!',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF78350F)),
                    ),
                  ),
                  if (_cartHasWashItem)
                    Checkbox(
                      value: _claimFreeWash,
                      activeColor: const Color(0xFFD97706),
                      onChanged: (val) {
                        setState(() => _claimFreeWash = val ?? false);
                      },
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // --- CART ITEMS SLIP LIST ---
  Widget _buildCartItemsList() {
    final cartItems = _allItems.where((it) => (_quantities[it.id ?? 0] ?? 0) > 0).toList();

    if (cartItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.receipt_long_rounded, size: 36, color: Colors.grey[300]),
            ),
            const SizedBox(height: 10),
            const Text(
              'Nota Pesanan Masih Kosong',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: StyleConstants.textHeading),
            ),
            const SizedBox(height: 2),
            const Text(
              'Klik kartu paket di sebelah kiri untuk menambahkan.',
              style: TextStyle(fontSize: 11, color: StyleConstants.textMuted),
            ),
          ],
        ),
      );
    }

    final firstWash = _firstWashItemInCart;
    bool freeRendered = false;

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      itemCount: cartItems.length,
      separatorBuilder: (_, __) => const Divider(height: 12, color: StyleConstants.borderLight),
      itemBuilder: (context, index) {
        final item = cartItems[index];
        final qty = _quantities[item.id ?? 0] ?? 0;
        final note = _notes[item.id];

        final m = (item.machineType ?? '').toLowerCase();
        final n = item.nama.toLowerCase();
        final isWash = m == 'cuci' || n.contains('cuci') || n.contains('wash') || n.contains('basah');

        if (_claimFreeWash && isWash && item.id == firstWash?.id && !freeRendered) {
          freeRendered = true;
          final int normalQty = qty - 1;
          final int subtotalNormal = normalQty * item.harga;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Free Line Item
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD97706),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      '1x',
                      style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 11.5),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${item.nama} (Gratis)',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: Color(0xFFD97706)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const Text(
                          '@ Rp 0 (Klaim Kupon)',
                          style: TextStyle(fontSize: 11, color: Color(0xFFD97706), fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  const Text(
                    'Rp 0',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Color(0xFFD97706)),
                  ),
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: () => setState(() => _quantities[item.id ?? 0] = 0),
                    child: const Icon(Icons.close_rounded, size: 16, color: StyleConstants.dangerColor),
                  ),
                ],
              ),

              // 2. Extra normal items if qty > 1
              if (normalQty > 0) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: StyleConstants.primaryColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${normalQty}x',
                        style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 11.5),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.nama,
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: StyleConstants.textHeading),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '@ ${formatRp(item.harga)}',
                            style: const TextStyle(fontSize: 11, color: StyleConstants.textMuted),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      formatRp(subtotalNormal),
                      style: StyleConstants.tabularNumbers(fontSize: 13, fontWeight: FontWeight.w900, color: StyleConstants.textHeading),
                    ),
                    const SizedBox(width: 22),
                  ],
                ),
              ],
            ],
          );
        }

        final subtotal = item.harga * qty;
        return Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: StyleConstants.primaryColor,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${qty}x',
                style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 11.5),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.nama,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: StyleConstants.textHeading),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '@ ${formatRp(item.harga)}',
                    style: const TextStyle(fontSize: 11, color: StyleConstants.textMuted),
                  ),
                  if (note != null && note.trim().isNotEmpty)
                    Text(
                      'Catatan: $note',
                      style: const TextStyle(fontSize: 10.5, fontStyle: FontStyle.italic, color: StyleConstants.primaryColor),
                    ),
                ],
              ),
            ),
            Text(
              formatRp(subtotal),
              style: StyleConstants.tabularNumbers(fontSize: 13, fontWeight: FontWeight.w900, color: StyleConstants.textHeading),
            ),
            const SizedBox(width: 6),
            InkWell(
              onTap: () => setState(() => _quantities[item.id ?? 0] = 0),
              child: const Icon(Icons.close_rounded, size: 16, color: StyleConstants.dangerColor),
            ),
          ],
        );
      },
    );
  }

  // --- INTEGRATED PAYMENT & HIGH-CONTRAST TOTAL SECTION ---
  Widget _buildIntegratedPaymentSection(int total, int totalItems) {
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
          // 1. High-Contrast Grand Total Banner (Slate 900 ground with bright Emerald text)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: StyleConstants.sidebarBackground, // Slate 900
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.account_balance_wallet_rounded, color: StyleConstants.accentCyan, size: 18),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'TOTAL TAGIHAN',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: StyleConstants.accentCyan, letterSpacing: 0.8),
                        ),
                        Text('$totalItems Layanan Terpilih', style: const TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8))),
                      ],
                    ),
                  ],
                ),
                Text(
                  formatRp(total),
                  style: StyleConstants.tabularNumbers(
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                    color: StyleConstants.successColor, // Emerald 500 Bright
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 2. Payment Method Selector (3-Pills)
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
                child: _methodTab(key: 'tempo', label: 'Tempo/DP', icon: Icons.schedule_rounded, color: StyleConstants.warningColor),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // --- CASH WORKBENCH ---
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
                      style: StyleConstants.tabularNumbers(fontSize: 19, fontWeight: FontWeight.w900, color: StyleConstants.textHeading),
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
                  Row(
                    children: [
                      Icon(
                        (change >= 0) ? Icons.price_check_rounded : Icons.warning_amber_rounded,
                        size: 20,
                        color: (change >= 0) ? StyleConstants.successColor : StyleConstants.warningColor,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        (change >= 0) ? 'KEMBALIAN TUNAI:' : 'UANG KURANG:',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                          color: (change >= 0) ? const Color(0xFF047857) : const Color(0xFFB45309),
                        ),
                      ),
                    ],
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
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle_rounded, size: 18),
                        SizedBox(width: 8),
                        Text('BAYAR LUNAS & CETAK STRUK (ENTER)', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.3)),
                      ],
                    ),
            ),
          ],

          // --- QRIS WORKBENCH ---
          if (_selectedPaymentTab == 'qris') ...[
            if (_qrisUrl == null) ...[
              if (_qrisError != null) ...[
                Text('Error: $_qrisError', style: const TextStyle(color: StyleConstants.dangerColor, fontSize: 11, fontWeight: FontWeight.bold)),
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

          // --- TEMPO / DP WORKBENCH ---
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
              ? (isSelected ? StyleConstants.primaryColor : StyleConstants.primaryColor.withValues(alpha: 0.1))
              : (isSelected ? StyleConstants.textHeading : Colors.white),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isExact ? StyleConstants.primaryColor : (isSelected ? StyleConstants.textHeading : StyleConstants.borderLight),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
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
