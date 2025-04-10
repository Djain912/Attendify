import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'dart:convert';

class StudentScreen extends StatefulWidget {
  const StudentScreen({super.key});

  @override
  _StudentScreenState createState() => _StudentScreenState();
}

class _StudentScreenState extends State<StudentScreen> {
  String studentId = '';
  bool isAdvertising = false;
  final fbp.Guid attendanceServiceUuid = fbp.Guid("a1b2c3d4-e5f6-7890-abcd-ef1234567890");
  final FlutterBlePeripheral _blePeripheral = FlutterBlePeripheral();

  Future<void> startAdvertising() async {
    if (studentId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a student ID')),
      );
      return;
    }
    try {
      final isBluetoothOn = await fbp.FlutterBluePlus.isOn;
      if (!isBluetoothOn) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enable Bluetooth')),
        );
        return;
      }
      final manufacturerDataBytes = utf8.encode(studentId);
      final advertiseData = AdvertiseData(
        serviceUuid: attendanceServiceUuid.toString(),
        manufacturerId: 65535,
        manufacturerData: manufacturerDataBytes,
        localName: 'Student_$studentId',
        includeDeviceName: false,
        includePowerLevel: false,
      );
      final advertiseSettings = AdvertiseSettings(
        advertiseMode: AdvertiseMode.advertiseModeBalanced,
        connectable: false,
        timeout: 0,
      );
      await _blePeripheral.start(
        advertiseData: advertiseData,
        advertiseSettings: advertiseSettings,
      );
      if (mounted) setState(() => isAdvertising = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> stopAdvertising() async {
    try {
      await _blePeripheral.stop();
      if (mounted) setState(() => isAdvertising = false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Student Attendance')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              onChanged: (value) => setState(() => studentId = value),
              decoration: InputDecoration(
                labelText: 'Student ID',
                prefixIcon: const Icon(Icons.badge, color: Colors.blue),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.grey[100],
              ),
            ),
            const SizedBox(height: 20),
            _buildButton(
              text: 'Start Advertising',
              onPressed: isAdvertising ? null : () async => await startAdvertising(),
              gradient: const LinearGradient(colors: [Colors.green, Colors.lightGreen]),
            ),
            const SizedBox(height: 10),
            if (isAdvertising)
              _buildButton(
                text: 'Stop Advertising',
                onPressed: () async => await stopAdvertising(),
                gradient: const LinearGradient(colors: [Colors.red, Colors.orange]),
              ),
            const SizedBox(height: 20),
            if (isAdvertising)
              AnimatedContainer(
                duration: const Duration(milliseconds: 800),
                curve: Curves.easeInOut,
                width: isAdvertising ? 20 : 10,
                height: isAdvertising ? 20 : 10,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.green,
                ),
              ),
            if (isAdvertising)
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.wifi_tethering, color: Colors.green),
                    const SizedBox(width: 8),
                    Text(
                      'Advertising as present...',
                      style: TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildButton({
    required String text,
    required VoidCallback? onPressed,
    required LinearGradient gradient,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
        child: Text(text, style: const TextStyle(color: Colors.white)),
      ),
    );
  }
}