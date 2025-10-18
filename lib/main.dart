import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:csv/csv.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DataLoggerApp());
}

class DataLoggerApp extends StatefulWidget {
  const DataLoggerApp({super.key});

  @override
  State<DataLoggerApp> createState() => _DataLoggerAppState();
}

class _DataLoggerAppState extends State<DataLoggerApp> {
  // --- State Variables ---
  bool _isRecording = false;
  String _currentLabel = 'normal';
  String? _savedFilePath;
  StreamSubscription? _accelerometerSubscription;
  int _rowCount = 0;
  IOSink? _fileSink; 
  File? _currentFile;
  Timer? _uiUpdateTimer; 

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }
  
  Future<void> _requestPermissions() async {
    var status = await Permission.storage.status;
    if (status.isPermanentlyDenied) {
      _showPermissionDialog();
    } else if (!status.isGranted) {
      await Permission.storage.request();
    }
  }

  void _showPermissionDialog() {
    // This check ensures we don't try to show a dialog if the widget is no longer on screen.
    if(mounted) {
      showDialog(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: const Text('Permission Required'),
          content: const Text('This app needs storage access to save data files. Please grant the permission in app settings.'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: const Text('Open Settings'),
              onPressed: () {
                openAppSettings();
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
      );
    }
  }

  // --- Core Logic ---
  Future<void> _startRecording() async {
    var status = await Permission.storage.status;
    if (!status.isGranted) {
      _requestPermissions(); 
      return;
    }

    setState(() {
      _isRecording = true;
      _savedFilePath = null;
      _rowCount = 0;
    });

    try {
      final directory = await getExternalStorageDirectory();
      final path = "${directory?.path}/pothole_data_${DateTime.now().millisecondsSinceEpoch}.csv";
      _currentFile = File(path);
      _fileSink = _currentFile?.openWrite(mode: FileMode.append);

      final header = const ListToCsvConverter().convert([
        ['timestamp', 'acc_x', 'acc_y', 'acc_z', 'label']
      ]);
      _fileSink?.writeln(header.trim());

      _accelerometerSubscription = accelerometerEventStream(
        samplingPeriod: SensorInterval.gameInterval)
          .listen((AccelerometerEvent event) {
        if (!_isRecording) return;
        
        final List<dynamic> row = [
          DateTime.now().millisecondsSinceEpoch,
          event.x, event.y, event.z, _currentLabel
        ];
        
        // FINAL POLISH: Use writeln and trim() for consistent data formatting.
        final csvRow = const ListToCsvConverter().convert([row]);
        _fileSink?.writeln(csvRow.trim());
        
        _rowCount++;

        if (_currentLabel != 'normal') {
          _currentLabel = 'normal';
        }
      });

      _uiUpdateTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if(mounted) {
          setState(() {}); 
        }
      });

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error starting recording: ${e.toString()}')),
        );
        setState(() { _isRecording = false; });
      }
    }
  }

  Future<void> _stopRecording() async {
    _uiUpdateTimer?.cancel();
    await _accelerometerSubscription?.cancel();
    await _fileSink?.flush();
    await _fileSink?.close();

    if (mounted) {
      setState(() {
        _isRecording = false;
        _savedFilePath = _currentFile?.path;
        _fileSink = null;
        _currentFile = null;
      });
    }
  }

  void _tagEvent(String label) {
    if (!_isRecording) return;
    _currentLabel = label;
  }

  // --- UI Build Method ---
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Sensor Data Logger'),
          backgroundColor: Colors.blueGrey[800],
        ),
        backgroundColor: Colors.blueGrey[900],
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                _isRecording ? 'RECORDING...' : 'Ready to Record',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: _isRecording ? Colors.redAccent : Colors.greenAccent,
                ),
              ),
              if (_isRecording)
                Text(
                  '$_rowCount rows collected',
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                icon: Icon(_isRecording ? Icons.stop_circle : Icons.play_circle_fill, size: 30),
                label: Text(_isRecording ? 'Stop Recording' : 'Start Recording',
                    style: const TextStyle(fontSize: 22)),
                onPressed: _isRecording ? _stopRecording : _startRecording,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isRecording ? Colors.red : Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                ),
              ),
              const SizedBox(height: 60),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildTagButton('Pothole', Colors.orange, _tagEvent),
                  _buildTagButton('Speed Bump', Colors.blueAccent, _tagEvent),
                ],
              ),
              const SizedBox(height: 40),
              if (_savedFilePath != null) ...[
                const Text('Last file saved to:',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white70)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Text(_savedFilePath!,
                      textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
                ),
              ]
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTagButton(String label, Color color, Function(String) onPressed) {
    return ElevatedButton(
      onPressed: () => onPressed(label.toLowerCase().replaceAll(' ', '_')),
      style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          fixedSize: const Size(160, 90),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          elevation: 5,
      ),
      child: Text(label, style: const TextStyle(fontSize: 20)),
    );
  }

  @override
  void dispose() {
    _uiUpdateTimer?.cancel();
    _accelerometerSubscription?.cancel();
    _fileSink?.close();
    super.dispose();
  }
}

