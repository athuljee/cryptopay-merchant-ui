// Basic Flutter widget test for CryptoPay Merchant app.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cryptopay_merchant/main.dart';

void main() {
  testWidgets('Merchant app loads', (WidgetTester tester) async {
    await tester.pumpWidget(const CryptoPayMerchantApp());
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
