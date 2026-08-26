import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../transactions/user_repository.dart';
import '../../utils/style_constants.dart';
import '../../utils/globals.dart';

class LaundrySettingsScreen extends StatefulWidget {
  const LaundrySettingsScreen({Key? key}) : super(key: key);

  @override
  State<LaundrySettingsScreen> createState() => _LaundrySettingsScreenState();
}

class _LaundrySettingsScreenState extends State<LaundrySettingsScreen> {
  final UserRepository _userRepo = UserRepository();
  bool _isAdmin = false;
  bool _loyaltyEnabled = true;
  int _loyaltyThreshold = 5;
  bool _isLoading = true;

  final TextEditingController _thresholdController = TextEditingController();

  final Color primaryColor = StyleConstants.primaryColor;
  final Color backgroundColor = StyleConstants.backgroundColor;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _thresholdController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('user_id');
    bool adminStatus = false;
    if (userId != null) {
      final user = await _userRepo.getUserById(userId);
      adminStatus = user?.role == 'admin';
    }

    setState(() {
      _isAdmin = adminStatus;
      _loyaltyEnabled = prefs.getBool('loyalty_program_enabled') ?? true;
      _loyaltyThreshold = prefs.getInt('loyalty_wash_threshold') ?? 5;
      _thresholdController.text = _loyaltyThreshold.toString();
      _isLoading = false;
    });
  }

  /// Verification Modal for Admin Password
  Future<bool> _promptAdminPassword() async {
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
                    decoration: const BoxDecoration(
                      color: Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                    ),
                    child: const Icon(Icons.admin_panel_settings_rounded, color: Color(0xFFD97706), size: 24),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Verifikasi Hak Akses Admin',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16.5, color: Color(0xFF0F172A)),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Masukkan password admin untuk membuka kunci',
                          style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 440,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Halaman ini memuat pengaturan bisnis krusial (Kupon Gratis & Kelola Mesin). Masukkan password akun Administrator untuk melanjutkan.',
                      style: TextStyle(fontSize: 12.5, color: Color(0xFF475569), height: 1.4),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Password Admin',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: Color(0xFF334155)),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: passwordCtrl,
                      obscureText: isObscure,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Password admin...',
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
                        focusedBorder: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                          borderSide: BorderSide(color: Color(0xFFD97706), width: 1.5),
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
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Batal', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
                ),
                ElevatedButton(
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
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD97706),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                  child: isVerifying
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Verifikasi & Buka Kunci', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ),
              ],
            );
          },
        );
      },
    );

    return verified == true;
  }

  Future<void> _saveLoyaltySettings() async {
    if (!_isAdmin) {
      final unlocked = await _promptAdminPassword();
      if (!unlocked) return;
      setState(() => _isAdmin = true);
    }

    final int? parsed = int.tryParse(_thresholdController.text.trim());
    if (parsed == null || parsed <= 0) {
      Globals.showWarningSnackBar('Target jumlah cuci harus berupa angka minimal 1.');
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('loyalty_program_enabled', _loyaltyEnabled);
    await prefs.setInt('loyalty_wash_threshold', parsed);

    setState(() {
      _loyaltyThreshold = parsed;
    });

    Globals.showSuccessSnackBar('Pengaturan program kupon cuci berhasil disimpan!');
  }

  void _incrementThreshold() async {
    if (!_isAdmin) {
      final unlocked = await _promptAdminPassword();
      if (!unlocked) return;
      setState(() => _isAdmin = true);
    }
    setState(() {
      _loyaltyThreshold++;
      _thresholdController.text = _loyaltyThreshold.toString();
    });
  }

  void _decrementThreshold() async {
    if (!_isAdmin) {
      final unlocked = await _promptAdminPassword();
      if (!unlocked) return;
      setState(() => _isAdmin = true);
    }
    if (_loyaltyThreshold > 1) {
      setState(() {
        _loyaltyThreshold--;
        _thresholdController.text = _loyaltyThreshold.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text('Pengaturan Laundry & Program Kupon', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        backgroundColor: Colors.white,
        foregroundColor: StyleConstants.textHeading,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: StyleConstants.borderLight, height: 1),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Admin Lock Warning Banner (if accessed by non-admin)
                      if (!_isAdmin) ...[
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF2F2),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFFECACA), width: 1.2),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.lock_rounded, color: Color(0xFFDC2626), size: 22),
                              ),
                              const SizedBox(width: 14),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Akses Dibatasi Khusus Administrator',
                                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Color(0xFF991B1B)),
                                    ),
                                    SizedBox(height: 2),
                                    Text(
                                      'Hanya akun Administrator yang berhak mengubah batas kupon dan program gratis.',
                                      style: TextStyle(fontSize: 12, color: Color(0xFFB91C1C)),
                                    ),
                                  ],
                                ),
                              ),
                              ElevatedButton.icon(
                                onPressed: () async {
                                  final unlocked = await _promptAdminPassword();
                                  if (unlocked) {
                                    setState(() => _isAdmin = true);
                                    Globals.showSuccessSnackBar('Akses Administrator berhasil dibuka!');
                                  }
                                },
                                icon: const Icon(Icons.lock_open_rounded, size: 16),
                                label: const Text('Buka Kunci', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFDC2626),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  elevation: 0,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],

                      // 1. Loyalty Program Settings Card
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: StyleConstants.borderLight),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF0F172A).withValues(alpha: 0.03),
                              blurRadius: 12,
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
                                    color: const Color(0xFFD97706).withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(Icons.card_giftcard_rounded, color: Color(0xFFD97706), size: 22),
                                ),
                                const SizedBox(width: 14),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Program Kupon Cuci Gratis',
                                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: StyleConstants.textHeading),
                                      ),
                                      SizedBox(height: 2),
                                      Text(
                                        'Atur otomatis cuci gratis setelah pelanggan mencuci sekian kali',
                                        style: TextStyle(fontSize: 12, color: StyleConstants.textMuted),
                                      ),
                                    ],
                                  ),
                                ),
                                Switch(
                                  value: _loyaltyEnabled,
                                  activeThumbColor: const Color(0xFFD97706),
                                  activeTrackColor: const Color(0xFFFDE68A),
                                  onChanged: _isAdmin
                                      ? (val) {
                                          setState(() => _loyaltyEnabled = val);
                                        }
                                      : (val) async {
                                          final unlocked = await _promptAdminPassword();
                                          if (unlocked) {
                                            setState(() {
                                              _isAdmin = true;
                                              _loyaltyEnabled = val;
                                            });
                                          }
                                        },
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            const Divider(color: StyleConstants.borderLight, height: 1),
                            const SizedBox(height: 20),

                            // Threshold Setting
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Jumlah Cuci untuk Dapat 1x Gratis',
                                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: StyleConstants.textHeading),
                                      ),
                                      SizedBox(height: 3),
                                      Text(
                                        'Berapa kali cuci yang dibutuhkan sebelum kupon gratis bisa dipakai',
                                        style: TextStyle(fontSize: 11.5, color: StyleConstants.textMuted),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: StyleConstants.borderLight),
                                  ),
                                  child: Row(
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.remove_rounded, size: 18),
                                        onPressed: _loyaltyEnabled ? _decrementThreshold : null,
                                        color: const Color(0xFFD97706),
                                      ),
                                      SizedBox(
                                        width: 44,
                                        child: TextField(
                                          controller: _thresholdController,
                                          enabled: _loyaltyEnabled && _isAdmin,
                                          keyboardType: TextInputType.number,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                                          decoration: const InputDecoration(
                                            border: InputBorder.none,
                                            contentPadding: EdgeInsets.zero,
                                          ),
                                          onTap: !_isAdmin
                                              ? () async {
                                                  final unlocked = await _promptAdminPassword();
                                                  if (unlocked) {
                                                    setState(() => _isAdmin = true);
                                                  }
                                                }
                                              : null,
                                          onChanged: (val) {
                                            final numVal = int.tryParse(val);
                                            if (numVal != null && numVal > 0) {
                                              _loyaltyThreshold = numVal;
                                            }
                                          },
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.add_rounded, size: 18),
                                        onPressed: _loyaltyEnabled ? _incrementThreshold : null,
                                        color: const Color(0xFFD97706),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // Preview banner
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: _loyaltyEnabled ? const Color(0xFFFFFBEB) : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: _loyaltyEnabled ? const Color(0xFFFDE68A) : const Color(0xFFE2E8F0),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    _loyaltyEnabled ? Icons.info_outline_rounded : Icons.pause_circle_outline_rounded,
                                    size: 18,
                                    color: _loyaltyEnabled ? const Color(0xFFD97706) : StyleConstants.textMuted,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      _loyaltyEnabled
                                          ? 'Program Aktif: Setiap pelanggan yang sudah mencuci $_loyaltyThreshold kali berhak memakai 1x Cuci Gratis (Rp 0) di kasir POS. Saat diklaim, kupon dipotong $_loyaltyThreshold (bukan di-reset).'
                                          : 'Program Cuci Gratis Nonaktif: Kupon cuci tidak akan dihitung dan opsi klaim di kasir POS disembunyikan.',
                                      style: TextStyle(
                                        fontSize: 12,
                                        height: 1.4,
                                        color: _loyaltyEnabled ? const Color(0xFF78350F) : StyleConstants.textMuted,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),

                            // Save Button
                            Align(
                              alignment: Alignment.centerRight,
                              child: ElevatedButton.icon(
                                onPressed: _saveLoyaltySettings,
                                icon: Icon(_isAdmin ? Icons.save_rounded : Icons.lock_rounded, size: 16),
                                label: Text(
                                  _isAdmin ? 'Simpan Pengaturan Kupon' : 'Buka Kunci untuk Simpan',
                                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFD97706),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  elevation: 0,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // 2. Hardware & Dryer Management Link
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: StyleConstants.borderLight),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF0F172A).withValues(alpha: 0.03),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: () async {
                              if (!_isAdmin) {
                                final unlocked = await _promptAdminPassword();
                                if (!unlocked) return;
                                setState(() => _isAdmin = true);
                              }
                              if (context.mounted) Navigator.pushNamed(context, '/mesin_pengering');
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF97316).withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(Icons.wb_sunny_rounded, color: Color(0xFFF97316), size: 22),
                                  ),
                                  const SizedBox(width: 14),
                                  const Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Kelola Mesin Pengering (Dryer)',
                                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: StyleConstants.textHeading),
                                        ),
                                        SizedBox(height: 2),
                                        Text(
                                          'Atur daftar mesin pengering, nama kustom, dan urutan tampilan kasir',
                                          style: TextStyle(fontSize: 12, color: StyleConstants.textMuted),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.arrow_forward_ios_rounded, color: StyleConstants.textMuted, size: 14),
                                ],
                              ),
                            ),
                          ),
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