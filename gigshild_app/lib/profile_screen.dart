
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'api_service.dart';
import 'app_state.dart';
import 'ui_kit.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic> partner = {};
  bool isLoading = true;
  bool _alertShown = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  // ──────────────────────────────────────────────
  // Load profile — use cached data first,
  // then refresh from Django
  // ──────────────────────────────────────────────
  Future<void> _loadProfile() async {
    // Use cached data immediately (from login)
    if (AppState.partnerData.isNotEmpty) {
      setState(() {
        partner = AppState.partnerData;
        isLoading = false;
      });
    }

    // 🔗 API CALL → GET /api/profile/<phone>/
    // Re-fetch to get latest data
    final result = await ApiService.getProfile(AppState.phone);

    if (result["success"] && mounted) {
      setState(() {
        partner = result["partner"];
        AppState.partnerData = result["partner"]; // Update cache
        isLoading = false;
      });
      if (partner["is_verified"] != true && !_alertShown) {
        _alertShown = true;
        _showUnverifiedAlert();
      }
    } else {
      setState(() => isLoading = false);
    }
  }

  // ──────────────────────────────────────────────
  // Verification helpers
  // ──────────────────────────────────────────────
  Future<void> _verifyUser() async {
    final picker = ImagePicker();
    final photo = await picker.pickImage(source: ImageSource.gallery);

    if (photo != null) {
      setState(() => isLoading = true);

      final result = await ApiService.verifyUser(
        phone: AppState.phone,
        selfieFile: photo,
      );

      if (!mounted) return;

      if (result["success"]) {
        setState(() {
          partner["is_verified"] = true;
          AppState.partnerData["is_verified"] = true;
          isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Verification complete! Automatic protection is now active.",
            ),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result["message"] ?? "Verification failed"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showUnverifiedAlert() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppUi.surface,
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent),
            SizedBox(width: 8),
            Text("Not Verified", style: TextStyle(color: Colors.orangeAccent)),
          ],
        ),
        content: const Text(
          "You are not verified yet. Please complete a selfie check so GigShild 2.0 can protect your work sessions and auto-review disruptions.",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Later", style: TextStyle(color: Colors.white38)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _verifyUser();
            },
            child: const Text(
              "Verify Now",
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Helper to build each info row
  // ──────────────────────────────────────────────
  Widget _infoRow(String label, String? value, {IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, color: Colors.white38, size: 18),
            const SizedBox(width: 10),
          ],
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white38, fontSize: 13),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value?.isNotEmpty == true ? value! : "—",
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Section card wrapper
  // ──────────────────────────────────────────────
  Widget _section(String title, List<Widget> children) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          const Divider(color: Colors.white12, height: 1),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppUi.background,
      appBar: AppBar(
        backgroundColor: AppUi.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(AppUi.appName, style: TextStyle(color: Colors.white)),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : RefreshIndicator(
              onRefresh: _loadProfile, // Pull to refresh
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    // ── Profile Header ──
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        children: [
                          // Profile photo
                          // 🔗 IMAGE: partner["profile_image"] is a full URL from Django
                          // e.g. http://127.0.0.1:8000/media/profiles/photo.jpg
                          CircleAvatar(
                            radius: 44,
                            backgroundColor: Colors.white12,
                            backgroundImage: partner["profile_image"] != null
                                ? NetworkImage(partner["profile_image"])
                                : null,
                            child: partner["profile_image"] == null
                                ? const Icon(
                                    Icons.person,
                                    color: Colors.white38,
                                    size: 40,
                                  )
                                : null,
                          ),
                          const SizedBox(height: 14),
                          Text(
                            partner["full_name"] ?? "—",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              "${partner["platform"] ?? "Zomato"} Partner",
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ── Verification Status ──
                    if (partner["is_verified"] != true)
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.red.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(
                                  Icons.warning_amber_rounded,
                                  color: Colors.orangeAccent,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  "Not Verified",
                                  style: TextStyle(
                                    color: Colors.orangeAccent,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Text(
                                "You are not verified yet. Verify with a selfie so GigShild 2.0 can validate your sessions and auto-review emergency support.",
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: _verifyUser,
                                icon: const Icon(Icons.camera_alt, size: 18),
                                label: const Text(
                                  "Verify Now",
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: Colors.black,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.green.withValues(alpha: 0.3),
                          ),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.verified, color: Colors.green),
                            SizedBox(width: 8),
                            Text(
                              "Verified Partner",
                              style: TextStyle(
                                color: Colors.green,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),

                    // ── Personal Info ──
                    _section("PERSONAL", [
                      _infoRow(
                        "Date of Birth",
                        partner["dob"],
                        icon: Icons.cake_outlined,
                      ),
                      _infoRow(
                        "Gender",
                        partner["gender"],
                        icon: Icons.person_outline,
                      ),
                    ]),

                    // ── Contact ──
                    _section("CONTACT", [
                      _infoRow(
                        "Phone",
                        partner["phone"],
                        icon: Icons.phone_outlined,
                      ),
                      _infoRow(
                        "Email",
                        partner["email"],
                        icon: Icons.email_outlined,
                      ),
                    ]),

                    // ── Location ──
                    _section("LOCATION", [
                      _infoRow(
                        "City",
                        partner["city"],
                        icon: Icons.location_city_outlined,
                      ),
                      _infoRow(
                        "Area",
                        partner["area"],
                        icon: Icons.map_outlined,
                      ),
                      _infoRow(
                        "Pincode",
                        partner["pincode"],
                        icon: Icons.pin_drop_outlined,
                      ),
                    ]),

                    // ── Platform ──
                    _section("PLATFORM", [
                      _infoRow(
                        "Platform",
                        partner["platform"],
                        icon: Icons.delivery_dining,
                      ),
                      _infoRow(
                        "Platform ID",
                        partner["platform_id"],
                        icon: Icons.badge_outlined,
                      ),
                    ]),

                    // ── Vehicle ──
                    _section("VEHICLE", [
                      _infoRow(
                        "Type",
                        partner["vehicle_type"],
                        icon: Icons.two_wheeler,
                      ),
                      _infoRow(
                        "Number",
                        partner["vehicle_number"],
                        icon: Icons.pin_outlined,
                      ),
                    ]),

                    // ── Emergency ──
                    _section("EMERGENCY CONTACT", [
                      _infoRow(
                        "Name",
                        partner["emergency_name"],
                        icon: Icons.contact_emergency_outlined,
                      ),
                      _infoRow(
                        "Phone",
                        partner["emergency_phone"],
                        icon: Icons.phone_callback_outlined,
                      ),
                    ]),

                    // ── Payment ──
                    _section("PAYMENT", [
                      _infoRow(
                        "UPI ID",
                        partner["upi_id"],
                        icon: Icons.account_balance_wallet_outlined,
                      ),
                    ]),

                    // ── Device ──
                    _section("DEVICE", [
                      _infoRow(
                        "Device Type",
                        partner["device_type"],
                        icon: Icons.phone_android_outlined,
                      ),
                    ]),

                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
    );
  }
}
