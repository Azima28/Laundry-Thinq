import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:laundry_apps/database/models/database_helper.dart';
import 'package:laundry_apps/database/models/machine_model.dart';
import 'package:laundry_apps/services/backend_services_manager.dart';

class LgThinqSettingsScreen extends StatefulWidget {
  const LgThinqSettingsScreen({Key? key}) : super(key: key);

  @override
  _LgThinqSettingsScreenState createState() => _LgThinqSettingsScreenState();
}

class _LgThinqSettingsScreenState extends State<LgThinqSettingsScreen> {
  final TextEditingController _countryCtrl = TextEditingController(text: 'ID');
  final TextEditingController _langCtrl = TextEditingController(text: 'id-ID');
  final TextEditingController _patTokenCtrl = TextEditingController();
  final TextEditingController _intervalIdleCtrl = TextEditingController(text: '300');
  final TextEditingController _intervalBookingCtrl = TextEditingController(text: '180');
  final TextEditingController _intervalRunningHighCtrl = TextEditingController(text: '300');
  final TextEditingController _intervalRunningLowCtrl = TextEditingController(text: '120');
  final TextEditingController _washerDurationCtrl = TextEditingController(text: '40');

  bool _isLoading = false;
  bool _isConnected = false;
  String _apiBaseUrl = 'http://localhost:5001/';
  int _washerDurationMinutes = 40;

  List<Map<String, dynamic>> _machinesList = [];
  bool _isMachinesLoading = false;
  List<Map<String, dynamic>> _scannedThinqDevices = [];
  bool _isScanningThinq = false;
  String _selectedCategoryFilter = 'all'; // 'all', 'cuci', 'pengering'

  final Color primaryColor = const Color(0xFF4E80EE);
  final Color lgeColor = const Color(0xFFC62828); // Magenta/Red LGE
  final Color backgroundColor = const Color(0xFFF8FAFC);

  @override
  void initState() {
    super.initState();
    _loadMachines();
    _loadBaseUrlAndStatus();
  }

  @override
  void dispose() {
    _countryCtrl.dispose();
    _langCtrl.dispose();
    _patTokenCtrl.dispose();
    _intervalIdleCtrl.dispose();
    _intervalBookingCtrl.dispose();
    _intervalRunningHighCtrl.dispose();
    _intervalRunningLowCtrl.dispose();
    _washerDurationCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadBaseUrlAndStatus() async {
    setState(() {
      _apiBaseUrl = 'http://localhost:5001/';
    });
    _fetchStatus();
  }

  Future<void> _autoDetectAndRegisterMachines() async {
    try {
      final response = await http.get(Uri.parse('${_apiBaseUrl}api/lg/devices')).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> devices = data['devices'] ?? [];
        if (devices.isNotEmpty) {
          final db = DatabaseHelper.instance;
          final List<MachineModel> existingMachines = await db.getAllMachines();
          final Set<String> existingUrls = existingMachines.map((m) => m.url).toSet();

          int addedCount = 0;
          for (var devName in devices) {
            final String targetName = devName.toString().replaceAll(' ', '_');
            if (!existingUrls.contains(targetName)) {
              final String displayName = targetName.replaceAll('_', ' ');
              final String nameLower = displayName.toLowerCase();
              String key = 'cuci';
              if (nameLower.contains('dryer') ||
                  nameLower.contains('pengering') ||
                  nameLower.contains('dry') ||
                  nameLower.contains('drying') ||
                  nameLower.contains('kering')) {
                key = 'pengering';
              }

              final newMachine = MachineModel(
                name: displayName,
                url: targetName,
                key: key,
                createdAt: DateTime.now(),
              );
              await db.insertMachine(newMachine);
              addedCount++;
            }
          }

          if (addedCount > 0) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Auto-detect: Berhasil mendaftarkan $addedCount mesin baru ke database kasir.'),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('[LgThinqSettings] Gagal auto-detect mesin: $e');
    }
  }

  Future<void> _fetchStatus() async {
    setState(() => _isLoading = true);
    try {
      await BackendServicesManager.instance.isBackendReady(timeout: const Duration(seconds: 4));
      final response = await http.get(Uri.parse('${_apiBaseUrl}api/lg/status')).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _isConnected = data['connected'] ?? false;
          _countryCtrl.text = data['country'] ?? 'ID';
          _langCtrl.text = data['language'] ?? 'id-ID';
          _patTokenCtrl.text = data['pat_token'] ?? '';
          _intervalIdleCtrl.text = (data['interval_idle'] ?? 300).toString();
          _intervalBookingCtrl.text = (data['interval_booking'] ?? 180).toString();
          _intervalRunningHighCtrl.text = (data['interval_running_high'] ?? 300).toString();
          _intervalRunningLowCtrl.text = (data['interval_running_low'] ?? 120).toString();
          _washerDurationMinutes = (data['washer_duration_minutes'] ?? 40);
          _washerDurationCtrl.text = _washerDurationMinutes.toString();
        });

        if (_isConnected) {
          await _autoDetectAndRegisterMachines();
        }
      }
    } catch (e) {
      debugPrint('[LgThinqSettings] Gagal memuat status: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isLoading = true);
    try {
      await BackendServicesManager.instance.isBackendReady(timeout: const Duration(seconds: 4));
      final response = await http.post(
        Uri.parse('${_apiBaseUrl}api/lg/settings'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'country': _countryCtrl.text.trim(),
          'language': _langCtrl.text.trim(),
          'pat_token': _patTokenCtrl.text.trim(),
          'interval_idle': int.tryParse(_intervalIdleCtrl.text.trim()) ?? 300,
          'interval_booking': int.tryParse(_intervalBookingCtrl.text.trim()) ?? 180,
          'interval_running_high': int.tryParse(_intervalRunningHighCtrl.text.trim()) ?? 300,
          'interval_running_low': int.tryParse(_intervalRunningLowCtrl.text.trim()) ?? 120,
          'washer_duration_minutes': int.tryParse(_washerDurationCtrl.text.trim()) ?? 40,
        }),
      );
      if (response.statusCode == 200) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('washer_duration_minutes', int.tryParse(_washerDurationCtrl.text.trim()) ?? 40);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Pengaturan LG ThinQ & Durasi Siklus berhasil disimpan.'), backgroundColor: Colors.green),
          );
        }
        _fetchStatus();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menyimpan: Status ${response.statusCode}'), backgroundColor: Colors.orange),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text('Integrasi LG ThinQ', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator())
          : Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Left Panel: Step by step instruction (360px)
                Container(
                  width: 360,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(right: BorderSide(color: Color(0xFFE2E8F0))),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Panduan Integrasi LG (PAT)',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                        ),
                        const SizedBox(height: 16),
                        _buildStepItem(
                          step: '1',
                          title: 'Buka Portal LG Connect',
                          desc: 'Buka portal resmi LG ThinQ Connect PAT di browser Anda: connect-pat.lgthinq.com.',
                        ),
                        _buildStepItem(
                          step: '2',
                          title: 'Dapatkan Token PAT',
                          desc: 'Login dengan akun LG ThinQ Anda, lalu generate Personal Access Token (PAT) baru dan salin tokennya.',
                        ),
                        _buildStepItem(
                          step: '3',
                          title: 'Tempel & Simpan',
                          desc: 'Tempel token PAT (diawali dengan thinqpat_...) pada form di sebelah kanan, lalu klik "Simpan Pengaturan".',
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              final uri = Uri.parse('https://connect-pat.lgthinq.com');
                              if (await canLaunchUrl(uri)) {
                                await launchUrl(uri, mode: LaunchMode.externalApplication);
                              }
                            },
                            icon: const Icon(Icons.open_in_browser_rounded, color: Colors.white),
                            label: const Text('Buka Portal LG Connect', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryColor,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // 2. Right Panel: Form and controls (Expanded with TabBar)
                Expanded(
                  child: DefaultTabController(
                    length: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            decoration: const BoxDecoration(
                              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
                            ),
                            child: const TabBar(
                              labelColor: Color(0xFF4E80EE),
                              unselectedLabelColor: Color(0xFF64748B),
                              indicatorColor: Color(0xFF4E80EE),
                              indicatorWeight: 3,
                              labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              tabs: [
                                Tab(
                                  icon: Icon(Icons.cloud_queue_rounded, size: 18),
                                  text: 'Koneksi Cloud LG',
                                ),
                                Tab(
                                  icon: Icon(Icons.playlist_add_rounded, size: 18),
                                  text: 'Daftar & Pemetaan Mesin',
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Expanded(
                            child: TabBarView(
                              children: [
                                _buildCloudConnectionTab(),
                                _buildMachineMappingTab(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),              ],
            ),
    );
  }

  Widget _buildStepItem({required String step, required String title, required String desc}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: primaryColor.withOpacity(0.1),
            foregroundColor: primaryColor,
            radius: 16,
            child: Text(step, style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Color(0xFF1E293B))),
                const SizedBox(height: 4),
                Text(
                  desc,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600], height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }



  Widget _buildStatusBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: _isConnected ? Colors.green.withOpacity(0.1) : Colors.grey[200],
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _isConnected ? Colors.green : Colors.grey[400]!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            backgroundColor: _isConnected ? Colors.green : Colors.grey,
            radius: 4,
          ),
          const SizedBox(width: 8),
          Text(
            _isConnected ? 'TERHUBUNG' : 'TERPUTUS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: _isConnected ? Colors.green : Colors.grey[700],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadMachines() async {
    setState(() => _isMachinesLoading = true);
    try {
      final response = await http.get(Uri.parse('${_apiBaseUrl}api/machines')).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          _machinesList = List<Map<String, dynamic>>.from(data);
        });
      }
    } catch (e) {
      debugPrint('[LgThinqSettings] Gagal memuat mesin: $e');
    } finally {
      setState(() => _isMachinesLoading = false);
    }
  }

  Future<void> _scanThinqDevices() async {
    setState(() => _isScanningThinq = true);
    try {
      final response = await http.get(Uri.parse('${_apiBaseUrl}api/thinq/discover')).timeout(const Duration(seconds: 25));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          _scannedThinqDevices = List<Map<String, dynamic>>.from(data);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Berhasil memindai ${data.length} perangkat LG ThinQ.'), backgroundColor: Colors.green),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal memindai perangkat LG ThinQ. Cek kredensial Anda.'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error memindai: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isScanningThinq = false);
    }
  }

  Future<void> _saveMachine(String name, String url, String key, {int? id}) async {
    setState(() => _isMachinesLoading = true);
    try {
      final response = await http.post(
        Uri.parse('${_apiBaseUrl}api/machines'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'name': name,
          'url': url,
          'key': key,
          if (id != null) 'id': id,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mesin berhasil disimpan.'), backgroundColor: Colors.green),
        );
        _loadMachines();
      } else {
        final err = json.decode(response.body)['error'] ?? 'Gagal menyimpan';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $err'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isMachinesLoading = false);
    }
  }

  Future<void> _deleteMachine(int id) async {
    setState(() => _isMachinesLoading = true);
    try {
      final response = await http.delete(
        Uri.parse('${_apiBaseUrl}api/machines/$id'),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mesin berhasil dihapus.'), backgroundColor: Colors.green),
        );
        _loadMachines();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal menghapus mesin.'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isMachinesLoading = false);
    }
  }

  void _showAddMachineDialog() {
    final nameCtrl = TextEditingController();
    String key = _selectedCategoryFilter == 'pengering' ? 'pengering' : 'cuci';
    String source = 'manual'; // 'manual' or 'thinq'
    String? selectedThinqId;

    final Set<String> usedUrls = _machinesList.map((m) => m['url'].toString()).toSet();
    final availableThinq = _scannedThinqDevices.where((d) {
      final String alias = d['alias'].toString();
      return !usedUrls.contains(alias);
    }).toList();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Tambah Mesin Baru', style: TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (source == 'manual') ...[
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nama Mesin (Kasir UI)',
                      hintText: 'e.g. Mesin Cuci A',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                DropdownButtonFormField<String>(
                  value: key,
                  decoration: const InputDecoration(
                    labelText: 'Jenis Mesin',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'cuci', child: Text('Mesin Cuci')),
                    DropdownMenuItem(value: 'pengering', child: Text('Mesin Pengering')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setModalState(() => key = val);
                    }
                  },
                ),
                const SizedBox(height: 16),
                const Text('Sumber Integrasi:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF475569))),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: RadioListTile<String>(
                        title: const Text('Manual', style: TextStyle(fontSize: 12)),
                        value: 'manual',
                        groupValue: source,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (val) {
                          if (val != null) {
                            setModalState(() => source = val);
                          }
                        },
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<String>(
                        title: const Text('LG ThinQ', style: TextStyle(fontSize: 12)),
                        value: 'thinq',
                        groupValue: source,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (val) {
                          if (val != null) {
                            setModalState(() => source = val);
                          }
                        },
                      ),
                    ),
                  ],
                ),
                if (source == 'thinq') ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _isScanningThinq
                            ? const Center(child: CircularProgressIndicator())
                            : ElevatedButton.icon(
                                onPressed: () async {
                                  await _scanThinqDevices();
                                  setModalState(() {});
                                },
                                icon: const Icon(Icons.refresh_rounded, color: Colors.white, size: 16),
                                label: const Text('Pindai LG ThinQ', style: TextStyle(color: Colors.white, fontSize: 12)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: lgeColor,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  availableThinq.isEmpty
                      ? const Text(
                          'Semua perangkat LG ThinQ yang terpindai sudah dipetakan.',
                          style: TextStyle(fontSize: 11, color: Colors.orange, fontStyle: FontStyle.italic),
                        )
                      : DropdownButtonFormField<String>(
                          value: selectedThinqId,
                          decoration: const InputDecoration(
                            labelText: 'Pilih Perangkat LG ThinQ',
                            border: OutlineInputBorder(),
                          ),
                          items: availableThinq.map((d) {
                            return DropdownMenuItem<String>(
                              value: d['alias'].toString(),
                              child: Text('${d['alias']} (${d['deviceType']})', style: const TextStyle(fontSize: 12)),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setModalState(() => selectedThinqId = val);
                            }
                          },
                        ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
              ),
              onPressed: () {
                String name = '';
                if (source == 'manual') {
                  name = nameCtrl.text.trim();
                  if (name.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Nama mesin wajib diisi')),
                    );
                    return;
                  }
                } else {
                  if (selectedThinqId == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Harap pilih perangkat LG ThinQ')),
                    );
                    return;
                  }
                  dynamic matchingThinq;
                  for (final d in availableThinq) {
                    if (d['alias'].toString() == selectedThinqId) {
                      matchingThinq = d;
                      break;
                    }
                  }
                  name = matchingThinq != null ? matchingThinq['alias'].toString() : selectedThinqId!.replaceAll('_', ' ');
                }
                final url = (source == 'thinq' && selectedThinqId != null) ? selectedThinqId! : '-';
                _saveMachine(name, url, key);
                Navigator.pop(ctx);
              },
              child: const Text('Simpan', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditMachineDialog(Map<String, dynamic> machine) {
    final nameCtrl = TextEditingController(text: machine['name']);
    final int id = machine['id'] as int;
    String key = machine['key'] ?? 'cuci';
    final initialUrl = machine['url'].toString();
    String source = initialUrl == '-' ? 'manual' : 'thinq';
    String? selectedThinqId = initialUrl == '-' ? null : initialUrl;

    final Set<String> usedUrls = _machinesList
        .where((m) => m['id'] != id)
        .map((m) => m['url'].toString())
        .toSet();
    final availableThinq = _scannedThinqDevices.where((d) {
      final String alias = d['alias'].toString();
      return !usedUrls.contains(alias) || alias == initialUrl;
    }).toList();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Edit Mesin', style: TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (source == 'manual') ...[
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nama Mesin (Kasir UI)',
                      hintText: 'e.g. Mesin Cuci A',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                DropdownButtonFormField<String>(
                  value: key,
                  decoration: const InputDecoration(
                    labelText: 'Jenis Mesin',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'cuci', child: Text('Mesin Cuci')),
                    DropdownMenuItem(value: 'pengering', child: Text('Mesin Pengering')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setModalState(() => key = val);
                    }
                  },
                ),
                const SizedBox(height: 16),
                const Text('Sumber Integrasi:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF475569))),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: RadioListTile<String>(
                        title: const Text('Manual', style: TextStyle(fontSize: 12)),
                        value: 'manual',
                        groupValue: source,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (val) {
                          if (val != null) {
                            setModalState(() => source = val);
                          }
                        },
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<String>(
                        title: const Text('LG ThinQ', style: TextStyle(fontSize: 12)),
                        value: 'thinq',
                        groupValue: source,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (val) {
                          if (val != null) {
                            setModalState(() => source = val);
                          }
                        },
                      ),
                    ),
                  ],
                ),
                if (source == 'thinq') ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _isScanningThinq
                            ? const Center(child: CircularProgressIndicator())
                            : ElevatedButton.icon(
                                onPressed: () async {
                                  await _scanThinqDevices();
                                  setModalState(() {});
                                },
                                icon: const Icon(Icons.refresh_rounded, color: Colors.white, size: 16),
                                label: const Text('Pindai LG ThinQ', style: TextStyle(color: Colors.white, fontSize: 12)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: lgeColor,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  availableThinq.isEmpty
                      ? const Text(
                          'Semua perangkat LG ThinQ yang terpindai sudah dipetakan.',
                          style: TextStyle(fontSize: 11, color: Colors.orange, fontStyle: FontStyle.italic),
                        )
                      : DropdownButtonFormField<String>(
                          value: (availableThinq.any((d) => d['alias'].toString() == selectedThinqId)) ? selectedThinqId : null,
                          decoration: const InputDecoration(
                            labelText: 'Pilih Perangkat LG ThinQ',
                            border: OutlineInputBorder(),
                          ),
                          items: availableThinq.map((d) {
                            return DropdownMenuItem<String>(
                              value: d['alias'].toString(),
                              child: Text('${d['alias']} (${d['deviceType']})', style: const TextStyle(fontSize: 12)),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setModalState(() => selectedThinqId = val);
                            }
                          },
                          hint: const Text('Pilih Perangkat ThinQ (Pindai jika kosong)', style: TextStyle(fontSize: 12)),
                        ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
              ),
              onPressed: () {
                String name = '';
                if (source == 'manual') {
                  name = nameCtrl.text.trim();
                  if (name.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Nama mesin wajib diisi')),
                    );
                    return;
                  }
                } else {
                  if (selectedThinqId == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Harap pilih perangkat LG ThinQ')),
                    );
                    return;
                  }
                  dynamic matchingThinq;
                  for (final d in availableThinq) {
                    if (d['alias'].toString() == selectedThinqId) {
                      matchingThinq = d;
                      break;
                    }
                  }
                  name = matchingThinq != null ? matchingThinq['alias'].toString() : selectedThinqId!.replaceAll('_', ' ');
                }
                final url = (source == 'thinq' && selectedThinqId != null) ? selectedThinqId! : '-';
                _saveMachine(name, url, key, id: machine['id'] as int);
                Navigator.pop(ctx);
              },
              child: const Text('Simpan', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCloudConnectionTab() {
    return SingleChildScrollView(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey[200]!),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.01), blurRadius: 10)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Status Koneksi Cloud',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                _buildStatusBadge(),
              ],
            ),
            const SizedBox(height: 24),
            const Divider(height: 1),
            const SizedBox(height: 24),
            
            // Credentials Section
            const Text('Konfigurasi Kredensial LG ThinQ (PAT)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF334155))),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _countryCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Kode Negara',
                      hintText: 'ID',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _langCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Kode Bahasa',
                      hintText: 'id-ID',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _patTokenCtrl,
              decoration: const InputDecoration(
                labelText: 'Token PAT Resmi (Personal Access Token)',
                hintText: 'thinqpat_...',
                border: OutlineInputBorder(),
                helperText: 'Dapatkan token PAT dari https://connect-pat.lgthinq.com',
              ),
            ),
            
            const SizedBox(height: 32),
            const Divider(height: 1),
            const SizedBox(height: 24),
            
            // Smart Intervals Section
            const Text('Pengaturan Interval Polling Pintar (Detik)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF334155))),
            const SizedBox(height: 6),
            const Text(
              'Interval ini digunakan untuk mengoptimalkan kuota request ke server LG agar aman dari rate-limit dan tetap responsif.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 20),
            
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Idle (Tidak Ada Pelanggan)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      const Text('Pemeriksaan berkala saat mesin standby.', style: TextStyle(fontSize: 11, color: Colors.grey)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _intervalIdleCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          hintText: '300',
                          border: OutlineInputBorder(),
                          suffixText: 'detik',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Booking (Baru Aktif)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      const Text('Pemeriksaan setelah kasir mengklik Mulai.', style: TextStyle(fontSize: 11, color: Colors.grey)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _intervalBookingCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          hintText: '180',
                          border: OutlineInputBorder(),
                          suffixText: 'detik',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Running (Sisa > 8 Menit)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      const Text('Pemeriksaan saat cucian masih lama.', style: TextStyle(fontSize: 11, color: Colors.grey)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _intervalRunningHighCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          hintText: '300',
                          border: OutlineInputBorder(),
                          suffixText: 'detik',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Running (Sisa 4-8 Menit)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      const Text('Pemeriksaan cepat saat hampir selesai.', style: TextStyle(fontSize: 11, color: Colors.grey)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _intervalRunningLowCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          hintText: '120',
                          border: OutlineInputBorder(),
                          suffixText: 'detik',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 32),
            const Divider(height: 1),
            const SizedBox(height: 24),

            // Washer Offline Fallback Cycle Duration Section
            const Text('Durasi Siklus Mesin Cuci (Offline Fallback)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF334155))),
            const SizedBox(height: 6),
            const Text(
              'Durasi timer hitung mundur saat mesin cuci beroperasi dalam mode offline (cloud ThinQ terputus atau mesin manual).',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [30, 35, 40, 45, 50, 60].map((dur) {
                final isSelected = _washerDurationMinutes == dur;
                return ChoiceChip(
                  label: Text(dur == 40 ? '$dur Menit (Standar)' : '$dur Menit'),
                  selected: isSelected,
                  selectedColor: primaryColor,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : const Color(0xFF334155),
                    fontWeight: FontWeight.bold,
                    fontSize: 12.5,
                  ),
                  onSelected: (selected) {
                    if (selected) {
                      setState(() {
                        _washerDurationMinutes = dur;
                        _washerDurationCtrl.text = dur.toString();
                      });
                    }
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                SizedBox(
                  width: 160,
                  child: TextField(
                    controller: _washerDurationCtrl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    decoration: const InputDecoration(
                      labelText: 'Custom Menit',
                      suffixText: 'Menit',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                    onChanged: (val) {
                      final p = int.tryParse(val.trim());
                      if (p != null && p > 0) {
                        setState(() {
                          _washerDurationMinutes = p;
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Text(
                    'Nilai ini menentukan batas estimasi selesai pencucian saat offline.',
                    style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 36),
            const Divider(height: 1),
            const SizedBox(height: 24),

            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ElevatedButton.icon(
                  onPressed: _saveSettings,
                  icon: const Icon(Icons.save_rounded, color: Colors.white),
                  label: const Text('Simpan Pengaturan', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryTab({
    required String label,
    required int count,
    required String keyName,
    required IconData icon,
    required Color activeColor,
  }) {
    final bool isSelected = _selectedCategoryFilter == keyName;
    return InkWell(
      onTap: () => setState(() => _selectedCategoryFilter = keyName),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withValues(alpha: 0.1) : Colors.grey[100],
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? activeColor : Colors.grey[300]!,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: isSelected ? activeColor : Colors.grey[600]),
            const SizedBox(width: 6),
            Text(
              '$label ($count)',
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                color: isSelected ? activeColor : Colors.grey[700],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMachineMappingTab() {
    final filteredMachines = _machinesList.where((m) {
      if (_selectedCategoryFilter == 'cuci') return m['key'] != 'pengering';
      if (_selectedCategoryFilter == 'pengering') return m['key'] == 'pengering';
      return true;
    }).toList();

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.01), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Daftar & Pemetaan Mesin Toko',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Kelola unit mesin cuci dan mesin pengering secara terpisah dan atur urutan tampilannya.',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, color: Color(0xFF64748B)),
                    onPressed: _loadMachines,
                    tooltip: 'Segarkan data',
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _showAddMachineDialog,
                    icon: const Icon(Icons.add_rounded, color: Colors.white, size: 18),
                    label: const Text('Tambah Mesin', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Category filter tabs
          Row(
            children: [
              _buildCategoryTab(
                label: 'Semua Mesin',
                count: _machinesList.length,
                keyName: 'all',
                icon: Icons.dashboard_customize_rounded,
                activeColor: primaryColor,
              ),
              const SizedBox(width: 8),
              _buildCategoryTab(
                label: 'Mesin Cuci',
                count: _machinesList.where((m) => m['key'] != 'pengering').length,
                keyName: 'cuci',
                icon: Icons.local_laundry_service_rounded,
                activeColor: const Color(0xFF2563EB),
              ),
              const SizedBox(width: 8),
              _buildCategoryTab(
                label: 'Mesin Pengering',
                count: _machinesList.where((m) => m['key'] == 'pengering').length,
                keyName: 'pengering',
                icon: Icons.wb_sunny_rounded,
                activeColor: const Color(0xFFEA580C),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 16),

          // Table header row (fixed)
          Container(
            color: Colors.grey[50],
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            child: const Row(
              children: [
                SizedBox(width: 56), // Spacer for up/down buttons
                Expanded(flex: 6, child: Text('NAMA MESIN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF64748B)))),
                Expanded(flex: 4, child: Text('JENIS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF64748B)))),
                Expanded(flex: 5, child: Text('INTEGRASI', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF64748B)))),
                Expanded(flex: 7, child: Text('THINQ ID / ALIAS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF64748B)))),
                Expanded(flex: 3, child: Align(alignment: Alignment.centerRight, child: Text('AKSI', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF64748B))))),
              ],
            ),
          ),
          const SizedBox(height: 8),

          Expanded(
            child: _isMachinesLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredMachines.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.local_laundry_service_outlined, size: 64, color: Colors.grey),
                            const SizedBox(height: 16),
                            Text(
                              _selectedCategoryFilter == 'cuci'
                                  ? 'Belum ada Mesin Cuci terdaftar.'
                                  : (_selectedCategoryFilter == 'pengering'
                                      ? 'Belum ada Mesin Pengering terdaftar.'
                                      : 'Belum ada mesin terdaftar.'),
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Klik tombol "Tambah Mesin" untuk mendaftarkan unit mesin.',
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: filteredMachines.length,
                        itemBuilder: (context, index) {
                          final m = filteredMachines[index];
                          final id = m['id'] as int;
                          final name = m['name'].toString();
                          final url = m['url'].toString();
                          final key = m['key'].toString();
                          final isManual = url == '-';

                          final origIndex = _machinesList.indexOf(m);

                          return Container(
                            key: ValueKey(id),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border(bottom: BorderSide(color: Colors.grey[100]!)),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                            child: Row(
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.arrow_upward_rounded, size: 16, color: Colors.blueGrey),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      onPressed: origIndex > 0
                                          ? () => _moveMachine(origIndex, origIndex - 1)
                                          : null,
                                      tooltip: 'Pindahkan ke atas',
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      icon: const Icon(Icons.arrow_downward_rounded, size: 16, color: Colors.blueGrey),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      onPressed: origIndex < _machinesList.length - 1
                                          ? () => _moveMachine(origIndex, origIndex + 1)
                                          : null,
                                      tooltip: 'Pindahkan ke bawah',
                                    ),
                                  ],
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  flex: 6,
                                  child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF1E293B))),
                                ),
                                Expanded(
                                  flex: 4,
                                  child: Row(
                                    children: [
                                      Icon(
                                        key == 'cuci' ? Icons.local_laundry_service_rounded : Icons.wb_sunny_rounded,
                                        size: 14,
                                        color: key == 'cuci' ? Colors.blue : Colors.orange,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(key == 'cuci' ? 'Cuci' : 'Pengering', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  flex: 5,
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: isManual ? Colors.grey[100] : lgeColor.withOpacity(0.06),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: isManual ? Colors.grey[300]! : lgeColor.withOpacity(0.2)),
                                      ),
                                      child: Text(
                                        isManual ? 'MANUAL' : 'LG THINQ',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: isManual ? Colors.grey[700] : lgeColor,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 7,
                                  child: Text(
                                    isManual ? '—' : url,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isManual ? Colors.grey[400] : const Color(0xFF334155),
                                      fontStyle: isManual ? FontStyle.italic : FontStyle.normal,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.edit_outlined, color: Colors.blue, size: 20),
                                        onPressed: () => _showEditMachineDialog(m),
                                        tooltip: 'Edit mesin',
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 20),
                                        onPressed: () {
                                          showDialog(
                                            context: context,
                                            builder: (ctx) => AlertDialog(
                                              title: const Text('Hapus Mesin'),
                                              content: Text('Apakah Anda yakin ingin menghapus mesin "$name" dari sistem?'),
                                              actions: [
                                                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
                                                ElevatedButton(
                                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                                  onPressed: () {
                                                    _deleteMachine(id);
                                                    Navigator.pop(ctx);
                                                  },
                                                  child: const Text('Hapus', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Future<void> _moveMachine(int oldIndex, int newIndex) async {
    setState(() {
      final item = _machinesList.removeAt(oldIndex);
      _machinesList.insert(newIndex, item);
    });

    // Kirim urutan baru ke backend API
    final List<int> idsList = _machinesList.map((m) => m['id'] as int).toList();
    try {
      final response = await http.post(
        Uri.parse('${_apiBaseUrl}api/machines/reorder'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'ids': idsList}),
      );
      if (response.statusCode != 200) {
        debugPrint('[LgThinqSettings] Gagal menyimpan susunan urutan mesin.');
      }
    } catch (e) {
      debugPrint('[LgThinqSettings] Error menyimpan susunan urutan: $e');
    }
  }
}
