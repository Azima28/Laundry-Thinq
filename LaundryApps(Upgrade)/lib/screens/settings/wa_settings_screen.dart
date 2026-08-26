import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/machine_status_service.dart';

class WaSettingsScreen extends StatefulWidget {
  const WaSettingsScreen({Key? key}) : super(key: key);

  @override
  State<WaSettingsScreen> createState() => _WaSettingsScreenState();
}

class _WaSettingsScreenState extends State<WaSettingsScreen> {
  final MachineStatusService _statusService = MachineStatusService.instance;
  
  bool _isLoading = true;
  bool _connected = false;
  String? _phone;
  String? _pushname;
  String? _qrCodeBase64;
  String? _qrMessage;
  Timer? _qrRefreshTimer;

  // Global & Sub-Feature Switches
  bool _waMasterEnabled = true;
  bool _waMachineNotificationsEnabled = true;

  // Templates controllers
  final TextEditingController _bookingController = TextEditingController();
  final TextEditingController _cucianMasukController = TextEditingController();
  final TextEditingController _cucianMulaiController = TextEditingController();
  final TextEditingController _cucianSelesaiController = TextEditingController();

  // Chatbot controllers
  bool _chatbotEnabled = true;
  final TextEditingController _chatbotWelcomeController = TextEditingController();
  int _chatbotWelcomeCooldown = 0;
  int _chatbotStaffCooldown = 30;
  List<dynamic> _chatbotMenu = [];
  final TextEditingController _testPhoneCtrl = TextEditingController();

  final Color primaryColor = const Color(0xFF4E80EE);
  final Color backgroundColor = const Color(0xFFF8FAFC);

  String _pollStatus = 'Belum dikirim';
  String _voteResult = 'Belum ada vote';

  @override
  void initState() {
    super.initState();
    _testPhoneCtrl.text = '6289522584477'; // default
    _loadWaStatus();
    _loadTemplates();
    // Only poll WA QR/connection status while on this settings screen and waiting for scan
    _qrRefreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_connected) {
        _loadWaStatus();
      }
    });
  }

  Future<void> _sendTestPoll() async {
    final phone = _testPhoneCtrl.text.trim();
    if (phone.isEmpty) {
      if (mounted) {
        setState(() {
          _pollStatus = 'Error: Nomor tes kosong';
        });
      }
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('wa_test_phone', phone);
    } catch (_) {}

    if (mounted) {
      setState(() {
        _pollStatus = 'Mengirim...';
      });
    }
    try {
      final uri = Uri.parse('${_statusService.dashboardUrl}/api/wa/test-poll?phone=$phone');
      final resp = await http.get(uri).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final data = json.decode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            _pollStatus = data['message'] ?? 'Berhasil terkirim!';
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _pollStatus = 'Gagal: HTTP ${resp.statusCode}';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _pollStatus = 'Error: $e';
        });
      }
    }
  }

  Future<void> _checkVoteResult() async {
    try {
      final uri = Uri.parse('${_statusService.dashboardUrl}/api/wa/test-poll-result');
      final resp = await http.get(uri).timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        final data = json.decode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
        final sender = data['sender'];
        final selected = data['selected'];
        if (sender != null && selected != null && mounted) {
          setState(() {
            _voteResult = 'Pengirim: $sender\nPilihan: $selected';
          });
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _qrRefreshTimer?.cancel();
    _bookingController.dispose();
    _cucianMasukController.dispose();
    _cucianMulaiController.dispose();
    _cucianSelesaiController.dispose();
    _chatbotWelcomeController.dispose();
    _testPhoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadWaStatus() async {
    try {
      final status = await _statusService.getWaStatus();
      bool isNowConnected = status['connected'] == true;
      if (mounted) {
        setState(() {
          _connected = isNowConnected;
          _phone = status['phone'];
          _pushname = status['pushname'];
          _isLoading = false;
        });
      }

      if (!_connected) {
        // Load QR Code if not connected
        final uri = Uri.parse('${_statusService.dashboardUrl}/api/wa/qr');
        final resp = await http.get(uri).timeout(const Duration(seconds: 4));
        if (resp.statusCode == 200 && mounted) {
          final data = json.decode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
          setState(() {
            final qrData = data['qr'] as String?;
            if (qrData != null && qrData.startsWith('data:image/png;base64,')) {
              _qrCodeBase64 = qrData.split(',')[1];
            } else {
              _qrCodeBase64 = null;
            }
            _qrMessage = data['message'];
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _connected = false;
        });
      }
    }
  }

  Future<void> _loadTemplates() async {
    try {
      final uri = Uri.parse('${_statusService.dashboardUrl}/api/config');
      final resp = await http.get(uri).timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        final data = json.decode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
        final templates = data['wa_templates'] as Map<String, dynamic>?;
        if (templates != null) {
          _bookingController.text = templates['booking'] ?? '';
          _cucianMasukController.text = templates['cucian_masuk'] ?? '';
          _cucianMulaiController.text = templates['cucian_mulai'] ?? '';
          _cucianSelesaiController.text = templates['cucian_selesai'] ?? '';
        }
        final prefs = await SharedPreferences.getInstance();
        if (mounted) {
          setState(() {
            _testPhoneCtrl.text = prefs.getString('wa_test_phone') ?? '6289522584477';
            _waMasterEnabled = data['wa_master_enabled'] ?? true;
            _waMachineNotificationsEnabled = data['wa_machine_notifications_enabled'] ?? true;
            _chatbotEnabled = data['chatbot_enabled'] ?? true;
            _chatbotWelcomeController.text = data['chatbot_welcome_message'] ?? 'Halo! Selamat datang di Smart Laundry. Ada yang bisa kami bantu?';
            _chatbotWelcomeCooldown = data['chatbot_welcome_cooldown'] ?? 0;
            _chatbotStaffCooldown = data['chatbot_staff_cooldown'] ?? 30;
            _chatbotMenu = List<dynamic>.from(data['chatbot_menu'] ?? []);
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _saveTemplates() async {
    try {
      final uri = Uri.parse('${_statusService.dashboardUrl}/api/config');
      final resp = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'wa_master_enabled': _waMasterEnabled,
          'wa_machine_notifications_enabled': _waMachineNotificationsEnabled,
          'wa_templates': {
            'booking': _bookingController.text,
            'cucian_masuk': _cucianMasukController.text,
            'cucian_mulai': _cucianMulaiController.text,
            'cucian_selesai': _cucianSelesaiController.text,
          },
          'chatbot_enabled': _chatbotEnabled,
          'chatbot_welcome_message': _chatbotWelcomeController.text,
          'chatbot_welcome_cooldown': _chatbotWelcomeCooldown,
          'chatbot_staff_cooldown': _chatbotStaffCooldown,
          'chatbot_menu': _chatbotMenu,
        }),
      ).timeout(const Duration(seconds: 5));

      if (resp.statusCode == 200) {
        // Save locally to SharedPrefs too
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('wa_master_enabled', _waMasterEnabled);
        await prefs.setBool('wa_machine_notifications_enabled', _waMachineNotificationsEnabled);
        await prefs.setString('wa_booking_template', _bookingController.text);
        await prefs.setString('wa_cucian_masuk_template', _cucianMasukController.text);
        await prefs.setString('wa_cucian_mulai_template', _cucianMulaiController.text);
        await prefs.setString('wa_cucian_selesai_template', _cucianSelesaiController.text);
        await prefs.setBool('wa_chatbot_enabled', _chatbotEnabled);
        await prefs.setString('wa_chatbot_welcome_message', _chatbotWelcomeController.text);
        await prefs.setInt('wa_chatbot_welcome_cooldown', _chatbotWelcomeCooldown);
        await prefs.setInt('wa_chatbot_staff_cooldown', _chatbotStaffCooldown);
        await prefs.setString('wa_chatbot_menu', json.encode(_chatbotMenu));

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Pengaturan WhatsApp berhasil disimpan.'), backgroundColor: Colors.green),
          );
        }
      } else {
        throw Exception('Server returned status ${resp.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menyimpan: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text('Pengaturan WhatsApp', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left Panel: Connection Manager (QR scanner)
                Expanded(
                  flex: 2,
                  child: Container(
                    padding: const EdgeInsets.all(32),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      border: Border(right: BorderSide(color: Color(0xFFE2E8F0))),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.qr_code_scanner_rounded, size: 24, color: Color(0xFF0F172A)),
                            SizedBox(width: 12),
                            Text(
                              'Koneksi WhatsApp',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        
                        // Status Card
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: _connected ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: _connected ? const Color(0xFFA7F3D0) : const Color(0xFFFCA5A5)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    _connected ? Icons.check_circle_rounded : Icons.cancel_rounded,
                                    color: _connected ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                                    size: 28,
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _connected ? 'Terhubung' : 'Terputus',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                            color: _connected ? const Color(0xFF065F46) : const Color(0xFF991B1B),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _connected
                                              ? 'HP: $_phone (${_pushname ?? 'Kasir'})'
                                              : 'WhatsApp belum tersambung ke komputer.',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: _connected ? const Color(0xFF047857) : const Color(0xFFB91C1C),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              ElevatedButton.icon(
                                onPressed: () async {
                                  final res = await _statusService.openWhatsAppWebGUI();
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(res['message'] ?? 'Membuka jendela WhatsApp Web...'),
                                        backgroundColor: res['success'] == true ? const Color(0xFF10B981) : Colors.red,
                                      ),
                                    );
                                  }
                                },
                                icon: const Icon(Icons.open_in_new_rounded, color: Colors.white, size: 16),
                                label: const Text('Buka Jendela WhatsApp Web', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12.5)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF10B981),
                                  minimumSize: const Size.fromHeight(38),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  elevation: 0,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),

                        // QR Code display section
                        if (!_connected) ...[
                          const Text(
                            'Pindai QR Code',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF475569)),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _qrMessage ?? 'Menunggu QR Code dari server...',
                            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                          ),
                          const SizedBox(height: 24),
                          Expanded(
                            child: Center(
                              child: _qrCodeBase64 != null
                                  ? Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(16),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(0.02),
                                            blurRadius: 20,
                                            offset: const Offset(0, 8),
                                          )
                                        ],
                                        border: Border.all(color: const Color(0xFFE2E8F0)),
                                      ),
                                      child: Image.memory(
                                        base64Decode(_qrCodeBase64!),
                                        width: 240,
                                        height: 240,
                                      ),
                                    )
                                  : const Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        CircularProgressIndicator(),
                                        SizedBox(height: 16),
                                        Text('Sedang memuat QR code...', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                      ],
                                    ),
                            ),
                          ),
                        ] else ...[
                          Expanded(
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const SizedBox(height: 16),
                                  const Center(
                                    child: Column(
                                      children: [
                                        Icon(Icons.celebration_rounded, size: 48, color: Color(0xFF10B981)),
                                        SizedBox(height: 12),
                                        Text(
                                          'Sistem WhatsApp Siap!',
                                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 32),
                                  Container(
                                    padding: const EdgeInsets.all(20),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: const Color(0xFFCBD5E1)),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        const Row(
                                          children: [
                                            Icon(Icons.bar_chart_rounded, size: 20, color: Color(0xFF334155)),
                                            SizedBox(width: 8),
                                            Text(
                                              'UJI COBA WA POLL',
                                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF334155), letterSpacing: 0.5),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 16),
                                        const Text(
                                          'Nomor HP Uji Coba:',
                                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF475569)),
                                        ),
                                        const SizedBox(height: 6),
                                        TextField(
                                          controller: _testPhoneCtrl,
                                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                          decoration: InputDecoration(
                                            hintText: 'Contoh: 6289522584477',
                                            filled: true,
                                            fillColor: Colors.white,
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                            border: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(8),
                                              borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                                            ),
                                            enabledBorder: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(8),
                                              borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          'Status Kirim: $_pollStatus',
                                          style: const TextStyle(fontSize: 12, color: Color(0xFF475569), fontWeight: FontWeight.w600),
                                        ),
                                        const SizedBox(height: 12),
                                        ElevatedButton.icon(
                                          onPressed: _sendTestPoll,
                                          icon: const Icon(Icons.send_rounded, size: 14, color: Colors.white),
                                          label: const Text('Kirim Uji Coba Poll', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFF3B82F6),
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(vertical: 12),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                          ),
                                        ),
                                        const SizedBox(height: 20),
                                        const Divider(color: Color(0xFFCBD5E1)),
                                        const SizedBox(height: 12),
                                        const Text(
                                          'HASIL VOTE TERBARU (Real-time):',
                                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                                        ),
                                        const SizedBox(height: 8),
                                        Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: const Color(0xFFE2E8F0)),
                                          ),
                                          child: Text(
                                            _voteResult,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Color(0xFF0F172A),
                                              fontFamily: 'monospace',
                                              fontWeight: FontWeight.bold,
                                              height: 1.4,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        TextButton.icon(
                                          onPressed: _checkVoteResult,
                                          icon: const Icon(Icons.refresh_rounded, size: 14, color: Color(0xFF475569)),
                                          label: const Text('Refresh Vote', style: TextStyle(color: Color(0xFF475569), fontSize: 11, fontWeight: FontWeight.bold)),
                                          style: TextButton.styleFrom(
                                            padding: EdgeInsets.zero,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                // Right Panel: WA Message Templates Editor
                Expanded(
                  flex: 3,
                  child: DefaultTabController(
                    length: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Master Switch Banner
                          Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: _waMasterEnabled ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: _waMasterEnabled ? const Color(0xFFA7F3D0) : const Color(0xFFFECACA)),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _waMasterEnabled ? Icons.chat_rounded : Icons.block_rounded,
                                  color: _waMasterEnabled ? const Color(0xFF059669) : const Color(0xFFDC2626),
                                  size: 26,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Master Switch: Semua Fitur WhatsApp',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13.5,
                                          color: _waMasterEnabled ? const Color(0xFF065F46) : const Color(0xFF991B1B),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _waMasterEnabled
                                            ? 'Fitur WhatsApp aktif (notifikasi mesin & chatbot beroperasi sesuai tab di bawah).'
                                            : 'Seluruh fitur WhatsApp dinonaktifkan total (tidak ada notifikasi & bot mati).',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          color: _waMasterEnabled ? const Color(0xFF047857) : const Color(0xFFB91C1C),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Switch(
                                  value: _waMasterEnabled,
                                  activeColor: const Color(0xFF10B981),
                                  onChanged: (val) {
                                    setState(() {
                                      _waMasterEnabled = val;
                                    });
                                  },
                                ),
                              ],
                            ),
                          ),
                          Container(
                            decoration: const BoxDecoration(
                              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
                            ),
                            child: const TabBar(
                              labelColor: Color(0xFF4E80EE),
                              unselectedLabelColor: Color(0xFF64748B),
                              indicatorColor: Color(0xFF4E80EE),
                              indicatorWeight: 3,
                              labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              tabs: [
                                Tab(
                                  icon: Icon(Icons.edit_note_rounded, size: 18),
                                  text: 'Notifikasi Otomatis Mesin',
                                ),
                                Tab(
                                  icon: Icon(Icons.smart_toy_rounded, size: 18),
                                  text: 'Chatbot Auto-Reply',
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          Expanded(
                            child: TabBarView(
                              children: [
                                // Tab 1: Notifikasi Otomatis Mesin
                                SingleChildScrollView(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      Container(
                                        margin: const EdgeInsets.only(bottom: 20),
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                        decoration: BoxDecoration(
                                          color: _waMachineNotificationsEnabled ? const Color(0xFFF8FAFC) : const Color(0xFFFFFBEB),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: _waMachineNotificationsEnabled ? const Color(0xFFE2E8F0) : const Color(0xFFFDE68A),
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'Aktifkan Notifikasi Mesin Otomatis',
                                                    style: TextStyle(
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 13.5,
                                                      color: _waMachineNotificationsEnabled ? const Color(0xFF0F172A) : const Color(0xFF92400E),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    _waMachineNotificationsEnabled
                                                        ? 'Kirim pesan otomatis saat cucian booking, masuk, mulai berputar, atau selesai.'
                                                        : 'Notifikasi mesin dinonaktifkan (pesan otomatis mesin tidak akan dikirim).',
                                                    style: TextStyle(
                                                      fontSize: 11.5,
                                                      color: _waMachineNotificationsEnabled ? const Color(0xFF64748B) : const Color(0xFFB45309),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Switch(
                                              value: _waMachineNotificationsEnabled,
                                              onChanged: _waMasterEnabled
                                                  ? (val) {
                                                      setState(() {
                                                        _waMachineNotificationsEnabled = val;
                                                      });
                                                    }
                                                  : null,
                                              activeColor: primaryColor,
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (_waMachineNotificationsEnabled) ...[
                                        const Text(
                                          'Template Pesan WhatsApp',
                                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                                        ),
                                        const SizedBox(height: 8),
                                        const Text(
                                          'Atur pesan yang akan dikirim secara otomatis. Gunakan tag {name} untuk nama pelanggan, {mesin} untuk nama mesin cuci, dan {estimasi} untuk sisa waktu.',
                                          style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B), height: 1.45),
                                        ),
                                        const SizedBox(height: 24),
                                        _templateField(
                                          label: '1. Pesan Saat Booking (Batas 5 Menit)',
                                          controller: _bookingController,
                                          hint: 'Contoh: Halo Kak {name}, mesin cuci {mesin} sudah siap digunakan...',
                                        ),
                                        const SizedBox(height: 20),
                                        _templateField(
                                          label: '2. Pesan Saat Cucian Masuk (Sebelum Mulai)',
                                          controller: _cucianMasukController,
                                          hint: 'Contoh: Halo Kak {name}, cucian anda sudah masuk ke mesin cuci...',
                                        ),
                                        const SizedBox(height: 20),
                                        _templateField(
                                          label: '3. Pesan Saat Cucian Mulai Berputar (Running)',
                                          controller: _cucianMulaiController,
                                          hint: 'Contoh: Halo Kak {name}, cucianmu di {mesin} sudah mulai diproses, estimasi selesai {estimasi}...',
                                        ),
                                        const SizedBox(height: 20),
                                        _templateField(
                                          label: '4. Pesan Saat Cucian Selesai',
                                          controller: _cucianSelesaiController,
                                          hint: 'Contoh: Halo Kak {name}, cucianmu di {mesin} sudah selesai! Silakan diambil...',
                                        ),
                                        const SizedBox(height: 20),
                                      ],
                                    ],
                                  ),
                                ),
                                // Tab 2: Chatbot Auto-Reply
                                SingleChildScrollView(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      Container(
                                        margin: const EdgeInsets.only(bottom: 20),
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                        decoration: BoxDecoration(
                                          color: _chatbotEnabled ? const Color(0xFFF8FAFC) : const Color(0xFFFFFBEB),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: _chatbotEnabled ? const Color(0xFFE2E8F0) : const Color(0xFFFDE68A),
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'Aktifkan Chatbot Auto-Reply',
                                                    style: TextStyle(
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 13.5,
                                                      color: _chatbotEnabled ? const Color(0xFF0F172A) : const Color(0xFF92400E),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    _chatbotEnabled
                                                        ? 'Bot otomatis membalas chat masuk pelanggan dengan polling menu.'
                                                        : 'Chatbot dinonaktifkan (kasir dapat chat manual tanpa gangguan balasan bot).',
                                                    style: TextStyle(
                                                      fontSize: 11.5,
                                                      color: _chatbotEnabled ? const Color(0xFF64748B) : const Color(0xFFB45309),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Switch(
                                              value: _chatbotEnabled,
                                              onChanged: _waMasterEnabled
                                                  ? (val) {
                                                      setState(() {
                                                        _chatbotEnabled = val;
                                                      });
                                                    }
                                                  : null,
                                              activeColor: primaryColor,
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (_chatbotEnabled) ...[
                                        _templateField(
                                          label: 'Pesan Sambutan (Judul Welcome Poll):',
                                          controller: _chatbotWelcomeController,
                                          hint: 'Halo! Selamat datang di Azima Laundry...',
                                        ),
                                        const SizedBox(height: 20),
                                        Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              child: _cooldownField(
                                                label: 'Jeda Sambutan:',
                                                value: _chatbotWelcomeCooldown,
                                                helperText: 'Jeda waktu sebelum bot mengirim kembali menu utama ke pelanggan yang sama.',
                                                onChanged: (val) {
                                                  setState(() {
                                                    _chatbotWelcomeCooldown = val;
                                                  });
                                                },
                                              ),
                                            ),
                                            const SizedBox(width: 16),
                                            Expanded(
                                              child: _cooldownField(
                                                label: 'Jeda saat Chat Manual:',
                                                value: _chatbotStaffCooldown,
                                                helperText: 'Chatbot dinonaktifkan sementara ketika kasir membalas chat secara manual.',
                                                onChanged: (val) {
                                                  setState(() {
                                                    _chatbotStaffCooldown = val;
                                                  });
                                                },
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 24),
                                        _buildChatbotMenuEditor(),
                                        const SizedBox(height: 20),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _saveTemplates,
                            icon: const Icon(Icons.save_rounded, size: 18, color: Colors.white),
                            label: const Text('Simpan Pengaturan', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryColor,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shadowColor: Colors.transparent,
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

  Widget _templateField({
    required String label,
    required TextEditingController controller,
    required String hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF475569)),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: 4,
          style: const TextStyle(fontSize: 13.5, color: Color(0xFF0F172A)),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            contentPadding: const EdgeInsets.all(16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF4E80EE), width: 2),
            ),
          ),
        ),
      ],
    );
  }

  Widget _cooldownField({
    required String label,
    required int value,
    required ValueChanged<int> onChanged,
    String? helperText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF475569)),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFCBD5E1)),
            borderRadius: BorderRadius.circular(10),
            color: Colors.white,
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: value,
              isExpanded: true,
              items: [0, 5, 10, 15, 30, 60, 120].map((int val) {
                return DropdownMenuItem<int>(
                  value: val,
                  child: Text(val == 0 ? '0 menit (Selalu Kirim)' : '$val menit'),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) onChanged(val);
              },
            ),
          ),
        ),
        if (helperText != null) ...[
          const SizedBox(height: 4),
          Text(
            helperText,
            style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B), height: 1.3),
          ),
        ],
      ],
    );
  }

  Widget _buildChatbotMenuEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Struktur Menu Poll Chatbot',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF475569)),
            ),
            TextButton.icon(
              onPressed: () => _openMenuItemDialog(null, null),
              icon: const Icon(Icons.add_circle_outline_rounded, size: 16),
              label: const Text('Tambah Menu Utama', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
              style: TextButton.styleFrom(
                foregroundColor: primaryColor,
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_chatbotMenu.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: const Center(
              child: Text(
                'Belum ada menu chatbot. Klik Tambah Menu Utama.',
                style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
              ),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _chatbotMenu.length,
            itemBuilder: (context, index) {
              final item = _chatbotMenu[index] as Map<String, dynamic>;
              return _buildMenuItemCard(item, index, null);
            },
          ),
      ],
    );
  }

  Widget _buildMenuItemCard(Map<String, dynamic> item, int index, int? parentIndex) {
    final bool isSubMenu = parentIndex != null;
    final String type = item['type'] ?? 'text';
    final String label = item['label'] ?? '';
    
    // Type description and color-code
    String typeLabel = 'Teks';
    Color typeColor = const Color(0xFF4F46E5); // Indigo
    IconData typeIcon = Icons.chat_bubble_outline_rounded;
    
    if (type == 'api') {
      typeLabel = 'Otomatis Sistem';
      typeColor = const Color(0xFF0D9488); // Teal
      typeIcon = Icons.settings_suggest_rounded;
    } else if (type == 'poll') {
      typeLabel = 'Sub-Menu Pilihan';
      typeColor = const Color(0xFFD97706); // Amber
      typeIcon = Icons.rule_rounded;
    } else if (type == 'staff') {
      typeLabel = 'Chat Manual Staff';
      typeColor = const Color(0xFFDC2626); // Red
      typeIcon = Icons.support_agent_rounded;
    } else if (type == 'back') {
      typeLabel = 'Kembali';
      typeColor = const Color(0xFF64748B);
      typeIcon = Icons.keyboard_return_rounded;
    }

    return Container(
      margin: EdgeInsets.only(
        bottom: 12,
        left: isSubMenu ? 24.0 : 0.0,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSubMenu ? const Color(0xFFE2E8F0) : const Color(0xFFCBD5E1),
          width: isSubMenu ? 1 : 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: CircleAvatar(
              backgroundColor: typeColor.withOpacity(0.1),
              foregroundColor: typeColor,
              radius: 18,
              child: Icon(typeIcon, size: 18),
            ),
            title: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A)),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: typeColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      typeLabel,
                      style: TextStyle(color: typeColor, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (item['mark_read'] == false)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'Pesan Unread',
                        style: TextStyle(color: Colors.orange, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                ],
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Move Up
                IconButton(
                  icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: index > 0 ? () => _moveMenuItem(index, parentIndex, true) : null,
                ),
                const SizedBox(width: 4),
                // Move Down
                IconButton(
                  icon: const Icon(Icons.arrow_downward_rounded, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    final int maxIdx = isSubMenu
                        ? (_chatbotMenu[parentIndex]['children'] as List).length - 1
                        : _chatbotMenu.length - 1;
                    if (index < maxIdx) {
                      _moveMenuItem(index, parentIndex, false);
                    }
                  },
                ),
                const SizedBox(width: 12),
                // Edit button
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18, color: Color(0xFF64748B)),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => _openMenuItemDialog(index, parentIndex),
                ),
                const SizedBox(width: 8),
                // Delete button
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => _deleteMenuItem(index, parentIndex),
                ),
              ],
            ),
          ),
          // If type is poll and it's root menu, build the sub-menu section
          if (type == 'poll' && !isSubMenu) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: const Color(0xFFF8FAFC),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Pilihan Sub-Menu:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                  ),
                  TextButton.icon(
                    onPressed: () => _openMenuItemDialog(null, index),
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('Tambah Sub-Menu', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    style: TextButton.styleFrom(
                      foregroundColor: primaryColor,
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (item['children'] == null || (item['children'] as List).isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Center(
                        child: Text(
                          'Belum ada sub-menu.',
                          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                        ),
                      ),
                    )
                  else
                    ...List.generate((item['children'] as List).length, (childIdx) {
                      final child = item['children'][childIdx] as Map<String, dynamic>;
                      return _buildMenuItemCard(child, childIdx, index);
                    }),
                ],
              ),
            ),
          ]
        ],
      ),
    );
  }

  void _moveMenuItem(int index, int? parentIndex, bool moveUp) {
    setState(() {
      final targetIndex = moveUp ? index - 1 : index + 1;
      if (parentIndex == null) {
        final item = _chatbotMenu.removeAt(index);
        _chatbotMenu.insert(targetIndex, item);
      } else {
        final parent = _chatbotMenu[parentIndex] as Map<String, dynamic>;
        final children = List<dynamic>.from(parent['children']);
        final item = children.removeAt(index);
        children.insert(targetIndex, item);
        parent['children'] = children;
      }
    });
  }

  void _deleteMenuItem(int index, int? parentIndex) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Menu?', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('Apakah Anda yakin ingin menghapus opsi menu ini?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                if (parentIndex == null) {
                  _chatbotMenu.removeAt(index);
                } else {
                  final parent = _chatbotMenu[parentIndex] as Map<String, dynamic>;
                  final children = List<dynamic>.from(parent['children']);
                  children.removeAt(index);
                  parent['children'] = children;
                }
              });
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Hapus', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _openMenuItemDialog(int? index, int? parentIndex) {
    Map<String, dynamic>? editingItem;
    
    if (index != null) {
      if (parentIndex == null) {
        editingItem = _chatbotMenu[index] as Map<String, dynamic>;
      } else {
        final parent = _chatbotMenu[parentIndex] as Map<String, dynamic>;
        editingItem = parent['children'][index] as Map<String, dynamic>;
      }
    }

    final TextEditingController labelController = TextEditingController(text: editingItem?['label'] ?? '');
    final TextEditingController responseController = TextEditingController(text: editingItem?['response'] ?? '');
    final TextEditingController pollTitleController = TextEditingController(text: editingItem?['poll_title'] ?? '');
    
    String currentType = editingItem?['type'] ?? 'text';
    final bool isSubMenuItem = parentIndex != null;
    
    bool markRead = editingItem?['mark_read'] ?? true;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              padding: EdgeInsets.only(
                top: 24,
                left: 24,
                right: 24,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          editingItem == null ? 'Tambah Menu Baru' : 'Edit Menu Item',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF0F172A)),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(sheetContext),
                        )
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    // Label field
                    const Text('Nama Tombol (di layar WhatsApp):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF475569))),
                    const SizedBox(height: 6),
                    TextField(
                      controller: labelController,
                      maxLength: 30,
                      decoration: InputDecoration(
                        hintText: 'Misal: Daftar Harga Layanan',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Action Type dropdown
                    const Text('Aksi Bot saat Tombol Ditekan:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF475569))),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFCBD5E1)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: currentType,
                          isExpanded: true,
                          items: [
                            const DropdownMenuItem(value: 'text', child: Text('Kirim Pesan Teks')),
                            if (!isSubMenuItem)
                              const DropdownMenuItem(value: 'poll', child: Text('Tampilkan Pilihan Baru (Sub-Menu)')),
                            const DropdownMenuItem(value: 'api', child: Text('Cek Status Cucian Otomatis')),
                            const DropdownMenuItem(value: 'staff', child: Text('Hubungi Kasir (Manual)')),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setSheetState(() {
                                currentType = val;
                                if (val == 'staff') {
                                  markRead = false;
                                } else {
                                  markRead = true;
                                }
                              });
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Mark as read checkbox
                    Row(
                      children: [
                        Checkbox(
                          value: markRead,
                          activeColor: primaryColor,
                          onChanged: (val) {
                            if (val != null) {
                              setSheetState(() {
                                markRead = val;
                              });
                            }
                          },
                        ),
                        const Expanded(
                          child: Text(
                            'Tandai sudah dibaca (Read) di HP Admin agar tidak muncul notifikasi',
                            style: TextStyle(fontSize: 12.5, color: Color(0xFF475569)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Additional fields based on type
                    if (currentType == 'text') ...[
                      const Text('Teks Balasan Bot:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF475569))),
                      const SizedBox(height: 6),
                      TextField(
                        controller: responseController,
                        maxLines: 4,
                        decoration: InputDecoration(
                          hintText: 'Tuliskan informasi lengkap di sini...',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.all(12),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ] else if (currentType == 'poll') ...[
                      const Text('Judul Polling Lanjutan (Pertanyaan):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF475569))),
                      const SizedBox(height: 6),
                      TextField(
                        controller: pollTitleController,
                        decoration: InputDecoration(
                          hintText: 'Pilih jenis layanan yang ingin dilihat harganya:',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ] else if (currentType == 'staff') ...[
                      const Text('Teks Balasan saat Staff Dihubungi:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF475569))),
                      const SizedBox(height: 6),
                      TextField(
                        controller: responseController,
                        maxLines: 2,
                        decoration: InputDecoration(
                          hintText: 'Mohon tunggu sebentar, staf kasir kami akan segera membalas chat Anda...',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.all(12),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    ElevatedButton(
                      onPressed: () {
                        if (labelController.text.trim().isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Nama tombol tidak boleh kosong!'), backgroundColor: Colors.orange),
                          );
                          return;
                        }
                        
                        final Map<String, dynamic> itemData = {
                          'id': editingItem?['id'] ?? 'item_${DateTime.now().millisecondsSinceEpoch}',
                          'label': labelController.text.trim(),
                          'type': currentType,
                          'mark_read': markRead,
                        };
                        
                        if (currentType == 'text') {
                          itemData['response'] = responseController.text.trim();
                        } else if (currentType == 'staff') {
                          itemData['response'] = responseController.text.trim();
                        } else if (currentType == 'poll') {
                          itemData['poll_title'] = pollTitleController.text.trim();
                          itemData['children'] = editingItem?['children'] ?? [];
                        } else if (currentType == 'api') {
                          itemData['action'] = 'status_cucian';
                        }
                        
                        setState(() {
                          if (index == null) {
                            if (parentIndex == null) {
                              _chatbotMenu.add(itemData);
                            } else {
                              final parent = _chatbotMenu[parentIndex] as Map<String, dynamic>;
                              final children = List<dynamic>.from(parent['children'] ?? []);
                              children.add(itemData);
                              parent['children'] = children;
                            }
                          } else {
                            if (parentIndex == null) {
                              _chatbotMenu[index] = itemData;
                            } else {
                              final parent = _chatbotMenu[parentIndex] as Map<String, dynamic>;
                              final children = List<dynamic>.from(parent['children'] ?? []);
                              children[index] = itemData;
                              parent['children'] = children;
                            }
                          }
                        });
                        
                        Navigator.pop(sheetContext);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Simpan Opsi Menu', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
