import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'session_page.dart'; // Import the session page

class TeacherHomePage extends StatefulWidget {
  const TeacherHomePage({Key? key}) : super(key: key);

  @override
  State<TeacherHomePage> createState() => _TeacherHomePageState();
}

class _TeacherHomePageState extends State<TeacherHomePage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final _secureStorage = const FlutterSecureStorage();

  Map<String, dynamic>? _teacherData;
  bool _isLoading = true;
  int _currentIndex = 0;
  List<Map<String, dynamic>> _students = []; // optional if needed

  @override
  void initState() {
    super.initState();
    _loadTeacherData();
  }

  Future<void> _loadTeacherData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final user = _auth.currentUser;
      if (user == null) {
        _navigateToLogin();
        return;
      }

      final teacherDoc = await _firestore
          .collection('teachers')
          .where('email', isEqualTo: user.email)
          .limit(1)
          .get();

      if (teacherDoc.docs.isEmpty) {
        _navigateToLogin();
        return;
      }

      setState(() {
        _teacherData = teacherDoc.docs.first.data();
      });

      // Optionally, load students data.
      await _loadStudents();

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showErrorDialog('Error loading data: ${e.toString()}');
    }
  }

  Future<void> _loadStudents() async {
    try {
      final studentsSnapshot = await _firestore.collection('students').get();
      setState(() {
        _students = studentsSnapshot.docs
            .map((doc) => {'id': doc.id, ...doc.data()})
            .toList();
      });
    } catch (e) {
      _showErrorDialog('Error loading students: ${e.toString()}');
    }
  }

  void _navigateToLogin() {
    Navigator.pushReplacementNamed(context, '/teacher_login');
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Logout method: update logout timestamp, clear local storage, and navigate back to HomeScreen.
  Future<void> _signOut() async {
    if (_teacherData != null && _teacherData!['teacher_id'] != null) {
      try {
        await _firestore
            .collection('teachers')
            .doc(_teacherData!['teacher_id'])
            .update({'last_logout': FieldValue.serverTimestamp()});
      } catch (e) {
        debugPrint('Error updating logout timestamp: $e');
      }
    }
    await FirebaseAuth.instance.signOut();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('is_logged_in_teacher');
    await prefs.remove('teacher_id');
    await _secureStorage.delete(key: 'teacher_id');
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/');
  }

  /// Build the Profile page using teacher data.
  Widget _buildProfilePage() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_teacherData == null) return const Center(child: Text('No teacher data found'));
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          CircleAvatar(
            radius: 40,
            backgroundColor: Colors.green,
            child: Text(
              _teacherData!['name'][0].toUpperCase(),
              style: const TextStyle(fontSize: 30, color: Colors.white),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _teacherData!['name'],
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          Text(
            'ID: ${_teacherData!['teacher_id']}',
            style: const TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 20),
          _buildInfoCard('Teacher Information', [
            _buildInfoRow('Teacher ID', _teacherData!['teacher_id']),
            _buildInfoRow('Email', _teacherData!['email']),

          ]),
        ],
      ),
    );
  }

  /// Build the Upcoming Classes page.
  /// This queries the "classes" collection and filters timetable entries for the current teacher and day.
  Widget _buildUpcomingClassesPage() {
    if (_teacherData == null) return const Center(child: Text('No teacher data available'));

    final teacherName = _teacherData!['name'];
    final currentDay = _getCurrentDayName();

    return FutureBuilder<QuerySnapshot>(
      future: _firestore.collection('classes').get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting)
          return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError)
          return Center(child: Text('Error loading classes: ${snapshot.error}'));
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty)
          return const Center(child: Text('No classes found'));

        List<Map<String, dynamic>> matchingEntries = [];
        for (var doc in snapshot.data!.docs) {
          final classData = doc.data() as Map<String, dynamic>;
          final List<dynamic> timetable = classData['timetable'] ?? [];
          for (var entry in timetable) {
            final Map<String, dynamic> mapEntry = Map<String, dynamic>.from(entry);
            if (mapEntry['teacher'] == teacherName && mapEntry['day'] == currentDay) {
              // Add the class name to the entry.
              mapEntry['className'] = classData['name'];
              matchingEntries.add(mapEntry);
            }
          }
        }

        if (matchingEntries.isEmpty) {
          return Center(child: Text('No classes scheduled for $currentDay'));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: matchingEntries.length,
          itemBuilder: (context, index) {
            final entry = matchingEntries[index];
            final subject = entry['subject'] ?? 'Subject Unknown';
            final fromTime = entry['fromTime'] ?? 'N/A';
            final toTime = entry['toTime'] ?? '';
            final className = entry['className'] ?? 'Unknown Class';
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 8),
              child: ListTile(
                title: Text('$subject ($className)'),
                subtitle: Text('Time: $fromTime - $toTime\nDay: $currentDay'),
                onTap: () {
                  // Navigate to the SessionPage to mark attendance for this class session.
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => SessionPage(sessionData: entry),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  /// Helper method to get the current day name.
  String _getCurrentDayName() {
    final now = DateTime.now();
    switch (now.weekday) {
      case DateTime.monday:
        return 'Monday';
      case DateTime.tuesday:
        return 'Tuesday';
      case DateTime.wednesday:
        return 'Wednesday';
      case DateTime.thursday:
        return 'Thursday';
      case DateTime.friday:
        return 'Friday';
      case DateTime.saturday:
        return 'Saturday';
      case DateTime.sunday:
        return 'Sunday';
      default:
        return '';
    }
  }

  Widget _buildInfoCard(String title, List<Widget> children) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Divider(),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text('$label:', style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.grey)),
          ),
          Expanded(
            child: Text(value.toString(), style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Define two pages: Profile and Upcoming Classes.
    final List<Widget> pages = [
      _buildProfilePage(),
      _buildUpcomingClassesPage(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Teacher Dashboard'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _signOut,
          ),
        ],
      ),
      body: pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Profile',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_today),
            label: 'Upcoming Classes',
          ),
        ],
      ),
    );
  }
}
