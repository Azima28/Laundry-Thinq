import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../database/models/database_helper.dart';
import '../../database/models/customer_model.dart';
import '../../database/models/machine_model.dart';
import '../../services/printer_service.dart';
import '../../utils/style_constants.dart';
import '../../utils/globals.dart';

class MachineLabelDialog extends StatefulWidget {
  final String? initialMachineName;
  final String? initialCustomerName;
  final String? initialServiceType;
  final String? initialNote;

  const MachineLabelDialog({
    Key? key,
    this.initialMachineName,
    this.initialCustomerName,
    this.initialServiceType,
    this.initialNote,
  }) : super(key: key);

  static Future<bool?> show(
    BuildContext context, {
    String? machineName,
    String? customerName,
    String? serviceType,
    String? note,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => MachineLabelDialog(
        initialMachineName: machineName,
        initialCustomerName: customerName,
        initialServiceType: serviceType,
        initialNote: note,
      ),
    );
  }

  @override
  State<MachineLabelDialog> createState() => _MachineLabelDialogState();
}

class _MachineLabelDialogState extends State<MachineLabelDialog> {
  final TextEditingController _machineNameCtrl = TextEditingController();
  final TextEditingController _customerNameCtrl = TextEditingController();
  final TextEditingController _customServiceCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();

  final List<String> _serviceOptions = [
    'Cuci Kering',
    'Cuci Saja',
    'Cuci Kering Lipat',
    'Kering Saja',
    'Setrika',
    'Lainnya (Ketik Custom)',
  ];

  String _selectedService = 'Cuci Kering';
  List<MachineModel> _allMachines = [];
  List<Customer> _allCustomers = [];
  bool _isPrinting = false;

  @override
  void initState() {
    super.initState();
    _machineNameCtrl.text = widget.initialMachineName ?? 'Mesin Cuci 1';
    _customerNameCtrl.text = widget.initialCustomerName ?? '';
    _noteCtrl.text = widget.initialNote ?? '';

    final initialType = widget.initialServiceType ?? 'Cuci Kering';
    if (_serviceOptions.contains(initialType)) {
      _selectedService = initialType;
    } else {
      _selectedService = 'Lainnya (Ketik Custom)';
      _customServiceCtrl.text = initialType;
    }

    _loadMachinesAndCustomers();
  }

  @override
  void dispose() {
    _machineNameCtrl.dispose();
    _customerNameCtrl.dispose();
    _customServiceCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMachinesAndCustomers() async {
    try {
      final db = DatabaseHelper.instance;
      final mList = await db.getAllMachines();
      final rawCList = await db.getAllCustomers();
      final cList = rawCList.map((m) => Customer.fromMap(m)).toList();
      if (mounted) {
        setState(() {
          _allMachines = mList;
          _allCustomers = cList;
        });
      }
    } catch (_) {}
  }

  String get _effectiveServiceType {
    if (_selectedService == 'Lainnya (Ketik Custom)') {
      final c = _customServiceCtrl.text.trim();
      return c.isNotEmpty ? c : 'Cuci Kering';
    }
    return _selectedService;
  }

  Future<void> _handlePrint() async {
    final machine = _machineNameCtrl.text.trim();
    final customer = _customerNameCtrl.text.trim();
    final service = _effectiveServiceType;
    final note = _noteCtrl.text.trim();

    if (customer.isEmpty) {
      Globals.showWarningSnackBar('Harap masukkan nama pelanggan!');
      return;
    }

    setState(() => _isPrinting = true);
    try {
      final success = await PrinterService.printMachineLabel(
        machineName: machine.isNotEmpty ? machine : 'Mesin Cuci 1',
        customerName: customer,
        serviceType: service,
        date: DateTime.now(),
        note: note.isNotEmpty ? note : null,
      );

      if (success) {
        Globals.showSuccessSnackBar('Label untuk $customer ($machine) berhasil dicetak!');
        if (mounted) Navigator.pop(context, true);
      } else {
        Globals.showErrorSnackBar('Gagal mencetak label. Periksa koneksi printer thermal di Pengaturan.');
      }
    } catch (e) {
      Globals.showErrorSnackBar('Error mencetak label: $e');
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dateStr = DateFormat('dd MMM').format(now);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      elevation: 20,
      backgroundColor: Colors.white,
      child: Container(
        width: 560,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Header Ribbon
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: StyleConstants.primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.label_important_rounded, color: StyleConstants.primaryColor, size: 22),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Cetak Label Mesin & Cucian',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: StyleConstants.textHeading,
                        ),
                      ),
                      Text(
                        'Format tiket tempel pakaian: Mesin, Nama Pelanggan, Layanan & Tanggal',
                        style: TextStyle(fontSize: 11.5, color: StyleConstants.textMuted),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: StyleConstants.textMuted),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1, color: StyleConstants.borderLight),
            const SizedBox(height: 18),

            // 2. Main Content Split: Form on Left, Live Preview on Right
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Form Inputs (Flex 55)
                Expanded(
                  flex: 55,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Dropdown & Input Mesin
                      const Text(
                        'PILIH / NAMA MESIN:',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: StyleConstants.textHeading, letterSpacing: 0.4),
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 38,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: StyleConstants.borderLight),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              child: TextField(
                                controller: _machineNameCtrl,
                                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(vertical: 9),
                                  hintText: 'Misal: Mesin Cuci 5',
                                ),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                          ),
                          if (_allMachines.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.arrow_drop_down_circle_outlined, size: 20, color: StyleConstants.primaryColor),
                              tooltip: 'Pilih dari daftar mesin',
                              onSelected: (val) {
                                setState(() => _machineNameCtrl.text = val);
                              },
                              itemBuilder: (ctx) => _allMachines.map((m) {
                                final isWasher = m.machineType == 'cuci';
                                return PopupMenuItem(
                                  value: m.name,
                                  child: Row(
                                    children: [
                                      Icon(
                                        isWasher ? Icons.local_laundry_service_rounded : Icons.wb_sunny_rounded,
                                        size: 16,
                                        color: isWasher ? StyleConstants.primaryColor : const Color(0xFFD97706),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(m.name, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Nama Pelanggan Input
                      const Text(
                        'NAMA PELANGGAN:',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: StyleConstants.textHeading, letterSpacing: 0.4),
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 38,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: StyleConstants.borderLight),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              child: TextField(
                                controller: _customerNameCtrl,
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Color(0xFF1E3A8A)),
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(vertical: 9),
                                  hintText: 'Nama pelanggan...',
                                ),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                          ),
                          if (_allCustomers.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.person_search_rounded, size: 20, color: StyleConstants.primaryColor),
                              tooltip: 'Pilih dari pelanggan terdaftar',
                              onSelected: (val) {
                                setState(() => _customerNameCtrl.text = val);
                              },
                              itemBuilder: (ctx) => _allCustomers.take(20).map((c) {
                                return PopupMenuItem(
                                  value: c.name,
                                  child: Text(c.name, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                                );
                              }).toList(),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Jenis Layanan Dropdown
                      const Text(
                        'JENIS LAYANAN:',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: StyleConstants.textHeading, letterSpacing: 0.4),
                      ),
                      const SizedBox(height: 5),
                      Container(
                        height: 38,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: StyleConstants.borderLight),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedService,
                            isExpanded: true,
                            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                            items: _serviceOptions.map((opt) {
                              return DropdownMenuItem(
                                value: opt,
                                child: Text(opt),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) setState(() => _selectedService = val);
                            },
                          ),
                        ),
                      ),

                      if (_selectedService == 'Lainnya (Ketik Custom)') ...[
                        const SizedBox(height: 8),
                        Container(
                          height: 38,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: StyleConstants.primaryColor),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: TextField(
                            controller: _customServiceCtrl,
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(vertical: 9),
                              hintText: 'Tulis jenis layanan custom...',
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),

                      // Catatan (Opsional) Input
                      const Text(
                        'CATATAN (OPSIONAL):',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: StyleConstants.textHeading, letterSpacing: 0.4),
                      ),
                      const SizedBox(height: 5),
                      Container(
                        height: 38,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: StyleConstants.borderLight),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: TextField(
                          controller: _noteCtrl,
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(vertical: 9),
                            hintText: 'Misal: Jangan dicampur / Pisah luntur...',
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 20),

                // Live Visual Label Preview Box (Flex 45)
                Expanded(
                  flex: 45,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'PREVIEW HASIL CETAK:',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: StyleConstants.textMuted, letterSpacing: 0.5),
                      ),
                      const SizedBox(height: 8),
                      // Frame Container representing thermal paper ticket
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.black, width: 3), // Bold black outline
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Top Left Machine Name
                            Text(
                              _machineNameCtrl.text.isNotEmpty ? _machineNameCtrl.text : 'Mesin Cuci 1',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                                color: Colors.black,
                              ),
                            ),
                            const SizedBox(height: 18),

                            // Center Customer Name (LARGE ALL CAPS)
                            Center(
                              child: Text(
                                _customerNameCtrl.text.isNotEmpty ? _customerNameCtrl.text.toUpperCase() : 'NAMA PELANGGAN',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 20,
                                  color: _customerNameCtrl.text.isNotEmpty ? Colors.black : Colors.grey[400],
                                  letterSpacing: 0.8,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(height: 4),

                            // Center Solid Underline Bar
                            Center(
                              child: Container(
                                width: 140,
                                height: 3.5,
                                color: Colors.black,
                              ),
                            ),
                            const SizedBox(height: 8),

                            // Center Service Type
                            Center(
                              child: Text(
                                _effectiveServiceType,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                  color: Colors.black,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            if (_noteCtrl.text.trim().isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Center(
                                child: Text(
                                  'Catatan: ${_noteCtrl.text.trim()}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 11.5,
                                    fontStyle: FontStyle.italic,
                                    color: Colors.black,
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                            const SizedBox(height: 20),

                            // Bottom Right Date
                            Align(
                              alignment: Alignment.bottomRight,
                              child: Text(
                                dateStr,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12.5,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // 3. Bottom Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                    ),
                    child: const Text(
                      'Batal',
                      style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF64748B)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _isPrinting ? null : _handlePrint,
                    icon: _isPrinting
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.print_rounded, size: 18),
                    label: Text(
                      _isPrinting ? 'Mencetak Label...' : 'Cetak Label Sekarang',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: StyleConstants.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 1,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
