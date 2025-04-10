import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'class_timetable_page.dart';

class ClassPage extends StatefulWidget {
  const ClassPage({super.key});

  @override
  State<ClassPage> createState() => _ClassPageState();
}

class _ClassPageState extends State<ClassPage> with SingleTickerProviderStateMixin {
  final TextEditingController subjectController = TextEditingController();
  final TextEditingController fromTimeController = TextEditingController();
  final TextEditingController toTimeController = TextEditingController();

  String selectedDay = "Monday";
  String? selectedTeacher;
  late TabController _tabController;
  List<String> teachers = [];
  Map<String, String> teacherMap = {}; // Mapping of teacher name to teacher document ID

  // New dropdown values
  String? selectedDepartment;
  String? selectedYear;
  String? selectedSemester;
  String? selectedSection;
  String? selectedType; // Theory or Practical
  String? selectedBatch; // B1, B2, B3

  final List<String> departments = ["INFT", "CMPN", "EXTC", "EXCS", "BMED"];
  final List<String> years = ["FE", "SE", "TE", "BE"];
  final List<String> sections = ["A", "B", "C"];
  final List<String> days = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
  final List<String> types = ["Theory", "Practical"];
  final List<String> batches = ["B1", "B2", "B3"];
  List<Map<String, dynamic>> timetable = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchTeachers();
  }

  List<String> getSemesters(String? year) {
    switch (year) {
      case "FE":
        return ["SEM I", "SEM II"];
      case "SE":
        return ["SEM III", "SEM IV"];
      case "TE":
        return ["SEM V", "SEM VI"];
      case "BE":
        return ["SEM VII", "SEM VIII"];
      default:
        return [];
    }
  }

  Future<void> _fetchTeachers() async {
    try {
      QuerySnapshot querySnapshot = await FirebaseFirestore.instance
          .collection('teachers')
          .get();
      // Build a map: teacher name => teacher document ID
      Map<String, String> fetchedTeacherMap = {};
      for (var doc in querySnapshot.docs) {
        fetchedTeacherMap[doc['name'].toString()] = doc.id;
      }
      setState(() {
        teacherMap = fetchedTeacherMap;
        teachers = fetchedTeacherMap.keys.toList();
      });
    } catch (e) {
      _showToast("Failed to fetch teachers", isError: true);
    }
  }

  Future<List<Map<String, dynamic>>> _fetchClasses() async {
    QuerySnapshot querySnapshot = await FirebaseFirestore.instance
        .collection('classes')
        .get();
    return querySnapshot.docs.map((doc) {
      var data = doc.data() as Map<String, dynamic>;
      data['id'] = doc.id;
      return data;
    }).toList();
  }

  void _showToast(String message, {bool isError = false}) {
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      backgroundColor: isError ? Colors.red : Colors.green,
      textColor: Colors.white,
    );
  }

  Future<void> _pickTime(TextEditingController controller) async {
    TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (pickedTime != null) {
      controller.text = pickedTime.format(context);
    }
  }

  void _addToTimetable() {
    String subject = subjectController.text.trim();
    String fromTime = fromTimeController.text.trim();
    String toTime = toTimeController.text.trim();

    if (subject.isNotEmpty && fromTime.isNotEmpty && toTime.isNotEmpty && selectedTeacher != null) {
      // Look up teacher_id from the mapping using the selected teacher's name
      String? teacherId = teacherMap[selectedTeacher];
      setState(() {
        timetable.add({
          'day': selectedDay,
          'fromTime': fromTime,
          'toTime': toTime,
          'subject': subject,
          'teacher': selectedTeacher,
          'teacher_id': teacherId, // Save the teacher's document ID
          'type': selectedType,
          'batch': selectedType == "Practical" ? selectedBatch : null,
        });
      });

      subjectController.clear();
      fromTimeController.clear();
      toTimeController.clear();
      selectedType = null;
      selectedBatch = null;
      _showToast("Lecture added for $selectedDay");
    } else {
      _showToast("Please fill all fields", isError: true);
    }
  }

  Future<void> _addClass() async {
    if (selectedDepartment == null ||
        selectedYear == null ||
        selectedSemester == null ||
        selectedSection == null) {
      _showToast("Please select all class details", isError: true);
      return;
    }

    if (timetable.isEmpty) {
      _showToast("Add at least one lecture", isError: true);
      return;
    }

    final className = "$selectedDepartment $selectedYear $selectedSection";

    try {
      // Check for existing class
      QuerySnapshot query = await FirebaseFirestore.instance
          .collection('classes')
          .where('department', isEqualTo: selectedDepartment)
          .where('year', isEqualTo: selectedYear)
          .where('section', isEqualTo: selectedSection)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        // Update existing class
        String docId = query.docs.first.id;
        List<dynamic> existing = query.docs.first['timetable'];
        existing.addAll(timetable);

        await FirebaseFirestore.instance
            .collection('classes')
            .doc(docId)
            .update({'timetable': existing});
      } else {
        // Create new class
        await FirebaseFirestore.instance.collection('classes').add({
          'name': className,
          'department': selectedDepartment,
          'year': selectedYear,
          'semester': selectedSemester,
          'section': selectedSection,
          'timetable': timetable,
          'created_at': FieldValue.serverTimestamp(),
        });
      }

      _showToast("Class Updated: $className");
      setState(() {
        timetable.clear();
        selectedDepartment = null;
        selectedYear = null;
        selectedSemester = null;
        selectedSection = null;
      });
    } catch (e) {
      _showToast("Failed to update class: $e", isError: true);
    }
  }

  Widget _buildAddClassTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(10),
      child: Column(
        children: [
          // Department Dropdown
          DropdownButtonFormField<String>(
            value: selectedDepartment,
            decoration: const InputDecoration(
              labelText: "Department",
              border: OutlineInputBorder(),
            ),
            items: departments.map((dept) {
              return DropdownMenuItem(value: dept, child: Text(dept));
            }).toList(),
            onChanged: (value) {
              setState(() {
                selectedDepartment = value;
                selectedYear = null;
                selectedSemester = null;
                selectedSection = null;
              });
            },
          ),
          const SizedBox(height: 10),

          // Year Dropdown
          DropdownButtonFormField<String>(
            value: selectedYear,
            decoration: const InputDecoration(
              labelText: "Year",
              border: OutlineInputBorder(),
            ),
            items: years.map((year) {
              return DropdownMenuItem(value: year, child: Text(year));
            }).toList(),
            onChanged: selectedDepartment != null ? (value) {
              setState(() {
                selectedYear = value;
                selectedSemester = null;
                selectedSection = null;
              });
            } : null,
          ),
          const SizedBox(height: 10),

          // Semester Dropdown
          DropdownButtonFormField<String>(
            value: selectedSemester,
            decoration: const InputDecoration(
              labelText: "Semester",
              border: OutlineInputBorder(),
            ),
            items: getSemesters(selectedYear).map((sem) {
              return DropdownMenuItem(value: sem, child: Text(sem));
            }).toList(),
            onChanged: selectedYear != null ? (value) {
              setState(() {
                selectedSemester = value;
              });
            } : null,
          ),
          const SizedBox(height: 10),

          // Section Dropdown
          DropdownButtonFormField<String>(
            value: selectedSection,
            decoration: const InputDecoration(
              labelText: "Section",
              border: OutlineInputBorder(),
            ),
            items: sections.map((sec) {
              return DropdownMenuItem(value: sec, child: Text(sec));
            }).toList(),
            onChanged: selectedSemester != null ? (value) {
              setState(() {
                selectedSection = value;
              });
            } : null,
          ),
          const SizedBox(height: 20),

          // Display generated class name
          if (selectedDepartment != null && selectedYear != null && selectedSection != null)
            Text(
              "Class Name: $selectedDepartment $selectedYear $selectedSection",
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          const SizedBox(height: 20),

          // Subject & Timing Inputs
          TextField(
            controller: subjectController,
            decoration: const InputDecoration(
              labelText: "Subject",
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),

          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: fromTimeController,
                  decoration: const InputDecoration(
                    labelText: "From Time",
                    border: OutlineInputBorder(),
                  ),
                  readOnly: true,
                  onTap: () => _pickTime(fromTimeController),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: toTimeController,
                  decoration: const InputDecoration(
                    labelText: "To Time",
                    border: OutlineInputBorder(),
                  ),
                  readOnly: true,
                  onTap: () => _pickTime(toTimeController),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Day & Teacher Dropdown
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: selectedDay,
                  items: days.map((day) {
                    return DropdownMenuItem(value: day, child: Text(day));
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      selectedDay = value!;
                    });
                  },
                  decoration: const InputDecoration(
                    labelText: "Day",
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: selectedTeacher,
                  items: teachers.map((teacher) {
                    return DropdownMenuItem(value: teacher, child: Text(teacher));
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      selectedTeacher = value;
                    });
                  },
                  decoration: const InputDecoration(
                    labelText: "Teacher",
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Type Dropdown (Theory/Practical)
          DropdownButtonFormField<String>(
            value: selectedType,
            decoration: const InputDecoration(
              labelText: "Type",
              border: OutlineInputBorder(),
            ),
            items: types.map((type) {
              return DropdownMenuItem(value: type, child: Text(type));
            }).toList(),
            onChanged: (value) {
              setState(() {
                selectedType = value;
                selectedBatch = null; // Reset batch when type changes
              });
            },
          ),
          const SizedBox(height: 10),

          // Batch Dropdown (only for Practical)
          if (selectedType == "Practical")
            DropdownButtonFormField<String>(
              value: selectedBatch,
              decoration: const InputDecoration(
                labelText: "Batch",
                border: OutlineInputBorder(),
              ),
              items: batches.map((batch) {
                return DropdownMenuItem(value: batch, child: Text(batch));
              }).toList(),
              onChanged: (value) {
                setState(() {
                  selectedBatch = value;
                });
              },
            ),
          const SizedBox(height: 10),

          // Add to Timetable Button
          ElevatedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text("Add Lecture"),
            onPressed: _addToTimetable,
          ),

          // Timetable List
          const SizedBox(height: 10),
          timetable.isEmpty
              ? const Text("No lectures added yet", style: TextStyle(color: Colors.grey))
              : ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: timetable.length,
            itemBuilder: (context, index) {
              var lecture = timetable[index];
              return ListTile(
                title: Text("${lecture['subject']} (${lecture['day']})"),
                subtitle: Text(
                    "Time: ${lecture['fromTime']} - ${lecture['toTime']} | Teacher: ${lecture['teacher']}\n"
                        "Type: ${lecture['type']}${lecture['type'] == "Practical" ? " | Batch: ${lecture['batch']}" : ""}"),
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () {
                    setState(() {
                      timetable.removeAt(index);
                    });
                  },
                ),
              );
            },
          ),

          // Save Class Button
          const SizedBox(height: 10),
          ElevatedButton.icon(
            icon: const Icon(Icons.check),
            label: const Text("Save Class"),
            onPressed: _addClass,
          ),
        ],
      ),
    );
  }

  Widget _buildViewClassesTab() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _fetchClasses(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) return Center(child: Text("Error: ${snapshot.error}"));
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text("No classes found"));
        }

        // Group classes by name
        Map<String, List<Map<String, dynamic>>> grouped = {};
        for (var cls in snapshot.data!) {
          String key = "${cls['department']} ${cls['year']} ${cls['section']}";
          grouped.putIfAbsent(key, () => []).add(cls);
        }

        return ListView(
          children: grouped.entries.map((entry) {
            String className = entry.key;
            List<Map<String, dynamic>> classes = entry.value;
            int totalLectures = classes.fold(0, (sum, cls) => (sum + (cls['timetable']?.length ?? 0)).toInt());

            return Card(
              elevation: 3,
              margin: const EdgeInsets.all(8),
              child: ListTile(
                title: Text(className,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                subtitle: Text("Lectures: $totalLectures"),
                trailing: const Icon(Icons.arrow_forward),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ClassTimetablePage(
                      className: className,
                      classId: classes.first['id'], // Ensure you pass the correct class ID
                    ),
                  ),
                ),

              ),
            );
          }).toList(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Manage Classes"),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: "Add Class"),
            Tab(text: "View Classes"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildAddClassTab(),
          _buildViewClassesTab(),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
}
