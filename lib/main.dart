import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:local_auth/local_auth.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ====== إعدادات الاتصال بأودو ======
// عدّل اسم قاعدة البيانات (db) حسب إعداد شركتكم الفعلي في أودو
const String odooBaseUrl =
    'https://varietyit-al-muhaidib-sanitary-ceramics.odoo.com';
const String odooDb = 'varietyit-al-muhaidib-sanitary-ceramics';

void main() {
  runApp(const EnterpriseApp());
}

class EnterpriseApp extends StatelessWidget {
  const EnterpriseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'تطبيق المهيدب',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      locale: const Locale('ar'),
      home: const LoginScreen(),
    );
  }
}

// ====== خدمة الاتصال بأودو ======
class OdooService {
  static String? sessionId;
  static int? uid;

  /// تسجيل الدخول عبر JSON-RPC (Odoo standard endpoint)
  static Future<Map<String, dynamic>> login(
      String employeeId, String password) async {
    final url = Uri.parse('$odooBaseUrl/web/session/authenticate');
    final body = jsonEncode({
      "jsonrpc": "2.0",
      "method": "call",
      "params": {
        "db": odooDb,
        "login": employeeId,
        "password": password,
      }
    });

    final response = await http.post(
      url,
      headers: {"Content-Type": "application/json"},
      body: body,
    );

    final data = jsonDecode(response.body);
    if (data['result'] != null && data['result']['uid'] != null) {
      uid = data['result']['uid'];
      // استخراج session_id من الكوكيز
      final rawCookie = response.headers['set-cookie'];
      if (rawCookie != null) {
        final match = RegExp(r'session_id=([^;]+)').firstMatch(rawCookie);
        sessionId = match?.group(1);
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('employee_id', employeeId);
      if (sessionId != null) {
        await prefs.setString('session_id', sessionId!);
      }
      return {"success": true, "uid": uid};
    } else {
      return {
        "success": false,
        "error": data['error']?['data']?['message'] ?? "بيانات الدخول غير صحيحة"
      };
    }
  }

  /// استدعاء عام لأي موديل في أودو (call_kw)
  static Future<dynamic> callKw({
    required String model,
    required String method,
    required List args,
    Map<String, dynamic> kwargs = const {},
  }) async {
    final url = Uri.parse('$odooBaseUrl/web/dataset/call_kw');
    final body = jsonEncode({
      "jsonrpc": "2.0",
      "method": "call",
      "params": {
        "model": model,
        "method": method,
        "args": args,
        "kwargs": kwargs,
      }
    });

    final response = await http.post(
      url,
      headers: {
        "Content-Type": "application/json",
        if (sessionId != null) "Cookie": "session_id=$sessionId",
      },
      body: body,
    );

    final data = jsonDecode(response.body);
    if (data['error'] != null) {
      throw Exception(data['error']['data']?['message'] ?? 'خطأ في الاتصال');
    }
    return data['result'];
  }

  /// تسجيل حضور/انصراف عبر موديل hr.attendance
  static Future<bool> checkInOut(double lat, double lng) async {
    try {
      await callKw(
        model: 'hr.attendance',
        method: 'create',
        args: [
          {
            'check_in': DateTime.now().toUtc().toIso8601String(),
          }
        ],
      );
      return true;
    } catch (e) {
      return false;
    }
  }
}

// ====== شاشة تسجيل الدخول ======
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _idController = TextEditingController();
  final _passController = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _login() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final result =
        await OdooService.login(_idController.text.trim(), _passController.text);

    setState(() => _loading = false);

    if (result['success'] == true) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } else {
      setState(() => _error = result['error']);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.business, size: 80, color: Colors.blue),
                const SizedBox(height: 16),
                const Text('شركة المهيدب',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 32),
                TextField(
                  controller: _idController,
                  decoration: const InputDecoration(
                    labelText: 'الرقم الوظيفي',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.badge),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'كلمة المرور',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock),
                  ),
                ),
                const SizedBox(height: 24),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(_error!, style: const TextStyle(color: Colors.red)),
                  ),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _login,
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
                    child: _loading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('تسجيل الدخول'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ====== الشاشة الرئيسية ======
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  final _screens = const [AttendanceScreen(), BarcodeScreen()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تطبيق المهيدب')),
      body: _screens[_index],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.fingerprint), label: 'الحضور والانصراف'),
          BottomNavigationBarItem(
              icon: Icon(Icons.qr_code_scanner), label: 'فحص باركود'),
        ],
      ),
    );
  }
}

// ====== شاشة الحضور والانصراف ======
class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  final LocalAuthentication _auth = LocalAuthentication();
  String _status = 'جاهز لتسجيل الحضور';
  bool _loading = false;

  Future<Position?> _getLocation() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      setState(() => _status = 'تم رفض إذن الموقع');
      return null;
    }
    return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);
  }

  Future<void> _markAttendance() async {
    setState(() {
      _loading = true;
      _status = 'جاري التحقق من البصمة...';
    });

    try {
      final canCheck = await _auth.canCheckBiometrics;
      if (!canCheck) {
        setState(() => _status = 'الجهاز لا يدعم بصمة الإصبع');
        return;
      }

      final authenticated = await _auth.authenticate(
        localizedReason: 'تحقق من هويتك لتسجيل الحضور',
        options: const AuthenticationOptions(biometricOnly: true),
      );

      if (!authenticated) {
        setState(() => _status = 'فشل التحقق من البصمة');
        return;
      }

      setState(() => _status = 'جاري تحديد الموقع...');
      final position = await _getLocation();
      if (position == null) return;

      setState(() => _status = 'جاري إرسال البيانات إلى أودو...');
      final success =
          await OdooService.checkInOut(position.latitude, position.longitude);

      setState(() {
        _status = success
            ? 'تم تسجيل الحضور بنجاح ✅\n(${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)})'
            : 'فشل إرسال البيانات لأودو';
      });
    } catch (e) {
      setState(() => _status = 'خطأ: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.fingerprint, size: 100, color: Colors.blue),
            const SizedBox(height: 24),
            Text(_status, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 32),
            if (_loading)
              const CircularProgressIndicator()
            else
              ElevatedButton.icon(
                onPressed: _markAttendance,
                icon: const Icon(Icons.check),
                label: const Text('تسجيل حضور/انصراف'),
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
              ),
          ],
        ),
      ),
    );
  }
}

// ====== شاشة فحص الباركود ======
class BarcodeScreen extends StatefulWidget {
  const BarcodeScreen({super.key});

  @override
  State<BarcodeScreen> createState() => _BarcodeScreenState();
}

class _BarcodeScreenState extends State<BarcodeScreen> {
  String? _lastCode;
  final MobileScannerController _controller = MobileScannerController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    final barcode = capture.barcodes.first;
    final value = barcode.rawValue;
    if (value != null && value != _lastCode) {
      setState(() => _lastCode = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          flex: 4,
          child: MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
        ),
        Expanded(
          flex: 1,
          child: Center(
            child: Text(
              _lastCode == null
                  ? 'وجّه الكاميرا نحو الباركود'
                  : 'الباركود: $_lastCode',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }
}
