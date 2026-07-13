import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PaymentSettingsScreen extends StatefulWidget {
  const PaymentSettingsScreen({Key? key}) : super(key: key);

  @override
  State<PaymentSettingsScreen> createState() => _PaymentSettingsScreenState();
}

class _PaymentSettingsScreenState extends State<PaymentSettingsScreen> {
  String _selectedProvider = 'midtrans';
  bool _isLoading = true;
  bool _hideClientKey = true;
  bool _hideServerKey = true;
  bool _hideXenditApi = true;
  bool _hideXenditSecret = true;
  
  // Midtrans controllers
  late TextEditingController _midtransMerchantIdController;
  late TextEditingController _midtransClientKeyController;
  late TextEditingController _midtransServerKeyController;
  
  // Xendit controllers
  late TextEditingController _xenditApiKeyController;
  late TextEditingController _xenditSecretKeyController;

  final Color primaryColor = const Color(0xFF4E80EE);
  final Color backgroundColor = const Color(0xFFF8FAFC);

  @override
  void initState() {
    super.initState();
    _midtransMerchantIdController = TextEditingController();
    _midtransClientKeyController = TextEditingController();
    _midtransServerKeyController = TextEditingController();
    _xenditApiKeyController = TextEditingController();
    _xenditSecretKeyController = TextEditingController();
    _loadSettings();
  }

  @override
  void dispose() {
    _midtransMerchantIdController.dispose();
    _midtransClientKeyController.dispose();
    _midtransServerKeyController.dispose();
    _xenditApiKeyController.dispose();
    _xenditSecretKeyController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _selectedProvider = prefs.getString('payment_provider') ?? 'midtrans';
        _midtransMerchantIdController.text = prefs.getString('midtrans_merchant_id') ?? '';
        _midtransClientKeyController.text = prefs.getString('midtrans_client_key') ?? '';
        _midtransServerKeyController.text = prefs.getString('midtrans_server_key') ?? '';
        _xenditApiKeyController.text = prefs.getString('xendit_api_key') ?? '';
        _xenditSecretKeyController.text = prefs.getString('xendit_secret_key') ?? '';
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading settings: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('payment_provider', _selectedProvider);
      await prefs.setString('midtrans_merchant_id', _midtransMerchantIdController.text.trim());
      await prefs.setString('midtrans_client_key', _midtransClientKeyController.text.trim());
      await prefs.setString('midtrans_server_key', _midtransServerKeyController.text.trim());
      await prefs.setString('xendit_api_key', _xenditApiKeyController.text.trim());
      await prefs.setString('xendit_secret_key', _xenditSecretKeyController.text.trim());
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Pengaturan pembayaran berhasil disimpan!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error saving settings: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Gagal menyimpan pengaturan: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  InputDecoration _inputDecoration(String label, String hint, IconData icon, {Widget? suffixIcon}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
      hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
      floatingLabelStyle: const TextStyle(color: Color(0xFF4E80EE), fontWeight: FontWeight.bold),
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
      prefixIcon: Icon(icon, color: const Color(0xFF64748B), size: 20),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text('Pengaturan Payment Gateway', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
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
                // 1. Left Panel: Provider Selection (360px)
                Container(
                  width: 360,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(right: BorderSide(color: Color(0xFFE2E8F0))),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Pilih Provider Pembayaran',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF475569), letterSpacing: 0.5),
                        ),
                        const SizedBox(height: 16),
                        
                        _buildProviderOption('midtrans', 'Midtrans Gateway', 'Dukungan QRIS, LinkAja, OVO, GOPAY, ShopeePay.', Icons.payment_rounded),
                        const SizedBox(height: 12),
                        _buildProviderOption('xendit', 'Xendit Invoice', 'Dukungan Virtual Account Bank, E-wallet, Credit Card.', Icons.account_balance_wallet_rounded),
                        
                        const SizedBox(height: 28),
                        const Divider(color: Color(0xFFF1F5F9)),
                        const SizedBox(height: 24),

                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.04),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.blue.withOpacity(0.12)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.info_outline_rounded, size: 18, color: primaryColor),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  'Kredensial client dan server key digunakan untuk membuat link/barcode QRIS pembayaran transaksi kasir secara otomatis.',
                                  style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B), height: 1.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // 2. Right Panel: Credentials Form (Expanded)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Container(
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.02),
                            blurRadius: 16,
                            offset: const Offset(0, 8),
                          )
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _selectedProvider == 'midtrans' ? 'Detail Akses Midtrans' : 'Detail Akses Xendit',
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'Lengkapi kredensial merchant API untuk integrasi e-wallet',
                                    style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
                                  ),
                                ],
                              ),
                              ElevatedButton.icon(
                                onPressed: _saveSettings,
                                icon: const Icon(Icons.save_rounded, color: Colors.white, size: 18),
                                label: const Text('Simpan Pengaturan', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: primaryColor,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shadowColor: Colors.transparent,
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          const Divider(color: Color(0xFFF1F5F9)),
                          const SizedBox(height: 24),

                          Expanded(
                            child: SingleChildScrollView(
                              child: _selectedProvider == 'midtrans'
                                  ? _buildMidtransForm()
                                  : _buildXenditForm(),
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

  Widget _buildProviderOption(String val, String title, String desc, IconData icon) {
    final isSelected = _selectedProvider == val;
    return Container(
      decoration: BoxDecoration(
        color: isSelected ? primaryColor.withOpacity(0.04) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected ? primaryColor : const Color(0xFFE2E8F0),
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          hoverColor: const Color(0xFFF8FAFC),
          onTap: () => setState(() => _selectedProvider = val),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: isSelected ? primaryColor : const Color(0xFFF1F5F9),
                  child: Icon(icon, color: isSelected ? Colors.white : const Color(0xFF64748B), size: 18),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13.5,
                          color: isSelected ? primaryColor : const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        desc,
                        style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), height: 1.3),
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  Icon(Icons.check_circle_rounded, color: primaryColor, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMidtransForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _midtransMerchantIdController,
          decoration: _inputDecoration(
            'Merchant ID',
            'Masukkan Merchant ID Midtrans',
            Icons.business_rounded,
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _midtransClientKeyController,
          obscureText: _hideClientKey,
          decoration: _inputDecoration(
            'Client Key',
            'Mulai dengan VT-client- atau Mid-client-',
            Icons.vpn_key_rounded,
            suffixIcon: IconButton(
              icon: Icon(_hideClientKey ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: const Color(0xFF64748B)),
              onPressed: () => setState(() => _hideClientKey = !_hideClientKey),
            ),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _midtransServerKeyController,
          obscureText: _hideServerKey,
          decoration: _inputDecoration(
            'Server Key',
            'Mulai dengan VT-server- atau Mid-server-',
            Icons.security_rounded,
            suffixIcon: IconButton(
              icon: Icon(_hideServerKey ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: const Color(0xFF64748B)),
              onPressed: () => setState(() => _hideServerKey = !_hideServerKey),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildXenditForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _xenditApiKeyController,
          obscureText: _hideXenditApi,
          decoration: _inputDecoration(
            'API Public Key',
            'Masukkan API Key Xendit',
            Icons.vpn_key_rounded,
            suffixIcon: IconButton(
              icon: Icon(_hideXenditApi ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: const Color(0xFF64748B)),
              onPressed: () => setState(() => _hideXenditApi = !_hideXenditApi),
            ),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _xenditSecretKeyController,
          obscureText: _hideXenditSecret,
          decoration: _inputDecoration(
            'Secret Key',
            'Masukkan Secret Key Xendit',
            Icons.security_rounded,
            suffixIcon: IconButton(
              icon: Icon(_hideXenditSecret ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: const Color(0xFF64748B)),
              onPressed: () => setState(() => _hideXenditSecret = !_hideXenditSecret),
            ),
          ),
        ),
      ],
    );
  }
}
