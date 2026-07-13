import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../transactions/user_repository.dart';
// user_model import removed (unused)

class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // Palet Warna Konsisten
  final Color _primaryColor = const Color(0xFF4E80EE);
  final Color _backgroundColor = const Color(0xFFF5F7FA);

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

  Future<void> _checkAdmin() async {
    final hasAdmin = await _userRepository.checkAdminExists();
    if (!hasAdmin) {
      setState(() {
        _isSettingUpAdmin = true;
      });
    }
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      if (_isSettingUpAdmin) {
        // Create admin account
        final success = await _userRepository.createAdmin(
          _usernameController.text,
          _passwordController.text,
        );

        if (success) {
          // Navigasi ke Dashboard setelah setup berhasil
          // Coba login otomatis setelah setup
          final user = await _userRepository.login(
             _usernameController.text,
             _passwordController.text,
           );

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Akun Admin berhasil dibuat. Silakan login kembali.')),
          );
          
          if (user != null) {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setInt('user_id', user.id!);
              // Navigate based on role
              if (user.role == 'admin') {
                Navigator.pushReplacementNamed(context, '/admin_dashboard', arguments: user);
              } else {
                Navigator.pushReplacementNamed(context, '/dashboard', arguments: user);
              }
          } else {
             // Jika gagal login otomatis, tampilkan layar login biasa
             setState(() {
              _isSettingUpAdmin = false;
             });
          }

        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Gagal membuat akun admin. Pastikan password kuat.')),
          );
        }
      } else {
        // Regular login
        final user = await _userRepository.login(
          _usernameController.text,
          _passwordController.text,
        );

        if (user != null) {
          // Save user ID to SharedPreferences
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt('user_id', user.id!);
          // Navigate based on role
          if (user.role == 'admin') {
            Navigator.pushReplacementNamed(context, '/admin_dashboard', arguments: user);
          } else {
            Navigator.pushReplacementNamed(context, '/dashboard', arguments: user);
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Username atau password salah')),
          );
        }
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor, // Background lembut
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Icon dan Judul Header
                Icon(
                  Icons.local_laundry_service_rounded,
                  size: 80,
                  color: _primaryColor,
                ),
                const SizedBox(height: 16),
                Text(
                  _isSettingUpAdmin
                      ? 'Setup Akun Admin Pertama'
                      : 'Selamat Datang Kembali!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: _primaryColor,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _isSettingUpAdmin
                      ? 'Buat kredensial admin untuk melanjutkan.'
                      : 'Silakan login untuk mengakses sistem.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 40),

                // Login Card Container
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: _primaryColor.withOpacity(0.1),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // Field Username
                      TextFormField(
                        controller: _usernameController,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Username tidak boleh kosong';
                          }
                          return null;
                        },
                        decoration: _inputDecoration(
                          'Username',
                          Icons.person_rounded,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Field Password
                      TextFormField(
                        controller: _passwordController,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Password tidak boleh kosong';
                          }
                          return null;
                        },
                        decoration: _inputDecoration(
                          'Password',
                          Icons.lock_rounded,
                          isPassword: true,
                        ),
                        obscureText: _obscureText,
                      ),
                      const SizedBox(height: 30),

                      // Tombol Login/Setup
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _login,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primaryColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 5,
                            shadowColor: _primaryColor.withOpacity(0.4),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                                )
                              : Text(
                                  _isSettingUpAdmin ? 'BUAT ADMIN' : 'LOGIN',
                                  style: const TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon, {bool isPassword = false}) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: Colors.grey[600]),
      filled: true,
      fillColor: _backgroundColor,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: _primaryColor, width: 2),
      ),
      prefixIcon: Icon(icon, color: _primaryColor.withOpacity(0.7)),
      suffixIcon: isPassword
          ? IconButton(
              icon: Icon(
                _obscureText ? Icons.visibility_off : Icons.visibility,
                color: Colors.grey,
              ),
              onPressed: () {
                setState(() {
                  _obscureText = !_obscureText;
                });
              },
            )
          : null,
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}
