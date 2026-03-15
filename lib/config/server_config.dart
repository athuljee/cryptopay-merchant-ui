class ServerConfig {
  // Existing online backend (unchanged flow).
  static const String onlineBaseUrl =
      "https://cryptopay-blockchain.onrender.com";

  // Backward-compatible alias used by existing online code.
  static const String baseUrl = onlineBaseUrl;

  // Offline local server for merchant web app.
  static const String localOfflineBaseUrl = "http://localhost:3001";
}