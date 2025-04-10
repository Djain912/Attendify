import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:device_info_plus/device_info_plus.dart';

class StudentLoginPage extends StatefulWidget {
  const StudentLoginPage({Key? key}) : super(key: key);

  @override
  State<StudentLoginPage> createState() => _StudentLoginPageState();
}

class _StudentLoginPageState extends State<StudentLoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _rollNoController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String _errorMessage = '';
  final _secureStorage = const FlutterSecureStorage();
  String? _studentEmail;
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  @override
  void initState() {
    super.initState();
    _checkSavedCredentials();
  }

  Future<void> _checkSavedCredentials() async {
    try {
      final savedRollNo = await _secureStorage.read(key: 'student_roll_no');
      if (savedRollNo != null) {
        _rollNoController.text = savedRollNo;
      }
    } catch (e) {
      debugPrint('Error reading saved credentials: $e');
    }
  }

  @override
  void dispose() {
    _rollNoController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<String> _getDeviceUniqueId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? deviceId = prefs.getString('device_unique_id');
      if (deviceId == null) {
        deviceId = const Uuid().v4();
        await prefs.setString('device_unique_id', deviceId);
      }

      String deviceFingerprint = deviceId;
      if (Theme.of(context).platform == TargetPlatform.android) {
        AndroidDeviceInfo androidInfo = await _deviceInfo.androidInfo;
        deviceFingerprint += androidInfo.id + androidInfo.model;
      } else if (Theme.of(context).platform == TargetPlatform.iOS) {
        IosDeviceInfo iosInfo = await _deviceInfo.iosInfo;
        deviceFingerprint += iosInfo.identifierForVendor ?? '';
      }

      return deviceFingerprint;
    } catch (e) {
      debugPrint('Error getting device fingerprint: $e');
      return const Uuid().v4();
    }
  }

  Future<void> _login() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
      });

      try {
        final rollNo = _rollNoController.text.trim();
        final password = _passwordController.text;
        final currentDeviceId = await _getDeviceUniqueId();

        // Get student data from Firestore
        final studentSnapshot = await FirebaseFirestore.instance
            .collection('students')
            .doc(rollNo)
            .get();

        if (!studentSnapshot.exists) {
          setState(() {
            _errorMessage = 'Student not found';
            _isLoading = false;
          });
          return;
        }

        final studentData = studentSnapshot.data();
        if (studentData == null) {
          setState(() {
            _errorMessage = 'Invalid student data';
            _isLoading = false;
          });
          return;
        }

        final email = studentData['email'] as String?;
        final storedDeviceId = studentData['device_id'] as String?;
        final isFirstLogin = studentData['first_login'] as bool? ?? true;

        if (email == null) {
          setState(() {
            _errorMessage = 'Student email not found';
            _isLoading = false;
          });
          return;
        }
        _studentEmail = email;

        // Enhanced device check
        if (!isFirstLogin) {
          if (storedDeviceId == null) {
            setState(() {
              _errorMessage = 'Device registration error - contact administrator';
              _isLoading = false;
            });
            return;
          }
          if (storedDeviceId != currentDeviceId) {
            setState(() {
              _errorMessage = 'This account can only be accessed from the registered device. Please contact administrator to reset device access.';
              _isLoading = false;
            });
            return;
          }
        }

        // Sign in with Firebase Auth
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );

        // Prepare updates
        final Map<String, dynamic> updates = {
          'last_login': FieldValue.serverTimestamp(),
          'updated_at': FieldValue.serverTimestamp(), // Add this for tracking
        };

        if (isFirstLogin) {
          updates.addAll({
            'device_id': currentDeviceId,
            'first_login': false,
            'device_registered_at': FieldValue.serverTimestamp(),
          });
        }

        // Update Firestore
        await FirebaseFirestore.instance
            .collection('students')
            .doc(rollNo)
            .update(updates);

        // Save credentials securely
        await _secureStorage.write(key: 'student_roll_no', value: rollNo);

        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('is_logged_in', true);

        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/student_home');
      } catch (e) {
        // ... error handling remains the same ...
      }
    }
  }

  Future<void> _sendPasswordResetEmail() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final rollNo = _rollNoController.text.trim();
      if (rollNo.isEmpty) {
        setState(() {
          _errorMessage = 'Please enter your roll number first';
          _isLoading = false;
        });
        return;
      }

      final studentDocRef =
      FirebaseFirestore.instance.collection('students').doc(rollNo);
      final studentSnapshot = await studentDocRef.get();

      if (!studentSnapshot.exists) {
        setState(() {
          _errorMessage = 'Student not found';
          _isLoading = false;
        });
        return;
      }

      final studentData = studentSnapshot.data()!;
      final email = studentData['email'] as String?;
      if (email == null) {
        setState(() {
          _errorMessage = 'Student email not found';
          _isLoading = false;
        });
        return;
      }

      int resetCount = studentData['password_reset_count'] as int? ?? 0;
      if (resetCount >= 2) {
        setState(() {
          _isLoading = false;
        });
        _showContactAdminDialog();
        return;
      }

      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);

      await studentDocRef.update({
        'password_reset_count': resetCount + 1,
        'last_password_reset': FieldValue.serverTimestamp(),
      });

      Fluttertoast.showToast(
        msg: "Password reset email sent to $email",
        toastLength: Toast.LENGTH_LONG,
        gravity: ToastGravity.BOTTOM,
        timeInSecForIosWeb: 3,
        backgroundColor: Colors.green,
        textColor: Colors.white,
        fontSize: 16.0,
      );

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        if (e is FirebaseAuthException) {
          _errorMessage = 'Error: ${e.message}';
        } else {
          _errorMessage = 'An error occurred: $e';
        }
      });
      Fluttertoast.showToast(
        msg: "Failed to send password reset email",
        toastLength: Toast.LENGTH_LONG,
        gravity: ToastGravity.BOTTOM,
        timeInSecForIosWeb: 3,
        backgroundColor: Colors.red,
        textColor: Colors.white,
        fontSize: 16.0,
      );
    }
  }

  void _showContactAdminDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Password Reset Limit Reached'),
        content: const Text(
            'You have reached the maximum number of password resets allowed. Please contact the administrator for assistance.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Fluttertoast.showToast(
                msg: "Contact admin at admin@school.edu",
                toastLength: Toast.LENGTH_LONG,
                gravity: ToastGravity.BOTTOM,
                timeInSecForIosWeb: 3,
                backgroundColor: Colors.blue,
                textColor: Colors.white,
                fontSize: 16.0,
              );
            },
            child: const Text('Contact Admin'),
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationCard(BuildContext context, String title, IconData icon,
      Color color, Widget page) {
    return GestureDetector(
      onTap: () {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => page),
        );
      },
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        elevation: 5,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            gradient: LinearGradient(
              colors: [color.withOpacity(0.7), color],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 40, color: Colors.white),
              const SizedBox(width: 15),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
              const Icon(Icons.arrow_forward_ios, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Student Login'),
        centerTitle: true,
        backgroundColor: Colors.blue.shade700,
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.blue.shade50, Colors.white],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircleAvatar(
                        radius: 50,
                        backgroundColor: Colors.blue,
                        child: Icon(
                          Icons.school,
                          size: 60,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Student Login',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(height: 32),
                      TextFormField(
                        controller: _rollNoController,
                        decoration: InputDecoration(
                          labelText: 'Roll Number',
                          hintText: 'Enter your roll number',
                          prefixIcon: const Icon(Icons.badge, color: Colors.blue),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.blue),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.blue, width: 2),
                          ),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter your roll number';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          hintText: 'Enter your password',
                          prefixIcon: const Icon(Icons.lock, color: Colors.blue),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.blue),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.blue, width: 2),
                          ),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter your password';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _isLoading ? null : _sendPasswordResetEmail,
                          child: const Text(
                            'Change Password',
                            style: TextStyle(
                              color: Colors.blue,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      if (_errorMessage.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.symmetric(vertical: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline, color: Colors.red),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMessage,
                                  style: TextStyle(color: Colors.red.shade700),
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _login,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade700,
                            foregroundColor: Colors.white,
                            elevation: 3,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: _isLoading
                              ? const CircularProgressIndicator(color: Colors.white)
                              : const Text(
                            'Login',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      TextButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                        },
                        icon: const Icon(Icons.arrow_back, size: 18),
                        label: const Text('Back to Role Selection'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.blue.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}