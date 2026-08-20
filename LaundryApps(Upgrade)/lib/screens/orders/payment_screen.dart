import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../database/models/order_model.dart';
import '../../database/models/database_helper.dart';
import '../../services/midtrans_service.dart';
import '../../utils/currency_format.dart';
import '../../utils/style_constants.dart';

class ThousandsSeparatorInputFormatter extends TextInputFormatter {
  static String format(String digitsOnly) {
    if (digitsOnly.isEmpty) return '';
    final number = int.tryParse(digitsOnly) ?? 0;
    if (number == 0) return '0';
    final s = number.toString();
    final buffer = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) {
        buffer.write('.');
      }
      buffer.write(s[i]);
    }
    return buffer.toString();
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue.copyWith(text: '');
    }

    final digitsOnly = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.isEmpty) {
      return const TextEditingValue(text: '', selection: TextSelection.collapsed(offset: 0));
    }

    final formatted = format(digitsOnly);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class PaymentScreen extends StatefulWidget {
  final Order order;

  const PaymentScreen({
    super.key,
    required this.order,
  });

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  String _paymentStatus = 'lunas'; // 'lunas', 'dp', 'piutang'
  String _paymentMethod = 'cash';  // 'cash', 'qris'
  bool _isProcessing = false;
  bool _paymentCompleted = false;
  String? _qrisUrl;
  String? _qrisId;
  Timer? _statusCheckTimer;
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  // Cash payment variables
  final TextEditingController _cashController = TextEditingController();
  int _cashReceived = 0;

  // Diagnostic fields
  String? _lastStatus;
  String? _lastError;

  String _midtransServerKey = '';

  @override
  void initState() {
    super.initState();
    _loadPaymentCredentials();
    _cashController.addListener(() {
      final text = _cashController.text.replaceAll('.', '').replaceAll(',', '');
      final parsed = int.tryParse(text) ?? 0;
      setState(() {
        _cashReceived = parsed;
      });
    });
  }

  Future<void> _loadPaymentCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _midtransServerKey = prefs.getString('midtrans_server_key') ?? '';
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _statusCheckTimer?.cancel();
    _cashController.dispose();
    super.dispose();
  }

  void _setQuickCash(int amount) {
    if (amount <= 0) {
      _cashController.clear();
    } else {
      final formatted = ThousandsSeparatorInputFormatter.format(amount.toString());
      _cashController.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }
  }

  Future<void> _processPayment() async {
    setState(() {
      _isProcessing = true;
      _lastError = null;
    });

    if (_paymentStatus == 'piutang') {
      await _completePayment(true);
      return;
    }

    if (_paymentMethod == 'cash') {
      if (_paymentStatus == 'lunas') {
        if (_cashReceived < widget.order.totalAmount) {
          setState(() => _isProcessing = false);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Uang tunai yang diterima kurang dari total tagihan!'), backgroundColor: StyleConstants.warningColor),
            );
          }
          return;
        }
        await _completePayment(true);
        return;
      } else if (_paymentStatus == 'dp') {
        if (_cashReceived <= 0 || _cashReceived >= widget.order.totalAmount) {
          setState(() => _isProcessing = false);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Jumlah DP harus lebih besar dari 0 dan kurang dari total tagihan!'), backgroundColor: StyleConstants.warningColor),
            );
          }
          return;
        }
        await _completePayment(true);
        return;
      }
    }

    // QRIS Payment Process (Lunas or DP)
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final orderId = 'ORDER-${widget.order.id ?? timestamp}-$timestamp';

      final double trxAmount = _paymentStatus == 'lunas'
          ? widget.order.totalAmount.toDouble()
          : _cashReceived.toDouble();

      if (trxAmount <= 0) {
        setState(() {
          _lastError = 'Jumlah pembayaran QRIS harus lebih besar dari 0';
          _isProcessing = false;
        });
        return;
      }

      final response = await MidtransService.createQRISTransaction(
        orderId: orderId,
        amount: trxAmount,
        customerName: widget.order.customerName,
        overrideServerKey: _midtransServerKey,
      );

      if (response['success'] != true) {
        final message = response['message'] ?? 'Gagal membuat transaksi QRIS';
        setState(() {
          _lastError = message.toString();
          _isProcessing = false;
        });
        return;
      }

      final qrisData = response['qris_url'] ?? response['qr_code_url'];

      if (qrisData == null || qrisData.toString().isEmpty) {
        setState(() {
          _lastError = 'QR code data tidak ditemukan dalam response server';
          _isProcessing = false;
        });
        return;
      }

      setState(() {
        _qrisUrl = qrisData.toString();
        _qrisId = orderId;
        _lastStatus = response['transaction_status'];
      });

      _startCheckingPaymentStatus(orderId);
    } catch (e) {
      setState(() {
        _lastError = e.toString();
        _isProcessing = false;
      });
    }
  }

  void _startCheckingPaymentStatus(String orderId) {
    _checkStatus(orderId);
    _statusCheckTimer = Timer.periodic(const Duration(seconds: 4), (timer) async {
      await _checkStatus(orderId);
    });
  }

  Future<void> _checkStatus(String orderId) async {
    try {
      final status = await MidtransService.checkTransactionStatus(
        orderId,
        overrideServerKey: _midtransServerKey,
      );

      if (mounted) {
        setState(() {
          _lastStatus = status['transaction_status']?.toString();
        });
      }

      if (_lastStatus == 'settlement' || _lastStatus == 'capture') {
        _statusCheckTimer?.cancel();
        await _completePayment(true);
      } else if (_lastStatus == 'deny' || _lastStatus == 'cancel' || _lastStatus == 'expire') {
        _statusCheckTimer?.cancel();
        if (mounted) {
          setState(() {
            _lastError = 'Pembayaran QRIS tidak berhasil: $_lastStatus';
            _isProcessing = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _lastError = e.toString();
        });
      }
    }
  }

  Future<void> _completePayment(bool success) async {
    _statusCheckTimer?.cancel();
    if (_paymentCompleted) return;
    _paymentCompleted = true;

    if (!success) {
      if (mounted) {
        setState(() => _isProcessing = false);
        Navigator.of(context).pop(false);
      }
      return;
    }

    try {
      bool isPaidFlag = false;
      int paidAmt = 0;
      String methodStr = 'cash';

      if (_paymentStatus == 'lunas') {
        isPaidFlag = true;
        paidAmt = widget.order.totalAmount;
        methodStr = _paymentMethod;
      } else if (_paymentStatus == 'dp') {
        isPaidFlag = false;
        paidAmt = _cashReceived;
        methodStr = _paymentMethod == 'cash' ? 'Bayar Setengah' : 'qris';
      } else if (_paymentStatus == 'piutang') {
        isPaidFlag = false;
        paidAmt = 0;
        methodStr = 'Belum Lunas';
      }

      final updatedOrder = widget.order.copyWith(
        isPaid: isPaidFlag,
        paidAmount: paidAmt,
        paymentMethod: methodStr,
        qrisUrl: _qrisUrl,
        qrisId: _qrisId,
        paymentTimestamp: DateTime.now(),
      );

      await _dbHelper.updateOrder(updatedOrder);
      if (mounted) {
        setState(() => _isProcessing = false);
        Navigator.of(context).pop(true);
      }
    } catch (_) {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final change = _cashReceived - widget.order.totalAmount;

    return Scaffold(
      backgroundColor: StyleConstants.backgroundColor,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Header Bar
          Container(
            height: StyleConstants.topBarHeight,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: StyleConstants.borderLight)),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, color: StyleConstants.textHeading),
                  tooltip: 'Batal / Kembali ke Nota',
                  onPressed: _isProcessing ? null : () => Navigator.pop(context, false),
                ),
                const SizedBox(width: 8),
                const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'STUDIO PEMBAYARAN KASIR (POS)',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: StyleConstants.textHeading,
                        letterSpacing: -0.3,
                      ),
                    ),
                    Text(
                      'Pilih metode pelunasan atau cetak nota QRIS dinamis',
                      style: TextStyle(fontSize: 11, color: StyleConstants.textMuted),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Main 2-Pane Split Workstation (Workstation Kiri, Ringkasan & Opsi Kanan)
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. SISI KIRI (Expanded): Dedicated Interactive Tender Workstation
                Expanded(
                  child: Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(28),
                    child: (_paymentStatus == 'piutang')
                        ? _buildUnpaidPane()
                        : (_paymentMethod == 'cash')
                            ? _buildCashPane(change)
                            : _buildQrisPane(),
                  ),
                ),

                // VERTICAL DIVIDER
                Container(width: 1, color: StyleConstants.borderLight),

                // 2. SISI KANAN (380px): Invoice Summary & Status Option Selector
                Container(
                  width: 380,
                  color: const Color(0xFFF8FAFC),
                  padding: const EdgeInsets.all(24),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Bill Recap Card
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: StyleConstants.cardDecoration(),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.receipt_long_rounded, size: 18, color: StyleConstants.primaryColor),
                                  SizedBox(width: 8),
                                  Text(
                                    'Tagihan Nota Pesanan',
                                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: StyleConstants.textHeading),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              const Divider(height: 1, color: StyleConstants.borderLight),
                              const SizedBox(height: 12),
                              _infoRow('Nama Pelanggan', widget.order.customerName),
                              const SizedBox(height: 8),
                              _infoRow('Total Tagihan', formatRp(widget.order.totalAmount), isBold: true, color: StyleConstants.primaryColor),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Payment Status Picker
                        const Text(
                          'STATUS PEMBAYARAN:',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: StyleConstants.textMuted, letterSpacing: 0.5),
                        ),
                        const SizedBox(height: 8),

                        _statusOptionTile(
                          key: 'lunas',
                          title: 'Bayar Lunas Penuh',
                          subtitle: 'Pembayaran diterima penuh saat ini',
                          icon: Icons.check_circle_rounded,
                          color: StyleConstants.successColor,
                        ),
                        const SizedBox(height: 8),
                        _statusOptionTile(
                          key: 'dp',
                          title: 'Bayar Uang Muka (DP)',
                          subtitle: 'Pembayaran sebagian, sisa jadi piutang',
                          icon: Icons.pending_rounded,
                          color: StyleConstants.warningColor,
                        ),
                        const SizedBox(height: 8),
                        _statusOptionTile(
                          key: 'piutang',
                          title: 'Bayar Nanti (Piutang / Tempo)',
                          subtitle: 'Pakaian diproses, bayar saat ambil',
                          icon: Icons.access_time_filled_rounded,
                          color: StyleConstants.dangerColor,
                        ),

                        const SizedBox(height: 20),

                        // Payment Method (Only for Lunas or DP)
                        if (_paymentStatus != 'piutang') ...[
                          const Text(
                            'METODE TRANSAKSI:',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: StyleConstants.textMuted, letterSpacing: 0.5),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: _methodSelectTile(
                                  key: 'cash',
                                  label: 'Tunai / Cash',
                                  icon: Icons.payments_rounded,
                                  color: StyleConstants.successColor,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _methodSelectTile(
                                  key: 'qris',
                                  label: 'QRIS Dinamis',
                                  icon: Icons.qr_code_scanner_rounded,
                                  color: StyleConstants.primaryColor,
                                ),
                              ),
                            ],
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
      ),
    );
  }

  Widget _infoRow(String label, String val, {bool isBold = false, Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 12.5, color: StyleConstants.textMuted)),
        Text(
          val,
          style: TextStyle(
            fontSize: isBold ? 15 : 12.5,
            fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
            color: color ?? StyleConstants.textHeading,
          ),
        ),
      ],
    );
  }

  Widget _statusOptionTile({
    required String key,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    final isSelected = _paymentStatus == key;
    return InkWell(
      onTap: _isProcessing ? null : () => setState(() => _paymentStatus = key),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? color : StyleConstants.borderLight,
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [BoxShadow(color: color.withValues(alpha: 0.15), blurRadius: 8, offset: const Offset(0, 2))]
              : null,
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? color : StyleConstants.textMuted, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: isSelected ? StyleConstants.textHeading : StyleConstants.textBody,
                    ),
                  ),
                  Text(subtitle, style: const TextStyle(fontSize: 11, color: StyleConstants.textMuted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _methodSelectTile({
    required String key,
    required String label,
    required IconData icon,
    required Color color,
  }) {
    final isSelected = _paymentMethod == key;
    return InkWell(
      onTap: _isProcessing ? null : () => setState(() => _paymentMethod = key),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.1) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? color : StyleConstants.borderLight,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: isSelected ? color : StyleConstants.textMuted),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: isSelected ? color : StyleConstants.textBody,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- CASH TENDER PANE (DESKTOP KEYBOARD WORKSTATION) ---
  Widget _buildCashPane(int change) {
    final isLunasMode = _paymentStatus == 'lunas';
    final isButtonEnabled = isLunasMode
        ? _cashReceived >= widget.order.totalAmount
        : (_cashReceived > 0 && _cashReceived < widget.order.totalAmount);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isLunasMode ? 'Input Nominal Uang Tunai Diterima' : 'Input Nominal Uang Muka (DP)',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: StyleConstants.textHeading),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Ketik langsung menggunakan keyboard fisik atau pilih pecahan cepat',
                  style: TextStyle(fontSize: 12, color: StyleConstants.textMuted),
                ),
              ],
            ),
            if (_cashReceived > 0)
              TextButton.icon(
                onPressed: () => _cashController.clear(),
                icon: const Icon(Icons.clear_rounded, size: 16, color: StyleConstants.dangerColor),
                label: const Text('Reset', style: TextStyle(color: StyleConstants.dangerColor, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
          ],
        ),
        const SizedBox(height: 16),

        // 1. Large Focused Cash Input Field (Keyboard First)
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isButtonEnabled ? StyleConstants.successColor : StyleConstants.borderFocus,
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: StyleConstants.primaryColor.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            children: [
              const Text(
                'Rp',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: StyleConstants.textMuted),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: TextField(
                  controller: _cashController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    ThousandsSeparatorInputFormatter(),
                  ],
                  autofocus: true,
                  style: StyleConstants.tabularNumbers(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: StyleConstants.textHeading,
                  ),
                  decoration: const InputDecoration(
                    hintText: '0',
                    hintStyle: TextStyle(color: Color(0xFFCBD5E1), fontSize: 28, fontWeight: FontWeight.w900),
                    border: InputBorder.none,
                  ),
                  onSubmitted: (_) {
                    if (isButtonEnabled && !_isProcessing) {
                      _processPayment();
                    }
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // 2. Quick Cash Denomination Suggestions
        const Text(
          'PILIHAN PECAHAN UANG CEPAT:',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: StyleConstants.textMuted, letterSpacing: 0.5),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _quickCashPresetBtn(widget.order.totalAmount, 'Uang Pas (${formatRp(widget.order.totalAmount)})', isExact: true),
            _quickCashPresetBtn(10000, 'Rp 10.000'),
            _quickCashPresetBtn(20000, 'Rp 20.000'),
            _quickCashPresetBtn(50000, 'Rp 50.000'),
            _quickCashPresetBtn(100000, 'Rp 100.000'),
            _quickCashPresetBtn(200000, 'Rp 200.000'),
            _quickCashPresetBtn(500000, 'Rp 500.000'),
          ],
        ),
        const SizedBox(height: 24),

        // 3. Live Change / Kembalian Calculation Display (Enterprise POS Banner)
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isLunasMode
                ? (change >= 0 ? const Color(0xFFECFDF5) : const Color(0xFFFFFBEB))
                : const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isLunasMode
                  ? (change >= 0 ? const Color(0xFFA7F3D0) : const Color(0xFFFDE68A))
                  : const Color(0xFFBFDBFE),
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isLunasMode
                          ? (change >= 0 ? StyleConstants.successColor.withValues(alpha: 0.15) : StyleConstants.warningColor.withValues(alpha: 0.15))
                          : StyleConstants.primaryColor.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isLunasMode
                          ? (change >= 0 ? Icons.price_check_rounded : Icons.warning_amber_rounded)
                          : Icons.account_balance_wallet_rounded,
                      size: 26,
                      color: isLunasMode
                          ? (change >= 0 ? StyleConstants.successColor : StyleConstants.warningColor)
                          : StyleConstants.primaryColor,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isLunasMode
                            ? (change >= 0 ? 'KEMBALIAN UANG TUNAI' : 'UANG PEMBAYARAN KURANG')
                            : 'SISA PEMBAYARAN (PIUTANG)',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          color: isLunasMode
                              ? (change >= 0 ? const Color(0xFF047857) : const Color(0xFFB45309))
                              : const Color(0xFF1D4ED8),
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        isLunasMode
                            ? (change >= 0 ? 'Uang kembalian yang harus diserahkan ke pelanggan' : 'Nominal diterima belum mencukupi total tagihan')
                            : 'Akan tercatat sebagai piutang pelanggan',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: isLunasMode
                              ? (change >= 0 ? const Color(0xFF065F46) : const Color(0xFF92400E))
                              : const Color(0xFF1E40AF),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Text(
                isLunasMode
                    ? formatRp(change >= 0 ? change : change.abs())
                    : formatRp((widget.order.totalAmount - _cashReceived).clamp(0, widget.order.totalAmount)),
                style: StyleConstants.tabularNumbers(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: isLunasMode
                      ? (change >= 0 ? const Color(0xFF047857) : const Color(0xFFB45309))
                      : const Color(0xFF1D4ED8),
                ),
              ),
            ],
          ),
        ),

        const Spacer(),

        // 4. Large Action Confirmation Button (Keyboard Enter Action)
        ElevatedButton(
          onPressed: (isButtonEnabled && !_isProcessing) ? _processPayment : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: isLunasMode ? StyleConstants.successColor : StyleConstants.warningColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 18),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 0,
          ),
          child: _isProcessing
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.check_circle_rounded, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      isLunasMode ? 'KONFIRMASI PEMBAYARAN LUNAS & CETAK STRUK (ENTER)' : 'KONFIRMASI PEMBAYARAN DP (ENTER)',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 0.5),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _quickCashPresetBtn(int amount, String label, {bool isExact = false}) {
    final isSelected = _cashReceived == amount;
    return OutlinedButton(
      onPressed: () => _setQuickCash(amount),
      style: OutlinedButton.styleFrom(
        backgroundColor: isExact
            ? (isSelected ? StyleConstants.primaryColor : StyleConstants.primaryColor.withValues(alpha: 0.08))
            : (isSelected ? StyleConstants.textHeading : Colors.white),
        foregroundColor: isExact
            ? (isSelected ? Colors.white : StyleConstants.primaryColor)
            : (isSelected ? Colors.white : StyleConstants.textHeading),
        side: BorderSide(
          color: isExact ? StyleConstants.primaryColor : (isSelected ? StyleConstants.textHeading : StyleConstants.borderLight),
          width: isSelected ? 1.5 : 1,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: isExact
              ? (isSelected ? Colors.white : StyleConstants.primaryColor)
              : (isSelected ? Colors.white : StyleConstants.textHeading),
        ),
      ),
    );
  }

  // --- UNPAID PANE ---
  Widget _buildUnpaidPane() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.pending_actions_rounded, size: 64, color: StyleConstants.dangerColor),
        const SizedBox(height: 14),
        const Text(
          'Konfirmasi Pembayaran Piutang (Tempo)',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: StyleConstants.textHeading),
        ),
        const SizedBox(height: 8),
        Text(
          'Pesanan atas nama "${widget.order.customerName}" akan dicatat sebagai Belum Bayar sebesar ${formatRp(widget.order.totalAmount)}.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12.5, color: StyleConstants.textMuted, height: 1.4),
        ),
        const SizedBox(height: 24),
        const Spacer(),
        ElevatedButton(
          onPressed: !_isProcessing ? _processPayment : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: StyleConstants.dangerColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            elevation: 0,
          ),
          child: _isProcessing
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('SIMPAN SEBAGAI PIUTANG', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5)),
        ),
      ],
    );
  }

  // --- QRIS PANE ---
  Widget _buildQrisPane() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (_qrisUrl == null) ...[
          const Icon(Icons.qr_code_2_rounded, size: 64, color: StyleConstants.primaryColor),
          const SizedBox(height: 14),
          const Text(
            'Pembuatan QRIS Dinamis Midtrans',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: StyleConstants.textHeading),
          ),
          const SizedBox(height: 8),
          Text(
            'Klik tombol di bawah untuk membuat barcode QRIS resmi sebesar ${formatRp(widget.order.totalAmount)}.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12.5, color: StyleConstants.textMuted, height: 1.4),
          ),
          if (_lastError != null) ...[
            const SizedBox(height: 12),
            Text('Error: $_lastError', textAlign: TextAlign.center, style: const TextStyle(color: StyleConstants.dangerColor, fontSize: 12, fontWeight: FontWeight.bold)),
          ],
          const Spacer(),
          ElevatedButton(
            onPressed: _isProcessing ? null : _processPayment,
            style: ElevatedButton.styleFrom(
              backgroundColor: StyleConstants.primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: _isProcessing
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('BUAT BARCODE QRIS LUNAS', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5)),
          ),
        ] else ...[
          const Text(
            'Scan Barcode QRIS di Bawah Ini',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: StyleConstants.textHeading),
          ),
          const SizedBox(height: 6),
          Text(
            'Nominal: ${formatRp(widget.order.totalAmount)}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: StyleConstants.primaryColor),
          ),
          const SizedBox(height: 14),
          Center(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: StyleConstants.borderLight),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.04),
                    blurRadius: 16,
                  ),
                ],
              ),
              child: QrImageView(
                data: _qrisUrl!,
                version: QrVersions.auto,
                size: 190.0,
                backgroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 8),
              Text(
                'Menunggu Pembayaran Pelanggan (${_lastStatus ?? "pending"})...',
                style: const TextStyle(fontSize: 12.5, color: StyleConstants.warningColor, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _checkStatus(_qrisId!),
                  icon: const Icon(Icons.sync_rounded, size: 16),
                  label: const Text('Cek Status Manual'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    _statusCheckTimer?.cancel();
                    setState(() {
                      _qrisUrl = null;
                      _qrisId = null;
                      _isProcessing = false;
                    });
                  },
                  icon: const Icon(Icons.cancel_rounded, size: 16),
                  label: const Text('Batalkan QRIS'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: StyleConstants.dangerColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
