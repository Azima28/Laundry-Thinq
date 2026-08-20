import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../database/models/order_model.dart';
import '../../transactions/transaction_repository.dart';
import '../../services/printer_service.dart';
import '../../services/machine_status_service.dart';
import '../../utils/currency_format.dart';
import '../../utils/style_constants.dart';

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

  @override
  void initState() {
    super.initState();
    _calculateDuration();
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
    setState(() => _isPrinting = true);
    try {
      final success = await PrinterService.printOrder(widget.order);
      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Nota berhasil dikirim ke printer thermal!'),
              backgroundColor: StyleConstants.successColor,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ Printer tidak merespons. Periksa koneksi printer thermal.'),
              backgroundColor: StyleConstants.dangerColor,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error cetak: $e'), backgroundColor: StyleConstants.dangerColor),
        );
      }
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  Future<void> _sendWaAgain() async {
    if (widget.order.customerPhone == null || widget.order.customerPhone!.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Pelanggan tidak memiliki nomor WhatsApp.')),
      );
      return;
    }

    setState(() => _isSendingWa = true);
    try {
      final phone = widget.order.customerPhone!.trim();
      final msg = 'Halo Kak *${widget.order.customerName}*, ini salinan nota #${widget.order.id} sebesar ${formatRp(widget.order.totalAmount)} di Smart Laundry.';
      await MachineStatusService.instance.sendCustomWa(phone: phone, message: msg);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Pesan WhatsApp berhasil dikirim ulang!'), backgroundColor: StyleConstants.successColor),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('❌ Gagal mengirim WhatsApp.'), backgroundColor: StyleConstants.dangerColor),
        );
      }
    } finally {
      if (mounted) setState(() => _isSendingWa = false);
    }
  }

  void _finishAndReturn() {
    Navigator.of(context).pushNamedAndRemoveUntil('/dashboard', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final sisaTagihan = widget.order.totalAmount - widget.paidAmount;

    return Scaffold(
      backgroundColor: StyleConstants.backgroundColor,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Header Bar
          Container(
            height: StyleConstants.topBarHeight,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: StyleConstants.borderLight)),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: StyleConstants.successColor, size: 24),
                const SizedBox(width: 10),
                const Text(
                  'Order Berhasil Dibuat & Tercatat',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: StyleConstants.textHeading,
                  ),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: _finishAndReturn,
                  icon: const Icon(Icons.dashboard_rounded, size: 16),
                  label: const Text('Selesai / Ke Beranda', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: StyleConstants.sidebarBackground,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                ),
              ],
            ),
          ),

          // Main 2-Pane Workstation Area
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Sisi Kiri (50%): Realistic Thermal Receipt Paper Preview
                Expanded(
                  flex: 5,
                  child: Container(
                    color: const Color(0xFFF1F5F9),
                    alignment: Alignment.center,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Container(
                        width: 360,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: StyleConstants.borderLight),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF0F172A).withValues(alpha: 0.04),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Header Nota
                            const Center(
                              child: Column(
                                children: [
                                  Icon(Icons.local_laundry_service_rounded, size: 32, color: StyleConstants.primaryColor),
                                  SizedBox(height: 8),
                                  Text(
                                    'SMART LAUNDRY PRO',
                                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1.2),
                                  ),
                                  Text(
                                    'Nota Pembayaran Kasir',
                                    style: TextStyle(fontSize: 11, color: StyleConstants.textMuted),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text('------------------------------------------------', textAlign: TextAlign.center, style: TextStyle(color: StyleConstants.borderLight, fontSize: 11)),
                            const SizedBox(height: 12),

                            // Meta
                            _buildReceiptRow('No. Nota', '#TRX-${widget.order.id}', isBold: true),
                            _buildReceiptRow('Tanggal', DateFormat('dd/MM/yyyy HH:mm').format(widget.order.orderDate)),
                            _buildReceiptRow('Pelanggan', widget.order.customerName),
                            if (widget.order.customerPhone != null && widget.order.customerPhone!.isNotEmpty)
                              _buildReceiptRow('No. WhatsApp', widget.order.customerPhone!),
                            _buildReceiptRow('Metode Bayar', widget.paymentMethod.toUpperCase()),
                            if (_maxDuration > 0)
                              _buildReceiptRow('Estimasi Pengerjaan', '$_maxDuration Hari'),

                            const SizedBox(height: 12),
                            const Text('------------------------------------------------', textAlign: TextAlign.center, style: TextStyle(color: StyleConstants.borderLight, fontSize: 11)),
                            const SizedBox(height: 12),

                            // Itemized
                            const Text('RINCIAN LAYANAN:', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: StyleConstants.textMuted)),
                            const SizedBox(height: 8),
                            ...widget.order.items.map((item) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8.0),
                                child: Row(
                                  children: [
                                    Text('${item.quantity}x ', style: const TextStyle(fontWeight: FontWeight.w900, color: StyleConstants.primaryColor, fontSize: 12)),
                                    Expanded(
                                      child: Text(item.itemName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                                    ),
                                    Text(
                                      formatRp(item.price),
                                      style: StyleConstants.tabularNumbers(fontSize: 12, fontWeight: FontWeight.w700),
                                    ),
                                  ],
                                ),
                              );
                            }),

                            const SizedBox(height: 12),
                            const Text('================================================', textAlign: TextAlign.center, style: TextStyle(color: StyleConstants.borderLight, fontSize: 11)),
                            const SizedBox(height: 12),

                            // Totals
                            _buildReceiptRow('Grand Total', formatRp(widget.order.totalAmount), isBold: true, valueColor: StyleConstants.textHeading),
                            _buildReceiptRow('Telah Dibayar', formatRp(widget.paidAmount), isBold: true, valueColor: StyleConstants.successColor),

                            const SizedBox(height: 12),

                            // Status Pill
                            if (widget.isPaid)
                              Container(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: StyleConstants.statusSuccessBg,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: StyleConstants.successColor.withValues(alpha: 0.3)),
                                ),
                                child: const Center(
                                  child: Text('LUNAS / TERBAYAR', style: TextStyle(color: StyleConstants.statusSuccessText, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1)),
                                ),
                              )
                            else
                              Container(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: StyleConstants.statusWarningBg,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: StyleConstants.warningColor.withValues(alpha: 0.3)),
                                ),
                                child: Center(
                                  child: Text(
                                    'SISA PIUTANG: ${formatRp(sisaTagihan)}',
                                    style: const TextStyle(color: StyleConstants.statusWarningText, fontWeight: FontWeight.w900, fontSize: 12),
                                  ),
                                ),
                              ),

                            const SizedBox(height: 16),
                            const Text(
                              'Simpan struk ini sebagai bukti pengambilan pakaian.\nTerima kasih telah mencuci bersama kami.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 10, color: StyleConstants.textMuted, height: 1.4),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // VERTICAL DIVIDER
                Container(width: 1, color: StyleConstants.borderLight),

                // Sisi Kanan (50%): Action Hub (Print & WhatsApp)
                Expanded(
                  flex: 5,
                  child: Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Pusat Aksi & Distribusi Struk',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: StyleConstants.textHeading,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Pilih aksi cetak nota fisik atau kirim ulang nota digital ke WhatsApp pelanggan.',
                          style: TextStyle(fontSize: 13, color: StyleConstants.textMuted),
                        ),
                        const SizedBox(height: 24),

                        // Action Card 1: Thermal Print
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: StyleConstants.cardDecoration(),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: StyleConstants.primaryColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(Icons.print_rounded, color: StyleConstants.primaryColor, size: 28),
                              ),
                              const SizedBox(width: 16),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Cetak Struk Thermal (ESC/POS)',
                                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: StyleConstants.textHeading),
                                    ),
                                    SizedBox(height: 2),
                                    Text(
                                      'Cetak nota 58mm/80mm ke printer kasir aktif.',
                                      style: TextStyle(fontSize: 11.5, color: StyleConstants.textMuted),
                                    ),
                                  ],
                                ),
                              ),
                              ElevatedButton.icon(
                                onPressed: _isPrinting ? null : _printReceipt,
                                icon: _isPrinting
                                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                    : const Icon(Icons.print_rounded, size: 16),
                                label: const Text('Cetak Nota', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: StyleConstants.primaryColor,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  elevation: 0,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Action Card 2: WhatsApp Share
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: StyleConstants.cardDecoration(),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(Icons.chat_rounded, color: Color(0xFF10B981), size: 28),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Kirim Nota ke WhatsApp',
                                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: StyleConstants.textHeading),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      widget.order.customerPhone?.isNotEmpty == true
                                          ? 'Nomor: ${widget.order.customerPhone}'
                                          : 'Nomor WhatsApp belum terdaftar.',
                                      style: const TextStyle(fontSize: 11.5, color: StyleConstants.textMuted),
                                    ),
                                  ],
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed: _isSendingWa ? null : _sendWaAgain,
                                icon: _isSendingWa
                                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                    : const Icon(Icons.send_rounded, size: 16, color: Color(0xFF10B981)),
                                label: const Text('Kirim Ulang WA', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF10B981))),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Color(0xFF10B981)),
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),

                        // Bottom Finish Big Button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _finishAndReturn,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: StyleConstants.sidebarBackground,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              elevation: 0,
                            ),
                            child: const Text('KEMBALI KE DASHBOARD UTAMA', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5, letterSpacing: 0.5)),
                          ),
                        ),
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

  Widget _buildReceiptRow(String label, String value, {Color? valueColor, bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 11.5, color: StyleConstants.textMuted)),
          Text(
            value,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
              color: valueColor ?? StyleConstants.textHeading,
            ),
          ),
        ],
      ),
    );
  }
}
