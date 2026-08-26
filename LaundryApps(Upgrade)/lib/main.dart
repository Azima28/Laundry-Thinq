import 'dart:io';
import 'dart:ui';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dashboard.dart';
import 'screens/orders/pesan.dart';
import 'screens/orders/tambah_item.dart';
import 'screens/orders/tambah_item_gosok.dart';
import 'screens/orders/pesan_gosok.dart';
import 'screens/orders/restock_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/customers/customer_screen.dart';
import 'screens/admin/admin_dashboard.dart';
import 'screens/settings/settings_screen.dart';
import 'screens/settings/backup_settings_screen.dart';
import 'screens/settings/wa_settings_screen.dart';
import 'screens/auth/setup_wizard_screen.dart';
import 'screens/settings/lg_thinq_settings_screen.dart';
import 'screens/settings/bardi_tuya_settings_screen.dart';
import 'screens/admin/printer_settings_screen.dart';
import 'screens/admin/payment_settings_screen.dart';
import 'screens/admin/laundry_settings_screen.dart';
import 'screens/admin/hubungi_pelanggan_screen.dart';
import 'screens/admin/pengeluaran_screen.dart';
import 'screens/history/global_history_screen.dart';
import 'screens/auth/check_role.dart';
import 'screens/machines/mesin_cuci_screen.dart';
import 'services/machine_status_service.dart';
import 'services/notification_service.dart';
import 'services/backend_services_manager.dart';
import 'screens/machines/mesin_pengering_screen.dart';
import 'database/models/database_helper.dart';
import 'transactions/user_repository.dart';
import 'utils/globals.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter/foundation.dart';
import 'utils/error_boundary.dart';

void main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isAndroid || Platform.isIOS) {
    FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  }

  // Graceful shutdown listener for Windows Desktop
  AppLifecycleListener(
    onDetach: () {
      BackendServicesManager.instance.stopServices();
    },
    onExitRequested: () async {
      await BackendServicesManager.instance.stopServices();
      return AppExitResponse.exit;
    },
  );

  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // Error boundary protection
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('UNCAUGHT_FLUTTER_ERROR: ${details.exceptionAsString()}');
  };

  PlatformDispatcher.instance.onError = (Object exception, StackTrace stackTrace) {
    debugPrint('UNCAUGHT_ASYNC_ERROR: $exception');
    return true; // prevent crash
  };

  ErrorWidget.builder = (FlutterErrorDetails details) {
    return CustomErrorScreen(details: details);
  };

  // 1. Jalankan tugas KRITIS secara paralel (Database & SharedPreferences)
  // Ini mempercepat startup karena tidak saling menunggu
  final initResults = await Future.wait([
    DatabaseHelper.instance.database,
    SharedPreferences.getInstance(),
  ]);

  final prefs = initResults[1] as SharedPreferences;
  final userId = prefs.getInt('user_id');
  final isSetupDone = prefs.getBool('is_setup_done') ?? false;

  // 2. Tampilkan UI secepat mungkin
  runApp(MyApp(isLoggedIn: userId != null, isSetupDone: isSetupDone));

  // 3. Jalankan tugas NON-KRITIS di background SETELAH UI muncul
  // User tidak akan merasa loading karena ini jalan di belakang layar
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    // Hilangkan splash screen jika di mobile
    if (Platform.isAndroid || Platform.isIOS) {
      FlutterNativeSplash.remove();
    }

    // Inisialisasi notifikasi
    try {
      await NotificationService.instance.init();
    } catch (_) {}

    // Inisialisasi proses child background (Python ThinQ & Node.js WA) terlebih dahulu
    try {
      await BackendServicesManager.instance.startServices();
    } catch (_) {}

    // Jalankan service status mesin
    try {
      await MachineStatusService.instance.start();
    } catch (_) {}

    // Cleanup data sampah/stuck (dilakukan terakhir agar tidak mengganggu)
    try {
      await DatabaseHelper.instance.cleanupStuckUsageRecords();
    } catch (_) {}
  });
}

class MyApp extends StatelessWidget {
  final bool isLoggedIn;
  final bool isSetupDone;
  const MyApp({super.key, this.isLoggedIn = false, this.isSetupDone = false});

  Future<bool> _checkAdminAccess() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('user_id');
    if (userId == null) return false;

    final userRepo = UserRepository();
    final user = await userRepo.getUserById(userId);
    return user?.role == 'admin';
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Laundry POS',
      scaffoldMessengerKey: Globals.scaffoldMessengerKey,
      initialRoute: !isSetupDone ? '/setup_wizard' : (isLoggedIn ? '/check_role' : '/'),
      routes: {
        '/': (context) => LoginScreen(),
        '/setup_wizard': (context) => const SetupWizardScreen(),
        '/check_role': (context) => CheckRolePage(),
        '/dashboard': (context) => DashboardPage(),
        '/admin_dashboard': (context) => AdminDashboard(),
        '/pesan': (context) => PesanPage(),
        '/pesan_gosok': (context) => PesanGosokPage(),
        '/tambah_item': (context) => FutureBuilder(
          future: _checkAdminAccess(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            if (snapshot.data == true) {
              return TambahItemScreen();
            }
            // Redirect to dashboard if not admin
            WidgetsBinding.instance.addPostFrameCallback((_) {
              Navigator.of(context).pushReplacementNamed('/dashboard');
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Akses ditolak: Hanya untuk admin')),
              );
            });
            return Container();
          },
        ),
        '/tambah_item_gosok': (context) => FutureBuilder(
          future: _checkAdminAccess(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            if (snapshot.data == true) {
              return TambahItemGosokScreen();
            }
            // Redirect to dashboard if not admin
            WidgetsBinding.instance.addPostFrameCallback((_) {
              Navigator.of(context).pushReplacementNamed('/dashboard');
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Akses ditolak: Hanya untuk admin')),
              );
            });
            return Container();
          },
        ),
        '/history': (context) => const GlobalHistoryScreen(initialCategoryTab: 'order', showAppBar: true),
        '/history_gosok': (context) => const GlobalHistoryScreen(initialCategoryTab: 'gosok', showAppBar: true),
        '/history_mesin_cuci': (context) => const GlobalHistoryScreen(initialCategoryTab: 'cuci', showAppBar: true),
        '/history_pengering': (context) => const GlobalHistoryScreen(initialCategoryTab: 'pengering', showAppBar: true),
        '/global_history': (context) => const GlobalHistoryScreen(initialCategoryTab: 'buku_besar', showAppBar: true),
        '/mesin': (context) => FutureBuilder(
          future: _checkAdminAccess(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            if (snapshot.data == true) {
              return const MesinCuciScreen();
            }
            // Redirect to dashboard if not admin
            WidgetsBinding.instance.addPostFrameCallback((_) {
              Navigator.of(context).pushReplacementNamed('/dashboard');
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Akses ditolak: Hanya untuk admin')),
              );
            });
            return Container();
          },
        ),
        '/mesin_pengering': (context) => FutureBuilder(
          future: _checkAdminAccess(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            if (snapshot.data == true) {
              return const MesinPengeringScreen();
            }
            // Redirect to dashboard if not admin
            WidgetsBinding.instance.addPostFrameCallback((_) {
              Navigator.of(context).pushReplacementNamed('/dashboard');
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Akses ditolak: Hanya untuk admin')),
              );
            });
            return Container();
          },
        ),
        '/settings': (context) => SettingsScreen(),
        '/wa_settings': (context) => const WaSettingsScreen(),
        '/lg_thinq_settings': (context) => FutureBuilder(
          future: _checkAdminAccess(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            if (snapshot.data == true) {
              return const LgThinqSettingsScreen();
            }
            // Redirect to dashboard if not admin
            WidgetsBinding.instance.addPostFrameCallback((_) {
              Navigator.of(context).pushReplacementNamed('/dashboard');
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Akses ditolak: Hanya untuk admin')),
              );
            });
            return Container();
          },
        ),
        '/bardi_tuya_settings': (context) => FutureBuilder(
          future: _checkAdminAccess(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            if (snapshot.data == true) {
              return const BardiTuyaSettingsScreen();
            }
            // Redirect to dashboard if not admin
            WidgetsBinding.instance.addPostFrameCallback((_) {
              Navigator.of(context).pushReplacementNamed('/dashboard');
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Akses ditolak: Hanya untuk admin')),
              );
            });
            return Container();
          },
        ),
        '/laundry_settings': (context) => FutureBuilder(
          future: _checkAdminAccess(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            if (snapshot.data == true) {
              return const LaundrySettingsScreen();
            }
            // Redirect to dashboard if not admin
            WidgetsBinding.instance.addPostFrameCallback((_) {
              Navigator.of(context).pushReplacementNamed('/dashboard');
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Akses ditolak: Hanya untuk admin')),
              );
            });
            return Container();
          },
        ),
        '/printer_settings': (context) => PrinterSettingsScreen(),
        '/payment_settings': (context) => PaymentSettingsScreen(),
        '/backup_settings': (context) => FutureBuilder(
          future: _checkAdminAccess(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            if (snapshot.data == true) {
              return const BackupSettingsScreen();
            }
            // Redirect to dashboard if not admin
            WidgetsBinding.instance.addPostFrameCallback((_) {
              Navigator.of(context).pushReplacementNamed('/dashboard');
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Akses ditolak: Hanya untuk admin')),
              );
            });
            return Container();
          },
        ),
        '/customers': (context) => const CustomerScreen(),
        '/hubungi_pelanggan': (context) => const HubungiPelangganScreen(),
        '/pengeluaran': (context) => const PengeluaranScreen(),
        '/restock': (context) => const RestockScreen(),
      },
    );
  }
}
