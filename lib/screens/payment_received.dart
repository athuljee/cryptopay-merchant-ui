import 'package:flutter/material.dart';

class PaymentReceivedScreen extends StatefulWidget {
  final String crypto;
  final double amount;
  final String fiat;
  /// When true, shows "Payment Received (Offline Mode)" with From: sender.
  final bool isOfflineMode;
  /// For offline mode: who sent the payment (e.g. "Client Wallet").
  final String? from;

  const PaymentReceivedScreen({
    super.key,
    required this.crypto,
    required this.amount,
    required this.fiat,
    this.isOfflineMode = false,
    this.from,
  });

  @override
  State<PaymentReceivedScreen> createState() => _PaymentReceivedScreenState();
}

class _PaymentReceivedScreenState extends State<PaymentReceivedScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Opacity(
              opacity: _fadeAnimation.value,
              child: Transform.scale(
                scale: _scaleAnimation.value,
                child: child,
              ),
            );
          },
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.check_circle,
                color: Colors.green.shade600,
                size: 120,
              ),
              const SizedBox(height: 20),
              Text(
                widget.isOfflineMode
                    ? "Offline Payment Received"
                    : "Payment Received",
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                widget.isOfflineMode
                    ? "Amount: ${widget.amount} Coins"
                    : "Amount: ${widget.amount} ${widget.crypto}",
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              if (widget.isOfflineMode) ...[
                const SizedBox(height: 8),
                Text(
                  "From: ${widget.from ?? "Client Wallet"}",
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.grey.shade700,
                      ),
                ),
              ],
              if (!widget.isOfflineMode) ...[
                const SizedBox(height: 6),
                Text(
                  "Paid in ${widget.fiat}",
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Done"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
