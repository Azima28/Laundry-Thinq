import 'package:flutter/material.dart';
import '../../database/models/user_model.dart';
import '../../transactions/user_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../utils/style_constants.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({Key? key}) : super(key: key);

  @override
  _AdminDashboardState createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final UserRepository _userRepository = UserRepository();
  List<UserModel> _users = [];
  bool _isLoading = true;

  final Color primaryColor = StyleConstants.primaryColor;
  final Color backgroundColor = StyleConstants.backgroundColor;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() => _isLoading = true);
    final users = await _userRepository.getAllUsers();
    setState(() {
      _users = users;
      _isLoading = false;
    });
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return StyleConstants.inputDecoration(label, icon);
  }

  Future<void> _showAddUserDialog() async {
    final usernameCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    String selectedRole = 'user';

    return showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          titlePadding: const EdgeInsets.fromLTRB(28, 28, 28, 16),
          contentPadding: const EdgeInsets.symmetric(horizontal: 28),
          actionsPadding: const EdgeInsets.fromLTRB(28, 16, 28, 28),
          title: const Row(
            children: [
              Icon(Icons.person_add_rounded, color: Color(0xFF4E80EE), size: 26),
              SizedBox(width: 12),
              Text(
                'Tambah User Baru',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF0F172A)),
              ),
            ],
          ),
          content: Container(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                TextField(
                  controller: usernameCtrl,
                  decoration: _inputDecoration('Username', Icons.person_outline_rounded),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: passwordCtrl,
                  obscureText: true,
                  decoration: _inputDecoration('Password', Icons.lock_outline_rounded),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedRole,
                  dropdownColor: Colors.white,
                  style: const TextStyle(color: Color(0xFF0F172A), fontSize: 14),
                  decoration: _inputDecoration('Role Hak Akses', Icons.security_rounded),
                  items: const [
                    DropdownMenuItem(value: 'admin', child: Text('Administrator')),
                    DropdownMenuItem(value: 'user', child: Text('Kasir / Operator')),
                  ],
                  onChanged: (val) {
                    if (val != null) setDialogState(() => selectedRole = val);
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Batal', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                elevation: 0,
                shadowColor: Colors.transparent,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                final uname = usernameCtrl.text.trim();
                final pwd = passwordCtrl.text.trim();
                if (uname.isEmpty || pwd.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('⚠️ Mohon isi semua field!')),
                  );
                  return;
                }

                // Check if username already exists
                final users = await _userRepository.getAllUsers();
                if (users.any((u) => u.username.toLowerCase() == uname.toLowerCase())) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('⚠️ Username sudah digunakan!')),
                  );
                  return;
                }

                final success = await _userRepository.createUser(uname, pwd, role: selectedRole);
                if (success) {
                  Navigator.pop(ctx);
                  _loadUsers();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('✅ User baru berhasil dibuat!'), backgroundColor: Colors.green),
                  );
                } else {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('❌ Gagal menambahkan user')),
                  );
                }
              },
              child: const Text('Simpan', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showChangePasswordDialog(UserModel user) async {
    final passwordCtrl = TextEditingController();

    return showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        titlePadding: const EdgeInsets.fromLTRB(28, 28, 28, 16),
        contentPadding: const EdgeInsets.symmetric(horizontal: 28),
        actionsPadding: const EdgeInsets.fromLTRB(28, 16, 28, 28),
        title: Row(
          children: [
            const Icon(Icons.vpn_key_rounded, color: Color(0xFF4E80EE), size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Ganti Password: ${user.username}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF0F172A)),
              ),
            ),
          ],
        ),
        content: Container(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              TextField(
                controller: passwordCtrl,
                obscureText: true,
                decoration: _inputDecoration('Password Baru', Icons.vpn_key_outlined),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Batal', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
              elevation: 0,
              shadowColor: Colors.transparent,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              final pwd = passwordCtrl.text.trim();
              if (pwd.isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('⚠️ Mohon isi password baru')),
                );
                return;
              }

              final success = await _userRepository.changePassword(user.id!, pwd);
              if (success) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('✅ Password berhasil diubah!'), backgroundColor: Colors.green),
                );
              } else {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('❌ Gagal mengubah password')),
                );
              }
            },
            child: const Text('Simpan', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_id');
    Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
  }

  Widget _buildStatsRibbon() {
    final totalUsers = _users.length;
    final adminCount = _users.where((u) => u.role.toLowerCase() == 'admin').length;
    final operatorCount = totalUsers - adminCount;

    return Row(
      children: [
        Expanded(
          child: _buildRibbonCard(
            title: 'Total Pengguna',
            value: '$totalUsers Akun',
            icon: Icons.people_alt_rounded,
            color: StyleConstants.primaryColor,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildRibbonCard(
            title: 'Administrator',
            value: '$adminCount User',
            icon: Icons.admin_panel_settings_rounded,
            color: StyleConstants.secondaryColor,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildRibbonCard(
            title: 'Operator / Kasir',
            value: '$operatorCount Staff',
            icon: Icons.person_outline_rounded,
            color: StyleConstants.successColor,
          ),
        ),
      ],
    );
  }

  Widget _buildRibbonCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: StyleConstants.borderLight),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
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
        title: const Text('Portal Kontrol Admin', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.5, fontSize: 22)),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: StyleConstants.borderLight, height: 1),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_rounded, color: Color(0xFF64748B)),
            tooltip: 'Pengaturan',
            style: IconButton.styleFrom(hoverColor: const Color(0xFFF1F5F9)),
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
            tooltip: 'Keluar Sistem',
            style: IconButton.styleFrom(hoverColor: Colors.red.withOpacity(0.05)),
            onPressed: _logout,
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Left Panel: Quick Actions (330px width for layout optimization)
                Container(
                  width: 330,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(right: BorderSide(color: StyleConstants.borderLight)),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Aksi Cepat Admin',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF475569), letterSpacing: 0.5),
                        ),
                        const SizedBox(height: 12),
                        _buildActionTile(
                          title: 'Kelola Item Laundry',
                          desc: 'Tambah & ubah variasi paket kiloan/satuan',
                          icon: Icons.local_laundry_service_rounded,
                          color: primaryColor,
                          route: '/tambah_item',
                        ),
                        const SizedBox(height: 12),
                        _buildActionTile(
                          title: 'Kelola Item Setrika',
                          desc: 'Tambah & ubah variasi tarif gosok pakaian',
                          icon: Icons.iron_rounded,
                          color: const Color(0xFFF97316),
                          route: '/tambah_item_gosok',
                        ),
                        const SizedBox(height: 16),
                        const Divider(color: Color(0xFFF1F5F9)),
                        const SizedBox(height: 16),
                        // Quick guide
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.security_rounded, size: 16, color: Color(0xFF64748B)),
                                  SizedBox(width: 8),
                                  Text(
                                    'Keamanan Hak Akses',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF1E293B)),
                                  ),
                                ],
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Buat akun operator/kasir agar mereka dapat melakukan input transaksi, sementara pengaturan sistem, inventaris, dan ThinQ tetap aman terkunci untuk Admin.',
                                style: TextStyle(fontSize: 11, color: Color(0xFF64748B), height: 1.45),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Database/Storage Card Info (New widget to make layout denser)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: StyleConstants.borderLight),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.storage_rounded, size: 16, color: StyleConstants.primaryColor),
                                  SizedBox(width: 8),
                                  Text(
                                    'Penyimpanan Lokal',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF1E293B)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Engine: SQLite FFI\nStatus: Terhubung\nKeamanan: Enkripsi Standar',
                                style: TextStyle(fontSize: 11, color: Colors.grey[600], height: 1.4),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // 2. Right Panel: User Management list (Expanded with stats ribbon)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(20.0), // reduced from 32 for dense layout
                    child: Container(
                      padding: const EdgeInsets.all(20), // reduced from 28
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: StyleConstants.borderLight),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.02),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          )
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Manajemen Pengguna Aplikasi',
                                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                                  ),
                                  SizedBox(height: 3),
                                  Text(
                                    'Daftar akun administrator dan kasir terdaftar',
                                    style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
                                  ),
                                ],
                              ),
                              ElevatedButton.icon(
                                onPressed: _showAddUserDialog,
                                icon: const Icon(Icons.add_rounded, color: Colors.white, size: 18),
                                label: const Text('Tambah User Baru', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: primaryColor,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shadowColor: Colors.transparent,
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _buildStatsRibbon(), // Stats Ribbon inserted here
                          const SizedBox(height: 16),
                          const Divider(color: Color(0xFFF1F5F9)),
                          const SizedBox(height: 12),

                          Expanded(
                            child: _users.isEmpty
                                ? const Center(child: Text('Belum ada pengguna terdaftar.'))
                                : ListView.builder(
                                    itemCount: _users.length,
                                    itemBuilder: (context, index) {
                                      final user = _users[index];
                                      return _buildUserCard(user);
                                    },
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

  Widget _buildUserCard(UserModel user) {
    final isAdmin = user.role.toLowerCase() == 'admin';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: StyleConstants.borderLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.005),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: isAdmin ? primaryColor.withValues(alpha: 0.08) : const Color(0xFFF1F5F9),
              child: Icon(
                isAdmin ? Icons.admin_panel_settings_rounded : Icons.person_rounded,
                color: isAdmin ? primaryColor : const Color(0xFF64748B),
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.username,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: isAdmin ? Colors.blue.withValues(alpha: 0.08) : Colors.purple.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          isAdmin ? 'Admin' : 'Operator / Kasir',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                            color: isAdmin ? const Color(0xFF1D4ED8) : const Color(0xFF6B21A8),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: user.isActive ? const Color(0xFF10B981).withValues(alpha: 0.08) : const Color(0xFFF43F5E).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          user.isActive ? 'Aktif' : 'Nonaktif',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                            color: user.isActive ? const Color(0xFF065F46) : const Color(0xFF991B1B),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.vpn_key_rounded, color: Color(0xFF64748B), size: 16),
              tooltip: 'Ubah Password',
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFFF1F5F9),
                hoverColor: const Color(0xFFE2E8F0),
                padding: const EdgeInsets.all(8),
              ),
              onPressed: () => _showChangePasswordDialog(user),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionTile({
    required String title,
    required String desc,
    required IconData icon,
    required Color color,
    required String route,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: StyleConstants.borderLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.005),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          hoverColor: const Color(0xFFF8FAFC),
          onTap: () => Navigator.pushNamed(context, route),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13.5,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        desc,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF64748B),
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, size: 16, color: Color(0xFF94A3B8)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}