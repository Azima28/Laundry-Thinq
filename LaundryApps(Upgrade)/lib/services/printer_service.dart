import 'package:shared_preferences/shared_preferences.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import '../database/models/order_model.dart';
import '../database/models/transaction_model.dart';
import '../database/models/database_helper.dart';
import '../utils/currency_format.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';

class PrinterService {
  /// Request necessary permissions for Bluetooth printing.
  /// Android 12+ requires BLUETOOTH_SCAN and BLUETOOTH_CONNECT.
  /// Older versions require BLUETOOTH and ACCESS_FINE_LOCATION.
  static Future<bool> requestPermissions() async {
    if (Platform.isAndroid) {
      // 1. Request Bluetooth permissions for Android 12+ (API 31+)
      // Note: permission_handler will automatically skip these on older Android versions
      Map<Permission, PermissionStatus> modernStatuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.bluetoothAdvertise,
      ].request();

      // 2. Request Location permission (Required for Bluetooth scanning on Android 11 and below)
      PermissionStatus locationStatus = await Permission.location.request();

      // 3. Request Legacy Bluetooth permission for older devices
      PermissionStatus legacyBtStatus = await Permission.bluetooth.request();

      // Logic for determining success:
      // On Android 12+, scan and connect are mandatory.
      // On Android 11-, location and basic bluetooth are mandatory.
      
      bool modernGranted = modernStatuses[Permission.bluetoothScan]?.isGranted == true &&
                          modernStatuses[Permission.bluetoothConnect]?.isGranted == true;
      
      bool legacyGranted = locationStatus.isGranted && legacyBtStatus.isGranted;

      // If either modern or legacy flow succeeds, we are likely good to go
      return modernGranted || legacyGranted;
    }
    return true; // Non-android platforms
  }

  /// Prints an order receipt via Bluetooth thermal printer.
  /// Automatically connects if not already connected.
  /// Returns true on success.
  static Future<bool> printOrder(Order order) async {
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

      final result = await PrintBluetoothThermal.writeBytes(bytes);
      return result;
    } catch (e) {
      print('PrinterService: Exception: $e');
      return false;
    }
  }

  static Future<bool> printTestPage() async {
    final prefs = await SharedPreferences.getInstance();
    final address = prefs.getString('printer_mac') ?? prefs.getString('printer_bt_address') ?? '';
    final businessName = prefs.getString('biz_name') ?? prefs.getString('business_name') ?? 'Smart Laundry';
    final businessAddress = prefs.getString('biz_address') ?? prefs.getString('business_address') ?? 'Jl. Raya Utama No. 8';
    
    if (address.isEmpty) return false;

    bool connected = await PrintBluetoothThermal.connectionStatus;
    if (!connected) {
      connected = await PrintBluetoothThermal.connect(macPrinterAddress: address);
      if (!connected) return false;
    }

    try {
      List<int> bytes = [];
      bytes += [0x1B, 0x40]; // Init
      bytes += [0x1B, 0x61, 0x01]; // Center alignment
      bytes += '$businessName\n'.codeUnits;
      if (businessAddress.isNotEmpty) bytes += '$businessAddress\n'.codeUnits;
      bytes += '--------------------------------\n'.codeUnits;
      bytes += 'HALAMAN PENGUJIAN PRINTER\n'.codeUnits;
      bytes += '--------------------------------\n'.codeUnits;
      bytes += [0x1B, 0x61, 0x00]; // Left alignment
      bytes += 'Status: PRINTER AKTIF & OK\n'.codeUnits;
      bytes += 'Waktu: ${DateTime.now().toLocal()}\n'.codeUnits;
      bytes += '--------------------------------\n'.codeUnits;
      bytes += [0x1B, 0x61, 0x01]; // Center alignment
      bytes += 'Terima kasih!\n'.codeUnits;
      bytes += '\n\n\n'.codeUnits;
      bytes += [0x1D, 0x56, 0x00]; // Cut

      return await PrintBluetoothThermal.writeBytes(bytes);
    } catch (e) {
      print('PrinterService: Test Page Exception: $e');
      return false;
    }
  }
}
