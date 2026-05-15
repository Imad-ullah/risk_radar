// lib/app_settings_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Import your existing screens
import 'officer_emergency_details_screen.dart';

/// Shared Settings screen
class AppSettingsScreen extends StatelessWidget {
  final void Function(BuildContext) onAboutTap;
  final void Function(ThemeMode) onThemeChanged;
  final void Function() onProfileTap;
  final ThemeMode currentThemeMode;

  const AppSettingsScreen({
    super.key,
    required this.onAboutTap,
    required this.onThemeChanged,
    required this.currentThemeMode,
    required this.onProfileTap,
  });

  // -------------------
  // Sign Out Helper
  // -------------------
  Future<void> _handleSignOut(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Confirm Logout',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        ),
        content: Text(
          'Are you sure you want to log out?',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        backgroundColor: Theme.of(context).colorScheme.surface,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: Theme.of(context).colorScheme.primary),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirm == true && context.mounted) {
      try {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Logging out...',
              style: TextStyle(color: Theme.of(context).colorScheme.onInverseSurface),
            ),
            backgroundColor: Theme.of(context).colorScheme.inverseSurface,
          ),
        );
        await Supabase.instance.client.auth.signOut();
        if (context.mounted) {
          Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Logout failed: ${e.toString()}',
                style: TextStyle(color: Theme.of(context).colorScheme.onError),
              ),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = currentThemeMode == ThemeMode.dark ||
        (currentThemeMode == ThemeMode.system &&
            MediaQuery.of(context).platformBrightness == Brightness.dark);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Profile Card
                  _CompactSettingsTile(
                    icon: Icons.person_outline,
                    title: 'Profile',
                    onTap: onProfileTap,
                  ),
                  const SizedBox(height: 16),

                  // Emergency Details Card
                  _CompactSettingsTile(
                    icon: Icons.warning_amber_outlined,
                    iconColor: Colors.red,
                    title: 'Emergency Details',
                    onTap: () {
                      final user = Supabase.instance.client.auth.currentUser;
                      if (user != null) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => OfficerEmergencyDetailsScreen(
                              officerId: user.id,
                            ),
                          ),
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 16),

                  // Theme Toggle Card
                  _CompactSettingsTile(
                    icon: Icons.color_lens_outlined,
                    title: isDark ? 'Dark Mode' : 'Light Mode',
                    trailing: ThemeToggle(
                      isDark: isDark,
                      onChanged: (value) {
                        onThemeChanged(value ? ThemeMode.dark : ThemeMode.light);
                      },
                    ),
                    onTap: () {
                      onThemeChanged(isDark ? ThemeMode.light : ThemeMode.dark);
                    },
                  ),
                  const SizedBox(height: 16),

                  // Notifications
                  _CompactSettingsTile(
                    icon: Icons.notifications_outlined,
                    title: 'Notifications',
                    onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Notification settings coming soon',
                          style: TextStyle(color: Theme.of(context).colorScheme.onInverseSurface),
                        ),
                        backgroundColor: Theme.of(context).colorScheme.inverseSurface,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Privacy
                  _CompactSettingsTile(
                    icon: Icons.security_outlined,
                    title: 'Privacy & Security',
                    onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Privacy settings coming soon',
                          style: TextStyle(color: Theme.of(context).colorScheme.onInverseSurface),
                        ),
                        backgroundColor: Theme.of(context).colorScheme.inverseSurface,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // About
                  _CompactSettingsTile(
                    icon: Icons.info_outline,
                    title: 'About App',
                    onTap: () => onAboutTap(context),
                  ),
                  const SizedBox(height: 32),

                  // Sign Out Button
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade600,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 56),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                    onPressed: () => _handleSignOut(context),
                    icon: const Icon(Icons.logout, size: 22),
                    label: const Text(
                      'Sign Out',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------
// Compact Settings Tile Widget
// -----------------------------------------------------------
class _CompactSettingsTile extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String title;
  final VoidCallback onTap;
  final Widget? trailing;

  const _CompactSettingsTile({
    required this.icon,
    this.iconColor,
    required this.title,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).shadowColor.withValues(alpha: 0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: iconColor ?? (Theme.of(context).brightness == Brightness.dark
                  ? Colors.white
                  : Colors.black),
              size: 26,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            if (trailing != null)
              trailing!
            else
              Icon(
                Icons.chevron_right,
                color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                size: 24,
              ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------
// Theme Toggle Widget (Optimized for smaller size)
// -----------------------------------------------------------
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
    final Color trackLight = Colors.grey.shade300;
    final Color trackDark = Colors.grey.shade800;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!isDark),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        width: 70,
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? [trackDark, Colors.black54]
                : [trackLight, Colors.white],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
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
                padding: const EdgeInsets.only(left: 8),
                child: Icon(
                  Icons.wb_sunny_rounded,
                  size: 16,
                  color: isDark ? Colors.white30 : Colors.orangeAccent.shade700,
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(
                  Icons.nightlight_round,
                  size: 16,
                  color: isDark ? Colors.indigoAccent.shade100 : Colors.black26,
                ),
              ),
            ),
            AnimatedAlign(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              alignment: isDark ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 28,
                height: 28,
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
                    size: 15,
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
