import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import '../../services/printer_service.dart';
import '../../services/machine_status_service.dart';
import '../../services/backend_services_manager.dart';
import '../../database/models/database_helper.dart';
import '../../database/models/machine_model.dart';
import '../../transactions/user_repository.dart';

class SetupWizardScreen extends StatefulWidget {
  const SetupWizardScreen({Key? key}) : super(key: key);

  @override
  _SetupWizardScreenState createState() => _SetupWizardScreenState();
}

class _SetupWizardScreenState extends State<SetupWizardScreen> {
  int _currentStep = 0;
  bool _isLoading = false;

  // Step 1: Admin & Toko
  final _formKey1 = GlobalKey<FormState>();
  final _bizNameCtrl = TextEditingController(text: 'Azima Laundry');
  final _bizAddressCtrl = TextEditingController(text: 'Jl. Raya Utama No. 8');
  final _bizPhoneCtrl = TextEditingController(text: '08123456789');
  final _adminUsernameCtrl = TextEditingController(text: 'admin');
  final _adminPasswordCtrl = TextEditingController();
  final _adminPasswordConfirmCtrl = TextEditingController();

  // Step 2: Printer
  List<BluetoothInfo> _printerDevices = [];
  String _selectedPrinterMac = '';
  String _selectedPrinterName = '';
  bool _isConnectingPrinter = false;
  bool _isBluetoothEnabled = false;

  // Step 3: LG ThinQ
  final _countryCtrl = TextEditingController(text: 'ID');
  final _langCtrl = TextEditingController(text: 'id-ID');
  final _patTokenCtrl = TextEditingController();
  bool _isThinqConnected = false;
  final ScrollController _thinqScrollController = ScrollController();

  // Step 4: Bardi Tuya
  final _tuyaAccessIdCtrl = TextEditingController();
  final _tuyaAccessSecretCtrl = TextEditingController();
  final _tuyaAppUidCtrl = TextEditingController();
  final _tuyaEndpointCtrl = TextEditingController(text: 'https://openapi.tuyaus.com');
  bool _isBardiConnected = false;
  final ScrollController _bardiScrollController = ScrollController();

  // Step 5: Daftar Mesin (Cuci & Pengering dipisah)
  List<MachineModel> _setupWashingMachines = [];
  List<MachineModel> _setupDryers = [];
  bool _isFetchingMachines = false;
  final ScrollController _washScrollController = ScrollController();
  final ScrollController _dryScrollController = ScrollController();

  // Step 6: WhatsApp
  bool _isWaConnected = false;
  String? _waQrBase64;
  String? _waQrMessage;

  final Color primaryColor = const Color(0xFF4E80EE);
  final Color successColor = const Color(0xFF10B981);
  final Color cardBackgroundColor = Colors.white;

  @override
  void initState() {
    super.initState();
    _checkBluetooth();
    _loadExistingMachines();
  }

  Future<void> _loadExistingMachines() async {
    try {
      final list = await DatabaseHelper.instance.getAllMachines();
      if (mounted) {
        setState(() {
          _setupWashingMachines = list.where((m) => m.machineType == 'cuci').toList();
          _setupWashingMachines.sort((a, b) {
            final numA = _extractMachineNumber(a);
            final numB = _extractMachineNumber(b);
            return numA.compareTo(numB);
          });
          
          _setupDryers = list.where((m) => m.machineType == 'pengering').toList();
          _setupDryers.sort((a, b) {
            final numA = _extractMachineNumber(a);
            final numB = _extractMachineNumber(b);
            return numA.compareTo(numB);
          });
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _bizNameCtrl.dispose();
    _bizAddressCtrl.dispose();
    _bizPhoneCtrl.dispose();
    _adminUsernameCtrl.dispose();
    _adminPasswordCtrl.dispose();
    _adminPasswordConfirmCtrl.dispose();
    _countryCtrl.dispose();
    _langCtrl.dispose();
    _patTokenCtrl.dispose();
    _tuyaAccessIdCtrl.dispose();
    _tuyaAccessSecretCtrl.dispose();
    _tuyaAppUidCtrl.dispose();
    _tuyaEndpointCtrl.dispose();
    _thinqScrollController.dispose();
    _bardiScrollController.dispose();
    _washScrollController.dispose();
    _dryScrollController.dispose();
    super.dispose();
  }

  // --- Bluetooth Helpers ---
  Future<void> _checkBluetooth() async {
    final hasPermission = await PrinterService.requestPermissions();
    if (!hasPermission) return;

    final enabled = await PrintBluetoothThermal.bluetoothEnabled;
    setState(() => _isBluetoothEnabled = enabled);
    if (enabled) {
      _scanPrinters();
    }
  }

  Future<void> _scanPrinters() async {
    final hasPermission = await PrinterService.requestPermissions();
    if (!hasPermission) return;

    setState(() => _isLoading = true);
    try {
      final List<BluetoothInfo> devices = await PrintBluetoothThermal.pairedBluetooths;
      setState(() {
        _printerDevices = devices;
        _isLoading = false;
      });
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _connectPrinter(String mac, String name) async {
    setState(() => _isConnectingPrinter = true);
    try {
      final bool result = await PrintBluetoothThermal.connect(macPrinterAddress: mac);
      setState(() {
        _isConnectingPrinter = false;
        if (result) {
          _selectedPrinterMac = mac;
          _selectedPrinterName = name;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result ? 'Terhubung ke $name' : 'Gagal terhubung ke $name'),
          backgroundColor: result ? Colors.green : Colors.red,
        ),
      );
    } catch (_) {
      setState(() => _isConnectingPrinter = false);
    }
  }

  Future<void> _printTestPage() async {
    if (_selectedPrinterMac.isEmpty) return;
    try {
      final bool connected = await PrintBluetoothThermal.connectionStatus;
      if (!connected) {
        await PrintBluetoothThermal.connect(macPrinterAddress: _selectedPrinterMac);
      }

      List<int> bytes = [];
      bytes += utf8.encode('\n');
      bytes += utf8.encode('================================\n');
      bytes += utf8.encode('      TEST PRINTER AZIMA\n');
      bytes += utf8.encode('================================\n');
      bytes += utf8.encode('Printer: $_selectedPrinterName\n');
      bytes += utf8.encode('Status: Berhasil Terhubung!\n');
      bytes += utf8.encode('Tanggal: ${DateTime.now().toString().substring(0, 19)}\n');
      bytes += utf8.encode('================================\n\n\n\n');

      await PrintBluetoothThermal.writeBytes(bytes);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal cetak: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // --- Step 1 Save ---
  Future<bool> _saveStep1() async {
    if (!_formKey1.currentState!.validate()) return false;

    setState(() => _isLoading = true);
    try {
      // 1. Save Biz Profile in SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('biz_name', _bizNameCtrl.text.trim());
      await prefs.setString('biz_address', _bizAddressCtrl.text.trim());
      await prefs.setString('biz_phone', _bizPhoneCtrl.text.trim());
      await prefs.setInt('receipt_width', 58);

      // 2. Create Admin Account in SQLite database
      final userRepo = UserRepository();
      final adminExists = await userRepo.checkAdminExists();
      if (!adminExists) {
        final result = await userRepo.createAdmin(
          _adminUsernameCtrl.text.trim(),
          _adminPasswordCtrl.text.trim(),
        );
        if (!result) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Gagal membuat akun administrator.'), backgroundColor: Colors.red),
          );
          setState(() => _isLoading = false);
          return false;
        }
      }
      setState(() => _isLoading = false);
      return true;
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
      return false;
    }
  }

  // --- Step 3 Save/Test ThinQ ---
  Future<void> _testThinq() async {
    setState(() => _isLoading = true);
    try {
      // Ensure backend server is ready before dispatching request
      await BackendServicesManager.instance.isBackendReady(timeout: const Duration(seconds: 5));

      final dashboardUri = Uri.parse(MachineStatusService.instance.dashboardUrl);
      final apiBaseUrl = '${dashboardUri.scheme}://${dashboardUri.host}:5001';

      final response = await http.post(
        Uri.parse('$apiBaseUrl/api/lg/settings'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'country': _countryCtrl.text.trim(),
          'language': _langCtrl.text.trim(),
          'pat_token': _patTokenCtrl.text.trim(),
          'interval_idle': 300,
          'interval_booking': 180,
          'interval_running_high': 300,
          'interval_running_low': 120,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        // Query status to verify connectivity
        final statusResp = await http.get(Uri.parse('$apiBaseUrl/api/lg/status'));
        if (statusResp.statusCode == 200) {
          final data = json.decode(statusResp.body);
          final connected = data['connected'] ?? false;
          setState(() {
            _isThinqConnected = connected;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(connected ? 'Sinkronisasi LG ThinQ Berhasil!' : 'Pengaturan disimpan, namun belum terhubung ke mesin.'),
              backgroundColor: connected ? Colors.green : Colors.orange,
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: Status ${response.statusCode}'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal terhubung ke API: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }
  // --- Step 4 Save/Test Bardi Tuya ---
  Future<void> _testBardi() async {
    setState(() => _isLoading = true);
    try {
      // Ensure backend server is ready before dispatching request
      await BackendServicesManager.instance.isBackendReady(timeout: const Duration(seconds: 5));

      final dashboardUri = Uri.parse(MachineStatusService.instance.dashboardUrl);
      final apiBaseUrl = '${dashboardUri.scheme}://${dashboardUri.host}:5001';

      // 1. First sync keys to verify if credentials work
      final response = await http.post(
        Uri.parse('$apiBaseUrl/api/tuya/sync-keys'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'access_id': _tuyaAccessIdCtrl.text.trim(),
          'access_secret': _tuyaAccessSecretCtrl.text.trim(),
          'app_uid': _tuyaAppUidCtrl.text.trim(),
          'endpoint': _tuyaEndpointCtrl.text.trim(),
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          // 2. If sync is successful, save these settings permanently
          final saveResp = await http.post(
            Uri.parse('$apiBaseUrl/api/tuya/settings'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'access_id': _tuyaAccessIdCtrl.text.trim(),
              'access_secret': _tuyaAccessSecretCtrl.text.trim(),
              'app_uid': _tuyaAppUidCtrl.text.trim(),
              'endpoint': _tuyaEndpointCtrl.text.trim(),
            }),
          );

          if (saveResp.statusCode == 200) {
            setState(() {
              _isBardiConnected = true;
            });
            final int count = data['total_devices'] ?? 0;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Sinkronisasi Bardi Tuya Berhasil! Menemukan $count perangkat.'),
                backgroundColor: Colors.green,
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Gagal menyimpan pengaturan: HTTP ${saveResp.statusCode}'), backgroundColor: Colors.orange),
            );
          }
        } else {
          setState(() {
            _isBardiConnected = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Gagal: ${data['error'] ?? 'koneksi ditolak'}'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } else {
        final data = json.decode(response.body);
        final errMsg = data['error'] ?? 'Status ${response.statusCode}';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sinkronisasi Gagal: $errMsg'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal terhubung ke API: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // --- Step 5 Save/Fetch Machines (Dipisah) ---
  int _extractNumber(String input) {
    final RegExp numRegExp = RegExp(r'\d+');
    final match = numRegExp.firstMatch(input);
    if (match != null) {
      return int.tryParse(match.group(0)!) ?? 99999;
    }
    return 99999;
  }

  int _extractMachineNumber(MachineModel m) {
    int val = _extractNumber(m.name);
    if (val != 99999) return val;
    val = _extractNumber(m.url);
    if (val != 99999) return val;
    val = _extractNumber(m.key);
    return val;
  }

  Future<void> _fetchThinqDevices({bool forceOverwrite = false}) async {
    setState(() => _isFetchingMachines = true);
    try {
      final dashboardUri = Uri.parse(MachineStatusService.instance.dashboardUrl);
      final apiBaseUrl = '${dashboardUri.scheme}://${dashboardUri.host}:5001';

      final resp = await http.get(Uri.parse('$apiBaseUrl/api/lg/devices')).timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body);
        final List<String> thinqDevices = List<String>.from(data['devices'] ?? []);

        final List<MachineModel> list = [];
        for (final name in thinqDevices) {
          final displayName = name.replaceAll('_', ' ');
          list.add(MachineModel(
            name: displayName,
            machineType: 'cuci',
            url: '',
            key: name,
            createdAt: DateTime.now(),
          ));
        }

        // Auto sort ascending by extracted number
        list.sort((a, b) {
          final numA = _extractMachineNumber(a);
          final numB = _extractMachineNumber(b);
          if (numA == numB) {
            return a.key.compareTo(b.key);
          }
          return numA.compareTo(numB);
        });

        setState(() {
          if (forceOverwrite || _setupWashingMachines.isEmpty) {
            _setupWashingMachines = list;
          } else {
            // merge unique
            for (final f in list) {
              if (!_setupWashingMachines.any((m) => m.key == f.key)) {
                _setupWashingMachines.add(f);
              }
            }
            // Sort full list again
            _setupWashingMachines.sort((a, b) {
              final numA = _extractMachineNumber(a);
              final numB = _extractMachineNumber(b);
              return numA.compareTo(numB);
            });
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Berhasil menyinkronkan ${thinqDevices.length} mesin cuci LG ThinQ.'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal sinkronisasi data ThinQ: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isFetchingMachines = false);
    }
  }

  Future<void> _fetchBardiDevices({bool forceOverwrite = false}) async {
    setState(() => _isFetchingMachines = true);
    try {
      final dashboardUri = Uri.parse(MachineStatusService.instance.dashboardUrl);
      final apiBaseUrl = '${dashboardUri.scheme}://${dashboardUri.host}:5001';

      final resp = await http.get(Uri.parse('$apiBaseUrl/api/tuya/devices')).timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body);
        final List<dynamic> tuyaDevices = data['devices'] ?? [];

        final List<MachineModel> list = [];
        for (final item in tuyaDevices) {
          final devId = item['id'] ?? '';
          final devName = item['name'] ?? 'Pengering';
          list.add(MachineModel(
            name: devName,
            machineType: 'pengering',
            url: devId,
            key: devId,
            createdAt: DateTime.now(),
          ));
        }

        // Auto sort ascending by extracted number
        list.sort((a, b) {
          final numA = _extractMachineNumber(a);
          final numB = _extractMachineNumber(b);
          if (numA == numB) {
            return a.url.compareTo(b.url);
          }
          return numA.compareTo(numB);
        });

        setState(() {
          if (forceOverwrite || _setupDryers.isEmpty) {
            _setupDryers = list;
          } else {
            // merge unique
            for (final f in list) {
              if (!_setupDryers.any((m) => m.url == f.url)) {
                _setupDryers.add(f);
              }
            }
            // Sort full list again
            _setupDryers.sort((a, b) {
              final numA = _extractMachineNumber(a);
              final numB = _extractMachineNumber(b);
              return numA.compareTo(numB);
            });
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Berhasil menyinkronkan ${tuyaDevices.length} stopkontak Bardi.'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal sinkronisasi data Bardi: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isFetchingMachines = false);
    }
  }

  Future<void> _saveMachinesToDb() async {
    try {
      final db = await DatabaseHelper.instance.database;
      await db.transaction((txn) async {
        await txn.delete('machines');
        
        // Save washing machines
        for (final m in _setupWashingMachines) {
          await txn.insert('machines', {
            'machine_type': 'cuci',
            'name': m.name.trim(),
            'url': m.url,
            'key': m.key,
            'created_at': DateTime.now().toIso8601String(),
          });
        }
        
        // Save dryers
        for (final m in _setupDryers) {
          await txn.insert('machines', {
            'machine_type': 'pengering',
            'name': m.name.trim(),
            'url': m.url,
            'key': m.key,
            'created_at': DateTime.now().toIso8601String(),
          });
        }
      });
      debugPrint('[SetupWizard] Saved ${_setupWashingMachines.length} washers and ${_setupDryers.length} dryers to DB.');
    } catch (e) {
      debugPrint('[SetupWizard] Error saving machines to DB: $e');
    }
  }

  // --- Step 4 WhatsApp QR & Status Check ---
  Future<void> _fetchWaStatus() async {
    try {
      final statusUri = Uri.parse('${MachineStatusService.instance.dashboardUrl}/api/wa/status');
      final resp = await http.get(statusUri).timeout(const Duration(seconds: 3));
      if (resp.statusCode == 200 && mounted) {
        final data = json.decode(resp.body);
        final connected = data['connected'] ?? false;
        setState(() {
          _isWaConnected = connected;
        });

        if (!connected) {
          // Fetch QR
          final qrUri = Uri.parse('${MachineStatusService.instance.dashboardUrl}/api/wa/qr');
          final qrResp = await http.get(qrUri);
          if (qrResp.statusCode == 200 && mounted) {
            final qrData = json.decode(qrResp.body);
            final qrString = qrData['qr'] as String?;
            setState(() {
              if (qrString != null && qrString.startsWith('data:image/png;base64,')) {
                _waQrBase64 = qrString.split(',')[1];
              } else {
                _waQrBase64 = null;
              }
              _waQrMessage = qrData['message'];
            });
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _completeSetup() async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_setup_done', true);
      
      // Save printer connection if selected
      if (_selectedPrinterMac.isNotEmpty) {
        await prefs.setString('printer_mac', _selectedPrinterMac);
        await prefs.setString('printer_name', _selectedPrinterName);
      }

      setState(() => _isLoading = false);
      Navigator.of(context).pushReplacementNamed('/');
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  // --- Next/Prev Navigation ---
  void _nextStep() async {
    if (_currentStep == 0) {
      final ok = await _saveStep1();
      if (!ok) return;
    }
    if (_currentStep == 1) {
      if (_setupWashingMachines.isEmpty) {
        _fetchThinqDevices();
      }
    }
    if (_currentStep == 2) {
      await _saveMachinesToDb();
    }
    if (_currentStep == 3) {
      if (_setupDryers.isEmpty) {
        _fetchBardiDevices();
      }
    }
    if (_currentStep == 4) {
      await _saveMachinesToDb();
      
      // Trigger WA check on going to WhatsApp Bot (index 5)
      _fetchWaStatus();
      // Periodically check WA status during step 6
      Future.doWhile(() async {
        await Future.delayed(const Duration(seconds: 4));
        if (_currentStep != 5 || _isWaConnected || !mounted) return false;
        await _fetchWaStatus();
        return true;
      });
    }

    setState(() {
      _currentStep++;
    });
  }

  void _prevStep() {
    setState(() {
      _currentStep--;
    });
  }

  // --- UI Components ---
  Widget _buildStepIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 32),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          _buildStepNode(0, 'Profil & Admin', Icons.admin_panel_settings_rounded),
          _buildStepLine(0),
          _buildStepNode(1, 'ThinQ Cloud', Icons.cloud_sync_rounded),
          _buildStepLine(1),
          _buildStepNode(2, 'Mesin Cuci', Icons.local_laundry_service_rounded),
          _buildStepLine(2),
          _buildStepNode(3, 'Bardi Tuya', Icons.outlet_rounded),
          _buildStepLine(3),
          _buildStepNode(4, 'Pengering', Icons.wb_sunny_rounded),
          _buildStepLine(4),
          _buildStepNode(5, 'WhatsApp Bot', Icons.chat_rounded),
          _buildStepLine(5),
          _buildStepNode(6, 'Printer thermal', Icons.print_rounded),
        ],
      ),
    );
  }

  Widget _buildStepNode(int index, String title, IconData icon) {
    final isActive = _currentStep == index;
    final isDone = _currentStep > index;

    return Expanded(
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDone
                  ? successColor
                  : isActive
                      ? primaryColor
                      : Colors.grey.shade200,
            ),
            child: Icon(
              isDone ? Icons.check_rounded : icon,
              color: isDone || isActive ? Colors.white : Colors.grey.shade500,
              size: 18,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              title,
              style: TextStyle(
                fontWeight: isActive || isDone ? FontWeight.bold : FontWeight.normal,
                color: isActive ? primaryColor : isDone ? successColor : Colors.grey.shade600,
                fontSize: 12,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepLine(int index) {
    final isDone = _currentStep > index;
    return Container(
      width: 48,
      height: 2,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: isDone ? successColor : Colors.grey.shade200,
    );
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 0:
        return _buildStep1();
      case 1:
        return _buildStep3(); // ThinQ Cloud setup
      case 2:
        return _buildStepWashingMachines(); // ThinQ Washers list
      case 3:
        return _buildStepBardi(); // Bardi Tuya Cloud setup
      case 4:
        return _buildStepDryers(); // Bardi Dryers list
      case 5:
        return _buildStep4(); // WhatsApp Bot
      case 6:
        return _buildStep2(); // Printer thermal
      default:
        return Container();
    }
  }

  Widget _buildStepWashingMachines() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Pengaturan Mesin Cuci',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Urutkan dengan panah, ganti nama, hapus, atau tambahkan mesin cuci manual.',
                    style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _isFetchingMachines ? null : () => _fetchThinqDevices(forceOverwrite: true),
                  icon: _isFetchingMachines
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.sync_rounded, size: 16),
                  label: const Text('Ambil Otomatis', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _showAddWashingMachineDialog,
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Tambah Manual', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: successColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_setupWashingMachines.isEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.local_laundry_service_rounded, size: 48, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  const Text(
                    'Belum ada mesin cuci terdaftar.',
                    style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Klik "Ambil Otomatis" untuk menarik data mesin dari LG ThinQ Cloud.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: Scrollbar(
              controller: _washScrollController,
              thumbVisibility: true,
              child: ListView.builder(
                controller: _washScrollController,
                itemCount: _setupWashingMachines.length,
                itemBuilder: (context, idx) {
                  final machine = _setupWashingMachines[idx];
                  final isManual = machine.key == 'manual';

                  return Card(
                    key: ValueKey('wash_${machine.key}_$idx'),
                    margin: const EdgeInsets.only(bottom: 8, right: 16),
                    elevation: 1,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      leading: CircleAvatar(
                        backgroundColor: Colors.blue.shade50,
                        child: const Icon(Icons.local_laundry_service_rounded, color: Colors.blue),
                      ),
                      title: TextFormField(
                        initialValue: machine.name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        decoration: const InputDecoration(
                          hintText: 'Nama mesin cuci...',
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onChanged: (val) {
                          _setupWashingMachines[idx] = MachineModel(
                            id: machine.id,
                            name: val,
                            machineType: 'cuci',
                            url: machine.url,
                            key: machine.key,
                            createdAt: machine.createdAt,
                          );
                        },
                      ),
                      subtitle: Text(
                        isManual ? 'Mesin fisik / manual' : 'Key ThinQ: ${machine.key}',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isManual ? Colors.grey.shade100 : Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              isManual ? 'MANUAL' : 'LG THINQ',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: isManual ? Colors.grey.shade700 : Colors.blue.shade700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Arrow Up
                          IconButton(
                            icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: idx == 0
                                ? null
                                : () {
                                    setState(() {
                                      final temp = _setupWashingMachines[idx];
                                      _setupWashingMachines[idx] = _setupWashingMachines[idx - 1];
                                      _setupWashingMachines[idx - 1] = temp;
                                    });
                                  },
                          ),
                          const SizedBox(width: 8),
                          // Arrow Down
                          IconButton(
                            icon: const Icon(Icons.arrow_downward_rounded, size: 18),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: idx == _setupWashingMachines.length - 1
                                ? null
                                : () {
                                    setState(() {
                                      final temp = _setupWashingMachines[idx];
                                      _setupWashingMachines[idx] = _setupWashingMachines[idx + 1];
                                      _setupWashingMachines[idx + 1] = temp;
                                    });
                                  },
                          ),
                          const SizedBox(width: 12),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                            onPressed: () {
                              setState(() {
                                _setupWashingMachines.removeAt(idx);
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildStepDryers() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Pengaturan Mesin Pengering',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Urutkan dengan panah, ganti nama, hapus, atau tambahkan mesin pengering manual.',
                    style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _isFetchingMachines ? null : () => _fetchBardiDevices(forceOverwrite: true),
                  icon: _isFetchingMachines
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.sync_rounded, size: 16),
                  label: const Text('Ambil Otomatis', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _showAddDryerDialog,
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Tambah Manual', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: successColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_setupDryers.isEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.outlet_rounded, size: 48, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  const Text(
                    'Belum ada mesin pengering terdaftar.',
                    style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Klik "Ambil Otomatis" untuk menarik data smart plug dari Bardi Tuya.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: Scrollbar(
              controller: _dryScrollController,
              thumbVisibility: true,
              child: ListView.builder(
                controller: _dryScrollController,
                itemCount: _setupDryers.length,
                itemBuilder: (context, idx) {
                  final machine = _setupDryers[idx];
                  final isManual = machine.key == 'manual';

                  return Card(
                    key: ValueKey('dry_${machine.url}_$idx'),
                    margin: const EdgeInsets.only(bottom: 8, right: 16),
                    elevation: 1,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      leading: CircleAvatar(
                        backgroundColor: Colors.orange.shade50,
                        child: const Icon(Icons.outlet_rounded, color: Colors.orange),
                      ),
                      title: TextFormField(
                        initialValue: machine.name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        decoration: const InputDecoration(
                          hintText: 'Nama mesin pengering...',
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onChanged: (val) {
                          _setupDryers[idx] = MachineModel(
                            id: machine.id,
                            name: val,
                            machineType: 'pengering',
                            url: machine.url,
                            key: machine.key,
                            createdAt: machine.createdAt,
                          );
                        },
                      ),
                      subtitle: Text(
                        isManual
                            ? 'Mesin fisik / manual'
                            : 'ID Perangkat: ${machine.url.substring(0, machine.url.length > 10 ? 10 : machine.url.length)}...',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isManual ? Colors.grey.shade100 : Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              isManual ? 'MANUAL' : 'BARDI TUYA',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: isManual ? Colors.grey.shade700 : Colors.orange.shade800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Arrow Up
                          IconButton(
                            icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: idx == 0
                                ? null
                                : () {
                                    setState(() {
                                      final temp = _setupDryers[idx];
                                      _setupDryers[idx] = _setupDryers[idx - 1];
                                      _setupDryers[idx - 1] = temp;
                                    });
                                  },
                          ),
                          const SizedBox(width: 8),
                          // Arrow Down
                          IconButton(
                            icon: const Icon(Icons.arrow_downward_rounded, size: 18),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: idx == _setupDryers.length - 1
                                ? null
                                : () {
                                    setState(() {
                                      final temp = _setupDryers[idx];
                                      _setupDryers[idx] = _setupDryers[idx + 1];
                                      _setupDryers[idx + 1] = temp;
                                    });
                                  },
                          ),
                          const SizedBox(width: 12),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                            onPressed: () {
                              setState(() {
                                _setupDryers.removeAt(idx);
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }

  void _showAddWashingMachineDialog() {
    String name = '';
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Tambah Mesin Cuci Manual', style: TextStyle(fontWeight: FontWeight.bold)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Nama Mesin Cuci', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextField(
                decoration: InputDecoration(
                  hintText: 'Contoh: Mesin Cuci Manual 4',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onChanged: (val) => name = val,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: primaryColor, foregroundColor: Colors.white),
              onPressed: () {
                if (name.trim().isEmpty) return;
                setState(() {
                  _setupWashingMachines.add(MachineModel(
                    name: name.trim(),
                    machineType: 'cuci',
                    url: '',
                    key: 'manual',
                    createdAt: DateTime.now(),
                  ));
                });
                Navigator.pop(context);
              },
              child: const Text('Tambah'),
            ),
          ],
        );
      },
    );
  }

  void _showAddDryerDialog() {
    String name = '';
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Tambah Pengering Manual', style: TextStyle(fontWeight: FontWeight.bold)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Nama Pengering', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextField(
                decoration: InputDecoration(
                  hintText: 'Contoh: Mesin Pengering Manual 3',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onChanged: (val) => name = val,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: primaryColor, foregroundColor: Colors.white),
              onPressed: () {
                if (name.trim().isEmpty) return;
                setState(() {
                  _setupDryers.add(MachineModel(
                    name: name.trim(),
                    machineType: 'pengering',
                    url: '',
                    key: 'manual',
                    createdAt: DateTime.now(),
                  ));
                });
                Navigator.pop(context);
              },
              child: const Text('Tambah'),
            ),
          ],
        );
      },
    );
  }

  // --- Step 4 View: Bardi Tuya Cloud ---
  Widget _buildStepBardi() {
    return Scrollbar(
      controller: _bardiScrollController,
      thumbVisibility: true,
      child: ListView(
        controller: _bardiScrollController,
        shrinkWrap: true,
        children: [
          const Text(
            'Integrasi Mesin Pengering Bardi Tuya',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
          ),
          const SizedBox(height: 4),
          const Text(
            'Masukkan kredensial API Tuya Developer Anda untuk menghubungkan stopkontak pintar Bardi.',
            style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 16),
          
          // Complete Guide Box
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Panduan Setup Bardi Tuya',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  final uri = Uri.parse('https://iot.tuya.com');
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                icon: const Icon(Icons.open_in_browser_rounded, size: 14, color: Colors.white),
                label: const Text('Buka Portal Tuya IoT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF5722), // Orange/Tuya Color
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildTutorialGuide([
            'Buka Tuya Developer Portal dengan menekan tombol "Buka Portal Tuya IoT" di atas.',
            'Login atau daftar akun developer baru, lalu masuk ke tab Cloud -> Development.',
            'Buat project baru (Create Cloud Project), pilih region "Western America" / "Asia".',
            'Buka project tersebut, salin nilai "Access ID" dan "Access Secret" ke input di bawah.',
            'Masuk ke tab "Link Tuya App", scan QR code menggunakan aplikasi Smart Life / Tuya Smart di HP Kakak.',
            'Buka profil aplikasi Smart Life di HP untuk melihat "User ID" akun Anda, lalu isi ke kolom UID di bawah.',
            'Klik tombol "Hubungkan & Sinkronisasi Perangkat" untuk mendeteksi stopkontak pintar Anda.'
          ]),
          _buildTextField('Access ID (Client ID)', _tuyaAccessIdCtrl, icon: Icons.vpn_key_rounded),
          const SizedBox(height: 16),
          _buildTextField('Access Secret (Client Secret)', _tuyaAccessSecretCtrl, icon: Icons.lock_outline_rounded),
          const SizedBox(height: 16),
          _buildTextField('Tuya App UID (User ID dari aplikasi Smart Life/Tuya)', _tuyaAppUidCtrl, icon: Icons.person_outline_rounded),
          const SizedBox(height: 16),
          _buildTextField('Endpoint API', _tuyaEndpointCtrl, icon: Icons.dns_rounded),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(
                _isBardiConnected ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                color: _isBardiConnected ? Colors.green : Colors.blue.shade600,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                _isBardiConnected ? 'Koneksi Bardi Tuya Aktif & Terhubung' : 'Belum Terhubung ke Bardi Tuya Cloud',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _isBardiConnected ? Colors.green : Colors.blue.shade700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: _isBardiConnected ? Colors.green : primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _isLoading ? null : _testBardi,
            icon: _isLoading 
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Icon(_isBardiConnected ? Icons.cloud_done_rounded : Icons.sync_rounded),
            label: Text(
              _isBardiConnected ? 'Tes Ulang Sinkronisasi' : 'Hubungkan & Sinkronisasi Perangkat',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  // --- Step 1 View: Profile & Admin ---
  Widget _buildStep1() {
    return Form(
      key: _formKey1,
      child: ListView(
        shrinkWrap: true,
        children: [
          const Text(
            'Informasi Toko & Akun Owner',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
          ),
          const SizedBox(height: 4),
          const Text(
            'Masukkan detail identitas laundry Anda dan buat pin admin utama.',
            style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _buildTextField('Nama Toko Laundry', _bizNameCtrl, icon: Icons.storefront_rounded),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildTextField('Nomor Telp Toko', _bizPhoneCtrl, icon: Icons.phone_rounded),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildTextField('Alamat Lengkap Toko', _bizAddressCtrl, icon: Icons.location_on_rounded),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),
          const Text(
            'Kredensial Owner (Super Admin)',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
          ),
          const SizedBox(height: 12),
          _buildTextField(
            'Username Admin', 
            _adminUsernameCtrl, 
            icon: Icons.person_rounded,
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Username Admin wajib diisi';
              if (v.contains(' ')) return 'Username tidak boleh mengandung spasi';
              return null;
            }
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildPasswordField('Password Admin', _adminPasswordCtrl),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildPasswordField('Konfirmasi Password Admin', _adminPasswordConfirmCtrl, isConfirm: true),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- Step 2 View: Printer thermal ---
  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Sambungkan Printer Thermal Kasir',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                ),
                SizedBox(height: 4),
                Text(
                  'Sambungkan printer thermal struk belanja via Bluetooth.',
                  style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                ),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: Colors.blue),
              onPressed: _scanPrinters,
              tooltip: 'Pindai Perangkat',
            )
          ],
        ),
        const SizedBox(height: 20),
        if (!_isBluetoothEnabled)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                Icon(Icons.bluetooth_disabled_rounded, color: Colors.amber.shade800),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Bluetooth terdeteksi tidak aktif. Pastikan Bluetooth di PC Anda aktif dan izinkan akses bluetooth.',
                    style: TextStyle(fontSize: 13, color: Colors.black87),
                  ),
                ),
              ],
            ),
          )
        else if (_isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_printerDevices.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.bluetooth_searching_rounded, size: 48, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  const Text('Tidak ada printer bluetooth terdeteksi.', style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: _scanPrinters,
                    child: const Text('Cari Perangkat'),
                  )
                ],
              ),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              itemCount: _printerDevices.length,
              itemBuilder: (context, i) {
                final d = _printerDevices[i];
                final isConnected = _selectedPrinterMac == d.macAdress;

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    border: Border.all(color: isConnected ? primaryColor : Colors.grey.shade200),
                    borderRadius: BorderRadius.circular(10),
                    color: Colors.white,
                  ),
                  child: ListTile(
                    leading: Icon(Icons.print_rounded, color: isConnected ? primaryColor : Colors.grey),
                    title: Text(d.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(d.macAdress),
                    trailing: isConnected
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.check_circle, color: Colors.green),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.grey.shade200,
                                  foregroundColor: Colors.black87,
                                ),
                                icon: const Icon(Icons.print, size: 14),
                                label: const Text('Test Print', style: TextStyle(fontSize: 12)),
                                onPressed: _printTestPage,
                              ),
                            ],
                          )
                        : _isConnectingPrinter
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: primaryColor,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: () => _connectPrinter(d.macAdress, d.name),
                                child: const Text('Sambungkan'),
                              ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  // --- Step 3 View: LG ThinQ Cloud ---
  Widget _buildStep3() {
    return Scrollbar(
      controller: _thinqScrollController,
      thumbVisibility: true,
      child: ListView(
        controller: _thinqScrollController,
        shrinkWrap: true,
        children: [
          const Text(
            'Integrasi Mesin LG ThinQ Cloud',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
          ),
          const SizedBox(height: 4),
          const Text(
            'Masukkan akun Personal Access Token (PAT) LG ThinQ Anda untuk memonitor mesin otomatis.',
            style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 16),
          
          // Complete Guide Box
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Panduan Setup LG ThinQ',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  final uri = Uri.parse('https://connect-pat.lgthinq.com');
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                icon: const Icon(Icons.open_in_browser_rounded, size: 14, color: Colors.white),
                label: const Text('Buka Portal LG Connect', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFC62828), // LG Red
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildTutorialGuide([
            'Buka portal LG ThinQ Connect dengan menekan tombol "Buka Portal LG Connect" di atas.',
            'Login menggunakan akun LG ThinQ Anda yang terdaftar pada mesin cuci/pengering.',
            'Di dasbor developer LG, klik tombol "Create PAT" (Personal Access Token).',
            'Salin kode Token PAT yang dihasilkan (formatnya berawalan: thinqpat_...).',
            'Kembali ke aplikasi kasir ini, lalu tempel kode token ke kolom input di bawah.',
            'Klik tombol "Hubungkan & Tes Sinkronisasi" untuk memverifikasi koneksi.'
          ]),
          Row(
            children: [
              Expanded(
                child: _buildTextField('Negara', _countryCtrl, icon: Icons.flag_rounded),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildTextField('Bahasa', _langCtrl, icon: Icons.language_rounded),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildTextField(
            'LG ThinQ PAT Token', 
            _patTokenCtrl, 
            icon: Icons.key_rounded,
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Token PAT diperlukan';
              return null;
            }
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(
                _isThinqConnected ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                color: _isThinqConnected ? Colors.green : Colors.blue.shade600,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                _isThinqConnected ? 'Koneksi LG ThinQ Aktif & Terhubung' : 'Belum Terhubung ke Cloud LG ThinQ',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _isThinqConnected ? Colors.green : Colors.blue.shade700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: _isThinqConnected ? Colors.green : primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _isLoading ? null : _testThinq,
            icon: _isLoading 
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Icon(_isThinqConnected ? Icons.cloud_done_rounded : Icons.sync_rounded),
            label: Text(
              _isThinqConnected ? 'Tes Ulang Sinkronisasi' : 'Hubungkan & Tes Sinkronisasi',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  // --- Step 4 View: WhatsApp Setup ---
  Widget _buildStep4() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Aktivasi Chatbot WhatsApp Toko',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
        ),
        const SizedBox(height: 4),
        const Text(
          'Scan QR Code menggunakan aplikasi WhatsApp di HP Kasir untuk mengaktifkan chatbot auto-reply.',
          style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 24),
        if (_isWaConnected)
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle_rounded, size: 64, color: Colors.green),
                  const SizedBox(height: 16),
                  const Text(
                    'WhatsApp Berhasil Terhubung!',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Chatbot auto-reply WhatsApp Anda sekarang aktif.',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_waQrBase64 != null)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade200),
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.white,
                      ),
                      child: Image.memory(
                        base64Decode(_waQrBase64!),
                        width: 200,
                        height: 200,
                      ),
                    )
                  else
                    Container(
                      width: 200,
                      height: 200,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade200),
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.grey.shade50,
                      ),
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                  const SizedBox(height: 16),
                  Text(
                    _waQrMessage ?? 'Mengambil QR Code WhatsApp...',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: _fetchWaStatus,
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('Refresh QR'),
                  )
                ],
              ),
            ),
          ),
      ],
    );
  }

  // --- Generic Field Builders ---
  Widget _buildTextField(String label, TextEditingController ctrl, {IconData? icon, String? Function(String?)? validator}) {
    return TextFormField(
      controller: ctrl,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: icon != null ? Icon(icon, size: 20) : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      ),
      validator: validator ?? (val) {
        if (val == null || val.trim().isEmpty) return '$label wajib diisi';
        return null;
      },
    );
  }

  Widget _buildPasswordField(String label, TextEditingController ctrl, {bool isConfirm = false}) {
    return TextFormField(
      controller: ctrl,
      obscureText: true,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.lock_rounded, size: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      ),
      validator: (val) {
        if (val == null || val.isEmpty) return '$label wajib diisi';
        if (val.contains(' ')) return 'Password tidak boleh mengandung spasi';
        if (val.length < 5) return 'Password minimal harus 5 karakter';
        if (isConfirm && val != _adminPasswordCtrl.text) return 'Konfirmasi Password tidak cocok';
        return null;
      },
    );
  }

  Widget _buildTutorialGuide(List<String> steps) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF), // soft blue background
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.info_outline_rounded, color: Color(0xFF2563EB), size: 20),
              SizedBox(width: 8),
              Text(
                'Langkah Panduan Setup (Tutorial):',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E3A8A),
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...steps.asMap().entries.map((entry) {
            final idx = entry.key + 1;
            final text = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: Color(0xFF2563EB),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$idx',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      text,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF1E3A8A),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: SafeArea(
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 800, maxHeight: 650),
            margin: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                )
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Header & Step nodes
                _buildStepIndicator(),
                // 2. Main content area
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: _buildStepContent(),
                  ),
                ),
                // 3. Navigation Footer
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    border: Border(top: BorderSide(color: Colors.grey.shade100)),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Back Button
                      if (_currentStep > 0)
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: _isLoading ? null : _prevStep,
                          icon: const Icon(Icons.arrow_back_rounded, size: 18),
                          label: const Text('Sebelumnya'),
                        )
                      else
                        const SizedBox(),
                      
                      // Next/Finish Button
                      Builder(
                        builder: (context) {
                          bool isEnabled = true;
                          if (_currentStep == 1) {
                            isEnabled = _isThinqConnected;
                          } else if (_currentStep == 2) {
                            isEnabled = true; // Always enabled for editing washers
                          } else if (_currentStep == 3) {
                            isEnabled = _isBardiConnected;
                          } else if (_currentStep == 4) {
                            isEnabled = true; // Always enabled for editing dryers
                          } else if (_currentStep == 5) {
                            isEnabled = _isWaConnected;
                          } else if (_currentStep == 6) {
                            isEnabled = _selectedPrinterMac.isNotEmpty;
                          }

                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_currentStep > 0) ...[
                                TextButton(
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                                  ),
                                  onPressed: _isLoading ? null : () {
                                    if (_currentStep < 6) {
                                      _nextStep();
                                    } else {
                                      _completeSetup();
                                    }
                                  },
                                  child: Text(
                                    _currentStep == 6 ? 'Lewati & Selesai' : 'Lewati',
                                    style: const TextStyle(
                                      color: Color(0xFF64748B),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                              ],
                              _currentStep < 6
                                  ? ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: isEnabled ? primaryColor : Colors.grey.shade300,
                                        foregroundColor: isEnabled ? Colors.white : Colors.grey.shade500,
                                        elevation: isEnabled ? 2 : 0,
                                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                      onPressed: (_isLoading || !isEnabled) ? null : _nextStep,
                                      icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                                      label: const Text('Berikutnya'),
                                    )
                                  : ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: isEnabled ? successColor : Colors.grey.shade300,
                                        foregroundColor: isEnabled ? Colors.white : Colors.grey.shade500,
                                        elevation: isEnabled ? 2 : 0,
                                        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                      onPressed: (_isLoading || !isEnabled) ? null : _completeSetup,
                                      icon: const Icon(Icons.done_all_rounded, size: 18),
                                      label: const Text('Selesai Setup'),
                                    ),
                            ],
                          );
                        }
                      ),
                    ],
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
