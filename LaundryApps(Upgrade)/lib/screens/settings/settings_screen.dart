import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../transactions/user_repository.dart';
import '../../utils/style_constants.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  final Color primaryColor = StyleConstants.primaryColor;
  final Color backgroundColor = StyleConstants.backgroundColor;

  Future<bool> _checkAdminAccess() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('user_id');
    if (userId == null) return false;
    final user = await UserRepository().getUserById(userId);
    return user?.role == 'admin';
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.canPop(context);

    Widget content = FutureBuilder<bool>(
      future: _checkAdminAccess(),
      builder: (context, snapshot) {
        final isAdmin = snapshot.data ?? false;

        return Padding(
          padding: EdgeInsets.all(canPop ? 32.0 : 0.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!canPop) ...[
                const Text(
                  'Kategori Pengaturan Sistem',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF475569),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 24),
              ],
              Expanded(
                child: GridView.count(
                  crossAxisCount: 3,
                  crossAxisSpacing: 20,
                  mainAxisSpacing: 20,
                  childAspectRatio: 1.45,
                  children: [
                    _buildSettingsCard(
                      context,
                      title: 'WhatsApp Notifications',
                      description: 'Konfigurasi QR Code login WA & edit template pesan otomatis',
                      icon: Icons.chat_rounded,
                      color: const Color(0xFF10B981),
                      route: '/wa_settings',
                    ),
                    _buildSettingsCard(
                      context,
                      title: 'Laundry Settings',
                      description: 'Konfigurasi harga default & set durasi monitoring standby',
                      icon: Icons.local_laundry_service_rounded,
                      color: primaryColor,
                      route: '/laundry_settings',
                    ),
                    _buildSettingsCard(
                      context,
                      title: 'Printer Settings',
                      description: 'Konfigurasi thermal printer kasir & ukuran struk belanja',
                      icon: Icons.print_rounded,
                      color: const Color(0xFF6366F1),
                      route: '/printer_settings',
                    ),
                    _buildSettingsCard(
                      context,
                      title: 'Payment Gateway',
                      description: 'Konfigurasi pembayaran e-wallet QRIS & merchant token',
                      icon: Icons.payment_rounded,
                      color: const Color(0xFFF97316),
                      route: '/payment_settings',
                    ),
                    if (isAdmin)
                      _buildSettingsCard(
                        context,
                        title: 'LG ThinQ Integration',
                        description: 'Otorisasi & sinkronisasi cloud akun LG ThinQ mesin laundry',
                        icon: Icons.cloud_sync_rounded,
                        color: const Color(0xFFEF4444),
                        route: '/lg_thinq_settings',
                      ),
                    if (isAdmin)
                      _buildSettingsCard(
                        context,
                        title: 'Bardi Tuya Integration',
                        description: 'Otorisasi & sinkronisasi stopkontak pintar Bardi mesin pengering',
                        icon: Icons.settings_input_component_rounded,
                        color: const Color(0xFF0284C7),
                        route: '/bardi_tuya_settings',
                      ),
                    _buildSettingsCard(
                      context,
                      title: 'Tentang Aplikasi',
                      description: 'Status diagnostic server kasir & informasi versi aplikasi',
                      icon: Icons.info_outline_rounded,
                      color: const Color(0xFF64748B),
                      route: null,
                      onTap: () => _showAboutDialog(context),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }
    );

    if (canPop) {
      return Scaffold(
        backgroundColor: backgroundColor,
        appBar: AppBar(
          title: const Text('Pengaturan Sistem', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF0F172A),
          elevation: 0,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(color: const Color(0xFFE2E8F0), height: 1),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: content,
      );
    } else {
      return content;
    }
  }

  Widget _buildSettingsCard(
    BuildContext context, {
    required String title,
    required String description,
    required IconData icon,
    required Color color,
    required String? route,
    VoidCallback? onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: StyleConstants.borderLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.01),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          hoverColor: const Color(0xFFF8FAFC),
          onTap: () {
            if (route != null) {
              Navigator.pushNamed(context, route);
            } else if (onTap != null) {
              onTap();
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(icon, color: color, size: 24),
                    ),
                    const Spacer(),
                    const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFF94A3B8), size: 14),
                  ],
                ),
                const Spacer(),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        titlePadding: const EdgeInsets.fromLTRB(28, 28, 28, 16),
        contentPadding: const EdgeInsets.symmetric(horizontal: 28),
        actionsPadding: const EdgeInsets.fromLTRB(28, 16, 28, 28),
        title: const Row(
          children: [
            Icon(Icons.info_outline_rounded, color: Color(0xFF0F172A), size: 26),
            SizedBox(width: 12),
            Text('Smart Laundry v2.0', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF0F172A))),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sistem Monitoring Laundry Mandiri & Notifikasi WhatsApp Otomatis.', style: TextStyle(fontSize: 13.5, color: Color(0xFF475569), height: 1.4)),
            SizedBox(height: 20),
            Text('Versi: 2.0.0 (Desktop Redesign Edition)', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
            Text('Developer: Antigravity AI & Team', style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B))),
            SizedBox(height: 16),
            Divider(color: Color(0xFFF1F5F9)),
            SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.link_rounded, size: 14, color: Color(0xFF64748B)),
                SizedBox(width: 8),
                Text('Koneksi Server: http://localhost:5000', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
              ],
            ),
            SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.link_rounded, size: 14, color: Color(0xFF64748B)),
                SizedBox(width: 8),
                Text('WhatsApp Service: http://localhost:3000', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
              ],
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
              elevation: 0,
              shadowColor: Colors.transparent,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Tutup', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
