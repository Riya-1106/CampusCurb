import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/auth_service.dart';
import '../../services/college_exchange_service.dart';
import '../auth/college_access_screen.dart';
import '../shared/profile_screen.dart';

class CollegeDashboard extends StatefulWidget {
  const CollegeDashboard({super.key});

  @override
  State<CollegeDashboard> createState() => _CollegeDashboardState();
}

class _CollegeDashboardState extends State<CollegeDashboard> {
  final CollegeExchangeService _service = CollegeExchangeService();
  final AuthService _authService = AuthService();

  static const String _pickupHubNameFallback = 'Campus Curb Main Canteen Gate';
  static const String _pickupHubAddressFallback =
      'Student campus pickup counter for approved surplus collections.';
  static const String _pickupHubMapQueryFallback =
      'Campus Curb Main Canteen Gate';

  bool _isLoading = true;
  List<Map<String, dynamic>> _availableListings = [];
  List<Map<String, dynamic>> _myRequests = [];

  List<Map<String, dynamic>> get _canteenWasteListings => _availableListings
      .where((listing) => listing['source'] == 'canteen_waste')
      .toList();

  int get _livePortions => _canteenWasteListings.fold<int>(
    0,
    (sum, listing) => sum + _asInt(listing['remaining_quantity']),
  );

  int get _pendingRequests => _myRequests
      .where((request) => _requestStatus(request) == 'pending')
      .length;

  int get _approvedRequests => _myRequests
      .where((request) => _requestStatus(request) == 'approved')
      .length;

  List<String> get _pickupWindows {
    final seen = <String>{};
    final windows = <String>[];
    for (final listing in _canteenWasteListings) {
      final value = listing['pickup_window']?.toString().trim() ?? '';
      if (value.isEmpty || seen.contains(value)) {
        continue;
      }
      seen.add(value);
      windows.add(value);
    }
    return windows;
  }

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final results = await Future.wait([
        _service.getAvailableListings(),
        _service.getMyRequests(),
      ]);
      _availableListings = results[0];
      _myRequests = results[1];
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load college pickup data: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _showRequestDialog(Map<String, dynamic> listing) async {
    final rootContext = context;
    final quantityController = TextEditingController(text: '1');
    final pickupTimeController = TextEditingController(
      text: (listing['pickup_window'] ?? '').toString(),
    );
    final notesController = TextEditingController(
      text:
          'Thakur College pickup team will collect this from the canteen gate.',
    );

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Request ${listing['food_item'] ?? 'Food'}'),
            const SizedBox(height: 8),
            Text(
              'Tell the student campus what quantity you need and when your college will come for pickup.',
              style: TextStyle(
                color: Colors.blueGrey.shade600,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _dialogInfoRow(
                Icons.inventory_2_outlined,
                'Available now',
                '${_asInt(listing['remaining_quantity'])} ${listing['unit'] ?? 'portions'}',
              ),
              const SizedBox(height: 10),
              _dialogInfoRow(
                Icons.schedule_outlined,
                'Suggested slot',
                _displayPickupWindow(listing),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: quantityController,
                decoration: InputDecoration(
                  labelText:
                      'Quantity to collect (max ${_asInt(listing['remaining_quantity'])})',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 14),
              TextField(
                controller: pickupTimeController,
                decoration: InputDecoration(
                  labelText: 'Pickup time your college wants',
                  hintText: '26 Apr • 5:00 PM',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: notesController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Pickup note',
                  hintText: 'Our team will collect from the main canteen gate.',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(dialogContext);
              final navigator = Navigator.of(dialogContext);
              final quantity = int.tryParse(quantityController.text.trim());
              if (quantity == null || quantity <= 0) {
                messenger.showSnackBar(
                  const SnackBar(content: Text('Enter a valid quantity.')),
                );
                return;
              }
              await _service.requestFood(
                listingId: listing['id'].toString(),
                quantity: quantity,
                preferredPickupTime: pickupTimeController.text.trim(),
                notes: notesController.text.trim(),
              );
              if (!dialogContext.mounted || !rootContext.mounted) return;
              navigator.pop();
              await _refresh();
              if (!rootContext.mounted) return;
              ScaffoldMessenger.of(rootContext).showSnackBar(
                SnackBar(
                  content: Text(
                    'Pickup request sent for ${listing['food_item']}. The student campus can now review the requested time.',
                  ),
                ),
              );
            },
            icon: const Icon(Icons.local_shipping_outlined),
            label: const Text('Confirm Pickup Request'),
          ),
        ],
      ),
    );
  }

  Future<void> _openMap({Map<String, dynamic>? listing}) async {
    final query = (listing?['pickup_map_query'] ?? _pickupHubMapQueryFallback)
        .toString()
        .trim();
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(query)}',
    );
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open maps on this device.')),
      );
    }
  }

  Widget _dialogInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFFE8F3F4),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: const Color(0xFF0D6E6E)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: Colors.blueGrey.shade500,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _heroPanel(double width) {
    final collegeLabel = _collegeLabel();
    final narrow = width < 760;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: const LinearGradient(
          colors: [Color(0xFF0C7C77), Color(0xFF2E63D9)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A4F9A).withValues(alpha: 0.18),
            blurRadius: 30,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _heroChip(Icons.apartment_rounded, '$collegeLabel pickup desk'),
              _heroChip(
                Icons.volunteer_activism_outlined,
                'Receive-only portal',
              ),
              _heroChip(
                Icons.schedule_outlined,
                _pickupWindows.isEmpty
                    ? 'Waiting for next waste batch'
                    : '${_pickupWindows.length} pickup slot${_pickupWindows.length == 1 ? '' : 's'} live',
              ),
            ],
          ),
          const SizedBox(height: 22),
          const Text(
            'Request surplus from the student campus canteen and schedule your pickup clearly.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 34,
              height: 1.08,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'This portal is for receiving food only. Your college does not post surplus here. Instead, it sees the latest canteen waste batch, selects items, proposes a pickup time, and tracks the collection request.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 15,
              height: 1.45,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 22),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              _heroStat(
                title: 'Live items',
                value: '${_canteenWasteListings.length}',
                accent: const Color(0xFFBFF6E8),
              ),
              _heroStat(
                title: 'Portions ready',
                value: '$_livePortions',
                accent: const Color(0xFFD8E5FF),
              ),
              _heroStat(
                title: 'Pending approval',
                value: '$_pendingRequests',
                accent: const Color(0xFFFFDFC6),
              ),
              _heroStat(
                title: 'Approved pickups',
                value: '$_approvedRequests',
                accent: const Color(0xFFCFF7D6),
              ),
            ],
          ),
          if (!narrow) ...[
            const SizedBox(height: 24),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: _canteenWasteListings.isEmpty
                      ? null
                      : () => _showRequestDialog(_canteenWasteListings.first),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF0D6E6E),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                  ),
                  icon: const Icon(Icons.shopping_bag_outlined),
                  label: const Text('Request First Available Item'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _openMap,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                  ),
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('Open Route to Pickup Gate'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _heroChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroStat({
    required String title,
    required String value,
    required Color accent,
  }) {
    return Container(
      width: 170,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            value,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _pickupMapCard(double width) {
    final narrow = width < 800;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.blueGrey.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Flex(
        direction: narrow ? Axis.vertical : Axis.horizontal,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: narrow ? 0 : 5, child: _mapPreview()),
          SizedBox(width: narrow ? 0 : 22, height: narrow ? 18 : 0),
          Expanded(
            flex: narrow ? 0 : 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionEyebrow('Pickup Route'),
                const SizedBox(height: 10),
                const Text(
                  'Where Thakur College should go',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF172034),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'All accepted surplus in this portal is collected from the student campus pickup hub. Use the map button if your team needs directions before leaving.',
                  style: TextStyle(
                    color: Colors.blueGrey.shade600,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 18),
                _locationDetail(
                  Icons.place_outlined,
                  _pickupHubNameFallback,
                  _pickupHubAddressFallback,
                ),
                const SizedBox(height: 12),
                _locationDetail(
                  Icons.access_time_rounded,
                  _pickupWindows.isEmpty
                      ? 'Next slot pending'
                      : 'Pickup windows live',
                  _pickupWindows.isEmpty
                      ? 'The next waste batch will appear here once the canteen uploads it.'
                      : _pickupWindows.join('  •  '),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed: _openMap,
                      icon: const Icon(Icons.map_outlined),
                      label: const Text('Open in Maps'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Refresh Slots'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _mapPreview() {
    return Container(
      height: 248,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFFE6F3FF), Color(0xFFEDF8F2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: const Color(0xFFD1E5F2)),
      ),
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _MiniMapPainter())),
          Positioned(
            left: 20,
            bottom: 26,
            child: _mapPin(
              color: const Color(0xFF7B4DFF),
              title: _collegeLabel(),
              subtitle: 'Requesting college',
            ),
          ),
          Positioned(
            right: 20,
            top: 24,
            child: _mapPin(
              color: const Color(0xFF0D6E6E),
              title: 'Student campus',
              subtitle: 'Pickup gate',
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 14,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.86),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'Follow this route after your pickup request is approved.',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF24324A),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mapPin({
    required Color color,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.2),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(
                subtitle,
                style: TextStyle(color: Colors.blueGrey.shade500, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _locationDetail(IconData icon, String title, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFFEAF3FE),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: const Color(0xFF2E63D9)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF172034),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(color: Colors.blueGrey.shade600, height: 1.4),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionEyebrow(String text) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        letterSpacing: 1.1,
        fontWeight: FontWeight.w800,
        color: Color(0xFF0D6E6E),
        fontSize: 12,
      ),
    );
  }

  Widget _sectionTitle(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: Color(0xFF172034),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: TextStyle(color: Colors.blueGrey.shade600, height: 1.45),
        ),
      ],
    );
  }

  Widget _pickupWindowsStrip() {
    if (_pickupWindows.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFE3EAF0)),
        ),
        child: const Text(
          'Pickup windows will appear here once the canteen uploads the latest waste batch.',
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE3EAF0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Latest pickup windows',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _pickupWindows
                .map(
                  (slot) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE9F8F3),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      slot,
                      style: const TextStyle(
                        color: Color(0xFF0D6E6E),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSurplusCard(Map<String, dynamic> listing, double width) {
    final remaining = _asInt(listing['remaining_quantity']);
    final confidenceLabel =
        listing['confidence_label']?.toString().trim() ?? '';
    final window = _displayPickupWindow(listing);
    final narrow = width < 640;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.blueGrey.withValues(alpha: 0.07),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flex(
            direction: narrow ? Axis.vertical : Axis.horizontal,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          listing['food_item']?.toString() ?? 'Unknown item',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF172034),
                          ),
                        ),
                        _statusChip('Live surplus', const Color(0xFF0D6E6E)),
                        if (confidenceLabel.isNotEmpty)
                          _statusChip(
                            '$confidenceLabel confidence',
                            const Color(0xFF2E63D9),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'The student campus canteen has logged this item as available for pickup.',
                      style: TextStyle(
                        color: Colors.blueGrey.shade600,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: narrow ? 0 : 16, height: narrow ? 16 : 0),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F8F8),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$remaining ${listing['unit'] ?? 'portions'}',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0D6E6E),
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Ready to collect',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _detailPill(Icons.schedule_outlined, window),
              _detailPill(
                Icons.place_outlined,
                (listing['pickup_location_name'] ?? _pickupHubNameFallback)
                    .toString(),
              ),
              _detailPill(Icons.inventory_2_outlined, 'Source: student campus'),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _showRequestDialog(listing),
                  icon: const Icon(Icons.local_shipping_outlined),
                  label: const Text('Schedule Pickup'),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () => _openMap(listing: listing),
                icon: const Icon(Icons.map_outlined),
                label: const Text('Map'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _detailPill(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F8FB),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF41536E)),
          const SizedBox(width: 8),
          Text(
            text,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xFF24324A),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _requestCard(Map<String, dynamic> request) {
    final status = request['status']?.toString() ?? 'pending';
    final pickupTime =
        request['preferred_pickup_time']?.toString().trim() ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE5EAF0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${request['food_item'] ?? 'Food'} • ${request['quantity'] ?? 0} ${request['unit'] ?? ''}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                    color: Color(0xFF172034),
                  ),
                ),
              ),
              _statusChip(_titleCase(status), _statusColor(status)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Thakur College requested this pickup from ${request['college_from'] ?? 'the student campus'}.',
            style: TextStyle(color: Colors.blueGrey.shade600, height: 1.45),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _detailPill(
                Icons.alarm_outlined,
                pickupTime.isEmpty ? 'Pickup time not set' : pickupTime,
              ),
              _detailPill(
                Icons.place_outlined,
                (request['pickup_location_name'] ?? _pickupHubNameFallback)
                    .toString(),
              ),
            ],
          ),
          if ((request['notes'] ?? '').toString().trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFD),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                request['notes'].toString(),
                style: TextStyle(color: Colors.blueGrey.shade700),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _openMap,
              icon: const Icon(Icons.map_outlined),
              label: const Text('View Pickup Route'),
            ),
          ),
        ],
      ),
    );
  }

  int _asInt(dynamic value) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _requestStatus(Map<String, dynamic> request) {
    return (request['status']?.toString() ?? '').trim().toLowerCase();
  }

  Color _statusColor(String status) {
    switch (status.trim().toLowerCase()) {
      case 'approved':
        return const Color(0xFF0D8C61);
      case 'rejected':
        return const Color(0xFFC14343);
      case 'completed':
        return const Color(0xFF2E63D9);
      default:
        return const Color(0xFFB86A16);
    }
  }

  String _displayPickupWindow(Map<String, dynamic> listing) {
    final pickup = listing['pickup_window']?.toString().trim() ?? '';
    if (pickup.isNotEmpty) {
      return pickup;
    }
    final date = listing['source_date']?.toString().trim() ?? '';
    final slot = listing['source_time_slot']?.toString().trim() ?? '';
    if (date.isNotEmpty && slot.isNotEmpty) {
      return '$date • $slot';
    }
    return 'Pickup window will be confirmed by the canteen';
  }

  String _collegeLabel() {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email?.trim() ?? '';
    final localPart = email.contains('@') ? email.split('@').first : email;
    if (localPart.isEmpty) {
      return 'Partner college';
    }
    return _titleCase(localPart.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), ' '));
  }

  String _titleCase(String value) {
    final words = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .map(
          (word) =>
              '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}',
        )
        .toList();
    return words.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final contentWidth = width > 1320 ? 1320.0 : width;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F7FB),
      appBar: AppBar(
        title: const Text('College Pickup Dashboard'),
        backgroundColor: const Color(0xFF0D6E6E),
        actions: [
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              );
            },
            icon: const Icon(Icons.person_outline),
          ),
          IconButton(
            onPressed: () async {
              await _authService.logout();
              if (!context.mounted) return;
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const CollegeAccessScreen()),
                (route) => false,
              );
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                children: [
                  Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: contentWidth),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _heroPanel(contentWidth),
                          const SizedBox(height: 22),
                          _pickupMapCard(contentWidth),
                          const SizedBox(height: 22),
                          _pickupWindowsStrip(),
                          const SizedBox(height: 26),
                          _sectionTitle(
                            'Available From Student Campus',
                            'These are the latest surplus items logged by the student canteen. Choose any item below and tell the campus when Thakur College will come to collect it.',
                          ),
                          const SizedBox(height: 14),
                          if (_canteenWasteListings.isEmpty)
                            Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: const Color(0xFFE2E8F0),
                                ),
                              ),
                              child: const Text(
                                'No student-campus surplus is visible right now. When the canteen saves new waste data, the items will appear here for pickup.',
                              ),
                            ),
                          ..._canteenWasteListings.map(
                            (listing) =>
                                _buildSurplusCard(listing, contentWidth),
                          ),
                          const SizedBox(height: 16),
                          _sectionTitle(
                            'My Pickup Requests',
                            'This confirms what your college asked to collect, the time you proposed, and the current approval state.',
                          ),
                          const SizedBox(height: 14),
                          if (_myRequests.isEmpty)
                            Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: const Color(0xFFE2E8F0),
                                ),
                              ),
                              child: const Text(
                                'No pickup requests yet. Choose an available surplus item above to schedule a collection time.',
                              ),
                            ),
                          ..._myRequests.map(_requestCard),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _MiniMapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final roadPaint = Paint()
      ..color = const Color(0xFFBDD5E9)
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final dottedPaint = Paint()
      ..color = const Color(0xFF2E63D9)
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final pathA = Path()
      ..moveTo(24, size.height - 54)
      ..quadraticBezierTo(
        size.width * 0.3,
        size.height * 0.56,
        size.width * 0.52,
        size.height * 0.52,
      )
      ..quadraticBezierTo(
        size.width * 0.72,
        size.height * 0.46,
        size.width - 34,
        44,
      );
    canvas.drawPath(pathA, roadPaint);

    for (double i = 0.06; i < 0.94; i += 0.08) {
      final x = size.width * i;
      canvas.drawLine(
        Offset(x, size.height * 0.14),
        Offset(x, size.height * 0.86),
        Paint()
          ..color = const Color(0xFFD6E4F2)
          ..strokeWidth = 1,
      );
    }
    for (double i = 0.12; i < 0.9; i += 0.14) {
      final y = size.height * i;
      canvas.drawLine(
        Offset(size.width * 0.08, y),
        Offset(size.width * 0.92, y),
        Paint()
          ..color = const Color(0xFFDDE8F1)
          ..strokeWidth = 1,
      );
    }

    final dashPath = Path()
      ..moveTo(46, size.height - 48)
      ..quadraticBezierTo(
        size.width * 0.28,
        size.height * 0.56,
        size.width * 0.52,
        size.height * 0.5,
      )
      ..quadraticBezierTo(
        size.width * 0.72,
        size.height * 0.43,
        size.width - 48,
        58,
      );

    for (final metric in dashPath.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final extracted = metric.extractPath(distance, distance + 12);
        canvas.drawPath(extracted, dottedPaint);
        distance += 20;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
