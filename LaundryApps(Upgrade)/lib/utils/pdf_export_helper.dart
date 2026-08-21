import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../database/models/database_helper.dart';
import '../database/models/transaction_model.dart';
import '../transactions/transaction_repository.dart';

class PdfExportHelper {
  static final NumberFormat _formatter = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  static String formatRp(int amount) {
    return _formatter.format(amount);
  }

  static Future<void> exportLedgerToPdf({
    required BuildContext context,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final pdf = pw.Document();
    
    // 1. Fetch Business Profile from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final bizName = prefs.getString('biz_name') ?? 'Smart Laundry';
    final bizAddress = prefs.getString('biz_address') ?? 'Alamat tidak tersedia';
    final bizPhone = prefs.getString('biz_phone') ?? '-';

    // 2. Fetch Data from SQLite for the date range
    final startStr = DateFormat('yyyy-MM-dd').format(startDate);
    final endStr = DateFormat('yyyy-MM-dd').format(endDate);

    final db = DatabaseHelper.instance;
    final orders = await db.getOrdersByDateRange(startStr, endStr);
    final expenses = await db.getExpensesByDateRange(startStr, endStr);

    // Get all transactions to identify iron (gosok) orders
    final allTransactions = await TransactionRepository().getAllTransactions();
    final ironItemIds = allTransactions
        .where((t) => t.type == TransactionType.iron)
        .map((t) => t.id)
        .toSet();

    // Prepare lists
    int totalDiterima = 0;
    int totalPiutang = 0;
    int totalPengeluaran = 0;

    List<Map<String, dynamic>> incomeRows = [];
    for (int i = 0; i < orders.length; i++) {
      final order = orders[i];
      final isGosok = order.items.isNotEmpty &&
          order.items.every((item) => ironItemIds.contains(item.itemId));

      final unpaid = (order.totalAmount - order.paidAmount).clamp(0, order.totalAmount);

      totalDiterima += order.paidAmount;
      if (unpaid > 0) {
        totalPiutang += unpaid;
      }

      String statusStr = 'Lunas';
      if (order.paidAmount == 0) {
        statusStr = 'Belum Bayar';
      } else if (unpaid > 0) {
        statusStr = 'Cicilan';
      }

      incomeRows.add({
        'no': '${i + 1}',
        'date': DateFormat('dd/MM/yyyy HH:mm').format(order.orderDate),
        'customer': order.customerName,
        'type': isGosok ? 'Gosok' : 'Cuci',
        'total': formatRp(order.totalAmount),
        'paid': formatRp(order.paidAmount),
        'unpaid': unpaid > 0 ? formatRp(unpaid) : '-',
        'method': order.paymentMethod.toUpperCase(),
        'status': statusStr,
      });
    }

    List<Map<String, dynamic>> expenseRows = [];
    for (int i = 0; i < expenses.length; i++) {
      final exp = expenses[i];
      final amt = int.tryParse(exp['amount']?.toString() ?? '') ?? 0;
      totalPengeluaran += amt;

      final dt = exp['created_at'] != null 
          ? DateTime.tryParse(exp['created_at']) ?? endDate 
          : endDate;

      expenseRows.add({
        'no': '${i + 1}',
        'date': DateFormat('dd/MM/yyyy').format(dt),
        'title': exp['name'] ?? '',
        'amount': formatRp(amt),
      });
    }

    final netProfit = totalDiterima - totalPengeluaran;

    // Define colors
    final primaryColor = PdfColor.fromHex('#1E3A8A'); // Deep Navy Blue
    final secondaryColor = PdfColor.fromHex('#EFF6FF'); // Light Blue Accent
    final borderGrey = PdfColor.fromHex('#E2E8F0');

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          // Header / Kop Surat
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    bizName.toUpperCase(),
                    style: pw.TextStyle(
                      fontSize: 20,
                      fontWeight: pw.FontWeight.bold,
                      color: primaryColor,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    bizAddress,
                    style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                  ),
                  pw.Text(
                    'WhatsApp: $bizPhone',
                    style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                  ),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'LAPORAN KEUANGAN',
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                      color: primaryColor,
                    ),
                  ),
                  pw.Text(
                    'BUKU BESAR & LABA/RUGI',
                    style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Text(
                    'Periode: ${DateFormat('dd MMM yyyy').format(startDate)} s/d ${DateFormat('dd MMM yyyy').format(endDate)}',
                    style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                  ),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Divider(thickness: 1, color: borderGrey),
          pw.SizedBox(height: 16),

          // Ringkasan Keuangan (Cards/Table)
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: secondaryColor,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Text(
                  'REKAPITULASI KEUANGAN',
                  style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: primaryColor),
                ),
                pw.SizedBox(height: 12),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Total Uang Masuk', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                        pw.Text(formatRp(totalDiterima), style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.green)),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Total Pengeluaran', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                        pw.Text(formatRp(totalPengeluaran), style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.red)),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Total Piutang', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                        pw.Text(formatRp(totalPiutang), style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.orange)),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text('Laba Bersih', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: primaryColor)),
                        pw.Text(
                          formatRp(netProfit),
                          style: pw.TextStyle(
                            fontSize: 16,
                            fontWeight: pw.FontWeight.bold,
                            color: netProfit >= 0 ? PdfColors.green900 : PdfColors.red900,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 24),

          // Detail Pemasukan (Tabel)
          pw.Text(
            'DETAIL PEMASUKAN TRANSAKSI',
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: primaryColor),
          ),
          pw.SizedBox(height: 8),
          if (incomeRows.isEmpty)
            pw.Text('Tidak ada transaksi pemasukan pada periode ini.', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600))
          else
            pw.Table(
              border: pw.TableBorder.all(color: borderGrey, width: 0.5),
              columnWidths: {
                0: const pw.FixedColumnWidth(24),
                1: const pw.FixedColumnWidth(80),
                2: const pw.FlexColumnWidth(2),
                3: const pw.FixedColumnWidth(40),
                4: const pw.FixedColumnWidth(60),
                5: const pw.FixedColumnWidth(60),
                6: const pw.FixedColumnWidth(60),
                7: const pw.FixedColumnWidth(50),
                8: const pw.FixedColumnWidth(50),
              },
              children: [
                // Header
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: primaryColor),
                  children: [
                    'No',
                    'Tanggal',
                    'Pelanggan',
                    'Tipe',
                    'Total',
                    'Diterima',
                    'Piutang',
                    'Metode',
                    'Status'
                  ].map((h) => pw.Container(
                    padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                    alignment: pw.Alignment.center,
                    child: pw.Text(
                      h,
                      style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                    ),
                  )).toList(),
                ),
                // Rows
                ...incomeRows.map((r) => pw.TableRow(
                  children: [
                    r['no']!,
                    r['date']!,
                    r['customer']!,
                    r['type']!,
                    r['total']!,
                    r['paid']!,
                    r['unpaid']!,
                    r['method']!,
                    r['status']!,
                  ].map((cell) => pw.Container(
                    padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                    alignment: pw.Alignment.center,
                    child: pw.Text(
                      cell,
                      style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey900),
                    ),
                  )).toList(),
                )).toList(),
              ],
            ),
          pw.SizedBox(height: 24),

          // Detail Pengeluaran (Tabel)
          pw.Text(
            'DETAIL PENGELUARAN BIAYA',
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: primaryColor),
          ),
          pw.SizedBox(height: 8),
          if (expenseRows.isEmpty)
            pw.Text('Tidak ada pengeluaran pada periode ini.', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600))
          else
            pw.Table(
              border: pw.TableBorder.all(color: borderGrey, width: 0.5),
              columnWidths: {
                0: const pw.FixedColumnWidth(30),
                1: const pw.FixedColumnWidth(100),
                2: const pw.FlexColumnWidth(),
                3: const pw.FixedColumnWidth(100),
              },
              children: [
                // Header
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: primaryColor),
                  children: [
                    'No',
                    'Tanggal',
                    'Keterangan Pengeluaran',
                    'Jumlah Biaya'
                  ].map((h) => pw.Container(
                    padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                    alignment: pw.Alignment.center,
                    child: pw.Text(
                      h,
                      style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                    ),
                  )).toList(),
                ),
                // Rows
                ...expenseRows.map((r) => pw.TableRow(
                  children: [
                    r['no']!,
                    r['date']!,
                    r['title']!,
                    r['amount']!,
                  ].map((cell) => pw.Container(
                    padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                    alignment: cell == r['title'] ? pw.Alignment.centerLeft : pw.Alignment.center,
                    child: pw.Text(
                      cell,
                      style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey900),
                    ),
                  )).toList(),
                )).toList(),
              ],
            ),

          pw.SizedBox(height: 40),
          // Signature Section
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Dibuat otomatis oleh Aplikasi Kasir Laundry', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500)),
                  pw.Text('Tanggal Cetak: ${DateFormat('dd MMMM yyyy HH:mm').format(DateTime.now())}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500)),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Text('Penanggung Jawab', style: const pw.TextStyle(fontSize: 9, color: PdfColors.black)),
                  pw.SizedBox(height: 30),
                  pw.Container(width: 100, height: 1, color: PdfColors.black),
                  pw.SizedBox(height: 2),
                  pw.Text('Kasir / Admin', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                ],
              ),
            ],
          ),
        ],
      ),
    );

    // 3. Save PDF - Let user freely choose destination location & file name (Windows Save As)
    try {
      final bytes = await pdf.save();
      final defaultFileName = startStr == endStr
          ? 'Laporan_Keuangan_$startStr.pdf'
          : 'Laporan_Keuangan_${startStr}_sd_$endStr.pdf';

      String? chosenPath;
      if (Platform.isWindows) {
        chosenPath = await _pickSaveLocationNative(defaultFileName: defaultFileName);
        if (chosenPath == null) {
          // User clicked Cancel in Windows Save As dialog
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Ekspor PDF dibatalkan oleh pengguna.'),
                backgroundColor: Color(0xFF64748B),
                duration: Duration(seconds: 2),
              ),
            );
          }
          return;
        }
      }

      File file;
      Directory targetDir;
      if (chosenPath != null) {
        file = File(chosenPath);
        targetDir = file.parent;
      } else {
        // Fallback for non-windows / mobile
        Directory? downloadsDir = await getDownloadsDirectory();
        downloadsDir ??= await getApplicationDocumentsDirectory();
        targetDir = Directory('${downloadsDir.path}/Laporan_Laundry');
        if (!await targetDir.exists()) {
          await targetDir.create(recursive: true);
        }
        file = File('${targetDir.path}/$defaultFileName');
      }

      await file.writeAsBytes(bytes);

      // Open PDF natively using default viewer
      final fileUri = Uri.file(file.path);
      final dirUri = Uri.file(targetDir.path);

      try {
        await launchUrl(fileUri, mode: LaunchMode.externalApplication);
      } catch (e) {
        await Process.run('explorer.exe', [file.path]);
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Laporan berhasil diekspor ke:\n${file.path}'),
            backgroundColor: const Color(0xFF10B981), // Emerald Green
            duration: const Duration(seconds: 7),
            action: SnackBarAction(
              label: 'Buka Folder',
              textColor: Colors.white,
              onPressed: () {
                try {
                  launchUrl(dirUri, mode: LaunchMode.externalApplication);
                } catch (_) {
                  Process.run('explorer.exe', [targetDir.path]);
                }
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal menyimpan PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Opens Native Windows Save File Dialog to choose location and file name for saving PDF (like Excel Save As)
  static Future<String?> _pickSaveLocationNative({
    required String defaultFileName,
  }) async {
    if (Platform.isWindows) {
      try {
        final script = '''
        Add-Type -AssemblyName System.Windows.Forms
        \$dialog = New-Object System.Windows.Forms.SaveFileDialog
        \$dialog.Filter = "Dokumen PDF (*.pdf)|*.pdf|Semua File (*.*)|*.*"
        \$dialog.DefaultExt = "pdf"
        \$dialog.FileName = "$defaultFileName"
        \$dialog.Title = "Simpan Laporan Keuangan PDF (Pilih Lokasi Simpan)"
        \$dialog.InitialDirectory = [Environment]::GetFolderPath("Desktop")
        if (\$dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
            Write-Output \$dialog.FileName
        }
        ''';

        final result = await Process.run('powershell', [
          '-NoProfile',
          '-Command',
          script,
        ]);

        if (result.exitCode == 0) {
          final out = (result.stdout as String).trim();
          if (out.isNotEmpty && out.toLowerCase().endsWith('.pdf')) {
            return out;
          } else if (out.isNotEmpty) {
            return '$out.pdf';
          }
        }
      } catch (e) {
        debugPrint('[PdfExportHelper] SaveFileDialog error: $e');
      }
    }
    return null;
  }
}
