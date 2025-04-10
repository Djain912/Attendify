import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class DeviceIdChangePage extends StatefulWidget {
  const DeviceIdChangePage({super.key});

  @override
  State<DeviceIdChangePage> createState() => _DeviceIdChangePageState();
}

class _DeviceIdChangePageState extends State<DeviceIdChangePage> {
  final TextEditingController _studentIdController = TextEditingController();
  bool isProcessing = false;
  String statusMessage = "";

  Future<void> _resetFirstLogin() async {
    final studentId = _studentIdController.text.trim();

    if (studentId.isEmpty) {
      setState(() {
        statusMessage = "Please enter a valid Student ID.";
      });
      return;
    }

    setState(() {
      isProcessing = true;
      statusMessage = "";
    });

    try {
      final docRef = FirebaseFirestore.instance.collection('students').doc(studentId);

      final docSnapshot = await docRef.get();
      if (!docSnapshot.exists) {
        setState(() {
          statusMessage = "Student ID not found.";
          isProcessing = false;
        });
        return;
      }

      // Update Firestore fields
      await docRef.update({
        'first_login': true,
        'device_id': null,
        'device_registered_at': null,
        'updated_at': FieldValue.serverTimestamp(),
      });

      setState(() {
        statusMessage = "✅ Successfully reset device access for student ID: $studentId";
      });
    } catch (e) {
      setState(() {
        statusMessage = "❌ Error: Could not update. ${e.toString()}";
      });
    } finally {
      setState(() {
        isProcessing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Reset Student Device Access")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Text(
              "Enter the Student ID (roll no) to allow login from a new device.",
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _studentIdController,
              decoration: const InputDecoration(
                labelText: "Student Roll No",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: isProcessing ? null : _resetFirstLogin,
              icon: const Icon(Icons.refresh),
              label: const Text("Reset First Login"),
            ),
            const SizedBox(height: 20),
            Text(
              statusMessage,
              style: TextStyle(
                color: statusMessage.contains("✅") ? Colors.green : Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
