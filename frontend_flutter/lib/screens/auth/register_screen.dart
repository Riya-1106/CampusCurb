import 'package:flutter/material.dart';
import '../../../services/auth_service.dart';
import '../../../services/firestore_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final AuthService _authService = AuthService();
  String _selectedRole = "student";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Register")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: "Email"),
            ),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(labelText: "Password"),
              obscureText: true,
            ),
            DropdownButton<String>(
              value: _selectedRole,
              items: const [
                DropdownMenuItem(value: "student", child: Text("Student")),
                DropdownMenuItem(value: "canteen", child: Text("Canteen")),
                DropdownMenuItem(value: "faculty", child: Text("Faculty")),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedRole = value!;
                });
              },
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                final user = await _authService.register(
                  _emailController.text.trim(),
                  _passwordController.text.trim(),
                );

                if (user != null) {
                  await FirestoreService().createUser(
                    uid: user.uid,
                    email: user.email!,
                    role: _selectedRole,
                  );

                  Navigator.pop(context);
                }
              },
              child: const Text("Register"),
            ),
          ],
        ),
      ),
    );
  }
}
