import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'kotv_page.dart';

class KotvShellController extends Notifier<KotvPage> {
  bool midnightActivated = false;

  @override
  KotvPage build() => const KotvPage(KotvPageKind.vod);

  KotvPage get currentPage => state;

  void select(KotvPage page) {
    if (page.requiresMidnightActivation && !midnightActivated) {
      return;
    }
    state = page;
  }

  void setMidnightActivated(bool value) {
    midnightActivated = value;
    if (!value && state.requiresMidnightActivation) {
      state = const KotvPage(KotvPageKind.vod);
    }
  }
}

final kotvShellControllerProvider =
    NotifierProvider<KotvShellController, KotvPage>(KotvShellController.new);
