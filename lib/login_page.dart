import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email'],
  );

  // ⚠️ google_sign_in 不需要 initialize()！
  // 🚫 GoogleSignIn.initialize(); 會報錯 → 不能用

  Future<void> signInWithGoogle() async {
    try {
      // 1️⃣ 跳出 Google 登入視窗
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return;

      // 2️⃣ 取得 token
      final GoogleSignInAuthentication googleAuth =
      await googleUser.authentication;

      // 3️⃣ 使用 FirebaseAuth 登入
      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
        accessToken: googleAuth.accessToken,
      );

      final userCredential =
      await FirebaseAuth.instance.signInWithCredential(credential);

      final user = userCredential.user;

      // 4️⃣ 更新 Firestore
      await FirebaseFirestore.instance
          .collection("users")
          .doc(user!.uid)
          .set({
        "name": user.displayName,
        "email": user.email,
        "photoURL": user.photoURL,
        "lastLogin": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) Navigator.pop(context);
    } catch (e) {
      print("❌ Google 登入失敗: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: signInWithGoogle,
          child: const Text("Google 登入"),
        ),
      ),
    );
  }
}