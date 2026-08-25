import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import '../../database/models/database_helper.dart';
import '../../database/models/customer_model.dart';
import '../../database/models/order_model.dart';
import '../../database/models/db_encryption_helper.dart';
import '../../services/machine_status_service.dart';
import '../../utils/style_constants.dart';
import '../../utils/currency_format.dart';
import '../../utils/contact_import_export_helper.dart';

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

    // 2. Only queue to SQLite wa_outbox if sending online failed (prevents double messages)
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
        debugPrint('[CustomerScreen] Gagal mencatat wa_outbox: $e');
      }
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

  Widget _buildTabPill({
    required String title,
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            color: isActive ? primaryColor.withValues(alpha: 0.1) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isActive ? primaryColor : const Color(0xFFE2E8F0),
              width: isActive ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: isActive ? primaryColor : const Color(0xFF64748B)),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                    color: isActive ? primaryColor : const Color(0xFF334155),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKpiBadge(String label, String count, Color textColor, Color bgColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            count,
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: textColor),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textColor),
          ),
        ],
      ),
    );
  }

  Widget _buildExportOptionTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Color(0xFF0F172A)),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), height: 1.3),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8), size: 20),
          ],
        ),
      ),
    );
  }

  /// Open Import Modal for Multi-Format Contacts (vCard, CSV, JSON)
  Future<void> _openImportDialog() async {
    String? selectedFileName;
    int currentTab = 0; // 0 = File, 1 = Paste Text
    bool isAnalyzing = false;
    bool isImporting = false;
    bool updateDuplicates = true;
    ContactAnalysisReport? report;
    final TextEditingController pasteCtrl = TextEditingController();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> analyze(String content, {String? fileName}) async {
              setModalState(() => isAnalyzing = true);
              try {
                final res = await ContactImportExportHelper.analyzeAndParseContent(content, fileName: fileName);
                setModalState(() {
                  report = res;
                  isAnalyzing = false;
                });
              } catch (e) {
                setModalState(() => isAnalyzing = false);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error menganalisis kontak: $e')));
                }
              }
            }

            Future<void> pickAndAnalyzeFile() async {
              try {
                final result = await FilePicker.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: ['vcf', 'csv', 'json', 'txt'],
                );

                if (result != null && result.files.single.path != null) {
                  final path = result.files.single.path!;
                  final name = result.files.single.name;
                  selectedFileName = name;

                  final file = File(path);
                  final content = await file.readAsString();
                  await analyze(content, fileName: name);
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal memilih file: $e')));
                }
              }
            }

            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              backgroundColor: Colors.white,
              elevation: 16,
              child: Container(
                width: 760,
                constraints: const BoxConstraints(maxHeight: 700),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 20, 20, 16),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.contacts_rounded, color: Color(0xFF059669), size: 22),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Impor Kontak & Pelanggan Multi-Format',
                                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: Color(0xFF0F172A)),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Mendukung vCard (.vcf) Android/iOS/Google, CSV Excel, & JSON (Aditif / Nambahin Data)',
                                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 20, color: Color(0xFF94A3B8)),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: Color(0xFFE2E8F0)),

                    // Source Mode Switch Tabs
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                      child: Row(
                        children: [
                          _buildTabPill(
                            title: 'Pilih File (.vcf / .csv / .json)',
                            icon: Icons.folder_open_rounded,
                            isActive: currentTab == 0,
                            onTap: () => setModalState(() => currentTab = 0),
                          ),
                          const SizedBox(width: 10),
                          _buildTabPill(
                            title: 'Tempel Teks Kontak (Paste)',
                            icon: Icons.paste_rounded,
                            isActive: currentTab == 1,
                            onTap: () => setModalState(() => currentTab = 1),
                          ),
                        ],
                      ),
                    ),

                    // Body
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (currentTab == 0) ...[
                              // File Picker Box
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: const Color(0xFFCBD5E1)),
                                ),
                                child: Column(
                                  children: [
                                    Icon(
                                      selectedFileName != null ? Icons.file_present_rounded : Icons.cloud_upload_outlined,
                                      size: 40,
                                      color: selectedFileName != null ? const Color(0xFF10B981) : const Color(0xFF64748B),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      selectedFileName ?? 'Pilih file kontak dari komputer Anda',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14,
                                        color: selectedFileName != null ? const Color(0xFF0F172A) : const Color(0xFF334155),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    const Text(
                                      'Format didukung: vCard (.vcf dari Android/Samsung/iPhone/Google), CSV (Excel/Google), JSON',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                    ),
                                    const SizedBox(height: 14),
                                    ElevatedButton.icon(
                                      onPressed: pickAndAnalyzeFile,
                                      icon: const Icon(Icons.folder_open_rounded, size: 18),
                                      label: Text(selectedFileName == null ? 'Jelajahi File...' : 'Ganti File Lain'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: primaryColor,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ] else ...[
                              // Paste Text Box
                              TextField(
                                controller: pasteCtrl,
                                maxLines: 5,
                                style: const TextStyle(fontSize: 12.5, fontFamily: 'monospace'),
                                decoration: InputDecoration(
                                  hintText: 'Tempel data kontak di sini (misal teks vCard "BEGIN:VCARD...", baris CSV "Nama, No WA", atau JSON)...',
                                  filled: true,
                                  fillColor: const Color(0xFFF8FAFC),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                                  contentPadding: const EdgeInsets.all(12),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Align(
                                alignment: Alignment.centerRight,
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    if (pasteCtrl.text.trim().isNotEmpty) {
                                      analyze(pasteCtrl.text.trim());
                                    }
                                  },
                                  icon: const Icon(Icons.search_rounded, size: 16),
                                  label: const Text('Analisis & Pratinjau Teks'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF0284C7),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                ),
                              ),
                            ],

                            if (isAnalyzing) ...[
                              const SizedBox(height: 24),
                              const Center(
                                child: Column(
                                  children: [
                                    CircularProgressIndicator(),
                                    SizedBox(height: 12),
                                    Text('Menganalisis format dan mengecek duplikasi database...', style: TextStyle(fontSize: 13, color: Color(0xFF64748B))),
                                  ],
                                ),
                              ),
                            ],

                            if (report != null && !isAnalyzing) ...[
                              const SizedBox(height: 16),
                              // Analysis Header Statistics
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF0FDF4),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: const Color(0xFF86EFAC)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 18),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Format Terdeteksi: ${report!.detectedFormat}',
                                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Color(0xFF166534)),
                                        ),
                                        const Spacer(),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: const Color(0xFF86EFAC)),
                                          ),
                                          child: Text(
                                            '${report!.totalFound} Kontak Ditemukan',
                                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: Color(0xFF15803D)),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        _buildKpiBadge('Kontak Baru', '${report!.newCount}', const Color(0xFF16A34A), const Color(0xFFDCFCE7)),
                                        const SizedBox(width: 8),
                                        _buildKpiBadge('Sudah Ada (Duplikat)', '${report!.existingCount}', const Color(0xFFD97706), const Color(0xFFFEF3C7)),
                                        if (report!.invalidCount > 0) ...[
                                          const SizedBox(width: 8),
                                          _buildKpiBadge('Dilewati/Kosong', '${report!.invalidCount}', const Color(0xFFDC2626), const Color(0xFFFEE2E2)),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),

                              // Duplicate Handling Options
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                ),
                                child: Row(
                                  children: [
                                    Checkbox(
                                      value: updateDuplicates,
                                      activeColor: primaryColor,
                                      onChanged: (v) => setModalState(() => updateDuplicates = v ?? true),
                                    ),
                                    const Expanded(
                                      child: Text(
                                        'Perbarui data kontak jika nomor sudah ada (Smart Merge - tidak menduplikat & tidak menghapus riwayat)',
                                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),

                              // Table Preview
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('PRATINJAU DAFTAR KONTAK:', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11, color: Color(0xFF64748B))),
                                  Row(
                                    children: [
                                      TextButton(
                                        onPressed: () {
                                          setModalState(() {
                                            for (final c in report!.allParsed) {
                                              c.isSelected = true;
                                            }
                                          });
                                        },
                                        child: const Text('Pilih Semua', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                      ),
                                      TextButton(
                                        onPressed: () {
                                          setModalState(() {
                                            for (final c in report!.allParsed) {
                                              c.isSelected = false;
                                            }
                                          });
                                        },
                                        child: const Text('Batal Semua', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),

                              Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                ),
                                constraints: const BoxConstraints(maxHeight: 220),
                                child: ListView.separated(
                                  shrinkWrap: true,
                                  itemCount: report!.allParsed.length,
                                  separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFE2E8F0)),
                                  itemBuilder: (ctx, i) {
                                    final item = report!.allParsed[i];
                                    return CheckboxListTile(
                                      value: item.isSelected,
                                      dense: true,
                                      activeColor: primaryColor,
                                      controlAffinity: ListTileControlAffinity.leading,
                                      title: Row(
                                        children: [
                                          Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: item.isExisting ? const Color(0xFFFEF3C7) : const Color(0xFFDCFCE7),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              item.isExisting ? 'SUDAH ADA' : 'BARU',
                                              style: TextStyle(
                                                fontSize: 9.5,
                                                fontWeight: FontWeight.w800,
                                                color: item.isExisting ? const Color(0xFFB45309) : const Color(0xFF15803D),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      subtitle: Text(
                                        '${item.phone.isNotEmpty ? item.phone : "Tanpa Nomor"}${item.address != null ? " • ${item.address}" : ""}',
                                        style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                                      ),
                                      onChanged: (v) => setModalState(() => item.isSelected = v ?? false),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),

                    // Footer Action Buttons
                    const Divider(height: 1, color: Color(0xFFE2E8F0)),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
                      child: Row(
                        children: [
                          OutlinedButton(
                            onPressed: () => Navigator.pop(ctx),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF64748B),
                              side: const BorderSide(color: Color(0xFFCBD5E1)),
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            child: const Text('Tutup', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                          const Spacer(),
                          if (report != null && report!.allParsed.any((c) => c.isSelected)) ...[
                            ElevatedButton.icon(
                              onPressed: isImporting
                                  ? null
                                  : () async {
                                      setModalState(() => isImporting = true);
                                      final summary = await ContactImportExportHelper.executeImport(
                                        contacts: report!.allParsed,
                                        updateDuplicates: updateDuplicates,
                                      );
                                      setModalState(() => isImporting = false);
                                      Navigator.pop(ctx);

                                      // Show Result Modal
                                      _showImportSummaryDialog(summary);
                                      _loadCustomers();
                                    },
                              icon: isImporting
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                  : const Icon(Icons.file_download_done_rounded, size: 18),
                              label: Text(isImporting
                                  ? 'Mengimpor...'
                                  : 'Impor (${report!.allParsed.where((c) => c.isSelected).length} Kontak)'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF059669),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Show Import Completion Summary Dialog
  void _showImportSummaryDialog(ImportResultSummary summary) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 24),
              SizedBox(width: 10),
              Text('Hasil Impor Kontak', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total ${summary.totalProcessed} kontak telah diproses ke database CRM.',
                  style: const TextStyle(fontSize: 13, color: Color(0xFF334155)),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Kontak Baru Ditambahkan:', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                          Text('${summary.newlyAdded}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Color(0xFF16A34A))),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Kontak Diperbarui (Smart Merge):', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                          Text('${summary.updatedDuplicates}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Color(0xFF0284C7))),
                        ],
                      ),
                      if (summary.skippedDuplicates > 0) ...[
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Kontak Duplikat Dilewati:', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                            Text('${summary.skippedDuplicates}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Color(0xFFD97706))),
                          ],
                        ),
                      ],
                      if (summary.invalidSkipped > 0) ...[
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Baris Kosong/Invalid Dilewati:', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                            Text('${summary.invalidSkipped}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Color(0xFFDC2626))),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Tutup & Lihat Data'),
            ),
          ],
        );
      },
    );
  }

  /// Open Export Modal for Multi-Format Contacts (vCard, CSV, JSON)
  Future<void> _openExportDialog() async {
    if (_customers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Belum ada data pelanggan untuk diekspor.')));
      return;
    }

    bool isExporting = false;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> doExport(String formatType) async {
              setModalState(() => isExporting = true);
              try {
                String content = '';
                String ext = '';
                String typeName = '';

                final dateStamp = DateFormat('yyyy-MM-dd').format(DateTime.now());

                if (formatType == 'vcf') {
                  content = ContactImportExportHelper.exportToVcf(_customers);
                  ext = 'vcf';
                  typeName = 'vCard (.vcf)';
                } else if (formatType == 'csv') {
                  content = ContactImportExportHelper.exportToCsv(_customers);
                  ext = 'csv';
                  typeName = 'Excel / CSV (.csv)';
                } else {
                  content = ContactImportExportHelper.exportToJson(_customers);
                  ext = 'json';
                  typeName = 'JSON Backup (.json)';
                }

                final fileName = 'laundry_pelanggan_$dateStamp.$ext';
                final savedFile = await ContactImportExportHelper.saveExportFile(
                  fileName: fileName,
                  content: content,
                );

                setModalState(() => isExporting = false);
                Navigator.pop(ctx);

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Berhasil mengekspor ${_customers.length} pelanggan ke $typeName di:\n${savedFile.path}',
                              style: const TextStyle(fontSize: 12.5),
                            ),
                          ),
                        ],
                      ),
                      action: SnackBarAction(
                        label: 'Buka Folder',
                        textColor: Colors.amber,
                        onPressed: () {
                          if (Platform.isWindows) {
                            Process.run('explorer.exe', ['/select,', savedFile.path]);
                          }
                        },
                      ),
                      backgroundColor: const Color(0xFF0F172A),
                      duration: const Duration(seconds: 8),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  );
                }
              } catch (e) {
                setModalState(() => isExporting = false);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal mengekspor: $e')));
                }
              }
            }

            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              backgroundColor: Colors.white,
              elevation: 16,
              child: Container(
                width: 580,
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: primaryColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(Icons.file_upload_outlined, color: primaryColor, size: 22),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Ekspor Data Pelanggan',
                                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: Color(0xFF0F172A)),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Pilih format ekspor untuk ${_customers.length} kontak pelanggan',
                                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20, color: Color(0xFF94A3B8)),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Format 1: vCard (.vcf)
                    _buildExportOptionTile(
                      title: 'vCard Kontak (.vcf)',
                      subtitle: 'Format universal HP Android, Samsung, iPhone / iCloud, & kontak WhatsApp',
                      icon: Icons.contact_phone_rounded,
                      color: const Color(0xFF10B981),
                      onTap: () => doExport('vcf'),
                    ),
                    const SizedBox(height: 12),

                    // Format 2: CSV / Excel (.csv)
                    _buildExportOptionTile(
                      title: 'Excel / Spreadsheet (.csv)',
                      subtitle: 'Format spreadsheet UTF-8 dengan BOM agar rapi saat dibuka di Microsoft Excel',
                      icon: Icons.table_view_rounded,
                      color: const Color(0xFF0284C7),
                      onTap: () => doExport('csv'),
                    ),
                    const SizedBox(height: 12),

                    // Format 3: JSON Backup (.json)
                    _buildExportOptionTile(
                      title: 'JSON Database Backup (.json)',
                      subtitle: 'Format data terstruktur untuk backup lengkap database CRM',
                      icon: Icons.data_object_rounded,
                      color: const Color(0xFF7C3AED),
                      onTap: () => doExport('json'),
                    ),
                    const SizedBox(height: 20),

                    if (isExporting) ...[
                      const Center(child: CircularProgressIndicator()),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),
              ),
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

              // Bottom Action Button Panel
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => _addOrEditCustomer(),
                        icon: const Icon(Icons.person_add_rounded, size: 18, color: Colors.white),
                        label: const Text('Pelanggan Baru', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _openImportDialog,
                            icon: const Icon(Icons.file_download_outlined, size: 16, color: Color(0xFF059669)),
                            label: const Text('Impor Kontak', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Color(0xFF059669))),
                            style: OutlinedButton.styleFrom(
                              backgroundColor: const Color(0xFFF0FDF4),
                              side: const BorderSide(color: Color(0xFF86EFAC), width: 1.3),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _openExportDialog,
                            icon: const Icon(Icons.file_upload_outlined, size: 16, color: Color(0xFF0284C7)),
                            label: const Text('Ekspor Data', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Color(0xFF0284C7))),
                            style: OutlinedButton.styleFrom(
                              backgroundColor: const Color(0xFFF0F9FF),
                              side: const BorderSide(color: Color(0xFFBAE6FD), width: 1.3),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
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
          actions: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: OutlinedButton.icon(
                onPressed: _openImportDialog,
                icon: const Icon(Icons.file_download_outlined, size: 17, color: Color(0xFF059669)),
                label: const Text('Impor Kontak', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF059669), fontSize: 12.5)),
                style: OutlinedButton.styleFrom(
                  backgroundColor: const Color(0xFFF0FDF4),
                  side: const BorderSide(color: Color(0xFF86EFAC), width: 1.3),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: OutlinedButton.icon(
                onPressed: _openExportDialog,
                icon: const Icon(Icons.file_upload_outlined, size: 17, color: Color(0xFF0284C7)),
                label: const Text('Ekspor Data', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF0284C7), fontSize: 12.5)),
                style: OutlinedButton.styleFrom(
                  backgroundColor: const Color(0xFFF0F9FF),
                  side: const BorderSide(color: Color(0xFFBAE6FD), width: 1.3),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(width: 16),
          ],
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
        title: Row(
          children: [
            Expanded(
              child: Text(
                customer.name,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                  color: isSelected ? StyleConstants.primaryColor : StyleConstants.textHeading,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (customer.washCountActive > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                decoration: BoxDecoration(
                  color: customer.washCountActive >= 5
                      ? const Color(0xFFFEF3C7)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: customer.washCountActive >= 5
                        ? const Color(0xFFFDE68A)
                        : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Text(
                  '${customer.washCountActive} Kupon',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: customer.washCountActive >= 5
                        ? const Color(0xFFB45309)
                        : const Color(0xFF64748B),
                  ),
                ),
              ),
            ],
          ],
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
          const SizedBox(height: 20),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton.icon(
                onPressed: _openImportDialog,
                icon: const Icon(Icons.file_download_outlined, size: 16),
                label: const Text('Impor Kontak dari HP / Excel'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF059669),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: _openExportDialog,
                icon: const Icon(Icons.file_upload_outlined, size: 16),
                label: const Text('Ekspor Data'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF0284C7),
                  side: const BorderSide(color: Color(0xFFBAE6FD)),
                  backgroundColor: const Color(0xFFF0F9FF),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerDetailPanel() {
    final customer = _selectedCustomer!;
    final hasPhone = customer.phone.isNotEmpty;

    return Container(
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row: Customer Avatar + Name & CRM Badge
              Row(
                children: [
                  CircleAvatar(
                    radius: 34,
                    backgroundColor: primaryColor.withValues(alpha: 0.12),
                    child: Text(
                      customer.name.isNotEmpty ? customer.name[0].toUpperCase() : '?',
                      style: TextStyle(color: primaryColor, fontWeight: FontWeight.w900, fontSize: 30),
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              customer.name,
                              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
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
                          'Terdaftar sejak: ${_formatDate(customer.createdAt)} • Total ${_selectedCustomerOrders.length} Nota Pesanan',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Divider(height: 1, color: Color(0xFFE2E8F0)),
              const SizedBox(height: 20),

              // =========================================================
              // STATISTIK LENGKAP & PROGRAM KUPON CUCI
              // =========================================================
              FutureBuilder<Map<String, dynamic>>(
                future: _db.getCustomerFullStats(customerId: customer.id, name: customer.name, phone: customer.phone),
                builder: (context, snapshot) {
                  final stats = snapshot.data ?? {};
                  final int washLifetime = (stats['wash_count_lifetime'] as num?)?.toInt() ?? customer.washCountLifetime;
                  final int activeStamps = (stats['wash_count_active'] as num?)?.toInt() ?? customer.washCountActive;
                  final int rewardsClaimed = (stats['rewards_claimed_count'] as num?)?.toInt() ?? customer.rewardsClaimedCount;
                  final int dryLifetime = (stats['dry_count_lifetime'] as num?)?.toInt() ?? customer.dryCountLifetime;
                  final int storeLifetime = (stats['store_item_count_lifetime'] as num?)?.toInt() ?? customer.storeItemCountLifetime;
                  final int ironLifetime = (stats['iron_count_lifetime'] as num?)?.toInt() ?? customer.ironCountLifetime;
                  final int spentLifetime = (stats['total_spent_lifetime'] as num?)?.toInt() ?? customer.totalSpentLifetime;
                  final int threshold = (stats['loyalty_threshold'] as num?)?.toInt() ?? 5;
                  final bool canClaim = stats['can_claim_reward'] == true;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 1. Loyalty Kupon Cuci Highlight Card (Gold)
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: canClaim ? const Color(0xFFFFFBEB) : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: canClaim ? const Color(0xFFF59E0B) : const Color(0xFFE2E8F0),
                            width: canClaim ? 1.5 : 1,
                          ),
                          boxShadow: canClaim
                              ? [
                                  BoxShadow(
                                    color: const Color(0xFFD97706).withValues(alpha: 0.1),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : null,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFD97706).withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.confirmation_number_rounded, color: Color(0xFFD97706), size: 18),
                                ),
                                const SizedBox(width: 10),
                                const Text(
                                  'Kupon Cuci Pelanggan',
                                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Color(0xFF0F172A)),
                                ),
                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: canClaim ? const Color(0xFFD97706) : const Color(0xFFE2E8F0),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '$activeStamps / $threshold Kupon',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 12,
                                      color: canClaim ? Colors.white : const Color(0xFF334155),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),

                            // Stamp Progress Row
                            Row(
                              children: List.generate(threshold, (index) {
                                final isFilled = index < activeStamps;
                                return Expanded(
                                  child: Container(
                                    margin: EdgeInsets.only(right: index == threshold - 1 ? 0 : 6),
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: isFilled ? const Color(0xFFD97706) : Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: isFilled ? const Color(0xFFD97706) : const Color(0xFFCBD5E1),
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Center(
                                      child: isFilled
                                          ? const Icon(Icons.check_rounded, color: Colors.white, size: 16)
                                          : Text(
                                              '${index + 1}',
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF94A3B8)),
                                            ),
                                    ),
                                  ),
                                );
                              }),
                            ),
                            const SizedBox(height: 12),

                            // Subtitle info
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  canClaim
                                      ? '🎁 Kupon siap digunakan: Tersedia 1x Cuci Gratis di kasir POS!'
                                      : 'Kurang ${threshold - activeStamps}x cuci lagi untuk dapat 1x gratis',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: canClaim ? const Color(0xFFB45309) : const Color(0xFF64748B),
                                  ),
                                ),
                                Text(
                                  'Pernah Cuci Gratis: $rewardsClaimed kali',
                                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 2. Multi-Stat KPI Grid (Cuci, Kering, Sabun, Setrika, Total Belanja)
                      Row(
                        children: [
                          Expanded(
                            child: _buildCustomerStatTile(
                              title: 'Total Cuci',
                              value: '$washLifetime kali',
                              icon: Icons.local_laundry_service_rounded,
                              color: const Color(0xFF2563EB),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildCustomerStatTile(
                              title: 'Total Kering',
                              value: '$dryLifetime kali',
                              icon: Icons.wb_sunny_rounded,
                              color: const Color(0xFFEA580C),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildCustomerStatTile(
                              title: 'Beli Sabun/Item',
                              value: '$storeLifetime item',
                              icon: Icons.shopping_bag_rounded,
                              color: const Color(0xFF10B981),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _buildCustomerStatTile(
                              title: 'Total Setrika',
                              value: '$ironLifetime kg',
                              icon: Icons.iron_rounded,
                              color: const Color(0xFF7C3AED),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: _buildCustomerStatTile(
                              title: 'Total Belanja (Kas Masuk)',
                              value: formatRp(spentLifetime),
                              icon: Icons.account_balance_wallet_rounded,
                              color: const Color(0xFF0F172A),
                              isBold: true,
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 20),
              const Divider(height: 1, color: Color(0xFFE2E8F0)),
              const SizedBox(height: 20),

              // Detail Section Rows (Nomor WhatsApp & Alamat)
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
              const SizedBox(height: 20),

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
                        TextButton.icon(
                          onPressed: () async {
                            final res = await MachineStatusService.instance.openWhatsAppWebGUI();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(res['message'] ?? 'Membuka jendela WhatsApp Web...'),
                                  backgroundColor: res['success'] == true ? const Color(0xFF10B981) : Colors.red,
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.open_in_new_rounded, size: 14, color: Color(0xFF047857)),
                          label: const Text('Buka WhatsApp Web', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF047857))),
                          style: TextButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981).withValues(alpha: 0.1),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
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
              const SizedBox(height: 24),

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
        ),
      ),
    );
  }

  Widget _buildCustomerStatTile({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    bool isBold = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: isBold ? 14 : 13,
                    fontWeight: FontWeight.w900,
                    color: isBold ? color : const Color(0xFF0F172A),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
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
