import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../database/models/database_helper.dart';
import '../../database/models/order_model.dart';
import '../../database/models/db_encryption_helper.dart';
import '../../services/machine_status_service.dart';
import '../../transactions/order_repository.dart';
import '../../utils/style_constants.dart';

class HubungiPelangganScreen extends StatefulWidget {
  const HubungiPelangganScreen({Key? key}) : super(key: key);

  @override
  State<HubungiPelangganScreen> createState() => _HubungiPelangganScreenState();
}

class _HubungiPelangganScreenState extends State<HubungiPelangganScreen> {
  final OrderRepository _orderRepo = OrderRepository();
  final DatabaseHelper _db = DatabaseHelper.instance;
  List<Order> _readyOrders = [];
  bool _isLoading = true;
  Timer? _refreshTimer;
  String _selectedFilter = 'Semua'; // 'Semua', 'Cucian', 'Gosok'
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  final Color primaryColor = StyleConstants.primaryColor;
  final Color backgroundColor = StyleConstants.backgroundColor;

  @override
  void initState() {
    super.initState();
    _loadReadyOrders();
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) => _loadReadyOrders());
    _searchCtrl.addListener(() {
      setState(() {
        _searchQuery = _searchCtrl.text.toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadReadyOrders() async {
    if (!mounted) return;

    try {
      final allOrders = await _orderRepo.getAllOrders();
      // Filter out completed, cancelled, and bypass clear orders
      final activeOrders = allOrders.where((o) {
        final st = o.status.toLowerCase();
        return st != 'completed' && st != 'cancelled' && st != 'bypass clear';
      }).toList();

      List<Order> readyOrders = [];
      final db = await _db.database;

      for (var order in activeOrders) {
        int totalWashingDryingQty = 0;
        bool hasGosok = false;

        for (var item in order.items) {
          String name = item.itemName.toLowerCase();
          bool hasCuci = item.machineType == 'cuci' || name.contains('cuci') || name.contains('wash');
          bool hasPengering = item.machineType == 'pengering' || name.contains('kering') || name.contains('pengering') || name.contains('dry');
          
          if (hasCuci && hasPengering) {
            totalWashingDryingQty += (item.quantity * 2);
          } else if (hasCuci || hasPengering) {
            totalWashingDryingQty += item.quantity;
          }
          
          if (name.contains('gosok')) {
            hasGosok = true;
          }
        }

        // Gosok-only order
        if (totalWashingDryingQty == 0 && hasGosok) {
          if (order.customerPhone == null || order.customerPhone!.isEmpty) {
            final customerRes = await db.query('customers', where: 'name = ?', whereArgs: [order.customerName], orderBy: 'id DESC', limit: 1);
            if (customerRes.isNotEmpty) {
              final phone = customerRes.first['phone'] as String?;
              if (phone != null && phone.isNotEmpty) {
                order = order.copyWith(customerPhone: phone);
              }
            }
          }
          readyOrders.add(order);
          continue;
        }

        // Washing/Drying orders check machine history
        final usageResult = await db.rawQuery(
          "SELECT COUNT(*) as cnt FROM machine_usage_history WHERE order_id = ? AND (status = 'Success' OR status = 'Bypass Clear')",
          [order.id],
        );
        int usedQty = usageResult.isNotEmpty ? (usageResult[0]['cnt'] as int) : 0;

        if (usedQty >= totalWashingDryingQty) {
          if (order.customerPhone == null || order.customerPhone!.isEmpty) {
            final customerRes = await db.query('customers', where: 'name = ?', whereArgs: [order.customerName], orderBy: 'id DESC', limit: 1);
            if (customerRes.isNotEmpty) {
              final phone = customerRes.first['phone'] as String?;
              if (phone != null && phone.isNotEmpty) {
                order = order.copyWith(customerPhone: phone);
              }
            }
          }
          readyOrders.add(order);
        }
      }

      if (mounted) {
        setState(() {
          _readyOrders = readyOrders;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[HubungiPelanggan] Gagal memuat pesanan: $e');
    }
  }

  bool _isGosokOrder(Order order) {
    int totalWashingDryingQty = 0;
    for (var item in order.items) {
      String name = item.itemName.toLowerCase();
      bool hasCuci = item.machineType == 'cuci' || name.contains('cuci') || name.contains('wash');
      bool hasPengering = item.machineType == 'pengering' || name.contains('kering') || name.contains('pengering') || name.contains('dry');
      if (hasCuci || hasPengering) {
        totalWashingDryingQty += item.quantity;
      }
    }
    return totalWashingDryingQty == 0;
  }

  Future<void> _editPhoneNumber(Order order) async {
    final controller = TextEditingController(text: order.customerPhone);
    final formKey = GlobalKey<FormState>();

    return showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Edit Nomor Telepon'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Nomor WhatsApp Pelanggan',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.phone_rounded),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) return 'Nomor HP tidak boleh kosong';
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Batal', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: primaryColor),
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                final phone = controller.text.trim();
                final db = await _db.database;

                await db.update(
                  'orders',
                  {'customer_phone': phone},
                  where: 'id = ?',
                  whereArgs: [order.id],
                );

                await db.update(
                  'customers',
                  {'phone': phone},
                  where: 'name = ?',
                  whereArgs: [order.customerName],
                );

                if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                _loadReadyOrders();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Nomor WhatsApp berhasil diubah.'), backgroundColor: Colors.green),
                  );
                }
              }
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  Future<bool> _sendWhatsAppMessageOnline({
    required String phone,
    required String message,
  }) async {
    String cleanPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanPhone.startsWith('0')) {
      cleanPhone = '62${cleanPhone.substring(1)}';
    } else if (!cleanPhone.startsWith('62')) {
      cleanPhone = '62$cleanPhone';
    }

    bool sentOnline = false;

    try {
      final base = MachineStatusService.instance.dashboardUrl;
      final cleanBase = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
      final uri = Uri.parse('$cleanBase/api/wa/send-custom');

      final resp = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'phone': cleanPhone,
          'message': message,
        }),
      ).timeout(const Duration(seconds: 8));

      if (resp.statusCode == 200) {
        final data = json.decode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
        if (data['success'] == true) {
          sentOnline = true;
        }
      }
    } catch (_) {}

    if (!sentOnline) {
      try {
        final db = await _db.database;
        await db.insert('wa_outbox', {
          'phone': DbEncryptionHelper.encrypt(cleanPhone),
          'message': DbEncryptionHelper.encrypt(message),
          'status': 'pending',
          'created_at': DateTime.now().toIso8601String(),
        });
      } catch (e) {
        debugPrint('[HubungiPelanggan] Gagal menyimpan ke wa_outbox: $e');
      }
    }

    return sentOnline;
  }

  Future<void> _notifyCustomer(Order order) async {
    if (order.customerPhone == null || order.customerPhone!.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Nomor WhatsApp pelanggan belum diatur. Silakan klik ikon pensil untuk mengisi nomor.'),
          backgroundColor: Colors.orange,
          action: SnackBarAction(
            label: 'Isi Nomor',
            textColor: Colors.white,
            onPressed: () => _editPhoneNumber(order),
          ),
        ),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final bizName = prefs.getString('biz_name')?.trim();
    final displayBizName = (bizName != null && bizName.isNotEmpty) ? bizName : 'Smart Laundry';

    final defaultMessage = "Halo Kak ${order.customerName},\n\nPesanan Laundry Anda dengan Nota #${order.id} telah *SELESAI* dan siap untuk diambil/diantarkan.\n\nTerima kasih banyak telah mencuci di $displayBizName!";
    final msgCtrl = TextEditingController(text: defaultMessage);
    bool isProcessing = false;

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (_, setModalState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          actionsPadding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.mark_chat_read_rounded, color: Color(0xFF10B981), size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Kirim Notifikasi Nota #${order.id}',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: Color(0xFF0F172A)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Penerima: ${order.customerName} • ${order.customerPhone}',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 540,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Order Items Mini Summary
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.receipt_long_rounded, size: 18, color: Color(0xFF64748B)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Item: ${order.items.map((it) => "${it.quantity}x ${it.itemName}").join(", ")}',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  const Text(
                    'Isi Pesan WhatsApp',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF334155)),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: msgCtrl,
                    maxLines: 4,
                    style: const TextStyle(fontSize: 13, height: 1.4, color: Color(0xFF1E293B)),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF10B981), width: 1.5),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isProcessing ? null : () => Navigator.pop(dialogCtx),
              child: const Text('Batal', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
            ),
            // Action 1: Kirim WA Saja
            OutlinedButton.icon(
              onPressed: isProcessing
                  ? null
                  : () async {
                      setModalState(() => isProcessing = true);
                      final sent = await _sendWhatsAppMessageOnline(
                        phone: order.customerPhone!,
                        message: msgCtrl.text.trim(),
                      );
                      if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(sent
                                ? 'Pesan WhatsApp berhasil dikirim ke ${order.customerName}!'
                                : 'Pesan tersimpan di antrean WhatsApp Outbox.'),
                            backgroundColor: sent ? const Color(0xFF10B981) : const Color(0xFF0284C7),
                          ),
                        );
                      }
                    },
              icon: const Icon(Icons.send_rounded, size: 16),
              label: const Text('Kirim WA Saja', style: TextStyle(fontWeight: FontWeight.bold)),
              style: OutlinedButton.styleFrom(
                foregroundColor: primaryColor,
                side: BorderSide(color: primaryColor, width: 1.5),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            // Action 2: Kirim WA & Selesai Sekaligus
            ElevatedButton.icon(
              onPressed: isProcessing
                  ? null
                  : () async {
                      setModalState(() => isProcessing = true);
                      await _sendWhatsAppMessageOnline(
                        phone: order.customerPhone!,
                        message: msgCtrl.text.trim(),
                      );
                      await _orderRepo.updateOrderStatus(order.id!, 'completed');
                      if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                      _loadReadyOrders();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Pesan WA terkirim & Nota #${order.id} (${order.customerName}) selesai!'),
                            backgroundColor: const Color(0xFF10B981),
                          ),
                        );
                      }
                    },
              icon: const Icon(Icons.done_all_rounded, size: 18, color: Colors.white),
              label: const Text('Kirim WA & Selesai', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _markOrderCompleted(Order order) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.check_circle_outline_rounded, color: Color(0xFF2563EB), size: 24),
            const SizedBox(width: 10),
            Text('Selesaikan Nota #${order.id}?', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          ],
        ),
        content: Text('Tandai pesanan ${order.customerName} sebagai Selesai? Nota ini akan diarsipkan dari daftar antrean siap ambil.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.done_rounded, size: 16, color: Colors.white),
            label: const Text('Ya, Selesaikan', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(backgroundColor: primaryColor),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await _orderRepo.updateOrderStatus(order.id!, 'completed');
      if (success) {
        _loadReadyOrders();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Nota #${order.id} (${order.customerName}) berhasil diselesaikan!'), backgroundColor: Colors.green),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Apply filters and search
    final filtered = _readyOrders.where((order) {
      final matchesSearch = order.customerName.toLowerCase().contains(_searchQuery) ||
          order.items.any((it) => it.itemName.toLowerCase().contains(_searchQuery));
      
      if (!matchesSearch) return false;

      final isGosok = _isGosokOrder(order);
      if (_selectedFilter == 'Cucian' && isGosok) return false;
      if (_selectedFilter == 'Gosok' && !isGosok) return false;
      
      return true;
    }).toList();

    final bool canPop = Navigator.canPop(context);

    final Widget content = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Left Panel: Filters & Statistics (340px)
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
                    'Filter Pesanan Siap',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF475569), letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 16),
                  
                  _buildFilterButton('Semua', Icons.all_inbox_rounded),
                  const SizedBox(height: 8),
                  _buildFilterButton('Cucian', Icons.local_laundry_service_rounded),
                  const SizedBox(height: 8),
                  _buildFilterButton('Gosok', Icons.iron_rounded),
                  
                  const SizedBox(height: 28),
                  const Divider(color: Color(0xFFF1F5F9)),
                  const SizedBox(height: 24),
                  
                  // Summary/Stats
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFA7F3D0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('SIAP DIAMBIL', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF047857), letterSpacing: 0.8)),
                        const SizedBox(height: 8),
                        Text(
                          '${_readyOrders.length} Nota',
                          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Color(0xFF065F46)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 2. Right Panel: List of ready orders (Expanded)
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
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    )
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _searchCtrl,
                            style: const TextStyle(fontSize: 14),
                            decoration: InputDecoration(
                              hintText: 'Cari nama pelanggan atau item laundry...',
                              hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                              prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF64748B), size: 20),
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        IconButton(
                          icon: const Icon(Icons.refresh_rounded, color: Color(0xFF64748B)),
                          onPressed: _loadReadyOrders,
                          tooltip: 'Refresh Data',
                          style: IconButton.styleFrom(
                            backgroundColor: const Color(0xFFF1F5F9),
                            hoverColor: const Color(0xFFE2E8F0),
                            padding: const EdgeInsets.all(12),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Divider(color: Color(0xFFF1F5F9)),
                    const SizedBox(height: 20),

                    Expanded(
                      child: _isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : filtered.isEmpty
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
                                        child: Icon(Icons.check_circle_outline_rounded, size: 48, color: Colors.grey[300]),
                                      ),
                                      const SizedBox(height: 16),
                                      const Text('Semua pesanan selesai dihubungi!', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: filtered.length,
                                  itemBuilder: (context, index) {
                                    final order = filtered[index];
                                    final isGosok = _isGosokOrder(order);

                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 12),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(color: const Color(0xFFE2E8F0)),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.01),
                                            blurRadius: 10,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.all(20),
                                        child: Row(
                                          children: [
                                            // Left portion: user & status info
                                            Expanded(
                                              flex: 3,
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Text(
                                                        order.customerName,
                                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0F172A)),
                                                      ),
                                                      const SizedBox(width: 12),
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                        decoration: BoxDecoration(
                                                          color: isGosok ? const Color(0xFFFFF7ED) : const Color(0xFFECFDF5),
                                                          borderRadius: BorderRadius.circular(20),
                                                        ),
                                                        child: Text(
                                                          isGosok ? 'Setrika' : 'Cucian',
                                                          style: TextStyle(
                                                            fontSize: 9.5,
                                                            fontWeight: FontWeight.bold,
                                                            color: isGosok ? const Color(0xFFC2410C) : const Color(0xFF047857),
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 8),
                                                  Row(
                                                    children: [
                                                      const Icon(Icons.phone_rounded, size: 14, color: Color(0xFF64748B)),
                                                      const SizedBox(width: 8),
                                                      Text(
                                                        (order.customerPhone == null || order.customerPhone!.trim().isEmpty)
                                                            ? 'Nomor tidak tersedia'
                                                            : order.customerPhone!,
                                                        style: TextStyle(
                                                          fontSize: 13,
                                                          fontWeight: FontWeight.w500,
                                                          color: (order.customerPhone == null || order.customerPhone!.trim().isEmpty) ? Colors.red : const Color(0xFF475569),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 10),
                                                      IconButton(
                                                        icon: Icon(Icons.edit_rounded, size: 13, color: primaryColor),
                                                        onPressed: () => _editPhoneNumber(order),
                                                        constraints: const BoxConstraints(),
                                                        style: IconButton.styleFrom(
                                                          backgroundColor: const Color(0xFFF1F5F9),
                                                          hoverColor: const Color(0xFFE2E8F0),
                                                          padding: const EdgeInsets.all(6),
                                                        ),
                                                        tooltip: 'Ubah Nomor',
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),

                                            // Center portion: clothes item list
                                            Expanded(
                                              flex: 3,
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: order.items
                                                    .map((it) => Padding(
                                                          padding: const EdgeInsets.symmetric(vertical: 2.0),
                                                          child: Text(
                                                            '• ${it.quantity}x ${it.itemName}',
                                                            style: const TextStyle(fontSize: 12.5, color: Color(0xFF475569), fontWeight: FontWeight.w500),
                                                          ),
                                                        ))
                                                    .toList(),
                                              ),
                                            ),

                                            // Right portion: actions
                                            Row(
                                              children: [
                                                ElevatedButton.icon(
                                                  onPressed: () => _notifyCustomer(order),
                                                  icon: const Icon(Icons.message_rounded, size: 16, color: Colors.white),
                                                  label: const Text('Kirim WA', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor: const Color(0xFF10B981),
                                                    foregroundColor: Colors.white,
                                                    elevation: 0,
                                                    shadowColor: Colors.transparent,
                                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                                                  ),
                                                ),
                                                const SizedBox(width: 10),
                                                ElevatedButton.icon(
                                                  onPressed: () => _markOrderCompleted(order),
                                                  icon: const Icon(Icons.done_all_rounded, size: 16, color: Colors.white),
                                                  label: const Text('Selesai', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor: primaryColor,
                                                    foregroundColor: Colors.white,
                                                    elevation: 0,
                                                    shadowColor: Colors.transparent,
                                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                                                  ),
                                                ),
                                              ],
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
            ),
          ),
        ],
      );

    if (canPop) {
      return Scaffold(
        backgroundColor: backgroundColor,
        appBar: AppBar(
          title: const Text('Hubungi Pelanggan & Broadcast WhatsApp', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF0F172A),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: StyleConstants.textHeading),
            tooltip: 'Kembali',
            onPressed: () => Navigator.pop(context),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(color: const Color(0xFFE2E8F0), height: 1),
          ),
        ),
        body: content,
      );
    }

    return content;
  }

  Widget _buildFilterButton(String label, IconData icon) {
    final isSelected = _selectedFilter == label;
    return Container(
      decoration: BoxDecoration(
        color: isSelected ? primaryColor : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? primaryColor : const Color(0xFFE2E8F0),
        ),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: primaryColor.withValues(alpha: 0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                )
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => _selectedFilter = label),
          borderRadius: BorderRadius.circular(12),
          hoverColor: isSelected
              ? Colors.white.withValues(alpha: 0.1)
              : const Color(0xFFF8FAFC),
          focusColor: isSelected
              ? Colors.white.withValues(alpha: 0.1)
              : const Color(0xFFF8FAFC),
          splashColor: isSelected
              ? Colors.white.withValues(alpha: 0.15)
              : primaryColor.withValues(alpha: 0.1),
          highlightColor: isSelected
              ? Colors.white.withValues(alpha: 0.05)
              : primaryColor.withValues(alpha: 0.05),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            child: Row(
              children: [
                Icon(icon, color: isSelected ? Colors.white : const Color(0xFF64748B), size: 18),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                    color: isSelected ? Colors.white : const Color(0xFF334155),
                    fontSize: 13.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
