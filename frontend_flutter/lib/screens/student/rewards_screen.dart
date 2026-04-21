import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/campus_service.dart';
import '../../services/prediction_service.dart';

class RewardsScreen extends StatefulWidget {
  const RewardsScreen({super.key});

  @override
  State<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends State<RewardsScreen> {
  final CampusService _campusService = CampusService();
  final PredictionService _predictionService = PredictionService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const Duration _rewardsTimeout = Duration(milliseconds: 1500);

  bool _isLoading = true;
  int _points = 0;
  String _reward = 'No reward';
  String _name = 'Student';

  static const List<int> _milestones = [100, 250, 500];

  @override
  void initState() {
    super.initState();
    _loadRewards();
  }

  int? get _nextMilestone {
    for (final target in _milestones) {
      if (_points < target) return target;
    }
    return null;
  }

  double get _progressValue {
    if (_points >= 500) return 1;
    if (_points >= 250) return (_points - 250) / 250;
    if (_points >= 100) return (_points - 100) / 150;
    return _points / 100;
  }

  String _milestoneReward(int points) {
    if (points >= 500) return 'Free meal';
    if (points >= 250) return '10% discount';
    return '5% discount';
  }

  Future<void> _loadRewards() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      final userDoc = await _firestore
          .collection('users')
          .doc(user.uid)
          .get()
          .timeout(_rewardsTimeout);
      final userData = userDoc.data() ?? <String, dynamic>{};
      final orders = await _campusService.getOrders(uid: user.uid);
      final attendancePayload = await _campusService.getAttendanceHistory(uid: user.uid);
      final attendanceRecords =
          (attendancePayload['records'] as List<dynamic>? ?? const [])
              .map((item) => Map<String, dynamic>.from(item as Map))
              .toList();
      final effectivePoints = _campusService.calculateRewardPoints(
        orders: orders,
        attendanceRecords: attendanceRecords,
      );
      final reward = await _predictionService.getReward(effectivePoints);

      if (!mounted) return;
      setState(() {
        _points = effectivePoints;
        _reward = reward;
        _name = userData['name']?.toString().trim().isNotEmpty ?? false
            ? userData['name'].toString().trim()
            : 'Student';
        _isLoading = false;
      });
      if (effectivePoints > 0) {
        await _campusService.cachePoints(uid: user.uid, points: effectivePoints);
      }
    } on TimeoutException catch (_) {
      final cachedPoints = await _campusService.getCachedPoints(uid: user.uid);
      final cachedReward = await _predictionService.getReward(cachedPoints);
      if (!mounted) return;
      setState(() {
        _points = cachedPoints;
        _reward = cachedReward;
        _name = user.displayName?.trim().isNotEmpty == true
            ? user.displayName!.trim()
            : 'Student';
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Rewards are taking too long to load, so a quick fallback view is shown.'),
        ),
      );
    } catch (_) {
      final cachedPoints = await _campusService.getCachedPoints(uid: user.uid);
      final cachedReward = await _predictionService.getReward(cachedPoints);
      if (!mounted) return;
      setState(() {
        _points = cachedPoints;
        _reward = cachedReward;
        _name = user.displayName?.trim().isNotEmpty == true
            ? user.displayName!.trim()
            : 'Student';
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to load rewards right now.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),
      appBar: AppBar(
        title: const Text('My Rewards'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadRewards,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
                children: [
                  _buildHeroCard(),
                  const SizedBox(height: 18),
                  _buildProgressCard(),
                  const SizedBox(height: 18),
                  _buildMilestoneCard(),
                  const SizedBox(height: 18),
                  _buildHelpCard(),
                ],
              ),
            ),
    );
  }

  Widget _buildHeroCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF7C3AED), Color(0xFF2563EB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Reward Wallet',
            style: TextStyle(
              color: Color(0xFFEDE9FE),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '$_points points collected',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Current benefit: $_reward',
            style: const TextStyle(
              color: Color(0xFFE0E7FF),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressCard() {
    final nextMilestone = _nextMilestone;
    final label = nextMilestone == null
        ? 'You have unlocked the top reward tier.'
        : '${nextMilestone - _points} points to ${_milestoneReward(nextMilestone)}';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Next Reward Progress',
            style: TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: _progressValue.clamp(0, 1),
              minHeight: 12,
              backgroundColor: const Color(0xFFE2E8F0),
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF7C3AED)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMilestoneCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Reward Milestones',
            style: TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          ..._milestones.map((milestone) {
            final unlocked = _points >= milestone;
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: unlocked
                    ? const Color(0xFFF5F3FF)
                    : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  Icon(
                    unlocked ? Icons.check_circle_rounded : Icons.lock_outline_rounded,
                    color: unlocked
                        ? const Color(0xFF7C3AED)
                        : const Color(0xFF94A3B8),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$milestone points',
                          style: const TextStyle(
                            color: Color(0xFF0F172A),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _milestoneReward(milestone),
                          style: const TextStyle(
                            color: Color(0xFF64748B),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    unlocked ? 'Unlocked' : 'Locked',
                    style: TextStyle(
                      color: unlocked
                          ? const Color(0xFF7C3AED)
                          : const Color(0xFF94A3B8),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildHelpCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How Rewards Work',
            style: TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 10),
          Text(
            'Rewards are based on the points stored on your CampusCurb profile. The backend currently maps 100 points to a 5% discount, 250 points to a 10% discount, and 500 points to a free meal.',
            style: TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w600,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
