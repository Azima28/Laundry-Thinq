import 'dart:async';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../database/models/payment_model.dart';
import '../../database/models/order_model.dart';
import '../../database/models/database_helper.dart';
import '../../services/midtrans_service.dart';
import '../../utils/currency_format.dart';

class PaymentScreen extends StatefulWidget {
  final Order order;

  const PaymentScreen({
    Key? key,
    required this.order,
  }) : super(key: key);

  @override
  _PaymentScreenState createState() => _PaymentScreenState();
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
  String? _lastResponse;
  String? _lastError;

  String _midtransServerKey = '';
  String _paymentProvider = 'midtrans';

  final Color primaryColor = const Color(0xFF4E80EE);
  final Color backgroundColor = const Color(0xFFF8FAFC);

  @override
  void initState() {
    super.initState();
    _loadPaymentCredentials();
    _cashController.addListener(() {
      final text = _cashController.text.replaceAll('.', '');
      final parsed = int.tryParse(text) ?? 0;
      setState(() {
        _cashReceived = parsed;
      });
    });
  }

  Future<void> _loadPaymentCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _paymentProvider = prefs.getString('payment_provider') ?? 'midtrans';
        _midtransServerKey = prefs.getString('midtrans_server_key') ?? '';
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _statusCheckTimer?.cancel();
    _cashController.dispose();
    super.dispose();
  }

  void _onKeyPress(String val) {
    String currentText = _cashController.text.replaceAll('.', '');
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('⚠️ Uang tunai yang diterima kurang dari total tagihan!'), backgroundColor: Colors.orange),
          );
          return;
        }
        await _completePayment(true);
        return;
      } else if (_paymentStatus == 'dp') {
        if (_cashReceived <= 0 || _cashReceived >= widget.order.totalAmount) {
          setState(() => _isProcessing = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('⚠️ Jumlah DP harus lebih besar dari 0 dan kurang dari total tagihan!'), backgroundColor: Colors.orange),
          );
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

      _lastResponse = response.toString();

      if (response['success'] != true) {
        final message = response['message'] ?? 'Gagal membuat QRIS';
        setState(() {
          _lastError = message.toString();
          _isProcessing = false;
        });
        return;
      }

      final qrisData = response['qris_url'] ?? response['qr_code_url'];

      if (qrisData == null || qrisData.toString().isEmpty) {
        setState(() {
          _lastError = 'QR code URL tidak ditemukan dalam response';
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
    _statusCheckTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      await _checkStatus(orderId);
    });
  }

  Future<void> _checkStatus(String orderId) async {
    try {
      final status = await MidtransService.checkTransactionStatus(
        orderId,
        overrideServerKey: _midtransServerKey,
      );

      setState(() {
        _lastResponse = status.toString();
        _lastStatus = status['transaction_status']?.toString();
      });

      if (_lastStatus == 'settlement' || _lastStatus == 'capture') {
        _statusCheckTimer?.cancel();
        _completePayment(true);
      } else if (_lastStatus == 'deny' || _lastStatus == 'cancel' || _lastStatus == 'expire') {
        _statusCheckTimer?.cancel();
        setState(() {
          _lastError = 'Pembayaran gagal: $_lastStatus';
          _isProcessing = false;
        });
      }
    } catch (e) {
      setState(() {
        _lastError = e.toString();
      });
    }
  }

  Future<void> _completePayment(bool success) async {
    _statusCheckTimer?.cancel();
    if (_paymentCompleted) return;
    _paymentCompleted = true;

    if (!success) {
      setState(() => _isProcessing = false);
      Navigator.of(context).pop(false);
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
      setState(() => _isProcessing = false);
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final change = _cashReceived - widget.order.totalAmount;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text('Pembayaran POS', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left Panel: Payment details & Method selector (45% width)
          Expanded(
            flex: 4,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Receipt Info Card
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Ringkasan Tagihan',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                        ),
                        const SizedBox(height: 16),
                        const Divider(height: 1),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Nama Pelanggan:', style: TextStyle(fontSize: 13, color: Colors.grey)),
                            Text(widget.order.customerName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Total Tagihan:', style: TextStyle(fontSize: 14, color: Colors.grey)),
                            Text(
                              formatRp(widget.order.totalAmount),
                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: primaryColor),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),

                  const Text(
                    'Pilih Status Pembayaran',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                  ),
                  const SizedBox(height: 12),

                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Column(
                      children: [
                        RadioListTile<String>(
                          title: const Row(
                            children: [
                              Icon(Icons.check_circle_rounded, color: Colors.green),
                              SizedBox(width: 12),
                              Text('Lunas', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            ],
                          ),
                          value: 'lunas',
                          groupValue: _paymentStatus,
                          onChanged: _isProcessing ? null : (val) {
                            setState(() {
                              _paymentStatus = val!;
                            });
                          },
                        ),
                        const Divider(height: 1),
                        RadioListTile<String>(
                          title: const Row(
                            children: [
                              Icon(Icons.payment_rounded, color: Colors.orange),
                              SizedBox(width: 12),
                              Text('Bayar Setengah / DP (Cicilan)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            ],
                          ),
                          value: 'dp',
                          groupValue: _paymentStatus,
                          onChanged: _isProcessing ? null : (val) {
                            setState(() {
                              _paymentStatus = val!;
                              _cashController.clear();
                            });
                          },
                        ),
                        const Divider(height: 1),
                        RadioListTile<String>(
                          title: const Row(
                            children: [
                              Icon(Icons.pending_actions_rounded, color: Colors.red),
                              SizedBox(width: 12),
                              Text('Belum Bayar (Piutang / Tempo)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            ],
                          ),
                          value: 'piutang',
                          groupValue: _paymentStatus,
                          onChanged: _isProcessing ? null : (val) {
                            setState(() {
                              _paymentStatus = val!;
                              _cashController.text = '0';
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  if (_paymentStatus != 'piutang') ...[
                    const Text(
                      'Pilih Metode Pembayaran',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: Column(
                        children: [
                          RadioListTile<String>(
                            title: const Row(
                              children: [
                                Icon(Icons.payments_rounded, color: Colors.green),
                                SizedBox(width: 12),
                                Text('Tunai / Cash', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              ],
                            ),
                            value: 'cash',
                            groupValue: _paymentMethod,
                            onChanged: _isProcessing ? null : (val) {
                              setState(() {
                                _paymentMethod = val!;
                              });
                            },
                          ),
                          const Divider(height: 1),
                          RadioListTile<String>(
                            title: const Row(
                              children: [
                                Icon(Icons.qr_code_scanner_rounded, color: Colors.blue),
                                SizedBox(width: 12),
                                Text('Scan QRIS Midtrans', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              ],
                            ),
                            value: 'qris',
                            groupValue: _paymentMethod,
                            onChanged: _isProcessing ? null : (val) {
                              setState(() {
                                _paymentMethod = val!;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Vertical divider
          Container(width: 1, color: Colors.grey[200]),

          // Right Panel: Dynamic Method Pane (55% width)
          Expanded(
            flex: 5,
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.all(28.0),
              child: (_paymentStatus == 'piutang')
                  ? _buildUnpaidPane()
                  : (_paymentMethod == 'cash')
                      ? _buildCashPane(change)
                      : _buildQrisPane(),
            ),
          ),
        ],
      ),
    );
  }

  // --- CASH PAYMENT PANE (POS STYLE) ---
  Widget _buildCashPane(int change) {
    final isLunasMode = _paymentStatus == 'lunas';
    final isButtonEnabled = isLunasMode 
        ? _cashReceived >= widget.order.totalAmount 
        : (_cashReceived > 0 && _cashReceived < widget.order.totalAmount);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          isLunasMode ? 'Input Pembayaran Tunai (Lunas)' : 'Input Pembayaran Tunai (DP / Setengah)',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
        ),
        const SizedBox(height: 20),

        // Cash Input Field Display (Real TextField for physical keyboard input)
        TextFormField(
          controller: _cashController,
          keyboardType: TextInputType.number,
          autofocus: true,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
          decoration: InputDecoration(
            prefixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Padding(
                  padding: EdgeInsets.only(left: 20, right: 12),
                  child: Text(
                    'Rp',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                  ),
                ),
              ],
            ),
            prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
            filled: true,
            fillColor: Colors.grey[50],
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.grey[200]!),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.grey[200]!),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFF4E80EE), width: 2),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Return Change Output Display (Only relevant for lunas mode, or shows remaining target for DP)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isLunasMode
                ? (change >= 0 ? const Color(0xFFDCFCE7) : Colors.orange.withOpacity(0.08))
                : const Color(0xFFEFF6FF), // Light blue for DP info
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isLunasMode
                  ? (change >= 0 ? const Color(0xFFBBF7D0) : Colors.orange.withOpacity(0.2))
                  : const Color(0xFFBFDBFE),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isLunasMode 
                    ? (change >= 0 ? 'Kembalian:' : 'Uang Kurang:')
                    : 'Sisa Pembayaran (Piutang):',
                style: TextStyle(
                  fontWeight: FontWeight.bold, 
                  color: isLunasMode 
                      ? (change >= 0 ? const Color(0xFF15803D) : Colors.orange[800])
                      : const Color(0xFF1E40AF),
                ),
              ),
              Text(
                isLunasMode 
                    ? formatRp(change.abs())
                    : formatRp((widget.order.totalAmount - _cashReceived).clamp(0, widget.order.totalAmount)),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isLunasMode 
                      ? (change >= 0 ? const Color(0xFF15803D) : Colors.orange[800])
                      : const Color(0xFF1E40AF),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Quick cash choices
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _quickCashBtn(widget.order.totalAmount, 'Uang Pas'),
            const SizedBox(width: 8),
            _quickCashBtn(10000, '10k'),
            const SizedBox(width: 8),
            _quickCashBtn(20000, '20k'),
            const SizedBox(width: 8),
            _quickCashBtn(50000, '50k'),
            const SizedBox(width: 8),
            _quickCashBtn(100000, '100k'),
          ],
        ),
        const SizedBox(height: 16),

        // Numeric Keypad Grid (With childAspectRatio increased to 2.8 so row 4 fits)
        Expanded(
          child: GridView.count(
            crossAxisCount: 3,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 2.8,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (var i = 1; i <= 9; i++) _padBtn(i.toString()),
              _padBtn('C', color: Colors.redAccent.withOpacity(0.1), textColor: Colors.redAccent),
              _padBtn('0'),
              _padIconBtn(Icons.backspace_rounded, 'back', color: Colors.grey[100]!),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Checkout Trigger
        ElevatedButton(
          onPressed: (isButtonEnabled && !_isProcessing) ? _processPayment : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: isLunasMode ? Colors.green : Colors.orange,
            disabledBackgroundColor: Colors.grey[200],
            padding: const EdgeInsets.symmetric(vertical: 18),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _isProcessing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                )
              : Text(
                  isLunasMode ? 'Konfirmasi Pembayaran Lunas' : 'Konfirmasi Pembayaran DP (Cicilan)',
                  style: TextStyle(
                    color: isButtonEnabled ? Colors.white : Colors.grey[500], 
                    fontWeight: FontWeight.bold, 
                    fontSize: 14,
                  ),
                ),
        ),
      ],
    );
  }

  Widget _padBtn(String val, {Color? color, Color? textColor}) {
    return Container(
      decoration: BoxDecoration(
        color: color ?? Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: InkWell(
        onTap: () => _onKeyPress(val),
        borderRadius: BorderRadius.circular(12),
        child: Center(
          child: Text(
            val,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: textColor ?? const Color(0xFF0F172A),
            ),
          ),
        ),
      ),
    );
  }

  Widget _padIconBtn(IconData icon, String action, {required Color color}) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () => _onKeyPress(action),
        borderRadius: BorderRadius.circular(12),
        child: Center(
          child: Icon(icon, size: 20, color: const Color(0xFF475569)),
        ),
      ),
    );
  }

  Widget _buildUnpaidPane() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.pending_actions_rounded, size: 80, color: Colors.redAccent),
        const SizedBox(height: 16),
        const Text(
          'Konfirmasi Pembayaran Piutang (Tempo)',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
        ),
        const SizedBox(height: 8),
        Text(
          'Pesanan atas nama "${widget.order.customerName}" akan dicatat ke database sebagai pesanan Belum Bayar (Piutang).',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: Color(0xFF64748B), height: 1.5),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.red.shade100),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total Pemasukan Tunai:',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
              ),
              Text(
                formatRp(0),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        ElevatedButton(
          onPressed: !_isProcessing ? _processPayment : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.redAccent,
            padding: const EdgeInsets.symmetric(vertical: 18),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _isProcessing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                )
              : const Text(
                  'Konfirmasi Simpan sebagai Piutang',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                ),
        ),
      ],
    );
  }

  Widget _quickCashBtn(int amount, String label) {
    return Expanded(
      child: OutlinedButton(
        onPressed: () => _setQuickCash(amount),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: Colors.grey[300]!),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
        ),
      ),
    );
  }

  // --- QRIS PAYMENT PANE ---
  Widget _buildQrisPane() {
    final isDpMode = _paymentStatus == 'dp';

    // If DP mode, and no QRIS generated yet, show the input screen first
    if (isDpMode && _qrisUrl == null) {
      final isButtonEnabled = _cashReceived > 0 && _cashReceived < widget.order.totalAmount;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Input Nominal DP untuk QRIS',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
          ),
          const SizedBox(height: 12),

          // Cash Input Field Display (Real TextField)
          TextFormField(
            controller: _cashController,
            keyboardType: TextInputType.number,
            autofocus: true,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
            decoration: InputDecoration(
              prefixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Padding(
                    padding: EdgeInsets.only(left: 20, right: 12),
                    child: Text(
                      'Rp',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                    ),
                  ),
                ],
              ),
              prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
              filled: true,
              fillColor: Colors.grey[50],
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.grey[200]!),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.grey[200]!),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xFF4E80EE), width: 2),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Info remaining debt
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFBFDBFE)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Sisa Pembayaran (Piutang):',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E40AF)),
                ),
                Text(
                  formatRp((widget.order.totalAmount - _cashReceived).clamp(0, widget.order.totalAmount)),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E40AF)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Quick choices
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _quickCashBtn(10000, '10k'),
              const SizedBox(width: 8),
              _quickCashBtn(20000, '20k'),
              const SizedBox(width: 8),
              _quickCashBtn(50000, '50k'),
              const SizedBox(width: 8),
              _quickCashBtn(100000, '100k'),
            ],
          ),
          const SizedBox(height: 12),

          // Keypad
          Expanded(
            child: GridView.count(
              crossAxisCount: 3,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              childAspectRatio: 2.8,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (var i = 1; i <= 9; i++) _padBtn(i.toString()),
                _padBtn('C', color: Colors.redAccent.withOpacity(0.1), textColor: Colors.redAccent),
                _padBtn('0'),
                _padIconBtn(Icons.backspace_rounded, 'back', color: Colors.grey[100]!),
              ],
            ),
          ),
          const SizedBox(height: 10),

          ElevatedButton(
            onPressed: isButtonEnabled && !_isProcessing ? _processPayment : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _isProcessing
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text('Buat Barcode QRIS DP: ${formatRp(_cashReceived)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      );
    }

    // Otherwise, normal QRIS pane (Lunas mode or QRIS already generated)
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (_qrisUrl == null) ...[
          const Icon(Icons.qr_code_2_rounded, size: 80, color: Colors.grey),
          const SizedBox(height: 16),
          const Text(
            'QRIS Midtrans Integration',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
          ),
          const SizedBox(height: 8),
          Text(
            'Klik tombol di bawah untuk membuat barcode QRIS Lunas sebesar ${formatRp(widget.order.totalAmount)} via API Midtrans.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Colors.grey, height: 1.4),
          ),
          const Spacer(),
          ElevatedButton(
            onPressed: _isProcessing ? null : _processPayment,
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _isProcessing
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Buat Barcode QRIS Lunas', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ] else ...[
          const Text(
            'Scan Barcode QRIS',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
          ),
          const SizedBox(height: 10),
          Text(
            isDpMode 
                ? 'Nominal DP: ${formatRp(_cashReceived)}'
                : 'Nominal Lunas: ${formatRp(widget.order.totalAmount)}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
          ),
          const SizedBox(height: 16),
          Center(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey[200]!),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 15)],
              ),
              child: QrImageView(
                data: _qrisUrl!,
                version: QrVersions.auto,
                size: 200.0,
                backgroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 10),
              Text(
                'Menunggu Pembayaran (${_lastStatus ?? "pending"})...',
                style: const TextStyle(fontSize: 13, color: Colors.orange, fontWeight: FontWeight.bold),
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
                  label: const Text('Cek Status'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
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
                  icon: const Icon(Icons.cancel_rounded, size: 16, color: Colors.white),
                  label: const Text('Batalkan', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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