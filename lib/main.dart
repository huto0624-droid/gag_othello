import 'dart:ui' show PlatformDispatcher, PointerDeviceKind;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'services/app_state.dart';
import 'services/audio_service.dart';
import 'services/error_report.dart';
import 'services/face_service.dart';
import 'ui/setup_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    reportError(details.exceptionAsString());
  };
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    debugPrint('$stack');
    reportError(error);
    return true;
  };

  try {
    await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  } catch (_) {
    // デスクトップ / Web では無視してよい
  }

  final audio = AudioService();
  final faces = FaceStore();
  final app = AppState(audio: audio, faces: faces);

  // 顔（初期顔のお絵かき）→ 音 → 保存済み設定の順で準備する
  await faces.init();
  await audio.init();
  await app.init();

  runApp(GagOthelloApp(app: app));
}

/// パソコンのブラウザでも、マウスのドラッグでスクロールできるようにする（スマホと同じ操作感）
class _AppScrollBehavior extends MaterialScrollBehavior {
  const _AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => <PointerDeviceKind>{
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
        PointerDeviceKind.trackpad,
      };
}

class GagOthelloApp extends StatefulWidget {
  const GagOthelloApp({super.key, required this.app});

  final AppState app;

  @override
  State<GagOthelloApp> createState() => _GagOthelloAppState();
}

class _GagOthelloAppState extends State<GagOthelloApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.app.audio.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // アプリが裏に回ったら音を止め、戻ってきたら再開する
    widget.app.audio.setSuspended(state != AppLifecycleState.resumed);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ギャグオセロ',
      debugShowCheckedModeBanner: false,
      scrollBehavior: const _AppScrollBehavior(),
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: kFontFamily,
        colorScheme: ColorScheme.fromSeed(seedColor: kP1),
        scaffoldBackgroundColor: kBg,
      ),
      builder: (BuildContext context, Widget? child) {
        return Stack(
          children: <Widget>[
            child ?? const SizedBox.shrink(),
            const _ErrorBanner(),
          ],
        );
      },
      home: SetupScreen(app: widget.app),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: errorBanner,
      builder: (BuildContext context, String? msg, Widget? _) {
        if (msg == null) return const SizedBox.shrink();
        return Positioned(
          left: 8,
          right: 8,
          bottom: 8,
          child: SafeArea(
            child: Material(
              color: const Color(0xEEB00020),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        'エラー: $msg',
                        maxLines: 6,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.3),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => errorBanner.value = null,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
