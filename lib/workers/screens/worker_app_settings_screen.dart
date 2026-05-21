// lib/worker_app_settings_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:riskradar/shared/theme/app_colors.dart';
import '../settings/worker_sites_screen.dart';
import '../settings/worker_emergency_details_screen.dart';

class WorkerAppSettingsScreen extends StatelessWidget {
  final void Function(BuildContext) onAboutTap;
  final void Function(ThemeMode) onThemeChanged;
  final void Function() onProfileTap;
  final ThemeMode currentThemeMode;

  const WorkerAppSettingsScreen({
    super.key,
    required this.onAboutTap,
    required this.onThemeChanged,
    required this.currentThemeMode,
    required this.onProfileTap,
  });

  void _showInfoSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: AppColors.brandTeal,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showErrorSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _handleSignOut(BuildContext context) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                AppColors.brandTeal,
                AppColors.brandTeal.withValues(alpha: 0.85),
              ],
            ),
            borderRadius: BorderRadius.circular(28),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.logout_rounded,
                  color: Colors.white,
                  size: 32,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Confirm Logout',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Are you sure you want to log out of RiskRadar?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.brandTeal,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 4,
                    ),
                    child: const Text(
                      'Logout',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirm == true && context.mounted) {
      try {
        _showInfoSnackBar(context, 'Logging out...');
        await Supabase.instance.client.auth.signOut();

        if (context.mounted) {
          Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
        }
      } catch (e) {
        if (context.mounted) {
          _showErrorSnackBar(context, 'Logout failed: $e');
        }
      }
    }
  }

  void _onChangeSiteTap(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const WorkerSitesScreen(),
      ),
    );
  }

  void _onEmergencyDetailsTap(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WorkerEmergencyDetailsScreen(
          workerId: Supabase.instance.client.auth.currentUser!.id,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _CompactSettingsTile(
                  icon: Icons.person_outline,
                  title: 'Profile',
                  subtitle: 'View and update your personal details',
                  onTap: onProfileTap,
                ),
                const SizedBox(height: 16),
                _CompactSettingsTile(
                  icon: Icons.warning_amber_outlined,
                  iconColor: Colors.red.shade200,
                  title: 'Emergency Details',
                  subtitle: 'View or update emergency contacts and info',
                  onTap: () => _onEmergencyDetailsTap(context),
                ),
                const SizedBox(height: 16),
                _CompactSettingsTile(
                  icon: Icons.location_on_outlined,
                  title: 'Change Current Site',
                  subtitle: 'Select or switch your active work site',
                  onTap: () => _onChangeSiteTap(context),
                ),
                const SizedBox(height: 16),
                _CompactSettingsTile(
                  icon: Icons.color_lens_outlined,
                  title: isDark ? 'Dark Mode' : 'Light Mode',
                  subtitle: 'Adjust RiskRadar appearance',
                  enableTileTap: false,
                  trailing: ThemeToggle(
                    isDark: isDark,
                    onChanged: (bool value) {
                      onThemeChanged(value ? ThemeMode.dark : ThemeMode.light);
                    },
                  ),
                  onTap: () {},
                ),
                const SizedBox(height: 16),
                _CompactSettingsTile(
                  icon: Icons.notifications_outlined,
                  title: 'Notifications',
                  subtitle: 'Manage notification preferences',
                  onTap: () => _showInfoSnackBar(
                    context,
                    'Notification settings coming soon',
                  ),
                ),
                const SizedBox(height: 16),
                _CompactSettingsTile(
                  icon: Icons.security_outlined,
                  title: 'Privacy & Security',
                  subtitle: 'Change password and privacy options',
                  onTap: () => _showInfoSnackBar(
                    context,
                    'Privacy settings coming soon',
                  ),
                ),
                const SizedBox(height: 16),
                _CompactSettingsTile(
                  icon: Icons.info_outline,
                  title: 'About App',
                  subtitle: 'Learn more about this application',
                  onTap: () => onAboutTap(context),
                ),
                const SizedBox(height: 32),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: <Color>[
                        Colors.red.shade600,
                        Colors.red.shade800,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: Colors.red.shade600.withValues(alpha: 0.32),
                        blurRadius: 14,
                        spreadRadius: 1,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 56),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () => _handleSignOut(context),
                    icon: const Icon(Icons.logout, size: 22),
                    label: const Text(
                      'Sign Out',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CompactSettingsTile extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool enableTileTap;

  const _CompactSettingsTile({
    required this.icon,
    this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
    this.enableTileTap = true,
  });

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final Color cardBase = isDark
        ? Color.lerp(AppColors.brandTeal, Colors.black, 0.35)!
        : AppColors.brandTeal;

    return InkWell(
      onTap: enableTileTap ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: cardBase,
          border: Border.all(
            color: isDark
                ? AppColors.surfaceTeal.withValues(alpha: 0.8)
                : AppColors.brandTeal.withValues(alpha: 0.22),
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.06),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: <Widget>[
            Icon(
              icon,
              color: iconColor ?? Colors.white,
              size: 26,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.74),
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null)
              trailing!
            else
              const Icon(
                Icons.chevron_right,
                color: Colors.white70,
                size: 24,
              ),
          ],
        ),
      ),
    );
  }
}

class ThemeToggle extends StatelessWidget {
  final bool isDark;
  final ValueChanged<bool> onChanged;

  const ThemeToggle({
    super.key,
    required this.isDark,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final trackLight = Colors.grey.shade300;
    final trackDark = Colors.grey.shade800;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!isDark),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        width: 86,
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? [trackDark, Colors.black54]
                : [trackLight, Colors.white],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 10),
                child: Icon(
                  Icons.wb_sunny_rounded,
                  size: 20,
                  color: isDark ? Colors.white30 : Colors.orangeAccent.shade700,
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Icon(
                  Icons.nightlight_round,
                  size: 20,
                  color: isDark ? Colors.indigoAccent.shade100 : Colors.black26,
                ),
              ),
            ),
            AnimatedAlign(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              alignment: isDark ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: isDark
                      ? Theme.of(context).colorScheme.primary
                      : Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Center(
                  child: Icon(
                    isDark ? Icons.nightlight_round : Icons.wb_sunny_rounded,
                    size: 18,
                    color: isDark ? Colors.white : Colors.orangeAccent.shade700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
