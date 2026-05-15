// lib/hse_workers/screens/resolved_hazard_report_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'package:riskradar/shared/widgets/voice_note_player.dart';
import 'package:riskradar/shared/theme/app_colors.dart';

class ResolvedHazardReportScreen extends StatefulWidget {
  final String hazardId;

  const ResolvedHazardReportScreen({super.key, required this.hazardId});

  @override
  State<ResolvedHazardReportScreen> createState() => _ResolvedHazardReportScreenState();
}

class _ResolvedHazardReportScreenState extends State<ResolvedHazardReportScreen> {
  final SupabaseClient supabase = Supabase.instance.client;
  Map<String, dynamic>? hazardData;
  bool _isLoading = true;

  static const Color _successGreen = Color(0xFF10B981);

  @override
  void initState() {
    super.initState();
    _fetchHazardDetails();
  }

  Future<void> _fetchHazardDetails() async {
    try {
      final response = await supabase
          .from('resolved_hazards')
          .select('''
            *,
            reporter:worker_id (first_name, last_name, profile_image_url, work_type),
            resolver:assigned_to (first_name, last_name, profile_image_url, designation),
            site:current_site_id (name)
          ''')
          .eq('id', widget.hazardId)
          .single();

      if (mounted) {
        setState(() {
          hazardData = response;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("❌ Database Error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _getDisplayId() {
    if (hazardData!['report_number'] != null) {
      return "REPORT #${hazardData!['report_number']}";
    }
    return "ID: ${hazardData!['id'].toString().substring(0, 8).toUpperCase()}";
  }

  String _formatName(Map<String, dynamic>? user) {
    if (user == null) return "Unassigned";

    final fName = user['first_name']?.toString().trim() ?? "";
    final lName = user['last_name']?.toString().trim() ?? "";
    final fullName = "$fName $lName".trim();

    if (fullName.isEmpty) return "Unassigned";

    return fullName.split(' ').map((word) {
      if (word.isEmpty) return '';
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }

  void _showLoadingDialog(String title, bool isDark) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: Theme.of(context).cardColor,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 24.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 30,
                height: 30,
                child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.brandTeal),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? Colors.white : AppColors.brandTeal)),
                    const SizedBox(height: 4),
                    Text("Please keep the app open", style: TextStyle(fontSize: 13, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600)),
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

    final reportedDate = _formatDate(hazardData!['created_at']);
    final startedDate = _formatDate(hazardData!['started_at']);
    final resolvedDate = _formatDate(hazardData!['resolved_at']);
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

    try {
      if (hazardData!['image_url'] != null && hazardData!['image_url'].toString().isNotEmpty) {
        final urls = hazardData!['image_url'].toString().split(',');
        for (String url in urls) {
          if (url.trim().isNotEmpty) {
            beforeImages.add(await networkImage(url.trim()));
          }
        }
      }
    } catch (e) { debugPrint("Could not load before images for PDF"); }

    try {
      if (hazardData!['resolution_image_url'] != null && hazardData!['resolution_image_url'].toString().isNotEmpty) {
        final urls = hazardData!['resolution_image_url'].toString().split(',');
        for (String url in urls) {
          if (url.trim().isNotEmpty) {
            afterImages.add(await networkImage(url.trim()));
          }
        }
      }
    } catch (e) { debugPrint("Could not load after images for PDF"); }

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
                pw.Expanded(child: _buildPdfPersonnelBox("REPORTED BY", hazardData!['reporter'], hazardData!['reporter']?['work_type'] ?? "Worker")),
                pw.SizedBox(width: 20),
                pw.Expanded(child: _buildPdfPersonnelBox("RESOLVED BY", hazardData!['resolver'], hazardData!['resolver']?['designation'] ?? "Specialist")),
              ],
            ),
            pw.SizedBox(height: 20),

            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                _buildPdfMetricBox("DURATION", _calculateTime()),
                pw.SizedBox(width: 10),
                _buildPdfMetricBox("SEVERITY", hazardData!['severity'] ?? "LOW"),
                pw.SizedBox(width: 10),
                _buildPdfMetricBox("IMPACT SCORE", "${(_getSeverityValue(hazardData!['severity']) * 100).toInt()}%"),
              ],
            ),
            pw.SizedBox(height: 30),

            pw.Text("METADATA LOG", style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#1B3D3D'))),
            pw.SizedBox(height: 10),
            pw.TableHelper.fromTextArray(
              headers: ['DATA FIELD', 'ENTRY LOG'],
              data: [
                ['Hazard Type', hazardData!['hazard_type'] ?? "N/A"],
                ['Site Name', hazardData!['site']?['name'] ?? "Unknown Site"],
                ['Location', '${hazardData!['latitude']}, ${hazardData!['longitude']}'],
                ['Reported At', reportedDate],
                ['Started At', startedDate],
                ['Resolved At', resolvedDate],
                ['Resolution Notes', hazardData!['resolution_notes'] ?? "N/A"],
              ],
              headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold),
              headerDecoration: pw.BoxDecoration(color: PdfColor.fromHex('#1B3D3D')),
              cellPadding: const pw.EdgeInsets.all(10),
              border: pw.TableBorder.all(color: PdfColors.grey300),
            ),
          ];
        },
      ),
    );

    if (beforeImages.isNotEmpty) {
      pdf.addPage(
          pw.MultiPage(
              pageFormat: PdfPageFormat.a4,
              margin: const pw.EdgeInsets.all(32),
              header: (context) => _buildPdfHeader(displayId, logoImage),
              build: (pw.Context context) {
                return [
                  pw.Text("VISUAL VERIFICATION: INITIAL HAZARD (BEFORE)", style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#1B3D3D'))),
                  pw.SizedBox(height: 10),
                  pw.Wrap(
                    spacing: 15,
                    runSpacing: 15,
                    children: beforeImages.map((img) => pw.Container(
                      width: 250,
                      height: 200,
                      decoration: pw.BoxDecoration(
                        image: pw.DecorationImage(image: img, fit: pw.BoxFit.cover),
                        border: pw.Border.all(color: PdfColors.grey300),
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                      ),
                    )).toList(),
                  ),
                ];
              }
          )
      );
    }

    if (afterImages.isNotEmpty) {
      pdf.addPage(
          pw.MultiPage(
              pageFormat: PdfPageFormat.a4,
              margin: const pw.EdgeInsets.all(32),
              header: (context) => _buildPdfHeader(displayId, logoImage),
              build: (pw.Context context) {
                return [
                  pw.Text("VISUAL VERIFICATION: RESOLUTION PROOF (AFTER)", style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#1B3D3D'))),
                  pw.SizedBox(height: 10),
                  pw.Wrap(
                    spacing: 15,
                    runSpacing: 15,
                    children: afterImages.map((img) => pw.Container(
                      width: 250,
                      height: 200,
                      decoration: pw.BoxDecoration(
                        image: pw.DecorationImage(image: img, fit: pw.BoxFit.cover),
                        border: pw.Border.all(color: PdfColors.grey300),
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                      ),
                    )).toList(),
                  ),
                ];
              }
          )
      );
    }

    return pdf.save();
  }

  Future<void> _downloadReport(bool isDark) async {
    _showLoadingDialog("Preparing PDF...", isDark);

    // Yield to the event loop so the dialog renders instantly BEFORE the heavy PDF generation
    await Future.delayed(const Duration(milliseconds: 100));

    try {
      final bytes = await _generatePdfBytes();
      if (mounted) Navigator.pop(context);

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => bytes,
        name: 'RiskRadar_Audit_${hazardData!['report_number'] ?? hazardData!['id'].toString().substring(0, 6)}.pdf',
      );
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error downloading PDF: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _shareReport(bool isDark) async {
    _showLoadingDialog("Generating Document...", isDark);

    // Yield to the event loop so the dialog renders instantly BEFORE the heavy PDF generation
    await Future.delayed(const Duration(milliseconds: 100));

    try {
      final bytes = await _generatePdfBytes();
      if (mounted) Navigator.pop(context);

      final fileName = 'RiskRadar_Audit_${hazardData!['report_number'] ?? hazardData!['id'].toString().substring(0, 6)}.pdf';

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(bytes, name: fileName, mimeType: 'application/pdf')],
          subject: 'Safety Report: ${hazardData!['hazard_type']}',
          text: 'Please find the attached Safety Compliance Audit for ${hazardData!['site']?['name'] ?? 'the site'}.',
        ),
      );

    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error sharing PDF: $e'), backgroundColor: Colors.red));
      }
    }
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
                  pw.Text("SAFETY COMPLIANCE AUDIT", style: pw.TextStyle(fontSize: 24, color: PdfColor.fromHex('#1B3D3D'), fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 4),
                  pw.Text(displayId, style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
                ],
              ),
            ),
            if (logoImage != null)
              pw.Container(
                height: 80,
                width: 140,
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

  pw.Widget _buildPdfPersonnelBox(String title, Map<String, dynamic>? user, String role) {
    final name = _formatName(user);
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(title, style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.Text(name, style: pw.TextStyle(fontSize: 14, color: PdfColor.fromHex('#1B3D3D'), fontWeight: pw.FontWeight.bold)),
          pw.Text(role, style: pw.TextStyle(fontSize: 11, color: PdfColor.fromHex('#E6A050'))),
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
            pw.Text(title, style: pw.TextStyle(fontSize: 8, color: PdfColors.grey300, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text(value, style: pw.TextStyle(fontSize: 14, color: PdfColors.white, fontWeight: pw.FontWeight.bold)),
          ],
        ),
      ),
    );
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
                  placeholder: (context, url) => const CircularProgressIndicator(color: AppColors.accentGold),
                  errorWidget: (context, url, error) => Icon(Icons.error, color: Theme.of(context).iconTheme.color),
                ),
              ),
            ),
            Positioned(
              top: 40, left: 20,
              child: IconButton(
                icon: Icon(Icons.close, color: Theme.of(context).iconTheme.color, size: 30),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isLoading) return Scaffold(backgroundColor: Theme.of(context).scaffoldBackgroundColor, body: const Center(child: CircularProgressIndicator(color: AppColors.brandTeal)));
    if (hazardData == null) return Scaffold(backgroundColor: Theme.of(context).scaffoldBackgroundColor, body: const Center(child: Text("Report not found.")));

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("HAZARD DETAILS", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 2)),
        backgroundColor: AppColors.brandTeal,
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 1,
        actions: [
          IconButton(icon: const Icon(Icons.download_outlined, color: Colors.white), onPressed: () => _downloadReport(isDark)),
          IconButton(icon: const Icon(Icons.share_outlined, color: Colors.white), onPressed: () => _shareReport(isDark)),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _buildPersonnelBadge(
                  label: "REPORTED BY",
                  userData: hazardData!['reporter'],
                  role: hazardData!['reporter']?['work_type'] ?? "Worker",
                  fallbackIcon: Icons.person_search_outlined,
                  isDark: isDark,
                ),
                const SizedBox(width: 12),
                _buildPersonnelBadge(
                  label: "RESOLVED BY",
                  userData: hazardData!['resolver'],
                  role: hazardData!['resolver']?['designation'] ?? "Specialist",
                  fallbackIcon: Icons.engineering,
                  isDark: isDark,
                ),
              ],
            ),
            const SizedBox(height: 30),

            Text("RESOLUTION SUMMARY",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: isDark ? Colors.white : AppColors.brandTeal, letterSpacing: -0.5)),
            const SizedBox(height: 5),
            Row(
              children: [
                _buildBadge(_getDisplayId(), AppColors.brandTeal.withValues(alpha: 0.6)),
                const SizedBox(width: 8),
                _buildBadge("VERIFIED RESOLUTION", _successGreen),
              ],
            ),
            const SizedBox(height: 25),

            Row(
              children: [
                _buildMetricCard("TOTAL DURATION", _calculateTime(), Icons.timer_outlined),
                const SizedBox(width: 12),
                _buildMetricCard("RISK SEVERITY", hazardData!['severity'] ?? "LOW", Icons.assessment_outlined),
              ],
            ),
            const SizedBox(height: 25),

            _buildSectionLabel("RISK IMPACT ANALYSIS", isDark),
            _buildChartCard(isDark),

            const SizedBox(height: 30),

            _buildSectionLabel("METADATA LOG", isDark),
            _buildAuditTable(isDark),

            const SizedBox(height: 30),

            _buildSectionLabel("VISUAL VERIFICATION (CLICK TO VIEW)", isDark),
            _buildClickableGallery("Initial Hazard (Before)", hazardData!['image_url'], isDark),
            const SizedBox(height: 15),
            _buildClickableGallery("Resolution Proof (After)", hazardData!['resolution_image_url'], isDark),

            if (hazardData!['voice_note_url'] != null || hazardData!['resolution_voice_note_url'] != null) ...[
              const SizedBox(height: 30),
              _buildSectionLabel("AUDIO TESTIMONY", isDark),
              if (hazardData!['voice_note_url'] != null)
                _buildSimpleCard("Original Voice Report", _buildVoiceList(hazardData!['voice_note_url']), isDark),
              const SizedBox(height: 12),
              if (hazardData!['resolution_voice_note_url'] != null)
                _buildSimpleCard("Resolution Testimony", _buildVoiceList(hazardData!['resolution_voice_note_url']), isDark),
            ],

            const SizedBox(height: 50),
          ],
        ),
      ),
    );
  }

  // ==================== UI BUILDERS ====================

  Widget _buildPersonnelBadge({required String label, required Map<String, dynamic>? userData, required String role, required IconData fallbackIcon, required bool isDark}) {
    final name = _formatName(userData);
    final String? imageUrl = userData?['profile_image_url'];
    final bool hasImage = imageUrl != null && imageUrl.trim().isNotEmpty;

    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: isDark ? Colors.grey.shade800 : AppColors.brandTeal.withValues(alpha: 0.1)),
        ),
        child: Column(
          children: [
            Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 10),
            CircleAvatar(
              radius: 28, backgroundColor: isDark ? Colors.grey.shade800 : AppColors.backgroundLight,
              backgroundImage: hasImage ? CachedNetworkImageProvider(imageUrl) : null,
              child: !hasImage ? Icon(fallbackIcon, color: AppColors.brandTeal) : null,
            ),
            const SizedBox(height: 10),
            Text(name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isDark ? Colors.white : AppColors.brandTeal), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(role, style: const TextStyle(fontSize: 10, color: AppColors.accentGold, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildClickableGallery(String title, String? urlStr, bool isDark) {
    if (urlStr == null) return const SizedBox.shrink();
    final urls = urlStr.split(',').where((s) => s.trim().isNotEmpty).toList();
    if (urls.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isDark ? Colors.white70 : AppColors.brandTeal)),
        const SizedBox(height: 10),
        SizedBox(
          height: 120,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: urls.length,
            itemBuilder: (ctx, i) {
              final cleanUrl = urls[i].trim();
              return GestureDetector(
                onTap: () => _showImagePreview(cleanUrl),
                child: Container(
                  width: 150, margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isDark ? Colors.grey.shade700 : Colors.white, width: 3),
                    image: DecorationImage(image: CachedNetworkImageProvider(cleanUrl), fit: BoxFit.cover),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4)],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildChartCard(bool isDark) {
    final double risk = _getSeverityValue(hazardData!['severity']);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(15), border: Border.all(color: isDark ? Colors.grey.shade800 : Colors.transparent)),
      child: Row(
        children: [
          SizedBox(
            height: 90, width: 90,
            child: PieChart(PieChartData(sectionsSpace: 0, centerSpaceRadius: 25, sections: [
              PieChartSectionData(value: risk, color: _getSeverityColor(hazardData!['severity']), radius: 12, showTitle: false),
              PieChartSectionData(value: 1 - risk, color: isDark ? Colors.grey.shade800 : AppColors.backgroundLight, radius: 12, showTitle: false),
            ])),
          ),
          const SizedBox(width: 25),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("IMPACT SCORE", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                Text("${(risk * 100).toInt()}%", style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: _getSeverityColor(hazardData!['severity']))),
                const Text("Risk level analyzed at original report.", style: TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildAuditTable(bool isDark) {
    return Container(
      decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(15), border: Border.all(color: isDark ? Colors.grey.shade800 : Colors.transparent)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: Table(
          border: TableBorder.all(color: isDark ? Colors.grey.shade800 : AppColors.backgroundLight, width: 1),
          children: [
            _buildTableRow("DATA FIELD", "ENTRY LOG", isDark, isHeader: true),
            _buildTableRow("Hazard Type", hazardData!['hazard_type'] ?? "N/A", isDark),
            _buildTableRow("Site Name", hazardData!['site']?['name'] ?? "Unknown Site", isDark),
            _buildTableRow("Location", "${hazardData!['latitude']}, ${hazardData!['longitude']}", isDark),
            _buildTableRow("Reported At", _formatDate(hazardData!['created_at']), isDark),
            _buildTableRow("Started At", _formatDate(hazardData!['started_at']), isDark),
            _buildTableRow("Resolved At", _formatDate(hazardData!['resolved_at']), isDark),
            _buildTableRow("Resolution Notes", hazardData!['resolution_notes'] ?? "N/A", isDark),
          ],
        ),
      ),
    );
  }

  // ==================== HELPERS ====================

  Widget _buildMetricCard(String l, String v, IconData i) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.brandTeal, borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(i, size: 14, color: AppColors.accentGold),
            const SizedBox(height: 10),
            Text(l, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white.withValues(alpha: 0.6))),
            Text(v, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
          ],
        ),
      ),
    );
  }

  Widget _buildBadge(String t, Color c) => Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: c.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20), border: Border.all(color: c.withValues(alpha: 0.5))), child: Text(t, style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.bold)));

  Widget _buildSectionLabel(String t, bool isDark) => Padding(padding: const EdgeInsets.only(bottom: 12, left: 4), child: Text(t, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isDark ? Colors.white54 : AppColors.brandTeal.withValues(alpha: 0.4), letterSpacing: 1.5)));

  Widget _buildSimpleCard(String label, List<Widget> children, bool isDark) => Container(width: double.infinity, padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(15), border: Border.all(color: isDark ? Colors.grey.shade800 : Colors.transparent)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)), ...children]));

  List<Widget> _buildVoiceList(String? url) => (url ?? "").split(',').where((u) => u.trim().isNotEmpty).map((u) => Padding(padding: const EdgeInsets.only(top: 8), child: VoiceNotePlayer(url: u.trim()))).toList();

  TableRow _buildTableRow(String l, String v, bool isDark, {bool isHeader = false}) {
    return TableRow(
        decoration: BoxDecoration(color: isHeader ? AppColors.brandTeal : Colors.transparent),
        children: [
          Padding(padding: const EdgeInsets.all(12), child: Text(l, style: TextStyle(fontSize: 11, color: isHeader ? Colors.white : Colors.grey.shade600, fontWeight: FontWeight.bold))),
          Padding(padding: const EdgeInsets.all(12), child: Text(v, style: TextStyle(fontSize: 11, color: isHeader ? Colors.white : (isDark ? Colors.white : AppColors.brandTeal), fontWeight: isHeader ? FontWeight.bold : FontWeight.normal)))
        ]
    );
  }

  String _calculateTime() {
    if (hazardData!['started_at'] == null || hazardData!['resolved_at'] == null) return "N/A";
    try {
      String startRaw = hazardData!['started_at'].toString().split('+')[0].split('Z')[0].replaceFirst(' ', 'T');
      String endRaw = hazardData!['resolved_at'].toString().split('+')[0].split('Z')[0].replaceFirst(' ', 'T');

      final start = DateTime.parse("${startRaw}Z");
      final end = DateTime.parse("${endRaw}Z");

      final diff = end.difference(start);
      return diff.inHours > 0 ? "${diff.inHours}h ${diff.inMinutes % 60}m" : "${diff.inMinutes}m";
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
      debugPrint("Date Format Error: $e");
      return "Invalid Date";
    }
  }

  Color _getSeverityColor(String? s) => s?.toLowerCase() == 'high' ? Colors.red : (s?.toLowerCase() == 'moderate' ? Colors.orange : _successGreen);
  double _getSeverityValue(String? s) => s?.toLowerCase() == 'high' ? 0.85 : (s?.toLowerCase() == 'moderate' ? 0.5 : 0.2);
}
