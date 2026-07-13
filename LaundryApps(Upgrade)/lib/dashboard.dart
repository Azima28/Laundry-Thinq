import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/models/user_model.dart';
import 'screens/machines/cuci_screen.dart';
import 'screens/machines/pengering_screen.dart';
import 'screens/customers/customer_screen.dart';
import 'screens/admin/hubungi_pelanggan_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'screens/admin/pengeluaran_screen.dart';
import 'screens/history/global_history_screen.dart';
import 'screens/orders/restock_screen.dart';
import 'transactions/order_repository.dart';
import 'services/machine_status_service.dart';
import 'database/models/database_helper.dart';
import 'database/models/order_model.dart';
import 'database/models/machine_model.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import 'utils/style_constants.dart';

class DashboardPage extends StatefulWidget {
  final UserModel? user;
  const DashboardPage({Key? key, this.user}) : super(key: key);

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int _selectedIndex = 0;
  final OrderRepository _orderRepo = OrderRepository();
  final MachineStatusService _statusService = MachineStatusService.instance;
  final DatabaseHelper _db = DatabaseHelper.instance;

  // Modern UI Colors using StyleConstants
  final Color primaryColor = StyleConstants.primaryColor;
  final Color secondaryColor = StyleConstants.secondaryColor;
  final Color backgroundColor = StyleConstants.backgroundColor;

  @override
  void initState() {
    super.initState();
    _statusService.updates.addListener(_onStatusUpdate);
  }

  @override
  void dispose() {
    _statusService.updates.removeListener(_onStatusUpdate);
    super.dispose();
  }

  void _onStatusUpdate() {
    if (mounted) setState(() {});
  }

  void _navigate(BuildContext context, String route) {
    Navigator.pushNamed(context, route);
  }

  Future<void> _logout(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_id');
    Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
  }

  Widget _buildBodyContent(String displayName) {
    switch (_selectedIndex) {
      case 0:
        return _buildDashboardView(displayName);
      case 1:
        return const CuciContent(items: 5, title: 'Status Mesin Cuci');
      case 2:
        return const PengeringContent(items: 3, title: 'Status Mesin Pengering');
      case 3:
        return const CustomerScreen();
      case 4:
        return const HubungiPelangganScreen();
      case 5:
        return const GlobalHistoryScreen();
      case 6:
        return const PengeluaranScreen();
      case 7:
        return SettingsScreen();
      default:
        return _buildDashboardView(displayName);
    }
  }

  String _getPageTitle() {
    switch (_selectedIndex) {
      case 0:
        return 'Dashboard Utama';
      case 1:
        return 'Status & Pemantauan Mesin Cuci';
      case 2:
        return 'Status & Pemantauan Mesin Pengering';
      case 3:
        return 'Kelola Data Pelanggan';
      case 4:
        return 'Hubungi Pelanggan (WhatsApp)';
      case 5:
        return 'Buku Besar & Riwayat Global';
      case 6:
        return 'Catatan Pengeluaran & Kas';
      case 7:
        return 'Pengaturan Sistem & Admin';
      default:
        return 'Smart Laundry';
    }
  }

  @override
  Widget build(BuildContext context) {
    final String displayName = widget.user?.username ?? 'Kasir';

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Row(
        children: [
          // 1. Sidebar Navigation (Left Side)
          _buildSidebar(displayName),

          // 2. Vertical Divider
          Container(width: 1, color: Colors.grey[200]),

          // 3. Main Workspace Area (Right Side)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 3a. Sleek Top Bar
                _buildTopBar(displayName),

                // 3b. Content Body
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(StyleConstants.densePadding),
                    child: _buildBodyContent(displayName),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- WIDGET: SIDEBAR NAVIGATION ---
  Widget _buildSidebar(String displayName) {
    return Container(
      width: 260,
      decoration: const BoxDecoration(
        gradient: StyleConstants.sidebarGradient,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Logo & Branding Redesigned (Larger & Premium)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: StyleConstants.primaryGradient,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: StyleConstants.primaryColor.withOpacity(0.4),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        )
                      ],
                    ),
                    child: const Icon(
                      Icons.local_laundry_service_rounded,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SMART',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 21,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                          ),
                        ),
                        Text(
                          'LAUNDRY PRO',
                          style: TextStyle(
                            color: Colors.cyanAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const Divider(color: Colors.white10, height: 1),
          const SizedBox(height: 16),

          // Menu Items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _sidebarItem(0, Icons.grid_view_rounded, 'Dashboard'),
                _sidebarItem(1, Icons.local_laundry_service_rounded, 'Mesin Cuci'),
                _sidebarItem(2, Icons.wb_sunny_rounded, 'Mesin Pengering'),
                _sidebarItem(3, Icons.people_alt_rounded, 'Data Pelanggan'),
                _sidebarItem(4, Icons.chat_rounded, 'Hubungi (WA)'),
                _sidebarItem(5, Icons.account_balance_wallet_rounded, 'Buku Besar'),
                _sidebarItem(6, Icons.receipt_long_rounded, 'Pengeluaran'),
                _sidebarItem(7, Icons.settings_rounded, 'Pengaturan'),
              ],
            ),
          ),

          // Logout Footer
          const Divider(color: Colors.white10, height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: InkWell(
              onTap: () => _logout(context),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.logout_rounded, color: Colors.redAccent, size: 20),
                    SizedBox(width: 12),
                    Text(
                      'Keluar Sistem',
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
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

  Widget _sidebarItem(int index, IconData icon, String label) {
    final isSelected = _selectedIndex == index;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: InkWell(
        onTap: () => setState(() => _selectedIndex = index),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            gradient: isSelected ? StyleConstants.primaryGradient : null,
            color: isSelected ? null : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: StyleConstants.primaryColor.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    )
                  ]
                : null,
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: isSelected ? Colors.white : Colors.grey[400],
                size: 22,
              ),
              const SizedBox(width: 14),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.grey[300],
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  int _getActiveMachinesCount() {
    int count = 0;
    _statusService.states.forEach((key, val) {
      if (!key.startsWith('sensor.') && val is Map) {
        final status = (val['status'] ?? '').toString().toLowerCase();
        final state = (val['state'] ?? '').toString().toLowerCase();
        if (status == 'run' || status == 'running' || status == 'on' || status == 'unready' || state == 'on' || state == 'run') {
          count++;
        }
      }
    });
    return count;
  }

  // --- WIDGET: SLEEK TOP BAR (UPGRADED) ---
  Widget _buildTopBar(String displayName) {
    return Container(
      height: 75,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: StyleConstants.borderLight)),
      ),
      child: Row(
        children: [
          // Current Page Title (Larger & Prominent)
          Text(
            _getPageTitle(),
            style: const TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
              letterSpacing: -0.5,
            ),
          ),
          const Spacer(),

          // Connectivity badges
          _buildNetworkStatusBar(),
          const SizedBox(width: 24),

          // User Info Card Redesigned
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: StyleConstants.borderLight),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: StyleConstants.primaryColor.withOpacity(0.1),
                  child: const Icon(Icons.person_rounded, size: 16, color: StyleConstants.primaryColor),
                ),
                const SizedBox(width: 10),
                Text(
                  displayName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- VIEW: DASHBOARD CONTENT (DESKTOP REDESIGN - DENSE & PREMIUM) ---
  Widget _buildDashboardView(String displayName) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Left Column: Quick Actions & Navigation Cards
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader('Menu Transaksi Utama', Icons.shopping_bag_rounded),
              const SizedBox(height: 14),
              
              // Row of Large Quick Actions
              Row(
                children: [
                  Expanded(
                    child: _buildDesktopActionCard(
                      title: 'Pesan Laundry',
                      description: 'Input pakaian kiloan/satuan baru',
                      icon: Icons.local_laundry_service_rounded,
                      color: StyleConstants.primaryColor,
                      onTap: () => _navigate(context, '/pesan'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildDesktopActionCard(
                      title: 'Pesan Gosok',
                      description: 'Input pakaian setrika saja',
                      icon: Icons.iron_rounded,
                      color: const Color(0xFFF97316),
                      onTap: () => _navigate(context, '/pesan_gosok'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              _buildSectionHeader('Menu Akses Cepat', Icons.grid_view_rounded),
              const SizedBox(height: 14),

              // Layout of smaller tiles in grid format (Dense Layout)
              Expanded(
                child: GridView.count(
                  crossAxisCount: 2,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                  childAspectRatio: 3.1, // tighter, more dense
                  children: [
                    _buildDesktopTile(
                      title: 'Riwayat Laundry',
                      icon: Icons.receipt_long_rounded,
                      color: const Color(0xFF14B8A6),
                      onTap: () => _navigate(context, '/history'),
                    ),
                    _buildDesktopTile(
                      title: 'Riwayat Gosok',
                      icon: Icons.iron_rounded,
                      color: const Color(0xFFE11D48),
                      onTap: () => _navigate(context, '/history_gosok'),
                    ),
                    _buildDesktopTile(
                      title: 'Riwayat Mesin Cuci',
                      icon: Icons.local_laundry_service_rounded,
                      color: const Color(0xFF6366F1),
                      onTap: () => _navigate(context, '/history_mesin_cuci'),
                    ),
                    _buildDesktopTile(
                      title: 'Riwayat Pengering',
                      icon: Icons.wb_sunny_rounded,
                      color: const Color(0xFFEAB308),
                      onTap: () => _navigate(context, '/history_pengering'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 24),

        // Right Column: Monitoring summary & diagnostics (Highly Dense)
        Expanded(
          flex: 2,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.02),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                )
              ],
              border: Border.all(color: StyleConstants.borderLight),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.analytics_rounded, color: Color(0xFF0F172A), size: 22),
                    SizedBox(width: 10),
                    Text(
                      'Ringkasan Sistem Pro',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 16),

                // Interactive Circle Monitor Widget (New)
                _buildCircularMachineStatus(),
                const SizedBox(height: 16),

                // Statistics/Counters
                _buildSystemStatRow(
                  icon: Icons.device_hub_rounded,
                  color: StyleConstants.primaryColor,
                  label: 'Mesin Cuci Terdeteksi',
                  value: '${_statusService.thinqDeviceCount} Unit',
                ),
                const SizedBox(height: 12),
                _buildSystemStatRow(
                  icon: Icons.people_alt_rounded,
                  color: const Color(0xFF8B5CF6),
                  label: 'Pelanggan Aktif',
                  value: 'Ready',
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 16),

                // Guide/Info Card (Compact Gradient Alert)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: StyleConstants.primaryColor.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: StyleConstants.primaryColor.withOpacity(0.1)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline_rounded, color: StyleConstants.primaryColor, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Mode Monitoring Saja',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: StyleConstants.primaryColor,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Sistem v2 berjalan tanpa ESP32/Relay. Klik tombol "Mulai" pada menu Mesin Cuci untuk memulai monitoring dan mengirimkan notifikasi WhatsApp otomatis ke HP pelanggan.',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[700],
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),

                // Admin Quick Shortcut
                if (widget.user?.role == 'admin') ...[
                  ElevatedButton.icon(
                    onPressed: () => _navigate(context, '/admin_dashboard'),
                    icon: const Icon(Icons.admin_panel_settings_rounded, size: 18),
                    label: const Text('Buka Panel Admin & Kasir', style: TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F172A),
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ]
              ],
            ),
          ),
        ),
      ],
    );
  }

  // --- WIDGET: CIRCULAR MACHINE UTILIZATION STATUS (NEW) ---
  Widget _buildCircularMachineStatus() {
    int total = _statusService.thinqDeviceCount;
    int active = _getActiveMachinesCount();
    if (total == 0) total = 5; // Mock fallback
    double percent = total > 0 ? (active / total) : 0.0;
    
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: StyleConstants.borderLight),
      ),
      child: Row(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 65,
                height: 65,
                child: CircularProgressIndicator(
                  value: percent,
                  strokeWidth: 7,
                  backgroundColor: const Color(0xFFE2E8F0),
                  valueColor: const AlwaysStoppedAnimation<Color>(StyleConstants.successColor),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$active/$total',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const Text(
                    'Aktif',
                    style: TextStyle(
                      fontSize: 9,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Utilisasi Mesin Cuci',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13.5,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Saat ini $active mesin sedang beroperasi memproses pakaian pelanggan.',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- HELPERS: CUSTOM ACTION WIDGETS ---
  Widget _buildDesktopActionCard({
    required String title,
    required String description,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
      height: 105,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
        border: Border.all(color: StyleConstants.borderLight),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        description,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: Colors.grey[400]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopTile({
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: StyleConstants.borderLight),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 20, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13.5,
                      color: Color(0xFF334155),
                    ),
                  ),
                ),
                Icon(Icons.arrow_forward_rounded, size: 14, color: Colors.grey[400]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSystemStatRow({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.bold,
              color: Color(0xFF475569),
            ),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: StyleConstants.primaryColor.withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: StyleConstants.primaryColor),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            fontSize: 15.5,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }

  // --- WIDGET: NETWORK CONNECTIVITY BADGES (UPGRADED TO SOLID PILLS) ---
  Widget _buildNetworkStatusBar() {
    return Row(
      children: [
        _statusChip(
          icon: Icons.wifi_rounded,
          label: 'Internet',
          isOk: _statusService.internetOk,
        ),
        const SizedBox(width: 10),
        _statusChip(
          icon: Icons.cloud_rounded,
          label: 'ThinQ',
          isOk: _statusService.thinqOk,
        ),
        const SizedBox(width: 10),
        _statusChip(
          icon: Icons.outlet_rounded,
          label: 'Bardi',
          isOk: _statusService.bardiOk,
        ),
        const SizedBox(width: 10),
        _statusChip(
          icon: Icons.chat_rounded,
          label: 'WhatsApp',
          isOk: _statusService.waOk,
        ),
      ],
    );
  }

  Widget _statusChip({required IconData icon, required String label, required bool isOk}) {
    final color = isOk ? StyleConstants.successColor : StyleConstants.dangerColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7, height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.4),
                  blurRadius: 4,
                  spreadRadius: 1,
                )
              ]
            ),
          ),
          const SizedBox(width: 6),
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
