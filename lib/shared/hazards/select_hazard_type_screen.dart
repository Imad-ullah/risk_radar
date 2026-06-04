// lib/shared/hazards/select_hazard_type_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:riskradar/shared/security/input_sanitizer.dart';

class SelectHazardTypeScreen extends StatefulWidget {
  const SelectHazardTypeScreen({super.key});

  @override
  State<SelectHazardTypeScreen> createState() => _SelectHazardTypeScreenState();
}

class _SelectHazardTypeScreenState extends State<SelectHazardTypeScreen> {
  // Brand Color Definition
  static const Color _brandTeal = Color(0xFF1B3D3D);
  static const int _maxSelectedHazards = 4;
  static const int _maxCustomHazardTitleLength = 40;
  static const String _maxHazardsMessage =
      'You can only select up to 4 hazards.';

  final List<Map<String, dynamic>> hazardTypes = [
    {
      'icon': 'assets/hazards/fire_warning.svg',
      'label': 'Fire',
      'color': const Color(0xFFFF6B35),
    },
    {
      'icon': 'assets/hazards/explosion.svg',
      'label': 'Explosives',
      'color': const Color(0xFFD84315),
    },
    {
      'icon': 'assets/hazards/radio_waves.svg',
      'label': 'Radio Waves',
      'color': const Color(0xFFF9A825),
    },
    {
      'icon': 'assets/hazards/freeze.svg',
      'label': 'Freeze',
      'color': const Color(0xFF00796B),
    },
    {
      'icon': 'assets/hazards/magnetic_field.svg',
      'label': 'Magnetic Field',
      'color': const Color(0xFF00BFA5),
    },
    {
      'icon': 'assets/hazards/machine_crush.svg',
      'label': 'Machine Crush',
      'color': const Color(0xFF616161),
    },
    {
      'icon': 'assets/hazards/falling_objects.svg',
      'label': 'Falling Objects',
      'color': const Color(0xFFFF9800),
    },
    {
      'icon': 'assets/hazards/high_temperature.svg',
      'label': 'High Temperature',
      'color': const Color(0xFFE64A19),
    },
    {
      'icon': 'assets/hazards/high_heat.svg',
      'label': 'High Heat',
      'color': const Color(0xFFEF6C00),
    },
    {
      'icon': 'assets/hazards/stairs_fall.svg',
      'label': 'Stairs Falls',
      'color': const Color(0xFFFF6F00),
    },
    {
      'icon': 'assets/hazards/radio_active.svg',
      'label': 'Radioactive',
      'color': const Color(0xFF4A148C),
    },
    {
      'icon': 'assets/hazards/slip_falling.svg',
      'label': 'Slip / Wet Floor',
      'color': const Color(0xFF2196F3),
    },
    {
      'icon': 'assets/hazards/electric_shock.svg',
      'label': 'Electrical / Shock',
      'color': const Color(0xFFFFC107),
    },
    {
      'icon': 'assets/hazards/load_lifting.svg',
      'label': 'Manual Handling',
      'color': const Color(0xFF6A1B9A),
    },
    {
      'icon': 'assets/hazards/fire_warning.svg',
      'label': 'Chemical Exposure',
      'color': const Color(0xFF9C27B0),
    },
    {
      'icon': 'assets/hazards/fire_warning.svg',
      'label': 'PPE Missing',
      'color': const Color(0xFFE53935),
    },
    {
      'icon': 'assets/hazards/fire_warning.svg',
      'label': 'Flooding',
      'color': const Color(0xFF0288D1),
    },
    {
      'icon': 'assets/hazards/fire_warning.svg',
      'label': 'Biological Hazard',
      'color': const Color(0xFF43A047),
    },
    {
      'icon': 'assets/hazards/fire_warning.svg',
      'label': 'Noise',
      'color': const Color(0xFF7B1FA2),
    },
    {
      'icon': 'assets/hazards/fire_warning.svg',
      'label': 'Dust / Air Quality',
      'color': const Color(0xFF78909C),
    },
    {
      'icon': 'assets/hazards/fire_warning.svg',
      'label': 'Poor Lighting',
      'color': const Color(0xFFFFB300),
    },
    {
      'icon': 'assets/hazards/fire_warning.svg',
      'label': 'Traffic / Vehicles',
      'color': const Color(0xFFD32F2F),
    },
    {
      'icon': 'assets/hazards/fire_warning.svg',
      'label': 'Equipment Failure',
      'color': const Color(0xFF616161),
    },
    {
      'icon': 'assets/hazards/fire_warning.svg',
      'label': 'Working at Heights',
      'color': const Color(0xFF1976D2),
    },
    {
      'icon': 'assets/hazards/fire_warning.svg',
      'label': 'Confined Spaces',
      'color': const Color(0xFF5D4037),
    },
    {
      'icon': 'assets/hazards/fire_warning.svg',
      'label': 'Scaffolding Hazard',
      'color': const Color(0xFF455A64),
    },
    {
      'icon': 'assets/hazards/fire_warning.svg',
      'label': 'Vibration',
      'color': const Color(0xFF00897B),
    },
    {
      'icon': 'assets/hazards/fire_warning.svg',
      'label': 'Collapsing Structures',
      'color': const Color(0xFF8D6E63),
    },
    {
      'icon': 'assets/hazards/fire_warning.svg',
      'label': 'Insects / Wildlife',
      'color': const Color(0xFF558B2F),
    },
    {
      'icon': 'assets/hazards/fire_warning.svg',
      'label': 'Uneven Ground',
      'color': const Color(0xFF689F38),
    },
    {
      'icon': 'assets/hazards/fire_warning.svg',
      'label': 'Unstable Excavation',
      'color': const Color(0xFFFF8F00),
    },
    {
      'icon': 'assets/hazards/fire_warning.svg',
      'label': 'Crane Operation',
      'color': const Color(0xFFF57C00),
    },
    {
      'icon': 'assets/hazards/fire_warning.svg',
      'label': 'Overhead Power Lines',
      'color': const Color(0xFFFDD835),
    },
    {
      'icon': 'assets/hazards/fire_warning.svg',
      'label': 'Crowded Work Area',
      'color': const Color(0xFF1E88E5),
    },
    {
      'icon': 'assets/hazards/fire_warning.svg',
      'label': 'Gas Leak',
      'color': const Color(0xFFAD1457),
    },
  ];

  final Set<String> _selected = {};
  final Map<String, int> _selectionOrder = {};
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";

  void _showMaxHazardsWarning() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text(_maxHazardsMessage)));
  }

  void _showInvalidInputWarning() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text(InputSanitizer.invalidInputMessage)),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleSelection(String label) {
    if (!_selected.contains(label) && _selected.length >= _maxSelectedHazards) {
      _showMaxHazardsWarning();
      return;
    }

    setState(() {
      if (_selected.contains(label)) {
        _selected.remove(label);
        final removedOrder = _selectionOrder.remove(label)!;
        _selectionOrder.updateAll(
          (key, value) => value > removedOrder ? value - 1 : value,
        );
      } else {
        _selected.add(label);
        _selectionOrder[label] = _selected.length;
      }
    });
  }

  // --- UPDATED: Gradient Dialog with Immediate Submit ---
  void _addCustomHazard() {
    showDialog(
      context: context,
      builder: (dialogContext) {
        String customHazardName = "";

        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          backgroundColor:
              Colors.transparent, // Transparent to show gradient container
          elevation: 0,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              // RiskRadar Theme Gradient
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_brandTeal, _brandTeal.withValues(alpha: 0.8)],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 15,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.add_circle_outline_rounded,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Add Custom Hazard',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ), // White text on gradient
                ),
                const SizedBox(height: 24),
                // Input Field inside Dialog
                TextField(
                  autofocus: true,
                  maxLength: _maxCustomHazardTitleLength,
                  inputFormatters: const [SanitizingTextInputFormatter()],
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                  ), // Black text inside input
                  cursorColor: _brandTeal,
                  decoration: InputDecoration(
                    hintText: "Enter hazard name",
                    hintStyle: TextStyle(color: Colors.grey[500]),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Colors.white, // White input background
                    counterStyle: const TextStyle(color: Colors.white70),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                  onChanged: (value) =>
                      customHazardName = InputSanitizer.cleanText(
                        value,
                        maxLength: _maxCustomHazardTitleLength,
                      ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        foregroundColor: Colors.white, // White text button
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () {
                        final validationError =
                            InputSanitizer.validateShortText(
                              customHazardName,
                              maxLength: _maxCustomHazardTitleLength,
                            );
                        if (validationError ==
                            InputSanitizer.invalidInputMessage) {
                          _showInvalidInputWarning();
                          return;
                        }
                        if (customHazardName.trim().isNotEmpty &&
                            validationError == null) {
                          if (_selected.length >= _maxSelectedHazards) {
                            Navigator.pop(dialogContext);
                            _showMaxHazardsWarning();
                            return;
                          }
                          setState(() {
                            final newHazard = {
                              'icon': Icons.warning_amber_rounded,
                              'label': customHazardName.trim(),
                              'color': const Color(0xFF757575),
                            };
                            hazardTypes.add(newHazard);
                            _selected.add(newHazard['label'] as String);
                            _selectionOrder[newHazard['label'] as String] =
                                _selected.length;
                          });

                          // 1. Close the Dialog
                          Navigator.pop(dialogContext);

                          // 2. IMMEDIATELY Return to previous screen with Selection
                          Navigator.pop(context, _selected.toList());
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white, // White button
                        foregroundColor: _brandTeal, // Teal text
                        elevation: 4,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        'Add',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;

    final filteredHazards = hazardTypes
        .where(
          (h) => h['label'].toString().toLowerCase().contains(
            _searchQuery.toLowerCase(),
          ),
        )
        .toList();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      // Use a Stack to overlay the curved top bar
      body: Stack(
        children: [
          // Main Content Grid
          Padding(
            // Top padding matches the height of the custom top bar
            padding: const EdgeInsets.only(top: 170.0),
            child: filteredHazards.isEmpty
                ? _buildEmptyState(isDarkTheme)
                : _buildHazardGrid(filteredHazards),
          ),

          // Custom Curved Top Bar
          _buildCurvedTopBar(isDarkTheme),
        ],
      ),
      floatingActionButton: _buildFloatingActionButtons(),
    );
  }

  // --- Curved Top Bar with Round Search Box ---
  Widget _buildCurvedTopBar(bool isDarkTheme) {
    return Container(
      height: 180,
      decoration: const BoxDecoration(
        color: _brandTeal,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            children: [
              // Header Row
              Row(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: Colors.white,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Expanded(
                    child: Text(
                      'Select Hazard Types',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 20,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 48), // Spacer to balance back button
                ],
              ),
              const Spacer(),

              // --- Search Bar (Proper Pill Shape) ---
              TextField(
                controller: _searchController,
                // Text style is black to contrast with white background
                style: const TextStyle(color: Colors.black87, fontSize: 15),
                decoration: InputDecoration(
                  hintText: "Search hazards...",
                  hintStyle: TextStyle(color: Colors.grey[500]),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: Colors.grey[600],
                  ),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: Icon(
                            Icons.clear_rounded,
                            color: Colors.grey[600],
                          ),
                          onPressed: () {
                            setState(() {
                              _searchController.clear();
                              _searchQuery = "";
                            });
                          },
                        )
                      : null,
                  // Background
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),

                  // Round Borders
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30), // Pill Shape
                    borderSide: BorderSide.none, // No line
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30), // Pill Shape
                    borderSide: BorderSide.none, // No line
                  ),
                ),
                onChanged: (value) =>
                    setState(() => _searchQuery = value.trim()),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isDarkTheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isDarkTheme ? Colors.grey[900] : Colors.grey[100],
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.search_off_rounded,
              size: 56,
              color: isDarkTheme ? Colors.grey[700] : Colors.grey[400],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            "No hazards found",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: isDarkTheme ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Try a different search term",
            style: TextStyle(
              fontSize: 15,
              color: isDarkTheme ? Colors.grey[400] : Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHazardGrid(List<Map<String, dynamic>> filteredHazards) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.88,
      ),
      itemCount: filteredHazards.length,
      itemBuilder: (context, index) {
        final hazard = filteredHazards[index];
        final label = hazard['label'] as String;
        final isSelected = _selected.contains(label);

        return HazardCard(
          hazard: hazard,
          isSelected: isSelected,
          hazardColor: hazard['color'] as Color,
          label: label,
          selectionNumber: _selectionOrder[label],
          onTap: () => _toggleSelection(label),
        );
      },
    );
  }

  Widget _buildFloatingActionButtons() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 32.0),
            child: FloatingActionButton(
              heroTag: 'addCustomHazard',
              onPressed: _addCustomHazard,
              backgroundColor: Colors.white,
              foregroundColor: _brandTeal,
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.add_rounded, size: 32),
            ),
          ),
          FloatingActionButton.extended(
            heroTag: 'confirmSelection',
            onPressed: _selected.isEmpty
                ? null
                : () => Navigator.pop(context, _selected.toList()),
            icon: const Icon(Icons.check_circle_rounded, size: 22),
            label: const Text(
              'Confirm',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            backgroundColor: _selected.isEmpty
                ? Colors.grey.shade400
                : _brandTeal,
            foregroundColor: Colors.white,
            elevation: _selected.isEmpty ? 0 : 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ],
      ),
    );
  }
}

// Enhanced Hazard Card with Flashing Animation
class HazardCard extends StatefulWidget {
  final Map<String, dynamic> hazard;
  final bool isSelected;
  final Color hazardColor;
  final String label;
  final int? selectionNumber;
  final VoidCallback onTap;

  static const String _fallbackPath = 'assets/icons/fire.svg';

  const HazardCard({
    super.key,
    required this.hazard,
    required this.isSelected,
    required this.hazardColor,
    required this.label,
    required this.onTap,
    this.selectionNumber,
  });

  @override
  State<HazardCard> createState() => _HazardCardState();
}

class _HazardCardState extends State<HazardCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.08), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.08, end: 1.0), weight: 50),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    _opacityAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.6), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 0.6, end: 1.0), weight: 50),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    if (widget.isSelected) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(HazardCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSelected && !oldWidget.isSelected) {
      _controller.repeat();
    } else if (!widget.isSelected && oldWidget.isSelected) {
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final iconData = widget.hazard['icon'];
    Widget iconWidget;

    if (iconData is String && iconData.endsWith('.svg')) {
      iconWidget = SvgPicture.asset(
        iconData,
        fit: BoxFit.contain,
        placeholderBuilder: (_) =>
            const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    } else {
      iconWidget = SvgPicture.asset(
        HazardCard._fallbackPath,
        fit: BoxFit.contain,
        placeholderBuilder: (_) =>
            const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.scale(
          scale: widget.isSelected ? _scaleAnimation.value : 1.0,
          child: Opacity(
            opacity: widget.isSelected ? _opacityAnimation.value : 1.0,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onTap,
                borderRadius: BorderRadius.circular(20),
                splashColor: widget.hazardColor.withValues(alpha: 0.3),
                highlightColor: widget.hazardColor.withValues(alpha: 0.2),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  decoration: BoxDecoration(
                    color: widget.hazardColor,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: widget.isSelected
                          ? Colors.white
                          : widget.hazardColor,
                      width: widget.isSelected ? 4 : 0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: widget.hazardColor.withValues(
                          alpha: widget.isSelected ? 0.6 : 0.3,
                        ),
                        blurRadius: widget.isSelected ? 16 : 8,
                        offset: Offset(0, widget.isSelected ? 6 : 3),
                        spreadRadius: widget.isSelected ? 2 : 0,
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      // Icon
                      Positioned.fill(
                        bottom: 35,
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Center(
                            child: SizedBox(
                              width: double.infinity,
                              height: double.infinity,
                              child: FittedBox(
                                fit: BoxFit.contain,
                                child: SizedBox(
                                  width: 100,
                                  height: 100,
                                  child: iconWidget,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Selection badge
                      if (widget.isSelected && widget.selectionNumber != null)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            width: 28,
                            height: 28,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: widget.hazardColor,
                                width: 2.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Text(
                              widget.selectionNumber.toString(),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                                color: widget.hazardColor,
                              ),
                            ),
                          ),
                        ),

                      // Label
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            borderRadius: const BorderRadius.only(
                              bottomLeft: Radius.circular(20),
                              bottomRight: Radius.circular(20),
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 6,
                          ),
                          child: Text(
                            widget.label,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                              height: 1.1,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
