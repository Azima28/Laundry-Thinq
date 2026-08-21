import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../database/models/database_helper.dart';
import '../../utils/style_constants.dart';

class BackupSettingsScreen extends StatefulWidget {
  const BackupSettingsScreen({super.key});

  @override
  State<BackupSettingsScreen> createState() => _BackupSettingsScreenState();
}

class _BackupSettingsScreenState extends State<BackupSettingsScreen> {
  final DatabaseHelper _db = DatabaseHelper.instance;
  Map<String, dynamic>? _dbStats;
  List<File> _availableBackups = [];
  bool _isLoading = true;
  bool _isBackingUp = false;
  bool _isRestoring = false;

  final Color primaryColor = StyleConstants.primaryColor;
  final Color backgroundColor = StyleConstants.backgroundColor;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final stats = await _db.getDatabaseStatistics();
      final backups = await _db.getAvailableBackups();
      if (mounted) {
        setState(() {
          _dbStats = stats;
          _availableBackups = backups;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[BackupSettings] Gagal memuat data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _createBackupNow() async {
    setState(() => _isBackingUp = true);
    try {
      final backupPath = await _db.createBackup();
      await _loadData();

      if (mounted) {
        final fileName = backupPath.split(Platform.pathSeparator).last;
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 28),
                SizedBox(width: 12),
                Text('Backup Database Berhasil!', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Seluruh data transaksi, pelanggan, layanan, dan pengeluaran berhasil dicadangkan dengan aman.',
                  style: TextStyle(fontSize: 13, color: Color(0xFF475569), height: 1.4),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.storage_rounded, size: 16, color: Color(0xFF64748B)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              fileName,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Color(0xFF0F172A)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Lokasi: $backupPath',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Tutup', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _openBackupFolder();
                },
                icon: const Icon(Icons.folder_open_rounded, size: 18, color: Colors.white),
                label: const Text('Buka Folder di Explorer', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal membuat backup: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isBackingUp = false);
      }
    }
  }

  Future<void> _openBackupFolder() async {
    try {
      final dirPath = await _db.getBackupDirectoryPath();
      if (Platform.isWindows) {
        await Process.run('explorer.exe', [dirPath]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [dirPath]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [dirPath]);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal membuka folder: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _restoreBackup(File backupFile) async {
    final fileName = backupFile.path.split(Platform.pathSeparator).last;
    final lastModified = DateFormat('dd/MM/yyyy HH:mm').format(backupFile.lastModifiedSync());

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFF59E0B), size: 28),
            SizedBox(width: 12),
            Text('Pulihkan Database?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'PERHATIAN: Memulihkan database akan mengganti seluruh data yang ada saat ini dengan data dari file backup yang dipilih.',
              style: TextStyle(fontSize: 13, color: Color(0xFFDC2626), fontWeight: FontWeight.w600, height: 1.4),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('File: $fileName', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A))),
                  const SizedBox(height: 4),
                  Text('Waktu Backup: $lastModified', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.restore_rounded, size: 18, color: Colors.white),
            label: const Text('Ya, Pulihkan Sekarang', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF59E0B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isRestoring = true);
      try {
        await _db.restoreDatabase(backupFile.path);
        await _loadData();

        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 28),
                  SizedBox(width: 12),
                  Text('Database Berhasil Dipulihkan!', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                ],
              ),
              content: const Text(
                'Seluruh data transaksi dan sistem telah berhasil dikembalikan dari file cadangan.',
                style: TextStyle(fontSize: 13, color: Color(0xFF475569)),
              ),
              actions: [
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Selesai', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal memulihkan database: $e'), backgroundColor: Colors.red),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isRestoring = false);
        }
      }
    }
  }

  Future<void> _deleteBackup(File backupFile) async {
    final fileName = backupFile.path.split(Platform.pathSeparator).last;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Hapus File Backup?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        content: Text('Yakin ingin menghapus file backup $fileName?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        if (await backupFile.exists()) {
          await backupFile.delete();
          await _loadData();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('File backup berhasil dihapus.'), backgroundColor: Colors.grey),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal menghapus file: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _restoreCustomFilePath() async {
    final pathController = TextEditingController();
    final customFile = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Pulihkan dari Lokasi File Luar (.db)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Masukkan path lengkap file database cadangan (misal dari USB Flashdisk):',
                style: TextStyle(fontSize: 12.5, color: Color(0xFF475569)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: pathController,
                decoration: InputDecoration(
                  hintText: 'D:\\backup\\laundry_backup.db',
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  prefixIcon: const Icon(Icons.usb_rounded, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () {
              final p = pathController.text.trim();
              if (p.isNotEmpty) Navigator.pop(ctx, p);
            },
            style: ElevatedButton.styleFrom(backgroundColor: primaryColor, foregroundColor: Colors.white),
            child: const Text('Lanjutkan', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (customFile != null && customFile.isNotEmpty) {
      final f = File(customFile);
      if (await f.exists()) {
        await _restoreBackup(f);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('File tidak ditemukan di lokasi tersebut.'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.canPop(context);

    Widget content = _isLoading
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(28.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Top Database Health & Metrics Card
                _buildDatabaseHealthCard(),
                const SizedBox(height: 24),

                // 2. Primary 1-Click Action Buttons
                _buildActionButtonsRow(),
                const SizedBox(height: 28),

                // 3. Backup History Table / Card
                _buildBackupHistoryCard(),
              ],
            ),
          );

    if (canPop) {
      return Scaffold(
        backgroundColor: backgroundColor,
        appBar: AppBar(
          title: const Text('Backup & Pulihkan Database', style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: Colors.white,
          foregroundColor: StyleConstants.textHeading,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: StyleConstants.textHeading),
            tooltip: 'Kembali',
            onPressed: () => Navigator.pop(context),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(color: StyleConstants.borderLight, height: 1),
          ),
        ),
        body: content,
      );
    }

    return content;
  }

  Widget _buildDatabaseHealthCard() {
    final stats = _dbStats ?? {};
    final fileSize = stats['fileSize'] ?? '0 KB';
    final orderCount = stats['orderCount'] ?? 0;
    final customerCount = stats['customerCount'] ?? 0;
    final expenseCount = stats['expenseCount'] ?? 0;
    final serviceCount = stats['serviceCount'] ?? 0;
    final dbPath = stats['path'] ?? 'laundry.db';

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(color: const Color(0xFF0F172A).withValues(alpha: 0.03), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.storage_rounded, color: Color(0xFF10B981), size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Text(
                          'Database Utama SQLite (laundry.db)',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                        ),
                        SizedBox(width: 10),
                        Icon(Icons.verified_rounded, color: Color(0xFF10B981), size: 18),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Path: $dbPath',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('UKURAN FILE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                    Text(fileSize, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          const SizedBox(height: 18),
          Row(
            children: [
              _buildStatChip(label: 'Total Transaksi Nota', value: '$orderCount Data', icon: Icons.receipt_long_rounded, color: const Color(0xFF2563EB)),
              const SizedBox(width: 14),
              _buildStatChip(label: 'Pelanggan CRM', value: '$customerCount Orang', icon: Icons.people_alt_rounded, color: const Color(0xFF10B981)),
              const SizedBox(width: 14),
              _buildStatChip(label: 'Buku Pengeluaran', value: '$expenseCount Catatan', icon: Icons.account_balance_wallet_rounded, color: const Color(0xFFEF4444)),
              const SizedBox(width: 14),
              _buildStatChip(label: 'Daftar Layanan', value: '$serviceCount Layanan', icon: Icons.local_laundry_service_rounded, color: const Color(0xFF6366F1)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 16),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(value, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtonsRow() {
    return Row(
      children: [
        // Primary Backup Button
        Expanded(
          flex: 2,
          child: ElevatedButton.icon(
            onPressed: _isBackingUp ? null : _createBackupNow,
            icon: _isBackingUp
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.cloud_upload_rounded, size: 22, color: Colors.white),
            label: Text(
              _isBackingUp ? 'Sedang Mencadangkan...' : 'Buat Backup Database Sekarang (1-Klik)',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
          ),
        ),
        const SizedBox(width: 14),
        // Open Folder Button
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _openBackupFolder,
            icon: const Icon(Icons.folder_open_rounded, size: 20, color: Color(0xFF2563EB)),
            label: const Text('Buka Folder Backup', style: TextStyle(color: Color(0xFF2563EB), fontWeight: FontWeight.bold)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
              backgroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
        const SizedBox(width: 14),
        // Custom File Restore Button
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _restoreCustomFilePath,
            icon: const Icon(Icons.usb_rounded, size: 20, color: Color(0xFF475569)),
            label: const Text('Pulihkan dari USB', style: TextStyle(color: Color(0xFF475569), fontWeight: FontWeight.bold)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.5),
              backgroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBackupHistoryCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(color: const Color(0xFF0F172A).withValues(alpha: 0.03), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                const Icon(Icons.history_rounded, size: 22, color: Color(0xFF0F172A)),
                const SizedBox(width: 10),
                const Text(
                  'Riwayat File Backup Tersimpan',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                ),
                const Spacer(),
                Text(
                  '${_availableBackups.length} File Cadangan Tersedia',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          if (_availableBackups.isEmpty)
            Padding(
              padding: const EdgeInsets.all(48.0),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey[300]),
                    const SizedBox(height: 12),
                    const Text(
                      'Belum ada file backup yang dibuat.',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Klik tombol "Buat Backup Database Sekarang" di atas untuk membuat cadangan pertama Anda.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _availableBackups.length,
              separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
              itemBuilder: (context, index) {
                final file = _availableBackups[index];
                final fileName = file.path.split(Platform.pathSeparator).last;
                final modTime = file.lastModifiedSync();
                final formattedDate = DateFormat('dd MMMM yyyy, HH:mm:ss').format(modTime);
                final bytes = file.lengthSync();
                final sizeStr = bytes < 1024 * 1024
                    ? '${(bytes / 1024).toStringAsFixed(1)} KB'
                    : '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.save_rounded, color: Color(0xFF2563EB), size: 22),
                  ),
                  title: Text(
                    fileName,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: Color(0xFF0F172A)),
                  ),
                  subtitle: Text(
                    'Dibuat pada: $formattedDate • Ukuran: $sizeStr',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _isRestoring ? null : () => _restoreBackup(file),
                        icon: const Icon(Icons.restore_rounded, size: 16, color: Colors.white),
                        label: const Text('Pulihkan Data', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF59E0B),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () => _deleteBackup(file),
                        icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Color(0xFFEF4444)),
                        tooltip: 'Hapus File Backup',
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
