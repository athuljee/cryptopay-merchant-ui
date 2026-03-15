import 'dart:convert';
import 'package:flutter/material.dart';
import 'payment_preview.dart';

class QRScanPage extends StatefulWidget {
  const QRScanPage({super.key});

  @override
  State<QRScanPage> createState() => _QRScanPageState();
}

class _QRScanPageState extends State<QRScanPage> {
  final TextEditingController _controller = TextEditingController();
  bool _busy = false;

  void _handle(String raw) {
    if (_busy) return;
    _busy = true;

    try {
      if (raw.startsWith('{')) {
        final data = jsonDecode(raw);
        final crypto = data['crypto'] ?? "";
        final merchant = data['merchant'] ?? "";
        double amount = 0;
        if (data['amount'] != null) {
          amount = (data['amount'] as num).toDouble();
        }

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => PaymentPreview(
              crypto: crypto.isNotEmpty ? crypto : "ETH",
              amount: amount,
              address: merchant.isNotEmpty ? merchant : "merchant",
            ),
          ),
        );
        return;
      }

      if (raw.startsWith("ethereum:")) {
        final uri = Uri.parse(raw);
        final address = uri.path;
        final wei = uri.queryParameters["value"] ?? "0";
        final eth = double.parse(wei) / 1e18;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => PaymentPreview(
              crypto: "ETH",
              amount: eth,
              address: address,
            ),
          ),
        );
        return;
      }

      if (raw.startsWith("bitcoin:")) {
        final uri = Uri.parse(raw);
        final address = uri.path;
        final btc = double.tryParse(uri.queryParameters["amount"] ?? "0") ?? 0;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => PaymentPreview(
              crypto: "BTC",
              amount: btc,
              address: address,
            ),
          ),
        );
        return;
      }

      throw Exception("Unsupported QR");
    } catch (e) {
      _busy = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Invalid QR or data")),
        );
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Scan QR")),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              "Paste QR payload (JSON or ethereum:/bitcoin: URI).",
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: "QR data",
                border: OutlineInputBorder(),
                hintText: '{"merchant":"m1","crypto":"ETH","amount":0.5}',
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _busy
                  ? null
                  : () {
                      final text = _controller.text.trim();
                      if (text.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Enter QR data")),
                        );
                        return;
                      }
                      _handle(text);
                    },
              icon: const Icon(Icons.check),
              label: const Text("Continue"),
            ),
          ],
        ),
      ),
    );
  }
}
