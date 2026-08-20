import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../transactions/user_repository.dart';
import '../../utils/style_constants.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _userRepository = UserRepository();
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = false;
  bool _isSettingUpAdmin = false;
  bool _obscureText = true;

  @override
  void initState() {
    super.initState();
    _checkAdmin();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _checkAdmin() async {
    final hasAdmin = await _userRepository.checkAdminExists();
    if (!hasAdmin && mounted) {
      setState(() {
        _isSettingUpAdmin = true;
      });
    }
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (_isSettingUpAdmin) {
        final success = await _userRepository.createAdmin(
          _usernameController.text.trim(),
          _passwordController.text.trim(),
        );

        if (success) {
          final user = await _userRepository.login(
            _usernameController.text.trim(),
            _passwordController.text.trim(),
          );

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Akun Admin berhasil dibuat.'),
                backgroundColor: StyleConstants.successColor,
              ),
            );
          }

          if (user != null) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setInt('user_id', user.id!);
            if (mounted) {
              if (user.role == 'admin') {
                Navigator.pushReplacementNamed(context, '/admin_dashboard', arguments: user);
              } else {
                Navigator.pushReplacementNamed(context, '/dashboard', arguments: user);
              }
            }
          } else {
            if (mounted) {
              setState(() {
                _isSettingUpAdmin = false;
              });
            }
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Gagal membuat akun admin.'),
                backgroundColor: StyleConstants.dangerColor,
              ),
            );
          }
        }
      } else {
        final user = await _userRepository.login(
          _usernameController.text.trim(),
          _passwordController.text.trim(),
        );

        if (user != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt('user_id', user.id!);
          if (mounted) {
            if (user.role == 'admin') {
              Navigator.pushReplacementNamed(context, '/admin_dashboard', arguments: user);
            } else {
              Navigator.pushReplacementNamed(context, '/dashboard', arguments: user);
            }
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Username atau password tidak cocok.'),
                backgroundColor: StyleConstants.dangerColor,
              ),
            );
          }
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: StyleConstants.backgroundColor,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. SISI KIRI (42%): Panel Pengenalan Aplikasi (Bahasa Ramah & Jelas)
          Expanded(
            flex: 42,
            child: Container(
              color: StyleConstants.sidebarBackground,
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Logo & Nama Toko
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: StyleConstants.primaryColor,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.local_laundry_service_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'SMART LAUNDRY',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.0,
                            ),
                          ),
                          Text(
                            'Aplikasi Kasir & Kontrol Toko',
                            style: TextStyle(
                              color: StyleConstants.accentCyan,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  const Spacer(),

                  // Judul & Deskripsi Utama (Lugas & Mudah Dipahami)
                  const Text(
                    'Kelola Usaha Laundry Jadi Lebih Rapi & Cepat',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      height: 1.35,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Catat pesanan pelanggan, pantau mesin cuci dan pengering, serta rekap laporan keuangan toko dalam satu aplikasi.',
                    style: TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),

                  const SizedBox(height: 28),

                  // 3 Fitur Utama (Bahasa Sehari-hari)
                  _buildSimpleFeatureItem(
                    icon: Icons.receipt_long_rounded,
                    title: 'Kasir & Pembayaran',
                    desc: 'Input pesanan kiloan & satuan, hitung tagihan otomatis, dan cetak struk.',
                  ),
                  const SizedBox(height: 16),
                  _buildSimpleFeatureItem(
                    icon: Icons.local_laundry_service_rounded,
                    title: 'Pantau Mesin Cuci & Pengering',
                    desc: 'Ketahui mesin yang sedang berputar, sisa waktu cuci, dan antrean cucian.',
                  ),
                  const SizedBox(height: 16),
                  _buildSimpleFeatureItem(
                    icon: Icons.account_balance_wallet_rounded,
                    title: 'Laporan Omzet & Keuangan',
                    desc: 'Rekap uang masuk, catatan pengeluaran harian, dan data piutang pelanggan.',
                  ),

                  const Spacer(),

                  // Footer Keterangan Sistem
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.check_circle_rounded, size: 14, color: StyleConstants.successColor),
                        SizedBox(width: 8),
                        Text(
                          'Sistem Kasir Offline · Data Tersimpan di Komputer Toko',
                          style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 11.5, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 2. SISI KANAN (58%): Kartu Login Kasir (Rapi & Proporsional)
          Expanded(
            flex: 58,
            child: Container(
              color: StyleConstants.backgroundColor,
              alignment: Alignment.center,
              padding: const EdgeInsets.all(32),
              child: SingleChildScrollView(
                child: Center(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 440),
                    padding: const EdgeInsets.all(36),
                    decoration: StyleConstants.cardDecoration(
                      withShadow: true,
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Header Form
                          Text(
                            _isSettingUpAdmin ? 'Buat Akun Admin' : 'Masuk Akun',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: StyleConstants.textHeading,
                              letterSpacing: -0.4,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _isSettingUpAdmin
                                ? 'Buat akun pengelola utama untuk memulai toko.'
                                : 'Masukkan username dan password akun Anda.',
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: StyleConstants.textMuted,
                            ),
                          ),
                          const SizedBox(height: 28),

                          // Kolom Username
                          TextFormField(
                            controller: _usernameController,
                            autofocus: true,
                            textInputAction: TextInputAction.next,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Username wajib diisi';
                              }
                              return null;
                            },
                            decoration: StyleConstants.inputDecoration(
                              'Username',
                              Icons.person_outline_rounded,
                              hintText: 'Ketik nama pengguna...',
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Kolom Password
                          TextFormField(
                            controller: _passwordController,
                            obscureText: _obscureText,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _isLoading ? null : _login(),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Password wajib diisi';
                              }
                              return null;
                            },
                            decoration: StyleConstants.inputDecoration(
                              'Password',
                              Icons.lock_outline_rounded,
                              hintText: 'Ketik password akun...',
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscureText ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                  size: 18,
                                  color: StyleConstants.textMuted,
                                ),
                                onPressed: () => setState(() => _obscureText = !_obscureText),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Tombol Masuk
                          ElevatedButton(
                            onPressed: _isLoading ? null : _login,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: StyleConstants.primaryColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              elevation: 0,
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2.2,
                                    ),
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.login_rounded, size: 18),
                                      const SizedBox(width: 8),
                                      Text(
                                        _isSettingUpAdmin ? 'Simpan & Masuk' : 'Masuk ke Kasir',
                                        style: const TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                          const SizedBox(height: 20),

                          // Keterangan Akses Aman
                          const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.lock_outline_rounded, size: 14, color: StyleConstants.textMuted),
                              SizedBox(width: 6),
                              Text(
                                'Akses Aman & Terproteksi',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: StyleConstants.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSimpleFeatureItem({
    required IconData icon,
    required String title,
    required String desc,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: StyleConstants.accentCyan),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                desc,
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
