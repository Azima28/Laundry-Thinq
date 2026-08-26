import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/machine_status_service.dart';
import '../../transactions/user_repository.dart';
import '../../utils/style_constants.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final MachineStatusService _machineStatus = MachineStatusService.instance;
  bool _isAdmin = false;
  bool _isLoading = true;

  final Color primaryColor = StyleConstants.primaryColor;
  final Color backgroundColor = StyleConstants.backgroundColor;

  @override
  void initState() {
    super.initState();
    _checkAdminAccess();
  }

  Future<void> _checkAdminAccess() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('user_id');
    if (userId != null) {
      final user = await UserRepository().getUserById(userId);
      if (mounted) {
        setState(() {
          _isAdmin = user?.role == 'admin';
          _isLoading = false;
        });
      }
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.canPop(context);

    Widget content = _isLoading
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: EdgeInsets.all(canPop ? 28.0 : 20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Top System Control Banner
                _buildTopControlBanner(),
                const SizedBox(height: 28),

                // 2. Section 1: Hardware & IoT Mesin
                _buildSectionHeader(
                  title: 'Integrasi Hardware & IoT Mesin',
                  subtitle: 'Monitoring otomatis mesin cuci, pengering, dan printer kasir',
                  icon: Icons.hub_rounded,
                  iconColor: const Color(0xFF0284C7),
                ),
                const SizedBox(height: 12),
                _buildCardsGrid([
                  if (_isAdmin)
                    _SettingsItemData(
                      title: 'LG ThinQ & Mesin Cuci',
                      description: 'Sinkronisasi akun PAT & pemetaan nomor mesin cuci toko',
                      icon: Icons.local_laundry_service_rounded,
                      color: const Color(0xFFEF4444),
                      statusBadge: _machineStatus.thinqOk ? 'Cloud Terhubung' : 'Standby / Auth',
                      statusColor: _machineStatus.thinqOk ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                      route: '/lg_thinq_settings',
                    ),
                  if (_isAdmin)
                    _SettingsItemData(
                      title: 'Bardi Tuya & Mesin Pengering',
                      description: 'Kontrol stopkontak pintar & pemetaan mesin pengering',
                      icon: Icons.wb_sunny_rounded,
                      color: const Color(0xFFEA580C),
                      statusBadge: _machineStatus.bardiOk ? 'Relay Aktif' : 'Standby',
                      statusColor: _machineStatus.bardiOk ? const Color(0xFF10B981) : const Color(0xFF64748B),
                      route: '/bardi_tuya_settings',
                    ),
                  _SettingsItemData(
                    title: 'Printer Thermal Kasir',
                    description: 'Atur koneksi printer ESC/POS & layout cetak nota struk',
                    icon: Icons.print_rounded,
                    color: const Color(0xFF6366F1),
                    statusBadge: 'ESC/POS Ready',
                    statusColor: const Color(0xFF6366F1),
                    route: '/printer_settings',
                  ),
                ]),
                const SizedBox(height: 28),

                // 3. Section 2: Transaksi & Komunikasi Pelanggan
                _buildSectionHeader(
                  title: 'Transaksi & Komunikasi Pelanggan',
                  subtitle: 'Pengaturan WhatsApp gateway dan saluran pembayaran digital QRIS',
                  icon: Icons.contactless_rounded,
                  iconColor: const Color(0xFF10B981),
                ),
                const SizedBox(height: 12),
                _buildCardsGrid([
                  _SettingsItemData(
                    title: 'WhatsApp Notification Hub',
                    description: 'Scan QR login WA, edit template selesai & outbox otomatis',
                    icon: Icons.chat_rounded,
                    color: const Color(0xFF10B981),
                    statusBadge: _machineStatus.waOk ? 'WhatsApp Terhubung' : 'Scan QR Login',
                    statusColor: _machineStatus.waOk ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                    route: '/wa_settings',
                  ),
                  _SettingsItemData(
                    title: 'Payment Gateway (QRIS)',
                    description: 'Konfigurasi pembayaran e-wallet QRIS & merchant token',
                    icon: Icons.payment_rounded,
                    color: const Color(0xFFF97316),
                    statusBadge: 'Midtrans Merchant',
                    statusColor: const Color(0xFFF97316),
                    route: '/payment_settings',
                  ),
                ]),
                const SizedBox(height: 28),

                // 4. Section 3: Layanan & Database Sistem
                _buildSectionHeader(
                  title: 'Layanan, Database & Pemeliharaan',
                  subtitle: 'Konfigurasi tarif harga, manajemen cadangan database, dan info aplikasi',
                  icon: Icons.admin_panel_settings_rounded,
                  iconColor: const Color(0xFF2563EB),
                ),
                const SizedBox(height: 12),
                _buildCardsGrid([
                  if (_isAdmin)
                    _SettingsItemData(
                      title: 'Tarif Layanan & Program Kupon',
                      description: 'Atur program cuci gratis 5x, target kupon, dan kelola mesin pengering',
                      icon: Icons.card_giftcard_rounded,
                      color: const Color(0xFFD97706),
                      statusBadge: 'Admin Only',
                      statusColor: const Color(0xFFD97706),
                      route: '/laundry_settings',
                    ),
                  if (_isAdmin)
                    _SettingsItemData(
                      title: 'Backup & Restore Database',
                      description: 'Cadangkan data transaksi ke file .db dan pulihkan database',
                      icon: Icons.storage_rounded,
                      color: const Color(0xFF0D9488),
                      statusBadge: 'SQLite Terenkripsi',
                      statusColor: const Color(0xFF0D9488),
                      route: '/backup_settings',
                    ),
                  _SettingsItemData(
                    title: 'Tentang Aplikasi & Diagnostik',
                    description: 'Status server kasir, lisensi aplikasi, dan informasi versi',
                    icon: Icons.info_outline_rounded,
                    color: const Color(0xFF64748B),
                    statusBadge: 'v2.4.0 Desktop',
                    statusColor: const Color(0xFF64748B),
                    route: null,
                    onTap: () => _showAboutDialog(context),
                  ),
                ]),
              ],
            ),
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
            icon: const Icon(Icons.arrow_back_rounded, size: 22),
            tooltip: 'Kembali',
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: content,
      );
    } else {
      return content;
    }
  }

  Widget _buildTopControlBanner() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.tune_rounded, color: primaryColor, size: 24),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pusat Kontrol & Konfigurasi Sistem',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Color(0xFF0F172A)),
                ),
                SizedBox(height: 2),
                Text(
                  'Kelola integrasi perangkat IoT, gateway komunikasi WhatsApp, pembayaran, dan pencadangan data.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // System Diagnostic Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.shield_outlined, size: 16, color: Color(0xFF10B981)),
                SizedBox(width: 8),
                Text(
                  'Sistem Stabil',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF047857)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: iconColor, size: 16),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1E293B),
                letterSpacing: 0.2,
              ),
            ),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 11.5,
                color: Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCardsGrid(List<_SettingsItemData> items) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 460,
        mainAxisExtent: 118,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return _buildSettingsCardItem(item);
      },
    );
  }

  Widget _buildSettingsCardItem(_SettingsItemData item) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: item.color.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            hoverColor: item.color.withValues(alpha: 0.03),
            onTap: () {
              if (item.route != null) {
                Navigator.pushNamed(context, item.route!);
              } else if (item.onTap != null) {
                item.onTap!();
              }
            },
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: item.color, width: 4),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Icon Avatar
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: item.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(item.icon, color: item.color, size: 22),
                  ),
                  const SizedBox(width: 14),

                  // Middle Texts & Badge
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: item.statusColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                item.statusBadge,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: item.statusColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFF64748B),
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Action Arrow Pill
                  Container(
                    width: 28,
                    height: 28,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF1F5F9),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.chevron_right_rounded,
                      color: Color(0xFF64748B),
                      size: 18,
                    ),
                  ),
                ],
              ),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        contentPadding: const EdgeInsets.symmetric(horizontal: 24),
        actionsPadding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        title: const Row(
          children: [
            Icon(Icons.info_outline_rounded, color: Color(0xFF0F172A), size: 24),
            SizedBox(width: 12),
            Text('Smart Laundry Desktop Pro', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Color(0xFF0F172A))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Sistem Manajemen Kasir & Monitoring IoT Laundry Mandiri.',
              style: TextStyle(fontSize: 13, color: Color(0xFF475569), height: 1.4),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Versi Aplikasi', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                      Text('v2.4.0 (Enterprise Desktop)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                    ],
                  ),
                  SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Database Engine', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                      Text('SQLite FFI (Terenkripsi)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
                    ],
                  ),
                  SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Backend API Port', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                      Text('5000 (Python) & 3000 (WA)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                    ],
                  ),
                ],
              ),
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
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Tutup', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

class _SettingsItemData {
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final String statusBadge;
  final Color statusColor;
  final String? route;
  final VoidCallback? onTap;

  _SettingsItemData({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.statusBadge,
    required this.statusColor,
    required this.route,
    this.onTap,
  });
}
