import 'package:flutter/material.dart';
import 'package:slide_to_act/slide_to_act.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'login_page.dart';
import 'package:flutter/foundation.dart' show kIsWeb;


void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: LoginPage(),
    );
  }
}

class RegistrationPage extends StatefulWidget {
  const RegistrationPage({super.key});

  @override
  State<RegistrationPage> createState() => _RegistrationPageState();
}

class _RegistrationPageState extends State<RegistrationPage> {
  final _formKey = GlobalKey<FormState>();

  // ✅ Controllers
  final nameController = TextEditingController();
  final dobController = TextEditingController();
  final phoneController = TextEditingController();
  final emailController = TextEditingController();
  final cityController = TextEditingController();
  final areaController = TextEditingController();
  final pincodeController = TextEditingController();
  final platformIdController = TextEditingController();
  final deviceController = TextEditingController();
  final emergencyNameController = TextEditingController();
  final emergencyPhoneController = TextEditingController();
  final upiController = TextEditingController();
  final vehicleTypeController = TextEditingController();
  final vehicleNumberController = TextEditingController();

  String selectedPlatform = "Zomato";
  String selectedGender = "Male";

  XFile? image;

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.white,
              onPrimary: Colors.black,
              surface: Colors.black,
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        dobController.text =
            "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
      });
    }
  }

  Widget buildTextField(String label, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextFormField(
        controller: controller,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: label,
          hintStyle: const TextStyle(color: Colors.white38),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.05),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
        validator: (value) => value!.isEmpty ? "Enter $label" : null,
      ),
    );
  }

  Widget sectionTitle(String title) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Text(
          title,
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
      ),
    );
  }

  Future<Map<String, dynamic>> registerUser() async {
    try {
      var uri = Uri.parse("http://localhost:8000/api/register/");
      var request = http.MultipartRequest('POST', uri);

      request.fields.addAll({
        "full_name": nameController.text,
        "dob": dobController.text,
        "gender": selectedGender,
        "phone": phoneController.text,
        "email": emailController.text,
        "city": cityController.text,
        "area": areaController.text,
        "pincode": pincodeController.text,
        "platform": selectedPlatform,
        "platform_id": platformIdController.text,
        "device_type": deviceController.text,
        "emergency_name": emergencyNameController.text,
        "emergency_phone": emergencyPhoneController.text,
        "upi_id": upiController.text,
        "vehicle_type": vehicleTypeController.text,
        "vehicle_number": vehicleNumberController.text,
      });

      if (image != null) {
        final bytes = await image!.readAsBytes();
        request.files.add(
          http.MultipartFile.fromBytes(
            'profile_image',
            bytes,
            filename: image!.name,
          ),
        );
      }

      var response = await request.send();
      final body = await response.stream.bytesToString();
      
      try {
        final data = jsonDecode(body);
        if (response.statusCode == 200 || response.statusCode == 201) {
          return {"success": true, "message": data["message"] ?? "Registered Successfully 🚀"};
        } else {
          String errorMsg = data["message"] ?? "Registration failed ❌";
          if (data["errors"] is Map) {
            final errors = data["errors"] as Map;
            if (errors.isNotEmpty) {
              final firstError = errors.values.first;
              if (firstError is List && firstError.isNotEmpty) {
                errorMsg = firstError.first.toString();
              } else {
                errorMsg = firstError.toString();
              }
            }
          }
          return {"success": false, "message": errorMsg};
        }
      } catch (e) {
        return {"success": false, "message": "Invalid response from server. ❌"};
      }
    } catch (e) {
      return {"success": false, "message": "Connection error: $e"};
    }
  }

  Future<void> submitForm() async {
    if (_formKey.currentState!.validate()) {
      final result = await registerUser();

      // Guard the BuildContext with a mounted check
      if (!mounted) return;

      if (result["success"]) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result["message"]),
            backgroundColor: Colors.green,
          ),
        );
        // Route to login page on success
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const LoginPage()),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result["message"]),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget platformSelector() {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() => selectedPlatform = "Zomato"),
            child: Container(
              height: 60,
              decoration: BoxDecoration(
                color: selectedPlatform == "Zomato"
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Text(
                  "Zomato",
                  style: TextStyle(
                    color: selectedPlatform == "Zomato"
                        ? Colors.black
                        : Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            height: 60,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Center(
              child: Text(
                "Swiggy (Coming Soon)",
                style: TextStyle(color: Colors.white38),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget genderSelector() {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() => selectedGender = "Male"),
            child: Container(
              height: 60,
              decoration: BoxDecoration(
                color: selectedGender == "Male"
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Text(
                  "Male",
                  style: TextStyle(
                    color: selectedGender == "Male"
                        ? Colors.black
                        : Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() => selectedGender = "Female"),
            child: Container(
              height: 60,
              decoration: BoxDecoration(
                color: selectedGender == "Female"
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Text(
                  "Female",
                  style: TextStyle(
                    color: selectedGender == "Female"
                        ? Colors.black
                        : Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final slideKey = GlobalKey<SlideActionState>();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text("Register"),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              sectionTitle("PERSONAL"),
              buildTextField("Full Name", nameController),
              GestureDetector(
                onTap: () => _selectDate(context),
                child: AbsorbPointer(
                  child: buildTextField("DOB (YYYY-MM-DD)", dobController),
                ),
              ),
              const SizedBox(height: 8),
              genderSelector(),

              sectionTitle("CONTACT"),
              buildTextField("Phone", phoneController),
              buildTextField("Email", emailController),

              sectionTitle("LOCATION"),
              buildTextField("City", cityController),
              buildTextField("Area", areaController),
              buildTextField("Pincode", pincodeController),

              sectionTitle("PLATFORM"),
              platformSelector(),
              buildTextField("Platform ID", platformIdController),

              sectionTitle("DEVICE"),
              buildTextField("Device", deviceController),

              sectionTitle("EMERGENCY"),
              buildTextField("Name", emergencyNameController),
              buildTextField("Phone", emergencyPhoneController),

              sectionTitle("PAYMENT"),
              buildTextField("UPI", upiController),

              sectionTitle("VEHICLE"),
              buildTextField("Type", vehicleTypeController),
              buildTextField("Number", vehicleNumberController),

              const SizedBox(height: 20),

              GestureDetector(
                onTap: () async {
                  final picker = ImagePicker();
                  final picked = await picker.pickImage(
                    source: ImageSource.gallery,
                  );
                  if (picked != null) {
                    setState(() => image = picked);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white24),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Text(
                    "Upload Profile Screenshot",
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              ),

              if (image != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: kIsWeb 
                      ? Image.network(image!.path, height: 100) 
                      : Image.file(File(image!.path), height: 100),
                ),

              const SizedBox(height: 30),

              SlideAction(
                key: slideKey,
                text: "Slide to Register",
                outerColor: Colors.white,
                innerColor: Colors.black,
                textStyle: const TextStyle(color: Colors.black),
                onSubmit: () async {
                  await submitForm();
                  slideKey.currentState?.reset();
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
