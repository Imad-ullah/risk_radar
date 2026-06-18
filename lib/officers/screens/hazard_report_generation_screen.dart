// lib/hse_workers/screens/hazard_report_generation_screen.dart

import 'package:flutter/material.dart';
import 'package:riskradar/utils/responsive.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'package:riskradar/shared/widgets/voice_note_player.dart';
import 'package:riskradar/shared/theme/app_colors.dart';
import 'package:riskradar/services/repositories/officer_repository.dart';

class ResolvedHazardDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> hazard;

  const ResolvedHazardDetailsScreen({super.key, required this.hazard});

  @override
  State<ResolvedHazardDetailsScreen> createState() =>
      _ResolvedHazardDetailsScreenState();
}

class _ResolvedHazardDetailsScreenState
    extends State<ResolvedHazardDetailsScreen> {
  final supabase = Supabase.instance.client;

  bool _isLoadingResolver = true;
  Map<String, dynamic>? _resolverData;

  static const Color _successGreen = Color(0xFF10B981);

  @override
  void initState() {
    super.initState();
    _fetchAssignedWorkerName();
  }

  Future<void> _fetchAssignedWorkerName() async {
    final assignedUid =
        widget.hazard['assigned_to'] ?? widget.hazard['worker_id'];
    if (assignedUid == null) {
      if (mounted) setState(() => _isLoadingResolver = false);
      return;
    }

    try {
      final workerResp = await supabase
          .from('hse_workers')
          .select('first_name, last_name, designation, profile_image_url')
          .eq('id', assignedUid)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _resolverData = workerResp ?? _cachedResolver(assignedUid.toString());
          _isLoadingResolver = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _resolverData = _cachedResolver(assignedUid.toString());
          _isLoadingResolver = false;
        });
      }
      debugPrint("Error fetching assigned worker: $e");
    }
  }

  Map<String, dynamic>? _cachedResolver(String assignedUid) {
    final cachedWorkers = OfficerRepository.instance.getOfficerHseWorkers();
    if (cachedWorkers == null) return null;
    return cachedWorkers.firstWhere(
      (worker) => worker['id']?.toString() == assignedUid,
      orElse: () => {},
    );
  }

  String _formatName(String? fName, String? lName, String fallback) {
    final fullName = "${fName ?? ''} ${lName ?? ''}".trim();
    if (fullName.isEmpty) return fallback;

    return fullName
        .split(' ')
        .map((word) {
          if (word.isEmpty) return '';
          return word[0].toUpperCase() + word.substring(1).toLowerCase();
        })
        .join(' ');
  }

  String _getReporterName() {
    if (widget.hazard['reporter_name'] != null &&
        widget.hazard['reporter_name'].toString().isNotEmpty) {
      return widget.hazard['reporter_name'];
    }
    if (widget.hazard['reporter'] != null) {
      return _formatName(
        widget.hazard['reporter']['first_name'],
        widget.hazard['reporter']['last_name'],
        "Unknown",
      );
    }
    return "Unknown Reporter";
  }

  // ==================== PDF & EXPORT LOGIC ====================

  String _getDisplayId() {
    if (widget.hazard['report_number'] != null) {
      return "REPORT #${widget.hazard['report_number']}";
    }
    return "ID: ${widget.hazard['id'].toString().substring(0, 8).toUpperCase()}";
  }

  void _showLoadingDialog(String title) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: Theme.of(context).cardColor,
        child: Padding(
          padding: EdgeInsets.symmetric(
            vertical: R.blockV * 3,
            horizontal: R.blockH * 6,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 30,
                height: 30,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: AppColors.brandTeal,
                ),
              ),
              SizedBox(width: 19.999),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : AppColors.brandTeal,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      "Please keep the app open",
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark
                            ? Colors.grey.shade400
                            : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<Uint8List> _generatePdfBytes() async {
    final pdf = pw.Document();

    final reportedDate = _formatDate(widget.hazard['created_at']);
    final startedDate = _formatDate(widget.hazard['started_at']);
    final resolvedDate = _formatDate(widget.hazard['resolved_at']);
    final displayId = _getDisplayId();

    List<pw.ImageProvider> beforeImages = [];
    List<pw.ImageProvider> afterImages = [];
    pw.ImageProvider? logoImage;

    try {
      final ByteData bytes = await rootBundle.load('assets/logo.png');
      logoImage = pw.MemoryImage(bytes.buffer.asUint8List());
    } catch (e) {
      debugPrint("Could not load logo from assets: $e");
    }

    // Load Before Images
    try {
      final String? rawBeforeUrl =
          widget.hazard['image_url'] ?? widget.hazard['images']?.toString();
      if (rawBeforeUrl != null && rawBeforeUrl.isNotEmpty) {
        final urls = rawBeforeUrl.split(',');
        for (String url in urls) {
          if (url.trim().isNotEmpty)
            beforeImages.add(await networkImage(url.trim()));
        }
      }
    } catch (e) {
      debugPrint("Could not load before images for PDF");
    }

    // Load After Images
    try {
      final String? rawAfterUrl = widget.hazard['resolution_image_url'];
      if (rawAfterUrl != null && rawAfterUrl.isNotEmpty) {
        final urls = rawAfterUrl.split(',');
        for (String url in urls) {
          if (url.trim().isNotEmpty)
            afterImages.add(await networkImage(url.trim()));
        }
      }
    } catch (e) {
      debugPrint("Could not load after images for PDF");
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (context) => _buildPdfHeader(displayId, logoImage),
        build: (pw.Context context) {
          return [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Expanded(
                  child: _buildPdfPersonnelBox(
                    "REPORTED BY",
                    _getReporterName(),
                    widget.hazard['reporter']?['work_type'] ?? "Worker",
                  ),
                ),
                pw.SizedBox(width: 19.999),
                pw.Expanded(
                  child: _buildPdfPersonnelBox(
                    "RESOLVED BY",
                    _formatName(
                      _resolverData?['first_name'],
                      _resolverData?['last_name'],
                      "Unassigned",
                    ),
                    _resolverData?['designation'] ?? "Specialist",
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 20),

            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                _buildPdfMetricBox("DURATION", _calculateTime()),
                pw.SizedBox(width: 10.001),
                _buildPdfMetricBox(
                  "SEVERITY",
                  widget.hazard['severity'] ?? "LOW",
                ),
                pw.SizedBox(width: 10.001),
                _buildPdfMetricBox(
                  "IMPACT SCORE",
                  "${(_getSeverityValue(widget.hazard['severity']) * 100).toInt()}%",
                ),
              ],
            ),
            pw.SizedBox(height: 30),

            pw.Text(
              "METADATA LOG",
              style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
                color: PdfColor.fromHex('#1B3D3D'),
              ),
            ),
            pw.SizedBox(height: 10),
            pw.TableHelper.fromTextArray(
              headers: ['DATA FIELD', 'ENTRY LOG'],
              data: [
                ['Hazard Type', widget.hazard['hazard_type'] ?? "N/A"],
                [
                  'Location',
                  '${widget.hazard['latitude'] ?? 'N/A'}, ${widget.hazard['longitude'] ?? 'N/A'}',
                ],
                ['Reported At', reportedDate],
                ['Started At', startedDate],
                ['Resolved At', resolvedDate],
                [
                  'Resolution Notes',
                  widget.hazard['resolution_notes'] ?? "N/A",
                ],
              ],
              headerStyle: pw.TextStyle(
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
              ),
              headerDecoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#1B3D3D'),
              ),
              cellPadding: const pw.EdgeInsets.all(10),
              border: pw.TableBorder.all(color: PdfColors.grey300),
            ),
          ];
        },
      ),
    );

    // Image Pages
    if (beforeImages.isNotEmpty)
      _addPdfImagePage(
        pdf,
        "VISUAL VERIFICATION: INITIAL HAZARD (BEFORE)",
        beforeImages,
        displayId,
        logoImage,
      );
    if (afterImages.isNotEmpty)
      _addPdfImagePage(
        pdf,
        "VISUAL VERIFICATION: RESOLUTION PROOF (AFTER)",
        afterImages,
        displayId,
        logoImage,
      );

    return pdf.save();
  }

  void _addPdfImagePage(
    pw.Document pdf,
    String title,
    List<pw.ImageProvider> images,
    String displayId,
    pw.ImageProvider? logoImage,
  ) {
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (context) => _buildPdfHeader(displayId, logoImage),
        build: (pw.Context context) {
          return [
            pw.Text(
              title,
              style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
                color: PdfColor.fromHex('#1B3D3D'),
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Wrap(
              spacing: 15,
              runSpacing: 15,
              children: images
                  .map(
                    (img) => pw.Container(
                      width: 250.001,
                      height: 200,
                      decoration: pw.BoxDecoration(
                        image: pw.DecorationImage(
                          image: img,
                          fit: pw.BoxFit.cover,
                        ),
                        border: pw.Border.all(color: PdfColors.grey300),
                        borderRadius: const pw.BorderRadius.all(
                          pw.Radius.circular(8),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ];
        },
      ),
    );
  }

  pw.Widget _buildPdfHeader(String displayId, pw.ImageProvider? logoImage) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    "SAFETY COMPLIANCE AUDIT",
                    style: pw.TextStyle(
                      fontSize: 24,
                      color: PdfColor.fromHex('#1B3D3D'),
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    displayId,
                    style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
                  ),
                ],
              ),
            ),
            if (logoImage != null)
              pw.Container(
                height: 80,
                width: 139.999,
                alignment: pw.Alignment.centerRight,
                child: pw.Image(logoImage, fit: pw.BoxFit.contain),
              ),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Divider(color: PdfColor.fromHex('#1B3D3D'), thickness: 2),
        pw.SizedBox(height: 20),
      ],
    );
  }

  pw.Widget _buildPdfPersonnelBox(String title, String name, String role) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(
              fontSize: 9,
              color: PdfColors.grey600,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            name,
            style: pw.TextStyle(
              fontSize: 14,
              color: PdfColor.fromHex('#1B3D3D'),
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.Text(
            role,
            style: pw.TextStyle(
              fontSize: 11,
              color: PdfColor.fromHex('#E6A050'),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildPdfMetricBox(String title, String value) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          color: PdfColor.fromHex('#1B3D3D'),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(
                fontSize: 8,
                color: PdfColors.grey300,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: 14,
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _downloadReport() async {
    _showLoadingDialog("Preparing PDF...");
    await Future.delayed(const Duration(milliseconds: 100));

    try {
      final bytes = await _generatePdfBytes();
      if (mounted) Navigator.pop(context);

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => bytes,
        name:
            'RiskRadar_Audit_${widget.hazard['report_number'] ?? widget.hazard['id'].toString().substring(0, 6)}.pdf',
      );
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error downloading PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _shareReport() async {
    _showLoadingDialog("Generating Document...");
    await Future.delayed(const Duration(milliseconds: 100));

    try {
      final bytes = await _generatePdfBytes();
      if (mounted) Navigator.pop(context);

      final fileName =
          'RiskRadar_Audit_${widget.hazard['report_number'] ?? widget.hazard['id'].toString().substring(0, 6)}.pdf';

      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(bytes, name: fileName, mimeType: 'application/pdf'),
          ],
          subject: 'Safety Report: ${widget.hazard['hazard_type']}',
          text:
              'Please find the attached Safety Compliance Audit for RiskRadar.',
        ),
      );
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sharing PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ==================== INTERACTIVE LOGIC ====================

  Future<void> _openMap(double lat, double lng) async {
    final Uri googleMapsUrl = Uri.parse(
      "https://www.google.com/maps/search/?api=1&query=$lat,$lng",
    );
    if (await canLaunchUrl(googleMapsUrl)) {
      await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Could not open map.')));
      }
    }
  }

  void _showImagePreview(String url) {
    showDialog(
      context: context,
      builder: (context) => Dialog.fullscreen(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                child: CachedNetworkImage(
                  imageUrl: url,
                  placeholder: (context, url) =>
                      const CircularProgressIndicator(
                        color: AppColors.accentGold,
                      ),
                  errorWidget: (context, url, error) => Icon(
                    Icons.error,
                    color: Theme.of(context).iconTheme.color,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 40,
              left: 20,
              child: IconButton(
                icon: Icon(
                  Icons.close,
                  color: Theme.of(context).iconTheme.color,
                  size: 30,
                ),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    R.init(context);
    if (_isLoadingResolver) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.brandTeal),
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hazard = widget.hazard;

    final String hazardType = hazard['hazard_type'] ?? 'General Hazard';
    final String description =
        hazard['description'] ?? 'No description provided.';
    final String severity = hazard['severity'] ?? 'LOW';
    final String status = hazard['status'] ?? 'Unknown';

    final double? latitude = double.tryParse(
      hazard['latitude']?.toString() ?? '',
    );
    final double? longitude = double.tryParse(
      hazard['longitude']?.toString() ?? '',
    );

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          "HAZARD DETAILS",
          style: TextStyle(
            fontSize: R.blockH * 3.5,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
        backgroundColor: AppColors.brandTeal,
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 1,
        actions: [
          IconButton(
            icon: Icon(Icons.download_outlined, color: Colors.white),
            onPressed: _downloadReport,
          ),
          IconButton(
            icon: Icon(Icons.share_outlined, color: Colors.white),
            onPressed: _shareReport,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(R.blockH * 5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- Personnel Badges ---
            Row(
              children: [
                _buildPersonnelBadge(
                  label: "REPORTED BY",
                  name: _getReporterName(),
                  imageUrl: hazard['reporter']?['profile_image_url'],
                  role: "Reporter",
                  fallbackIcon: Icons.person_search_outlined,
                  isDark: isDark,
                ),
                SizedBox(width: R.blockH * 3.2),
                _buildPersonnelBadge(
                  label: "RESOLVED BY",
                  name: _formatName(
                    _resolverData?['first_name'],
                    _resolverData?['last_name'],
                    "Unassigned",
                  ),
                  imageUrl: _resolverData?['profile_image_url'],
                  role: _resolverData?['designation'] ?? "Specialist",
                  fallbackIcon: Icons.engineering,
                  isDark: isDark,
                ),
              ],
            ),
            SizedBox(height: R.blockV * 3.75),

            // --- Summary Section ---
            Text(
              "RESOLUTION SUMMARY",
              style: TextStyle(
                fontSize: R.blockH * 6,
                fontWeight: FontWeight.w900,
                color: isDark ? Colors.white : AppColors.brandTeal,
                letterSpacing: -0.5,
              ),
            ),
            SizedBox(height: R.blockV * 0.625),
            Row(
              children: [
                _buildBadge(hazardType.toUpperCase(), AppColors.accentGold),
                SizedBox(width: R.blockH * 2.133),
                _buildBadge(status.toUpperCase(), _getStatusColor(status)),
              ],
            ),
            SizedBox(height: R.blockV * 3.125),

            // --- Metric Cards ---
            Row(
              children: [
                _buildMetricCard(
                  "TOTAL DURATION",
                  _calculateTime(),
                  Icons.timer_outlined,
                ),
                SizedBox(width: R.blockH * 3.2),
                _buildMetricCard(
                  "RISK SEVERITY",
                  severity.toUpperCase(),
                  Icons.assessment_outlined,
                ),
              ],
            ),
            SizedBox(height: R.blockV * 3.125),

            // --- Impact Score Chart ---
            _buildSectionLabel("RISK IMPACT ANALYSIS", isDark),
            _buildChartCard(severity, isDark),
            SizedBox(height: R.blockV * 3.75),

            // --- Description & Metadata Log ---
            _buildSectionLabel("DESCRIPTION & METADATA", isDark),
            _buildAuditTable(hazard, description, isDark),
            SizedBox(height: R.blockV * 2),

            if (latitude != null && longitude != null)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _openMap(latitude, longitude),
                  icon: Icon(Icons.location_on),
                  label: Text('View Location on Map'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brandTeal,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: R.blockV * 1.75),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            SizedBox(height: R.blockV * 3.75),

            // --- Image Galleries ---
            _buildSectionLabel("VISUAL VERIFICATION (CLICK TO VIEW)", isDark),
            _buildClickableGallery(
              "Initial Hazard (Before)",
              hazard['image_url'] ?? hazard['images']?.toString(),
              isDark,
            ),
            SizedBox(height: R.blockV * 1.875),
            _buildClickableGallery(
              "Resolution Proof (After)",
              hazard['resolution_image_url'],
              isDark,
            ),

            // --- Voice Notes ---
            if (hazard['voice_note_url'] != null ||
                hazard['resolution_voice_note_url'] != null) ...[
              SizedBox(height: R.blockV * 3.75),
              _buildSectionLabel("AUDIO TESTIMONY", isDark),
              if (hazard['voice_note_url'] != null)
                _buildSimpleCard(
                  "Original Voice Report",
                  _buildVoiceList(hazard['voice_note_url']),
                  isDark,
                ),
              SizedBox(height: R.blockV * 1.5),
              if (hazard['resolution_voice_note_url'] != null)
                _buildSimpleCard(
                  "Resolution Testimony",
                  _buildVoiceList(hazard['resolution_voice_note_url']),
                  isDark,
                ),
            ],

            SizedBox(height: R.blockV * 6.25),
          ],
        ),
      ),
    );
  }

  // ==================== UI BUILDERS ====================

  Widget _buildPersonnelBadge({
    required String label,
    required String name,
    required String? imageUrl,
    required String role,
    required IconData fallbackIcon,
    required bool isDark,
  }) {
    // ✅ THE FIX: Bulletproof check to ensure empty string URLs don't break the widget
    final bool hasImage = imageUrl != null && imageUrl.trim().isNotEmpty;

    return Expanded(
      child: Container(
        padding: EdgeInsets.all(R.blockH * 3),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: isDark
                ? Colors.grey.shade800
                : AppColors.brandTeal.withValues(alpha: 0.1),
          ),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: R.blockH * 2.25,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            SizedBox(height: R.blockV * 1.25),
            CircleAvatar(
              radius: 28,
              backgroundColor: isDark
                  ? Colors.grey.shade800
                  : AppColors.backgroundLight,
              // ✅ Updated to only load the image if `hasImage` is truly valid
              backgroundImage: hasImage
                  ? CachedNetworkImageProvider(imageUrl)
                  : null,
              child: !hasImage
                  ? Icon(fallbackIcon, color: AppColors.brandTeal)
                  : null,
            ),
            SizedBox(height: R.blockV * 1.25),
            Text(
              name,
              style: TextStyle(
                fontSize: R.blockH * 3.25,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : AppColors.brandTeal,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              role,
              style: TextStyle(
                fontSize: R.blockH * 2.5,
                color: AppColors.accentGold,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClickableGallery(String title, String? urlStr, bool isDark) {
    if (urlStr == null || urlStr.isEmpty) return const SizedBox.shrink();
    final urls = urlStr.split(',').where((s) => s.trim().isNotEmpty).toList();
    if (urls.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: R.blockH * 2.75,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white70 : AppColors.brandTeal,
          ),
        ),
        SizedBox(height: R.blockV * 1.25),
        SizedBox(
          height: R.blockV * 15,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: urls.length,
            itemBuilder: (ctx, i) {
              final cleanUrl = urls[i].trim();
              return GestureDetector(
                onTap: () => _showImagePreview(cleanUrl),
                child: Container(
                  width: R.blockH * 40,
                  margin: EdgeInsets.only(right: R.blockH * 3),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark ? Colors.grey.shade700 : Colors.white,
                      width: R.blockH * 0.8,
                    ),
                    image: DecorationImage(
                      image: CachedNetworkImageProvider(cleanUrl),
                      fit: BoxFit.cover,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildChartCard(String severity, bool isDark) {
    final double risk = _getSeverityValue(severity);
    return Container(
      padding: EdgeInsets.all(R.blockH * 5),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: isDark ? Colors.grey.shade800 : Colors.transparent,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            height: R.blockV * 11.25,
            width: R.blockH * 24,
            child: PieChart(
              PieChartData(
                sectionsSpace: 0,
                centerSpaceRadius: 25,
                sections: [
                  PieChartSectionData(
                    value: risk,
                    color: _getSeverityColor(severity),
                    radius: 12,
                    showTitle: false,
                  ),
                  PieChartSectionData(
                    value: 1 - risk,
                    color: isDark
                        ? Colors.grey.shade800
                        : AppColors.backgroundLight,
                    radius: 12,
                    showTitle: false,
                  ),
                ],
              ),
            ),
          ),
          SizedBox(width: R.blockH * 6.667),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "IMPACT SCORE",
                  style: TextStyle(
                    fontSize: R.blockH * 2.5,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
                Text(
                  "${(risk * 100).toInt()}%",
                  style: TextStyle(
                    fontSize: R.blockH * 7,
                    fontWeight: FontWeight.w900,
                    color: _getSeverityColor(severity),
                  ),
                ),
                Text(
                  "Risk level analyzed at original report.",
                  style: TextStyle(
                    fontSize: R.blockH * 2.75,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuditTable(
    Map<String, dynamic> hazard,
    String description,
    bool isDark,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: isDark ? Colors.grey.shade800 : Colors.transparent,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: Table(
          border: TableBorder.all(
            color: isDark ? Colors.grey.shade800 : AppColors.backgroundLight,
            width: 1,
          ),
          children: [
            _buildTableRow(
              "DATA FIELD",
              "ENTRY LOG",
              isHeader: true,
              isDark: isDark,
            ),
            _buildTableRow("Description", description, isDark: isDark),
            _buildTableRow(
              "Location",
              "${hazard['latitude'] ?? 'N/A'}, ${hazard['longitude'] ?? 'N/A'}",
              isDark: isDark,
            ),
            _buildTableRow(
              "Reported At",
              _formatDate(hazard['created_at']),
              isDark: isDark,
            ),
            _buildTableRow(
              "Assigned At",
              _formatDate(hazard['assigned_at']),
              isDark: isDark,
            ),
            _buildTableRow(
              "Resolved At",
              _formatDate(hazard['resolved_at']),
              isDark: isDark,
            ),
            _buildTableRow(
              "Resolution Notes",
              hazard['resolution_notes'] ?? "N/A",
              isDark: isDark,
            ),
          ],
        ),
      ),
    );
  }

  // ==================== HELPERS ====================

  Widget _buildMetricCard(String l, String v, IconData i) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.all(R.blockH * 4),
        decoration: BoxDecoration(
          color: AppColors.brandTeal,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(i, size: 14, color: AppColors.accentGold),
            SizedBox(height: R.blockV * 1.25),
            Text(
              l,
              style: TextStyle(
                fontSize: R.blockH * 2.25,
                fontWeight: FontWeight.bold,
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ),
            Text(
              v,
              style: TextStyle(
                fontSize: R.blockH * 4,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBadge(String t, Color c) => Container(
    padding: EdgeInsets.symmetric(
      horizontal: R.blockH * 2.5,
      vertical: R.blockV * 0.5,
    ),
    decoration: BoxDecoration(
      color: c.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: c.withValues(alpha: 0.5)),
    ),
    child: Text(
      t,
      style: TextStyle(
        color: c,
        fontSize: R.blockH * 2.5,
        fontWeight: FontWeight.bold,
      ),
    ),
  );

  Widget _buildSectionLabel(String t, bool isDark) => Padding(
    padding: EdgeInsets.only(bottom: R.blockV * 1.5, left: R.blockH * 1),
    child: Text(
      t,
      style: TextStyle(
        fontSize: R.blockH * 2.5,
        fontWeight: FontWeight.bold,
        color: isDark
            ? Colors.white54
            : AppColors.brandTeal.withValues(alpha: 0.4),
        letterSpacing: 1.5,
      ),
    ),
  );

  Widget _buildSimpleCard(String label, List<Widget> children, bool isDark) =>
      Container(
        width: double.infinity,
        padding: EdgeInsets.all(R.blockH * 4),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: isDark ? Colors.grey.shade800 : Colors.transparent,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: R.blockH * 2.5,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            ...children,
          ],
        ),
      );

  List<Widget> _buildVoiceList(String? url) => (url ?? "")
      .split(',')
      .where((u) => u.trim().isNotEmpty)
      .map(
        (u) => Padding(
          padding: EdgeInsets.only(top: R.blockV * 1),
          child: VoiceNotePlayer(url: u.trim()),
        ),
      )
      .toList();

  TableRow _buildTableRow(
    String l,
    String v, {
    bool isHeader = false,
    required bool isDark,
  }) {
    return TableRow(
      decoration: BoxDecoration(
        color: isHeader ? AppColors.brandTeal : Colors.transparent,
      ),
      children: [
        Padding(
          padding: EdgeInsets.all(R.blockH * 3),
          child: Text(
            l,
            style: TextStyle(
              fontSize: R.blockH * 2.75,
              color: isHeader ? Colors.white : Colors.grey.shade600,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.all(R.blockH * 3),
          child: Text(
            v,
            style: TextStyle(
              fontSize: R.blockH * 2.75,
              color: isHeader
                  ? Colors.white
                  : (isDark ? Colors.white : AppColors.brandTeal),
              fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ],
    );
  }

  String _calculateTime() {
    if (widget.hazard['created_at'] == null ||
        widget.hazard['resolved_at'] == null)
      return "N/A";
    try {
      String startRaw = widget.hazard['created_at']
          .toString()
          .split('+')[0]
          .split('Z')[0]
          .replaceFirst(' ', 'T');
      String endRaw = widget.hazard['resolved_at']
          .toString()
          .split('+')[0]
          .split('Z')[0]
          .replaceFirst(' ', 'T');

      final start = DateTime.parse("${startRaw}Z");
      final end = DateTime.parse("${endRaw}Z");

      final diff = end.difference(start);
      return diff.inHours > 0
          ? "${diff.inHours}h ${diff.inMinutes % 60}m"
          : "${diff.inMinutes}m";
    } catch (e) {
      return "N/A";
    }
  }

  String _formatDate(String? d) {
    if (d == null) return "N/A";
    try {
      String rawDate = d.split('+')[0].split('Z')[0].replaceFirst(' ', 'T');
      DateTime utcDate = DateTime.parse("${rawDate}Z");
      DateTime localDate = utcDate.toLocal();

      return DateFormat('dd MMM yyyy, hh:mm a').format(localDate);
    } catch (e) {
      return "Invalid Date";
    }
  }

  Color _getStatusColor(String? s) {
    switch (s?.toLowerCase()) {
      case 'resolved':
        return _successGreen;
      case 'in_progress':
      case 'in progress':
        return Colors.orange;
      default:
        return Colors.red;
    }
  }

  Color _getSeverityColor(String? s) => s?.toLowerCase() == 'high'
      ? Colors.red
      : (s?.toLowerCase() == 'moderate' ? Colors.orange : _successGreen);
  double _getSeverityValue(String? s) => s?.toLowerCase() == 'high'
      ? 0.85
      : (s?.toLowerCase() == 'moderate' ? 0.5 : 0.2);
}
