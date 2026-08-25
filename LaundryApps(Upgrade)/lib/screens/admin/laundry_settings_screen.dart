import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../utils/style_constants.dart';
import '../../utils/globals.dart';

class LaundrySettingsScreen extends StatefulWidget {
  const LaundrySettingsScreen({Key? key}) : super(key: key);

  @override
  State<LaundrySettingsScreen> createState() => _LaundrySettingsScreenState();
}

class _LaundrySettingsScreenState extends State<LaundrySettingsScreen> {
  bool _loyaltyEnabled = true;
  int _loyaltyThreshold = 5;
  bool _isLoading = true;

  final TextEditingController _thresholdController = TextEditingController();

  final Color primaryColor = StyleConstants.primaryColor;
  final Color backgroundColor = StyleConstants.backgroundColor;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _thresholdController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _loyaltyEnabled = prefs.getBool('loyalty_program_enabled') ?? true;
      _loyaltyThreshold = prefs.getInt('loyalty_wash_threshold') ?? 5;
      _thresholdController.text = _loyaltyThreshold.toString();
      _isLoading = false;
    });
  }

  Future<void> _saveLoyaltySettings() async {
    final int? parsed = int.tryParse(_thresholdController.text.trim());
    if (parsed == null || parsed <= 0) {
      Globals.showWarningSnackBar('Target jumlah cuci harus berupa angka minimal 1.');
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('loyalty_program_enabled', _loyaltyEnabled);
    await prefs.setInt('loyalty_wash_threshold', parsed);

    setState(() {
      _loyaltyThreshold = parsed;
    });

    Globals.showSuccessSnackBar('Pengaturan program kupon cuci berhasil disimpan!');
  }

  void _incrementThreshold() {
    setState(() {
      _loyaltyThreshold++;
      _thresholdController.text = _loyaltyThreshold.toString();
    });
  }

  void _decrementThreshold() {
    if (_loyaltyThreshold > 1) {
      setState(() {
        _loyaltyThreshold--;
        _thresholdController.text = _loyaltyThreshold.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text('Pengaturan Laundry & Program Kupon', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        backgroundColor: Colors.white,
        foregroundColor: StyleConstants.textHeading,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: StyleConstants.borderLight, height: 1),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 1. Loyalty Program Settings Card
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: StyleConstants.borderLight),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF0F172A).withValues(alpha: 0.03),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFD97706).withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(Icons.card_giftcard_rounded, color: Color(0xFFD97706), size: 22),
                                ),
                                const SizedBox(width: 14),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Program Kupon Cuci Gratis',
                                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: StyleConstants.textHeading),
                                      ),
                                      SizedBox(height: 2),
                                      Text(
                                        'Atur otomatis cuci gratis setelah pelanggan mencuci sekian kali',
                                        style: TextStyle(fontSize: 12, color: StyleConstants.textMuted),
                                      ),
                                    ],
                                  ),
                                ),
                                Switch(
                                  value: _loyaltyEnabled,
                                  activeColor: const Color(0xFFD97706),
                                  activeTrackColor: const Color(0xFFFDE68A),
                                  onChanged: (val) {
                                    setState(() => _loyaltyEnabled = val);
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            const Divider(color: StyleConstants.borderLight, height: 1),
                            const SizedBox(height: 20),

                            // Threshold Setting
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Jumlah Cuci untuk Dapat 1x Gratis',
                                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: StyleConstants.textHeading),
                                      ),
                                      SizedBox(height: 3),
                                      Text(
                                        'Berapa kali cuci yang dibutuhkan sebelum kupon gratis bisa dipakai',
                                        style: TextStyle(fontSize: 11.5, color: StyleConstants.textMuted),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: StyleConstants.borderLight),
                                  ),
                                  child: Row(
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.remove_rounded, size: 18),
                                        onPressed: _loyaltyEnabled ? _decrementThreshold : null,
                                        color: const Color(0xFFD97706),
                                      ),
                                      SizedBox(
                                        width: 44,
                                        child: TextField(
                                          controller: _thresholdController,
                                          enabled: _loyaltyEnabled,
                                          keyboardType: TextInputType.number,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                                          decoration: const InputDecoration(
                                            border: InputBorder.none,
                                            contentPadding: EdgeInsets.zero,
                                          ),
                                          onChanged: (val) {
                                            final numVal = int.tryParse(val);
                                            if (numVal != null && numVal > 0) {
                                              _loyaltyThreshold = numVal;
                                            }
                                          },
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.add_rounded, size: 18),
                                        onPressed: _loyaltyEnabled ? _incrementThreshold : null,
                                        color: const Color(0xFFD97706),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // Preview banner
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: _loyaltyEnabled ? const Color(0xFFFFFBEB) : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: _loyaltyEnabled ? const Color(0xFFFDE68A) : const Color(0xFFE2E8F0),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    _loyaltyEnabled ? Icons.info_outline_rounded : Icons.pause_circle_outline_rounded,
                                    size: 18,
                                    color: _loyaltyEnabled ? const Color(0xFFD97706) : StyleConstants.textMuted,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      _loyaltyEnabled
                                          ? 'Program Aktif: Setiap pelanggan yang sudah mencuci $_loyaltyThreshold kali berhak memakai 1x Cuci Gratis (Rp 0) di kasir POS. Saat diklaim, kupon dipotong $_loyaltyThreshold (bukan di-reset).'
                                          : 'Program Cuci Gratis Nonaktif: Kupon cuci tidak akan dihitung dan opsi klaim di kasir POS disembunyikan.',
                                      style: TextStyle(
                                        fontSize: 12,
                                        height: 1.4,
                                        color: _loyaltyEnabled ? const Color(0xFF78350F) : StyleConstants.textMuted,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),

                            // Save Button
                            Align(
                              alignment: Alignment.centerRight,
                              child: ElevatedButton.icon(
                                onPressed: _saveLoyaltySettings,
                                icon: const Icon(Icons.save_rounded, size: 16),
                                label: const Text('Simpan Pengaturan Kupon', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFD97706),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  elevation: 0,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // 2. Hardware & Dryer Management Link
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: StyleConstants.borderLight),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF0F172A).withValues(alpha: 0.03),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: () => Navigator.pushNamed(context, '/mesin_pengering'),
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF97316).withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(Icons.wb_sunny_rounded, color: Color(0xFFF97316), size: 22),
                                  ),
                                  const SizedBox(width: 14),
                                  const Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Kelola Mesin Pengering (Dryer)',
                                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: StyleConstants.textHeading),
                                        ),
                                        SizedBox(height: 2),
                                        Text(
                                          'Atur daftar mesin pengering, nama kustom, dan urutan tampilan kasir',
                                          style: TextStyle(fontSize: 12, color: StyleConstants.textMuted),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.arrow_forward_ios_rounded, color: StyleConstants.textMuted, size: 14),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}