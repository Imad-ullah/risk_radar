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
  bool _isCustomHazardDialogOpen = false;

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
  Future<void> _addCustomHazard() async {
    final mediaQuery = MediaQuery.of(context);
    final size = mediaQuery.size;
    final visibleHeight =
        size.height - mediaQuery.padding.top - mediaQuery.padding.bottom;
    setState(() => _isCustomHazardDialogOpen = true);
    await showDialog(
      context: context,
      builder: (dialogContext) {
        final dialogMediaQuery = MediaQuery.of(dialogContext);
        final keyboardInset = dialogMediaQuery.viewInsets.bottom;
        final keyboardOpen = keyboardInset > size.height * 0.001;
        final availableDialogHeight = visibleHeight - keyboardInset;
        String customHazardName = "";

        return PopScope(
          canPop: !keyboardOpen,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop && keyboardOpen) {
              FocusScope.of(dialogContext).unfocus();
            }
          },
          child: GestureDetector(
            onTap: () => FocusScope.of(dialogContext).unfocus(),
            child: Dialog(
              insetPadding: EdgeInsets.symmetric(
                horizontal: size.width * 0.085,
                vertical: visibleHeight * 0.018,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(size.width * 0.071),
              ),
              backgroundColor:
                  Colors.transparent, // Transparent to show gradient container
              elevation: 0,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: availableDialogHeight * 0.760,
                ),
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(size.width * 0.071),
                      // RiskRadar Theme Gradient
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [_brandTeal, _brandTeal.withValues(alpha: 0.8)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: size.width * 0.038,
                          offset: Offset(
                            size.width * 0.0,
                            visibleHeight * 0.012,
                          ),
                        ),
                      ],
                    ),
                    padding: EdgeInsets.all(size.width * 0.048),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: EdgeInsets.all(size.width * 0.030),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.add_circle_outline_rounded,
                            color: Colors.white,
                            size: size.width * 0.064,
                          ),
                        ),
                        SizedBox(height: visibleHeight * 0.016),
                        Text(
                          'Add Custom Hazard',
                          style: TextStyle(
                            fontSize: size.width * 0.047,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ), // White text on gradient
                        ),
                        SizedBox(height: visibleHeight * 0.018),
                        // Input Field inside Dialog
                        TextField(
                          autofocus: false,
                          maxLength: _maxCustomHazardTitleLength,
                          inputFormatters: const [
                            SanitizingTextInputFormatter(),
                          ],
                          style: TextStyle(
                            fontSize: size.width * 0.038,
                            fontWeight: FontWeight.w500,
                            color: Colors.black87,
                          ), // Black text inside input
                          cursorColor: _brandTeal,
                          decoration: InputDecoration(
                            hintText: "Enter hazard name",
                            hintStyle: TextStyle(color: Colors.grey[500]),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                size.width * 0.041,
                              ),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: Colors.white, // White input background
                            counterStyle: TextStyle(color: Colors.white70),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: size.width * 0.038,
                              vertical: visibleHeight * 0.012,
                            ),
                          ),
                          onChanged: (value) =>
                              customHazardName = InputSanitizer.cleanText(
                                value,
                                maxLength: _maxCustomHazardTitleLength,
                              ),
                        ),
                        SizedBox(height: visibleHeight * 0.014),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => Navigator.pop(dialogContext),
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.symmetric(
                                  horizontal: size.width * 0.044,
                                  vertical: visibleHeight * 0.010,
                                ),
                                foregroundColor:
                                    Colors.white, // White text button
                              ),
                              child: Text(
                                'Cancel',
                                style: TextStyle(
                                  fontSize: size.width * 0.038,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            SizedBox(width: size.width * 0.024),
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
                                    _selectionOrder[newHazard['label']
                                            as String] =
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
                                elevation: size.width * 0.010,
                                padding: EdgeInsets.symmetric(
                                  horizontal: size.width * 0.048,
                                  vertical: visibleHeight * 0.011,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    size.width * 0.041,
                                  ),
                                ),
                              ),
                              child: Text(
                                'Add',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: size.width * 0.038,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    if (mounted) {
      setState(() => _isCustomHazardDialogOpen = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final size = mediaQuery.size;
    final visibleHeight =
        size.height - mediaQuery.padding.top - mediaQuery.padding.bottom;
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
      resizeToAvoidBottomInset: false,
      // Use a Stack to overlay the curved top bar
      body: Stack(
        children: [
          // Main Content Grid
          Padding(
            // Top padding matches the height of the custom top bar
            padding: EdgeInsets.only(top: visibleHeight * 0.213),
            child: TickerMode(
              enabled: !_isCustomHazardDialogOpen,
              child: filteredHazards.isEmpty
                  ? _buildEmptyState(isDarkTheme)
                  : _buildHazardGrid(filteredHazards),
            ),
          ),

          // Custom Curved Top Bar
          _buildCurvedTopBar(isDarkTheme),
        ],
      ),
      floatingActionButton: _isCustomHazardDialogOpen
          ? null
          : _buildFloatingActionButtons(),
    );
  }

  // --- Curved Top Bar with Round Search Box ---
  Widget _buildCurvedTopBar(bool isDarkTheme) {
    final mediaQuery = MediaQuery.of(context);
    final size = mediaQuery.size;
    final visibleHeight =
        size.height - mediaQuery.padding.top - mediaQuery.padding.bottom;
    final headerRowHeight = visibleHeight * 0.052;
    final searchHeight = visibleHeight * 0.054;
    final headerGap = visibleHeight * 0.006;
    return Container(
      height: visibleHeight * 0.225,
      decoration: BoxDecoration(
        color: _brandTeal,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(size.width * 0.061),
          bottomRight: Radius.circular(size.width * 0.061),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            size.width * 0.040,
            visibleHeight * 0.010,
            size.width * 0.040,
            visibleHeight * 0.020,
          ),
          child: Column(
            children: [
              // Header Row
              SizedBox(
                height: headerRowHeight,
                child: Row(
                  children: [
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: BoxConstraints(
                        minWidth: size.width * 0.112,
                        minHeight: headerRowHeight,
                      ),
                      icon: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Colors.white,
                        size: size.width * 0.056,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    Expanded(
                      child: Text(
                        'Select Hazard Types',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: size.width * 0.046,
                          color: Colors.white,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    SizedBox(width: size.width * 0.112),
                  ],
                ),
              ),
              SizedBox(height: headerGap),

              // --- Search Bar (Proper Pill Shape) ---
              SizedBox(
                height: searchHeight,
                child: TextField(
                  controller: _searchController,
                  // Text style is black to contrast with white background
                  style: TextStyle(
                    color: Colors.black87,
                    fontSize: size.width * 0.036,
                  ),
                  decoration: InputDecoration(
                    hintText: "Search hazards...",
                    hintStyle: TextStyle(
                      color: Colors.grey[500],
                      fontSize: size.width * 0.036,
                    ),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      color: Colors.grey[600],
                      size: size.width * 0.056,
                    ),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            padding: EdgeInsets.zero,
                            icon: Icon(
                              Icons.clear_rounded,
                              color: Colors.grey[600],
                              size: size.width * 0.056,
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
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: size.width * 0.051,
                      vertical: visibleHeight * 0.010,
                    ),

                    // Round Borders
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(size.width * 0.077),
                      borderSide: BorderSide.none, // No line
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(size.width * 0.077),
                      borderSide: BorderSide.none, // No line
                    ),
                  ),
                  onChanged: (value) =>
                      setState(() => _searchQuery = value.trim()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isDarkTheme) {
    final mediaQuery = MediaQuery.of(context);
    final size = mediaQuery.size;
    final visibleHeight =
        size.height - mediaQuery.padding.top - mediaQuery.padding.bottom;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: EdgeInsets.all(size.width * 0.060),
            decoration: BoxDecoration(
              color: isDarkTheme ? Colors.grey[900] : Colors.grey[100],
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.search_off_rounded,
              size: size.width * 0.143,
              color: isDarkTheme ? Colors.grey[700] : Colors.grey[400],
            ),
          ),
          SizedBox(height: visibleHeight * 0.025),
          Text(
            "No hazards found",
            style: TextStyle(
              fontSize: size.width * 0.050,
              fontWeight: FontWeight.w700,
              color: isDarkTheme ? Colors.white : Colors.black87,
            ),
          ),
          SizedBox(height: visibleHeight * 0.010),
          Text(
            "Try a different search term",
            style: TextStyle(
              fontSize: size.width * 0.038,
              color: isDarkTheme ? Colors.grey[400] : Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHazardGrid(List<Map<String, dynamic>> filteredHazards) {
    final mediaQuery = MediaQuery.of(context);
    final size = mediaQuery.size;
    final visibleHeight =
        size.height - mediaQuery.padding.top - mediaQuery.padding.bottom;
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(
        size.width * 0.040,
        visibleHeight * 0.020,
        size.width * 0.040,
        visibleHeight * 0.113,
      ),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: size.width * 0.031,
        mainAxisSpacing: visibleHeight * 0.015,
        childAspectRatio: 0.88,
      ),
      itemCount: filteredHazards.length,
      itemBuilder: (context, index) {
        final hazard = filteredHazards[index];
        final label = hazard['label'] as String;
        final isSelected = _selected.contains(label);

        return RepaintBoundary(
          child: HazardCard(
            hazard: hazard,
            isSelected: isSelected,
            hazardColor: hazard['color'] as Color,
            label: label,
            selectionNumber: _selectionOrder[label],
            onTap: () => _toggleSelection(label),
          ),
        );
      },
    );
  }

  Widget _buildFloatingActionButtons() {
    final mediaQuery = MediaQuery.of(context);
    final size = mediaQuery.size;
    final visibleHeight =
        size.height - mediaQuery.padding.top - mediaQuery.padding.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: visibleHeight * 0.010),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Padding(
            padding: EdgeInsets.only(left: size.width * 0.080),
            child: FloatingActionButton(
              heroTag: 'addCustomHazard',
              onPressed: _addCustomHazard,
              backgroundColor: Colors.white,
              foregroundColor: _brandTeal,
              elevation: size.width * 0.010,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(size.width * 0.041),
              ),
              child: Icon(Icons.add_rounded, size: size.width * 0.081),
            ),
          ),
          FloatingActionButton.extended(
            heroTag: 'confirmSelection',
            onPressed: _selected.isEmpty
                ? null
                : () => Navigator.pop(context, _selected.toList()),
            icon: Icon(Icons.check_circle_rounded, size: size.width * 0.056),
            label: Text(
              'Confirm',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: size.width * 0.040,
              ),
            ),
            backgroundColor: _selected.isEmpty
                ? Colors.grey.shade400
                : _brandTeal,
            foregroundColor: Colors.white,
            elevation: _selected.isEmpty
                ? size.width * 0.0
                : size.width * 0.010,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(size.width * 0.041),
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
    final mediaQuery = MediaQuery.of(context);
    final size = mediaQuery.size;
    final visibleHeight =
        size.height - mediaQuery.padding.top - mediaQuery.padding.bottom;
    final iconData = widget.hazard['icon'];
    Widget iconWidget;

    if (iconData is String && iconData.endsWith('.svg')) {
      iconWidget = SvgPicture.asset(
        iconData,
        fit: BoxFit.contain,
        placeholderBuilder: (_) =>
            Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    } else {
      iconWidget = SvgPicture.asset(
        HazardCard._fallbackPath,
        fit: BoxFit.contain,
        placeholderBuilder: (_) =>
            Center(child: CircularProgressIndicator(strokeWidth: 2)),
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
                borderRadius: BorderRadius.circular(size.width * 0.051),
                splashColor: widget.hazardColor.withValues(alpha: 0.3),
                highlightColor: widget.hazardColor.withValues(alpha: 0.2),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  decoration: BoxDecoration(
                    color: widget.hazardColor,
                    borderRadius: BorderRadius.circular(size.width * 0.051),
                    border: Border.all(
                      color: widget.isSelected
                          ? Colors.white
                          : widget.hazardColor,
                      width: widget.isSelected ? size.width * 0.010 : 0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: widget.hazardColor.withValues(
                          alpha: widget.isSelected ? 0.6 : 0.3,
                        ),
                        blurRadius: widget.isSelected
                            ? size.width * 0.041
                            : size.width * 0.020,
                        offset: Offset(
                          size.width * 0.0,
                          widget.isSelected
                              ? visibleHeight * 0.008
                              : visibleHeight * 0.004,
                        ),
                        spreadRadius: widget.isSelected
                            ? size.width * 0.005
                            : size.width * 0.0,
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      // Icon
                      Positioned.fill(
                        bottom: visibleHeight * 0.044,
                        child: Padding(
                          padding: EdgeInsets.all(size.width * 0.030),
                          child: Center(
                            child: SizedBox(
                              width: double.infinity,
                              height: double.infinity,
                              child: FittedBox(
                                fit: BoxFit.contain,
                                child: SizedBox(
                                  width: size.width * 0.267,
                                  height: visibleHeight * 0.125,
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
                          top: visibleHeight * 0.010,
                          right: size.width * 0.020,
                          child: Container(
                            width: size.width * 0.075,
                            height: visibleHeight * 0.035,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: widget.hazardColor,
                                width: size.width * 0.006,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  blurRadius: size.width * 0.015,
                                  offset: Offset(
                                    size.width * 0.0,
                                    visibleHeight * 0.003,
                                  ),
                                ),
                              ],
                            ),
                            child: Text(
                              widget.selectionNumber.toString(),
                              style: TextStyle(
                                fontSize: size.width * 0.035,
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
                            borderRadius: BorderRadius.only(
                              bottomLeft: Radius.circular(size.width * 0.051),
                              bottomRight: Radius.circular(size.width * 0.051),
                            ),
                          ),
                          padding: EdgeInsets.symmetric(
                            horizontal: size.width * 0.015,
                            vertical: visibleHeight * 0.008,
                          ),
                          child: Text(
                            widget.label,
                            style: TextStyle(
                              fontSize: size.width * 0.033,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                              height: visibleHeight * 0.0014,
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
