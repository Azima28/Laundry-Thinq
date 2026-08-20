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
          // 1. SISI KIRI (42%): Form Login Kasir / Admin
          Expanded(
            flex: 42,
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 40),
              child: SingleChildScrollView(
                child: Center(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Brand Header
                          Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  gradient: StyleConstants.primaryGradient,
                                  borderRadius: BorderRadius.circular(10),
                                  boxShadow: [
                                    BoxShadow(
                                      color: StyleConstants.primaryColor.withValues(alpha: 0.3),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.local_laundry_service_rounded,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'SMART LAUNDRY',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w900,
                                      color: StyleConstants.textHeading,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                  Text(
                                    'Aplikasi Kasir & Kontrol Toko',
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

                          const SizedBox(height: 48),

                          // Form Title & Subtitle
                          Text(
                            _isSettingUpAdmin ? 'Buat Akun Admin' : 'Masuk Akun',
                            style: const TextStyle(
                              fontSize: 24,
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
                              fontSize: 13,
                              color: StyleConstants.textMuted,
                            ),
                          ),
                          const SizedBox(height: 32),

                          // Field Username
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
                          const SizedBox(height: 18),

                          // Field Password
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
                          const SizedBox(height: 28),

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
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                          const SizedBox(height: 24),

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

          // VERTICAL DIVIDER
          Container(width: 1, color: StyleConstants.borderLight),

          // 2. SISI KANAN (58%): Dark Hero Panel dengan Garis Naga / Dynamic Wave Art
          Expanded(
            flex: 58,
            child: Stack(
              children: [
                // Background Gradient & Flowing Dragon Lines Canvas
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF0B0F19), Color(0xFF0F172A), Color(0xFF1E293B)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: CustomPaint(
                    painter: FlowingDragonLinesPainter(),
                    size: Size.infinite,
                  ),
                ),

                // Foreground Content (Lugas & Jelas)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 56, vertical: 48),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Spacer(),

                      // Title
                      const Text(
                        'Kelola Usaha Laundry Jadi Lebih Rapi & Cepat',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          height: 1.35,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Catat pesanan pelanggan, pantau mesin cuci dan pengering, serta rekap laporan keuangan toko dalam satu aplikasi.',
                        style: TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 13.5,
                          height: 1.5,
                        ),
                      ),

                      const SizedBox(height: 36),

                      // 3 Feature Cards
                      _buildFeatureCard(
                        icon: Icons.receipt_long_rounded,
                        title: 'Kasir & Pembayaran',
                        desc: 'Input pesanan kiloan & satuan, hitung tagihan otomatis, dan cetak struk.',
                        accentColor: StyleConstants.primaryColor,
                      ),
                      const SizedBox(height: 16),
                      _buildFeatureCard(
                        icon: Icons.local_laundry_service_rounded,
                        title: 'Pantau Mesin Cuci & Pengering',
                        desc: 'Ketahui mesin yang sedang berputar, sisa waktu cuci, dan antrean cucian.',
                        accentColor: StyleConstants.accentCyan,
                      ),
                      const SizedBox(height: 16),
                      _buildFeatureCard(
                        icon: Icons.account_balance_wallet_rounded,
                        title: 'Laporan Omzet & Keuangan',
                        desc: 'Rekap uang masuk, catatan pengeluaran harian, dan data piutang pelanggan.',
                        accentColor: const Color(0xFF10B981),
                      ),

                      const Spacer(),

                      // Bottom Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B).withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF334155)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
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
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureCard({
    required IconData icon,
    required String title,
    required String desc,
    required Color accentColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF334155).withValues(alpha: 0.6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: accentColor),
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
      ),
    );
  }
}

/// CustomPainter to render elegant glowing flowing dragon/wave contour lines
class FlowingDragonLinesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;

    // Line 1: Primary Cyan Ribbon
    final paint1 = Paint()
      ..color = const Color(0xFF06B6D4).withValues(alpha: 0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final path1 = Path();
    path1.moveTo(0, height * 0.75);
    path1.cubicTo(
      width * 0.25, height * 0.60,
      width * 0.45, height * 0.90,
      width * 0.75, height * 0.50,
    );
    path1.cubicTo(
      width * 0.88, height * 0.32,
      width * 0.92, height * 0.25,
      width, height * 0.15,
    );
    canvas.drawPath(path1, paint1);

    // Line 2: Blue Wave Line
    final paint2 = Paint()
      ..color = const Color(0xFF3B82F6).withValues(alpha: 0.20)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;

    final path2 = Path();
    path2.moveTo(0, height * 0.68);
    path2.cubicTo(
      width * 0.28, height * 0.52,
      width * 0.48, height * 0.82,
      width * 0.72, height * 0.42,
    );
    path2.cubicTo(
      width * 0.86, height * 0.22,
      width * 0.95, height * 0.18,
      width, height * 0.08,
    );
    canvas.drawPath(path2, paint2);

    // Line 3: Indigo Contour
    final paint3 = Paint()
      ..color = const Color(0xFF6366F1).withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;

    final path3 = Path();
    path3.moveTo(0, height * 0.82);
    path3.cubicTo(
      width * 0.22, height * 0.68,
      width * 0.42, height * 0.98,
      width * 0.78, height * 0.58,
    );
    path3.cubicTo(
      width * 0.90, height * 0.38,
      width * 0.96, height * 0.30,
      width, height * 0.22,
    );
    canvas.drawPath(path3, paint3);

    // Line 4: Subtle Soft Highlight Line
    final paint4 = Paint()
      ..color = const Color(0xFF38BDF8).withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    final path4 = Path();
    path4.moveTo(0, height * 0.60);
    path4.cubicTo(
      width * 0.30, height * 0.45,
      width * 0.50, height * 0.75,
      width * 0.70, height * 0.35,
    );
    path4.cubicTo(
      width * 0.82, height * 0.15,
      width * 0.90, height * 0.12,
      width, 0,
    );
    canvas.drawPath(path4, paint4);

    // Line 5: Low Ambient Ground Contour
    final paint5 = Paint()
      ..color = const Color(0xFF0EA5E9).withValues(alpha: 0.10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final path5 = Path();
    path5.moveTo(0, height * 0.90);
    path5.cubicTo(
      width * 0.20, height * 0.80,
      width * 0.40, height * 1.05,
      width * 0.80, height * 0.65,
    );
    path5.cubicTo(
      width * 0.92, height * 0.48,
      width * 0.98, height * 0.40,
      width, height * 0.32,
    );
    canvas.drawPath(path5, paint5);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
