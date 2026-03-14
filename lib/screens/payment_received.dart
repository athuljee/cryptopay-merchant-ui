import 'package:flutter/material.dart';

class PaymentReceivedScreen extends StatelessWidget {
  final String crypto;
  final double amount;
  final String fiat;

  const PaymentReceivedScreen({
    super.key,
    required this.crypto,
    required this.amount,
    required this.fiat,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.check_circle,
              color: Colors.green,
              size: 120,
            ),
            const SizedBox(height: 20),
            const Text(
              "Payment Received",
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              "$amount $crypto",
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              "Paid in $fiat",
              style: const TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text("Done"),
            )
          ],
        ),
      ),
    );
  }

}
