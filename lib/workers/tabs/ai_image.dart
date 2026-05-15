// lib/screens/ai_image.dart

import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:riskradar/workers/screens/worker_hazard_report_screen.dart';
import 'package:riskradar/services/hazard_service.dart';

class HazardScreen extends StatefulWidget {
  const HazardScreen({super.key});

  @override
  State<HazardScreen> createState() => _HazardScreenState();
}

class _HazardScreenState extends State<HazardScreen> with TickerProviderStateMixin {
  final HazardService _hazardService = HazardService();

  File? _selectedImage;
  Map<String, dynamic>? _analysisResults;
  bool _isLoading = false;
  String? _errorMessage;

  // --- Brand Styling ---
  static const Color _brandTeal = Color(0xFF1B3D3D);
  static const Color _accentGold = Color(0xFFE6A050);

  // --- Animation Controllers ---
  late AnimationController _scannerController;
  late Animation<double> _scannerAnimation;

  @override
  void initState() {
    super.initState();
    // Laser Sweep Animation setup
    _scannerController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _scannerAnimation = Tween<double>(begin: 0, end: 1).animate(_scannerController);
  }

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  // --- Logic Methods ---

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.camera);

    if (pickedFile != null) {
      setState(() {
        _selectedImage = File(pickedFile.path);
        _analysisResults = null;
        _errorMessage = null;
      });
    }
  }

  Future<void> _analyzeImage() async {
    if (_selectedImage == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await _hazardService.detectHazards(_selectedImage!);
      setState(() => _analysisResults = result);
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _proceedToReport() {
    if (_selectedImage == null || _analysisResults == null) return;

    final summary = _analysisResults!['summary'] ?? '';
    final hazards = _analysisResults!['hazards'] as List<dynamic>;

    StringBuffer descriptionBuffer = StringBuffer();
    descriptionBuffer.writeln("AI Assessment Summary: $summary\n");

    String severity = 'Low';
    List<String> hazardTypes = [];

    for (var hazard in hazards) {
      String hazSev = hazard['severity'] ?? 'Low';
      String hazType = hazard['category'] ?? 'General';
      String hazDesc = hazard['description'] ?? '';
      String hazAction = hazard['action'] ?? '';

      descriptionBuffer.writeln("- [${hazSev.toUpperCase()}] $hazType: $hazDesc (Action: $hazAction)");

      if (hazSev.toLowerCase() == 'critical' || hazSev.toLowerCase() == 'high') {
        severity = 'High';
      } else if (hazSev.toLowerCase() == 'medium' && severity != 'High') {
        severity = 'Moderate';
      }

      if (!hazardTypes.contains(hazType)) {
        hazardTypes.add(hazType);
      }
    }

    // Direct data transfer to the Report Screen using the provided parameters
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => WorkerReportHazardScreen(
          initialImage: _selectedImage,
          initialDescription: descriptionBuffer.toString().trim(),
          initialSeverity: severity,
          initialHazardTypes: hazardTypes,
        ),
      ),
    );
  }

  void _resetScanner() {
    setState(() {
      _selectedImage = null;
      _analysisResults = null;
      _errorMessage = null;
    });
    _pickImage();
  }

  Color _getSeverityColor(String? severity) {
    switch (severity?.toLowerCase()) {
      case 'critical':
      case 'high': return Colors.red.shade700;
      case 'medium':
      case 'moderate': return Colors.orange.shade800;
      case 'low': return Colors.green.shade700;
      default: return Colors.grey.shade700;
    }
  }

  // --- UI Switcher ---

  @override
  Widget build(BuildContext context) {
    // If analysis is done, show the result list preview
    if (_analysisResults != null) {
      return _buildResultsDetailView();
    }
    // Otherwise, show the scanning/capture interface
    return _buildScannerView();
  }

  // ---------------------------------------------------------------------------
  // VIEW 1: THE SCANNER INTERFACE
  // ---------------------------------------------------------------------------
  Widget _buildScannerView() {
    final bool hasImage = _selectedImage != null;

    return Scaffold(
      backgroundColor: _brandTeal,
      appBar: AppBar(
        title: const Text("AI Safety Scanner", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (hasImage)
            IconButton(icon: const Icon(Icons.refresh, color: Colors.white), onPressed: _resetScanner)
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 10),
          Expanded(
            flex: 3,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 10))],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (hasImage) Image.file(_selectedImage!, fit: BoxFit.cover) else const _ScannerPlaceholder(),
                    if (_isLoading) _buildLaserScanner(),
                    if (hasImage && !_isLoading) const _ScannerOverlay(),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildStatusText(hasImage),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: _buildScannerActionButton(hasImage),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // VIEW 2: THE RESULTS DETAIL PREVIEW (Premium UI)
  // ---------------------------------------------------------------------------
  Widget _buildResultsDetailView() {
    final summary = _analysisResults!['summary'] ?? "";
    final hazards = _analysisResults!['hazards'] as List<dynamic>;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Scan Preview", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: _brandTeal,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.refresh_rounded, color: Colors.white),
          onPressed: _resetScanner, // Allow rescanning
        ),
      ),
      body: Column(
        children: [
          // Visual context image header
          Container(
            height: 180,
            width: double.infinity,
            decoration: const BoxDecoration(color: Colors.black),
            child: Image.file(_selectedImage!, fit: BoxFit.cover),
          ),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Assessment Summary Section
                  const Text(
                      "ASSESSMENT SUMMARY",
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: _brandTeal, letterSpacing: 1.1)
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: const Color(0xFFF5F7FA), borderRadius: BorderRadius.circular(16)),
                    child: Text(
                        summary,
                        style: TextStyle(fontSize: 14, height: 1.5, color: Colors.grey[900], fontWeight: FontWeight.w500)
                    ),
                  ),
                  const SizedBox(height: 25),

                  // Hazards List Section
                  const Text(
                      "DETAILED HAZARDS & ACTIONS",
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: _brandTeal, letterSpacing: 1.1)
                  ),
                  const SizedBox(height: 10),
                  ...hazards.map((h) => _buildHazardResultCard(h)),
                ],
              ),
            ),
          ),

          // Bottom Action: Generate Report
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -5))]
            ),
            child: SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _proceedToReport,
                icon: const Icon(Icons.assignment_turned_in_rounded, color: Colors.white),
                label: const Text("GENERATE OFFICIAL REPORT", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFC62828), // Deep Alert Red
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
                ),
              ),
            ),
          )
        ],
      ),
    );
  }

  // --- Helper Widget: Detailed Hazard Card ---
  Widget _buildHazardResultCard(Map<String, dynamic> hazard) {
    final sevColor = _getSeverityColor(hazard['severity']);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 5, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                  hazard['category'] ?? "General",
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black)
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: sevColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: Text(
                    (hazard['severity'] ?? "LOW").toUpperCase(),
                    style: TextStyle(color: sevColor, fontWeight: FontWeight.bold, fontSize: 11)
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
              hazard['description'] ?? "",
              style: TextStyle(fontSize: 14, color: Colors.grey[800], height: 1.3)
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: Colors.grey),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.bolt_rounded, size: 18, color: sevColor),
              const SizedBox(width: 8),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: TextStyle(fontSize: 13, color: Colors.grey[900], height: 1.4),
                    children: [
                      const TextSpan(text: "Action Needed: ", style: TextStyle(fontWeight: FontWeight.bold)),
                      TextSpan(text: hazard['action'] ?? 'Review immediately'),
                    ],
                  ),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  // --- Helper Widgets: Scanner UI ---

  Widget _buildLaserScanner() {
    return AnimatedBuilder(
      animation: _scannerAnimation,
      builder: (context, child) {
        return Stack(
          children: [
            Container(color: Colors.black.withValues(alpha: 0.2)),
            Positioned(
              top: MediaQuery.of(context).size.height * 0.45 * _scannerAnimation.value,
              left: 0, right: 0,
              child: Container(
                height: 4,
                decoration: BoxDecoration(
                  boxShadow: [BoxShadow(color: _accentGold.withValues(alpha: 0.8), blurRadius: 15, spreadRadius: 4)],
                  gradient: const LinearGradient(colors: [Colors.transparent, _accentGold, Colors.transparent]),
                ),
              ),
            ),
            const Center(child: CircularProgressIndicator(color: Colors.white)),
          ],
        );
      },
    );
  }

  Widget _buildStatusText(bool hasImage) {
    if (_errorMessage != null) return Text("Error: $_errorMessage", textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFFF8A80)));
    if (_isLoading) return const Text("Analyzing site imagery...", textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold));
    return Text(
      hasImage ? "Capture locked. Tap to analyze site." : "Position the hazard inside the frame\nand ensure good lighting.",
      textAlign: TextAlign.center,
      style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 14, height: 1.5, fontWeight: FontWeight.w500),
    );
  }

  Widget _buildScannerActionButton(bool hasImage) {
    if (_isLoading) return const SizedBox.shrink();
    if (!hasImage) return _cmdBtn("CAPTURE PHOTO", Icons.camera_alt_rounded, _pickImage, _accentGold, Colors.white);
    return _cmdBtn("ANALYZE SITE", Icons.analytics_rounded, _analyzeImage, _accentGold, Colors.white);
  }

  Widget _cmdBtn(String label, IconData icon, VoidCallback onPressed, Color bg, Color tx) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, color: tx),
      label: Text(label, textAlign: TextAlign.center, style: TextStyle(color: tx, fontWeight: FontWeight.bold, fontSize: 16)),
      style: ElevatedButton.styleFrom(backgroundColor: bg, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 0),
    );
  }
}

class _ScannerPlaceholder extends StatelessWidget {
  const _ScannerPlaceholder();
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.qr_code_scanner_rounded, size: 80, color: Colors.grey.shade300),
        const SizedBox(height: 20),
        Text("Scanner Standby", style: TextStyle(color: Colors.grey.shade400, fontSize: 18, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

class _ScannerOverlay extends StatelessWidget {
  const _ScannerOverlay();
  @override
  Widget build(BuildContext context) {
    return const Stack(
      children: [
        Positioned(left: 20, top: 20, child: _ScannerCorner(rotation: 0)),
        Positioned(right: 20, top: 20, child: _ScannerCorner(rotation: 1)),
        Positioned(right: 20, bottom: 20, child: _ScannerCorner(rotation: 2)),
        Positioned(left: 20, bottom: 20, child: _ScannerCorner(rotation: 3)),
      ],
    );
  }
}

class _ScannerCorner extends StatefulWidget {
  final int rotation;
  const _ScannerCorner({required this.rotation});
  @override
  State<_ScannerCorner> createState() => _ScannerCornerState();
}

class _ScannerCornerState extends State<_ScannerCorner> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..repeat(reverse: true);
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.3, end: 1.0).animate(_ctrl),
      child: RotatedBox(
        quarterTurns: widget.rotation,
        child: Container(
          width: 44, height: 44,
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: Colors.white, width: 4),
              left: BorderSide(color: Colors.white, width: 4),
            ),
          ),
        ),
      ),
    );
  }
}
