import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import '../../services/printer_service.dart';

class PrinterSettingsScreen extends StatefulWidget {
  const PrinterSettingsScreen({Key? key}) : super(key: key);

  @override
  _PrinterSettingsScreenState createState() => _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends State<PrinterSettingsScreen> {
  final TextEditingController _businessNameController = TextEditingController();
  final TextEditingController _businessAddressController = TextEditingController();
  final TextEditingController _businessPhoneController = TextEditingController();
  int _receiptWidth = 58;

  String _selectedName = '';
  String _selectedAddress = '';
  List<BluetoothInfo> _devices = [];
  bool _isLoading = false;
  bool _isConnecting = false;
  bool _isConnected = false;
  bool _btEnabled = false;

  final Color primaryColor = const Color(0xFF4E80EE);
  final Color backgroundColor = const Color(0xFFF8FAFC);

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _checkBluetooth();
  }

  @override
  void dispose() {
    _businessNameController.dispose();
    _businessAddressController.dispose();
    _businessPhoneController.dispose();
    super.dispose();
  }

  Future<void> _checkBluetooth() async {
    final hasPermission = await PrinterService.requestPermissions();
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('⚠️ Izin Bluetooth diperlukan untuk mendeteksi printer')),
        );
      }
    }
    
    final enabled = await PrintBluetoothThermal.bluetoothEnabled;
    if (mounted) setState(() => _btEnabled = enabled);
    if (enabled && hasPermission) _loadDevices();
  }

  Future<void> _loadDevices() async {
    final hasPermission = await PrinterService.requestPermissions();
    if (!hasPermission) return;
    
    setState(() => _isLoading = true);
    try {
      final List<BluetoothInfo> devices = await PrintBluetoothThermal.pairedBluetooths;
      final connected = await PrintBluetoothThermal.connectionStatus;
      if (mounted) {
        setState(() {
          _devices = devices;
          _isLoading = false;
          _isConnected = connected;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _connectDevice(String mac, String name) async {
    setState(() => _isConnecting = true);
    try {
      final bool result = await PrintBluetoothThermal.connect(macPrinterAddress: mac);
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _isConnected = result;
          if (result) {
            _selectedName = name;
            _selectedAddress = mac;
          }
        });
        _savePrinterConnection(mac, name);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result ? '✅ Terhubung ke $name' : '❌ Gagal terhubung ke $name'),
            backgroundColor: result ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  Future<void> _disconnect() async {
    try {
      await PrintBluetoothThermal.disconnect;
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('printer_mac');
      await prefs.remove('printer_name');
      setState(() {
        _isConnected = false;
        _selectedAddress = '';
        _selectedName = '';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('🔌 Sambungan printer diputus'), backgroundColor: Colors.blueGrey),
      );
    } catch (e) {
      debugPrint('Error disconnecting printer: $e');
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _businessNameController.text = prefs.getString('biz_name') ?? 'Smart Laundry';
      _businessAddressController.text = prefs.getString('biz_address') ?? 'Jl. Raya Utama No. 8';
      _businessPhoneController.text = prefs.getString('biz_phone') ?? '08123456789';
      _receiptWidth = prefs.getInt('receipt_width') ?? 58;
      _selectedAddress = prefs.getString('printer_mac') ?? '';
      _selectedName = prefs.getString('printer_name') ?? '';
    });
  }

  Future<void> _savePrinterConnection(String mac, String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('printer_mac', mac);
    await prefs.setString('printer_name', name);
  }

  Future<void> _saveReceiptSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('biz_name', _businessNameController.text.trim());
    await prefs.setString('biz_address', _businessAddressController.text.trim());
    await prefs.setString('biz_phone', _businessPhoneController.text.trim());
    await prefs.setInt('receipt_width', _receiptWidth);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Pengaturan struk belanja berhasil disimpan!'), backgroundColor: Colors.green),
      );
    }
  }

  Future<void> _testPrint() async {
    if (!_isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Hubungkan printer bluetooth terlebih dahulu!'), backgroundColor: Colors.orange),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('🖨️ Mencetak halaman pengujian...'), duration: Duration(seconds: 1)),
    );

    try {
      await PrinterService.printTestPage();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Gagal cetak: $e'), backgroundColor: Colors.red),
      );
    }
  }

  InputDecoration _inputDecoration(String label, String hint, IconData icon) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
      hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
      floatingLabelStyle: const TextStyle(color: Color(0xFF4E80EE), fontWeight: FontWeight.bold),
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
      prefixIcon: Icon(icon, color: const Color(0xFF64748B), size: 20),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text('Pengaturan Printer Thermal', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: const Color(0xFFE2E8F0), height: 1),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Left Panel: Bluetooth Scan and Pairing (360px)
          Container(
            width: 360,
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(right: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // BT disabled notice
                  if (!_btEnabled)
                    Container(
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFFCA5A5)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.bluetooth_disabled_rounded, color: Color(0xFFEF4444), size: 22),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Bluetooth tidak aktif! Silakan aktifkan Bluetooth komputer.',
                              style: TextStyle(color: const Color(0xFFB91C1C), fontSize: 11.5, height: 1.5, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Connection Status
                  const Text('Printer Terkoneksi', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF475569), letterSpacing: 0.5)),
                  const SizedBox(height: 12),
                  _buildPrinterStatusCard(),
                  const SizedBox(height: 24),
                  
                  // Device List Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Daftar Perangkat', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF475569))),
                      IconButton(
                        icon: const Icon(Icons.refresh_rounded, size: 20, color: Color(0xFF64748B)),
                        onPressed: _loadDevices,
                        tooltip: 'Scan ulang bluetooth',
                        style: IconButton.styleFrom(hoverColor: const Color(0xFFF1F5F9)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Device list builder
                  _isLoading
                      ? const Center(child: Padding(padding: EdgeInsets.all(24.0), child: CircularProgressIndicator()))
                      : _devices.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 24.0),
                                child: Text('Tidak ada perangkat bluetooth paired.', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                              ),
                            )
                          : Column(
                              children: _devices.map((dev) {
                                final isSelected = _selectedAddress == dev.macAdress;
                                return Container(
                                  decoration: BoxDecoration(
                                    color: isSelected ? primaryColor.withOpacity(0.04) : Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: isSelected ? primaryColor : const Color(0xFFE2E8F0),
                                      width: isSelected ? 1.5 : 1,
                                    ),
                                  ),
                                  margin: const EdgeInsets.only(bottom: 8),
                                  child: ListTile(
                                    dense: true,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                    title: Text(dev.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A))),
                                    subtitle: Text(dev.macAdress, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                                    trailing: _isConnecting && isSelected
                                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                        : (isSelected && _isConnected)
                                            ? const Icon(Icons.check_circle_rounded, color: Colors.green, size: 20)
                                            : ElevatedButton(
                                                onPressed: () => _connectDevice(dev.macAdress, dev.name),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: primaryColor,
                                                  foregroundColor: Colors.white,
                                                  elevation: 0,
                                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                                ),
                                                child: const Text('Hubungkan', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                              ),
                                  ),
                                );
                              }).toList(),
                            ),
                ],
              ),
            ),
          ),

          // 2. Right Panel: Header Settings Form (Expanded)
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
                      color: Colors.black.withOpacity(0.02),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    )
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Desain & Informasi Kepala Struk (Header)',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Konfigurasi data cetak identitas toko pada nota belanja',
                              style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            ElevatedButton.icon(
                              onPressed: _testPrint,
                              icon: const Icon(Icons.print_rounded, color: Color(0xFF4F46E5), size: 18),
                              label: const Text('Cetak Test Page', style: TextStyle(color: Color(0xFF4F46E5), fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFEEF2F6),
                                shadowColor: Colors.transparent,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton.icon(
                              onPressed: _saveReceiptSettings,
                              icon: const Icon(Icons.save_rounded, color: Colors.white, size: 18),
                              label: const Text('Simpan Struk', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: primaryColor,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shadowColor: Colors.transparent,
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Divider(color: Color(0xFFF1F5F9)),
                    const SizedBox(height: 24),

                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextField(
                              controller: _businessNameController,
                              decoration: _inputDecoration(
                                'Nama Bisnis / Toko Laundry',
                                'Smart Laundry',
                                Icons.store_rounded,
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _businessAddressController,
                              decoration: _inputDecoration(
                                'Alamat Toko',
                                'Jl. Raya Utama No. 8',
                                Icons.location_on_rounded,
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _businessPhoneController,
                              decoration: _inputDecoration(
                                'Nomor Telepon Toko',
                                '08123456789',
                                Icons.phone_rounded,
                              ),
                            ),
                            const SizedBox(height: 16),
                            
                            // Width Dropdown
                            DropdownButtonFormField<int>(
                              value: _receiptWidth,
                              dropdownColor: Colors.white,
                              style: const TextStyle(color: Color(0xFF0F172A), fontSize: 14),
                              decoration: _inputDecoration(
                                'Lebar Kertas Cetak (Printer Thermal)',
                                '',
                                Icons.straighten_rounded,
                              ),
                              items: const [
                                DropdownMenuItem(value: 48, child: Text('48 mm (Mini Thermal)')),
                                DropdownMenuItem(value: 58, child: Text('58 mm (Standar POS Kasir)')),
                                DropdownMenuItem(value: 72, child: Text('72 mm (Medium)')),
                                DropdownMenuItem(value: 80, child: Text('80 mm (Kasir Besar/Lebar)')),
                              ],
                              onChanged: (val) {
                                if (val != null) setState(() => _receiptWidth = val);
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrinterStatusCard() {
    if (_selectedAddress.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: const Row(
          children: [
            Icon(Icons.print_disabled_rounded, color: Color(0xFF94A3B8), size: 22),
            const SizedBox(width: 12),
            Expanded(child: Text('Belum ada printer terhubung.', style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)))),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _isConnected ? const Color(0xFFECFDF5) : const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _isConnected ? const Color(0xFF10B981) : const Color(0xFFF97316)),
      ),
      child: Row(
        children: [
          Icon(Icons.print_rounded, color: _isConnected ? const Color(0xFF10B981) : const Color(0xFFF97316), size: 24),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_selectedName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Color(0xFF0F172A))),
                const SizedBox(height: 4),
                Text(
                  _isConnected ? 'TERHUBUNG' : 'DISCONNECTED (Tersimpan)',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: _isConnected ? const Color(0xFF047857) : const Color(0xFFC2410C),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.link_off_rounded, color: Colors.redAccent, size: 20),
            onPressed: _disconnect,
            tooltip: 'Putuskan printer',
            style: IconButton.styleFrom(
              backgroundColor: Colors.white,
              hoverColor: Colors.red.withOpacity(0.05),
            ),
          ),
        ],
      ),
    );
  }
}
