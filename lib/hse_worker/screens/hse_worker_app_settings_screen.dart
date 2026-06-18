// lib/workers/screens/hse_worker_app_settings_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:riskradar/utils/responsive.dart';
import 'package:riskradar/services/logger_service.dart';
import 'package:riskradar/services/repositories/auth_repository.dart';
import 'package:riskradar/services/repositories/sync_repository.dart';
import 'package:riskradar/services/sync_service.dart';
import 'package:riskradar/shared/theme/app_colors.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'hse_worker_sites_screen.dart';
import 'hse_worker_view_profile_screen.dart';
import 'hse_worker_emergency_details_screen.dart';

class HSEWorkerAppSettingsScreen extends StatefulWidget {
  final void Function(BuildContext) onAboutTap;
  final void Function(ThemeMode) onThemeChanged;
  final ThemeMode currentThemeMode;

  const HSEWorkerAppSettingsScreen({
    super.key,
    required this.onAboutTap,
    required this.onThemeChanged,
    required this.currentThemeMode,
  });

  // ✅ BRAND COLORS (Defining locally since it's used in the popup)
  static const Color brandTeal = AppColors.brandTeal;

  @override
  State<HSEWorkerAppSettingsScreen> createState() =>
      _HSEWorkerAppSettingsScreenState();
}

class _HSEWorkerAppSettingsScreenState
    extends State<HSEWorkerAppSettingsScreen> {
  static const Color brandTeal = HSEWorkerAppSettingsScreen.brandTeal;
  static const String _availabilityEnabledText =
      'Available for new hazard assignments';
  static const String _availabilityDisabledText =
      'Paused for new hazard assignments';
  static const String _availabilitySavedText =
      'Availability update queued for sync';
  static const String _availabilityFailedText = 'Failed to update availability';

  final AuthRepository _authRepository = AuthRepository();
  final SyncRepository _syncRepository = SyncRepository();

  bool _isAvailable = true;
  bool _isSavingAvailability = false;

  @override
  void initState() {
    super.initState();
    _loadAvailabilityFromCache();
  }

  void _loadAvailabilityFromCache() {
    final Map<String, dynamic>? profile = _authRepository.getHseProfile();
    final bool? cachedAvailability = _readBool(profile?['is_available']);
    _isAvailable = cachedAvailability ?? true;
  }

  bool? _readBool(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    final String normalized = value.toString().trim().toLowerCase();
    if (normalized == 'true' || normalized == '1') {
      return true;
    }
    if (normalized == 'false' || normalized == '0') {
      return false;
    }
    return null;
  }

  Future<void> _handleAvailabilityChanged(bool value) async {
    if (_isSavingAvailability) {
      return;
    }

    final String? userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      _showErrorSnackBar('Sign in again to update availability');
      return;
    }

    final bool previousValue = _isAvailable;
    setState(() {
      _isAvailable = value;
      _isSavingAvailability = true;
    });

    try {
      await _cacheAvailability(userId: userId, isAvailable: value);
      await _syncRepository.enqueueAction(
        id: 'hse_availability_${userId}_${DateTime.now().millisecondsSinceEpoch}',
        table: 'hse_workers',
        action: 'update',
        payload: {'id': userId, 'is_available': value},
      );
      unawaited(SyncService.instance.run());

      if (!mounted) {
        return;
      }
      _showInfoSnackBar(_availabilitySavedText);
    } catch (e, s) {
      LoggerService.error(_availabilityFailedText, e, s);
      await _cacheAvailability(userId: userId, isAvailable: previousValue);

      if (!mounted) {
        return;
      }
      setState(() {
        _isAvailable = previousValue;
      });
      _showErrorSnackBar(_availabilityFailedText);
    } finally {
      if (mounted) {
        setState(() {
          _isSavingAvailability = false;
        });
      }
    }
  }

  Future<void> _cacheAvailability({
    required String userId,
    required bool isAvailable,
  }) {
    final Map<String, dynamic> currentProfile =
        _authRepository.getHseProfile() ?? <String, dynamic>{};
    return _authRepository.saveHseProfile({
      ...currentProfile,
      'id': userId,
      'is_available': isAvailable,
    });
  }

  void _showInfoSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        backgroundColor: AppColors.brandTeal,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _handleSignOut(BuildContext context) async {
    // ✅ NEW THEMED DIALOG DESIGN
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          padding: EdgeInsets.all(R.blockH * 6),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                brandTeal,
                Color(0xDA1B3D3D), // brandTeal with values (alpha: 0.85)
              ],
            ),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: EdgeInsets.all(R.blockH * 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.logout_rounded,
                  color: Colors.white,
                  size: 32,
                ),
              ),
              SizedBox(height: R.blockV * 2.5),
              Text(
                'Confirm Logout',
                style: TextStyle(
                  fontSize: R.blockH * 5.5,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: R.blockV * 1.5),
              Text(
                'Are you sure you want to log out of RiskRadar?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: R.blockH * 3.75,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
              SizedBox(height: R.blockV * 3.5),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        fontSize: R.blockH * 4,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  SizedBox(width: R.blockH * 3.2),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: brandTeal,
                      padding: EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 4,
                    ),
                    child: Text(
                      'Logout',
                      style: TextStyle(
                        fontSize: R.blockH * 4,
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
        _showInfoSnackBar('Logging out...');

        await Supabase.instance.client.auth.signOut();

        if (context.mounted) {
          Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
        }
      } catch (e) {
        if (context.mounted) {
          _showErrorSnackBar('Logout failed: $e');
        }
      }
    }
  }

  void _onChangeSiteTap(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const HSEWorkerSitesScreen()),
    );
  }

  void _onEmergencyDetailsTap(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => HSEWorkerEmergencyDetailsScreen(
          hseWorkerId: Supabase.instance.client.auth.currentUser!.id,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    R.init(context);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: R.blockH * 4,
              vertical: R.blockV * 1.5,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _CompactSettingsTile(
                  icon: Icons.person_outline,
                  title: 'Profile',
                  subtitle: 'View and update your personal details',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const HSEWorkerEditProfileScreen(),
                      ),
                    );
                  },
                ),
                SizedBox(height: R.blockV * 2),
                _CompactSettingsTile(
                  icon: Icons.warning_amber_outlined,
                  iconColor: Colors.red.shade200,
                  title: 'Emergency Details',
                  subtitle: 'Update contacts and critical medical info',
                  onTap: () => _onEmergencyDetailsTap(context),
                ),
                SizedBox(height: R.blockV * 2),
                _CompactSettingsTile(
                  icon: Icons.location_on_outlined,
                  title: 'Change Current Site',
                  subtitle: 'Select or switch your active work site',
                  onTap: () => _onChangeSiteTap(context),
                ),
                SizedBox(height: R.blockV * 2),
                _CompactSettingsTile(
                  icon: _isAvailable
                      ? Icons.assignment_turned_in_outlined
                      : Icons.pause_circle_outline_rounded,
                  iconColor: _isAvailable
                      ? AppColors.accentGold
                      : Colors.white70,
                  title: 'Availability',
                  subtitle: _isAvailable
                      ? _availabilityEnabledText
                      : _availabilityDisabledText,
                  enableTileTap: false,
                  trailing: Switch(
                    value: _isAvailable,
                    onChanged: _isSavingAvailability
                        ? null
                        : _handleAvailabilityChanged,
                    activeThumbColor: AppColors.accentGold,
                    activeTrackColor: AppColors.brandTeal.withValues(
                      alpha: 0.65,
                    ),
                    inactiveThumbColor: Colors.white,
                    inactiveTrackColor: const Color(0xFF355F67),
                  ),
                  onTap: () {},
                ),
                SizedBox(height: R.blockV * 2),
                _CompactSettingsTile(
                  icon: Icons.color_lens_outlined,
                  title: isDark ? 'Dark Mode' : 'Light Mode',
                  subtitle: 'Adjust RiskRadar appearance',
                  enableTileTap: false,
                  trailing: ThemeToggle(
                    isDark: isDark,
                    onChanged: (bool value) {
                      widget.onThemeChanged(
                        value ? ThemeMode.dark : ThemeMode.light,
                      );
                    },
                  ),
                  onTap: () {},
                ),
                SizedBox(height: R.blockV * 2),
                _CompactSettingsTile(
                  icon: Icons.notifications_outlined,
                  title: 'Notifications',
                  subtitle: 'Manage notification preferences',
                  onTap: () =>
                      _showInfoSnackBar('Notification settings coming soon'),
                ),
                SizedBox(height: R.blockV * 2),
                _CompactSettingsTile(
                  icon: Icons.security_outlined,
                  title: 'Privacy & Security',
                  subtitle: 'Change password and privacy options',
                  onTap: () =>
                      _showInfoSnackBar('Privacy settings coming soon'),
                ),
                SizedBox(height: R.blockV * 2),
                _CompactSettingsTile(
                  icon: Icons.info_outline,
                  title: 'About App',
                  subtitle: 'Learn more about this application',
                  onTap: () => widget.onAboutTap(context),
                ),
                SizedBox(height: R.blockV * 4),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: <Color>[Colors.red.shade600, Colors.red.shade800],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: Colors.red.shade600.withValues(alpha: 0.32),
                        blurRadius: 14,
                        spreadRadius: 1,
                        offset: Offset(0, 6),
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
                    icon: Icon(Icons.logout, size: 22),
                    label: Text(
                      'Sign Out',
                      style: TextStyle(
                        fontSize: R.blockH * 4,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: R.blockV * 2),
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
    R.init(context);
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final Color cardBase = isDark
        ? Color.lerp(AppColors.brandTeal, Colors.black, 0.35)!
        : AppColors.brandTeal;

    return InkWell(
      onTap: enableTileTap ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: R.blockH * 4,
          vertical: R.blockV * 2,
        ),
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
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, color: iconColor ?? Colors.white, size: 26),
            SizedBox(width: R.blockH * 4.267),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: R.blockH * 4,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: R.blockV * 0.5),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: R.blockH * 3,
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
              Icon(Icons.chevron_right, color: Colors.white70, size: 24),
          ],
        ),
      ),
    );
  }
}

class ThemeToggle extends StatelessWidget {
  final bool isDark;
  final ValueChanged<bool> onChanged;

  const ThemeToggle({super.key, required this.isDark, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    R.init(context);
    final trackLight = Colors.grey.shade300;
    final trackDark = Colors.grey.shade800;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!isDark),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        width: R.blockH * 22.933,
        height: R.blockV * 4.75,
        padding: EdgeInsets.symmetric(horizontal: R.blockH * 1.5),
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
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.only(left: R.blockH * 2.5),
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
                padding: EdgeInsets.only(right: R.blockH * 2.5),
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
                width: R.blockH * 9.067,
                height: R.blockV * 4.25,
                decoration: BoxDecoration(
                  color: isDark
                      ? Theme.of(context).colorScheme.primary
                      : Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 4,
                      offset: Offset(0, 2),
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
