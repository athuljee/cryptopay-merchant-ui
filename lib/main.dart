import 'package:flutter/material.dart';
import 'screens/login_screen.dart';
import 'screens/merchant_home.dart';
import 'screens/transaction_history.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/offline_sync_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  OfflineSyncService.startListening();
  runApp(const CryptoPayMerchantApp());
}

class CryptoPayMerchantApp extends StatelessWidget {
  const CryptoPayMerchantApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CryptoPay Merchant Terminal',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
      ),
      home: const LoginScreen(),
      routes: {
        '/login': (_) => const LoginScreen(),
        '/home': (_) => const MerchantHome(),
        '/history': (_) => const TransactionHistory(),
      },
    );
  }
}
