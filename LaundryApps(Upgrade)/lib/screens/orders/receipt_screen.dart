import 'package:flutter/material.dart';
import '../../database/models/order_model.dart';
import '../../database/models/transaction_model.dart';
import '../../transactions/transaction_repository.dart';
import '../../services/printer_service.dart';
import '../../utils/currency_format.dart';

class ReceiptScreen extends StatefulWidget {
  final Order order;
  final bool isPaid;
  final String paymentMethod;
  final int paidAmount;

  const ReceiptScreen({
    Key? key,
    required this.order,
    this.isPaid = false,
    this.paymentMethod = 'cash',
    this.paidAmount = 0,
  }) : super(key: key);

  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  bool _isPrinting = false;
  int _maxDuration = 0;
  final TransactionRepository _transRepo = TransactionRepository();

  final Color primaryColor = const Color(0xFF4E80EE);
  final Color backgroundColor = const Color(0xFFF8FAFC);

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
    setState(() {
      _isPrinting = true;
    });

    try {
      final success = await PrinterService.printOrder(widget.order);

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Nota berhasil dicetak!'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );

          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) {
              Navigator.of(context).pushNamedAndRemoveUntil(
                '/dashboard',
                (route) => false,
              );
            }
          });
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ Gagal mencetak nota. Periksa printer!'),
              backgroundColor: Colors.red,
            ),
          );
          setState(() {
            _isPrinting = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() {
          _isPrinting = false;
        });
      }
    }
  }

  void _skipPrint() {
    Navigator.of(context).pushNamedAndRemoveUntil(
      '/dashboard',
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final sisaTagihan = widget.order.totalAmount - widget.paidAmount;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text('Konfirmasi Order Selesai', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        automaticallyImplyLeading: false, // Prevent going back after order submission
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 40.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Skeuomorphic Paper slip Container (max-width 420px)
              Container(
                width: 420,
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 30,
                      offset: const Offset(0, 10),
                    )
                  ],
                  border: Border.all(color: Colors.grey[150] ?? Colors.grey[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header logo & branding
                    const Center(
                      child: Column(
                        children: [
                          Icon(Icons.local_laundry_service_rounded, size: 36, color: Color(0xFF4E80EE)),
                          SizedBox(height: 12),
                          Text(
                            'SMART LAUNDRY',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                          ),
                          Text(
                            'Nota Transaksi Kasir',
                            style: TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Divider(height: 1),
                    const SizedBox(height: 20),

                    // Metadata
                    _buildReceiptRow('No. Nota:', '#${widget.order.id}', isBold: true),
                    _buildReceiptRow('Tanggal:', _formatDate(widget.order.orderDate)),
                    _buildReceiptRow('Pelanggan:', widget.order.customerName),
                    if (widget.order.customerPhone != null && widget.order.customerPhone!.isNotEmpty)
                      _buildReceiptRow('WhatsApp:', widget.order.customerPhone!),
                    _buildReceiptRow('Metode Bayar:', widget.paymentMethod.toUpperCase()),
                    const SizedBox(height: 16),
                    const Divider(height: 1),
                    const SizedBox(height: 20),

                    // Items List Table
                    const Text('Rincian Belanja:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                    const SizedBox(height: 12),
                    ...widget.order.items.map((item) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${item.quantity}x ', style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold, fontSize: 13)),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.itemName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                  if (item.note?.isNotEmpty == true)
                                    Text(item.note ?? '', style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.grey)),
                                ],
                              ),
                            ),
                            Text(
                              formatRp(item.price),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ],
                        ),
                      );
                    }).toList(),

                    const SizedBox(height: 16),
                    const Divider(height: 1),
                    const SizedBox(height: 20),

                    // Pricing block
                    _buildReceiptRow('Grand Total:', formatRp(widget.order.totalAmount), isBold: true, valueColor: Colors.black),
                    _buildReceiptRow('Jumlah Dibayar:', formatRp(widget.paidAmount), isBold: true, valueColor: Colors.green[700]),
                    const SizedBox(height: 12),

                    // Payment status tag
                    if (widget.isPaid) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDCFCE7),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFBBF7D0)),
                        ),
                        child: const Center(
                          child: Text(
                            'LUNAS',
                            style: TextStyle(color: Color(0xFF15803D), fontWeight: FontWeight.bold, letterSpacing: 1),
                          ),
                        ),
                      ),
                    ] else if (widget.paidAmount > 0) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orange.withOpacity(0.2)),
                        ),
                        child: Column(
                          children: [
                            const Text(
                              'BAYAR SETENGAH (DP)',
                              style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Sisa Tagihan: ${formatRp(sisaTagihan)}',
                              style: TextStyle(fontSize: 14, color: Colors.orange[800], fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.red.withOpacity(0.2)),
                        ),
                        child: Column(
                          children: [
                            const Text(
                              'BELUM BAYAR',
                              style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Sisa Tagihan: ${formatRp(sisaTagihan)}',
                              style: const TextStyle(fontSize: 14, color: Colors.redAccent, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    Text(
                      'Terima kasih telah mencuci bersama kami.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: Colors.grey[400], fontStyle: FontStyle.italic),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Bottom Actions
              Container(
                width: 420,
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isPrinting ? null : _skipPrint,
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: Colors.grey[300]!, width: 1.5),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Selesai / Lewati', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isPrinting ? null : _printReceipt,
                        icon: _isPrinting
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.print_rounded, color: Colors.white, size: 18),
                        label: const Text('Cetak Nota', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
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

  Widget _buildReceiptRow(String label, String value, {Color? valueColor, bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 12.5, color: Colors.grey[500])),
          Text(
            value,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: valueColor ?? const Color(0xFF334155),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}
