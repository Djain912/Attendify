// role_login_page.dart
import 'package:flutter/material.dart';
import 'package:attendence/pages/student_login.dart'; // StudentLoginPage
import 'package:attendence/pages/teacher_login.dart'; // TeacherLoginPage
import 'package:attendence/pages/admin_login.dart'; // TeacherLoginPage


class RoleLoginPage extends StatelessWidget {
  final String role;
  const RoleLoginPage({Key? key, required this.role}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Select the appropriate login page based on the role
    Widget loginWidget;
    switch (role) {
      case 'Teacher':
        loginWidget = const TeacherLoginPage();
        break;
      case 'Admin':
        loginWidget = const AdminLoginPage();
        break;
      case 'Student':
      default:
        loginWidget = const StudentLoginPage();
        break;
    }

    // You can return the chosen login page directly
    return loginWidget;
  }
}
