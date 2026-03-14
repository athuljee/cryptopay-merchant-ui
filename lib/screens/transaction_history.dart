import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/server_config.dart';
import '../services/local_storage.dart';

class TransactionHistory extends StatefulWidget {
  const TransactionHistory({super.key});

  @override
  State<TransactionHistory> createState() => _TransactionHistoryState();
}

class _TransactionHistoryState extends State<TransactionHistory> {
  List<Map<String, dynamic>> transactions = [];
  bool loading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    loadHistory();
  }

  Future<void> loadHistory() async {
    if (!mounted) return;
    setState(() {
      loading = true;
      errorMessage = null;
    });
    try {
      final response = await http
          .get(Uri.parse("${ServerConfig.baseUrl}/chain"))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        if (mounted) setState(() {
          loading = false;
          errorMessage = "Server error. Pull to retry.";
        });
        return;
      }

      final chain = jsonDecode(response.body);
      if (chain is! List) {
        if (mounted) setState(() => loading = false);
        return;
      }

      final List<Map<String, dynamic>> txs = [];
      for (var block in chain) {
        if (block is Map && block["transactions"] is List) {
          for (var tx in block["transactions"] as List) {
            if (tx is Map) txs.add(Map<String, dynamic>.from(tx));
          }
        }
      }

      final pending = await LocalStorage.getPendingOfflineTxs();
      for (final p in pending) {
        txs.add({
          "sender": p[OfflineTxKeys.from],
          "receiver": p[OfflineTxKeys.to],
          "amount": p[OfflineTxKeys.amount],
          "token": p[OfflineTxKeys.token],
          "status": p[OfflineTxKeys.status],
        });
      }

      if (mounted) setState(() {
        transactions = txs.reversed.toList();
        loading = false;
        errorMessage = null;
      });
    } catch (e) {
      if (kDebugMode) debugPrint("TransactionHistory loadHistory: $e");
      if (mounted) {
        final pending = await LocalStorage.getPendingOfflineTxs();
        setState(() {
          transactions = pending.map((p) => {
            "sender": p[OfflineTxKeys.from],
            "receiver": p[OfflineTxKeys.to],
            "amount": p[OfflineTxKeys.amount],
            "token": p[OfflineTxKeys.token],
            "status": p[OfflineTxKeys.status],
          }).toList();
          loading = false;
          errorMessage = "No internet. Showing offline transactions only.";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(title: const Text("Transaction History")),

      body: RefreshIndicator(

        onRefresh: loadHistory,

        child: loading
            ? const Center(child: CircularProgressIndicator())
            : errorMessage != null && transactions.isEmpty
            ? Center(child: Text(errorMessage!, textAlign: TextAlign.center))
            : transactions.isEmpty
            ? const Center(child: Text("No transactions yet"))
            : ListView.builder(

          itemCount: transactions.length,

          itemBuilder: (context, index) {

            final tx = transactions[index];

            final status = tx['status'];
            final isPending = status == 'pending';
            return ListTile(
              leading: Icon(Icons.swap_horiz, color: isPending ? Colors.orange : null),
              title: Text(
                "${tx['amount']} ${tx['token']}",
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                "From ${tx['sender']} → ${tx['receiver']}${isPending ? ' (pending sync)' : ''}",
              ),
              trailing: Icon(
                isPending ? Icons.sync : Icons.check_circle,
                color: isPending ? Colors.orange : Colors.green,
              ),
            );

          },

        ),

      ),

    );

  }
}