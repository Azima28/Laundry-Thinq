import 'dart:async';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../database/models/order_model.dart';
import '../../database/models/database_helper.dart';
import '../../services/midtrans_service.dart';
import '../../utils/currency_format.dart';
import '../../utils/style_constants.dart';

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

  void _onKeyPress(String val) {
    String currentText = _cashController.text.replaceAll('.', '').replaceAll(',', '');
    if (val == 'C') {
      _cashController.clear();
    } else if (val == 'back') {
      if (currentText.isNotEmpty) {
        currentText = currentText.substring(0, currentText.length - 1);
        _cashController.text = currentText;
      }
    } else {
      currentText += val;
      _cashController.text = currentText;
    }
  }

  void _setQuickCash(int amount) {
    _cashController.text = amount.toString();
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

          // Main 2-Pane Split Workstation
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Sisi Kiri (380px): Invoice Summary & Status Option Selector
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

                // VERTICAL DIVIDER
                Container(width: 1, color: StyleConstants.borderLight),

                // Sisi Kanan: Dedicated Interactive Tender Workstation
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

  // --- CASH TENDER PANE ---
  Widget _buildCashPane(int change) {
    final isLunasMode = _paymentStatus == 'lunas';
    final isButtonEnabled = isLunasMode
        ? _cashReceived >= widget.order.totalAmount
        : (_cashReceived > 0 && _cashReceived < widget.order.totalAmount);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          isLunasMode ? 'Input Nominal Uang Tunai (Lunas)' : 'Input Nominal Uang Tunai DP (Cicilan)',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: StyleConstants.textHeading),
        ),
        const SizedBox(height: 14),

        // Cash Input Field
        TextFormField(
          controller: _cashController,
          keyboardType: TextInputType.number,
          autofocus: true,
          style: StyleConstants.tabularNumbers(fontSize: 24, fontWeight: FontWeight.w900, color: StyleConstants.textHeading),
          decoration: InputDecoration(
            prefixIcon: const Padding(
              padding: EdgeInsets.only(left: 18, right: 10),
              child: Text('Rp', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: StyleConstants.textMuted)),
            ),
            prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: StyleConstants.borderLight)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: StyleConstants.borderLight)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: StyleConstants.borderFocus, width: 2)),
          ),
        ),
        const SizedBox(height: 12),

        // Change or Debt Box
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isLunasMode
                ? (change >= 0 ? StyleConstants.statusSuccessBg : StyleConstants.statusWarningBg)
                : StyleConstants.statusInfoBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isLunasMode
                  ? (change >= 0 ? StyleConstants.successColor.withValues(alpha: 0.3) : StyleConstants.warningColor.withValues(alpha: 0.3))
                  : StyleConstants.primaryColor.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isLunasMode
                    ? (change >= 0 ? 'Kembalian Pelanggan:' : 'Uang Pembayaran Kurang:')
                    : 'Sisa Pembayaran (Piutang):',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: isLunasMode
                      ? (change >= 0 ? StyleConstants.statusSuccessText : StyleConstants.statusWarningText)
                      : StyleConstants.statusInfoText,
                ),
              ),
              Text(
                isLunasMode
                    ? formatRp(change.abs())
                    : formatRp((widget.order.totalAmount - _cashReceived).clamp(0, widget.order.totalAmount)),
                style: StyleConstants.tabularNumbers(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: isLunasMode
                      ? (change >= 0 ? StyleConstants.statusSuccessText : StyleConstants.statusWarningText)
                      : StyleConstants.statusInfoText,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Quick Cash Money Presets
        Row(
          children: [
            _quickCashPresetBtn(widget.order.totalAmount, 'Uang Pas'),
            const SizedBox(width: 8),
            _quickCashPresetBtn(10000, '10k'),
            const SizedBox(width: 8),
            _quickCashPresetBtn(20000, '20k'),
            const SizedBox(width: 8),
            _quickCashPresetBtn(50000, '50k'),
            const SizedBox(width: 8),
            _quickCashPresetBtn(100000, '100k'),
          ],
        ),
        const SizedBox(height: 14),

        // Numpad Grid
        Expanded(
          child: GridView.count(
            crossAxisCount: 3,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 2.9,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (var i = 1; i <= 9; i++) _padBtn(i.toString()),
              _padBtn('C', color: StyleConstants.statusDangerBg, textColor: StyleConstants.dangerColor),
              _padBtn('0'),
              _padIconBtn(Icons.backspace_rounded, 'back'),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Confirm Action Button
        ElevatedButton(
          onPressed: (isButtonEnabled && !_isProcessing) ? _processPayment : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: isLunasMode ? StyleConstants.successColor : StyleConstants.warningColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            elevation: 0,
          ),
          child: _isProcessing
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(
                  isLunasMode ? 'KONFIRMASI PEMBAYARAN LUNAS (SELESAI)' : 'KONFIRMASI PEMBAYARAN DP (CICILAN)',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5, letterSpacing: 0.4),
                ),
        ),
      ],
    );
  }

  Widget _quickCashPresetBtn(int amount, String label) {
    return Expanded(
      child: OutlinedButton(
        onPressed: () => _setQuickCash(amount),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: StyleConstants.borderLight),
          padding: const EdgeInsets.symmetric(vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text(label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: StyleConstants.textBody)),
      ),
    );
  }

  Widget _padBtn(String val, {Color? color, Color? textColor}) {
    return Container(
      decoration: BoxDecoration(
        color: color ?? const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: StyleConstants.borderLight),
      ),
      child: InkWell(
        onTap: () => _onKeyPress(val),
        borderRadius: BorderRadius.circular(10),
        child: Center(
          child: Text(
            val,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: textColor ?? StyleConstants.textHeading,
            ),
          ),
        ),
      ),
    );
  }

  Widget _padIconBtn(IconData icon, String action) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: StyleConstants.borderLight),
      ),
      child: InkWell(
        onTap: () => _onKeyPress(action),
        borderRadius: BorderRadius.circular(10),
        child: Center(
          child: Icon(icon, size: 20, color: StyleConstants.textBody),
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
