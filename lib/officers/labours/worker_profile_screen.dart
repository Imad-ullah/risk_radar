import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/services.dart';

class WorkerProfileScreen extends StatelessWidget {
  final Map<String, dynamic> worker;
  final String tableName; // 'workers' or 'hse_workers'

  const WorkerProfileScreen({
    super.key,
    required this.worker,
    required this.tableName,
  });

  bool get isHseWorker => tableName == 'hse_workers';

  // --- Theme Colors ---
  static const Color _headerTeal = Color(0xFF1B3D3D);
  static const Color _bgWhite = Color(0xFFF9FAFB);
  static const Color _cardWhite = Colors.white;
  static const Color _textDark = Color(0xFF1B3D3D);

  // Capitalize first letter of any string
  String capitalize(String text) {
    if (text.isEmpty) return '';
    return text[0].toUpperCase() + text.substring(1).toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    // Both First and Last name initials capitalized
    final firstName = capitalize(worker['first_name'] ?? '');
    final lastName = capitalize(worker['last_name'] ?? '');
    final fullName = "$firstName $lastName".trim();

    // Role information to be used only in the bottom info tiles
    final roleValue = isHseWorker
        ? (worker['designation'] ?? 'Safety Officer')
        : (worker['work_type'] ?? 'Site Personnel');

    final email = worker['email'] ?? 'Not provided';
    final dob = worker['dob'] ?? 'Not provided';
    final uid = worker['worker_uid'] ?? 'N/A';
    final phone = worker['phone_number'] ?? 'Not provided';

    return Scaffold(
      backgroundColor: _bgWhite,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Profile',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      body: Stack(
        children: [
          // 1. TEAL HEADER BACKGROUND
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 320,
            child: ClipPath(
              clipper: ProfileHeaderClipper(),
              child: Container(
                color: _headerTeal,
              ),
            ),
          ),

          // 2. MAIN CONTENT
          SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const SizedBox(height: 110),

                // 3. FLOATING PROFILE CARD
                Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.topCenter,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 50),
                      padding: const EdgeInsets.fromLTRB(20, 65, 20, 30),
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: _cardWhite,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          // Name Header (Strictly Capitalized)
                          Text(
                            fullName.isEmpty ? "Unknown Profile" : fullName,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: _textDark,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          // ID Chip (Role mention removed from here as requested)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: _headerTeal.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              "Worker ID: $uid",
                              style: const TextStyle(
                                color: _headerTeal,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Floating Avatar
                    Positioned(
                      top: 0,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: _cardWhite,
                          shape: BoxShape.circle,
                        ),
                        child: CircleAvatar(
                          radius: 50,
                          backgroundColor: Colors.grey.shade200,
                          backgroundImage: worker['profile_image_url'] != null
                              ? CachedNetworkImageProvider(worker['profile_image_url'])
                              : null,
                          child: worker['profile_image_url'] == null
                              ? const Icon(Icons.person, size: 50, color: Colors.grey)
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 30),

                // 4. GENERAL INFO LIST
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "General Information",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _textDark,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Colorful Info Tiles
                _buildInfoTile(
                  icon: Icons.email_outlined,
                  title: "Email",
                  value: email,
                  iconColor: Colors.blue,
                  bgColor: Colors.blue.withValues(alpha: 0.1),
                ),
                _buildInfoTile(
                  icon: Icons.cake_outlined,
                  title: "Date of Birth",
                  value: dob,
                  iconColor: Colors.pink,
                  bgColor: Colors.pink.withValues(alpha: 0.1),
                ),
                _buildInfoTile(
                  icon: Icons.phone_outlined,
                  title: "Phone",
                  value: phone,
                  iconColor: Colors.orange,
                  bgColor: Colors.orange.withValues(alpha: 0.1),
                ),
                // Role displayed here only
                _buildInfoTile(
                  icon: Icons.badge_outlined,
                  title: "Role Type",
                  value: roleValue,
                  iconColor: Colors.deepPurple,
                  bgColor: Colors.deepPurple.withValues(alpha: 0.1),
                ),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String title,
    required String value,
    required Color iconColor,
    required Color bgColor,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: _cardWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 15,
                    color: _textDark,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ProfileHeaderClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height - 60);
    path.quadraticBezierTo(
        size.width / 2,
        size.height,
        size.width,
        size.height - 60
    );
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}