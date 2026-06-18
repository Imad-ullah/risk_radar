import 'dart:async';

import 'package:flutter/material.dart';
import 'package:riskradar/utils/responsive.dart';
import 'package:riskradar/services/connectivity_service.dart';

class OfflineBanner extends StatefulWidget {
  const OfflineBanner({super.key});

  static const String offlineMessage =
      "📡 You're offline. Changes will sync when reconnected.";

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slideAnimation;
  late final StreamSubscription<bool> _subscription;

  bool _isOnline = ConnectivityService.instance.isOnline;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _slideAnimation = Tween<Offset>(
      begin: Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _subscription = ConnectivityService.instance.isOnlineStream.listen(
      _handleConnectivityChanged,
    );
    if (!_isOnline) {
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _subscription.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _handleConnectivityChanged(bool isOnline) {
    if (!mounted) {
      return;
    }
    setState(() {
      _isOnline = isOnline;
    });
    if (isOnline) {
      _controller.reverse();
    } else {
      _controller.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    R.init(context);
    return ClipRect(
      child: SizeTransition(
        sizeFactor: _controller,
        axisAlignment: -1,
        child: SlideTransition(
          position: _slideAnimation,
          child: Semantics(
            liveRegion: true,
            label: _isOnline ? 'Online' : OfflineBanner.offlineMessage,
            child: Container(
              width: double.infinity,
              color: Colors.orange.shade700,
              padding: EdgeInsets.only(
                left: R.blockH * 4,
                right: R.blockH * 4,
                top: MediaQuery.paddingOf(context).top > 0 ? 10 : 8,
                bottom: 8,
              ),
              child: SafeArea(
                top: false,
                bottom: false,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        OfflineBanner.offlineMessage,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: R.blockH * 3.25,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
