import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/campus_service.dart';

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  final CampusService _service = CampusService();
  bool _loading = true;
  List<Map<String, dynamic>> _menu = [];

  @override
  void initState() {
    super.initState();
    _loadMenu();
  }

  Future<void> _loadMenu() async {
    setState(() {
      _loading = true;
    });
    try {
      _menu = await _service.getMenu();
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Load menu failed: $e')));
      _menu = [];
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> placeOrder(BuildContext context, String item, int price) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await _service.placeOrder(
        uid: user.uid,
        item: item,
        price: price,
        quantity: 1,
      );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("$item ordered successfully")));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Order failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Today's Menu")),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _menu.isEmpty
          ? const Center(child: Text("No menu available"))
          : ListView.builder(
              itemCount: _menu.length,
              itemBuilder: (context, index) {
                final data = _menu[index];
                final itemName = data['name']?.toString() ?? 'Unnamed Item';
                final itemPrice = data['price'] is int
                    ? data['price']
                    : int.tryParse(data['price']?.toString() ?? '') ?? 0;
                return Card(
                  margin: const EdgeInsets.all(10),
                  child: ListTile(
                    title: Text(itemName),
                    subtitle: Text("₹$itemPrice"),
                    trailing: ElevatedButton(
                      onPressed: itemPrice > 0
                          ? () {
                              placeOrder(context, itemName, itemPrice);
                            }
                          : null,
                      child: const Text("Order"),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
