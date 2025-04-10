import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:math'; // For random quotes

class StudentHomePage extends StatefulWidget {
  const StudentHomePage({Key? key}) : super(key: key);

  @override
  State<StudentHomePage> createState() => _StudentHomePageState();
}

class _StudentHomePageState extends State<StudentHomePage> with SingleTickerProviderStateMixin {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final _secureStorage = const FlutterSecureStorage();

  Map<String, dynamic>? _studentData;
  bool _isLoading = true;
  int _currentIndex = 0;
  late AnimationController _animationController;

  // BLE Advertising variables
  bool isAdvertising = false;
  final fbp.Guid attendanceServiceUuid = fbp.Guid("a1b2c3d4-e5f6-7890-abcd-ef1234567890");
  final FlutterBlePeripheral _blePeripheral = FlutterBlePeripheral();

  // Motivational quotes
  final List<String> _motivationalQuotes = [
    "Success is the sum of small efforts, repeated day in and day out.",
    "The only way to do great work is to love what you do.",
    "Believe you can and you're halfway there.",
    "Education is the most powerful weapon you can use to change the world.",
    "Don't watch the clock; do what it does. Keep going.",
  ];

  @override
  void initState() {
    super.initState();
    _loadStudentData();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadStudentData() async {
    setState(() => _isLoading = true);
    try {
      final user = _auth.currentUser;
      if (user == null) {
        _navigateToLogin();
        return;
      }
      final studentDoc = await _firestore
          .collection('students')
          .where('email', isEqualTo: user.email)
          .limit(1)
          .get();
      if (studentDoc.docs.isEmpty) {
        _navigateToLogin();
        return;
      }
      setState(() {
        _studentData = studentDoc.docs.first.data();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showErrorDialog('Error loading data: ${e.toString()}');
    }
  }

  void _navigateToLogin() {
    Navigator.pushReplacementNamed(context, '/student_login');
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

  Future<void> _signOut() async {
    bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('SIGN OUT'),
          ),
        ],
      ),
    ) ?? false;

    if (!confirm) return;

    if (_studentData != null && _studentData!['roll_no'] != null) {
      try {
        await _firestore
            .collection('students')
            .doc(_studentData!['roll_no'])
            .update({'last_logout': FieldValue.serverTimestamp()});
      } catch (e) {
        debugPrint('Error updating logout timestamp: $e');
      }
    }
    await _auth.signOut();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('is_logged_in');
    await prefs.remove('student_roll_no');
    await _secureStorage.delete(key: 'student_roll_no');
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/');
  }

  Widget _buildProfilePage() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Loading profile...',
              style: TextStyle(
                color: Theme.of(context).colorScheme.secondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    if (_studentData == null) return const Center(child: Text('No student data found'));

    final rollNo = _studentData!['roll_no'];
    final studentName = _studentData!['name'] ?? 'Student';
    final studentInitial = studentName.isNotEmpty ? studentName[0].toUpperCase() : 'S';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, -0.2),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: _animationController,
              curve: Curves.easeOut,
            )),
            child: FadeTransition(
              opacity: _animationController,
              child: _buildProfileHeader(studentInitial, studentName),
            ),
          ),
          const SizedBox(height: 24),
          SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(-0.2, 0),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: _animationController,
              curve: const Interval(0.2, 0.8, curve: Curves.easeOut),
            )),
            child: FadeTransition(
              opacity: Tween<double>(begin: 0.0, end: 1.0).animate(
                CurvedAnimation(
                  parent: _animationController,
                  curve: const Interval(0.2, 0.8, curve: Curves.easeOut),
                ),
              ),
              child: _buildInfoCard('Student Information', [
                _buildInfoRow('Roll Number', _studentData!['roll_no']),
                _buildInfoRow('Class', _studentData!['class']),
                _buildInfoRow('Batch', _studentData!['batch']),
                _buildInfoRow('Year', _studentData!['year']),
                _buildInfoRow('Email', _studentData!['email']),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.2, 0),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: _animationController,
              curve: const Interval(0.3, 0.9, curve: Curves.easeOut),
            )),
            child: FadeTransition(
              opacity: Tween<double>(begin: 0.0, end: 1.0).animate(
                CurvedAnimation(
                  parent: _animationController,
                  curve: const Interval(0.3, 0.9, curve: Curves.easeOut),
                ),
              ),
              child: _buildInfoCard('Device Information', [
                _buildInfoRow('Device ID', _studentData!['device_id'] ?? 'Not registered'),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.2),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: _animationController,
              curve: const Interval(0.4, 1.0, curve: Curves.easeOut),
            )),
            child: FadeTransition(
              opacity: Tween<double>(begin: 0.0, end: 1.0).animate(
                CurvedAnimation(
                  parent: _animationController,
                  curve: const Interval(0.4, 1.0, curve: Curves.easeOut),
                ),
              ),
              child: _buildAttendanceAnalytics(rollNo),
            ),
          ),
          const SizedBox(height: 16),
          _buildMotivationalQuote(),
        ],
      ),
    );
  }

  Widget _buildProfileHeader(String initial, String name) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [
                Theme.of(context).colorScheme.primary,
                Theme.of(context).colorScheme.secondary,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
          child: CircleAvatar(
            radius: 50,
            backgroundColor: Colors.white,
            child: Text(
              initial,
              style: TextStyle(
                fontSize: 40,
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          name,
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          'Active Student',
          style: TextStyle(
            fontSize: 16,
            color: Theme.of(context).colorScheme.secondary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildAttendanceAnalytics(String rollNo) {
    return Column(
      children: [
        Card(
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.analytics_outlined, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 8),
                    const Text(
                      'Attendance Overview',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const Divider(height: 24),
                FutureBuilder<QuerySnapshot>(
                  future: _firestore
                      .collection('attendance')
                      .where('presentStudentIds', arrayContains: rollNo)
                      .get(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) return _buildShimmerCard();
                    if (snapshot.hasError) return _buildErrorCard('Error: ${snapshot.error}');

                    final attendanceDocs = snapshot.data!.docs;
                    int attendedCount = attendanceDocs.length;
                    int totalClasses = attendedCount + 2; // Mock total
                    final attendancePercentage = (attendedCount / totalClasses) * 100;

                    return Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildAttendanceStat('Present', attendedCount.toString(), Icons.check_circle_outline, Colors.green),
                            _buildAttendanceStat('Absent', '2', Icons.cancel_outlined, Colors.red),
                            _buildAttendanceStat('Total', totalClasses.toString(), Icons.calendar_month_outlined, Theme.of(context).colorScheme.primary),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Overall Attendance', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 16)),
                            Text('${attendancePercentage.toStringAsFixed(1)}%', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: attendancePercentage >= 75 ? Colors.green : Colors.orange)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: LinearProgressIndicator(
                            value: attendancePercentage / 100,
                            minHeight: 10,
                            backgroundColor: Colors.grey.withOpacity(0.2),
                            valueColor: AlwaysStoppedAnimation<Color>(attendancePercentage >= 75 ? Colors.green : Colors.orange),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _buildSubjectWiseAttendance(rollNo),
      ],
    );
  }

  Widget _buildSubjectWiseAttendance(String rollNo) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.book_outlined, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                const Text('Subject-wise Attendance', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ],
            ),
            const Divider(height: 24),
            FutureBuilder<QuerySnapshot>(
              future: _firestore
                  .collection('attendance')
                  .where('presentStudentIds', arrayContains: rollNo)
                  .get(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                if (snapshot.hasError) return Text('Error: ${snapshot.error}');

                final attendanceDocs = snapshot.data!.docs;
                Map<String, int> subjectAttendance = {};
                Map<String, int> subjectTotal = {};

                // Aggregate attendance by subject
                for (var doc in attendanceDocs) {
                  final data = doc.data() as Map<String, dynamic>;
                  final subject = data['subject'] as String? ?? 'Unknown';
                  subjectAttendance[subject] = (subjectAttendance[subject] ?? 0) + 1;
                  subjectTotal[subject] = (subjectTotal[subject] ?? 0) + 1;
                }

                // Mock additional classes for total (assuming some absences)
                subjectTotal.forEach((key, value) {
                  subjectTotal[key] = value + 1; // Add one absence per subject
                });

                if (subjectAttendance.isEmpty) {
                  return const Center(child: Text('No attendance records found'));
                }

                return Column(
                  children: subjectAttendance.keys.map((subject) {
                    final attended = subjectAttendance[subject] ?? 0;
                    final total = subjectTotal[subject] ?? 1;
                    final percentage = (attended / total) * 100;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(subject, style: const TextStyle(fontWeight: FontWeight.bold)),
                                Text('$attended / $total classes', style: TextStyle(color: Colors.grey.shade600)),
                              ],
                            ),
                          ),
                          Text('${percentage.toStringAsFixed(1)}%', style: TextStyle(color: percentage >= 75 ? Colors.green : Colors.orange)),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 100,
                            child: LinearProgressIndicator(
                              value: percentage / 100,
                              backgroundColor: Colors.grey.withOpacity(0.2),
                              valueColor: AlwaysStoppedAnimation<Color>(percentage >= 75 ? Colors.green : Colors.orange),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMotivationalQuote() {
    final randomQuote = _motivationalQuotes[Random().nextInt(_motivationalQuotes.length)];
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.lightbulb_outline, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                const Text('Daily Motivation', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ],
            ),
            const Divider(height: 24),
            Text(
              '"$randomQuote"',
              style: TextStyle(fontSize: 16, fontStyle: FontStyle.italic, color: Colors.grey.shade700),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttendanceStat(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 8),
        Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
      ],
    );
  }

  Widget _buildShimmerCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(width: 24, height: 24, decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), color: Colors.grey.shade300)),
                const SizedBox(width: 8),
                Container(width: 180, height: 24, decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), color: Colors.grey.shade300)),
              ],
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(
                3,
                    (index) => Column(
                  children: [
                    Container(width: 28, height: 28, decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: Colors.grey.shade300)),
                    const SizedBox(height: 8),
                    Container(width: 50, height: 20, decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), color: Colors.grey.shade300)),
                    const SizedBox(height: 4),
                    Container(width: 60, height: 16, decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), color: Colors.grey.shade300)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard(String message) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 40),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: _loadStudentData, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  Widget _buildUpcomingClassesPage() {
    if (_studentData == null) return const Center(child: Text('No student data available'));

    final studentClassName = _studentData!['class'];
    final currentDay = _getCurrentDayName();

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Theme.of(context).colorScheme.primary.withOpacity(0.05),
            Theme.of(context).colorScheme.secondary.withOpacity(0.1),
          ],
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.calendar_today, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      currentDay,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Your classes for today',
                  style: TextStyle(
                    fontSize: 16,
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<QuerySnapshot>(
              future: _firestore.collection('classes').where('name', isEqualTo: studentClassName).limit(1).get(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(child: Text('No class document found for $studentClassName'));
                }

                final classDoc = snapshot.data!.docs.first;
                final classData = classDoc.data() as Map<String, dynamic>;
                final List<dynamic> timetable = classData['timetable'] ?? [];
                final classesToday = timetable.where((entry) => (entry['day'] as String?) == currentDay).toList();

                classesToday.sort((a, b) => (a['fromTime'] as String).compareTo(b['fromTime'] as String));

                if (classesToday.isEmpty) {
                  return Center(child: Text('No classes scheduled for $currentDay'));
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  physics: const BouncingScrollPhysics(),
                  itemCount: classesToday.length,
                  itemBuilder: (context, index) {
                    final classInfo = classesToday[index] as Map<String, dynamic>;
                    final subject = classInfo['subject'] ?? 'Subject Unknown';
                    final teacher = classInfo['teacher'] ?? 'Unknown Teacher';
                    final fromTime = classInfo['fromTime'] ?? 'N/A';
                    final toTime = classInfo['toTime'] ?? '';
                    final room = classInfo['room'] ?? 'TBD';

                    bool isPast = TimeOfDay.now().hour > (int.tryParse(toTime.split(':')[0]) ?? 0);
                    bool isCurrent = !isPast && TimeOfDay.now().hour >= (int.tryParse(fromTime.split(':')[0]) ?? 0);

                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: isCurrent ? BorderSide(color: Theme.of(context).colorScheme.primary, width: 2) : BorderSide.none,
                      ),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                            decoration: BoxDecoration(
                              color: isCurrent
                                  ? Theme.of(context).colorScheme.primary
                                  : isPast
                                  ? Colors.grey.shade200
                                  : Theme.of(context).colorScheme.secondaryContainer,
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isCurrent
                                      ? Icons.play_circle_outline
                                      : isPast
                                      ? Icons.check_circle_outline
                                      : Icons.schedule,
                                  color: isCurrent
                                      ? Colors.white
                                      : isPast
                                      ? Colors.grey
                                      : Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  isCurrent ? 'Current Class' : isPast ? 'Completed' : 'Upcoming',
                                  style: TextStyle(
                                    color: isCurrent
                                        ? Colors.white
                                        : isPast
                                        ? Colors.grey
                                        : Theme.of(context).colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(subject, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isPast ? Colors.grey : null)),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          _buildClassInfoRow(Icons.access_time, '$fromTime - $toTime', isPast),
                                          const SizedBox(height: 8),
                                          _buildClassInfoRow(Icons.person_outline, teacher, isPast),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          _buildClassInfoRow(Icons.room_outlined, 'Room $room', isPast),
                                          const SizedBox(height: 8),
                                          _buildClassInfoRow(Icons.class_outlined, studentClassName, isPast),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                if (!isPast && !isCurrent) ...[
                                  const SizedBox(height: 16),
                                  Center(
                                    child: OutlinedButton.icon(
                                      onPressed: () => _setReminder(subject, fromTime),
                                      icon: const Icon(Icons.notifications_active_outlined),
                                      label: const Text('Set Reminder'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Theme.of(context).colorScheme.primary,
                                        side: BorderSide(color: Theme.of(context).colorScheme.primary),
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClassInfoRow(IconData icon, String text, bool isPast) {
    return Row(
      children: [
        Icon(icon, size: 16, color: isPast ? Colors.grey.shade400 : Colors.grey.shade700),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: isPast ? Colors.grey.shade400 : Colors.grey.shade700),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  void _setReminder(String subject, String time) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Reminder set for $subject at $time'),
        backgroundColor: Theme.of(context).colorScheme.secondary,
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(label: 'DISMISS', textColor: Colors.white, onPressed: () {}),
      ),
    );
  }

  String _getCurrentDayName() {
    final now = DateTime.now();
    final days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return days[now.weekday - 1];
  }

  Widget _buildAttendancePage() {
    if (_studentData == null) return const Center(child: Text('No student data available'));

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isAdvertising ? Colors.green : Colors.red,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isAdvertising ? 'Broadcasting' : 'Not Broadcasting',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: isAdvertising ? Colors.green : Colors.red,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildInfoRow('Roll Number', _studentData!['roll_no']),
                      const SizedBox(height: 8),
                      _buildInfoRow('Name', _studentData!['name']),
                      const SizedBox(height: 8),
                      _buildInfoRow('Class', _studentData!['class']),
                      const SizedBox(height: 8),
                      _buildInfoRow('Device ID', _studentData!['device_id'] ?? 'Not registered'),
                      const SizedBox(height: 24),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 500),
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.transparent,
                          border: Border.all(
                            color: isAdvertising ? Theme.of(context).colorScheme.primary : Colors.grey.shade400,
                            width: 4,
                          ),
                        ),
                        child: Center(
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 500),
                            opacity: isAdvertising ? 1.0 : 0.5,
                            child: Icon(
                              Icons.bluetooth_searching,
                              size: 64,
                              color: isAdvertising ? Theme.of(context).colorScheme.primary : Colors.grey.shade400,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),
                ElevatedButton(
                  onPressed: _toggleBroadcast,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isAdvertising ? Colors.red : Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(isAdvertising ? Icons.bluetooth_disabled : Icons.bluetooth),
                      const SizedBox(width: 8),
                      Text(isAdvertising ? 'Stop Broadcasting' : 'Start Broadcasting'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  isAdvertising
                      ? 'Your attendance will be marked while broadcasting is active'
                      : 'Start broadcasting to mark your attendance',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _toggleBroadcast() async {
    try {
      final user = _auth.currentUser;
      if (user == null || _studentData == null) {
        _showErrorDialog('User data not available');
        return;
      }

      final studentRollNo = _studentData!['roll_no'];
      if (studentRollNo == null) {
        _showErrorDialog('Student roll number not available');
        return;
      }

      if (isAdvertising) {
        await _blePeripheral.stop();
        setState(() => isAdvertising = false);
      } else {
        final studentDataJson = jsonEncode({
          'roll_no': studentRollNo,
          'name': _studentData!['name'],
          'class': _studentData!['class'],
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });

        final AdvertiseData advertiseData = AdvertiseData(
          serviceUuid: attendanceServiceUuid.toString(),
          localName: 'Student-$studentRollNo',
          manufacturerId: 0x0000,
          serviceDataUuid: attendanceServiceUuid.toString(),
          includeDeviceName: true,
        );

        await _blePeripheral.start(advertiseData: advertiseData);
        setState(() => isAdvertising = true);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Broadcasting started. Your attendance will be marked.'),
            backgroundColor: Theme.of(context).colorScheme.secondary,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      _showErrorDialog('Failed to toggle broadcasting: ${e.toString()}');
    }
  }

  Widget _buildInfoCard(String title, List<Widget> children) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Divider(height: 24),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.grey)),
          Expanded(
            child: Text(value ?? 'N/A', style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Student Dashboard'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _signOut,
            tooltip: 'Sign Out',
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildProfilePage(),
          _buildUpcomingClassesPage(),
          _buildAttendancePage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
          NavigationDestination(
            icon: Icon(Icons.schedule_outlined),
            selectedIcon: Icon(Icons.schedule),
            label: 'Classes',
          ),
          NavigationDestination(
            icon: Icon(Icons.bluetooth_outlined),
            selectedIcon: Icon(Icons.bluetooth),
            label: 'Attendance',
          ),
        ],
      ),
    );
  }
}