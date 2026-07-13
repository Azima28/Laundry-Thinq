import 'package:flutter/material.dart';
import '../database/models/database_helper.dart';
import '../../database/models/machine_model.dart';

class MesinPengeringScreen extends StatefulWidget {
  const MesinPengeringScreen({Key? key}) : super(key: key);

  @override
  _MesinPengeringScreenState createState() => _MesinPengeringScreenState();
}

class _MesinPengeringScreenState extends State<MesinPengeringScreen> {
  final DatabaseHelper _db = DatabaseHelper.instance;
  List<MachineModel> _machines = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMachines();
  }

  Future<void> _loadMachines() async {
    setState(() => _isLoading = true);
    final items = await _db.getAllMachines(type: 'pengering');
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
        title: Text(isNew ? 'Tambah Mesin Pengering' : 'Edit Mesin Pengering'),
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
                final m = MachineModel(name: name, url: url, key: key, createdAt: now, machineType: 'pengering');
                await _db.insertMachine(m);
              } else {
                final m = MachineModel(id: machine.id, name: name, url: url, key: key, createdAt: machine.createdAt, machineType: 'pengering');
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
            title: const Text('Hapus Mesin Pengering'),
        content: Text('Yakin ingin menghapus mesin "${machine.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal', style: TextStyle(color: Color.fromARGB(255, 255, 255, 255)))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus', style: TextStyle(color: Color.fromARGB(255, 255, 255, 255))),
          ),
        ],
      ),
    );

    if (ok == true) {
      await _db.deleteMachine(machine.id!);
      await _loadMachines();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kelola Mesin Pengering'),
        backgroundColor: const Color(0xFF3F51B5),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showMachineDialog(),
            tooltip: 'Tambah Mesin Pengering',
          )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _machines.isEmpty
              ? Center(child: Text('Belum ada mesin pengering. Tekan + untuk menambah.'))
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _machines.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, idx) {
                    final m = _machines[idx];
                    return Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        title: Text(m.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        // Hide URL and ID in list since they're secret. Keep edit dialog for full details.
                        subtitle: const Text('URL: (hidden) · ID: (hidden)'),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.indigo),
                            onPressed: () => _showMachineDialog(machine: m),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.redAccent),
                            onPressed: () => _confirmDelete(m),
                          ),
                        ]),
                      ),
                    );
                  },
                ),
    );
  }
}
