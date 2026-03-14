import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';
import '../config/server_config.dart';
import '../services/local_payment_server.dart';
import '../services/local_ip_helper.dart';
import '../services/network_availability_service.dart';
import 'payment_received.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'login_screen.dart';



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
  String? localIp;
  bool _offlinePaymentShowing = false;
  Timer? _offlineIpRefreshTimer;
  List<ConnectivityResult> _connectivity = [ConnectivityResult.none];
  bool _clientHotspotReachable = false;
  String? _clientHotspotIp;
  DateTime? _lastHotspotSubnetScanAt;
  bool _isDiscoveringClient = false;
  bool _isOnline = false; // assume offline until proven; avoids API calls on startup when no internet
  Timer? _internetCheckTimer;

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
    if (!_isOnline) return;

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
    LocalPaymentServer.onPaymentReceived = _onOfflinePaymentReceived;
    Connectivity().checkConnectivity().then((r) {
      if (mounted) setState(() => _connectivity = r);
    });
    Connectivity().onConnectivityChanged.listen((r) {
      if (mounted) setState(() => _connectivity = r);
      if (offlineMode) {
        _refreshOfflineIp();
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
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PaymentReceivedScreen(
          crypto: token,
          amount: amount,
          fiat: fiat,
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

  bool _hasLocalNetworkLink(String? ip) {
    final hasNetworkAdapter = _connectivity.any(
      (c) => c == ConnectivityResult.wifi || c == ConnectivityResult.ethernet,
    );
    return hasNetworkAdapter || (ip != null && ip.isNotEmpty);
  }

  Future<bool> _pingClientAt(String ip) async {
    try {
      final res = await http
          .get(Uri.parse("http://$ip:8766/ping"))
          .timeout(const Duration(milliseconds: 700));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  String? _subnetPrefix(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return null;
    return "${parts[0]}.${parts[1]}.${parts[2]}";
  }

  Future<String?> _discoverClientOnSubnet(
    String localIp, {
    bool forceFullScan = false,
  }) async {
    final subnet = _subnetPrefix(localIp);
    if (subnet == null) return null;
    final myOctet = int.tryParse(localIp.split('.').last);
    final priority = <String>[];

    void addCandidate(String? ip) {
      if (ip == null || ip.isEmpty) return;
      if (!ip.startsWith("$subnet.")) return;
      if (!priority.contains(ip)) priority.add(ip);
    }

    addCandidate(_clientHotspotIp);
    addCandidate(await getGatewayIpAddress(localIp));
    addCandidate("$subnet.1");
    addCandidate("$subnet.2");
    addCandidate("$subnet.10");
    addCandidate("$subnet.100");
    addCandidate("$subnet.101");
    if (myOctet != null) {
      for (int delta = 1; delta <= 20; delta++) {
        final lower = myOctet - delta;
        final higher = myOctet + delta;
        if (lower >= 1) addCandidate("$subnet.$lower");
        if (higher <= 254) addCandidate("$subnet.$higher");
      }
    }

    for (final ip in priority) {
      if (await _pingClientAt(ip)) return ip;
    }

    final now = DateTime.now();
    final allowFullScan = forceFullScan ||
        _lastHotspotSubnetScanAt == null ||
        now.difference(_lastHotspotSubnetScanAt!) > const Duration(seconds: 12);
    if (!allowFullScan) return null;
    _lastHotspotSubnetScanAt = now;

    final excluded = priority.toSet();
    final candidates = <String>[];
    for (int i = 1; i <= 254; i++) {
      if (i == myOctet) continue;
      final ip = "$subnet.$i";
      if (excluded.contains(ip)) continue;
      candidates.add(ip);
    }

    const batchSize = 24;
    for (int i = 0; i < candidates.length; i += batchSize) {
      final batch = candidates.skip(i).take(batchSize).toList();
      final hits = await Future.wait(
        batch.map((ip) async => await _pingClientAt(ip) ? ip : null),
      );
      for (final hit in hits) {
        if (hit != null) return hit;
      }
    }
    return null;
  }

  Future<void> _refreshOfflineIp({bool forceClientDiscovery = false}) async {
    if (!offlineMode || !LocalPaymentServer.isRunning) return;
    final ip = await getLocalIpAddress();
    if (mounted && ip != localIp) {
      setState(() => localIp = ip);
    }

    if (!_hasLocalNetworkLink(ip) || ip == null || ip.isEmpty) {
      if (mounted) {
        setState(() {
          _clientHotspotReachable = false;
          _clientHotspotIp = null;
        });
      }
      return;
    }

    if (_clientHotspotIp != null && await _pingClientAt(_clientHotspotIp!)) {
      if (mounted) setState(() => _clientHotspotReachable = true);
      return;
    }

    if (_isDiscoveringClient) return;
    _isDiscoveringClient = true;
    try {
      final foundIp = await _discoverClientOnSubnet(
        ip,
        forceFullScan: forceClientDiscovery,
      );
      if (mounted) {
        setState(() {
          _clientHotspotIp = foundIp;
          _clientHotspotReachable = foundIp != null;
        });
      }
    } finally {
      _isDiscoveringClient = false;
    }
  }

  Future<void> toggleOfflineMode(bool value) async {
    _offlineIpRefreshTimer?.cancel();
    _offlineIpRefreshTimer = null;
    setState(() => offlineMode = value);
    if (value) {
      final err = await LocalPaymentServer.start();
      if (err != null) {
        setState(() => offlineMode = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Could not start offline server: $err")),
          );
        }
        return;
      }
      // Get IP: retry with delays (adapter often not ready immediately when connecting to hotspot)
      String? ip = await getLocalIpAddress();
      for (final delayMs in [400, 800, 1200]) {
        if (ip != null) break;
        await Future.delayed(Duration(milliseconds: delayMs));
        ip = await getLocalIpAddress();
      }
      if (mounted) {
        setState(() {
          localIp = ip;
          _clientHotspotReachable = false;
          _clientHotspotIp = null;
        });
        if (ip != null && ip.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Offline mode ready. IP detected.")),
          );
        }
        // Refresh IP/discovery periodically; full subnet scan is throttled internally.
        _offlineIpRefreshTimer = Timer.periodic(
          const Duration(seconds: 3),
          (_) => _refreshOfflineIp(),
        );
      }
      await _refreshOfflineIp(forceClientDiscovery: true);
    } else {
      LocalPaymentServer.stop();
      setState(() {
        localIp = null;
        _clientHotspotReachable = false;
        _clientHotspotIp = null;
      });
      if (qrData != null) {
        qrData = null;
        cryptoAmount = null;
      }
    }
  }

  Widget _buildConnectivityStatus() {
    final hasWlan = _hasLocalNetworkLink(localIp);
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
                  ? "Customer hotspot: Connected${_clientHotspotIp != null ? " ($_clientHotspotIp)" : ""}"
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
      ],
    );
  }

  Future<void> generateQR() async {

    if(amountController.text.isEmpty) return;

    if (offlineMode && (localIp == null || localIp!.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Detecting network... Connect this device to the customer's hotspot; IP will appear automatically.",
          ),
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    double fiatAmount = double.parse(amountController.text);

    double cryptoRate = rates[crypto] ?? 0;

    if (cryptoRate == 0 && !offlineMode) {
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
    if (offlineMode && localIp != null && LocalPaymentServer.isRunning) {
      payload["localIp"] = localIp;
      payload["port"] = LocalPaymentServer.port ?? LocalPaymentServer.defaultPort;
    }

    qrData = jsonEncode(payload);

    setState(() {});
  }

  @override
  void dispose() {
    watcher?.cancel();
    _offlineIpRefreshTimer?.cancel();
    _internetCheckTimer?.cancel();
    if (offlineMode) LocalPaymentServer.stop();
    LocalPaymentServer.onPaymentReceived = null;
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

                          const SizedBox(width: 20),

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
                                          localIp != null && localIp!.isNotEmpty
                                              ? "Local: $localIp:${LocalPaymentServer.port ?? ""} (ready)"
                                              : "Detecting network... Connect this device to the customer's hotspot (no internet needed).",
                                          style: TextStyle(fontSize: 12, color: localIp != null ? Colors.green : Colors.orange),
                                        ),
                                      ),
                                      TextButton.icon(
                                        onPressed: () async {
                                          setState(() {
                                            localIp = null;
                                            _clientHotspotIp = null;
                                            _clientHotspotReachable = false;
                                          });
                                          String? ip = await getLocalIpAddress();
                                          for (final delayMs in [300, 600, 1000]) {
                                            if (ip != null) break;
                                            await Future.delayed(Duration(milliseconds: delayMs));
                                            ip = await getLocalIpAddress();
                                          }
                                          if (mounted) {
                                            setState(() => localIp = ip);
                                          }
                                          await _refreshOfflineIp(forceClientDiscovery: true);
                                          if (mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  ip == null
                                                      ? "Could not detect IP. Ensure you're connected to the customer's hotspot."
                                                      : _clientHotspotReachable
                                                          ? "Connected to customer hotspot (${_clientHotspotIp ?? "client found"})."
                                                          : "IP refreshed: $ip. Client not detected yet; keep client app open and retry.",
                                                ),
                                                duration: Duration(seconds: ip != null ? 2 : 4),
                                              ),
                                            );
                                          }
                                        },
                                        icon: const Icon(Icons.refresh, size: 18),
                                        label: const Text("Refresh IP"),
                                      ),
                                    ],
                                  ),
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