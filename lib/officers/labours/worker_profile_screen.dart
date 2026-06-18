import 'package:flutter/material.dart';
import 'package:riskradar/utils/responsive.dart';
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
    R.init(context);
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
        title: Text(
          'Profile',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.white),
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
            height: R.blockV * 40,
            child: ClipPath(
              clipper: ProfileHeaderClipper(),
              child: Container(color: _headerTeal),
            ),
          ),

          // 2. MAIN CONTENT
          SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: R.blockH * 6),
            child: Column(
              children: [
                SizedBox(height: R.blockV * 13.75),

                // 3. FLOATING PROFILE CARD
                Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.topCenter,
                  children: [
                    Container(
                      margin: EdgeInsets.only(top: R.blockV * 6.25),
                      padding: EdgeInsets.fromLTRB(
                        R.blockH * 5,
                        R.blockV * 8.125,
                        R.blockH * 5,
                        R.blockV * 3.75,
                      ),
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: _cardWhite,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 20,
                            offset: Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          // Name Header (Strictly Capitalized)
                          Text(
                            fullName.isEmpty ? "Unknown Profile" : fullName,
                            style: TextStyle(
                              fontSize: R.blockH * 6,
                              fontWeight: FontWeight.bold,
                              color: _textDark,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          SizedBox(height: R.blockV * 2),
                          // ID Chip (Role mention removed from here as requested)
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: R.blockH * 3.5,
                              vertical: R.blockV * 0.75,
                            ),
                            decoration: BoxDecoration(
                              color: _headerTeal.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              "Worker ID: $uid",
                              style: TextStyle(
                                color: _headerTeal,
                                fontSize: R.blockH * 3.25,
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
                        padding: EdgeInsets.all(R.blockH * 1),
                        decoration: const BoxDecoration(
                          color: _cardWhite,
                          shape: BoxShape.circle,
                        ),
                        child: CircleAvatar(
                          radius: 50,
                          backgroundColor: Colors.grey.shade200,
                          backgroundImage: worker['profile_image_url'] != null
                              ? CachedNetworkImageProvider(
                                  worker['profile_image_url'],
                                )
                              : null,
                          child: worker['profile_image_url'] == null
                              ? Icon(Icons.person, size: 50, color: Colors.grey)
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),

                SizedBox(height: R.blockV * 3.75),

                // 4. GENERAL INFO LIST
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "General Information",
                    style: TextStyle(
                      fontSize: R.blockH * 4.5,
                      fontWeight: FontWeight.bold,
                      color: _textDark,
                    ),
                  ),
                ),
                SizedBox(height: R.blockV * 2),

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

                SizedBox(height: R.blockV * 5),
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
      margin: EdgeInsets.only(bottom: R.blockV * 2),
      padding: EdgeInsets.symmetric(
        horizontal: R.blockH * 4,
        vertical: R.blockV * 2,
      ),
      decoration: BoxDecoration(
        color: _cardWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Container(
            width: R.blockH * 12.267,
            height: R.blockV * 5.75,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          SizedBox(width: R.blockH * 4.267),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: R.blockH * 3,
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: R.blockH * 3.75,
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
      size.height - 60,
    );
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}
