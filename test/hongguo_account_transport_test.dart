import 'dart:convert';

import 'package:duanju_app/core_bridge.dart';
import 'package:duanju_app/hongguo_account.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

class _StubAccountRepository extends FixtureRepository {
  Map<String, dynamic> sendSmsResult = {
    'maskedMobile': '138****8000',
    'retrySeconds': 60,
  };
  Map<String, dynamic> verifyResult = {
    'cookie': 'sessionid=s1; uid=1',
    'deviceId': '123456789',
    'installId': '987654321',
  };
  Object? verifyError;
  Map<String, dynamic> qrCodeResult = {
    'imageBase64': base64Encode([1, 2, 3, 4]),
    'expiresInSeconds': 180,
  };
  String pollResult = 'waiting';
  Map<String, dynamic> confirmResult = {
    'cookie': 'sessionid=s1',
    'deviceId': '',
    'installId': '',
  };
  Map<String, dynamic> profileResult = {
    'profile': {'biz_user_id': 'u1', 'user_name': '小明'},
  };
  Map<String, dynamic> favoritesResult = {
    'rows': [
      {
        'series_id': '111',
        'series_title': '剧一',
        'video_data': {'episode_cnt': 24},
      },
    ],
  };
  Map<String, dynamic> historyResult = {
    'rows': [
      {
        'series_id': '111',
        'title': '剧一',
        'thumb_url': 'https://cover',
        'vid': '222',
        'vid_index': 3,
        'current_play_time': 120,
        'current_total_time': 600,
        'last_watch_time': 1700000001000,
        'episode_count': 24,
      },
      {
        'series_id': '333',
        'vid': '444',
        'vid_index': 1,
        'current_play_time': 10,
        'current_total_time': 100,
        'last_watch_time': 1700000000000,
        'episode_count': 0,
      },
    ],
  };
  Map<String, dynamic> reservationsResult = {
    'rows': [
      {
        'series_id': '111',
        'series_title': '剧一',
        'episode_badge': '全 24 集',
        'subscribe_data': {'series_id': '111'},
      },
    ],
  };
  Map<String, dynamic>? lastUploadProgress;
  String? lastSetFavoriteId;
  bool? lastSetFavoriteAdd;

  @override
  Future<Map<String, dynamic>> hongguoAccountSendSms(String mobile) async =>
      sendSmsResult;

  @override
  Future<Map<String, dynamic>> hongguoAccountVerifySms(
    String mobile,
    String code,
  ) async {
    if (verifyError != null) throw verifyError!;
    return verifyResult;
  }

  @override
  Future<Map<String, dynamic>> hongguoAccountQrCode() async => qrCodeResult;

  @override
  Future<Map<String, dynamic>> hongguoAccountQrPoll() async => {
    'result': pollResult,
  };

  @override
  Future<Map<String, dynamic>> hongguoAccountQrConfirm() async =>
      confirmResult;

  @override
  Future<Map<String, dynamic>> hongguoAccountProfile(String cookie) async =>
      profileResult;

  @override
  Future<Map<String, dynamic>> hongguoAccountFavorites(String cookie) async =>
      favoritesResult;

  @override
  Future<Map<String, dynamic>> hongguoAccountSetFavorite(
    String cookie,
    String seriesId,
    bool add,
  ) async {
    lastSetFavoriteId = seriesId;
    lastSetFavoriteAdd = add;
    return {'ok': true};
  }

  @override
  Future<Map<String, dynamic>> hongguoAccountHistory(String cookie) async =>
      historyResult;

  @override
  Future<Map<String, dynamic>> hongguoAccountUploadProgress(
    String cookie,
    Map<String, dynamic> progress,
  ) async {
    lastUploadProgress = progress;
    return {'ok': true};
  }

  @override
  Future<Map<String, dynamic>> hongguoAccountReservations(
    String cookie,
    bool online,
  ) async => reservationsResult;

  @override
  Future<Map<String, dynamic>> hongguoAccountReserve(
    String cookie,
    String seriesId,
  ) async => {'ok': true};
}

void main() {
  const credentials = HongguoAccountCredentials(cookie: 'sessionid=s1');

  test('短信发码解析回显号码与倒计时', () async {
    final transport = GoHongguoAccountTransport(_StubAccountRepository());
    final sent = await transport.sendSmsCode('13800138000');
    expect(sent.maskedMobile, '138****8000');
    expect(sent.retrySeconds, 60);
  });

  test('短信验码返回凭证且 1102 转可重试登录失败', () async {
    final repository = _StubAccountRepository();
    final transport = GoHongguoAccountTransport(repository);
    final result = await transport.verifySmsCode(
      mobile: '13800138000',
      code: '123456',
    );
    expect(result.cookie, 'sessionid=s1; uid=1');
    expect(result.deviceId, '123456789');
    expect(result.installId, '987654321');
    repository.verifyError = AppFailure('验证码错误（错误码 1102）');
    try {
      await transport.verifySmsCode(mobile: '13800138000', code: '123456');
      fail('must throw');
    } on HongguoLoginFailure catch (error) {
      expect(error.errorCode, 1102);
      expect(error.canRetryCode, isTrue);
    }
  });

  test('扫码取码解 base64 且轮询四态映射', () async {
    final repository = _StubAccountRepository();
    final transport = GoHongguoAccountTransport(repository);
    final code = await transport.fetchQrCode();
    expect(code.imageBytes, [1, 2, 3, 4]);
    expect(code.expiresInSeconds, 180);
    repository.pollResult = 'scanned';
    expect(await transport.pollQrCode(), HongguoQrPollResult.scanned);
    repository.pollResult = 'confirmed';
    expect(await transport.pollQrCode(), HongguoQrPollResult.confirmed);
    repository.pollResult = 'expired';
    expect(await transport.pollQrCode(), HongguoQrPollResult.expired);
    repository.pollResult = 'unknown';
    expect(await transport.pollQrCode(), HongguoQrPollResult.waiting);
    final confirmed = await transport.confirmQrCode();
    expect(confirmed.cookie, 'sessionid=s1');
  });

  test('账号资料与收藏走已有解析', () async {
    final transport = GoHongguoAccountTransport(_StubAccountRepository());
    final profile = await transport.fetchProfile(credentials);
    expect(profile.id, 'u1');
    expect(profile.nickname, '小明');
    final favorites = await transport.fetchCloudFavorites(credentials);
    expect(favorites, hasLength(1));
    expect(favorites.first.drama.id, '111');
    expect(favorites.first.drama.title, '剧一');
  });

  test('云端历史缺标题回落剧集编号', () async {
    final repository = _StubAccountRepository();
    final transport = GoHongguoAccountTransport(repository);
    final history = await transport.fetchCloudHistory(credentials);
    expect(history, hasLength(2));
    expect(history.first.seriesTitle, '剧一');
    expect(history.first.episodeIndex, 2);
    expect(history.last.seriesTitle, '剧集 333');
    await transport.uploadCloudProgress(
      credentials,
      progress: history.first,
    );
    expect(repository.lastUploadProgress?['seriesId'], '111');
    expect(repository.lastUploadProgress?['episodeIndex'], 2);
    await transport.setCloudFavorite(
      credentials,
      seriesId: '111',
      add: true,
    );
    expect(repository.lastSetFavoriteId, '111');
    expect(repository.lastSetFavoriteAdd, isTrue);
  });

  test('预约集数徽标与待上线命名空间', () async {
    final transport = GoHongguoAccountTransport(_StubAccountRepository());
    final rows = await transport.fetchReservations(
      credentials,
      online: true,
    );
    expect(rows, hasLength(1));
    expect(rows.first.drama.releaseStatus, '全 24 集');
    final offline = HongguoCloudReservation.parseList([
      {
        'item_id': '999',
        'name': '待播剧',
        'online': false,
      },
    ], false);
    expect(offline, hasLength(1));
    expect(offline.first.drama.id, 'reservation:999');
    await transport.reserveWork(credentials, seriesId: '999');
  });
}
