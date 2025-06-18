import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:VetApp/features/user_auth/firebase_auth_implementation/firebase_auth_services.dart';
import 'package:VetApp/features/user_auth/presentation/pages/login_page.dart';
import 'package:VetApp/features/user_auth/presentation/widgets/form_container_widget.dart';
import 'package:VetApp/global/common/toast.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../constants/colors.dart';

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final FirebaseAuthService _auth = FirebaseAuthService();

  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _contactController =
  TextEditingController(); // Contact field
  final TextEditingController _addressController =
  TextEditingController(); // Address field

  bool isSigningUp = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,  // Set the background color here
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 0),
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              // gradient: LinearGradient(
              //   colors: [
              //     Color(0xFFF1F1F1),
              //     Color(0xFFE0E0E0)
              //   ],
              //   begin: Alignment.topLeft,
              //   end: Alignment.bottomRight,
              // ),
            ),
            child: SingleChildScrollView(  // Wrap the Column with SingleChildScrollView to allow scrolling
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "Sign Up",
                    style: GoogleFonts.bungeeSpice(
                      textStyle: TextStyle(
                        fontSize: 70,
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  // Wrap the input fields and button inside a Container with fixed width
                  Container(
                    width: 300, // Set fixed width for the input fields
                    child: Column(
                      children: [
                        _buildFormField(_usernameController, "Username"),
                        const SizedBox(height: 10),
                        _buildFormField(_emailController, "Email"),
                        const SizedBox(height: 10),
                        _buildFormField(_passwordController, "Password", isPassword: true),
                        const SizedBox(height: 10),
                        _buildFormField(_contactController, "Contact Number"),
                        const SizedBox(height: 10),
                        _buildFormField(_addressController, "Address", verticalPadding: 30, maxLines: 5),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),
                  if (isSigningUp)
                    const CircularProgressIndicator(color: Color(0xFFFF6F00))
                  else ...[
                    // Button with fixed width
                    Container(
                      width: 300, // Set fixed width for the button
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF6F00),
                          minimumSize: const Size(double.infinity, 45),
                        ),
                        onPressed: () => _signUp("customer"),
                        child: const Text(
                          "Register as Normal User",
                          style: TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text("Already have an account?",
                          style: TextStyle(color: Color(0xFF333333))),
                      const SizedBox(width: 5),
                      GestureDetector(
                        onTap: () => Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(builder: (context) => LoginPage()),
                              (route) => false,
                        ),
                        child: const Text(
                          "Login",
                          style: TextStyle(
                              color: Color(0xFFFF6F00),
                              fontWeight: FontWeight.bold),
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
    );
  }

  // Helper method to create form fields with 3D effect and shadows
  Widget _buildFormField(TextEditingController controller, String hintText,
      {bool isPassword = false, double? verticalPadding, int? maxLines}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.3),
            spreadRadius: 2,
            blurRadius: 5,
            offset: const Offset(0, 3), // Changes position of shadow
          ),
        ],
      ),
      child: TextFormField(
        controller: controller,
        obscureText: isPassword,
        decoration: InputDecoration(
          hintText: hintText,
          border: InputBorder.none,
          contentPadding:
          EdgeInsets.symmetric( vertical: verticalPadding ?? 15, // Default vertical padding is 15 if not specified
            horizontal: 20,),
        ),
      ),
    );
  }

  // In sign-up logic (for assigning roles manually by the admin)
  Future<void> _signUp(String role) async {
    setState(() => isSigningUp = true);

    String username = _usernameController.text;
    String email = _emailController.text;
    String password = _passwordController.text;
    String contact = _contactController.text;
    String address = _addressController.text;

    User? user = await _auth.signUpWithEmailAndPassword(email, password);

    if (user != null) {
      String finalRole = 'customer'; // Default role is customer
      final userRef =
      FirebaseFirestore.instance.collection('users').doc(user.uid);
      final userDoc = await userRef.get();

      if (userDoc.exists) {
        final data = userDoc.data();
        if (data != null && data['userRole'] == 'admin') {
          finalRole = 'admin'; // Preserve admin role
        }
      }

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'email': email,
        'username': username,
        'userRole': finalRole,
        'contact': contact,
        'address': address,
      });

      // Save FCM Token after user creation
      await saveUserTokenToFirestore(user.uid);

      showToast(
          message: role == "pending_vet"
              ? "Vet registration successful. Awaiting admin approval."
              : "User successfully created.");
      Navigator.pushNamedAndRemoveUntil(context, "/login", (route) => false);
    } else {
      showToast(message: "Error during sign-up.");
    }

    setState(() => isSigningUp = false);
  }
}
