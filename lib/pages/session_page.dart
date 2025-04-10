import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';

class SessionPage extends StatefulWidget {
  final Map<String, dynamic> sessionData;
  const SessionPage({Key? key, required this.sessionData}) : super(key: key);

  @override
  State<SessionPage> createState() => _SessionPageState();
}

class _SessionPageState extends State<SessionPage> with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FlutterBlePeripheral _blePeripheral = FlutterBlePeripheral();

  bool isScanning = false;
  List<String> detectedStudents = [];
  List<String> removedStudents = [];

  StreamSubscription<List<fbp.ScanResult>>? scanSubscription;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    )..repeat(reverse: true);
    _startScanning();
    _loadExistingAttendance(); // Load existing attendance if any
  }

  @override
  void dispose() {
    scanSubscription?.cancel();
    fbp.FlutterBluePlus.stopScan();
    _pulseController.dispose();
    super.dispose();
  }

  /// Load existing attendance for the current session
  Future<void> _loadExistingAttendance() async {
    try {
      DateTime now = DateTime.now();
      String dateString = "${now.year}-${now.month}-${now.day}";

      final existingAttendance = await _firestore
          .collection('attendance')
          .where('className', isEqualTo: widget.sessionData['className'])
          .where('subject', isEqualTo: widget.sessionData['subject'])
          .where('teacher', isEqualTo: widget.sessionData['teacher'])
          .where('date', isEqualTo: dateString)
          .limit(1)
          .get();

      if (existingAttendance.docs.isNotEmpty) {
        final attendanceData = existingAttendance.docs.first.data();
        setState(() {
          detectedStudents = List<String>.from(attendanceData['presentStudentIds'] ?? []);
        });
      }
    } catch (e) {
      debugPrint('Error loading existing attendance: $e');
    }
  }

  void _startScanning() {
    scanSubscription = fbp.FlutterBluePlus.scanResults.listen((results) {
      final students = results
          .where((result) => result.advertisementData.manufacturerData.containsKey(65535))
          .map((result) => utf8.decode(result.advertisementData.manufacturerData[65535]!))
          .toSet()
          .toList();

      final filteredStudents = students.where((rollNo) => !removedStudents.contains(rollNo)).toList();

      setState(() {
        detectedStudents = filteredStudents;
      });
    });
    fbp.FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
    setState(() {
      isScanning = true;
    });

    // Auto-set isScanning to false after the scan timeout
    Future.delayed(const Duration(seconds: 15), () {
      if (mounted) {
        setState(() {
          isScanning = false;
        });
      }
    });
  }

  Future<String> _fetchStudentName(String rollNo) async {
    try {
      final doc = await _firestore.collection('students').doc(rollNo).get();
      if (doc.exists && doc.data() != null && doc.data()!['name'] != null) {
        return doc.data()!['name'];
      }
    } catch (e) {
      debugPrint('Error fetching student name for $rollNo: $e');
    }
    return rollNo;
  }

  Future<List<String>> _filterStudentsByClass() async {
    List<String> validStudents = [];
    String sessionClass = widget.sessionData['className']?.toString().trim().toLowerCase() ?? "";
    for (String rollNo in detectedStudents) {
      try {
        final doc = await _firestore.collection('students').doc(rollNo).get();
        if (doc.exists && doc.data() != null) {
          String studentClass = doc.data()!['class']?.toString().trim().toLowerCase() ?? "";
          if (studentClass == sessionClass) {
            validStudents.add(rollNo);
          }
        }
      } catch (e) {
        debugPrint('Error filtering student $rollNo: $e');
      }
    }
    return validStudents;
  }

  Future<void> _submitAttendance() async {
    try {
      DateTime now = DateTime.now();
      String dateString = "${now.year}-${now.month}-${now.day}";

      // Check for existing attendance record
      final existingAttendance = await _firestore
          .collection('attendance')
          .where('className', isEqualTo: widget.sessionData['className'])
          .where('subject', isEqualTo: widget.sessionData['subject'])
          .where('teacher', isEqualTo: widget.sessionData['teacher'])
          .where('date', isEqualTo: dateString)
          .limit(1)
          .get();

      if (existingAttendance.docs.isNotEmpty) {
        // Update existing record
        await _firestore
            .collection('attendance')
            .doc(existingAttendance.docs.first.id)
            .update({
          'presentStudentIds': detectedStudents,
          'timestamp': FieldValue.serverTimestamp(),
        });
      } else {
        // Create new record
        await _firestore.collection('attendance').add({
          'className': widget.sessionData['className'],
          'subject': widget.sessionData['subject'],
          'teacher': widget.sessionData['teacher'],
          'date': dateString,
          'presentStudentIds': detectedStudents,
          'timestamp': FieldValue.serverTimestamp(),
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Attendance marked successfully")),
      );
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error marking attendance: $e")),
      );
    }
  }

  Future<void> _downloadAttendance() async {
    try {
      final validStudents = await _filterStudentsByClass();
      final Excel excel = Excel.createExcel();
      final Sheet sheet = excel['Attendance'];

      sheet.cell(CellIndex.indexByString('A1')).value = TextCellValue('S.No');
      sheet.cell(CellIndex.indexByString('B1')).value = TextCellValue('Roll Number');
      sheet.cell(CellIndex.indexByString('C1')).value = TextCellValue('Name');

      for (int i = 0; i < validStudents.length; i++) {
        final rollNo = validStudents[i];
        final studentName = await _fetchStudentName(rollNo);

        sheet.cell(CellIndex.indexByString('A${i + 2}')).value = IntCellValue(i + 1);
        sheet.cell(CellIndex.indexByString('B${i + 2}')).value = TextCellValue(rollNo);
        sheet.cell(CellIndex.indexByString('C${i + 2}')).value = TextCellValue(studentName);
      }

      Directory? downloadsDir;
      if (Platform.isAndroid) {
        downloadsDir = Directory('/storage/emulated/0/Download');
      } else if (Platform.isIOS) {
        final documentsDir = await getApplicationDocumentsDirectory();
        downloadsDir = Directory('${documentsDir.path}/Downloads');
      } else {
        throw UnsupportedError('Platform not supported for downloads');
      }

      if (!downloadsDir.existsSync()) {
        downloadsDir.createSync(recursive: true);
      }

      final String filename = 'Attendance_${widget.sessionData['subject']}_'
          '${widget.sessionData['className']}_'
          '${DateTime.now().toIso8601String().substring(0, 10)}.xlsx';

      final File file = File('${downloadsDir.path}/$filename');
      final List<int>? fileBytes = excel.save();
      if (fileBytes != null) {
        await file.writeAsBytes(fileBytes);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Attendance downloaded to: ${file.path}")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error downloading attendance: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mark Attendance'),
        backgroundColor: Colors.indigo,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                isScanning = true;
                detectedStudents.clear();
                removedStudents.clear();
              });
              _startScanning();
            },
            tooltip: 'Rescan Devices',
          ),
        ],
      ),
      body: Column(
        children: [
          // Header Section
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.indigo, Colors.indigo.shade700],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 5,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 25),
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  widget.sessionData['subject'],
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Class: ${widget.sessionData['className']}',
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.white,
                    fontWeight: FontWeight.w300,
                  ),
                ),
                const SizedBox(height: 5),
                Chip(
                  avatar: CircleAvatar(
                    backgroundColor: Colors.white,
                    child: Icon(
                      Icons.person,
                      size: 14,
                      color: Colors.indigo.shade700,
                    ),
                  ),
                  label: Text(
                    'Teacher: ${widget.sessionData['teacher'] ?? "Not specified"}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.indigo.shade700,
                    ),
                  ),
                  backgroundColor: Colors.white,
                ),
              ],
            ),
          ),

          // Scanning Status Indicator
          Container(
            color: isScanning ? Colors.amber.shade50 : Colors.green.shade50,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            child: Row(
              children: [
                if (isScanning)
                  FadeTransition(
                    opacity: _pulseController,
                    child: Icon(Icons.bluetooth_searching, color: Colors.amber.shade800),
                  )
                else
                  Icon(Icons.bluetooth_connected, color: Colors.green.shade800),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isScanning
                        ? "Scanning for student devices..."
                        : "Scan complete. Found ${detectedStudents.length} students.",
                    style: TextStyle(
                      color: isScanning ? Colors.amber.shade800 : Colors.green.shade800,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (isScanning)
                  Container(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.amber.shade800),
                    ),
                  ),
              ],
            ),
          ),

          // Students List
          Expanded(
            child: FutureBuilder<List<String>>(
              future: _filterStudentsByClass(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
                        const SizedBox(height: 16),
                        Text(
                          "Error: ${snapshot.error}",
                          style: TextStyle(color: Colors.red.shade700),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                }

                final validStudents = snapshot.data ?? [];
                if (validStudents.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.person_off, size: 64, color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        Text(
                          "No student devices detected",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "Tap the refresh button to scan again",
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return Container(
                  color: Colors.grey.shade50,
                  child: ListView.builder(
                    padding: const EdgeInsets.only(top: 8, bottom: 80),
                    itemCount: validStudents.length,
                    itemBuilder: (context, index) {
                      final rollNo = validStudents[index];
                      return Dismissible(
                        key: Key(rollNo),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          color: Colors.red.shade700,
                          padding: const EdgeInsets.only(right: 20),
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        onDismissed: (direction) {
                          setState(() {
                            removedStudents.add(rollNo);
                            detectedStudents.remove(rollNo);
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text("$rollNo removed"),
                              action: SnackBarAction(
                                label: 'UNDO',
                                onPressed: () {
                                  setState(() {
                                    removedStudents.remove(rollNo);
                                    detectedStudents.add(rollNo);
                                  });
                                },
                              ),
                            ),
                          );
                        },
                        child: Card(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            leading: Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [Colors.indigo.shade400, Colors.indigo.shade700],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: Center(
                                child: FutureBuilder<String>(
                                  future: _fetchStudentName(rollNo),
                                  builder: (context, snapshot) {
                                    return Text(
                                      snapshot.hasData ? snapshot.data![0].toUpperCase() : '?',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                            title: FutureBuilder<String>(
                              future: _fetchStudentName(rollNo),
                              builder: (context, snapshot) {
                                if (snapshot.connectionState == ConnectionState.waiting) {
                                  return const Text("Loading...");
                                }
                                if (snapshot.hasError) {
                                  return Text(rollNo);
                                }
                                return Text(
                                  snapshot.data ?? rollNo,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                );
                              },
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.credit_card,
                                    size: 16,
                                    color: Colors.grey.shade600,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    rollNo,
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            trailing: const Icon(
                              Icons.check_circle,
                              color: Colors.green,
                              size: 24,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),

      // Counter badge and action buttons
      floatingActionButton: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              spreadRadius: 1,
              blurRadius: 5,
            ),
          ],
        ),
        child: FutureBuilder<List<String>>(
          future: _filterStudentsByClass(),
          builder: (context, snapshot) {
            int count = snapshot.data?.length ?? 0;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.indigo.shade700,
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Students Present',
                  style: TextStyle(
                    color: Colors.grey.shade800,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            );
          },
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,

      // Bottom action bar
      bottomNavigationBar: Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: SafeArea(
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _submitAttendance,
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text("Submit"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _downloadAttendance,
                  icon: const Icon(Icons.download),
                  label: const Text("Download"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}