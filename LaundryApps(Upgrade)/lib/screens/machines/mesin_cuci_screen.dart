import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../../database/models/database_helper.dart';
import '../../database/models/machine_model.dart';

class MesinCuciScreen extends StatefulWidget {
  const MesinCuciScreen({Key? key}) : super(key: key);

  @override
  _MesinCuciScreenState createState() => _MesinCuciScreenState();
}

class _MesinCuciScreenState extends State<MesinCuciScreen> {
  final DatabaseHelper _db = DatabaseHelper.instance;
  List<MachineModel> _savedMachines = [];
  List<String> _entities = [];
  List<String> _customOrder = [];
  bool _isLoading = false;
  final TextEditingController _baseUrlCtrl = TextEditingController(text: 'http://azima.local:5001/');
  final Map<String, dynamic> _machineStates = {};

  final Color primaryColor = const Color(0xFF4E80EE);
  final Color backgroundColor = const Color(0xFFF8FAFC);

  List<String> get _displayEntities {
    final List<String> names = [];
    for (var m in _savedMachines) {
      if (!names.contains(m.name)) names.add(m.name);
    }
    for (var e in _entities) {
      if (!names.contains(e)) names.add(e);
    }
    return names;
  }

  List<String> _orderedEntities() {
    final base = _displayEntities;
    if (_customOrder.isEmpty) return base;
    final List<String> ordered = [];
    for (var name in _customOrder) {
      if (base.contains(name) && !ordered.contains(name)) ordered.add(name);
    }
    for (var name in base) {
      if (!ordered.contains(name)) ordered.add(name);
    }
    return ordered;
  }

  @override
  void initState() {
    super.initState();
    _loadSavedMachines();
    _loadCustomOrder();
    _loadBaseUrl();
  }

  Future<void> _loadBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    String url = prefs.getString('machines_base_url_cuci') ?? 'http://127.0.0.1:5001/';
    if (url.contains('azima.local')) {
      url = url.replaceAll('azima.local', '127.0.0.1');
      await prefs.setString('machines_base_url_cuci', url);
    }
    setState(() => _baseUrlCtrl.text = url);
  }

  Future<void> _saveBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('machines_base_url_cuci', url);
  }

  Future<void> _loadCustomOrder() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('machines_order_cuci') ?? [];
    setState(() => _customOrder = list);
  }

  Future<void> _saveCustomOrder() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('machines_order_cuci', _customOrder);
  }

  Future<void> _loadSavedMachines() async {
    final items = await _db.getAllMachines(type: 'cuci');
    setState(() {
      _savedMachines = items;
      for (var m in items) {
        if (!_machineStates.containsKey(m.name)) {
          _machineStates[m.name] = {
            'state': 'unknown',
            'run_state': '-',
            'remain_time': '-',
            'current_course': '-',
            'url': m.url
          };
        }
      }
    });
  }

  bool _isSaved(String name) {
    return _savedMachines.any((m) => m.name == name);
  }

  Future<void> _saveEntity(String name) async {
    final key = name;
    final model = MachineModel(
      name: name,
      key: key,
      machineType: 'cuci',
      url: 'api/washer/state',
      createdAt: DateTime.now(),
    );
    await _db.insertMachine(model);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ Mesin "$name" berhasil disimpan ke Database!'), backgroundColor: Colors.green),
      );
    }
    _loadSavedMachines();
  }

  Future<void> _removeSavedEntity(String name) async {
    final machine = _savedMachines.firstWhere((m) => m.name == name);
    if (machine.id != null) {
      await _db.deleteMachine(machine.id!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('🗑️ Mesin "$name" berhasil dihapus dari Database!'), backgroundColor: Colors.redAccent),
        );
      }
      _loadSavedMachines();
    }
  }

  Future<void> _fetchFromUrl() async {
    final base = _baseUrlCtrl.text.trim();
    if (base.isEmpty) return;
    await _saveBaseUrl(base);

    setState(() => _isLoading = true);
    try {
      final response = await http.get(Uri.parse('${base}api/washer/discover')).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is List) {
          final List<String> fetched = [];
          for (var item in data) {
            fetched.add(item.toString());
          }
          setState(() {
            _entities = fetched;
            // populate states immediately with defaults
            for (var key in fetched) {
              if (!_machineStates.containsKey(key)) {
                _machineStates[key] = {
                  'state': 'discovered',
                  'run_state': '-',
                  'remain_time': '-',
                  'current_course': '-',
                  'url': 'api/washer/state'
                };
              }
            }
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ Berhasil mendeteksi mesin ThinQ!'), backgroundColor: Colors.green),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('⚠️ Gagal fetch: Status ${response.statusCode}'), backgroundColor: Colors.orange),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Gagal menghubungi API server: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _testUrl(String entityId) async {
    final base = _baseUrlCtrl.text.trim();
    if (base.isEmpty) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('🔌 Menghubungkan ke $entityId...'), duration: const Duration(seconds: 1)),
    );

    try {
      final response = await http.post(
        Uri.parse('${base}api/washer/state'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'entity_id': entityId}),
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _machineStates[entityId] = {
            'state': data['state'] ?? 'unknown',
            'run_state': data['run_state'] ?? '-',
            'remain_time': data['remain_time'] ?? '-',
            'current_course': data['current_course'] ?? '-',
            'title': data['title'] ?? '',
            'url': 'api/washer/state'
          };
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('🟢 Koneksi OK! Status: ${data['state']}'), backgroundColor: Colors.green),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('🔴 Gagal tes koneksi: HTTP ${response.statusCode}'), backgroundColor: Colors.redAccent),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Gagal menghubungi API: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _showEditDialog(String entityId, String currentTitle) async {
    final ctrl = TextEditingController(text: currentTitle);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Edit Nama Tampilan Mesin'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Nama Custom Mesin', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () async {
              final newTitle = ctrl.text.trim();
              if (newTitle.isEmpty) return;
              
              // If already saved in database, we can update key/name mappings
              final exists = _savedMachines.any((m) => m.name == entityId);
              if (exists) {
                final model = _savedMachines.firstWhere((m) => m.name == entityId);
                final updated = MachineModel(
                  id: model.id,
                  name: model.name,
                  url: model.url,
                  machineType: model.machineType,
                  key: newTitle,
                  createdAt: model.createdAt,
                );
                await _db.updateMachine(updated);
                _loadSavedMachines();
              }
              
              setState(() {
                if (_machineStates[entityId] != null) {
                  _machineStates[entityId]['title'] = newTitle;
                } else {
                  _machineStates[entityId] = {'title': newTitle};
                }
              });
              Navigator.pop(ctx);
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text('Pengaturan Mesin Cuci', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Left Panel: Discover settings & info (340px)
          Container(
            width: 340,
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(right: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'ThinQ API Sync',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                  ),
                  const SizedBox(height: 16),
                  
                  // Base URL input
                  TextField(
                    controller: _baseUrlCtrl,
                    decoration: InputDecoration(
                      labelText: 'API Monitor Base URL',
                      hintText: 'http://azima.local:5001/',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.all(14),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Discover button
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : _fetchFromUrl,
                    icon: _isLoading 
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.sync_rounded, size: 16, color: Colors.white),
                    label: const Text('Fetch ThinQ Devices', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 28),
                  const Divider(height: 1),
                  const SizedBox(height: 24),

                  // Guide card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.info_outline_rounded, size: 16, color: Colors.grey),
                            SizedBox(width: 8),
                            Text('Reorder Mesin', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF334155))),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Tarik dan lepas (drag-and-drop) card mesin di sisi kanan untuk mengurutkan tata letak tampilan mesin cuci kasir.',
                          style: TextStyle(fontSize: 11, color: Colors.grey, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 2. Right Panel: Drag and drop discovered list (Expanded)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(28.0),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.grey[200]!),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.01), blurRadius: 10)],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Daftar Mesin Cuci ThinQ',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                        ),
                        Text(
                          '${_orderedEntities().length} Mesin',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey[500]),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(height: 1),
                    const SizedBox(height: 16),
                    
                    Expanded(
                      child: _orderedEntities().isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.cloud_off_rounded, size: 48, color: Colors.grey[300]),
                                  const SizedBox(height: 12),
                                  const Text('Belum ada mesin terdeteksi. Tekan Fetch di sisi kiri.', style: TextStyle(color: Colors.grey)),
                                ],
                              ),
                            )
                          : ReorderableListView(
                              onReorder: (oldIndex, newIndex) async {
                                final list = List<String>.from(_orderedEntities());
                                if (newIndex > oldIndex) newIndex -= 1;
                                final item = list.removeAt(oldIndex);
                                list.insert(newIndex, item);
                                setState(() => _customOrder = list);
                                await _saveCustomOrder();
                              },
                              children: List.generate(_orderedEntities().length, (idx) {
                                final key = _orderedEntities()[idx];
                                final state = _machineStates[key] as Map<String, dynamic>?;
                                final machineState = state?['state'] ?? '-';
                                final remain = state?['remain_time'] ?? '-';
                                final course = state?['current_course'] ?? '-';
                                final saved = _isSaved(key);
                                MachineModel? savedModel;
                                for (var m in _savedMachines) {
                                  if (m.name == key) {
                                    savedModel = m;
                                    break;
                                  }
                                }
                                final title = (state?['title'] as String?) ?? (savedModel?.key ?? '');
                                final displayTitle = title.isNotEmpty ? title : key;

                                return Card(
                                  key: ValueKey(key),
                                  margin: const EdgeInsets.only(bottom: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  elevation: 0,
                                  borderOnForeground: false,
                                  color: Colors.grey[50],
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                                    leading: CircleAvatar(
                                      backgroundColor: saved ? Colors.green.withOpacity(0.1) : Colors.grey[200],
                                      child: Icon(Icons.local_laundry_service_rounded, color: saved ? Colors.green : Colors.grey),
                                    ),
                                    title: Text(displayTitle, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                    subtitle: Padding(
                                      padding: const EdgeInsets.only(top: 4.0),
                                      child: Text(
                                        'ID: $key\nStatus: $machineState · Sisa: $remain · Course: $course',
                                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                      ),
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: Icon(Icons.edit_rounded, color: primaryColor, size: 20),
                                          tooltip: 'Ubah Nama',
                                          onPressed: () => _showEditDialog(key, displayTitle),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.link_rounded, color: Colors.blue, size: 20),
                                          tooltip: 'Tes Koneksi API',
                                          onPressed: () => _testUrl(key),
                                        ),
                                        if (!saved) ...[
                                          IconButton(
                                            icon: const Icon(Icons.save_rounded, color: Colors.green, size: 20),
                                            tooltip: 'Simpan ke Database',
                                            onPressed: () => _saveEntity(key),
                                          ),
                                        ] else ...[
                                          IconButton(
                                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                                            tooltip: 'Hapus dari Database',
                                            onPressed: () => _removeSavedEntity(key),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                );
                              }),
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
}
