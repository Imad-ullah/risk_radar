// lib/shared/settings/about_app_screen.dart

import 'package:flutter/material.dart';
import 'package:riskradar/utils/responsive.dart';
import 'package:riskradar/shared/theme/app_colors.dart'; // Ensure correct import

class AboutAppScreen extends StatelessWidget {
  const AboutAppScreen({super.key});

  @override
  Widget build(BuildContext context) {
    R.init(context);
    // Theme Detection
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark
        ? const Color(0xFF121212)
        : AppColors.backgroundLight;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.grey[400] : Colors.grey[600];

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(
          "About RiskRadar",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppColors.brandTeal,
        foregroundColor: Colors.white,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.all(R.blockH * 6),
        children: [
          // App Logo / Icon
          Center(
            child: CircleAvatar(
              radius: 56,
              // ✅ Teal Background
              backgroundColor: AppColors.brandTeal.withValues(alpha: 0.1),
              child: Icon(
                Icons.shield_rounded,
                size: 56,
                color: AppColors.brandTeal, // ✅ Teal Icon
              ),
            ),
          ),
          SizedBox(height: R.blockV * 2.5),
          Center(
            child: Text(
              "RiskRadar",
              style: TextStyle(
                fontSize: R.blockH * 6,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
          ),
          SizedBox(height: R.blockV * 0.75),
          Center(
            child: Text(
              "Version 1.0.0",
              style: TextStyle(color: subTextColor, fontSize: R.blockH * 3.5),
            ),
          ),
          SizedBox(height: R.blockV * 4),

          // About description
          Text(
            "About RiskRadar",
            style: TextStyle(
              fontSize: R.blockH * 4.5,
              fontWeight: FontWeight.bold,
              color: isDark ? AppColors.accentGold : AppColors.brandTeal,
            ),
          ),
          SizedBox(height: R.blockV * 1.5),
          Text(
            "RiskRadar is a workplace safety and hazard management application "
            "designed to streamline reporting and monitoring of workplace risks. "
            "It helps workers report hazards quickly and allows officers to review, "
            "assign and resolve tasks. The app aims to improve safety culture by "
            "increasing hazard visibility and speeding up corrective actions. "
            "RiskRadar uses Supabase for secure authentication and data storage.",
            textAlign: TextAlign.justify,
            style: TextStyle(
              fontSize: R.blockH * 3.75,
              height: 1.6,
              color: textColor,
            ),
          ),
          SizedBox(height: R.blockV * 3),

          Text(
            "Our Aim",
            style: TextStyle(
              fontSize: R.blockH * 4.5,
              fontWeight: FontWeight.bold,
              color: isDark ? AppColors.accentGold : AppColors.brandTeal,
            ),
          ),
          SizedBox(height: R.blockV * 1.5),
          Text(
            "Reduce workplace accidents by enabling quick hazard reporting, "
            "transparent task assignments, and timely resolutions. We want to "
            "empower teams to proactively manage safety and reduce incident costs.",
            textAlign: TextAlign.justify,
            style: TextStyle(
              fontSize: R.blockH * 3.75,
              height: 1.6,
              color: textColor,
            ),
          ),
          SizedBox(height: R.blockV * 4),

          Divider(color: isDark ? Colors.grey[800] : Colors.grey[200]),

          // Info tiles
          _buildInfoTile(
            context,
            icon: Icons.privacy_tip_outlined,
            title: "Privacy Policy",
            subtitle: "Read about how we handle your data",
            isDark: isDark,
            textColor: textColor,
            subTextColor: subTextColor,
          ),
          Divider(
            height: 1,
            indent: 56,
            color: isDark ? Colors.grey[800] : Colors.grey[200],
          ),

          _buildInfoTile(
            context,
            icon: Icons.description_outlined,
            title: "Terms & Conditions",
            subtitle: "Understand our terms of use",
            isDark: isDark,
            textColor: textColor,
            subTextColor: subTextColor,
          ),
          Divider(
            height: 1,
            indent: 56,
            color: isDark ? Colors.grey[800] : Colors.grey[200],
          ),

          _buildInfoTile(
            context,
            icon: Icons.support_agent_rounded,
            title: "Support",
            subtitle: "Get help or contact our team",
            isDark: isDark,
            textColor: textColor,
            subTextColor: subTextColor,
          ),

          SizedBox(height: R.blockV * 4),
          Center(
            child: Text(
              "© 2024 RiskRadar Inc.",
              style: TextStyle(color: Colors.grey[500], fontSize: R.blockH * 3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isDark,
    required Color textColor,
    required Color? subTextColor,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.symmetric(
        vertical: R.blockV * 0.5,
        horizontal: R.blockH * 2,
      ),
      leading: Container(
        padding: EdgeInsets.all(R.blockH * 2),
        decoration: BoxDecoration(
          color: isDark ? Colors.grey[800] : Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: AppColors.brandTeal, size: 24),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: R.blockH * 4,
          color: textColor,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: subTextColor, fontSize: R.blockH * 3.25),
      ),
      trailing: Icon(Icons.chevron_right_rounded, color: Colors.grey[400]),
      onTap: () {
        // Placeholder for future navigation
      },
    );
  }
}
