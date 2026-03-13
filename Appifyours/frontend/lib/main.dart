import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'screens/element_screen/delivery.dart';
import 'services/api_service.dart';

// Auth Helper class (replacing the import)
class AuthHelper {
  static final AuthHelper _instance = AuthHelper._internal();
  factory AuthHelper() => _instance;
  AuthHelper._internal();

  Future<bool> isAdmin() async {
    final prefs = await SharedPreferences.getInstance();
    final userType = prefs.getString('user_type');
    return userType == 'admin';
  }

  Future<Map<String, String>> getAuthHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  Future<String?> getCurrentUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_id');
  }
}

final authHelper = AuthHelper();

// PriceUtils class
class PriceUtils {
  static String formatPrice(double price, {String currency = '\$'}) {
    return '$currency${price.toStringAsFixed(2)}';
  }
  
  static double parsePrice(String priceString) {
    if (priceString.isEmpty) return 0.0;
    String numericString = priceString.replaceAll(RegExp(r'[^\d.]'), '');
    return double.tryParse(numericString) ?? 0.0;
  }
  
  static String detectCurrency(String priceString) {
    if (priceString.contains('₹')) return '₹';
    if (priceString.contains('\$')) return '\$';
    if (priceString.contains('€')) return '€';
    if (priceString.contains('£')) return '£';
    if (priceString.contains('¥')) return '¥';
    if (priceString.contains('₩')) return '₩';
    if (priceString.contains('₽')) return '₽';
    if (priceString.contains('₦')) return '₦';
    if (priceString.contains('₨')) return '₨';
    return '\$';
  }
  
  static String currencySymbolFromCode(String code) {
    switch (code.toUpperCase()) {
      case 'USD':
      case 'AUD':
      case 'CAD':
        return '\$';
      case 'EUR':
        return '€';
      case 'GBP':
        return '£';
      case 'JPY':
        return '¥';
      case 'INR':
        return '₹';
      case 'KRW':
        return '₩';
      case 'RUB':
        return '₽';
      case 'NGN':
        return '₦';
      case 'PKR':
        return '₨';
      default:
        return '\$';
    }
  }
  
  static double calculateDiscountPrice(double originalPrice, double discountPercentage) {
    return originalPrice * (1 - discountPercentage / 100);
  }
  
  static double calculateTotal(List<double> prices) {
    return prices.fold(0.0, (sum, price) => sum + price);
  }
  
  static double calculateTax(double subtotal, double taxRate) {
    return subtotal * (taxRate / 100);
  }
  
  static double applyShipping(double total, double shippingFee, {double freeShippingThreshold = 100.0}) {
    return total >= freeShippingThreshold ? total : total + shippingFee;
  }
}

// Cart item model
class CartItem {
  final String id;
  final String name;
  final double price;
  final double discountPrice;
  int quantity;
  final String? image;
  final String currencySymbol;
  
  CartItem({
    required this.id,
    required this.name,
    required this.price,
    this.discountPrice = 0.0,
    this.quantity = 1,
    this.image,
    this.currencySymbol = '\$',
  });
  
  double get effectivePrice => discountPrice > 0 ? discountPrice : price;
  double get totalPrice => effectivePrice * quantity;
}

// Cart manager
class CartManager extends ChangeNotifier {
  final List<CartItem> _items = [];
  double _gstPercentage = 18.0;
  double _discountPercentage = 0.0;
  
  List<CartItem> get items => List.unmodifiable(_items);
  
  int get totalQuantity => _items.fold(0, (sum, item) => sum + item.quantity);
  
  String get displayCurrencySymbol => '\$';
  
  void updateGSTPercentage(double percentage) {
    _gstPercentage = percentage;
    notifyListeners();
  }
  
  void updateDiscountPercentage(double percentage) {
    _discountPercentage = percentage;
    notifyListeners();
  }
  
  double get gstPercentage => _gstPercentage;
  double get discountPercentage => _discountPercentage;
  
  void addItem(CartItem item) {
    final existingIndex = _items.indexWhere((i) => i.id == item.id);
    if (existingIndex >= 0) {
      _items[existingIndex].quantity += item.quantity;
    } else {
      _items.add(item);
    }
    notifyListeners();
  }
  
  void removeItem(String id) {
    _items.removeWhere((item) => item.id == id);
    notifyListeners();
  }
  
  void updateQuantity(String id, int quantity) {
    final item = _items.firstWhere((i) => i.id == id);
    item.quantity = quantity;
    notifyListeners();
  }
  
  void clear() {
    _items.clear();
    notifyListeners();
  }
  
  double get subtotal {
    return _items.fold(0.0, (sum, item) => sum + item.totalPrice);
  }
  
  double get totalWithTax {
    final tax = PriceUtils.calculateTax(subtotal, 8.0);
    return subtotal + tax;
  }
  
  double get totalDiscount {
    return _items.fold(0.0, (sum, item) => 
      sum + ((item.price - item.effectivePrice) * item.quantity));
  }
  
  double get gstAmount {
    return PriceUtils.calculateTax(subtotal, _gstPercentage);
  }
  
  double get finalTotal {
    return subtotal + gstAmount;
  }
  
  double get finalTotalWithShipping {
    return PriceUtils.applyShipping(totalWithTax, 5.99);
  }
}

// Wishlist item model
class WishlistItem {
  final String id;
  final String name;
  final double price;
  final double discountPrice;
  final String? image;
  final String currencySymbol;
  
  WishlistItem({
    required this.id,
    required this.name,
    required this.price,
    this.discountPrice = 0.0,
    this.image,
    this.currencySymbol = '\$',
  });
  
  double get effectivePrice => discountPrice > 0 ? discountPrice : price;
}

// Wishlist manager
class WishlistManager extends ChangeNotifier {
  final List<WishlistItem> _items = [];
  
  List<WishlistItem> get items => List.unmodifiable(_items);
  
  void addItem(WishlistItem item) {
    if (!_items.any((i) => i.id == item.id)) {
      _items.add(item);
      notifyListeners();
    }
  }
  
  void removeItem(String id) {
    _items.removeWhere((item) => item.id == id);
    notifyListeners();
  }
  
  void clear() {
    _items.clear();
    notifyListeners();
  }
  
  bool isInWishlist(String id) {
    return _items.any((item) => item.id == id);
  }
}

// Dynamic Configuration
String gstNumber = '';
String selectedCategory = '';
Map<String, dynamic> storeInfo = {
  'storeName': 'My Store',
  'address': '123 Main St',
  'email': 'support@example.com',
  'phone': '(123) 456-7890',
};

// Dynamic Product Data
List<Map<String, dynamic>> productCards = [];
bool isLoading = true;
String? errorMessage;

// Quantity tracking for products
Map<String, int> _productQuantities = {};

// WebSocket Real-time Sync Service
class DynamicAppSync {
  static final DynamicAppSync _instance = DynamicAppSync._internal();
  factory DynamicAppSync() => _instance;
  DynamicAppSync._internal();

  IO.Socket? _socket;
  final StreamController<Map<String, dynamic>> _updateController = 
      StreamController<Map<String, dynamic>>.broadcast();
  
  bool _isConnected = false;
  String? _adminId;

  Stream<Map<String, dynamic>> get updates => _updateController.stream;
  bool get isConnected => _isConnected;

  void connect({String? adminId, required String apiBase}) {
    if (_isConnected && _socket != null) return;

    _adminId = adminId;
    
    try {
      final options = {
        'transports': ['websocket'],
        'autoConnect': true,
        'reconnection': true,
        'reconnectionAttempts': 5,
        'reconnectionDelay': 1000,
        'timeout': 5000,
      };

      _socket = IO.io('$apiBase/real-time-updates', options);
      _setupSocketListeners();
      
    } catch (e) {
      print('DynamicAppSync: Error connecting: $e');
    }
  }

  void _setupSocketListeners() {
    if (_socket == null) return;

    _socket!.onConnect((_) {
      print('DynamicAppSync: Connected');
      _isConnected = true;
      
      if (_adminId != null && _adminId!.isNotEmpty) {
        _socket!.emit('join-admin-room', {'adminId': _adminId});
      }
    });

    _socket!.onDisconnect((_) {
      print('DynamicAppSync: Disconnected');
      _isConnected = false;
    });

    _socket!.on('dynamic-update', (data) {
      print('DynamicAppSync: Received update: $data');
      if (!_updateController.isClosed) {
        _updateController.add(Map<String, dynamic>.from(data));
      }
    });

    _socket!.on('home-page', (data) {
      _handleUpdate({'type': 'home-page', 'data': data});
    });
  }

  void _handleUpdate(Map<String, dynamic> update) {
    if (!_updateController.isClosed) {
      _updateController.add(update);
    }
  }

  void disconnect() {
    if (_socket != null) {
      _socket!.disconnect();
      _socket = null;
    }
    _isConnected = false;
  }

  void dispose() {
    disconnect();
    if (!_updateController.isClosed) {
      _updateController.close();
    }
  }
}

// API Configuration
class ApiConfig {
  static String get baseUrl => dotenv.env['API_BASE'] ?? 'http://localhost:5000';
  static const String adminObjectId = '695cd3bc9d407628795684fb';
  static const String appId = 'APP_ID_HERE';
}

class SessionManager {
  static const String adminUserId = ApiConfig.adminObjectId;
  static String? currentUserId;
  static String? authToken;
  static String appName = 'AppifyYours';

  static Future<void> initFromAdminConfig({
    required String loadedAppName,
  }) async {
    appName = loadedAppName;
    print('🔍 Admin config loaded: $loadedAppName');
    print('🎨 App name set globally: $appName');

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_name', appName);
  }

  static Future<void> bindAuth({
    required String userId,
    required String token,
  }) async {
    currentUserId = userId;
    authToken = token;
    print('✅ User logged in: $userId');
    print('🔐 Session bound to userId: $userId');

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
    await prefs.setString('user_id', userId);
  }
}

// Dynamic Admin ID Detection
class AdminManager {
  static String? _currentAdminId;
  
  static Future<String> getCurrentAdminId() async {
    if (_currentAdminId != null) return _currentAdminId!;

    final adminId = ApiConfig.adminObjectId;
    _currentAdminId = adminId;
    print('✅ Admin ID locked: $adminId');
    return adminId;
  }
  
  static Future<String?> _autoDetectAdminId() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/admin/app-info'),
        headers: {'Content-Type': 'application/json'},
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['data'] != null) {
          final appInfo = data['data'];
          final adminId = appInfo['adminId'];
          if (adminId != null && adminId.toString().isNotEmpty) {
            return adminId.toString();
          }
        }
      }
    } catch (e) {
      print('Auto-detection failed: $e');
    }
    return null;
  }
  
  static Future<void> setAdminId(String adminId) async {
    throw UnsupportedError('Admin ID is immutable in generated apps');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Generated E-commerce App',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorSchemeSeed: Colors.blue,
        appBarTheme: const AppBarTheme(
          elevation: 4,
          shadowColor: Colors.black38,
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
        ),
        cardTheme: const CardTheme(
          elevation: 4,
          shadowColor: Colors.black12,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
          ),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
      home: const SplashScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// Splash Screen
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  String _appName = 'Loading...';
  bool _mounted = true;

  @override
  void initState() {
    super.initState();
    _fetchAppNameAndNavigate();
  }

  @override
  void dispose() {
    _mounted = false;
    super.dispose();
  }

  Future<void> _fetchAppNameAndNavigate() async {
    try {
      final adminId = await AdminManager.getCurrentAdminId();
      print('🔍 Splash screen using admin ID: $adminId');

      final response = await http.get(
        Uri.parse('${dotenv.env['API_BASE'] ?? 'http://localhost:5000'}/api/admin/splash?adminId=$adminId&appId=${ApiConfig.appId}'),
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (_mounted) {
          final loadedName = (data['appName'] ?? data['shopName'] ?? 'AppifyYours').toString();
          await SessionManager.initFromAdminConfig(loadedAppName: loadedName);
          setState(() {
            _appName = SessionManager.appName;
          });
          print('✅ Splash screen loaded app name: $_appName');
        }
      } else {
        print('⚠️ Splash screen API error: ${response.statusCode}');
        if (_mounted) {
          setState(() {
            _appName = SessionManager.appName;
          });
        }
      }
    } catch (e) {
      print('Error fetching app name: $e');
      if (_mounted) {
        setState(() {
          _appName = SessionManager.appName;
        });
      }
    }
    
    await Future.delayed(const Duration(seconds: 3));
    
    if (_mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const SignInPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.blue.shade400, Colors.blue.shade800],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              const Icon(
                Icons.shopping_bag,
                size: 100,
                color: Colors.white,
              ),
              const SizedBox(height: 24),
              Text(
                _appName,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              const CircularProgressIndicator(color: Colors.white),
              const Spacer(),
              const Text(
                'Powered by AppifyYours',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

// Sign In Page
class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _mounted = true;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _mounted = false;
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields')),
      );
      return;
    }

    if (_mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final adminId = await AdminManager.getCurrentAdminId();
      final response = await http.post(
        Uri.parse('${dotenv.env['API_BASE'] ?? 'http://localhost:5000'}/api/login'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'email': _emailController.text.trim(),
          'password': _passwordController.text,
          'adminId': adminId,
          'appId': ApiConfig.appId,
        }),
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final token = data['token']?.toString();
          final user = data['user'];
          final userId = (user is Map)
              ? (user['_id']?.toString() ?? user['id']?.toString())
              : null;
          if (token != null && token.isNotEmpty && userId != null && userId.isNotEmpty) {
            await SessionManager.bindAuth(userId: userId, token: token);
          }
          if (_mounted) {
            setState(() => _isLoading = false);
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const HomePage()),
            );
          }
        } else {
          throw Exception(data['error'] ?? 'Sign in failed');
        }
      } else {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Invalid credentials');
      }
    } catch (e) {
      if (_mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sign in failed: ${e.toString().replaceAll("Exception: ", "")}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 60),
              const Icon(
                Icons.shopping_bag,
                size: 80,
                color: Colors.blue,
              ),
              const SizedBox(height: 24),
              const Text(
                'Welcome Back',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Sign in to continue',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              TextField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.email),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                    onPressed: () {
                      if (_mounted) {
                        setState(() => _obscurePassword = !_obscurePassword);
                      }
                    },
                  ),
                ),
                obscureText: _obscurePassword,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoading ? null : _signIn,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Sign In', style: TextStyle(fontSize: 16)),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const CreateAccountPage(),
                    ),
                  );
                },
                child: const Text('Create Your Account'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Create Account Page
class CreateAccountPage extends StatefulWidget {
  const CreateAccountPage({super.key});

  @override
  State<CreateAccountPage> createState() => _CreateAccountPageState();
}

class _CreateAccountPageState extends State<CreateAccountPage> {
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _mounted = true;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _mounted = false;
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool _validateEmail(String email) {
    return RegExp(r'^[a-zA-Z0-9._-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,4}$').hasMatch(email);
  }

  bool _validatePhone(String phone) {
    return RegExp(r'^[0-9]{10}$').hasMatch(phone);
  }

  bool _validatePassword(String password) {
    return password.length >= 6;
  }

  Future<void> _createAccount() async {
    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final email = _emailController.text.trim();
    final phone = _phoneController.text.trim();
    final password = _passwordController.text;

    if (firstName.isEmpty || lastName.isEmpty || email.isEmpty || phone.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields')),
      );
      return;
    }

    if (!_validateEmail(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid email')),
      );
      return;
    }

    if (!_validatePhone(phone)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid 10-digit phone number')),
      );
      return;
    }

    if (!_validatePassword(password)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password must be at least 6 characters')),
      );
      return;
    }

    if (_mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final adminId = await AdminManager.getCurrentAdminId();
      final response = await http.post(
        Uri.parse('${dotenv.env['API_BASE'] ?? 'http://localhost:5000'}/api/signup'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'firstName': firstName,
          'lastName': lastName,
          'email': email,
          'password': password,
          'phone': phone,
          'adminId': adminId,
          'shopName': SessionManager.appName,
        }),
      );

      final result = json.decode(response.body);

      if (_mounted) {
        setState(() => _isLoading = false);
      }

      if (result['success'] == true) {
        final token = result['token']?.toString();
        final user = result['user'];
        final userId = (user is Map)
            ? (user['_id']?.toString() ?? user['id']?.toString())
            : (result['data'] is Map ? (result['data']['userId']?.toString()) : null);
        if (token != null && token.isNotEmpty && userId != null && userId.isNotEmpty) {
          await SessionManager.bindAuth(userId: userId, token: token);
        }
        if (_mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Account created successfully! Please sign in.'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context);
        }
      } else {
        final data = result['data'];
        String message = 'Failed to create account';
        if (data is Map<String, dynamic> && data['message'] != null) {
          message = data['message'].toString();
        }
        throw Exception(message);
      }
    } catch (e) {
      if (_mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: ${e.toString().replaceAll('Exception: ', '')}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Account'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Join Us Today',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Create your account to get started',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _firstNameController,
              decoration: const InputDecoration(
                labelText: 'First Name',
                prefixIcon: Icon(Icons.person),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _lastNameController,
              decoration: const InputDecoration(
                labelText: 'Last Name',
                prefixIcon: Icon(Icons.person_outline),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _phoneController,
              decoration: const InputDecoration(
                labelText: 'Phone Number',
                prefixIcon: Icon(Icons.phone),
                hintText: '10 digit number',
              ),
              keyboardType: TextInputType.phone,
              maxLength: 10,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'Email ID',
                prefixIcon: Icon(Icons.email),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock),
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                  onPressed: () {
                    if (_mounted) {
                      setState(() => _obscurePassword = !_obscurePassword);
                    }
                  },
                ),
              ),
              obscureText: _obscurePassword,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isLoading ? null : _createAccount,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Create Account', style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}

// Home Page
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late PageController _pageController;
  late ScrollController _scrollController;
  final GlobalKey _productGridKey = GlobalKey();

  int _currentPageIndex = 0;
  final CartManager _cartManager = CartManager();
  final WishlistManager _wishlistManager = WishlistManager();
  int _cartNotificationCount = 0;
  int _wishlistNotificationCount = 0;
  String _searchQuery = '';
  List<Map<String, dynamic>> _filteredProducts = [];
  List<Map<String, dynamic>> _dynamicProductCards = [];
  bool _isLoading = true;
  List<Map<String, dynamic>> _homeWidgets = [];
  Map<String, dynamic> _dynamicStoreInfo = {};
  Map<String, dynamic> _dynamicDesignSettings = {};
  Color _pageBackgroundColor = Colors.white;
  bool _mounted = true;
  final DynamicAppSync _appSync = DynamicAppSync();
  StreamSubscription? _updateSubscription;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    _scrollController = ScrollController();
    _dynamicProductCards = List.from(productCards);
    _filteredProducts = List.from(_dynamicProductCards);
    _loadDynamicData();
    _startRealTimeUpdates();
  }

  @override
  void dispose() {
    _mounted = false;
    _updateSubscription?.cancel();
    _appSync.dispose();
    _pageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToProductGrid() {
    final context = _productGridKey.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }

  void _handleBuyNow() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DeliveryCheckoutPage(cartManager: _cartManager),
      ),
    );
  }

  Future<void> _loadDynamicData() async {
    if (_mounted) {
      setState(() => _isLoading = true);
    }
    await _loadDynamicAppConfig();
    if (_mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadDynamicAppConfig() async {
    try {
      final adminId = await AdminManager.getCurrentAdminId();
      print('🔍 Home page using admin ID: $adminId');

      final response = await http.get(
        Uri.parse('${dotenv.env['API_BASE'] ?? 'http://localhost:5000'}/api/get-form?adminId=$adminId&appId=${ApiConfig.appId}'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final pages = (data['pages'] is List) ? List.from(data['pages']) : <dynamic>[];

          Map<String, dynamic> pageProps = <String, dynamic>{};
          if (pages.isNotEmpty && pages.first is Map) {
            final propsRaw = (pages.first as Map)['properties'];
            if (propsRaw is Map) {
              pageProps = Map<String, dynamic>.from(propsRaw);
            }
          }

          List<Map<String, dynamic>> extractedWidgets = [];
          if (pages.isNotEmpty && pages.first is Map && (pages.first as Map)['widgets'] is List) {
            extractedWidgets = List<Map<String, dynamic>>.from((pages.first as Map)['widgets']);
          }

          List<Map<String, dynamic>> extractedProducts = [];
          for (final w in extractedWidgets) {
            final name = (w['name'] ?? '').toString();
            if (name == 'ProductGridWidget' || name == 'Catalog View Card' || name == 'Product Detail Card') {
              final props = w['properties'];
              if (props is Map && props['productCards'] is List) {
                extractedProducts.addAll(List<Map<String, dynamic>>.from(props['productCards']));
              }
            }
          }
          
          extractedWidgets.sort((a, b) {
            bool aIsHeader = a['name'] == 'HeaderWidget';
            bool bIsHeader = b['name'] == 'HeaderWidget';
            if (aIsHeader && !bIsHeader) return -1;
            if (!aIsHeader && bIsHeader) return 1;
            return 0;
          });

          final storeInfo = (data['storeInfo'] is Map) ? Map<String, dynamic>.from(data['storeInfo']) : <String, dynamic>{};
          final designSettings = (data['designSettings'] is Map)
              ? Map<String, dynamic>.from(data['designSettings'])
              : <String, dynamic>{};

          if (_mounted) {
            setState(() {
              _dynamicProductCards = extractedProducts.isNotEmpty ? extractedProducts : productCards;
              _filterProducts(_searchQuery);
              _homeWidgets = extractedWidgets;
              _dynamicStoreInfo = storeInfo;
              _dynamicDesignSettings = designSettings;
              _pageBackgroundColor = _colorFromHex(pageProps['backgroundColor']?.toString()) ?? Colors.white;
            });
          }
          print('✅ Loaded ${_dynamicProductCards.length} products from backend');
        }
      }
    } catch (e) {
      print('❌ Error loading dynamic data: $e');
      if (_mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _startRealTimeUpdates() async {
    final adminId = await AdminManager.getCurrentAdminId();
    if (adminId.isNotEmpty) {
      _appSync.connect(adminId: adminId, apiBase: dotenv.env['API_BASE'] ?? 'http://localhost:5000');
      
      _updateSubscription = _appSync.updates.listen((update) {
        if (!_mounted) return;
        
        final type = update['type']?.toString().toLowerCase();
        print('📱 Received real-time update: $type');
        
        switch (type) {
          case 'home-page':
          case 'dynamic-update':
            _loadDynamicData();
            break;
        }
      });
    }
  }

  void _onPageChanged(int index) {
    if (_mounted) {
      setState(() => _currentPageIndex = index);
    }
  }

  void _onItemTapped(int index) {
    if (_mounted) {
      setState(() {
        _currentPageIndex = index;
        if (index == 1) {
          _cartNotificationCount = 0;
        } else if (index == 2) {
          _wishlistNotificationCount = 0;
        }
      });
    }
    _pageController.jumpToPage(index);
  }

  void _filterProducts(String query) {
    if (_mounted) {
      setState(() {
        _searchQuery = query;
        if (query.isEmpty) {
          _filteredProducts = List.from(_dynamicProductCards);
        } else {
          _filteredProducts = _dynamicProductCards.where((product) {
            final productName = (product['productName'] ?? '').toString().toLowerCase();
            final price = (product['price'] ?? '').toString().toLowerCase();
            final discountPrice = (product['discountPrice'] ?? '').toString().toLowerCase();
            final searchLower = query.toLowerCase();
            return productName.contains(searchLower) || price.contains(searchLower) || discountPrice.contains(searchLower);
          }).toList();
        }
      });
    }
  }

  IconData _getIconData(String iconName) {
    switch (iconName) {
      case 'home':
        return Icons.home;
      case 'shopping_cart':
        return Icons.shopping_cart;
      case 'favorite':
        return Icons.favorite;
      case 'person':
        return Icons.person;
      default:
        return Icons.error;
    }
  }

  String _currencySymbolForProduct(Map<String, dynamic> product) {
    final String symbol = (product['currencySymbol'] ?? '').toString();
    if (symbol.isNotEmpty) return symbol;
    final String code = (product['currencyCode'] ?? '').toString();
    if (code.isNotEmpty) return PriceUtils.currencySymbolFromCode(code);
    return PriceUtils.detectCurrency((product['price'] ?? '').toString());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentPageIndex,
        children: [
          _buildHomePage(),
          _buildCartPage(),
          _buildWishlistPage(),
          _buildProfilePage(),
        ],
      ),
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }

  Widget _buildHomePage() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading...'),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadDynamicData,
      child: Container(
        color: _pageBackgroundColor,
        child: SingleChildScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: _homeWidgets.isNotEmpty
                ? _homeWidgets.map((w) => _buildHomeWidgetFromConfig(w)).toList()
                : <Widget>[
                    _buildHomeWidgetFromConfig({'name': 'HeaderWidget', 'properties': {}}),
                    _buildHomeWidgetFromConfig({'name': 'HeroBannerWidget', 'properties': {}}),
                    _buildHomeWidgetFromConfig({'name': 'ProductSearchBarWidget', 'properties': {}}),
                    _buildHomeWidgetFromConfig({'name': 'Catalog View Card', 'properties': {}}),
                    _buildHomeWidgetFromConfig({'name': 'StoreInfoWidget', 'properties': {}}),
                  ],
          ),
        ),
      ),
    );
  }

  Widget _buildHomeWidgetFromConfig(Map<String, dynamic> widgetData) {
    final name = (widgetData['name'] ?? '').toString();
    final props = widgetData['properties'] is Map
        ? Map<String, dynamic>.from(widgetData['properties'])
        : <String, dynamic>{};

    switch (name) {
      case 'HeaderWidget':
        final appName = (props['appName'] ?? _dynamicStoreInfo['storeName'] ?? 'My Store').toString();
        final logoAsset = (props['logoAsset'] ?? '').toString();
        final bg = (props['backgroundColor'] ?? _dynamicDesignSettings['headerColor'] ?? '#4fb322').toString();
        final backgroundColor = _colorFromHex(bg);
        final height = double.tryParse(props['height']?.toString() ?? '') ?? 60.0;
        final textColor = props['textColor'] != null ? _colorFromHex(props['textColor']) : Colors.white;
        final fontSize = double.tryParse(props['fontSize']?.toString() ?? '') ?? 16.0;
        final textAlign = (props['alignment'] ?? props['textAlign'] ?? 'left').toString();
        final logoHeight = double.tryParse(props['logoHeight']?.toString() ?? '') ?? 24.0;
        final logoWidth = double.tryParse(props['logoWidth']?.toString() ?? '') ?? 24.0;

        return Container(
          width: double.infinity,
          height: height,
          color: backgroundColor,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisAlignment: textAlign == 'center' ? MainAxisAlignment.center : 
                         textAlign == 'right' ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              if (textAlign != 'right')
                (logoAsset.isNotEmpty
                    ? (logoAsset.startsWith('data:image/')
                        ? Image.memory(
                            base64Decode(logoAsset.split(',')[1]),
                            width: logoWidth,
                            height: logoHeight,
                            fit: BoxFit.cover,
                          )
                        : Image.network(
                            logoAsset,
                            width: logoWidth,
                            height: logoHeight,
                            fit: BoxFit.cover,
                          ))
                    : const Icon(Icons.store, size: 24, color: Colors.white)),
              if (textAlign != 'right') const SizedBox(width: 6),
              Expanded(
                child: Text(
                  appName,
                  textAlign: textAlign == 'center' ? TextAlign.center : 
                           textAlign == 'right' ? TextAlign.right : TextAlign.left,
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.bold,
                    fontSize: fontSize,
                  ),
                ),
              ),
              if (textAlign == 'right') const SizedBox(width: 6),
              if (textAlign == 'right')
                (logoAsset.isNotEmpty
                    ? (logoAsset.startsWith('data:image/')
                        ? Image.memory(
                            base64Decode(logoAsset.split(',')[1]),
                            width: logoWidth,
                            height: logoHeight,
                            fit: BoxFit.cover,
                          )
                        : Image.network(
                            logoAsset,
                            width: logoWidth,
                            height: logoHeight,
                            fit: BoxFit.cover,
                          ))
                    : const Icon(Icons.store, size: 24, color: Colors.white)),
            ],
          ),
        );

      case 'HeroBannerWidget':
        final imageAsset = props['imageAsset'];
        final title = props['title'] ?? 'Welcome to Our Store!';
        final subtitle = props['subtitle'] ?? 'Shop the latest products';
        final buttonText = props['buttonText'] ?? 'Shop Now';
        final height = double.tryParse(props['height']?.toString() ?? '200') ?? 200.0;
        final backgroundColor = props['backgroundColor'] != null
            ? _colorFromHex(props['backgroundColor'])
            : Colors.blue;
        final buttonColor = props['buttonColor'] != null
            ? _colorFromHex(props['buttonColor'])
            : Colors.orange;
        final buttonTextColor = props['buttonTextColor'] != null
            ? _colorFromHex(props['buttonTextColor'])
            : Colors.white;
        final titleColor = props['titleColor'] != null
            ? _colorFromHex(props['titleColor'])
            : Colors.white;
        final subtitleColor = props['subtitleColor'] != null
            ? _colorFromHex(props['subtitleColor'])
            : Colors.white70;
        final alignment = props['alignment'] ?? 'center';
        final textAlign = props['textAlign'] ?? 'center';
        final showButton = props['showButton'] ?? true;
        final showSubtitle = props['showSubtitle'] ?? true;
        final borderRadiusValue = double.tryParse(props['borderRadius']?.toString() ?? '0') ?? 0.0;

        return Container(
          height: height,
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(borderRadiusValue),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(borderRadiusValue),
            child: Stack(
              children: [
                if (imageAsset != null)
                  Container(
                    width: double.infinity,
                    height: double.infinity,
                    child: imageAsset.toString().startsWith('data:image/')
                        ? Image.memory(
                            base64Decode(imageAsset.toString().split(',')[1]),
                            width: double.infinity,
                            height: double.infinity,
                            fit: BoxFit.cover,
                          )
                        : Image.network(
                            imageAsset,
                            width: double.infinity,
                            height: double.infinity,
                            fit: BoxFit.cover,
                          ),
                  ),
                Container(
                  width: double.infinity,
                  height: double.infinity,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.3),
                        Colors.black.withOpacity(0.5),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(borderRadiusValue),
                  ),
                ),
                Container(
                  width: double.infinity,
                  height: double.infinity,
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: alignment == 'top' ? MainAxisAlignment.start :
                                      alignment == 'bottom' ? MainAxisAlignment.end :
                                      MainAxisAlignment.center,
                    crossAxisAlignment: textAlign == 'left' ? CrossAxisAlignment.start :
                                    textAlign == 'right' ? CrossAxisAlignment.end :
                                    CrossAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        textAlign: textAlign == 'left' ? TextAlign.left :
                                  textAlign == 'right' ? TextAlign.right :
                                  TextAlign.center,
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: titleColor,
                        ),
                      ),
                      if (showSubtitle && subtitle.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          subtitle,
                          textAlign: textAlign == 'left' ? TextAlign.left :
                                    textAlign == 'right' ? TextAlign.right :
                                    TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            color: subtitleColor,
                          ),
                        ),
                      ],
                      if (showButton) ...[
                        const SizedBox(height: 20),
                        ElevatedButton(
                          onPressed: _scrollToProductGrid,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: buttonColor,
                            foregroundColor: buttonTextColor,
                            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(25),
                            ),
                          ),
                          child: Text(
                            buttonText,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );

      case 'ProductSearchBarWidget':
        final placeholder = props['placeholder'] ?? 'Search products';
        final height = double.tryParse(props['height']?.toString() ?? '50') ?? 50.0;
        final width = double.tryParse(props['width']?.toString() ?? '300') ?? 300.0;
        final borderRadius = double.tryParse(props['borderRadius']?.toString() ?? '25') ?? 25.0;
        final borderWidth = double.tryParse(props['borderWidth']?.toString() ?? '1') ?? 1.0;
        final iconColor = props['iconColor'] != null
            ? _colorFromHex(props['iconColor'])
            : Colors.grey.shade600;
        final textColor = props['textColor'] != null
            ? _colorFromHex(props['textColor'])
            : Colors.black;
        final borderColor = props['borderColor'] != null
            ? _colorFromHex(props['borderColor'])
            : Colors.grey.shade300;
        final backgroundColor = props['backgroundColor'] != null
            ? _colorFromHex(props['backgroundColor'])
            : Colors.white;

        return Container(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: width,
            height: height,
            child: TextField(
              onChanged: _filterProducts,
              style: TextStyle(color: textColor, fontSize: 14),
              decoration: InputDecoration(
                hintText: placeholder,
                hintStyle: TextStyle(color: textColor.withOpacity(0.6), fontSize: 14),
                prefixIcon: Icon(Icons.search, color: iconColor, size: 20),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(borderRadius),
                  borderSide: BorderSide(color: borderColor, width: borderWidth),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(borderRadius),
                  borderSide: BorderSide(color: borderColor, width: borderWidth),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(borderRadius),
                  borderSide: BorderSide(color: textColor, width: borderWidth),
                ),
                filled: true,
                fillColor: backgroundColor,
              ),
            ),
          ),
        );

      case 'Catalog View Card':
      case 'Product Detail Card':
        return _buildDynamicProductGrid(styleProps: props);

      case 'StoreInfoWidget':
        final storeName = ((props['storeName'] ?? _dynamicStoreInfo['storeName'])?.toString().trim() ?? '');
        final address = ((props['address'] ?? _dynamicStoreInfo['address'])?.toString().trim() ?? '');
        final email = ((props['email'] ?? _dynamicStoreInfo['email'])?.toString().trim() ?? '');
        final phone = ((props['phone'] ?? _dynamicStoreInfo['phone'])?.toString().trim() ?? '');
        final website = ((props['website'] ?? _dynamicStoreInfo['website'])?.toString().trim() ?? '');
        final footerText = ((props['footerText'] ?? _dynamicStoreInfo['footerText'])?.toString().trim() ?? '');
        final storeLogo = (props['storeLogo'] ?? _dynamicStoreInfo['storeLogo']);

        final textColor = props['textColor'] != null ? _colorFromHex(props['textColor']) : Colors.black;
        final iconColor = props['iconColor'] != null ? _colorFromHex(props['iconColor']) : Colors.blue;
        final backgroundColor = props['backgroundColor'] != null ? _colorFromHex(props['backgroundColor']) : const Color(0xFFE3F2FD);
        final borderRadius = double.tryParse(props['borderRadius']?.toString() ?? '') ?? 8.0;
        final marginV = double.tryParse(props['margin']?.toString() ?? '') ?? 4.0;
        final paddingV = double.tryParse(props['padding']?.toString() ?? '') ?? 16.0;

        return Container(
          width: double.infinity,
          margin: EdgeInsets.symmetric(horizontal: 8, vertical: marginV),
          child: Card(
            elevation: 2,
            color: backgroundColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(borderRadius)),
            child: Padding(
              padding: EdgeInsets.all(paddingV),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (storeLogo != null && storeLogo.toString().isNotEmpty)
                        storeLogo.toString().startsWith('data:image/')
                            ? Image.memory(
                                base64Decode(storeLogo.toString().split(',')[1]),
                                width: 48,
                                height: 48,
                                fit: BoxFit.cover,
                              )
                            : Image.network(
                                storeLogo,
                                width: 48,
                                height: 48,
                                fit: BoxFit.cover,
                              )
                      else
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.store, size: 24),
                        ),
                      const SizedBox(width: 12),
                      if (storeName.isNotEmpty)
                        Expanded(
                          child: Text(
                            storeName,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: textColor,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (address.isNotEmpty) ...[
                    Row(
                      children: [
                        Icon(Icons.location_on, color: iconColor, size: 16),
                        const SizedBox(width: 8),
                        Expanded(child: Text(address, style: TextStyle(fontSize: 12, color: textColor))),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (email.isNotEmpty) ...[
                    Row(
                      children: [
                        Icon(Icons.email, color: iconColor, size: 16),
                        const SizedBox(width: 8),
                        Expanded(child: Text(email, style: TextStyle(fontSize: 12, color: textColor))),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (phone.isNotEmpty) ...[
                    Row(
                      children: [
                        Icon(Icons.phone, color: iconColor, size: 16),
                        const SizedBox(width: 8),
                        Expanded(child: Text(phone, style: TextStyle(fontSize: 12, color: textColor))),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (website.isNotEmpty) ...[
                    Row(
                      children: [
                        Icon(Icons.language, color: iconColor, size: 16),
                        const SizedBox(width: 8),
                        Expanded(child: Text(website, style: TextStyle(fontSize: 12, color: textColor))),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 12),
                  if (footerText.isNotEmpty)
                    Center(
                      child: Text(
                        footerText,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 10,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );

      case 'ImageSliderWidget':
        final height = double.tryParse(props['height']?.toString() ?? '150') ?? 150.0;
        final width = double.tryParse(props['width']?.toString() ?? '300') ?? 300.0;
        final borderRadius = double.tryParse(props['borderRadius']?.toString() ?? '12') ?? 12.0;
        final autoPlay = props['autoPlay'] ?? true;
        final autoPlayInterval = int.tryParse(props['autoPlayInterval']?.toString() ?? '3') ?? 3;
        final showIndicators = props['showIndicators'] ?? true;
        
        List<Map<String, dynamic>> sliderImages = [];
        
        if (_homeWidgets.isNotEmpty) {
          for (var widget in _homeWidgets) {
            if (widget is Map && widget['name'] == 'ImageSliderWidget') {
              var widgetProps = widget['properties'] ?? {};
              if (widgetProps['sliderImages'] != null) {
                sliderImages = List<Map<String, dynamic>>.from(widgetProps['sliderImages']);
                break;
              }
            }
          }
        }
        
        if (sliderImages.isEmpty && props['sliderImages'] != null) {
          sliderImages = List<Map<String, dynamic>>.from(props['sliderImages']);
        }

        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (sliderImages.isNotEmpty)
                Column(
                  children: [
                    Container(
                      constraints: BoxConstraints(
                        maxWidth: width,
                        maxHeight: height + 20,
                      ),
                      child: CarouselSlider(
                        options: CarouselOptions(
                          height: height,
                          autoPlay: autoPlay,
                          autoPlayInterval: Duration(seconds: autoPlayInterval),
                          autoPlayAnimationDuration: const Duration(milliseconds: 800),
                          autoPlayCurve: Curves.fastOutSlowIn,
                          enlargeCenterPage: true,
                          scrollDirection: Axis.horizontal,
                          enableInfiniteScroll: true,
                          viewportFraction: 0.8,
                          enlargeFactor: 0.3,
                        ),
                        items: sliderImages.map((imageData) {
                          return Builder(
                            builder: (BuildContext context) {
                              return Container(
                                margin: const EdgeInsets.symmetric(horizontal: 5.0),
                                decoration: BoxDecoration(
                                  color: Colors.grey[300],
                                  borderRadius: BorderRadius.circular(borderRadius),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(borderRadius),
                                  child: imageData['imageAsset']?.isNotEmpty == true
                                      ? (imageData['imageAsset'].toString().startsWith('data:image/')
                                          ? Image.memory(
                                              base64Decode(imageData['imageAsset'].toString().split(',')[1]),
                                              width: double.infinity,
                                              height: height,
                                              fit: BoxFit.cover,
                                            )
                                          : Image.network(
                                              imageData['imageAsset'].toString(),
                                              width: double.infinity,
                                              height: height,
                                              fit: BoxFit.cover,
                                            ))
                                      : Container(
                                          color: Colors.grey[300],
                                          child: const Center(
                                            child: Icon(Icons.image, size: 40, color: Colors.grey),
                                          ),
                                        ),
                                ),
                              );
                            },
                          );
                        }).toList(),
                      ),
                    ),
                    if (showIndicators) ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: sliderImages.asMap().entries.map((entry) {
                          return Container(
                            width: 8.0,
                            height: 8.0,
                            margin: const EdgeInsets.symmetric(horizontal: 4.0),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.blue.withOpacity(0.5),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                )
              else
                Container(
                  height: height,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: Text('No images added to slider'),
                  ),
                ),
            ],
          ),
        );

      case 'ProductDescriptionWidget':
        final title = props['descriptionTitle'] ?? 'Description';
        final content = props['descriptionContent'] ?? '';
        final productImage = props['productImage'];

        final titleFontSize = double.tryParse(props['titleFontSize']?.toString() ?? '18') ?? 18.0;
        final contentFontSize = double.tryParse(props['contentFontSize']?.toString() ?? '14') ?? 14.0;
        final titleColor = props['titleColor'] != null
            ? _colorFromHex(props['titleColor'])
            : Colors.black;
        final contentColor = props['contentColor'] != null
            ? _colorFromHex(props['contentColor'])
            : Colors.grey.shade700;
        final backgroundColor = props['backgroundColor'] != null
            ? _colorFromHex(props['backgroundColor'])
            : Colors.white;

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Card(
            elevation: 2,
            color: backgroundColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: titleFontSize,
                      fontWeight: FontWeight.bold,
                      color: titleColor,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (productImage != null && productImage.toString().isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: productImage.toString().startsWith('data:image/')
                          ? Image.memory(
                              base64Decode(productImage.toString().split(',')[1]),
                              width: double.infinity,
                              height: 160,
                              fit: BoxFit.cover,
                            )
                          : Image.network(
                              productImage,
                              width: double.infinity,
                              height: 160,
                              fit: BoxFit.cover,
                            ),
                    ),
                  if (productImage != null && productImage.toString().isNotEmpty) 
                    const SizedBox(height: 12),
                  if (content.isNotEmpty)
                    Text(
                      content,
                      style: TextStyle(
                        fontSize: contentFontSize,
                        color: contentColor,
                        height: 1.5,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );

      case 'SmallCardWidget':
        final title = (props['title'] ?? 'Small Card').toString();
        final subtitle = (props['subtitle'] ?? 'Card subtitle').toString();
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          child: Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.blue.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.card_giftcard, color: Colors.blue),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        Text(
                          subtitle,
                          style: TextStyle(color: Colors.grey[600], fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildDynamicProductGrid({Map<String, dynamic>? styleProps}) {
    final products = _searchQuery.isEmpty ? _dynamicProductCards : _filteredProducts;

    final Map<String, dynamic> props = styleProps ?? const <String, dynamic>{};
    final Color gridBackgroundColor = _colorFromHex(props['backgroundColor']?.toString()) ?? Colors.transparent;

    if (products.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Column(
            children: const [
              Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text('No products available'),
              Text('Add products in admin panel to see them here'),
            ],
          ),
        ),
      );
    }

    return Container(
      key: _productGridKey,
      color: gridBackgroundColor == Colors.transparent ? null : gridBackgroundColor,
      padding: const EdgeInsets.all(16),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 0.68,
        ),
        itemCount: products.length,
        itemBuilder: (context, index) {
          final product = products[index];
          return _buildProductCard(product, index, styleProps: props);
        },
      ),
    );
  }

  Widget _buildProductCard(Map<String, dynamic> product, int index, {Map<String, dynamic>? styleProps}) {
    final String productId = 'product_$index';

    final String productName = product['productName'] ?? product['name'] ?? 'Product';

    final Map<String, dynamic> props = styleProps ?? const <String, dynamic>{};
    final Color cardBackgroundColor = _colorFromHex(props['cardBackgroundColor']?.toString()) ?? Colors.white;
    final Color borderColor = _colorFromHex(props['borderColor']?.toString()) ?? Colors.transparent;
    final Color priceColor = _colorFromHex(props['priceColor']?.toString()) ?? Colors.blue;
    final Color discountBadgeColor = _colorFromHex(props['discountBadgeColor']?.toString()) ?? Colors.redAccent;

    final String? priceField1 = product['price']?.toString();
    final String? priceField2 = product['basePrice']?.toString();
    final String? priceField3 = product['currentPrice']?.toString();
    final String? priceField4 = product['productPrice']?.toString();

    final String rawPrice = priceField1 ?? priceField2 ?? priceField3 ?? priceField4 ?? '99.99';
    final double basePrice = PriceUtils.parsePrice(rawPrice);
    final String currencySymbol = _currencySymbolForProduct(product);
    final double badgeDiscountPercent = double.tryParse((product['discountPercent'] ?? '0').toString()) ?? 0.0;
    final double manualDiscountPrice = PriceUtils.parsePrice(product['discountPrice']?.toString() ?? '0.00');
    final bool hasPercentDiscount = badgeDiscountPercent > 0;
    final double discountedPriceFromPercent = hasPercentDiscount ? basePrice * (1 - badgeDiscountPercent / 100) : 0.0;
    final double effectivePrice = hasPercentDiscount
        ? discountedPriceFromPercent
        : (manualDiscountPrice > 0 ? manualDiscountPrice : basePrice);
    final bool hasDiscount = hasPercentDiscount || (manualDiscountPrice > 0 && manualDiscountPrice < basePrice);
    final String? image = product['imageAsset'] ?? product['image'];
    final int quantityAvailable = int.tryParse((product['quantity'] ?? '10').toString()) ?? 10;
    final bool isSoldOut = quantityAvailable <= 0;
    final String discountLabel = hasPercentDiscount ? '${badgeDiscountPercent.toStringAsFixed(0)}% OFF' : 'OFFER';
    final bool isInWishlist = _wishlistManager.isInWishlist(productId);

    return Container(
      constraints: const BoxConstraints(minHeight: 320),
      child: Card(
        elevation: 4,
        color: cardBackgroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: borderColor, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: Stack(
                children: [
                  Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                      color: Colors.white,
                    ),
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                      child: image != null && image.isNotEmpty
                          ? (image.startsWith('data:image/')
                              ? Image.memory(
                                  base64Decode(image.split(',')[1]),
                                  width: double.infinity,
                                  height: double.infinity,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) => Container(
                                    color: Colors.grey[200],
                                    child: const Icon(Icons.image, size: 40, color: Colors.grey),
                                  ),
                                )
                              : Image.network(
                                  image,
                                  width: double.infinity,
                                  height: double.infinity,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) => Container(
                                    color: Colors.grey[200],
                                    child: const Icon(Icons.image, size: 40, color: Colors.grey),
                                  ),
                                ))
                          : Container(
                              color: Colors.grey[200],
                              child: const Icon(Icons.image, size: 40, color: Colors.grey),
                            ),
                    ),
                  ),
                  if (hasDiscount)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: discountBadgeColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          discountLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  if (isSoldOut)
                    Positioned(
                      bottom: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'SOLD OUT',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.9),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: IconButton(
                        onPressed: () {
                          if (isInWishlist) {
                            _wishlistManager.removeItem(productId);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Removed from wishlist')),
                            );
                          } else {
                            final wishlistItem = WishlistItem(
                              id: productId,
                              name: productName,
                              price: basePrice,
                              discountPrice: hasDiscount ? effectivePrice : 0.0,
                              image: image,
                              currencySymbol: currencySymbol,
                            );
                            _wishlistManager.addItem(wishlistItem);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Added to wishlist')),
                            );
                          }
                          if (_mounted) setState(() {});
                        },
                        icon: Icon(
                          isInWishlist ? Icons.favorite : Icons.favorite_border,
                          color: Colors.red,
                          size: 20,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.all(10.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      productName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '$currencySymbol${effectivePrice.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: priceColor,
                              ),
                            ),
                            const SizedBox(width: 4),
                            if (hasDiscount)
                              Text(
                                '$currencySymbol${basePrice.toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontSize: 11,
                                  decoration: TextDecoration.lineThrough,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Builder(
                      builder: (context) {
                        final currentQuantity = _cartManager.items
                            .where((item) => item.id == productId)
                            .fold(0, (sum, item) => sum + item.quantity);

                        if (isSoldOut) {
                          return Container(
                            height: 32,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade400),
                            ),
                            child: const Center(
                              child: Text(
                                'Out of Stock',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                          );
                        }

                        if (currentQuantity <= 0) {
                          return SizedBox(
                            width: double.infinity,
                            height: 32,
                            child: ElevatedButton(
                              onPressed: () {
                                final cartItem = CartItem(
                                  id: productId,
                                  name: productName,
                                  price: basePrice,
                                  discountPrice: hasDiscount ? effectivePrice : 0.0,
                                  image: image,
                                  currencySymbol: currencySymbol,
                                );
                                _cartManager.addItem(cartItem);
                                if (_mounted) setState(() {});
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Added to cart')),
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                elevation: 2,
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: const Text(
                                'Add to Cart',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                          );
                        }

                        return Container(
                          height: 32,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              IconButton(
                                onPressed: () {
                                  if (currentQuantity > 1) {
                                    _cartManager.updateQuantity(productId, currentQuantity - 1);
                                  } else {
                                    _cartManager.removeItem(productId);
                                  }
                                  if (_mounted) setState(() {});
                                },
                                icon: const Icon(Icons.remove, size: 16),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                              ),
                              Expanded(
                                child: Center(
                                  child: Text(
                                    currentQuantity.toString(),
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: () {
                                  if (currentQuantity < 10) {
                                    _cartManager.updateQuantity(productId, currentQuantity + 1);
                                    if (_mounted) setState(() {});
                                  }
                                },
                                icon: const Icon(Icons.add, size: 16),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _shareToPlatform(String platform, String link, String text) {
    print('Share to $platform: $link with text: $text');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Sharing to $platform...')),
    );
  }

  void _copyShareLink(String link) {
    print('Copy link: $link');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Link copied to clipboard!')),
    );
  }

  Color _colorFromHex(String? hexColor) {
    if (hexColor == null || hexColor.isEmpty) return Colors.blue;
    
    String formattedColor = hexColor.toUpperCase().replaceAll('#', '');
    
    if (formattedColor.length == 6) {
      formattedColor = 'FF$formattedColor';
    } else if (formattedColor.length == 8) {
      // Already has alpha
    } else {
      return Colors.blue;
    }
    
    try {
      return Color(int.parse('0x$formattedColor'));
    } catch (e) {
      print('Invalid color: $hexColor');
      return Colors.blue;
    }
  }

  Widget _buildCartPage() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Shopping Cart'),
      ),
      body: ListenableBuilder(
        listenable: _cartManager,
        builder: (context, child) {
          return _cartManager.items.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.shopping_cart_outlined, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text('Your cart is empty', style: TextStyle(fontSize: 18, color: Colors.grey)),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        itemCount: _cartManager.items.length,
                        itemBuilder: (context, index) {
                          final item = _cartManager.items[index];
                          return Card(
                            margin: const EdgeInsets.all(8),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  Container(
                                    width: 60,
                                    height: 60,
                                    color: Colors.grey[300],
                                    child: item.image != null && item.image!.isNotEmpty
                                        ? (item.image!.startsWith('data:image/')
                                            ? Image.memory(
                                                base64Decode(item.image!.split(',')[1]),
                                                width: 60,
                                                height: 60,
                                                fit: BoxFit.cover,
                                                errorBuilder: (context, error, stackTrace) => const Icon(Icons.image),
                                              )
                                            : Image.network(
                                                item.image!,
                                                width: 60,
                                                height: 60,
                                                fit: BoxFit.cover,
                                                errorBuilder: (context, error, stackTrace) => const Icon(Icons.image),
                                              ))
                                        : const Icon(Icons.image),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                        Text(
                                          PriceUtils.formatPrice(item.effectivePrice),
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.blue,
                                          ),
                                        ),
                                        if (item.discountPrice > 0 && item.price != item.discountPrice)
                                          Text(
                                            PriceUtils.formatPrice(item.price),
                                            style: TextStyle(
                                              fontSize: 14,
                                              decoration: TextDecoration.lineThrough,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      GestureDetector(
                                        onTap: () {
                                          if (item.quantity > 1) {
                                            _cartManager.updateQuantity(item.id, item.quantity - 1);
                                          } else {
                                            _cartManager.removeItem(item.id);
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(content: Text('Item removed from cart')),
                                            );
                                          }
                                        },
                                        child: Container(
                                          width: 32,
                                          height: 32,
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade200,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Icon(Icons.remove, size: 16, color: Colors.black87),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        decoration: BoxDecoration(
                                          border: Border.all(color: Colors.grey.shade300),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          item.quantity.toString(),
                                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      GestureDetector(
                                        onTap: () {
                                          if (_cartManager.totalQuantity < 10) {
                                            _cartManager.updateQuantity(item.id, item.quantity + 1);
                                          } else {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(
                                                content: Text('Only 10 products allowed'),
                                                backgroundColor: Colors.orange,
                                              ),
                                            );
                                          }
                                        },
                                        child: Container(
                                          width: 32,
                                          height: 32,
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade200,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Icon(Icons.add, size: 16, color: Colors.black87),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.all(16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Bill Summary',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Subtotal', style: TextStyle(fontSize: 14, color: Colors.grey)),
                                Text(PriceUtils.formatPrice(_cartManager.subtotal), style: const TextStyle(fontSize: 14, color: Colors.grey)),
                              ],
                            ),
                          ),
                          if (_cartManager.totalDiscount > 0)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Discount', style: TextStyle(fontSize: 14, color: Colors.grey)),
                                  Text('-${PriceUtils.formatPrice(_cartManager.totalDiscount)}', style: const TextStyle(fontSize: 14, color: Colors.green)),
                                ],
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('GST (18%)', style: TextStyle(fontSize: 14, color: Colors.grey)),
                                Text(PriceUtils.formatPrice(_cartManager.gstAmount), style: const TextStyle(fontSize: 14, color: Colors.grey)),
                              ],
                            ),
                          ),
                          const Divider(thickness: 1),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Total', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black)),
                                Text(PriceUtils.formatPrice(_cartManager.finalTotal), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.all(16),
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _handleBuyNow,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 4,
                        ),
                        child: const Text(
                          'Buy Now',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
        },
      ),
    );
  }

  Widget _buildWishlistPage() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wishlist'),
      ),
      body: _wishlistManager.items.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.favorite_border, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('Your wishlist is empty', style: TextStyle(fontSize: 18, color: Colors.grey)),
                ],
              ),
            )
          : ListView.builder(
              itemCount: _wishlistManager.items.length,
              itemBuilder: (context, index) {
                final item = _wishlistManager.items[index];
                return Card(
                  margin: const EdgeInsets.all(8),
                  child: ListTile(
                    leading: Container(
                      width: 50,
                      height: 50,
                      color: Colors.grey[300],
                      child: item.image != null && item.image!.isNotEmpty
                          ? (item.image!.startsWith('data:image/')
                              ? Image.memory(
                                  base64Decode(item.image!.split(',')[1]),
                                  width: 50,
                                  height: 50,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) => const Icon(Icons.image),
                                )
                              : Image.network(
                                  item.image!,
                                  width: 50,
                                  height: 50,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) => const Icon(Icons.image),
                                ))
                          : const Icon(Icons.image),
                    ),
                    title: Text(item.name),
                    subtitle: Text(PriceUtils.formatPrice(item.effectivePrice)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: () {
                            final cartItem = CartItem(
                              id: item.id,
                              name: item.name,
                              price: item.price,
                              discountPrice: item.discountPrice,
                              image: item.image,
                              currencySymbol: item.currencySymbol,
                            );
                            _cartManager.addItem(cartItem);
                            if (_mounted) {
                              setState(() {
                                _cartNotificationCount += 1;
                              });
                            }
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Added to cart')),
                            );
                          },
                          icon: const Icon(Icons.shopping_cart),
                        ),
                        IconButton(
                          onPressed: () {
                            _wishlistManager.removeItem(item.id);
                            if (_mounted) setState(() {});
                          },
                          icon: const Icon(Icons.delete, color: Colors.red),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildProfilePage() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircleAvatar(
                radius: 60,
                backgroundColor: Colors.grey,
                child: Icon(Icons.person, size: 60, color: Colors.white),
              ),
              const SizedBox(height: 20),
              FutureBuilder<Map<String, dynamic>>(
                future: _fetchUserProfile(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const CircularProgressIndicator();
                  }
                  if (snapshot.hasError) {
                    return const Text(
                      'User',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    );
                  }
                  final userData = snapshot.data ?? {};
                  final firstName = userData['firstName'] ?? '';
                  final lastName = userData['lastName'] ?? '';
                  final displayName = (firstName.isNotEmpty && lastName.isNotEmpty) 
                      ? '$firstName $lastName'
                      : (firstName.isNotEmpty ? firstName : (lastName.isNotEmpty ? lastName : 'User'));
                  
                  return Text(
                    displayName,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  );
                },
              ),
              const SizedBox(height: 15),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(250, 50),
                  side: const BorderSide(color: Colors.red),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SignInPage(),
                    ),
                    (route) => false,
                  );
                },
                child: const Text(
                  'Log Out',
                  style: TextStyle(fontSize: 18, color: Colors.red, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNavigationBar() {
    return BottomNavigationBar(
      currentIndex: _currentPageIndex,
      onTap: _onItemTapped,
      type: BottomNavigationBarType.fixed,
      selectedItemColor: Colors.blue,
      unselectedItemColor: Colors.grey,
      items: [
        const BottomNavigationBarItem(
          icon: Icon(Icons.home),
          label: 'Home',
        ),
        BottomNavigationBarItem(
          icon: Badge(
            label: Text('${_cartManager.items.length}'),
            isLabelVisible: _cartManager.items.length > 0,
            child: const Icon(Icons.shopping_cart),
          ),
          label: 'Cart',
        ),
        BottomNavigationBarItem(
          icon: Badge(
            label: Text('${_wishlistManager.items.length}'),
            isLabelVisible: _wishlistManager.items.length > 0,
            child: const Icon(Icons.favorite),
          ),
          label: 'Wishlist',
        ),
        const BottomNavigationBarItem(
          icon: Icon(Icons.person),
          label: 'Profile',
        ),
      ],
    );
  }

  Future<Map<String, dynamic>> _fetchUserProfile() async {
    try {
      final ApiService apiService = ApiService();
      final userProfile = await apiService.getUserProfile();
      return userProfile;
    } catch (e) {
      print('Error fetching user profile: $e');
      return {};
    }
  }
}
