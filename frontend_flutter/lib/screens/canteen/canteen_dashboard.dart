import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../auth/login_screen.dart';
import 'menu_upload_screen.dart';
import 'inventory_screen.dart';
import 'menu_upload_screen.dart';
import 'prediction_screen.dart';
import 'waste_screen.dart';
import 'analytics_screen.dart';

class CanteenDashboard extends StatelessWidget {
  const CanteenDashboard({super.key});

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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            color: Colors.orange.shade50,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 40, color: Colors.orange),
              const SizedBox(height: 10),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
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
        title: const Text("Canteen Dashboard"),
        centerTitle: true,
        actions: [
          /// 🔔 Notification Icon
          IconButton(
            icon: const Icon(Icons.notifications_none),
            onPressed: () {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text("No notifications")));
            },
          ),

          /// 👤 Profile Menu
          PopupMenuButton<String>(
            icon: const CircleAvatar(
              radius: 16,
              child: Icon(Icons.person, size: 18),
            ),
            onSelected: (value) async {
              if (value == "logout") {
                await AuthService().logout();

                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
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
              "Upload Menu",
              Icons.restaurant_menu,
              const MenuUploadScreen(),
            ),

            dashboardCard(
              context,
              "View Orders",
              Icons.receipt_long,
              const InventoryScreen(),
            ),

            dashboardCard(
              context,
              "Food Analytics",
              Icons.analytics,
              const PredictionScreen(),
            ),

            dashboardCard(
              context,
              "Food Waste",
              Icons.delete_outline,
              const WasteScreen(),
            ),

            dashboardCard(
              context,
              "Analytics",
              Icons.analytics,
              const AnalyticsScreen(),
            ),
          ],
        ),
      ),
    );
  }
}
