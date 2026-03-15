import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';
import '../config/server_config.dart';
import '../services/network_availability_service.dart';
import '../services/offline_server_service.dart';
import 'payment_received.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'login_screen.dart';
import 'transaction_history.dart';



class MerchantHome extends StatefulWidget {
  const MerchantHome({super.key});

  @override
  State<MerchantHome> createState() => _MerchantHomeState();
}

class _MerchantHomeState extends State<MerchantHome> {


  final TextEditingController amountController = TextEditingController();
  final FlutterTts tts = FlutterTts();

  Timer? watcher;

  bool processingPayment = false;

  String merchantUsername = "merchant1";

  Future<void> loadMerchant() async {
    final prefs = await SharedPreferences.getInstance();
    merchantUsername = prefs.getString("user") ?? "merchant1";
  }

  Future<void> initMerchant() async {

    await loadMerchant(); // ensure merchant is loaded first

    fetchRates();
    Timer.periodic(const Duration(seconds: 30), (_) => fetchRates());
  }

  String crypto = "ETH";
  String fiat = "INR";

  String? qrData;
  double? cryptoAmount;

  Map<String,double> rates = {};
  String lastUpdated = "";

  bool offlineMode = false;
  bool _offlinePaymentShowing = false;
  List<ConnectivityResult> _connectivity = [ConnectivityResult.none];
  bool _clientHotspotReachable = false;
  bool _isOnline = false; // assume offline until proven; avoids API calls on startup when no internet
  Timer? _internetCheckTimer;
  Timer? _offlineServerPollTimer;
  bool _offlineServerHealthy = false;
  int _offlineTxCount = 0;
  Map<String, dynamic>? _offlineWallet;
  final Set<String> _seenOfflineTxIds = <String>{};
  DateTime? _lastOfflineSyncAt;

  Future<void> setupTTS() async {
    await tts.setLanguage("en-US");
    await tts.setSpeechRate(0.6);
    await tts.setPitch(2.2);

    await tts.setVoice({
      "name": "en-us-x-sfg#female_1-local",
      "locale": "en-US"
    });
  }



  Future<void> fetchRates() async {
    if (!_isOnline || offlineMode) return;

    try {
      final res = await http
          .get(
            Uri.parse(
                "https://api.coingecko.com/api/v3/simple/price?ids=bitcoin,ethereum,tether&vs_currencies=inr"),
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>?;
      if (data == null) return;
      final bitcoin = data["bitcoin"];
      final ethereum = data["ethereum"];
      final tether = data["tether"];
      if (bitcoin == null || ethereum == null || tether == null) return;

      final now = DateTime.now();
      if (mounted) {
        setState(() {
          rates["BTC"] = (bitcoin["inr"] as num).toDouble();
          rates["ETH"] = (ethereum["inr"] as num).toDouble();
          rates["USDT"] = (tether["inr"] as num).toDouble();
          lastUpdated =
              "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
        });
      }
    } catch (e) {
      if (kDebugMode) debugPrint("Price fetch error: $e");
      if (mounted) setState(() {});
    }
  }

  /// Manual refresh: re-check internet and fetch rates. Stays on current page.
  Future<void> _onRefresh() async {
    await _updateInternetStatus();
    await fetchRates();
    if (!mounted) return;
    setState(() {});
    if (!_isOnline || rates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Live rates unavailable. Working in offline mode."),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  final Map<String,double> fiatRates = {
    "INR":1,
    "USD":0.012,
    "EUR":0.011
  };

  Future<void> _updateInternetStatus() async {
    final online = await NetworkAvailabilityService.hasInternet();
    if (mounted && _isOnline != online) setState(() => _isOnline = online);
  }

  @override
  void initState()  {
    super.initState();
    setupTTS();
    initMerchant();
    startWatching();
    Connectivity().checkConnectivity().then((r) {
      if (mounted) setState(() => _connectivity = r);
    });
    Connectivity().onConnectivityChanged.listen((r) {
      if (mounted) {
        setState(() {
          _connectivity = r;
          _clientHotspotReachable = offlineMode && _hasLocalNetworkLink();
        });
      }
    });
    // Check actual internet (backend reachable); gate API calls on this
    _updateInternetStatus();
    _internetCheckTimer = Timer.periodic(const Duration(seconds: 25), (_) => _updateInternetStatus());
  }

  void _onOfflinePaymentReceived(Map<String, dynamic> tx) {
    if (_offlinePaymentShowing || !mounted) return;
    _offlinePaymentShowing = true;
    final amount = (tx["amount"] as num?)?.toDouble() ?? 0.0;
    final token = tx["token"] as String? ?? "ETH";
    final from = tx["from_user_id"] ?? tx["from"] ?? "Client Wallet";
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PaymentReceivedScreen(
          crypto: token,
          amount: amount,
          fiat: fiat,
          isOfflineMode: true,
          from: from?.toString(),
        ),
      ),
    ).then((_) {
      _offlinePaymentShowing = false;
    });
  }

  void startWatching() {

    watcher = Timer.periodic(
      const Duration(seconds:2),
          (_) => checkPayment(),
    );

  }

  Future<void> checkPayment() async {

    if (processingPayment) return;
    if (!_isOnline || offlineMode) return;

    try {
      final res = await http
          .get(
            Uri.parse("${ServerConfig.baseUrl}/last-payment?time=${DateTime.now().millisecondsSinceEpoch}"),
            headers: {
              "Cache-Control": "no-cache",
              "Pragma": "no-cache",
            },
          )
          .timeout(const Duration(seconds: 8));

      if (res.statusCode != 200) return;

      final data = jsonDecode(res.body) as Map<String, dynamic>?;
      if (data == null || data["receiver"] != merchantUsername) return;

      processingPayment = true;

      final amount = (data["amount"] as num?)?.toDouble() ?? 0.0;
      final token = data["token"] as String? ?? "ETH";

      await tts.speak("Payment received ${amount.toStringAsFixed(4)} $token");

      if(!mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PaymentReceivedScreen(
            crypto: token,
            amount: amount,
            fiat: fiat,
          ),
        ),
      );

      await http
          .post(Uri.parse("${ServerConfig.baseUrl}/clear-payment"))
          .timeout(const Duration(seconds: 5));

      setState(() {
        qrData = null;
        cryptoAmount = null;
        amountController.clear();
      });

      processingPayment = false;

    } catch (e) {
      if (kDebugMode) debugPrint("Merchant checkPayment: $e");
      processingPayment = false;
    }

  }

  Future<void> logout() async {

    final prefs = await SharedPreferences.getInstance();

    await prefs.remove("user"); // remove login user

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
    );

  }

  bool _hasLocalNetworkLink() {
    final hasNetworkAdapter = _connectivity.any(
      (c) => c == ConnectivityResult.wifi || c == ConnectivityResult.ethernet,
    );
    return hasNetworkAdapter;
  }

  void _startOfflineServerPolling() {
    _offlineServerPollTimer?.cancel();
    _refreshOfflineServerData();
    _offlineServerPollTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _refreshOfflineServerData(),
    );
  }

  void _stopOfflineServerPolling() {
    _offlineServerPollTimer?.cancel();
    _offlineServerPollTimer = null;
    if (mounted) {
      setState(() {
        _offlineServerHealthy = false;
        _offlineTxCount = 0;
        _offlineWallet = null;
      });
    }
  }

  Future<void> _refreshOfflineServerData() async {
    if (!offlineMode) return;
    final healthy = await MerchantOfflineServerService.health();
    if (_isOnline && healthy) {
      final now = DateTime.now();
      if (_lastOfflineSyncAt == null ||
          now.difference(_lastOfflineSyncAt!) > const Duration(seconds: 20)) {
        _lastOfflineSyncAt = now;
        await MerchantOfflineServerService.syncNow();
      }
    }
    final wallet = await MerchantOfflineServerService.getOfflineWallet(merchantUsername);
    final txs = await MerchantOfflineServerService.getOfflineTransactions(merchantId: merchantUsername);

    if (mounted) {
      setState(() {
        _offlineServerHealthy = healthy;
        _offlineWallet = wallet;
        _offlineTxCount = txs.length;
      });
    }

    for (final tx in txs) {
      final txId = tx["tx_id"]?.toString();
      if (txId == null || txId.isEmpty || _seenOfflineTxIds.contains(txId)) continue;
      _seenOfflineTxIds.add(txId);
      _onOfflinePaymentReceived({
        "amount": tx["amount"],
        "token": tx["token"],
        "from": tx["from_user_id"],
        "from_user_id": tx["from_user_id"],
      });
      break;
    }
  }

  Future<void> toggleOfflineMode(bool value) async {
    setState(() => offlineMode = value);
    if (value) {
      if (mounted) {
        setState(() => _clientHotspotReachable = _hasLocalNetworkLink());
      }
      // Seed seen IDs with current offline server txs so we don't show old transactions as "new"
      try {
        final existing = await MerchantOfflineServerService.getOfflineTransactions(merchantId: merchantUsername);
        if (mounted) {
          setState(() {
            for (final tx in existing) {
              final id = tx["tx_id"]?.toString() ?? tx["txId"]?.toString();
              if (id != null && id.isNotEmpty) _seenOfflineTxIds.add(id);
            }
          });
        }
      } catch (_) {}
      _startOfflineServerPolling();
    } else {
      _stopOfflineServerPolling();
      setState(() {
        _clientHotspotReachable = false;
      });
      if (qrData != null) {
        qrData = null;
        cryptoAmount = null;
      }
    }
  }

  Widget _buildConnectivityStatus() {
    final hasWlan = _hasLocalNetworkLink();
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(hasWlan ? Icons.wifi : Icons.wifi_off, size: 14, color: hasWlan ? Colors.green : Colors.grey),
            const SizedBox(width: 4),
            Text("WLAN: ${hasWlan ? "Connected" : "None"}", style: TextStyle(fontSize: 11, color: hasWlan ? Colors.green : Colors.grey)),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_clientHotspotReachable ? Icons.link : Icons.link_off, size: 14, color: _clientHotspotReachable ? Colors.green : Colors.orange),
            const SizedBox(width: 4),
            Text(
              _clientHotspotReachable
                  ? "Customer hotspot: Connected (offline-ready)"
                  : "Customer hotspot: Not connected",
              style: TextStyle(fontSize: 11, color: _clientHotspotReachable ? Colors.green : Colors.orange),
            ),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_isOnline ? Icons.cloud_done : Icons.cloud_off, size: 14, color: _isOnline ? Colors.green : Colors.orange),
            const SizedBox(width: 4),
            Text(_isOnline ? "Internet: Available" : "Internet: Offline", style: TextStyle(fontSize: 11, color: _isOnline ? Colors.green : Colors.orange)),
          ],
        ),
        if (offlineMode)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_offlineServerHealthy ? Icons.dns : Icons.dns_outlined, size: 14, color: _offlineServerHealthy ? Colors.green : Colors.orange),
              const SizedBox(width: 4),
              Text(
                _offlineServerHealthy
                    ? "Offline server: Connected ($_offlineTxCount tx)"
                    : "Offline server: Not reachable (localhost:3001)",
                style: TextStyle(fontSize: 11, color: _offlineServerHealthy ? Colors.green : Colors.orange),
              ),
            ],
          ),
      ],
    );
  }

  Future<void> generateQR() async {

    if(amountController.text.isEmpty) return;

    double fiatAmount = double.parse(amountController.text);

    double cryptoRate = rates[crypto] ?? 0;

    if (cryptoRate == 0 && _isOnline && !offlineMode) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Fetching live crypto prices...")),
      );
      return;
    }
    double fiatRate = fiatRates[fiat]!;
    if (cryptoRate == 0) cryptoRate = 1;

    cryptoAmount = (fiatAmount / fiatRate) / cryptoRate;

    final payload = {
      "merchant": merchantUsername,
      "crypto": crypto,
      "amount": cryptoAmount
    };
    if (offlineMode) {
      // Merchant web offline mode uses local offline server on 3001.
      payload["port"] = 3001;
      payload["mode"] = "offline_server";
    }

    qrData = jsonEncode(payload);

    setState(() {});
  }

  @override
  void dispose() {
    watcher?.cancel();
    _internetCheckTimer?.cancel();
    _offlineServerPollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      backgroundColor: Colors.grey[100],

      body: Center(
        child: Card(
          elevation:6,
          shape:RoundedRectangleBorder(
            borderRadius:BorderRadius.circular(16),
          ),

          child: SizedBox(
            width:900,
            height:520,

            child: Padding(
              padding:const EdgeInsets.all(24),

              child:Column(
                children:[

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [

                      Row(
                        children: const [
                          Icon(Icons.qr_code_2, size: 32),
                          SizedBox(width: 8),
                          Text(
                            "CryptoPay Merchant Terminal",
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),

                      Row(
                        children: [

                          const Icon(
                            Icons.circle,
                            color: Colors.red,
                            size: 10,
                          ),

                          const SizedBox(width: 6),

                          const Text(
                            "LIVE",
                            style: TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),

                          const SizedBox(width: 6),

                          Text(
                            lastUpdated,
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                            ),
                          ),

                          const SizedBox(width: 12),

                          IconButton(
                            icon: const Icon(Icons.refresh),
                            tooltip: "Refresh (rates & data)",
                            onPressed: () => _onRefresh(),
                          ),

                          IconButton(
                            icon: const Icon(Icons.history),
                            tooltip: "Transaction History",
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const TransactionHistory()),
                              );
                            },
                          ),

                          const SizedBox(width: 8),

                          IconButton(
                            icon: const Icon(Icons.logout),
                            tooltip: "Logout",
                            onPressed: logout,
                          ),

                        ],
                      ),

                    ],
                  ),

                  const SizedBox(height:20),
                  const Divider(),
                  if (!_isOnline)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Material(
                        color: Colors.amber.shade100,
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Row(
                            children: const [
                              Icon(Icons.cloud_off, color: Colors.amber, size: 20),
                              SizedBox(width: 8),
                              Text(
                                "Live rates unavailable. Working in offline mode.",
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (!_isOnline) const SizedBox(height: 8),
                  const SizedBox(height:20),

                  Expanded(
                    child:Row(
                      children:[

                        Expanded(
                          child:SingleChildScrollView(
                            child:Column(
                              crossAxisAlignment:CrossAxisAlignment.start,
                              children:[

                                const Text(
                                  "Payment Details",
                                  style:TextStyle(
                                    fontSize:18,
                                    fontWeight:FontWeight.w600,
                                  ),
                                ),

                                Row(
                                  children: [
                                    const Text("Offline mode (customer hotspot)"),
                                    const SizedBox(width: 8),
                                    Switch(
                                      value: offlineMode,
                                      onChanged: toggleOfflineMode,
                                    ),
                                  ],
                                ),
                                if (offlineMode) ...[
                                  _buildConnectivityStatus(),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          _offlineServerHealthy
                                              ? "Offline server ready at localhost:3001."
                                              : "Offline mode active. Start offline-server.js on merchant system (localhost:3001).",
                                          style: TextStyle(fontSize: 12, color: _offlineServerHealthy ? Colors.green : Colors.orange),
                                        ),
                                      ),
                                      TextButton.icon(
                                        onPressed: () async {
                                          await _refreshOfflineServerData();
                                          if (mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  _offlineServerHealthy
                                                      ? "Offline server reachable."
                                                      : "Offline server not reachable. Ensure localhost:3001 is running.",
                                                ),
                                                duration: const Duration(seconds: 3),
                                              ),
                                            );
                                          }
                                        },
                                        icon: const Icon(Icons.refresh, size: 18),
                                        label: const Text("Refresh Offline Server"),
                                      ),
                                    ],
                                  ),
                                  if (_offlineWallet != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      "Offline wallet - BTC: ${((_offlineWallet!["balances"] as Map<String, dynamic>?)?["BTC"] ?? 0)} | "
                                      "ETH: ${((_offlineWallet!["balances"] as Map<String, dynamic>?)?["ETH"] ?? 0)} | "
                                      "USDT: ${((_offlineWallet!["balances"] as Map<String, dynamic>?)?["USDT"] ?? 0)}",
                                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                                    ),
                                  ],
                                ],
                                const SizedBox(height: 12),

                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [

                                    const Text("Select Crypto"),

                                    if(lastUpdated.isNotEmpty)
                                      Text(
                                        "Updated: $lastUpdated",
                                        style: const TextStyle(
                                          color: Colors.grey,
                                          fontSize: 12,
                                        ),
                                      ),

                                  ],
                                ),

                                DropdownButton<String>(
                                  value: crypto,
                                  items: const [
                                    DropdownMenuItem(value:"ETH",child:Text("ETH")),
                                    DropdownMenuItem(value:"BTC",child:Text("BTC")),
                                    DropdownMenuItem(value:"USDT",child:Text("USDT")),
                                  ],
                                  onChanged:(v){
                                    setState(()=>crypto=v!);
                                  },
                                ),

                                const SizedBox(height:8),

                                if (rates.containsKey(crypto))
                                  Text(
                                    "1 $crypto = ₹${rates[crypto]!.toStringAsFixed(2)}",
                                    style: const TextStyle(
                                      color: Colors.grey,
                                      fontSize: 14,
                                    ),
                                  ),



                                const SizedBox(height:20),

                                const Text("Select Fiat Currency"),

                                DropdownButton<String>(
                                  value:fiat,
                                  items:const[
                                    DropdownMenuItem(value:"INR",child:Text("INR")),
                                    DropdownMenuItem(value:"USD",child:Text("USD")),
                                    DropdownMenuItem(value:"EUR",child:Text("EUR")),
                                  ],
                                  onChanged:(v){
                                    setState(()=>fiat=v!);
                                  },
                                ),

                                const SizedBox(height:20),

                                const Text("Enter Amount"),

                                TextField(
                                  controller:amountController,
                                  keyboardType:TextInputType.number,
                                  decoration:const InputDecoration(
                                    border:OutlineInputBorder(),
                                  ),
                                ),

                                const SizedBox(height:20),

                                ElevatedButton.icon(
                                  onPressed:generateQR,
                                  icon:const Icon(Icons.qr_code),
                                  label:const Text("Generate QR"),
                                ),

                                const SizedBox(height:20),

                                if(cryptoAmount!=null)
                                  Text(
                                    "$fiat ${amountController.text} → ${cryptoAmount!.toStringAsFixed(6)} $crypto",
                                    style:const TextStyle(
                                      fontSize:16,
                                      fontWeight:FontWeight.bold,
                                    ),
                                  )

                              ],
                            ),
                          ),
                        ),

                        const SizedBox(width:30),

                        Expanded(
                          child:Container(
                            padding:const EdgeInsets.all(20),
                            decoration:BoxDecoration(
                              color:Colors.grey[50],
                              borderRadius:BorderRadius.circular(16),
                              border:Border.all(color:Colors.grey.shade300),
                            ),

                            child:Column(
                              children:[

                                const Text(
                                  "Payment QR",
                                  style:TextStyle(
                                    fontSize:16,
                                    fontWeight:FontWeight.w600,
                                  ),
                                ),

                                const SizedBox(height:20),

                                Expanded(
                                  child:Center(
                                    child:qrData==null
                                        ? const Text(
                                      "QR will appear here\nonce generated",
                                      textAlign:TextAlign.center,
                                    )
                                        : QrImageView(
                                      data:qrData!,
                                      size:220,
                                    ),
                                  ),
                                ),

                                const SizedBox(height:10),

                                const Text(
                                  "Customer scans this QR\nusing the CryptoPay wallet",
                                  textAlign:TextAlign.center,
                                  style:TextStyle(fontSize:12),
                                ),

                              ],
                            ),
                          ),
                        )

                      ],
                    ),
                  )

                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}