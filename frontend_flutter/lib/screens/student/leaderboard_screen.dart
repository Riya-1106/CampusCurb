import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/campus_service.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  final CampusService _service = CampusService();
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  String _searchQuery = '';
  String? _errorMessage;
  List<Map<String, dynamic>> _leaderboard = [];

  int _readInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is double) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  @override
  void initState() {
    super.initState();
    _loadLeaderboard();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadLeaderboard() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final entries = await _service.getLeaderboard();
      if (!mounted) return;
      setState(() {
        _leaderboard = entries;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _leaderboard = [];
        _isLoading = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  List<Map<String, dynamic>> get _filteredLeaderboard {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return _leaderboard;
    return _leaderboard.where((entry) {
      final name = entry['name']?.toString().toLowerCase() ?? '';
      final email = entry['email']?.toString().toLowerCase() ?? '';
      final role = entry['role']?.toString().toLowerCase() ?? '';
      return name.contains(query) || email.contains(query) || role.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final filtered = _filteredLeaderboard;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),
      appBar: AppBar(
        title: const Text('Leaderboard'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _loadLeaderboard,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadLeaderboard,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
          children: [
            _buildHeroCard(),
            const SizedBox(height: 18),
            _buildSearchCard(),
            if (_errorMessage != null) ...[
              const SizedBox(height: 18),
              _buildErrorBanner(_errorMessage!),
            ],
            const SizedBox(height: 18),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (filtered.isEmpty)
              _buildEmptyState()
            else
              ...filtered.map((entry) => _buildRankCard(entry, currentUid)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroCard() {
    final topPoints = _leaderboard.isEmpty ? 0 : _readInt(_leaderboard.first['points']);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF97316), Color(0xFFEF4444)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Campus Ranking',
            style: TextStyle(
              color: Color(0xFFFFEDD5),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'See who is leading on engagement and rewards.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _leaderboard.isEmpty
                ? 'Rankings will appear once users start earning points.'
                : 'Current top score: $topPoints points',
            style: const TextStyle(
              color: Color(0xFFFEE2E2),
              fontWeight: FontWeight.w600,
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
          hintText: 'Search by name, email, or role',
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

  Widget _buildErrorBanner(String message) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFF991B1B),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: const Column(
        children: [
          Icon(Icons.emoji_events_outlined, size: 42, color: Color(0xFF94A3B8)),
          SizedBox(height: 12),
          Text(
            'No leaderboard entries found.',
            style: TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Once points are available, rankings will show here.',
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

  Widget _buildRankCard(Map<String, dynamic> entry, String? currentUid) {
    final rank = _readInt(entry['rank']);
    final points = _readInt(entry['points']);
    final isCurrentUser = currentUid != null && entry['uid'] == currentUid;
    final role = entry['role']?.toString().trim().isNotEmpty == true
        ? entry['role'].toString().trim()
        : 'student';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isCurrentUser ? const Color(0xFFEEF6FF) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isCurrentUser
              ? const Color(0xFF93C5FD)
              : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: _rankColor(rank).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Text(
                '#$rank',
                style: TextStyle(
                  color: _rankColor(rank),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry['name']?.toString() ?? 'Campus User',
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  entry['email']?.toString() ?? '',
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _pill(role.toUpperCase()),
                    _pill(entry['reward']?.toString() ?? 'No reward'),
                    if (isCurrentUser) _pill('YOU'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '$points pts',
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF475569),
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Color _rankColor(int rank) {
    if (rank == 1) return const Color(0xFFF59E0B);
    if (rank == 2) return const Color(0xFF64748B);
    if (rank == 3) return const Color(0xFFF97316);
    return const Color(0xFF2563EB);
  }
}
