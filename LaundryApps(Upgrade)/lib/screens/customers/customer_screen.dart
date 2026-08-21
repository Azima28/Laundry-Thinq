import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../database/models/database_helper.dart';
import '../../database/models/customer_model.dart';
import '../../database/models/order_model.dart';
import '../../database/models/db_encryption_helper.dart';
import '../../services/machine_status_service.dart';
import '../../utils/style_constants.dart';

class CustomerScreen extends StatefulWidget {
  const CustomerScreen({super.key});

  @override
  State<CustomerScreen> createState() => _CustomerScreenState();
}

class _CustomerScreenState extends State<CustomerScreen> {
  final DatabaseHelper _db = DatabaseHelper.instance;
  List<Customer> _customers = [];
  List<Customer> _filteredCustomers = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();

  // Master-Detail selected customer
  Customer? _selectedCustomer;
  List<Order> _selectedCustomerOrders = [];

  final Color primaryColor = StyleConstants.primaryColor;
  final Color backgroundColor = StyleConstants.backgroundColor;

  @override
  void initState() {
    super.initState();
    _loadCustomers();
    _searchController.addListener(_filterCustomers);
  }

  @override
  void dispose() {
    _searchController.removeListener(_filterCustomers);
    _searchController.dispose();
    super.dispose();
  }

  String _formatPhoneNumber(String phone) {
    String cleaned = phone.replaceAll(RegExp(r'[\s\-()]+'), '');
    if (cleaned.isEmpty) return '';

    if (cleaned.startsWith('+62')) {
      return cleaned;
    } else if (cleaned.startsWith('62')) {
      return '+$cleaned';
    } else if (cleaned.startsWith('0')) {
      return '+62${cleaned.substring(1)}';
    } else {
      return cleaned.startsWith('+') ? cleaned : '+62$cleaned';
    }
  }

  Future<void> _loadCustomers() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    final data = await _db.getAllCustomers();
    if (mounted) {
      setState(() {
        _customers = data.map((e) => Customer.fromMap(e)).toList();
        _filteredCustomers = _customers;
        _isLoading = false;

        // Refresh detail info of selected customer if modified
        if (_selectedCustomer != null) {
          final updated = _customers.firstWhere(
            (c) => c.id == _selectedCustomer!.id,
            orElse: () => _selectedCustomer!,
          );
          _selectedCustomer = updated;
          _loadCustomerOrders(updated);
        }
      });
    }
  }

  Future<void> _loadCustomerOrders(Customer customer) async {
    try {
      final allOrders = await _db.getAllOrders();
      final filtered = allOrders.where((o) =>
        o.customerName.trim().toLowerCase() == customer.name.trim().toLowerCase() ||
        (customer.phone.isNotEmpty && o.customerPhone == customer.phone)
      ).toList();
      if (mounted) {
        setState(() {
          _selectedCustomerOrders = filtered;
        });
      }
    } catch (e) {
      debugPrint('[CustomerScreen] Gagal memuat pesanan pelanggan: $e');
    }
  }

  void _filterCustomers() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredCustomers = _customers.where((c) {
        return c.name.toLowerCase().contains(query) || c.phone.contains(query);
      }).toList();
    });
  }

  Future<void> _addOrEditCustomer([Customer? customer]) async {
    final nameController = TextEditingController(text: customer?.name);

    String initialPhone = customer?.phone ?? '';
    if (initialPhone.startsWith('+62 ')) {
      initialPhone = initialPhone.substring(4);
    } else if (initialPhone.startsWith('+62')) {
      initialPhone = initialPhone.substring(3);
    } else if (initialPhone.startsWith('0')) {
      initialPhone = initialPhone.substring(1);
    }
    final phoneController = TextEditingController(text: initialPhone);
    final addressController = TextEditingController(text: customer?.address);

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            customer == null ? 'Tambah Pelanggan Baru' : 'Edit Profil Pelanggan',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Nama Lengkap', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF334155))),
                  const SizedBox(height: 6),
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      hintText: 'Misal: Anton Rahardjo',
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      prefixIcon: const Icon(Icons.person_outline_rounded, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Nomor WhatsApp', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF334155))),
                  const SizedBox(height: 6),
                  TextField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      prefixText: '+62 ',
                      hintText: '81234567890',
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      prefixIcon: const Icon(Icons.phone_rounded, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Alamat Lengkap (Opsional)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF334155))),
                  const SizedBox(height: 6),
                  TextField(
                    controller: addressController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: 'Misal: Jl. Mawar No. 12, RT 02/05',
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      prefixIcon: const Icon(Icons.location_on_outlined, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal', style: TextStyle(color: Color(0xFF64748B))),
            ),
            ElevatedButton(
              onPressed: () {
                if (nameController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Nama pelanggan wajib diisi')));
                  return;
                }
                Navigator.pop(ctx, true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Simpan Pelanggan', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );

    if (result == true) {
      String finalPhone = phoneController.text.trim();
      if (finalPhone.isNotEmpty) {
        if (finalPhone.startsWith('0')) finalPhone = finalPhone.substring(1);
        finalPhone = '+62$finalPhone';
      }

      if (customer == null) {
        await _db.insertCustomer(Customer(
          name: nameController.text.trim(),
          phone: finalPhone,
          address: addressController.text.trim(),
          createdAt: DateTime.now(),
        ).toMap());
      } else {
        await _db.updateCustomer(customer.copyWith(
          name: nameController.text.trim(),
          phone: finalPhone,
          address: addressController.text.trim(),
        ).toMap());
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Text(customer == null ? 'Pelanggan baru berhasil ditambahkan!' : 'Profil pelanggan berhasil diperbarui!'),
              ],
            ),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
      _loadCustomers();
    }
  }

  Future<void> _deleteCustomer(Customer customer) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 24),
            SizedBox(width: 10),
            Text('Hapus Data Pelanggan?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          ],
        ),
        content: Text('Yakin ingin menghapus data ${customer.name}? Riwayat order tidak akan terhapus.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.delete_rounded, size: 18),
            label: const Text('Hapus Sekarang'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _db.deleteCustomer(customer.id!);
      setState(() {
        _selectedCustomer = null;
        _selectedCustomerOrders = [];
      });
      _loadCustomers();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pelanggan berhasil dihapus.'),
            backgroundColor: Colors.grey,
          ),
        );
      }
    }
  }

  /// Send WhatsApp message via Backend API and queue to SQLite outbox
  Future<bool> _sendWhatsAppMessage({
    required String phone,
    required String message,
  }) async {
    final cleanPhone = _formatPhoneNumber(phone).replaceAll('+', '').replaceAll(' ', '');
    if (cleanPhone.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.error_outline_rounded, color: Colors.white, size: 20),
                SizedBox(width: 10),
                Text('Nomor WhatsApp pelanggan belum diisi.'),
              ],
            ),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    }

    bool sentOnline = false;
    String statusNote = '';

    // 1. Try sending via Python Backend WA Bridge API
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
        } else {
          statusNote = data['error'] ?? 'WhatsApp belum tersambung';
        }
      } else {
        statusNote = 'Server HTTP ${resp.statusCode}';
      }
    } catch (e) {
      statusNote = 'Layanan offline';
    }

    // 2. Always persist into SQLite wa_outbox queue for tracking/reliability
    try {
      final db = await _db.database;
      await db.insert('wa_outbox', {
        'phone': DbEncryptionHelper.encrypt(cleanPhone),
        'message': DbEncryptionHelper.encrypt(message),
        'status': sentOnline ? 'sent' : 'pending',
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('[CustomerScreen] Gagal mencatat wa_outbox: $e');
    }

    if (mounted) {
      if (sentOnline) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text('Pesan WhatsApp berhasil dikirim ke +$cleanPhone!')),
              ],
            ),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.mark_chat_unread_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Pesan tersimpan di Antrean Outbox ($statusNote). Akan terkirim saat WA terhubung.'),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF0284C7),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }

    return true;
  }

  /// Open WhatsApp Studio / Custom Message Dialog
  void _openWhatsAppDialog(Customer customer, {String? defaultTemplate}) {
    if (customer.phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pelanggan ini belum memiliki nomor WhatsApp.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final latestOrder = _selectedCustomerOrders.isNotEmpty ? _selectedCustomerOrders.first : null;
    final orderNote = latestOrder != null ? ' (Nota #${latestOrder.id})' : '';

    final templateSelesai = "Halo Kak ${customer.name},\n\nPemberitahuan dari Smart Laundry:\nCucian Anda$orderNote telah *SELESAI* dan siap untuk diambil / diantarkan.\n\nTerima kasih telah mencuci di Smart Laundry!";
    final templateDiambil = "Halo Kak ${customer.name},\n\nLaundry Anda$orderNote sudah rapi, bersih, dan wangi! Silakan diambil di outlet Smart Laundry pada jam operasional kami ya Kak.\n\nTerima kasih!";
    final templateProses = "Halo Kak ${customer.name},\n\nPesanan Laundry Anda$orderNote saat ini sedang kami proses dengan cermat dan higienis. Kami akan mengabari kembali saat cucian selesai.\n\nSalam hangat, Smart Laundry.";

    final msgController = TextEditingController(text: defaultTemplate ?? templateSelesai);
    String selectedPreset = defaultTemplate != null ? 'Kustom' : 'Selesai';
    bool isSending = false;

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              actionsPadding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.chat_rounded, color: Color(0xFF10B981), size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Kirim Pesan WhatsApp',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: Color(0xFF0F172A)),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Kepada: ${customer.name} • ${customer.phone}',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 580,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 8),
                      // Preset Template Chips
                      const Text(
                        'PILIH TEMPLATE ATAU KETIK SENDIRI:',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF64748B), letterSpacing: 0.5),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildPresetChip(
                            label: 'Cucian Selesai',
                            icon: Icons.check_circle_outline_rounded,
                            isSelected: selectedPreset == 'Selesai',
                            onTap: () {
                              setDialogState(() {
                                selectedPreset = 'Selesai';
                                msgController.text = templateSelesai;
                              });
                            },
                          ),
                          _buildPresetChip(
                            label: 'Siap Diambil',
                            icon: Icons.storefront_rounded,
                            isSelected: selectedPreset == 'Diambil',
                            onTap: () {
                              setDialogState(() {
                                selectedPreset = 'Diambil';
                                msgController.text = templateDiambil;
                              });
                            },
                          ),
                          _buildPresetChip(
                            label: 'Dalam Proses',
                            icon: Icons.hourglass_top_rounded,
                            isSelected: selectedPreset == 'Proses',
                            onTap: () {
                              setDialogState(() {
                                selectedPreset = 'Proses';
                                msgController.text = templateProses;
                              });
                            },
                          ),
                          _buildPresetChip(
                            label: 'Ketik Sendiri',
                            icon: Icons.edit_note_rounded,
                            isSelected: selectedPreset == 'Kustom',
                            onTap: () {
                              setDialogState(() {
                                selectedPreset = 'Kustom';
                                msgController.text = '';
                              });
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Text Editor Field
                      const Text(
                        'Isi Pesan WhatsApp',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF334155)),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: msgController,
                        maxLines: 6,
                        style: const TextStyle(fontSize: 13.5, height: 1.45, color: Color(0xFF1E293B)),
                        decoration: InputDecoration(
                          hintText: 'Tulis pesan Anda di sini...',
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
                      const SizedBox(height: 12),

                      // Preview Box Banner
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFF64748B)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Pesan akan dikirim langsung ke nomor WhatsApp ${customer.phone} melalui modul WhatsApp Service.',
                                style: const TextStyle(fontSize: 11.5, color: Color(0xFF475569), height: 1.35),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSending ? null : () => Navigator.pop(dialogCtx),
                  child: const Text('Batal', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
                ),
                ElevatedButton.icon(
                  onPressed: isSending
                      ? null
                      : () async {
                          final text = msgController.text.trim();
                          if (text.isEmpty) {
                            ScaffoldMessenger.of(dialogCtx).showSnackBar(
                              const SnackBar(content: Text('Isi pesan tidak boleh kosong')),
                            );
                            return;
                          }

                          setDialogState(() => isSending = true);
                          Navigator.pop(dialogCtx);
                          await _sendWhatsAppMessage(phone: customer.phone, message: text);
                        },
                  icon: isSending
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.send_rounded, size: 18, color: Colors.white),
                  label: Text(
                    isSending ? 'Mengirim...' : 'Kirim WhatsApp',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildPresetChip({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF10B981).withValues(alpha: 0.15) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF10B981) : const Color(0xFFCBD5E1),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? const Color(0xFF10B981) : const Color(0xFF64748B),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? const Color(0xFF047857) : const Color(0xFF475569),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool canPop = Navigator.canPop(context);

    final Widget content = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Left Panel: Customer search & list (Master: 340px)
        Container(
          width: 340,
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(right: BorderSide(color: Color(0xFFE2E8F0))),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Search Input
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Cari nama atau no. WA...',
                    hintStyle: TextStyle(fontSize: 13, color: Colors.grey[400]),
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    contentPadding: const EdgeInsets.all(12),
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
                      borderSide: BorderSide(color: primaryColor, width: 1.5),
                    ),
                  ),
                ),
              ),
              const Divider(height: 1, color: Color(0xFFE2E8F0)),

              // Customer List
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _filteredCustomers.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.person_search_rounded, size: 42, color: Colors.grey[300]),
                                const SizedBox(height: 10),
                                Text(
                                  'Belum ada pelanggan',
                                  style: TextStyle(color: Colors.grey[500], fontSize: 13, fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            itemCount: _filteredCustomers.length,
                            padding: const EdgeInsets.all(16),
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final customer = _filteredCustomers[index];
                              final isSelected = _selectedCustomer?.id == customer.id;
                              return _buildCustomerListTile(customer, isSelected);
                            },
                          ),
              ),
              const Divider(height: 1, color: Color(0xFFE2E8F0)),

              // Bottom Button Panel
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: ElevatedButton.icon(
                  onPressed: () => _addOrEditCustomer(),
                  icon: const Icon(Icons.person_add_rounded, size: 18, color: Colors.white),
                  label: const Text('Pelanggan Baru', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ),

        // 2. Right Panel: Customer Profile Details (Detail: Expanded)
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: _selectedCustomer == null
                ? _buildEmptyDetailState()
                : _buildCustomerDetailPanel(),
          ),
        ),
      ],
    );

    if (canPop) {
      return Scaffold(
        backgroundColor: StyleConstants.backgroundColor,
        appBar: AppBar(
          title: const Text('Database & Manajemen CRM Pelanggan', style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: Colors.white,
          foregroundColor: StyleConstants.textHeading,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: StyleConstants.textHeading),
            tooltip: 'Kembali',
            onPressed: () => Navigator.pop(context),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(color: StyleConstants.borderLight, height: 1),
          ),
        ),
        body: content,
      );
    }

    return content;
  }

  Widget _buildCustomerListTile(Customer customer, bool isSelected) {
    return Container(
      decoration: BoxDecoration(
        color: isSelected ? StyleConstants.primaryColor.withValues(alpha: 0.06) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? StyleConstants.primaryColor : StyleConstants.borderLight,
          width: isSelected ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isSelected ? StyleConstants.primaryColor.withValues(alpha: 0.1) : const Color(0xFF0F172A).withValues(alpha: 0.02),
            blurRadius: isSelected ? 6 : 3,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: isSelected ? StyleConstants.primaryColor : const Color(0xFFF1F5F9),
          child: Text(
            customer.name.isNotEmpty ? customer.name[0].toUpperCase() : '?',
            style: TextStyle(
              color: isSelected ? Colors.white : StyleConstants.primaryColor,
              fontWeight: FontWeight.w900,
              fontSize: 14,
            ),
          ),
        ),
        title: Text(
          customer.name,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 13.5,
            color: isSelected ? StyleConstants.primaryColor : StyleConstants.textHeading,
          ),
        ),
        subtitle: Text(
          customer.phone.isNotEmpty ? customer.phone : 'Belum ada WhatsApp',
          style: TextStyle(
            fontSize: 11.5,
            color: customer.phone.isNotEmpty ? StyleConstants.textMuted : Colors.orange[700],
          ),
        ),
        trailing: isSelected
            ? const Icon(Icons.check_circle_rounded, color: StyleConstants.primaryColor, size: 18)
            : const Icon(Icons.chevron_right_rounded, color: StyleConstants.borderMedium, size: 18),
        onTap: () {
          setState(() {
            _selectedCustomer = customer;
          });
          _loadCustomerOrders(customer);
        },
      ),
    );
  }

  Widget _buildEmptyDetailState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: const Color(0xFF0F172A).withValues(alpha: 0.05), blurRadius: 16),
              ],
            ),
            child: const Icon(Icons.people_outline_rounded, size: 52, color: Color(0xFF94A3B8)),
          ),
          const SizedBox(height: 18),
          const Text(
            'Pilih Pelanggan untuk Melihat Detail',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Color(0xFF334155)),
          ),
          const SizedBox(height: 6),
          const Text(
            'Pilih salah satu pelanggan di daftar sebelah kiri untuk kirim WhatsApp atau ubah profil.',
            style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerDetailPanel() {
    final customer = _selectedCustomer!;
    final hasPhone = customer.phone.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.03),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row: Customer Avatar + Name & CRM Badge
          Row(
            children: [
              CircleAvatar(
                radius: 36,
                backgroundColor: primaryColor.withValues(alpha: 0.12),
                child: Text(
                  customer.name.isNotEmpty ? customer.name[0].toUpperCase() : '?',
                  style: TextStyle(color: primaryColor, fontWeight: FontWeight.w900, fontSize: 32),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          customer.name,
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: hasPhone ? const Color(0xFF10B981).withValues(alpha: 0.12) : const Color(0xFFF59E0B).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: hasPhone ? const Color(0xFF10B981).withValues(alpha: 0.3) : const Color(0xFFF59E0B).withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                hasPhone ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                                size: 12,
                                color: hasPhone ? const Color(0xFF10B981) : const Color(0xFFD97706),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                hasPhone ? 'WhatsApp Siap' : 'Nomor Belum Ada',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: hasPhone ? const Color(0xFF047857) : const Color(0xFFB45309),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Terdaftar sejak: ${_formatDate(customer.createdAt)} • Total ${_selectedCustomerOrders.length} Pesanan Tercatat',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          const SizedBox(height: 20),

          // Detail Section Rows
          Row(
            children: [
              Expanded(
                child: _buildDetailRow(
                  icon: Icons.phone_rounded,
                  title: 'Nomor WhatsApp',
                  value: hasPhone ? customer.phone : 'Belum diatur',
                  iconColor: const Color(0xFF10B981),
                  trailing: hasPhone
                      ? TextButton.icon(
                          onPressed: () => _openWhatsAppDialog(customer),
                          icon: const Icon(Icons.chat_rounded, size: 15, color: Color(0xFF10B981)),
                          label: const Text('Kirim WA', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
                        )
                      : null,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildDetailRow(
                  icon: Icons.home_rounded,
                  title: 'Alamat Rumah',
                  value: customer.address?.isNotEmpty == true ? customer.address! : '—',
                  iconColor: const Color(0xFF6366F1),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // WHATSAPP COMMUNICATION HUB (Highlight Box)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFCBD5E1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.mark_chat_read_rounded, color: Color(0xFF10B981), size: 18),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Pusat Komunikasi WhatsApp Pelanggan',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Color(0xFF0F172A)),
                    ),
                    const Spacer(),
                    const Text(
                      'Direct Delivery & Custom Chat',
                      style: TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    // Button 1: Send Template Cucian Selesai
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: hasPhone ? () => _openWhatsAppDialog(customer) : null,
                        icon: const Icon(Icons.check_circle_outline_rounded, size: 18, color: Colors.white),
                        label: const Text(
                          'Kirim Template: Cucian Selesai',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          disabledBackgroundColor: Colors.grey[300],
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          elevation: 0,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Button 2: Custom Text / Ketik Sendiri
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: hasPhone ? () => _openWhatsAppDialog(customer, defaultTemplate: '') : null,
                        icon: const Icon(Icons.edit_note_rounded, size: 18, color: Color(0xFF2563EB)),
                        label: const Text(
                          'Tulis Pesan Kustom (Ketik Sendiri)',
                          style: TextStyle(color: Color(0xFF2563EB), fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
                          backgroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Spacer(),

          // Actions Buttons Row at Bottom
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: hasPhone ? () => _openWhatsAppDialog(customer) : null,
                  icon: const Icon(Icons.chat_rounded, size: 18, color: Colors.white),
                  label: const Text('Kirim WhatsApp', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    disabledBackgroundColor: Colors.grey[300],
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _addOrEditCustomer(customer),
                  icon: const Icon(Icons.edit_rounded, size: 18, color: Colors.white),
                  label: const Text('Ubah Profil', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _deleteCustomer(customer),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.white),
                  label: const Text('Hapus Pelanggan', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String title,
    required String value,
    Color? iconColor,
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: (iconColor ?? const Color(0xFF475569)).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor ?? const Color(0xFF475569), size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                ),
              ],
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}
