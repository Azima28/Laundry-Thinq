import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../database/models/user_model.dart';
import 'screens/machines/cuci_screen.dart';
import 'screens/machines/pengering_screen.dart';
import 'screens/machines/machine_label_dialog.dart';
import 'screens/customers/customer_screen.dart';
import 'screens/admin/hubungi_pelanggan_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'screens/admin/pengeluaran_screen.dart';
import 'screens/history/global_history_screen.dart';
import 'services/machine_status_service.dart';
import 'database/models/database_helper.dart';
import 'utils/style_constants.dart';
import 'utils/currency_format.dart';

class DashboardPage extends StatefulWidget {
  final UserModel? user;
  const DashboardPage({Key? key, this.user}) : super(key: key);

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int _selectedIndex = 0;
  final List<int> _navHistory = [];
  bool _isSidebarExpanded = true;
  final MachineStatusService _statusService = MachineStatusService.instance;
  final DatabaseHelper _db = DatabaseHelper.instance;

  // Daily Quick Metrics Cache
  int _todayOrderCount = 0;
  int _todayRevenue = 0;
  int _readyOrdersCount = 0;
  bool _isLoadingMetrics = false;

  @override
  void initState() {
    super.initState();
    _statusService.updates.addListener(_onStatusUpdate);
    _loadDailyMetrics();
  }

  @override
  void dispose() {
    _statusService.updates.removeListener(_onStatusUpdate);
    super.dispose();
  }

  void _onStatusUpdate() {
    if (mounted) setState(() {});
  }

  Future<void> _loadDailyMetrics() async {
    if (_isLoadingMetrics) return;
    setState(() => _isLoadingMetrics = true);
    try {
      final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final orders = await _db.getOrdersByDate(todayStr);

      int totalRev = 0;
      int readyCount = 0;
      for (var o in orders) {
        totalRev += o.paidAmount;
        if (o.status.toLowerCase() == 'selesai' || o.status.toLowerCase() == 'siap diambil') {
          readyCount++;
        }
      }

      if (mounted) {
        setState(() {
          _todayOrderCount = orders.length;
          _todayRevenue = totalRev;
          _readyOrdersCount = readyCount;
          _isLoadingMetrics = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingMetrics = false);
    }
  }

  void _navigate(BuildContext context, String route) {
    Navigator.pushNamed(context, route).then((_) => _loadDailyMetrics());
  }

  void _selectTab(int index) {
    if (index == _selectedIndex) return;
    setState(() {
      _navHistory.add(_selectedIndex);
      _selectedIndex = index;
    });
  }

  void _goBack() {
    if (_navHistory.isNotEmpty) {
      final prev = _navHistory.removeLast();
      setState(() => _selectedIndex = prev);
    } else {
      setState(() => _selectedIndex = 0);
    }
  }

  Future<void> _logout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.logout_rounded, color: StyleConstants.dangerColor, size: 22),
            SizedBox(width: 10),
            Text('Konfirmasi Keluar', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ],
        ),
        content: const Text('Apakah Anda yakin ingin keluar dari sistem kasir desktop?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal', style: TextStyle(color: StyleConstants.textMuted, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: StyleConstants.dangerColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Keluar Sistem', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('user_id');
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    }
  }

  Widget _buildBodyContent(String displayName) {
    switch (_selectedIndex) {
      case 0:
        return _buildDashboardHome(displayName);
      case 1:
        return const CuciContent(items: 5, title: 'Status & Pemantauan Mesin Cuci');
      case 2:
        return const PengeringContent(items: 3, title: 'Status & Pemantauan Mesin Pengering');
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
        return _buildDashboardHome(displayName);
    }
  }

  String _getPageTitle() {
    switch (_selectedIndex) {
      case 0:
        return 'Beranda & Pusat Operasional';
      case 1:
        return 'Matriks Mesin Cuci IoT (LG ThinQ)';
      case 2:
        return 'Matriks Mesin Pengering IoT (Tuya/Bardi)';
      case 3:
        return 'Database & Manajemen CRM Pelanggan';
      case 4:
        return 'Hubungi Pelanggan & Broadcast WhatsApp';
      case 5:
        return 'Pusat Riwayat & Buku Besar Global';
      case 6:
        return 'Catatan Pengeluaran & Kas Kecil';
      case 7:
        return 'Pusat Pengaturan Sistem & Hardware';
      default:
        return 'Smart Laundry Pro Desktop';
    }
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

  @override
  Widget build(BuildContext context) {
    final String displayName = widget.user?.username ?? 'Kasir';

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_selectedIndex != 0) _goBack();
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: StyleConstants.backgroundColor,
          body: Row(
            children: [
              // 1. Adaptive Collapsible Sidebar (Left Rail)
              _buildSidebar(displayName),

              // 2. Main Workspace (Right Side)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Top Universal Command Bar
                    _buildTopBar(displayName),

                    // Main Scrollable / Viewport Workspace Body
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(StyleConstants.densePadding),
                        child: _buildBodyContent(displayName),
                      ),
                    ),

                    // Bottom Status Utility Bar (Enterprise POS Style)
                    _buildBottomUtilityBar(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================
  // 1. SIDEBAR NAVIGATION COMPONENT (COLLAPSIBLE)
  // ==========================================
  Widget _buildSidebar(String displayName) {
    final currentWidth = _isSidebarExpanded
        ? StyleConstants.sidebarExpandedWidth
        : StyleConstants.sidebarCollapsedWidth;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      width: currentWidth,
      decoration: const BoxDecoration(
        color: StyleConstants.sidebarBackground,
        border: Border(
          right: BorderSide(color: Color(0xFF1E293B), width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Branding Header
          Container(
            height: StyleConstants.topBarHeight,
            padding: EdgeInsets.symmetric(horizontal: _isSidebarExpanded ? 16 : 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: StyleConstants.primaryColor.withValues(alpha: 0.35),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.asset(
                    'assets/images/logo.png',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      decoration: BoxDecoration(
                        gradient: StyleConstants.primaryGradient,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.local_laundry_service_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                ),
                if (_isSidebarExpanded) ...[
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SMART LAUNDRY',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'DESKTOP PRO v2.4',
                          style: TextStyle(
                            color: StyleConstants.accentCyan,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Menu Items List
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(horizontal: _isSidebarExpanded ? 10 : 8),
              children: [
                _sidebarMenuItem(0, Icons.dashboard_rounded, 'Dashboard', null),
                const SizedBox(height: 4),
                _sidebarMenuItem(
                  1,
                  Icons.local_laundry_service_rounded,
                  'Mesin Cuci',
                  _getActiveMachinesCount() > 0 ? '${_getActiveMachinesCount()} On' : null,
                ),
                const SizedBox(height: 4),
                _sidebarMenuItem(2, Icons.wb_sunny_rounded, 'Mesin Pengering', null),
                const SizedBox(height: 4),
                _sidebarMenuItem(3, Icons.people_alt_rounded, 'Data Pelanggan', null),
                const SizedBox(height: 4),
                _sidebarMenuItem(4, Icons.chat_rounded, 'Hubungi (WA)', null),
                const SizedBox(height: 4),
                _sidebarMenuItem(5, Icons.receipt_long_rounded, 'Riwayat', null),
                const SizedBox(height: 4),
                _sidebarMenuItem(6, Icons.receipt_long_rounded, 'Pengeluaran', null),
                const SizedBox(height: 4),
                _sidebarMenuItem(7, Icons.tune_rounded, 'Pengaturan Hub', null),
              ],
            ),
          ),

          // Collapse/Expand Toggle + Logout
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFF1E293B))),
            ),
            child: Column(
              children: [
                // Collapse toggle button
                InkWell(
                  onTap: () => setState(() => _isSidebarExpanded = !_isSidebarExpanded),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                    child: Row(
                      mainAxisAlignment: _isSidebarExpanded ? MainAxisAlignment.start : MainAxisAlignment.center,
                      children: [
                        Icon(
                          _isSidebarExpanded ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
                          color: const Color(0xFF94A3B8),
                          size: 20,
                        ),
                        if (_isSidebarExpanded) ...[
                          const SizedBox(width: 10),
                          const Text(
                            'Ciutkan Sidebar',
                            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ]
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                // Logout action
                InkWell(
                  onTap: () => _logout(context),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: _isSidebarExpanded ? MainAxisAlignment.start : MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.power_settings_new_rounded, color: Colors.redAccent, size: 20),
                        if (_isSidebarExpanded) ...[
                          const SizedBox(width: 10),
                          const Text(
                            'Keluar Sistem',
                            style: TextStyle(
                              color: Colors.redAccent,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ]
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sidebarMenuItem(int index, IconData icon, String label, String? badgeText) {
    final isSelected = _selectedIndex == index;

    return Tooltip(
      message: !_isSidebarExpanded ? label : '',
      preferBelow: false,
      child: InkWell(
        onTap: () => _selectTab(index),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: EdgeInsets.symmetric(
            vertical: 10,
            horizontal: _isSidebarExpanded ? 12 : 0,
          ),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF1E293B) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: isSelected
                ? Border.all(color: const Color(0xFF334155), width: 1)
                : null,
          ),
          child: Row(
            mainAxisAlignment: _isSidebarExpanded ? MainAxisAlignment.start : MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: isSelected ? StyleConstants.accentCyan : const Color(0xFF94A3B8),
                size: 20,
              ),
              if (_isSidebarExpanded) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                      fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (badgeText != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isSelected ? StyleConstants.accentCyan.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      badgeText,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: isSelected ? StyleConstants.accentCyan : const Color(0xFF94A3B8),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================
  // 2. TOP UNIVERSAL COMMAND BAR
  // ==========================================
  Widget _buildTopBar(String displayName) {
    return Container(
      height: StyleConstants.topBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: StyleConstants.borderLight)),
      ),
      child: Row(
        children: [
          // 1. Back / Return Button (Active whenever not on Dashboard Home)
          if (_selectedIndex != 0) ...[
            Tooltip(
              message: 'Kembali ke Beranda (Esc)',
              child: InkWell(
                onTap: _goBack,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: StyleConstants.borderLight),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.arrow_back_rounded,
                        size: 16,
                        color: StyleConstants.textHeading,
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Kembali',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: StyleConstants.textHeading,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
          ],

          // 2. Interactive Breadcrumb Navigation
          Row(
            children: [
              MouseRegion(
                cursor: _selectedIndex != 0 ? SystemMouseCursors.click : SystemMouseCursors.basic,
                child: GestureDetector(
                  onTap: _selectedIndex != 0 ? () => _selectTab(0) : null,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.dashboard_rounded,
                        size: 14,
                        color: _selectedIndex != 0 ? StyleConstants.primaryColor : StyleConstants.textMuted,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'POS Desktop',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: _selectedIndex != 0 ? FontWeight.w700 : FontWeight.w600,
                          color: _selectedIndex != 0 ? StyleConstants.primaryColor : StyleConstants.textMuted,
                          decoration: _selectedIndex != 0 ? TextDecoration.underline : TextDecoration.none,
                          decorationColor: StyleConstants.primaryColor.withValues(alpha: 0.3),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded, size: 16, color: StyleConstants.textMuted),
              const SizedBox(width: 6),
              Text(
                _getPageTitle(),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: StyleConstants.textHeading,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),

          const Spacer(),

          // Standalone Label Maker Button
          Tooltip(
            message: 'Buat & Cetak Label Mesin Manual',
            child: InkWell(
              onTap: () => MachineLabelDialog.show(context),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: StyleConstants.primaryColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: StyleConstants.primaryColor.withValues(alpha: 0.25)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.label_important_rounded, size: 15, color: StyleConstants.primaryColor),
                    SizedBox(width: 6),
                    Text(
                      'Cetak Label',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: StyleConstants.primaryColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Hardware & Gateway Connectivity Pills
          _buildNetworkStatusBar(),
          const SizedBox(width: 16),

          // User Profile Pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: StyleConstants.borderLight),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: StyleConstants.primaryColor.withValues(alpha: 0.12),
                  child: const Icon(Icons.person_rounded, size: 14, color: StyleConstants.primaryColor),
                ),
                const SizedBox(width: 8),
                Text(
                  displayName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                    color: StyleConstants.textHeading,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: widget.user?.role == 'admin' ? StyleConstants.secondaryColor : StyleConstants.successColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    widget.user?.role == 'admin' ? 'ADMIN' : 'KASIR',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openWhatsAppGUI() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
            SizedBox(width: 10),
            Text('Membuka jendela WhatsApp Web di layar...'),
          ],
        ),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
    final res = await _statusService.openWhatsAppWebGUI();
    if (!res['success'] && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res['message'] ?? 'Gagal membuka WA'), backgroundColor: Colors.red),
      );
    }
  }

  Widget _buildNetworkStatusBar() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _statusPill('Internet', _statusService.internetOk, Icons.wifi_rounded),
        const SizedBox(width: 6),
        _statusPill('LG ThinQ', _statusService.thinqOk, Icons.cloud_rounded),
        const SizedBox(width: 6),
        _statusPill('Tuya/Bardi', _statusService.bardiOk, Icons.outlet_rounded),
        const SizedBox(width: 6),
        _statusPill(
          'WhatsApp',
          _statusService.waOk,
          Icons.chat_rounded,
          onTap: _openWhatsAppGUI,
          tooltip: 'Klik untuk membuka jendela WhatsApp Web di desktop',
        ),
      ],
    );
  }

  Widget _statusPill(String label, bool isOk, IconData icon, {VoidCallback? onTap, String? tooltip}) {
    final color = isOk ? StyleConstants.successColor : StyleConstants.dangerColor;
    final bg = isOk ? StyleConstants.statusSuccessBg : StyleConstants.statusDangerBg;

    Widget pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
            ),
          ),
          const SizedBox(width: 5),
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 4),
            Icon(Icons.open_in_new_rounded, size: 10, color: color),
          ]
        ],
      ),
    );

    if (onTap != null) {
      pill = MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: pill,
        ),
      );
    }

    if (tooltip != null) {
      pill = Tooltip(message: tooltip, child: pill);
    }

    return pill;
  }

  // ==========================================
  // 3. DASHBOARD HOME VIEW (HIGH DENSITY & ENTERPRISE KPI)
  // ==========================================
  Widget _buildDashboardHome(String displayName) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 4-in-1 KPI Ribbon Row
        _buildKpiRibbonRow(),
        const SizedBox(height: 16),

        // Main 2-Column Split Workspace
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left Workspace: POS Launchers & Quick Access (Flex 3)
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Quick POS Terminal Launchers
                    Row(
                      children: [
                        Expanded(
                          child: _buildPosActionCard(
                            title: 'Pesan Laundry',
                            subtitle: 'Cuci Kiloan, Bedcover, Express & Satuan',
                            shortcutTag: 'F1',
                            icon: Icons.local_laundry_service_rounded,
                            accentColor: StyleConstants.primaryColor,
                            onTap: () => _navigate(context, '/pesan'),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _buildPosActionCard(
                            title: 'Pesan Setrika',
                            subtitle: 'Pakaian Kiloan Gosok Saja / Uap Rapi',
                            shortcutTag: 'F2',
                            icon: Icons.iron_rounded,
                            accentColor: const Color(0xFFF97316),
                            onTap: () => _navigate(context, '/pesan_gosok'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    const Text(
                      'Modul Akses Cepat & Operasional',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: StyleConstants.textHeading,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // 4-Grid Navigation Tiles
                    Expanded(
                      child: GridView.count(
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 2.8,
                        children: [
                          _buildQuickNavTile(
                            title: 'Pusat Riwayat',
                            desc: 'Nota, log mesin cuci, pengering & kas',
                            icon: Icons.receipt_long_rounded,
                            color: const Color(0xFF0D9488),
                            onTap: () => _selectTab(5),
                          ),
                          _buildQuickNavTile(
                            title: 'Database Pelanggan',
                            desc: 'Kelola kontak CRM & WhatsApp',
                            icon: Icons.people_alt_rounded,
                            color: const Color(0xFF6366F1),
                            onTap: () => _selectTab(3),
                          ),
                          _buildQuickNavTile(
                            title: 'Broadcast WhatsApp',
                            desc: 'Kirim notifikasi & promo massal',
                            icon: Icons.chat_rounded,
                            color: const Color(0xFF10B981),
                            onTap: () => _selectTab(4),
                          ),
                          _buildQuickNavTile(
                            title: 'Catat Pengeluaran',
                            desc: 'Kas kecil beli deterjen & operasional',
                            icon: Icons.account_balance_wallet_rounded,
                            color: const Color(0xFFE11D48),
                            onTap: () => _selectTab(6),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),

              // Right Workspace: Telemetry & Machine Hub (Flex 2)
              Expanded(
                flex: 2,
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: StyleConstants.cardDecoration(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.memory_rounded, color: StyleConstants.primaryColor, size: 20),
                          const SizedBox(width: 8),
                          const Text(
                            'Status Telemetri Mesin IoT',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: StyleConstants.textHeading,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                            tooltip: 'Perbarui Status',
                            onPressed: () {
                              _statusService.pollNow();
                              _loadDailyMetrics();
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      const SizedBox(height: 14),

                      // Machine Circular Progress
                      _buildMachineUtilizationWidget(),
                      const SizedBox(height: 16),

                      // Statistics list
                      _buildTelemetryRow(
                        icon: Icons.local_laundry_service_rounded,
                        label: 'Mesin Cuci Terhubung (ThinQ)',
                        value: '${_statusService.thinqDeviceCount} Unit',
                        color: StyleConstants.primaryColor,
                      ),
                      const SizedBox(height: 10),
                      _buildTelemetryRow(
                        icon: Icons.wb_sunny_rounded,
                        label: 'Pengering Bardi Smart Plug',
                        value: 'Ready',
                        color: const Color(0xFFF59E0B),
                      ),
                      const SizedBox(height: 10),
                      _buildTelemetryRow(
                        icon: Icons.check_circle_outline_rounded,
                        label: 'Cucian Selesai Siap Ambil',
                        value: '$_readyOrdersCount Nota',
                        color: StyleConstants.successColor,
                      ),

                      const Spacer(),

                      // Admin Shortcut
                      if (widget.user?.role == 'admin') ...[
                        ElevatedButton.icon(
                          onPressed: () => _navigate(context, '/admin_dashboard'),
                          icon: const Icon(Icons.admin_panel_settings_rounded, size: 16),
                          label: const Text('Portal Kontrol Admin & Staf', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: StyleConstants.sidebarBackground,
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(42),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            elevation: 0,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // KPI Ribbon 4 Cards
  Widget _buildKpiRibbonRow() {
    return Row(
      children: [
        Expanded(
          child: _buildKpiCard(
            title: 'ORDER HARI INI',
            value: '$_todayOrderCount Nota',
            icon: Icons.receipt_rounded,
            color: StyleConstants.primaryColor,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildKpiCard(
            title: 'KAS MASUK HARI INI',
            value: formatRp(_todayRevenue),
            icon: Icons.payments_rounded,
            color: StyleConstants.successColor,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildKpiCard(
            title: 'UTILISASI MESIN CUCI',
            value: '${_getActiveMachinesCount()} Unit Aktif',
            icon: Icons.sync_rounded,
            color: const Color(0xFF6366F1),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildKpiCard(
            title: 'SIAP DIAMBIL',
            value: '$_readyOrdersCount Pelanggan',
            icon: Icons.mark_email_read_rounded,
            color: const Color(0xFF0D9488),
          ),
        ),
      ],
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: StyleConstants.borderLight),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: color, width: 3),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
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
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: StyleConstants.textMuted,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      value,
                      style: StyleConstants.tabularNumbers(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: StyleConstants.textHeading,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // POS Launcher Card
  Widget _buildPosActionCard({
    required String title,
    required String subtitle,
    required String shortcutTag,
    required IconData icon,
    required Color accentColor,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accentColor.withValues(alpha: 0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.12),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: accentColor, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 16.5,
                              fontWeight: FontWeight.w900,
                              color: StyleConstants.textHeading,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: accentColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              shortcutTag,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                color: accentColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: StyleConstants.textMuted,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.arrow_forward_rounded, color: accentColor, size: 16),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Quick Navigation Tile
  Widget _buildQuickNavTile({
    required String title,
    required String desc,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: StyleConstants.borderLight),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: StyleConstants.textHeading,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        desc,
                        style: const TextStyle(fontSize: 11, color: StyleConstants.textMuted),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios_rounded, color: Colors.grey[400], size: 13),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Machine Utilization Widget
  Widget _buildMachineUtilizationWidget() {
    int total = _statusService.thinqDeviceCount;
    int active = _getActiveMachinesCount();
    if (total == 0) total = 5;
    double percent = total > 0 ? (active / total) : 0.0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: StyleConstants.borderLight),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 54,
            height: 54,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: percent,
                  strokeWidth: 6,
                  backgroundColor: const Color(0xFFE2E8F0),
                  valueColor: const AlwaysStoppedAnimation<Color>(StyleConstants.successColor),
                ),
                Text(
                  '$active/$total',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: StyleConstants.textHeading,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Utilisasi Kapasitas Mesin',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: StyleConstants.textHeading,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$active unit mesin cuci sedang aktif beroperasi.',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: StyleConstants.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTelemetryRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: StyleConstants.textBody,
            ),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            color: StyleConstants.textHeading,
          ),
        ),
      ],
    );
  }

  // ==========================================
  // 4. BOTTOM DOCKED UTILITY BAR
  // ==========================================
  Widget _buildBottomUtilityBar() {
    return Container(
      height: StyleConstants.bottomBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        border: Border(top: BorderSide(color: Color(0xFF1E293B))),
      ),
      child: Row(
        children: [
          const Icon(Icons.storage_rounded, size: 12, color: StyleConstants.successColor),
          const SizedBox(width: 6),
          const Text(
            'SQLite FFI: Terkoneksi Lokal',
            style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8), fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 20),
          const Icon(Icons.print_rounded, size: 12, color: StyleConstants.accentCyan),
          const SizedBox(width: 6),
          const Text(
            'Thermal ESC/POS: Siap Cetak',
            style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8), fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          Text(
            DateFormat('EEEE, dd MMMM yyyy').format(DateTime.now()),
            style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8), fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
