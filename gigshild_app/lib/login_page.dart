import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'otp_page.dart';
import 'registor_page.dart';
import 'ui_kit.dart';

// To connect this with your Django backend, you can use the http package to request OTP.
// Example:
// import 'package:http/http.dart' as http;
// Future<void> requestOTP(String phone) async {
//   var response = await http.post(
//     Uri.parse('YOUR_DJANGO_BACKEND_URL/api/login/'),
//     body: {'phone': phone},
//   );
//   if (response.statusCode == 200) {
//      // navigate to OTP page
//   }
// }

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _phoneController = TextEditingController();

  Future<void> loginUser(dynamic phoneController) async {
    var uri = Uri.parse("http://127.0.0.1:8000/api/login/");

    var response = await http.post(uri, body: {"phone": phoneController.text});

    if (!mounted) return;

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;

      // ✅ Go to home page
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => OTPPage(
            phoneNumber: _phoneController.text,
            partnerData: data["partner"] as Map<String, dynamic>?,
          ),
        ),
      );
    } else {
      // ❌ Phone not found
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Phone number not registered ❌")));
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: AppUi.pagePadding,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 12),
                  const Text(
                    AppUi.appName,
                    style: TextStyle(
                      color: AppUi.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'The better ML powered system',
                    style: TextStyle(
                      color: AppUi.text,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Intelligent premium collection and automatic claim protection for delivery partners.',
                    style: TextStyle(color: AppUi.muted, fontSize: 15, height: 1.4),
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    style: const TextStyle(color: AppUi.text, fontSize: 16),
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                    decoration: const InputDecoration(
                      hintText: 'Enter mobile number',
                      prefixIcon: Icon(Icons.phone_android, color: AppUi.muted),
                    ),
                  ),
                  const SizedBox(height: 18),
                  ElevatedButton(
                    onPressed: () => loginUser(_phoneController),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppUi.text,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Continue',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Center(
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 4,
                      children: [
                        const Text(
                          "New here?",
                          style: TextStyle(color: AppUi.muted),
                        ),
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const RegistrationPage(),
                              ),
                            );
                          },
                          child: const Text(
                            'Create account',
                            style: TextStyle(
                              color: AppUi.text,
                              fontWeight: FontWeight.w600,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
