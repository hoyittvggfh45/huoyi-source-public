class MiniAppDenied implements Exception {
  const MiniAppDenied(this.message);
  final String message;
  @override
  String toString() => 'MiniAppDenied: $message';
}

class MiniAppPermissions {
  static const network = 'network';
  static const storage = 'storage';
  static const ui = 'ui';
  static const navigation = 'navigation';
  static const player = 'player';
  static const source = 'source';
  static const service = 'service';
  static const node = 'node';
  static const miniapp = 'miniapp';
  static const known = {
    network,
    storage,
    ui,
    navigation,
    player,
    source,
    service,
    node,
    miniapp,
  };
  static const supported = {network, storage, ui, navigation, player, source};

  const MiniAppPermissions(this.granted);
  final Set<String> granted;

  bool allows(String permission) => granted.contains(permission);

  void require(String permission) {
    if (!allows(permission)) {
      throw MiniAppDenied('permission not declared: $permission');
    }
  }
}
