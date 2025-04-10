import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:fluttertoast/fluttertoast.dart';

class StudentPage extends StatefulWidget {
  const StudentPage({super.key});

  @override
  State<StudentPage> createState() => _StudentPageState();
}

class _StudentPageState extends State<StudentPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final TextEditingController nameController = TextEditingController();
  final TextEditingController rollNoController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  // Removed the random secure password generator in favor of our custom one.
  // Password will be generated automatically based on name and roll number.

  // Dropdown values
  String selectedYear = 'FE'; // Default value
  String selectedBatch = 'B1'; // Default value
  String? selectedClass; // Initially null
  List<String> classNames = []; // List of class names from Firestore
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchClassNames(); // Load class names from Firestore
    // Listen to changes in name and roll number to update the temporary password if needed.
    nameController.addListener(_updateTempPassword);
    rollNoController.addListener(_updateTempPassword);
  }

  @override
  void dispose() {
    _tabController.dispose();
    nameController.dispose();
    rollNoController.dispose();
    emailController.dispose();
    super.dispose();
  }

  /// Fetch class names from Firestore collection 'classes'
  Future<void> _fetchClassNames() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('classes').get();
      if (!mounted) return;
      final List<String> names = snapshot.docs
          .map((doc) => doc.data())
          .where((data) => data != null && data['name'] != null)
          .map((data) => data['name'] as String)
          .toList();
      setState(() {
        classNames = names;
        if (classNames.isNotEmpty) {
          selectedClass = classNames.first;
        }
      });
    } catch (e) {
      _showToast("Failed to fetch classes: ${e.toString()}", isError: true);
    }
  }

  /// Generate a temporary password using first two letters of first and last name (if available)
  /// concatenated with the last four digits of the roll number.
  String _generateTempPassword(String name, String rollNo) {
    if (name.trim().isEmpty || rollNo.length < 4) return "";
    List<String> parts = name.trim().split(" ");
    String initials;
    if (parts.length >= 2) {
      // Use first two letters from first and last name.
      initials = parts.first.substring(0, 2).toLowerCase() +
          parts.last.substring(0, 2).toLowerCase();
    } else {
      // If only one word is provided, repeat its first two letters.
      initials = name.substring(0, 2).toLowerCase() + name.substring(0, 2).toLowerCase();
    }
    String lastFour = rollNo.substring(rollNo.length - 4);
    return initials + lastFour;
  }

  /// Update the temporary password field if needed.
  void _updateTempPassword() {
    // We won't display the password in a controller; instead, the _addStudent method will generate it on the fly.
    // Optionally, you could update a read-only TextFormField with the generated password.
    // For example:
    // passwordController.text = _generateTempPassword(nameController.text, rollNoController.text);
  }

  /// Show toast messages.
  void _showToast(String message, {bool isError = false}) {
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      backgroundColor: isError ? Colors.red : Colors.green,
      textColor: Colors.white,
    );
  }

  /// Validate email format.
  bool _isValidEmail(String email) {
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    return emailRegex.hasMatch(email);
  }

  /// Add student details to Firebase Auth and Firestore.
  Future<void> _addStudent() async {
    setState(() {
      _isLoading = true;
    });

    String name = nameController.text.trim();
    String rollNo = rollNoController.text.trim();
    String email = emailController.text.trim();

    // Input validation.
    if (name.isEmpty || rollNo.isEmpty || email.isEmpty || selectedClass == null) {
      _showToast("Please fill all fields", isError: true);
      setState(() {
        _isLoading = false;
      });
      return;
    }
    if (!_isValidEmail(email)) {
      _showToast("Please enter a valid email address", isError: true);
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      // Check if the roll number already exists.
      final rollNoDoc = await FirebaseFirestore.instance
          .collection('students')
          .doc(rollNo)
          .get();
      if (rollNoDoc.exists) {
        _showToast("Roll number already exists", isError: true);
        setState(() {
          _isLoading = false;
        });
        return;
      }

      // Check if the email is already in use.
      final emailQuery = await FirebaseFirestore.instance
          .collection('students')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();
      if (emailQuery.docs.isNotEmpty) {
        _showToast("Email already in use", isError: true);
        setState(() {
          _isLoading = false;
        });
        return;
      }

      // Generate temporary password based on name and roll number.
      String password = _generateTempPassword(name, rollNo);
      if (password.isEmpty) {
        _showToast("Invalid name or roll number for generating password", isError: true);
        setState(() {
          _isLoading = false;
        });
        return;
      }

      final FirebaseAuth auth = FirebaseAuth.instance;
      final FirebaseFirestore firestore = FirebaseFirestore.instance;

      // Create the user in Firebase Auth.
      UserCredential userCredential = await auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Set display name for the user.
      await userCredential.user?.updateDisplayName(name);

      // Add user to Firestore.
      final studentRef = firestore.collection('students').doc(rollNo);
      Map<String, dynamic> studentData = {
        'uid': userCredential.user!.uid,
        'name': name,
        'roll_no': rollNo,
        'year': selectedYear,
        'batch': selectedBatch,
        'class': selectedClass,
        'email': email,
        'temp_password': password, // The generated temporary password.
        'password_changed': false,
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      };

      await studentRef.set(studentData);

      // Sign out to prevent staying logged in as the student.
      await auth.signOut();

      _showToast("Student Added: $name (Roll No: $rollNo)");

      // Clear fields after adding.
      nameController.clear();
      rollNoController.clear();
      emailController.clear();

      setState(() {
        selectedYear = 'FE';
        selectedBatch = 'B1';
        selectedClass = classNames.isNotEmpty ? classNames.first : null;
        _isLoading = false;
      });
    } catch (e) {
      String errorMessage = "Failed to add student";
      if (e is FirebaseAuthException) {
        switch (e.code) {
          case 'email-already-in-use':
            errorMessage = "Email already in use by another account";
            break;
          case 'invalid-email':
            errorMessage = "Invalid email format";
            break;
          default:
            errorMessage = "Authentication error: ${e.message}";
        }
      } else {
        errorMessage = "Error: ${e.toString()}";
      }
      _showToast(errorMessage, isError: true);
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Tab for Adding a Student.
  Widget _buildAddStudentTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Add Student", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 15),
          TextFormField(
            controller: nameController,
            decoration: const InputDecoration(
              labelText: 'Student Name',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 15),
          TextFormField(
            controller: rollNoController,
            decoration: const InputDecoration(
              labelText: 'Roll No',
              border: OutlineInputBorder(),
              helperText: 'This will be used as the student ID',
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 15),
          TextFormField(
            controller: emailController,
            decoration: const InputDecoration(
              labelText: 'Email',
              border: OutlineInputBorder(),
              helperText: 'Used for login and password recovery',
            ),
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 15),
          // Display generated password (read-only)
          TextFormField(
            controller: TextEditingController(text: _generateTempPassword(nameController.text, rollNoController.text)),
            decoration: const InputDecoration(
              labelText: 'Temporary Password',
              border: OutlineInputBorder(),
              helperText: 'Auto-generated: first 2 letters of first and last name + last 4 digits of roll no',
            ),
            readOnly: true,
          ),
          const SizedBox(height: 20),
          // Year Dropdown
          const Text("Select Year", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 5),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(5),
            ),
            child: DropdownButtonHideUnderline(
              child: ButtonTheme(
                alignedDropdown: true,
                child: DropdownButton<String>(
                  value: selectedYear,
                  isExpanded: true,
                  items: ['FE', 'SE', 'TE', 'BE'].map((year) {
                    return DropdownMenuItem(value: year, child: Text(year));
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      selectedYear = value!;
                    });
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Batch Dropdown
          const Text("Select Batch", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 5),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(5),
            ),
            child: DropdownButtonHideUnderline(
              child: ButtonTheme(
                alignedDropdown: true,
                child: DropdownButton<String>(
                  value: selectedBatch,
                  isExpanded: true,
                  items: ['B1', 'B2', 'B3'].map((batch) {
                    return DropdownMenuItem(value: batch, child: Text(batch));
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      selectedBatch = value!;
                    });
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Class Dropdown
          const Text("Select Class", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          classNames.isEmpty
              ? const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Text("Loading classes..."),
          )
              : Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 5),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(5),
            ),
            child: DropdownButtonHideUnderline(
              child: ButtonTheme(
                alignedDropdown: true,
                child: DropdownButton<String>(
                  value: selectedClass,
                  isExpanded: true,
                  items: classNames.map((className) {
                    return DropdownMenuItem(value: className, child: Text(className));
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      selectedClass = value!;
                    });
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 25),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _addStudent,
              style: ButtonStyle(
                backgroundColor: MaterialStateProperty.resolveWith<Color>(
                      (Set<MaterialState> states) {
                    if (states.contains(MaterialState.disabled)) {
                      return Colors.blue.withOpacity(0.5);
                    }
                    return Colors.blue;
                  },
                ),
              ),
              child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Add Student', style: TextStyle(fontSize: 16, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  /// Tab for Viewing Students.
  Widget _buildViewStudentsTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(10.0),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Search by name or roll number',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onChanged: (value) {
              // Implement search functionality here.
              setState(() {
                // This will trigger a rebuild with the filter.
              });
            },
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('students').snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const Center(child: Text("No students available."));
              }
              final students = snapshot.data!.docs;
              return ListView.builder(
                itemCount: students.length,
                itemBuilder: (context, index) {
                  try {
                    final studentData = students[index].data() as Map<String, dynamic>;
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    studentData['name'] ?? 'Unknown',
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Row(
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit, color: Colors.blue),
                                      onPressed: () {
                                        // Implement edit functionality
                                      },
                                      tooltip: 'Edit Student',
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete, color: Colors.red),
                                      onPressed: () {
                                        // Implement delete functionality with confirmation
                                      },
                                      tooltip: 'Delete Student',
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            Row(
                              children: [
                                const Icon(Icons.badge, size: 16, color: Colors.grey),
                                const SizedBox(width: 5),
                                Text("Roll No: ${studentData['roll_no'] ?? 'Unknown'}"),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                const Icon(Icons.school, size: 16, color: Colors.grey),
                                const SizedBox(width: 5),
                                Text("Year: ${studentData['year'] ?? 'Unknown'} | Batch: ${studentData['batch'] ?? 'Unknown'}"),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                const Icon(Icons.class_, size: 16, color: Colors.grey),
                                const SizedBox(width: 5),
                                Text("Class: ${studentData['class'] ?? 'Unknown'}"),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                const Icon(Icons.email, size: 16, color: Colors.grey),
                                const SizedBox(width: 5),
                                Text("Email: ${studentData['email'] ?? 'Unknown'}"),
                              ],
                            ),
                            if (studentData.containsKey('temp_password'))
                              Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Row(
                                  children: [
                                    const Icon(Icons.vpn_key, size: 16, color: Colors.orange),
                                    const SizedBox(width: 5),
                                    Text(
                                      "Temp Password: ${studentData['temp_password']}",
                                      style: const TextStyle(color: Colors.red),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  } catch (e) {
                    return Card(
                      color: Colors.red[100],
                      child: ListTile(
                        title: Text('Error loading student data: $e'),
                      ),
                    );
                  }
                },
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Manage Students"),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _fetchClassNames,
              tooltip: 'Refresh Classes',
            ),
          ],
          bottom: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: "Add Student"),
              Tab(text: "View Students"),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildAddStudentTab(),
            _buildViewStudentsTab(),
          ],
        ),
      ),
    );
  }
}
