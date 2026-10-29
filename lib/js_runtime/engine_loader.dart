import 'dart:io';

import 'js_engine.dart';

class EngineLoader {
  static Future<QuickJsEngine> load() async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('QuickJS engine is not supported on this platform');
    }
    return QuickJsEngine.open('libquickjs.so');
  }
}
