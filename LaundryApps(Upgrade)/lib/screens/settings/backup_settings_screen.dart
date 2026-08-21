import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../database/models/database_helper.dart';
import '../../transactions/user_repository.dart';
import '../../utils/style_constants.dart';

class BackupSettingsScreen extends StatefulWidget {
  const BackupSettingsScreen({super.key});

  @override
  State<BackupSettingsScreen> createState() => _BackupSettingsScreenState();
}

class _BackupSettingsScreenState extends State<BackupSettingsScreen> {
  final DatabaseHelper _db = DatabaseHelper.instance;
  final UserRepository _userRepo = UserRepository();

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

  /// Verification Modal for Admin Password (not PIN, actual admin login password)
  Future<bool> _promptAdminPassword({
    required String title,
    required String subtitle,
    required String actionButtonText,
    required Color actionButtonColor,
    required IconData actionIcon,
  }) async {
    final passwordCtrl = TextEditingController();
    bool isObscure = true;
    String? errorMessage;
    bool isVerifying = false;

    final verified = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              actionsPadding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: actionButtonColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(actionIcon, color: actionButtonColor, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: Color(0xFF0F172A)),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Otorisasi Keamanan Hak Akses Admin',
                          style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 460,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 13, color: Color(0xFF475569), height: 1.4),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Password Akun Admin',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF334155)),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: passwordCtrl,
                      obscureText: isObscure,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Masukkan password admin...',
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                        suffixIcon: IconButton(
                          icon: Icon(isObscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
                          onPressed: () {
                            setModalState(() {
                              isObscure = !isObscure;
                            });
                          },
                        ),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: actionButtonColor, width: 1.5),
                        ),
                      ),
                      onSubmitted: (_) async {
                        final pwd = passwordCtrl.text.trim();
                        if (pwd.isEmpty) {
                          setModalState(() => errorMessage = 'Password tidak boleh kosong');
                          return;
                        }
                        setModalState(() {
                          isVerifying = true;
                          errorMessage = null;
                        });
                        final isValid = await _userRepo.verifyAdminPassword(pwd);
                        if (isValid) {
                          if (ctx.mounted) Navigator.pop(ctx, true);
                        } else {
                          setModalState(() {
                            isVerifying = false;
                            errorMessage = 'Password Admin salah! Otorisasi ditolak.';
                          });
                        }
                      },
                    ),
                    if (errorMessage != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFFECACA)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline_rounded, size: 16, color: Color(0xFFEF4444)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                errorMessage!,
                                style: const TextStyle(fontSize: 12, color: Color(0xFFDC2626), fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isVerifying ? null : () => Navigator.pop(ctx, false),
                  child: const Text('Batal', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
                ),
                ElevatedButton.icon(
                  onPressed: isVerifying
                      ? null
                      : () async {
                          final pwd = passwordCtrl.text.trim();
                          if (pwd.isEmpty) {
                            setModalState(() => errorMessage = 'Password tidak boleh kosong');
                            return;
                          }
                          setModalState(() {
                            isVerifying = true;
                            errorMessage = null;
                          });
                          final isValid = await _userRepo.verifyAdminPassword(pwd);
                          if (isValid) {
                            if (ctx.mounted) Navigator.pop(ctx, true);
                          } else {
                            setModalState(() {
                              isVerifying = false;
                              errorMessage = 'Password Admin salah! Otorisasi ditolak.';
                            });
                          }
                        },
                  icon: isVerifying
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Icon(actionIcon, size: 18, color: Colors.white),
                  label: Text(
                    isVerifying ? 'Memverifikasi...' : actionButtonText,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: actionButtonColor,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    return verified ?? false;
  }

  /// Create Database Backup with Admin Password check & optional label
  Future<void> _createBackupFlow() async {
    // 1. Password Verification
    final isAuthorized = await _promptAdminPassword(
      title: 'Konfirmasi Buat Backup',
      subtitle: 'Masukkan password admin untuk membuat salinan file cadangan database sistem.',
      actionButtonText: 'Lanjutkan Backup',
      actionButtonColor: const Color(0xFF10B981),
      actionIcon: Icons.cloud_upload_rounded,
    );

    if (!isAuthorized) return;
    if (!mounted) return;

    // 2. Optional Label Dialog
    final labelCtrl = TextEditingController();
    final shouldProceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Beri Label Versi Backup (Opsional)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Anda dapat memberi catatan versi pada file backup ini (misal: Tutup_Buku_Agustus atau Sebelum_Update):',
                style: TextStyle(fontSize: 12.5, color: Color(0xFF475569)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: labelCtrl,
                decoration: InputDecoration(
                  hintText: 'Misal: Tutup_Buku_Mingguan',
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  prefixIcon: const Icon(Icons.bookmark_outline_rounded, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white),
            child: const Text('Buat Backup Sekarang', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (shouldProceed != true) return;

    setState(() => _isBackingUp = true);
    try {
      final label = labelCtrl.text.trim();
      final backupPath = await _db.createBackup(label: label.isNotEmpty ? label : 'manual');
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
                  'Seluruh data transaksi, pelanggan, layanan, pengeluaran, dan riwayat mesin berhasil dicadangkan.',
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
          SnackBar(content: Text('Gagal membuat backup: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isBackingUp = false);
      }
    }
  }

  /// Restore Database with Auto Safety Snapshot & Admin Password verification
  Future<void> _restoreBackupFlow(File backupFile) async {
    final fileName = backupFile.path.split(Platform.pathSeparator).last;
    final lastModified = DateFormat('dd/MM/yyyy HH:mm').format(backupFile.lastModifiedSync());

    // 1. Strong Warning and Information Dialog
    final proceedToPassword = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 28),
            SizedBox(width: 12),
            Text('PERINGATAN PEMULIHAN DATABASE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Color(0xFFDC2626))),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Anda akan memulihkan database dari file cadangan terpilih. Data aktif saat ini akan digantikan oleh data dari file backup tersebut.',
                style: TextStyle(fontSize: 13.5, color: Color(0xFF334155), height: 1.45),
              ),
              const SizedBox(height: 16),
              // Target Restore File Info
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
                    Text('File yang akan dipulihkan: $fileName', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A))),
                    const SizedBox(height: 4),
                    Text('Waktu Pembuatan Backup: $lastModified', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Auto-Snapshot Guarantee Banner
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFBBF7D0)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.shield_rounded, color: Color(0xFF16A34A), size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Jaminan Keamanan Data (Auto-Snapshot):',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Color(0xFF15803D)),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Sistem akan otomatis mencadangkan versi data Anda saat ini sebelum restore dilakukan, sehingga data lama Anda TIDAK AKAN HILANG dan tetap tersimpan sebagai snapshot cadangan.',
                            style: TextStyle(fontSize: 11.5, color: Color(0xFF166534), height: 1.35),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batalkan', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Lanjut Verifikasi Password', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (proceedToPassword != true) return;

    // 2. Admin Password Verification
    final isAuthorized = await _promptAdminPassword(
      title: 'Otorisasi Pulihkan Database',
      subtitle: 'Masukkan password admin untuk mengonfirmasi pemulihan database dari: $fileName',
      actionButtonText: 'Pulihkan Database Sekarang',
      actionButtonColor: const Color(0xFFDC2626),
      actionIcon: Icons.restore_rounded,
    );

    if (!isAuthorized) return;

    // 3. Execute Restore with Auto Snapshot
    setState(() => _isRestoring = true);
    try {
      final result = await _db.restoreDatabaseWithSnapshot(backupFile.path);
      await _loadData();

      if (mounted) {
        final snapshotFileName = result['snapshotFile']?.split(Platform.pathSeparator).last ?? 'snapshot.db';

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
            content: SizedBox(
              width: 480,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Seluruh data sistem telah berhasil dikembalikan ke versi backup yang dipilih.',
                    style: TextStyle(fontSize: 13, color: Color(0xFF334155), height: 1.4),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('• Versi Dipulihkan: $fileName', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF0F172A))),
                        const SizedBox(height: 4),
                        Text('• Snapshot Data Lama Tersimpan: $snapshotFileName', style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B))),
                      ],
                    ),
                  ),
                ],
              ),
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

  Future<void> _deleteBackup(File backupFile) async {
    final fileName = backupFile.path.split(Platform.pathSeparator).last;
    final isAuthorized = await _promptAdminPassword(
      title: 'Konfirmasi Hapus File Backup',
      subtitle: 'Masukkan password admin untuk menghapus file cadangan: $fileName',
      actionButtonText: 'Hapus File',
      actionButtonColor: Colors.red,
      actionIcon: Icons.delete_outline_rounded,
    );

    if (!isAuthorized) return;

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

  /// Opens Native Windows File Dialog to pick a .db backup file from any folder or USB Flashdisk
  Future<String?> _pickFileNative() async {
    if (Platform.isWindows) {
      try {
        final result = await Process.run('powershell', [
          '-NoProfile',
          '-Command',
          r'''
          Add-Type -AssemblyName System.Windows.Forms
          $dialog = New-Object System.Windows.Forms.OpenFileDialog
          $dialog.Filter = "Database SQLite (*.db;*.sqlite;*.db3)|*.db;*.sqlite;*.db3|Semua File (*.*)|*.*"
          $dialog.Title = "Pilih File Database Cadangan (.db) untuk Diimpor"
          $dialog.InitialDirectory = [Environment]::GetFolderPath("MyDocuments")
          if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
              [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
              Write-Output $dialog.FileName
          }
          '''
        ]);
        final output = (result.stdout as String).trim();
        if (output.isNotEmpty && File(output).existsSync()) {
          return output;
        }
      } catch (e) {
        debugPrint('[BackupSettings] Gagal memanggil native file picker: $e');
      }
    }
    return null;
  }

  /// Import and restore a database file directly from any folder or USB Flashdisk
  Future<void> _importAndRestoreFromFile() async {
    // 1. Try opening native Windows file dialog
    String? selectedPath = await _pickFileNative();

    // 2. If native picker was not triggered or returned empty, fallback to manual path prompt
    if (selectedPath == null || selectedPath.isEmpty) {
      if (!mounted) return;
      final pathController = TextEditingController();
      final customFile = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.file_open_rounded, color: Color(0xFF6366F1), size: 24),
              SizedBox(width: 10),
              Text('Impor File Database Luar (.db)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            ],
          ),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Masukkan path lengkap file database cadangan yang ingin diimpor (misal dari Flashdisk D: atau folder download):',
                  style: TextStyle(fontSize: 12.5, color: Color(0xFF475569), height: 1.4),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: pathController,
                  decoration: InputDecoration(
                    hintText: 'D:\\backup\\laundry_backup.db',
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    prefixIcon: const Icon(Icons.folder_open_rounded, size: 20),
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
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1), foregroundColor: Colors.white),
              child: const Text('Lanjutkan Pemulihan', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );

      if (customFile != null && customFile.isNotEmpty) {
        selectedPath = customFile;
      }
    }

    // 3. Process the chosen file with safety snapshot & admin verification
    if (selectedPath != null && selectedPath.isNotEmpty) {
      final f = File(selectedPath);
      if (await f.exists()) {
        await _restoreBackupFlow(f);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('File database tidak ditemukan di lokasi tersebut.'), backgroundColor: Colors.red),
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

                // 3. Backup History Table / Card with Version Badges
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
            onPressed: _isBackingUp ? null : _createBackupFlow,
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
        // Import & Restore from External File / USB Button
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _importAndRestoreFromFile,
            icon: const Icon(Icons.file_open_rounded, size: 20, color: Color(0xFF6366F1)),
            label: const Text('Pilih & Impor File (.db)', style: TextStyle(color: Color(0xFF6366F1), fontWeight: FontWeight.bold)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFF6366F1), width: 1.5),
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
                  'Riwayat File Backup & Versi Snapshot',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                ),
                const Spacer(),
                Text(
                  '${_availableBackups.length} Versi Cadangan Tersedia',
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
                final isSnapshot = fileName.contains('snapshot_sebelum_restore');
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
                      color: isSnapshot ? const Color(0xFFFFFBEB) : const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: isSnapshot ? const Color(0xFFFDE68A) : const Color(0xFFBBF7D0)),
                    ),
                    child: Icon(
                      isSnapshot ? Icons.history_toggle_off_rounded : Icons.save_rounded,
                      color: isSnapshot ? const Color(0xFFD97706) : const Color(0xFF16A34A),
                      size: 22,
                    ),
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          fileName,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: Color(0xFF0F172A)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: isSnapshot ? const Color(0xFFFEF3C7) : const Color(0xFFDCFCE7),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          isSnapshot ? 'Auto-Snapshot Sebelum Restore' : 'Versi Cadangan',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isSnapshot ? const Color(0xFF92400E) : const Color(0xFF166534),
                          ),
                        ),
                      ),
                    ],
                  ),
                  subtitle: Text(
                    'Dibuat pada: $formattedDate • Ukuran: $sizeStr',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _isRestoring ? null : () => _restoreBackupFlow(file),
                        icon: const Icon(Icons.restore_rounded, size: 16, color: Colors.white),
                        label: const Text('Pulihkan Versi Ini', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isSnapshot ? const Color(0xFFD97706) : const Color(0xFF2563EB),
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
