import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../auth/login_screen.dart';
import 'menu_screen.dart';
import 'attendance_screen.dart';
import 'leaderboard_screen.dart';
import 'rewards_screen.dart';

class StudentDashboard extends StatelessWidget {
  const StudentDashboard({super.key});

  Widget dashboardCard(
      BuildContext context,
      String title,
      IconData icon,
      Widget screen,
      ) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => screen),
        );
      },
      child: Card(
        elevation: 5,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            color: Colors.blue.shade50,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 40, color: Colors.blue),
              const SizedBox(height: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              )
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
        title: const Text("Student Dashboard"),
        centerTitle: true,

        actions: [

          /// 🔔 Notification Icon
          IconButton(
            icon: const Icon(Icons.notifications_none),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("No notifications yet"),
                ),
              );
            },
          ),

          /// 👤 Profile Menu
          PopupMenuButton<String>(
            icon: const CircleAvatar(
              radius: 16,
              child: Icon(Icons.person, size: 18),
            ),
            onSelected: (value) async {

              if (value == "profile") {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Profile page coming soon")),
                );
              }

              if (value == "logout") {
                await AuthService().logout();

                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const LoginScreen(),
                  ),
                );
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: "profile",
                child: Row(
                  children: [
                    Icon(Icons.person),
                    SizedBox(width: 10),
                    Text("Profile"),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: "logout",
                child: Row(
                  children: [
                    Icon(Icons.logout),
                    SizedBox(width: 10),
                    Text("Logout"),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(width: 10),
        ],
      ),

      body: Padding(
        padding: const EdgeInsets.all(16),
        child: GridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: 15,
          mainAxisSpacing: 15,
          children: [

            dashboardCard(
              context,
              "View Menu",
              Icons.restaurant_menu,
              const MenuScreen(),
            ),

            dashboardCard(
              context,
              "Mark Attendance",
              Icons.check_circle,
              const AttendanceScreen(),
            ),

            dashboardCard(
              context,
              "Leaderboard",
              Icons.emoji_events,
              const LeaderboardScreen(),
            ),

            dashboardCard(
              context,
              "My Rewards",
              Icons.card_giftcard,
              const RewardsScreen(),
            ),

          ],
        ),
      ),
    );
  }
}