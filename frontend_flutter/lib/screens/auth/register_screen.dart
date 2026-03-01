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
  bool _obscurePassword = true;
  Widget roleChip(String role, IconData icon) {
  return ChoiceChip(
    label: Text(role.toUpperCase()),
    avatar: Icon(icon, size: 18),
    selected: _selectedRole == role,
    selectedColor: const Color(0xFF4A90E2),
    labelStyle: TextStyle(
      color: _selectedRole == role ? Colors.white : Colors.black87,
      fontWeight: FontWeight.w500,
    ),
    onSelected: (selected) {
      setState(() {
        _selectedRole = role;
      });
    },
  );
}

  Widget roleButton(String role, IconData icon) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedRole = role;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: _selectedRole == role
              ? const Color(0xFF4A90E2)
              : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                color: _selectedRole == role
                    ? Colors.white
                    : Colors.black54,
                size: 18),
            const SizedBox(width: 8),
            Text(
              role.toUpperCase(),
              style: TextStyle(
                color: _selectedRole == role
                    ? Colors.white
                    : Colors.black87,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [

              // 🔥 TOP GRADIENT HEADER
              Container(
                height: 200,
                width: double.infinity,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF4A90E2), Color(0xFF357ABD)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(30),
                    bottomRight: Radius.circular(30),
                  ),
                ),
                child: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.fastfood,
                          size: 50, color: Colors.white),
                      SizedBox(height: 10),
                      Text(
                        "CampusCurb",
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        "Order smarter on campus",
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 30),

              // 🧾 FORM CARD
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Card(
                  elevation: 8,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 400),
                        child: Column(
                          children: [
                            // EMAIL
                            TextField(
                              controller: _emailController,
                              decoration: const InputDecoration(
                                prefixIcon: Icon(Icons.email_outlined),
                                labelText: "Email",
                                border: OutlineInputBorder(),
                              ),
                            ),

                            const SizedBox(height: 18),

                            // PASSWORD
                            TextField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              decoration: InputDecoration(
                                prefixIcon: const Icon(Icons.lock_outline),
                                labelText: "Password",
                                border: const OutlineInputBorder(),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _obscurePassword = !_obscurePassword;
                                    });
                                  },
                                ),
                              ),
                            ),

                            const SizedBox(height: 25),

                            // ROLE SELECTION LABEL
                            const Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                "Select Role",
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ),

                            const SizedBox(height: 10),

                            // 🔥 COMPACT ROLE CHIPS
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                roleChip("student", Icons.school),
                                roleChip("faculty", Icons.person_outline),
                                roleChip("canteen", Icons.fastfood_outlined),
                                roleChip("others", Icons.group_outlined),
                              ],
                            ),

                            const SizedBox(height: 30),

                            // 🚀 REGISTER BUTTON (ONLY THIS FULL WIDTH)
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF4A90E2),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
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
                                child: const Text(
                                  "Create Account",
                                  style: TextStyle(fontSize: 16),
                                ),
                              ),
                            ),

                            const SizedBox(height: 18),

                            GestureDetector(
                              onTap: () {
                                Navigator.pop(context);
                              },
                              child: const Text(
                                "Already have an account? Login",
                                style: TextStyle(
                                  color: Color(0xFF4A90E2),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}