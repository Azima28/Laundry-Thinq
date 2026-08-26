import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class BackendServicesManager {
  static final BackendServicesManager instance = BackendServicesManager._internal();

  BackendServicesManager._internal();

  Process? _pythonProcess;
  Process? _nodeProcess;

  bool _isStarting = false;

  bool get isPythonRunning => _pythonProcess != null;
  bool get isNodeRunning => _nodeProcess != null;

  Future<bool> isBackendReady({Duration timeout = const Duration(seconds: 8)}) async {
    final stopwatch = Stopwatch()..start();
    while (stopwatch.elapsed < timeout) {
      try {
        final resp = await http.get(Uri.parse('http://127.0.0.1:5001/')).timeout(const Duration(milliseconds: 1200));
        if (resp.statusCode >= 200 && resp.statusCode < 500) {
          return true;
        }
      } catch (_) {
        // Backend still booting
      }
      await Future.delayed(const Duration(milliseconds: 400));
    }
    return false;
  }

  Future<void> startServices() async {
    if (_isStarting) return;
    _isStarting = true;

    final int parentPid = pid;
    debugPrint('[ServicesManager] Parent process PID: $parentPid');

    // 1. Resolve working directories relative to executable or current project root
    String appDir = File(Platform.resolvedExecutable).parent.path;
    String parentDir = Directory.current.parent.path;

    debugPrint('[ServicesManager] Executable Directory: $appDir');
    debugPrint('[ServicesManager] Working Directory: ${Directory.current.path}');

    // Find Python backend executable/script in multiple candidate locations
    File? pythonFile;
    String pythonWorkingDir = appDir;

    final candidatePythonPaths = [
      '$appDir\\main.exe',
      '$appDir\\main.py',
      '$parentDir\\main.exe',
      '$parentDir\\main.py',
      '${Directory.current.path}\\main.exe',
      '${Directory.current.path}\\main.py',
    ];

    for (final path in candidatePythonPaths) {
      final f = File(path);
      if (f.existsSync()) {
        pythonFile = f;
        pythonWorkingDir = f.parent.path;
        break;
      }
    }

    // 2. Start Python server: main.exe (compiled) or main.py (dev)
    try {
      if (pythonFile != null && _pythonProcess == null) {
        final isExe = pythonFile.path.toLowerCase().endsWith('.exe');
        if (isExe) {
          debugPrint('[ServicesManager] Starting compiled Python server: ${pythonFile.path}...');
          _pythonProcess = await Process.start(
            pythonFile.path,
            ['--parent-pid', '$parentPid'],
            workingDirectory: pythonWorkingDir,
            environment: {'PYTHONUNBUFFERED': '1'},
          );
        } else {
          debugPrint('[ServicesManager] Starting Python script: ${pythonFile.path}...');
          _pythonProcess = await Process.start(
            'python',
            ['-u', pythonFile.path, '--parent-pid', '$parentPid'],
            workingDirectory: pythonWorkingDir,
          );
        }

        _pythonProcess?.exitCode.then((code) {
          debugPrint('[ServicesManager] Python backend process terminated with exit code: $code');
          _pythonProcess = null;
        });
      } else if (pythonFile == null) {
        debugPrint('[ServicesManager] Warning: Python backend (main.exe / main.py) not found in candidate paths.');
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

    // 3. Start Node.js WhatsApp microservice
    try {
      File? nodeFile;
      String nodeWorkingDir = '$appDir\\wa_service';

      final candidateNodePaths = [
        '$appDir\\wa_service\\wa_service.exe',
        '$appDir\\wa_service\\index.js',
        '$parentDir\\wa_service\\wa_service.exe',
        '$parentDir\\wa_service\\index.js',
        '${Directory.current.path}\\wa_service\\wa_service.exe',
        '${Directory.current.path}\\wa_service\\index.js',
      ];

      for (final path in candidateNodePaths) {
        final f = File(path);
        if (f.existsSync()) {
          nodeFile = f;
          nodeWorkingDir = f.parent.path;
          break;
        }
      }

      if (nodeFile != null && _nodeProcess == null) {
        final isExe = nodeFile.path.toLowerCase().endsWith('.exe');
        if (isExe) {
          debugPrint('[ServicesManager] Starting compiled Node.js WA microservice: ${nodeFile.path}...');
          _nodeProcess = await Process.start(
            nodeFile.path,
            ['--parent-pid=$parentPid'],
            workingDirectory: nodeWorkingDir,
          );
        } else {
          String nodeExe = 'node';
          final candidateNodeExes = [
            '$appDir\\wa_service\\node.exe',
            '$parentDir\\wa_service\\node.exe',
            '${Directory.current.path}\\wa_service\\node.exe',
            '$appDir\\node.exe',
          ];
          for (final p in candidateNodeExes) {
            if (File(p).existsSync()) {
              nodeExe = p;
              break;
            }
          }

          debugPrint('[ServicesManager] Starting Node.js WA microservice with ($nodeExe): ${nodeFile.path}...');
          _nodeProcess = await Process.start(
            nodeExe,
            [nodeFile.path, '--parent-pid=$parentPid'],
            workingDirectory: nodeWorkingDir,
          );
        }

        _nodeProcess?.exitCode.then((code) {
          debugPrint('[ServicesManager] Node.js WA process terminated with exit code: $code');
          _nodeProcess = null;
        });
      } else if (nodeFile == null) {
        debugPrint('[ServicesManager] Warning: WhatsApp microservice not found.');
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
