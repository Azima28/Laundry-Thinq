import 'package:flutter/material.dart';
import '../../database/models/database_helper.dart';
import '../../database/models/customer_model.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

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

  final Color primaryColor = const Color(0xFF4E80EE);
  final Color backgroundColor = const Color(0xFFF8FAFC);

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

  Future<void> _syncContactsFromPhone() async {
    setState(() => _isLoading = true);
    try {
      if (await FlutterContacts.requestPermission()) {
        List<Contact> contacts = await FlutterContacts.getContacts(
          withProperties: true,
          withPhoto: false,
        );

        int newSyncedCount = 0;
        int skippedCount = 0;

        for (var contact in contacts) {
          if (contact.phones.isNotEmpty) {
            String name = contact.displayName;
            String rawPhone = contact.phones.first.number;
            String formattedPhone = _formatPhoneNumber(rawPhone);

            if (formattedPhone.isNotEmpty) {
              bool exists = await _db.checkIfCustomerPhoneExists(formattedPhone);
              if (!exists) {
                await _db.insertCustomer(Customer(
                  name: name,
                  phone: formattedPhone,
                  address: '',
                  createdAt: DateTime.now(),
                ).toMap());
                newSyncedCount++;
              } else {
                skippedCount++;
              }
            }
          }
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Sinkronisasi selesai! Berhasil mengimpor $newSyncedCount pelanggan baru. ($skippedCount sudah ada)'),
              backgroundColor: Colors.green,
            ),
          );
        }
        _loadCustomers();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Izin akses kontak ditolak. Silakan aktifkan izin kontak di pengaturan HP Anda.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal menyinkronkan kontak: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
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
        }
      });
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

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) {
        bool saveToPhoneChecked = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text(customer == null ? 'Tambah Pelanggan' : 'Edit Pelanggan', style: const TextStyle(fontWeight: FontWeight.bold)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: 'Nama', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(labelText: 'Nomor WhatsApp (Opsional)', prefixText: '+62 ', border: OutlineInputBorder(), hintText: '812...'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: addressController,
                      maxLines: 2,
                      decoration: const InputDecoration(labelText: 'Alamat (Opsional)', border: OutlineInputBorder()),
                    ),
                    if (customer == null) ...[
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        title: const Text('Simpan juga ke Kontak HP', style: TextStyle(fontSize: 14)),
                        value: saveToPhoneChecked,
                        onChanged: (val) {
                          setDialogState(() {
                            saveToPhoneChecked = val ?? false;
                          });
                        },
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ]
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
                ElevatedButton(
                  onPressed: () {
                    if (nameController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Nama wajib diisi')));
                      return;
                    }
                    Navigator.pop(ctx, {
                      'save': true,
                      'saveToPhone': saveToPhoneChecked,
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Simpan', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          }
        );
      },
    );

    if (result != null && result['save'] == true) {
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

      bool saveToPhoneSuccess = false;
      if (result['saveToPhone'] == true && finalPhone.isNotEmpty) {
        try {
          if (await FlutterContacts.requestPermission()) {
            final newContact = Contact()
              ..name = Name(first: nameController.text.trim())
              ..phones = [Phone(finalPhone)];
            await newContact.insert();
            saveToPhoneSuccess = true;
          }
        } catch (e) {
          print('Gagal menyimpan ke kontak HP: $e');
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(saveToPhoneSuccess 
                ? 'Pelanggan berhasil disimpan di aplikasi dan kontak HP!'
                : 'Pelanggan berhasil disimpan!'),
            backgroundColor: Colors.green,
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
        title: const Text('Hapus Pelanggan?', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('Yakin ingin menghapus ${customer.name}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Hapus', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _db.deleteCustomer(customer.id!);
      setState(() {
        _selectedCustomer = null;
      });
      _loadCustomers();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
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
                    hintText: 'Cari pelanggan...',
                    hintStyle: TextStyle(fontSize: 13, color: Colors.grey[400]),
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    filled: true,
                    fillColor: Colors.grey[50],
                    contentPadding: const EdgeInsets.all(12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[200]!),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[200]!),
                    ),
                  ),
                ),
              ),
              const Divider(height: 1),

              // Customer List
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _filteredCustomers.isEmpty
                        ? Center(
                            child: Text(
                              'Belum ada pelanggan',
                              style: TextStyle(color: Colors.grey[500], fontSize: 13),
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
              const Divider(height: 1),

              // Bottom Button Panel
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => _addOrEditCustomer(),
                      icon: const Icon(Icons.add_rounded, size: 18, color: Colors.white),
                      label: const Text('Pelanggan Baru', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
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
            padding: const EdgeInsets.all(28.0),
            child: _selectedCustomer == null
                ? _buildEmptyDetailState()
                : _buildCustomerDetailPanel(),
          ),
        ),
      ],
    );
  }

  Widget _buildCustomerListTile(Customer customer, bool isSelected) {
    return Container(
      decoration: BoxDecoration(
        color: isSelected ? primaryColor.withOpacity(0.04) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isSelected ? primaryColor : Colors.grey[200]!, width: isSelected ? 1.5 : 1),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: isSelected ? primaryColor : Colors.grey[100],
          child: Text(
            customer.name.isNotEmpty ? customer.name[0].toUpperCase() : '?',
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.grey[700],
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
        title: Text(
          customer.name,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13.5,
            color: isSelected ? primaryColor : const Color(0xFF0F172A),
          ),
        ),
        subtitle: Text(
          customer.phone,
          style: TextStyle(fontSize: 11, color: Colors.grey[500]),
        ),
        onTap: () {
          setState(() {
            _selectedCustomer = customer;
          });
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
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.05), blurRadius: 10)],
            ),
            child: Icon(Icons.people_outline_rounded, size: 48, color: Colors.grey[300]),
          ),
          const SizedBox(height: 16),
          const Text(
            'Pilih Pelanggan',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF475569)),
          ),
          const SizedBox(height: 6),
          const Text(
            'Pilih salah satu pelanggan di daftar kiri untuk melihat rincian.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerDetailPanel() {
    final customer = _selectedCustomer!;
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.01), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row: Customer Initials + Name
          Row(
            children: [
              CircleAvatar(
                radius: 36,
                backgroundColor: primaryColor.withOpacity(0.1),
                child: Text(
                  customer.name.isNotEmpty ? customer.name[0].toUpperCase() : '?',
                  style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold, fontSize: 32),
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customer.name,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Terdaftar sejak: ${_formatDate(customer.createdAt)}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          const Divider(height: 1),
          const SizedBox(height: 32),

          // Detail Section
          _buildDetailRow(
            icon: Icons.phone_rounded,
            title: 'Nomor WhatsApp',
            value: customer.phone,
          ),
          const SizedBox(height: 24),
          _buildDetailRow(
            icon: Icons.home_rounded,
            title: 'Alamat',
            value: customer.address?.isNotEmpty == true ? customer.address! : '—',
          ),
          const Spacer(),

          // Actions Buttons Row
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _syncContactsFromPhone,
                  icon: const Icon(Icons.sync_rounded, size: 18),
                  label: const Text('Sinkronkan Kontak'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[100],
                    foregroundColor: const Color(0xFF334155),
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
                  icon: const Icon(Icons.delete_rounded, size: 18, color: Colors.white),
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
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Icon(icon, color: const Color(0xFF475569), size: 20),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 6),
              Text(
                value,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}
