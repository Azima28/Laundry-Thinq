import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../database/models/database_helper.dart';
import '../../database/models/machine_model.dart';

class BardiTuyaSettingsScreen extends StatefulWidget {
  const BardiTuyaSettingsScreen({Key? key}) : super(key: key);

  @override
  State<BardiTuyaSettingsScreen> createState() => _BardiTuyaSettingsScreenState();
}

class _BardiTuyaSettingsScreenState extends State<BardiTuyaSettingsScreen> {
  final _accessIdCtrl = TextEditingController();
  final _accessSecretCtrl = TextEditingController();
  final _appUidCtrl = TextEditingController();
  final _endpointCtrl = TextEditingController(text: 'https://openapi.tuyaus.com');

  bool _isLoading = false;
  bool _isConnected = false;
  String _apiBaseUrl = 'http://localhost:5001/';
  
  List<dynamic> _scannedPlugs = [];
  bool _isScanning = false;

  List<Map<String, dynamic>> _dryerMachinesList = [];
  bool _isMachinesLoading = false;

  final Color primaryColor = const Color(0xFF4E80EE);
  final Color tuyaColor = const Color(0xFFFF5500); // Orange Tuya
  final Color backgroundColor = const Color(0xFFF8FAFC);

  @override
  void initState() {
    super.initState();
    _loadBaseUrlAndStatus();
  }

  @override
  void dispose() {
    _accessIdCtrl.dispose();
    _accessSecretCtrl.dispose();
    _appUidCtrl.dispose();
    _endpointCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadBaseUrlAndStatus() async {
    setState(() {
      _apiBaseUrl = 'http://localhost:5001/';
    });
    await _fetchCredentialsAndStatus();
    await _loadDryerMachines();
  }

  Future<void> _fetchCredentialsAndStatus() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.get(Uri.parse('${_apiBaseUrl}api/tuya/settings')).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          setState(() {
            _accessIdCtrl.text = data['access_id'] ?? '';
            _accessSecretCtrl.text = data['access_secret'] ?? '';
            _appUidCtrl.text = data['app_uid'] ?? '';
            _endpointCtrl.text = data['endpoint'] ?? 'https://openapi.tuyaus.com';
            
            _isConnected = _accessIdCtrl.text.isNotEmpty && _accessSecretCtrl.text.isNotEmpty && _appUidCtrl.text.isNotEmpty;
          });
        }
      }
    } catch (e) {
      debugPrint('[BardiTuyaSettings] Error fetching credentials: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadDryerMachines() async {
    setState(() => _isMachinesLoading = true);
    try {
      final response = await http.get(Uri.parse('${_apiBaseUrl}api/machines')).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          _dryerMachinesList = List<Map<String, dynamic>>.from(data)
              .where((m) => m['key'] == 'pengering')
              .toList();
        });
      }
    } catch (e) {
      debugPrint('[BardiTuyaSettings] Error loading dryer machines: $e');
    } finally {
      setState(() => _isMachinesLoading = false);
    }
  }

  Future<void> _saveCredentials() async {
    final accessId = _accessIdCtrl.text.trim();
    final accessSecret = _accessSecretCtrl.text.trim();
    final appUid = _appUidCtrl.text.trim();
    final endpoint = _endpointCtrl.text.trim();

    if (accessId.isEmpty || accessSecret.isEmpty || appUid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Harap lengkapi semua kolom kredensial!'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final response = await http
          .post(
            Uri.parse('${_apiBaseUrl}api/tuya/settings'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'access_id': accessId,
              'access_secret': accessSecret,
              'app_uid': appUid,
              'endpoint': endpoint,
            }),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          setState(() => _isConnected = true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Kredensial Tuya Bardi berhasil disimpan.'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Gagal menyimpan: ${data['error']}'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Koneksi server error: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _syncAndScanDevices() async {
    final accessId = _accessIdCtrl.text.trim();
    final accessSecret = _accessSecretCtrl.text.trim();
    final appUid = _appUidCtrl.text.trim();
    final endpoint = _endpointCtrl.text.trim();

    if (accessId.isEmpty || accessSecret.isEmpty || appUid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Harap simpan kredensial terlebih dahulu sebelum men-scan!'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _isScanning = true);
    try {
      final response = await http
          .post(
            Uri.parse('${_apiBaseUrl}api/tuya/sync-keys'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'access_id': accessId,
              'access_secret': accessSecret,
              'app_uid': appUid,
              'endpoint': endpoint,
            }),
          )
          .timeout(const Duration(seconds: 15));

      dynamic data;
      try {
        data = json.decode(response.body);
      } catch (_) {}

      if (response.statusCode == 200 && data != null && data['success'] == true) {
        final List<dynamic> devices = data['devices'] ?? [];
        setState(() {
          _scannedPlugs = devices;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Berhasil mensinkronkan ${devices.length} stopkontak Bardi (kategori cz).'),
            backgroundColor: Colors.green,
          ),
        );
        await _loadDryerMachines();
      } else {
        final errorMsg = (data is Map && data['error'] != null)
            ? data['error']
            : 'Server Error: HTTP ${response.statusCode}';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sinkronisasi gagal: $errorMsg'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error sinkronisasi: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      setState(() => _isScanning = false);
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
          const SnackBar(content: Text('Mesin pengering berhasil disimpan.'), backgroundColor: Colors.green),
        );
        _loadDryerMachines();
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
          const SnackBar(content: Text('Mesin pengering berhasil dihapus.'), backgroundColor: Colors.green),
        );
        _loadDryerMachines();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal menghapus mesin pengering.'), backgroundColor: Colors.red),
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

  Future<void> _moveMachine(int oldIndex, int newIndex) async {
    setState(() {
      final item = _dryerMachinesList.removeAt(oldIndex);
      _dryerMachinesList.insert(newIndex, item);
    });

    try {
      final response = await http.get(Uri.parse('${_apiBaseUrl}api/machines')).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final List<dynamic> all = json.decode(response.body);
        final washMachines = all.where((m) => m['key'] != 'pengering').toList();
        
        final List<int> idsList = [];
        idsList.addAll(washMachines.map((m) => m['id'] as int));
        idsList.addAll(_dryerMachinesList.map((m) => m['id'] as int));

        final reorderResponse = await http.post(
          Uri.parse('${_apiBaseUrl}api/machines/reorder'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'ids': idsList}),
        );
        
        if (reorderResponse.statusCode != 200) {
          debugPrint('[BardiTuyaSettings] Gagal menyimpan susunan urutan mesin.');
        }
      }
    } catch (e) {
      debugPrint('[BardiTuyaSettings] Error menyimpan susunan urutan: $e');
    }
  }

  void _showAddMachineDialog() {
    final nameCtrl = TextEditingController();
    String source = 'manual'; 
    String? selectedTuyaId;

    final Set<String> usedUrls = _dryerMachinesList.map((m) => m['url'].toString()).toSet();
    final availablePlugs = _scannedPlugs.where((d) {
      final String name = d['name'] ?? '';
      final String rawUrl = name.replaceAll(' ', '_');
      return !usedUrls.contains(rawUrl);
    }).toList();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Tambah Pengering Baru', style: TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (source == 'manual') ...[
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nama Pengering (Kasir UI)',
                      hintText: 'e.g. Pengering A',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
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
                        title: const Text('Bardi Tuya', style: TextStyle(fontSize: 12)),
                        value: 'tuya',
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
                if (source == 'tuya') ...[
                  const SizedBox(height: 12),
                  availablePlugs.isEmpty
                      ? const Text(
                          'Semua stopkontak Bardi yang terdeteksi sudah dipetakan ke mesin lain.',
                          style: TextStyle(fontSize: 11, color: Colors.orange, fontStyle: FontStyle.italic),
                        )
                      : DropdownButtonFormField<String>(
                          value: selectedTuyaId,
                          decoration: const InputDecoration(
                            labelText: 'Pilih Stopkontak Bardi',
                            border: OutlineInputBorder(),
                          ),
                          items: availablePlugs.map((d) {
                            final String name = d['name'] ?? 'Bardi Smartplug';
                            final String rawUrl = name.toString().replaceAll(' ', '_');
                            return DropdownMenuItem<String>(
                              value: rawUrl,
                              child: Text(name, style: const TextStyle(fontSize: 12)),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setModalState(() => selectedTuyaId = val);
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
              style: ElevatedButton.styleFrom(backgroundColor: primaryColor),
              onPressed: () {
                String name = '';
                if (source == 'manual') {
                  name = nameCtrl.text.trim();
                  if (name.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Nama pengering wajib diisi')),
                    );
                    return;
                  }
                } else {
                  if (selectedTuyaId == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Harap pilih stopkontak Bardi')),
                    );
                    return;
                  }
                  dynamic matchingPlug;
                  for (final d in availablePlugs) {
                    if ((d['name'] ?? '').replaceAll(' ', '_') == selectedTuyaId) {
                      matchingPlug = d;
                      break;
                    }
                  }
                  name = matchingPlug != null ? matchingPlug['name'] : selectedTuyaId!.replaceAll('_', ' ');
                }
                final url = (source == 'tuya' && selectedTuyaId != null) ? selectedTuyaId! : '-';
                _saveMachine(name, url, 'pengering');
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
    final initialUrl = machine['url'].toString();
    String source = initialUrl == '-' ? 'manual' : 'tuya';
    String? selectedTuyaId = initialUrl == '-' ? null : initialUrl;

    final Set<String> usedUrls = _dryerMachinesList
        .where((m) => m['id'] != id)
        .map((m) => m['url'].toString())
        .toSet();
    final availablePlugs = _scannedPlugs.where((d) {
      final String name = d['name'] ?? '';
      final String rawUrl = name.replaceAll(' ', '_');
      return !usedUrls.contains(rawUrl) || rawUrl == initialUrl;
    }).toList();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Edit Pengering', style: TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (source == 'manual') ...[
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nama Pengering (Kasir UI)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
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
                        title: const Text('Bardi Tuya', style: TextStyle(fontSize: 12)),
                        value: 'tuya',
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
                if (source == 'tuya') ...[
                  const SizedBox(height: 12),
                  availablePlugs.isEmpty
                      ? const Text(
                          'Semua stopkontak Bardi yang terdeteksi sudah dipetakan ke mesin lain.',
                          style: TextStyle(fontSize: 11, color: Colors.orange, fontStyle: FontStyle.italic),
                        )
                      : DropdownButtonFormField<String>(
                          value: selectedTuyaId,
                          decoration: const InputDecoration(
                            labelText: 'Pilih Stopkontak Bardi',
                            border: OutlineInputBorder(),
                          ),
                          items: availablePlugs.map((d) {
                            final String name = d['name'] ?? 'Bardi Smartplug';
                            final String rawUrl = name.toString().replaceAll(' ', '_');
                            return DropdownMenuItem<String>(
                              value: rawUrl,
                              child: Text(name, style: const TextStyle(fontSize: 12)),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setModalState(() => selectedTuyaId = val);
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
              style: ElevatedButton.styleFrom(backgroundColor: primaryColor),
              onPressed: () {
                String name = '';
                if (source == 'manual') {
                  name = nameCtrl.text.trim();
                  if (name.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Nama pengering wajib diisi')),
                    );
                    return;
                  }
                } else {
                  if (selectedTuyaId == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Harap pilih stopkontak Bardi')),
                    );
                    return;
                  }
                  dynamic matchingPlug;
                  for (final d in availablePlugs) {
                    if ((d['name'] ?? '').replaceAll(' ', '_') == selectedTuyaId) {
                      matchingPlug = d;
                      break;
                    }
                  }
                  name = matchingPlug != null ? matchingPlug['name'] : selectedTuyaId!.replaceAll('_', ' ');
                }
                final url = (source == 'tuya' && selectedTuyaId != null) ? selectedTuyaId! : '-';
                _saveMachine(name, url, 'pengering', id: id);
                Navigator.pop(ctx);
              },
              child: const Text('Simpan', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text('Bardi Tuya Integration', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(28.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildStatusCard(),
                  const SizedBox(height: 24),
                  _buildCredentialsForm(),
                  const SizedBox(height: 24),
                  _buildDevicesListCard(),
                  const SizedBox(height: 24),
                  _buildDryersMappingCard(),
                ],
              ),
            ),
    );
  }

  Widget _buildStatusCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _isConnected ? Colors.green.withOpacity(0.08) : Colors.redAccent.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _isConnected ? Icons.check_circle_rounded : Icons.cancel_rounded,
              color: _isConnected ? Colors.green : Colors.redAccent,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Status Hubungan Tuya Cloud',
                  style: TextStyle(fontSize: 14, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 4),
                Text(
                  _isConnected ? 'Terhubung (Kredensial Aktif)' : 'Kredensial Belum Terisi Lengkap',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCredentialsForm() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.vpn_key_rounded, color: tuyaColor, size: 20),
              const SizedBox(width: 10),
              const Text(
                'Kredensial Pengembang Tuya',
                style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _buildTextField('Access ID / Client ID', _accessIdCtrl, 'Masukkan Access ID dari Tuya Portal'),
          const SizedBox(height: 14),
          _buildTextField('Access Secret / Client Secret', _accessSecretCtrl, 'Masukkan Access Secret', obscureText: true),
          const SizedBox(height: 14),
          _buildTextField('App Account UID', _appUidCtrl, 'Masukkan UID Akun Smart Life/Bardi Anda'),
          const SizedBox(height: 14),
          _buildTextField('Endpoint Region URL', _endpointCtrl, 'https://openapi.tuyaus.com'),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              ElevatedButton.icon(
                onPressed: _saveCredentials,
                icon: const Icon(Icons.save_rounded, size: 18),
                label: const Text('Simpan Kredensial', style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController ctrl, String hint, {bool obscureText = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF475569)),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: ctrl,
          obscureText: obscureText,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: primaryColor, width: 1.5)),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
          ),
        ),
      ],
    );
  }

  Widget _buildDevicesListCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.power_rounded, color: primaryColor, size: 22),
              const SizedBox(width: 10),
              const Text(
                'Daftar Perangkat Bardi Terdeteksi (Kategori CZ)',
                style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
              ),
              const Spacer(),
              if (_isScanning)
                const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              else
                IconButton(
                  onPressed: _syncAndScanDevices,
                  icon: const Icon(Icons.sync_rounded),
                  tooltip: 'Sinkronisasi & Scan Perangkat',
                  color: primaryColor,
                ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Hanya stopkontak pintar (tipe colokan/kategori "cz") yang akan dimunculkan dan didaftarkan otomatis ke mesin pengering.',
            style: TextStyle(fontSize: 12, color: Color(0xFF64748B), height: 1.4),
          ),
          const SizedBox(height: 20),
          _scannedPlugs.isEmpty
              ? Container(
                  padding: const EdgeInsets.symmetric(vertical: 36),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFF1F5F9)),
                  ),
                  child: const Center(
                    child: Column(
                      children: [
                        Icon(Icons.power_off_rounded, size: 36, color: Color(0xFF94A3B8)),
                        SizedBox(height: 12),
                        Text(
                          'Belum ada stopkontak tersinkronisasi.\nSilakan klik tombol scan di atas.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Color(0xFF64748B), fontSize: 13, height: 1.45),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _scannedPlugs.length,
                  separatorBuilder: (context, index) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                  itemBuilder: (context, index) {
                    final dev = _scannedPlugs[index];
                    final String name = dev['name'] ?? 'Bardi Smartplug';
                    final String devId = dev['id'] ?? dev['device_id'] ?? '-';
                    final bool isOnline = dev['online'] == true;
                    
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14.0),
                      child: Row(
                        children: [
                          Icon(Icons.outlet_rounded, color: primaryColor, size: 24),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A)),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'ID: ${devId.substring(0, devId.length > 8 ? 8 : devId.length)}... | Kategori: cz',
                                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: isOnline ? Colors.green.withOpacity(0.08) : Colors.redAccent.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              isOnline ? 'ONLINE' : 'OFFLINE',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isOnline ? Colors.green : Colors.redAccent,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ],
      ),
    );
  }

  Widget _buildDryersMappingCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
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
                    'Daftar & Pemetaan Mesin Pengering',
                    style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Gunakan tombol panah (up/down) untuk menyusun posisi urutan di Dashboard.',
                    style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                  ),
                ],
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, color: Color(0xFF64748B)),
                    onPressed: _loadDryerMachines,
                    tooltip: 'Segarkan data',
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _showAddMachineDialog,
                    icon: const Icon(Icons.add_rounded, color: Colors.white, size: 18),
                    label: const Text('Tambah Pengering', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Divider(height: 1),
          const SizedBox(height: 12),

          Container(
            color: const Color(0xFFF8FAFC),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            child: const Row(
              children: [
                SizedBox(width: 56), 
                Expanded(flex: 5, child: Text('NAMA PENGERING', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF64748B)))),
                Expanded(flex: 4, child: Text('INTEGRASI', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF64748B)))),
                Expanded(flex: 6, child: Text('STOPKONTAK ALIAS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF64748B)))),
                Expanded(flex: 2, child: Align(alignment: Alignment.centerRight, child: Text('AKSI', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF64748B))))),
              ],
            ),
          ),
          const SizedBox(height: 8),

          _isMachinesLoading
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 36.0),
                  child: Center(child: CircularProgressIndicator()),
                )
              : _dryerMachinesList.isEmpty
                  ? Container(
                      padding: const EdgeInsets.symmetric(vertical: 36),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFF1F5F9)),
                      ),
                      child: const Center(
                        child: Column(
                          children: [
                            Icon(Icons.wb_sunny_outlined, size: 36, color: Color(0xFF94A3B8)),
                            SizedBox(height: 12),
                            Text(
                              'Belum ada mesin pengering terdaftar.\nKlik "Tambah Pengering" atau "Sinkronisasi" di atas.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Color(0xFF64748B), fontSize: 13, height: 1.45),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _dryerMachinesList.length,
                      separatorBuilder: (context, index) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                      itemBuilder: (context, index) {
                        final m = _dryerMachinesList[index];
                        final id = m['id'] as int;
                        final name = m['name'].toString();
                        final url = m['url'].toString();
                        final isManual = url == '-';

                        return Container(
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                          child: Row(
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.arrow_upward_rounded, size: 16, color: Colors.blueGrey),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed: index > 0 ? () => _moveMachine(index, index - 1) : null,
                                    tooltip: 'Pindahkan ke atas',
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: const Icon(Icons.arrow_downward_rounded, size: 16, color: Colors.blueGrey),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed: index < _dryerMachinesList.length - 1 ? () => _moveMachine(index, index + 1) : null,
                                    tooltip: 'Pindahkan ke bawah',
                                  ),
                                ],
                              ),
                              const SizedBox(width: 16),

                              Expanded(
                                flex: 5,
                                child: Text(
                                  name,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B)),
                                ),
                              ),

                              Expanded(
                                flex: 4,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isManual ? Colors.grey[100] : tuyaColor.withOpacity(0.06),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: isManual ? Colors.grey[300]! : tuyaColor.withOpacity(0.2)),
                                    ),
                                    child: Text(
                                      isManual ? 'MANUAL' : 'BARDI TUYA',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: isManual ? Colors.grey[700] : tuyaColor,
                                      ),
                                    ),
                                  ),
                                ),
                              ),

                              Expanded(
                                flex: 6,
                                child: Text(
                                  isManual ? '-' : url,
                                  style: const TextStyle(fontSize: 12, color: Color(0xFF475569), fontStyle: FontStyle.italic),
                                ),
                              ),

                              Expanded(
                                flex: 2,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit_rounded, size: 18, color: Colors.blueAccent),
                                      onPressed: () => _showEditMachineDialog(m),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      tooltip: 'Ubah Nama/Sumber',
                                    ),
                                    const SizedBox(width: 12),
                                    IconButton(
                                      icon: const Icon(Icons.delete_rounded, size: 18, color: Colors.redAccent),
                                      onPressed: () {
                                        showDialog(
                                          context: context,
                                          builder: (ctx) => AlertDialog(
                                            title: const Text('Hapus Pengering'),
                                            content: Text('Apakah Anda yakin ingin menghapus "$name"?'),
                                            actions: [
                                              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
                                              ElevatedButton(
                                                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                                onPressed: () {
                                                  _deleteMachine(id);
                                                  Navigator.pop(ctx);
                                                },
                                                child: const Text('Hapus', style: TextStyle(color: Colors.white)),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      tooltip: 'Hapus Pengering',
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
        ],
      ),
    );
  }
}
