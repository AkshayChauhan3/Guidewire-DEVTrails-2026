import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'api_service.dart';
import 'ui_kit.dart';

class SessionHistoryScreen extends StatefulWidget {
  final String phone;
  final String? date;

  const SessionHistoryScreen({super.key, required this.phone, this.date});

  @override
  State<SessionHistoryScreen> createState() => _SessionHistoryScreenState();
}

class _SessionHistoryScreenState extends State<SessionHistoryScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  // Upload State
  bool isUploading = false;
  List<XFile> selectedImages = [];
  
  // History State
  bool isFetching = true;
  List<dynamic> historyList = [];
  String? fetchError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchHistory();
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade800 : AppUi.surface,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _fetchHistory() async {
    setState(() {
      isFetching = true;
      fetchError = null;
    });

    final result = await ApiService.getSessionHistory(phone: widget.phone);
    if (!mounted) return;

    if (result["success"] == true) {
      setState(() {
        historyList = (result["data"] as List?) ?? [];
        isFetching = false;
      });
    } else {
      setState(() {
        fetchError = result["message"] ?? "Failed to load history";
        isFetching = false;
      });
    }
  }

  Future<void> _pickHistoryImages() async {
    try {
      final picker = ImagePicker();
      final pickedFiles = await picker.pickMultiImage(
        imageQuality: 85,
        maxHeight: 1920,
        maxWidth: 1080,
      );

      if (pickedFiles.isEmpty) {
        return;
      }

      setState(() {
        selectedImages.addAll(pickedFiles);
      });
    } catch (e) {
      _showSnack("Error picking images: $e", isError: true);
    }
  }

  Future<void> _uploadHistory() async {
    if (selectedImages.isEmpty) {
      _showSnack("Select at least one delivery history screenshot");
      return;
    }

    setState(() => isUploading = true);

    final now = DateTime.now();
    final historyDate =
        widget.date ??
        "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";

    // Send images to backend for OCR
    final result = await ApiService.submitSessionHistory(
      phone: widget.phone,
      date: historyDate,
      historyFiles: selectedImages,
    );

    if (!mounted) return;
    setState(() => isUploading = false);

    if (result["success"] == true) {
      final totalAmount = result["total_earned_amount"] ?? "0.00";
      final extractedAmounts = result["extracted_amounts"];

      _showSnack("History uploaded successfully ✅");
      
      setState(() {
        selectedImages = [];
      });
      
      _fetchHistory(); // Refresh history
      _tabController.animateTo(0); // Switch to history tab

      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: AppUi.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            "Earnings Summary",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.shade800),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Total Earned",
                            style: TextStyle(color: Colors.white60, fontSize: 13),
                          ),
                          Text(
                            "₹ $totalAmount",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                "Amounts Found (${extractedAmounts is List ? extractedAmounts.length : 0}):",
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 8),
              if (extractedAmounts is List && extractedAmounts.isNotEmpty)
                Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: SingleChildScrollView(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: extractedAmounts
                          .map(
                            (amount) => Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                "₹ $amount",
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2EA043),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text("Done"),
            ),
          ],
        ),
      );
    } else {
      _showSnack(result["message"] ?? "Failed to upload history", isError: true);
    }
  }

  void _clearSelection() {
    setState(() {
      selectedImages = [];
    });
  }
  
  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      final months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
      return "${months[date.month - 1]} ${date.day}, ${date.year}";
    } catch (_) {
      return dateStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppUi.background,
      appBar: AppBar(
        backgroundColor: AppUi.surface,
        elevation: 0,
        title: const Text(
          "Delivery History",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppUi.accent,
          labelColor: AppUi.accent,
          unselectedLabelColor: Colors.white54,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          tabs: const [
            Tab(text: "Past Sessions"),
            Tab(text: "New Upload"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildHistoryTab(),
          _buildUploadTab(),
        ],
      ),
    );
  }

  Widget _buildHistoryTab() {
    if (isFetching) {
      return const Center(
        child: CircularProgressIndicator(color: AppUi.accent),
      );
    }

    if (fetchError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
            const SizedBox(height: 16),
            Text(
              fetchError!,
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _fetchHistory,
              icon: const Icon(Icons.refresh, color: AppUi.accent),
              label: const Text("Retry", style: TextStyle(color: AppUi.accent)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppUi.accent),
              ),
            ),
          ],
        ),
      );
    }

    if (historyList.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppUi.surface,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.history_toggle_off,
                color: Colors.white24,
                size: 64,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              "No history found",
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Upload screenshots to see your earnings here",
              style: TextStyle(color: Colors.white54, fontSize: 14),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => _tabController.animateTo(1),
              icon: const Icon(Icons.cloud_upload),
              label: const Text("Go to Upload"),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF238636),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchHistory,
      color: AppUi.accent,
      backgroundColor: AppUi.surface,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: historyList.length,
        itemBuilder: (context, index) {
          final item = historyList[index];
          final date = _formatDate(item["date"] ?? "");
          final amount = item["total_earned_amount"] ?? "0.00";
          final extracted = (item["extracted_amounts"] as List?) ?? [];
          final hours = item["total_working_hours"] ?? "0.00";
          final shifts = item["total_shifts"] ?? 0;
          
          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: AppUi.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.03),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today, color: Colors.white54, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        date,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF238636).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF238636).withValues(alpha: 0.5)),
                        ),
                        child: Text(
                          "₹ $amount",
                          style: const TextStyle(
                            color: Color(0xFF3FB950),
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Content
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildStatItem(
                          icon: Icons.timer_outlined,
                          title: "Hours",
                          value: hours,
                        ),
                      ),
                      Container(width: 1, height: 40, color: Colors.white10),
                      Expanded(
                        child: _buildStatItem(
                          icon: Icons.work_outline,
                          title: "Shifts",
                          value: shifts.toString(),
                        ),
                      ),
                      Container(width: 1, height: 40, color: Colors.white10),
                      Expanded(
                        child: _buildStatItem(
                          icon: Icons.receipt_long_outlined,
                          title: "Extracts",
                          value: "${extracted.length}",
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatItem({required IconData icon, required String title, required String value}) {
    return Column(
      children: [
        Icon(icon, color: Colors.white38, size: 20),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildUploadTab() {
    return Stack(
      children: [
        SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Instructions
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppUi.accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppUi.accent.withValues(alpha: 0.16)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline, color: AppUi.accent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            "Upload Screenshots",
                            style: TextStyle(
                              color: AppUi.accent,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            "Upload your delivery app earnings history (Swiggy, Zomato, Uber Eats). The backend automatically extracts amounts.",
                            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Selected Images Preview
              if (selectedImages.isNotEmpty) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Selected Files (${selectedImages.length})",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _clearSelection,
                      icon: const Icon(Icons.clear_all, size: 18),
                      label: const Text("Clear all"),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                      ),
                    )
                  ],
                ),
                const SizedBox(height: 12),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 2.5,
                  ),
                  itemCount: selectedImages.length,
                  itemBuilder: (_, index) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: AppUi.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.image, color: Colors.white38, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            selectedImages[index].name,
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        InkWell(
                          onTap: () => setState(() => selectedImages.removeAt(index)),
                          child: const Icon(Icons.close, color: Colors.white54, size: 18),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // Pick Button
              InkWell(
                onTap: _pickHistoryImages,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.02),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white10,
                      style: BorderStyle.solid,
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.add_photo_alternate_outlined,
                        color: selectedImages.isEmpty ? Colors.white38 : AppUi.accent,
                        size: 48,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        selectedImages.isEmpty ? "Tap to select images" : "Add more images",
                        style: TextStyle(
                          color: selectedImages.isEmpty ? Colors.white54 : AppUi.accent,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),
              
              // Best Practices
              const Text(
                "TIPS FOR BEST RESULTS",
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 12),
              _buildTipItem(Icons.crop_free, "Take full-page screenshots without cropping"),
              _buildTipItem(Icons.currency_rupee, "Ensure ₹ symbol is clearly visible"),
              _buildTipItem(Icons.brightness_6, "Use clear, well-lit screenshots"),
              
              const SizedBox(height: 100), // Space for bottom button
            ],
          ),
        ),
        
        // Bottom Upload Button
        if (selectedImages.isNotEmpty)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppUi.surface,
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 10, offset: const Offset(0, -5))
                ],
              ),
              child: FilledButton(
                onPressed: isUploading ? null : _uploadHistory,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF238636),
                  disabledBackgroundColor: const Color(0xFF238636).withValues(alpha: 0.5),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: isUploading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Text(
                        "Upload & Extract",
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ),
      ],
    );
  }
  
  Widget _buildTipItem(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: Colors.white38, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white60, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
