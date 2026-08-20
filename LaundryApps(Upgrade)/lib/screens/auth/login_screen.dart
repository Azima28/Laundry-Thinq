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
      body: Stack(
        children: [
          // 1. FULL-SCREEN UNIFIED DARK CANVAS + FLOWING DRAGON WAVE LINES
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF070B14), Color(0xFF0B0F19), Color(0xFF111827)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: CustomPaint(
              painter: CenterDragonLinesPainter(),
              size: Size.infinite,
            ),
          ),

          // 2. CENTERED ELEGANT LOGIN CARD (MACOS / ENTERPRISE DESKTOP STYLE)
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 440),
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 42),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: const Color(0xFF334155),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.55),
                        blurRadius: 36,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Centered Brand Logo
                        Center(
                          child: Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              gradient: StyleConstants.primaryGradient,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: StyleConstants.primaryColor.withValues(alpha: 0.4),
                                  blurRadius: 14,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.local_laundry_service_rounded,
                              color: Colors.white,
                              size: 30,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Brand Title
                        const Center(
                          child: Text(
                            'SMART LAUNDRY',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                        const Center(
                          child: Text(
                            'Aplikasi Kasir & Kontrol Toko',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: StyleConstants.accentCyan,
                            ),
                          ),
                        ),

                        const SizedBox(height: 32),
                        const Divider(height: 1, color: Color(0xFF1E293B)),
                        const SizedBox(height: 28),

                        // Form Heading
                        Text(
                          _isSettingUpAdmin ? 'Buat Akun Admin' : 'Masuk Akun',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _isSettingUpAdmin
                              ? 'Buat akun pengelola utama untuk memulai toko.'
                              : 'Masukkan username dan password akun Anda.',
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Username Field
                        TextFormField(
                          controller: _usernameController,
                          autofocus: true,
                          style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600),
                          textInputAction: TextInputAction.next,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Username wajib diisi';
                            }
                            return null;
                          },
                          decoration: _buildDarkInputDecoration(
                            'Username',
                            Icons.person_outline_rounded,
                            hintText: 'Ketik nama pengguna...',
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Password Field
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscureText,
                          style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600),
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _isLoading ? null : _login(),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Password wajib diisi';
                            }
                            return null;
                          },
                          decoration: _buildDarkInputDecoration(
                            'Password',
                            Icons.lock_outline_rounded,
                            hintText: 'Ketik password akun...',
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscureText ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                size: 18,
                                color: const Color(0xFF94A3B8),
                              ),
                              onPressed: () => setState(() => _obscureText = !_obscureText),
                            ),
                          ),
                        ),
                        const SizedBox(height: 26),

                        // Submit Button
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
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                        const SizedBox(height: 24),

                        // Security Footer
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.shield_outlined, size: 14, color: Color(0xFF94A3B8)),
                            SizedBox(width: 6),
                            Text(
                              'Sistem Kasir Offline · Akses Terproteksi',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF94A3B8),
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
        ],
      ),
    );
  }

  InputDecoration _buildDarkInputDecoration(String label, IconData icon, {String? hintText, Widget? suffixIcon}) {
    return InputDecoration(
      labelText: label,
      hintText: hintText,
      labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13, fontWeight: FontWeight.w500),
      floatingLabelStyle: const TextStyle(color: StyleConstants.accentCyan, fontWeight: FontWeight.w700),
      hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF334155)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF334155)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: StyleConstants.accentCyan, width: 1.8),
      ),
      prefixIcon: Icon(icon, color: const Color(0xFF94A3B8), size: 18),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: const Color(0xFF1E293B),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }
}

/// CustomPainter to render full-screen flowing dragon/wave lines harmonized for centered layout
class CenterDragonLinesPainter extends CustomPainter {
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
    path1.moveTo(0, height * 0.70);
    path1.cubicTo(
      width * 0.20, height * 0.85,
      width * 0.45, height * 0.45,
      width * 0.70, height * 0.75,
    );
    path1.cubicTo(
      width * 0.85, height * 0.90,
      width * 0.92, height * 0.35,
      width, height * 0.20,
    );
    canvas.drawPath(path1, paint1);

    // Line 2: Blue Wave Line
    final paint2 = Paint()
      ..color = const Color(0xFF3B82F6).withValues(alpha: 0.20)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;

    final path2 = Path();
    path2.moveTo(0, height * 0.62);
    path2.cubicTo(
      width * 0.22, height * 0.78,
      width * 0.48, height * 0.38,
      width * 0.68, height * 0.68,
    );
    path2.cubicTo(
      width * 0.82, height * 0.82,
      width * 0.94, height * 0.25,
      width, height * 0.12,
    );
    canvas.drawPath(path2, paint2);

    // Line 3: Indigo Contour
    final paint3 = Paint()
      ..color = const Color(0xFF6366F1).withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;

    final path3 = Path();
    path3.moveTo(0, height * 0.78);
    path3.cubicTo(
      width * 0.18, height * 0.92,
      width * 0.42, height * 0.52,
      width * 0.74, height * 0.82,
    );
    path3.cubicTo(
      width * 0.88, height * 0.95,
      width * 0.96, height * 0.45,
      width, height * 0.28,
    );
    canvas.drawPath(path3, paint3);

    // Line 4: Ambient Soft Wave
    final paint4 = Paint()
      ..color = const Color(0xFF38BDF8).withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    final path4 = Path();
    path4.moveTo(0, height * 0.48);
    path4.cubicTo(
      width * 0.25, height * 0.65,
      width * 0.52, height * 0.25,
      width * 0.75, height * 0.55,
    );
    path4.cubicTo(
      width * 0.86, height * 0.70,
      width * 0.92, height * 0.15,
      width, 0,
    );
    canvas.drawPath(path4, paint4);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
