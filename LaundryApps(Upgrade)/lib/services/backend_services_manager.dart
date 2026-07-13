import 'dart:io';
import 'package:flutter/foundation.dart';

class BackendServicesManager {
  static final BackendServicesManager instance = BackendServicesManager._internal();

  BackendServicesManager._internal();

  Process? _pythonProcess;
  Process? _nodeProcess;

  bool _isStarting = false;

  Future<void> startServices() async {
    if (_isStarting) return;
    _isStarting = true;

    final int parentPid = pid;
    debugPrint('[ServicesManager] Parent process PID: $parentPid');

    // Clean lingering processes on ports 3000, 5000, 5001 (Windows-only)
    try {
      if (Platform.isWindows) {
        debugPrint('[ServicesManager] Cleaning lingering backend processes on ports 3000, 5000, 5001...');
        Process.runSync('powershell', [
          '-Command',
          'Get-NetTCPConnection -LocalPort 3000, 5000, 5001 -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id \$_.OwningProcess -Force }'
        ]);
      }
    } catch (e) {
      debugPrint('[ServicesManager] Error cleaning lingering processes: $e');
    }

    // 1. Resolve working directories relative to executable or current project root
    // In dev: CWD is c:\Work\project laundry\laundry\LaundryApps(Upgrade)
    // Parent directory contains main.py and wa_service/
    String workingDir = Directory.current.path;
    String parentDir = Directory.current.parent.path;

    debugPrint('[ServicesManager] Working Directory: $workingDir');
    debugPrint('[ServicesManager] Parent Directory: $parentDir');

    // 2. Start Python server: main.exe (compiled) or main.py (dev)
    try {
      final pythonExe = File('$parentDir\\main.exe');
      final pythonScript = File('$parentDir\\main.py');
      
      if (await pythonExe.exists()) {
        debugPrint('[ServicesManager] Starting compiled Python server (main.exe)...');
        _pythonProcess = await Process.start(
          pythonExe.path,
          ['--parent-pid', '$parentPid'],
          workingDirectory: parentDir,
          environment: {'PYTHONUNBUFFERED': '1'},
        );
      } else if (await pythonScript.exists()) {
        debugPrint('[ServicesManager] Starting Python server (main.py)...');
        _pythonProcess = await Process.start(
          'python',
          ['-u', pythonScript.path, '--parent-pid', '$parentPid'],
          workingDirectory: parentDir,
        );
      } else {
        debugPrint('[ServicesManager] Warning: Neither main.exe nor main.py found at $parentDir');
      }

      if (_pythonProcess != null) {
        // Pipe stdout & stderr for debugging
        _pythonProcess!.stdout.transform(const SystemEncoding().decoder).listen((data) {
          debugPrint('[Python STDOUT] ${data.trim()}');
        });
        _pythonProcess!.stderr.transform(const SystemEncoding().decoder).listen((data) {
          debugPrint('[Python STDERR] ${data.trim()}');
        });
        debugPrint('[ServicesManager] Python server successfully started in background.');
      }
    } catch (e) {
      debugPrint('[ServicesManager] Error starting Python server: $e');
    }

    // 3. Start Node.js WhatsApp microservice: wa_service.exe (compiled) or wa_service/index.js (dev)
    try {
      final nodeExe = File('$parentDir\\wa_service\\wa_service.exe');
      final nodeScript = File('$parentDir\\wa_service\\index.js');
      
      if (await nodeExe.exists()) {
        debugPrint('[ServicesManager] Starting compiled Node.js WA microservice (wa_service.exe)...');
        _nodeProcess = await Process.start(
          nodeExe.path,
          ['--parent-pid=$parentPid'],
          workingDirectory: '$parentDir\\wa_service',
        );
      } else if (await nodeScript.exists()) {
        debugPrint('[ServicesManager] Starting Node.js WA microservice (index.js)...');
        _nodeProcess = await Process.start(
          'node',
          [nodeScript.path, '--parent-pid=$parentPid'],
          workingDirectory: '$parentDir\\wa_service',
        );
      } else {
        debugPrint('[ServicesManager] Warning: Neither wa_service.exe nor index.js found at $parentDir\\wa_service');
      }

      if (_nodeProcess != null) {
        // Pipe stdout & stderr
        _nodeProcess!.stdout.transform(const SystemEncoding().decoder).listen((data) {
          debugPrint('[Node STDOUT] ${data.trim()}');
        });
        _nodeProcess!.stderr.transform(const SystemEncoding().decoder).listen((data) {
          debugPrint('[Node STDERR] ${data.trim()}');
        });
        debugPrint('[ServicesManager] Node.js WhatsApp microservice successfully started in background.');
      }
    } catch (e) {
      debugPrint('[ServicesManager] Error starting Node.js server: $e');
    }

    _isStarting = false;
  }

  Future<void> stopServices() async {
    debugPrint('[ServicesManager] Stopping background child services...');
    
    if (_pythonProcess != null) {
      _pythonProcess!.kill();
      _pythonProcess = null;
      debugPrint('[ServicesManager] Python process killed.');
    }

    if (_nodeProcess != null) {
      _nodeProcess!.kill();
      _nodeProcess = null;
      debugPrint('[ServicesManager] Node process killed.');
    }
  }
}
