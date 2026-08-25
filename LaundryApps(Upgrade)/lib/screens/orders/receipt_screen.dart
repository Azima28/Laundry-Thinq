import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../database/models/order_model.dart';
import '../../database/models/database_helper.dart';
import '../../transactions/transaction_repository.dart';
import '../../services/printer_service.dart';
import '../../services/machine_status_service.dart';
import '../../utils/currency_format.dart';
import '../../utils/style_constants.dart';
import '../../utils/globals.dart';

class ReceiptScreen extends StatefulWidget {
  final Order order;
  final bool isPaid;
  final String paymentMethod;
  final int paidAmount;

  const ReceiptScreen({
    super.key,
    required this.order,
    this.isPaid = false,
    this.paymentMethod = 'cash',
    this.paidAmount = 0,
  });

  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  bool _isPrinting = false;
  bool _isSendingWa = false;
  int _maxDuration = 0;
  final TransactionRepository _transRepo = TransactionRepository();

  String _bizName = 'SMART LAUNDRY PRO';
  String _bizAddress = 'Layanan Cuci & Setrika Profesional';
  String _bizPhone = '';
  String _customerKuponStr = '';
  TextEditingController _phoneCtrl = TextEditingController();
  List<Map<String, dynamic>> _orderUsages = [];

  @override
  void initState() {
    super.initState();
    _phoneCtrl = TextEditingController(
      text: widget.order.customerPhone ?? '',
    );
    _loadBizProfile();
    _calculateDuration();
    _loadOrderUsages();

    // Auto-print receipt directly upon opening screen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _printReceipt();
    });
  }

  Future<void> _loadOrderUsages() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final usages = await db.query(
        'machine_usage_history',
        where: 'order_id = ?',
        whereArgs: [widget.order.id],
        orderBy: 'started_at ASC',
      );
      if (mounted) {
        setState(() {
          _orderUsages = usages;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadBizProfile() async {
    final prefs = await SharedPreferences.getInstance();
    String kuponStr = '';
    try {
      final stats = await DatabaseHelper.instance.getCustomerFullStats(
        name: widget.order.customerName,
        phone: widget.order.customerPhone,
      );
      if (stats['loyalty_enabled'] == true && widget.order.customerName.isNotEmpty) {
        final activeKupon = stats['wash_count_active'] ?? 0;
        final threshold = stats['loyalty_threshold'] ?? 5;
        kuponStr = '$activeKupon / $threshold';
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _bizName = prefs.getString('biz_name') ?? 'SMART LAUNDRY PRO';
        _bizAddress = prefs.getString('biz_address') ?? 'Layanan Cuci & Setrika Profesional';
        _bizPhone = prefs.getString('biz_phone') ?? '';
        _customerKuponStr = kuponStr;
      });
    }
  }

  Future<void> _calculateDuration() async {
    int maxDays = 0;
    for (var item in widget.order.items) {
      final trans = await _transRepo.getTransaction(item.itemId);
      if (trans != null && trans.durationDays != null) {
        if (trans.durationDays! > maxDays) {
          maxDays = trans.durationDays!;
        }
      }
    }
    if (mounted) {
      setState(() {
        _maxDuration = maxDays;
      });
    }
  }

  Future<void> _printReceipt() async {
    if (_isPrinting) return;
    setState(() => _isPrinting = true);
    try {
      final success = await PrinterService.printOrder(widget.order);
      if (mounted) {
        if (success) {
          Globals.showSuccessSnackBar('Nota #${widget.order.id} berhasil dicetak ke printer kasir.');
        } else {
          Globals.showErrorSnackBar('Printer tidak merespons. Periksa sambungan printer kasir.');
        }
      }
    } catch (e) {
      if (mounted) {
        Globals.showErrorSnackBar('Error cetak: $e');
      }
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  Future<void> _sendWhatsAppReceipt() async {
    final targetPhone = _phoneCtrl.text.trim();
    if (targetPhone.isEmpty) {
      Globals.showErrorSnackBar('Nomor WhatsApp pelanggan belum dimasukkan.');
      return;
    }

    setState(() => _isSendingWa = true);
    try {
      final String phone = targetPhone;
      final String name = widget.order.customerName;
      final orderId = widget.order.id;
      final d = widget.order.orderDate;
      final dateStr = '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

      String statusBayar = 'BELUM LUNAS';
      if (widget.order.isPaid || widget.paidAmount >= widget.order.totalAmount) {
        statusBayar = 'LUNAS';
      } else if (widget.paidAmount > 0) {
        statusBayar = 'BELUM LUNAS (Telah Dibayar DP: ${formatRp(widget.paidAmount)})';
      }

      final buffer = StringBuffer();
      buffer.writeln("=========================");
      buffer.writeln("   *$_bizName*");
      buffer.writeln("=========================");
      buffer.writeln("Halo Kak *$name*, berikut adalah rincian pesanan cuci Kakak:\n");
      buffer.writeln("*Nota #$orderId* - _($dateStr)_");
      buffer.writeln("---------------------------------");
      buffer.writeln("*DETAIL LAYANAN:*");

      for (var item in widget.order.items) {
        if (item.price == 0) {
          buffer.writeln("- *${item.itemName}* -> *Rp 0 (Gratis)*");
        } else if (item.quantity == 1) {
          buffer.writeln("- *${item.itemName}* -> *${formatRp(item.price)}*");
        } else {
          buffer.writeln("- *${item.itemName}* -> *${item.quantity} x ${formatRp(item.price)}* = *${formatRp(item.price * item.quantity)}*");
        }
        if (item.note != null && item.note!.trim().isNotEmpty) {
          buffer.writeln("  _Catatan: ${item.note!.trim()}_");
        }
      }

      buffer.writeln("---------------------------------");
      buffer.writeln("*TOTAL TAGIHAN:* *${formatRp(widget.order.totalAmount)}*");
      buffer.writeln("*STATUS PEMBAYARAN:* *$statusBayar*");
      if (_customerKuponStr.isNotEmpty) {
        buffer.writeln("---------------------------------");
        buffer.writeln("*Kupon Cuci:* *$_customerKuponStr*");
      }
      buffer.writeln("---------------------------------");
      buffer.writeln("*INFORMASI:* Kakak akan menerima pesan WhatsApp otomatis ketika proses pencucian dimulai dan setelah selesai/siap diambil.");
      buffer.writeln("=========================");
      buffer.writeln("Terima kasih telah mempercayakan pakaian Kakak kepada kami.");

      final res = await MachineStatusService.instance.sendCustomWa(
        phone: phone,
        message: buffer.toString(),
      );

      if (mounted) {
        if (res['success'] == true) {
          Globals.showSuccessSnackBar('Nota digital berhasil dikirimkan ke WhatsApp $targetPhone!');
        } else {
          Globals.showErrorSnackBar('Gagal kirim WhatsApp: ${res['error'] ?? 'Service error'}');
        }
      }
    } catch (e) {
      if (mounted) {
        Globals.showErrorSnackBar('Error kirim WA: $e');
      }
    } finally {
      if (mounted) setState(() => _isSendingWa = false);
    }
  }

  void _finishAndReturn() {
    Navigator.of(context).pushNamedAndRemoveUntil('/dashboard', (route) => false);
  }

  void _newOrder() {
    Navigator.of(context).pushReplacementNamed('/pesan');
  }

  @override
  Widget build(BuildContext context) {
    final sisaTagihan = (widget.order.totalAmount - widget.paidAmount).clamp(0, widget.order.totalAmount);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): _printReceipt,
        const SingleActivator(LogicalKeyboardKey.keyW, control: true): _sendWhatsAppReceipt,
        const SingleActivator(LogicalKeyboardKey.f1): _newOrder,
        const SingleActivator(LogicalKeyboardKey.escape): _finishAndReturn,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: StyleConstants.backgroundColor,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Top Universal Status & Command Bar
              _buildTopBar(),

              // 2. Main 2-Pane Workstation (Left: Realistic Receipt Canvas, Right: POS Action Hub)
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Left Pane: Realistic Thermal Receipt Paper Canvas (44%)
                    Expanded(
                      flex: 44,
                      child: Container(
                        color: const Color(0xFFF1F5F9),
                        child: Center(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                            child: _buildRealisticReceiptPaper(sisaTagihan),
                          ),
                        ),
                      ),
                    ),

                    // Vertical Sleek Border
                    Container(width: 1.5, color: StyleConstants.borderLight),

                    // Right Pane: Action & Distribution Studio (56%)
                    Expanded(
                      flex: 56,
                      child: Container(
                        color: Colors.white,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(32, 24, 32, 24),
                          child: _buildActionStudio(sisaTagihan),
                        ),
                      ),
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

  // ==========================================
  // 1. TOP COMMAND BAR
  // ==========================================
  Widget _buildTopBar() {
    return Container(
      height: StyleConstants.topBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: StyleConstants.borderLight)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: StyleConstants.statusSuccessBg,
              shape: BoxShape.circle,
              border: Border.all(color: StyleConstants.successColor.withValues(alpha: 0.3)),
            ),
            child: const Icon(Icons.check_circle_rounded, color: StyleConstants.successColor, size: 20),
          ),
          const SizedBox(width: 12),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'Pesanan Tercatat: ',
                    style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: StyleConstants.textHeading),
                  ),
                  Text(
                    '#TRX-${widget.order.id}',
                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w900, color: StyleConstants.primaryColor),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: widget.isPaid ? StyleConstants.statusSuccessBg : StyleConstants.statusWarningBg,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      widget.isPaid ? 'LUNAS' : 'CICILAN',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        color: widget.isPaid ? StyleConstants.statusSuccessText : StyleConstants.statusWarningText,
                      ),
                    ),
                  ),
                ],
              ),
              Text(
                'Pelanggan: ${widget.order.customerName} • ${DateFormat('dd MMM yyyy, HH:mm').format(widget.order.orderDate)}',
                style: const TextStyle(fontSize: 11.5, color: StyleConstants.textMuted, fontWeight: FontWeight.w500),
              ),
            ],
          ),
          const Spacer(),

          // Shortcut Badges Help
          Row(
            children: [
              _buildShortcutPill('Enter', 'Cetak'),
              const SizedBox(width: 6),
              _buildShortcutPill('Ctrl+W', 'Kirim WA'),
              const SizedBox(width: 6),
              _buildShortcutPill('F1', 'Order Baru'),
              const SizedBox(width: 6),
              _buildShortcutPill('Esc', 'Selesai'),
            ],
          ),
          const SizedBox(width: 16),

          ElevatedButton.icon(
            onPressed: _finishAndReturn,
            icon: const Icon(Icons.check_rounded, size: 16),
            label: const Text('Selesai / Beranda', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
            style: ElevatedButton.styleFrom(
              backgroundColor: StyleConstants.sidebarBackground,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShortcutPill(String key, String action) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: StyleConstants.borderLight),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: StyleConstants.borderMedium),
            ),
            child: Text(
              key,
              style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: StyleConstants.textHeading),
            ),
          ),
          const SizedBox(width: 5),
          Text(action, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: StyleConstants.textMuted)),
        ],
      ),
    );
  }

  // ==========================================
  // 2. REALISTIC THERMAL RECEIPT CANVAS
  // ==========================================
  Widget _buildRealisticReceiptPaper(int sisaTagihan) {
    return Container(
      width: 440,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFCBD5E1), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Decorative Thermal Roll Accent Bar
          Container(
            height: 6,
            decoration: const BoxDecoration(
              color: StyleConstants.primaryColor,
              borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Store Header Branding
                Center(
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: StyleConstants.primaryColor.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.local_laundry_service_rounded, size: 28, color: StyleConstants.primaryColor),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _bizName.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: StyleConstants.textHeading,
                          letterSpacing: 1.0,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _bizAddress,
                        style: const TextStyle(fontSize: 11.5, color: StyleConstants.textMuted, fontWeight: FontWeight.w500),
                        textAlign: TextAlign.center,
                      ),
                      if (_bizPhone.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Telp / WA: $_bizPhone',
                          style: const TextStyle(fontSize: 11.5, color: StyleConstants.textMuted, fontWeight: FontWeight.w600),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'NOTA RESMI PEMBAYARAN KASIR',
                          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: StyleConstants.textBody),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(height: 1, color: Color(0xFFE2E8F0), thickness: 1.2),
                const SizedBox(height: 12),

                // Transaction Metadata Grid
                _buildReceiptRow('Nomor Nota', '#TRX-${widget.order.id}', isBold: true, valueColor: StyleConstants.primaryColor),
                _buildReceiptRow('Tanggal & Waktu', DateFormat('dd/MM/yyyy  HH:mm').format(widget.order.orderDate)),
                _buildReceiptRow('Nama Pelanggan', widget.order.customerName, isBold: true),
                _buildReceiptRow(
                  'No. WhatsApp',
                  widget.order.customerPhone?.isNotEmpty == true ? widget.order.customerPhone! : 'Belum Ada No. WA',
                ),
                _buildReceiptRow('Metode Pembayaran', widget.paymentMethod.toUpperCase()),
                if (_maxDuration > 0)
                  _buildReceiptRow('Estimasi Selesai', '$_maxDuration Hari Kerja'),
                if (_orderUsages.isNotEmpty) ...[
                  if (_orderUsages.length == 1) ...[
                    _buildReceiptRow(
                      'Mesin Digunakan',
                      '${_orderUsages.first['machine_name']} (${DateFormat('HH:mm').format(DateTime.parse(_orderUsages.first['started_at'] as String).toLocal())})',
                      isBold: true,
                    ),
                  ] else ...[
                    _buildReceiptRow('Alokasi Mesin', '${_orderUsages.length} Siklus Terdata', isBold: true),
                    for (int i = 0; i < _orderUsages.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(left: 6, bottom: 2),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '• Siklus #${i + 1}: ${_orderUsages[i]['machine_name']}',
                              style: const TextStyle(fontSize: 11, color: StyleConstants.textMuted),
                            ),
                            Text(
                              DateFormat('HH:mm').format(DateTime.parse(_orderUsages[i]['started_at'] as String).toLocal()),
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                  ],
                ],

                const SizedBox(height: 12),
                const Divider(height: 1, color: Color(0xFFE2E8F0), thickness: 1.2),
                const SizedBox(height: 12),

                // Itemized Table Header
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: const Row(
                    children: [
                      Expanded(
                        flex: 6,
                        child: Text(
                          'RINCIAN LAYANAN',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: StyleConstants.textMuted, letterSpacing: 0.5),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          'QTY',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: StyleConstants.textMuted),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          'TOTAL',
                          textAlign: TextAlign.right,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: StyleConstants.textMuted),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),

                // Itemized Rows
                ...widget.order.items.map((item) {
                  final bool isGratis = item.price == 0;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 6,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      item.itemName,
                                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: StyleConstants.textHeading),
                                    ),
                                  ),
                                  if (isGratis) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFEF3C7),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: const Color(0xFFFDE68A)),
                                      ),
                                      child: const Text(
                                        'Gratis',
                                        style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Color(0xFFB45309)),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              Text(
                                isGratis ? '@ Rp 0 (Gratis)' : '@ ${formatRp(item.price)}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isGratis ? const Color(0xFFD97706) : StyleConstants.textMuted,
                                  fontWeight: isGratis ? FontWeight.w700 : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            '${item.quantity}x',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: StyleConstants.textBody),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            isGratis ? 'Rp 0' : formatRp(item.price * item.quantity),
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                              color: isGratis ? const Color(0xFFD97706) : StyleConstants.textHeading,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),

                const SizedBox(height: 12),
                const Divider(height: 1, color: Color(0xFFCBD5E1), thickness: 1.5),
                const SizedBox(height: 12),

                // Grand Totals & Payment Breakdown
                _buildReceiptRow(
                  'Total Tagihan (Grand Total)',
                  formatRp(widget.order.totalAmount),
                  isBold: true,
                  fontSize: 14,
                  valueColor: StyleConstants.textHeading,
                ),
                const SizedBox(height: 4),
                _buildReceiptRow(
                  'Telah Dibayar (Kasir)',
                  formatRp(widget.paidAmount),
                  isBold: true,
                  fontSize: 13,
                  valueColor: StyleConstants.successColor,
                ),

                if (sisaTagihan > 0) ...[
                  const SizedBox(height: 4),
                  _buildReceiptRow(
                    'Sisa Tagihan (Piutang)',
                    formatRp(sisaTagihan),
                    isBold: true,
                    fontSize: 13,
                    valueColor: StyleConstants.dangerColor,
                  ),
                ],

                if (_customerKuponStr.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.card_giftcard_rounded, size: 16, color: Color(0xFFD97706)),
                            SizedBox(width: 6),
                            Text(
                              'Kupon Cuci',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF92400E)),
                            ),
                          ],
                        ),
                        Text(
                          _customerKuponStr,
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900, color: Color(0xFFB45309)),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 14),

                // Payment Status Badge Box
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                  decoration: BoxDecoration(
                    color: widget.isPaid ? StyleConstants.statusSuccessBg : StyleConstants.statusWarningBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: widget.isPaid
                          ? StyleConstants.successColor.withValues(alpha: 0.3)
                          : StyleConstants.warningColor.withValues(alpha: 0.3),
                      width: 1.2,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        widget.isPaid ? Icons.check_circle_rounded : Icons.pending_actions_rounded,
                        size: 18,
                        color: widget.isPaid ? StyleConstants.statusSuccessText : StyleConstants.statusWarningText,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        widget.isPaid ? 'LUNAS / TERBAYAR LENGKAP' : 'BELUM LUNAS (SISA ${formatRp(sisaTagihan)})',
                        style: TextStyle(
                          color: widget.isPaid ? StyleConstants.statusSuccessText : StyleConstants.statusWarningText,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                // Footer Notes
                const Center(
                  child: Column(
                    children: [
                      Text(
                        'Simpan nota ini sebagai bukti sah pengambilan pakaian.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11, color: StyleConstants.textMuted, fontWeight: FontWeight.w600),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Terima kasih telah mempercayakan cucian Anda kepada kami!',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11, color: StyleConstants.textMuted, height: 1.3),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReceiptRow(
    String label,
    String value, {
    Color? valueColor,
    bool isBold = false,
    double fontSize = 12.5,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: fontSize,
              color: StyleConstants.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: isBold ? FontWeight.w900 : FontWeight.w700,
              color: valueColor ?? StyleConstants.textHeading,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // 3. RIGHT ACTION & DISTRIBUTION STUDIO
  // ==========================================
  Widget _buildActionStudio(int sisaTagihan) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Title & Description
        const Text(
          'Pusat Aksi & Distribusi Struk',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: StyleConstants.textHeading,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Cetak bukti fisik thermal untuk pelanggan atau kirimkan salinan nota digital langsung ke WhatsApp.',
          style: TextStyle(fontSize: 13, color: StyleConstants.textMuted),
        ),
        const SizedBox(height: 20),

        // Action Card 1: Thermal Printer Studio
        _buildThermalPrinterCard(),
        const SizedBox(height: 16),

        // Action Card 2: WhatsApp Dispatch Studio
        _buildWhatsAppDispatchCard(),
        const SizedBox(height: 20),

        // Action Card 3: Post-Transaction Navigation Shortcuts
        _buildQuickWorkflowCard(),
        const SizedBox(height: 24),

        // Finish Big Action Bar
        ElevatedButton.icon(
          onPressed: _finishAndReturn,
          icon: const Icon(Icons.check_circle_outline_rounded, size: 20),
          label: const Text(
            'SELESAI & KEMBALI KE BERANDA (ESC)',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 0.6),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: StyleConstants.sidebarBackground,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 0,
          ),
        ),
      ],
    );
  }

  // --- CARD 1: THERMAL PRINTER ---
  Widget _buildThermalPrinterCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: StyleConstants.borderLight),
        boxShadow: [
          BoxShadow(
            color: StyleConstants.primaryColor.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: StyleConstants.primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.print_rounded, color: StyleConstants.primaryColor, size: 26),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cetak Struk Kasir (Printer Thermal / Dot Matrix)',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: StyleConstants.textHeading),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Mendukung Epson TM-U220D (76mm), POS-58, POS-80 via USB Cable & Bluetooth.',
                      style: TextStyle(fontSize: 12, color: StyleConstants.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _isPrinting ? null : _printReceipt,
            icon: _isPrinting
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                : const Icon(Icons.print_rounded, size: 18),
            label: Text(
              _isPrinting ? 'Mencetak Nota ke Printer...' : 'CETAK NOTA SEKARANG (ENTER)',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5, letterSpacing: 0.4),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: StyleConstants.primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 2,
            ),
          ),
        ],
      ),
    );
  }

  // --- CARD 2: WHATSAPP DISPATCH ---
  Widget _buildWhatsAppDispatchCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: StyleConstants.borderLight),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF10B981).withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.chat_rounded, color: Color(0xFF10B981), size: 26),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Kirim Nota Digital ke WhatsApp Pelanggan',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: StyleConstants.textHeading),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Kirim salinan rincian nota & total tagihan otomatis melalui WhatsApp Gateway.',
                      style: TextStyle(fontSize: 12, color: StyleConstants.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Phone Number Field
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  decoration: InputDecoration(
                    labelText: 'Nomor WhatsApp Pelanggan',
                    hintText: 'Contoh: 08123456789 atau +628123456789',
                    prefixIcon: const Icon(Icons.phone_rounded, size: 18, color: Color(0xFF10B981)),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _isSendingWa ? null : _sendWhatsAppReceipt,
                icon: _isSendingWa
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_rounded, size: 17),
                label: Text(
                  _isSendingWa ? 'Mengirim...' : 'KIRIM WA (CTRL+W)',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- CARD 3: QUICK WORKFLOW ACCELERATOR ---
  Widget _buildQuickWorkflowCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: StyleConstants.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.bolt_rounded, size: 18, color: Color(0xFFF59E0B)),
              SizedBox(width: 6),
              Text(
                'Aksi Cepat Kasir Selanjutnya:',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: StyleConstants.textHeading),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildWorkflowButton(
                  title: 'Order Baru (F1)',
                  subtitle: 'Buat pesanan lain',
                  icon: Icons.add_shopping_cart_rounded,
                  color: StyleConstants.primaryColor,
                  onTap: _newOrder,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildWorkflowButton(
                  title: 'Mesin Cuci',
                  subtitle: 'Nyalakan mesin',
                  icon: Icons.local_laundry_service_rounded,
                  color: const Color(0xFF0D9488),
                  onTap: () {
                    Navigator.of(context).pushNamedAndRemoveUntil('/dashboard', (r) => false);
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildWorkflowButton(
                  title: 'Lihat Riwayat',
                  subtitle: 'Buku besar & nota',
                  icon: Icons.receipt_long_rounded,
                  color: StyleConstants.secondaryColor,
                  onTap: () {
                    Navigator.of(context).pushNamedAndRemoveUntil('/dashboard', (r) => false);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWorkflowButton({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: StyleConstants.borderLight),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 16),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: StyleConstants.textHeading),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 10.5, color: StyleConstants.textMuted),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
