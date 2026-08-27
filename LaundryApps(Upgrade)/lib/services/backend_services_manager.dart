import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class BackendServicesManager {
  static final BackendServicesManager instance = BackendServicesManager._internal();

  BackendServicesManager._internal();

  Process? _pythonProcess;
  Process? _nodeProcess;

  bool _isStarting = false;
  Timer? _watchdogTimer;

  bool get isPythonRunning => _pythonProcess != null;
  bool get isNodeRunning => _nodeProcess != null;

  List<String> _getCandidateDirectories() {
    final List<String> dirs = [];

    // 1. Executable dir
    try {
      final appDir = File(Platform.resolvedExecutable).parent.path;
      dirs.add(appDir);

      // Traverse up to 5 levels (from build/windows/x64/runner/Debug up to root)
      Directory current = Directory(appDir);
      for (int i = 0; i < 5; i++) {
        current = current.parent;
        dirs.add(current.path);
      }
    } catch (_) {}

    // 2. Working directory & parent
    try {
      final cwd = Directory.current.path;
      dirs.add(cwd);
      dirs.add(Directory.current.parent.path);
    } catch (_) {}

    // 3. Known workspace path
    dirs.add('C:\\Work\\project laundry\\laundry');

    // Remove duplicates and non-existent directories
    final uniqueDirs = <String>{};
    final validDirs = <String>[];
    for (final d in dirs) {
      final normalized = d.trim().replaceAll('/', '\\');
      if (normalized.isNotEmpty && uniqueDirs.add(normalized.toLowerCase())) {
        if (Directory(normalized).existsSync()) {
          validDirs.add(normalized);
        }
      }
    }
    return validDirs;
  }

  Future<bool> isPythonReady({Duration timeout = const Duration(seconds: 2)}) async {
    final stopwatch = Stopwatch()..start();
    while (stopwatch.elapsed < timeout) {
      try {
        final resp = await http.get(Uri.parse('http://127.0.0.1:5001/')).timeout(const Duration(milliseconds: 600));
        if (resp.statusCode >= 200 && resp.statusCode < 500) {
          return true;
        }
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 200));
    }
    return false;
  }

  Future<bool> isNodeReady({Duration timeout = const Duration(seconds: 2)}) async {
    final stopwatch = Stopwatch()..start();
    while (stopwatch.elapsed < timeout) {
      try {
        final resp = await http.get(Uri.parse('http://127.0.0.1:3000/status')).timeout(const Duration(milliseconds: 600));
        if (resp.statusCode >= 200 && resp.statusCode < 500) {
          return true;
        }
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 200));
    }
    return false;
  }

  Future<bool> isBackendReady({Duration timeout = const Duration(seconds: 3)}) async {
    return isPythonReady(timeout: timeout);
  }

  Future<void> ensureServicesRunning() async {
    if (_isStarting) return;
    final pythonOk = await isPythonReady(timeout: const Duration(milliseconds: 500));
    final nodeOk = await isNodeReady(timeout: const Duration(milliseconds: 500));
    if (!pythonOk || !nodeOk) {
      debugPrint('[ServicesManager] Services check: Python=$pythonOk, Node=$nodeOk. Running startServices...');
      await startServices();
    }
  }

  void startWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(const Duration(seconds: 12), (_) async {
      if (_isStarting) return;
      final pythonOk = await isPythonReady(timeout: const Duration(milliseconds: 800));
      final nodeOk = await isNodeReady(timeout: const Duration(milliseconds: 800));
      if (!pythonOk || !nodeOk) {
        debugPrint('[ServicesManager Watchdog] Service offline: Python=$pythonOk, Node=$nodeOk. Auto-recovering...');
        await startServices();
      }
    });
  }

  Future<void> startServices() async {
    if (_isStarting) return;
    _isStarting = true;

    final int parentPid = pid;
    debugPrint('[ServicesManager] Parent process PID: $parentPid');

    final candidateDirs = _getCandidateDirectories();
    debugPrint('[ServicesManager] Candidate search dirs: $candidateDirs');

    // 1. Start Python server if not already responding
    final pythonAlreadyReady = await isPythonReady(timeout: const Duration(milliseconds: 400));
    if (!pythonAlreadyReady) {
      File? pythonExe;
      File? pythonScript;
      String pythonWorkingDir = candidateDirs.isNotEmpty ? candidateDirs.first : Directory.current.path;

      for (final dir in candidateDirs) {
        final exe = File('$dir\\main.exe');
        if (exe.existsSync() && pythonExe == null) {
          pythonExe = exe;
          pythonWorkingDir = dir;
        }
        final script = File('$dir\\main.py');
        if (script.existsSync() && pythonScript == null) {
          pythonScript = script;
          if (pythonExe == null) pythonWorkingDir = dir;
        }
      }

      try {
        if (_pythonProcess == null) {
          if (pythonExe != null) {
            debugPrint('[ServicesManager] Starting compiled Python server: ${pythonExe.path} (cwd: $pythonWorkingDir)...');
            try {
              _pythonProcess = await Process.start(
                pythonExe.path,
                ['--parent-pid', '$parentPid'],
                workingDirectory: pythonWorkingDir,
                environment: {'PYTHONUNBUFFERED': '1'},
              );
            } catch (exeError) {
              debugPrint('[ServicesManager] Failed to launch main.exe: $exeError. Falling back to python script...');
            }
          }

          if (_pythonProcess == null && pythonScript != null) {
            debugPrint('[ServicesManager] Starting Python script: ${pythonScript.path} (cwd: $pythonWorkingDir)...');
            _pythonProcess = await Process.start(
              'python',
              ['-u', pythonScript.path, '--parent-pid', '$parentPid'],
              workingDirectory: pythonWorkingDir,
            );
          }

          _pythonProcess?.exitCode.then((code) {
            debugPrint('[ServicesManager] Python backend process terminated with exit code: $code');
            _pythonProcess = null;
          });

          if (_pythonProcess != null) {
            _pythonProcess!.stdout.transform(const SystemEncoding().decoder).listen((data) {
              debugPrint('[Python STDOUT] ${data.trim()}');
            });
            _pythonProcess!.stderr.transform(const SystemEncoding().decoder).listen((data) {
              debugPrint('[Python STDERR] ${data.trim()}');
            });
            debugPrint('[ServicesManager] Python server process spawned.');
          }
        }
      } catch (e) {
        debugPrint('[ServicesManager] Error starting Python server: $e');
      }
    } else {
      debugPrint('[ServicesManager] Python server is already active on port 5001.');
    }

    // 2. Start Node.js WhatsApp microservice if not already responding
    final nodeAlreadyReady = await isNodeReady(timeout: const Duration(milliseconds: 400));
    if (!nodeAlreadyReady) {
      File? nodeExe;
      File? nodeScript;
      String nodeWorkingDir = candidateDirs.isNotEmpty ? candidateDirs.first : Directory.current.path;

      for (final dir in candidateDirs) {
        final exe = File('$dir\\wa_service\\wa_service.exe');
        if (exe.existsSync() && nodeExe == null) {
          nodeExe = exe;
          nodeWorkingDir = '$dir\\wa_service';
        }
        final script = File('$dir\\wa_service\\index.js');
        if (script.existsSync() && nodeScript == null) {
          nodeScript = script;
          if (nodeExe == null) nodeWorkingDir = '$dir\\wa_service';
        }
      }

      try {
        if (_nodeProcess == null) {
          if (nodeExe != null) {
            debugPrint('[ServicesManager] Starting compiled Node.js WA microservice: ${nodeExe.path}...');
            _nodeProcess = await Process.start(
              nodeExe.path,
              ['--parent-pid=$parentPid'],
              workingDirectory: nodeWorkingDir,
            );
          } else if (nodeScript != null) {
            String runtimeNode = 'node';
            for (final dir in candidateDirs) {
              final localNode = File('$dir\\wa_service\\node.exe');
              if (localNode.existsSync()) {
                runtimeNode = localNode.path;
                break;
              }
            }

            debugPrint('[ServicesManager] Starting Node.js WA microservice with ($runtimeNode): ${nodeScript.path}...');
            _nodeProcess = await Process.start(
              runtimeNode,
              [nodeScript.path, '--parent-pid=$parentPid'],
              workingDirectory: nodeWorkingDir,
            );
          }

          _nodeProcess?.exitCode.then((code) {
            debugPrint('[ServicesManager] Node.js WA process terminated with exit code: $code');
            _nodeProcess = null;
          });

          if (_nodeProcess != null) {
            _nodeProcess!.stdout.transform(const SystemEncoding().decoder).listen((data) {
              debugPrint('[Node STDOUT] ${data.trim()}');
            });
            _nodeProcess!.stderr.transform(const SystemEncoding().decoder).listen((data) {
              debugPrint('[Node STDERR] ${data.trim()}');
            });
            debugPrint('[ServicesManager] Node.js WhatsApp microservice spawned.');
          }
        }
      } catch (e) {
        debugPrint('[ServicesManager] Error starting Node.js server: $e');
      }
    } else {
      debugPrint('[ServicesManager] Node.js WhatsApp service is already active on port 3000.');
    }

    _isStarting = false;
    startWatchdog();
  }

  Future<void> stopServices() async {
    debugPrint('[ServicesManager] Stopping background child services...');
    _watchdogTimer?.cancel();
    _watchdogTimer = null;

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
