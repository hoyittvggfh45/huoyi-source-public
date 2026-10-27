import 'package:flutter/widgets.dart';

import 'remote_widgets.dart';

class TvFocusHelper {
  TvFocusHelper._();

  static void ensureFocus(BuildContext context) =>
      ensureTelevisionFocus(context);

  static void focusCurrent(GlobalKey<RemoteRowState> key) =>
      key.currentState?.focusCurrent();
}
