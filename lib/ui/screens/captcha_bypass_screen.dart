import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../theme/ng_theme.dart';
import '../widgets/ng_retro.dart';

/// Screen to bypass Cloudflare/Newgrounds captcha by loading any NG page in WebView.
/// This initializes cookies needed to access the API.
class CaptchaBypassScreen extends StatefulWidget {
  const CaptchaBypassScreen({super.key});

  @override
  State<CaptchaBypassScreen> createState() => _CaptchaBypassScreenState();
}

class _CaptchaBypassScreenState extends State<CaptchaBypassScreen> {
  late final WebViewController _ctrl;
  bool _loading = true;
  bool _success = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) {
          if (!_success) setState(() => _loading = true);
        },
        onPageFinished: (url) async {
          setState(() => _loading = false);
          debugPrint('[captcha-bypass] finished: $url');

          // Check if we successfully loaded a Newgrounds page
          if (url.contains('newgrounds.com') && !_success) {
            // Give it a moment to ensure cookies are set
            await Future.delayed(const Duration(milliseconds: 500));
            _onSuccess();
          }
        },
        onWebResourceError: (error) {
          debugPrint('[captcha-bypass] error: ${error.description}');
          if (!_success) {
            setState(() {
              _error = 'Failed to load page: ${error.description}';
              _loading = false;
            });
          }
        },
      ))
      ..loadRequest(Uri.parse('https://www.newgrounds.com/audio'));
  }

  void _onSuccess() {
    if (_success) return;
    setState(() => _success = true);

    // Auto-dismiss after a short delay
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) Navigator.pop(context, true);
    });
  }

  void _retry() {
    setState(() {
      _error = null;
      _loading = true;
      _success = false;
    });
    _ctrl.loadRequest(Uri.parse('https://www.newgrounds.com/audio'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ngBlack,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _TopBar(
              onBack: () => Navigator.maybePop(context),
              onReload: _retry,
            ),
            Expanded(
              child: NgPageColumn(
                padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
                child: NgPod.fill(
                  icon: 'flag',
                  title: _success ? 'Verification Complete!' : 'Verifying Access',
                  skin: NgSkin.gold,
                  action: _success
                      ? NgPlateLink(
                          label: 'Continue »',
                          onTap: () => Navigator.pop(context, true),
                        )
                      : null,
                  child: _error != null ? _errorBody() : _webBody(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _webBody() {
    return Stack(
      children: [
        Positioned.fill(child: WebViewWidget(controller: _ctrl)),
        if (_loading && !_success)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: ColoredBox(
              color: ngBlack,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const NgLoading(width: 140),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Loading Newgrounds…',
                      style: ngLabel,
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (_success)
          Positioned.fill(
            child: ColoredBox(
              color: ngBlack.withOpacity(0.9),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle, color: ngGreen, size: 64),
                    const SizedBox(height: 16),
                    Text(
                      'Access verified!',
                      style: TextStyle(
                        fontFamily: ngHeaderFont,
                        fontSize: 18,
                        color: ngWhite,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'You can now browse music',
                      style: ngLabel,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _errorBody() {
    return SingleChildScrollView(
      child: NgNotice(
        text: _error!,
        icon: 'flag',
        action: NgButton(
          label: 'Try Again',
          icon: 'refresh',
          width: 122,
          onPressed: _retry,
        ),
      ),
    );
  }
}


class _TopBar extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback onReload;
  const _TopBar({required this.onBack, required this.onReload});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: ngBlack,
        border: Border(bottom: BorderSide(color: ngHairline)),
      ),
      child: Row(
        children: [
          NgIconButton(
            icon: 'arrow-left',
            padding: 10,
            tooltip: 'Back',
            onTap: onBack,
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Image.asset(NgTex.logo, height: 40, fit: BoxFit.contain),
            ),
          ),
          NgIconButton(
            icon: 'refresh',
            padding: 10,
            tooltip: 'Reload',
            onTap: onReload,
          ),
        ],
      ),
    );
  }
}
