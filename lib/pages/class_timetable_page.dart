import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ClassTimetablePage extends StatefulWidget {
  final String classId;
  final String className;

  const ClassTimetablePage({super.key, required this.classId, required this.className});

  @override
  State<ClassTimetablePage> createState() => _ClassTimetablePageState();
}

class _ClassTimetablePageState extends State<ClassTimetablePage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<String> days = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: days.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Widget _buildLectureCard(Map<String, dynamic> lecture) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      elevation: 4,
      child: ListTile(
        leading: const Icon(Icons.book, size: 30, color: Colors.blueAccent),
        title: Text(
          lecture['subject'],
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          "Time: ${lecture['fromTime']} - ${lecture['toTime']}\nTeacher: ${lecture['teacher'] ?? 'Unknown'}",
          style: const TextStyle(fontSize: 14, color: Colors.black54),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Timetable - ${widget.className}"),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: days.map((day) => Tab(text: day)).toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: days.map((day) {
          return StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('classes').doc(widget.classId).snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

              var classData = snapshot.data!.data() as Map<String, dynamic>;
              var timetable = classData['timetable'] as List<dynamic>? ?? [];

              var lectures = timetable.where((entry) => entry['day'] == day).toList();
              return lectures.isEmpty
                  ? const Center(child: Text("No lectures for this day."))
                  : ListView.builder(
                itemCount: lectures.length,
                itemBuilder: (context, index) => _buildLectureCard(lectures[index]),
              );
            },
          );
        }).toList(),
      ),
    );
  }
}
