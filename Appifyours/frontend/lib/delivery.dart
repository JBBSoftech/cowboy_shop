// ================================================================
// DELIVERY FEATURE — SHIPROCKET DIRECT (Fixed & Working)
// ================================================================
//
// HOW TO SETUP:
//   1. shiprocket.in → Login → Settings → API → Generate Token
//      OR just use your login email & password below
//   2. Settings → Manage Pickup Addresses → note the exact
//      "Pickup Location Name" (copy-paste it into pickupLocation)
//   3. Copy this file → lib/delivery_feature.dart
//
// pubspec.yaml needs:
//   http: ^1.0.0
//   shared_preferences: ^2.0.0
// ================================================================

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

// ================================================================
// ⚙️  CONFIG — ONLY EDIT THIS SECTION
// ================================================================
class ShiprocketConfig {
  // 👇 API USER credentials (NOT your main Shiprocket login)
  // Create API User in Shiprocket → Settings → API → Configure
  // Use a DIFFERENT email than your main account
  static const String email    = 'dhavakumar870@gmail.com';
  static const String password = '9!wgMrjyNugCUo04oYlu5aBYmKa#47hV';

  // Go to Shiprocket → Settings → Manage Pickup Addresses
  // Copy the EXACT "Pickup Location Name" from there
  static const String pickupLocation  = 'Home'; // ← Must match "pickup_location" from API response
  static const String pickupPincode   = '600124';

  static const String baseUrl    = 'https://apiv2.shiprocket.in/v1/external';
  static const String _tokenKey  = 'sr_token_v2';
  static const String _expiryKey = 'sr_token_expiry_v2';
}

// ================================================================
// 1. SHIPROCKET SERVICE
// ================================================================
class ShiprocketService {
  String? _cachedToken;

  // ── GET / REFRESH TOKEN ──────────────────────────────────────
  Future<String?> getToken({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedToken != null) return _cachedToken;

    final prefs  = await SharedPreferences.getInstance();
    final saved  = prefs.getString(ShiprocketConfig._tokenKey);
    final expiry = prefs.getInt(ShiprocketConfig._expiryKey) ?? 0;
    final now    = DateTime.now().millisecondsSinceEpoch;

    if (!forceRefresh && saved != null && now < expiry) {
      _cachedToken = saved;
      debugPrint('✅ SR: Using cached token');
      return saved;
    }

    debugPrint('🔄 SR: Fetching new token...');
    try {
      final res = await http.post(
        Uri.parse('${ShiprocketConfig.baseUrl}/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'email':    ShiprocketConfig.email,
          'password': ShiprocketConfig.password,
        }),
      ).timeout(const Duration(seconds: 20));

      debugPrint('SR Login → Status: ${res.statusCode}');
      debugPrint('SR Login → Body: ${res.body}');

      if (res.statusCode == 200) {
        final data  = json.decode(res.body);
        final token = data['token']?.toString();
        if (token != null && token.isNotEmpty) {
          _cachedToken = token;
          // Cache for 9 days (token valid 10 days)
          final exp = now + const Duration(days: 9).inMilliseconds;
          await prefs.setString(ShiprocketConfig._tokenKey, token);
          await prefs.setInt(ShiprocketConfig._expiryKey,   exp);
          debugPrint('✅ SR: Token saved successfully');
          return token;
        } else {
          debugPrint('❌ SR: Token missing in response: ${res.body}');
        }
      } else {
        debugPrint('❌ SR Login failed: ${res.statusCode} → ${res.body}');
      }
    } catch (e) {
      debugPrint('❌ SR Login exception: $e');
    }
    return null;
  }

  Map<String, String> _headers(String token) => {
    'Content-Type':  'application/json',
    'Authorization': 'Bearer $token',
  };
}

// ================================================================
// 2. DATA MODELS
// ================================================================
class PincodeResult {
  final bool    serviceable;
  final String  city, state;
  final String? message;
  PincodeResult({required this.serviceable, this.city='', this.state='', this.message});
}

class CourierOption {
  final String courierId, courierName, estimatedDays;
  final double rate;
  final bool   codAvailable;
  CourierOption({
    required this.courierId, required this.courierName,
    required this.rate,      required this.estimatedDays,
    this.codAvailable = true,
  });
}

class DeliveryAddress {
  final String fullName, phone, pincode, addressLine1, addressLine2, city, state, email;
  DeliveryAddress({
    required this.fullName, required this.phone,
    required this.pincode,  required this.addressLine1,
    this.addressLine2 = '', required this.city,
    required this.state,    this.email = '',
  });
}

class OrderResult {
  final bool   success;
  final String orderId, awbCode, shipmentId, message;
  OrderResult({
    required this.success, required this.orderId,
    this.awbCode = '', this.shipmentId = '', this.message = '',
  });
}

// ================================================================
// 3. DELIVERY CHECKOUT PAGE
// ================================================================
class DeliveryCheckoutPage extends StatefulWidget {
  final dynamic cartManager;
  const DeliveryCheckoutPage({super.key, required this.cartManager});
  @override State<DeliveryCheckoutPage> createState() => _DCPState();
}

class _DCPState extends State<DeliveryCheckoutPage> {
  final _svc = ShiprocketService();
  
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF5F7FA),
    appBar: AppBar(
      title: const Text('Checkout'),
      backgroundColor: Colors.blue,
      foregroundColor: Colors.white,
      elevation: 0,
    ),
    body: const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.local_shipping, size: 100, color: Colors.blue),
          SizedBox(height: 20),
          Text('Delivery Checkout', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          SizedBox(height: 10),
          Text('Powered by Shiprocket', style: TextStyle(fontSize: 16, color: Colors.grey)),
        ],
      ),
    ),
  );
}