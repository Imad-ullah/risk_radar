// lib/shared/settings/about_app_screen.dart

import 'package:flutter/material.dart';
import 'package:riskradar/shared/theme/app_colors.dart'; // Ensure correct import

class AboutAppScreen extends StatelessWidget {
  const AboutAppScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Theme Detection
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF121212) : AppColors.backgroundLight;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.grey[400] : Colors.grey[600];

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text(
          "About RiskRadar",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppColors.brandTeal,
        foregroundColor: Colors.white,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // App Logo / Icon
          Center(
            child: CircleAvatar(
              radius: 56,
              // ✅ Teal Background
              backgroundColor: AppColors.brandTeal.withValues(alpha: 0.1),
              child: const Icon(
                Icons.shield_rounded,
                size: 56,
                color: AppColors.brandTeal, // ✅ Teal Icon
              ),
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: Text(
              "RiskRadar",
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              "Version 1.0.0",
              style: TextStyle(color: subTextColor, fontSize: 14),
            ),
          ),
          const SizedBox(height: 32),

          // About description
          Text(
            "About RiskRadar",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? AppColors.accentGold : AppColors.brandTeal,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            "RiskRadar is a workplace safety and hazard management application "
                "designed to streamline reporting and monitoring of workplace risks. "
                "It helps workers report hazards quickly and allows officers to review, "
                "assign and resolve tasks. The app aims to improve safety culture by "
                "increasing hazard visibility and speeding up corrective actions. "
                "RiskRadar uses Supabase for secure authentication and data storage.",
            textAlign: TextAlign.justify,
            style: TextStyle(fontSize: 15, height: 1.6, color: textColor),
          ),
          const SizedBox(height: 24),

          Text(
            "Our Aim",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? AppColors.accentGold : AppColors.brandTeal,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            "Reduce workplace accidents by enabling quick hazard reporting, "
                "transparent task assignments, and timely resolutions. We want to "
                "empower teams to proactively manage safety and reduce incident costs.",
            textAlign: TextAlign.justify,
            style: TextStyle(fontSize: 15, height: 1.6, color: textColor),
          ),
          const SizedBox(height: 32),

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
          Divider(height: 1, indent: 56, color: isDark ? Colors.grey[800] : Colors.grey[200]),

          _buildInfoTile(
            context,
            icon: Icons.description_outlined,
            title: "Terms & Conditions",
            subtitle: "Understand our terms of use",
            isDark: isDark,
            textColor: textColor,
            subTextColor: subTextColor,
          ),
          Divider(height: 1, indent: 56, color: isDark ? Colors.grey[800] : Colors.grey[200]),

          _buildInfoTile(
            context,
            icon: Icons.support_agent_rounded,
            title: "Support",
            subtitle: "Get help or contact our team",
            isDark: isDark,
            textColor: textColor,
            subTextColor: subTextColor,
          ),

          const SizedBox(height: 32),
          Center(
            child: Text(
              "© 2024 RiskRadar Inc.",
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
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
      contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      leading: Container(
        padding: const EdgeInsets.all(8),
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
          fontSize: 16,
          color: textColor,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: subTextColor, fontSize: 13),
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: Colors.grey[400],
      ),
      onTap: () {
        // Placeholder for future navigation
      },
    );
  }
}