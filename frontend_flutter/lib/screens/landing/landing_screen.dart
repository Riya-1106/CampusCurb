import 'package:flutter/material.dart';

import '../auth/college_access_screen.dart';
import '../auth/login_screen.dart';

class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  static const _heroImage =
      'https://images.unsplash.com/photo-1495474472287-4d71bcdd2085?auto=format&fit=crop&w=1800&q=80';
  static const _secondaryImage =
      'https://images.unsplash.com/photo-1565299507177-b0ac66763828?auto=format&fit=crop&w=1400&q=80';

  Widget _featurePill(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: Colors.white),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _roleTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: color.withValues(alpha: 0.15),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12.5, color: Colors.black54),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _networkBackground(String imageUrl) {
    return Image.network(
      imageUrl,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1B5E8F), Color(0xFF1D9A8A), Color(0xFF0E3B59)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        );
      },
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Container(
          color: const Color(0xFF113A57),
          child: const Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 760;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: _networkBackground(_heroImage)),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF051A2F).withValues(alpha: 0.74),
                    const Color(0xFF102A43).withValues(alpha: 0.68),
                    const Color(0xFF0C7A67).withValues(alpha: 0.6),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
          SafeArea(
            child: TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 650),
              tween: Tween(begin: 0, end: 1),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, (1 - value) * 20),
                    child: child,
                  ),
                );
              },
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 980),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'CampusCurb',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: isWide ? 52 : 38,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
                            height: 1.0,
                          ),
                        ),
                        const SizedBox(height: 10),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 640),
                          child: const Text(
                            'Smart campus food operations powered by demand forecasting, waste intelligence, and role-based control.',
                            style: TextStyle(
                              color: Color(0xFFE5F4FF),
                              fontSize: 16,
                              height: 1.45,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _featurePill(
                              Icons.psychology_alt_outlined,
                              'Demand Forecasting',
                            ),
                            _featurePill(
                              Icons.auto_graph_outlined,
                              'Live Analytics',
                            ),
                            _featurePill(
                              Icons.delete_sweep_outlined,
                              'Waste Reduction',
                            ),
                            _featurePill(
                              Icons.verified_user_outlined,
                              'Admin Managed Access',
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.25),
                            ),
                          ),
                          child: isWide
                              ? Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Role-Based Platform',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 18,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: 0.3,
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          _roleTile(
                                            icon: Icons.school_outlined,
                                            title: 'Student',
                                            subtitle:
                                                'Browse menu, mark attendance, and earn rewards.',
                                            color: const Color(0xFF1C6FE9),
                                          ),
                                          const SizedBox(height: 8),
                                          _roleTile(
                                            icon: Icons.storefront_outlined,
                                            title: 'Canteen',
                                            subtitle:
                                                'Manage menu and use data to reduce over-prep.',
                                            color: const Color(0xFF1F9362),
                                          ),
                                          const SizedBox(height: 8),
                                          _roleTile(
                                            icon: Icons.badge_outlined,
                                            title: 'Faculty + Admin',
                                            subtitle:
                                                'Track operations, monitor security, and provision users.',
                                            color: const Color(0xFF9654E8),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(16),
                                      child: SizedBox(
                                        width: 220,
                                        height: 270,
                                        child: Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            _networkBackground(_secondaryImage),
                                            Container(
                                              color: Colors.black.withValues(
                                                alpha: 0.32,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Role-Based Platform',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    _roleTile(
                                      icon: Icons.school_outlined,
                                      title: 'Student',
                                      subtitle:
                                          'Browse menu, mark attendance, and earn rewards.',
                                      color: const Color(0xFF1C6FE9),
                                    ),
                                    const SizedBox(height: 8),
                                    _roleTile(
                                      icon: Icons.storefront_outlined,
                                      title: 'Canteen',
                                      subtitle:
                                          'Manage menu and use data to reduce over-prep.',
                                      color: const Color(0xFF1F9362),
                                    ),
                                    const SizedBox(height: 8),
                                    _roleTile(
                                      icon: Icons.badge_outlined,
                                      title: 'Faculty + Admin',
                                      subtitle:
                                          'Track operations, monitor security, and provision users.',
                                      color: const Color(0xFF9654E8),
                                    ),
                                  ],
                                ),
                        ),
                        const SizedBox(height: 18),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF4D9),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFF1C56D)),
                          ),
                          child: const Text(
                            'Account access is provisioned by admin. For email or account updates, contact admin.',
                            style: TextStyle(
                              color: Color(0xFF724A00),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.arrow_forward_rounded),
                            label: const Text(
                              'Continue to Campus Login',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1F7AE0),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const LoginScreen(),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: OutlinedButton.icon(
                            icon: const Icon(
                              Icons.store_mall_directory_outlined,
                            ),
                            label: const Text(
                              'Open College Portal',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Colors.white70),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const CollegeAccessScreen(),
                                ),
                              );
                            },
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
    );
  }
}
