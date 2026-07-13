import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../database/models/database_helper.dart';
import '../../database/models/machine_model.dart';

class MesinCuciScreen extends StatefulWidget {
  const MesinCuciScreen({Key? key}) : super(key: key);

  @override
  _MesinCuciScreenState createState() => _MesinCuciScreenState();
}

class _MesinCuciScreenState extends State<MesinCuciScreen> {
  final DatabaseHelper _db = DatabaseHelper.instance;
  List<MachineModel> _machines = [];
  bool _isLoading = true;
  final TextEditingController _baseUrlCtrl = TextEditingController(text: 'http://azima.local:5001/');
  final Map<String, dynamic> _machineStates = {};

  @override
  void initState() {
    super.initState();
    _loadMachines();
  }

  Future<void> _loadMachines() async {
    setState(() => _isLoading = true);
    final items = await _db.getAllMachines(type: 'cuci');
    setState(() {
      _machines = items;
      _isLoading = false;
    });
  }

  Future<void> _showMachineDialog({MachineModel? machine}) async {
    final nameCtrl = TextEditingController(text: machine?.name ?? '');
    final urlCtrl = TextEditingController(text: machine?.url ?? '');
    final keyCtrl = TextEditingController(text: machine?.key ?? '');

    final isNew = machine == null;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isNew ? 'Tambah Mesin' : 'Edit Mesin'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(labelText: 'Nama Mesin', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: urlCtrl,
                decoration: InputDecoration(labelText: 'URL (contoh: https://19301203/mesin.com)', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: keyCtrl,
                decoration: InputDecoration(labelText: 'Key', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
            ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3F51B5)),
            onPressed: () async {
              final name = nameCtrl.text.trim();
              final url = urlCtrl.text.trim();
              final key = keyCtrl.text.trim();

              final now = DateTime.now();
              if (isNew) {
              final m = MachineModel(name: name, url: url, key: key, createdAt: now, machineType: 'cuci');
              await _db.insertMachine(m);
              } else {
              final m = MachineModel(id: machine.id, name: name, url: url, key: key, createdAt: machine.createdAt, machineType: 'cuci');
              await _db.updateMachine(m);
              }

              Navigator.pop(context);
              await _loadMachines();
            },
            child: Text(isNew ? 'Tambah' : 'Simpan', style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(MachineModel machine) async {
    final ok = await showDialog<bool?>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus Mesin'),
        content: Text('Yakin ingin menghapus mesin "${machine.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await _db.deleteMachine(machine.id!);
      await _loadMachines();
    }
  }

  Future<void> _fetchFromUrl() async {
    final url = _baseUrlCtrl.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Masukkan URL')));
      return;
    }

    setState(() => _isLoading = true);
    try {
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(res.body) as Map<String, dynamic>;
        final List<MachineModel> list = [];
        _machineStates.clear();
        data.forEach((key, value) {
          if (value is Map<String, dynamic>) {
            _machineStates[key] = value;
            final m = MachineModel(
              id: null,
              name: key,
              url: value['url'] ?? '',
              key: '',
              createdAt: DateTime.now(),
              machineType: 'cuci',
            );
            list.add(m);
          }
        });
        setState(() => _machines = list);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Request failed: ${res.statusCode}')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kelola Mesin Cuci'),
        backgroundColor: const Color(0xFF3F51B5),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Color(0xFFFFFFFF),),
            onPressed: () => _showMachineDialog(),
            tooltip: 'Tambah Mesin',
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _baseUrlCtrl,
                        decoration: InputDecoration(labelText: 'Base URL', hintText: 'http://azima.local:5001/', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3F51B5)),
                      onPressed: _fetchFromUrl,
                      child: const Text('Fetch'),
                    )
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _machines.isEmpty
                      ? Center(child: Text('Belum ada mesin. Tekan + untuk menambah.'))
                      : ListView.separated(
                          padding: const EdgeInsets.all(0),
                          itemCount: _machines.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, idx) {
                            final m = _machines[idx];
                            final state = _machineStates[m.name] as Map<String, dynamic>?;
                            final subtitle = state != null
                                ? '${state['run_state'] ?? '-'} · ${state['remain_time'] ?? '-'}'
                                : 'URL: (hidden) · ID: (hidden)';
                            return Card(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              child: ListTile(
                                title: Text(m.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text(subtitle),
                                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                  if (m.id == null) ...[
                                    IconButton(
                                      icon: const Icon(Icons.add, color: Colors.green),
                                      tooltip: 'Tambah ke DB',
                                      onPressed: () async {
                                        await _db.insertMachine(m);
                                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mesin ditambahkan ke database')));
                                        await _loadMachines();
                                      },
                                    ),
                                  ] else ...[
                                    IconButton(
                                      icon: const Icon(Icons.edit, color: Colors.indigo),
                                      onPressed: () => _showMachineDialog(machine: m),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete, color: Colors.redAccent),
                                      onPressed: () => _confirmDelete(m),
                                    ),
                                  ],
                                ]),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
