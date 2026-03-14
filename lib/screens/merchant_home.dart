import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:network_info_plus/network_info_plus.dart';
import '../config/server_config.dart';
import '../services/local_payment_server.dart';
import '../services/local_ip_helper.dart';
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

    startWatching();
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

    try {

      final res = await http.get(
        Uri.parse(
            "https://api.coingecko.com/api/v3/simple/price?ids=bitcoin,ethereum,tether&vs_currencies=inr"
        ),
      );

      final data = jsonDecode(res.body);
      final now = DateTime.now();

      setState(() {

        rates["BTC"] = (data["bitcoin"]["inr"]).toDouble();
        rates["ETH"] = (data["ethereum"]["inr"]).toDouble();
        rates["USDT"] = (data["tether"]["inr"]).toDouble();

        lastUpdated =
        "${now.hour.toString().padLeft(2,'0')}:${now.minute.toString().padLeft(2,'0')}";

      });

    } catch (e) {

      print("Price fetch error: $e");

    }

  }

  final Map<String,double> fiatRates = {
    "INR":1,
    "USD":0.012,
    "EUR":0.011
  };

  @override
  void initState()  {
    super.initState();
    setupTTS();
    initMerchant();
    startWatching();
    LocalPaymentServer.onPaymentReceived = _onOfflinePaymentReceived;
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

    if(processingPayment) return;

    try {

      final res = await http.get(
        Uri.parse("${ServerConfig.baseUrl}/last-payment?time=${DateTime.now().millisecondsSinceEpoch}"),
        headers: {
          "Cache-Control": "no-cache",
          "Pragma": "no-cache",
        },
      );
      print("SERVER RESPONSE: ${res.body}");

      if(res.statusCode != 200) return;

      final data = jsonDecode(res.body);

      if(data == null) return;

      if(data["receiver"] != merchantUsername) return;

      processingPayment = true;

      final amount = (data["amount"] as num).toDouble();
      final token = data["token"];

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

      await http.post(
        Uri.parse("${ServerConfig.baseUrl}/clear-payment"),
      );

      setState(() {
        qrData = null;
        cryptoAmount = null;
        amountController.clear();
      });

      processingPayment = false;

    } catch(e) {

      print("Merchant error: $e");

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

  Future<void> _refreshOfflineIp() async {
    if (!offlineMode || !LocalPaymentServer.isRunning) return;
    final ip = await getLocalIpAddress();
    if (mounted && ip != null && ip != localIp) {
      setState(() => localIp = ip);
    }
    // Notify client (hotspot host) that merchant is connected so client can show "Merchant connected"
    if (ip != null) _pingClientHotspot();
  }

  Future<void> _pingClientHotspot() async {
    try {
      final info = NetworkInfo();
      final gateway = await info.getWifiGatewayIP();
      if (gateway == null || gateway.isEmpty) return;
      await http.get(Uri.parse("http://$gateway:8766/ping")).timeout(const Duration(seconds: 2));
    } catch (_) {}
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
      // Prefer WiFi IP, then fallback to any local IPv4 (works when connected to hotspot)
      final ip = await getLocalIpAddress();
      if (mounted) {
        setState(() => localIp = ip);
        if (ip != null && ip.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Offline mode ready. Connect to customer's hotspot if needed.")),
          );
        }
        // Refresh IP periodically so when merchant connects to client hotspot, IP appears
        _offlineIpRefreshTimer = Timer.periodic(const Duration(seconds: 3), (_) => _refreshOfflineIp());
      }
    } else {
      LocalPaymentServer.stop();
      setState(() => localIp = null);
      if (qrData != null) {
        qrData = null;
        cryptoAmount = null;
      }
    }
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
                                if (offlineMode)
                                  Text(
                                    localIp != null && localIp!.isNotEmpty
                                        ? "Local: $localIp:${LocalPaymentServer.port ?? ""} (ready for offline payments)"
                                        : "Detecting network... Connect to customer's hotspot.",
                                    style: TextStyle(fontSize: 12, color: localIp != null ? Colors.green : Colors.orange),
                                  ),
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