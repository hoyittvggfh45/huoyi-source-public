import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'core_bridge.dart';
import 'tgdrama_credentials.dart';

enum TdlibAuthStateName {
  initializing,
  waitPhoneNumber,
  showQr,
  waitCode,
  waitPassword,
  ready,
  error,
  signingOut,
  loggedOut,
}

class TdlibAuthState {
  const TdlibAuthState({
    required this.name,
    this.link = '',
    this.phone = '',
    this.hint = '',
    this.error = '',
    this.checking = false,
    this.message = '',
  });

  final TdlibAuthStateName name;
  final String link;
  final String phone;
  final String hint;
  final String error;
  final bool checking;
  final String message;

  bool get isReady => name == TdlibAuthStateName.ready;

  static TdlibAuthState fromMap(Map<String, dynamic> map) {
    final name = switch (map['name'] as String? ?? '') {
      'waitPhoneNumber' => TdlibAuthStateName.waitPhoneNumber,
      'showQr' => TdlibAuthStateName.showQr,
      'waitCode' => TdlibAuthStateName.waitCode,
      'waitPassword' => TdlibAuthStateName.waitPassword,
      'ready' => TdlibAuthStateName.ready,
      'error' => TdlibAuthStateName.error,
      'signingOut' => TdlibAuthStateName.signingOut,
      'loggedOut' => TdlibAuthStateName.loggedOut,
      _ => TdlibAuthStateName.initializing,
    };
    return TdlibAuthState(
      name: name,
      link: map['link'] as String? ?? '',
      phone: map['phone'] as String? ?? '',
      hint: map['hint'] as String? ?? '',
      error: map['error'] as String? ?? '',
      checking: map['checking'] == true,
      message: map['message'] as String? ?? '',
    );
  }
}

class TdlibChat {
  const TdlibChat({
    required this.id,
    required this.title,
    required this.type,
    this.isProtected = false,
  });

  final int id;
  final String title;
  final String type;
  final bool isProtected;

  bool get isVideoChannel => type == 'channel' || type == 'supergroup';

  factory TdlibChat.fromMap(Map<String, dynamic> map) => TdlibChat(
    id: map['id'] is num ? (map['id'] as num).toInt() : int.tryParse('${map['id']}') ?? 0,
    title: map['title'] as String? ?? '',
    type: map['type'] as String? ?? 'unknown',
    isProtected: map['isProtected'] == true,
  );
}

class TdlibVideoMessage {
  const TdlibVideoMessage({
    required this.messageId,
    required this.chatId,
    required this.date,
    required this.duration,
    required this.width,
    required this.height,
    required this.fileName,
    required this.mimeType,
    required this.supportsStreaming,
    required this.fileId,
    required this.fileSize,
    required this.thumbFileId,
    required this.thumbWidth,
    required this.thumbHeight,
    required this.caption,
  });

  final int messageId;
  final int chatId;
  final int date;
  final int duration;
  final int width;
  final int height;
  final String fileName;
  final String mimeType;
  final bool supportsStreaming;
  final int fileId;
  final int fileSize;
  final int thumbFileId;
  final int thumbWidth;
  final int thumbHeight;
  final String caption;

  static int _asInt(Object? value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;

  factory TdlibVideoMessage.fromMap(Map<String, dynamic> map) =>
      TdlibVideoMessage(
        messageId: _asInt(map['messageId']),
        chatId: _asInt(map['chatId']),
        date: _asInt(map['date']),
        duration: _asInt(map['duration']),
        width: _asInt(map['width']),
        height: _asInt(map['height']),
        fileName: map['fileName'] as String? ?? '',
        mimeType: map['mimeType'] as String? ?? '',
        supportsStreaming: map['supportsStreaming'] == true,
        fileId: _asInt(map['fileId']),
        fileSize: _asInt(map['fileSize']),
        thumbFileId: _asInt(map['thumbFileId']),
        thumbWidth: _asInt(map['thumbWidth']),
        thumbHeight: _asInt(map['thumbHeight']),
        caption: map['caption'] as String? ?? '',
      );
}

class TdlibFile {
  const TdlibFile({
    required this.id,
    required this.size,
    required this.expectedSize,
    required this.localPath,
    required this.downloadedPrefixSize,
    required this.downloadOffset,
    required this.isDownloadingCompleted,
    required this.isDownloadingActive,
  });

  final int id;
  final int size;
  final int expectedSize;
  final String localPath;
  final int downloadedPrefixSize;
  final int downloadOffset;
  final bool isDownloadingCompleted;
  final bool isDownloadingActive;

  static int _asInt(Object? value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;

  factory TdlibFile.fromMap(Map<String, dynamic> map) => TdlibFile(
    id: _asInt(map['id']),
    size: _asInt(map['size']),
    expectedSize: _asInt(map['expectedSize']),
    localPath: map['localPath'] as String? ?? '',
    downloadedPrefixSize: _asInt(map['downloadedPrefixSize']),
    downloadOffset: _asInt(map['downloadOffset']),
    isDownloadingCompleted: map['isDownloadingCompleted'] == true,
    isDownloadingActive: map['isDownloadingActive'] == true,
  );
}

class TdlibMe {
  const TdlibMe({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.username,
  });

  final int id;
  final String firstName;
  final String lastName;
  final String username;

  String get displayName {
    final name = '$firstName $lastName'.trim();
    if (name.isNotEmpty) return name;
    if (username.isNotEmpty) return username;
    return '';
  }

  factory TdlibMe.fromMap(Map<String, dynamic> map) => TdlibMe(
    id: map['id'] is num ? (map['id'] as num).toInt() : int.tryParse('${map['id']}') ?? 0,
    firstName: map['firstName'] as String? ?? '',
    lastName: map['lastName'] as String? ?? '',
    username: map['username'] as String? ?? '',
  );
}

class TdlibService {
  TdlibService({
    MethodChannel? methodChannel,
    EventChannel? authChannel,
    EventChannel? fileChannel,
    Future<Directory> Function()? supportDirProvider,
    this._isAndroidProvider,
  }) : _methodChannel =
           methodChannel ?? const MethodChannel('huoyi/tdlib'),
       _authChannel = authChannel ?? const EventChannel('huoyi/tdlib/auth'),
       _fileChannel = fileChannel ?? const EventChannel('huoyi/tdlib/file'),
       _supportDirProvider =
           supportDirProvider ?? getApplicationSupportDirectory;

  static final TdlibService _instance = TdlibService();
  static TdlibService get instance => _instance;

  final MethodChannel _methodChannel;
  final EventChannel _authChannel;
  final EventChannel _fileChannel;
  final Future<Directory> Function() _supportDirProvider;
  final bool Function()? _isAndroidProvider;

  bool get isSupported => _isAndroidProvider?.call() ?? Platform.isAndroid;

  Stream<TdlibAuthState> get authStateStream => _authEvents
      .where((event) => event.containsKey('state'))
      .map(
        (event) => TdlibAuthState.fromMap(
          Map<String, dynamic>.from(event['state'] as Map),
        ),
      );

  Stream<bool> get connectedStream => _authEvents
      .where((event) => event.containsKey('connected'))
      .map((event) => event['connected'] == true);

  Stream<TdlibFile> get fileStream => _fileChannel
      .receiveBroadcastStream()
      .map(
        (event) => TdlibFile.fromMap(Map<String, dynamic>.from(event as Map)),
      );

  Stream<Map<String, dynamic>> get _authEvents => _authChannel
      .receiveBroadcastStream()
      .map((event) => Map<String, dynamic>.from(event as Map));

  Future<Map<String, dynamic>> _invoke(
    String method, [
    Map<String, dynamic> args = const {},
  ]) async {
    try {
      final raw = await _methodChannel.invokeMethod<Map<Object?, Object?>>(
        method,
        args,
      );
      if (raw == null) return const {};
      return Map<String, dynamic>.from(raw);
    } on MissingPluginException {
      throw AppFailure('当前安装包未集成 TDLib 桥');
    } on PlatformException catch (error) {
      throw AppFailure(error.message ?? 'TDLib 调用失败');
    } catch (e) {
      throw AppFailure('TDLib 调用失败：$e');
    }
  }

  Future<TdlibAuthState> init() async {
    if (!isSupported) throw AppFailure('当前平台不支持 TDLib 登录');
    if (!TgdramaCredentials.hasCredentials) {
      throw AppFailure('缺少 Telegram API 凭证');
    }
    final apiId = int.tryParse(TgdramaCredentials.apiId);
    if (apiId == null) throw AppFailure('Telegram API 凭证格式错误');
    final support = await _supportDirProvider();
    final result = await _invoke('init', {
      'apiId': apiId,
      'apiHash': TgdramaCredentials.apiHash,
      'databaseDir': '${support.path}/tdlib',
      'filesDir': '${support.path}/tdlib-files',
    });
    return TdlibAuthState.fromMap(
      Map<String, dynamic>.from(result['state'] as Map? ?? const {}),
    );
  }

  Future<TdlibAuthState> authState() async {
    final result = await _invoke('authState');
    return TdlibAuthState.fromMap(
      Map<String, dynamic>.from(result['state'] as Map? ?? const {}),
    );
  }

  Future<void> requestQr() async {
    await _invoke('requestQr');
  }

  Future<void> requestPhone(String phone) async {
    await _invoke('requestPhone', {'phone': phone.trim()});
  }

  Future<void> submitCode(String code) async {
    await _invoke('submitCode', {'code': code.trim()});
  }

  Future<void> submitPassword(String password) async {
    await _invoke('submitPassword', {'password': password});
  }

  Future<void> restartQr() async {
    await _invoke('restartQr');
  }

  Future<void> logout() async {
    await _invoke('logout');
  }

  Future<TdlibMe> getMe() async {
    return TdlibMe.fromMap(await _invoke('getMe'));
  }

  Future<List<TdlibChat>> chats({int limit = 40}) async {
    final result = await _invoke('chats', {'limit': limit});
    return [
      for (final row in result['chats'] as List? ?? const [])
        if (row is Map) TdlibChat.fromMap(Map<String, dynamic>.from(row)),
    ];
  }

  Future<({List<TdlibVideoMessage> messages, int nextFromMessageId})>
  chatHistory({
    required int chatId,
    int fromMessageId = 0,
    int limit = 100,
  }) async {
    final result = await _invoke('chatHistory', {
      'chatId': chatId,
      'fromMessageId': fromMessageId,
      'limit': limit,
    });
    return (
      messages: [
        for (final row in result['messages'] as List? ?? const [])
          if (row is Map)
            TdlibVideoMessage.fromMap(Map<String, dynamic>.from(row)),
      ],
      nextFromMessageId: result['nextFromMessageId'] is num
          ? (result['nextFromMessageId'] as num).toInt()
          : 0,
    );
  }

  Future<List<TdlibVideoMessage>> searchMessages({
    required String query,
    int limit = 50,
  }) async {
    final result = await _invoke('searchMessages', {
      'query': query,
      'limit': limit,
    });
    return [
      for (final row in result['messages'] as List? ?? const [])
        if (row is Map)
          TdlibVideoMessage.fromMap(Map<String, dynamic>.from(row)),
    ];
  }

  Future<({List<TdlibVideoMessage> messages, int nextFromMessageId})>
  searchChatMessages({
    required int chatId,
    required String query,
    int fromMessageId = 0,
    int limit = 30,
  }) async {
    final result = await _invoke('searchChatMessages', {
      'chatId': chatId,
      'query': query,
      'fromMessageId': fromMessageId,
      'limit': limit,
    });
    return (
      messages: [
        for (final row in result['messages'] as List? ?? const [])
          if (row is Map)
            TdlibVideoMessage.fromMap(Map<String, dynamic>.from(row)),
      ],
      nextFromMessageId: result['nextFromMessageId'] is num
          ? (result['nextFromMessageId'] as num).toInt()
          : 0,
    );
  }

  Future<TdlibFile> downloadFile(int fileId, {int priority = 32}) async {
    final result = await _invoke('downloadFile', {
      'fileId': fileId,
      'priority': priority,
    });
    return TdlibFile.fromMap(result);
  }

  Future<TdlibFile> getFile(int fileId) async {
    return TdlibFile.fromMap(await _invoke('getFile', {'fileId': fileId}));
  }

  Future<TdlibFile> downloadFileAndWait(
    int fileId, {
    int priority = 32,
    Duration timeout = const Duration(minutes: 10),
  }) async {
    var file = await downloadFile(fileId, priority: priority);
    if (file.isDownloadingCompleted) return file;
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      file = await getFile(fileId);
      if (file.isDownloadingCompleted) return file;
      if (file.localPath.isEmpty && !file.isDownloadingActive) {
        file = await downloadFile(fileId, priority: priority);
      }
    }
    throw AppFailure('下载超时，请检查网络后重试');
  }
}
