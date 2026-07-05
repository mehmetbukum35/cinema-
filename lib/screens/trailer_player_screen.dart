import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/localization_service.dart';

/// Fragmanı uygulama içinde, kendi WebView ekranımızda gösterir.
/// YouTube mobil izleme sayfasını (m.youtube.com/watch) yükler:
/// - intent açmadığı için YouTube uygulamasına devretmez,
/// - izleme sayfası olduğundan embed kısıtına ("unavailable") takılmaz,
/// - üstte net bir KAPAT (✕) butonu ile tek dokunuşta uygulamaya dönülür.
class TrailerPlayerScreen extends StatefulWidget {
  /// TMDB'den gelen YouTube video anahtarı (ör. "dQw4w9WgXcQ").
  final String videoId;
  final String? title;

  const TrailerPlayerScreen({super.key, required this.videoId, this.title});

  @override
  State<TrailerPlayerScreen> createState() => _TrailerPlayerScreenState();
}

class _TrailerPlayerScreenState extends State<TrailerPlayerScreen> {
  late final WebViewController _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
        ),
      )
      ..loadRequest(
        Uri.parse('https://m.youtube.com/watch?v=${widget.videoId}'),
      );
  }

  @override
  Widget build(BuildContext context) {
    final isTr = AppLocalizations.of(context)?.locale.languageCode == 'tr';
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white),
          tooltip: isTr ? 'Kapat' : 'Close',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          widget.title ?? (isTr ? 'Fragman' : 'Trailer'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading)
            const Center(
              child: CircularProgressIndicator(color: Colors.white24),
            ),
        ],
      ),
    );
  }
}
