import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
// Import your role selection page and teacher home page widgets
import 'package:attendence/main.dart'; // For navigation back to HomeScreen if needed.
import 'package:attendence/pages/teacher_home.dart';

class TeacherLoginPage extends StatefulWidget {
  const TeacherLoginPage({Key? key}) : super(key: key);

  @override
  State<TeacherLoginPage> createState() => _TeacherLoginPageState();
}

class _TeacherLoginPageState extends State<TeacherLoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _teacherIdController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String _errorMessage = '';
  final _secureStorage = const FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    _checkLoginState();
  }

  /// Checks if a teacher is already logged in by reading secure storage and SharedPreferences.
  Future<void> _checkLoginState() async {
    try {
      // Read the saved teacher id from secure storage.
      final savedTeacherId = await _secureStorage.read(key: 'teacher_id');
      if (savedTeacherId != null) {
        // Also check a boolean flag from SharedPreferences.
        final prefs = await SharedPreferences.getInstance();
        final isLoggedIn = prefs.getBool('is_logged_in_teacher') ?? false;
        if (isLoggedIn) {
          // If already logged in, navigate directly to the TeacherHomePage.
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const TeacherHomePage()),
            );
          }
        } else {
          // Pre-fill the teacher ID for convenience.
          _teacherIdController.text = savedTeacherId;
        }
      }
    } catch (e) {
      debugPrint('Error checking saved login state: $e');
    }
  }

  @override
  void dispose() {
    _teacherIdController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
      });

      try {
        final teacherId = _teacherIdController.text.trim();
        final password = _passwordController.text;

        // Fetch teacher document from Firestore using teacher ID.
        final teacherSnapshot = await FirebaseFirestore.instance
            .collection('teachers')
            .doc(teacherId)
            .get();

        if (!teacherSnapshot.exists) {
          setState(() {
            _errorMessage = 'Teacher not found';
            _isLoading = false;
          });
          return;
        }

        final teacherData = teacherSnapshot.data();
        if (teacherData == null) {
          setState(() {
            _errorMessage = 'Invalid teacher data';
            _isLoading = false;
          });
          return;
        }

        final email = teacherData['email'] as String?;
        if (email == null) {
          setState(() {
            _errorMessage = 'Teacher email not found';
            _isLoading = false;
          });
          return;
        }

        // Sign in using Firebase Authentication.
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );

        // Generate a unique device identifier.
        final deviceId = await _getOrCreateDeviceId();

        // Update the teacher document with the device identifier and last login timestamp.
        await FirebaseFirestore.instance.collection('teachers').doc(teacherId).update({
          'device_id': deviceId,
          'last_login': FieldValue.serverTimestamp(),
        });

        // Save teacher ID securely.
        await _secureStorage.write(key: 'teacher_id', value: teacherId);

        // Save login state in SharedPreferences.
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('is_logged_in_teacher', true);

        if (!mounted) return;

        // Navigate to the teacher home page.
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const TeacherHomePage()),
        );
      } catch (e) {
        setState(() {
          _isLoading = false;
          if (e is FirebaseAuthException) {
            switch (e.code) {
              case 'user-not-found':
                _errorMessage = 'No user found with this email.';
                break;
              case 'wrong-password':
                _errorMessage = 'Invalid password.';
                break;
              case 'invalid-credential':
                _errorMessage = 'Invalid credentials provided.';
                break;
              default:
                _errorMessage = 'Authentication failed: ${e.message}';
            }
          } else {
            _errorMessage = 'An error occurred: $e';
          }
        });
      }
    }
  }

  Future<String> _getOrCreateDeviceId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? deviceId = prefs.getString('teacher_device_id');
      if (deviceId == null) {
        deviceId = const Uuid().v4();
        await prefs.setString('teacher_device_id', deviceId);
      }
      return deviceId;
    } catch (e) {
      debugPrint('Error getting/creating device ID: $e');
      return const Uuid().v4();
    }
  }

  /// Helper method to build a navigation card widget.
  Widget _buildNavigationCard(
      BuildContext context, String title, IconData icon, Color color, Widget page) {
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
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
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
        title: const Text('Teacher Login'),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.person,
                  size: 80,
                  color: Colors.green,
                ),
                const SizedBox(height: 20),
                const Text(
                  'Teacher Login',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 30),
                TextFormField(
                  controller: _teacherIdController,
                  decoration: InputDecoration(
                    labelText: 'Teacher ID',
                    prefixIcon: const Icon(Icons.badge),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your Teacher ID';
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
                    prefixIcon: const Icon(Icons.lock),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your password';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                if (_errorMessage.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      _errorMessage,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _login,
                    style: ButtonStyle(
                      backgroundColor: MaterialStateProperty.resolveWith<Color>(
                            (Set<MaterialState> states) {
                          if (states.contains(MaterialState.disabled)) {
                            return Colors.green.withOpacity(0.5);
                          }
                          return Colors.green;
                        },
                      ),
                      shape: MaterialStateProperty.all<RoundedRectangleBorder>(
                        RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                      'Login',
                      style: TextStyle(fontSize: 18, color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                // Navigation card to go back to Role Selection page.
                _buildNavigationCard(
                  context,
                  "Back to Role Selection",
                  Icons.arrow_back,
                  Colors.grey,
                  const MyApp(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
