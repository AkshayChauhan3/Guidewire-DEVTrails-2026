// ============================================================
// session_history_screen.dart
// ============================================================
// Screen for uploading delivery history screenshots after
// completing a work session.
//
// Flow:
// 1. User ends session
// 2. Shown this screen to upload delivery history
// 3. User selects delivery app screenshots (e.g., Swiggy, Zomato)
// 4. Backend extracts amounts and calculates total earnings
// 5. Results shown to user
// ============================================================

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'api_service.dart';

class SessionHistoryScreen extends StatefulWidget {
  final String phone;
  final String? date;

  const SessionHistoryScreen({super.key, required this.phone, this.date});

  @override
  State<SessionHistoryScreen> createState() => _SessionHistoryScreenState();
}

class _SessionHistoryScreenState extends State<SessionHistoryScreen> {
  bool isLoading = false;
  List<XFile> selectedImages = [];

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF262D33),
        duration: const Duration(seconds: 2),
      ),
    );
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
        _showSnack("No images selected");
        return;
      }

      setState(() {
        selectedImages = pickedFiles;
      });
    } catch (e) {
      _showSnack("Error picking images: $e");
    }
  }

  Future<void> _uploadHistory() async {
    if (selectedImages.isEmpty) {
      _showSnack("Select at least one delivery history screenshot");
      return;
    }

    setState(() => isLoading = true);

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
    setState(() => isLoading = false);

    if (result["success"] == true) {
      final totalAmount = result["total_earned_amount"] ?? "0.00";
      final extractedAmounts = result["extracted_amounts"];

      _showSnack("History uploaded successfully ✅");

      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF161B22),
          title: const Text(
            "Earnings Summary",
            style: TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Total Earned: Rs $totalAmount",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: extractedAmounts
                          .map(
                            (amount) => Text(
                              "• Rs $amount",
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 12,
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
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context); // Close history screen
              },
              child: const Text("Done"),
            ),
          ],
        ),
      );
    } else {
      _showSnack(result["message"] ?? "Failed to upload history");
    }
  }

  void _clearSelection() {
    setState(() {
      selectedImages = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        elevation: 0,
        title: const Text(
          "Upload Delivery History",
          style: TextStyle(color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(Color(0xFF4CAF50)),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Instructions
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: const Text(
                      "📸 Upload screenshots of your delivery app earnings history "
                      "(Swiggy, Zomato, Uber Eats, etc.). "
                      "The backend will automatically extract earnings amounts.",
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Selected Images Preview
                  if (selectedImages.isNotEmpty) ...[
                    const Text(
                      "Selected Files:",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: selectedImages.length,
                      itemBuilder: (_, index) => Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E1E1E),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.image,
                              color: Colors.white60,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    selectedImages[index].name,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.red),
                              onPressed: () => setState(() {
                                selectedImages.removeAt(index);
                              }),
                              iconSize: 20,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Buttons
                  Column(
                    children: [
                      FilledButton.icon(
                        onPressed: _pickHistoryImages,
                        icon: const Icon(Icons.add_photo_alternate),
                        label: Text(
                          selectedImages.isEmpty
                              ? "Select Screenshots"
                              : "Add More Images",
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF4CAF50),
                          minimumSize: const Size.fromHeight(48),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (selectedImages.isNotEmpty) ...[
                        FilledButton(
                          onPressed: _uploadHistory,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF2196F3),
                            minimumSize: const Size.fromHeight(48),
                          ),
                          child: const Text(
                            "Upload & Extract Earnings",
                            style: TextStyle(fontSize: 16),
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: _clearSelection,
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.red),
                            minimumSize: const Size.fromHeight(48),
                          ),
                          child: const Text(
                            "Clear Selection",
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Tips
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.blue.withValues(alpha: 0.3),
                      ),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "💡 Tips for best results:",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          "• Take full-page screenshots of earnings summary\n"
                          "• Include the rupee (₹) symbol with amounts\n"
                          "• Avoid cropping important parts\n"
                          "• Use clear, well-lit screenshots",
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
