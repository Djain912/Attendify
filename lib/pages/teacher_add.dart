import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fluttertoast/fluttertoast.dart';

class TeacherPage extends StatefulWidget {
  const TeacherPage({super.key});

  @override
  State<TeacherPage> createState() => _TeacherPageState();
}

class _TeacherPageState extends State<TeacherPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final TextEditingController nameController = TextEditingController();
  final TextEditingController teacherIdController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController searchController = TextEditingController();

  bool _isLoading = false;
  List<String> classNames = []; // List of class names from Firestore
  List<String> selectedClasses = []; // Classes assigned to this teacher
  String searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchClassNames(); // Load class names from Firestore

    // Listen for tab changes to clear search when switching tabs
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        searchController.clear();
        setState(() {
          searchQuery = '';
        });
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    nameController.dispose();
    teacherIdController.dispose();
    emailController.dispose();
    searchController.dispose();
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
      });
    } catch (e) {
      _showToast("Failed to fetch classes: ${e.toString()}", isError: true);
    }
  }

  /// Generate a temporary password based on teacher id and the first four initials of the teacher's name.
  /// If name length is less than 4, use the whole name.
  String _generateTempPassword(String teacherId, String name) {
    String trimmedName = name.trim();
    String initials = "";
    if (trimmedName.isNotEmpty) {
      // Remove extra spaces and get first four letters.
      initials = trimmedName.replaceAll(RegExp(r'\s+'), '');
      if (initials.length > 4) {
        initials = initials.substring(0, 4);
      }
    }
    return teacherId + initials;
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

  /// Add teacher details to Firebase Auth and Firestore.
  Future<void> _addTeacher() async {
    setState(() {
      _isLoading = true;
    });

    String name = nameController.text.trim();
    String teacherId = teacherIdController.text.trim();
    String email = emailController.text.trim();

    // Input validation.
    if (name.isEmpty || teacherId.isEmpty || email.isEmpty) {
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
    if (selectedClasses.isEmpty) {
      _showToast("Please assign at least one class", isError: true);
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      // Check if the teacher ID already exists.
      final teacherIdDoc = await FirebaseFirestore.instance
          .collection('teachers')
          .doc(teacherId)
          .get();
      if (teacherIdDoc.exists) {
        _showToast("Teacher ID already exists", isError: true);
        setState(() {
          _isLoading = false;
        });
        return;
      }

      // Check if the email is already in use.
      final emailQuery = await FirebaseFirestore.instance
          .collection('teachers')
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

      // Generate a temporary password using teacherId and first 4 letters of name.
      String password = _generateTempPassword(teacherId, name);

      final FirebaseAuth auth = FirebaseAuth.instance;
      final FirebaseFirestore firestore = FirebaseFirestore.instance;

      // Create the user in Firebase Auth.
      UserCredential userCredential = await auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Set display name for the user.
      await userCredential.user?.updateDisplayName(name);

      // Add teacher to Firestore.
      final teacherRef = firestore.collection('teachers').doc(teacherId);

      Map<String, dynamic> teacherData = {
        'uid': userCredential.user!.uid,
        'name': name,
        'teacher_id': teacherId,
        'email': email,
        // Removed subject field.
        'temp_password': password, // Mark as temporary.
        'password_changed': false,
        'assigned_classes': selectedClasses,
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      };

      await teacherRef.set(teacherData);

      // Sign out to prevent staying logged in as the teacher.
      await auth.signOut();

      _showToast("Teacher Added: $name (ID: $teacherId)");

      // Clear fields after adding.
      nameController.clear();
      teacherIdController.clear();
      emailController.clear();

      setState(() {
        selectedClasses = [];
        _isLoading = false;
      });
    } catch (e) {
      String errorMessage = "Failed to add teacher";
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

  /// Tab for Adding a Teacher.
  Widget _buildAddTeacherTab() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.grey.shade50, Colors.grey.shade100],
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Card(
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.person_add, size: 28, color: Colors.indigo),
                    SizedBox(width: 10),
                    Text(
                      "Add New Teacher",
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 20),
                // Teacher Details Section
                Text(
                  "TEACHER DETAILS",
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade700,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 15),
                TextFormField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: 'Teacher Name',
                    hintText: 'Enter full name',
                    prefixIcon: const Icon(Icons.person_outline, color: Colors.indigo),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Colors.indigo),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Colors.indigo, width: 2),
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 15),
                TextFormField(
                  controller: teacherIdController,
                  decoration: InputDecoration(
                    labelText: 'Teacher ID',
                    hintText: 'Unique identifier',
                    prefixIcon: const Icon(Icons.badge_outlined, color: Colors.indigo),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Colors.indigo),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Colors.indigo, width: 2),
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    helperText: 'This will be used for login',
                    helperStyle: TextStyle(color: Colors.grey.shade600),
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 15),
                TextFormField(
                  controller: emailController,
                  decoration: InputDecoration(
                    labelText: 'Email Address',
                    hintText: 'example@school.com',
                    prefixIcon: const Icon(Icons.email_outlined, color: Colors.indigo),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Colors.indigo),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Colors.indigo, width: 2),
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    helperText: 'Used for login and password recovery',
                    helperStyle: TextStyle(color: Colors.grey.shade600),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 25),
                // Classes Assignment Section
                Row(
                  children: [
                    Icon(Icons.class_, color: Colors.grey.shade700),
                    const SizedBox(width: 10),
                    Text(
                      "ASSIGN CLASSES",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade700,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                classNames.isEmpty
                    ? Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: const Center(
                    child: Column(
                      children: [
                        CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.indigo),
                          strokeWidth: 3,
                        ),
                        SizedBox(height: 10),
                        Text(
                          "Loading available classes...",
                          style: TextStyle(color: Colors.indigo),
                        ),
                      ],
                    ),
                  ),
                )
                    : Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          "Select classes to assign to this teacher:",
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                      Column(
                        children: classNames.map((className) {
                          return CheckboxListTile(
                            title: Text(
                              className,
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            value: selectedClasses.contains(className),
                            activeColor: Colors.indigo,
                            checkColor: Colors.white,
                            onChanged: (bool? value) {
                              setState(() {
                                if (value == true) {
                                  if (!selectedClasses.contains(className)) {
                                    selectedClasses.add(className);
                                  }
                                } else {
                                  selectedClasses.remove(className);
                                }
                              });
                            },
                            secondary: CircleAvatar(
                              backgroundColor: Colors.indigo.withOpacity(0.1),
                              child: Text(
                                className.isNotEmpty ? className[0].toUpperCase() : "C",
                                style: const TextStyle(
                                  color: Colors.indigo,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _addTeacher,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                    child: _isLoading
                        ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        ),
                        SizedBox(width: 16),
                        Text(
                          'Adding Teacher...',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    )
                        : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.person_add, size: 20),
                        SizedBox(width: 10),
                        Text(
                          'Add Teacher',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Tab for Viewing Teachers with filtering capabilities.
  Widget _buildViewTeachersTab() {
    return Column(
        children: [
    Container(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
    decoration: BoxDecoration(
    color: Colors.white,
    boxShadow: [
    BoxShadow(
    color: Colors.black.withOpacity(0.05),
    blurRadius: 5,
    offset: const Offset(0, 3),
    ),
    ],
    ),
    child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
    const Text(
    "TEACHERS DIRECTORY",
    style: TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.bold,
    color: Colors.indigo,
    letterSpacing: 1.2,
    ),
    ),
    const SizedBox(height: 12),
    TextField(
    controller: searchController,
    decoration: InputDecoration(
    hintText: 'Search by name or ID',
    hintStyle: TextStyle(color: Colors.grey.shade400),
    prefixIcon: Icon(Icons.search, color: Colors.grey.shade600),
    suffixIcon: searchQuery.isNotEmpty
    ? IconButton(
    icon: Icon(Icons.clear, color: Colors.grey.shade600),
    onPressed: () {
    searchController.clear();
    setState(() {
    searchQuery = '';
    });
    },
    )
        : null,
    filled: true,
    fillColor: Colors.grey.shade100,
    border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide.none,
    ),
    contentPadding: const EdgeInsets.symmetric(vertical: 12),
    ),
    onChanged: (value) {
    setState(() {
    searchQuery = value.toLowerCase();
    });
    },
    ),
    ],
    ),
    ),
    Expanded(
    child: StreamBuilder<QuerySnapshot>(
    stream: FirebaseFirestore.instance.collection('teachers').snapshots(),
    builder: (context, snapshot) {
    if (snapshot.connectionState == ConnectionState.waiting) {
    return const Center(
    child: CircularProgressIndicator(
    valueColor: AlwaysStoppedAnimation<Color>(Colors.indigo),
    ),
    );
    }
    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
    return Center(
    child: Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
    Icon(
    Icons.person_off,
    size: 64,
    color: Colors.grey.shade400,
    ),
    const SizedBox(height: 16),
    Text(
    "No teachers available",
    style: TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w500,
    color: Colors.grey.shade600,
    ),
    ),
    const SizedBox(height: 8),
    Text(
    "Add teachers using the 'Add Teacher' tab",
    style: TextStyle(
    fontSize: 14,
    color: Colors.grey.shade500,
    ),
    ),
    ],
    ),
    );
    }

    final teachers = snapshot.data!.docs;
    final filteredTeachers = teachers.where((doc) {
    if (searchQuery.isEmpty) return true;

    try {
    final data = doc.data() as Map<String, dynamic>;
    final name = (data['name'] ?? '').toString().toLowerCase();
    final id = (data['teacher_id'] ?? '').toString().toLowerCase();

    return name.contains(searchQuery) || id.contains(searchQuery);
    } catch (e) {
    return false;
    }
    }).toList();

    if (filteredTeachers.isEmpty) {
    return Center(
    child: Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
    Icon(
    Icons.search_off,
    size: 64,
    color: Colors.grey.shade400,
    ),
    const SizedBox(height: 16),
    Text(
    "No results found",
    style: TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w500,
    color: Colors.grey.shade600,
    ),
    ),
    const SizedBox(height: 8),
    Text(
    "Try a different search term",
    style: TextStyle(
    fontSize: 14,
    color: Colors.grey.shade500,
    ),
    ),
    ],
    ),
    );
    }

    return ListView.builder(
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
    itemCount: filteredTeachers.length,
    itemBuilder: (context, index) {
    try {
    final teacherData = filteredTeachers[index].data() as Map<String, dynamic>;
    final String teacherName = teacherData['name'] ?? 'Unknown';
    final bool hasTemporaryPassword = teacherData.containsKey('temp_password') &&
    !teacherData['password_changed'];
    final List<String> assignedClasses =
    List<String>.from(teacherData['assigned_classes'] as List<dynamic>? ?? []);

    return Card(
    margin: const EdgeInsets.only(bottom: 12),
    elevation: 2,
    shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
    // Header with avatar and actions
    Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
    color: Colors.indigo.shade50,
    borderRadius: const BorderRadius.only(
    topLeft: Radius.circular(12),
    topRight: Radius.circular(12),
    ),
    ),
    child: Row(
    children: [
    CircleAvatar(
    radius: 24,
    backgroundColor: Colors.indigo.shade100,
    child: Text(
    teacherName.isNotEmpty ? teacherName[0].toUpperCase() : "?",
    style: const TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.bold,
    color: Colors.indigo,
    ),
    ),
    ),
    const SizedBox(width: 16),
    Expanded(
    child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
    Text(
    teacherName,
    style: const TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.bold,
    ),
    overflow: TextOverflow.ellipsis,
    ),
    Row(
    children: [
    Icon(
    Icons.badge_outlined,
    size: 14,
    color: Colors.grey.shade700,
    ),
    const SizedBox(width: 4),
    Text(
    teacherData['teacher_id'] ?? 'Unknown ID',
    style: TextStyle(
    fontSize: 14,
    color: Colors.grey.shade700,
    ),
    ),
    ],
    ),
    ],
    ),
    ),
    Row(
    children: [
    IconButton(
    icon: const Icon(Icons.edit, color: Colors.indigo),
    onPressed: () {
    // Implement edit functionality.
    },
    tooltip: 'Edit Teacher',
    style: IconButton.styleFrom(
    backgroundColor: Colors.indigo.withOpacity(0.1),
    ),
    ),
    const SizedBox(width: 8),
    IconButton(
    icon: const Icon(Icons.delete, color: Colors.red),
    onPressed: () {
    // Implement delete functionality with confirmation.
    },
    tooltip: 'Delete Teacher',
    style: IconButton.styleFrom(
    backgroundColor: Colors.red.withOpacity(0.1),
    ),
    ),
    ],
    ),
    ],
    ),
    ),
    // Details
    Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
    // Email
    Row(
    children: [
    Container(
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
    color: Colors.blue.shade50,
    borderRadius: BorderRadius.circular(8),
    ),
    child: Icon(
    Icons.email_outlined,
    size: 20,
    color: Colors.blue.shade700,
    ),
    ),
    const SizedBox(width: 12),
    Expanded(
    child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
    Text(
    "Email Address",
    style: TextStyle(
    fontSize: 12,
    color: Colors.grey.shade600,
    ),
    ),
    Text(
    teacherData['email'] ?? 'Not specified',
    style: const TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w500,
    ),
    ),
    ],
    ),
    ),
    ],
    ),
    const SizedBox(height: 16),
    // Classes
    Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
    Container(
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
    color: Colors.purple.shade50,
    borderRadius: BorderRadius.circular(8),
    ),
    child: Icon(
    Icons.class_outlined,
    size: 20,
    color: Colors.purple.shade700,
    ),
    ),
    const SizedBox(width: 12),
    Expanded(
    child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
    Text(
    "Assigned Classes",
    style: TextStyle(
    fontSize: 12,
    color: Colors.grey.shade600,
    ),
    ),
    const SizedBox(height: 4),
    assignedClasses.isEmpty
    ? Text(
    "No classes assigned",
    style: TextStyle(
    fontStyle: FontStyle.italic,
    color: Colors.grey.shade500,
    ),
    )
        : Wrap(
    spacing: 8,
    runSpacing: 8,
    children: assignedClasses.map((className) {
    return Container(
    padding: const EdgeInsets.symmetric(
    horizontal: 10,
    vertical: 6,
    ),
    decoration: BoxDecoration(
    color: Colors.purple.shade100,
    borderRadius: BorderRadius.circular(30),
    ),
    child: Text(
    className,
    style: TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: Colors.purple.shade800,
    ),
    ),
    );
    }).toList(),
    ),
    ],
    ),
    ),
    ],
    ),
    if (hasTemporaryPassword) ...[
    const SizedBox(height: 16),
    // Temporary Password
    Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
    color: Colors.amber.shade50,
    borderRadius: BorderRadius.circular(8),
    border: Border.all(color: Colors.amber.shade200),
    ),
    child: Row(
    children: [
    Container(
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
    color: Colors.amber.shade100,
    borderRadius: BorderRadius.circular(8),
    ),
    child: Icon(
    Icons.vpn_key_outlined,
    size: 20,
    color: Colors.amber.shade800,
    ),
    ),
    const SizedBox(width: 12),
    Expanded(
    child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [Text(
      "Temporary Password",
      style: TextStyle(
        fontSize: 12,
        color: Colors.grey.shade600,
      ),
    ),
      Row(
        children: [
          Text(
            teacherData['temp_password'] ?? 'Unknown',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: "Password not yet changed by teacher",
            child: Icon(
              Icons.info_outline,
              size: 16,
              color: Colors.amber.shade700,
            ),
          ),
        ],
      ),
    ],
    ),
    ),
    ],
    ),
    ),
    ],
      const SizedBox(height: 16),
      // Account Status
      Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.verified_user_outlined,
              size: 20,
              color: Colors.green.shade700,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Account Status",
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: hasTemporaryPassword
                            ? Colors.amber.shade100
                            : Colors.green.shade100,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            hasTemporaryPassword
                                ? Icons.hourglass_bottom_outlined
                                : Icons.check_circle_outline,
                            size: 14,
                            color: hasTemporaryPassword
                                ? Colors.amber.shade800
                                : Colors.green.shade800,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            hasTemporaryPassword
                                ? "Awaiting First Login"
                                : "Account Active",
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: hasTemporaryPassword
                                  ? Colors.amber.shade800
                                  : Colors.green.shade800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ],
    ),
    ),
    ],
    ),
    );
    } catch (e) {
      // Handle any errors when displaying teacher data
      return Card(
        margin: const EdgeInsets.only(bottom: 12),
        color: Colors.red.shade50,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Icon(Icons.error_outline, color: Colors.red.shade700),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  "Error displaying teacher data: ${e.toString()}",
                  style: TextStyle(color: Colors.red.shade700),
                ),
              ),
            ],
          ),
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
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Teacher Management",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        elevation: 2,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(
              icon: Icon(Icons.person_add),
              text: "Add Teacher",
            ),
            Tab(
              icon: Icon(Icons.people),
              text: "View Teachers",
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildAddTeacherTab(),
          _buildViewTeachersTab(),
        ],
      ),
      floatingActionButton: _tabController.index == 1
          ? FloatingActionButton(
        onPressed: () {
          _tabController.animateTo(0);
        },
        backgroundColor: Colors.indigo,
        child: const Icon(Icons.add),
      )
          : null,
    );
  }
}

// Helper function to reset a teacher's password (implementation)
Future<void> _resetTeacherPassword(BuildContext context, String teacherId, String teacherName) async {
  try {
    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text("Resetting password..."),
              ],
            ),
          ),
        );
      },
    );

    // Get teacher document reference
    final teacherDoc = await FirebaseFirestore.instance
        .collection('teachers')
        .doc(teacherId)
        .get();

    if (!teacherDoc.exists) {
      Navigator.of(context).pop(); // Close dialog
      Fluttertoast.showToast(
        msg: "Teacher not found",
        backgroundColor: Colors.red,
      );
      return;
    }

    final teacherData = teacherDoc.data() as Map<String, dynamic>;
    final email = teacherData['email'] as String;

    // Generate new temporary password
    final newPassword = _generateTempPassword(teacherId, teacherName);

    // Get the user by email (Firebase Auth)
    final FirebaseAuth auth = FirebaseAuth.instance;
    final List<String> signInMethods = await auth.fetchSignInMethodsForEmail(email);

    if (signInMethods.isEmpty) {
      Navigator.of(context).pop(); // Close dialog
      Fluttertoast.showToast(
        msg: "Teacher account not found in authentication system",
        backgroundColor: Colors.red,
      );
      return;
    }

    // Reset password process
    // Note: In a real-world scenario, you would use Firebase Admin SDK on the backend
    // to securely reset passwords. This is a simplified implementation.

    // Update Firestore with the new temporary password and reset status
    await FirebaseFirestore.instance
        .collection('teachers')
        .doc(teacherId)
        .update({
      'temp_password': newPassword,
      'password_changed': false,
      'updated_at': FieldValue.serverTimestamp(),
    });

    // Close dialog
    Navigator.of(context).pop();

    // Show success message
    Fluttertoast.showToast(
      msg: "Password reset. New temporary password: $newPassword",
      backgroundColor: Colors.green,
      toastLength: Toast.LENGTH_LONG,
    );

  } catch (e) {
    // Close dialog if open
    if (context.mounted) {
      Navigator.of(context).pop();
    }

    Fluttertoast.showToast(
      msg: "Error resetting password: ${e.toString()}",
      backgroundColor: Colors.red,
    );
  }
}

// Helper function to generate temporary password (duplicated from main class for context)
String _generateTempPassword(String teacherId, String name) {
  String trimmedName = name.trim();
  String initials = "";
  if (trimmedName.isNotEmpty) {
    // Remove extra spaces and get first four letters.
    initials = trimmedName.replaceAll(RegExp(r'\s+'), '');
    if (initials.length > 4) {
      initials = initials.substring(0, 4);
    }
  }
  return teacherId + initials;
}