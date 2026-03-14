<<<<<<< HEAD
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:http/http.dart' as http;
import 'screens/payment_received.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
=======
import 'package:flutter/material.dart';

// Screens
import 'screens/auth_gate.dart';
import 'screens/home_screen.dart';
import 'screens/trending_page.dart';
import 'screens/qr_scan_page.dart';
import 'screens/transaction_history.dart';
>>>>>>> f3a655a4b2e76f0d0f740cc4824154709b492ccd
import 'screens/login_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';


<<<<<<< HEAD
const String server = "http://192.168.1.6:3000";



void main() {
  runApp(const CryptoPayApp());
}

class CryptoPayApp extends StatelessWidget {
  const CryptoPayApp({super.key});
=======
// Services


Future<void> main() async {
  /// REQUIRED for async + SharedPreferences
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final user = prefs.getString("user");

  /// Initialize demo balances ONCE
  //await LocalStorage.initDemoBalance();

  runApp(ClientPayApp(startLoggedIn: user != null));
}

class ClientPayApp extends StatelessWidget {
  final bool startLoggedIn;

  const ClientPayApp({super.key, required this.startLoggedIn});
>>>>>>> f3a655a4b2e76f0d0f740cc4824154709b492ccd

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
<<<<<<< HEAD
      title: 'Crypto Payment Terminal',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
      ),
      home: const LoginScreen(),
    );
  }
}

class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  Timer? paymentWatcher;
  double lastBalance = 0;
  final player = AudioPlayer();
  final FlutterTts tts = FlutterTts();

  Future<bool> checkPayment() async {
    final response = await http.get(
      Uri.parse("$server/balance/merchant1"),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);

      final received = data[_selectedCrypto] ?? 0;

      if (received > 0) {
        return true;
      }
    }

    return false;
  }

  // dropdown options
  final List<String> _cryptoOptions = ['ETH', 'BTC', 'USDT'];
  final List<String> _fiatOptions = ['USD', 'INR', 'EUR'];

  String _selectedCrypto = 'ETH';
  String _selectedFiat = 'USD';

  final TextEditingController _amountController = TextEditingController();

  double? _fiatAmount;
  double? _cryptoAmount;

  String? _paymentUri;

  // fallback demo rates – overwritten by live API
  final Map<String, Map<String, double>> _rates = {
    'ETH': {
      'USD': 3000.0,
      'INR': 250000.0,
      'EUR': 2700.0,
    },
    'BTC': {
      'USD': 50000.0,
      'INR': 4200000.0,
      'EUR': 47000.0,
    },
    'USDT': {
      'USD': 1.0,
      'INR': 83.0,
      'EUR': 0.92,
    },
  };

  // your merchant addresses
  final String _ethUsdtAddress = '0x4147Cbd2c64d809723D50C755C10328ef84CFe78';
  final String _btcAddress = 'bc1qp75rhfq0t89rym4huj7pr7zf4dvmpvn0mngtx9';

  bool _isFetching = false;
  DateTime? _lastUpdated;

  @override
  void initState() {
    super.initState();

    tts.setLanguage("en-US");
    tts.setSpeechRate(0.5);

    // load once at start
    fetchLiveRates();

    // auto refresh every 1 minute
    Timer.periodic(const Duration(minutes: 1), (timer) {
      fetchLiveRates();
    });
  }

  Future<void> logout() async {

    final prefs = await SharedPreferences.getInstance();

    await prefs.remove("merchant");

    if(!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
    );

  }

  Future<void> fetchLiveRates() async {
    if (_isFetching) return;
    setState(() => _isFetching = true);

    final url = Uri.parse(
      'https://api.coingecko.com/api/v3/simple/price'
          '?ids=bitcoin,ethereum,tether&vs_currencies=inr,usd,eur',
    );

    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        setState(() {
          _rates['BTC'] = {
            'INR': (data['bitcoin']['inr']).toDouble(),
            'USD': (data['bitcoin']['usd']).toDouble(),
            'EUR': (data['bitcoin']['eur']).toDouble(),
          };
          _rates['ETH'] = {
            'INR': (data['ethereum']['inr']).toDouble(),
            'USD': (data['ethereum']['usd']).toDouble(),
            'EUR': (data['ethereum']['eur']).toDouble(),
          };
          _rates['USDT'] = {
            'INR': (data['tether']['inr']).toDouble(),
            'USD': (data['tether']['usd']).toDouble(),
            'EUR': (data['tether']['eur']).toDouble(),
          };
          _lastUpdated = DateTime.now();
        });

        _showSnack("Live rates updated ✔");
      } else {
        _showSnack("Failed to fetch live rates ❌");
      }
    } catch (e) {
      _showSnack("Error fetching rates: $e");
    } finally {
      if (mounted) {
        setState(() => _isFetching = false);
      }
    }
  }

  void _generatePayment() {
    final txt = _amountController.text.trim();
    if (txt.isEmpty) {
      _showSnack('Enter an amount first');
      return;
    }

    final value = double.tryParse(txt);
    if (value == null || value <= 0) {
      _showSnack('Enter a valid positive number');
      return;
    }

    final selectedMap = _rates[_selectedCrypto];
    if (selectedMap == null) {
      _showSnack('Rate map missing for $_selectedCrypto');
      return;
    }

    final rate = selectedMap[_selectedFiat];
    if (rate == null || rate == 0) {
      _showSnack('Rate not available for $_selectedCrypto / $_selectedFiat');
      return;
    }

    final cryptoAmount = value / rate;

    setState(() {
      _fiatAmount = value;
      _cryptoAmount = double.parse(cryptoAmount.toStringAsFixed(6));

      _paymentUri = jsonEncode({
        "merchant": "merchant1",
        "crypto": _selectedCrypto,
        "amount": _cryptoAmount,
        "fiat": _selectedFiat
      });
      startWatchingPayment();
    });

  }
  void startWatchingPayment() async {

    final response = await http.get(
      Uri.parse("$server/balance/merchant1"),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      lastBalance = data[_selectedCrypto] ?? 0;
    }

    paymentWatcher?.cancel();

    paymentWatcher = Timer.periodic(const Duration(seconds: 3), (timer) async {

      final response = await http.get(
        Uri.parse("$server/balance/merchant1"),
      );

      if (response.statusCode == 200) {

        final data = jsonDecode(response.body);
        final balance = data[_selectedCrypto] ?? 0;

        if (balance > lastBalance) {

          await tts.speak("Payment received. ${_cryptoAmount} ${_selectedCrypto}");
          await player.play(AssetSource('sounds/payment_success.mp3'));

          timer.cancel();

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PaymentReceivedScreen(
                crypto: _selectedCrypto,
                amount: _cryptoAmount!,
                fiat: _selectedFiat,
              ),
            ),
          );
        }

        lastBalance = balance;
      }

    });
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  @override
  void dispose() {
    paymentWatcher?.cancel();
    _amountController.dispose();
    super.dispose();
  }

  String _formatLastUpdated() {
    if (_lastUpdated == null) return 'Never';
    final t = _lastUpdated!;
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final currentRate = _rates[_selectedCrypto]?[_selectedFiat];

    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    // Header
                    Row(
                      children: [
                        const Icon(Icons.qr_code_2, size: 32),
                        const SizedBox(width: 8),
                        const Text(
                          'CryptoPay Merchant Terminal',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.logout),
                          tooltip: "Logout",
                          onPressed: logout,
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.indigo.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            children: [
                              if (_isFetching)
                                const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              else
                                const Icon(Icons.wifi_tethering, size: 16),
                              const SizedBox(width: 6),
                              Text(
                                'Live rates • ${_formatLastUpdated()}',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),
                    const Divider(),
                    const SizedBox(height: 8),

                    // Main content: left form, right QR
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // LEFT: form
                          Expanded(
                            flex: 3,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Payment Details',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 16),

                                // labels + inputs
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // labels column
                                    const Expanded(
                                      flex: 2,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          SizedBox(height: 8),
                                          Text('Select Crypto:'),
                                          SizedBox(height: 24),
                                          Text('Select Fiat Currency:'),
                                          SizedBox(height: 24),
                                          Text('Enter Amount:'),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),

                                    // inputs
                                    Expanded(
                                      flex: 4,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          // crypto dropdown
                                          DropdownButtonFormField<String>(
                                            value: _selectedCrypto,
                                            items: _cryptoOptions
                                                .map(
                                                  (c) => DropdownMenuItem(
                                                value: c,
                                                child: Text(c),
                                              ),
                                            )
                                                .toList(),
                                            onChanged: (v) {
                                              if (v != null) {
                                                setState(() => _selectedCrypto = v);
                                              }
                                            },
                                            decoration: const InputDecoration(
                                              border: OutlineInputBorder(),
                                              isDense: true,
                                            ),
                                          ),
                                          const SizedBox(height: 16),

                                          // fiat dropdown
                                          DropdownButtonFormField<String>(
                                            value: _selectedFiat,
                                            items: _fiatOptions
                                                .map(
                                                  (f) => DropdownMenuItem(
                                                value: f,
                                                child: Text(f),
                                              ),
                                            )
                                                .toList(),
                                            onChanged: (v) {
                                              if (v != null) {
                                                setState(() => _selectedFiat = v);
                                              }
                                            },
                                            decoration: const InputDecoration(
                                              border: OutlineInputBorder(),
                                              isDense: true,
                                            ),
                                          ),
                                          const SizedBox(height: 16),

                                          // amount + button
                                          Row(
                                            children: [
                                              Expanded(
                                                child: TextField(
                                                  controller: _amountController,
                                                  keyboardType:
                                                  const TextInputType.numberWithOptions(
                                                    decimal: true,
                                                  ),
                                                  decoration: const InputDecoration(
                                                    border: OutlineInputBorder(),
                                                    isDense: true,
                                                    prefixText: 'Amount ',
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              ElevatedButton.icon(
                                                onPressed: _generatePayment,
                                                icon: const Icon(Icons.qr_code),
                                                label: const Text('Generate QR'),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 20),

                                // current rate + summary
                                if (currentRate != null)
                                  Text(
                                    '1 $_selectedCrypto ≈ '
                                        '${currentRate.toStringAsFixed(2)} $_selectedFiat',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Colors.black54,
                                    ),
                                  ),
                                const SizedBox(height: 8),

                                if (_fiatAmount != null && _cryptoAmount != null)
                                  Text(
                                    '$_selectedFiat ${_fiatAmount!.toStringAsFixed(2)}'
                                        '  →  $_cryptoAmount $_selectedCrypto',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                const SizedBox(height: 20),

                                if (_cryptoAmount != null)
                                  const Padding(
                                    padding: EdgeInsets.only(top: 12),
                                    child: Text(
                                      "Waiting for customer payment...",
                                      style: TextStyle(color: Colors.grey),
                                    ),
                                  ),

                              ],
                            ),
                          ),

                          const SizedBox(width: 24),

                          // RIGHT: QR panel
                          Expanded(
                            flex: 2,
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.grey[50],
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.grey.shade300,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  const Text(
                                    'Payment QR',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Expanded(
                                    child: Center(
                                      child: _paymentUri == null
                                          ? const Text(
                                        'QR will appear here after you\ngenerate a payment.',
                                        textAlign: TextAlign.center,
                                      )
                                          : QrImageView(
                                        data: _paymentUri!,
                                        version: QrVersions.auto,
                                        size: 220,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Customer can scan this using\nTrust Wallet or any crypto wallet.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ],
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
      ),
=======
      title: "CryptoPay Client Wallet",
      debugShowCheckedModeBanner: false,



      theme: ThemeData(
        colorSchemeSeed: Colors.teal,
        useMaterial3: true,
      ),

      /// First screen → biometric gate
      home: const AuthGate(),

      /// Named routes
      routes: {
        '/login': (_) => const LoginScreen(),
        '/home': (_) => const HomeScreen(),
        '/trending': (_) => const TrendingPage(),
        '/scan': (_) => const QRScanPage(),
        '/history': (_) => const TransactionHistory(),
      },
>>>>>>> f3a655a4b2e76f0d0f740cc4824154709b492ccd
    );
  }
}
