import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:printing/printing.dart';
import '../../services/printer_service.dart';
import '../../utils/style_constants.dart';

class PrinterSettingsScreen extends StatefulWidget {
  const PrinterSettingsScreen({Key? key}) : super(key: key);

  @override
  _PrinterSettingsScreenState createState() => _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends State<PrinterSettingsScreen> {
  final TextEditingController _businessNameController = TextEditingController();
  final TextEditingController _businessAddressController = TextEditingController();
  final TextEditingController _businessPhoneController = TextEditingController();
  final TextEditingController _footerNoteController = TextEditingController();

  String _connectionType = 'usb'; // 'usb' or 'bluetooth'
  int _receiptWidth = 58; // 58, 76 (Epson TM-U220D), 80

  // USB Printers State
  List<Printer> _usbPrinters = [];
  String _selectedUsbPrinter = '';
  bool _isLoadingUsb = false;

  // Bluetooth Printers State
  List<BluetoothInfo> _btDevices = [];
  String _selectedBtName = '';
  String _selectedBtAddress = '';
  bool _isLoadingBt = false;
  bool _isConnectingBt = false;
  bool _isBtConnected = false;
  bool _btEnabled = false;

  bool _isTestingPrint = false;
  bool _isClearingSpooler = false;

  final Color primaryColor = StyleConstants.primaryColor;
  final Color backgroundColor = StyleConstants.backgroundColor;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadUsbPrinters();
    _checkBluetooth();
  }

  @override
  void dispose() {
    _businessNameController.dispose();
    _businessAddressController.dispose();
    _businessPhoneController.dispose();
    _footerNoteController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _businessNameController.text = prefs.getString('biz_name') ?? 'Azima Laundry';
      _businessAddressController.text = prefs.getString('biz_address') ?? 'Jl. Raya Utama No. 8';
      _businessPhoneController.text = prefs.getString('biz_phone') ?? '08123456789';
      _footerNoteController.text = prefs.getString('biz_footer') ?? 'Terima kasih telah mencuci di Azima Laundry!';
      _connectionType = prefs.getString('printer_connection_type') ?? 'usb';
      _receiptWidth = prefs.getInt('receipt_width') ?? 58;
      _selectedUsbPrinter = prefs.getString('printer_usb_name') ?? '';
      _selectedBtAddress = prefs.getString('printer_mac') ?? '';
      _selectedBtName = prefs.getString('printer_name') ?? '';
    });
  }

  Future<void> _loadUsbPrinters() async {
    setState(() => _isLoadingUsb = true);
    try {
      final list = await PrinterService.getAvailableUsbPrinters();
      if (mounted) {
        setState(() {
          _usbPrinters = list;
          _isLoadingUsb = false;
          // Auto select default printer if none is selected yet
          if (_selectedUsbPrinter.isEmpty && list.isNotEmpty) {
            final defaultPrinter = list.firstWhere((p) => p.isDefault, orElse: () => list.first);
            _selectedUsbPrinter = defaultPrinter.name;
          }
        });
      }
    } catch (e) {
      debugPrint('[PrinterSettings] Gagal memuat USB printers: $e');
      if (mounted) setState(() => _isLoadingUsb = false);
    }
  }

  Future<void> _checkBluetooth() async {
    if (!Platform.isAndroid) return;
    final hasPermission = await PrinterService.requestPermissions();
    final enabled = await PrintBluetoothThermal.bluetoothEnabled;
    if (mounted) setState(() => _btEnabled = enabled);
    if (enabled && hasPermission) _loadBtDevices();
  }

  Future<void> _loadBtDevices() async {
    setState(() => _isLoadingBt = true);
    try {
      final List<BluetoothInfo> devices = await PrintBluetoothThermal.pairedBluetooths;
      final connected = await PrintBluetoothThermal.connectionStatus;
      if (mounted) {
        setState(() {
          _btDevices = devices;
          _isLoadingBt = false;
          _isBtConnected = connected;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingBt = false);
    }
  }

  Future<void> _selectUsbPrinter(Printer printer) async {
    setState(() => _selectedUsbPrinter = printer.name);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('printer_usb_name', printer.name);
    await prefs.setString('printer_connection_type', 'usb');

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Printer kabel aktif diset ke: ${printer.name}'),
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  Future<void> _connectBtDevice(String mac, String name) async {
    setState(() => _isConnectingBt = true);
    try {
      final bool result = await PrintBluetoothThermal.connect(macPrinterAddress: mac);
      if (mounted) {
        setState(() {
          _isConnectingBt = false;
          _isBtConnected = result;
          if (result) {
            _selectedBtName = name;
            _selectedBtAddress = mac;
          }
        });
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('printer_mac', mac);
        await prefs.setString('printer_name', name);
        await prefs.setString('printer_connection_type', 'bluetooth');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result ? 'Terhubung ke $name' : 'Gagal terhubung ke $name'),
              backgroundColor: result ? Colors.green : Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isConnectingBt = false);
    }
  }

  Future<void> _disconnectBt() async {
    try {
      await PrintBluetoothThermal.disconnect;
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('printer_mac');
      await prefs.remove('printer_name');
      setState(() {
        _isBtConnected = false;
        _selectedBtAddress = '';
        _selectedBtName = '';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sambungan bluetooth diputus'), backgroundColor: Colors.blueGrey),
        );
      }
    } catch (e) {
      debugPrint('Error disconnecting printer: $e');
    }
  }

  Future<void> _saveAllSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('printer_connection_type', _connectionType);
    await prefs.setString('printer_usb_name', _selectedUsbPrinter);
    await prefs.setInt('receipt_width', _receiptWidth);
    await prefs.setString('biz_name', _businessNameController.text.trim());
    await prefs.setString('biz_address', _businessAddressController.text.trim());
    await prefs.setString('biz_phone', _businessPhoneController.text.trim());
    await prefs.setString('biz_footer', _footerNoteController.text.trim());

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              const Text('Pengaturan printer dan struk berhasil disimpan!'),
            ],
          ),
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  Future<void> _testPrint() async {
    setState(() => _isTestingPrint = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
            SizedBox(width: 10),
            Text('Mengirim halaman pengujian ke printer...'),
          ],
        ),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );

    try {
      final result = await PrinterService.printTestPage();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result ? 'Halaman tes cetak berhasil dikirim!' : 'Gagal mengirim cetak ke printer.'),
            backgroundColor: result ? const Color(0xFF10B981) : Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error cetak: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isTestingPrint = false);
      }
    }
  }

  Future<void> _clearSpooler() async {
    setState(() => _isClearingSpooler = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
            SizedBox(width: 10),
            Text('Membersihkan antrean Print Spooler Windows...'),
          ],
        ),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );

    try {
      final result = await PrinterService.clearPrintSpooler();
      await _loadUsbPrinters();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.cleaning_services_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text(result['message'] ?? 'Spooler berhasil dibersihkan!')),
              ],
            ),
            backgroundColor: result['success'] == true ? const Color(0xFF10B981) : Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal bersihkan spooler: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isClearingSpooler = false);
      }
    }
  }

  InputDecoration _inputDecoration(String label, String hint, IconData icon) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 12.5, fontWeight: FontWeight.bold),
      hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
      floatingLabelStyle: TextStyle(color: primaryColor, fontWeight: FontWeight.w800),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: primaryColor, width: 2)),
      prefixIcon: Icon(icon, color: const Color(0xFF64748B), size: 20),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.canPop(context);

    Widget content = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Left Panel: Connection Manager (USB / Bluetooth Selector & Device List)
        Container(
          width: 440,
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(right: BorderSide(color: Color(0xFFE2E8F0))),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.print_rounded, size: 22, color: Color(0xFF0F172A)),
                        SizedBox(width: 10),
                        Text(
                          'Pilih Tipe Koneksi Printer',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Connection Type Segmented Switcher
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildTypeSegment(
                              label: 'Kabel USB / Windows',
                              icon: Icons.usb_rounded,
                              type: 'usb',
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: _buildTypeSegment(
                              label: 'Bluetooth Nirkabel',
                              icon: Icons.bluetooth_rounded,
                              type: 'bluetooth',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFFE2E8F0)),

              // Device List Area
              Expanded(
                child: _connectionType == 'usb' ? _buildUsbPrinterList() : _buildBluetoothDeviceList(),
              ),
            ],
          ),
        ),

        // 2. Right Panel: Receipt Header & Design Configuration
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28.0),
            child: Container(
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
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.receipt_long_rounded, color: Color(0xFF6366F1), size: 24),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Desain & Informasi Kepala Struk (Header)',
                              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Konfigurasi identitas toko, ukuran kertas, dan format cetak nota kasir',
                              style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                            ),
                          ],
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _isClearingSpooler ? null : _clearSpooler,
                        icon: _isClearingSpooler
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFE11D48)))
                            : const Icon(Icons.cleaning_services_rounded, size: 16, color: Color(0xFFE11D48)),
                        label: Text(
                          _isClearingSpooler ? 'Clearing...' : 'Clear Spooler',
                          style: const TextStyle(color: Color(0xFFE11D48), fontWeight: FontWeight.bold),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFFDA4AF)),
                          backgroundColor: const Color(0xFFFFF1F2),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: _isTestingPrint ? null : _testPrint,
                        icon: const Icon(Icons.print_rounded, size: 18, color: Colors.white),
                        label: const Text('Cetak Test Page', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6366F1),
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          elevation: 0,
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: _saveAllSettings,
                        icon: const Icon(Icons.save_rounded, size: 18, color: Colors.white),
                        label: const Text('Simpan Struk', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          elevation: 0,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  const SizedBox(height: 24),

                  // Form Fields
                  TextField(
                    controller: _businessNameController,
                    decoration: _inputDecoration('Nama Bisnis / Toko Laundry', 'Misal: Azima Laundry', Icons.store_rounded),
                  ),
                  const SizedBox(height: 18),

                  TextField(
                    controller: _businessAddressController,
                    decoration: _inputDecoration('Alamat Toko', 'Misal: Jl. Raya Utama No. 8', Icons.location_on_rounded),
                  ),
                  const SizedBox(height: 18),

                  TextField(
                    controller: _businessPhoneController,
                    keyboardType: TextInputType.phone,
                    decoration: _inputDecoration('Nomor Telepon / WhatsApp Toko', 'Misal: 08123456789', Icons.phone_rounded),
                  ),
                  const SizedBox(height: 18),

                  // Receipt Paper Width Selector (with Epson TM-U220D 76mm Support!)
                  DropdownButtonFormField<int>(
                    value: _receiptWidth,
                    decoration: _inputDecoration('Lebar Kertas Cetak (Printer POS)', 'Pilih ukuran kertas', Icons.straighten_rounded),
                    items: const [
                      DropdownMenuItem(
                        value: 58,
                        child: Row(
                          children: [
                            Icon(Icons.receipt_rounded, size: 18, color: Color(0xFF64748B)),
                            SizedBox(width: 10),
                            Text('58 mm (Printer Thermal Standar Kasir)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                          ],
                        ),
                      ),
                      DropdownMenuItem(
                        value: 76,
                        child: Row(
                          children: [
                            Icon(Icons.precision_manufacturing_rounded, size: 18, color: Color(0xFF6366F1)),
                            SizedBox(width: 10),
                            Text('76 mm (Dot Matrix Epson TM-U220D / Star SP700)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Color(0xFF4338CA))),
                          ],
                        ),
                      ),
                      DropdownMenuItem(
                        value: 80,
                        child: Row(
                          children: [
                            Icon(Icons.receipt_long_rounded, size: 18, color: Color(0xFF64748B)),
                            SizedBox(width: 10),
                            Text('80 mm (Printer Thermal Lebar / POS-80)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                          ],
                        ),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _receiptWidth = val);
                      }
                    },
                  ),
                  if (_receiptWidth == 76) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF2FF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFC7D2FE)),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.verified_rounded, size: 20, color: Color(0xFF4338CA)),
                          SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Konfigurasi Optimal Epson TM-U220D (76 mm Dot Matrix):',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Color(0xFF3730A3)),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  '• Ukuran font otomatis diperbesar (13.5pt Header / 10pt Item) dengan ketebalan ekstra tebal agar teks terbaca tajam dan rapat di pita ribbon/NCR 2-ply 9-pin.\n• Margin telah disesuaikan dengan batas area cetak 63.5 mm (40 kolom) agar tidak terpotong di tepi kertas.',
                                  style: TextStyle(fontSize: 11.5, color: Color(0xFF4338CA), height: 1.4),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),

                  TextField(
                    controller: _footerNoteController,
                    maxLines: 2,
                    decoration: _inputDecoration('Catatan Kaki Struk (Footer Message)', 'Misal: Terima kasih telah mencuci di tempat kami!', Icons.notes_rounded),
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
          title: const Text('Pengaturan Printer Kasir', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF0F172A),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, size: 22),
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
    } else {
      return content;
    }
  }

  Widget _buildTypeSegment({
    required String label,
    required IconData icon,
    required String type,
  }) {
    final isSelected = _connectionType == type;
    return InkWell(
      onTap: () {
        setState(() => _connectionType = type);
        final prefs = SharedPreferences.getInstance();
        prefs.then((p) => p.setString('printer_connection_type', type));
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: isSelected
              ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 2))]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: isSelected ? primaryColor : const Color(0xFF64748B)),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? primaryColor : const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUsbPrinterList() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              const Text(
                'Printer Kabel Terdeteksi (Windows)',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 18),
                onPressed: _loadUsbPrinters,
                tooltip: 'Refresh Printer',
                style: IconButton.styleFrom(backgroundColor: const Color(0xFFF1F5F9), padding: const EdgeInsets.all(6)),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: Color(0xFFF1F5F9)),
        Expanded(
          child: _isLoadingUsb
              ? const Center(child: CircularProgressIndicator())
              : _usbPrinters.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.print_disabled_rounded, size: 42, color: Colors.grey[300]),
                            const SizedBox(height: 12),
                            const Text(
                              'Tidak ada printer driver terpasang di Windows.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _usbPrinters.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final printer = _usbPrinters[index];
                        final isSelected = _selectedUsbPrinter == printer.name;

                        return Container(
                          decoration: BoxDecoration(
                            color: isSelected ? const Color(0xFFEFF6FF) : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected ? primaryColor : const Color(0xFFE2E8F0),
                              width: isSelected ? 2 : 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: isSelected ? primaryColor.withValues(alpha: 0.1) : const Color(0xFF0F172A).withValues(alpha: 0.02),
                                blurRadius: isSelected ? 6 : 2,
                              ),
                            ],
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: isSelected ? primaryColor : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.usb_rounded,
                                color: isSelected ? Colors.white : const Color(0xFF64748B),
                                size: 20,
                              ),
                            ),
                            title: Text(
                              printer.name,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13.5,
                                color: isSelected ? primaryColor : const Color(0xFF0F172A),
                              ),
                            ),
                            subtitle: Text(
                              printer.isDefault ? 'Default Windows Printer' : 'Kabel USB / Spooler Siap',
                              style: TextStyle(
                                fontSize: 11,
                                color: isSelected ? const Color(0xFF2563EB) : const Color(0xFF64748B),
                              ),
                            ),
                            trailing: isSelected
                                ? const Icon(Icons.check_circle_rounded, color: Color(0xFF2563EB), size: 20)
                                : ElevatedButton(
                                    onPressed: () => _selectUsbPrinter(printer),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFF1F5F9),
                                      foregroundColor: const Color(0xFF0F172A),
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    child: const Text('Pilih', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                  ),
                            onTap: () => _selectUsbPrinter(printer),
                          ),
                        );
                      },
                    ),
        ),
        // Clear Spooler Footer Button
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: OutlinedButton.icon(
            onPressed: _isClearingSpooler ? null : _clearSpooler,
            icon: _isClearingSpooler
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFE11D48)))
                : const Icon(Icons.cleaning_services_rounded, size: 18, color: Color(0xFFE11D48)),
            label: Text(
              _isClearingSpooler ? 'Sedang Bersihkan Spooler...' : 'Bersihkan Antrean Print Spooler (Clear Spooler)',
              style: const TextStyle(color: Color(0xFFE11D48), fontWeight: FontWeight.bold, fontSize: 12),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFFFDA4AF), width: 1.5),
              backgroundColor: const Color(0xFFFFF1F2),
              minimumSize: const Size.fromHeight(44),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBluetoothDeviceList() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              const Text(
                'Perangkat Bluetooth Paired',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 18),
                onPressed: _loadBtDevices,
                tooltip: 'Scan Bluetooth',
                style: IconButton.styleFrom(backgroundColor: const Color(0xFFF1F5F9), padding: const EdgeInsets.all(6)),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: Color(0xFFF1F5F9)),
        Expanded(
          child: _isLoadingBt
              ? const Center(child: CircularProgressIndicator())
              : _btDevices.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.bluetooth_disabled_rounded, size: 42, color: Colors.grey[300]),
                            const SizedBox(height: 12),
                            const Text(
                              'Tidak ada printer bluetooth yang paired.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _btDevices.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final dev = _btDevices[index];
                        final isConnected = _isBtConnected && _selectedBtAddress == dev.macAdress;

                        return Container(
                          decoration: BoxDecoration(
                            color: isConnected ? const Color(0xFFF0FDF4) : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isConnected ? const Color(0xFF10B981) : const Color(0xFFE2E8F0),
                              width: isConnected ? 2 : 1,
                            ),
                          ),
                          child: ListTile(
                            leading: Icon(Icons.bluetooth_connected_rounded, color: isConnected ? const Color(0xFF10B981) : const Color(0xFF64748B)),
                            title: Text(dev.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                            subtitle: Text(dev.macAdress, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                            trailing: isConnected
                                ? ElevatedButton(
                                    onPressed: _disconnectBt,
                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red[50], foregroundColor: Colors.red, elevation: 0),
                                    child: const Text('Putus', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                  )
                                : ElevatedButton(
                                    onPressed: _isConnectingBt ? null : () => _connectBtDevice(dev.macAdress, dev.name),
                                    style: ElevatedButton.styleFrom(backgroundColor: primaryColor, foregroundColor: Colors.white, elevation: 0),
                                    child: const Text('Hubungkan', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                  ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
