import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/campus_service.dart';

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key, this.initialSearchQuery = ''});

  final String initialSearchQuery;

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> with WidgetsBindingObserver {
  final CampusService _service = CampusService();
  final TextEditingController _searchController = TextEditingController();

  String? _currentUid;
  bool _loading = true;
  bool _isCheckingOut = false;
  bool _hasAttendanceIntentToday = false;
  String _searchQuery = '';
  String _selectedCategory = 'All';

  List<Map<String, dynamic>> _menu = [];
  final Map<String, int> _quantities = {};
  final Map<String, _CartLine> _cart = {};

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _loadMenu();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _searchController.text = widget.initialSearchQuery;
    _searchQuery = widget.initialSearchQuery.trim();
    _restoreCart();
    _loadMenu();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    super.dispose();
  }

  int _readInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is double) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  String _itemKey(Map<String, dynamic> item) {
    final key =
        item['id']?.toString() ??
        item['item_id']?.toString() ??
        item['name']?.toString() ??
        item.toString();
    return key;
  }

  String _titleCase(String value) {
    final cleaned = value.trim();
    if (cleaned.isEmpty) return 'General';
    return cleaned
        .split(RegExp(r'[_\s]+'))
        .map((word) {
          if (word.isEmpty) return word;
          return '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}';
        })
        .join(' ');
  }

  IconData _categoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'breakfast':
        return Icons.free_breakfast_rounded;
      case 'beverage':
      case 'drinks':
        return Icons.local_cafe_rounded;
      case 'dessert':
      case 'sweet':
        return Icons.icecream_rounded;
      case 'rice':
      case 'meal':
      case 'lunch':
        return Icons.lunch_dining_rounded;
      case 'snack':
      case 'sandwich':
        return Icons.fastfood_rounded;
      default:
        return Icons.restaurant_menu_rounded;
    }
  }

  int _bonusPointsForCategory(String category, int quantity) {
    final normalized = category.trim().toLowerCase();
    if (quantity <= 0) return 0;
    if (normalized == 'meal' || normalized == 'lunch' || normalized == 'rice') {
      return quantity * 6;
    }
    if (normalized == 'breakfast' ||
        normalized == 'snack' ||
        normalized == 'sandwich') {
      return quantity * 4;
    }
    if (normalized == 'dessert' ||
        normalized == 'sweet' ||
        normalized == 'beverage' ||
        normalized == 'drinks') {
      return quantity * 2;
    }
    return quantity * 3;
  }

  int _estimatedPointsForItem(Map<String, dynamic> item, int quantity) {
    final category = item['category']?.toString() ?? 'general';
    final basePoints = quantity <= 0
        ? 0
        : (quantity * 10 < 10 ? 10 : quantity * 10);
    return basePoints + _bonusPointsForCategory(category, quantity);
  }

  String _rewardLabel(int points) {
    if (points >= 500) return 'Free meal unlocked';
    if (points >= 250) return '10% discount active';
    if (points >= 100) return '5% discount active';
    return 'Building toward your first reward';
  }

  int get _cartQuantity {
    return _cart.values.fold<int>(0, (sum, line) => sum + line.quantity);
  }

  int get _cartSubtotal {
    return _cart.values.fold<int>(0, (sum, line) => sum + line.subtotal);
  }

  int get _cartBonusPoints {
    return _cart.values.fold<int>(0, (sum, line) => sum + line.bonusPoints);
  }

  int get _cartEstimatedPoints {
    return _cart.values.fold<int>(0, (sum, line) => sum + line.estimatedPoints);
  }

  String get _cartPreviewNames {
    final entries = _cart.values.toList();
    if (entries.isEmpty) return 'No items added yet';
    final preview = entries
        .take(2)
        .map(
          (line) => line.quantity > 1
              ? '${line.itemName} x${line.quantity}'
              : line.itemName,
        )
        .join(', ');
    if (entries.length <= 2) return preview;
    return '$preview +${entries.length - 2} more';
  }

  _CartLine _cartLineFromMap(Map<String, dynamic> payload) {
    return _CartLine(
      key: payload['key']?.toString() ?? payload['itemName']?.toString() ?? '',
      itemName: payload['itemName']?.toString() ?? 'Menu item',
      category: payload['category']?.toString() ?? 'general',
      price: _readInt(payload['price']),
      quantity: _readInt(payload['quantity'], fallback: 1).clamp(1, 10),
    );
  }

  Map<String, dynamic> _cartLineToMap(_CartLine line) {
    return <String, dynamic>{
      'key': line.key,
      'itemName': line.itemName,
      'category': line.category,
      'price': line.price,
      'quantity': line.quantity,
    };
  }

  void _persistCart() {
    final uid = _currentUid;
    if (uid == null) return;

    final snapshot = _cart.values.map(_cartLineToMap).toList();
    if (snapshot.isEmpty) {
      _service.clearSavedCart(uid: uid).catchError((_) {});
      return;
    }
    _service.saveCart(uid: uid, cart: snapshot).catchError((_) {});
  }

  Future<void> _restoreCart() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _currentUid = user.uid;
    final savedCart = await _service.getSavedCart(uid: user.uid);
    if (!mounted || savedCart.isEmpty) return;

    final restored = <String, _CartLine>{};
    for (final entry in savedCart) {
      final line = _cartLineFromMap(entry);
      if (line.key.isEmpty) continue;
      restored[line.key] = line;
    }

    if (!mounted) return;
    setState(() {
      _cart
        ..clear()
        ..addAll(restored);
    });
  }

  Future<void> _loadMenu() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _currentUid = user.uid;
      final intentDate = await _service.getAttendanceIntent(uid: user.uid);
      final now = DateTime.now();
      final todayKey =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      _hasAttendanceIntentToday = intentDate == todayKey;
    }

    setState(() {
      _loading = true;
    });

    try {
      final menu = await _service.getMenu();
      final nextQuantities = <String, int>{};
      for (final item in menu) {
        final key = _itemKey(item);
        nextQuantities[key] = _quantities[key] ?? 1;
      }

      if (!mounted) return;
      setState(() {
        _menu = menu;
        _quantities
          ..clear()
          ..addAll(nextQuantities);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _menu = [];
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Load menu failed: $e')));
    }
  }

  List<String> get _categories {
    final values =
        _menu
            .map((item) => item['category']?.toString().trim() ?? '')
            .where((category) => category.isNotEmpty)
            .map(_titleCase)
            .toSet()
            .toList()
          ..sort();
    return ['All', ...values];
  }

  List<Map<String, dynamic>> get _filteredMenu {
    return _menu.where((item) {
      final name = item['name']?.toString().toLowerCase() ?? '';
      final category = _titleCase(item['category']?.toString() ?? 'General');
      final matchesSearch =
          _searchQuery.trim().isEmpty ||
          name.contains(_searchQuery.trim().toLowerCase());
      final matchesCategory =
          _selectedCategory == 'All' || category == _selectedCategory;
      return matchesSearch && matchesCategory;
    }).toList();
  }

  void _updateQuantity(String key, int nextValue) {
    setState(() {
      _quantities[key] = nextValue.clamp(1, 10);
    });
  }

  void _addToCart(Map<String, dynamic> item) {
    final key = _itemKey(item);
    final selectedQuantity = _quantities[key] ?? 1;
    final price = _readInt(item['price']);
    final itemName = item['name']?.toString() ?? 'Menu item';
    final category = item['category']?.toString() ?? 'general';

    if (price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This item is not available for ordering yet.'),
        ),
      );
      return;
    }

    final existing = _cart[key];
    final nextQuantity = (existing?.quantity ?? 0) + selectedQuantity;
    final nextLine = _CartLine(
      key: key,
      itemName: itemName,
      category: category,
      price: price,
      quantity: nextQuantity,
    );

    setState(() {
      _cart[key] = nextLine;
      _quantities[key] = 1;
    });
    _persistCart();

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            '$selectedQuantity x $itemName added to cart. Est. +${nextLine.estimatedPoints} pts for this line.',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  void _removeFromCart(String key) {
    setState(() {
      _cart.remove(key);
    });
    _persistCart();
  }

  Future<void> _checkoutCart() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _cart.isEmpty || _isCheckingOut) return;

    setState(() {
      _isCheckingOut = true;
    });

    final entries = _cart.entries.toList();
    try {
      final result = await _service.placeCartOrder(
        uid: user.uid,
        items: entries
            .map(
              (entry) => <String, dynamic>{
                'item': entry.value.itemName,
                'price': entry.value.price,
                'quantity': entry.value.quantity,
                'category': entry.value.category,
              },
            )
            .toList(),
      );

      if (!mounted) return;

      final batchId = result['order_batch_id']?.toString();
      final orderToken = result['order_token']?.toString();
      final counterMessage =
          result['counter_message']?.toString() ??
          'Show your order ID at the canteen counter.';
      final totalAwarded = _readInt(result['points_awarded']);
      final totalBonus = _readInt(result['bonus_points']);
      final totalCost = _readInt(result['total_cost']);
      final totalItems = _readInt(result['quantity_total']);
      final latestTotalPoints = _readInt(result['total_points']);
      final attendanceAwarded = _readInt(result['attendance_points_awarded']);
      final attendanceMarked = result['attendance_marked'] == true;

      setState(() {
        for (final key in _cart.keys.toList()) {
          _quantities[key] = 1;
        }
        _cart.clear();
        _isCheckingOut = false;
        _hasAttendanceIntentToday = false;
      });
      _persistCart();

      await _service.clearAttendanceIntent(uid: user.uid);
      if (!mounted) return;

      final reward = _rewardLabel(latestTotalPoints);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Order ID ${orderToken ?? batchId ?? 'N/A'}: '
              '$totalItems item${totalItems == 1 ? '' : 's'} for Rs. $totalCost. '
              '+$totalAwarded pts (incl. $totalBonus bonus)'
              '${attendanceMarked && attendanceAwarded > 0 ? ' +$attendanceAwarded attendance' : ''}. '
              '$reward. $counterMessage',
            ),
            duration: const Duration(seconds: 4),
          ),
        );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isCheckingOut = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  void _openCartSheet() {
    if (_cart.isEmpty) return;

    final width = MediaQuery.of(context).size.width;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final entries = _cart.values.toList();
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.72,
              maxWidth: width > 720 ? 700 : width,
            ),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Your Cart',
                        style: TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFBBF7D0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '₹$_cartSubtotal total • $_cartQuantity item${_cartQuantity == 1 ? '' : 's'}',
                        style: const TextStyle(
                          color: Color(0xFF166534),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Estimated +$_cartEstimatedPoints total points, with $_cartBonusPoints bonus points already included.',
                        style: const TextStyle(
                          color: Color(0xFF166534),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView.separated(
                    itemCount: entries.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final line = entries[index];
                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFF0F766E,
                                ).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(
                                _categoryIcon(_titleCase(line.category)),
                                color: const Color(0xFF0F766E),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    line.itemName,
                                    style: const TextStyle(
                                      color: Color(0xFF0F172A),
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${_titleCase(line.category)} • Qty ${line.quantity}',
                                    style: const TextStyle(
                                      color: Color(0xFF64748B),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Est. +${line.estimatedPoints} pts',
                                    style: const TextStyle(
                                      color: Color(0xFF2563EB),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '₹${line.subtotal}',
                                  style: const TextStyle(
                                    color: Color(0xFF0F766E),
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                TextButton(
                                  onPressed: _isCheckingOut
                                      ? null
                                      : () {
                                          Navigator.of(sheetContext).pop();
                                          _removeFromCart(line.key);
                                        },
                                  child: const Text('Remove'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _isCheckingOut
                        ? null
                        : () {
                            Navigator.of(sheetContext).pop();
                            _checkoutCart();
                          },
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0F766E),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    icon: _isCheckingOut
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.shopping_bag_rounded),
                    label: Text(
                      _isCheckingOut
                          ? 'Placing order...'
                          : 'Checkout • ₹$_cartSubtotal',
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredMenu = _filteredMenu;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),
      appBar: AppBar(
        title: const Text("Today's Menu"),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _loadMenu,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      bottomNavigationBar: _cart.isEmpty
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _buildCartBar(),
            ),
      body: RefreshIndicator(
        onRefresh: _loadMenu,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(18, 12, 18, _cart.isEmpty ? 28 : 36),
          children: [
            _buildHeaderCard(filteredMenu.length),
            const SizedBox(height: 18),
            if (_hasAttendanceIntentToday) ...[
              _buildIntentBanner(),
              const SizedBox(height: 18),
            ],
            _buildSearchCard(),
            const SizedBox(height: 18),
            _buildCategoryChips(),
            const SizedBox(height: 18),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (filteredMenu.isEmpty)
              _buildEmptyState()
            else
              ...filteredMenu.map(_buildMenuCard),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCard(int visibleCount) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F766E), Color(0xFF2563EB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Text(
              'Approved menu only',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Build your cart, checkout once, and use the order ID at the canteen counter.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _cart.isEmpty
                ? '$visibleCount item${visibleCount == 1 ? '' : 's'} visible in your current view'
                : 'Cart: $_cartQuantity item${_cartQuantity == 1 ? '' : 's'} • Est. +$_cartEstimatedPoints pts',
            style: const TextStyle(
              color: Color(0xFFE0F2FE),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIntentBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF2FF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFC7D2FE)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.fact_check_rounded, color: Color(0xFF4F46E5)),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Attendance intent is saved for today. Finish checkout to confirm attendance and receive your order ID.',
              style: TextStyle(
                color: Color(0xFF3730A3),
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (value) {
          setState(() {
            _searchQuery = value;
          });
        },
        decoration: InputDecoration(
          hintText: 'Search food items',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: _searchQuery.isEmpty
              ? null
              : IconButton(
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _searchQuery = '';
                    });
                  },
                  icon: const Icon(Icons.close_rounded),
                ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: const Color(0xFFF8FAFC),
        ),
      ),
    );
  }

  Widget _buildCategoryChips() {
    final categories = _categories;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: categories.map((category) {
        final isSelected = _selectedCategory == category;
        return ChoiceChip(
          label: Text(category),
          selected: isSelected,
          onSelected: (_) {
            setState(() {
              _selectedCategory = category;
            });
          },
          labelStyle: TextStyle(
            color: isSelected ? Colors.white : const Color(0xFF334155),
            fontWeight: FontWeight.w700,
          ),
          selectedColor: const Color(0xFF0F766E),
          backgroundColor: Colors.white,
          side: BorderSide(
            color: isSelected
                ? const Color(0xFF0F766E)
                : const Color(0xFFE2E8F0),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: const Column(
        children: [
          Icon(Icons.no_food_rounded, size: 44, color: Color(0xFF94A3B8)),
          SizedBox(height: 12),
          Text(
            'No menu items match your current search.',
            style: TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 8),
          Text(
            'Try a different category or clear the search input.',
            style: TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildMenuCard(Map<String, dynamic> item) {
    final key = _itemKey(item);
    final category = _titleCase(item['category']?.toString() ?? 'General');
    final rawCategory = item['category']?.toString() ?? 'general';
    final itemName = item['name']?.toString() ?? 'Menu item';
    final price = _readInt(item['price']);
    final quantity = _quantities[key] ?? 1;
    final estimatedPoints = _estimatedPointsForItem(item, quantity);
    final bonusPoints = _bonusPointsForCategory(rawCategory, quantity);
    final cartQuantity = _cart[key]?.quantity ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFF0F766E).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  _categoryIcon(category),
                  color: const Color(0xFF0F766E),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      itemName,
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      category,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (cartQuantity > 0) ...[
                      const SizedBox(height: 6),
                      Text(
                        '$cartQuantity already in cart',
                        style: const TextStyle(
                          color: Color(0xFF2563EB),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '₹$price',
                  style: const TextStyle(
                    color: Color(0xFF0F766E),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '+$estimatedPoints pts',
                  style: const TextStyle(
                    color: Color(0xFF2563EB),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (bonusPoints > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F3FF),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$bonusPoints bonus pts',
                    style: const TextStyle(
                      color: Color(0xFF7C3AED),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: quantity > 1
                          ? () => _updateQuantity(key, quantity - 1)
                          : null,
                      icon: const Icon(Icons.remove_rounded),
                    ),
                    Text(
                      '$quantity',
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    IconButton(
                      onPressed: quantity < 10
                          ? () => _updateQuantity(key, quantity + 1)
                          : null,
                      icon: const Icon(Icons.add_rounded),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _isCheckingOut ? null : () => _addToCart(item),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0F766E),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                ),
                icon: const Icon(Icons.add_shopping_cart_rounded),
                label: Text(
                  cartQuantity > 0
                      ? 'Add More • ₹${price * quantity}'
                      : 'Add to Cart • ₹${price * quantity}',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCartBar() {
    return Material(
      color: Colors.transparent,
      elevation: 12,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 120),
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: InkWell(
                onTap: _openCartSheet,
                borderRadius: BorderRadius.circular(18),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Cart • $_cartQuantity item${_cartQuantity == 1 ? '' : 's'} • ₹$_cartSubtotal',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _cartPreviewNames,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFCBD5E1),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Est. +$_cartEstimatedPoints total pts, $_cartBonusPoints bonus included',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF93C5FD),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton(
                  onPressed: _isCheckingOut ? null : _openCartSheet,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF0F172A),
                  ),
                  child: const Text('View Cart'),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _isCheckingOut ? null : _checkoutCart,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0F766E),
                    foregroundColor: Colors.white,
                  ),
                  child: Text(_isCheckingOut ? 'Placing...' : 'Checkout'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CartLine {
  const _CartLine({
    required this.key,
    required this.itemName,
    required this.category,
    required this.price,
    required this.quantity,
  });

  final String key;
  final String itemName;
  final String category;
  final int price;
  final int quantity;

  int get subtotal => price * quantity;

  int get bonusPoints {
    final normalized = category.trim().toLowerCase();
    if (normalized == 'meal' || normalized == 'lunch' || normalized == 'rice') {
      return quantity * 6;
    }
    if (normalized == 'breakfast' ||
        normalized == 'snack' ||
        normalized == 'sandwich') {
      return quantity * 4;
    }
    if (normalized == 'dessert' ||
        normalized == 'sweet' ||
        normalized == 'beverage' ||
        normalized == 'drinks') {
      return quantity * 2;
    }
    return quantity * 3;
  }

  int get estimatedPoints {
    final base = quantity * 10 < 10 ? 10 : quantity * 10;
    return base + bonusPoints;
  }
}
