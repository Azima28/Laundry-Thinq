import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:permission_handler/permission_handler.dart';

import '../database/models/order_model.dart';
import '../database/models/database_helper.dart';
import '../utils/currency_format.dart';

class PrinterService {
  /// Request necessary permissions for Bluetooth printing on Android.
  static Future<bool> requestPermissions() async {
    if (Platform.isAndroid) {
      Map<Permission, PermissionStatus> modernStatuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.bluetoothAdvertise,
      ].request();

      PermissionStatus locationStatus = await Permission.location.request();
      PermissionStatus legacyBtStatus = await Permission.bluetooth.request();

      bool modernGranted = modernStatuses[Permission.bluetoothScan]?.isGranted == true &&
          modernStatuses[Permission.bluetoothConnect]?.isGranted == true;

      bool legacyGranted = locationStatus.isGranted && legacyBtStatus.isGranted;

      return modernGranted || legacyGranted;
    }
    return true; // Desktop platforms (Windows, macOS, Linux)
  }

  /// Get list of installed Windows / OS system printers (USB, Network, Virtual)
  static Future<List<Printer>> getAvailableUsbPrinters() async {
    try {
      return await Printing.listPrinters();
    } catch (e) {
      debugPrint('[PrinterService] Error listing USB/System printers: $e');
      return [];
    }
  }

  /// Get the active connection type ('usb' or 'bluetooth')
  static Future<String> getConnectionType() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('printer_connection_type') ?? 'usb';
  }

  /// Main Print Order Method: Dispatches to USB or Bluetooth based on settings
  static Future<bool> printOrder(Order order) async {
    final prefs = await SharedPreferences.getInstance();
    final connectionType = prefs.getString('printer_connection_type') ?? 'usb';

    if (connectionType == 'usb') {
      return await _printOrderUsb(order);
    } else {
      return await _printOrderBluetooth(order);
    }
  }

  /// Prints an order receipt to USB / Windows System Printer directly
  static Future<bool> _printOrderUsb(Order order) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final targetPrinterName = prefs.getString('printer_usb_name') ?? '';
      final receiptWidth = prefs.getInt('receipt_width') ?? 58;
      final businessName = prefs.getString('biz_name') ?? 'Smart Laundry';
      final businessAddress = prefs.getString('biz_address') ?? 'Jl. Raya Utama No. 8';
      final businessPhone = prefs.getString('biz_phone') ?? '08123456789';
      final footerNote = prefs.getString('biz_footer') ?? 'Terima kasih telah mencuci di Smart Laundry!';

      final printers = await Printing.listPrinters();
      if (printers.isEmpty) {
        debugPrint('[PrinterService] Tidak ada printer terdeteksi di Windows.');
        return false;
      }

      Printer? selectedPrinter;
      if (targetPrinterName.isNotEmpty) {
        try {
          selectedPrinter = printers.firstWhere((p) => p.name == targetPrinterName);
        } catch (_) {}
      }

      // Fallback to default printer or first available printer
      selectedPrinter ??= printers.firstWhere((p) => p.isDefault, orElse: () => printers.first);

      // Page format based on width (58mm, 76mm Dot Matrix Epson TM-U220D, or 80mm)
      final double widthMm = receiptWidth == 76 ? 76.0 : (receiptWidth == 80 ? 80.0 : 58.0);
      final pageFormat = PdfPageFormat(
        widthMm * PdfPageFormat.mm,
        double.infinity,
        marginAll: 2 * PdfPageFormat.mm,
      );

      final pdfBytes = await _generateReceiptPdf(
        order: order,
        businessName: businessName,
        businessAddress: businessAddress,
        businessPhone: businessPhone,
        footerNote: footerNote,
        pageFormat: pageFormat,
      );

      final result = await Printing.directPrintPdf(
        printer: selectedPrinter,
        onLayout: (format) => pdfBytes,
        name: 'Nota_Laundry_${order.id}',
        format: pageFormat,
      );

      return result;
    } catch (e) {
      debugPrint('[PrinterService] Error printing via USB: $e');
      return false;
    }
  }

  /// Generates clean, crisp PDF bytes for Receipt Print matching standard POS thermal / dot matrix styling
  static Future<Uint8List> _generateReceiptPdf({
    required Order order,
    required String businessName,
    required String businessAddress,
    required String businessPhone,
    required String footerNote,
    required PdfPageFormat pageFormat,
  }) async {
    final doc = pw.Document();

    // Calculate Max Pickup Duration
    int maxDays = 0;
    final db = DatabaseHelper.instance;
    for (var item in order.items) {
      final trans = await db.getTransaction(item.itemId);
      if (trans != null && trans.durationDays != null && trans.durationDays! > maxDays) {
        maxDays = trans.durationDays!;
      }
    }

    final d = order.orderDate;
    final dateStr = DateFormat('dd/MM/yyyy HH:mm').format(d);
    String pickupDateStr = '';
    if (maxDays > 0) {
      final pickup = d.add(Duration(days: maxDays));
      pickupDateStr = DateFormat('dd/MM/yyyy HH:mm').format(pickup);
    }

    final bool isLunas = order.isPaid || order.paidAmount >= order.totalAmount;
    final int sisaTagihan = order.totalAmount - order.paidAmount;

    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (pw.Context ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              // 1. Header Toko
              pw.Center(
                child: pw.Text(
                  businessName.toUpperCase(),
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
                  textAlign: pw.TextAlign.center,
                ),
              ),
              if (businessAddress.isNotEmpty)
                pw.Center(
                  child: pw.Text(
                    businessAddress,
                    style: const pw.TextStyle(fontSize: 8),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
              if (businessPhone.isNotEmpty)
                pw.Center(
                  child: pw.Text(
                    'Tel: $businessPhone',
                    style: const pw.TextStyle(fontSize: 8),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
              pw.Divider(thickness: 0.8, height: 8),

              // 2. Info Nota & Pelanggan
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Nota: #${order.id}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5)),
                  pw.Text(dateStr, style: const pw.TextStyle(fontSize: 7.5)),
                ],
              ),
              pw.SizedBox(height: 2),
              pw.Text('Pelanggan: ${order.customerName}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5)),
              if (pickupDateStr.isNotEmpty) ...[
                pw.SizedBox(height: 2),
                pw.Text('Estimasi Selesai: $pickupDateStr', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
              ],
              pw.Divider(thickness: 0.8, height: 8),

              // 3. Daftar Item
              ...order.items.map((item) {
                final priceFormatted = formatRp(item.price);
                final subtotal = formatRp(item.price * item.quantity);
                return pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Expanded(
                            child: pw.Text(
                              item.itemName,
                              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
                            ),
                          ),
                          pw.Text(subtotal, style: const pw.TextStyle(fontSize: 8)),
                        ],
                      ),
                      pw.Text(
                        '${item.quantity} x $priceFormatted',
                        style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
                      ),
                      if (item.note != null && item.note!.isNotEmpty)
                        pw.Text(
                          'Catatan: ${item.note}',
                          style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey600),
                        ),
                    ],
                  ),
                );
              }),
              pw.Divider(thickness: 0.8, height: 8),

              // 4. Financial Total & Payment Status
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('TOTAL TAGIHAN:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                  pw.Text(formatRp(order.totalAmount), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                ],
              ),
              pw.SizedBox(height: 3),
              if (isLunas) ...[
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Metode Bayar: ${order.paymentMethod.toUpperCase()}', style: const pw.TextStyle(fontSize: 7.5)),
                    pw.Text('STATUS: LUNAS', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8, color: PdfColors.green900)),
                  ],
                ),
              ] else if (order.paidAmount > 0) ...[
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Telah Dibayar (DP):', style: const pw.TextStyle(fontSize: 7.5)),
                    pw.Text(formatRp(order.paidAmount), style: const pw.TextStyle(fontSize: 7.5)),
                  ],
                ),
                pw.SizedBox(height: 1),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('SISA TAGIHAN:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
                    pw.Text(formatRp(sisaTagihan), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
                  ],
                ),
              ] else ...[
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('STATUS:', style: const pw.TextStyle(fontSize: 7.5)),
                    pw.Text('BELUM BAYAR', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
                  ],
                ),
              ],
              pw.Divider(thickness: 0.8, height: 8),

              // 5. Footer Message
              pw.Center(
                child: pw.Text(
                  footerNote,
                  style: const pw.TextStyle(fontSize: 7),
                  textAlign: pw.TextAlign.center,
                ),
              ),
              pw.SizedBox(height: 14),
            ],
          );
        },
      ),
    );

    return await doc.save();
  }

  /// Prints an order receipt via Bluetooth thermal printer.
  static Future<bool> _printOrderBluetooth(Order order) async {
    final prefs = await SharedPreferences.getInstance();
    final address = prefs.getString('printer_mac') ?? prefs.getString('printer_bt_address') ?? '';
    final businessName = prefs.getString('biz_name') ?? prefs.getString('business_name') ?? 'Smart Laundry';
    final businessAddress = prefs.getString('biz_address') ?? prefs.getString('business_address') ?? '';
    final businessPhone = prefs.getString('biz_phone') ?? prefs.getString('business_phone') ?? '';

    if (address.isEmpty) return false;

    // Ensure connected
    bool connected = await PrintBluetoothThermal.connectionStatus;
    if (!connected) {
      connected = await PrintBluetoothThermal.connect(macPrinterAddress: address);
      if (!connected) return false;
    }

    try {
      List<int> bytes = [];

      // Init printer
      bytes += [0x1B, 0x40];

      // Center alignment
      bytes += [0x1B, 0x61, 0x01];
      bytes += '$businessName\n'.codeUnits;
      if (businessAddress.isNotEmpty) bytes += '$businessAddress\n'.codeUnits;
      if (businessPhone.isNotEmpty) bytes += 'Tel: $businessPhone\n'.codeUnits;

      // Left alignment
      bytes += [0x1B, 0x61, 0x00];
      bytes += '--------------------------------\n'.codeUnits;

      // Order info
      bytes += 'Order: #${order.id}\n'.codeUnits;
      bytes += 'Nama: ${order.customerName}\n'.codeUnits;

      final d = order.orderDate;
      final dateStr = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final timeStr = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
      bytes += 'Tgl Pesan: $dateStr $timeStr\n'.codeUnits;

      // Calculate max duration for pickup date
      int maxDays = 0;
      final db = DatabaseHelper.instance;
      for (var item in order.items) {
        final trans = await db.getTransaction(item.itemId);
        if (trans != null && trans.durationDays != null) {
          if (trans.durationDays! > maxDays) {
            maxDays = trans.durationDays!;
          }
        }
      }

      if (maxDays > 0) {
        final pickup = d.add(Duration(days: maxDays));
        final pDateStr = '${pickup.year}-${pickup.month.toString().padLeft(2, '0')}-${pickup.day.toString().padLeft(2, '0')}';
        final pTimeStr = '${pickup.hour.toString().padLeft(2, '0')}:${pickup.minute.toString().padLeft(2, '0')}';
        bytes += [0x1B, 0x45, 0x01]; // Bold on
        bytes += 'Tgl Ambil: $pDateStr $pTimeStr\n'.codeUnits;
        bytes += [0x1B, 0x45, 0x00]; // Bold off
      }

      bytes += '--------------------------------\n'.codeUnits;

      // Items
      for (var item in order.items) {
        final name = item.itemName.length > 16 ? item.itemName.substring(0, 16) : item.itemName;
        final priceFormatted = formatNumber(item.price);
        final line = '$name  ${item.quantity} x $priceFormatted\n';
        bytes += line.codeUnits;
        if (item.note != null && item.note!.isNotEmpty) {
          bytes += '  * ${item.note}\n'.codeUnits;
        }
      }

      bytes += '--------------------------------\n'.codeUnits;

      // Bold on for total
      bytes += [0x1B, 0x45, 0x01];
      bytes += 'Total: ${formatRp(order.totalAmount)}\n'.codeUnits;
      bytes += [0x1B, 0x45, 0x00]; // Bold off

      final bool isLunas = order.isPaid || order.paidAmount >= order.totalAmount;
      final int sisaTagihan = order.totalAmount - order.paidAmount;

      if (isLunas) {
        bytes += 'Metode: ${order.paymentMethod}\n'.codeUnits;
        bytes += [0x1B, 0x45, 0x01]; // Bold on
        bytes += 'Status: LUNAS\n'.codeUnits;
        bytes += [0x1B, 0x45, 0x00]; // Bold off
      } else if (order.paidAmount > 0) {
        bytes += 'Telah Dibayar: ${formatRp(order.paidAmount)}\n'.codeUnits;
        bytes += [0x1B, 0x45, 0x01]; // Bold on
        bytes += 'Status: BELUM LUNAS\n'.codeUnits;
        bytes += 'Sisa Tagihan: ${formatRp(sisaTagihan)}\n'.codeUnits;
        bytes += [0x1B, 0x45, 0x00]; // Bold off
      } else {
        bytes += [0x1B, 0x45, 0x01]; // Bold on
        bytes += 'Status: BELUM BAYAR\n'.codeUnits;
        bytes += 'Tagihan: ${formatRp(sisaTagihan)}\n'.codeUnits;
        bytes += [0x1B, 0x45, 0x00]; // Bold off
      }

      bytes += '--------------------------------\n'.codeUnits;

      // Center alignment
      bytes += [0x1B, 0x61, 0x01];
      bytes += 'Terima kasih telah berbelanja!\n'.codeUnits;

      // Feed and cut
      bytes += '\n\n\n'.codeUnits;
      bytes += [0x1D, 0x56, 0x00];

      return await PrintBluetoothThermal.writeBytes(bytes);
    } catch (e) {
      debugPrint('[PrinterService] Bluetooth Exception: $e');
      return false;
    }
  }

  /// Print Test Page on the configured active printer (USB or Bluetooth)
  static Future<bool> printTestPage() async {
    final prefs = await SharedPreferences.getInstance();
    final connectionType = prefs.getString('printer_connection_type') ?? 'usb';
    final businessName = prefs.getString('biz_name') ?? 'Smart Laundry';
    final businessAddress = prefs.getString('biz_address') ?? 'Jl. Raya Utama No. 8';
    final businessPhone = prefs.getString('biz_phone') ?? '08123456789';
    final receiptWidth = prefs.getInt('receipt_width') ?? 58;

    if (connectionType == 'usb') {
      try {
        final targetPrinterName = prefs.getString('printer_usb_name') ?? '';
        final printers = await Printing.listPrinters();
        if (printers.isEmpty) return false;

        Printer? selectedPrinter;
        if (targetPrinterName.isNotEmpty) {
          try {
            selectedPrinter = printers.firstWhere((p) => p.name == targetPrinterName);
          } catch (_) {}
        }
        selectedPrinter ??= printers.firstWhere((p) => p.isDefault, orElse: () => printers.first);

        final double widthMm = receiptWidth == 76 ? 76.0 : (receiptWidth == 80 ? 80.0 : 58.0);
        final pageFormat = PdfPageFormat(widthMm * PdfPageFormat.mm, double.infinity, marginAll: 2 * PdfPageFormat.mm);

        final doc = pw.Document();
        doc.addPage(
          pw.Page(
            pageFormat: pageFormat,
            build: (ctx) => pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Center(child: pw.Text(businessName.toUpperCase(), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11))),
                if (businessAddress.isNotEmpty) pw.Center(child: pw.Text(businessAddress, style: const pw.TextStyle(fontSize: 8))),
                if (businessPhone.isNotEmpty) pw.Center(child: pw.Text('Tel: $businessPhone', style: const pw.TextStyle(fontSize: 8))),
                pw.Divider(thickness: 0.8, height: 8),
                pw.Center(child: pw.Text('PENGUJIAN PRINTER KASIR', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9))),
                pw.Divider(thickness: 0.8, height: 8),
                pw.Text('Koneksi: KABEL USB / DRIVER WINDOWS', style: const pw.TextStyle(fontSize: 7.5)),
                pw.Text('Printer: ${selectedPrinter?.name}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
                pw.Text('Lebar Kertas: $receiptWidth mm', style: const pw.TextStyle(fontSize: 7.5)),
                pw.Text('Waktu: ${DateFormat("dd/MM/yyyy HH:mm:ss").format(DateTime.now())}', style: const pw.TextStyle(fontSize: 7.5)),
                pw.Divider(thickness: 0.8, height: 8),
                pw.Center(child: pw.Text('STATUS: PRINTER BERFUNGSI DENGAN BAIK!', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                pw.SizedBox(height: 14),
              ],
            ),
          ),
        );

        return await Printing.directPrintPdf(
          printer: selectedPrinter,
          onLayout: (f) => doc.save(),
          name: 'Test_Print_POS',
          format: pageFormat,
        );
      } catch (e) {
        debugPrint('[PrinterService] USB Test print error: $e');
        return false;
      }
    } else {
      final address = prefs.getString('printer_mac') ?? '';
      if (address.isEmpty) return false;

      bool connected = await PrintBluetoothThermal.connectionStatus;
      if (!connected) {
        connected = await PrintBluetoothThermal.connect(macPrinterAddress: address);
        if (!connected) return false;
      }

      try {
        List<int> bytes = [];
        bytes += [0x1B, 0x40]; // Init
        bytes += [0x1B, 0x61, 0x01]; // Center
        bytes += '$businessName\n'.codeUnits;
        if (businessAddress.isNotEmpty) bytes += '$businessAddress\n'.codeUnits;
        bytes += '--------------------------------\n'.codeUnits;
        bytes += 'HALAMAN PENGUJIAN BLUETOOTH\n'.codeUnits;
        bytes += '--------------------------------\n'.codeUnits;
        bytes += [0x1B, 0x61, 0x00];
        bytes += 'Status: PRINTER AKTIF & OK\n'.codeUnits;
        bytes += 'Waktu: ${DateTime.now().toLocal()}\n'.codeUnits;
        bytes += '--------------------------------\n'.codeUnits;
        bytes += [0x1B, 0x61, 0x01];
        bytes += 'Terima kasih!\n'.codeUnits;
        bytes += '\n\n\n'.codeUnits;
        bytes += [0x1D, 0x56, 0x00]; // Cut

        return await PrintBluetoothThermal.writeBytes(bytes);
      } catch (e) {
        debugPrint('[PrinterService] Bluetooth Test Page Exception: $e');
        return false;
      }
    }
  }
}
